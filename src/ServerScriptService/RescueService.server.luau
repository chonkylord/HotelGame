--!strict
-- Network, prompt, and lifecycle boundary for the two-strike rescue loop.
-- RescueController owns every state transition and physical constraint; this
-- service validates player intent before handing it across that boundary.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local ClueConfig = require(ReplicatedStorage:WaitForChild("ClueConfig"))
local RescueConfig = require(ReplicatedStorage:WaitForChild("RescueConfig"))

type RescueControllerApi = {
	initializePlayer: (player: Player) -> (),
	resetPlayer: (player: Player) -> (),
	resetRound: () -> (),
	getState: (player: Player) -> string,
	revive: (reviver: Player, target: Player) -> (boolean, string?),
	toggleCarry: (carrier: Player, target: Player?) -> (boolean, string?),
	dropCarry: (carrier: Player) -> boolean,
}

local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing then
		assert(existing:IsA("Folder"), `{existing:GetFullName()} must be a Folder`)
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function ensureRemote(parent: Instance, name: string): RemoteEvent
	local existing = parent:FindFirstChild(name)
	if existing then
		assert(existing:IsA("RemoteEvent"), `{existing:GetFullName()} must be a RemoteEvent`)
		return existing
	end
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = parent
	return event
end

local remotes = ensureFolder(ReplicatedStorage, RescueConfig.RemotesFolder)
local carryToggleEvent = ensureRemote(remotes, RescueConfig.CarryToggleEvent)
local feedbackEvent = ensureRemote(remotes, RescueConfig.FeedbackEvent)

local RescueController = require(ServerStorage:WaitForChild("RescueController")) :: RescueControllerApi

type CharacterContext = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
}

type PickupBinding = {
	prompt: ProximityPrompt,
	triggered: RBXScriptConnection,
	destroying: RBXScriptConnection,
}

local playerConnections: { [Player]: { RBXScriptConnection } } = {}
local revivePrompts: { [Player]: ProximityPrompt } = {}
local pickupBindings: { [Instance]: PickupBinding } = {}
local reviveTargetLocks: { [Player]: boolean } = {}
local bandageUserLocks: { [Player]: boolean } = {}
local pickupLocks: { [Instance]: boolean } = {}
local lastCarryRequest: { [Player]: number } = {}

local function feedback(player: Player, text: string, tone: string?)
	if player.Parent ~= Players then
		return
	end
	feedbackEvent:FireClient(player, {
		text = text,
		tone = tone or "neutral",
	})
end

local function characterContext(player: Player): CharacterContext?
	if player.Parent ~= Players then
		return nil
	end
	local character = player.Character
	if not character or not character:IsDescendantOf(Workspace) then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") or not root:IsDescendantOf(character) then
		return nil
	end
	return {
		character = character,
		humanoid = humanoid,
		root = root,
	}
end

local function numberAttribute(player: Player, attribute: string): number
	local value = player:GetAttribute(attribute)
	return if typeof(value) == "number" then value else 0
end

local function isRevivable(player: Player): boolean
	local state = RescueController.getState(player)
	return (state == RescueConfig.StateDowned or state == RescueConfig.StateCarried)
		and numberAttribute(player, RescueConfig.CatchCountAttribute) == 1
end

local function removeRevivePrompt(player: Player)
	local prompt = revivePrompts[player]
	revivePrompts[player] = nil
	if prompt and prompt.Parent then
		prompt:Destroy()
	end
end

local attemptRevive: (reviver: Player, target: Player, sourcePrompt: ProximityPrompt) -> ()

local function revivePromptPart(character: Model): BasePart?
	for _, name in { "UpperTorso", "Torso", "HumanoidRootPart" } do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

