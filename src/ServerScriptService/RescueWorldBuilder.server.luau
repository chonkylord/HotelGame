--!strict
-- Authors the physical support layer for player rescue: invisible, same-floor
-- recovery anchors and a bounded set of visible bandage dispensers. Rescue
-- authority lives elsewhere; this script only publishes tagged world objects.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local RescueConfig = require(ReplicatedStorage:WaitForChild("RescueConfig"))

local FOLDER_NAME = "RescueWorld"
local DROP_ZONE_TAG = RescueConfig.DropZoneTag
local DROP_ZONE_FLOOR_ATTRIBUTE = RescueConfig.DropZoneFloorAttribute
local DROP_ZONE_ID_ATTRIBUTE = "RescueZoneId"
local BANDAGE_PICKUP_TAG = RescueConfig.BandagePickupTag
local BANDAGE_PROMPT_NAME = RescueConfig.BandagePromptName
local BANDAGE_SITE_ATTRIBUTE = "BandageSiteId"
local BANDAGE_CLAIMED_ATTRIBUTE = RescueConfig.BandageClaimedAttribute

local MIN_ZONE_SPACING = 25
local BANDAGE_RESPAWN_SECONDS = 75
local DROP_ZONE_SIZE = Vector3.new(7, 0.2, 7)

type DropZonePlacement = {
	id: string,
	floorId: string,
	position: Vector3,
}

type BandagePlacement = {
	id: string,
	floorId: string,
	cframe: CFrame,
}

type BandageSite = {
	placement: BandagePlacement,
	model: Model,
	pickup: Model?,
	revision: number,
}

local function facing(position: Vector3, direction: Vector3): CFrame
	return CFrame.lookAt(position, position + direction)
end

-- VaultChamberBuilder owns this anchor and may run after this script. Deriving
-- expedition placements from it keeps rescue aligned if the whole vault is
-- rotated or moved; the fallback is the builder's documented default.
--
-- That default is (960, 19, 15), matching the hand-placed VaultAnchor the baked
-- vault ships with. It used to read (960, -140, 15) from back when the chamber
-- was dug out 160 studs under the map; leaving it there meant a ten-second
-- WaitForChild timeout scattered every Vault-floor drop zone and both
-- expedition bandage cabinets deep underground, where no player can ever reach
-- them -- silently, because the fallback path only warns about the anchor.
local defaultVaultAnchor = CFrame.new(960, 19, 15)
local vaultAnchorInstance = Workspace:WaitForChild("VaultAnchor", 10)
local vaultAnchorCFrame = defaultVaultAnchor
if vaultAnchorInstance and vaultAnchorInstance:IsA("BasePart") then
	vaultAnchorCFrame = vaultAnchorInstance.CFrame
else
	warn("[RescueWorldBuilder] VaultAnchor was unavailable; using the generated default transform")
end

local function vaultPosition(x: number, y: number, z: number): Vector3
	return (vaultAnchorCFrame * CFrame.new(x, y, z)).Position
end

local function vaultFacing(x: number, y: number, z: number, localDirection: Vector3): CFrame
	local position = vaultPosition(x, y, z)
	local direction = vaultAnchorCFrame:VectorToWorldSpace(localDirection)
	return facing(position, direction)
end

