--!strict
-- Shared contract for Superman's Room 2 fate roulette. The server owns the
-- result and effect attributes; the client reads this module to draw the same
-- eight faces in the same order that the server rolls.

local RouletteConfig = {}

RouletteConfig.TableTag = "RouletteTable"
RouletteConfig.PromptTag = "RoulettePrompt"
RouletteConfig.UnlockedAttribute = "RouletteUnlocked"
RouletteConfig.BedLiftedAttribute = "RouletteBedLifted"

RouletteConfig.RemotesFolder = "RouletteRemotes"
RouletteConfig.OpenEvent = "RouletteOpen"
RouletteConfig.SpinEvent = "RouletteSpin"
RouletteConfig.ResultEvent = "RouletteResult"

RouletteConfig.CooldownSeconds = 4 * 60
RouletteConfig.EffectDurationSeconds = RouletteConfig.CooldownSeconds
RouletteConfig.InteractionDistance = 12

RouletteConfig.NextRollAttribute = "RouletteNextRollAt"
RouletteConfig.EffectIdAttribute = "RouletteEffectId"
RouletteConfig.EffectExpiresAttribute = "RouletteEffectExpiresAt"
RouletteConfig.SpeedMultiplierAttribute = "RouletteSpeedMultiplier"
RouletteConfig.HealthMultiplierAttribute = "RouletteHealthMultiplier"
RouletteConfig.JumpMultiplierAttribute = "RouletteJumpMultiplier"
RouletteConfig.RegenAttribute = "RouletteRegenPerSecond"

export type Outcome = {
	id: string,
	name: string,
	shortLabel: string,
	description: string,
	good: boolean,
	color: Color3,
	speedMultiplier: number?,
	healthMultiplier: number?,
	jumpMultiplier: number?,
	regenPerSecond: number?,
}

local outcomes: { Outcome } = {
	{
		id = "MetropolisRush",
		name = "Metropolis Rush",
		shortLabel = "2x SPEED",
		description = "Move at twice your normal speed.",
		good = true,
		color = Color3.fromRGB(48, 151, 184),
		speedMultiplier = 2,
	},
	{
		id = "ManOfSteel",
		name = "Man of Steel",
		shortLabel = "2x HEALTH",
		description = "Double your maximum health.",
		good = true,
		color = Color3.fromRGB(211, 166, 63),
		healthMultiplier = 2,
	},
	{
		id = "UpUpAndAway",
		name = "Up, Up & Away",
		shortLabel = "2x JUMP",
		description = "Jump twice as high until fate resets.",
		good = true,
		color = Color3.fromRGB(72, 111, 183),
		jumpMultiplier = 2,
	},
	{
		id = "SolarRenewal",
		name = "Solar Renewal",
		shortLabel = "REGEN",
		description = "Regenerate six health every second.",
		good = true,
		color = Color3.fromRGB(208, 116, 48),
		regenPerSecond = 6,
	},
	{
		id = "HeroicSurge",
		name = "Heroic Surge",
		shortLabel = "ALL STATS",
		description = "Gain 1.35x speed, jump, and maximum health.",
		good = true,
		color = Color3.fromRGB(64, 145, 112),
		speedMultiplier = 1.35,
		healthMultiplier = 1.35,
		jumpMultiplier = 1.35,
	},
	{
		id = "KryptoniteDrag",
		name = "Kryptonite Drag",
		shortLabel = "0.5x SPEED",
		description = "Your movement speed is cut in half.",
		good = false,
		color = Color3.fromRGB(84, 132, 66),
		speedMultiplier = 0.5,
	},
	{
		id = "LeadBoots",
		name = "Lead Boots",
		shortLabel = "0.5x JUMP",
		description = "Your jump height is cut in half.",
		good = false,
		color = Color3.fromRGB(116, 82, 112),
		jumpMultiplier = 0.5,
	},
	{
		id = "MortalFrame",
		name = "Mortal Frame",
		shortLabel = "0.5x HEALTH",
		description = "Your maximum health is cut in half.",
		good = false,
		color = Color3.fromRGB(151, 57, 47),
		healthMultiplier = 0.5,
	},
}

RouletteConfig.Outcomes = outcomes

function RouletteConfig.findOutcome(id: string): Outcome?
	for _, outcome in outcomes do
		if outcome.id == id then
			return outcome
		end
	end
	return nil
end

function RouletteConfig.remaining(now: number, readyAt: number): number
	return math.max(0, readyAt - now)
end

return RouletteConfig