local function refreshRevivePrompt(target: Player)
	if target.Parent ~= Players or not isRevivable(target) then
		removeRevivePrompt(target)
		return
	end

	local context = characterContext(target)
	local part = if context then revivePromptPart(context.character) else nil
	if not context or context.humanoid.Health <= 0 or not part then
		removeRevivePrompt(target)
		return
	end

	local current = revivePrompts[target]
	if current and current.Parent == part then
		current.Enabled = true
		current.ObjectText = target.DisplayName
		return
	end
	removeRevivePrompt(target)

	-- Clear only stale prompts using this reserved rescue-system name. This also
	-- prevents duplicate E prompts after a live script resync.
	for _, descendant in context.character:GetDescendants() do
		if descendant:IsA("ProximityPrompt") and descendant.Name == RescueConfig.RevivePromptName then
			descendant:Destroy()
		end
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = RescueConfig.RevivePromptName
	prompt.ActionText = "Revive with bandage"
	prompt.ObjectText = target.DisplayName
	prompt.HoldDuration = RescueConfig.ReviveHoldSeconds
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.MaxActivationDistance = RescueConfig.ReviveRange
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt.Parent = part
	revivePrompts[target] = prompt
	prompt.Triggered:Connect(function(reviver: Player)
		attemptRevive(reviver, target, prompt)
	end)
end

attemptRevive = function(reviver: Player, target: Player, sourcePrompt: ProximityPrompt)
	if reviveTargetLocks[target] or bandageUserLocks[reviver] then
		return
	end
	if reviver == target then
		feedback(reviver, "You need a teammate to revive you.", "warning")
		return
	end
	if reviver.Parent ~= Players or target.Parent ~= Players then
		return
	end
	if sourcePrompt ~= revivePrompts[target] or not sourcePrompt:IsDescendantOf(Workspace) then
		return
	end
	if RescueController.getState(reviver) ~= RescueConfig.StateHealthy then
		feedback(reviver, "You cannot revive anyone while incapacitated.", "warning")
		return
	end
	if not isRevivable(target) then
		refreshRevivePrompt(target)
		feedback(reviver, "That player cannot be revived.", "warning")
		return
	end
	if numberAttribute(reviver, RescueConfig.BandageCountAttribute) < 1 then
		feedback(reviver, "You need a bandage to revive them.", "warning")
		return
	end

	local reviverContext = characterContext(reviver)
	local targetContext = characterContext(target)
	if
		not reviverContext
		or not targetContext
		or reviverContext.humanoid.Health <= 0
		or targetContext.humanoid.Health <= 0
	then
		feedback(reviver, "The revive could not be completed.", "warning")
		return
	end
	if (reviverContext.root.Position - targetContext.root.Position).Magnitude > RescueConfig.ReviveRange then
		feedback(reviver, "Move closer to revive them.", "warning")
		return
	end

	reviveTargetLocks[target] = true
	bandageUserLocks[reviver] = true
	local callOk, revived, reason = pcall(function()
		return RescueController.revive(reviver, target)
	end)
	reviveTargetLocks[target] = nil
	bandageUserLocks[reviver] = nil

	if not callOk then
		warn(`[RescueService] revive failed: {revived}`)
		feedback(reviver, "The revive could not be completed.", "danger")
		return
	end
	if revived ~= true then
		feedback(reviver, if typeof(reason) == "string" then reason else "The revive was refused.", "warning")
		refreshRevivePrompt(target)
		return
	end

	refreshRevivePrompt(target)
	feedback(reviver, `Bandage used. {target.DisplayName} is back on their feet.`, "success")
	feedback(target, `{reviver.DisplayName} revived you. Joel's next catch will be final.`, "success")
end

-- Bandage pickups -----------------------------------------------------------

local function pickupPart(pickup: Instance): BasePart?
	if pickup:IsA("BasePart") then
		return pickup
	elseif pickup:IsA("Model") and pickup.PrimaryPart then
		return pickup.PrimaryPart
	end
	return pickup:FindFirstChildWhichIsA("BasePart", true)
end