-- Positions were measured against the live hotel geometry. Marker Y values sit
-- just above their walkable surface. The Room anchors stay in the broad corridor
-- floor parts rather than inside guest rooms, so no locked door can strand one.
local DROP_ZONES: { DropZonePlacement } = {
	{
		id = "LobbyReception",
		floorId = "Lobby",
		position = Vector3.new(-70, 18.05, 146),
	},
	{
		id = "LobbyClassHall",
		floorId = "Lobby",
		position = Vector3.new(-80, 18.05, 78),
	},
	{
		id = "LobbyFountainEast",
		floorId = "Lobby",
		position = Vector3.new(-60, 18.05, 111),
	},
	{
		id = "RoomsElevatorGallery",
		floorId = "Rooms",
		position = Vector3.new(260.3, 18.05, -14),
	},
	{
		id = "RoomsWestJunction",
		floorId = "Rooms",
		position = Vector3.new(228, 18.05, -38.25),
	},
	{
		id = "RoomsEastJunction",
		floorId = "Rooms",
		position = Vector3.new(292, 18.05, -38.25),
	},
	{
		id = "RoomsNorthConnector",
		floorId = "Rooms",
		position = Vector3.new(238, 18.05, -74),
	},
	{
		id = "AmenitiesArrival",
		floorId = "Amenities",
		position = Vector3.new(273.9, 32.7, -92),
	},
	{
		id = "AmenitiesLoungeEast",
		floorId = "Amenities",
		position = Vector3.new(247, 32.7, -34),
	},
	{
		id = "AmenitiesBallroomStageWest",
		floorId = "Amenities",
		position = Vector3.new(302.5, 33.4, 27.45),
	},
	{
		id = "SuitesElevatorLobby",
		floorId = "Suite",
		position = Vector3.new(560, 33.7, 42),
	},
	{
		id = "SuitesGalleryMid",
		floorId = "Suite",
		position = Vector3.new(560, 33.7, 5),
	},
	{
		id = "SuitesGallerySouth",
		floorId = "Suite",
		position = Vector3.new(560, 33.7, -28),
	},
	{
		id = "VaultLiftApronWest",
		floorId = "Vault",
		position = vaultPosition(-20, 0.05, -42),
	},
	{
		id = "VaultLiftApronEast",
		floorId = "Vault",
		position = vaultPosition(20, 0.05, -42),
	},
	{
		id = "VaultFacadeEast",
		floorId = "Vault",
		position = vaultPosition(25, 0.05, -10),
	},
}

-- The cabinets sit beside walls, reception/service edges, or backstage. Their
-- parts never collide, so even a shifted wall cannot turn one into a path block.
-- Local -Z is the cabinet front.
local BANDAGE_PLACEMENTS: { BandagePlacement } = {
	{
		id = "LobbyReceptionAid",
		floorId = "Lobby",
		cframe = facing(Vector3.new(-45.5, 18.05, 139.5), Vector3.new(-1, 0, 0)),
	},
	{
		id = "LobbyWestAid",
		floorId = "Lobby",
		cframe = facing(Vector3.new(-101.5, 18.05, 101.5), Vector3.new(1, 0, 0)),
	},
	{
		id = "RoomsWestHallAid",
		floorId = "Rooms",
		cframe = facing(Vector3.new(220.5, 18.05, -57), Vector3.new(1, 0, 0)),
	},
	{
		id = "RoomsEastHallAid",
		floorId = "Rooms",
		cframe = facing(Vector3.new(299.5, 18.05, -68), Vector3.new(-1, 0, 0)),
	},
	{
		id = "AmenitiesArrivalAid",
		floorId = "Amenities",
		cframe = facing(Vector3.new(268.2, 32.7, -98), Vector3.new(1, 0, 0)),
	},
	{
		id = "AmenitiesBackstageAid",
		floorId = "Amenities",
		cframe = facing(Vector3.new(337.8, 33.4, 28), Vector3.new(-1, 0, 0)),
	},
	{
		id = "SuitesLobbyAid",
		floorId = "Suite",
		cframe = facing(Vector3.new(542.5, 33.65, 36), Vector3.new(1, 0, 0)),
	},
	{
		id = "SuitesGalleryAid",
		floorId = "Suite",
		cframe = facing(Vector3.new(554, 33.65, -17), Vector3.new(1, 0, 0)),
	},
	{
		id = "VaultExpeditionAid",
		floorId = "Vault",
		cframe = vaultFacing(-39, 0.05, -38, Vector3.new(1, 0, 0)),
	},
	{
		id = "VaultSecurityAid",
		floorId = "Vault",
		cframe = vaultFacing(39, 0.05, -12, Vector3.new(-1, 0, 0)),
	},
}

local VALID_FLOORS: { [string]: boolean } = {
	Lobby = true,
	Rooms = true,
	Amenities = true,
	Suite = true,
	Vault = true,
}

