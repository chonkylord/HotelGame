--!strict
--[[
	Points the flashlight where you are actually looking.

	The marketplace model shipped a "Turn" script that aimed the beam by writing
	to RightShoulder.C0. That cannot work here: this place's R15 rig joints are
	AnimationConstraints, not Motor6Ds, so C0 is read-only and the script threw
	"Unable to assign property C0" every frame from inside a `while wait()` loop.
	It was removed.

	The symptom it was meant to fix was real and measurable — with the beam left
	on the default hold animation it stays perfectly level no matter where you
	look. Pitching the camera 60 degrees down left the beam 60.3 degrees off,
	firing horizontally while you stared at the floor. In a first-person horror
	game where the torch is the only light, that is the whole tool broken.

	Yaw already tracks correctly, because the whole character turns with the
	camera. Only pitch was missing, so that is all this adds: the tool's Grip is
	rotated by the camera's pitch, which swings the handle — and the welded lamp
	with it — up and down.

	This runs on the owning client, so the aim is instant with no network cost or
	replication jitter. The trade is that other players see your torch lit (the
	on/off state is server-side) but held at the animation's own pitch rather
	than yours.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local TOOL_NAME = "Flashlight"
-- Roblox clamps how far the arm reads as natural; past this it looks dislocated.
local MAX_PITCH = math.rad(75)

local player = Players.LocalPlayer

local equipped: Tool? = nil
local baseGrip: CFrame? = nil

type EmitterState = {
	weld: Weld,
	part: BasePart,
	baseC0: CFrame,
}

-- The visible handle is allowed to follow the run animation. Only the two
-- transparent parts that carry the lights are counter-rotated toward the final
-- camera direction, after camera bob and roll have been applied.
local emitters: { EmitterState } = {}
local watchedTools: { [Tool]: boolean } = {}

-- Aim state. See the RenderStepped binding for why the pitch is eased and why
-- the grip is only rewritten once it has moved.
local smoothedPitch = 0
local writtenPitch = nil :: number?

local function restoreEmitters()
	for _, state in emitters do
		if state.weld.Parent then
			state.weld.C0 = state.baseC0
		end
	end
	table.clear(emitters)
end

local function captureEmitters(tool: Tool)
	restoreEmitters()
	local handle = tool:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		return
	end

	for _, name in { "Light", "Front" } do
		local joint = handle:FindFirstChild(name)
		if joint and joint:IsA("Weld") then
			local part = joint.Part1
			if part and part:IsA("BasePart") then
				table.insert(emitters, {
					weld = joint,
					part = part,
					baseC0 = joint.C0,
				})
			end
		end
	end
end

local function onEquipped(tool: Tool)
	equipped = tool
	-- Remember the authored grip so the pitch is applied relative to it rather
	-- than accumulating.
	baseGrip = tool.Grip
	-- Forget the last aim, or the epsilon below can suppress the first write and
	-- leave a freshly drawn torch pointing flat until you next move the mouse.
	writtenPitch = nil
	captureEmitters(tool)
end

local function onUnequipped(tool: Tool)
	if equipped == tool then
		if baseGrip then
			tool.Grip = baseGrip
		end
		restoreEmitters()
		equipped = nil
		baseGrip = nil
	end
end

local function watch(tool: Tool)
	if tool.Name ~= TOOL_NAME or watchedTools[tool] then
		return
	end
	watchedTools[tool] = true
	tool.Equipped:Connect(function()
		onEquipped(tool)
	end)
	tool.Unequipped:Connect(function()
		onUnequipped(tool)
	end)
	if tool.Parent == player.Character then
		onEquipped(tool)
	end
end

local function watchContainer(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("Tool") then
			watch(child)
		end
	end
	container.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Tool") then
			watch(child)
		end
	end)
end

local function onCharacter(character: Model)
	watchContainer(character)
	local backpack = player:WaitForChild("Backpack")
	watchContainer(backpack)
end

if player.Character then
	onCharacter(player.Character)
end
player.CharacterAdded:Connect(onCharacter)

--[[
	Smoothed, and only written when it has actually moved.

	Assigning Tool.Grip is not a cheap property set — it tears down and rebuilds
	the RightGrip weld that joins the tool to the hand. Doing that every single
	frame was the flashlight's share of the hand jitter: the joint was being
	recreated 60 times a second underneath an arm that was trying to hold still,
	and the torch shivered in the hand even standing still, because raw camera
	pitch never sits perfectly constant while the mouse is live.

	So the pitch is eased rather than tracked exactly, and the weld is only
	rebuilt once the eased value has drifted far enough to see. Standing still
	now writes nothing at all.
]]
-- Per second. Fast enough that the beam still feels bolted to the view.
local PITCH_RESPONSE = 18
-- About a fifth of a degree; below this a rebuild cannot be seen, only felt.
local PITCH_EPSILON = math.rad(0.2)

RunService.RenderStepped:Connect(function(deltaTime: number)
	local tool = equipped
	local base = baseGrip
	if not tool or not base or not tool.Parent then
		return
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	-- The beam leaves along the handle's +Z (the SpotLights use Face = Back), so
	-- pitching about the handle's X axis raises and lowers it. The sign is
	-- negative because the grip rotates the handle relative to the hand, which
	-- is the opposite sense to the camera's own pitch — measured, not guessed:
	-- the positive form drove the beam to twice the error rather than zero.
	local pitch = math.clamp(math.asin(math.clamp(camera.CFrame.LookVector.Y, -1, 1)), -MAX_PITCH, MAX_PITCH)

	local ease = math.min(deltaTime * PITCH_RESPONSE, 1)
	smoothedPitch += (pitch - smoothedPitch) * ease

	local written = writtenPitch
	if written ~= nil and math.abs(smoothedPitch - written) < PITCH_EPSILON then
		return
	end
	writtenPitch = smoothedPitch
	tool.Grip = CFrame.new(base.Position) * base.Rotation * CFrame.Angles(-smoothedPitch, 0, 0)
end)

-- CameraOffset and the final roll are both finished by Camera + 1. Aligning at
-- Camera + 2 keeps the beam centred in the final view while the visible tool
-- continues to move with the hand animation underneath it.
local STABILIZE_PRIORITY = Enum.RenderPriority.Camera.Value + 2
RunService:BindToRenderStep("FlashlightBeamStabilize", STABILIZE_PRIORITY, function()
	if not equipped then
		return
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	for _, state in emitters do
		local weld = state.weld
		local part0 = weld.Part0
		if not weld.Parent or not part0 or not state.part.Parent then
			continue
		end

		-- All three existing lights emit from NormalId.Back, the transparent
		-- part's +Z face. CFrame.lookAt points -Z, so looking opposite the camera
		-- makes +Z land exactly on the camera LookVector.
		local origin = part0.CFrame:PointToWorldSpace(state.baseC0.Position)
		local desired = CFrame.lookAt(origin, origin - camera.CFrame.LookVector, camera.CFrame.UpVector)
		weld.C0 = part0.CFrame:ToObjectSpace(desired * weld.C1)
	end
end)