local function unbindPickup(pickup: Instance)
	local binding = pickupBindings[pickup]
	pickupBindings[pickup] = nil
	pickupLocks[pickup] = nil
	if binding then
		binding.triggered:Disconnect()
		binding.destroying:Disconnect()
	end
end

local function claimBandage(player: Player, pickup: Instance, prompt: ProximityPrompt)
	if pickupLocks[pickup] then
		return
	end
	if
		player.Parent ~= Players
		or not pickup:IsDescendantOf(Workspace)
		or not CollectionService:HasTag(pickup, RescueConfig.BandagePickupTag)
		or pickup:GetAttribute(RescueConfig.BandageClaimedAttribute) == true
		or prompt.Parent == nil
		or not prompt:IsDescendantOf(pickup)
	then
		return
	end
	if RescueController.getState(player) ~= RescueConfig.StateHealthy then
		feedback(player, "You cannot take supplies while incapacitated.", "warning")
		return
	end

	local context = characterContext(player)
	local part = pickupPart(pickup)
	if not context or context.humanoid.Health <= 0 or not part then
		return
	end
	if (context.root.Position - part.Position).Magnitude > RescueConfig.BandagePickupRange then
		return
	end

	local held = math.max(0, math.floor(numberAttribute(player, RescueConfig.BandageCountAttribute)))
	if held >= RescueConfig.MaxBandages then
		feedback(player, "Your bandage pouch is full.", "warning")
		return
	end

	-- No yield occurs between this lock, the replicated claim mark, inventory
	-- increment, and destruction. Two prompt triggers therefore cannot award the
	-- same physical roll.
	pickupLocks[pickup] = true
	pickup:SetAttribute(RescueConfig.BandageClaimedAttribute, true)
	prompt.Enabled = false
	local nextHeld = math.min(RescueConfig.MaxBandages, held + 1)
	player:SetAttribute(RescueConfig.BandageCountAttribute, nextHeld)
	feedback(player, `Bandage collected ({nextHeld}/{RescueConfig.MaxBandages}).`, "success")
	pickup:Destroy()
	-- Destroying/removed callbacks normally clear this; assigning nil is also
	-- safe when destruction is deferred by an engine callback.
	pickupLocks[pickup] = nil
end

local function bindPickup(pickup: Instance)
	if pickupBindings[pickup] then
		return
	end
	local prompt = pickup:FindFirstChild(RescueConfig.BandagePromptName, true)
	if not prompt or not prompt:IsA("ProximityPrompt") then
		warn(`[RescueService] tagged bandage {pickup:GetFullName()} has no {RescueConfig.BandagePromptName}`)
		return
	end
	prompt.MaxActivationDistance = math.min(prompt.MaxActivationDistance, RescueConfig.BandagePickupRange)
	local triggered = prompt.Triggered:Connect(function(player: Player)
		claimBandage(player, pickup, prompt)
	end)
	local destroying = pickup.Destroying:Connect(function()
		unbindPickup(pickup)
	end)
	pickupBindings[pickup] = {
		prompt = prompt,
		triggered = triggered,
		destroying = destroying,
	}
end

CollectionService:GetInstanceAddedSignal(RescueConfig.BandagePickupTag):Connect(bindPickup)
CollectionService:GetInstanceRemovedSignal(RescueConfig.BandagePickupTag):Connect(unbindPickup)
for _, pickup in CollectionService:GetTagged(RescueConfig.BandagePickupTag) do
	bindPickup(pickup)
end

-- Carry intent --------------------------------------------------------------

local function nearestBody(carrier: Player, carrierContext: CharacterContext): Player?
	local nearest: Player? = nil
	local nearestDistance = RescueConfig.BodyPickupRange
	for _, candidate in Players:GetPlayers() do
		if candidate == carrier or not RescueConfig.canPickUp(RescueController.getState(candidate)) then
			continue
		end
		if numberAttribute(candidate, RescueConfig.CarrierUserIdAttribute) > 0 then
			continue
		end
		local candidateContext = characterContext(candidate)
		if not candidateContext or candidateContext.humanoid.Health <= 0 then
			continue
		end
		local distance = (candidateContext.root.Position - carrierContext.root.Position).Magnitude
		if distance <= nearestDistance then
			nearest = candidate
			nearestDistance = distance
		end
	end
	return nearest
