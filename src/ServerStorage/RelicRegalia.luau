--!strict
--[[
	What a claimed relic looks like on the person who claimed it.

	Two of the three treasury exhibits are objects a body can wear, so once
	ClueService has written the entitlement onto the Player this hangs the object
	itself off their character:

	  * the Master Cipher is a laptop, carried open on the left hand;
	  * the Ironhand is an iron gauntlet, worn over the hand.

	Neither piece does anything. The abilities live exactly where they lived
	before -- HotelDoorService reads MuscleRelic and HackerRelic off the Player
	and neither one has heard of this file. That separation is the point: the
	regalia can be restyled, rescaled, reposed or deleted outright without a
	door behaving differently, and a relic claimed on a server where the template
	is missing still grants what it always granted.

	One template serves two jobs. The models in ServerStorage.RelicRegaliaModels are
	built with every part parented UNDER a root part named Stone, which is what
	lets the same model stand on a treasury plinth -- ClueService's setPlinthShown
	hides a stone and its descendants, so a sibling part would stay lit on a
	claimed plinth -- and be welded to a hand here.

	The pose is data, not code. HoldOffset, HoldAngles, HoldScale and HoldAnchor
	are attributes on the template model, so getting the laptop sitting right on
	the hand is a property edit in Studio rather than a change to this file.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ClueConfig = require(ReplicatedStorage:WaitForChild("ClueConfig"))

local RelicRegalia = {}

RelicRegalia.FolderName = "RelicRegaliaModels"
RelicRegalia.RootName = "Stone"

-- Everything this file welds onto a character wears this, so a stale piece is
-- one GetTagged away rather than a name search through the character.
RelicRegalia.Tag = "RelicRegalia"

export type Spec = {
	id: string,
	templateName: string,
	attribute: string,
	-- Which hand it hangs off. Both are Left on purpose: Roblox welds every Tool
	-- to the right hand, and Muscle spends the round holding a mallet and a sack
	-- there. A gauntlet on that hand is a gauntlet inside a mallet handle.
	side: "Left" | "Right",
	-- Defaults for the four tunables. The template's attributes win when set;
	-- these are what a template that has never been touched in Studio uses.
	offset: Vector3,
	angles: Vector3,
	scale: number,
}

--[[
	The two wearable relics.

	The Sunstone is deliberately absent. It is not an object you keep -- claiming
	it hands over the Solar Lance, which is a Tool and already appears in the
	hand the ordinary way.
]]
local SPECS: { Spec } = {
	{
		id = "MasterCipher",
		templateName = "MasterCipher",
		attribute = ClueConfig.HackerRelicAttribute,
		side = "Left",
		-- Held out in front of the palm, screen turned back towards the face.
		-- The 180 degree yaw is doing the aiming: the laptop model's own -Z is
		-- the side a person sits on, so pointing its +Z down the character's
		-- forward axis is what puts the screen in front of their eyes.
		--
		-- The 45 degree pitch is not a guess. A hanging left hand sits about
		-- 2.9 studs below the head, so a laptop held flat on it points its
		-- screen at the floor in front of the player rather than at their face.
		-- Solved against a rest-pose R15 by sweeping pitch against the angle
		-- between the screen's normal and the head: flat scores 0.37, this
		-- scores 0.91, and steeper than this only buys hundredths while
		-- dropping the whole machine down towards the knee.
		offset = Vector3.new(0, 0.45, -0.50),
		angles = Vector3.new(-45, 180, 0),
		scale = 0.85,
	},
	{
		id = "Ironhand",
		templateName = "Ironhand",
		attribute = ClueConfig.MuscleRelicAttribute,
		side = "Left",
		-- Worn over the hand rather than held in front of it, so it sits on the
		-- palm centre. The X flip points the fingers down the arm: the mesh is
		-- generated standing upright, which is fingers-up until it is turned.
		offset = Vector3.new(0, 0.15, 0),
		angles = Vector3.new(180, 0, 0),
		scale = 1.35,
	},
}

RelicRegalia.SPECS = SPECS

-- Attribute names on the template model. Named on the model rather than on the
-- root part because scale and anchor are properties of the whole piece.
local OFFSET_ATTRIBUTE = "HoldOffset"
local ANGLES_ATTRIBUTE = "HoldAngles"
local SCALE_ATTRIBUTE = "HoldScale"
local ANCHOR_ATTRIBUTE = "HoldAnchor"

-- Limb names, by rig. Resolved by trying both rather than by reading
-- Humanoid.RigType alone: an NPC rig or an old saved character can report one
-- and be built like the other, and a missing limb has to degrade to "no
-- regalia" rather than to an error in the middle of a claim.
local HAND_NAMES: { [string]: { string } } = {
	Left = { "LeftHand", "Left Arm" },
	Right = { "RightHand", "Right Arm" },
}
local TORSO_NAMES = { "UpperTorso", "Torso", "HumanoidRootPart" }

local function firstPart(character: Model, names: { string }): BasePart?
	for _, name in names do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

local function vectorAttribute(model: Model, name: string, fallback: Vector3): Vector3
	local value = model:GetAttribute(name)
	return if typeof(value) == "Vector3" then value else fallback
end

local function numberAttribute(model: Model, name: string, fallback: number): number
	local value = model:GetAttribute(name)
	return if typeof(value) == "number" and value > 0 then value else fallback
end

function RelicRegalia.templateFor(spec: Spec): Model?
	local home = ServerStorage:FindFirstChild(RelicRegalia.FolderName)
	local template = if home then home:FindFirstChild(spec.templateName) else nil
	if not template or not template:IsA("Model") then
		return nil
	end
	local root = template:FindFirstChild(RelicRegalia.RootName)
	return if root and root:IsA("BasePart") then template else nil
end

function RelicRegalia.wornName(spec: Spec): string
	return spec.id .. "Regalia"
end

--[[
	Take a piece off a character.

	Swept by tag as well as by name so a piece left behind by an older build of
	this file -- or one renamed by hand in Studio -- still goes when the relic
	does.
]]
function RelicRegalia.detach(character: Model, spec: Spec)
	local wanted = RelicRegalia.wornName(spec)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("Model") and descendant.Name == wanted then
			descendant:Destroy()
		end
	end
end

--[[
	Weld one piece onto a character.

	The offset is built in the limb's OWN space rather than from a world CFrame
	measured at the moment of attachment. That distinction is load-bearing: a
	world measurement bakes in whatever the character's animation happened to be
	doing on that frame, so claiming a relic mid-stride would leave the laptop
	permanently held at a running arm's angle.

	Y is measured up from the bottom face of the limb rather than from its
	centre, which is what lets one number cover both rigs: the palm is at the
	bottom of a 0.3-stud R15 hand and the bottom of a 2-stud R6 arm, and
	-Size.Y/2 finds it either way.
]]
function RelicRegalia.attach(character: Model, spec: Spec): boolean
	local template = RelicRegalia.templateFor(spec)
	if not template then
		return false
	end

	local anchorPart: BasePart?
	if template:GetAttribute(ANCHOR_ATTRIBUTE) == "Torso" then
		anchorPart = firstPart(character, TORSO_NAMES)
	else
		anchorPart = firstPart(character, HAND_NAMES[spec.side])
	end
	if not anchorPart then
		return false
	end

	RelicRegalia.detach(character, spec)

	local model = template:Clone()
	model.Name = RelicRegalia.wornName(spec)
	model:ScaleTo(numberAttribute(template, SCALE_ATTRIBUTE, spec.scale))

	local root = model:FindFirstChild(RelicRegalia.RootName)
	if not root or not root:IsA("BasePart") then
		model:Destroy()
		return false
	end

	-- CanQuery off on every piece, not just for tidiness: a Hacker holds this
	-- directly in front of their own chest, and a queryable laptop is a laptop
	-- the sack's aim ray and the crosshair both hit before the world does.
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
			if descendant ~= root then
				local rigid = Instance.new("WeldConstraint")
				rigid.Part0 = root
				rigid.Part1 = descendant
				rigid.Parent = descendant
			end
		end
	end

	local offset = vectorAttribute(model, OFFSET_ATTRIBUTE, spec.offset)
	local angles = vectorAttribute(model, ANGLES_ATTRIBUTE, spec.angles)
	local pose = CFrame.new(offset.X, -anchorPart.Size.Y / 2 + offset.Y, offset.Z)
		* CFrame.Angles(math.rad(angles.X), math.rad(angles.Y), math.rad(angles.Z))

	CollectionService:AddTag(model, RelicRegalia.Tag)
	model.Parent = character

	local weld = Instance.new("Weld")
	weld.Name = "RegaliaWeld"
	weld.Part0 = anchorPart
	weld.Part1 = root
	weld.C0 = pose
	weld.Parent = root

	return true
end

return RelicRegalia