local function horizontalDistance(a: Vector3, b: Vector3): number
	return (Vector2.new(a.X, a.Z) - Vector2.new(b.X, b.Z)).Magnitude
end

-- Catch a mistyped floor or a future coordinate edit that clusters all of a
-- floor's recovery options around one hazard.
for index, placement in DROP_ZONES do
	assert(VALID_FLOORS[placement.floorId], `invalid rescue floor "{placement.floorId}"`)
	for otherIndex = index + 1, #DROP_ZONES do
		local other = DROP_ZONES[otherIndex]
		if placement.floorId == other.floorId then
			assert(
				horizontalDistance(placement.position, other.position) >= MIN_ZONE_SPACING,
				`rescue zones {placement.id} and {other.id} are too close`
			)
		end
	end
end

for _, placement in BANDAGE_PLACEMENTS do
	assert(VALID_FLOORS[placement.floorId], `invalid bandage floor "{placement.floorId}"`)
end

-- RescueWorld is exclusively generated by this builder. Replacing it makes a
-- script restart deterministic and removes obsolete tagged children at once.
local existing = Workspace:FindFirstChild(FOLDER_NAME)
if existing then
	existing:Destroy()
end

local folder = Instance.new("Folder")
folder.Name = FOLDER_NAME
folder.Parent = Workspace

local dropZoneFolder = Instance.new("Folder")
dropZoneFolder.Name = "DropZones"
dropZoneFolder.Parent = folder

local dispenserFolder = Instance.new("Folder")
dispenserFolder.Name = "BandageDispensers"
dispenserFolder.Parent = folder

local folderAlive = true
folder.Destroying:Connect(function()
	folderAlive = false
end)

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.FilterDescendantsInstances = { folder }

local function verifySurface(id: string, position: Vector3)
	local result = Workspace:Raycast(position + Vector3.new(0, 4, 0), Vector3.new(0, -8, 0), raycastParams)
	if not result then
		warn(`[RescueWorldBuilder] {id} has no surface within four studs`)
		return
	end
	if math.abs(result.Position.Y - position.Y) > 1.5 then
		warn(
			`[RescueWorldBuilder] {id} expected floor Y {position.Y}, found {string.format("%.2f", result.Position.Y)}`
		)
	end
end

for _, placement in DROP_ZONES do
	verifySurface(placement.id, placement.position)

	local marker = Instance.new("Part")
	marker.Name = `DropZone_{placement.id}`
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.CastShadow = false
	marker.CFrame = CFrame.new(placement.position)
	marker.Size = DROP_ZONE_SIZE
	marker.Transparency = 1
	marker:SetAttribute(DROP_ZONE_FLOOR_ATTRIBUTE, placement.floorId)
	marker:SetAttribute(DROP_ZONE_ID_ATTRIBUTE, placement.id)
	marker.Parent = dropZoneFolder
	CollectionService:AddTag(marker, DROP_ZONE_TAG)
end

