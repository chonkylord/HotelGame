--!strict
--[[
	The Hacker's kit: a back-mounted rig and a visor with a code feed running
	across the lens.

	Built out of parts rather than pulled off the catalog, for the reason
	ClassConfig gives at length about the Muscle build — but with one extra of
	its own. The lens has to carry a live SurfaceGui, and no catalog accessory
	will render text that changes at run time. A mesh visor would be a picture of
	code; this is code.

	Both pieces are Accessories, so Roblox's own accessory welding puts them on
	the character and takes them off with it. Nothing here writes
	HumanoidDescription, so the player keeps their own body, clothes, face and
	accessories — the class adds kit, it does not replace the person wearing it.

	Everything is tagged HACKER_GEAR_TAG on the way out, which is how `clear`
	finds it again without having to know how any of this is put together, and
	the lens is tagged separately for the client that animates it.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClassConfig = require(ReplicatedStorage:WaitForChild("ClassDefinitions"))

local HackerGear = {}

local VISOR_NAME = "HackerVisor"
local PACK_NAME = "HackerPack"

local FRAME = Color3.fromRGB(16, 18, 22)
local SHELL = Color3.fromRGB(34, 36, 43)
local STRAP = Color3.fromRGB(22, 24, 29)
local ACCENT = Color3.fromRGB(40, 255, 190)
local AMBER = Color3.fromRGB(255, 176, 64)

-- Three lines is what fits across a visor before the glyphs stop being glyphs.
local LENS_LINES = 3

local function newPart(name: string, size: Vector3, colour: Color3, material: Enum.Material, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = colour
	part.Material = material
	part.Anchored = false
	-- Worn kit must not collide, must not swallow raycasts aimed at the player,
	-- and must not weigh anything: a heavy backpack would change how the
	-- character walks, which is not what anyone is asking for by picking a class.
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = CFrame.new()
	part.Parent = parent
	return part
end

--[[
	Fixes a part to the handle at wherever it currently sits.

	A WeldConstraint captures the offset between the two parts as they stand
	when it is created, so everything is laid out around a handle parked at the
	origin and welded there. Roblox then moves the handle onto the character and
	the rest is carried along.
]]
local function weld(handle: BasePart, part: BasePart)
	local constraint = Instance.new("WeldConstraint")
	constraint.Part0 = handle
	constraint.Part1 = part
	constraint.Parent = part
end

local function tagGear(inst: Instance)
	CollectionService:AddTag(inst, ClassConfig.HACKER_GEAR_TAG)
end

-- The visor ------------------------------------------------------------------

--[[
	The lens is the Handle, so the part carrying the SurfaceGui is the one Roblox
	positions directly — one less weld between the code and the face it is
	supposed to sit on.

	NormalId.Front is a part's -Z face, and -Z on the head is the way the
	character is looking, so the feed faces outward. That is deliberate: this is
	kit other players read off you. The wearer cannot see their own face, and in
	first person Roblox hides worn accessories anyway.
]]
local function buildVisor(): Accessory
	local accessory = Instance.new("Accessory")
	accessory.Name = VISOR_NAME

	local lens = newPart("Handle", Vector3.new(1.66, 0.34, 0.10), ACCENT, Enum.Material.Neon, accessory)
	lens.Transparency = 0.18
	CollectionService:AddTag(lens, ClassConfig.HACKER_LENS_TAG)

	--[[
		Where the visor ends up on the head.

		Roblox lines this attachment up with the one of the same name on the
		Head, so the offset here is what moves the lens off the face: up to eye
		height, and a hair proud of the skin so it does not z-fight with it.
		FaceFrontAttachment sits at the middle of the face, which is why the Y is
		positive rather than zero.
	]]
	local attachment = Instance.new("Attachment")
	attachment.Name = "FaceFrontAttachment"
	attachment.CFrame = CFrame.new(0, -0.16, 0.06)
	attachment.Parent = lens

	local gui = Instance.new("SurfaceGui")
	gui.Name = "Feed"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 160
	-- Unlit and pushed bright, so the feed reads in a dark corridor. This game
	-- is mostly dark corridors.
	gui.LightInfluence = 0
	gui.Brightness = 2.5
	gui.Parent = lens

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = gui

	for i = 1, LENS_LINES do
		local line = Instance.new("TextLabel")
		line.Name = `Line{i}`
		line.LayoutOrder = i
		line.BackgroundTransparency = 1
		line.Size = UDim2.fromScale(1, 1 / LENS_LINES)
		line.Font = Enum.Font.Code
		line.TextScaled = true
		line.TextColor3 = Color3.fromRGB(190, 255, 230)
		line.TextXAlignment = Enum.TextXAlignment.Left
		-- Filled in by HackerVisorClient. Left blank rather than seeded with
		-- placeholder text so a visor whose animator never starts reads as an
		-- unlit lens instead of as frozen code.
		line.Text = ""
		line.Parent = gui
	end

	-- Brow and chin rails, which are what stop the lens reading as a floating
	-- green rectangle.
	for _, spec in
		ipairs({
			{ name = "BrowRail", y = 0.215, height = 0.09 },
			{ name = "ChinRail", y = -0.215, height = 0.07 },
		})
	do
		local rail = newPart("Rail", Vector3.new(1.72, spec.height, 0.13), FRAME, Enum.Material.SmoothPlastic, accessory)
		rail.Name = spec.name
		rail.CFrame = CFrame.new(0, spec.y, 0)
		weld(lens, rail)
	end

	-- Temples, running back along the sides of the head to the ears.
	for _, side in ipairs({ -1, 1 }) do
		local temple =
			newPart("Temple", Vector3.new(0.09, 0.10, 0.62), FRAME, Enum.Material.SmoothPlastic, accessory)
		temple.Name = if side < 0 then "TempleL" else "TempleR"
		temple.CFrame = CFrame.new(0.84 * side, 0.06, 0.34)
		weld(lens, temple)
	end

	-- A single lit stud on the right temple: the thing is powered.
	local pilot = newPart("Pilot", Vector3.new(0.07, 0.07, 0.07), AMBER, Enum.Material.Neon, accessory)
	pilot.CFrame = CFrame.new(0.87, 0.14, 0.12)
	weld(lens, pilot)

	for _, part in accessory:GetDescendants() do
		if part:IsA("BasePart") then
			tagGear(part)
		end
	end
	tagGear(accessory)
	return accessory
end

-- The pack -------------------------------------------------------------------

local function buildPack(): Accessory
	local accessory = Instance.new("Accessory")
	accessory.Name = PACK_NAME

	local shell = newPart("Handle", Vector3.new(1.24, 1.42, 0.62), SHELL, Enum.Material.SmoothPlastic, accessory)

	--[[
		BodyBackAttachment sits on the back face of the torso, and +Z there is
		away from the character's chest, so pushing the handle's own attachment
		to -Z stands the pack off the back rather than sinking it into the spine.

		Measured on a stock R15 rig rather than guessed, because the number that
		matters is not the one you would assume. UpperTorso is 1.00 deep here,
		not the 0.8 an R15 diagram implies, which puts its back face and this
		attachment both at torso-space Z +0.50. The -0.36 below lands the shell
		centre at +0.86, so its front face sits 0.05 proud of the back — a strap's
		thickness of daylight, which is what a worn pack looks like. Pulling it in
		any further does not close a gap, it buries the pack in the spine.
	]]
	local attachment = Instance.new("Attachment")
	attachment.Name = "BodyBackAttachment"
	attachment.CFrame = CFrame.new(0, -0.26, -0.36)
	attachment.Parent = shell

	-- Lid, slightly proud of the shell so the seam catches light.
	local lid = newPart("Lid", Vector3.new(1.28, 0.34, 0.66), STRAP, Enum.Material.SmoothPlastic, accessory)
	lid.CFrame = CFrame.new(0, 0.6, 0)
	weld(shell, lid)

	-- Side pouches.
	for _, side in ipairs({ -1, 1 }) do
		local pouch = newPart("Pouch", Vector3.new(0.22, 0.72, 0.5), STRAP, Enum.Material.SmoothPlastic, accessory)
		pouch.Name = if side < 0 then "PouchL" else "PouchR"
		pouch.CFrame = CFrame.new(0.73 * side, -0.24, 0)
		weld(shell, pouch)
	end

	--[[
		Shoulder straps.

		These run forward over the shoulders and are the piece that sells the
		pack as worn rather than stuck on. They sit outboard of the neck and
		above the shoulder line, tilted forward, so they clear the torso instead
		of cutting through the chest.
	]]
	for _, side in ipairs({ -1, 1 }) do
		local strap = newPart("Strap", Vector3.new(0.18, 0.12, 1.15), STRAP, Enum.Material.SmoothPlastic, accessory)
		strap.Name = if side < 0 then "StrapL" else "StrapR"
		strap.CFrame = CFrame.new(0.42 * side, 0.84, -0.42) * CFrame.Angles(math.rad(-14), 0, 0)
		weld(shell, strap)
	end

	-- The rig itself: a lit panel and a stub aerial, so the pack reads as
	-- equipment rather than luggage.
	local panel = newPart("Panel", Vector3.new(0.52, 0.20, 0.06), ACCENT, Enum.Material.Neon, accessory)
	panel.CFrame = CFrame.new(-0.28, 0.12, 0.33)
	weld(shell, panel)

	local aerial = newPart("Aerial", Vector3.new(0.06, 0.86, 0.06), FRAME, Enum.Material.SmoothPlastic, accessory)
	aerial.CFrame = CFrame.new(0.46, 1.14, 0.16) * CFrame.Angles(math.rad(9), 0, math.rad(7))
	weld(shell, aerial)

	local tip = newPart("AerialTip", Vector3.new(0.09, 0.09, 0.09), AMBER, Enum.Material.Neon, accessory)
	tip.CFrame = CFrame.new(0.52, 1.57, 0.2)
	weld(shell, tip)

	for _, part in accessory:GetDescendants() do
		if part:IsA("BasePart") then
			tagGear(part)
		end
	end
	tagGear(accessory)
	return accessory
end

-- Fitting and stripping ------------------------------------------------------

--[[
	Takes any kit off the character.

	Driven off the tag rather than off the names, so a piece that gets renamed or
	re-parented later still comes off. Called before fitting as well as on a
	class change, which is what stops a player who re-picks Hacker from ending up
	wearing two of everything.
]]
function HackerGear.clear(character: Model)
	for _, inst in character:GetChildren() do
		if inst:IsA("Accessory") and CollectionService:HasTag(inst, ClassConfig.HACKER_GEAR_TAG) then
			inst:Destroy()
		end
	end
end

function HackerGear.apply(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	HackerGear.clear(character)

	-- AddAccessory is what performs the weld, matching the attachment names on
	-- the handles against the ones already on the head and torso.
	humanoid:AddAccessory(buildVisor())
	humanoid:AddAccessory(buildPack())
end

return HackerGear
