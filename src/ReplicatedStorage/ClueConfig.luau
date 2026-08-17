--!strict
--[[
	Shared contract and authored content for the hotel's clue hunt. The server is
	the sole authority over the shuffled route and its answers, while clients and
	builders consume these names so replicated state and tagged props cannot drift
	into parallel dialects. Riddles remain fixed here because their quality depends
	on facts observable in this particular hotel; only their route changes.
]]

local ClueConfig = {}

-- Tags -----------------------------------------------------------------------

ClueConfig.SiteTag = "ClueSite"
ClueConfig.PromptTag = "CluePrompt"
ClueConfig.LeverTag = "ClueLever"
ClueConfig.CarryItemTag = "ClueCarryItem"
ClueConfig.ReceptacleTag = "ClueReceptacle"
ClueConfig.ExitDoorTag = "ClueExitDoor"

-- These belong to systems the clue builders integrate with. Keeping the names
-- here prevents a generated service lift, carry item, or exit door from becoming
-- an almost-correct prop that the owning service never discovers.
ClueConfig.HotelDoorTag = "HotelDoor"
ClueConfig.CollectableTag = "Collectable"
ClueConfig.ElevatorCabTag = "ElevatorCab"
ClueConfig.ElevatorArriveTag = "ElevatorArrive"

-- Attributes -----------------------------------------------------------------

ClueConfig.SiteIdAttribute = "SiteId"
ClueConfig.GeneratedSiteAttribute = "GeneratedClueSite"
ClueConfig.GeneratedVaultChamberAttribute = "GeneratedVaultChamber"
ClueConfig.GeneratedExitDoorAttribute = "GeneratedClueExitDoor"
ClueConfig.LeverIndexAttribute = "LeverIndex"
ClueConfig.CarryIdAttribute = "CarryId"
ClueConfig.NodeIndexAttribute = "NodeIndex"
ClueConfig.NodeKindAttribute = "NodeKind"
ClueConfig.VaultUnlockedAttribute = "VaultUnlocked"

--[[
	One relic per class, so the payday is not Superman's alone.

	The vault used to hold exactly one claimable -- the Sunstone -- which meant
	Muscle forced the road open and Hacker cracked the doors on the way, and then
	neither got anything out of the room they had opened. These two attributes are
	the other two halves, written on the Player by ClueService when a relic is
	claimed and read by HotelDoorService when it decides what a door will allow.

	Both upgrade a limit the class already lives with rather than granting
	something new, which keeps them legible: Muscle can already smash, Hacker can
	already bypass, and the relic widens what that works on.
]]
ClueConfig.MuscleRelicAttribute = "MuscleRelic"
ClueConfig.HackerRelicAttribute = "HackerRelic"

-- Worth of a single piece of treasure, summed out of a player's sack when they
-- escape. Set on the loot itself so value lives with the object, not in a table
-- that has to be kept in step with the model.
ClueConfig.LootValueAttribute = "LootValue"

-- Written on the Player at the moment they escape, so the HUD can show a haul
-- without the client needing to see inside anyone's sack.
ClueConfig.LootScoreAttribute = "LootScore"

ClueConfig.RoomLabelAttribute = "RoomLabel"
ClueConfig.DoorCodeAttribute = "Code"
ClueConfig.DoorStateAttribute = "State"
ClueConfig.ExitPromptAttribute = "ExitPrompt"
ClueConfig.CabIdAttribute = "CabId"
ClueConfig.PartnerAttribute = "Partner"

-- Replicated round state ------------------------------------------------------

ClueConfig.StateFolder = "ClueState"
ClueConfig.ChainLengthAttribute = "ChainLength"
ClueConfig.DigitsKnownAttribute = "DigitsKnown"
ClueConfig.PhaseAttribute = "Phase"
ClueConfig.ExitCodeKnownAttribute = "ExitCodeKnown"
ClueConfig.CurrentRiddleAttribute = "CurrentRiddle"
ClueConfig.EscapeEndsAtAttribute = "EscapeEndsAt"

