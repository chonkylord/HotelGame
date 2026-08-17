--!strict
--[[
	Drives the first-person walk bob. Curves and tuning live in ViewBobConfig.

	Split across two render-step bindings, because the two halves of the effect
	have to land on opposite sides of the default camera update:

	  * Position runs just BEFORE Enum.RenderPriority.Camera. Humanoid.CameraOffset
	    is consumed by the camera script when it builds its CFrame, so writing it
	    afterwards would show up a frame late.
	  * Roll runs just AFTER. CameraOffset is a Vector3 and cannot tilt anything,
	    so the lean has to be multiplied onto the finished CFrame — and that only
	    survives if the default camera has already written.

	Both bindings share one simulation pass, done in the first.

	It cooperates rather than competes for CameraOffset. FurnitureInteractionService
	sets it server-side to drop the view when you hide in a closet, and that
	replicates down mid-bob. So each frame we compare what the Humanoid holds
	against what we last wrote: if it moved, somebody else moved it, and that
	becomes the new base the bob is applied on top of. Blindly assigning would
	cancel the crouch; blindly reading would make the bob compound into itself.

	Speed is measured from the root part's actual velocity, not MoveDirection.
	Holding W against a wall produces a full MoveDirection and no motion, and
	bobbing on the spot there looks broken.

	Deliberately not touched: FieldOfView. FurnitureHideClient tweens it and
	latches whatever it reads at that moment as the value to restore to, so a
	sprint FOV push would leak into its "default" and never come back.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("ViewBobConfig"))

local player = Players.LocalPlayer

local POSITION_PRIORITY = Enum.RenderPriority.Camera.Value - 1
local ROLL_PRIORITY = Enum.RenderPriority.Camera.Value + 1

-- Character state ------------------------------------------------------------

local humanoid: Humanoid? = nil
local rootPart: BasePart? = nil

-- Simulation state -----------------------------------------------------------

-- Advances at the step frequency; every multiple of StepPhase is a footfall.
local phase = 0
-- Eased gait strength, so walking off and stopping ramp instead of snapping.
local intensity = 0
-- Impact spring: one value, one velocity, kicked by footfalls and landings.
local springValue = 0
local springVelocity = 0
-- Peak downward speed seen since leaving the floor, for the landing impulse.
local peakFallSpeed = 0
local wasGrounded = true
local breathClock = 0

-- What we last assigned, so an external write is recognisable.
local baseOffset = Vector3.zero
local lastWritten: Vector3? = nil

local currentRoll = 0

local function resetState()
	phase = 0
	intensity = 0
	springValue = 0
	springVelocity = 0
	peakFallSpeed = 0
	wasGrounded = true
	breathClock = 0
	baseOffset = Vector3.zero
	lastWritten = nil
	currentRoll = 0
end

local function onCharacter(character: Model)
	resetState()
	humanoid = character:WaitForChild("Humanoid") :: Humanoid
	rootPart = character:WaitForChild("HumanoidRootPart") :: BasePart
end

local function onCharacterRemoving()
	humanoid = nil
	rootPart = nil
	resetState()
end

-- Is the character in a state where a walk bob makes any sense at all?
local function isBobbable(currentHumanoid: Humanoid): boolean
	if currentHumanoid.Health <= 0 then
		return false
	end
	local state = currentHumanoid:GetState()
	return state ~= Enum.HumanoidStateType.Dead
		and state ~= Enum.HumanoidStateType.Seated
		and state ~= Enum.HumanoidStateType.PlatformStanding
end

-- Simulation -----------------------------------------------------------------

local function update(deltaTime: number)
	local currentHumanoid = humanoid
	local currentRoot = rootPart
	local camera = Workspace.CurrentCamera
	if not currentHumanoid or not currentRoot or not camera or not currentRoot.Parent then
		currentRoll = 0
		return
	end

	breathClock += deltaTime

	local alive = isBobbable(currentHumanoid)
	local grounded = currentHumanoid.FloorMaterial ~= Enum.Material.Air

	local velocity = currentRoot.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

	-- Track the fall so a landing can be weighted by how far it was, then fire
	-- the impact on the airborne -> grounded edge. Reading the edge here rather
	-- than from StateChanged keeps it consistent with the FloorMaterial test
	-- everything else in this function uses.
	if not grounded then
		peakFallSpeed = math.max(peakFallSpeed, -velocity.Y)
	elseif not wasGrounded then
		if alive then
			springVelocity -= Config.landingImpulse(peakFallSpeed)
		end
		peakFallSpeed = 0
	end
	wasGrounded = grounded

	-- Only a grounded, living, actually-moving character has a gait.
	local targetIntensity = 0
	if alive and grounded then
		targetIntensity = Config.gaitIntensity(speed)
	end
	local ease = math.min(deltaTime * Config.IntensityResponse, 1)
	intensity += (targetIntensity - intensity) * ease

	local scale = Config.amplitudeScale(speed)

	-- Advance the gait and fire a footfall on each StepPhase boundary. The
	-- crossing count is taken before the wrap so a step landing on the wrap
	-- still registers; wrapping on the full stride keeps left/right alternation.
	if targetIntensity > 0 then
		local previousPhase = phase
		phase += Config.stepFrequency(speed) * Config.StepPhase * deltaTime

		local steps = math.floor(phase / Config.StepPhase) - math.floor(previousPhase / Config.StepPhase)
		if steps > 0 then
			springVelocity -= Config.FootfallImpulse * intensity * scale * steps
		end

		if phase >= Config.StridePhase then
			phase -= Config.StridePhase
		end
	end

	springValue, springVelocity = Config.springStep(springValue, springVelocity, deltaTime)

	-- Compose the layers.
	local offset = Config.gaitOffset(phase, intensity, scale)
	offset += Vector3.new(0, springValue, 0)
	if alive then
		offset += Config.breathOffset(breathClock, 1 - intensity)
	end

	-- Adopt anything another system wrote as the new base to bob around.
	local existing = currentHumanoid.CameraOffset
	local written = lastWritten
	if written == nil or (existing - written).Magnitude > Config.ExternalOffsetEpsilon then
		baseOffset = existing
	end

	local finalOffset = baseOffset + offset
	currentHumanoid.CameraOffset = finalOffset
	lastWritten = finalOffset

	-- Roll: the gait lean, plus a strafe lean from how much of the intended
	-- movement points along the camera's right axis.
	local roll = Config.gaitRoll(phase, intensity, scale)
	local moveDirection = currentHumanoid.MoveDirection
	if alive and moveDirection.Magnitude > 0 then
		roll += Config.strafeRoll(moveDirection:Dot(camera.CFrame.RightVector)) * intensity
	end
	currentRoll = roll
end

local function applyRoll()
	if currentRoll == 0 then
		return
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	camera.CFrame = camera.CFrame * CFrame.Angles(0, 0, currentRoll)
end

-- Wiring ---------------------------------------------------------------------

if player.Character then
	onCharacter(player.Character)
end
player.CharacterAdded:Connect(onCharacter)
player.CharacterRemoving:Connect(onCharacterRemoving)

RunService:BindToRenderStep("ViewBobPosition", POSITION_PRIORITY, update)
RunService:BindToRenderStep("ViewBobRoll", ROLL_PRIORITY, applyRoll)
