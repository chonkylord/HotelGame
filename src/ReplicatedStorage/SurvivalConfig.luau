--!strict
-- Shared tuning for the survival HUD: hearts, hunger, and sprint.
--
-- SurvivalService is the authority and SurvivalClient only draws, but both read
-- these numbers so the meter on screen is always scaled against the same values
-- the server is enforcing. Retune here and both sides follow.

local SurvivalConfig = {}

-- Health ---------------------------------------------------------------------
-- MaxHealth becomes Hearts * HealthPerHeart (8 * 10 = 80). Hearts render as a
-- partial fill, so a heart worth 10 HP still shows halves and quarters.
SurvivalConfig.Hearts = 8
SurvivalConfig.HealthPerHeart = 10

SurvivalConfig.HeartImage = "rbxassetid://80314405017101"

-- Meter icons, drawn to match the skull: black outline, white fill, grey depth.
-- The white fill is what lets the HUD tint each one with ImageColor3 while the
-- outline stays black.
SurvivalConfig.HungerIcon = "rbxassetid://107513953544773"
SurvivalConfig.SprintIcon = "rbxassetid://101757406436076"

-- Hunger ---------------------------------------------------------------------
SurvivalConfig.MaxHunger = 100
SurvivalConfig.HungerOnSpawn = 100
-- The meter is drawn as this many discrete cells. It lives here rather than in
-- SurvivalClient because food is balanced in whole bars — "this restores one
-- bar" only means something if both the HUD and the server agree what a bar is.
SurvivalConfig.HungerSegments = 16
-- Full to empty in ten minutes of ordinary walking around the hotel.
SurvivalConfig.HungerDrainPerSecond = 100 / 600
-- Sprinting burns through it noticeably faster, which is what stops sprint from
-- being free once food is on the map.
SurvivalConfig.SprintHungerMultiplier = 2.5
-- Set above 0 to make an empty stomach chip away at health. Off by default:
-- running out only costs speed and the ability to sprint.
SurvivalConfig.StarveDamagePerSecond = 0

-- Movement -------------------------------------------------------------------
-- 12 rather than the Roblox default 16, because the body animation has to be
-- able to keep up with it. A character is about five studs tall against a 1.7m
-- human, so a stud is roughly a third of a metre and 16 studs/sec works out at
-- ~19.6 km/h — a flat sprint. No walk cycle can cover that without either
-- skating or spinning up into a scurry, which is why the stock Animate script
-- gives up and plays the *run* clip at 1.25x from the moment you touch W.
-- At 12 the walk clip carries ordinary movement and sprinting still reads as a
-- clear gear change. See LocomotionConfig for the curve this feeds.
SurvivalConfig.BaseWalkSpeed = 12
SurvivalConfig.SprintWalkSpeed = 24
-- Above this much hunger you move at full speed; below it you slow off
-- gradually rather than falling off a cliff at some threshold.
SurvivalConfig.HungerComfort = 70
-- Speed multiplier at zero hunger — 0.7 of 16 is a shade over 11, slow enough
-- to feel bad without making the walk back to food a chore.
SurvivalConfig.MinSpeedScale = 0.7

-- Sprint ---------------------------------------------------------------------
SurvivalConfig.SprintSeconds = 6
-- A touch under nine seconds from empty back to full.
SurvivalConfig.SprintRegenPerSecond = 0.7
-- Beat of nothing after you let go of shift before the bar starts refilling.
SurvivalConfig.SprintRegenDelay = 1
-- Run the bar all the way down and sprint locks out until it has recovered this
-- fraction, so you cannot stutter-tap shift at zero for free bursts.
SurvivalConfig.SprintRecoveryFraction = 0.25

-- Networking -----------------------------------------------------------------
SurvivalConfig.RemotesFolder = "SurvivalRemotes"
SurvivalConfig.StatsEvent = "SurvivalStats"
SurvivalConfig.SprintEvent = "SurvivalSprint"
-- The simulation steps every frame; only the screen update is rate limited.
SurvivalConfig.BroadcastInterval = 1 / 10

-- Food -----------------------------------------------------------------------
-- Tag an instance "Food" and the server binds it: a Tool is eaten on activate,
-- a Part or Model gets a ClickDetector. Attributes tune each one.
SurvivalConfig.FoodTag = "Food"
-- World food is eaten by clicking it, not by a proximity prompt, so this is how
-- far away a player can still click one. Clicking already needs line of sight
-- and an aimed cursor, so this can be more generous than a prompt radius.
SurvivalConfig.FoodClickReach = 14
SurvivalConfig.FoodAttributes = {
	Hunger = "HungerRestore", -- hunger points returned (default: a third of the meter)
	Health = "HealthRestore", -- HP returned (default 0)
	Stamina = "StaminaRestore", -- seconds of sprint returned, for energy drinks (default 0)
	Uses = "FoodUses", -- servings before the item is spent (default 1)
	Action = "FoodAction", -- verb for the item, e.g. "Eat"/"Drink" (default "Eat")
	Respawn = "FoodRespawn", -- seconds until a world item returns (default 0 = gone for good)
}
SurvivalConfig.DefaultHungerRestore = 100 / 3

-- Derived helpers ------------------------------------------------------------

function SurvivalConfig.maxHealth(): number
	return SurvivalConfig.Hearts * SurvivalConfig.HealthPerHeart
end

-- Hunger worth exactly one cell on the meter, so a snack can be specified as
-- "one bar" and land on a cell boundary instead of somewhere between two.
function SurvivalConfig.hungerPerSegment(): number
	return SurvivalConfig.MaxHunger / SurvivalConfig.HungerSegments
end

-- How much of your speed hunger is letting you keep, 0..1. Flat at 1 while well
-- fed, then a straight line down to MinSpeedScale at an empty meter.
function SurvivalConfig.hungerSpeedScale(hunger: number): number
	local comfort = SurvivalConfig.HungerComfort
	if hunger >= comfort or comfort <= 0 then
		return 1
	end
	local t = math.clamp(hunger / comfort, 0, 1)
	return SurvivalConfig.MinSpeedScale + (1 - SurvivalConfig.MinSpeedScale) * t
end

function SurvivalConfig.walkSpeedFor(hunger: number, sprinting: boolean): number
	local base = if sprinting then SurvivalConfig.SprintWalkSpeed else SurvivalConfig.BaseWalkSpeed
	return base * SurvivalConfig.hungerSpeedScale(hunger)
end

-- Infinite sprint is a server-authorised override. Keeping the eligibility
-- rule pure makes it possible to pin the important edge cases in a spec while
-- SurvivalService remains the only code that reads the admin attribute.
function SurvivalConfig.sprintAllowed(
	hunger: number,
	stamina: number,
	exhausted: boolean,
	infiniteSprint: boolean
): boolean
	return infiniteSprint or (hunger > 0 and stamina > 0 and not exhausted)
end

function SurvivalConfig.speedHunger(hunger: number, sprinting: boolean, infiniteSprint: boolean): number
	return if sprinting and infiniteSprint then SurvivalConfig.MaxHunger else hunger
end

return SurvivalConfig
