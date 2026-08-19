--!strict
--[[
	Every fixed light in the hotel: how dim it sits, how far it reaches, and how
	it fails.

	Purely cosmetic and entirely client-side: it costs the server nothing and
	never replicates. Despite that, every player sees the *same* flicker at the
	same moment, because the schedule is not random — it is a hash of each
	light's name and the shared clock (Workspace:GetServerTimeNow()). Two players
	in the same corridor watch the same tube die at the same instant, which is
	the whole point in a horror game, and it costs no network traffic to do.

	The rhythm is deliberately not a gentle pulse. A light sits steady for
	several seconds, then either strobes violently for up to a second or drops
	out completely and struggles back. During the dark phase the light is fully
	off, not dimmed, and any Neon bulb it hangs on goes dark with it so the
	fixture does not stay glowing over an unlit room.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local HorrorZones = require(ReplicatedStorage:WaitForChild("HorrorZones"))
local OnboardingConfig = require(ReplicatedStorage:WaitForChild("OnboardingConfig"))

local player = Players.LocalPlayer

-- Fixture profiles ------------------------------------------------------------

--[[
	Steady-state dimming, applied to each fixture's authored Brightness.

	These are the numbers that decide how dark the hotel is when nothing is
	flickering, which is most of the time — a fit lasts about a second and the
	quiet between them runs to eight. So the *unflickering* look is the look, and
	it wants to be uncomfortable rather than merely atmospheric.

	`range` matters as much as `brightness` and used to be left alone, which was
	a mistake worth naming. Almost every fixture in this place is authored
	without shadows (44 of 44 in the guest wing, 22 of 24 on the amenities
	floor), and a shadowless light does not stop at a wall — it fills a sphere of
	its Range regardless of what is in the way. Corridor panels authored at Range
	26 hang about 8 studs under the ceiling, so they were pushing light up
	through the floor above and down into the rooms below, and a "dark" room lit
	by four neighbours it cannot see is the reason the hotel read as evenly lit
	however far the brightness came down. Capping the reach is what turns a
	fixture back into a pool of light with an edge.
]]
--[[
	`ceiling` is the safety net under `brightness`, and it exists because scaling
	alone quietly trusts whatever the fixture was authored with. The switchable
	light kit drives its lamp from a `LightBrightness` value of 20 — an order of
	magnitude above the 1.9 the hotel's own fixtures use — so scaling alone left
	it many times brighter than the corridor it stands in, waiting for someone to
	hit the switch and blow a hole in the grade.

	A room's light budget is a property of the room, not of whatever free model
	happens to be bolted to its wall. The ceilings below sit just above what the
	place's own fixtures reach, so they never touch a normally-authored light and
	catch anything absurd.
]]
type Profile = {
	brightness: number, -- multiplier on the authored Brightness
	ceiling: number, -- absolute cap, whatever the fixture was authored at
	range: number, -- hard cap on studs, so a shadowless light stays in its room
	quietMin: number, -- seconds of uneasy light between fits
	quietMax: number,
	burstMin: number, -- how long a fit lasts
	burstMax: number,
	burstChance: number, -- rare quiet windows keep the rhythm unpredictable
	dropoutChance: number, -- how often a fit becomes a hard blackout
	surge: number, -- sickly over-bright kick on the way back
	shadowChance: number, -- selective occlusion detail without shadowing every bulb
}

--[[
	Corridors are the default: navigable, not readable. You can tell a doorway
	from a wall and nothing else, and the torch is still worth holding up.
]]
local CORRIDOR: Profile = {
	brightness = 0.4,
	ceiling = 1.0,
	range = 20,
	quietMin = 2.5,
	quietMax = 8.0,
	burstMin = 0.45,
	burstMax = 1.55,
	burstChance = 0.88,
	dropoutChance = 0.52,
	surge = 1.5,
	shadowChance = 0.18,
}

--[[
	Guest rooms are the darkest thing in the hotel and the point of the whole
	grade: you open a door onto black and have to walk in with the torch to find
	out what is in there. Their panels are authored at the same 2.2 as the
	corridor's, so without a profile of their own they lit identically — which is
	exactly how they ended up brighter than the lobby.
]]
local GUEST_ROOM: Profile = {
	-- An eight-percent lift: enough to keep furniture edges alive between torch
	-- passes, not enough to make a suite readable from its doorway.
	brightness = 0.24,
	ceiling = 0.74,
	range = 17,
	quietMin = 3.0,
	quietMax = 9.0,
	burstMin = 0.45,
	burstMax = 1.55,
	burstChance = 0.9,
	dropoutChance = 0.6,
	surge = 1.5,
	shadowChance = 0.32,
}

--[[
	Chandeliers, ceiling candles, and every fixture owned by the amenities floor
	are the primary navigation lights there. They still twitch, but rarely and
	without turning the whole restaurant/ballroom into a repeated blackout, and
	they are authored dim to begin with (0.99 average) so they take a gentler cut.
]]
local GENTLE: Profile = {
	brightness = 0.6,
	ceiling = 1.4,
	range = 24,
	quietMin = 18,
	quietMax = 42,
	burstMin = 0.12,
	burstMax = 0.38,
	burstChance = 0.28,
	dropoutChance = 0.06,
	surge = 1.12,
	shadowChance = 0.12,
}

--[[
	The lobby is the one room meant to be read without a torch. Its chandeliers
	and lamps carry that on their own rather than leaning on the ambient lift in
	HorrorVisibilityZones, so the light has shape and direction instead of the
	flat wash you get from raising ambient alone. It flickers least of anywhere:
	the lobby is where you arrive and where you pick a class, and a fixture
	dropping out mid-decision reads as broken rather than as atmosphere.
]]
local LOBBY: Profile = {
	brightness = 0.85,
	ceiling = 1.9,
	range = 30,
	quietMin = 14,
	quietMax = 34,
	burstMin = 0.18,
	burstMax = 0.5,
	burstChance = 0.34,
	dropoutChance = 0.08,
	surge = 1.15,
	shadowChance = 0.18,
}

-- Room 1 is the player's first destination and keeps the fixture values that
-- were authored in Studio. It is deliberately stable as well as bright: this
-- onboarding space should never lose its light while a new player is learning
-- the keypad and room controls.
local ROOM_ONE: Profile = {
	brightness = 1,
	ceiling = math.huge,
	range = math.huge,
	quietMin = 60,
	quietMax = 60,
	burstMin = 0,
	burstMax = 0,
	burstChance = 0,
	dropoutChance = 0,
	surge = 1,
	shadowChance = 0,
}

--[[
	Every fixture in the building, for as long as the first stay lasts.

	The grade half of the intro lives in HorrorGradeProfiles.Calm, and on its own
	it is not enough: ambient decides how much of a room is legible with no
	fixture pointing at it, but the fixtures are still the thing you actually
	look at, and a corridor whose panels keep dropping out is not "normal
	lighting" however high the ambient goes. A tube dying over Noel's desk while
	a new player reads their room code is the single most horror-coded thing in
	the place, and it fires on a 2.5-to-8-second cycle.

	So this profile is the fixtures switched on and left alone: what the place
	authored, at the reach it authored, with the fit chance at zero. The ceiling
	stays — it is the guard against the switchable-light kit's Brightness of 20,
	which is absurd under any grade — and so does a range cap generous enough
	that no hotel fixture meets it, because a shadowless panel reaching 26 studs
	still lights the floor below through the ceiling.
]]
local CALM: Profile = {
	brightness = 1,
	ceiling = 3,
	range = 34,
	quietMin = 60,
	quietMax = 60,
	burstMin = 0,
	burstMax = 0,
	burstChance = 0,
	dropoutChance = 0,
	surge = 1,
	shadowChance = 0.2,
}

local STROBE_STEP = 0.05 -- how fast the strobe stutters

--[[
	Shadow-casting lights share a fixed budget, and the 48 ceiling candles were
	spending most of it: every one of them was authored `Shadows = true` at a
	Range of 3 to 5 studs, where the shadow it casts is smaller than the fixture
	and nobody has ever seen it. Meanwhile the flashlight — the one light in the
	place that genuinely needs to be stopped by a wall — is competing for what is
	left. Tiny fixtures give their shadows up so the torch keeps its.
]]
local SHADOW_WORTH_CASTING_RANGE = 8

type BulbState = {
	part: BasePart,
	material: Enum.Material,
	colour: Color3,
	darkCount: number,
}

--[[
	Reach is half of what a profile controls, and `Range` is awkward to get at:
	it is declared on PointLight, SpotLight and SurfaceLight individually rather
	than on the abstract `Light` they share, and a union of the three is not
	something Luau will read a property off. `track` rejects any light that is
	not one of those three, so this is the one place the assumption can fail and
	the one place it is checked.
]]
type Ranged = { Range: number }

local function ranged(light: Light): Ranged
	return light :: any
end

type LightState = {
	light: Light,
	anchor: BasePart,
	seed: number,
	bulb: BulbState?,
	profile: Profile,
	-- What the place authored, kept so the profile can be re-applied without
	-- compounding, and so a late re-classification starts from the right number.
	authoredBrightness: number,
	authoredRange: number,
	baseBrightness: number,
	maxBrightness: number,
	maxRange: number,
	authoredShadows: boolean,
	baseEnabled: boolean,
	dark: boolean,
	active: boolean, -- true while this script is driving the light
	-- cached window, recomputed only when the slot rolls over
	slot: number,
	burstStart: number,
	burstEnd: number,
	dropout: boolean,
	period: number,
}

local states: { [Light]: LightState } = {}
local bulbs: { [BasePart]: BulbState } = {}

-- Deterministic noise ---------------------------------------------------------
-- Same inputs give the same answer on every machine, which is what keeps the
-- clients in step without a single RemoteEvent.

local function hashString(text: string): number
	local h = 2166136261
	for index = 1, #text do
		h = bit32.bxor(h, string.byte(text, index))
		h = (h * 16777619) % 4294967296
	end
	return h % 1048576
end

-- Names are not unique enough to seed from: the place has 193 lights but only
-- 55 distinct full names, and all 48 ceiling candles share one. Seeding off the
-- name alone made whole rooms blink in lockstep. Position is the discriminator —
-- lights in the same fixture still share a seed, which is what you want, but
-- separate fixtures get their own rhythm.
local function seedFor(light: Light, parent: BasePart): number
	local p = parent.Position
	return hashString(
		string.format("%s|%d|%d|%d", light.Name, math.floor(p.X * 4), math.floor(p.Y * 4), math.floor(p.Z * 4))
	)
end

local function noise(seed: number, salt: number): number
	local x = (seed * 374761393 + salt * 668265263) % 2147483647
	x = bit32.bxor(x, bit32.rshift(x, 13))
	x = (x * 1274126177) % 2147483647
	x = bit32.bxor(x, bit32.rshift(x, 16))
	return (x % 1000003) / 1000003
end

-- Classification --------------------------------------------------------------

local function isPortableLight(light: Light): boolean
	local node: Instance? = light
	while node and node ~= Workspace do
		if node:IsA("Tool") then
			return true
		end
		node = node.Parent
	end
	return false
end

--[[
	The class podiums light themselves and are left entirely alone — not dimmed
	either, which is why this is checked before a profile is chosen rather than
	folded in as another one.

	They are a menu, not a room. A player standing there is reading three labels
	and picking between them, and a fixture that keeps dropping out mid-decision
	reads as the podium being broken rather than as atmosphere.
]]
local function isSelectionPodium(light: Light): boolean
	local node: Instance? = light
	while node and node ~= Workspace do
		if node.Name == "ClassPodiums" then
			return true
		end
		node = node.Parent
	end
	return false
end

local function ancestorMatches(light: Light, predicate: (string, Instance) -> boolean): boolean
	local node: Instance? = light
	while node and node ~= Workspace do
		if predicate(string.lower(node.Name), node) then
			return true
		end
		node = node.Parent
	end
	return false
end

local function isGentleFixture(light: Light): boolean
	return ancestorMatches(light, function(lowered, node)
		return node.Name == "AmenitiesFloorBlueprint"
			or string.find(lowered, "chandelier", 1, true) ~= nil
			or string.find(lowered, "ceiling candle", 1, true) ~= nil
	end)
end

local function isNamedGuestRoomFixture(light: Light): boolean
	return ancestorMatches(light, function(lowered, node)
		return node.Name == "SuiteFloor"
			or string.find(lowered, "room floor", 1, true) ~= nil
			or string.find(lowered, "guestroom", 1, true) ~= nil
	end)
end

local function isLobbyFixture(light: Light): boolean
	return ancestorMatches(light, function(_, node)
		return HorrorZones.isLobbyGeometry(node)
	end)
end

local function introActive(): boolean
	return OnboardingConfig.isIntroStage(player:GetAttribute(OnboardingConfig.ATTRIBUTE))
end

--[[
	Order matters. The intro wins over everything, including the lobby: it is not
	a room, it is the whole building told to behave for two minutes. After that
	the lobby wins outright — it is the one lit room and nothing else should be
	able to dim it. The amenities floor is checked before the guest-room
	footprint test because its lounge sits directly above part of the wing and
	would otherwise inherit the darkest profile in the hotel.
]]
local function profileFor(light: Light, anchor: BasePart): Profile
	if introActive() then
		return CALM
	end
	if isLobbyFixture(light) then
		return LOBBY
	end
	if HorrorZones.isInRoomOne(anchor.Position) then
		return ROOM_ONE
	end
	if isGentleFixture(light) then
		return GENTLE
	end
	if isNamedGuestRoomFixture(light) or HorrorZones.isInGuestRoom(anchor.Position) then
		return GUEST_ROOM
	end
	return CORRIDOR
end

-- Discovery -------------------------------------------------------------------

local function bulbFor(part: BasePart): BulbState?
	-- Only Neon fixtures are touched. Dimming arbitrary geometry would risk
	-- recolouring something that is not a bulb at all.
	if part.Material ~= Enum.Material.Neon then
		return nil
	end
	local existing = bulbs[part]
	if existing then
		return existing
	end
	local created: BulbState = {
		part = part,
		material = part.Material,
		colour = part.Color,
		darkCount = 0,
	}
	bulbs[part] = created
	return created
end

-- Idempotent: always derived from the authored values, never from whatever the
-- light happens to be showing, so it is safe to call again after the geometry
-- this classifies against has finished replicating.
local function applyProfile(state: LightState)
	local light = state.light
	if state.profile == ROOM_ONE then
		light.Brightness = state.authoredBrightness
		ranged(light).Range = state.authoredRange
		light.Shadows = state.authoredShadows
		state.baseBrightness = state.authoredBrightness
		state.maxBrightness = state.authoredBrightness
		state.maxRange = state.authoredRange
		return
	end

	local dimmed = math.min(state.authoredBrightness * state.profile.brightness, state.profile.ceiling)
	local reach = math.min(state.authoredRange, state.profile.range)

	light.Brightness = dimmed
	ranged(light).Range = reach
	-- A few long-range practicals cast real occlusion, chosen deterministically
	-- so each room keeps the same shadow composition for every player. Small
	-- decorative lights still surrender the shared shadow budget.
	light.Shadows = reach > SHADOW_WORTH_CASTING_RANGE and noise(state.seed, 97) < state.profile.shadowChance

	state.baseBrightness = dimmed
	state.maxBrightness = dimmed
	state.maxRange = reach
end

local function track(instance: Instance)
	if not instance:IsA("Light") or states[instance] then
		return
	end
	-- The only three light classes that carry a Range, which every fixture here
	-- is and which `ranged` above relies on.
	if not (instance:IsA("PointLight") or instance:IsA("SpotLight") or instance:IsA("SurfaceLight")) then
		return
	end
	local parent = instance.Parent
	if not parent or not parent:IsA("BasePart") then
		return
	end
	if isPortableLight(instance) then
		return
	end
	if isSelectionPodium(instance) then
		return
	end

	local state: LightState = {
		light = instance,
		anchor = parent,
		seed = seedFor(instance, parent),
		bulb = bulbFor(parent),
		profile = profileFor(instance, parent),
		authoredBrightness = instance.Brightness,
		authoredRange = ranged(instance).Range,
		baseBrightness = instance.Brightness,
		maxBrightness = instance.Brightness,
		maxRange = ranged(instance).Range,
		authoredShadows = instance.Shadows,
		baseEnabled = instance.Enabled,
		dark = false,
		active = false,
		slot = -1,
		burstStart = 0,
		burstEnd = 0,
		dropout = false,
		period = 0,
	}
	state.period = state.profile.quietMin
	applyProfile(state)
	states[instance] = state
end

local function untrack(instance: Instance)
	if instance:IsA("Light") then
		states[instance] = nil
	end
end

for _, descendant in Workspace:GetDescendants() do
	track(descendant)
end
Workspace.DescendantAdded:Connect(track)
Workspace.DescendantRemoving:Connect(untrack)

--[[
	Guest rooms are identified by standing over a `HotelWing.Rooms.Floor_R*`
	footprint, and on a slow join that folder can still be replicating when the
	pass above runs. A fixture classified before its floor arrived would be stuck
	on the corridor profile for the whole session — three times too bright, in
	the one place that most needs to be dark. Re-running the classification once
	the geometry is there costs a single pass and cannot compound, because
	applyProfile always works from the authored values.
]]
--[[
	Re-decides every fixture's profile and puts the new one on.

	Safe to run at any point and any number of times, because applyProfile always
	works from the authored values rather than from whatever the light is
	currently showing, so nothing it does compounds. Clearing `slot` is what
	makes the change take immediately: the drive loop recomputes this light's
	flicker window on the next Heartbeat and, for a profile that never bursts,
	releases it back to steady in the same pass.
]]
local function reclassify(): number
	local changed = 0
	for _, state in states do
		local wanted = profileFor(state.light, state.anchor)
		if wanted ~= state.profile then
			state.profile = wanted
			state.slot = -1
			applyProfile(state)
			changed += 1
		end
	end
	return changed
end

task.spawn(function()
	local deadline = os.clock() + 20
	while not HorrorZones.roomsReady() and os.clock() < deadline do
		task.wait(0.5)
	end
	if not HorrorZones.roomsReady() then
		warn("[LightFlicker] guest-room geometry never replicated; rooms keep the corridor profile")
		return
	end
	print(string.format("[LightFlicker] re-classified %d fixture(s) once room geometry arrived", reclassify()))
end)

-- The first stay ending is the whole hotel changing profile at once — every
-- fixture drops off CALM and back onto the room it hangs in, which is the
-- lights failing for the first time.
player:GetAttributeChangedSignal(OnboardingConfig.ATTRIBUTE):Connect(function()
	print(string.format("[LightFlicker] re-classified %d fixture(s) for the onboarding stage", reclassify()))
end)

-- Bulbs are shared: a fixture holding three lights only relights once all three
-- are back on.
local function setBulbDark(bulb: BulbState, dark: boolean)
	local before = bulb.darkCount
	bulb.darkCount = math.max(0, before + (if dark then 1 else -1))
	if before == 0 and bulb.darkCount > 0 then
		bulb.part.Material = Enum.Material.SmoothPlastic
		bulb.part.Color = bulb.colour:Lerp(Color3.new(), 0.78)
	elseif before > 0 and bulb.darkCount == 0 then
		bulb.part.Material = bulb.material
		bulb.part.Color = bulb.colour
	end
end

local function setDark(state: LightState, dark: boolean)
	if state.dark == dark then
		return
	end
	state.dark = dark
	state.light.Enabled = if dark then false else state.baseEnabled
	if state.bulb then
		setBulbDark(state.bulb, dark)
	end
end

-- Put the light back exactly as it was found, so nothing this script does can
-- accumulate — in particular the surge must never become the new baseline.
local function release(state: LightState)
	setDark(state, false)
	state.light.Enabled = state.baseEnabled
	state.light.Brightness = state.baseBrightness
	state.active = false
end

-- Drive -----------------------------------------------------------------------

RunService.Heartbeat:Connect(function()
	local now = Workspace:GetServerTimeNow()

	for light, state in states do
		if not light.Parent then
			states[light] = nil
			continue
		end

		local profile = state.profile

		-- Roll the window forward. Slot length varies per light, so the hotel
		-- never falls into a shared rhythm.
		local period = state.period
		local slot = math.floor(now / period)
		if slot ~= state.slot then
			state.slot = slot
			state.period = profile.quietMin + noise(state.seed, 1) * (profile.quietMax - profile.quietMin)

			if noise(state.seed, slot * 3 + 2) < profile.burstChance then
				local length = profile.burstMin
					+ noise(state.seed, slot * 3 + 3) * (profile.burstMax - profile.burstMin)
				local start = slot * period + noise(state.seed, slot * 3 + 4) * math.max(period - length, 0)
				state.burstStart = start
				state.burstEnd = start + length
				state.dropout = noise(state.seed, slot * 3 + 5) < profile.dropoutChance
			else
				state.burstStart = 0
				state.burstEnd = 0
			end
		end

		if now < state.burstStart or now >= state.burstEnd then
			if state.active then
				release(state)
			else
				-- Steady: re-read the authored values, so a light switched off
				-- elsewhere stays off instead of being flicked back on.
				state.baseEnabled = light.Enabled
				state.baseBrightness = math.min(light.Brightness, state.maxBrightness)
				if light.Brightness > state.maxBrightness then
					light.Brightness = state.maxBrightness
				end
				-- Reach is held to the cap the same way brightness is. The
				-- switchable-light models write Brightness and Range back from
				-- their own configuration values, and a fixture that keeps its
				-- dimming but recovers its 26-stud reach is still lighting the
				-- floor above through the ceiling.
				local reach = ranged(light)
				if reach.Range > state.maxRange then
					reach.Range = state.maxRange
				end
			end
			continue
		end

		if not state.baseEnabled then
			continue -- switched off by something else; leave it alone
		end
		state.active = true

		local elapsed = now - state.burstStart
		local length = state.burstEnd - state.burstStart
		local progress = elapsed / length
		local dark: boolean

		if state.dropout then
			-- Gone, then a couple of failed restarts before it holds.
			dark = progress < 0.72 or (progress < 0.88 and noise(state.seed, math.floor(elapsed / 0.09)) < 0.5)
		else
			-- Violent strobe that settles as it runs out.
			local step = math.floor(elapsed / STROBE_STEP)
			local threshold = 0.62 - progress * 0.45 -- biased to ON near the end
			dark = noise(state.seed, slot * 7919 + step) > threshold
		end

		setDark(state, dark)

		if not dark then
			local wanted = state.baseBrightness * (if progress > 0.6 then profile.surge else 1)
			if light.Brightness ~= wanted then
				light.Brightness = wanted
			end
		end
	end
end)
