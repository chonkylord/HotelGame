--!strict
--[[
	The mallet, in its two shapes.

	It exists twice because it lives two lives: a Model lying on a restaurant
	table that you can walk up to, look at, and bag; and a Tool once it is in
	your hands. Both are built from the same `dress` call so the thing you pick
	up is visibly the thing you saw, and MalletService swaps one for the other.

	Geometry only. Nothing here tags, prompts, welds itself to a player, or
	decides who may hold it — that is MalletService's business, the same split
	CluePropKit keeps with ClueService.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DisplayCaseConfig = require(ReplicatedStorage:WaitForChild("DisplayCaseConfig"))

local MalletKit = {}

local WOOD = Color3.fromRGB(94, 63, 39)
local LEATHER = Color3.fromRGB(48, 36, 30)
local STEEL = Color3.fromRGB(108, 116, 126)
local STEEL_LIGHT = Color3.fromRGB(176, 186, 196)
local BRASS = Color3.fromRGB(198, 152, 62)

-- The shaft runs along the part's own +Y, which is the convention the rest of
-- this place's hand-built tools use (see ClueService's solar lance) and what a
-- default Tool.Grip expects.
local SHAFT_SIZE = Vector3.new(0.3, 2.6, 0.3)

type Piece = {
	name: string,
	size: Vector3,
	offset: Vector3,
	colour: Color3,
	material: Enum.Material,
	reflectance: number?,
	-- Collides only where the shaft does, which is the prop and never the Tool:
	-- a collidable part welded to a hand shoves the character it is welded to.
	solid: boolean?,
}

-- A steel head heavy enough to read across a dark dining room, with pale end
-- caps so the silhouette does not disappear into the wood.
local PIECES: { Piece } = {
	{
		name = "Head",
		size = Vector3.new(1.7, 0.92, 0.92),
		offset = Vector3.new(0, 1.16, 0),
		colour = STEEL,
		material = Enum.Material.Metal,
		reflectance = 0.16,
		-- The head is half a stud deeper than the shaft it hangs off. Without a
		-- collider of its own, a mallet dropped on the floor balances on the
		-- shaft and buries its head in the boards.
		solid = true,
	},
	{
		name = "HeadFaceA",
		size = Vector3.new(0.14, 0.98, 0.98),
		offset = Vector3.new(-0.85, 1.16, 0),
		colour = STEEL_LIGHT,
		material = Enum.Material.Metal,
		reflectance = 0.28,
	},
	{
		name = "HeadFaceB",
		size = Vector3.new(0.14, 0.98, 0.98),
		offset = Vector3.new(0.85, 1.16, 0),
		colour = STEEL_LIGHT,
		material = Enum.Material.Metal,
		reflectance = 0.28,
	},
	{
		name = "Collar",
		size = Vector3.new(0.4, 0.3, 0.4),
		offset = Vector3.new(0, 0.62, 0),
		colour = BRASS,
		material = Enum.Material.Metal,
		reflectance = 0.3,
	},
	{
		name = "Grip",
		size = Vector3.new(0.36, 0.95, 0.36),
		offset = Vector3.new(0, -0.62, 0),
		colour = LEATHER,
		material = Enum.Material.Fabric,
	},
	{
		name = "Pommel",
		size = Vector3.new(0.42, 0.16, 0.42),
		offset = Vector3.new(0, -1.34, 0),
		colour = BRASS,
		material = Enum.Material.Metal,
		reflectance = 0.3,
	},
}

local function styleShaft(shaft: BasePart)
	shaft.Size = SHAFT_SIZE
	shaft.Color = WOOD
	shaft.Material = Enum.Material.Wood
	shaft.TopSurface = Enum.SurfaceType.Smooth
	shaft.BottomSurface = Enum.SurfaceType.Smooth
end

--[[
	Hang the head and its fittings off a shaft.

	WeldConstraints rather than anchoring, because both shapes need to survive
	being moved: the Tool is welded to a hand every time it is equipped, and the
	prop is unanchored the moment the sack drops it or a player throws it away.
]]
function MalletKit.dress(container: Instance, shaft: BasePart)
	for _, piece in PIECES do
		local part = Instance.new("Part")
		part.Name = piece.name
		part.Size = piece.size
		part.CFrame = shaft.CFrame * CFrame.new(piece.offset)
		part.Color = piece.colour
		part.Material = piece.material
		part.Reflectance = piece.reflectance or 0
		part.Anchored = shaft.Anchored
		part.CanCollide = piece.solid == true and shaft.CanCollide
		part.CanTouch = false
		part.Massless = true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = container

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = shaft
		weld.Part1 = part
		weld.Parent = part
	end
end

-- The held version. CanBeDropped stays on: MalletService turns a dropped tool
-- back into a prop, so throwing it away puts a real, baggable mallet on the
-- floor rather than an inert Tool nobody can interact with.
function MalletKit.buildTool(): Tool
	local tool = Instance.new("Tool")
	tool.Name = DisplayCaseConfig.MalletName
	tool.ToolTip = "Swing it at the glass"
	tool.RequiresHandle = true
	tool.CanBeDropped = true

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Anchored = false
	handle.CanCollide = false
	handle.CanTouch = false
	handle.Massless = true
	styleShaft(handle)
	handle.Parent = tool

	MalletKit.dress(tool, handle)
	return tool
end

-- The world version: anchored where it is put down, one collidable body so it
-- can also be thrown, and a PrimaryPart the sack and the prompt can both hang
-- off.
function MalletKit.buildProp(): Model
	local model = Instance.new("Model")
	model.Name = DisplayCaseConfig.MalletName

	local shaft = Instance.new("Part")
	shaft.Name = "Shaft"
	shaft.Anchored = true
	shaft.CanCollide = true
	shaft.CanTouch = false
	styleShaft(shaft)
	shaft.Parent = model

	MalletKit.dress(model, shaft)
	model.PrimaryPart = shaft
	return model
end

-- World-axis-aligned extents, correct for a rotated model. The prop is laid on
-- its side across a table, so Size.Y is not its height and seating it by the
-- bounding box alone drops the head through the tabletop. Same correction
-- FoodPantry makes for the food meshes.
function MalletKit.worldBounds(instance: Instance): (Vector3?, Vector3?)
	local min: Vector3?, max: Vector3? = nil, nil
	for _, part in instance:GetDescendants() do
		if part:IsA("BasePart") then
			local cframe, size = part.CFrame, part.Size
			local rx, ry, rz = cframe.XVector, cframe.YVector, cframe.ZVector
			local extent = Vector3.new(
				math.abs(rx.X) * size.X / 2 + math.abs(ry.X) * size.Y / 2 + math.abs(rz.X) * size.Z / 2,
				math.abs(rx.Y) * size.X / 2 + math.abs(ry.Y) * size.Y / 2 + math.abs(rz.Y) * size.Z / 2,
				math.abs(rx.Z) * size.X / 2 + math.abs(ry.Z) * size.Y / 2 + math.abs(rz.Z) * size.Z / 2
			)
			local low, high = cframe.Position - extent, cframe.Position + extent
			min = if min
				then Vector3.new(math.min(min.X, low.X), math.min(min.Y, low.Y), math.min(min.Z, low.Z))
				else low
			max = if max
				then Vector3.new(math.max(max.X, high.X), math.max(max.Y, high.Y), math.max(max.Z, high.Z))
				else high
		end
	end
	return min, max
end

return MalletKit
