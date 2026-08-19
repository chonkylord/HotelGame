--!strict
--[[
	Which space of the hotel a point or a fixture belongs to.

	Two scripts need the same answer and used to work it out separately:
	LightFlicker dims each fixture by the room it hangs in, and
	HorrorVisibilityZones lifts the grade while you stand in the lobby. When only
	one of them knew about a space the hotel lit inconsistently, so the geometry
	lives here and both ask the same question.
]]

local Workspace = game:GetService("Workspace")

local HorrorZones = {}

-- Lobby ----------------------------------------------------------------------

--[[
	The lobby is found by name, which is what lets it survive being moved or
	rebuilt in Studio — and was also a bug worth spelling out, because it made
	two thirds of the hotel light wrongly.

	The amenities floor owns a `LobbyCarpet`, a `CentralLobbyFurniture` model and
	a `RestaurantLobbyScreen`. Every name containing "lobby" was taken as lobby
	geometry and padded outward by 28 studs, and those three padded boxes came
	out spanning X[220..318] Y[8..64] Z[-69..62] — the whole restaurant and
	ballroom, and, because the padding reached down through the ceiling, the
	guest-room corridor underneath them as well.

	So both floors silently ran the *lobby* grade: ambient lifted from (4,5,9) to
	(48,42,36) and exposure from -0.82 to +0.55. That is why the amenities floor
	appeared to switch its ceiling lights on by itself, and why the guest rooms
	read as brightly lit when they are meant to be the darkest part of the hotel.

	Name matching stays. Anything owned by another floor is not the lobby, no
	matter what it is called.
]]
local FOREIGN_ROOTS = {
	AmenitiesFloorBlueprint = true,
	SuiteFloor = true,
	HotelWing = true,
}

--[[
	Enough padding to cover the lobby's walls and the doorway you step through,
	not enough to swallow whatever is on the other side of them. The old 28/24/28
	was reaching a floor and a half in every direction.
]]
HorrorZones.LobbyPadding = Vector3.new(14, 10, 14)

function HorrorZones.isLobbyGeometry(instance: Instance): boolean
	if not string.find(string.lower(instance.Name), "lobby", 1, true) then
		return false
	end
	local node: Instance? = instance
	while node and node ~= Workspace do
		if FOREIGN_ROOTS[node.Name] then
			return false
		end
		node = node.Parent
	end
	return true
end

-- Vault -----------------------------------------------------------------------

--[[
	The bank vault, found from its geometry rather than from a number.

	It is not part of the hotel and must not be lit like it. The hotel is dark
	because a torch beam is the thing that shapes a room; the vault is a working
	strongroom with its own security lighting, and running the Dark grade's
	(7,8,12) ambient in there just made the payoff of the entire clue hunt
	invisible.

	Deciding where it starts used to be `position.Y < -80`, and while the vault
	was a sealed sublevel that was honest: the hotel bottomed out around Y 16,
	the chamber floor was at Y -140, and sixty-odd studs of dead rock in between
	meant nothing else in the place could satisfy the test.

	The chamber sits at ground level now — floor top Y 19, ceiling Y 52 — which
	is the same Y band as the guest rooms (17.5..33) and the amenities floor
	stacked above them (32.6..52). A depth test is therefore wrong in both
	directions at once: it says "no" while you are standing in the strongroom, so
	the payoff arrives as a black screen again, and it says "yes" for anything
	that ever falls off the map, which would light a falling player like a
	treasury on the way down.

	Height cannot separate the vault from the hotel any more, so the footprint
	has to. The volume is read back off Workspace rather than written down here,
	because coming up out of the ground is exactly what made the chamber a saved
	model somebody can drag around in Studio — a constant in this file would go
	stale the first time it moved, which is the failure we are already fixing.

	JoelConfig.floorOf calls this so his floor classifier and the lighting can
	never disagree about where the vault is.
]]

export type VaultVolume = {
	cframe: CFrame,
	size: Vector3,
}

--[[
	What a bare VaultAnchor implies, in the anchor's own local space.

	VaultChamberBuilder lays the shell out relative to that anchor: side walls at
	local X ±44 and 2 thick, floor and ceiling slabs centred at Y -1 and 33, end
	walls at Z -59 and 49. That outer envelope is centred at (0, 16, -5) and
	measures 90 x 36 x 110.

	This is the fallback and not the main path, because the saved model is the
	thing the user actually edits and the anchor only says where a chamber would
	go. But every builder in the place already keys off that anchor, so honouring
	it keeps this module answering sensibly in a place whose chamber has not been
	built — or, on a client, has not replicated — yet.
]]
local ANCHOR_SHELL_CENTRE = Vector3.new(0, 16, -5)
local ANCHOR_SHELL_SIZE = Vector3.new(90, 36, 110)
-- Same bargain as the guest-room floor cache below: the chamber does not move at
-- runtime but it does replicate late, and HorrorVisibilityZones asks this
-- question four times a second on every client, so walking Workspace per call is
-- not on. Re-reading every few seconds costs nothing and avoids caching "there
-- is no vault" forever.
local VAULT_CACHE_TTL = 3

