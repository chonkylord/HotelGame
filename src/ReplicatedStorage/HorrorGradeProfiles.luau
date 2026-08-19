--!strict
--[[
	The grades the hotel is lit with.

	HorrorLighting applies `Dark` on the server at startup; HorrorVisibilityZones
	tweens the local player between them as they walk from space to space. They
	used to hold private copies of the same eight numbers, so darkening the hotel
	in one file left the lobby exit tweening back to a "dark" that no longer
	existed. Both now read from here.

	Each profile is split the way TweenService wants it — one table of Lighting
	properties, one of ColorCorrectionEffect properties, one of Atmosphere
	properties — so callers can hand any of them straight to
	`TweenService:Create` without unpacking.

	EVERY PROFILE MUST DEFINE EVERY KEY, and HorrorGradeProfilesSpec fails the
	build if one does not. A profile that leaves a property out does not restore
	it, it inherits whatever the profile before it set: the moment `Calm` lifted
	Brightness and the fog, a `Dark` that did not restate them would have tweened
	back to a "dark" that stayed lit — the same bug this file was written to end,
	one property deeper.
]]

local Profiles = {}

export type Profile = {
	lighting: { [string]: any },
	grade: { [string]: any },
	atmosphere: { [string]: any },
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
		-- The four below are the night itself rather than the room: the moon and
		-- nothing else, and an environment map dark enough that no surface is lit
		-- by the sky. Restated in every profile because `Calm` lifts all of them.
		Brightness = 1,
		EnvironmentDiffuseScale = 0.08,
		EnvironmentSpecularScale = 0.09,
		ColorShift_Top = Color3.fromRGB(3, 6, 12),
	},
	grade = {
		Brightness = -0.04,
		Contrast = 0.22,
		Saturation = -0.3,
		TintColor = Color3.fromRGB(184, 198, 220),
	},
	-- The corridor haze. Cold, thick, and the reason a long hall disappears
	-- rather than staying evenly readable to its far end.
	atmosphere = {
		Density = 0.28,
		Offset = 0.08,
		Color = Color3.fromRGB(70, 79, 98),
		Decay = Color3.fromRGB(10, 13, 22),
		Glare = 0,
		Haze = 1.9,
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
		-- Restated here so leaving Calm restores the night; see the header.
		Brightness = 1,
		EnvironmentDiffuseScale = 0.08,
		EnvironmentSpecularScale = 0.09,
		ColorShift_Top = Color3.fromRGB(3, 6, 12),
	},
	grade = {
		Brightness = 0.05,
		Contrast = 0.06,
		Saturation = -0.14,
		TintColor = Color3.fromRGB(226, 214, 196),
	},
	-- The corridor haze. Cold, thick, and the reason a long hall disappears
	-- rather than staying evenly readable to its far end.
	atmosphere = {
		Density = 0.28,
		Offset = 0.08,
		Color = Color3.fromRGB(70, 79, 98),
		Decay = Color3.fromRGB(10, 13, 22),
		Glare = 0,
		Haze = 1.9,
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
		-- Restated here so leaving Calm restores the night; see the header.
		Brightness = 1,
		EnvironmentDiffuseScale = 0.08,
		EnvironmentSpecularScale = 0.09,
		ColorShift_Top = Color3.fromRGB(3, 6, 12),
	},
	grade = {
		Brightness = 0.02,
		Contrast = 0.14,
		Saturation = -0.42,
		TintColor = Color3.fromRGB(206, 216, 230),
	},
	-- The corridor haze. Cold, thick, and the reason a long hall disappears
	-- rather than staying evenly readable to its far end.
	atmosphere = {
		Density = 0.28,
		Offset = 0.08,
		Color = Color3.fromRGB(70, 79, 98),
		Decay = Color3.fromRGB(10, 13, 22),
		Glare = 0,
		Haze = 1.9,
	},
} :: Profile

--[[
	The hotel before it is a horror game, and the only profile the player is
	meant to be able to read the place in.

	It runs for the whole of the first stay — Noel's desk, the lift, the walk
	down the guest corridor, the sealed room — and then never again. That is the
	point of it: the intro asks a brand-new player to find a receptionist, punch
	a code into a keypad and read an arrow off the floor, and every one of those
	is a chore in a corridor lit at ambient (7,8,12). Worse, it spends the scare.
	A hotel that was frightening from the loading screen has nowhere to go when
	the notice goes up; one that was ordinary for two minutes first does.

	So this is not "the lobby, everywhere". The lobby profile is warm, amber and
	still visibly night — relief inside a horror game. This is the horror game
	switched off: neutral colour, no crushed blacks, the fog pushed past any
	distance the building spans, and enough ambient that a room is lit whether or
	not a fixture points at it. The gap between it and Dark is meant to be the
	largest in the file, because the player crosses it once, in one cut, and that
	cut is the moment the game starts.
]]
Profiles.Calm = {
	lighting = {
		-- Ambient does the work. Raising Brightness instead would light the place
		-- through its windows, and the fiction is still a hotel at night.
		Ambient = Color3.fromRGB(104, 101, 96),
		OutdoorAmbient = Color3.fromRGB(112, 116, 126),
		ExposureCompensation = 0.15,
		-- Past the longest sightline in the building, so nothing fades out.
		FogStart = 90,
		FogEnd = 900,
		Brightness = 1.4,
		EnvironmentDiffuseScale = 0.4,
		EnvironmentSpecularScale = 0.25,
		ColorShift_Top = Color3.fromRGB(28, 32, 40),
	},
	-- Neutral on purpose: every other profile in this file pulls saturation down
	-- and pushes contrast up, and the absence of that is most of what makes this
	-- one read as an ordinary building rather than a graded one.
	grade = {
		Brightness = 0,
		Contrast = 0.02,
		Saturation = 0,
		TintColor = Color3.fromRGB(252, 250, 246),
	},
	atmosphere = {
		Density = 0.1,
		Offset = 0,
		Color = Color3.fromRGB(190, 198, 210),
		Decay = Color3.fromRGB(96, 104, 118),
		Glare = 0,
		Haze = 0.35,
	},
} :: Profile

return Profiles
