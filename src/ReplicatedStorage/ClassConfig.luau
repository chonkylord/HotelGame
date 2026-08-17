--!strict
--[[
	Shared class definitions.

	Three podiums stand in the lobby (Workspace.ClassPodiums) — MUSCLE, HACKER
	and SUPERMAN. Stepping on an available podium claims its class, which the
	server stamps on the Player object as an attribute so both sides can read it
	and only the server can write it. Each player and each class may be claimed
	only once per server.

	Superman's exclusive interaction is the Room 2 fate roulette. The old
	SUPERHERO key remains as an alias so older place copies and saved tooling do
	not silently stop recognising the third podium.
]]

local ClassConfig = {}

ClassConfig.NONE = "None"
ClassConfig.MUSCLE = "Muscle"
ClassConfig.HACKER = "Hacker"
ClassConfig.SUPERMAN = "Superman"
ClassConfig.SUPERHERO = ClassConfig.SUPERMAN

-- Stamped on the Player, not the character, so it survives respawns.
ClassConfig.ATTRIBUTE = "Class"
ClassConfig.ADMIN_ALL_CLASSES_ATTRIBUTE = "AdminAllClasses"

local playableClasses: { [string]: boolean } = {
	[ClassConfig.MUSCLE] = true,
	[ClassConfig.HACKER] = true,
	[ClassConfig.SUPERMAN] = true,
}

local function canonicalClass(className: string): string
	return if className == "SuperHero" then ClassConfig.SUPERMAN else className
end

-- AdminAllClasses overlays the selected class rather than replacing it. This
-- keeps the podium claim intact and makes disabling the toggle restore the
-- player's ordinary entitlement immediately.
function ClassConfig.hasClass(subject: Instance, className: string): boolean
	local wanted = canonicalClass(className)
	local selected = subject:GetAttribute(ClassConfig.ATTRIBUTE)
	if typeof(selected) == "string" and canonicalClass(selected) == wanted then
		return true
	end
	return subject:GetAttribute(ClassConfig.ADMIN_ALL_CLASSES_ATTRIBUTE) == true and playableClasses[wanted] == true
end

--[[
	Tag on every smash prompt.

	A ProximityPrompt is either on or off for everyone, so the prompt is created
	disabled and ClassClient switches it on locally for players who are actually
	Muscle. That is presentation only — a client that turns one on for itself
	still gets refused by the server, which re-checks the class when the prompt
	fires.
]]
ClassConfig.SMASH_PROMPT_TAG = "SmashPrompt"

-- Podium folder name in Workspace.ClassPodiums -> class it grants.
local podiumClass: { [string]: string } = {
	MUSCLE = ClassConfig.MUSCLE,
	HACKER = ClassConfig.HACKER,
	SUPERMAN = ClassConfig.SUPERMAN,
	SUPERHERO = ClassConfig.SUPERMAN,
}
ClassConfig.PodiumClass = podiumClass

--[[
	The Muscle build.

	These are the individual body-part assets out of the catalog bundle, read
	once with AvatarEditorService:GetItemDetails and written down here rather
	than resolved at run time. The bundle does not change, and a web call on
	every spawn is a web call that can fail on every spawn — a player who
	respawns mid-round should not be able to lose their build to a timeout.

	Only these parts are copied onto a player. Shirt, pants, face, accessories
	and body colours stay theirs: the class changes what they are built like,
	not what they are wearing.
]]
--[[
	The Muscle build: the stock blocky body, scaled. Deliberately not a bundle.

	Every muscular body bundle on the catalog works by replacing the player's
	body parts with meshes, and that broke three things at once here. Measured,
	not assumed — each of these came off rigs built with
	Players:CreateHumanoidModelFromDescription:

	  Clothing. Classic Shirt and Pants are drawn onto Roblox's own body parts.
	  Swap in a UGC mesh body and there is nothing for them to draw on, so the
	  player loses their outfit the instant they pick the class.

	  The flashlight. Body-part meshes carry their own RightGripAttachment, and
	  the bundle's was authored backwards — grip forward (0, +1, 0) against the
	  stock (0, -1, 0), an exact 180-degree flip. The tool is fine; the hand was
	  holding it back to front, which is why the beam pointed at the player.

	  The hands. Buff Blocky (2286) and Muscular Robloxian (256402830761479)
	  both shrank the hand about 20% below stock (0.80 and 0.77 wide against
	  0.98) while inflating the chest. That is invisible in a catalog thumbnail
	  and is most of the screen in a first-person game.

	Scaling the stock body avoids all three: the parts stay the ones Roblox
	draws clothing on, the hand keeps the grip attachment every tool in the
	place was authored against, and the silhouette stays blocky and R6-ish
	rather than turning anatomical.

	These are MULTIPLIERS on what the player already is, not absolute sizes, so
	someone playing a short or wide avatar still reads as themselves.
]]
local muscleScale: { [string]: number } = {
	BodyWidthScale = 1.30,
	BodyDepthScale = 1.25,
	BodyHeightScale = 1.05,
	-- A head that does not grow with the shoulders is what sells the bulk;
	-- scale it with them and you get a giant instead of a heavy.
	HeadScale = 0.95,
}
ClassConfig.MuscleScale = muscleScale

