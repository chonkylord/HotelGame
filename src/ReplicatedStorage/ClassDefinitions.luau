--!strict

-- Shared class identifiers, settings, and entitlement helpers. Every server
-- and client system reads the same definitions from this module.
local ClassDefinitions = {}

ClassDefinitions.NONE = "None"
ClassDefinitions.MUSCLE = "Muscle"
ClassDefinitions.HACKER = "Hacker"
ClassDefinitions.SUPERMAN = "Superman"
ClassDefinitions.SUPERHERO = ClassDefinitions.SUPERMAN
ClassDefinitions.ATTRIBUTE = "Class"
ClassDefinitions.ADMIN_ALL_CLASSES_ATTRIBUTE = "AdminAllClasses"

local playableClasses: { [string]: boolean } = {
	[ClassDefinitions.MUSCLE] = true,
	[ClassDefinitions.HACKER] = true,
	[ClassDefinitions.SUPERMAN] = true,
}

local function canonicalClass(className: string): string
	-- The podium/team is historically named SuperHero while the selected-class
	-- value is Superman. Accept either spelling at an entitlement boundary.
	return if className == "SuperHero" then ClassDefinitions.SUPERMAN else className
end

-- Tests whether a player is entitled to a class without changing their actual
-- podium selection. AdminAllClasses is an overlay: turning it off immediately
-- exposes the unchanged Class attribute again.
function ClassDefinitions.hasClass(subject: Instance, className: string): boolean
	local wanted = canonicalClass(className)
	local selected = subject:GetAttribute(ClassDefinitions.ATTRIBUTE)
	if typeof(selected) == "string" and canonicalClass(selected) == wanted then
		return true
	end
	return subject:GetAttribute(ClassDefinitions.ADMIN_ALL_CLASSES_ATTRIBUTE) == true
		and playableClasses[wanted] == true
end

ClassDefinitions.SMASH_PROMPT_TAG = "SmashPrompt"
ClassDefinitions.HACK_PROMPT_TAG = "HackPrompt"
ClassDefinitions.BED_LIFT_PROMPT_TAG = "BedLiftPrompt"

local podiumClass: { [string]: string } = {
	MUSCLE = ClassDefinitions.MUSCLE,
	HACKER = ClassDefinitions.HACKER,
	SUPERMAN = ClassDefinitions.SUPERMAN,
	SUPERHERO = ClassDefinitions.SUPERMAN,
}
ClassDefinitions.PodiumClass = podiumClass

local muscleScale: { [string]: number } = {
	BodyWidthScale = 1.30,
	BodyDepthScale = 1.25,
	BodyHeightScale = 1.05,
	HeadScale = 0.95,
}
ClassDefinitions.MuscleScale = muscleScale

local smashableStates: { [string]: boolean } = {
	Normal = false,
	Broken = true,
	Jammed = true,
	Smashed = false,
}
ClassDefinitions.SmashableStates = smashableStates

local hackableStates: { [string]: boolean } = {
	Broken = true,
}
ClassDefinitions.HackableStates = hackableStates

ClassDefinitions.HACK_HOLD = 5
ClassDefinitions.HACK_DISTANCE = 10

ClassDefinitions.HACKER_GEAR_TAG = "HackerGear"
ClassDefinitions.HACKER_LENS_TAG = "HackerLens"
ClassDefinitions.SUPERMAN_GEAR_TAG = "SupermanGear"

ClassDefinitions.HackerGlyphs = "0123456789ABCDEF<>[]{}/\\|_=+*$#@%&"
ClassDefinitions.HackerWords = { "SYS", "ROOT", "0x", "RUN", "ACK", "NUL", "REQ", "0b", "PWN", "SEG" }

return ClassDefinitions
