--!strict
--[[
	Binds F to the flashlight beam.

	The toggle deliberately is not on the mouse: clicking is how food is eaten in
	this place, so a click-toggle would flick the beam every time you ate
	something. F is only bound while the flashlight is actually in your hands, so
	it does not swallow the key the rest of the time.

	The server owns the beam — this only asks. See FlashlightService.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TOOL_NAME = "Flashlight"
local ACTION = "ToggleFlashlight"

local toggleEvent = ReplicatedStorage:WaitForChild("FlashlightToggle") :: RemoteEvent
local player = Players.LocalPlayer

local function onAction(_actionName: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		toggleEvent:FireServer()
	end
	return Enum.ContextActionResult.Pass
end

local function bindWhileHeld(tool: Tool)
	tool.Equipped:Connect(function()
		ContextActionService:BindAction(ACTION, onAction, false, Enum.KeyCode.F)
	end)
	tool.Unequipped:Connect(function()
		ContextActionService:UnbindAction(ACTION)
	end)
end

local function watchContainer(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("Tool") and child.Name == TOOL_NAME then
			bindWhileHeld(child)
		end
	end
	container.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Tool") and child.Name == TOOL_NAME then
			bindWhileHeld(child)
		end
	end)
end

local function onCharacter(character: Model)
	-- The tool moves between Backpack and character as it is equipped, so both
	-- need watching to catch it wherever it is handed to us.
	local backpack = player:WaitForChild("Backpack")
	watchContainer(backpack)
	watchContainer(character)
end

if player.Character then
	onCharacter(player.Character)
end
player.CharacterAdded:Connect(onCharacter)