--[[
	Which door states a Muscle player can put a shoulder through.

	Only doors whose own mechanism has already failed. Normal locked doors still
	belong to the code hunt; Muscle is the answer to a physically jammed leaf or
	a dead/broken lock, not a universal room key.
]]
local smashableStates: { [string]: boolean } = {
	Normal = false,
	Broken = true,
	Jammed = true,
	Smashed = false,
}
ClassConfig.SmashableStates = smashableStates

--[[
	Tag on every hack prompt. Same trick as SMASH_PROMPT_TAG, same caveat: the
	client switching one on is presentation, and the server re-checks the class
	when it fires.
]]
ClassConfig.HACK_PROMPT_TAG = "HackPrompt"

-- The Room 2 bed can only be lifted by Muscle. As with every class prompt,
-- this tag controls local visibility while the server owns permission.
ClassConfig.BED_LIFT_PROMPT_TAG = "BedLiftPrompt"

--[[
	Which door states a Hacker can talk their way through.

	Broken only, and that is the whole design. A broken door is the one whose
	keypad is still bolted to the wall, still powered, and reading ERROR — there
	is a machine there to be argued with. Jammed doors had their keypad torn off,
	so there is nothing to hack; those stay Muscle's problem, which is what keeps
	the two classes from being the same key with different names.

	Normal doors are deliberately absent. Those already open to anyone holding
	the code, and letting a Hacker skip that would delete the code hunt from the
	game rather than add to it.
]]
local hackableStates: { [string]: boolean } = {
	Broken = true,
}
ClassConfig.HackableStates = hackableStates

--[[
	How long E is held to force a bypass, and from how far.

	Five seconds is the whole point of the class rather than a number to tune
	casually. The Hacker is pinned in place and facing a wall for every one of
	them — see the freeze in HotelDoorService — so this is the window in which
	Joel gets a free approach on someone who cannot run. Shorten it and the class
	stops costing anything; lengthen it and no door is ever worth opening.
]]
ClassConfig.HACK_HOLD = 5
ClassConfig.HACK_DISTANCE = 10

--[[
	Tags on the two pieces of Hacker kit, so the client can find them without
	knowing how the character is put together. The visor's lens is tagged
	separately because it is the one part with anything to animate.
]]
ClassConfig.HACKER_GEAR_TAG = "HackerGear"
ClassConfig.HACKER_LENS_TAG = "HackerLens"
ClassConfig.SUPERMAN_GEAR_TAG = "SupermanGear"

--[[
	The glyphs the visor scrolls.

	Deliberately not real code. At visor size it is three or four characters of
	legible text and the rest is texture, so what sells it is the SHAPE of the
	line — mixed hex, brackets, and the odd word — rather than anything that
	would survive being read. Kept here so the look can be retuned without
	touching the animation.
]]
ClassConfig.HackerGlyphs = "0123456789ABCDEF<>[]{}/\\|_=+*$#@%&"
ClassConfig.HackerWords = { "SYS", "ROOT", "0x", "RUN", "ACK", "NUL", "REQ", "0b", "PWN", "SEG" }

return ClassConfig
