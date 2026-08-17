--!strict
-- Superman's class silhouette: a hotel-red cape with gold edging and an
-- angular brass crown. Both are Accessories, so Roblox fits them through the
-- character's standard attachments without replacing the player's avatar.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClassConfig = require(ReplicatedStorage:WaitForChild("ClassDefinitions"))

local SupermanGear = {}

local CAPE_NAME = "SupermanCape"
local CROWN_NAME = "SupermanCrown"

local RED = Color3.fromRGB(151, 43, 39)
local RED_DARK = Color3.fromRGB(92, 27, 31)
local GOLD = Color3.fromRGB(222, 174, 67)
local GOLD_PALE = Color3.fromRGB(247, 215, 128)
local GEM = Color3.fromRGB(49, 132, 196)

local function part(
	name: string,
	size: Vector3,
	colour: Color3,
	material: Enum.Material,
	parent: Instance
): Part
	local value = Instance.new("Part")
	value.Name = name
	value.Size = size
	value.Color = colour
	value.Material = material
	value.Anchored = false
	value.CanCollide = false
	value.CanQuery = false
	value.CanTouch = false
	value.Massless = true
	value.TopSurface = Enum.SurfaceType.Smooth
	value.BottomSurface = Enum.SurfaceType.Smooth
	value.CFrame = CFrame.new()
	value.Parent = parent
	return value
end

local function weld(handle: BasePart, value: BasePart)
	local constraint = Instance.new("WeldConstraint")
	constraint.Part0 = handle
	constraint.Part1 = value
	constraint.Parent = value
end

local function tag(accessory: Accessory)
	CollectionService:AddTag(accessory, ClassConfig.SUPERMAN_GEAR_TAG)
	for _, descendant in accessory:GetDescendants() do
		if descendant:IsA("BasePart") then
			CollectionService:AddTag(descendant, ClassConfig.SUPERMAN_GEAR_TAG)
		end
	end
end

local function buildCape(): Accessory
	local accessory = Instance.new("Accessory")
	accessory.Name = CAPE_NAME

	local handle = part("Handle", Vector3.new(0.12, 0.12, 0.12), RED, Enum.Material.Fabric, accessory)
	handle.Transparency = 1

	local attachment = Instance.new("Attachment")
	attachment.Name = "BodyBackAttachment"
	attachment.CFrame = CFrame.new(0, 0.3, -0.12)
	attachment.Parent = handle

	-- Three overlapping panels taper toward the hem. The shallow backward bend
	-- keeps the cape clear of the legs while still reading as cloth at a run.
	local panels = {
		{ name = "CapeUpper", size = Vector3.new(2.5, 1.15, 0.11), y = -0.65, z = 0.12, tilt = -7 },
		{ name = "CapeMiddle", size = Vector3.new(2.22, 1.2, 0.11), y = -1.72, z = 0.27, tilt = -9 },
		{ name = "CapeHem", size = Vector3.new(1.9, 1.05, 0.12), y = -2.77, z = 0.46, tilt = -11 },
	}
	for _, spec in panels do
		local panel = part(spec.name, spec.size, RED, Enum.Material.Fabric, accessory)
		panel.CFrame = CFrame.new(0, spec.y, spec.z) * CFrame.Angles(math.rad(spec.tilt), 0, 0)
		weld(handle, panel)
	end

	for _, side in { -1, 1 } do
		local trim = part("GoldEdge", Vector3.new(0.09, 3.35, 0.08), GOLD, Enum.Material.Metal, accessory)
		trim.CFrame = CFrame.new(side * 1.13, -1.68, 0.29) * CFrame.Angles(math.rad(-9), 0, 0)
		weld(handle, trim)

		local clasp = part("ShoulderClasp", Vector3.new(0.28, 0.28, 0.28), GOLD_PALE, Enum.Material.Metal, accessory)
		clasp.Shape = Enum.PartType.Ball
		clasp.CFrame = CFrame.new(side * 0.92, 0.03, -0.02)
		weld(handle, clasp)
	end

	local hem = part("GoldHem", Vector3.new(1.9, 0.1, 0.12), GOLD, Enum.Material.Metal, accessory)
	hem.CFrame = CFrame.new(0, -3.29, 0.56) * CFrame.Angles(math.rad(-11), 0, 0)
	weld(handle, hem)

	tag(accessory)
	return accessory
end

local function buildCrown(): Accessory
	local accessory = Instance.new("Accessory")
	accessory.Name = CROWN_NAME

	local handle = part("Handle", Vector3.new(0.1, 0.1, 0.1), GOLD, Enum.Material.Metal, accessory)
	handle.Transparency = 1
	local attachment = Instance.new("Attachment")
	attachment.Name = "HatAttachment"
	attachment.CFrame = CFrame.new(0, -0.22, 0)
	attachment.Parent = handle

	local rails = {
		{ name = "CrownFront", size = Vector3.new(1.32, 0.22, 0.14), cf = CFrame.new(0, 0, -0.48) },
		{ name = "CrownBack", size = Vector3.new(1.32, 0.22, 0.14), cf = CFrame.new(0, 0, 0.48) },
		{ name = "CrownLeft", size = Vector3.new(0.14, 0.22, 0.96), cf = CFrame.new(-0.59, 0, 0) },
		{ name = "CrownRight", size = Vector3.new(0.14, 0.22, 0.96), cf = CFrame.new(0.59, 0, 0) },
	}
	for _, spec in rails do
		local rail = part(spec.name, spec.size, GOLD, Enum.Material.Metal, accessory)
		rail.CFrame = spec.cf
		weld(handle, rail)
	end

	for index, x in { -0.52, -0.26, 0, 0.26, 0.52 } do
		local height = if index == 3 then 0.95 else if index == 2 or index == 4 then 0.72 else 0.55
		local spike = part("CrownSpike", Vector3.new(0.13, height, 0.13), GOLD_PALE, Enum.Material.Metal, accessory)
		spike.CFrame = CFrame.new(x, 0.18 + height / 2, -0.48)
		weld(handle, spike)

		local jewel = part("CrownJewel", Vector3.new(0.16, 0.16, 0.1), if index == 3 then GEM else RED_DARK, Enum.Material.Neon, accessory)
		jewel.CFrame = CFrame.new(x, 0.27, -0.57)
		weld(handle, jewel)
	end

	tag(accessory)
	return accessory
end

function SupermanGear.clear(character: Model)
	for _, value in character:GetChildren() do
		if value:IsA("Accessory") and CollectionService:HasTag(value, ClassConfig.SUPERMAN_GEAR_TAG) then
			value:Destroy()
		end
	end
end

function SupermanGear.apply(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	SupermanGear.clear(character)
	humanoid:AddAccessory(buildCape())
	humanoid:AddAccessory(buildCrown())
end

return SupermanGear
