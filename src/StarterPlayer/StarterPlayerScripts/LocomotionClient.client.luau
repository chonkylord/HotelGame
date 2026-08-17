--!strict
--[[
	Owns the walk/run blend, so ordinary movement looks like walking.

	LocomotionAnimService picks the clips; this picks how they are mixed and how
	fast they run. It has to exist because the stock Animate script's blend is
	hard-coded: `speed * 1.25 / 16`, crossfading walk into run between 0.5 and
	1.0 of that, which hands everything above 12.8 studs/sec to the run clip at
	a rate that climbs without limit. There is no configuration hook for it —
	the constants live in the script's own locals — so the choice is to fork the
	whole ~800-line script or to overwrite the two numbers it sets. This does
	the latter, which leaves idle, jumping, falling, climbing, tools and emotes
	on Roblox's implementation where they can keep getting Roblox's fixes.

	It runs only for the local player. Animation state replicates outward from
	whoever owns the character, so adjusting the local tracks is what everybody
	else ends up seeing; reaching into another player's replicated tracks would
	change nothing but this machine's view of them, and would be overwritten by
	the next replicated update anyway.

	Nothing here touches the camera. First person is ViewBobConfig's job and the
	two only meet at SurvivalConfig's speeds.

	The stock script still writes its own weights and speeds on every
	Humanoid.Running event, so this cannot cache what it last wrote and skip —
	it compares against what the track currently holds instead, which makes any
	foreign write self-correcting on the next frame.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("LocomotionConfig"))

local player = Players.LocalPlayer

--[[
	Just BEFORE the character update, which is where the Animator turns track
	weights and speeds into a pose.

	This was originally +1, and that was the cause of a visible hand jitter while
	walking. Weights and speeds are *inputs* to the animation step, not outputs
	like Motor6D.Transform — the familiar "bind after Character to override the
	pose" rule is for the latter and is exactly wrong here. Writing at +1 meant
	every correction landed after the frame it was meant for, so each of the
	stock script's Humanoid.Running stomps got one fully rendered frame before
	being undone, and the arms popped between the two clips at event rate.

	Running at -1 means the pose is always built from our numbers.
]]
local UPDATE_PRIORITY = Enum.RenderPriority.Character.Value - 1

-- Character state ------------------------------------------------------------

local rootPart: BasePart? = nil
local walkTrack: AnimationTrack? = nil
local runTrack: AnimationTrack? = nil
local animatorConnection: RBXScriptConnection? = nil
local runningConnection: RBXScriptConnection? = nil

-- Low-passed horizontal speed. The gait is driven from this rather than from
-- the raw velocity; see Config.SpeedResponse.
local smoothedSpeed = 0

-- Ids are matched on their numeric part: what comes back out of AnimationId is
-- not guaranteed to be the string that went in ("rbxassetid://123" and
-- "http://www.roblox.com/asset/?id=123" name the same asset).
local function assetNumber(animationId: string?): string?
	if not animationId then
		return nil
	end
	return string.match(animationId, "%d+")
end

local walkAsset = assetNumber(Config.Animations.walk)
local runAsset = assetNumber(Config.Animations.run)

local function classify(track: AnimationTrack)
	local animation = track.Animation
	if not animation then
		return
	end
	local asset = assetNumber(animation.AnimationId)
	if asset == nil then
		return
	end
	if asset == walkAsset then
		walkTrack = track
	elseif asset == runAsset then
		runTrack = track
	end
end

-- Update ---------------------------------------------------------------------

--[[
	Compared against what the track currently holds rather than against what we
	last wrote, so any foreign write — the stock script's, most of the time — is
	corrected rather than mistaken for our own value still being in place.
]]
local function applyTo(track: AnimationTrack, weight: number, rate: number)
	if math.abs(track.WeightTarget - weight) > Config.WeightEpsilon then
		track:AdjustWeight(weight, 0)
	end
	if math.abs(track.Speed - rate) > Config.RateEpsilon then
		track:AdjustSpeed(rate)
	end
end

-- Advance the filtered speed the gait is driven from.
local function simulate(deltaTime: number)
	local root = rootPart
	if not root or not root.Parent then
		smoothedSpeed = 0
		return
	end

	-- Measured from real velocity rather than MoveDirection, for the reason
	-- ViewBobClient gives: holding W against a wall is a full MoveDirection and
	-- no motion, and animating a walk on the spot there looks broken.
	local velocity = root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

	local ease = math.min(deltaTime * Config.SpeedResponse, 1)
	smoothedSpeed += (speed - smoothedSpeed) * ease
end

--[[
	Push the blend onto the tracks.

	Split out from simulate so it can also be fired off Humanoid.Running. That
	event is what the stock script recomputes its own blend from, and at walking
	speed its answer and ours are about as far apart as they can be — it wants
	most of the run clip at 1x where we want all of the walk clip at 1.6x. Being
	connected to the same signal *after* it means its write is undone in the same
	dispatch, so the render priority above is only ever the backstop rather than
	the sole defence.
]]
local function apply()
	local walk, run = walkTrack, runTrack
	if not walk or not run then
		return
	end
	-- Both are stopped together whenever the character is doing something other
	-- than moving along the floor, which is exactly when this should stand down
	-- and let the stock script's jump, fall or idle play untouched.
	if not walk.IsPlaying or not run.IsPlaying then
		return
	end

	local runWeight = Config.runWeight(smoothedSpeed)
	local rate = Config.playbackRate(smoothedSpeed)

	applyTo(walk, math.max(1 - runWeight, Config.MinWeight), rate)
	applyTo(run, math.max(runWeight, Config.MinWeight), rate)
end

local function update(deltaTime: number)
	simulate(deltaTime)
	apply()
end

-- Character ------------------------------------------------------------------

local function resetState()
	rootPart = nil
	walkTrack = nil
	runTrack = nil
	smoothedSpeed = 0
	if animatorConnection then
		animatorConnection:Disconnect()
		animatorConnection = nil
	end
	if runningConnection then
		runningConnection:Disconnect()
		runningConnection = nil
	end
end

local function onCharacter(character: Model)
	resetState()
	rootPart = character:WaitForChild("HumanoidRootPart") :: BasePart
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local animator = humanoid:WaitForChild("Animator") :: Animator

	-- The stock script destroys and reloads its tracks on every pose change, so
	-- the pair has to be picked up again each time rather than resolved once.
	animatorConnection = animator.AnimationPlayed:Connect(classify)

	-- The stock script's own blend is recomputed here. Connecting after it means
	-- ours is the last word within the dispatch, rather than a frame later.
	runningConnection = humanoid.Running:Connect(apply)

	-- Anything already running before we connected.
	for _, track in animator:GetPlayingAnimationTracks() do
		classify(track)
	end
end

-- Wiring ---------------------------------------------------------------------

if walkAsset and runAsset then
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
	player.CharacterRemoving:Connect(resetState)

	RunService:BindToRenderStep("LocomotionBlend", UPDATE_PRIORITY, update)
end
