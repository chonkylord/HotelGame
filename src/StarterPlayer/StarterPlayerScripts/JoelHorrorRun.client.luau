--!strict
-- Local procedural animation for Joel. HunterState/IsHunting are replicated
-- by JoelService; this script only blends poses and never moves the rig.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local function awaitJoel(): Model
	while true do
		for _, tagged in ipairs(CollectionService:GetTagged("JoelHunter")) do
			if tagged:IsA("Model") and tagged:IsDescendantOf(Workspace) then
				return tagged
			end
		end
		local direct = Workspace:FindFirstChild("Joel")
		if direct and direct:IsA("Model") then
			return direct
		end
		CollectionService:GetInstanceAddedSignal("JoelHunter"):Wait()
	end
end

local joel = awaitJoel()
local torsoInstance = joel:WaitForChild("Torso")
local rootInstance = joel:WaitForChild("HumanoidRootPart")
if not torsoInstance:IsA("BasePart") or not rootInstance:IsA("BasePart") then
	warn("[JoelHorrorRun] Joel is not an R6 rig")
	return
end

local torso: BasePart = torsoInstance
local rootPart: BasePart = rootInstance
local rootJointInstance = rootPart:WaitForChild("RootJoint")
if not rootJointInstance:IsA("Motor6D") then
	warn("[JoelHorrorRun] Joel has no R6 RootJoint")
	return
end
local rootJoint: Motor6D = rootJointInstance

local joints: { [string]: Motor6D } = {}
local rest: { [string]: CFrame } = {}
for _, name in ipairs({ "Neck", "Left Shoulder", "Right Shoulder", "Left Hip", "Right Hip" }) do
	local instance = torso:FindFirstChild(name)
	if instance and instance:IsA("Motor6D") then
		joints[name] = instance
		rest[name] = instance.C0
	end
end
local rootRest = rootJoint.C0

-- Distinct locomotion performances. Values are blended continuously, so idle
-- breathes into a wary walk and the walk folds into the chase instead of tracks
-- popping on/off at a speed threshold.
local WALK_HZ = 1.35
local RUN_HZ = 3.4
local DRAG_HZ = 1.05
local WALK_LEG_SWING = math.rad(26)
local RUN_LEG_SWING = math.rad(78)
local WALK_ARM_SWING = math.rad(20)
local RUN_ARM_SWING = math.rad(66)
local RUN_ARM_REACH = math.rad(51)
local IDLE_HUNCH = math.rad(8)
local WALK_HUNCH = math.rad(14)
local RUN_HUNCH = math.rad(57)
local RUN_SPLAY = math.rad(15)
local RUN_YAW = math.rad(18)
local RUN_ROLL = math.rad(13)
local RUN_HEAD_COCK = math.rad(-19)
local ASYMMETRY = 0.42

local BLEND_RESPONSE = 7.5
local DRAG_BLEND_RESPONSE = 5.5
local MOVE_RESPONSE = 10
local FULL_MOVE_SPEED = 10

local TWITCH_SLOT = 0.58
local TWITCH_ATTACK = 0.028
local TWITCH_DECAY = 11
local TWITCH_TURN = math.rad(52)
local TWITCH_COCK = math.rad(42)
local TWITCH_NOD = math.rad(24)

local huntBlend = 0
local dragBlend = 0
local moveBlend = 0
local phase = 0

local function lerp(a: number, b: number, alpha: number): number
	return a + (b - a) * alpha
end

local function ease(current: number, goal: number, response: number, delta: number): number
	return current + (goal - current) * (1 - math.exp(-response * delta))
end

-- A deterministic twitch pattern keeps all clients close to the same head
-- performance without remotes or replicated AnimationTracks.
local function noise(seed: number, salt: number): number
	local x = (seed * 374761393 + salt * 668265263) % 2147483647
	x = bit32.bxor(x, bit32.rshift(x, 13))
	x = (x * 1274126177) % 2147483647
	x = bit32.bxor(x, bit32.rshift(x, 16))
	return (x % 1000003) / 1000003
end

