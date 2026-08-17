--!strict
--[[
	Scatters edible food across the hotel: restaurant tables, the service
	buffet, and the tables in the suites.

	Everything it places is a clone from the mesh pack (see FoodPantry) tagged
	"Food", so SurvivalService hangs a ClickDetector on each one and applies the
	hunger when it is clicked. One item is worth one bar of the meter.

	Surfaces are found rather than hardcoded. The furniture models are rotated,
	which makes their Size components useless for working out where the top is,
	so each candidate is raycast from above and the highest hit inside the middle
	of the model becomes the surface. Move a table in Studio and the food follows
	it on the next run.

	Food inside drawers is not handled here — that lives in
	FurnitureInteractionService, because a drawer's contents have to be part of
	the set that slides out with it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local FoodPantry = require(ServerStorage:WaitForChild("FoodPantry"))
local SurvivalConfig = require(ReplicatedStorage:WaitForChild("SurvivalConfig"))

local FOLDER_NAME = "PlacedFood"
-- Not every table. A restaurant where every single cover is laid reads as a
-- set dressing; a few plates left out reads as a place people fled.
local DINING_TABLE_CHANCE = 0.55

local rng = Random.new()

local existing = Workspace:FindFirstChild(FOLDER_NAME)
if existing then
	existing:Destroy()
end

local folder = Instance.new("Folder")
folder.Name = FOLDER_NAME
folder.Parent = Workspace

local placed = 0
local rejected = 0

-- Surfaces --------------------------------------------------------------------

-- The top surface at a given column, restricted to one model.
local function rayDown(model: Model, x: number, z: number, fromY: number, distance: number): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { model }
	return Workspace:Raycast(Vector3.new(x, fromY, z), Vector3.new(0, -distance, 0), params)
end

-- The part a diner would put a plate on: whatever the model presents at its own
-- horizontal centre. Returning the part, not just a point, is what lets the
-- scatter below stay on the table instead of wandering onto a chair back — the
-- failure that put food in mid-air over the edge of a dining set.
local function tableTop(model: Model): (BasePart?, number?)
	local min, max = FoodPantry.worldBounds(model)
	if not min or not max then
		return nil, nil
	end
	local centre = (min + max) / 2
	local hit = rayDown(model, centre.X, centre.Z, max.Y + 2, (max.Y - min.Y) + 4)
	if not hit then
		return nil, nil
	end
	return hit.Instance, hit.Position.Y
end

-- Horizontal half-extents of a part, correct for rotation.
local function halfFootprint(part: BasePart): (number, number)
	local cf, size = part.CFrame, part.Size
	local rx, ry, rz = cf.XVector, cf.YVector, cf.ZVector
	local halfX = math.abs(rx.X) * size.X / 2 + math.abs(ry.X) * size.Y / 2 + math.abs(rz.X) * size.Z / 2
	local halfZ = math.abs(rx.Z) * size.X / 2 + math.abs(ry.Z) * size.Y / 2 + math.abs(rz.Z) * size.Z / 2
	return halfX, halfZ
end

-- Does the item actually rest on `top`? Sampling the item's own footprint
-- corners catches the case a single centre ray misses: an item whose chosen
-- point was on the surface but which is wide enough to overhang the edge.
local function supported(item: Model, top: BasePart, topY: number): boolean
	local min, max = FoodPantry.worldBounds(item)
	if not min or not max then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { top }

	-- A diamond through the item's middle rather than its bounding corners: the
	-- tables here are round, so corner samples fall off a top the item is
	-- comfortably sitting on.
	local centre = (min + max) / 2
	local reach = (max - min) * 0.3
	local samples = {
		Vector2.new(0, 0),
		Vector2.new(reach.X, 0),
		Vector2.new(-reach.X, 0),
		Vector2.new(0, reach.Z),
		Vector2.new(0, -reach.Z),
	}
	for _, offset in samples do
		local hit = Workspace:Raycast(
			Vector3.new(centre.X + offset.X, topY + 2, centre.Z + offset.Y),
			Vector3.new(0, -4, 0),
			params
		)
		if not hit or math.abs(hit.Position.Y - topY) > 0.3 then
			return false
		end
	end
	return true
end

-- Scatter `count` items across a model's top surface without stacking them.
local function dress(model: Model, menu: string, count: number, targetSize: number, maxSpread: number?)
	local top, topY = tableTop(model)
	if not top or not topY then
		return
	end

	-- Scatter inside the ellipse inscribed in the surface's footprint rather
	-- than the footprint itself. The restaurant tables are round, so the corners
	-- of their bounding box are thin air; an inscribed ellipse is also safe on a
	-- rectangular counter, just a little conservative.
	local halfX, halfZ = halfFootprint(top)
	local margin = targetSize * 0.75
	local spreadX = math.max(halfX - margin, 0)
	local spreadZ = math.max(halfZ - margin, 0)
	if maxSpread then
		spreadX = math.min(spreadX, maxSpread)
		spreadZ = math.min(spreadZ, maxSpread)
	end

	local centreX, centreZ = top.Position.X, top.Position.Z
	local used: { Vector3 } = {}

	for _ = 1, count do
		for _ = 1, 14 do
			-- sqrt keeps the scatter even instead of bunched at the middle
			local radius = math.sqrt(rng:NextNumber())
			local angle = rng:NextNumber(0, math.pi * 2)
			local x = centreX + math.cos(angle) * radius * spreadX
			local z = centreZ + math.sin(angle) * radius * spreadZ

			local clear = true
			for _, other in used do
				if (Vector3.new(x, 0, z) - Vector3.new(other.X, 0, other.Z)).Magnitude < targetSize * 1.2 then
					clear = false
					break
				end
			end

			if clear then
				-- Must land on the same part we measured, at the same height:
				-- that is the difference between "on the table" and "over the
				-- edge of it".
				local hit = rayDown(model, x, z, topY + 3, 6)
				if hit and hit.Instance == top and math.abs(hit.Position.Y - topY) < 0.2 then
					-- Placed unarmed: a rejected item is destroyed below, and
					-- tagging it first would hand SurvivalService a model that
					-- is gone by the time it binds ("has no part to click on").
					local item = FoodPantry.place({
						menu = menu,
						position = hit.Position,
						parent = folder,
						rng = rng,
						bars = 1,
						targetSize = targetSize,
						armNow = false,
					})
					if item then
						-- Prove it landed on something before leaving it there.
						-- The item is wider than the ray that chose the spot, so
						-- check its own footprint corners are still over the
						-- surface — that is what stops food hanging off an edge.
						if supported(item, top, topY) then
							item:SetAttribute("PlacedOn", top:GetFullName())
							item:SetAttribute("PlacedOnY", topY)
							FoodPantry.serve(item)
							placed += 1
							table.insert(used, Vector3.new(x, topY, z))
						else
							item:Destroy()
							rejected += 1
						end
					end
					break
				end
			end
		end
	end
end

-- Restaurant ------------------------------------------------------------------

local amenities = Workspace:FindFirstChild("AmenitiesFloorBlueprint")
local restaurant = amenities
	and amenities:FindFirstChild("Furnishing")
	and amenities.Furnishing:FindFirstChild("HeavyLuxuryDecor")
	and amenities.Furnishing.HeavyLuxuryDecor:FindFirstChild("RestaurantFurniture")

local tablesLaid = 0
if restaurant then
	for _, model in restaurant:GetChildren() do
		if model:IsA("Model") then
			if string.find(model.Name, "DiningSet", 1, true) then
				if rng:NextNumber() < DINING_TABLE_CHANCE then
					dress(model, "restaurant", rng:NextInteger(1, 2), 1.3)
					tablesLaid += 1
				end
			elseif string.find(model.Name, "Buffet", 1, true) then
				dress(model, "buffet", 6, 1.4)
			end
		end
	end
else
	warn("[FoodPlacementService] restaurant furniture not found — skipped")
end

-- Suites ----------------------------------------------------------------------

local suiteFloor = Workspace:FindFirstChild("SuiteFloor")
local suiteFurniture = suiteFloor and suiteFloor:FindFirstChild("Furniture")
local suiteTables = 0
if suiteFurniture then
	for _, wing in suiteFurniture:GetChildren() do
		for _, model in wing:GetChildren() do
			if model:IsA("Model") then
				local name = model.Name
				local isTable = (string.find(name, "Table", 1, true) or string.find(name, "Dining", 1, true))
					and not string.find(name, "Lamp", 1, true)
				if isTable then
					dress(model, "suite", rng:NextInteger(1, 2), 1.15)
					suiteTables += 1
				end
			end
		end
	end
else
	warn("[FoodPlacementService] suite furniture not found — skipped")
end

print(
	string.format(
		"[FoodPlacementService] %d items out (%d restaurant tables, %d suite tables), %d rejected as unsupported; one item = %.2f hunger (1 of %d bars)",
		placed,
		tablesLaid,
		suiteTables,
		rejected,
		SurvivalConfig.hungerPerSegment(),
		SurvivalConfig.HungerSegments
	)
)
