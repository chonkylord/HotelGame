--!strict
--[[
	Stocks the rear service storage room with searchable containers.

	The room ships as three metal shelf units against the west wall and a lot of
	empty floor. This fills that floor with cardboard boxes, crates, supply
	lockers, footlockers and a filing cabinet — every one of them openable, and
	most of them holding something.

	Server authority: the loot roll, what ends up in each container, and the
	prompt handler all live here. Consumables are handed to SurvivalService by
	tagging them "Food" (see SurvivalConfig.FoodAttributes), which is what makes
	a found can of beans actually restore hunger instead of being scenery. The
	tag is only applied once a container has been opened, so nothing is edible
	through a closed lid.

	Layout is authored in world coordinates measured off the room itself:
	interior floor spans X 266..282 and Z 44..66, plus a narrow alcove at
	X 266..270 / Z 68..70. The doorway sits at X 274 on the Z 42 wall, so the
	middle of the room is deliberately left clear as a walking lane.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local ContainerKit = require(ServerStorage:WaitForChild("ContainerKit"))
local SackConfig = require(ReplicatedStorage:WaitForChild("SackConfig"))
local SurvivalConfig = require(ReplicatedStorage:WaitForChild("SurvivalConfig"))

local FOLDER_NAME = "StorageRoomContainers"
local PROMPT_DISTANCE = 8
local FOOD_ATTR = SurvivalConfig.FoodAttributes

-- Ceiling of the room is at Y 46.5 and the floor at Y 32.5; probing from 44
-- keeps us under the ceiling while still clearing anything standing on the floor.
local PROBE_Y = 44
local PROBE_DEPTH = 14

type LootDef = {
	name: string,
	weight: number,
	size: Vector3,
	colour: Color3,
	material: Enum.Material,
	shape: Enum.PartType?,
	hunger: number?,
	health: number?,
	stamina: number?,
	action: string?,
}

-- Loot ------------------------------------------------------------------------
-- Anything carrying hunger/health/stamina becomes a real SurvivalService pickup
-- once found. The rest is flavour: props that tell you someone lived here.

local LOOT: { LootDef } = {
	{
		name = "Canned Beans",
		weight = 10,
		size = Vector3.new(0.62, 0.86, 0.62),
		colour = Color3.fromRGB(168, 122, 61),
		material = Enum.Material.Metal,
		shape = Enum.PartType.Cylinder,
		hunger = 30,
		action = "Eat",
	},
	{
		name = "Tinned Peaches",
		weight = 8,
		size = Vector3.new(0.64, 0.7, 0.64),
		colour = Color3.fromRGB(196, 156, 84),
		material = Enum.Material.Metal,
		shape = Enum.PartType.Cylinder,
		hunger = 24,
		health = 4,
		action = "Eat",
	},
	{
		name = "Granola Bar",
		weight = 9,
		size = Vector3.new(0.85, 0.16, 0.36),
		colour = Color3.fromRGB(126, 91, 52),
		material = Enum.Material.SmoothPlastic,
		hunger = 16,
		action = "Eat",
	},
	{
		name = "Bottled Water",
		weight = 9,
		size = Vector3.new(0.42, 1.05, 0.42),
		colour = Color3.fromRGB(163, 203, 214),
		material = Enum.Material.Glass,
		shape = Enum.PartType.Cylinder,
		hunger = 8,
		stamina = 2,
		action = "Drink",
	},
	{
		name = "Energy Drink",
		weight = 6,
		size = Vector3.new(0.44, 0.92, 0.44),
		colour = Color3.fromRGB(78, 158, 92),
		material = Enum.Material.Metal,
		shape = Enum.PartType.Cylinder,
		hunger = 6,
		stamina = 4,
		action = "Drink",
	},
	{
		name = "First Aid Tin",
		weight = 5,
		size = Vector3.new(0.95, 0.34, 0.66),
		colour = Color3.fromRGB(198, 198, 198),
		material = Enum.Material.Metal,
		health = 25,
		action = "Use",
	},
	{
		-- This is ordinary self-heal loot. Keep its name distinct from the
		-- rescue bandages stored in first-aid dispensers, which are consumed
		-- specifically when reviving another player.
		name = "Antiseptic Wrap",
		weight = 9,
		size = Vector3.new(0.44, 0.44, 0.28),
		colour = Color3.fromRGB(238, 232, 214),
		material = Enum.Material.Fabric,
		shape = Enum.PartType.Cylinder,
		health = 12,
		action = "Apply",
	},
	{
		name = "Spare Batteries",
		weight = 8,
		size = Vector3.new(0.7, 0.32, 0.5),
		colour = Color3.fromRGB(56, 56, 62),
		material = Enum.Material.Metal,
	},
	{
		name = "Service Keycard",
		weight = 4,
		size = Vector3.new(0.56, 0.03, 0.36),
		colour = Color3.fromRGB(184, 152, 66),
		material = Enum.Material.SmoothPlastic,
	},
	{
		name = "Folded Linen",
		weight = 10,
		size = Vector3.new(1.15, 0.3, 0.85),
		colour = Color3.fromRGB(206, 202, 190),
		material = Enum.Material.Fabric,
	},
	{
		name = "Crumpled Note",
		weight = 7,
		size = Vector3.new(0.5, 0.06, 0.42),
		colour = Color3.fromRGB(224, 214, 186),
		material = Enum.Material.SmoothPlastic,
	},
	{
		name = "Bar of Soap",
		weight = 6,
		size = Vector3.new(0.5, 0.22, 0.34),
		colour = Color3.fromRGB(212, 206, 224),
		material = Enum.Material.SmoothPlastic,
	},
	{
		name = "Rusted Wrench",
		weight = 5,
		size = Vector3.new(1.25, 0.14, 0.26),
		colour = Color3.fromRGB(112, 96, 86),
		material = Enum.Material.CorrodedMetal,
	},
}

-- Weight of "you opened it and there was nothing". Searching wants to be able to
-- come up empty or none of it is tense.
local EMPTY_WEIGHT = 26

local rng = Random.new()

local totalWeight = EMPTY_WEIGHT
for _, def in LOOT do
	totalWeight += def.weight
end

local function rollLoot(): LootDef?
	local pick = rng:NextNumber() * totalWeight
	for _, def in LOOT do
		pick -= def.weight
		if pick <= 0 then
			return def
		end
	end
	return nil
end

-- Setup -----------------------------------------------------------------------

local existing = Workspace:FindFirstChild(FOLDER_NAME)
if existing then
	existing:Destroy()
end

local folder = Instance.new("Folder")
folder.Name = FOLDER_NAME
folder.Parent = Workspace

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
-- Exclude our own containers so a later box never seats itself on an earlier one.
groundParams.FilterDescendantsInstances = { folder }

local function groundAt(x: number, z: number): number?
	local hit = Workspace:Raycast(Vector3.new(x, PROBE_Y, z), Vector3.new(0, -PROBE_DEPTH, 0), groundParams)
	return if hit then hit.Position.Y else nil
end

local function drawerSoundTemplate(): Sound?
	local drawer = Workspace:FindFirstChild("Drawer")
	local body = drawer and drawer:FindFirstChild("Body")
	return if body then body:FindFirstChildOfClass("Sound") else nil
end

local soundTemplate = drawerSoundTemplate()

local containerCount = 0
local openableCount = 0
local lootCount = 0

-- Contents --------------------------------------------------------------------

-- Drop a rolled item onto the floor of a container. `interior` is centred on that
-- floor with its own -Z pointing at the container's front.
local function fillContainer(container: Model, interior: CFrame, interiorSize: Vector3): { BasePart }
	local placed: { BasePart } = {}
	local def = rollLoot()
	if not def then
		container:SetAttribute("Empty", true)
		return placed
	end

	local contents = container:FindFirstChild("Contents") :: Folder?
	if not contents then
		local created = Instance.new("Folder")
		created.Name = "Contents"
		created.Parent = container
		contents = created
	end

	-- Sit it on the floor, nudged off centre so it does not look placed.
	local halfX = math.max(interiorSize.X / 2 - def.size.X / 2 - 0.12, 0)
	local halfZ = math.max(interiorSize.Z / 2 - def.size.Z / 2 - 0.12, 0)
	local offsetX = rng:NextNumber(-halfX, halfX)
	local offsetZ = rng:NextNumber(-halfZ, halfZ)
	local lift = def.size.Y / 2

	local item = ContainerKit.makePart(
		contents :: Folder,
		def.name,
		def.size,
		interior * CFrame.new(offsetX, lift, offsetZ) * CFrame.Angles(0, rng:NextNumber(-1, 1) * 0.7, 0),
		def.colour,
		def.material,
		false
	)
	if def.shape then
		item.Shape = def.shape
		-- Roblox cylinders run along X, so stand tins and bottles upright.
		if def.shape == Enum.PartType.Cylinder then
			item.CFrame = item.CFrame * CFrame.Angles(0, 0, math.rad(90))
		end
	end

	-- SurvivalService reads these when the tag goes on after the first search.
	if def.hunger or def.health or def.stamina then
		item:SetAttribute("IsFood", true)
		item:SetAttribute(FOOD_ATTR.Hunger, def.hunger or 0)
		item:SetAttribute(FOOD_ATTR.Health, def.health or 0)
		item:SetAttribute(FOOD_ATTR.Stamina, def.stamina or 0)
		item:SetAttribute(FOOD_ATTR.Action, def.action or "Take")
		item:SetAttribute(FOOD_ATTR.Uses, 1)
	end

	container:SetAttribute("Loot", def.name)
	lootCount += 1
	table.insert(placed, item)
	return placed
end

-- Hand whatever is inside over to SurvivalService the first time a container is
-- opened. Before that the tag is absent, so a closed box has no live prompt in it.
local function revealContents(container: Model)
	if container:GetAttribute("Searched") then
		return
	end
	container:SetAttribute("Searched", true)

	local contents = container:FindFirstChild("Contents")
	if not contents then
		return
	end
	for _, item in contents:GetChildren() do
		if item:GetAttribute("IsFood") then
			CollectionService:AddTag(item, SurvivalConfig.FoodTag)
		end
		-- Everything in here can go in the sack once the lid is off, edible or
		-- not — batteries and keycards are worth carrying too.
		CollectionService:AddTag(item, SackConfig.CollectableTag)
	end
end

local function registerContainer(container: Model, options: ContainerKit.RegisterOptions): ContainerKit.AnimatedSet?
	local emptyLabel = options.objectText .. " (Empty)"
	options.promptDistance = PROMPT_DISTANCE
	options.openText = "Search"
	options.onTriggered = function(_player: Player, animated: ContainerKit.AnimatedSet)
		local opening = not animated.isOpen
		if opening then
			revealContents(container)
			-- Say so plainly rather than leaving the player wondering.
			animated.objectText = if container:GetAttribute("Empty") then emptyLabel else options.objectText
		end
		ContainerKit.setOpen(animated, opening)
	end

	local animated = ContainerKit.register(options)
	if animated then
		openableCount += 1
	end
	return animated
end

-- Builders --------------------------------------------------------------------

-- baseCF sits on the floor with -Z facing the way the container is turned.
local function buildCardboardBox(baseCF: CFrame, index: number): number
	local width, depth, height = 3.0, 2.6, 2.4
	local t = 0.09
	local shade = 1 - (index % 3) * 0.06
	local colour = Color3.fromRGB(math.floor(184 * shade), math.floor(150 * shade), math.floor(108 * shade))
	local inner = colour:Lerp(Color3.fromRGB(64, 50, 34), 0.35)

	local box = Instance.new("Model")
	box.Name = string.format("CardboardBox_%02d", index)
	box:SetAttribute("ContainerType", "CardboardBox")
	box.Parent = folder
	containerCount += 1

	local centre = baseCF * CFrame.new(0, height / 2, 0)
	ContainerKit.makePart(
		box,
		"Bottom",
		Vector3.new(width, t, depth),
		centre * CFrame.new(0, -height / 2 + t / 2, 0),
		inner,
		Enum.Material.Cardboard
	)
	ContainerKit.makePart(
		box,
		"Front",
		Vector3.new(width, height, t),
		centre * CFrame.new(0, 0, -depth / 2 + t / 2),
		colour,
		Enum.Material.Cardboard
	)
	ContainerKit.makePart(
		box,
		"Back",
		Vector3.new(width, height, t),
		centre * CFrame.new(0, 0, depth / 2 - t / 2),
		colour,
		Enum.Material.Cardboard
	)
	ContainerKit.makePart(
		box,
		"Left",
		Vector3.new(t, height, depth - t * 2),
		centre * CFrame.new(-width / 2 + t / 2, 0, 0),
		colour,
		Enum.Material.Cardboard
	)
	ContainerKit.makePart(
		box,
		"Right",
		Vector3.new(t, height, depth - t * 2),
		centre * CFrame.new(width / 2 - t / 2, 0, 0),
		colour,
		Enum.Material.Cardboard
	)

	local interior = baseCF * CFrame.new(0, t, 0)
	fillContainer(box, interior, Vector3.new(width - t * 2, height, depth - t * 2))

	-- Two long flaps fold down first, two short ones close over them — so the
	-- side pair sits a hair lower than the front/back pair, as on a real box.
	local innerY = height / 2 - t * 1.5
	local outerY = height / 2 - t * 0.5
	local moving: { BasePart } = {}
	local opened: { CFrame } = {}

	local function addFlap(name: string, size: Vector3, offset: CFrame, hingeOffset: CFrame, rotation: CFrame)
		local flap = ContainerKit.makePart(box, name, size, centre * offset, colour, Enum.Material.Cardboard, false)
		local hinge = centre * hingeOffset
		table.insert(moving, flap)
		table.insert(opened, ContainerKit.hinged(hinge, rotation, flap))
	end

	local swing = math.rad(112)
	addFlap(
		"FlapLeft",
		Vector3.new(width / 2 - t, t, depth - t * 2),
		CFrame.new(-width / 4, innerY, 0),
		CFrame.new(-width / 2 + t, innerY, 0),
		CFrame.Angles(0, 0, swing)
	)
	addFlap(
		"FlapRight",
		Vector3.new(width / 2 - t, t, depth - t * 2),
		CFrame.new(width / 4, innerY, 0),
		CFrame.new(width / 2 - t, innerY, 0),
		CFrame.Angles(0, 0, -swing)
	)
	addFlap(
		"FlapFront",
		Vector3.new(width - t * 2, t, depth / 2 - t),
		CFrame.new(0, outerY, -depth / 4),
		CFrame.new(0, outerY, -depth / 2 + t),
		CFrame.Angles(-swing, 0, 0)
	)
	addFlap(
		"FlapBack",
		Vector3.new(width - t * 2, t, depth / 2 - t),
		CFrame.new(0, outerY, depth / 4),
		CFrame.new(0, outerY, depth / 2 - t),
		CFrame.Angles(swing, 0, 0)
	)

	registerContainer(box, {
		parts = moving,
		opened = opened,
		promptParts = { moving[3] },
		objectText = "Cardboard Box",
		closeText = "Close",
		openSound = ContainerKit.cloneSound(soundTemplate, moving[3], 1.25, 0.35),
		closeSound = ContainerKit.cloneSound(soundTemplate, moving[3], 1.1, 0.3),
	})

	return height
end

local function buildCrate(baseCF: CFrame, index: number): number
	local width, depth, height = 3.4, 3.0, 2.8
	local t = 0.16
	local colour = Color3.fromRGB(118, 86, 55)
	local inner = colour:Lerp(Color3.fromRGB(28, 20, 14), 0.5)

	local crate = Instance.new("Model")
	crate.Name = string.format("Crate_%02d", index)
	crate:SetAttribute("ContainerType", "WoodenCrate")
	crate.Parent = folder
	containerCount += 1

	local centre = baseCF * CFrame.new(0, height / 2, 0)
	ContainerKit.makePart(
		crate,
		"Bottom",
		Vector3.new(width, t, depth),
		centre * CFrame.new(0, -height / 2 + t / 2, 0),
		inner,
		Enum.Material.WoodPlanks
	)
	ContainerKit.makePart(
		crate,
		"Front",
		Vector3.new(width, height - t, t),
		centre * CFrame.new(0, t / 2, -depth / 2 + t / 2),
		colour,
		Enum.Material.WoodPlanks
	)
	ContainerKit.makePart(
		crate,
		"Back",
		Vector3.new(width, height - t, t),
		centre * CFrame.new(0, t / 2, depth / 2 - t / 2),
		colour,
		Enum.Material.WoodPlanks
	)
	ContainerKit.makePart(
		crate,
		"Left",
		Vector3.new(t, height - t, depth - t * 2),
		centre * CFrame.new(-width / 2 + t / 2, t / 2, 0),
		colour,
		Enum.Material.WoodPlanks
	)
	ContainerKit.makePart(
		crate,
		"Right",
		Vector3.new(t, height - t, depth - t * 2),
		centre * CFrame.new(width / 2 - t / 2, t / 2, 0),
		colour,
		Enum.Material.WoodPlanks
	)
	-- Corner battens, so it reads as a crate and not a painted cube.
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			ContainerKit.makePart(
				crate,
				"Batten",
				Vector3.new(t * 1.6, height - t, t * 1.6),
				centre * CFrame.new(sx * (width / 2 - t), t / 2, sz * (depth / 2 - t)),
				colour:Lerp(Color3.fromRGB(255, 255, 255), 0.06),
				Enum.Material.Wood,
				false
			)
		end
	end

	fillContainer(crate, baseCF * CFrame.new(0, t, 0), Vector3.new(width - t * 2, height, depth - t * 2))

	local lid = ContainerKit.makePart(
		crate,
		"Lid",
		Vector3.new(width, t * 1.5, depth),
		centre * CFrame.new(0, height / 2 - t * 0.75, 0),
		colour:Lerp(Color3.fromRGB(255, 255, 255), 0.04),
		Enum.Material.WoodPlanks
	)
	-- Hinged along the back edge so it swings up and away from the player.
	local hinge = centre * CFrame.new(0, height / 2 - t * 1.5, depth / 2)
	registerContainer(crate, {
		parts = { lid },
		opened = { ContainerKit.hinged(hinge, CFrame.Angles(math.rad(108), 0, 0), lid) },
		promptParts = { lid },
		objectText = "Wooden Crate",
		closeText = "Close",
		openSound = ContainerKit.cloneSound(soundTemplate, lid, 0.82, 0.5),
		closeSound = ContainerKit.cloneSound(soundTemplate, lid, 0.7, 0.5),
	})

	return height
end

local function buildFootlocker(baseCF: CFrame, index: number): number
	local width, depth, height = 3.8, 2.3, 1.9
	local t = 0.13
	local colour = Color3.fromRGB(74, 62, 52)
	local metal = Color3.fromRGB(94, 96, 100)

	local locker = Instance.new("Model")
	locker.Name = string.format("Footlocker_%02d", index)
	locker:SetAttribute("ContainerType", "Footlocker")
	locker.Parent = folder
	containerCount += 1

	local bodyHeight = height * 0.72
	local centre = baseCF * CFrame.new(0, bodyHeight / 2, 0)
	ContainerKit.makePart(
		locker,
		"Bottom",
		Vector3.new(width, t, depth),
		centre * CFrame.new(0, -bodyHeight / 2 + t / 2, 0),
		colour,
		Enum.Material.Wood
	)
	ContainerKit.makePart(
		locker,
		"Front",
		Vector3.new(width, bodyHeight, t),
		centre * CFrame.new(0, 0, -depth / 2 + t / 2),
		colour,
		Enum.Material.Wood
	)
	ContainerKit.makePart(
		locker,
		"Back",
		Vector3.new(width, bodyHeight, t),
		centre * CFrame.new(0, 0, depth / 2 - t / 2),
		colour,
		Enum.Material.Wood
	)
	ContainerKit.makePart(
		locker,
		"Left",
		Vector3.new(t, bodyHeight, depth - t * 2),
		centre * CFrame.new(-width / 2 + t / 2, 0, 0),
		colour,
		Enum.Material.Wood
	)
	ContainerKit.makePart(
		locker,
		"Right",
		Vector3.new(t, bodyHeight, depth - t * 2),
		centre * CFrame.new(width / 2 - t / 2, 0, 0),
		colour,
		Enum.Material.Wood
	)
	for _, sx in { -1, 1 } do
		ContainerKit.makePart(
			locker,
			"Strap",
			Vector3.new(t * 1.2, bodyHeight, depth + t * 0.4),
			centre * CFrame.new(sx * width * 0.3, 0, 0),
			metal,
			Enum.Material.Metal,
			false
		)
	end

	fillContainer(locker, baseCF * CFrame.new(0, t, 0), Vector3.new(width - t * 2, bodyHeight, depth - t * 2))

	local lidHeight = height - bodyHeight
	local lidCentre = baseCF * CFrame.new(0, bodyHeight + lidHeight / 2, 0)
	local lid = ContainerKit.makePart(
		locker,
		"Lid",
		Vector3.new(width, lidHeight, depth),
		lidCentre,
		colour,
		Enum.Material.Wood
	)
	local latch = ContainerKit.makePart(
		locker,
		"Latch",
		Vector3.new(0.5, lidHeight * 0.8, 0.12),
		lidCentre * CFrame.new(0, 0, -depth / 2 - 0.04),
		metal,
		Enum.Material.Metal,
		false
	)

	local hinge = baseCF * CFrame.new(0, bodyHeight, depth / 2)
	local rotation = CFrame.Angles(math.rad(104), 0, 0)
	registerContainer(locker, {
		parts = { lid, latch },
		opened = { ContainerKit.hinged(hinge, rotation, lid), ContainerKit.hinged(hinge, rotation, latch) },
		promptParts = { lid },
		objectText = "Footlocker",
		closeText = "Close",
		openSound = ContainerKit.cloneSound(soundTemplate, lid, 0.74, 0.5),
		closeSound = ContainerKit.cloneSound(soundTemplate, lid, 0.66, 0.5),
	})

	return height
end

local function buildSupplyLocker(baseCF: CFrame, index: number): number
	local width, depth, height = 3.6, 2.2, 6.4
	local t = 0.12
	local colour = Color3.fromRGB(104, 112, 116)
	local inner = Color3.fromRGB(46, 50, 53)

	local cabinet = Instance.new("Model")
	cabinet.Name = string.format("SupplyLocker_%02d", index)
	cabinet:SetAttribute("ContainerType", "SupplyLocker")
	cabinet.Parent = folder
	containerCount += 1

	local centre = baseCF * CFrame.new(0, height / 2, 0)
	ContainerKit.makePart(
		cabinet,
		"Bottom",
		Vector3.new(width, t, depth),
		centre * CFrame.new(0, -height / 2 + t / 2, 0),
		inner,
		Enum.Material.Metal
	)
	ContainerKit.makePart(
		cabinet,
		"Top",
		Vector3.new(width, t, depth),
		centre * CFrame.new(0, height / 2 - t / 2, 0),
		colour,
		Enum.Material.Metal
	)
	ContainerKit.makePart(
		cabinet,
		"Back",
		Vector3.new(width, height, t),
		centre * CFrame.new(0, 0, depth / 2 - t / 2),
		inner,
		Enum.Material.Metal
	)
	ContainerKit.makePart(
		cabinet,
		"Left",
		Vector3.new(t, height, depth),
		centre * CFrame.new(-width / 2 + t / 2, 0, 0),
		colour,
		Enum.Material.Metal
	)
	ContainerKit.makePart(
		cabinet,
		"Right",
		Vector3.new(t, height, depth),
		centre * CFrame.new(width / 2 - t / 2, 0, 0),
		colour,
		Enum.Material.Metal
	)

	-- Two shelves, and something sitting on each of them plus the floor.
	local levels = { -height / 2 + t, -height * 0.1, height * 0.22 }
	for level = 2, #levels do
		ContainerKit.makePart(
			cabinet,
			"Shelf",
			Vector3.new(width - t * 2, t, depth - t * 2),
			centre * CFrame.new(0, levels[level], 0),
			inner,
			Enum.Material.Metal
		)
	end
	for _, y in levels do
		fillContainer(cabinet, centre * CFrame.new(0, y + t / 2, 0), Vector3.new(width - t * 3, 1, depth - t * 3))
	end

	local doorThickness = 0.11
	local doorWidth = width / 2 - t * 0.6
	local doorHeight = height - t * 2
	local frontZ = -depth / 2 - doorThickness / 2
	local moving: { BasePart } = {}
	local opened: { CFrame } = {}

	for _, side in { -1, 1 } do
		local door = ContainerKit.makePart(
			cabinet,
			if side < 0 then "LeftDoor" else "RightDoor",
			Vector3.new(doorWidth, doorHeight, doorThickness),
			centre * CFrame.new(side * width / 4, 0, frontZ),
			colour,
			Enum.Material.Metal
		)
		local vent = ContainerKit.makePart(
			cabinet,
			"Vent",
			Vector3.new(doorWidth * 0.6, doorHeight * 0.16, doorThickness * 0.4),
			centre * CFrame.new(side * width / 4, doorHeight * 0.32, frontZ - doorThickness * 0.6),
			inner,
			Enum.Material.DiamondPlate,
			false
		)
		local handle = ContainerKit.makePart(
			cabinet,
			"Handle",
			Vector3.new(0.1, 0.66, 0.11),
			centre * CFrame.new(side * t * 0.9, -height * 0.05, frontZ - doorThickness * 0.9),
			Color3.fromRGB(38, 40, 42),
			Enum.Material.Metal,
			false
		)
		local hinge = centre * CFrame.new(side * (width / 2 - t * 0.4), 0, frontZ)
		local rotation = CFrame.Angles(0, math.rad(-side * 106), 0)
		for _, part in { door, vent, handle } do
			table.insert(moving, part)
			table.insert(opened, ContainerKit.hinged(hinge, rotation, part))
		end
	end

	registerContainer(cabinet, {
		parts = moving,
		opened = opened,
		promptParts = { moving[1], moving[4] },
		objectText = "Supply Locker",
		closeText = "Close",
		openSound = ContainerKit.cloneSound(soundTemplate, moving[1], 0.7, 0.55),
		closeSound = ContainerKit.cloneSound(soundTemplate, moving[4], 0.62, 0.55),
	})

	return height
end

local function buildFilingCabinet(baseCF: CFrame, index: number): number
	local width, depth, height = 2.6, 2.6, 4.4
	local t = 0.1
	local colour = Color3.fromRGB(88, 92, 96)
	local inner = Color3.fromRGB(42, 45, 48)
	local rows = 3

	local cabinet = Instance.new("Model")
	cabinet.Name = string.format("FilingCabinet_%02d", index)
	cabinet:SetAttribute("ContainerType", "FilingCabinet")
	cabinet.Parent = folder
	containerCount += 1

	local centre = baseCF * CFrame.new(0, height / 2, 0)
	ContainerKit.makePart(
		cabinet,
		"Bottom",
		Vector3.new(width, t, depth),
		centre * CFrame.new(0, -height / 2 + t / 2, 0),
		inner,
		Enum.Material.Metal
	)
	ContainerKit.makePart(
		cabinet,
		"Top",
		Vector3.new(width, t, depth),
		centre * CFrame.new(0, height / 2 - t / 2, 0),
		colour,
		Enum.Material.Metal
	)
	ContainerKit.makePart(
		cabinet,
		"Back",
		Vector3.new(width, height, t),
		centre * CFrame.new(0, 0, depth / 2 - t / 2),
		inner,
		Enum.Material.Metal
	)
	ContainerKit.makePart(
		cabinet,
		"Left",
		Vector3.new(t, height, depth),
		centre * CFrame.new(-width / 2 + t / 2, 0, 0),
		colour,
		Enum.Material.Metal
	)
	ContainerKit.makePart(
		cabinet,
		"Right",
		Vector3.new(t, height, depth),
		centre * CFrame.new(width / 2 - t / 2, 0, 0),
		colour,
		Enum.Material.Metal
	)

	local cellHeight = (height - t * (rows + 1)) / rows
	local drawerDepth = depth - t * 2.5
	local frontZ = -depth / 2

	for row = 1, rows do
		local y = height / 2 - t - cellHeight / 2 - (row - 1) * (cellHeight + t)
		local drawer = Instance.new("Model")
		drawer.Name = string.format("Drawer_%02d", row)
		drawer.Parent = cabinet

		local drawerCF = centre * CFrame.new(0, y, 0)
		local box = ContainerKit.makePart(
			drawer,
			"DrawerBottom",
			Vector3.new(width - t * 3, t, drawerDepth),
			drawerCF * CFrame.new(0, -cellHeight / 2 + t / 2, 0),
			inner,
			Enum.Material.Metal
		)
		local left = ContainerKit.makePart(
			drawer,
			"DrawerSide",
			Vector3.new(t, cellHeight * 0.8, drawerDepth),
			drawerCF * CFrame.new(-(width - t * 3) / 2, 0, 0),
			inner,
			Enum.Material.Metal
		)
		local right = ContainerKit.makePart(
			drawer,
			"DrawerSide",
			Vector3.new(t, cellHeight * 0.8, drawerDepth),
			drawerCF * CFrame.new((width - t * 3) / 2, 0, 0),
			inner,
			Enum.Material.Metal
		)
		local back = ContainerKit.makePart(
			drawer,
			"DrawerBack",
			Vector3.new(width - t * 3, cellHeight * 0.8, t),
			drawerCF * CFrame.new(0, 0, drawerDepth / 2),
			inner,
			Enum.Material.Metal
		)
		local front = ContainerKit.makePart(
			drawer,
			"DrawerFront",
			Vector3.new(width - t * 1.4, cellHeight - t * 0.3, t * 1.3),
			drawerCF * CFrame.new(0, 0, frontZ - t * 0.65),
			colour,
			Enum.Material.Metal
		)
		local handle = ContainerKit.makePart(
			drawer,
			"Handle",
			Vector3.new(width * 0.42, 0.11, t * 0.8),
			drawerCF * CFrame.new(0, -cellHeight * 0.16, frontZ - t * 1.5),
			Color3.fromRGB(36, 38, 40),
			Enum.Material.Metal,
			false
		)

		local moving: { BasePart } = { box, left, right, back, front, handle }
		for _, item in
			fillContainer(
				drawer,
				drawerCF * CFrame.new(0, -cellHeight / 2 + t, 0),
				Vector3.new(width - t * 4, cellHeight, drawerDepth - t)
			)
		do
			table.insert(moving, item)
		end

		-- Contents ride out with the drawer, so the slide is applied to all of it.
		local travel = math.clamp(depth * 0.7, 1.3, 2.2)
		local opened: { CFrame } = {}
		for movingIndex, part in moving do
			opened[movingIndex] = ContainerKit.slid(centre, CFrame.new(0, 0, -travel), part)
		end

		registerContainer(drawer :: any, {
			parts = moving,
			opened = opened,
			promptParts = { front },
			objectText = "Filing Cabinet",
			closeText = "Close",
			openSound = ContainerKit.cloneSound(soundTemplate, front, 0.95, 0.45),
			closeSound = ContainerKit.cloneSound(soundTemplate, front, 0.85, 0.45),
		})
	end

	return height
end

-- Layout ----------------------------------------------------------------------

type Spot = {
	x: number,
	z: number,
	yaw: number,
	kind: string,
	stack: number?,
}

-- Local -Z is a container's front, so yaw -90 faces east (+X), 90 faces west,
-- 0 faces the doorway at the north end of the room.
local SPOTS: { Spot } = {
	-- West run, backs to the metal shelving, facing the middle of the room.
	-- Elevator 2's floor slab reaches to X 267.7 / Z 50.4 at Y 32.6: containers
	-- sitting fully on it just seat 0.1 higher, but anything straddling its edge
	-- would clip the corner, so the first two are kept north of Z 50.4.
	{ x = 267.6, z = 45.0, yaw = -90, kind = "crate" },
	{ x = 267.6, z = 48.7, yaw = -90, kind = "box", stack = 2 },
	{ x = 267.6, z = 52.8, yaw = -90, kind = "locker" },
	{ x = 267.6, z = 56.8, yaw = -90, kind = "crate" },
	{ x = 267.6, z = 60.5, yaw = -90, kind = "box", stack = 3 },
	{ x = 267.6, z = 64.3, yaw = -90, kind = "footlocker" },

	-- East run along the far wall.
	{ x = 280.6, z = 45.6, yaw = 90, kind = "locker" },
	{ x = 280.6, z = 49.6, yaw = 90, kind = "locker" },
	{ x = 280.6, z = 53.6, yaw = 90, kind = "box", stack = 2 },
	{ x = 280.6, z = 57.4, yaw = 90, kind = "crate" },
	{ x = 280.6, z = 61.0, yaw = 90, kind = "filing" },
	{ x = 280.6, z = 64.6, yaw = 90, kind = "crate" },

	-- Inner rows. These sit hard against the wall runs and leave the middle of
	-- the room — about three and a half studs, lined up on the doorway at X 274
	-- — as the walking lane.
	{ x = 271.0, z = 47.4, yaw = -90, kind = "box" },
	{ x = 271.0, z = 51.0, yaw = -90, kind = "crate" },
	-- These two stop short of Z 64 on purpose: the way through to the alcove runs
	-- between here and the rear crate, and pathfinding needs four clear studs.
	{ x = 271.0, z = 57.9, yaw = -90, kind = "box", stack = 2 },
	{ x = 271.0, z = 61.6, yaw = -90, kind = "footlocker" },

	{ x = 277.2, z = 47.4, yaw = 90, kind = "crate" },
	{ x = 277.2, z = 51.0, yaw = 90, kind = "box", stack = 2 },
	{ x = 277.2, z = 54.6, yaw = 90, kind = "box", stack = 2 },
	{ x = 277.2, z = 58.4, yaw = 90, kind = "crate" },
	{ x = 277.2, z = 62.4, yaw = 90, kind = "box" },

	-- Crowding the doorway, which is the first thing you see walking in.
	{ x = 271.0, z = 43.6, yaw = -90, kind = "box", stack = 2 },
	{ x = 277.2, z = 43.6, yaw = 90, kind = "box", stack = 2 },

	-- Rear wall, facing back toward the door. SuiteElevator1's shaft starts at
	-- Z 68.3 and the inner rows end around Z 66, so only one fits back here.
	{ x = 276.0, z = 66.4, yaw = 0, kind = "crate" },

	-- The alcove past the shelving on the west side. The rear shelf unit starts at
	-- Z 71.85 and the west run ends at Z 65.9, so there is room for exactly one
	-- container back here — a second would clip the shelf.
	{ x = 267.8, z = 69.0, yaw = -90, kind = "crate" },
}

local BUILDERS: { [string]: (CFrame, number) -> number } = {
	box = buildCardboardBox,
	crate = buildCrate,
	locker = buildSupplyLocker,
	footlocker = buildFootlocker,
	filing = buildFilingCabinet,
}

-- Local width (X) and depth (Z) of each carcass, kept in step with the builders.
-- The layout above is authored by hand, and hand-authored coordinates drift out
-- of true by a couple of tenths; rather than trust them, every spot is checked
-- against the ones already placed and nudged along its run until it fits.
-- Measured off the built models, not off the carcass constants: locker doors,
-- footlocker straps and drawer fronts all stand proud of the box they hang on.
local FOOTPRINTS: { [string]: Vector2 } = {
	box = Vector2.new(3.0, 2.6),
	crate = Vector2.new(3.4, 3.0),
	locker = Vector2.new(3.6, 2.45),
	footlocker = Vector2.new(3.8, 2.45),
	filing = Vector2.new(2.6, 2.8),
}

type Rect = { minX: number, maxX: number, minZ: number, maxZ: number }

-- Clearance required between neighbours. Large enough to swallow the corner
-- sweep from the yaw jitter below, so nothing ends up interpenetrating.
local GAP = 0.3

-- Yaw is always a multiple of 90 here, so the footprint just swaps axes.
local function rectFor(spot: Spot, x: number, z: number): Rect
	local size = FOOTPRINTS[spot.kind]
	local sideways = math.abs(spot.yaw) == 90
	local halfX = (if sideways then size.Y else size.X) / 2
	local halfZ = (if sideways then size.X else size.Y) / 2
	return { minX = x - halfX, maxX = x + halfX, minZ = z - halfZ, maxZ = z + halfZ }
end

local function overlaps(a: Rect, b: Rect): boolean
	return a.minX < b.maxX + GAP and b.minX < a.maxX + GAP and a.minZ < b.maxZ + GAP and b.minZ < a.maxZ + GAP
end

local placed: { Rect } = {}

local function fits(rect: Rect): boolean
	for _, other in placed do
		if overlaps(rect, other) then
			return false
		end
	end
	return true
end

-- Slide along the axis the run extends: rows against a side wall shuffle in Z,
-- rows against the back wall shuffle in X.
local function resolve(spot: Spot): (number?, number?)
	local alongZ = math.abs(spot.yaw) == 90
	for step = 0, 8 do
		for _, direction in { 1, -1 } do
			local shift = step * 0.3 * direction
			local x = if alongZ then spot.x else spot.x + shift
			local z = if alongZ then spot.z + shift else spot.z
			local rect = rectFor(spot, x, z)
			if fits(rect) then
				table.insert(placed, rect)
				return x, z
			end
			if step == 0 then
				break
			end
		end
	end
	return nil, nil
end

local skipped = 0
local nudged = 0
for index, spot in SPOTS do
	local x, z = resolve(spot)
	if not x or not z then
		warn(
			string.format(
				"[StorageRoomLootService] no room for %s at (%.1f, %.1f) — skipping",
				spot.kind,
				spot.x,
				spot.z
			)
		)
		skipped += 1
		continue
	end
	if math.abs(x - spot.x) > 0.01 or math.abs(z - spot.z) > 0.01 then
		nudged += 1
	end

	local floorY = groundAt(x, z)
	if not floorY then
		-- No floor under the authored position means the room moved; say so
		-- rather than dropping a box into the void.
		warn(string.format("[StorageRoomLootService] no floor at (%.1f, %.1f) — skipping", x, z))
		skipped += 1
		continue
	end

	local builder = BUILDERS[spot.kind]
	if builder then
		-- A degree of slop stops the room reading as a grid. Kept small so the
		-- swept corners stay inside the footprint reserved above.
		local jitter = rng:NextNumber(-1.5, 1.5)
		local baseCF = CFrame.new(x, floorY, z) * CFrame.Angles(0, math.rad(spot.yaw + jitter), 0)
		local stack = spot.stack or 1
		local lift = 0
		for level = 1, stack do
			local height = builder(baseCF * CFrame.new(0, lift, 0), index * 10 + level)
			lift += height
		end
	end
end

print(
	string.format(
		"[StorageRoomLootService] %d containers, %d openable, %d items stashed%s%s",
		containerCount,
		openableCount,
		lootCount,
		if nudged > 0 then string.format(", %d nudged clear", nudged) else "",
		if skipped > 0 then string.format(", %d spots skipped", skipped) else ""
	)
)