local function twitch(now: number): (number, number, number)
	local slot = math.floor(now / TWITCH_SLOT)
	if noise(slot, 1) > lerp(0.38, 0.78, huntBlend) then
		return 0, 0, 0
	end
	local start = slot * TWITCH_SLOT + noise(slot, 2) * (TWITCH_SLOT * 0.5)
	local elapsed = now - start
	if elapsed < 0 then
		return 0, 0, 0
	end
	local envelope = if elapsed < TWITCH_ATTACK
		then elapsed / TWITCH_ATTACK
		else math.exp(-(elapsed - TWITCH_ATTACK) * TWITCH_DECAY)
	if envelope < 0.004 then
		return 0, 0, 0
	end

	local side = if noise(slot, 3) < 0.5 then -1 else 1
	local intensity = lerp(0.32, 1, huntBlend)
	return (noise(slot, 4) - 0.35) * TWITCH_NOD * envelope * intensity,
		(noise(slot, 5) - 0.5) * 2 * TWITCH_COCK * envelope * intensity,
		side * (0.45 + noise(slot, 6) * 0.55) * TWITCH_TURN * envelope * intensity
end

local function pose(now: number)
	local swing = math.sin(phase)
	local counter = math.sin(phase + math.pi)
	local doubleTime = math.sin(phase * 2)
	local breath = math.sin(now * math.pi * 0.7)
	local chase = huntBlend * moveBlend
	-- The second harmonic makes the chase feel like a broken, animal gallop
	-- instead of a perfectly mirrored Roblox run cycle. The narrow stomp pulse
	-- gives every other footfall a violent shoulder-and-torso impact.
	local gallop = math.sin(phase * 2 + 0.55)
	local stomp = math.max(0, math.sin(phase * 2 - 0.18)) ^ 3
	local rightStride = swing + gallop * 0.18 * chase
	local leftStride = swing - gallop * 0.12 * chase

	local legAmplitude = lerp(WALK_LEG_SWING, RUN_LEG_SWING, huntBlend) * moveBlend * lerp(1, 0.72, dragBlend)
	local armAmplitude = lerp(WALK_ARM_SWING, RUN_ARM_SWING, huntBlend) * moveBlend
	local armReach = RUN_ARM_REACH * huntBlend
	local splay = RUN_SPLAY * huntBlend
	local hunch = if moveBlend > 0.05
		then lerp(WALK_HUNCH, RUN_HUNCH, huntBlend)
		else lerp(IDLE_HUNCH, RUN_HUNCH * 0.72, huntBlend)

	local rightHip = joints["Right Hip"]
	local leftHip = joints["Left Hip"]
	if rightHip and rest["Right Hip"] then
		rightHip.C0 = rest["Right Hip"]
			* CFrame.Angles(splay, -splay * 0.22 * chase, legAmplitude * rightStride * (1 + ASYMMETRY))
	end
	if leftHip and rest["Left Hip"] then
		leftHip.C0 = rest["Left Hip"] * CFrame.Angles(splay * 0.75, splay * 0.16 * chase, legAmplitude * leftStride)
	end

	local rightShoulder = joints["Right Shoulder"]
	local leftShoulder = joints["Left Shoulder"]
	if rightShoulder and rest["Right Shoulder"] then
		local ordinary = rest["Right Shoulder"]
			* CFrame.Angles(
				-splay * 2.05 - stomp * math.rad(8) * chase,
				-splay * 0.36 * chase,
				armReach + armAmplitude * (counter + gallop * 0.15 * chase) * (1 + ASYMMETRY)
			)
		-- RescueController joins this arm to the victim's ankle. Keeping the
		-- shoulder low and just behind Joel sells the pull while the physical
		-- ragdoll supplies the changing weight and floor contact.
		local pulling = rest["Right Shoulder"]
			* CFrame.Angles(math.rad(-9), math.rad(15), math.rad(34) + swing * math.rad(3))
		rightShoulder.C0 = ordinary:Lerp(pulling, dragBlend)
	end
	if leftShoulder and rest["Left Shoulder"] then
		local ordinary = rest["Left Shoulder"]
			* CFrame.Angles(
				-splay * 1.55 + stomp * math.rad(5) * chase,
				splay * 0.28 * chase,
				-armReach * 0.88 + armAmplitude * (counter - gallop * 0.2 * chase)
			)
		local counterbalance = rest["Left Shoulder"]
			* CFrame.Angles(math.rad(-3), math.rad(-8), -math.rad(15) - swing * math.rad(8))
		leftShoulder.C0 = ordinary:Lerp(counterbalance, dragBlend)
	end

	local bob = lerp(0.08, 0.36, huntBlend) * doubleTime * moveBlend - 0.17 * stomp * chase
	local lateralLurch = (0.1 * swing + 0.08 * gallop) * chase
	local forwardLunge = -0.2 * stomp * chase
	local torsoYaw = RUN_YAW * (swing + gallop * 0.18) * chase
	local torsoRoll = RUN_ROLL * (counter - gallop * 0.25) * chase
	local ordinaryRoot = rootRest
		* CFrame.new(lateralLurch, bob + breath * 0.035 * (1 - moveBlend), forwardLunge)
		* CFrame.Angles(hunch + stomp * math.rad(6) * chase, torsoYaw, torsoRoll)
	local pullPulse = math.max(0, math.sin(phase * 2 - 0.35)) ^ 2
	local draggingRoot = rootRest
		* CFrame.new(-0.045, bob * 0.52, 0.055 + pullPulse * 0.035)
		* CFrame.Angles(math.rad(6) + pullPulse * math.rad(1.5), math.rad(-4), math.rad(-5))
	rootJoint.C0 = ordinaryRoot:Lerp(draggingRoot, dragBlend)

	local neck = joints.Neck
	local neckRest = rest.Neck
	if neck and neckRest then
		local nod, cock, turn = twitch(now)
		nod *= 1 - dragBlend
		cock *= 1 - dragBlend
		turn *= 1 - dragBlend
		local tremor = math.sin(now * math.pi * 46) * math.rad(2.2) * lerp(0.25, 1, huntBlend)
		-- Counter-rotate the body thrash so Joel's stare remains fixed on his prey,
		-- then interrupt it with fast, inhuman snaps and a permanent chase tilt.
		local ordinary = neckRest
			* CFrame.Angles(
				-hunch * 1.06 - stomp * math.rad(4) * chase + nod + tremor,
				-torsoYaw * 0.88 + turn + tremor * 0.35,
				RUN_HEAD_COCK * huntBlend - torsoRoll * 0.72 + cock + tremor * 0.65
			)
		-- A restrained glance toward the hand/ankle connection reads human and
		-- deliberate, in contrast to the fixed predatory stare of the chase.
		local checkingVictim = neckRest * CFrame.Angles(math.rad(13), math.rad(14), math.rad(5))
		neck.C0 = ordinary:Lerp(checkingVictim, dragBlend)
	end
end

RunService.RenderStepped:Connect(function(delta: number)
	local velocity = rootPart.AssemblyLinearVelocity
	local groundSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local hunting = joel:GetAttribute("IsHunting") == true
	local dragging = joel:GetAttribute("HunterState") == "Dragging"

	huntBlend = ease(huntBlend, if hunting then 1 else 0, BLEND_RESPONSE, delta)
	dragBlend = ease(dragBlend, if dragging then 1 else 0, DRAG_BLEND_RESPONSE, delta)
	moveBlend = ease(moveBlend, math.clamp(groundSpeed / FULL_MOVE_SPEED, 0, 1), MOVE_RESPONSE, delta)
	local strideHz = lerp(lerp(WALK_HZ, RUN_HZ, huntBlend), DRAG_HZ, dragBlend)
	-- Slightly rush the planted half of each stride. This preserves a smooth
	-- blend while making the full chase cadence feel urgent and uneven.
	local cadence = 1 + math.max(0, math.sin(phase)) * 0.2 * huntBlend * moveBlend
	phase = (phase + delta * strideHz * cadence * math.pi * 2) % (math.pi * 2)
	pose(Workspace:GetServerTimeNow())
end)
