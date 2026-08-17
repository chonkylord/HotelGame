--!strict
--[[
	The first-person crosshair, and the key that lets go of the mouse.

	The place runs LockFirstPerson, which pins the pointer to the centre of the
	screen — so the stock arrow just sits there mid-screen looking like a bug.
	It is hidden and a dot is drawn in its place.

	Unlocking is a CameraMode change rather than a MouseBehavior one. While
	LockFirstPerson is set the engine re-asserts LockCenter every frame, so
	writing MouseBehavior alone is overwritten immediately; dropping to Classic
	is what actually releases the pointer. That is only safe here because
	StarterPlayer clamps CameraMinZoomDistance and CameraMaxZoomDistance both to
	0.5 — the camera cannot pull out of first person even when it is allowed to,
	so the view does not change when the mouse comes free. If either of those
	zoom distances is ever widened, this starts zooming the player out on Ctrl
	and needs revisiting.

	...and dropping to Classic is necessary but not sufficient, which is what the
	paragraph above got wrong. Those same 0.5 zoom clamps mean the camera is
	still *in* first person after the mode change, and the engine pins the
	pointer to the centre for as long as that is true no matter what CameraMode
	says. So Ctrl produced a visible cursor welded to the middle of the screen:
	the icon came back, the pointer never moved.

	A one-shot write cannot win against a per-frame one, so this re-asserts
	Default every frame while unlocked, bound at RenderPriority.Last so it runs
	after the camera has had its say. RouletteClientUI and ClueClientUI already
	hold their modal cursors open exactly this way — the crosshair was the odd
	one out in setting it once and hoping.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Small enough not to sit in front of what it is aiming at, big enough to find
-- on a dark wall.
local DOT_SIZE = 5
local HALO_SIZE = 11

local gui = Instance.new("ScreenGui")
gui.Name = "Crosshair"
gui.ResetOnSpawn = false
-- Without this, "the middle" is the middle of the area under the topbar, which
-- is a couple of dozen pixels below where the camera is actually pointing.
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local function circle(name: string, size: number, colour: Color3, transparency: number, z: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(size, size)
	frame.BackgroundColor3 = colour
	frame.BackgroundTransparency = transparency
	frame.BorderSizePixel = 0
	frame.ZIndex = z
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = frame
	return frame
end

-- A dark halo under the dot so it survives a white wall lit by the flashlight;
-- a bare white dot disappears completely against the beam.
circle("Halo", HALO_SIZE, Color3.new(0, 0, 0), 0.55, 1)
circle("Dot", DOT_SIZE, Color3.fromRGB(240, 240, 240), 0.1, 2)

local FREE_MOUSE_BINDING = "CrosshairFreeMouse"

local locked = true
local enforcing = false

-- Re-applied every frame while the mouse is free. Cheap: three property writes
-- that are almost always already at these values.
local function enforceFreeMouse()
	player.CameraMode = Enum.CameraMode.Classic
	UserInputService.MouseIconEnabled = true
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
end

local function stopEnforcing()
	if not enforcing then
		return
	end
	enforcing = false
	RunService:UnbindFromRenderStep(FREE_MOUSE_BINDING)
end

local function setLocked(value: boolean)
	locked = value
	gui.Enabled = locked

	if locked then
		stopEnforcing()
		player.CameraMode = Enum.CameraMode.LockFirstPerson
		UserInputService.MouseIconEnabled = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		return
	end

	enforceFreeMouse()
	if not enforcing then
		enforcing = true
		RunService:BindToRenderStep(FREE_MOUSE_BINDING, Enum.RenderPriority.Last.Value, enforceFreeMouse)
	end
end

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	-- processed covers the player typing in chat, where Ctrl is not ours.
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
		setLocked(not locked)
	end
end)

-- Respawning rebuilds the camera, and a player who died with the mouse free
-- should come back looking through the crosshair rather than at a loose cursor.
player.CharacterAdded:Connect(function()
	setLocked(true)
end)

setLocked(true)