end

local function carryRequest(player: Player)
	local now = os.clock()
	if now - (lastCarryRequest[player] or -math.huge) < RescueConfig.RequestCooldownSeconds then
		return
	end
	lastCarryRequest[player] = now

	if RescueController.getState(player) ~= RescueConfig.StateHealthy then
		feedback(player, "You cannot carry anyone while incapacitated.", "warning")
		return
	end
	local context = characterContext(player)
	if not context or context.humanoid.Health <= 0 then
		return
	end

	if numberAttribute(player, RescueConfig.CarryingUserIdAttribute) > 0 then
		local ok, dropped = pcall(function()
			return RescueController.dropCarry(player)
		end)
		if not ok then
			warn(`[RescueService] dropCarry failed: {dropped}`)
			feedback(player, "The body could not be put down safely.", "danger")
		elseif dropped then
			feedback(player, "Body placed down.", "neutral")
		end
		return
	end

	local target = nearestBody(player, context)
	if not target then
		feedback(player, "No downed body is close enough to carry.", "warning")
		return
	end
	local ok, carried, reason = pcall(function()
		return RescueController.toggleCarry(player, target)
	end)
	if not ok then
		warn(`[RescueService] toggleCarry failed: {carried}`)
		feedback(player, "The body could not be lifted safely.", "danger")
	elseif carried == true then
		feedback(player, `Carrying {target.DisplayName}. Your movement is slower.`, "success")
		feedback(target, `{player.DisplayName} picked you up.`, "neutral")
	else
		feedback(player, if typeof(reason) == "string" then reason else "That body cannot be carried.", "warning")
	end
end

carryToggleEvent.OnServerEvent:Connect(carryRequest)

local carryAuditElapsed = 0
RunService.Heartbeat:Connect(function(dt: number)
	carryAuditElapsed += dt
	if carryAuditElapsed < 0.25 then
		return
	end
	carryAuditElapsed = 0

	for _, carrier in Players:GetPlayers() do
		local targetUserId = numberAttribute(carrier, RescueConfig.CarryingUserIdAttribute)
		if targetUserId <= 0 then
			continue
		end
		local target = Players:GetPlayerByUserId(targetUserId)
		local carrierContext = characterContext(carrier)
		local targetContext = if target then characterContext(target) else nil
		local valid = RescueController.getState(carrier) == RescueConfig.StateHealthy
			and carrierContext ~= nil
			and carrierContext.humanoid.Health > 0
			and target ~= nil
			and targetContext ~= nil
			and targetContext.humanoid.Health > 0
			and RescueController.getState(target) == RescueConfig.StateCarried
			and numberAttribute(target, RescueConfig.CarrierUserIdAttribute) == carrier.UserId
			and (carrierContext.root.Position - targetContext.root.Position).Magnitude
				<= RescueConfig.CarryBreakDistance
		if not valid then
			local ok, dropped = pcall(function()
				return RescueController.dropCarry(carrier)
			end)
			if not ok then
				warn(`[RescueService] automatic drop failed: {dropped}`)
			elseif dropped then
				feedback(carrier, "You lost your grip and put the body down.", "warning")
			end
		end
	end
end)

-- Player and round lifecycle ------------------------------------------------

local function dropPlayerRelationships(player: Player)
	if numberAttribute(player, RescueConfig.CarryingUserIdAttribute) > 0 then
		pcall(function()
			RescueController.dropCarry(player)
		end)
	end
	local carrierUserId = numberAttribute(player, RescueConfig.CarrierUserIdAttribute)
	if carrierUserId > 0 then
		local carrier = Players:GetPlayerByUserId(carrierUserId)
		if carrier then
			pcall(function()
				RescueController.dropCarry(carrier)
			end)
		end
	end
