--!strict
--[[
	Gives every player a flashlight in their toolbar.

	The model is a Creator Marketplace asset (a PBR mesh with a two-cone beam —
	a tight 15-degree throw plus a wide 75-degree spill, which is what makes it
	read as a real torch rather than a cone of white). It lives in
	ServerStorage.FlashlightTemplate because a mesh cannot live in a script file.

	The asset shipped with its own LocalScript. That script has been removed and
	replaced by this service, for three reasons:

	  * It was a client-side viewmodel — it floated the flashlight in front of
	    your camera and moved it locally, so other players saw the torch stuck
	    wherever it was last replicated. Here it is a normal held tool, welded to
	    the hand, and the beam is switched on the SERVER, so everyone sees your
	    light sweep the corridor. That is most of the value of a flashlight in a
	    horror game.
	  * It toggled on Tool.Activated — a mouse click. Clicking is how food is
	    eaten in this place now, so that would flick the beam every time someone
	    ate something. The toggle is on F instead (see FlashlightClient).
	  * It was third-party code from a free model, and this is a system the game
	    depends on.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local TOOL_NAME = "Flashlight"
local TEMPLATE_NAME = "FlashlightTemplate"
local TOGGLE_COOLDOWN = 0.12 -- a click of the switch, not a strobe

local template = ServerStorage:FindFirstChild(TEMPLATE_NAME)
if not template or not template:IsA("Tool") then
	warn("[FlashlightService] ServerStorage." .. TEMPLATE_NAME .. " is missing — no flashlights handed out")
	return
end

local toggleEvent = ReplicatedStorage:FindFirstChild("FlashlightToggle")
if not toggleEvent then
	local created = Instance.new("RemoteEvent")
	created.Name = "FlashlightToggle"
	created.Parent = ReplicatedStorage
	toggleEvent = created
end

local lastToggle: { [Player]: number } = {}

-- Light control ---------------------------------------------------------------

local function lightsOf(tool: Tool): { Light }
	local found: { Light } = {}
	for _, descendant in tool:GetDescendants() do
		if descendant:IsA("Light") then
			table.insert(found, descendant)
		end
	end
	return found
end

local function setBeam(tool: Tool, on: boolean, click: boolean)
	for _, light in lightsOf(tool) do
		light.Enabled = on
	end
	tool:SetAttribute("BeamOn", on)

	if click then
		local handle = tool:FindFirstChild("Handle")
		local sound = handle and handle:FindFirstChildOfClass("Sound")
		if sound then
			sound:Play()
		end
	end
end

local function equippedFlashlight(player: Player): Tool?
	local character = player.Character
	if not character then
		return nil
	end
	local tool = character:FindFirstChild(TOOL_NAME)
	return if tool and tool:IsA("Tool") then tool else nil
end

-- Wiring ----------------------------------------------------------------------

local function bind(tool: Tool)
	if tool:GetAttribute("Bound") then
		return
	end
	tool:SetAttribute("Bound", true)
	setBeam(tool, false, false)

	tool.Equipped:Connect(function()
		-- Taking it out turns it on; that is what you took it out for.
		setBeam(tool, true, true)
	end)
	tool.Unequipped:Connect(function()
		setBeam(tool, false, false)
	end)
end

toggleEvent.OnServerEvent:Connect(function(player: Player)
	local now = os.clock()
	if now - (lastToggle[player] or 0) < TOGGLE_COOLDOWN then
		return
	end
	lastToggle[player] = now

	-- Only a flashlight actually in the player's hands can be switched.
	local tool = equippedFlashlight(player)
	if not tool then
		return
	end
	setBeam(tool, tool:GetAttribute("BeamOn") ~= true, true)
end)

-- Handing them out ------------------------------------------------------------

local function giveTo(player: Player)
	-- StarterGear is copied into the Backpack on every spawn, so one copy there
	-- keeps the flashlight through deaths with no respawn bookkeeping.
	local gear = player:FindFirstChildOfClass("StarterGear")
	if gear and not gear:FindFirstChild(TOOL_NAME) then
		local stored = template:Clone()
		stored.Name = TOOL_NAME
		stored.Parent = gear
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	local character = player.Character
	local held = character ~= nil and character:FindFirstChild(TOOL_NAME) ~= nil
	if backpack and not backpack:FindFirstChild(TOOL_NAME) and not held then
		local copy = template:Clone()
		copy.Name = TOOL_NAME
		copy.Parent = backpack
		bind(copy)
	elseif backpack then
		local existing = backpack:FindFirstChild(TOOL_NAME)
		if existing and existing:IsA("Tool") then
			bind(existing)
		end
	end
end

local function watch(player: Player)
	giveTo(player)
	player.CharacterAdded:Connect(function()
		-- The Backpack is rebuilt on spawn, so wait a beat before topping up.
		task.defer(function()
			giveTo(player)
		end)
	end)
end

for _, player in Players:GetPlayers() do
	watch(player)
end
Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(function(player: Player)
	lastToggle[player] = nil
end)

print("[FlashlightService] ready — flashlight in every toolbar, F toggles the beam")