local function makePart(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CastShadow = false
	part.Color = color
	part.CFrame = cframe
	part.Material = material
	part.Size = size
	if shape then
		part.Shape = shape
	end
	part.Parent = parent
	return part
end

local IVORY = Color3.fromRGB(222, 217, 201)
local IVORY_DARK = Color3.fromRGB(149, 145, 135)
local GAUZE = Color3.fromRGB(239, 235, 219)
local MEDICAL_RED = Color3.fromRGB(156, 45, 43)

local function buildDispenser(placement: BandagePlacement): Model
	local model = Instance.new("Model")
	model.Name = `FirstAidDispenser_{placement.id}`
	model:SetAttribute(BANDAGE_SITE_ATTRIBUTE, placement.id)
	model:SetAttribute(DROP_ZONE_FLOOR_ATTRIBUTE, placement.floorId)

	local base = makePart(
		model,
		"Foot",
		Vector3.new(1.9, 0.12, 0.9),
		placement.cframe * CFrame.new(0, 0.06, 0),
		IVORY_DARK,
		Enum.Material.Metal
	)
	makePart(
		model,
		"Cabinet",
		Vector3.new(1.75, 1.75, 0.36),
		placement.cframe * CFrame.new(0, 0.94, 0.2),
		IVORY,
		Enum.Material.Metal
	)
	makePart(
		model,
		"Tray",
		Vector3.new(1.45, 0.09, 0.72),
		placement.cframe * CFrame.new(0, 0.48, -0.32),
		IVORY_DARK,
		Enum.Material.Metal
	)
	makePart(
		model,
		"CrossVertical",
		Vector3.new(0.22, 0.72, 0.06),
		placement.cframe * CFrame.new(0, 1.21, -0.015),
		MEDICAL_RED,
		Enum.Material.SmoothPlastic
	)
	makePart(
		model,
		"CrossHorizontal",
		Vector3.new(0.72, 0.22, 0.06),
		placement.cframe * CFrame.new(0, 1.21, -0.015),
		MEDICAL_RED,
		Enum.Material.SmoothPlastic
	)

	model.PrimaryPart = base
	model.Parent = dispenserFolder
	return model
end

local spawnBandage: (BandageSite) -> ()

spawnBandage = function(site: BandageSite)
	if not folderAlive or folder.Parent ~= Workspace or site.model.Parent ~= dispenserFolder then
		return
	end
	if site.pickup and site.pickup.Parent then
		return
	end

	site.revision += 1
	local pickup = Instance.new("Model")
	pickup.Name = `Bandage_{site.placement.id}`
	pickup:SetAttribute(BANDAGE_SITE_ATTRIBUTE, site.placement.id)
	pickup:SetAttribute(DROP_ZONE_FLOOR_ATTRIBUTE, site.placement.floorId)
	pickup:SetAttribute(BANDAGE_CLAIMED_ATTRIBUTE, false)

	local itemCFrame = site.placement.cframe * CFrame.new(0, 0.73, -0.53) * CFrame.Angles(0, 0, math.rad(-7))
	local roll = makePart(
		pickup,
		"GauzeRoll",
		Vector3.new(0.76, 0.48, 0.48),
		itemCFrame,
		GAUZE,
		Enum.Material.Fabric,
		Enum.PartType.Cylinder
	)
	roll.CanQuery = true
	makePart(
		pickup,
		"RedSeal",
		Vector3.new(0.2, 0.5, 0.5),
		itemCFrame,
		MEDICAL_RED,
		Enum.Material.Fabric,
		Enum.PartType.Cylinder
	)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = BANDAGE_PROMPT_NAME
	prompt.ActionText = "Take bandage"
	prompt.ObjectText = "Sterile gauze"
	prompt.HoldDuration = 0.35
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = roll

	pickup.PrimaryPart = roll
	site.pickup = pickup

	pickup.Destroying:Connect(function()
		if site.pickup ~= pickup then
			return
		end
		site.pickup = nil
		site.revision += 1
		local expectedRevision = site.revision
		task.delay(BANDAGE_RESPAWN_SECONDS, function()
			if
				folderAlive
				and folder.Parent == Workspace
				and site.model.Parent == dispenserFolder
				and site.pickup == nil
				and site.revision == expectedRevision
			then
				spawnBandage(site)
			end
		end)
	end)

	-- The prompt and complete visual model exist before the service receives the
	-- tag-added signal. This avoids a startup race with RescueController.
	pickup.Parent = site.model
	CollectionService:AddTag(pickup, BANDAGE_PICKUP_TAG)
end

local sites: { BandageSite } = {}
for _, placement in BANDAGE_PLACEMENTS do
	verifySurface(placement.id, placement.cframe.Position)
	local site: BandageSite = {
		placement = placement,
		model = buildDispenser(placement),
		pickup = nil,
		revision = 0,
	}
	table.insert(sites, site)
	spawnBandage(site)
end

print(
	`[RescueWorldBuilder] ready — {#DROP_ZONES} same-floor drop zones, {#sites} bandages (one/site, {BANDAGE_RESPAWN_SECONDS}s refill)`
)
