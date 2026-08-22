--!strict
--[[
	Server authority for the hotel's shared clue hunt and its three-act escape.
	Clients may ask to grade text and Roblox prompts may report an interaction,
	but this script re-establishes the current node, world ancestry, tag, range,
	inventory, class, line of sight, and phase before it changes the round. The
	result is one communal case file rather than five client-owned quest lines:
	one solve moves the whole server forward, and every mistake gives Joel a real
	place to investigate.

	The generated props deliberately contain no progress logic. CluePropKit owns
	their shapes and ContainerKit owns their motion; this service owns when those
	objects are live, what constitutes a solution, and how the vault, Sunstone,
	Joel, exit code, and emergency return lift fit into one resettable round.

	The three treasury exhibits are the one exception to "generated". They are
	ADOPTED from Workspace.VaultChamber.Relics when the user has saved models
	there, and only built by makePlinth when they are missing. A room the user
	cannot open in Studio and redress is a room they cannot design, so the
	per-round mechanism is expressed as SHOW and HIDE over content that outlives
	the round rather than as create and destroy over content that does not.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local ClassDefinitions = require(ReplicatedStorage:WaitForChild("ClassDefinitions"))
local ClueConfig = require(ReplicatedStorage:WaitForChild("ClueConfig"))
local DisplayCaseConfig = require(ReplicatedStorage:WaitForChild("DisplayCaseConfig"))
local JoelConfig = require(ReplicatedStorage:WaitForChild("JoelConfig"))
local SackConfig = require(ReplicatedStorage:WaitForChild("SackConfig"))
local ClueChain = require(ServerStorage:WaitForChild("ClueChain"))
local CluePropKit = require(ServerStorage:WaitForChild("CluePropKit"))
local ContainerKit = require(ServerStorage:WaitForChild("ContainerKit"))

local ROUND_FOLDER_NAME = "ClueRound"
local JOEL_TAG = "JoelHunter"
local GENERATED_VAULT_ATTRIBUTE = "GeneratedBankVault"
local VAULT_PROMPT_NAME = "InspectKeypad"
local EXIT_TRIGGER_NAME = "ClueExitThreshold"
local LOCKED_EXIT_CODE = "LOCKED"
local SOLAR_LANCE_NAME = "SolarLance"
local SUNSTONE_NAME = "Sunstone"
local ROUND_RESET_DELAY = 10
local STARTUP_SITE_TIMEOUT = 12
local HEARTBEAT_INTERVAL = 0.25
local ROUTE_REROLL_ATTEMPTS = 8

-- Where a hand-built treasury lives. These names are a contract with the place
-- file, not with any other script: drop a Model here whose name matches a
-- RelicSpec.modelName and this service stops generating that exhibit and starts
-- driving the saved one instead.
local RELIC_CHAMBER_NAME = "VaultChamber"
local RELIC_FOLDER_NAME = "Relics"
-- ObjectValue inside a relic model, pointing at the vitrine it stands in.
local RELIC_CASE_VALUE = "Case"
local PLINTH_STONE_NAME = "Stone"

-- Hiding an adopted plinth overwrites properties the user chose, so the chosen
-- values are banked on the instances before the first overwrite and read back
-- on every show. Attributes rather than a Lua table because a Studio re-run of
-- this script starts with empty tables but does NOT reload the place: a table
-- would forget that a stone is currently hidden and then bank Transparency 1
-- as "what the user authored", which is unrecoverable without a rollback.
-- Runtime attributes never reach the saved file, so this leaves no residue.
local AUTHORED_TRANSPARENCY = "ClueAuthoredTransparency"
local AUTHORED_CAN_COLLIDE = "ClueAuthoredCanCollide"
local AUTHORED_CAN_TOUCH = "ClueAuthoredCanTouch"
local AUTHORED_CAN_QUERY = "ClueAuthoredCanQuery"
local AUTHORED_LIGHT_ENABLED = "ClueAuthoredLightEnabled"

local LED_IDLE = Color3.fromRGB(255, 183, 62)
local LED_GOOD = Color3.fromRGB(78, 255, 157)
local LED_BAD = Color3.fromRGB(255, 72, 58)
local SUNSTONE_GOLD = Color3.fromRGB(255, 211, 92)
local SUNSTONE_CORE = Color3.fromRGB(255, 247, 177)
local LANCE_GOLD = Color3.fromRGB(235, 190, 72)
local LANCE_LIGHT = Color3.fromRGB(255, 245, 165)

-- Remotes and server APIs ----------------------------------------------------

local function ensure(parent: Instance, name: string, className: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end
	local created = Instance.new(className)
	created.Name = name
	created.Parent = parent
	return created
end

local remotes = ensure(ReplicatedStorage, ClueConfig.RemotesFolder, "Folder")
local openEvent = ensure(remotes, ClueConfig.OpenEvent, "RemoteEvent") :: RemoteEvent
local submitEvent = ensure(remotes, ClueConfig.SubmitEvent, "RemoteEvent") :: RemoteEvent
local resultEvent = ensure(remotes, ClueConfig.ResultEvent, "RemoteEvent") :: RemoteEvent
local announceEvent = ensure(remotes, ClueConfig.AnnounceEvent, "RemoteEvent") :: RemoteEvent

-- Not this service's folder: the brass refusal plaque belongs to the display
-- cases, and MalletService, DisplayCaseService and this file all hang notices on
-- it. Ensured the same way in all three, so whichever starts first creates it.
local refusedEvent = ensure(
	ensure(ReplicatedStorage, DisplayCaseConfig.RemotesFolder, "Folder"),
	DisplayCaseConfig.RefusalEvent,
	"RemoteEvent"
) :: RemoteEvent

local joelNoise = ensure(ServerStorage, ClueConfig.JoelNoiseEvent, "BindableEvent") :: BindableEvent
local joelDefeat = ensure(ServerStorage, ClueConfig.JoelDefeatEvent, "BindableEvent") :: BindableEvent
local joelRevive = ensure(ServerStorage, ClueConfig.JoelReviveEvent, "BindableEvent") :: BindableEvent
local sackConsume = ensure(ServerStorage, ClueConfig.SackConsumeEvent, "BindableEvent") :: BindableEvent

local clueState = ensure(Workspace, ClueConfig.StateFolder, "Folder") :: Folder

-- Shared state ---------------------------------------------------------------

type BreakerLever = {
	index: number,
	part: BasePart,
	prompt: ProximityPrompt,
	animated: ContainerKit.AnimatedSet,
	led: BasePart,
}

type BreakerPanel = {
	model: Model,
	levers: { BreakerLever },
	handle: BasePart,
	handlePrompt: ProximityPrompt,
	hatch: BasePart,
	hatchAnimated: ContainerKit.AnimatedSet,
}

type BreakerState = {
	nodeIndex: number,
	panel: BreakerPanel,
	required: { [number]: boolean },
	lockoutUntil: number,
}

type SearchState = {
	nodeIndex: number,
	model: Model,
	prompt: ProximityPrompt,
	animated: ContainerKit.AnimatedSet,
}

type CarryState = {
	nodeIndex: number,
	id: string,
	item: Model,
	prompt: ProximityPrompt,
	sourceCFrame: CFrame,
	displayName: string,
}

type PromptCategory =
	"StartingNote"
	| "Note"
	| "Cipher"
	| "LeverToggle"
	| "LeverHandle"
	| "Search"
	| "Carry"
	| "Sunstone"
	| "ClassRelic"
	| "ExitCode"

type PromptContext = {
	category: PromptCategory,
	focus: BasePart,
	nodeIndex: number?,
	nodeKind: string?,
	site: BasePart?,
	breaker: BreakerState?,
	leverIndex: number?,
	search: SearchState?,
	carry: CarryState?,
	relicId: string?,
}

type ExitBinding = {
	model: Model,
	hinge: BasePart?,
	closedCFrame: CFrame?,
	trigger: BasePart,
	ownsTrigger: boolean,
	connection: RBXScriptConnection,
}

local roundState: ClueChain.State? = nil
local roundFolder: Folder? = nil
local roundRevision = 0
local previousRouteKey: string? = nil
local sitesById: { [string]: BasePart } = {}
local riddlesByIndex: { [number]: string } = {}
local ciphersByIndex: { [number]: ClueConfig.Cipher } = {}
local breakersByIndex: { [number]: BreakerState } = {}
local searchesByIndex: { [number]: SearchState } = {}
local carriesByIndex: { [number]: CarryState } = {}

local promptContexts: { [ProximityPrompt]: PromptContext } = {}
local promptConnections: { [ProximityPrompt]: RBXScriptConnection } = {}
local exitBindings: { [Model]: ExitBinding } = {}
local playerConnections: { [Player]: { RBXScriptConnection } } = {}
local cooldownReadyAt: { [Player]: number } = {}
local openCipherIndex: { [Player]: number } = {}
local lanceOwners: { [Player]: boolean } = {}
local lanceConnections: { [Tool]: { RBXScriptConnection } } = {}

local vaultOpenedAt = -math.huge
local fallbackReleased = false
local fallbackAnnounced = false
local sunstoneClaimed = false
local sunstoneModel: Model? = nil
-- The Muscle and Hacker plinths, keyed by relic id. Declared up here with the
-- rest of the round state because refreshPrompts reads them long before the
-- relic definitions further down the file.
local relicModels: { [string]: Model } = {}
local relicClaimed: { [string]: boolean } = {}
-- Saved plinths this session has taken over, keyed by RelicSpec.id. This is the
-- single source of truth for "is this model mine to destroy?", and it is
-- deliberately NOT cleared when a relic is claimed: a claimed adopted plinth
-- leaves relicModels but still has to be found and re-hidden at round reset.
-- Keyed by id rather than by Model so it stays bounded at three entries no
-- matter how many times the place is edited underneath us.
local adoptedPlinths: { [string]: Model } = {}
local exitCodeNote: Model? = nil
local joelWasDefeated = false
local downedEndsAt = 0
local escapeExpired = false
local resetting = false

local refreshPrompts: () -> ()
local rebuildRound: () -> ()
local handlePrompt: (ProximityPrompt, Player) -> ()
local winRound: (Player) -> ()

-- World and player validation ------------------------------------------------

local function rootFor(player: Player): BasePart?
	if player.Parent ~= Players then
		return nil
	end
	local character = player.Character
	if not character or not character:IsDescendantOf(Workspace) then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	return root
end

local function inRange(player: Player, focus: BasePart, reach: number?): boolean
	local root = rootFor(player)
	return root ~= nil
		and focus:IsDescendantOf(Workspace)
		and (root.Position - focus.Position).Magnitude <= (reach or ClueConfig.InteractionDistance) + 4
end

local function promptFocus(prompt: ProximityPrompt): BasePart?
	local parent = prompt.Parent
	return if parent and parent:IsA("BasePart") then parent else nil
end

local function findJoel(): Model?
	for _, instance in CollectionService:GetTagged(JOEL_TAG) do
		if instance:IsA("Model") and instance:IsDescendantOf(Workspace) then
			return instance
		end
	end
	local direct = Workspace:FindFirstChild("Joel")
	return if direct and direct:IsA("Model") then direct else nil
end

local function findVault(): Model?
	for _, child in Workspace:GetChildren() do
		if child:IsA("Model") and child:GetAttribute(GENERATED_VAULT_ATTRIBUTE) == true then
			return child
		end
	end
	local named = Workspace:FindFirstChild("BankVault") or Workspace:FindFirstChild("BankVault_Procedural")
	return if named and named:IsA("Model") then named else nil
end

local function findVaultPrompt(): ProximityPrompt?
	local vault = findVault()
	if not vault then
		return nil
	end
	local prompt = vault:FindFirstChild(VAULT_PROMPT_NAME, true)
	return if prompt and prompt:IsA("ProximityPrompt") then prompt else nil
end

local function routeKey(state: ClueChain.State): string
	local ids = table.create(#state.nodes)
	for index, node in state.nodes do
		ids[index] = node.siteId
	end
	return table.concat(ids, "|")
end

local function readableSiteId(siteId: string): string
	local spaced = string.gsub(siteId, "_", " ")
	spaced = string.gsub(spaced, "(%l)(%u)", "%1 %2")
	return spaced
end

local function nodeRiddle(index: number): string
	return riddlesByIndex[index] or "The trail has gone cold."
end

local function currentRiddle(): string
	local activeRound = roundState
	if not activeRound then
		return "The case file is still being assembled."
	end
	if activeRound.phase == ClueConfig.PhaseHunt then
		return nodeRiddle(activeRound.index)
	end
	if activeRound.phase == ClueConfig.PhaseVault then
		if joelWasDefeated then
			return "Joel dropped the last page. Find it before he stands again."
		end
		if sunstoneClaimed then
			return "Keep the Solar Lance on Joel, close enough that the light does not break."
		end
		local vault = findVault()
		if vault and vault:GetAttribute(ClueConfig.VaultUnlockedAttribute) == true then
			return "The vault is open. Take the Sunstone from the treasury."
		end
		local vaultSite = ClueConfig.findSite("VaultFacade")
		return if vaultSite then vaultSite.riddle else "The five marks belong beneath the hotel."
	end
	if activeRound.phase == ClueConfig.PhaseEscape then
		return "The exit is in the lobby. The Rooms lift has one final trip in it."
	end
	return "Someone made it out. The hotel is already forgetting."
end

local function announce(kind: string, text: string)
	announceEvent:FireAllClients({
		kind = kind,
		text = text,
	})
end

local function reject(player: Player, reason: string)
	local activeRound = roundState
	resultEvent:FireClient(player, {
		ok = false,
		reason = reason,
		digitsKnown = if activeRound then ClueChain.digitsKnown(activeRound) else "",
		nextRiddle = currentRiddle(),
	})
end

local function onCooldown(player: Player): boolean
	local remaining = ClueConfig.remaining(os.clock(), cooldownReadyAt[player] or 0)
	if remaining <= 0 then
		return false
	end
	reject(player, `The ink is still wet. Try again in {math.ceil(remaining)} seconds.`)
	return true
end

local function punish(player: Player, position: Vector3, reason: string)
	cooldownReadyAt[player] = os.clock() + ClueConfig.WrongAnswerCooldown
	reject(player, reason)
	joelNoise:Fire(position, ClueConfig.NoiseRadiusWrong)
end

local function siteStillValid(site: BasePart, expectedId: string): boolean
	return site:IsDescendantOf(Workspace)
		and CollectionService:HasTag(site, ClueConfig.SiteTag)
		and site:GetAttribute(ClueConfig.SiteIdAttribute) == expectedId
end

local function nodeContextIsCurrent(player: Player, prompt: ProximityPrompt, context: PromptContext): boolean
	local activeRound = roundState
	local index = context.nodeIndex
	local kind = context.nodeKind
	if not activeRound or activeRound.phase ~= ClueConfig.PhaseHunt or not index or not kind then
		return false
	end
	local node = ClueChain.currentNode(activeRound)
	if not node or activeRound.index ~= index or node.kind ~= kind then
		return false
	end
	if
		prompt:GetAttribute(ClueConfig.NodeIndexAttribute) ~= index
		or prompt:GetAttribute(ClueConfig.NodeKindAttribute) ~= kind
	then
		return false
	end
	local site = context.site
	if not site or not siteStillValid(site, node.siteId) then
		return false
	end
	return inRange(player, context.focus)
end

local function hasSuperman(): boolean
	for _, player in Players:GetPlayers() do
		if ClassDefinitions.hasClass(player, ClassDefinitions.SUPERMAN) then
			return true
		end
	end
	return false
end

local function carriedInstance(player: Player, carryId: string): Instance?
	local sackVault = ServerStorage:FindFirstChild("SackVault")
	local pack = sackVault and sackVault:FindFirstChild(tostring(player.UserId))
	if not pack then
		return nil
	end
	for _, item in pack:GetChildren() do
		if item:GetAttribute(ClueConfig.CarryIdAttribute) == carryId then
			return item
		end
	end
	return nil
end

local function anyoneCarries(carryId: string): boolean
	for _, player in Players:GetPlayers() do
		if carriedInstance(player, carryId) then
			return true
		end
	end
	return false
end

local function setEmergencyReturn(enabled: boolean)
	for _, cab in CollectionService:GetTagged(ClueConfig.ElevatorCabTag) do
		if cab:IsA("Model") and cab:GetAttribute(ClueConfig.CabIdAttribute) == "Rooms" then
			cab:SetAttribute(ClueConfig.PartnerAttribute, if enabled then "Lobby" else nil)
		end
	end
end

-- Replication and prompt gating ---------------------------------------------

local function publishRound()
	local activeRound = roundState
	if not activeRound then
		return
	end
	clueState:SetAttribute(ClueConfig.ChainLengthAttribute, #activeRound.nodes)
	clueState:SetAttribute(
		ClueConfig.NodeIndexAttribute,
		math.clamp(activeRound.index, 1, math.max(1, #activeRound.nodes))
	)
	clueState:SetAttribute(ClueConfig.DigitsKnownAttribute, ClueChain.digitsKnown(activeRound))
	clueState:SetAttribute(ClueConfig.PhaseAttribute, activeRound.phase)
	clueState:SetAttribute(ClueConfig.CurrentRiddleAttribute, currentRiddle())
end

local function setAnimatedLocked(animated: ContainerKit.AnimatedSet, locked: boolean)
	if animated.locked == locked then
		return
	end
	animated.locked = locked
	ContainerKit.updatePromptText(animated)
end

--[[
	Is this relic still behind its glass?

	The two cased relics stand INSIDE a vitrine without being children of it,
	which is deliberate -- a relic parented into a case would be tagged
	Collectable by armContents the moment the glass went, turning a claimable
	relic into ordinary sack loot, and it would also stop being a direct child of
	the Relics folder, which is the only place findSavedPlinth looks.

	So the link is an ObjectValue named Case inside the relic, pointing at the
	vitrine. A relic with no such link has no glass in front of it and claims
	exactly as it always did, which is what keeps an uncased Sunstone working.

	The player-facing half of this is not here: the claim prompt already carries
	RequiresLineOfSight, and intact panes are queryable, so the prompt is simply
	invisible until somebody swings a mallet. This is the half that makes it
	true rather than merely apparent.
]]
local function caseSealed(model: Model?): boolean
	if not model then
		return false
	end
	local link = model:FindFirstChild(RELIC_CASE_VALUE)
	local case = if link and link:IsA("ObjectValue") then link.Value else nil
	if not case or not case:IsDescendantOf(Workspace) then
		return false
	end
	return case:GetAttribute(DisplayCaseConfig.CaseOpenedAttribute) ~= true
end

-- The live plinth for a relic id, from whichever table is holding it. Adopted
-- models stay in adoptedPlinths for the whole session; relicModels only holds
-- one while it is unclaimed and on show.
local function relicPlinth(relicId: string?): Model?
	if not relicId then
		return nil
	end
	return relicModels[relicId] or adoptedPlinths[relicId]
end

refreshPrompts = function()
	local activeRound = roundState
	local activeIndex = if activeRound and activeRound.phase == ClueConfig.PhaseHunt then activeRound.index else -1
	local now = os.clock()

	for prompt, context in promptContexts do
		if not prompt.Parent or not CollectionService:HasTag(prompt, ClueConfig.PromptTag) then
			continue
		end

		local enabled = false
		if context.category == "StartingNote" then
			enabled = activeRound ~= nil and activeRound.phase == ClueConfig.PhaseHunt and activeRound.index == 1
		elseif context.category == "Sunstone" then
			local vault = findVault()
			enabled = activeRound ~= nil
				and activeRound.phase == ClueConfig.PhaseVault
				and not sunstoneClaimed
				and vault ~= nil
				and vault:GetAttribute(ClueConfig.VaultUnlockedAttribute) == true
		elseif context.category == "ClassRelic" then
			local vault = findVault()
			enabled = activeRound ~= nil
				and activeRound.phase == ClueConfig.PhaseVault
				and context.relicId ~= nil
				and not relicClaimed[context.relicId :: string]
				and vault ~= nil
				and vault:GetAttribute(ClueConfig.VaultUnlockedAttribute) == true
				and not caseSealed(relicPlinth(context.relicId))
		elseif context.category == "ExitCode" then
			enabled = activeRound ~= nil and activeRound.phase == ClueConfig.PhaseVault and joelWasDefeated
		elseif context.nodeIndex == activeIndex then
			if context.category == "Carry" then
				local carry = context.carry
				enabled = carry ~= nil and anyoneCarries(carry.id)
			elseif context.category == "Search" then
				local search = context.search
				enabled = search ~= nil and search.animated.isOpen
			elseif context.category == "LeverToggle" or context.category == "LeverHandle" then
				local breaker = context.breaker
				enabled = breaker ~= nil and now >= breaker.lockoutUntil
			else
				enabled = true
			end
		end
		prompt.Enabled = enabled
	end

	for index, breaker in breakersByIndex do
		local unlocked = index == activeIndex and now >= breaker.lockoutUntil
		for _, lever in breaker.panel.levers do
			setAnimatedLocked(lever.animated, not unlocked)
			lever.prompt.Enabled = unlocked
		end
		breaker.panel.handlePrompt.Enabled = unlocked
	end

	for index, search in searchesByIndex do
		local active = index == activeIndex
		setAnimatedLocked(search.animated, not active)
		search.prompt.Enabled = active and search.animated.isOpen
	end

	for index, carry in carriesByIndex do
		carry.item:SetAttribute(SackConfig.LockedAttribute, index ~= activeIndex)
		carry.prompt.Enabled = index == activeIndex and anyoneCarries(carry.id)
	end
end

local function markNode(instance: Instance, index: number, kind: string)
	instance:SetAttribute(ClueConfig.NodeIndexAttribute, index)
	instance:SetAttribute(ClueConfig.NodeKindAttribute, kind)
end

local function registerPrompt(prompt: ProximityPrompt, context: PromptContext)
	markNode(prompt, context.nodeIndex or 0, context.nodeKind or context.category)
	promptContexts[prompt] = context
	if not CollectionService:HasTag(prompt, ClueConfig.PromptTag) then
		CollectionService:AddTag(prompt, ClueConfig.PromptTag)
	end
	if promptConnections[prompt] then
		promptConnections[prompt]:Disconnect()
	end
	promptConnections[prompt] = prompt.Triggered:Connect(function(player: Player)
		handlePrompt(prompt, player)
	end)
end

local function teardownPrompt(instance: Instance)
	if not instance:IsA("ProximityPrompt") then
		return
	end
	local connection = promptConnections[instance]
	if connection then
		connection:Disconnect()
		promptConnections[instance] = nil
	end
	promptContexts[instance] = nil
end

local function setupPrompt(instance: Instance)
	if not instance:IsA("ProximityPrompt") or not instance:IsDescendantOf(Workspace) then
		return
	end
	local focus = promptFocus(instance)
	if not focus then
		return
	end
	local connection = promptConnections[instance]
	if connection then
		connection:Disconnect()
	end
	promptConnections[instance] = instance.Triggered:Connect(function(player: Player)
		handlePrompt(instance, player)
	end)
end

-- Node progress --------------------------------------------------------------

local function solvedReason(digit: string): string
	return `The hotel yields a mark: {digit}.`
end

local function enterVault()
	local activeRound = roundState
	if not activeRound or activeRound.phase ~= ClueConfig.PhaseHunt then
		return
	end
	activeRound.phase = ClueConfig.PhaseVault
	vaultOpenedAt = -math.huge
	fallbackReleased = false
	fallbackAnnounced = false
	sunstoneClaimed = false
	table.clear(relicClaimed)
	joelWasDefeated = false
	downedEndsAt = 0
end

local function solveNode(player: Player, nodeIndex: number, position: Vector3): boolean
	local activeRound = roundState
	if not activeRound or activeRound.phase ~= ClueConfig.PhaseHunt then
		return false
	end
	local node = activeRound.nodes[nodeIndex]
	if not node or not ClueChain.solve(activeRound, nodeIndex) then
		return false
	end

	openCipherIndex[player] = nil
	cooldownReadyAt[player] = 0
	joelNoise:Fire(position, ClueConfig.NoiseRadiusSolve)
	local completed = ClueChain.isComplete(activeRound)
	if completed then
		enterVault()
	end
	publishRound()
	refreshPrompts()

	local nextText = currentRiddle()
	resultEvent:FireClient(player, {
		ok = true,
		reason = solvedReason(node.digit),
		digitsKnown = ClueChain.digitsKnown(activeRound),
		nextRiddle = nextText,
	})
	announce("Solved", `{player.DisplayName} found mark {nodeIndex} of {#activeRound.nodes}.`)

	if completed then
		announce("Solved", "Five marks. The service lift and the steel below are waiting.")
	end
	return true
end

local function choosePattern(rng: Random): ({ [number]: boolean }, { number })
	local pool = table.create(ClueConfig.LeverCount)
	for index = 1, ClueConfig.LeverCount do
		pool[index] = index
	end
	for index = #pool, 2, -1 do
		local replacement = rng:NextInteger(1, index)
		pool[index], pool[replacement] = pool[replacement], pool[index]
	end
	local required: { [number]: boolean } = {}
	local ordered = table.create(ClueConfig.LeverRequired)
	for index = 1, ClueConfig.LeverRequired do
		required[pool[index]] = true
		ordered[index] = pool[index]
	end
	table.sort(ordered)
	return required, ordered
end

local function breakerMatches(breaker: BreakerState): boolean
	for _, lever in breaker.panel.levers do
		if lever.animated.isOpen ~= (breaker.required[lever.index] == true) then
			return false
		end
	end
	return true
end

local function resetBreaker(breaker: BreakerState)
	local revision = roundRevision
	for _, lever in breaker.panel.levers do
		if lever.animated.busy then
			task.delay(ContainerKit.OpenInfo.Time + 0.1, function()
				if revision == roundRevision and lever.part.Parent then
					ContainerKit.setOpen(lever.animated, false)
				end
			end)
		else
			ContainerKit.setOpen(lever.animated, false)
		end
		lever.led.Color = LED_BAD
		task.delay(0.45, function()
			if lever.led.Parent and roundState and roundState.index == breaker.nodeIndex then
				lever.led.Color = LED_IDLE
			end
		end)
	end
end

-- Vault, Sunstone, and Joel --------------------------------------------------

--[[
	A treasury plinth: pedestal, floating charge, light, claim prompt.

	Generalised from the Sunstone, which used to be the only claimable in the
	vault. All three now share this so a fourth is a table entry rather than
	another fifty lines, and so they read as a matched set of exhibits standing
	in the same room.
]]
type RelicSpec = {
	id: string,
	modelName: string,
	actionText: string,
	objectText: string,
	core: Color3,
	glow: Color3,
	shape: Enum.PartType,
	-- Sideways offset from the Sunstone's plinth, so the three stand in a row.
	lateral: number,
}

--[[
	The claim prompt, to one specification wherever the plinth came from.

	Split out of makePlinth so a saved exhibit and a generated one cannot drift
	apart: reach, hold time, and line of sight are what a player actually feels
	when claiming, and those must not depend on whether the user has dressed the
	treasury yet.
]]
local function makeClaimPrompt(spec: RelicSpec): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Claim" .. spec.id
	prompt.ActionText = spec.actionText
	prompt.ObjectText = spec.objectText
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 1.2
	prompt.MaxActivationDistance = ClueConfig.InteractionDistance
	prompt.RequiresLineOfSight = true
	return prompt
end

local function makePlinth(parent: Instance, cframe: CFrame, spec: RelicSpec): (Model, ProximityPrompt)
	local model = Instance.new("Model")
	model.Name = spec.modelName

	local pedestal = Instance.new("Part")
	pedestal.Name = "Pedestal"
	pedestal.Anchored = true
	pedestal.CanCollide = true
	pedestal.Size = Vector3.new(3.2, 3, 3.2)
	pedestal.CFrame = cframe * CFrame.new(0, 1.5, 0)
	pedestal.Color = Color3.fromRGB(47, 51, 57)
	pedestal.Material = Enum.Material.Metal
	pedestal.TopSurface = Enum.SurfaceType.Smooth
	pedestal.BottomSurface = Enum.SurfaceType.Smooth
	pedestal.Parent = model

	local stone = Instance.new("Part")
	stone.Name = PLINTH_STONE_NAME
	stone.Anchored = true
	stone.CanCollide = false
	stone.CanTouch = false
	stone.Size = Vector3.new(1.45, 2.1, 1.45)
	stone.CFrame = cframe * CFrame.new(0, 3.75, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45))
	stone.Color = spec.core
	stone.Material = Enum.Material.Neon
	stone.Shape = spec.shape
	stone.Parent = model

	local light = Instance.new("PointLight")
	light.Color = spec.glow
	light.Brightness = 2.5
	light.Range = 18
	light.Shadows = true
	light.Parent = stone

	local prompt = makeClaimPrompt(spec)
	prompt.Parent = stone

	model.PrimaryPart = pedestal
	model.Parent = parent
	return model, prompt
end

-- Adopting a saved plinth ----------------------------------------------------

--[[
	Bank a property the user chose, once, before anything overwrites it.

	Never overwrites an existing bank. That single rule is what makes the whole
	show/hide scheme safe to re-enter: whatever a stone's Transparency happens to
	be right now, if the attribute is already there then the real authored value
	was captured earlier and this call must not clobber it with a hidden one.
]]
local function bankAuthored(instance: Instance, name: string, value: number | boolean)
	if instance:GetAttribute(name) == nil then
		instance:SetAttribute(name, value)
	end
end

-- Banked values are read back defensively: an attribute a user retyped by hand
-- into the wrong type must not be able to error a claim out mid-round.
local function bankedNumber(instance: Instance, name: string, fallback: number): number
	local value = instance:GetAttribute(name)
	return if typeof(value) == "number" then value else fallback
end

local function bankedBoolean(instance: Instance, name: string, fallback: boolean): boolean
	local value = instance:GetAttribute(name)
	return if typeof(value) == "boolean" then value else fallback
end

local function plinthStone(model: Model): BasePart?
	local stone = model:FindFirstChild(PLINTH_STONE_NAME)
	return if stone and stone:IsA("BasePart") then stone else nil
end

--[[
	The whole per-round mechanism for an adopted exhibit, in one property sweep.

	Hidden is NOT destroyed. A saved plinth belongs to the place file, so
	removing it at runtime would take the user's editable content out of the
	running game and out of any save that followed. The stone goes invisible,
	untouchable, unlit, and unpromptable; everything else in the model is left
	exactly as authored. The pedestal in particular stays standing, because an
	empty pedestal after a claim reads as a treasury someone just robbed, while a
	vanished exhibit reads as a bug.

	Show is the inverse and restores what the user chose rather than what
	makePlinth would have chosen, so a deliberately half-transparent crystal or a
	deliberately dark light survives a round it was claimed in.
]]
local function setPlinthShown(model: Model, shown: boolean)
	local stone = plinthStone(model)
	if not stone then
		return
	end
	local pieces: { Instance } = { stone }
	for _, descendant in stone:GetDescendants() do
		table.insert(pieces, descendant)
	end

	for _, piece in pieces do
		if piece:IsA("BasePart") then
			bankAuthored(piece, AUTHORED_TRANSPARENCY, piece.Transparency)
			bankAuthored(piece, AUTHORED_CAN_COLLIDE, piece.CanCollide)
			bankAuthored(piece, AUTHORED_CAN_TOUCH, piece.CanTouch)
			bankAuthored(piece, AUTHORED_CAN_QUERY, piece.CanQuery)
			piece.Transparency = if shown then bankedNumber(piece, AUTHORED_TRANSPARENCY, 0) else 1
			piece.CanCollide = shown and bankedBoolean(piece, AUTHORED_CAN_COLLIDE, false)
			piece.CanTouch = shown and bankedBoolean(piece, AUTHORED_CAN_TOUCH, false)
			piece.CanQuery = shown and bankedBoolean(piece, AUTHORED_CAN_QUERY, true)
		elseif piece:IsA("Light") then
			bankAuthored(piece, AUTHORED_LIGHT_ENABLED, piece.Enabled)
			piece.Enabled = shown and bankedBoolean(piece, AUTHORED_LIGHT_ENABLED, true)
		elseif piece:IsA("ProximityPrompt") and not shown then
			-- refreshPrompts is the only thing in this file that ENABLES a
			-- prompt, and it runs on the same heartbeat that gates every other
			-- interaction, so showing deliberately leaves this alone. Hiding
			-- does not wait for it: a claim has to close its own prompt in the
			-- frame it lands, not a quarter second later.
			piece.Enabled = false
		end
	end
end

--[[
	The saved exhibit for one spec, if the user has built it.

	Direct children only. A recursive search would happily match a decorative
	part somebody named "Ironhand" three levels down inside the chamber, and
	adopting the wrong instance is a far worse failure than not adopting at all
	-- the fallback below still produces a playable round.
]]
local function findSavedPlinth(spec: RelicSpec): Model?
	local chamber = Workspace:FindFirstChild(RELIC_CHAMBER_NAME)
	local relics = if chamber then chamber:FindFirstChild(RELIC_FOLDER_NAME) else nil
	if not relics then
		return nil
	end
	local candidate = relics:FindFirstChild(spec.modelName)
	return if candidate and candidate:IsA("Model") then candidate else nil
end

--[[
	Take ownership of the saved exhibit for one spec and put it on show.

	Note what is absent: the model itself is never constructed, reparented, or
	moved. It stays precisely where the user saved it, which is also what keeps
	it OUT of roundFolder -- the round teardown destroys that folder wholesale,
	and an adopted plinth reparented into it would be deleted out of the place on
	the first reset. Adoption is: find, prompt, show. Nothing else.

	The one thing that is added to the user's model is the claim prompt, hung on
	the Stone. That is unavoidable -- a plinth with no prompt cannot be claimed --
	and harmless: instances created at runtime never reach the saved file, so the
	model the user opens in Studio is still exactly the model they authored.
]]
local function adoptPlinth(spec: RelicSpec): (Model?, ProximityPrompt?)
	local model: Model? = adoptedPlinths[spec.id]
	if model and not model:IsDescendantOf(Workspace) then
		adoptedPlinths[spec.id] = nil
		model = nil
	end
	if not model then
		model = findSavedPlinth(spec)
	end
	if not model then
		return nil, nil
	end

	local stone = plinthStone(model)
	if not stone then
		warn(
			`[ClueService] {model:GetFullName()} has no BasePart named "{PLINTH_STONE_NAME}", so there is nowhere to `
				.. `hang the claim prompt. Generating a runtime {spec.modelName} instead — add a Stone part to the `
				.. `saved model to have this service drive yours.`
		)
		return nil, nil
	end

	adoptedPlinths[spec.id] = model
	-- An existing prompt of this name is the user's, tweaked text and all, and
	-- editing it in Studio is exactly the freedom this change exists to give.
	local existing = stone:FindFirstChild("Claim" .. spec.id)
	local prompt: ProximityPrompt
	if existing and existing:IsA("ProximityPrompt") then
		prompt = existing
	else
		prompt = makeClaimPrompt(spec)
		prompt.Parent = stone
	end

	setPlinthShown(model, true)
	return model, prompt
end

--[[
	One live, claimable exhibit for this round, from whichever source has one.

	Adopted first, generated second. The fallback is not a courtesy: it is what
	lets this land before, after, or entirely without the Studio work, and what
	keeps a round winnable in a place where somebody has deleted a plinth. Only
	the generated branch reads `base` — an adopted plinth ignores it and keeps
	the placement the user gave it.

	Returns nil when neither source produced a model, which callers read as "this
	relic is simply not on offer this round" rather than as an error.
]]
local function stagePlinth(spec: RelicSpec, base: CFrame, category: PromptCategory, relicId: string?): Model?
	local folder = roundFolder
	local model: Model?
	local prompt: ProximityPrompt?

	local adoptedModel, adoptedPrompt = adoptPlinth(spec)
	if adoptedModel and adoptedPrompt then
		model, prompt = adoptedModel, adoptedPrompt
	elseif folder then
		model, prompt = makePlinth(folder, base, spec)
	end
	if not model or not prompt then
		return nil
	end

	local focus = promptFocus(prompt) or plinthStone(model)
	if not focus then
		return nil
	end
	registerPrompt(prompt, {
		category = category,
		focus = focus,
		relicId = relicId,
	})
	return model
end

--[[
	Take one exhibit off the floor for the rest of the round.

	The two origins part ways here and only here. A generated plinth is ours: it
	lives in roundFolder, has no life beyond this round, and dies on the claim
	exactly as it always has. An adopted plinth is the user's saved content and
	is only hidden — see setPlinthShown for why destroying it would be the one
	unrecoverable mistake available in this file.
]]
local function retirePlinth(specId: string, model: Model)
	if adoptedPlinths[specId] == model then
		setPlinthShown(model, false)
		return
	end
	model:Destroy()
end

local SUNSTONE_SPEC: RelicSpec = {
	id = "Sunstone",
	modelName = SUNSTONE_NAME,
	actionText = "Claim Sunstone",
	objectText = "A light the hotel cannot swallow",
	core = SUNSTONE_CORE,
	glow = SUNSTONE_GOLD,
	shape = Enum.PartType.Ball,
	lateral = 0,
}

--[[
	The other two thirds of the payday.

	Muscle forces the service door that opens the road to the vault, and Hacker
	gets the party through the keypads on the way. Before these, the room they
	opened held exactly one claimable and it belonged to Superman, so two of the
	three classes did the work and collected nothing.

	Each relic widens a limit its class already lives against rather than handing
	out a new verb, which keeps them easy to reason about and impossible to
	confuse with each other:

	  * Muscle can smash Broken and Jammed doors. The Ironhand drops the state
	    restriction, so a Normal keypad door gives way to a shoulder as well.
	  * Hacker can bypass Broken doors, anchored and facing the wall for five
	    seconds. The Cipher removes the anchor, which is the actual cost of the
	    ability -- HotelDoorService's own comment notes those five seconds are
	    "precisely when Joel catches people".

	Both are read as Player attributes by HotelDoorService, so nothing here has to
	know how a door works.
]]
type ClassRelic = {
	spec: RelicSpec,
	class: string,
	attribute: string,
	denial: string,
	claimLine: string,
	-- Which brass notice hangs over the plinth when the wrong class tries. A key
	-- into DisplayCaseConfig.Refusals, so the relic and the Sun Sword refuse on
	-- the same surface in the same voice rather than one plaque and one toast.
	refusal: string,
}

local CLASS_RELICS: { ClassRelic } = {
	{
		spec = {
			id = "Ironhand",
			modelName = "Ironhand",
			actionText = "Claim the Ironhand",
			objectText = "Cast for a hand that does not knock",
			core = Color3.fromRGB(255, 168, 132),
			glow = Color3.fromRGB(206, 74, 42),
			shape = Enum.PartType.Block,
			lateral = -7,
		},
		class = ClassDefinitions.MUSCLE,
		attribute = ClueConfig.MuscleRelicAttribute,
		denial = "The Ironhand does not lift for anyone but the muscle.",
		claimLine = "%s takes the Ironhand. No door in the hotel is shut to them now.",
		refusal = "Ironhand",
	},
	{
		spec = {
			id = "MasterCipher",
			modelName = "MasterCipher",
			actionText = "Claim the Master Cipher",
			objectText = "Every code the hotel ever issued",
			core = Color3.fromRGB(163, 255, 235),
			glow = Color3.fromRGB(48, 214, 190),
			shape = Enum.PartType.Cylinder,
			lateral = 7,
		},
		class = ClassDefinitions.HACKER,
		attribute = ClueConfig.HackerRelicAttribute,
		denial = "The cipher is meaningless to anyone who cannot read it.",
		claimLine = "%s carries the Master Cipher. Keypads no longer hold them still.",
		refusal = "MasterCipher",
	},
}

-- Every exhibit the treasury owns, Sunstone first. The claim rules differ per
-- relic; the question "does a saved model exist for this and is it showing?"
-- does not, so the reset sweep below walks this rather than the two tables the
-- claim paths maintain.
local RELIC_SPECS: { RelicSpec } = { SUNSTONE_SPEC }
for _, classRelic in CLASS_RELICS do
	table.insert(RELIC_SPECS, classRelic.spec)
end

--[[
	Put every saved exhibit back to its between-rounds state.

	Driven off the specs rather than off adoptedPlinths so it also catches a
	plinth this script body has never staged — which is exactly the state after a
	Studio re-run that interrupted a live round, where the old body left stones
	lit and the new body's tables start empty. Idempotent by construction, so
	calling it on an already-hidden treasury costs nothing.
]]
local function hideSavedPlinths()
	for _, spec in RELIC_SPECS do
		local model: Model? = adoptedPlinths[spec.id]
		if not model or not model:IsDescendantOf(Workspace) then
			adoptedPlinths[spec.id] = nil
			model = findSavedPlinth(spec)
		end
		if model then
			setPlinthShown(model, false)
		end
	end
end

local function findClassRelic(id: string?): ClassRelic?
	if not id then
		return nil
	end
	for _, relic in CLASS_RELICS do
		if relic.spec.id == id then
			return relic
		end
	end
	return nil
end

local function canStrikeJoel(player: Player): (boolean, Model?, BasePart?)
	local character = player.Character
	local root = rootFor(player)
	local joel = findJoel()
	local joelRoot = joel and joel:FindFirstChild("HumanoidRootPart")
	if not character or not root or not joel or not joelRoot or not joelRoot:IsA("BasePart") then
		return false, nil, nil
	end
	if
		joel:GetAttribute("HunterState") == "Downed"
		or (root.Position - joelRoot.Position).Magnitude > JoelConfig.DefeatRange
	then
		return false, joel, joelRoot
	end

	local origin = root.Position + Vector3.new(0, 1.2, 0)
	local target = joelRoot.Position + Vector3.new(0, 0.8, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true
	local hit = Workspace:Raycast(origin, target - origin, params)
	local visible = hit == nil or hit.Instance:IsDescendantOf(joel)
	return visible, joel, joelRoot
end

local function spawnExitCodeNote(position: Vector3)
	if exitCodeNote or not roundFolder then
		return
	end
	local notePosition = position - Vector3.new(0, 2.8, 0)
	local joel = findJoel()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if joel then { joel } else {}
	params.IgnoreWater = true
	local ground = Workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -14, 0), params)
	if ground then
		notePosition = ground.Position
	end
	local model, prompt = CluePropKit.makeNote(
		roundFolder,
		CFrame.new(notePosition) * CFrame.Angles(0, math.rad(-7), 0),
		"Read what Joel dropped"
	)
	model.Name = "ExitCodeNote"
	exitCodeNote = model
	registerPrompt(prompt, {
		category = "ExitCode",
		focus = promptFocus(prompt) or (model.PrimaryPart :: BasePart),
	})
	refreshPrompts()
	announce("Danger", "Joel is down. Something fell from his coat.")
end

local function completeLanceHold(player: Player, tool: Tool, revision: number, cancelled: () -> boolean)
	local started = os.clock()
	while os.clock() - started < JoelConfig.DefeatHoldSeconds do
		if cancelled() or tool.Parent ~= player.Character then
			return
		end
		local valid = canStrikeJoel(player)
		if not valid then
			reject(player, "Keep the light on Joel. Do not let the wall break the beam.")
			return
		end
		task.wait(0.1)
	end
	if cancelled() then
		return
	end
	local valid, joel, joelRoot = canStrikeJoel(player)
	local activeRound = roundState
	if not valid or not joel or not joelRoot or not activeRound or activeRound.phase ~= ClueConfig.PhaseVault then
		return
	end
	if joelWasDefeated then
		return
	end

	joelWasDefeated = true
	downedEndsAt = Workspace:GetServerTimeNow() + JoelConfig.DownedSeconds
	joelDefeat:Fire(player, revision)
	local replicatedEnd = joel:GetAttribute("DownedUntil")
	if typeof(replicatedEnd) == "number" and replicatedEnd > 0 then
		downedEndsAt = replicatedEnd
	end
	spawnExitCodeNote(joelRoot.Position)
	publishRound()
	refreshPrompts()
end

local function makeSolarLance(player: Player): Tool
	local tool = Instance.new("Tool")
	tool.Name = SOLAR_LANCE_NAME
	tool.ToolTip = `Hold the beam on Joel for {JoelConfig.DefeatHoldSeconds} seconds`
	tool.CanBeDropped = false

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.35, 4.6, 0.35)
	handle.Color = LANCE_GOLD
	handle.Material = Enum.Material.Metal
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool

	local tip = Instance.new("Part")
	tip.Name = "SolarTip"
	tip.Size = Vector3.new(0.7, 1.25, 0.7)
	tip.Color = LANCE_LIGHT
	tip.Material = Enum.Material.Neon
	tip.CanCollide = false
	tip.Massless = true
	tip.CFrame = handle.CFrame * CFrame.new(0, 2.85, 0)
	tip.Parent = tool
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = tip
	weld.Parent = tip

	local light = Instance.new("PointLight")
	light.Color = LANCE_LIGHT
	light.Brightness = 2
	light.Range = 14
	light.Parent = tip

	local activationRevision = 0
	local active = false
	local activatedConnection = tool.Activated:Connect(function()
		if active or joelWasDefeated or not lanceOwners[player] then
			return
		end
		local activeRound = roundState
		if not activeRound or activeRound.phase ~= ClueConfig.PhaseVault then
			return
		end
		local valid = canStrikeJoel(player)
		if not valid then
			reject(player, "Get closer and keep Joel in sight before raising the lance.")
			return
		end
		active = true
		activationRevision += 1
		local myRevision = activationRevision
		task.spawn(function()
			completeLanceHold(player, tool, myRevision, function(): boolean
				return not active or activationRevision ~= myRevision
			end)
			if activationRevision == myRevision then
				active = false
			end
		end)
	end)
	local deactivatedConnection = tool.Deactivated:Connect(function()
		active = false
		activationRevision += 1
	end)
	local ancestryConnection = tool.AncestryChanged:Connect(function(_, parent: Instance?)
		if parent == nil then
			active = false
			activationRevision += 1
			local connections = lanceConnections[tool]
			if connections then
				for _, connection in connections do
					connection:Disconnect()
				end
				lanceConnections[tool] = nil
			end
		end
	end)
	lanceConnections[tool] = { activatedConnection, deactivatedConnection, ancestryConnection }
	return tool
end

local function giveSolarLance(player: Player)
	if player.Parent ~= Players or not lanceOwners[player] then
		return
	end
	local character = player.Character
	local backpack = player:FindFirstChildOfClass("Backpack")
	if
		(character and character:FindFirstChild(SOLAR_LANCE_NAME))
		or (backpack and backpack:FindFirstChild(SOLAR_LANCE_NAME))
	then
		return
	end
	if backpack then
		makeSolarLance(player).Parent = backpack
	end
end

local function claimSunstone(player: Player, context: PromptContext)
	local activeRound = roundState
	if not activeRound or activeRound.phase ~= ClueConfig.PhaseVault or sunstoneClaimed then
		return
	end
	local vault = findVault()
	if
		not vault
		or vault:GetAttribute(ClueConfig.VaultUnlockedAttribute) ~= true
		or not inRange(player, context.focus)
	then
		return
	end
	local fallbackAvailable = fallbackReleased
		or (os.clock() - vaultOpenedAt >= ClueConfig.SupermanFallbackSeconds and not hasSuperman())
	if not ClassDefinitions.hasClass(player, ClassDefinitions.SUPERMAN) and not fallbackAvailable then
		reject(player, "The stone answers only the guest in the cape.")
		return
	end

	sunstoneClaimed = true
	lanceOwners[player] = true
	if sunstoneModel then
		-- Cleared either way: sunstoneModel means "on show and claimable", and
		-- unwatch relies on nil here to put the stone back on its pedestal when
		-- the lance owner leaves mid-round. adoptedPlinths keeps the reference a
		-- hidden saved model still needs.
		retirePlinth(SUNSTONE_SPEC.id, sunstoneModel)
		sunstoneModel = nil
	end
	giveSolarLance(player)
	publishRound()
	announce("Solved", `{player.DisplayName} carries the Sunstone's light.`)
	refreshPrompts()
end

--[[
	Claiming a class relic.

	Deliberately the same shape as claimSunstone, including the fallback: if
	nobody on the server holds the class after SupermanFallbackSeconds, the relic
	opens to anyone. A three-player server missing a Hacker should not be locked
	out of a third of its own payday.
]]
local function claimClassRelic(player: Player, context: PromptContext)
	local relic = findClassRelic(context.relicId)
	local activeRound = roundState
	if not relic or not activeRound or activeRound.phase ~= ClueConfig.PhaseVault then
		return
	end
	if relicClaimed[relic.spec.id] then
		return
	end
	local vault = findVault()
	if
		not vault
		or vault:GetAttribute(ClueConfig.VaultUnlockedAttribute) ~= true
		or not inRange(player, context.focus)
	then
		return
	end

	-- Hard class lock, no fallback. This used to open to anybody after
	-- SupermanFallbackSeconds if nobody on the server held the class, on the
	-- reasoning that a short-handed lobby should not lose a third of its payday.
	-- That reasoning does not survive what these two became: they are no longer
	-- abstract "relics" but a Hacker's laptop and a Muscle's gauntlet, worn on
	-- the body of the class they belong to, and a Superman walking out wearing
	-- the other man's glove reads as a bug rather than as a consolation.
	--
	-- Nothing is lost by locking them. Neither relic is on the critical path:
	-- the vault is already open by the time they can be claimed, the treasure is
	-- baggable without either, and the exit needs only the code. An unclaimed
	-- relic is an exhibit nobody could use, which is what it should look like.
	--
	-- The Sunstone keeps ITS fallback deliberately -- see claimSunstone. That
	-- one hands over the Solar Lance, which is the only answer to Joel, and
	-- locking a server with no Superman out of its only weapon is a different
	-- proposition entirely.
	-- Silent, unlike the class refusal below. A sealed case means the prompt was
	-- never on screen, so anybody reaching this line is a client asking for
	-- something it was not offered -- and a plaque would be answering a question
	-- no honest player asked.
	if caseSealed(relicModels[relic.spec.id] or adoptedPlinths[relic.spec.id]) then
		return
	end

	if not ClassDefinitions.hasClass(player, relic.class) then
		-- The brass plaque rather than reject()'s toast. The toast is the clue
		-- desk answering a submitted answer; this is an object in the room
		-- refusing the hand on it, and it belongs over that object where the
		-- mallet's refusal and the Sun Sword's already hang.
		local focus = context.focus
		if focus and focus:IsA("BasePart") then
			refusedEvent:FireClient(player, focus, relic.refusal)
		else
			reject(player, relic.denial)
		end
		return
	end

	relicClaimed[relic.spec.id] = true
	player:SetAttribute(relic.attribute, true)
	local model = relicModels[relic.spec.id]
	if model then
		retirePlinth(relic.spec.id, model)
		relicModels[relic.spec.id] = nil
	end
	publishRound()
	announce("Solved", string.format(relic.claimLine, player.DisplayName))
	refreshPrompts()
end

--[[
	Open the treasury for this round.

	Named for what it does to the round, not for how the models arrive: each
	exhibit is staged from the saved place if the user has built one there and
	generated only otherwise. The per-relic guards are unchanged, so this stays
	safe to re-enter -- unwatch calls it again mid-round when a lance owner
	leaves, and an exhibit already on show is left alone.

	The old `if sunstoneModel then return end` guard has moved onto the Sunstone
	itself. It used to also skip the class relics, which meant a missing relic
	could never be restored while the Sunstone was standing.
]]
local function spawnSunstone(vault: Model)
	local anchor = Workspace:FindFirstChild("VaultAnchor")
	local base = if anchor and anchor:IsA("BasePart")
		then anchor.CFrame * CFrame.new(0, 0, 28)
		else vault:GetPivot() * CFrame.new(0, 0, 18)

	if not sunstoneClaimed and not sunstoneModel then
		sunstoneModel = stagePlinth(SUNSTONE_SPEC, base, "Sunstone", nil)
	end

	-- The other two stand either side of it, so the treasury reads as three
	-- exhibits rather than one prize and some scenery. That layout only applies
	-- to generated plinths; adopted ones stand wherever the user put them, which
	-- is the entire point of adopting them.
	for _, relic in CLASS_RELICS do
		if not relicClaimed[relic.spec.id] and not relicModels[relic.spec.id] then
			local staged =
				stagePlinth(relic.spec, base * CFrame.new(relic.spec.lateral, 0, 0), "ClassRelic", relic.spec.id)
			if staged then
				relicModels[relic.spec.id] = staged
			end
		end
	end

	refreshPrompts()
end

local function submitVaultCode(player: Player, answer: string, prompt: ProximityPrompt): boolean
	local activeRound = roundState
	local focus = promptFocus(prompt)
	local vault = findVault()
	if
		not activeRound
		or activeRound.phase ~= ClueConfig.PhaseVault
		or not focus
		or not vault
		or not prompt:IsDescendantOf(vault)
		or not prompt:IsDescendantOf(Workspace)
		or not inRange(player, focus)
	then
		return false
	end
	if vault:GetAttribute(ClueConfig.VaultUnlockedAttribute) == true then
		reject(player, "The vault already knows the five marks.")
		return true
	end
	if onCooldown(player) then
		return true
	end
	if not ClueConfig.answerMatches(answer, activeRound.code) then
		punish(player, focus.Position, "The steel refuses that sequence.")
		return true
	end

	cooldownReadyAt[player] = 0
	vault:SetAttribute(ClueConfig.VaultUnlockedAttribute, true)
	vaultOpenedAt = os.clock()
	spawnSunstone(vault)
	publishRound()
	resultEvent:FireClient(player, {
		ok = true,
		reason = "The locks withdraw. Something inside is still burning.",
		digitsKnown = ClueChain.digitsKnown(activeRound),
		nextRiddle = "Take the Sunstone from the treasury. The cape has first claim.",
	})
	announce("Solved", "The vault is open. The light inside belongs in stronger hands.")
	joelNoise:Fire(focus.Position, ClueConfig.NoiseRadiusSolve)
	refreshPrompts()
	return true
end

-- Prompt interactions -------------------------------------------------------

local function revealExitCode(player: Player, context: PromptContext)
	local activeRound = roundState
	if
		not activeRound
		or activeRound.phase ~= ClueConfig.PhaseVault
		or not joelWasDefeated
		or not inRange(player, context.focus)
	then
		return
	end

	clueState:SetAttribute(ClueConfig.ExitCodeKnownAttribute, true)
	activeRound.phase = ClueConfig.PhaseEscape
	clueState:SetAttribute(ClueConfig.EscapeEndsAtAttribute, downedEndsAt)
	escapeExpired = false
	for _, exit in CollectionService:GetTagged(ClueConfig.ExitDoorTag) do
		if exit:IsA("Model") and exit:IsDescendantOf(Workspace) then
			exit:SetAttribute(ClueConfig.DoorCodeAttribute, activeRound.exitCode)
		end
	end
	setEmergencyReturn(true)

	openEvent:FireClient(player, {
		nodeId = "ExitCode",
		kind = "Note",
		riddle = `The last numbers on the page are {activeRound.exitCode}. Do not leave them here.`,
		prompt = `EXIT CODE  ·  {activeRound.exitCode}`,
	})
	resultEvent:FireClient(player, {
		ok = true,
		reason = `The exit code is {activeRound.exitCode}.`,
		digitsKnown = ClueChain.digitsKnown(activeRound),
		nextRiddle = "Return to the lobby. The Rooms lift will answer once.",
	})
	publishRound()
	refreshPrompts()
	announce("Danger", `EXIT CODE {activeRound.exitCode} · THE ROOMS LIFT CAN RETURN · RUN`)
end

handlePrompt = function(prompt: ProximityPrompt, player: Player)
	if not prompt:IsDescendantOf(Workspace) or not CollectionService:HasTag(prompt, ClueConfig.PromptTag) then
		return
	end
	local context = promptContexts[prompt]
	local focus = promptFocus(prompt)
	if not context or not focus or focus ~= context.focus then
		return
	end
	if context.category == "StartingNote" then
		local activeRound = roundState
		local site = context.site
		if
			not activeRound
			or activeRound.phase ~= ClueConfig.PhaseHunt
			or activeRound.index ~= 1
			or not site
			or not siteStillValid(site, "ReceptionDesk")
			or not inRange(player, focus)
		then
			return
		end
		openEvent:FireClient(player, {
			nodeId = "StartingNote",
			kind = "Note",
			riddle = nodeRiddle(1),
			prompt = "The first entry names where the hunt begins.",
		})
		return
	elseif context.category == "Sunstone" then
		claimSunstone(player, context)
		return
	elseif context.category == "ClassRelic" then
		claimClassRelic(player, context)
		return
	elseif context.category == "ExitCode" then
		revealExitCode(player, context)
		return
	end
	if not nodeContextIsCurrent(player, prompt, context) then
		return
	end
	if context.category == "LeverToggle" then
		local leverIndex = context.leverIndex
		if
			not leverIndex
			or not CollectionService:HasTag(context.focus, ClueConfig.LeverTag)
			or context.focus:GetAttribute(ClueConfig.LeverIndexAttribute) ~= leverIndex
			or prompt:GetAttribute(ClueConfig.LeverIndexAttribute) ~= leverIndex
		then
			return
		end
	elseif context.category == "Carry" then
		local carry = context.carry
		if
			not carry
			or not CollectionService:HasTag(context.focus, ClueConfig.ReceptacleTag)
			or context.focus:GetAttribute(ClueConfig.CarryIdAttribute) ~= carry.id
			or prompt:GetAttribute(ClueConfig.CarryIdAttribute) ~= carry.id
		then
			return
		end
	end

	local index = context.nodeIndex
	if not index then
		return
	end
	if context.category == "Note" then
		if solveNode(player, index, focus.Position) then
			openEvent:FireClient(player, {
				nodeId = index,
				kind = "Note",
				riddle = currentRiddle(),
				prompt = "A mark surfaced in the margin.",
			})
		end
	elseif context.category == "Cipher" then
		local cipher = ciphersByIndex[index]
		if not cipher then
			return
		end
		openCipherIndex[player] = index
		openEvent:FireClient(player, {
			nodeId = index,
			kind = "Cipher",
			riddle = cipher.question,
			prompt = "Type only what this hotel can prove.",
		})
	elseif context.category == "LeverHandle" then
		local breaker = context.breaker
		if not breaker or os.clock() < breaker.lockoutUntil or onCooldown(player) then
			return
		end
		if breakerMatches(breaker) then
			for _, lever in breaker.panel.levers do
				lever.led.Color = LED_GOOD
			end
			ContainerKit.setOpen(breaker.panel.hatchAnimated, true)
			solveNode(player, index, focus.Position)
		else
			breaker.lockoutUntil = os.clock() + ClueConfig.LeverLockoutSeconds
			resetBreaker(breaker)
			punish(player, focus.Position, "The breaker rejects the pattern. Every lever slams down.")
			refreshPrompts()
		end
	elseif context.category == "Search" then
		local search = context.search
		if search and search.animated.isOpen then
			solveNode(player, index, focus.Position)
		end
	elseif context.category == "Carry" then
		local carry = context.carry
		if not carry or not carriedInstance(player, carry.id) then
			reject(player, "The empty slot is waiting for what belongs here.")
			return
		end
		sackConsume:Fire(player, carry.id)
		solveNode(player, index, focus.Position)
	elseif context.category == "LeverToggle" then
		-- CluePropKit's ContainerKit registration owns the actual throw. Reaching
		-- this branch is still useful: every authority gate above has been checked.
		return
	end
end

-- Remote grading ------------------------------------------------------------

submitEvent.OnServerEvent:Connect(function(player: Player, answer: any)
	if typeof(answer) ~= "string" or #answer > ClueConfig.MaxAnswerLength then
		return
	end
	local activeRound = roundState
	if not activeRound then
		return
	end

	local vaultPrompt = findVaultPrompt()
	local vaultFocus = if vaultPrompt then promptFocus(vaultPrompt) else nil
	if vaultPrompt and vaultFocus and vaultPrompt:IsDescendantOf(Workspace) and inRange(player, vaultFocus) then
		if activeRound.phase == ClueConfig.PhaseVault and submitVaultCode(player, answer, vaultPrompt) then
			return
		end
		reject(player, "The panel has nothing to accept until all five marks are known.")
		return
	end

	local index = openCipherIndex[player]
	local node = ClueChain.currentNode(activeRound)
	if
		activeRound.phase ~= ClueConfig.PhaseHunt
		or not index
		or not node
		or index ~= activeRound.index
		or node.kind ~= "Cipher"
	then
		return
	end
	local cipher = ciphersByIndex[index]
	local site = sitesById[node.siteId]
	if not cipher or not site or not siteStillValid(site, node.siteId) or not inRange(player, site) then
		return
	end
	if onCooldown(player) then
		return
	end
	if not ClueConfig.answerMatches(answer, cipher.answer) then
		punish(player, site.Position, "That answer does not belong to this hotel.")
		return
	end
	solveNode(player, index, site.Position)
end)

-- Prop construction ---------------------------------------------------------

local function gatherSites(): ({ [string]: BasePart }, { string })
	local byId: { [string]: BasePart } = {}
	local ids: { string } = {}
	for _, instance in CollectionService:GetTagged(ClueConfig.SiteTag) do
		if not instance:IsA("BasePart") or not instance:IsDescendantOf(Workspace) then
			continue
		end
		local id = instance:GetAttribute(ClueConfig.SiteIdAttribute)
		if typeof(id) ~= "string" or not ClueConfig.findSite(id) or byId[id] then
			continue
		end
		byId[id] = instance
		table.insert(ids, id)
	end
	table.sort(ids)
	return byId, ids
end

local function actOneSiteCount(ids: { string }): number
	local count = 0
	for _, id in ids do
		local site = ClueConfig.findSite(id)
		if site and site.actOne then
			count += 1
		end
	end
	return count
end

local function buildNodeProps(activeRound: ClueChain.State, folder: Folder, rng: Random)
	for index, node in activeRound.nodes do
		local site = sitesById[node.siteId]
		if not site then
			continue
		end
		assert(
			ClueConfig.siteAllowsKind(node.siteId, node.kind),
			`Clue node {index} cannot place {node.kind} at {node.siteId}`
		)
		local base = site.CFrame
		riddlesByIndex[index] = node.riddle

		if node.kind == "Note" or node.kind == "Cipher" then
			local model, prompt =
				CluePropKit.makeNote(folder, base, if node.kind == "Cipher" then "Study cipher" else "Read note")
			model.Name = `Clue{index}_{node.kind}`
			markNode(model, index, node.kind)
			registerPrompt(prompt, {
				category = node.kind,
				focus = promptFocus(prompt) or (model.PrimaryPart :: BasePart),
				nodeIndex = index,
				nodeKind = node.kind,
				site = site,
			})
			if node.kind == "Cipher" then
				ciphersByIndex[index] = ClueConfig.Ciphers[rng:NextInteger(1, #ClueConfig.Ciphers)]
			end
		elseif node.kind == "Lever" then
			local panel: BreakerPanel = CluePropKit.makeBreakerPanel(folder, base, ClueConfig.LeverCount)
			panel.model.Name = `Clue{index}_Breaker`
			markNode(panel.model, index, node.kind)
			local required, ordered = choosePattern(rng)
			local breaker: BreakerState = {
				nodeIndex = index,
				panel = panel,
				required = required,
				lockoutUntil = 0,
			}
			breakersByIndex[index] = breaker
			riddlesByIndex[index] = `{node.riddle} The maintenance log circles switches {table.concat(ordered, ", ")}.`
			for _, lever in panel.levers do
				markNode(lever.part, index, node.kind)
				registerPrompt(lever.prompt, {
					category = "LeverToggle",
					focus = promptFocus(lever.prompt) or lever.part,
					nodeIndex = index,
					nodeKind = node.kind,
					site = site,
					breaker = breaker,
					leverIndex = lever.index,
				})
			end
			markNode(panel.handle, index, node.kind)
			registerPrompt(panel.handlePrompt, {
				category = "LeverHandle",
				focus = promptFocus(panel.handlePrompt) or panel.handle,
				nodeIndex = index,
				nodeKind = node.kind,
				site = site,
				breaker = breaker,
			})
		elseif node.kind == "Search" then
			local model, prompt, animated = CluePropKit.makeSearchContainer(folder, base, "Unlogged hotel crate")
			model.Name = `Clue{index}_Search`
			markNode(model, index, node.kind)
			local search: SearchState = {
				nodeIndex = index,
				model = model,
				prompt = prompt,
				animated = animated,
			}
			searchesByIndex[index] = search
			registerPrompt(prompt, {
				category = "Search",
				focus = promptFocus(prompt) or (model.PrimaryPart :: BasePart),
				nodeIndex = index,
				nodeKind = node.kind,
				site = site,
				search = search,
			})
		elseif node.kind == "Carry" then
			local sourceIndex = index
			if index > 1 then
				local previous = activeRound.nodes[index - 1]
				local crossesLobbyBoundary = ClueConfig.LobbySiteIds[previous.siteId]
					and not ClueConfig.LobbySiteIds[node.siteId]
				if not crossesLobbyBoundary then
					sourceIndex = index - 1
				end
			end
			local sourceNode = activeRound.nodes[sourceIndex]
			local sourceSite = sitesById[sourceNode.siteId] or site
			local carryId = `Round{roundRevision}_Node{index}`
			local sourceCFrame = sourceSite.CFrame * CFrame.new(-3.5, 0, 0)
			local displayName = "Service Keycard"
			local item = CluePropKit.makeCarryItem(folder, sourceCFrame, carryId, displayName)
			item:SetAttribute(SackConfig.LockedAttribute, index ~= activeRound.index)
			local _, prompt = CluePropKit.makeReceptacle(folder, base * CFrame.new(3.5, 0, 0), carryId)
			item.Name = `Clue{index}_ServiceKeycard`
			markNode(item, index, node.kind)
			local carry: CarryState = {
				nodeIndex = index,
				id = carryId,
				item = item,
				prompt = prompt,
				sourceCFrame = sourceCFrame,
				displayName = displayName,
			}
			carriesByIndex[index] = carry
			if sourceIndex == index then
				riddlesByIndex[index] =
					`{node.riddle} A Service Keycard lies nearby. Bag it, then slot it into the reader.`
			else
				riddlesByIndex[index] =
					`{node.riddle} Bring the Service Keycard left at {readableSiteId(sourceNode.siteId)}.`
			end
			registerPrompt(prompt, {
				category = "Carry",
				focus = promptFocus(prompt) or site,
				nodeIndex = index,
				nodeKind = node.kind,
				site = site,
				carry = carry,
			})
		end
	end
end

local function buildStartingNote(folder: Folder)
	local reception = sitesById.ReceptionDesk
	if not reception then
		return
	end
	local model, prompt =
		CluePropKit.makeNote(folder, reception.CFrame * CFrame.new(3.8, 0, 0), "Read the starting note")
	model.Name = "ClueStartingNote"
	registerPrompt(prompt, {
		category = "StartingNote",
		focus = promptFocus(prompt) or (model.PrimaryPart :: BasePart),
		site = reception,
	})
end

local function clearLances()
	for tool, connections in lanceConnections do
		for _, connection in connections do
			connection:Disconnect()
		end
		lanceConnections[tool] = nil
		if tool.Parent then
			tool:Destroy()
		end
	end
	for player in lanceOwners do
		lanceOwners[player] = nil
	end
	-- Relic privileges are per-round like the lance. Clearing the tables alone
	-- would leave the attribute set on the Player, so a Muscle who claimed the
	-- Ironhand once would keep opening Normal doors in every later round.
	for _, player in Players:GetPlayers() do
		for _, relic in CLASS_RELICS do
			player:SetAttribute(relic.attribute, nil)
		end
	end
	-- A Studio hot re-run has no connection registry for tools made by the old
	-- script body. Their name is service-owned, so remove those copies too.
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local backpack = player:FindFirstChildOfClass("Backpack")
		for _, parent in { character, backpack } do
			if not parent then
				continue
			end
			local stale = parent:FindFirstChild(SOLAR_LANCE_NAME)
			if stale and stale:IsA("Tool") then
				stale:Destroy()
			end
		end
	end
end

local function repairMissingCarries()
	local activeRound = roundState
	local folder = roundFolder
	if not activeRound or activeRound.phase ~= ClueConfig.PhaseHunt or not folder then
		return
	end
	for index, carry in carriesByIndex do
		local node = activeRound.nodes[index]
		if not node or node.solved or carry.item.Parent or anyoneCarries(carry.id) then
			continue
		end
		local replacement = CluePropKit.makeCarryItem(folder, carry.sourceCFrame, carry.id, carry.displayName)
		replacement.Name = `Clue{index}_ServiceKeycard`
		replacement:SetAttribute(SackConfig.LockedAttribute, index ~= activeRound.index)
		markNode(replacement, index, node.kind)
		carry.item = replacement
	end
end

local function clearRoundProps()
	local carryIds: { [string]: boolean } = {}
	local carryItems: { Instance } = {}
	for _, carry in carriesByIndex do
		carryIds[carry.id] = true
		table.insert(carryItems, carry.item)
	end
	-- Also catches a carry item left by a previous hot run, for which this new
	-- script body never had a CarryState record.
	for _, item in CollectionService:GetTagged(ClueConfig.CarryItemTag) do
		local carryId = item:GetAttribute(ClueConfig.CarryIdAttribute)
		if typeof(carryId) == "string" then
			carryIds[carryId] = true
		end
		table.insert(carryItems, item)
	end
	for carryId in carryIds do
		for _, player in Players:GetPlayers() do
			sackConsume:Fire(player, carryId)
		end
	end
	-- A quest item can leave both the round folder and the private sack vault
	-- when its owner drops it. The consume bridge clears private entries first;
	-- this second half removes that same round's loose world copy.
	for _, item in carryItems do
		if item.Parent then
			item:Destroy()
		end
	end
	clearLances()
	if roundFolder and roundFolder.Parent then
		roundFolder:Destroy()
	end
	roundFolder = nil
	for _, child in Workspace:GetChildren() do
		if child.Name == ROUND_FOLDER_NAME then
			child:Destroy()
		end
	end
	local ownedPrompts: { ProximityPrompt } = {}
	for prompt, context in promptContexts do
		if
			context.nodeIndex
			or context.category == "StartingNote"
			or context.category == "Sunstone"
			or context.category == "ClassRelic"
			or context.category == "ExitCode"
		then
			table.insert(ownedPrompts, prompt)
		end
	end
	for _, prompt in ownedPrompts do
		teardownPrompt(prompt)
	end
	table.clear(riddlesByIndex)
	table.clear(ciphersByIndex)
	table.clear(breakersByIndex)
	table.clear(searchesByIndex)
	table.clear(carriesByIndex)
	sunstoneModel = nil
	table.clear(relicModels)
	exitCodeNote = nil
	-- Last, and deliberately after the prompts are unregistered: the generated
	-- plinths went down with roundFolder above, but the adopted ones are still
	-- standing in the user's chamber, possibly lit and possibly already claimed.
	-- Hiding them here is what makes a round reset mean the same thing for both
	-- origins -- present, dark, and waiting for the next PhaseVault -- without a
	-- single :Destroy() reaching content the user owns.
	hideSavedPlinths()
end

local function resetExternalState()
	local vault = findVault()
	if vault then
		local anchor = Workspace:FindFirstChild("VaultAnchor")
		if anchor and anchor:IsA("BasePart") then
			local evacuees: { BasePart } = {}
			for _, player in Players:GetPlayers() do
				local root = rootFor(player)
				if not root then
					continue
				end
				local localPosition = anchor.CFrame:PointToObjectSpace(root.Position)
				if
					math.abs(localPosition.X) <= 22
					and localPosition.Y >= -2
					and localPosition.Y <= 32
					and localPosition.Z >= -4
					and localPosition.Z <= 45
				then
					table.insert(evacuees, root)
				end
			end
			for index, root in evacuees do
				local x = (index - (#evacuees + 1) / 2) * 3
				root.CFrame = anchor.CFrame * CFrame.new(x, 3, -10)
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
			end
		end
		vault:SetAttribute(ClueConfig.VaultUnlockedAttribute, false)
	end
	for _, exit in CollectionService:GetTagged(ClueConfig.ExitDoorTag) do
		if exit:IsA("Model") and exit:IsDescendantOf(Workspace) then
			exit:SetAttribute(ClueConfig.DoorCodeAttribute, LOCKED_EXIT_CODE)
		end
	end
	setEmergencyReturn(false)
	joelRevive:Fire()
end

rebuildRound = function()
	if resetting then
		return
	end
	resetting = true
	roundRevision += 1
	clearRoundProps()
	resetExternalState()

	local byId, ids = gatherSites()
	local eligibleCount = actOneSiteCount(ids)
	if eligibleCount < ClueConfig.ChainLength then
		warn(`[ClueService] only {eligibleCount} valid Act I clue sites remain; round rebuild aborted`)
		resetting = false
		return
	end
	sitesById = byId

	local rng = Random.new()
	local built = ClueChain.build(ids, rng)
	for _ = 2, ROUTE_REROLL_ATTEMPTS do
		if routeKey(built) ~= previousRouteKey then
			break
		end
		built = ClueChain.build(ids, rng)
	end
	previousRouteKey = routeKey(built)
	roundState = built

	local folder = Instance.new("Folder")
	folder.Name = ROUND_FOLDER_NAME
	folder.Parent = Workspace
	roundFolder = folder
	buildNodeProps(built, folder, rng)
	buildStartingNote(folder)

	vaultOpenedAt = -math.huge
	fallbackReleased = false
	fallbackAnnounced = false
	sunstoneClaimed = false
	table.clear(relicClaimed)
	joelWasDefeated = false
	downedEndsAt = 0
	escapeExpired = false
	clueState:SetAttribute(ClueConfig.ExitCodeKnownAttribute, false)
	clueState:SetAttribute(ClueConfig.EscapeEndsAtAttribute, 0)
	for player in cooldownReadyAt do
		cooldownReadyAt[player] = 0
		openCipherIndex[player] = nil
	end
	publishRound()
	refreshPrompts()
	resetting = false
end

-- Exit door -----------------------------------------------------------------

local function doorIsOpen(binding: ExitBinding): boolean
	local hinge = binding.hinge
	local closed = binding.closedCFrame
	if not hinge or not closed or not hinge.Parent then
		return false
	end
	local lookDot = math.abs(hinge.CFrame.LookVector:Dot(closed.LookVector))
	local rightDot = math.abs(hinge.CFrame.RightVector:Dot(closed.RightVector))
	return math.min(lookDot, rightDot) < 0.85
end

local function teardownExit(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	local binding = exitBindings[instance]
	if not binding then
		return
	end
	binding.connection:Disconnect()
	if binding.ownsTrigger and binding.trigger.Parent then
		binding.trigger:Destroy()
	end
	exitBindings[instance] = nil
end

local function setupExit(instance: Instance)
	if not instance:IsA("Model") or not instance:IsDescendantOf(Workspace) then
		return
	end
	teardownExit(instance)
	local leaf = instance:FindFirstChild("Leaf")
	local core = leaf and leaf:FindFirstChild("Core")
	local hingeValue = leaf and leaf:FindFirstChild("Hinge")
	local hinge = if hingeValue and hingeValue:IsA("BasePart") then hingeValue else nil
	if not hinge then
		warn(`[ClueService] {instance:GetFullName()} is tagged as an exit but has no Leaf.Hinge`)
	end

	local authoredTrigger = instance:FindFirstChild("ExitTrigger", true)
	local ownsTrigger = not (authoredTrigger and authoredTrigger:IsA("BasePart"))
	local trigger: BasePart
	if authoredTrigger and authoredTrigger:IsA("BasePart") then
		trigger = authoredTrigger
	else
		local generated = Instance.new("Part")
		generated.Name = EXIT_TRIGGER_NAME
		generated.Anchored = true
		generated.CanCollide = false
		generated.CanQuery = false
		generated.CanTouch = true
		generated.Transparency = 1
		if core and core:IsA("BasePart") then
			generated.Size =
				Vector3.new(math.max(3, core.Size.X), math.max(6, core.Size.Y), math.max(4.5, core.Size.Z + 4))
			generated.CFrame = core.CFrame
		else
			local boxCFrame, boxSize = instance:GetBoundingBox()
			generated.Size = Vector3.new(math.max(4, math.min(boxSize.X, 10)), math.max(6, boxSize.Y), 6)
			generated.CFrame = boxCFrame
		end
		generated.Parent = instance
		trigger = generated
	end

	local binding: ExitBinding
	local connection = trigger.Touched:Connect(function(hit: BasePart)
		local activeRound = roundState
		if
			not activeRound
			or activeRound.phase ~= ClueConfig.PhaseEscape
			or instance:GetAttribute(ClueConfig.DoorCodeAttribute) ~= activeRound.exitCode
		then
			return
		end
		if not binding or not doorIsOpen(binding) then
			return
		end
		local character = hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		if player and rootFor(player) then
			winRound(player)
		end
	end)
	binding = {
		model = instance,
		hinge = hinge,
		closedCFrame = if hinge then hinge.CFrame else nil,
		trigger = trigger,
		ownsTrigger = ownsTrigger,
		connection = connection,
	}
	exitBindings[instance] = binding

	local activeRound = roundState
	instance:SetAttribute(
		ClueConfig.DoorCodeAttribute,
		if activeRound and activeRound.phase == ClueConfig.PhaseEscape then activeRound.exitCode else LOCKED_EXIT_CODE
	)
end

--[[
	What a player actually got out of the building.

	SackService parks bagged items in ServerStorage.SackVault under a folder
	named for the UserId, and hands them back intact on a drop, so the sack is
	readable from here without SackService having to expose its packs table.

	Only what is still in the sack at the door counts. Anything dropped to free a
	slot for bandages, or lost with a body Joel dragged off, is money left in the
	hotel -- which is the whole point of making treasure compete with medical
	supplies for ten slots.
]]
local function carriedLootValue(player: Player): number
	local sackVault = ServerStorage:FindFirstChild("SackVault")
	local folder = sackVault and sackVault:FindFirstChild(tostring(player.UserId))
	if not folder then
		return 0
	end
	local total = 0
	for _, item in folder:GetDescendants() do
		local value = item:GetAttribute(ClueConfig.LootValueAttribute)
		if type(value) == "number" then
			total += value
		end
	end
	return total
end

winRound = function(player: Player)
	local activeRound = roundState
	if not activeRound or activeRound.phase ~= ClueConfig.PhaseEscape then
		return
	end
	activeRound.phase = ClueConfig.PhaseWon
	publishRound()
	refreshPrompts()

	-- Tally every survivor, not just whoever happened to reach the door first:
	-- the escape is a group effort and the haul should read like one.
	local haul = 0
	local carriers = 0
	for _, other in Players:GetPlayers() do
		local value = carriedLootValue(other)
		other:SetAttribute(ClueConfig.LootScoreAttribute, value)
		if value > 0 then
			haul += value
			carriers += 1
		end
	end

	announce("Won", `{player.DisplayName} got the lobby door open. The hotel lost this round.`)
	if haul > 0 then
		announce(
			"Won",
			string.format(
				"%d in treasure walked out with %d %s.",
				haul,
				carriers,
				if carriers == 1 then "guest" else "guests"
			)
		)
	else
		announce("Won", "Not one bar of gold made it out of the building.")
	end
	local revision = roundRevision
	task.delay(ROUND_RESET_DELAY, function()
		if revision == roundRevision and roundState and roundState.phase == ClueConfig.PhaseWon then
			rebuildRound()
		end
	end)
end

-- Player lifecycle ----------------------------------------------------------

local function watch(player: Player)
	if playerConnections[player] then
		return
	end
	cooldownReadyAt[player] = 0
	local connections: { RBXScriptConnection } = {}
	playerConnections[player] = connections
	table.insert(
		connections,
		player.CharacterAdded:Connect(function()
			task.defer(function()
				giveSolarLance(player)
			end)
		end)
	)
end

local function unwatch(player: Player)
	local ownedLance = lanceOwners[player] == true
	local connections = playerConnections[player]
	if connections then
		for _, connection in connections do
			connection:Disconnect()
		end
	end
	playerConnections[player] = nil
	cooldownReadyAt[player] = nil
	openCipherIndex[player] = nil
	lanceOwners[player] = nil
	if ownedLance and not joelWasDefeated and roundState and roundState.phase == ClueConfig.PhaseVault then
		sunstoneClaimed = false
		local vault = findVault()
		if vault then
			spawnSunstone(vault)
		end
		announce("Danger", "The Sunstone returned to its pedestal.")
	end
end

for _, player in Players:GetPlayers() do
	watch(player)
end
Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(unwatch)

-- Tags and heartbeat --------------------------------------------------------

for _, instance in CollectionService:GetTagged(ClueConfig.PromptTag) do
	setupPrompt(instance)
end
CollectionService:GetInstanceAddedSignal(ClueConfig.PromptTag):Connect(setupPrompt)
CollectionService:GetInstanceRemovedSignal(ClueConfig.PromptTag):Connect(teardownPrompt)

for _, instance in CollectionService:GetTagged(ClueConfig.ExitDoorTag) do
	setupExit(instance)
end
CollectionService:GetInstanceAddedSignal(ClueConfig.ExitDoorTag):Connect(setupExit)
CollectionService:GetInstanceRemovedSignal(ClueConfig.ExitDoorTag):Connect(teardownExit)

CollectionService:GetInstanceAddedSignal(ClueConfig.ElevatorCabTag):Connect(function(instance: Instance)
	local activeRound = roundState
	if
		activeRound
		and activeRound.phase == ClueConfig.PhaseEscape
		and instance:IsA("Model")
		and instance:GetAttribute(ClueConfig.CabIdAttribute) == "Rooms"
	then
		instance:SetAttribute(ClueConfig.PartnerAttribute, "Lobby")
	end
end)

local siteDeadline = os.clock() + STARTUP_SITE_TIMEOUT
local startupSites, startupIds = gatherSites()
while actOneSiteCount(startupIds) < ClueConfig.ChainLength and os.clock() < siteDeadline do
	task.wait(0.25)
	startupSites, startupIds = gatherSites()
end
local startupEligibleCount = actOneSiteCount(startupIds)
if startupEligibleCount < ClueConfig.ChainLength then
	warn(`[ClueService] needs {ClueConfig.ChainLength} tagged Act I sites, but only {startupEligibleCount} arrived`)
	return
end
sitesById = startupSites

rebuildRound()

local heartbeatAccumulator = 0
RunService.Heartbeat:Connect(function(delta: number)
	heartbeatAccumulator += delta
	if heartbeatAccumulator < HEARTBEAT_INTERVAL then
		return
	end
	heartbeatAccumulator = 0

	local activeRound = roundState
	if not activeRound then
		return
	end
	if
		activeRound.phase == ClueConfig.PhaseVault
		and vaultOpenedAt > -math.huge
		and not sunstoneClaimed
		and not fallbackReleased
		and os.clock() - vaultOpenedAt >= ClueConfig.SupermanFallbackSeconds
		and not hasSuperman()
	then
		fallbackReleased = true
		if not fallbackAnnounced then
			fallbackAnnounced = true
			announce("Danger", "No cape answered. The Sunstone will accept any living hand.")
		end
	end

	if activeRound.phase == ClueConfig.PhaseEscape and not escapeExpired then
		local endsAt = clueState:GetAttribute(ClueConfig.EscapeEndsAtAttribute)
		if typeof(endsAt) == "number" and Workspace:GetServerTimeNow() >= endsAt then
			escapeExpired = true
			announce("Danger", "Joel is moving again. The lobby door is still your only way out.")
		end
	end
	repairMissingCarries()
	refreshPrompts()
end)

print(`[ClueService] ready — {#startupIds} sites, chain of {ClueConfig.ChainLength}.`)
