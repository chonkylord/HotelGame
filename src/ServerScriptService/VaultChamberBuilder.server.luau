--!strict
--[[
	Builds the isolated vault expedition and the two pieces of hotel access that
	make it playable: a two-way service lift behind a Muscle-gated vestibule and
	the final coded lobby exit. Geometry generated here is replaceable by marker
	attribute; authored doors, anchors, and clue exits are never deleted.

	The chamber is deliberately larger along +Z than the original design sketch.
	BankVaultBuilder's treasury reaches 42 studs behind VaultAnchor, so a wall at
	world Z=35 would cut through it. The sealed north wall sits at Z=65 instead,
	leaving real inspection space behind the generated treasury wall at Z≈57.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ClueConfig = require(ReplicatedStorage:WaitForChild("ClueConfig"))

--[[
	Stand down when the place itself owns the chamber.

	Same story as BankVaultBuilder: the chamber only ever existed for the life of
	a server, so none of it could be selected, moved or restyled in Studio. It is
	now baked into the place as saved instances, and this script is the fallback
	for a place that has none rather than the thing that makes it.

	The `VaultChamber_Procedural` rename further down only avoids a name
	collision; it still leaves two overlapping 90x110 concrete rooms in the
	world, plus a second pair of elevator cabs registering against the same
	VaultLift/SuiteVaultLift ids, which is the kind of duplicate ElevatorService
	resolves by whichever tag fired last.

	GeneratedVaultChamber tells the two apart: a baked chamber has had it
	stripped, anything this script built still carries it. Returning here rather
	than lower down is load-bearing for three separate reasons:
	  * the sweep below destroys every Workspace child carrying that marker (or
	    GeneratedClueExitDoor) -- a stood-down builder must not delete;
	  * the anchor branch below CREATES Workspace.VaultAnchor when it is absent,
	    and the baked vault ships with a hand-placed one that must be left
	    exactly where the author put it;
	  * both elevator cabs are clones of an authored template, so building them
	    a second time also re-tags and re-registers the originals' partners.
]]
local savedChamber = Workspace:FindFirstChild("VaultChamber")
if
	savedChamber
	and savedChamber:IsA("Model")
	and savedChamber:GetAttribute(ClueConfig.GeneratedVaultChamberAttribute) ~= true
then
	print(
		"[VaultChamberBuilder] Workspace.VaultChamber is authored in the place (no GeneratedVaultChamber marker) — builder standing down; no geometry, no sweep, anchor left alone"
	)
	return
end

type PartStyle = {
	color: Color3?,
	material: Enum.Material?,
	shape: Enum.PartType?,
	reflectance: number?,
	transparency: number?,
	castShadow: boolean?,
	canCollide: boolean?,
}

local STEEL_DARK = Color3.fromRGB(31, 38, 48)
local STEEL_MID = Color3.fromRGB(72, 84, 99)
local STEEL_LIGHT = Color3.fromRGB(143, 159, 175)
local STEEL_EDGE = Color3.fromRGB(189, 202, 212)
local GUNMETAL = Color3.fromRGB(22, 27, 34)
local CONCRETE = Color3.fromRGB(54, 58, 62)
local GASKET = Color3.fromRGB(10, 14, 18)
local AMBER = Color3.fromRGB(255, 183, 62)
local GREEN = Color3.fromRGB(78, 255, 157)
local BLOOD = Color3.fromRGB(111, 38, 32)
local WOOD_DARK = Color3.fromRGB(59, 39, 28)

-- Only used for a place that has neither an authored anchor nor an authored
-- vault. Kept in step with RescueWorldBuilder's identical fallback: if these two
-- ever disagree, a fresh place generates its vault in one spot and its rescue
-- drop zones in another. Y is the chamber's floor level, so it reads as the
-- surface height it now sits at rather than the old sealed sublevel.
local VAULT_ANCHOR_CFRAME = CFrame.new(960, 19, 15)
local VAULT_LIFT_ID = "VaultLift"
-- Named for where it is, not what it serves: the hotel end of this pair sits in
-- the Presidential Suite, at the end of the Lobby -> Rooms -> Amenities -> Suite
-- progression rather than off the amenities service corridor it used to.
local SUITE_LIFT_ID = "SuiteVaultLift"
local PENDING_EXIT_CODE = "--------"

local function makePart(parent: Instance, name: string, size: Vector3, cframe: CFrame, style: PartStyle?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = if style and style.canCollide ~= nil then style.canCollide else true
	part.CanQuery = true
	part.CanTouch = false
	part.Size = size
	part.CFrame = cframe
	part.Color = if style and style.color then style.color else STEEL_MID
	part.Material = if style and style.material then style.material else Enum.Material.Metal
	part.Reflectance = if style and style.reflectance then style.reflectance else 0
	part.Transparency = if style and style.transparency then style.transparency else 0
	part.CastShadow = if style and style.castShadow ~= nil then style.castShadow else true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if style and style.shape then
		part.Shape = style.shape
	end
	part.Parent = parent
	return part
end

local function cylinder(
	parent: Instance,
	name: string,
	diameter: number,
	depth: number,
	cframe: CFrame,
	style: PartStyle?
): Part
	return makePart(parent, name, Vector3.new(depth, diameter, diameter), cframe * CFrame.Angles(0, math.rad(90), 0), {
		color = if style and style.color then style.color else STEEL_MID,
		material = if style and style.material then style.material else Enum.Material.Metal,
		reflectance = if style and style.reflectance then style.reflectance else 0,
		transparency = if style and style.transparency then style.transparency else 0,
		castShadow = if style and style.castShadow ~= nil then style.castShadow else true,
		canCollide = if style and style.canCollide ~= nil then style.canCollide else true,
		shape = Enum.PartType.Cylinder,
	})
end

local function addLabel(
	part: BasePart,
	face: Enum.NormalId,
	text: string,
	color: Color3,
	font: Enum.Font?,
	canvasSize: Vector2?
): TextLabel
	local surface = Instance.new("SurfaceGui")
	surface.Name = "FaceLabel"
	surface.Face = face
	surface.CanvasSize = canvasSize or Vector2.new(512, 256)
	surface.LightInfluence = 0
	surface.PixelsPerStud = 100
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.ZOffset = 1
	surface.Parent = part

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = font or Enum.Font.GothamBold
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.72
	label.Parent = surface
	return label
end

local function weldTo(hinge: BasePart, part: BasePart)
	part.Anchored = false
	part.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Name = "DoorWeld"
	weld.Part0 = hinge
	weld.Part1 = part
	weld.Parent = part
end

-- Generated-root lifecycle ---------------------------------------------------

for _, child in Workspace:GetChildren() do
	if
		child:GetAttribute(ClueConfig.GeneratedVaultChamberAttribute) == true
		or child:GetAttribute(ClueConfig.GeneratedExitDoorAttribute) == true
	then
		child:Destroy()
	end
end

local anchor: BasePart
local existingAnchor = Workspace:FindFirstChild("VaultAnchor")
if existingAnchor then
	if not existingAnchor:IsA("BasePart") then
		warn("[VaultChamberBuilder] Workspace.VaultAnchor exists but is not a BasePart; cannot build safely")
		return
	end
	anchor = existingAnchor
else
	local created = makePart(Workspace, "VaultAnchor", Vector3.new(1, 0.2, 1), VAULT_ANCHOR_CFRAME, {
		transparency = 1,
		castShadow = false,
		canCollide = false,
	})
	created.CanQuery = false
	created:SetAttribute(ClueConfig.GeneratedVaultChamberAttribute, true)
	anchor = created
end

local function vaultAt(x: number, y: number, z: number): CFrame
	return anchor.CFrame * CFrame.new(x, y, z)
end

-- Elevator cab ---------------------------------------------------------------

--[[
	Both vault lifts are clones of the hotel's own elevator, not built from boxes.

	This used to assemble a cab out of six slabs, two door panels and a button
	part. It satisfied ElevatorService's contract -- ButtonDoor.{Button, Door1,
	Door2} plus a tagged Arrive marker -- so it worked, but it read as a concrete
	crate next to the authored cabs, which have unioned doors, a moulded frame,
	open/close sounds and interior lights.

	Workspace.Elevators.SuiteElevator1 is the Amenities end of the existing
	Amenities <-> Suite pair and already carries everything required, including
	the ElevatorCab and ElevatorArrive tags (tags clone with the instance). So
	the cab is now that model, copied and moved, and the vault gets the same
	elevator as the rest of the hotel for free -- including any future restyle of
	the original.

	Two things the template pins down, measured rather than assumed:
	  * its pivot sits PIVOT_TO_FLOOR studs above the cab floor, so callers can
	    keep passing the floor position they want the cab to stand on;
	  * at identity rotation its doors face -Z, which is also its pivot
	    LookVector, so aiming the pivot along `doorsFace` aims the doors.

	The template is left untouched -- only clones are moved.
]]
local CAB_TEMPLATE_PATH = { "Elevators", "SuiteElevator1" }

local function findCabTemplate(): Model?
	local node: Instance? = Workspace
	for _, segment in CAB_TEMPLATE_PATH do
		node = node and node:FindFirstChild(segment)
	end
	return if node and node:IsA("Model") then node else nil
end

-- Distance from the template's pivot down to the underside of its cab floor.
local function pivotToFloor(template: Model): number
	local lowest = math.huge
	for _, descendant in template:GetDescendants() do
		if descendant:IsA("BasePart") then
			lowest = math.min(lowest, descendant.Position.Y - descendant.Size.Y / 2)
		end
	end
	if lowest == math.huge then
		return 0
	end
	return template:GetPivot().Position.Y - lowest
end

local function makeElevatorCab(
	parent: Instance,
	id: string,
	partnerId: string,
	floorPosition: Vector3,
	doorsFace: Vector3
): Model?
	local template = findCabTemplate()
	if not template then
		warn(`[VaultChamberBuilder] {table.concat(CAB_TEMPLATE_PATH, ".")} is missing; {id} was not built`)
		return nil
	end

	local cab = template:Clone()

	--[[
		Untag first, position, then tag last. This ordering is load-bearing.

		ElevatorService registers a cab the moment it sees the ElevatorCab tag,
		and register() captures `shut1 = door1.CFrame` right then -- that pose is
		the closed position every later tween animates back to. A clone carries
		the template's tags with it, so the cab was being registered while still
		sitting on top of the original 300 studs away, and its doors would have
		tweened toward a closed pose out in the amenities floor.

		Dropping the tag and re-adding it after the move forces a teardown and a
		fresh register against the final pose, whichever moment the engine
		chooses to fire the added-signal on.
	]]
	CollectionService:RemoveTag(cab, ClueConfig.ElevatorCabTag)
	cab.Name = id
	cab:SetAttribute(ClueConfig.CabIdAttribute, id)
	cab:SetAttribute(ClueConfig.PartnerAttribute, partnerId)

	local stand = floorPosition + Vector3.new(0, pivotToFloor(template), 0)
	cab:PivotTo(CFrame.lookAt(stand, stand + doorsFace.Unit))
	cab.Parent = parent

	-- The template is authored, so a future edit there could drop the arrive tag
	-- without anyone noticing here. Re-assert it rather than inherit silently.
	for _, descendant in cab:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name == "Arrive" then
			CollectionService:AddTag(descendant, ClueConfig.ElevatorArriveTag)
		end
	end
	CollectionService:AddTag(cab, ClueConfig.ElevatorCabTag)

	return cab
end

-- Hotel-door rig -------------------------------------------------------------

local function makeKeypad(door: Model, floorCFrame: CFrame)
	local keypad = Instance.new("Model")
	keypad.Name = "Keypad"
	keypad.Parent = door

	local housing =
		makePart(keypad, "Housing", Vector3.new(3.35, 7.1, 0.7), floorCFrame * CFrame.new(-6.45, 4.65, -0.5), {
			color = GASKET,
			material = Enum.Material.DiamondPlate,
		})
	local display =
		makePart(keypad, "Display", Vector3.new(2.55, 0.82, 0.2), floorCFrame * CFrame.new(-6.35, 7.3, -0.96), {
			color = Color3.fromRGB(24, 64, 44),
			material = Enum.Material.Neon,
			castShadow = false,
			canCollide = false,
		})
	addLabel(display, Enum.NormalId.Front, "ENTER CODE", GREEN, Enum.Font.Code)
	local led = makePart(keypad, "LED", Vector3.new(0.38, 0.38, 0.18), floorCFrame * CFrame.new(-7.65, 7.3, -0.98), {
		color = Color3.fromRGB(255, 60, 60),
		material = Enum.Material.Neon,
		castShadow = false,
		canCollide = false,
	})
	led.CanQuery = false

	local buttons = Instance.new("Folder")
	buttons.Name = "Buttons"
	buttons.Parent = keypad
	local rows = {
		{ "1", "2", "3" },
		{ "4", "5", "6" },
		{ "7", "8", "9" },
		{ "C", "0", "E" },
	}
	for rowIndex, row in rows do
		for columnIndex, key in row do
			local x = -7.18 + (columnIndex - 1) * 0.83
			local y = 6.15 - (rowIndex - 1) * 0.9
			local keyPart =
				makePart(buttons, `B{key}`, Vector3.new(0.68, 0.62, 0.24), floorCFrame * CFrame.new(x, y, -0.94), {
					color = STEEL_LIGHT,
					material = Enum.Material.Metal,
					canCollide = false,
				})
			addLabel(keyPart, Enum.NormalId.Front, key, GUNMETAL, Enum.Font.GothamBold)
			local click = Instance.new("ClickDetector")
			click.MaxActivationDistance = 12
			click.Parent = keyPart
		end
	end
	keypad.PrimaryPart = housing
end

local function makeHotelDoor(
	parent: Instance,
	name: string,
	floorCFrame: CFrame,
	roomLabel: string,
	state: string,
	exitPrompt: boolean,
	code: string,
	doorColor: Color3
): Model
	local door = Instance.new("Model")
	door.Name = name
	door:SetAttribute(ClueConfig.RoomLabelAttribute, roomLabel)
	door:SetAttribute(ClueConfig.DoorStateAttribute, state)
	door:SetAttribute(ClueConfig.ExitPromptAttribute, exitPrompt)
	door:SetAttribute(ClueConfig.DoorCodeAttribute, code)

	makePart(door, "FrameLeft", Vector3.new(0.95, 10.25, 1.05), floorCFrame * CFrame.new(-4.75, 5.12, 0), {
		color = STEEL_DARK,
		material = Enum.Material.DiamondPlate,
	})
	makePart(door, "FrameRight", Vector3.new(0.95, 10.25, 1.05), floorCFrame * CFrame.new(4.75, 5.12, 0), {
		color = STEEL_DARK,
		material = Enum.Material.DiamondPlate,
	})
	makePart(door, "FrameTop", Vector3.new(10.45, 0.95, 1.05), floorCFrame * CFrame.new(0, 9.78, 0), {
		color = STEEL_DARK,
		material = Enum.Material.DiamondPlate,
	})
	makePart(door, "Threshold", Vector3.new(10.45, 0.24, 1.3), floorCFrame * CFrame.new(0, 0.12, 0), {
		color = STEEL_EDGE,
		material = Enum.Material.DiamondPlate,
	})

	local leaf = Instance.new("Model")
	leaf.Name = "Leaf"
	leaf.Parent = door
	local hinge = makePart(leaf, "Hinge", Vector3.new(0.24, 9.15, 0.24), floorCFrame * CFrame.new(4.18, 4.68, 0), {
		transparency = 1,
		castShadow = false,
		canCollide = false,
	})
	hinge.CanQuery = false

	local core = makePart(leaf, "Core", Vector3.new(8.4, 9.15, 0.58), floorCFrame * CFrame.new(0, 4.68, 0), {
		color = doorColor,
		material = Enum.Material.WoodPlanks,
	})
	weldTo(hinge, core)
	for index, y in { 1.45, 4.68, 7.9 } do
		local band =
			makePart(leaf, `Band_{index}`, Vector3.new(7.75, 0.35, 0.16), floorCFrame * CFrame.new(0, y, -0.38), {
				color = STEEL_DARK,
				material = Enum.Material.Metal,
				canCollide = false,
			})
		weldTo(hinge, band)
	end
	local handle = cylinder(leaf, "DoorHandle", 0.62, 0.7, floorCFrame * CFrame.new(-3.12, 4.25, -0.62), {
		color = AMBER,
		material = Enum.Material.Metal,
		canCollide = false,
	})
	weldTo(hinge, handle)

	local exitButton =
		makePart(door, "ExitButton", Vector3.new(1.8, 1.05, 0.32), floorCFrame * CFrame.new(-5.8, 4.2, 0.72), {
			color = AMBER,
			material = Enum.Material.Metal,
			canCollide = false,
		})
	addLabel(exitButton, Enum.NormalId.Back, "EXIT", GUNMETAL, Enum.Font.GothamBold)

	if state == "Jammed" then
		local jam = Instance.new("Model")
		jam.Name = "Jam"
		jam.Parent = door
		makePart(
			jam,
			"Brace",
			Vector3.new(6.5, 0.42, 0.5),
			floorCFrame * CFrame.new(0, 2.15, -0.62) * CFrame.Angles(0, 0, math.rad(17)),
			{
				color = WOOD_DARK,
				material = Enum.Material.WoodPlanks,
			}
		)
		makePart(
			jam,
			"Chock",
			Vector3.new(0.9, 0.68, 1.15),
			floorCFrame * CFrame.new(-3.55, 0.34, -0.18) * CFrame.Angles(0, math.rad(-9), 0),
			{
				color = WOOD_DARK,
				material = Enum.Material.WoodPlanks,
			}
		)
	else
		makeKeypad(door, floorCFrame)
	end

	door.PrimaryPart = hinge
	door.Parent = parent
	CollectionService:AddTag(door, ClueConfig.HotelDoorTag)
	return door
end

-- Vault sublevel -------------------------------------------------------------

local chamber = Instance.new("Model")
chamber.Name = if Workspace:FindFirstChild("VaultChamber") then "VaultChamber_Procedural" else "VaultChamber"
chamber:SetAttribute(ClueConfig.GeneratedVaultChamberAttribute, true)
chamber.Parent = Workspace

-- Floor/ceiling footprint: local X -45..45 and local Z -60..50, which is
-- world X 915..1005 and Z -45..65 at the default identity anchor.
makePart(chamber, "VaultFloor", Vector3.new(90, 2, 110), vaultAt(0, -1, -5), {
	color = CONCRETE,
	material = Enum.Material.Concrete,
})
makePart(chamber, "VaultCeiling", Vector3.new(90, 2, 110), vaultAt(0, 33, -5), {
	color = CONCRETE,
	material = Enum.Material.Concrete,
})
makePart(chamber, "VaultWall_W", Vector3.new(2, 32, 110), vaultAt(-44, 16, -5), {
	color = CONCRETE,
	material = Enum.Material.Concrete,
})
makePart(chamber, "VaultWall_E", Vector3.new(2, 32, 110), vaultAt(44, 16, -5), {
	color = CONCRETE,
	material = Enum.Material.Concrete,
})
makePart(chamber, "VaultWall_S", Vector3.new(90, 32, 2), vaultAt(0, 16, -59), {
	color = CONCRETE,
	material = Enum.Material.Concrete,
})
makePart(chamber, "VaultWall_N", Vector3.new(90, 32, 2), vaultAt(0, 16, 49), {
	color = CONCRETE,
	material = Enum.Material.Concrete,
})

--[[
	The wall the vault door is set into.

	Without this the vault was a free-standing façade parked in the middle of a
	90-stud-wide room: BankVaultBuilder's shell spans world X 939..981, the
	chamber interior spans X 917..1003, and the ~22 studs left open down each
	side were simply walkable. You could stroll past the door into the treasury
	and help yourself, which makes the code, the keypad and the entire five-node
	clue hunt leading to them decorative.

	A partition on each flank turns the façade into a doorway. The panels stop
	where the shell begins and are run 2 studs into the side walls so the
	junction cannot show a hairline seam, and the header closes the 3-odd studs
	between the top of the shell and the ceiling — unreachable, but "sealed"
	should mean sealed rather than "too high to bother with".

	These are deliberately keyed to BankVaultBuilder's real extents. If that
	façade is ever resized, re-measure it and move these with it.
]]
local SHELL_HALF_WIDTH = 20.9 -- BankVault spans 41.8 studs across, centred on the anchor
local INTERIOR_HALF_WIDTH = 43 -- inner faces of VaultWall_W/E
local PARTITION_WIDTH = (INTERIOR_HALF_WIDTH + 2) - SHELL_HALF_WIDTH
local PARTITION_CENTRE = SHELL_HALF_WIDTH + PARTITION_WIDTH / 2

for _, side in { -1, 1 } do
	makePart(
		chamber,
		if side < 0 then "VaultPartition_W" else "VaultPartition_E",
		Vector3.new(PARTITION_WIDTH, 32, 2),
		vaultAt(side * PARTITION_CENTRE, 16, 1),
		{ color = CONCRETE, material = Enum.Material.Concrete }
	)
end

-- Shell top sits at local Y 28.8; the ceiling starts at 32.
makePart(chamber, "VaultPartition_Header", Vector3.new(SHELL_HALF_WIDTH * 2, 4, 2), vaultAt(0, 30.6, 1), {
	color = CONCRETE,
	material = Enum.Material.Concrete,
})

makePart(chamber, "ApproachRunner", Vector3.new(8, 0.12, 43), vaultAt(0, 0.07, -31), {
	color = STEEL_DARK,
	material = Enum.Material.DiamondPlate,
	reflectance = 0.08,
})
for index, z in { -46, -28, -10 } do
	local fixture = makePart(chamber, `SecurityLamp_{index}`, Vector3.new(8, 0.18, 1.1), vaultAt(0, 31.85, z), {
		color = AMBER,
		material = Enum.Material.Neon,
		castShadow = false,
		canCollide = false,
	})
	local light = Instance.new("PointLight")
	light.Name = "SublevelGlow"
	light.Color = Color3.fromRGB(255, 190, 98)
	light.Brightness = 0.72
	light.Range = 19
	light.Shadows = true
	light.Parent = fixture

	makePart(chamber, `CeilingRib_{index}`, Vector3.new(84, 0.5, 0.7), vaultAt(0, 31.55, z), {
		color = STEEL_DARK,
		material = Enum.Material.DiamondPlate,
	})
end

local warningPosition = vaultAt(0, 12, -47.8).Position
local warningPlate = makePart(
	chamber,
	"SublevelWarning",
	Vector3.new(13, 2.4, 0.14),
	CFrame.lookAt(warningPosition, warningPosition - anchor.CFrame.LookVector),
	{
		color = STEEL_EDGE,
		material = Enum.Material.Metal,
		canCollide = false,
	}
)
addLabel(warningPlate, Enum.NormalId.Front, "AUTHORIZED PERSONNEL  ·  SUBLEVEL", BLOOD, Enum.Font.GothamBold)

-- Local z -51 puts the cab's back flush with VaultWall_S's inner face at world
-- Z -43: the authored cab reaches 7 studs behind its pivot and 5.45 in front,
-- where the old box reached 5 each way, so this sits 2 studs further in.
makeElevatorCab(chamber, VAULT_LIFT_ID, SUITE_LIFT_ID, vaultAt(0, 0, -51).Position, -anchor.CFrame.LookVector)

-- Suite vault lift -----------------------------------------------------------

--[[
	The hotel end of the vault lift lives in the Presidential Suite.

	It was previously a service vestibule grafted onto the back of the amenities
	storage room, and that had two problems. The small one is that it was
	invasive: it suppressed the storage room's authored rear wall, rebuilt the
	partition around a new opening and pivoted StorageShelvesRear out of the way
	to make room. The large one is that it did not work -- pathfinding could not
	reach that vestibule from anywhere in the hotel, so the only route to the
	vault was sealed off.

	The intended progression is Lobby -> Rooms -> (stairs) -> Amenities ->
	Suite -> Vault, which means the lift belongs at the far end of that chain,
	not hanging off a service corridor two floors below it. Putting it in the
	Presidential Suite also reads: it is the suite nobody can afford, and the
	riddle set already points at it as the one Midnight and Garnet bow to.

	The spot was measured, not guessed. (558, -56) stands on
	PresidentialSuite_Inset at Y 33.75 with 14.5 studs of clear wall to the west,
	15.6 to the east and open room to the north, so a 10 x 12.44 cab facing +Z
	sits clear of the walls with its back 3.6 studs off the nearest furniture.
]]
local suiteLift = Instance.new("Model")
suiteLift.Name = "VaultSuiteLift"
suiteLift:SetAttribute(ClueConfig.GeneratedVaultChamberAttribute, true)
suiteLift.Parent = Workspace

makeElevatorCab(suiteLift, SUITE_LIFT_ID, VAULT_LIFT_ID, Vector3.new(558, 33.75, -56), Vector3.new(0, 0, 1))

-- Lobby escape door ----------------------------------------------------------

local authoredExitExists = false
for _, tagged in CollectionService:GetTagged(ClueConfig.ExitDoorTag) do
	if tagged:IsA("Model") and tagged:IsDescendantOf(Workspace) then
		authoredExitExists = true
		break
	end
end

if not authoredExitExists then
	-- The authored entrance leaf sits against the lobby's south wall at Z=66.8.
	-- This inner security leaf creates a shallow airlock in front of it; crossing
	-- ExitTrigger is enough for ClueService to award the win without carving the
	-- place's single monolithic wall Part.
	local exitFrame = CFrame.lookAt(Vector3.new(-60.07, 18, 70.5), Vector3.new(-60.07, 18, 71.5))
	local exitDoor =
		makeHotelDoor(Workspace, "ClueExitDoor", exitFrame, "Hotel Exit", "Normal", false, PENDING_EXIT_CODE, BLOOD)
	exitDoor:SetAttribute(ClueConfig.GeneratedExitDoorAttribute, true)

	local trigger = makePart(exitDoor, "ExitTrigger", Vector3.new(8.2, 6.5, 1), exitFrame * CFrame.new(0, 3.25, 2.05), {
		transparency = 1,
		castShadow = false,
		canCollide = false,
	})
	trigger.CanQuery = false
	trigger.CanTouch = true
	makePart(exitDoor, "ExitAirlockFloor", Vector3.new(10.4, 0.22, 3.8), exitFrame * CFrame.new(0, 0.11, 1.7), {
		color = STEEL_DARK,
		material = Enum.Material.DiamondPlate,
	})
	CollectionService:AddTag(exitDoor, ClueConfig.ExitDoorTag)
end

print(
	"[VaultChamberBuilder] ready — sealed vault Z -45..65, SuiteVaultLift (Presidential Suite) <-> VaultLift, lobby exit rigged"
)
