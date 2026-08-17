--[[
	The flashlight's beam shape, and the click that turns it on.

	The world is deliberately underexposed — HorrorLighting puts Ambient at
	(4,5,9) and ExposureCompensation at -0.82 — so this is the primary light
	source in the hotel and its shape is a balance question, not a decorative
	one. Too wide and the darkness stops mattering.

	This used to raise every light to a *floor*: Brightness >= 5, Range >= 46,
	Angle >= 72. The floors were the whole problem. The model is authored as a
	tight 24-degree core sitting inside a soft 44-degree surround, which is a
	good torch; forcing both cones up to 72 degrees threw that away and left a
	120-stud flood that lit entire rooms from the doorway. Whole corridors read
	at a glance, the fixture flicker stopped meaning anything, and there was no
	reason to ever walk into a dark room carefully.

	So the beam is now set outright rather than floored, and the authored cone
	angles are honoured instead of overridden. It comes out at roughly a third
	of the old brightness in a third of the old cone: you can see clearly where
	you point it, and almost nothing where you do not.
]]

--[[
	Keyed by the light's own name. Three lights, three jobs — they are not
	interchangeable, which is exactly why a single blanket rule was wrong.
]]
--[[
	Three cones, wide-and-short stacked under narrow-and-long.

	The first pass at this made all three narrow, and it broke the torch at close
	range: a 24-degree cone thrown 100 studs is a big bright circle on a far
	wall, but only a few studs across at your feet. Walking up a staircase, the
	steps are close and low and simply fell outside every cone, so the light
	appeared to work only when there was distant geometry to land on.

	Reach and coverage are separate jobs and need separate lights. The core keeps
	the long throw. The surround is now genuinely wide but deliberately
	short-ranged, so it fills in stairs, doorframes and anything else within a
	few strides without reaching far enough to flood a room from the doorway —
	which was the original complaint and still has to stay fixed.
]]
--[[
	Raised once more, after the suite floor turned out to be unplayable.

	The suite floor is the darkest room in the game and nothing above was tuned
	against it: its fixtures take LightFlicker's GUEST_ROOM profile (the dimmest
	of the five) on top of the Dark grade's (7,8,12) ambient, so unlike a
	corridor there is essentially no light in the room to supplement the torch.
	Everywhere else the beam is *aimed*; there, it is the only light there is.

	So the surround takes the biggest lift — it is what shows you the floor, the
	furniture beside you and the doorway you are about to walk into, and that
	near-field blindness was the actual complaint. The core is widened rather
	than mainly brightened, because a 26-degree cone means turning your whole
	body to sweep a room.

	This deliberately stops short of the flood documented above: at 34 degrees
	and 100 studs the core is still less than half the 72-degree, 120-stud cone
	that once let you read a whole corridor from the doorway, and the surround
	still dies at 32 studs so it cannot light a room you are not standing in.
]]
local BEAM = {
	-- The throw. Narrow and long: this is the bit you aim down a corridor, and
	-- the only one that should reach any distance. It keeps its shadows, and
	-- LightFlicker gives up the ceiling candles' shadows so that it can.
	Light = { Brightness = 6.2, Range = 100, Angle = 34, Shadows = true },

	-- The surround, and the fix for close geometry. Wide enough to cover what is
	-- under and beside you, cut short so the width costs nothing at distance —
	-- still short enough that it cannot read a guest room from its doorway, but
	-- no longer so dim that an unlit suite reads as a black screen.
	Shadow = { Brightness = 3.4, Range = 32, Angle = 74, Shadows = true },

	--[[
		The lens itself, so the torch looks lit in your hands rather than being an
		invisible emitter — and so the step directly under your feet is lit at all.

		This one gives its shadows up. At a 100-degree spread it is the widest
		light on the tool and the most expensive to shadow, and the thing it
		exists to light is six studs away in your own hands. Being shadowless
		means it leaks through whatever you are standing on, so its range is cut
		to less than a floor's thickness to keep that leak inside the room.
	]]
	SurfaceLight = { Brightness = 1.6, Range = 10, Angle = 100, Shadows = false },
}

-- Any light added to the model later lands here rather than keeping whatever it
-- was authored with, so a stray addition cannot quietly undo the tuning.
local FALLBACK = { Brightness = 0.6, Range = 10, Angle = 60, Shadows = false }

local BEAM_COLOUR = Color3.fromRGB(220, 231, 255)

--[[
	Shadows stay on for the two cones that reach. They are not free, but a torch
	that casts no shadow bleeds straight through the hotel's thin interior walls
	and lights the room next door, which looks worse than it costs — and in a
	hotel this dark, a beam that ignores walls is the difference between a horror
	game and a lit one.
]]
for _, descendant in script.Parent:GetDescendants() do
	if descendant:IsA("Light") then
		local tuning = BEAM[descendant.Name] or FALLBACK
		descendant.Brightness = tuning.Brightness
		descendant.Range = tuning.Range
		descendant.Color = BEAM_COLOUR
		descendant.Shadows = tuning.Shadows
		-- PointLight is the one Light class with no cone.
		if descendant:IsA("SpotLight") or descendant:IsA("SurfaceLight") then
			descendant.Angle = tuning.Angle
		end
	end
end

local on = false

script.Parent.Activated:Connect(function()
	on = not on
	script.Parent.Light.Shadow.Enabled = on
	script.Parent.Light.Light.Enabled = on
	script.Parent.Front.SurfaceLight.Enabled = on
	if on then
		script.Parent.Light.Sound:Play()
	else
		script.Parent.Light.Sound2:Play()
	end
end)
