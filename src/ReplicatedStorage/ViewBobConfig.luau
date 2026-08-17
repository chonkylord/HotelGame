--!strict
--[[
	Tunables and pure maths for the first-person walk bob.

	The place runs LockFirstPerson, so the player never sees their own body —
	the camera IS the walk animation as far as they are concerned. Everything
	here shapes how the view moves under a step.

	Three layers stack, because a single sine is exactly the "too smooth" feel
	we are trying to get away from:

	  1. A figure-eight gait curve. Real heads drop twice per stride (once per
	     footfall) but sway side to side only once, so vertical runs at double
	     the lateral frequency. Tracing both together draws a figure eight,
	     which is the shape a walking head actually makes.
	  2. A footfall spring. Weight landing on a leg is an impact, not a
	     sinusoid, so each step kicks a lightly underdamped spring that snaps
	     down and settles. This is the layer that reads as "not floaty".
	  3. Breathing, blended in only while standing still. A perfectly frozen
	     view in a horror game reads as a paused game.

	Frequencies scale sub-linearly with speed (StepFrequencyExponent < 1): a
	sprint is a longer stride, not just a faster shuffle, so doubling speed
	must not double step rate or it looks like a cartoon scurry.

	The maths lives here rather than in the client script so the curves can be
	tested without a running game — see ViewBobConfigSpec.
]]

-- Cadence is not tuned here; it comes from the body's gait so the two stay in
-- step. See ViewBobConfig.stepFrequency.
local LocomotionConfig = require(script.Parent:WaitForChild("LocomotionConfig"))

local ViewBobConfig = {}

local TAU = math.pi * 2

-- One footfall per TAU of phase; a full stride (left then right) is 2 * TAU.
ViewBobConfig.StepPhase = TAU
ViewBobConfig.StridePhase = TAU * 2

-- Gait -----------------------------------------------------------------------
-- Speed the amplitude curve is written against: SurvivalConfig.BaseWalkSpeed. It
-- tracks that value, so ordinary walking always sits at exactly the tuning below
-- no matter what the base speed is retuned to.
ViewBobConfig.ReferenceSpeed = 12

-- Below MinBobSpeed the view is still; it reaches full strength at FullBobSpeed.
-- The gap stops a nudge against a wall or a slow turn from bobbing the camera.
ViewBobConfig.MinBobSpeed = 1.5
ViewBobConfig.FullBobSpeed = 6

--[[
	Amplitude grows with speed, and it is deliberately steep.

	This is the one knob that separates walking from sprinting in first person.
	Cadence alone does not do it: 1.9 steps/sec against 3.0 is a difference you
	have to concentrate to notice, so a sprint used to feel like a walk with the
	speed lines turned up. An exponent near 1 means the whole gait — dip, sway,
	roll lean and footfall impact all scale off this one number — grows roughly
	in proportion to speed, so shift reads as a gear change rather than a nudge.

	At the 24 sprint speed this lands near 1.8x the walking bob. The cap is what
	stops a speed powerup or a conveyor from shaking the screen apart, and sits
	just above the sprint value so sprinting is felt but not clipped.
]]
ViewBobConfig.AmplitudeExponent = 0.85
ViewBobConfig.MaxAmplitudeScale = 2

-- Amplitudes (studs) ---------------------------------------------------------
--[[
	Deliberately small. Camera bob is one of those effects where the value that
	feels right while tuning is roughly double what is comfortable over an hour.

	These came down by about a third when the cadence was handed to the gait.
	What the neck actually feels is speed, not distance, and speed is amplitude
	times frequency — so the same 0.16 dip arriving at 5.12 steps/sec instead of
	1.9 would have been nearly three times the motion. Scaling by the old ratio
	(1.9 / 5.12) keeps walking feeling about as it did before, with the dips now
	landing on the footfalls instead of drifting against them.
]]
ViewBobConfig.VerticalAmplitude = 0.06
ViewBobConfig.LateralAmplitude = 0.041
-- Radians of roll at full gait, toward whichever leg is carrying the weight.
ViewBobConfig.RollAmplitude = math.rad(0.33)
-- Extra roll while strafing, so sidestepping down a corridor leans slightly.
ViewBobConfig.StrafeRollAmplitude = math.rad(1.6)

-- Footfall impact ------------------------------------------------------------
-- Downward velocity (studs/sec) injected into the spring on each footfall.
-- Down with the amplitudes, and for the same reason: these now fire 2.7x as
-- often, and a spring kicked before it has settled just reads as rumble.
ViewBobConfig.FootfallImpulse = 0.56
-- Underdamped on purpose: critical damping here is 2*sqrt(200) ~= 28.3, and
-- sitting under it leaves a small rebound that sells the weight of the step.
ViewBobConfig.SpringStiffness = 200
ViewBobConfig.SpringDamping = 19
-- The spring is integrated explicitly, so a long frame would otherwise let it
-- gain energy and diverge. Never advance it by more than this in one go.
ViewBobConfig.MaxSpringStep = 1 / 60

-- Landing --------------------------------------------------------------------
-- Falls below this barely register; at or above LandingFullSpeed the dip caps.
ViewBobConfig.LandingMinSpeed = 8
ViewBobConfig.LandingFullSpeed = 70
ViewBobConfig.LandingMaxImpulse = 9

