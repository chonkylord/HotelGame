--!strict
--[[
	The mallet: one on the map, laid out on a restaurant table.

	It is the key to the treasury's display cases and it is deliberately not in
	the vault — you have to have picked it up on the way down, on the amenities
	floor, before the lift to the suite. So it is left somewhere a player walks
	past rather than hidden: on a laid dining cover, under the restaurant
	lighting, with a prompt on it.

	Three states, and it can move between all of them:

	  * a prop on the table   — E to equip, or F to bag it like any other loot;
	  * a Tool in your hands  — click to swing;
	  * a prop on the floor   — what a dropped Tool turns back into, so throwing
	                            it away never leaves an inert Tool lying in
	                            Workspace that nothing knows how to pick up.

	Muscle only, both ways in. The prompt is shown to everybody on purpose: a
	prompt that is simply absent for four out of five players is indistinguishable
	from scenery, and the mallet has to read as a thing somebody could carry if
	they were the right somebody. Pressing E without the class puts a brass notice
	over it saying so (MalletPlaqueClient draws it). The sack is gated by the same
	entitlement through SackConfig.RequiredClassAttribute, so F is not a way round
	E.

	Swings are resolved here and nowhere else. Tool.Activated replicates to the
	server on its own, so no remote is needed and no client is asked where it is
	aiming: the server sweeps a sphere in front of the player's own chest and, if
	glass is in it, tells DisplayCaseService what it hit.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local BreakableGlass = require(ServerStorage:WaitForChild("BreakableGlass"))
local ClassDefinitions = require(ReplicatedStorage:WaitForChild("ClassDefinitions"))
local DisplayCaseConfig = require(ReplicatedStorage:WaitForChild("DisplayCaseConfig"))
local MalletKit = require(ServerStorage:WaitForChild("MalletKit"))
local SackConfig = require(ReplicatedStorage:WaitForChild("SackConfig"))

local EQUIP_PROMPT_NAME = "EquipMallet"

local function ensure(parent: Instance, name: string, className: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end
	local created = Instance.new(className)
	created.Name = name
	created.Parent = parent
	return created
end

local struckEvent = ensure(ServerStorage, DisplayCaseConfig.StruckEvent, "BindableEvent") :: BindableEvent

local remotes = ensure(ReplicatedStorage, DisplayCaseConfig.RemotesFolder, "Folder")
local refusedEvent = ensure(remotes, DisplayCaseConfig.RefusalEvent, "RemoteEvent") :: RemoteEvent

local function refuse(player: Player, adornee: BasePart, reason: string)
	refusedEvent:FireClient(player, adornee, reason)
end

local function mayLift(player: Player): boolean
	return ClassDefinitions.hasClass(player, ClassDefinitions.MUSCLE)
end

local propFolder = Workspace:FindFirstChild(DisplayCaseConfig.PropFolderName)
if propFolder then
	propFolder:Destroy()
end
propFolder = Instance.new("Folder")
propFolder.Name = DisplayCaseConfig.PropFolderName
propFolder.Parent = Workspace
local tools = propFolder :: Folder

local rng = Random.new()

-- Who is carrying one. Kept here rather than read off the character, because it
-- has to survive a death: the Backpack is emptied on respawn and the mallet is
-- handed back only to someone who had it.
local carriers: { [Player]: boolean } = {}
local lastSwing: { [Player]: number } = {}

local giveMallet: (Player) -> ()
local armProp: (Model) -> ()

-- Prop ------------------------------------------------------------------------

local function dropAsProp(tool: Tool)
	local handle = tool:FindFirstChild("Handle")
	local at = if handle and handle:IsA("BasePart") then handle.CFrame else nil
	tool:Destroy()
	if not at then
		return
	end

	local prop = MalletKit.buildProp()
	prop.Parent = tools
	prop:PivotTo(at)
	-- Let it fall where it was thrown. The pieces are weld-constrained to the
	-- shaft, so unanchoring the lot keeps one assembly rather than six parts.
	for _, part in prop:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end
	armProp(prop)
end

local function equipFromProp(player: Player, prop: Model, prompt: ProximityPrompt)
	if not prop:IsDescendantOf(Workspace) then
		return
	end
	local root = prop.PrimaryPart
	local character = player.Character
	local characterRoot = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not characterRoot or not characterRoot:IsA("BasePart") then
		return
	end
	if (characterRoot.Position - root.Position).Magnitude > DisplayCaseConfig.PromptDistance + 4 then
		return
	end

	-- Range is checked before the class is, so a refusal only ever appears over
	-- a mallet the player is genuinely standing at. Firing the notice at someone
	-- out of range would hang a plaque across the room for them.
	if not mayLift(player) then
		refuse(player, root, DisplayCaseConfig.RefusalClass)
		return
	end
	if carriers[player] then
		refuse(player, root, DisplayCaseConfig.RefusalCarrying)
		return
	end

	prompt:Destroy()
	prop:Destroy()
	giveMallet(player)
	print(`[MalletService] {player.Name} picked up the mallet`)
end

--[[
	Make a prop interactive: E to equip, and taggable so the sack will take it.

	The Collectable tag goes on the Model, because that is what SackService can
	anchor and park — and bagging it works precisely because the sack gives back
	the same instance, prompt and all, when it is dropped again.

	SackClass carries the Muscle gate into the sack. SackService already checks
	that attribute with the same ClassDefinitions.hasClass this file calls, which
	is the whole reason to gate F through an attribute rather than by teaching
	the sack about mallets: one entitlement, decided in one place, enforced at
	both doors. Without it, bagging the mallet would be the way round the prompt.
]]
armProp = function(prop: Model)
	local root = prop.PrimaryPart
	if not root then
		return
	end
	if not CollectionService:HasTag(prop, SackConfig.CollectableTag) then
		CollectionService:AddTag(prop, SackConfig.CollectableTag)
	end
	prop:SetAttribute(SackConfig.RequiredClassAttribute, ClassDefinitions.MUSCLE)
	if root:FindFirstChild(EQUIP_PROMPT_NAME) then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = EQUIP_PROMPT_NAME
	prompt.ActionText = "Equip"
	prompt.ObjectText = DisplayCaseConfig.MalletName
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0.12
	prompt.MaxActivationDistance = DisplayCaseConfig.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	prompt.Triggered:Connect(function(player: Player)
		equipFromProp(player, prop, prompt)
	end)
end

-- Swinging --------------------------------------------------------------------

local function swing(player: Player, tool: Tool)
	local now = os.clock()
	if now - (lastSwing[player] or 0) < DisplayCaseConfig.SwingCooldown then
		return
	end
	lastSwing[player] = now

	local handle = tool:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") then
		BreakableGlass.playAt(handle, DisplayCaseConfig.SwingSoundId, 0.55, rng:NextNumber(0.82, 1))
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end

	local origin = root.Position + root.CFrame.LookVector * DisplayCaseConfig.SwingOffset
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = CollectionService:GetTagged(DisplayCaseConfig.GlassTag)
	params.MaxParts = 24

	local target: BasePart? = nil
	local targetPoint = origin
	local closest = math.huge
	for _, part in Workspace:GetPartBoundsInRadius(origin, DisplayCaseConfig.SwingReach, params) do
		-- Transparency 1 is a pane that has already gone; the case guard would
		-- catch it anyway, but skipping it here keeps a swing from picking a
		-- broken pane over the intact one next to it.
		if part:IsA("BasePart") and part.Transparency < 1 then
			local point = BreakableGlass.closestPoint(part, origin)
			local distance = (point - origin).Magnitude
			if distance < closest then
				target, targetPoint, closest = part, point, distance
			end
		end
	end

	if target then
		struckEvent:Fire(player, target, targetPoint)
	end
end

-- Handing it out --------------------------------------------------------------

giveMallet = function(player: Player)
	if player.Parent ~= Players then
		return
	end
	carriers[player] = true

	local backpack = player:FindFirstChildOfClass("Backpack")
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not backpack then
		return
	end
	local held = character and character:FindFirstChild(DisplayCaseConfig.MalletName)
	if held or backpack:FindFirstChild(DisplayCaseConfig.MalletName) then
		return
	end

	--[[
		A fresh Tool every time rather than a StarterGear copy.

		StarterGear would re-stock the Backpack on respawn by itself, but the
		copy Roblox makes is a clone with none of the connections below — a
		mallet that looks right and does nothing when you click it. Building it
		here means every mallet in the world is one this script is listening to.
	]]
	local tool = MalletKit.buildTool()
	tool.Activated:Connect(function()
		swing(player, tool)
	end)
	tool.AncestryChanged:Connect(function(_, parent: Instance?)
		-- Dropped with Backspace: Roblox parents the Tool straight to Workspace.
		-- Give the world a prop back instead, so it can be bagged or re-equipped
		-- like the one on the table.
		if parent == Workspace then
			carriers[player] = nil
			dropAsProp(tool)
		end
	end)

	tool.Parent = backpack
	if humanoid then
		humanoid:EquipTool(tool)
	end
end

local function watch(player: Player)
	player.CharacterAdded:Connect(function()
		task.defer(function()
			if carriers[player] then
				giveMallet(player)
			end
		end)
	end)
end

for _, player in Players:GetPlayers() do
	watch(player)
end
Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(function(player: Player)
	carriers[player] = nil
	lastSwing[player] = nil
end)

-- Placing it ------------------------------------------------------------------

-- The part a diner would set something down on: whatever the dining set
-- presents at its own horizontal centre. Raycast rather than measured, because
-- the furniture is rotated and its Size tells you nothing about where the top
-- is — move the table in Studio and the mallet follows it next run.
local function tableTop(model: Model): Vector3?
	local cframe, size = model:GetBoundingBox()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { model }
	local hit = Workspace:Raycast(
		cframe.Position + Vector3.new(0, size.Y / 2 + 2, 0),
		Vector3.new(0, -(size.Y + 4), 0),
		params
	)
	return if hit then hit.Position else nil
end

local function findDiningSet(): Model?
	local amenities = Workspace:FindFirstChild("AmenitiesFloorBlueprint")
	local furnishing = amenities and amenities:FindFirstChild("Furnishing")
	local decor = furnishing and furnishing:FindFirstChild("HeavyLuxuryDecor")
	local restaurant = decor and decor:FindFirstChild("RestaurantFurniture")
	if not restaurant then
		return nil
	end

	local named = restaurant:FindFirstChild(DisplayCaseConfig.MalletTableName)
	if named and named:IsA("Model") then
		return named
	end
	for _, child in restaurant:GetChildren() do
		if child:IsA("Model") and string.find(child.Name, "DiningSet", 1, true) then
			return child
		end
	end
	return nil
end

local diningSet = findDiningSet()
local surface = diningSet and tableTop(diningSet)
if diningSet and surface then
	local prop = MalletKit.buildProp()
	prop.Parent = tools

	-- Lying on its side, across the cover and turned off square: a mallet set
	-- down mid-shift, not an exhibit. The last rotation tips the shaft from
	-- standing up to lying flat, and it is a roll about the shaft's own long
	-- axis rather than across it — pitching the other way lands the mallet on
	-- the table with its head sticking a foot and a half into the air.
	prop:PivotTo(
		CFrame.new(surface + Vector3.new(0.5, 1, -0.3))
			* CFrame.Angles(0, math.rad(24), 0)
			* CFrame.Angles(math.rad(90), 0, 0)
	)
	-- Seat it exactly on the tabletop. Its own lowest world point, not the
	-- bounding box's, because the head is wider than the shaft it is welded to.
	local min = MalletKit.worldBounds(prop)
	if min then
		prop:PivotTo(prop:GetPivot() + Vector3.new(0, surface.Y - min.Y, 0))
	end

	armProp(prop)
	print(
		string.format(
			"[MalletService] mallet laid out on %s at %.1f, %.1f, %.1f — E to equip, F to bag",
			diningSet.Name,
			prop:GetPivot().X,
			prop:GetPivot().Y,
			prop:GetPivot().Z
		)
	)
else
	warn(
		"[MalletService] no restaurant dining set found — the mallet is not on the map and the vault display cases cannot be opened"
	)
end