ClueConfig.PhaseHunt = "Hunt"
ClueConfig.PhaseVault = "Vault"
ClueConfig.PhaseEscape = "Escape"
ClueConfig.PhaseWon = "Won"

-- Network and server-internal events -----------------------------------------

ClueConfig.RemotesFolder = "ClueRemotes"
ClueConfig.OpenEvent = "ClueOpen"
ClueConfig.SubmitEvent = "ClueSubmit"
ClueConfig.ResultEvent = "ClueResult"
ClueConfig.AnnounceEvent = "ClueAnnounce"

ClueConfig.JoelNoiseEvent = "JoelNoise"
ClueConfig.JoelDefeatEvent = "JoelDefeat"
ClueConfig.JoelReviveEvent = "JoelRevive"
ClueConfig.SackConsumeEvent = "ClueSackConsume"

-- Tuning ---------------------------------------------------------------------

ClueConfig.ChainLength = 5
-- The plan deliberately leaves the second code's length open. Matching the
-- vault code avoids adding a separate, unexplained difficulty knob.
ClueConfig.ExitCodeLength = ClueConfig.ChainLength
ClueConfig.InteractionDistance = 12
ClueConfig.WrongAnswerCooldown = 6
ClueConfig.LeverCount = 6
ClueConfig.LeverRequired = 3
ClueConfig.LeverLockoutSeconds = 6
ClueConfig.NoiseRadiusSolve = 45
ClueConfig.NoiseRadiusWrong = 80
ClueConfig.EscapeWindowSeconds = 120
ClueConfig.SupermanFallbackSeconds = 60
ClueConfig.MaxAnswerLength = 64

-- Authored clue content -------------------------------------------------------

export type NodeKind = "Note" | "Cipher" | "Lever" | "Search" | "Carry"

export type Site = {
	id: string,
	riddle: string,
	actOne: boolean,
	allowedKinds: { NodeKind },
}

export type Cipher = {
	question: string,
	answer: string,
}

local sites: { Site } = {
	{
		id = "ReceptionDesk",
		riddle = "Back to the desk. He is not there — he said he would be, but he said a lot of things.",
		actOne = true,
		allowedKinds = { "Note", "Cipher", "Carry" },
	},
	{
		id = "ClassPodiums",
		riddle = "Three plinths, three names, and only one of them ever wears a cape. Stand where nobody has claimed a body yet.",
		actOne = true,
		allowedKinds = { "Note", "Cipher" },
	},
	{
		id = "Room2Bed",
		riddle = "A bed too heavy for anyone but the strongest guest. Eight faces sleep beneath it — five kind, three cruel.",
		actOne = true,
		allowedKinds = { "Note", "Cipher", "Search", "Carry" },
	},
	{
		id = "StorageBreaker",
		riddle = "Past the crates nobody logged, a grey door hides the hotel's heartbeat. Six switches. Only some of them belong up.",
		actOne = true,
		allowedKinds = { "Lever" },
	},
	{
		id = "RestaurantBuffet",
		riddle = "Where the last supper is served and never runs out. Look behind the slatted screen.",
		actOne = true,
		allowedKinds = { "Note", "Cipher", "Search", "Carry" },
	},
	{
		id = "BallroomStage",
		riddle = "Two curtains, one platform, and an audience of empty chairs. Whatever they applauded, they left it up there.",
		actOne = true,
		allowedKinds = { "Note", "Cipher", "Search", "Carry" },
	},
	{
		id = "SuiteA_Midnight",
		riddle = "The first suite is named for an hour you are not expected to see.",
		actOne = true,
		allowedKinds = { "Note", "Cipher", "Carry" },
	},
	{
		id = "SuiteB_Garnet",
		riddle = "The second suite is named for a red stone. You will recognise the colour.",
		actOne = true,
		allowedKinds = { "Note", "Cipher", "Carry" },
	},
	{
		id = "SuiteC_Presidential",
		riddle = "Midnight and Garnet both bow to the third. The one you could never afford.",
		actOne = true,
		allowedKinds = { "Note", "Cipher", "Carry" },
	},
	{
		id = "LobbyElevator",
		riddle = "The lift that carried you down refuses to carry you up. Stand where its doors first opened on you.",
		actOne = true,
		allowedKinds = { "Note", "Cipher", "Carry" },
	},
	{
		id = "CorridorPanels",
		riddle = "Forty-one lamps watch the guest wing sleep. One of them is lying.",
		actOne = true,
		allowedKinds = { "Note", "Cipher", "Carry" },
	},
	{
		id = "ProjectMirror",
		riddle = "You have walked past yourself a dozen times tonight. Go back and look properly.",
		actOne = true,
		allowedKinds = { "Note", "Cipher" },
	},
	{
		id = "WaterFountain",
		riddle = "It still runs, though nobody here has been thirsty in years.",
		actOne = true,
		allowedKinds = { "Note", "Cipher" },
	},
	{
		id = "VaultFacade",
		riddle = "Twenty-two feet of steel, and a door that has never once been asked politely.",
		actOne = false,
		allowedKinds = { "Note", "Cipher" },
	},
}

