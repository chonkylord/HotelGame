--!strict
--[[
	What the player's body does while it moves, as everybody else sees it.

	ViewBobConfig is the first-person half of walking and never touches the
	character; this is the third-person half and never touches the camera. The
	two are deliberately independent — the local player is on LockFirstPerson,
	so the only person who sees the body is somebody else.

	Two things were wrong with the stock setup.

	The first is the clips. Roblox's default R15 set is the generic avatar walk,
	which is fine and reads as nothing in particular. The Rthro package is the
	one Roblox authored for realistically-proportioned avatars, so it is the
	grounded, unexaggerated gait a hotel corridor wants.

	The second is the blend, and it was the real problem. The stock Animate
	script computes `speed * 1.25 / 16` and crossfades walk into run between
	0.5 and 1.0 of that — so the run clip takes over completely at 12.8 studs/s
	and the walk clip is never seen above 6.4. At the old base speed of 16 that
	meant every player was permanently in the run clip at 1.25x, ~3.9 steps/sec,
	while the camera bobbed at the 1.9 steps/sec ViewBobConfig calls "an
	unhurried walk". The view said walking and the body said jogging.

	So this module owns the blend instead, and LocomotionClient applies it. The
	curve here is built from measurements rather than taste — see the constants.
]]

local LocomotionConfig = {}

-- The animation set ----------------------------------------------------------
--[[
	Rthro package, bundle 356. These are the *underlying* animation assets, not
	the catalog ids the bundle lists: a catalog "Animation" item wraps the real
	asset, and only the inner id can be handed to Animation.AnimationId. They
	were resolved by loading each catalog item and reading the Animation inside,
	then verified by fetching each one's KeyframeSequence.

	Trimming this table is safe — anything left out keeps Roblox's default. If
	only the walking should change, delete every line but walk and run.
]]
LocomotionConfig.Animations = {
	idle = "rbxassetid://10921258489",
	walk = "rbxassetid://10921269718",
	run = "rbxassetid://10921261968",
	jump = "rbxassetid://10921263860",
	fall = "rbxassetid://10921262864",
	climb = "rbxassetid://10921257536",
	swim = "rbxassetid://10921264784",
} :: { [string]: string }

-- Measured clip properties ---------------------------------------------------
--[[
	Both clips are 0.625s long and hold two footfalls, so each runs at 3.2
	steps/sec at 1x playback. That they are the *same* length is load-bearing:
	the walk and run play simultaneously and are crossfaded, so equal cycle
	lengths keep them phase-locked at a shared playback rate and their footfalls
	land together. Retiming one and not the other makes the blend band shuffle.
]]
LocomotionConfig.ClipCadence = 3.2

--[[
	The ground speed each clip is drawn for — the speed at which the planted
	foot stays planted and nothing skates.

	These are Roblox's own normalisation constants, recovered from the stock
	Animate script: it treats `speed * 1.25 / 16` of 0.5 as pure walk and 1.0 as
	pure run, i.e. 6.4 and 12.8 studs/sec. Every official package is authored
	against them, which is what makes packages interchangeable at all.

	Forward-kinematics on the actual keyframes — replaying each pose onto an R15
	rig and measuring how fast the planted foot travels backwards — put the
	Rthro walk nearer 5 studs/sec, so the clip may be drawn a touch slower than
	the reference it is filed under. That estimate is noisy (the clips have only
	a handful of grounded samples), so the engine's published figure wins here.
	If feet visibly slide while walking slowly, WalkClipSpeed is the knob.
]]
LocomotionConfig.WalkClipSpeed = 6.4
LocomotionConfig.RunClipSpeed = 12.8

-- The blend ------------------------------------------------------------------
--[[
	Where the walk clip hands over to the run clip. Set either side of
	SurvivalConfig.BaseWalkSpeed (12) so ordinary movement is unambiguously the
	walk, and below SprintWalkSpeed (24) so sprinting is unambiguously the run.
	The gap between them is what stops the gait flickering between the two when
	hunger drags the walk speed around near a threshold.

	The ceiling is tighter than it looks. Hunger scales sprinting down as well as
	walking, so the slowest a sprint ever goes is SprintWalkSpeed * MinSpeedScale
	= 16.8, not 24 — and a starving sprint still has to be a run. Anything above
	16.8 here would leave a hungry player sprinting on a half-blended walk clip
	spinning at its cap, which is both the wrong gait and the worst skate in the
	whole curve. So the band has to close inside [BaseWalkSpeed, 16.8], not
	[BaseWalkSpeed, SprintWalkSpeed]. LocomotionConfigSpec pins both ends.
]]
LocomotionConfig.RunBlendStart = 9
LocomotionConfig.RunBlendEnd = 11.5

