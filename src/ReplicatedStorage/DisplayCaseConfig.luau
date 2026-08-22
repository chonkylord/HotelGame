--!strict
--[[
	Shared tuning for the treasury's display cases and the mallet that opens them.

	The four vitrines are authored geometry, not generated: each is a Model under
	Workspace.BankVault.TreasuryCollection.DisplayCases holding one opaque Base
	and five Glass_n panes, tagged with the two tags below. Nothing in code
	builds them, which is deliberate — the vault itself is baked into the place
	(see BankVaultBuilder's stand-down comment) and a case that only existed for
	the life of a server could not be selected, moved, or restyled in Studio.

	Tags rather than names or paths are the binding, so a case duplicated in
	Studio keeps working and a pane deleted simply stops being breakable.

	Nothing on the client reads this yet — the mallet is a plain Tool and the
	server does every check — but the numbers live in ReplicatedStorage so a
	future crosshair or HUD hint can be scaled against the same reach the server
	is enforcing.
]]

local DisplayCaseConfig = {}

-- Instances -------------------------------------------------------------------

DisplayCaseConfig.CaseTag = "VaultDisplayCase"
DisplayCaseConfig.GlassTag = "BreakableGlass"

-- Set on a pane the moment it shatters and on a case the moment any of its
-- glass goes. Both are re-entry guards first and state second: a second swing
-- landing on the same vitrine must not spawn a second cloud of shards.
DisplayCaseConfig.PaneBrokenAttribute = "GlassBroken"
DisplayCaseConfig.CaseOpenedAttribute = "CaseOpened"

-- ServerStorage BindableEvent, fired (player, pane, impactPosition). It is the
-- whole seam between the two services: MalletService decides that a swing
-- connected, DisplayCaseService decides what a hit on a vitrine means. Same
-- shape as ClueService -> SackService's consume event.
DisplayCaseConfig.StruckEvent = "GlassStruck"

DisplayCaseConfig.MalletName = "Mallet"
DisplayCaseConfig.PropFolderName = "PlacedTools"

-- Set on an exhibit to say whose it is. Absent on ordinary treasure, which
-- anybody may take once the glass is gone.
--
-- The two gates are deliberately separate. The mallet decides who can OPEN a
-- case; this decides who can take what is inside it. So the Sun Sword needs a
-- Muscle to break the glass and a Superman to lift it, which is a two-class
-- handshake rather than a lock one player can pick alone.
--
-- Read with ClassDefinitions.hasClass, so the value is a class name and the
-- same string works for the sack's own gate.
DisplayCaseConfig.ExhibitClassAttribute = "ExhibitClass"

-- The class gate is not named here. MalletService and SackService both decide
-- it with ClassDefinitions.hasClass, and repeating the string "Muscle" in a
-- second module is how the two ends of one rule drift apart.

-- Remote for the refusal notice. Server -> client only, carrying the part to
-- hang the plaque on and which of the lines below to engrave on it. There is no
-- client -> server direction: pressing E is a ProximityPrompt, which the engine
-- already replicates, and the entitlement is decided on the server either way.
DisplayCaseConfig.RemotesFolder = "MalletRemotes"
DisplayCaseConfig.RefusalEvent = "MalletRefused"

-- Which restaurant cover the mallet is left on. Named rather than random: a
-- tool you need to finish the vault has to be in the same place every round.
-- Falls back to any DiningSet in the restaurant if this one is ever renamed.
DisplayCaseConfig.MalletTableName = "DiningSet6"

-- Interaction -----------------------------------------------------------------

DisplayCaseConfig.PromptDistance = 9

-- One swing every three quarters of a second. Long enough that the shatter is
-- an event rather than a stutter of overlapping sounds.
DisplayCaseConfig.SwingCooldown = 0.75

-- Where the swing lands: a sphere this wide, this far in front of the chest.
-- A sphere rather than a ray because the server does not know where the camera
-- is pointing, and asking the client for an aim vector would mean trusting it.
-- The cases stand 19 studs apart, so there is never a question which one a
-- player standing in front of one meant to hit.
DisplayCaseConfig.SwingOffset = 2
DisplayCaseConfig.SwingReach = 4.2

-- Server re-check, measured to the nearest point on the pane rather than its
-- centre: a 5-stud sheet of glass is close when its edge is close.
DisplayCaseConfig.StrikeRange = 13

-- Shards ----------------------------------------------------------------------

-- Each pane is cut into a grid of roughly this many studs per piece, clamped to
-- at most 4 across either axis. A four-pane box plus its lid works out at about
-- 33 shards — enough to read as glass, few enough that a treasury full of
-- broken cases is not a physics bill.
DisplayCaseConfig.ShardTargetSize = 1.6
DisplayCaseConfig.ShardMaxPerAxis = 4

-- Fall, lie there a moment, fade out. The pause matters: shards that begin
-- fading the instant they land read as a particle effect, not as broken glass.
DisplayCaseConfig.ShardSettleSeconds = 1.6
DisplayCaseConfig.ShardFadeSeconds = 1.2

-- The refusal notice -----------------------------------------------------------

--[[
	What the plaque over the mallet says, and to whom.

	Written as hotel signage rather than as a game message, because that is what
	the round plaque is and this is the same object in the same voice — a brass
	notice screwed to something, not a system telling you your class is wrong.
	The header is spaced by hand for the same reason it is in RoundTimerClient:
	Roblox has no letter tracking and the engraved look lives in the gaps.
]]
export type Refusal = {
	header: string,
	line: string,
	accent: "warn" | "calm",
}

local REFUSALS: { [string]: Refusal } = {
	-- Anyone who is not Muscle.
	Class = {
		header = "— T O O   H E A V Y —",
		line = "Only thee who wield the might may lift it",
		accent = "warn",
	},
	-- Muscle, already carrying it. The prompt is still on the prop after a drop,
	-- so this is reachable, and a prompt that does nothing at all is worse than
	-- one that says why.
	Carrying = {
		header = "— A L R E A D Y   B O R N E —",
		line = "Thou hast the mallet upon thee",
		accent = "calm",
	},
	-- The wrong hands on a claimed exhibit. Worth its own line rather than
	-- reusing Class: that one is about a mallet too heavy to lift, and this is
	-- about a relic that has already chosen somebody else.
	--
	-- This is the fallback. An exhibit that names its own key below gets a line
	-- that says WHICH hands, because a refusal the player cannot learn from is
	-- just a locked door.
	Exhibit = {
		header = "— N O T   T H Y   R E L I C —",
		line = "The glass yields, but the prize knows its own",
		accent = "warn",
	},
	--[[
		One per relic, each naming its class by what that class DOES rather than
		by the word on the podium. "The cape", "the arm that breaks doors", "one
		who reads" are all unmistakable to a player who has picked a class and
		still read as the hotel talking rather than as a permissions error.
	]]
	SunSword = {
		header = "— N O T   T H Y   L I G H T —",
		line = "The sun lifts only for the guest in the cape",
		accent = "warn",
	},
	Ironhand = {
		header = "— A   D E A D   W E I G H T —",
		line = "It shuts for every hand but the one that breaks doors",
		accent = "warn",
	},
	MasterCipher = {
		header = "— O N L Y   N O I S E —",
		line = "The screen wakes for one who reads its tongue, no other",
		accent = "warn",
	},
}

DisplayCaseConfig.Refusals = REFUSALS

-- The keys above, named so the server cannot fire a reason the client has no
-- plaque for.
DisplayCaseConfig.RefusalClass = "Class"
DisplayCaseConfig.RefusalCarrying = "Carrying"
DisplayCaseConfig.RefusalExhibit = "Exhibit"

-- Optional per-exhibit override, naming one of the keys above. Absent, an
-- exhibit refuses with the generic Exhibit line.
DisplayCaseConfig.ExhibitRefusalAttribute = "ExhibitRefusal"

-- How long the notice hangs there before it fades.
DisplayCaseConfig.RefusalSeconds = 3.25
DisplayCaseConfig.RefusalFadeSeconds = 0.45

-- Audio -----------------------------------------------------------------------
-- All three are Pro Sound Effects library uploads, free and verified to load in
-- this place.

DisplayCaseConfig.SwingSoundId = "rbxassetid://9120972444" -- Wood Whoosh Quick Swing 1
DisplayCaseConfig.ShatterSoundId = "rbxassetid://9114592245" -- Glass Breaks 3
-- Layered a fifth of a second behind the break, quieter and pitched up: the
-- shards hitting the floor after the sheet goes.
DisplayCaseConfig.TinkleSoundId = "rbxassetid://9114591862" -- Glass Breaks 10
DisplayCaseConfig.TinkleDelay = 0.22

return DisplayCaseConfig