local ciphers: { Cipher } = {
	{
		question = "The wheel beneath the bed shows eight fates. How many are cruel?",
		answer = "3",
	},
	{
		question = "How many lamps line the guest wing?",
		answer = "41",
	},
	{
		question = "How many plinths stand in the claiming room?",
		answer = "3",
	},
	{
		question = "Your sack is full. How many things are in it?",
		answer = "10",
	},
	{
		question = "What room did Noel put you in?",
		answer = "1",
	},
	{
		question = "Name the third suite.",
		answer = "presidential",
	},
}

ClueConfig.Sites = sites
ClueConfig.Ciphers = ciphers

-- Lobby sites must form a prefix of every route. Once players take the
-- one-way Lobby -> Rooms lift, no later clue may send them back here.
local lobbySiteIds: { [string]: boolean } = {
	ReceptionDesk = true,
	ClassPodiums = true,
	LobbyElevator = true,
	WaterFountain = true,
}
ClueConfig.LobbySiteIds = lobbySiteIds

local numberWords: { [string]: string } = {
	zero = "0",
	one = "1",
	two = "2",
	three = "3",
	four = "4",
	five = "5",
	six = "6",
	seven = "7",
	eight = "8",
	nine = "9",
	ten = "10",
	eleven = "11",
	twelve = "12",
}

-- Pure helpers ---------------------------------------------------------------

function ClueConfig.findSite(id: string): Site?
	for _, site in sites do
		if site.id == id then
			return site
		end
	end
	return nil
end

function ClueConfig.siteAllowsKind(siteId: string, kind: string): boolean
	local site = ClueConfig.findSite(siteId)
	if not site then
		return false
	end
	for _, allowedKind in site.allowedKinds do
		if allowedKind == kind then
			return true
		end
	end
	return false
end

function ClueConfig.normaliseAnswer(answer: string): string
	local compact = string.gsub(string.lower(answer), "%s+", "")
	return numberWords[compact] or compact
end

function ClueConfig.answerMatches(given: string, expected: string): boolean
	return ClueConfig.normaliseAnswer(given) == ClueConfig.normaliseAnswer(expected)
end

export type RevealedDigits = number | { boolean }

function ClueConfig.maskedDigits(code: string, revealed: RevealedDigits): string
	local masked = table.create(#code)
	for index = 1, #code do
		local visible = if typeof(revealed) == "number" then index <= math.floor(revealed) else revealed[index] == true
		masked[index] = if visible then string.sub(code, index, index) else "_"
	end
	return table.concat(masked)
end

function ClueConfig.remaining(now: number, readyAt: number): number
	return math.max(0, readyAt - now)
end

return ClueConfig
