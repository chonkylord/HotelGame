--!strict

--[[
	Builds a premium bank-vault façade when the server starts.

	Place a Part named "VaultAnchor" in Workspace to choose the centre and facing
	of the vault. Without one, the vault is centred at the world origin and faces
	towards negative Z. The builder only replaces models it previously generated.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ClueConfig = require(ReplicatedStorage:WaitForChild("ClueConfig"))

type PartStyle = {
	color: Color3?,
	material: Enum.Material?,
	shape: Enum.PartType?,
	reflectance: number?,
	transparency: number?,
	castShadow: boolean?,
}

local STEEL_DARK = Color3.fromRGB(31, 38, 48)
local STEEL_MID = Color3.fromRGB(72, 84, 99)
local STEEL_LIGHT = Color3.fromRGB(143, 159, 175)
local STEEL_EDGE = Color3.fromRGB(189, 202, 212)
local GUNMETAL = Color3.fromRGB(22, 27, 34)
local CONCRETE = Color3.fromRGB(54, 58, 62)
local GASKET = Color3.fromRGB(10, 14, 18)
local AMBER = Color3.fromRGB(255, 183, 62)
local CYAN = Color3.fromRGB(72, 225, 255)
local GREEN = Color3.fromRGB(78, 255, 157)

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

-- Ensured, but no longer fired from here: the keypad handler that used to need
-- it now lives in VaultDoorService. Kept above the stand-down check anyway so
-- ClueClientUI's WaitForChild on this folder cannot hang on a server where the
-- builder returns early, whatever order the scripts happen to start in.
local remotes = ensure(ReplicatedStorage, ClueConfig.RemotesFolder, "Folder")
ensure(remotes, ClueConfig.OpenEvent, "RemoteEvent")

--[[
	Stand down when the place itself owns the vault.

	This script used to be the only place BankVault existed. It ran on every
	server start and threw the model away again when the server died, which is
	why nothing below was visible -- or editable -- in Studio's edit mode. The
	vault has since been baked into the place as real saved instances, so this
	file is now the fallback for a place that has none, not the source of truth.

	The `BankVault_Procedural` rename further down was the first attempt at
	coping with that and it does not go far enough: it keeps the saved model's
	name intact but still drops a second, identical vault beside it. Nothing
	downstream wants two -- ClueService's findVault() prefers whichever child
	carries GeneratedBankVault, so the procedural copy would silently win every
	lookup and the hand-authored one the user is editing would become scenery.

	The marker attribute is the whole test. A baked vault has had
	GeneratedBankVault stripped; anything this script produced (including a
	Studio Run-mode session that was saved by accident) still carries it. So a
	marker-less BankVault means the place owns the vault and we do nothing at
	all -- and in particular we return BEFORE the sweep below, because sweeping
	is destructive and a builder that has stood down has no business destroying
	anything it did not make.

	The remotes above are deliberately ensured first: ClueClientUI blocks on
	WaitForChild(ClueRemotes) and standing down must not be the reason a client
	hangs, however this script and ClueService happen to be ordered.
]]
local savedVault = Workspace:FindFirstChild("BankVault")
if savedVault and savedVault:IsA("Model") and savedVault:GetAttribute("GeneratedBankVault") ~= true then
	print(
		"[BankVault] Workspace.BankVault is authored in the place (no GeneratedBankVault marker) — builder standing down; no geometry, no sweep"
	)
	return
end

local function makePart(parent: Instance, name: string, size: Vector3, cframe: CFrame, style: PartStyle?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = true
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
		shape = Enum.PartType.Cylinder,
	})
end

local function addFrontLabel(
	part: BasePart,
	text: string,
	color: Color3,
	textSize: number,
	font: Enum.Font?
): SurfaceGui
	local surface = Instance.new("SurfaceGui")
	surface.Name = "FaceLabel"
	surface.Face = Enum.NormalId.Front
	surface.CanvasSize = Vector2.new(512, 512)
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 110
	surface.LightInfluence = 0
	surface.AlwaysOnTop = false
	surface.ZOffset = 1
	surface.Parent = part

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.TextSize = textSize
	label.Font = font or Enum.Font.GothamBold
	label.TextStrokeTransparency = 0.65
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Parent = surface
	return surface
end

-- A rename of the authored BankVault model should not leave an earlier
-- procedural version behind. Only generated models are ever removed.
for _, child in ipairs(Workspace:GetChildren()) do
	if child:IsA("Model") and child:GetAttribute("GeneratedBankVault") == true then
		child:Destroy()
	end
end

local vault = Instance.new("Model")
vault.Name = if Workspace:FindFirstChild("BankVault") then "BankVault_Procedural" else "BankVault"
vault:SetAttribute("GeneratedBankVault", true)
vault:SetAttribute(ClueConfig.VaultUnlockedAttribute, false)
vault.Parent = Workspace

local anchor = Workspace:WaitForChild("VaultAnchor", 10)
if not (anchor and anchor:IsA("BasePart")) then
	warn("[BankVault] no VaultAnchor; building at origin")
end
local origin = if anchor and anchor:IsA("BasePart") then anchor.CFrame else CFrame.new(0, 0, 0)
local function at(x: number, y: number, z: number): CFrame
	return origin * CFrame.new(x, y, z)
end

-- The façade is deliberately built as a frame, leaving a real doorway behind
-- the circular door. The original solid wall made the vault read as a flat
-- prop and prevented the player from ever reaching the treasury.
makePart(vault, "FacadeLeft", Vector3.new(6.5, 28, 5), at(-16.75, 14, 4), {
	color = CONCRETE,
	material = Enum.Material.Concrete,
})
makePart(vault, "FacadeRight", Vector3.new(6.5, 28, 5), at(16.75, 14, 4), {
	color = CONCRETE,
	material = Enum.Material.Concrete,
})
makePart(vault, "FacadeLintel", Vector3.new(27, 3, 5), at(0, 26.5, 4), {
	color = CONCRETE,
	material = Enum.Material.Concrete,
})
makePart(vault, "LeftButtress", Vector3.new(3.4, 28.8, 6), at(-19.2, 14.4, 1.9), {
	color = STEEL_DARK,
	material = Enum.Material.DiamondPlate,
})
makePart(vault, "RightButtress", Vector3.new(3.4, 28.8, 6), at(19.2, 14.4, 1.9), {
	color = STEEL_DARK,
	material = Enum.Material.DiamondPlate,
})
makePart(vault, "OverheadLintel", Vector3.new(36.5, 3, 6), at(0, 26.5, 1.8), {
	color = STEEL_DARK,
	material = Enum.Material.DiamondPlate,
})
--[[
	The wall the round door is actually set into.

	Without this the facade was a rectangle with a circle parked in it and
	nothing in between. FacadeLeft and FacadeRight leave an opening spanning
	x -13.5..13.5 and y 0.8..25; StructuralCollar is 26.8 across, so the door is
	a 13.4-radius circle centred at y 13.2. A circle inscribed in that rectangle
	touches it only at the equator, and everywhere else there is a crescent of
	nothing:

	      y  0.8  ->  8.42 studs of open air EACH SIDE of the door
	      y  4.0  ->  3.76
	      y 13.2  ->  0.10   (the only height that is actually closed)
	      y 23.0  ->  4.36
	      y 25.0  ->  7.15

	Eight studs at floor level is a doorway. You could walk straight past the
	vault door into the treasury, which is why the keypad, the code and the hunt
	that produces it were all optional.

	Boxes cannot close a crescent without either clipping the door or leaving a
	residual gap, so this is a real solid: one slab filling the whole opening
	with the doorway subtracted out of it. The cutter is 0.1 wider than the
	collar so the aperture clears the ironwork rather than z-fighting it, and it
	sits at z 3.6 -- behind the collar (z 0.65) and the leaf (z -1.25), so the
	door still swings into open air.

	If SubtractAsync ever fails the slab is removed rather than left whole: an
	un-subtracted slab would seal the vault permanently shut, which is a worse
	failure than the gap it replaces.
]]
local spandrel = makePart(vault, "FacadeSpandrel", Vector3.new(27, 24.2, 1.6), at(0, 12.9, 3.6), {
	color = CONCRETE,
	material = Enum.Material.Concrete,
})

do
	local cutter = Instance.new("Part")
	cutter.Name = "SpandrelCutter"
	cutter.Anchored = true
	cutter.Shape = Enum.PartType.Cylinder
	-- Same construction as the cylinder() helper: length on X, then yawed so the
	-- axis runs along Z, straight through the wall.
	cutter.Size = Vector3.new(6, 26.9, 26.9)
	cutter.CFrame = at(0, 13.2, 3.6) * CFrame.Angles(0, math.rad(90), 0)
	cutter.Parent = vault

	local ok, result = pcall(function()
		return spandrel:SubtractAsync({ cutter })
	end)
	cutter:Destroy()

	if ok and result then
		result.Name = "FacadeSpandrel"
		result.Anchored = true
		result.CanCollide = true
		result.Color = CONCRETE
		result.Material = Enum.Material.Concrete
		result.UsePartColor = true
		result.Parent = vault
		spandrel:Destroy()
	else
		warn(`[BankVault] spandrel subtraction failed ({tostring(result)}); removing it so the door still opens`)
		spandrel:Destroy()
	end
end

makePart(vault, "Threshold", Vector3.new(35, 0.8, 8), at(0, 0.4, -0.6), {
	color = STEEL_DARK,
	material = Enum.Material.DiamondPlate,
})
makePart(vault, "ThresholdInlay", Vector3.new(30, 0.16, 1.1), at(0, 0.84, -3.1), {
	color = STEEL_EDGE,
	material = Enum.Material.Metal,
	reflectance = 0.12,
})

-- The actual chamber begins just beyond the door. Diamond-plate floor strips,
-- reinforced walls, ceiling ribs, and restrained warm lighting make this feel
-- like a destination rather than an empty box behind a façade.
makePart(vault, "TreasuryFloor", Vector3.new(36, 0.82, 45), at(0, 0.41, 20), {
	color = Color3.fromRGB(39, 46, 53),
	material = Enum.Material.DiamondPlate,
})
makePart(vault, "TreasuryLeftWall", Vector3.new(1.2, 27, 42), at(-17.4, 13.5, 21), {
	color = CONCRETE,
	material = Enum.Material.Concrete,
})
makePart(vault, "TreasuryRightWall", Vector3.new(1.2, 27, 42), at(17.4, 13.5, 21), {
	color = CONCRETE,
	material = Enum.Material.Concrete,
})
makePart(vault, "TreasuryCeiling", Vector3.new(36, 1.1, 42), at(0, 27.1, 21), {
	color = STEEL_DARK,
	material = Enum.Material.DiamondPlate,
})
makePart(vault, "TreasuryRearWall", Vector3.new(36, 27, 1.2), at(0, 13.5, 41.4), {
	color = CONCRETE,
	material = Enum.Material.Concrete,
})

for index, z in ipairs({ 8, 17, 26, 35 }) do
	makePart(vault, `CeilingRib_{index}`, Vector3.new(35, 0.55, 0.7), at(0, 25.9, z), {
		color = STEEL_MID,
		material = Enum.Material.Metal,
		reflectance = 0.1,
	})
	local strip = makePart(vault, `CeilingLight_{index}`, Vector3.new(10, 0.12, 0.32), at(0, 25.57, z), {
		color = AMBER,
		material = Enum.Material.Neon,
		castShadow = false,
	})
	strip.CanCollide = false
	local light = Instance.new("PointLight")
	light.Name = "WarmTreasuryGlow"
	light.Color = Color3.fromRGB(255, 205, 122)
	light.Brightness = 1.35
	light.Range = 18
	light.Shadows = true
	light.Parent = strip
end

-- Layered cylinders create a real machined door, a seal, and the structural
-- locking collar. Keeping the movable metalwork in its own model lets the
-- round door swing open at the keypad instead of being a static set piece.
local doorAssembly = Instance.new("Model")
doorAssembly.Name = "RoundVaultDoor"
doorAssembly.Parent = vault

-- Cylinder axes are rotated to face the player on -Z.
cylinder(doorAssembly, "StructuralCollar", 26.8, 0.9, at(0, 13.2, 0.65), {
	color = STEEL_DARK,
	material = Enum.Material.DiamondPlate,
})
cylinder(doorAssembly, "OuterMachinedRing", 25.5, 0.78, at(0, 13.2, -0.18), {
	color = STEEL_LIGHT,
	material = Enum.Material.Metal,
	reflectance = 0.14,
})
cylinder(doorAssembly, "LockingCollar", 23.7, 0.36, at(0, 13.2, -0.64), {
	color = GASKET,
	material = Enum.Material.SmoothPlastic,
})
cylinder(doorAssembly, "VaultDoor", 22.7, 1.28, at(0, 13.2, -1.25), {
	color = STEEL_MID,
	material = Enum.Material.Metal,
	reflectance = 0.08,
})
cylinder(doorAssembly, "DoorFacePlate", 20.2, 0.26, at(0, 13.2, -1.98), {
	color = STEEL_DARK,
	material = Enum.Material.Metal,
	reflectance = 0.1,
})
cylinder(doorAssembly, "InnerMachinedRing", 18.6, 0.2, at(0, 13.2, -2.14), {
	color = STEEL_LIGHT,
	material = Enum.Material.Metal,
	reflectance = 0.17,
})
cylinder(doorAssembly, "InnerFace", 17.35, 0.15, at(0, 13.2, -2.27), {
	color = STEEL_DARK,
	material = Enum.Material.Metal,
	reflectance = 0.06,
})

-- Twelve locking pins around the collar give the outer edge a convincing
-- mechanical rhythm and break up what would otherwise be a flat circle.
for index = 0, 11 do
	local angle = math.rad(index * 30)
	local radius = 11.65
	local x = math.cos(angle) * radius
	local y = 13.2 + math.sin(angle) * radius
	cylinder(doorAssembly, `LockingBolt_{index + 1}`, 0.95, 0.68, at(x, y, -1.0), {
		color = STEEL_EDGE,
		material = Enum.Material.Metal,
		reflectance = 0.22,
	})
	-- A smaller dark socket makes each bolt read as an engineered fitting.
	cylinder(doorAssembly, `BoltSocket_{index + 1}`, 0.38, 0.7, at(x, y, -1.37), {
		color = GUNMETAL,
		material = Enum.Material.Metal,
	})
end

-- Large vertical hinges live outside the main circle, while short braces make
-- them look capable of carrying the door's enormous weight.
for index, y in ipairs({ 5.2, 13.2, 21.2 }) do
	local hinge = makePart(
		vault,
		`Hinge_{index}`,
		Vector3.new(1.1, 3.7, 1.1),
		at(-12.65, y, -0.2) * CFrame.Angles(0, 0, math.rad(90)),
		{
			color = STEEL_LIGHT,
			material = Enum.Material.Metal,
			shape = Enum.PartType.Cylinder,
			reflectance = 0.16,
		}
	)
	hinge.CanCollide = false
	makePart(vault, `HingeBrace_{index}`, Vector3.new(2.4, 1.15, 1.25), at(-11.65, y, -0.55), {
		color = STEEL_DARK,
		material = Enum.Material.DiamondPlate,
	})
end

-- The six-spoke handwheel is assembled in the face plane. Each spoke points
-- exactly from the hub rather than being a flat decal, so it catches light.
cylinder(doorAssembly, "WheelBackplate", 6.9, 0.3, at(0, 13.2, -2.45), {
	color = GUNMETAL,
	material = Enum.Material.Metal,
})
cylinder(doorAssembly, "WheelRim", 6.15, 0.42, at(0, 13.2, -2.65), {
	color = STEEL_LIGHT,
	material = Enum.Material.Metal,
	reflectance = 0.2,
})
cylinder(doorAssembly, "WheelInset", 5.15, 0.45, at(0, 13.2, -2.88), {
	color = STEEL_DARK,
	material = Enum.Material.Metal,
})

for index = 0, 5 do
	local angle = math.rad(index * 60)
	local direction = Vector3.new(math.cos(angle), math.sin(angle), 0)
	local localMidpoint = Vector3.new(direction.X * 2.15, 13.2 + direction.Y * 2.15, -3.18)
	local midpoint = origin:PointToWorldSpace(localMidpoint)
	local worldDirection = origin:VectorToWorldSpace(direction)
	local worldUp = origin:VectorToWorldSpace(Vector3.zAxis)
	local spoke = makePart(
		doorAssembly,
		`WheelSpoke_{index + 1}`,
		Vector3.new(4.15, 0.42, 0.42),
		CFrame.fromMatrix(midpoint, worldDirection, worldUp),
		{
			color = STEEL_EDGE,
			material = Enum.Material.Metal,
			reflectance = 0.2,
		}
	)
	spoke.CanCollide = false

	local knobPosition = origin:PointToWorldSpace(Vector3.new(direction.X * 4.25, 13.2 + direction.Y * 4.25, -3.18))
	local knob = cylinder(doorAssembly, `WheelHandle_{index + 1}`, 0.85, 0.72, CFrame.new(knobPosition), {
		color = STEEL_LIGHT,
		material = Enum.Material.Metal,
		reflectance = 0.25,
	})
	knob.CanCollide = false
end

cylinder(doorAssembly, "WheelHub", 2.45, 0.85, at(0, 13.2, -3.38), {
	color = STEEL_EDGE,
	material = Enum.Material.Metal,
	reflectance = 0.3,
})
cylinder(doorAssembly, "WheelHubCap", 1.25, 0.91, at(0, 13.2, -3.8), {
	color = GUNMETAL,
	material = Enum.Material.Metal,
})

-- A discrete serial plaque adds a small, premium detail without covering the
-- working parts of the door.
local manufacturerPlaque =
	makePart(doorAssembly, "ManufacturerPlaque", Vector3.new(5.3, 1.25, 0.12), at(0, 5.2, -2.4), {
		color = GUNMETAL,
		material = Enum.Material.Metal,
		reflectance = 0.08,
	})
addFrontLabel(manufacturerPlaque, "AURUM  •  CLASS V", STEEL_EDGE, 68, Enum.Font.GothamMedium)

-- Keypad: a separate armoured housing, glowing status display, and all twelve
-- raised buttons make it unmistakably functional from a distance.
local keypadCFrame = at(9.2, 13.15, -2.0)
local keypadBack = makePart(vault, "KeypadArmouredHousing", Vector3.new(5.2, 8.6, 0.68), keypadCFrame, {
	color = GUNMETAL,
	material = Enum.Material.DiamondPlate,
	reflectance = 0.06,
})
keypadBack.CanCollide = false

local keypadBorder =
	makePart(vault, "KeypadMetalBezel", Vector3.new(4.75, 8.1, 0.18), keypadCFrame * CFrame.new(0, 0, -0.43), {
		color = STEEL_LIGHT,
		material = Enum.Material.Metal,
		reflectance = 0.18,
	})
keypadBorder.CanCollide = false

local keypadFace = makePart(vault, "KeypadFace", Vector3.new(4.35, 7.7, 0.2), keypadCFrame * CFrame.new(0, 0, -0.57), {
	color = STEEL_DARK,
	material = Enum.Material.Metal,
})
keypadFace.CanCollide = false

local display =
	makePart(vault, "KeypadDisplay", Vector3.new(3.45, 1.05, 0.16), keypadCFrame * CFrame.new(0, 2.75, -0.73), {
		color = Color3.fromRGB(7, 27, 35),
		material = Enum.Material.Glass,
		reflectance = 0.08,
	})
display.CanCollide = false
-- The SurfaceGui and its "Label" are geometry: VaultDoorService finds the label
-- by name and writes READY/OPENING/ACCESS into it, so this call still has to
-- happen even though nothing here reads the result any more.
addFrontLabel(display, "READY", GREEN, 150, Enum.Font.Code)

local displayLight = Instance.new("PointLight")
displayLight.Name = "KeypadGlow"
displayLight.Color = CYAN
displayLight.Brightness = 0.75
displayLight.Range = 8
displayLight.Shadows = true
displayLight.Parent = display

local buttonLabels = {
	"1",
	"2",
	"3",
	"4",
	"5",
	"6",
	"7",
	"8",
	"9",
	"CLR",
	"0",
	"ENTER",
}

for index, labelText in ipairs(buttonLabels) do
	local row = math.floor((index - 1) / 3)
	local column = (index - 1) % 3
	local x = (column - 1) * 1.23
	local y = 1.18 - row * 1.28
	local isEnter = labelText == "ENTER"
	local isClear = labelText == "CLR"
	local buttonColor = if isEnter
		then Color3.fromRGB(20, 101, 76)
		elseif isClear then Color3.fromRGB(118, 59, 41)
		else Color3.fromRGB(62, 75, 88)
	local button = makePart(
		vault,
		`KeypadButton_{labelText}`,
		Vector3.new(1.04, 0.94, 0.26),
		keypadCFrame * CFrame.new(x, y, -0.82),
		{
			color = buttonColor,
			material = Enum.Material.Metal,
			reflectance = 0.12,
		}
	)
	button.CanCollide = false
	addFrontLabel(
		button,
		labelText,
		if isEnter then GREEN elseif isClear then AMBER else STEEL_EDGE,
		if #labelText > 1 then 68 else 155,
		Enum.Font.GothamBold
	)
end

local scanner =
	makePart(vault, "KeypadStatusLED", Vector3.new(0.48, 0.48, 0.18), keypadCFrame * CFrame.new(-1.72, 2.75, -0.74), {
		color = GREEN,
		material = Enum.Material.Neon,
		shape = Enum.PartType.Ball,
	})
scanner.CanCollide = false

local keypadPrompt = Instance.new("ProximityPrompt")
keypadPrompt.Name = "InspectKeypad"
keypadPrompt.ActionText = "Inspect keypad"
keypadPrompt.ObjectText = "Vault access panel"
keypadPrompt.KeyboardKeyCode = Enum.KeyCode.E
keypadPrompt.MaxActivationDistance = 10
keypadPrompt.RequiresLineOfSight = true
keypadPrompt.HoldDuration = 0
keypadPrompt.Parent = keypadFace

-- Symmetrical warning lamps and a security header finish the façade. These
-- are intentionally restrained: the metalwork remains the focal point.
for _, x in ipairs({ -15.5, 15.5 }) do
	local lampBase = cylinder(vault, `SecurityLampBase_{x}`, 1.65, 0.45, at(x, 24.6, -0.85), {
		color = GUNMETAL,
		material = Enum.Material.Metal,
	})
	lampBase.CanCollide = false
	local lamp = cylinder(vault, `SecurityLamp_{x}`, 0.88, 0.56, at(x, 24.6, -1.16), {
		color = AMBER,
		material = Enum.Material.Neon,
	})
	lamp.CanCollide = false
	local light = Instance.new("PointLight")
	light.Color = AMBER
	light.Brightness = 0.5
	light.Range = 7
	light.Parent = lamp
end

local header = makePart(vault, "VaultHeader", Vector3.new(13.4, 1.85, 0.16), at(0, 25.1, -1.26), {
	color = GUNMETAL,
	material = Enum.Material.Metal,
	reflectance = 0.08,
})
header.CanCollide = false
addFrontLabel(header, "SECURE VAULT", STEEL_EDGE, 116, Enum.Font.GothamBold)

-- Treasury layout: a lit central aisle frames the premium collection visible
-- through the doorway, while the deeper room rewards players who enter.
local GOLD = Color3.fromRGB(255, 202, 73)
local GOLD_LIGHT = Color3.fromRGB(255, 231, 142)
local CASH = Color3.fromRGB(52, 108, 76)
local CASH_BAND = Color3.fromRGB(232, 200, 95)
local VELVET = Color3.fromRGB(42, 10, 26)
local SAPPHIRE = Color3.fromRGB(65, 164, 255)
local RUBY = Color3.fromRGB(255, 71, 88)
local EMERALD = Color3.fromRGB(70, 244, 165)

local loot = Instance.new("Folder")
loot.Name = "TreasuryCollection"
loot.Parent = vault

local aisle = makePart(loot, "InlaidCentralAisle", Vector3.new(5.4, 0.12, 35), at(0, 0.88, 22), {
	color = Color3.fromRGB(79, 84, 88),
	material = Enum.Material.Metal,
	reflectance = 0.12,
	castShadow = false,
})
aisle.CanCollide = false
for index, z in ipairs({ 6, 14, 22, 30, 38 }) do
	local marker = makePart(loot, `AisleMarker_{index}`, Vector3.new(4.25, 0.06, 0.18), at(0, 0.97, z), {
		color = AMBER,
		material = Enum.Material.Neon,
		castShadow = false,
	})
	marker.CanCollide = false
end

local function goldBar(name: string, x: number, y: number, z: number, rotation: number): Part
	local bar =
		makePart(loot, name, Vector3.new(1.85, 0.45, 0.92), at(x, y, z) * CFrame.Angles(0, math.rad(rotation), 0), {
			color = GOLD,
			material = Enum.Material.Metal,
			reflectance = 0.27,
		})
	bar.CanCollide = false
	local inset = makePart(
		loot,
		`${name}_Hallmark`,
		Vector3.new(1.38, 0.06, 0.56),
		at(x, y + 0.26, z) * CFrame.Angles(0, math.rad(rotation), 0),
		{
			color = GOLD_LIGHT,
			material = Enum.Material.Metal,
			reflectance = 0.34,
			castShadow = false,
		}
	)
	inset.CanCollide = false
	return bar
end

local function cashBundle(name: string, x: number, y: number, z: number, rotation: number): Part
	local bundle =
		makePart(loot, name, Vector3.new(1.55, 0.58, 1.0), at(x, y, z) * CFrame.Angles(0, math.rad(rotation), 0), {
			color = CASH,
			material = Enum.Material.SmoothPlastic,
		})
	bundle.CanCollide = false
	local band = makePart(
		loot,
		`${name}_SealBand`,
		Vector3.new(0.22, 0.62, 1.05),
		at(x, y, z) * CFrame.Angles(0, math.rad(rotation), 0),
		{
			color = CASH_BAND,
			material = Enum.Material.Metal,
			reflectance = 0.12,
			castShadow = false,
		}
	)
	band.CanCollide = false
	return bundle
end

local function bullionPallet(name: string, x: number, z: number)
	local pallet = makePart(loot, `${name}_Pallet`, Vector3.new(6.2, 0.5, 4.8), at(x, 1.15, z), {
		color = STEEL_DARK,
		material = Enum.Material.DiamondPlate,
	})
	pallet.CanCollide = false
	for row = 0, 2 do
		for column = 0, 2 do
			local stackX = x + (column - 1) * 1.72
			local stackZ = z + (row - 1) * 1.18
			goldBar(`${name}_Bar_{row}_{column}_Lower`, stackX, 1.67, stackZ, (row * 17 + column * 11) % 35 - 17)
			if (row + column) % 2 == 0 then
				goldBar(
					`${name}_Bar_{row}_{column}_Upper`,
					stackX + 0.08,
					2.13,
					stackZ - 0.04,
					(row * 11 - column * 13) % 30 - 15
				)
			end
		end
	end
	local bullionPlaque = makePart(loot, `${name}_Plaque`, Vector3.new(3.8, 0.65, 0.1), at(x, 1.7, z - 2.46), {
		color = GUNMETAL,
		material = Enum.Material.Metal,
	})
	bullionPlaque.CanCollide = false
	addFrontLabel(bullionPlaque, "999.9 FINE GOLD", GOLD_LIGHT, 72, Enum.Font.GothamMedium)
end

local function cashCrate(name: string, x: number, z: number)
	local crate = makePart(loot, `${name}_Crate`, Vector3.new(5.8, 4.2, 4.4), at(x, 2.55, z), {
		color = Color3.fromRGB(73, 54, 34),
		material = Enum.Material.WoodPlanks,
	})
	crate.CanCollide = false
	local label = makePart(loot, `${name}_Stencil`, Vector3.new(3.6, 0.85, 0.08), at(x, 3.0, z - 2.23), {
		color = Color3.fromRGB(21, 31, 26),
		material = Enum.Material.SmoothPlastic,
	})
	label.CanCollide = false
	addFrontLabel(label, "RESERVE NOTES", Color3.fromRGB(210, 229, 195), 60, Enum.Font.GothamBold)
	for row = 0, 2 do
		for column = 0, 2 do
			cashBundle(
				`${name}_Bundle_{row}_{column}`,
				x + (column - 1) * 1.5,
				4.94,
				z + (row - 1) * 1.15,
				row * 7 - column * 9
			)
		end
	end
end

local function crystal(name: string, x: number, y: number, z: number, color: Color3): Part
	local gem = makePart(
		loot,
		name,
		Vector3.new(1.25, 1.25, 1.25),
		at(x, y, z) * CFrame.Angles(math.rad(45), math.rad(25), math.rad(15)),
		{
			color = color,
			material = Enum.Material.Neon,
			shape = Enum.PartType.Ball,
			reflectance = 0.18,
			castShadow = false,
		}
	)
	gem.CanCollide = false
	local glow = Instance.new("PointLight")
	glow.Name = "GemRadiance"
	glow.Color = color
	glow.Brightness = 0.9
	glow.Range = 7
	glow.Shadows = true
	glow.Parent = gem
	return gem
end

local function artifactCase(name: string, x: number, z: number, title: string, color: Color3)
	local base = makePart(loot, `${name}_Plinth`, Vector3.new(6.4, 1.25, 5.2), at(x, 1.48, z), {
		color = GUNMETAL,
		material = Enum.Material.Metal,
		reflectance = 0.08,
	})
	base.CanCollide = false
	local cushion = makePart(loot, `${name}_Velvet`, Vector3.new(4.6, 0.16, 3.4), at(x, 2.19, z), {
		color = VELVET,
		material = Enum.Material.Fabric,
	})
	cushion.CanCollide = false
	local glass = makePart(loot, `${name}_Glass`, Vector3.new(5.55, 4.6, 4.35), at(x, 4.52, z), {
		color = Color3.fromRGB(170, 232, 255),
		material = Enum.Material.Glass,
		transparency = 0.68,
		reflectance = 0.22,
		castShadow = false,
	})
	glass.CanCollide = false
	for cornerIndex, offset in ipairs({
		Vector3.new(-2.57, 0, -1.98),
		Vector3.new(2.57, 0, -1.98),
		Vector3.new(-2.57, 0, 1.98),
		Vector3.new(2.57, 0, 1.98),
	}) do
		local post = makePart(
			loot,
			`${name}_CasePost_{cornerIndex}`,
			Vector3.new(0.16, 4.75, 0.16),
			at(x + offset.X, 4.5, z + offset.Z),
			{
				color = STEEL_LIGHT,
				material = Enum.Material.Metal,
				reflectance = 0.25,
				castShadow = false,
			}
		)
		post.CanCollide = false
	end
	local crownBand = makePart(loot, `${name}_CrownBand`, Vector3.new(3.15, 0.54, 0.45), at(x, 2.64, z), {
		color = GOLD,
		material = Enum.Material.Metal,
		reflectance = 0.35,
	})
	crownBand.CanCollide = false
	for jewelIndex, jewelX in ipairs({ -1.05, 0, 1.05 }) do
		local spike = makePart(
			loot,
			`${name}_CrownPoint_{jewelIndex}`,
			Vector3.new(0.3, 1.22 + math.abs(jewelX) * 0.15, 0.3),
			at(x + jewelX, 3.24, z),
			{
				color = GOLD_LIGHT,
				material = Enum.Material.Metal,
				reflectance = 0.35,
			}
		)
		spike.CanCollide = false
		crystal(`${name}_Jewel_{jewelIndex}`, x + jewelX, 2.88, z - 0.28, color)
	end
	local artifactPlaque =
		makePart(loot, `${name}_ArtifactPlaque`, Vector3.new(5.1, 0.76, 0.1), at(x, 1.74, z - 2.66), {
			color = GUNMETAL,
			material = Enum.Material.Metal,
		})
	artifactPlaque.CanCollide = false
	addFrontLabel(artifactPlaque, title, GOLD_LIGHT, 62, Enum.Font.GothamMedium)
end

-- A gallery-like front row provides the strongest first read when the door opens.
artifactCase("AureliaCrown", -10.1, 14.5, "CROWN OF AURELIA", SAPPHIRE)
artifactCase("ImperialCrown", 10.1, 14.5, "IMPERIAL DIADEM", RUBY)
bullionPallet("WestBullion", -10.2, 24)
bullionPallet("EastBullion", 10.2, 24)
cashCrate("WestReserve", -10.2, 33.8)
cashCrate("EastReserve", 10.2, 33.8)

-- The rear display turns the end wall into a visual focal point rather than a
-- dead surface. The three gems carry distinct color accents through the room.
local reservePanel = makePart(loot, "ReserveEmblemPanel", Vector3.new(13.8, 8.2, 0.18), at(0, 13.6, 40.72), {
	color = STEEL_DARK,
	material = Enum.Material.Metal,
	reflectance = 0.12,
})
reservePanel.CanCollide = false
addFrontLabel(reservePanel, "AURUM RESERVE", STEEL_EDGE, 92, Enum.Font.GothamBold)
for _, gemInfo in ipairs({
	{ x = -4.2, color = EMERALD, name = "Emerald" },
	{ x = 0, color = SAPPHIRE, name = "Sapphire" },
	{ x = 4.2, color = RUBY, name = "Ruby" },
}) do
	local mount = cylinder(loot, `RearGemMount_{gemInfo.name}`, 2.45, 0.3, at(gemInfo.x, 8.5, 40.5), {
		color = GUNMETAL,
		material = Enum.Material.Metal,
	})
	mount.CanCollide = false
	crystal(`RearVaultGem_{gemInfo.name}`, gemInfo.x, 8.5, 40.21, gemInfo.color)
end

--[[
	Turn the treasury from a painting into loot.

	Everything above is modelled and lit and completely inert: 28 bullion bars,
	18 banded bundles and five jewels, none of which could be picked up, so the
	reward for the whole five-node hunt was a room you looked at.

	Tagging them Collectable hands them to the Sack, which already knows how to
	bag a part and give it back intact. The value attribute is what ClueService
	totals at the exit door.

	The point is not the number. The sack holds ten things, and during the
	120-second escape those slots are also where bandages go -- so every bar you
	take out is a teammate you cannot pick up off the floor. Greed is supposed to
	cost something.

	Matching is done here in one pass rather than at each construction site
	because the loot is built by four different helpers. Sub-parts are excluded
	explicitly: a bar's Hallmark and a bundle's SealBand are decoration welded to
	the piece, not separate treasure.
]]
local LOOT_VALUES: { { pattern: string, value: number, reject: string? } } = {
	{ pattern = "_Bar_", value = 2500, reject = "_Hallmark" },
	{ pattern = "_Bundle_", value = 800, reject = "_SealBand" },
	{ pattern = "Crown_Jewel", value = 5000 },
	{ pattern = "RearVaultGem", value = 4000 },
}

local tagged, worth = 0, 0
for _, descendant in loot:GetDescendants() do
	if not descendant:IsA("BasePart") then
		continue
	end
	for _, entry in LOOT_VALUES do
		local name = descendant.Name
		if string.find(name, entry.pattern, 1, true) and not (entry.reject and string.find(name, entry.reject, 1, true)) then
			descendant:SetAttribute(ClueConfig.LootValueAttribute, entry.value)
			CollectionService:AddTag(descendant, ClueConfig.CollectableTag)
			tagged += 1
			worth += entry.value
			break
		end
	end
end
print(`[BankVault] {tagged} pieces of treasure are collectable, {worth} total on the floor`)

for index, x in ipairs({ -14.2, 14.2 }) do
	local wallLamp = cylinder(loot, `WallSecurityLamp_{index}`, 1.05, 0.25, at(x, 15.5, 7.5), {
		color = AMBER,
		material = Enum.Material.Neon,
		castShadow = false,
	})
	wallLamp.CanCollide = false
	local lampLight = Instance.new("PointLight")
	lampLight.Color = AMBER
	lampLight.Brightness = 1.1
	lampLight.Range = 13
	lampLight.Shadows = true
	lampLight.Parent = wallLamp
end

--[[
	The door's swing state is emitted as saved geometry; VaultDoorService is what
	animates it.

	The tween, the keypad handler and the VaultUnlocked listener all used to live
	here, wired out of the locals that had just built the door. That only worked
	while the vault was rebuilt every server start. Now that the builder stands
	down in front of an authored vault, anything wired here would simply not
	happen -- ClueService would unlock a door that nothing was listening to.

	Emitting the NumberValue and nothing else means a generated vault and a baked
	one are structurally identical, so the service cannot tell them apart. That
	is the point: one behaviour path, not two that drift.
]]
local doorAngle = Instance.new("NumberValue")
doorAngle.Name = "DoorSwingAngle"
doorAngle.Value = 0
doorAngle.Parent = doorAssembly

vault.PrimaryPart = keypadBack
