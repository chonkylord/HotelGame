--!strict
--[[
	The sack's readout and controls.

	Deliberately just a counter. It is drawn directly over the first-person sack
	like old painted lettering, rather than sitting inside a modern HUD panel.
	That keeps it clear of Roblox's hotbar and the survival meters while making
	the capacity feel like part of the object the player is holding.

	Equip the sack and:
	  * looking at something collectable outlines it, and F bags it;
	  * F while looking at nothing drops the last thing you bagged at your feet.

	Dropped items keep their tags, so you can pick them straight back up — and
	food you drop is still clickable to eat, which is how you eat what you carry.

	This half only asks. The server decides what can be bagged, from how far, and
	how many. See SackService.
]]

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ClassDefinitions = require(ReplicatedStorage:WaitForChild("ClassDefinitions"))
local SackConfig = require(ReplicatedStorage:WaitForChild("SackConfig"))

local remotes = ReplicatedStorage:WaitForChild(SackConfig.RemotesFolder)
local storeEvent = remotes:WaitForChild(SackConfig.StoreEvent) :: RemoteEvent
local dropEvent = remotes:WaitForChild(SackConfig.DropEvent) :: RemoteEvent
local updateEvent = remotes:WaitForChild(SackConfig.UpdateEvent) :: RemoteEvent

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Warm, worn ink colours that sit naturally against the sack's leather.
local OUTLINE = Color3.fromRGB(28, 26, 32)
local BONE = Color3.fromRGB(239, 218, 170)
local FULL = Color3.fromRGB(218, 105, 70)
local HINT = Color3.fromRGB(174, 151, 111)

-- UI --------------------------------------------------------------------------

local screen = Instance.new("ScreenGui")
screen.Name = "SackHud"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 4
screen.Enabled = false
screen.Parent = playerGui

-- Bottom-right, over the visible sack model. No card, border, title, or other
-- modern chrome: just slightly crooked antique lettering on the sack itself.
local count = Instance.new("TextLabel")
count.Name = "Count"
count.BackgroundTransparency = 1
count.AnchorPoint = Vector2.new(0.5, 0.5)
count.Position = UDim2.new(1, -108, 1, -158)
count.Size = UDim2.fromOffset(122, 48)
count.Font = Enum.Font.Antique
count.TextSize = 28
count.TextXAlignment = Enum.TextXAlignment.Center
count.TextYAlignment = Enum.TextYAlignment.Center
count.TextColor3 = BONE
count.TextStrokeColor3 = Color3.fromRGB(58, 35, 20)
count.TextStrokeTransparency = 0.18
count.Rotation = -4
count.Text = "0 / " .. SackConfig.Capacity
count.Parent = screen

local hint = Instance.new("TextLabel")
hint.Name = "Hint"
hint.BackgroundTransparency = 1
hint.AnchorPoint = Vector2.new(1, 1)
hint.Position = UDim2.new(1, -24, 1, -74)
hint.Size = UDim2.fromOffset(240, 14)
hint.Font = Enum.Font.Antique
hint.TextSize = 13
hint.TextXAlignment = Enum.TextXAlignment.Right
hint.TextColor3 = HINT
hint.TextStrokeColor3 = OUTLINE
hint.TextStrokeTransparency = 0.4
hint.Text = ""
hint.Parent = screen

local contents: { SackConfig.Slot } = {}
local hovered: Instance? = nil

local function redraw()
	local held = #contents
	count.Text = string.format("%d / %d", held, SackConfig.Capacity)
	local isFull = held >= SackConfig.Capacity
	count.TextColor3 = if isFull then FULL else BONE

	if hovered then
		hint.Text = if isFull then "SACK FULL" else "F  —  bag " .. hovered.Name
		hint.TextColor3 = if isFull then FULL else BONE
	elseif held > 0 then
		hint.Text = "F  —  drop " .. contents[held].name
		hint.TextColor3 = HINT
	else
		hint.Text = ""
	end
end

updateEvent.OnClientEvent:Connect(function(list: { SackConfig.Slot })
	contents = list or {}
	redraw()
end)
redraw()

-- Hover -----------------------------------------------------------------------

local highlight = Instance.new("Highlight")
highlight.Name = "SackTarget"
highlight.FillTransparency = 1
highlight.OutlineColor = Color3.fromRGB(236, 236, 236)
highlight.OutlineTransparency = 0
highlight.Enabled = false
highlight.Parent = screen

-- Walk up from whatever the crosshair hit to the tagged item it belongs to.
local function collectableFrom(instance: Instance?): Instance?
	local node = instance
	while node and node ~= Workspace do
		if CollectionService:HasTag(node, SackConfig.CollectableTag) then
			if node:GetAttribute(SackConfig.LockedAttribute) == true then
				return nil
			end
			local requiredClass = node:GetAttribute(SackConfig.RequiredClassAttribute)
			if typeof(requiredClass) == "string" and not ClassDefinitions.hasClass(player, requiredClass) then
				return nil
			end
			return node
		end
		node = node.Parent
	end
	return nil
end

local function setHovered(found: Instance?)
	if found == hovered then
		return
	end
	hovered = found
	highlight.Adornee = found
	highlight.Enabled = found ~= nil
	redraw()
end

-- Set by Equipped/Unequipped. The hover loop below is connected once and reads
-- this, rather than being connected and disconnected as the sack is taken out:
-- the tool moves between Backpack and Character on every equip, which fires the
-- container watchers again, and juggling a connection across that was fragile
-- enough to silently leave the loop disconnected.
local equipped = false

local function updateHover()
	local character = player.Character
	local camera = Workspace.CurrentCamera
	if not equipped or not character or not camera then
		setHovered(nil)
		return
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local hit = Workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * SackConfig.Reach, params)
	setHovered(if hit then collectableFrom(hit.Instance) else nil)
end

-- Input -----------------------------------------------------------------------

-- One key does both jobs, the way the sack it is modelled on works: F on
-- something puts it in, F on nothing takes the last one back out.
local function onSackKey(_name: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if hovered then
		storeEvent:FireServer(hovered)
		setHovered(nil)
	elseif #contents > 0 then
		dropEvent:FireServer(#contents)
	end
	return Enum.ContextActionResult.Pass
end

-- Equip state -----------------------------------------------------------------

local function onEquipped()
	equipped = true
	screen.Enabled = true
	ContextActionService:BindAction("SackKey", onSackKey, false, Enum.KeyCode.F)
	redraw()
end

local function onUnequipped()
	equipped = false
	screen.Enabled = false
	ContextActionService:UnbindAction("SackKey")
	setHovered(nil)
end

RunService.RenderStepped:Connect(updateHover)

local function watch(tool: Tool)
	if tool.Name ~= SackConfig.ToolName then
		return
	end
	tool.Equipped:Connect(onEquipped)
	tool.Unequipped:Connect(onUnequipped)
	if tool.Parent == player.Character then
		onEquipped()
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
	onUnequipped()
	watchContainer(character)
	watchContainer(player:WaitForChild("Backpack"))
end

if player.Character then
	onCharacter(player.Character)
end
player.CharacterAdded:Connect(onCharacter)