end

local function watchPlayer(player: Player)
	if playerConnections[player] then
		return
	end
	local connections: { RBXScriptConnection } = {}
	playerConnections[player] = connections

	RescueController.initializePlayer(player)
	if typeof(player:GetAttribute(RescueConfig.BandageCountAttribute)) ~= "number" then
		player:SetAttribute(RescueConfig.BandageCountAttribute, 0)
	end

	table.insert(
		connections,
		player.CharacterAdded:Connect(function(character: Model)
			task.defer(function()
				if player.Parent == Players and player.Character == character then
					refreshRevivePrompt(player)
				end
			end)
		end)
	)
	table.insert(
		connections,
		player.CharacterRemoving:Connect(function()
			removeRevivePrompt(player)
			dropPlayerRelationships(player)
		end)
	)
	table.insert(
		connections,
		player:GetAttributeChangedSignal(RescueConfig.StateAttribute):Connect(function()
			refreshRevivePrompt(player)
		end)
	)
	table.insert(
		connections,
		player:GetAttributeChangedSignal(RescueConfig.CatchCountAttribute):Connect(function()
			refreshRevivePrompt(player)
		end)
	)
	refreshRevivePrompt(player)
end

local function unwatchPlayer(player: Player)
	dropPlayerRelationships(player)
	removeRevivePrompt(player)
	lastCarryRequest[player] = nil
	reviveTargetLocks[player] = nil
	bandageUserLocks[player] = nil
	local connections = playerConnections[player]
	playerConnections[player] = nil
	if connections then
		for _, connection in connections do
			connection:Disconnect()
		end
	end
end

Players.PlayerAdded:Connect(watchPlayer)
Players.PlayerRemoving:Connect(unwatchPlayer)
for _, player in Players:GetPlayers() do
	watchPlayer(player)
end

local clueStateConnection: RBXScriptConnection? = nil
local clueStateDestroying: RBXScriptConnection? = nil
local observedClueState: Instance? = nil
local lastPhase: any = nil

local function resetForNewHunt()
	local ok, failure = pcall(function()
		RescueController.resetRound()
	end)
	if not ok then
		warn(`[RescueService] round reset failed: {failure}`)
		return
	end
	for _, player in Players:GetPlayers() do
		refreshRevivePrompt(player)
		feedback(player, "A new hunt begins. Rescue strikes were reset.", "neutral")
	end
end

local function observeCluePhase()
	local folder = observedClueState
	if not folder then
		return
	end
	local phase = folder:GetAttribute(ClueConfig.PhaseAttribute)
	if phase == nil then
		-- Rebuilding the replicated folder may briefly clear attributes. Preserve
		-- the last real phase so Won -> nil -> Hunt is still a new-round edge.
		return
	end
	if phase == ClueConfig.PhaseHunt and lastPhase ~= nil and lastPhase ~= ClueConfig.PhaseHunt then
		resetForNewHunt()
	end
	lastPhase = phase
end

local function bindClueState(instance: Instance)
	if instance.Name ~= ClueConfig.StateFolder then
		return
	end
	if clueStateConnection then
		clueStateConnection:Disconnect()
	end
	if clueStateDestroying then
		clueStateDestroying:Disconnect()
	end
	observedClueState = instance
	clueStateConnection = instance:GetAttributeChangedSignal(ClueConfig.PhaseAttribute):Connect(observeCluePhase)
	clueStateDestroying = instance.Destroying:Connect(function()
		if observedClueState == instance then
			observedClueState = nil
		end
	end)
	observeCluePhase()
end

ReplicatedStorage.ChildAdded:Connect(bindClueState)
local existingClueState = ReplicatedStorage:FindFirstChild(ClueConfig.StateFolder)
if existingClueState then
	bindClueState(existingClueState)
end