-- Breathing ------------------------------------------------------------------
ViewBobConfig.BreathCyclesPerSecond = 0.23
ViewBobConfig.BreathAmplitude = 0.022

-- Response -------------------------------------------------------------------
-- How fast gait strength chases its target, per second. Low enough to ease in
-- and out of a walk, high enough that stopping does not coast.
ViewBobConfig.IntensityResponse = 8
-- Above this the offset is treated as somebody else's write. Well clear of
-- float noise, well under the 0.55 stud crouch the closet applies.
ViewBobConfig.ExternalOffsetEpsilon = 1e-3

-- Curves ---------------------------------------------------------------------

--[[
	Footfalls per second at a given horizontal speed — taken from the body's
	actual gait rather than tuned here.

	This used to have its own curve, tuned by feel at 1.9 steps/sec for an
	unhurried walk, and that was the cause of a wobble players read as the held
	item jittering. The body walks at LocomotionConfig's cadence, which at the 12
	base speed is 5.12 steps/sec — the rate the walk clip has to run at to keep
	its feet on the floor. Two periodic motions at 1.9 and 5.12 do not look like
	two motions; they look like one motion beating at the 3.2Hz difference. In
	first person there is normally nothing on screen to notice that against, so
	it read as fine until a flashlight or a sack was in shot and suddenly had a
	visible tremor.

	They cannot be tuned independently and be right. Cadence is a property of the
	gait, so the gait owns it and the camera follows.
]]
function ViewBobConfig.stepFrequency(speed: number): number
	-- Standing still has no gait to follow. Matches gaitIntensity's threshold so
	-- the phase can never advance while the bob is faded out anyway.
	if speed <= ViewBobConfig.MinBobSpeed then
		return 0
	end
	return LocomotionConfig.stepFrequency(speed)
end

-- 0 when standing, 1 once properly walking. Drives how much of the gait shows.
function ViewBobConfig.gaitIntensity(speed: number): number
	local span = ViewBobConfig.FullBobSpeed - ViewBobConfig.MinBobSpeed
	return math.clamp((speed - ViewBobConfig.MinBobSpeed) / span, 0, 1)
end

-- Multiplier on every amplitude, so faster movement bobs further.
function ViewBobConfig.amplitudeScale(speed: number): number
	if speed <= 0 then
		return 0
	end
	local ratio = speed / ViewBobConfig.ReferenceSpeed
	return math.min(ratio ^ ViewBobConfig.AmplitudeExponent, ViewBobConfig.MaxAmplitudeScale)
end

--[[
	The figure eight, in camera space: X is screen-right, Y is screen-up.

	Vertical is -cos(phase), so phase 0 sits at the bottom of the dip and each
	footfall lands exactly on a multiple of StepPhase — which is what lets the
	client fire the impact spring on a plain phase-crossing test.

	Lateral is sin(phase / 2): one cycle per stride, peaking midway between
	footfalls. That is the real timing — the body is furthest over the stance
	leg at mid-stance, not at the instant the heel lands.
]]
function ViewBobConfig.gaitOffset(phase: number, intensity: number, scale: number): Vector3
	local strength = intensity * scale
	local vertical = -ViewBobConfig.VerticalAmplitude * math.cos(phase) * strength
	local lateral = ViewBobConfig.LateralAmplitude * math.sin(phase / 2) * strength
	return Vector3.new(lateral, vertical, 0)
end

-- Roll tracks the lateral sway, so the view leans toward the loaded leg.
function ViewBobConfig.gaitRoll(phase: number, intensity: number, scale: number): number
	return ViewBobConfig.RollAmplitude * math.sin(phase / 2) * intensity * scale
end

-- `lean` is -1..1, how far the player is strafing right. Negative rolls right.
function ViewBobConfig.strafeRoll(lean: number): number
	return -ViewBobConfig.StrafeRollAmplitude * math.clamp(lean, -1, 1)
end

-- Standing-still idle. `calmness` is 1 - gaitIntensity, so it fades out the
-- moment the player starts walking and the gait takes over.
function ViewBobConfig.breathOffset(clock: number, calmness: number): Vector3
	local wave = math.sin(clock * TAU * ViewBobConfig.BreathCyclesPerSecond)
	return Vector3.new(0, wave * ViewBobConfig.BreathAmplitude * calmness, 0)
end

--[[
	One explicit-Euler step of the impact spring, returning value and velocity.

	`dt` is clamped rather than sub-stepped: a frame long enough to matter is
	also long enough that nobody can see the difference, and clamping cannot
	diverge the way an unbounded explicit step can.
]]
function ViewBobConfig.springStep(value: number, velocity: number, dt: number): (number, number)
	local step = math.min(dt, ViewBobConfig.MaxSpringStep)
	local acceleration = -ViewBobConfig.SpringStiffness * value - ViewBobConfig.SpringDamping * velocity
	local nextVelocity = velocity + acceleration * step
	return value + nextVelocity * step, nextVelocity
end

-- Downward kick for a landing, scaled by how hard the player hit the floor.
function ViewBobConfig.landingImpulse(fallSpeed: number): number
	local span = ViewBobConfig.LandingFullSpeed - ViewBobConfig.LandingMinSpeed
	local amount = math.clamp((fallSpeed - ViewBobConfig.LandingMinSpeed) / span, 0, 1)
	return amount * ViewBobConfig.LandingMaxImpulse
end

return ViewBobConfig