local vaultCache: VaultVolume? = nil
local vaultCacheAt = -math.huge

-- The vault's oriented box, or nil if neither the chamber nor its anchor exists
-- yet. Public so callers can ask where the vault is instead of restating
-- coordinates that this module would then have to keep them in sync with.
function HorrorZones.vaultVolume(): VaultVolume?
	local now = os.clock()
	if now - vaultCacheAt < VAULT_CACHE_TTL then
		return vaultCache
	end
	vaultCacheAt = now

	local resolved: VaultVolume? = nil
	local chamber = Workspace:FindFirstChild("VaultChamber")
	if chamber and chamber:IsA("Model") then
		-- GetBoundingBox hands back the box in the model's own orientation, which
		-- is the reason to use it over a min/max sweep: a chamber turned in Studio
		-- keeps a tight box instead of growing an axis-aligned one whose corners
		-- reach into whatever it was turned away from.
		local cframe, size = chamber:GetBoundingBox()
		resolved = { cframe = cframe, size = size }
	else
		local anchor = Workspace:FindFirstChild("VaultAnchor")
		if anchor and anchor:IsA("BasePart") then
			resolved = {
				cframe = anchor.CFrame * CFrame.new(ANCHOR_SHELL_CENTRE),
				size = ANCHOR_SHELL_SIZE,
			}
		end
	end

	vaultCache = resolved
	return resolved
end

--[[
	Inside the chamber's box, walls included.

	Tested in the box's local space rather than against world min/max so that a
	rotated chamber is still tested against the chamber, not against the larger
	square it happens to sit in.

	No outward slack here, unlike the guest rooms. Those are separate floor parts
	with gaps between them and a stud of slack closes the gaps; this is one
	enclosing shell whose box already reaches a stud past the inner wall faces, so
	padding it would start claiming the far side of a 2-stud wall — the approach
	corridor — as vault.
]]
function HorrorZones.isInVault(position: Vector3): boolean
	local volume = HorrorZones.vaultVolume()
	if not volume then
		return false
	end
	local offset = volume.cframe:PointToObjectSpace(position)
	local half = volume.size / 2
	return math.abs(offset.X) <= half.X and math.abs(offset.Y) <= half.Y and math.abs(offset.Z) <= half.Z
end

-- Guest rooms -----------------------------------------------------------------

--[[
	Guest rooms are not a container you can walk the parent chain to find.
	`HotelWing.Lights` is one flat folder of 41 identical `LightPanel` parts
	covering the corridors and the rooms they open onto alike, so a fixture's
	ancestry says nothing about which side of a door it is on — which is exactly
	why the guest rooms were being lit at the corridor's brightness.

	The rooms are floored by `HotelWing.Rooms.Floor_R*` parts, though, and those
	footprints are what the walls were built around. Standing over one is a
	reliable test, and it keeps working when a room is re-dressed or its fixtures
	are renamed.
]]
local ROOM_CEILING_HEIGHT = 22
local ROOM_FOOTPRINT_SLACK = 1
-- Geometry does not move at runtime, but it does replicate late; re-reading it
-- occasionally costs nothing and avoids caching an empty list forever.
local FLOOR_CACHE_TTL = 3

local floorCache: { BasePart } = {}
local floorCacheAt = -math.huge

local function guestRoomFloors(): { BasePart }
	local now = os.clock()
	if now - floorCacheAt < FLOOR_CACHE_TTL then
		return floorCache
	end
	floorCacheAt = now

	local found: { BasePart } = {}
	local wing = Workspace:FindFirstChild("HotelWing")
	local rooms = wing and wing:FindFirstChild("Rooms")
	if rooms then
		for _, child in rooms:GetChildren() do
			if child:IsA("BasePart") and string.sub(child.Name, 1, 6) == "Floor_" then
				table.insert(found, child)
			end
		end
	end
	floorCache = found
	return found
end