--[[
	How far the clips may be sped up, and the one honest compromise in here.

	Playing a clip at exactly speed/clipSpeed means zero foot skate, but at the
	12 base speed that asks the walk clip for 1.88x — 6 steps/sec, which is not
	a walk, it is a scurry. Capping the walk at 1.6x holds it to ~5.1 steps/sec
	and leaves the feet covering 10.2 of the 12 studs/sec the body travels: a
	15% slide, which at this speed is genuinely hard to catch.

	So: below ~10 studs/sec the walk is exact, between there and the blend band
	it trades a little slide to stay looking like a walk, and everything from
	the blend band up — including the whole sprint — is exact again, because the
	run clip's longer stride covers those speeds without help.

	Lower MaxWalkRate for a more relaxed gait and more slide; raise it toward
	1.88 for no slide and a busier one.

	MinRate only bites below ~3 studs/sec, where the alternative is a walk clip
	crawling frame by frame. Nothing in the game moves that slowly under its own
	power; it is here so a conveyor or a knockback cannot stall the gait.

	One consequence worth knowing before it looks like a bug: the rate falls
	rather than rises through the hand-over band, from about 1.66 down to 1.29.
	The run clip's stride is twice the walk clip's, so once it takes over it
	needs less playback to cover the same ground — fewer, longer strides, which
	is what changing gait is. Skate peaks around 21% just inside RunBlendStart
	for the same reason, and is zero across every speed the game actually holds:
	8.4-12 walking and 16.8-24 sprinting. LocomotionConfigSpec pins all of it.
]]
LocomotionConfig.MinRate = 0.5
LocomotionConfig.MaxWalkRate = 1.6
LocomotionConfig.MaxRunRate = 1.9

-- Below this the character is standing as far as the gait is concerned. The
-- stock Animate script does its own idle/walk switch at 0.75 studs/sec; this
-- only has to stop a wall-nudge from driving the rate maths.
LocomotionConfig.MinMoveSpeed = 0.5

--[[
	How fast the measured speed the gait is driven from chases the real one, per
	second.

	Velocity read off the root part is not smooth. Floor contact, stair steps,
	brushing a doorframe and the humanoid's own acceleration all put noise on it,
	and feeding that straight into the curve modulates the playback rate frame to
	frame — which is visible in the arms, because a walk cycle's hands travel
	further per unit of playback than anything else in the pose.

	High enough that starting and stopping still feel immediate, low enough that
	a single noisy frame cannot show. ViewBobClient eases its gait strength the
	same way and for the same reason.
]]
LocomotionConfig.SpeedResponse = 12

-- A track weight of exactly zero stops the track contributing at all, which
-- pops. The stock script uses the same trick for the same reason.
LocomotionConfig.MinWeight = 1e-4

-- Only push a change to the Animator once it is big enough to see. Every write
-- replicates, and these are recomputed every frame.
LocomotionConfig.RateEpsilon = 1e-2
LocomotionConfig.WeightEpsilon = 1e-2

-- Curves ---------------------------------------------------------------------

--[[
	How much of the run clip is showing, 0..1.

	Smoothstep rather than a straight ramp so the hand-over has no corner at
	either end — a linear blend visibly changes pace the instant you cross
	RunBlendStart, because the weight starts moving at full rate from zero.
]]
function LocomotionConfig.runWeight(speed: number): number
	local span = LocomotionConfig.RunBlendEnd - LocomotionConfig.RunBlendStart
	if span <= 0 then
		return if speed >= LocomotionConfig.RunBlendEnd then 1 else 0
	end
	local t = math.clamp((speed - LocomotionConfig.RunBlendStart) / span, 0, 1)
	return t * t * (3 - 2 * t)
end

-- The ground speed the blended pose is drawn for, which is the two clips'
-- authored speeds mixed in the same proportion as the pose itself.
function LocomotionConfig.blendedClipSpeed(runWeight: number): number
	local t = math.clamp(runWeight, 0, 1)
	return LocomotionConfig.WalkClipSpeed + (LocomotionConfig.RunClipSpeed - LocomotionConfig.WalkClipSpeed) * t
end

-- The rate cap follows the blend too, so crossing the band cannot uncap the
-- gait in one step and jolt the cadence.
function LocomotionConfig.maxRate(runWeight: number): number
	local t = math.clamp(runWeight, 0, 1)
	return LocomotionConfig.MaxWalkRate + (LocomotionConfig.MaxRunRate - LocomotionConfig.MaxWalkRate) * t
end

--[[
	Playback rate for both tracks at a given ground speed.

	Stride matching, capped: the clip covers `blendedClipSpeed` studs/sec at 1x,
	so running it at speed/that keeps the feet with the floor.
]]
function LocomotionConfig.playbackRate(speed: number): number
	if speed <= LocomotionConfig.MinMoveSpeed then
		return LocomotionConfig.MinRate
	end
	local weight = LocomotionConfig.runWeight(speed)
	local exact = speed / LocomotionConfig.blendedClipSpeed(weight)
	return math.clamp(exact, LocomotionConfig.MinRate, LocomotionConfig.maxRate(weight))
end

-- Footfalls per second the body is actually taking. Not used to drive anything
-- — it is how the gait is compared against ViewBobConfig.stepFrequency when
-- retuning either half, and what the spec pins the tuning against.
function LocomotionConfig.stepFrequency(speed: number): number
	return LocomotionConfig.playbackRate(speed) * LocomotionConfig.ClipCadence
end

-- How much of the body's travel the feet fail to account for, 0..1. Zero means
-- the feet are planted; 1 would be moonwalking on the spot.
function LocomotionConfig.footSkate(speed: number): number
	if speed <= LocomotionConfig.MinMoveSpeed then
		return 0
	end
	local covered = LocomotionConfig.playbackRate(speed)
		* LocomotionConfig.blendedClipSpeed(LocomotionConfig.runWeight(speed))
	return math.clamp(1 - covered / speed, 0, 1)
end

return LocomotionConfig
