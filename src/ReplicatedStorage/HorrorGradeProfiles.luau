--!strict
--[[
	The two grades the hotel is lit with.

	HorrorLighting applies `Dark` on the server at startup; HorrorVisibilityZones
	tweens the local player between `Dark` and `Lobby` as they walk in and out of
	the entrance hall. They used to hold private copies of the same eight numbers,
	so darkening the hotel in one file left the lobby exit tweening back to a
	"dark" that no longer existed. Both now read from here.

	Each profile is split the way TweenService wants it — one table of Lighting
	properties, one of ColorCorrectionEffect properties — so callers can hand
	either straight to `TweenService:Create` without unpacking.
]]

local Profiles = {}

export type Profile = {
	lighting: { [string]: any },
	grade: { [string]: any },
}

--[[
	The hotel proper: corridors, guest rooms, amenities, stairwells.

	Ambient is the number that decides whether this is a horror game. It is the
	light that arrives on a surface with no fixture pointing at it, so the higher
	it goes the more of a room is legible from anywhere and the less the torch
	matters. Keeping it low is what makes the fixtures — and the flashlight — the
	things that actually shape a room.

	Low, though, not absent. This sat at (2,2,4) with exposure at -0.95 and the
	fog closing at 58 studs, and that was a mistake worth keeping written down:
	the darkening here compounds with three other cuts that all landed at once —
	the fixture profiles in LightFlicker, the range caps that stop light crossing
	a wall, and the lobby-zone fix that stopped two whole floors borrowing the
	bright profile by accident. Any one of those is a large change on its own.
	Stacked, they multiplied out to a screen with a chandelier on it and nothing
	else, which is not scary, just blind.

	The zone fix is what does the real work here — the amenities floor and the
	guest corridor used to run at ambient (48,42,36) and exposure +0.55, so
	simply putting them on this profile at all is most of the drop. These numbers
	only have to finish the job.
]]
Profiles.Dark = {
	lighting = {
		Ambient = Color3.fromRGB(7, 8, 12),
		OutdoorAmbient = Color3.fromRGB(10, 12, 18),
		ExposureCompensation = -0.45,
		FogStart = 14,
		FogEnd = 110,
	},
	grade = {
		Brightness = -0.04,
		Contrast = 0.22,
		Saturation = -0.3,
		TintColor = Color3.fromRGB(184, 198, 220),
	},
} :: Profile

--[[
	The entrance hall, and the one place that is meant to be readable.

	It is where you arrive, check in, and pick a class, and none of that should
	need a torch held up to a sign. Warm and lifted, but the fog still closes in
	well before the far wall and the saturation is still pulled down, so it reads
	as a lit room at night rather than as daylight.

	The gap between the two profiles is deliberately large — larger than it was —
	because the hotel around it is now much darker, and the lobby has to feel like
	relief to be worth having.
]]
Profiles.Lobby = {
	lighting = {
		Ambient = Color3.fromRGB(46, 40, 34),
		OutdoorAmbient = Color3.fromRGB(33, 34, 40),
		ExposureCompensation = 0.8,
		FogStart = 26,
		FogEnd = 185,
	},
	grade = {
		Brightness = 0.05,
		Contrast = 0.06,
		Saturation = -0.14,
		TintColor = Color3.fromRGB(226, 214, 196),
	},
} :: Profile

--[[
	The vault sublevel, which is not the hotel and is not lit like it.

	Everything above is tuned around a torch being the only meaningful light. The
	vault is the opposite case: a sealed strongroom on its own security circuit,
	160 studs below the building, that the whole clue hunt exists to reach. Run
	the Dark profile down there and the payoff arrives as a black screen with a
	keypad glow on it.

	So this is lit — brighter than the lobby, even — but deliberately not
	welcoming. Cold blue-grey ambient instead of the lobby's warm amber, contrast
	held high and saturation pulled further down than anywhere else, so it reads
	as fluorescent strip light in a concrete box rather than as somewhere safe.
	The fog is pushed out past the chamber's 90-stud span so the far wall is
	visible: this is the one room in the game meant to be taken in at a glance.
]]
Profiles.Vault = {
	lighting = {
		Ambient = Color3.fromRGB(54, 60, 70),
		OutdoorAmbient = Color3.fromRGB(54, 60, 70),
		ExposureCompensation = 0.35,
		FogStart = 40,
		FogEnd = 240,
	},
	grade = {
		Brightness = 0.02,
		Contrast = 0.14,
		Saturation = -0.42,
		TintColor = Color3.fromRGB(206, 216, 230),
	},
} :: Profile

return Profiles