function HorrorZones.isInGuestRoom(position: Vector3): boolean
	for _, floor in guestRoomFloors() do
		local half = floor.Size / 2
		local centre = floor.Position
		if
			position.X >= centre.X - half.X - ROOM_FOOTPRINT_SLACK
			and position.X <= centre.X + half.X + ROOM_FOOTPRINT_SLACK
			and position.Z >= centre.Z - half.Z - ROOM_FOOTPRINT_SLACK
			and position.Z <= centre.Z + half.Z + ROOM_FOOTPRINT_SLACK
			and position.Y >= centre.Y - 2
			and position.Y <= centre.Y + ROOM_CEILING_HEIGHT
		then
			return true
		end
	end
	return false
end

--[[
	Room 1, the onboarding room, which is a volume rather than a footprint.

	Unlike the other guest rooms its floor is not a `Floor_R*` part, so there is
	nothing to stand on and test for. It is also the one room the game asks a
	question about that has to be exactly right: IntroSealService slams the door
	and starts the whole opening beat the instant a player is judged to be
	inside it, so a box that is roughly the room is not good enough here — too
	small and the beat never fires, too large and it fires in the corridor with
	the door open.

	So the room is a part in the place, `Room1Zone`, and this reads its box the
	same way the vault reads its chamber's: authored where it can be seen,
	dragged and resized in Studio, and never restated as coordinates in a file
	that would go stale the first time somebody moved a wall.
]]
local ROOM_ONE_ZONE = "Room1Zone"
-- Same bargain as the vault and the guest-room floors: cheap to re-read, and
-- caching "there is no zone" forever would be worse than the lookup.
local ROOM_ONE_CACHE_TTL = 3

local roomOneCache: BasePart? = nil
local roomOneCacheAt = -math.huge
local warnedAboutZone = false

local function roomOneZone(): BasePart?
	local now = os.clock()
	if now - roomOneCacheAt < ROOM_ONE_CACHE_TTL then
		return roomOneCache
	end
	roomOneCacheAt = now

	local wing = Workspace:FindFirstChild("HotelWing")
	local rooms = wing and wing:FindFirstChild("Rooms")
	local found = rooms and rooms:FindFirstChild(ROOM_ONE_ZONE)
	if not found then
		found = Workspace:FindFirstChild(ROOM_ONE_ZONE, true)
	end
	roomOneCache = if found and found:IsA("BasePart") then found else nil
	return roomOneCache
end

--[[
	The approximation, used only when the zone part is missing.

	It works the way this function used to work in full: the room begins on the
	door's forward side and fills the bay behind it. That is honest about the
	direction and wrong about the extent — the bay is not centred on its own
	doorway, so this claims some space north of the room and misses the south
	half of it. Kept because a place whose Room1Zone has not replicated (or has
	been deleted) should still light room 1 roughly right rather than treat it
	as corridor; it is not good enough to seal a door on, which is why
	IntroSealService asks for the zone itself.
]]
local function inRoomOneByDoor(position: Vector3): boolean
	local wing = Workspace:FindFirstChild("HotelWing")
	local doors = wing and wing:FindFirstChild("Doors")
	local door = doors and doors:FindFirstChild("Room1Door")
	if not door or not door:IsA("Model") then
		return false
	end

	local doorCFrame = door:GetBoundingBox()
	local offset = position - doorCFrame.Position
	local depth = offset:Dot(doorCFrame.LookVector)
	local sideways = math.abs(offset:Dot(doorCFrame.RightVector))
	return depth >= 0
		and depth <= 58
		and sideways <= 12.5
		and position.Y >= doorCFrame.Position.Y - 6
		and position.Y <= doorCFrame.Position.Y + 11
end

-- True when the zone part exists, so callers that must not act on the
-- approximation above can say so rather than guessing.
function HorrorZones.roomOneZoneExists(): boolean
	return roomOneZone() ~= nil
end

function HorrorZones.isInRoomOne(position: Vector3): boolean
	local zone = roomOneZone()
	if not zone then
		if not warnedAboutZone then
			warnedAboutZone = true
			warn(`[HorrorZones] no {ROOM_ONE_ZONE} part found; room 1 falls back to its door's bay`)
		end
		return inRoomOneByDoor(position)
	end

	-- Tested in the part's own space, so a zone turned to follow a re-angled
	-- room stays tight to the room instead of growing the square it sits in.
	local offset = zone.CFrame:PointToObjectSpace(position)
	local half = zone.Size / 2
	return math.abs(offset.X) <= half.X and math.abs(offset.Y) <= half.Y and math.abs(offset.Z) <= half.Z
end

-- True once the room geometry this module classifies against has replicated.
-- Callers that classify at startup use it to know whether a "corridor" answer
-- is real or just early.
function HorrorZones.roomsReady(): boolean
	return #guestRoomFloors() > 0
end

return HorrorZones
