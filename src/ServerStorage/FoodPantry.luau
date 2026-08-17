--!strict
--[[
	Real food, cloned out of the mesh pack the place already ships with.

	Workspace.Folder holds ~190 food meshes (burgers, pizza, cookies, cereal,
	canned goods...) parked off-map as a template pile. Building food out of
	Parts would look like coloured bricks next to them, so everything edible in
	the hotel is a clone of one of those meshes.

	The pack's models are unanchored and small — a burger is under half a stud —
	so `place` anchors each clone, scales it up to something you can actually see
	on a table, and seats it on the surface you hand it.

	Edibility is SurvivalService's job: tag an instance "Food" and it hangs a
	ClickDetector on it and applies the attributes when clicked. This module only
	sets those attributes and decides when the tag goes on, which is the
	difference between a snack you can see and one you can eat through a shut
	drawer.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local SackConfig = require(ReplicatedStorage:WaitForChild("SackConfig"))
local SurvivalConfig = require(ReplicatedStorage:WaitForChild("SurvivalConfig"))

local FoodPantry = {}

local ATTR = SurvivalConfig.FoodAttributes
local SOURCE_FOLDER = "Folder"

-- How long until an eaten item comes back. Without this a server that has been
-- up for an hour has been picked clean and there is nothing to find.
FoodPantry.RespawnSeconds = 150

-- Menus ----------------------------------------------------------------------
-- Name prefixes, matched against the template pile. Numbered variants
-- (Burger_01, Cookies_17, ...) all match their family, so each entry is a
-- family rather than one specific mesh.

local MENUS: { [string]: { string } } = {
	-- Plated meals, for restaurant tables.
	restaurant = {
		"Burger", "Pizza", "Sliced_pizza", "Hot_dog", "Fried_chicken",
		"Waffle", "Fast_food", "Roast_meat", "Rice",
	},
	-- A service spread: things that sit out under lights.
	buffet = {
		"bread", "Roast_meat", "Rice", "Watermelon", "Cookies", "Donuts",
		"Fried_chicken", "Sliced_pizza",
	},
	-- Room service leftovers and fruit bowls for the suites.
	suite = {
		"Donuts", "Cookies", "bread", "Watermelon", "Milk", "Water", "Waffle",
	},
	-- Packaged snacks, for drawers and bedside tables.
	snack = {
		"potato_chips", "Box_cookies", "Cereal", "Canned_food", "Soda",
		"Popcorn", "Cookies",
	},
}

-- Templates ------------------------------------------------------------------

local templateCache: { [string]: { Model } } = {}

local function sourceFolder(): Instance?
	return Workspace:FindFirstChild(SOURCE_FOLDER)
end

-- Every model whose name is `family` or `family_NN`.
local function familyMembers(folder: Instance, family: string): { Model }
	local found: { Model } = {}
	local lowered = string.lower(family)
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			local name = string.lower(child.Name)
			if name == lowered or string.match(name, "^" .. lowered:gsub("%-", "%%-") .. "_%d+$") then
				table.insert(found, child)
			end
		end
	end
	return found
end

function FoodPantry.templatesFor(menu: string): { Model }
	local cached = templateCache[menu]
	if cached then
		return cached
	end

	local folder = sourceFolder()
	local families = MENUS[menu]
	local templates: { Model } = {}
	if folder and families then
		for _, family in families do
			for _, model in familyMembers(folder, family) do
				table.insert(templates, model)
			end
		end
	end
	templateCache[menu] = templates
	return templates
end

-- Geometry -------------------------------------------------------------------

-- World-axis-aligned bounds. The pack's meshes are rotated, so Size.Y is not
-- the vertical extent and naive maths drops food through tables.
function FoodPantry.worldBounds(instance: Instance): (Vector3?, Vector3?)
	local min: Vector3?, max: Vector3? = nil, nil
	for _, part in instance:GetDescendants() do
		if part:IsA("BasePart") then
			local cf, size = part.CFrame, part.Size
			local rx, ry, rz = cf.XVector, cf.YVector, cf.ZVector
			local extent = Vector3.new(
				math.abs(rx.X) * size.X / 2 + math.abs(ry.X) * size.Y / 2 + math.abs(rz.X) * size.Z / 2,
				math.abs(rx.Y) * size.X / 2 + math.abs(ry.Y) * size.Y / 2 + math.abs(rz.Y) * size.Z / 2,
				math.abs(rx.Z) * size.X / 2 + math.abs(ry.Z) * size.Y / 2 + math.abs(rz.Z) * size.Z / 2
			)
			local lo, hi = cf.Position - extent, cf.Position + extent
			min = if min
				then Vector3.new(math.min(min.X, lo.X), math.min(min.Y, lo.Y), math.min(min.Z, lo.Z))
				else lo
			max = if max
				then Vector3.new(math.max(max.X, hi.X), math.max(max.Y, hi.Y), math.max(max.Z, hi.Z))
				else hi
		end
	end
	return min, max
end

-- Edibility ------------------------------------------------------------------

local function prettyName(rawName: string): string
	local name = rawName:gsub("_%d+$", ""):gsub("_", " ")
	return (name:gsub("^%l", string.upper))
end

-- Attributes only. The "Food" tag is what actually arms it, and callers decide
-- when that happens — immediately for food sitting out, on first open for food
-- hidden inside something.
function FoodPantry.season(model: Model, bars: number, action: string?)
	model:SetAttribute(ATTR.Hunger, SurvivalConfig.hungerPerSegment() * bars)
	model:SetAttribute(ATTR.Health, 0)
	model:SetAttribute(ATTR.Stamina, 0)
	model:SetAttribute(ATTR.Action, action or "Eat")
	model:SetAttribute(ATTR.Uses, 1)
	model:SetAttribute(ATTR.Respawn, FoodPantry.RespawnSeconds)
	model:SetAttribute("EdibleBars", bars)
end

-- Arming an item does two things: SurvivalService gives it a click-to-eat
-- detector, and the sack is allowed to bag it. Both happen at the same moment
-- so a snack inside a shut drawer is neither edible nor pocketable.
function FoodPantry.serve(model: Model)
	CollectionService:AddTag(model, SurvivalConfig.FoodTag)
	CollectionService:AddTag(model, SackConfig.CollectableTag)
end

-- Arm everything stashed inside a container the moment it is opened.
function FoodPantry.serveInside(container: Instance)
	for _, descendant in container:GetDescendants() do
		if descendant:IsA("Model") and descendant:GetAttribute("EdibleBars") then
			FoodPantry.serve(descendant)
		end
	end
end

-- Placement ------------------------------------------------------------------

export type PlaceOptions = {
	menu: string,
	position: Vector3, -- a point ON the surface; the food is seated on top of it
	parent: Instance,
	rng: Random,
	bars: number?,
	targetSize: number?, -- longest dimension after scaling, in studs
	yaw: number?,
	armNow: boolean?, -- false for food hidden inside a container
}

function FoodPantry.place(options: PlaceOptions): Model?
	local templates = FoodPantry.templatesFor(options.menu)
	if #templates == 0 then
		return nil
	end

	local template = templates[options.rng:NextInteger(1, #templates)]
	local model = template:Clone()

	-- Scale before seating: the lift depends on how tall it ends up.
	--
	-- ScaleTo takes an ABSOLUTE scale, and the pack's models are not authored at
	-- 1 — most sit around 2.4. Passing a bare ratio here silently shrinks them,
	-- so the existing scale has to be carried through.
	local _, size = model:GetBoundingBox()
	local longest = math.max(size.X, size.Y, size.Z)
	if longest > 0 then
		local target = options.targetSize or 1.2
		local factor = math.clamp(target / longest, 0.5, 4)
		model:ScaleTo(model:GetScale() * factor)
	end

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			-- Anchored props on a table should not shove players or block shots.
			part.CanCollide = false
			part.CanTouch = false
			part.CastShadow = true
		end
	end

	model.Name = prettyName(template.Name)
	model.Parent = options.parent

	local yaw = options.yaw or options.rng:NextNumber(0, math.pi * 2)
	model:PivotTo(CFrame.new(options.position) * CFrame.Angles(0, yaw, 0))

	-- These models carry a large pivot offset — the pivot can sit two studs away
	-- from the mesh itself — so PivotTo alone puts the food somewhere near the
	-- target rather than on it. Correct all three axes against the geometry:
	-- centred horizontally on the point, resting on it vertically.
	local min, max = FoodPantry.worldBounds(model)
	if min and max then
		local centre = (min + max) / 2
		local delta = Vector3.new(
			options.position.X - centre.X,
			options.position.Y - min.Y,
			options.position.Z - centre.Z
		)
		model:PivotTo(CFrame.new(delta) * model:GetPivot())
	end

	FoodPantry.season(model, options.bars or 1)
	if options.armNow ~= false then
		FoodPantry.serve(model)
	end
	return model
end

return FoodPantry
