--!strict
-- Server-authoritative hunting, navigation, and combat for Joel.

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

type CatchResult = {
	outcome: string,
	job: any?,
	dropPosition: Vector3?,
}

type RescueControllerApi = {
	beginCatch: (player: Player, joel: Model) -> CatchResult?,
	finishDrag: (job: any) -> boolean,
	abortDrag: (job: any) -> boolean,
}

local ClueConfig = require(ReplicatedStorage:WaitForChild("ClueConfig"))
local JoelConfig = require(ReplicatedStorage:WaitForChild("JoelConfig"))
local OnboardingConfig = require(ReplicatedStorage:WaitForChild("OnboardingConfig"))
local RescueController = require(ServerStorage:WaitForChild("RescueController")) :: RescueControllerApi

local ADMIN_INVINCIBLE_ATTRIBUTE = "AdminInvincible"

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

local joelNoise = ensure(ServerStorage, ClueConfig.JoelNoiseEvent, "BindableEvent") :: BindableEvent
local joelDefeat = ensure(ServerStorage, ClueConfig.JoelDefeatEvent, "BindableEvent") :: BindableEvent
local joelRevive = ensure(ServerStorage, ClueConfig.JoelReviveEvent, "BindableEvent") :: BindableEvent

-- What the plaque at the top of every screen reads. It is created before the rig
-- is even looked for, so a place with no Joel in it still resolves the client's
-- WaitForChild and simply leaves the plaque hidden, rather than hanging it.
local joelState = ensure(Workspace, JoelConfig.StateFolder, "Folder") :: Folder

-- Rig ------------------------------------------------------------------------

local function findJoel(): Model?
	for _, tagged in ipairs(CollectionService:GetTagged("JoelHunter")) do
		if tagged:IsA("Model") and tagged:IsDescendantOf(Workspace) then
			return tagged
		end
	end
	local direct = Workspace:FindFirstChild("Joel")
	return if direct and direct:IsA("Model") then direct else nil
end

local joel = findJoel()
if not joel then
	warn("[JoelService] no model tagged JoelHunter — Joel will not hunt")
	return
end

local foundHumanoid = joel:FindFirstChildOfClass("Humanoid")
local foundRoot = joel:FindFirstChild("HumanoidRootPart")
if not foundHumanoid or not foundRoot or not foundRoot:IsA("BasePart") then
	warn(`[JoelService] {joel:GetFullName()} needs a Humanoid and HumanoidRootPart`)
	return
end

local joelHumanoid: Humanoid = foundHumanoid
local joelRoot: BasePart = foundRoot
local spawnPivot = joel:GetPivot()

joelHumanoid.MaxHealth = math.huge
joelHumanoid.Health = math.huge
joelHumanoid.BreakJointsOnDeath = false
joelHumanoid.AutoRotate = true

pcall(function()
	joelRoot:SetNetworkOwner(nil)
end)

-- Shared types and state ------------------------------------------------------

type HunterState = "Dormant" | "Prowl" | "Investigate" | "Search" | "Chase" | "Dragging" | "Downed" | "Resting"

type CharacterBinding = {
	player: Player,
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	connections: { RBXScriptConnection },
}

type Contact = {
	binding: CharacterBinding,
	position: Vector3,
	velocity: Vector3,
	distance: number,
	speed: number,
	visible: boolean,
	audible: boolean,
}

type ActiveDrag = {
	job: any,
	player: Player,
	character: Model,
	root: BasePart,
	dropPosition: Vector3,
	startedAt: number,
	pathFailedAt: number?,
	stuckAt: number?,
}

local state: HunterState = "Dormant"
local targetBinding: CharacterBinding? = nil
local sensedTarget: Contact? = nil
local lastKnownAt: Vector3? = nil
local lastKnownVelocity = Vector3.zero
local lastVisibleClock = -math.huge
local lastSensedClock = -math.huge
local nextHearingUpdate = 0
local noiseExpiresAt = -math.huge
local downedUntil = -math.huge
local downedRevision = 0
local activeDrag: ActiveDrag? = nil
local catchInProgress = false
local downedEndsAt = 0
local cycleEpoch: number? = nil
local publishedPhase = ""
local publishedEndsAt = 0

-- How often the dormant server re-asks whether anyone who finished the intro
-- has left the lobby yet. A third of a second is under the time it takes to
-- walk through the lobby doorway, so the round still starts on the step out.
local ARM_POLL_INTERVAL = 0.34

local waypoints: { PathWaypoint } = {}
local waypointIndex = 1
local pathGoal: Vector3? = nil
local pathPending = false
local pathFailed = false
local pathRevision = 0
local nextRepath = 0

local currentSpeed = 0
local lastJumpAt = 0
local lastTeleportAt = 0
local stuckAnchor = joelRoot.Position
local stuckSince = os.clock()

local prowlGoal: Vector3? = nil
local searchGoal: Vector3? = nil
local searchStep = 0
local nextSearchDecision = 0

local bindingsByPlayer: { [Player]: CharacterBinding } = {}
local bindingsByCharacter: { [Model]: CharacterBinding } = {}
local playerConnections: { [Player]: { RBXScriptConnection } } = {}
local bindGeneration: { [Player]: number } = {}

-- Attributes are also the animation contract. Clients only render the pose;
-- the server remains authoritative over every gameplay decision.
local function publishState()
	joel:SetAttribute("HunterState", state)
	joel:SetAttribute(
		"IsHunting",
		targetBinding ~= nil and state ~= "Dormant" and state ~= "Prowl" and state ~= "Dragging" and state ~= "Resting"
	)
	joel:SetAttribute("TargetUserId", if targetBinding then targetBinding.player.UserId else 0)
	joel:SetAttribute("CurrentSpeed", currentSpeed)
end

local function setState(nextState: HunterState)
	if state ~= nextState then
		state = nextState
		joel:SetAttribute("HunterState", state)
	end
	publishState()
end

--[[
	Publishing a phase and the server time it ends at — rather than a number that
	ticks — is what keeps the plaque exact for nothing. Clients subtract from
	GetServerTimeNow() themselves, so these attributes replicate twice a cycle
	instead of sixty times a second, and a player who joins eleven seconds into a
	window reads the same nineteen as everyone already inside it.
]]
local function clearCycle()
	publishedPhase = ""
	publishedEndsAt = 0
	joelState:SetAttribute(JoelConfig.CyclePhaseAttribute, nil)
	joelState:SetAttribute(JoelConfig.CycleEndsAtAttribute, nil)
end

local function publishCycle(phase: string, endsAt: number)
	if publishedPhase == phase and math.abs(publishedEndsAt - endsAt) < 0.05 then
		return
	end
	publishedPhase = phase
	publishedEndsAt = endsAt
	joelState:SetAttribute(JoelConfig.CyclePhaseAttribute, phase)
	joelState:SetAttribute(JoelConfig.CycleEndsAtAttribute, endsAt)
end

local function clearPath()
	pathRevision += 1
	waypoints = {}
	waypointIndex = 1
	pathGoal = nil
	pathPending = false
	pathFailed = false
end

local function clearTarget()
	targetBinding = nil
	sensedTarget = nil
	lastKnownAt = nil
	lastKnownVelocity = Vector3.zero
	lastVisibleClock = -math.huge
	lastSensedClock = -math.huge
	nextHearingUpdate = 0
	searchGoal = nil
	searchStep = 0
	clearPath()
	setState("Prowl")
end

local function forgetTarget()
	targetBinding = nil
	sensedTarget = nil
	lastKnownAt = nil
	lastKnownVelocity = Vector3.zero
	lastVisibleClock = -math.huge
	lastSensedClock = -math.huge
	nextHearingUpdate = 0
	noiseExpiresAt = -math.huge
	searchGoal = nil
	searchStep = 0
	clearPath()
end

local function playAttackScream()
	local scream = joelRoot:FindFirstChild("AttackScream")
	if scream and scream:IsA("Sound") then
		scream:Stop()
		scream.TimePosition = 0
		scream:Play()
	end
end

local function callAbortDrag(job: any, reason: string)
	local ok, released = pcall(function()
		return RescueController.abortDrag(job)
	end)
	if not ok then
		warn(`[JoelService] RescueController.abortDrag failed ({reason}): {released}`)
	end
end

local function endActiveDrag(completed: boolean, reason: string)
	local drag = activeDrag
	if not drag then
		return
	end
	activeDrag = nil

	if completed then
		local ok, released = pcall(function()
			return RescueController.finishDrag(drag.job)
		end)
		if not ok then
			warn(`[JoelService] RescueController.finishDrag failed: {released}`)
		end
	else
		callAbortDrag(drag.job, reason)
	end

	forgetTarget()
	setState("Prowl")
end

local function reviveJoel()
	if state ~= "Downed" then
		return
	end

	downedRevision += 1
	downedUntil = -math.huge
	downedEndsAt = 0
	joel:SetAttribute("DownedUntil", 0)
	currentSpeed = 0
	joelHumanoid.WalkSpeed = JoelConfig.ProwlSpeed
	forgetTarget()
	setState("Prowl")
end

local function downJoel()
	endActiveDrag(false, "Joel was downed")
	downedRevision += 1
	local revision = downedRevision
	downedUntil = os.clock() + JoelConfig.DownedSeconds
	downedEndsAt = Workspace:GetServerTimeNow() + JoelConfig.DownedSeconds
	joel:SetAttribute("DownedUntil", downedEndsAt)
	forgetTarget()
	currentSpeed = 0
	joelHumanoid.WalkSpeed = 0
	joelHumanoid:MoveTo(joelRoot.Position)
	joelRoot.AssemblyLinearVelocity = Vector3.zero
	setState("Downed")

	playAttackScream()

	task.delay(JoelConfig.DownedSeconds, function()
		if revision == downedRevision and state == "Downed" then
			reviveJoel()
		end
	end)
end

joelNoise.Event:Connect(function(position: any, weight: any)
	if typeof(position) ~= "Vector3" or typeof(weight) ~= "number" then
		return
	end
	if state == "Downed" or state == "Dragging" or state == "Resting" or weight <= 0 then
		return
	end
	if (position - joelRoot.Position).Magnitude > weight * JoelConfig.NoiseInvestigateWeight then
		return
	end
	if state == "Chase" and sensedTarget and sensedTarget.visible then
		return
	end

	forgetTarget()
	lastKnownAt = position
	searchGoal = position
	noiseExpiresAt = os.clock() + JoelConfig.LoseInterestSeconds
	setState("Investigate")
end)

joelDefeat.Event:Connect(function()
	downJoel()
end)

joelRevive.Event:Connect(function()
	reviveJoel()
end)

-- Character lifecycle --------------------------------------------------------

local function bindingIsCurrent(binding: CharacterBinding): boolean
	return bindingsByPlayer[binding.player] == binding
		and binding.player.Character == binding.character
		and binding.character.Parent ~= nil
		and binding.humanoid.Parent == binding.character
		and binding.root:IsDescendantOf(binding.character)
		and binding.humanoid.Health > 0
end

--[[
	The single gate for "may Joel do anything to this player". Every call site
	that matters routes through here — perception (scanContacts), keeping a
	target (refreshPerception), and the catch itself (attackNearby) — so adding
	a condition here makes a player unseeable, untargetable and uncatchable in
	one place rather than three that can drift apart.
]]
local function bindingIsHuntable(binding: CharacterBinding): boolean
	return bindingIsCurrent(binding)
		--[[
			Nobody is hunted during their first stay.

			The intro walks a new player through a lit hotel to a room that seals
			behind them and puts up a notice saying he is prowling. Joel taking
			someone in the lift on the way there does not just spoil that, it
			makes the notice a lie about something that already happened.

			Written as "is in the intro" rather than "is not finished", so a
			player the server has not classified yet is huntable. See
			OnboardingConfig.isIntroStage: the other reading would make an
			unclassified player permanently invisible to him, which is the far
			worse failure and the one that is hard to notice.
		]]
		and not OnboardingConfig.isIntroStage(binding.player:GetAttribute(OnboardingConfig.ATTRIBUTE))
		and JoelConfig.canTargetRescueState(binding.player:GetAttribute(JoelConfig.RescueStateAttribute))
		and JoelConfig.canTargetHidingState(binding.player:GetAttribute(JoelConfig.HidingAttribute))
end

local function unbindPlayer(player: Player, character: Model?)
	local binding = bindingsByPlayer[player]
	if not binding or (character and binding.character ~= character) then
		return
	end

	bindingsByPlayer[player] = nil
	bindingsByCharacter[binding.character] = nil
	for _, connection in ipairs(binding.connections) do
		connection:Disconnect()
	end
	table.clear(binding.connections)

	if targetBinding == binding then
		clearTarget()
	end
end

local function bindCharacter(player: Player, character: Model)
	bindGeneration[player] = (bindGeneration[player] or 0) + 1
	local generation = bindGeneration[player]
	unbindPlayer(player, nil)

	-- CharacterAdded can fire before the rig is assembled. Waiting happens in a
	-- task so one slow avatar cannot stall Joel or another player's binding.
	task.spawn(function()
		local humanoidInstance = character:WaitForChild("Humanoid", 10)
		local rootInstance = character:WaitForChild("HumanoidRootPart", 10)
		if bindGeneration[player] ~= generation or player.Character ~= character then
			return
		end
		if not humanoidInstance or not humanoidInstance:IsA("Humanoid") then
			return
		end
		if not rootInstance or not rootInstance:IsA("BasePart") then
			return
		end

		local binding: CharacterBinding = {
			player = player,
			character = character,
			humanoid = humanoidInstance,
			root = rootInstance,
			connections = {},
		}

		table.insert(
			binding.connections,
			humanoidInstance.Died:Connect(function()
				if targetBinding == binding then
					clearTarget()
				end
			end)
		)
		table.insert(
			binding.connections,
			character.AncestryChanged:Connect(function(_, parent: Instance?)
				if parent == nil then
					unbindPlayer(player, character)
				end
			end)
		)

		bindingsByPlayer[player] = binding
		bindingsByCharacter[character] = binding
	end)
end

--[[
	The round starts when somebody finishes their first stay AND is out of the
	lobby.

	Not at server start, and not when Joel's rig loads. The intro deliberately
	walks a new player through a lit, safe hotel to a room that seals behind
	them and puts up a notice saying he is prowling — and JoelService already
	refuses to hunt anyone still inside that sequence. Running the cycle
	underneath it would mean the plaque counting down a hunt that cannot touch
	anybody, and a player walking out of room 1 into the middle of a window
	rather than the start of one.

	The lobby half of the condition covers the cases COMPLETE alone does not.
	A player who rejoins already carrying COMPLETE is classified the instant
	they connect, standing on the lobby spawn — the old rule started the round
	there and then, so their first minute of a hunt window was spent in the one
	room the hotel treats as a safe arrival. The same happens to anybody who
	rides back down to the desk before the round has begun. Neither is a round
	that has actually started; the round starts when somebody is out in the
	hotel.

	Keyed on reaching COMPLETE rather than on the absence of an intro stage. The
	two readings differ for a player the server has not classified yet, and here
	the positive one is right: an unclassified player should not start the round
	on everyone else's behalf. The opposite choice is the correct one a few lines
	up in bindingIsHuntable, for the opposite reason — see the note there.

	One player out of the lobby is enough. Requiring all of them would hand any
	single person standing at the desk a veto over everyone else's round, which
	is the same "waiting is the correct play" failure the cycle exists to remove.

	It arms once and stays armed. Later joiners inherit the running cycle, and
	the plaque appears for each of them as they finish their own first stay.
]]

-- Players who finished the intro while still in the lobby. Held here so the
-- round can start the moment one of them walks out, rather than waiting for
-- some other event to happen to re-ask the question.
local awaitingLobbyExit: { [Player]: true } = {}
local lastArmPoll = 0

--[[
	False whenever the answer is not knowable.

	A player mid-respawn has no HumanoidRootPart to classify, and guessing in
	that gap would start the round on a position nobody is standing at. Waiting
	costs at most a respawn; the next poll asks again.
]]
local function isOutOfLobby(player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	return JoelConfig.floorOf(root.Position) ~= "Lobby"
end

local function armCycle()
	if cycleEpoch then
		return
	end
	cycleEpoch = Workspace:GetServerTimeNow()
	table.clear(awaitingLobbyExit)
	print("[JoelService] first stay over and out of the lobby — the hunt cycle is running")
end

local function considerArming(player: Player)
	if cycleEpoch then
		return
	end
	if player:GetAttribute(OnboardingConfig.ATTRIBUTE) ~= OnboardingConfig.COMPLETE then
		return
	end
	if isOutOfLobby(player) then
		armCycle()
	else
		awaitingLobbyExit[player] = true
	end
end

-- Cheap enough to run on a timer rather than on movement: a handful of players,
-- one vector comparison each, and it stops entirely the moment the round starts.
local function pollLobbyExit(now: number)
	if cycleEpoch or now - lastArmPoll < ARM_POLL_INTERVAL then
		return
	end
	lastArmPoll = now
	for player in awaitingLobbyExit do
		if player.Parent == nil then
			awaitingLobbyExit[player] = nil
		elseif isOutOfLobby(player) then
			armCycle()
			return
		end
	end
end

local function watchOnboarding(player: Player, connections: { RBXScriptConnection })
	local attribute = OnboardingConfig.ATTRIBUTE
	considerArming(player)
	table.insert(
		connections,
		player:GetAttributeChangedSignal(attribute):Connect(function()
			considerArming(player)
		end)
	)
end

local function connectPlayer(player: Player)
	if playerConnections[player] then
		return
	end
	local connections: { RBXScriptConnection } = {}
	playerConnections[player] = connections

	watchOnboarding(player, connections)

	table.insert(
		connections,
		player.CharacterAdded:Connect(function(character: Model)
			bindCharacter(player, character)
		end)
	)
	table.insert(
		connections,
		player.CharacterRemoving:Connect(function(character: Model)
			bindGeneration[player] = (bindGeneration[player] or 0) + 1
			unbindPlayer(player, character)
		end)
	)

	if player.Character then
		bindCharacter(player, player.Character)
	end
end

local function disconnectPlayer(player: Player)
	bindGeneration[player] = (bindGeneration[player] or 0) + 1
	awaitingLobbyExit[player] = nil
	unbindPlayer(player, nil)
	local connections = playerConnections[player]
	if connections then
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		playerConnections[player] = nil
	end
	bindGeneration[player] = nil
end

for _, player in ipairs(Players:GetPlayers()) do
	connectPlayer(player)
end
Players.PlayerAdded:Connect(connectPlayer)
Players.PlayerRemoving:Connect(disconnectPlayer)

-- Perception -----------------------------------------------------------------

local sightParams = RaycastParams.new()
sightParams.FilterType = Enum.RaycastFilterType.Exclude
sightParams.IgnoreWater = true

local function canSee(from: Vector3, to: Vector3, ignore: { Instance }): boolean
	sightParams.FilterDescendantsInstances = ignore
	local delta = to - from
	if delta.Magnitude < 1e-3 then
		return true
	end
	return Workspace:Raycast(from, delta, sightParams) == nil
end

local function scanContacts(): { Contact }
	local contacts: { Contact } = {}
	local eye = joelRoot.Position + Vector3.new(0, 1.25, 0)

	for _, binding in pairs(bindingsByPlayer) do
		if not bindingIsHuntable(binding) then
			continue
		end

		local position = binding.root.Position
		local distance = (position - joelRoot.Position).Magnitude
		local velocity = binding.root.AssemblyLinearVelocity
		local flatSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local running = flatSpeed > binding.humanoid.WalkSpeed * 0.85 and binding.humanoid.WalkSpeed > 16
		local hearingRange = JoelConfig.noticeRange(running)
		local visible: boolean = false
		if distance <= JoelConfig.SightRange then
			visible = canSee(eye, position + Vector3.new(0, 0.75, 0), { joel, binding.character })
		end
		local audible = distance <= hearingRange

		if visible or audible then
			local contact: Contact = {
				binding = binding,
				position = position,
				velocity = velocity,
				distance = distance,
				speed = flatSpeed,
				visible = visible :: boolean,
				audible = audible,
			}
			table.insert(contacts, contact)
		end
	end

	return contacts
end

local function contactScore(contact: Contact): number
	local score = contact.distance + (if contact.visible then 0 else 32)
	if targetBinding == contact.binding then
		score -= JoelConfig.TargetSwitchMargin
	end
	return score
end

local function noisyHearingPosition(position: Vector3): Vector3
	local angle = math.random() * math.pi * 2
	local radius = math.random() * JoelConfig.HearingPositionError
	return position + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

local function refreshPerception(now: number)
	local contacts = scanContacts()
	local byBinding: { [CharacterBinding]: Contact } = {}
	local best: Contact? = nil
	local bestScore = math.huge

	for _, contact in ipairs(contacts) do
		byBinding[contact.binding] = contact
		local score = contactScore(contact)
		if score < bestScore then
			best = contact
			bestScore = score
		end
	end

	if targetBinding and not bindingIsHuntable(targetBinding) then
		clearTarget()
	end

	if best and (not targetBinding or best.binding ~= targetBinding) then
		targetBinding = best.binding
		lastKnownAt = nil
		searchGoal = nil
		searchStep = 0
		clearPath()
	end

	sensedTarget = if targetBinding then byBinding[targetBinding] else nil
	local contact = sensedTarget

	if contact and contact.visible then
		lastKnownAt = contact.position
		lastKnownVelocity = contact.velocity
		lastVisibleClock = now
		lastSensedClock = now
		searchGoal = contact.position
		setState("Chase")
	elseif contact and contact.audible then
		lastSensedClock = now
		if now >= nextHearingUpdate or not lastKnownAt then
			lastKnownAt = noisyHearingPosition(contact.position)
			lastKnownVelocity = Vector3.zero
			searchGoal = lastKnownAt
			nextHearingUpdate = now + JoelConfig.HearingUpdateInterval
		end
		setState("Investigate")
	elseif targetBinding then
		if now - lastSensedClock > JoelConfig.LoseInterestSeconds then
			clearTarget()
		elseif now - lastVisibleClock <= JoelConfig.LostSightCommitSeconds then
			-- Commit briefly to the last intercept instead of snapping into a turn
			-- the instant the victim crosses a door frame.
			setState("Chase")
		else
			setState("Search")
		end
	elseif now < noiseExpiresAt and lastKnownAt then
		setState("Investigate")
	else
		setState("Prowl")
	end
end

-- Pathfinding ----------------------------------------------------------------

local agentParams = {
	AgentRadius = 2.5,
	AgentHeight = 5,
	AgentCanJump = true,
	AgentCanClimb = true,
	WaypointSpacing = 4,
}

local function requestPath(goal: Vector3)
	if pathPending then
		return
	end

	pathRevision += 1
	local revision = pathRevision
	local origin = joelRoot.Position
	pathPending = true
	pathFailed = false
	pathGoal = goal

	task.spawn(function()
		local candidate = PathfindingService:CreatePath(agentParams)
		local ok = pcall(function()
			candidate:ComputeAsync(origin, goal)
		end)
		if revision ~= pathRevision then
			return
		end

		pathPending = false
		if ok and candidate.Status == Enum.PathStatus.Success then
			local points = candidate:GetWaypoints()
			if #points > 0 then
				waypoints = points
				waypointIndex = math.min(2, #points)
				pathFailed = false
				return
			end
		end

		waypoints = {}
		waypointIndex = 1
		pathFailed = true
	end)
end

local function advanceWaypoints()
	while waypointIndex <= #waypoints do
		local waypoint = waypoints[waypointIndex]
		local delta = waypoint.Position - joelRoot.Position
		local flatDistance = Vector3.new(delta.X, 0, delta.Z).Magnitude
		if flatDistance > JoelConfig.WaypointReached then
			break
		end
		if waypoint.Action == Enum.PathWaypointAction.Jump and state ~= "Dragging" then
			joelHumanoid.Jump = true
		end
		waypointIndex += 1
	end
end

local function pathLookAhead(): Vector3?
	advanceWaypoints()
	if waypointIndex > #waypoints then
		return nil
	end

	local eye = joelRoot.Position + Vector3.new(0, 1, 0)
	local chosenIndex = waypointIndex
	local limit = math.min(#waypoints, waypointIndex + JoelConfig.MaxWaypointSkip)
	for index = waypointIndex, limit do
		local point = waypoints[index].Position
		if canSee(eye, point + Vector3.new(0, 1, 0), { joel }) then
			chosenIndex = index
		else
			break
		end
	end
	waypointIndex = chosenIndex
	return waypoints[chosenIndex].Position
end

local function moveToward(now: number, goal: Vector3, directCharacter: Model?): Vector3?
	local needsPath = pathGoal == nil
		or now >= nextRepath
		or (pathGoal - goal).Magnitude >= JoelConfig.RepathTargetDrift
	if needsPath then
		nextRepath = now + JoelConfig.RepathInterval
		requestPath(goal)
	end

	local distance = (goal - joelRoot.Position).Magnitude
	if directCharacter and distance <= JoelConfig.DirectChaseDistance then
		if canSee(joelRoot.Position + Vector3.new(0, 1, 0), goal, { joel, directCharacter }) then
			joelHumanoid:MoveTo(goal)
			return goal
		end
	end

	local steer = pathLookAhead()
	if steer then
		joelHumanoid:MoveTo(steer)
		return steer
	end

	-- Do not freeze during the first asynchronous path computation when the
	-- target is plainly in the same open corridor.
	if directCharacter and canSee(joelRoot.Position + Vector3.new(0, 1, 0), goal, { joel, directCharacter }) then
		joelHumanoid:MoveTo(goal)
		return goal
	end
	return nil
end

local function maybeJump(now: number, moveDirection: Vector3)
	if now - lastJumpAt < JoelConfig.JumpCooldown then
		return
	end
	local flat = Vector3.new(moveDirection.X, 0, moveDirection.Z)
	if flat.Magnitude < 0.1 then
		return
	end
	flat = flat.Unit

	sightParams.FilterDescendantsInstances = { joel }
	local low = joelRoot.Position - Vector3.new(0, 1.6, 0)
	if not Workspace:Raycast(low, flat * JoelConfig.JumpProbeDistance, sightParams) then
		return
	end
	local high = joelRoot.Position + Vector3.new(0, JoelConfig.JumpProbeHeight, 0)
	if not Workspace:Raycast(high, flat * JoelConfig.JumpProbeDistance, sightParams) then
		joelHumanoid.Jump = true
		lastJumpAt = now
	end
end

-- Disconnected hotel floors --------------------------------------------------

type Cab = { arrive: BasePart, partnerId: string? }

local function cabs(): { [string]: Cab }
	local found: { [string]: Cab } = {}
	for _, model in ipairs(CollectionService:GetTagged("ElevatorCab")) do
		if not model:IsA("Model") then
			continue
		end
		local id = model:GetAttribute("CabId")
		if type(id) ~= "string" then
			continue
		end
		local arrive: BasePart? = nil
		for _, descendant in ipairs(model:GetDescendants()) do
			if descendant:IsA("BasePart") and CollectionService:HasTag(descendant, "ElevatorArrive") then
				arrive = descendant
				break
			end
		end
		if arrive then
			local partner = model:GetAttribute("Partner")
			found[id] = {
				arrive = arrive,
				partnerId = if type(partner) == "string" then partner else nil,
			}
		end
	end
	return found
end

local function cabToward(targetPosition: Vector3): Cab?
	local all = cabs()
	local targetFloor = JoelConfig.floorOf(targetPosition)
	local joelFloor = JoelConfig.floorOf(joelRoot.Position)
	for _, cab in pairs(all) do
		local partner = if cab.partnerId then all[cab.partnerId] else nil
		if
			partner
			and JoelConfig.floorOf(cab.arrive.Position) == joelFloor
			and JoelConfig.floorOf(partner.arrive.Position) == targetFloor
			and targetFloor ~= joelFloor
		then
			return cab
		end
	end
	return nil
end

local function observed(): boolean
	for _, binding in pairs(bindingsByPlayer) do
		if not bindingIsHuntable(binding) then
			continue
		end
		local head = binding.character:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			local distance = (head.Position - joelRoot.Position).Magnitude
			if
				distance <= JoelConfig.TeleportMaxObserverDistance
				and canSee(head.Position, joelRoot.Position, { joel, binding.character })
			then
				return true
			end
		end
	end
	return false
end

local function translocate(binding: CharacterBinding, around: Vector3): boolean
	if not bindingIsHuntable(binding) then
		return false
	end
	if JoelConfig.floorOf(around) == "Vault" then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { joel, binding.character }

	for _ = 1, 24 do
		local angle = math.random() * math.pi * 2
		local radius = JoelConfig.TeleportArriveMin
			+ math.random() * (JoelConfig.TeleportArriveMax - JoelConfig.TeleportArriveMin)
		local candidate = around + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		local floorHit = Workspace:Raycast(candidate + Vector3.new(0, 14, 0), Vector3.new(0, -40, 0), params)
		if not floorHit then
			continue
		end
		local stand = floorHit.Position + Vector3.new(0, 3, 0)
		local headroom = Workspace:Raycast(floorHit.Position + Vector3.new(0, 0.5, 0), Vector3.new(0, 6, 0), params)
		if not headroom and not canSee(binding.root.Position, stand, { joel, binding.character }) then
			joel:PivotTo(CFrame.new(stand, Vector3.new(around.X, stand.Y, around.Z)))
			joelRoot.AssemblyLinearVelocity = Vector3.zero
			clearPath()
			return true
		end
	end
	return false
end

-- Combat ---------------------------------------------------------------------

local function beginCatch(binding: CharacterBinding): boolean
	if catchInProgress then
		return false
	end
	catchInProgress = true
	local ok, result = pcall(function()
		return RescueController.beginCatch(binding.player, joel)
	end)
	catchInProgress = false

	if not ok then
		warn(`[JoelService] RescueController.beginCatch failed: {result}`)
		return false
	end
	if type(result) ~= "table" then
		return false
	end

	local outcome = result.outcome
	if state == "Downed" or joelHumanoid.Health <= 0 then
		if outcome == "Drag" and result.job ~= nil then
			callAbortDrag(result.job, "catch was interrupted by Joel's defeat")
		end
		return outcome == "Drag" or outcome == "Incapacitated"
	end
	if outcome == "Incapacitated" then
		playAttackScream()
		if targetBinding == binding then
			clearTarget()
		end
		return true
	end
	if outcome ~= "Drag" then
		warn(`[JoelService] RescueController returned unknown catch outcome {tostring(outcome)}`)
		return false
	end

	local job = result.job
	local dropPosition = result.dropPosition
	playAttackScream()
	if job == nil or typeof(dropPosition) ~= "Vector3" then
		if job ~= nil then
			callAbortDrag(job, "invalid drag result")
		end
		warn("[JoelService] RescueController returned a drag without a job and Vector3 dropPosition")
		if targetBinding == binding then
			clearTarget()
		end
		return true
	end
	if not JoelConfig.isSameFloorDrop(joelRoot.Position, dropPosition) then
		callAbortDrag(job, "drop point was not on Joel's floor")
		warn("[JoelService] RescueController returned a drop point on another floor; victim released safely")
		if targetBinding == binding then
			clearTarget()
		end
		return true
	end

	activeDrag = {
		job = job,
		player = binding.player,
		character = binding.character,
		root = binding.root,
		dropPosition = dropPosition,
		startedAt = os.clock(),
		pathFailedAt = nil,
		stuckAt = nil,
	}
	forgetTarget()
	stuckAnchor = joelRoot.Position
	stuckSince = os.clock()
	currentSpeed = JoelConfig.DragSpeed
	joelHumanoid.WalkSpeed = JoelConfig.DragSpeed
	setState("Dragging")
	return true
end

local function attackNearby()
	if state == "Downed" or state == "Dragging" or not JoelConfig.ContactDamageEnabled then
		return
	end
	-- This intentionally does not depend on target selection or Touched. Every
	-- healthy character is checked each heartbeat; RescueController owns strike
	-- count, ragdolling, health protection, and permanent incapacitation.
	for _, binding in pairs(bindingsByPlayer) do
		if not bindingIsHuntable(binding) then
			continue
		end
		if binding.player:GetAttribute(ADMIN_INVINCIBLE_ATTRIBUTE) == true then
			continue
		end
		if (binding.root.Position - joelRoot.Position).Magnitude > JoelConfig.CatchRadius then
			continue
		end

		local reachable = not JoelConfig.CatchRequiresLineOfSight
			or canSee(
				joelRoot.Position + Vector3.new(0, 1, 0),
				binding.root.Position + Vector3.new(0, 0.75, 0),
				{ joel, binding.character }
			)
		if reachable and bindingIsHuntable(binding) and beginCatch(binding) then
			return
		end
	end
end

local function prepareActiveDrag(now: number): boolean
	if state ~= "Dragging" then
		return false
	end
	local drag = activeDrag
	if not drag then
		forgetTarget()
		setState("Prowl")
		return false
	end

	local validVictim = drag.player.Parent == Players
		and drag.player.Character == drag.character
		and drag.character.Parent ~= nil
		and drag.root:IsDescendantOf(drag.character)
		and drag.player:GetAttribute(JoelConfig.RescueStateAttribute) == JoelConfig.RescueDraggingState
	if not validVictim then
		endActiveDrag(false, "victim became invalid")
		return false
	end
	if not JoelConfig.isSameFloorDrop(joelRoot.Position, drag.dropPosition) then
		endActiveDrag(false, "Joel left the destination floor")
		return false
	end
	if JoelConfig.dragTimedOut(drag.startedAt, now) then
		endActiveDrag(false, "drag timed out")
		return false
	end
	if JoelConfig.hasReachedDragDrop(joelRoot.Position, drag.dropPosition) then
		endActiveDrag(true, "destination reached")
		return false
	end
	return true
end

local function monitorDragPath(now: number, moveGoal: Vector3?): boolean
	local drag = activeDrag
	if state ~= "Dragging" or not drag then
		return false
	end
	if moveGoal then
		drag.pathFailedAt = nil
	elseif pathFailed and not pathPending and not drag.pathFailedAt then
		drag.pathFailedAt = now
	end
	if drag.pathFailedAt and JoelConfig.dragFailureExpired(drag.pathFailedAt, now) then
		endActiveDrag(false, "drop point remained unreachable")
		return false
	end
	if drag.stuckAt and JoelConfig.dragFailureExpired(drag.stuckAt, now) then
		endActiveDrag(false, "Joel remained stuck while dragging")
		return false
	end
	return true
end

-- Movement decisions ---------------------------------------------------------

local PROWL_GOAL_ATTEMPTS = 12

--[[
	A wander goal has to be somewhere he could actually stand, near home.

	Two independent things went wrong without this. The floor probe rejects
	points over open space. The leash rejects points outside the patrol area,
	which is what stops the random walk escaping the building: goals are picked
	relative to his current position, so once he was outside there was nothing
	drawing him back and he simply kept going across the Baseplate.
]]
local function prowlGoalIsSane(candidate: Vector3): boolean
	local fromHome = candidate - spawnPivot.Position
	if Vector3.new(fromHome.X, 0, fromHome.Z).Magnitude > JoelConfig.ProwlLeashRadius then
		return false
	end
	sightParams.FilterDescendantsInstances = { joel }
	return Workspace:Raycast(candidate + Vector3.new(0, 8, 0), Vector3.new(0, -48, 0), sightParams) ~= nil
end

local function chooseProwlGoal(now: number): Vector3
	local reached = not prowlGoal or (prowlGoal - joelRoot.Position).Magnitude < 7
	if reached or (pathFailed and not pathPending) then
		local picked: Vector3? = nil
		for _ = 1, PROWL_GOAL_ATTEMPTS do
			local angle = math.random() * math.pi * 2
			local radius = 24 + math.random() * 42
			local candidate = joelRoot.Position + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
			if prowlGoalIsSane(candidate) then
				picked = candidate
				break
			end
		end

		-- Nothing valid within reach means he is off the leash already — either
		-- drifted out or deliberately parked outside the map for testing. Head
		-- home instead of rolling another random point deeper into the void.
		prowlGoal = picked or spawnPivot.Position
		clearPath()
		nextRepath = now
	end
	return prowlGoal :: Vector3
end

local function chooseSearchGoal(now: number): Vector3?
	local anchor = lastKnownAt
	if not anchor then
		return nil
	end
	if not searchGoal then
		searchGoal = anchor
		return searchGoal
	end

	local reached = (searchGoal - joelRoot.Position).Magnitude <= JoelConfig.WaypointReached + 1
	if reached and now >= nextSearchDecision then
		searchStep += 1
		local fraction = ((searchStep - 1) % 4) / 3
		local radius = JoelConfig.SearchRadiusMin + fraction * (JoelConfig.SearchRadiusMax - JoelConfig.SearchRadiusMin)
		local angle = searchStep * 2.399963229728653 -- golden angle avoids a repeated square patrol
		searchGoal = anchor + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		nextSearchDecision = now + JoelConfig.SearchPointInterval
		clearPath()
		nextRepath = now
	end
	return searchGoal
end

local function desiredSpeed(clock: number): number
	if state == "Dormant" or state == "Downed" or state == "Resting" then
		return 0
	elseif state == "Dragging" then
		return JoelConfig.DragSpeed
	elseif state == "Prowl" then
		return JoelConfig.ProwlSpeed
	elseif state == "Search" then
		return JoelConfig.SearchSpeed
	elseif state == "Investigate" then
		return JoelConfig.InvestigateSpeed
	end

	local binding = targetBinding
	local targetWalkSpeed = if binding and bindingIsHuntable(binding) then binding.humanoid.WalkSpeed else nil
	return JoelConfig.speedFor(targetWalkSpeed, JoelConfig.isSprinting(clock))
end

local function movementGoal(now: number): Vector3?
	if state == "Dragging" then
		local drag = activeDrag
		return if drag then moveToward(now, drag.dropPosition, nil) else nil
	end

	if state == "Prowl" then
		local goal = chooseProwlGoal(now)
		return moveToward(now, goal, nil)
	end

	if state == "Chase" then
		local binding = targetBinding
		if not binding or not bindingIsHuntable(binding) then
			return nil
		end
		local contact = sensedTarget
		local goal: Vector3?
		if contact and contact.visible then
			goal = JoelConfig.interceptPoint(
				joelRoot.Position,
				contact.position,
				contact.velocity,
				math.max(currentSpeed, 1)
			)
		else
			goal = if lastKnownAt
				then lastKnownAt + Vector3.new(lastKnownVelocity.X, 0, lastKnownVelocity.Z) * 0.35
				else nil
		end
		if goal then
			return moveToward(now, goal, binding.character)
		end
		return nil
	end

	if state == "Investigate" or state == "Search" then
		local goal = if state == "Investigate" then lastKnownAt else chooseSearchGoal(now)
		if not goal then
			return nil
		end
		local moveGoal = moveToward(now, goal, nil)

		--[[
			A goal on another floor has no navmesh route to fail against.

			The hotel's floors are not connected by geometry — the elevators are
			teleports — so pathfinding to a point one floor up does not find a
			bad route, it grinds out a full search and returns nothing. Waiting
			for that failure before considering the cab graph cost a repath
			interval (0.4s) plus the search itself, every cycle, and the practical
			effect was that Joel would mill about the floor he was already on
			instead of walking to the lift. It also stranded him completely if he
			was ever placed off the map, where nothing is reachable.

			A floor mismatch is knowable up front, so take it up front and let the
			cab graph (then translocation) have the decision immediately. Same-floor
			goals are untouched and still get the full pathfinding attempt first.
		]]
		local crossFloor = JoelConfig.floorOf(goal) ~= JoelConfig.floorOf(joelRoot.Position)
		if not crossFloor and (moveGoal or not pathFailed or pathPending) then
			return moveGoal
		end

		-- Elevators are teleports in this place, so disconnected floors have no
		-- navmesh route. Prefer the building's cab graph, then an unseen horror
		-- translocation near Joel's remembered (not omniscient) target position.
		local cab = cabToward(goal)
		if cab then
			joelHumanoid:MoveTo(cab.arrive.Position)
			if (joelRoot.Position - cab.arrive.Position).Magnitude < 6 then
				local all = cabs()
				local partner = if cab.partnerId then all[cab.partnerId] else nil
				if partner then
					joel:PivotTo(partner.arrive.CFrame)
					joelRoot.AssemblyLinearVelocity = Vector3.zero
					clearPath()
				end
			end
			return cab.arrive.Position
		end

		local binding = targetBinding
		if
			binding
			and bindingIsHuntable(binding)
			and (binding.root.Position - joelRoot.Position).Magnitude >= JoelConfig.TeleportMinTargetDistance
			and now - lastTeleportAt >= JoelConfig.TeleportCooldown
			and not observed()
			and translocate(binding, goal)
		then
			lastTeleportAt = now
		end
	end
	return nil
end

-- Main loop ------------------------------------------------------------------

local started = os.clock()
local nextPerception = 0
publishState()
clearCycle()

RunService.Heartbeat:Connect(function(delta: number)
	if not joelRoot.Parent or joelHumanoid.Health <= 0 then
		return
	end

	local now = os.clock()
	if state == "Downed" then
		currentSpeed = 0
		joelHumanoid.WalkSpeed = 0
		joelHumanoid:MoveTo(joelRoot.Position)
		if now >= downedUntil then
			reviveJoel()
		else
			publishCycle(JoelConfig.PhaseDowned, downedEndsAt)
			publishState()
			return
		end
	end
	if now - started < JoelConfig.StartGraceSeconds then
		endActiveDrag(false, "start grace became active")
		setState("Dormant")
		currentSpeed = 0
		joelHumanoid.WalkSpeed = 0
		joelHumanoid:MoveTo(joelRoot.Position)
		publishState()
		return
	end

	pollLobbyExit(now)

	local epoch = cycleEpoch
	if not epoch then
		-- Nobody has left their first stay and got out of the lobby, so there is
		-- no round to hunt in. He waits where he was placed, and with no phase
		-- published the plaque stays off every screen rather than counting down
		-- nothing.
		forgetTarget()
		currentSpeed = 0
		joelHumanoid.WalkSpeed = 0
		joelHumanoid:MoveTo(joelRoot.Position)
		setState("Dormant")
		return
	end

	-- Both numbers come off the same GetServerTimeNow() reading, so the published
	-- deadline is the boundary itself and holds still frame to frame instead of
	-- drifting by a heartbeat's worth of clock each time.
	local serverNow = Workspace:GetServerTimeNow()
	local phase, remaining = JoelConfig.cycleAt(serverNow - epoch)
	publishCycle(phase, serverNow + remaining)

	--[[
		The stand-down is a real stop, not a slower prowl. Joel drops whoever he
		was following, plants where he is, and stops sensing entirely — hearing
		included, which is the part that matters, because his ears reach through
		walls and a stand-down that only blinded him would still have him waiting
		outside the door you ran through. A chase that runs into the window is
		genuinely broken rather than resumed from the same corridor fifteen
		seconds later, which is the whole reason the window is worth spending.

		A drag already under way is the one thing it does not interrupt. Cutting
		one short would leave the victim mid-carry between two of the rescue
		system's states for no reason a player could read; he finishes the
		delivery and stands down for whatever is left of the window.

		Speed is eased to a halt rather than zeroed. MoveTo already stops him
		dead, so this is purely for CurrentSpeed, which is what JoelHorrorRun
		blends its stride against — snapping it would jam the run animation
		mid-stride instead of letting it settle.
	]]
	if phase == JoelConfig.PhaseRest then
		if state ~= "Dragging" then
			forgetTarget()
			currentSpeed = JoelConfig.approachSpeed(currentSpeed, 0, delta)
			joelHumanoid.WalkSpeed = currentSpeed
			joelHumanoid:MoveTo(joelRoot.Position)
			stuckAnchor = joelRoot.Position
			stuckSince = now
			setState("Resting")
			return
		end
	elseif state == "Resting" then
		-- The window just reopened. Perception only runs every tenth of a second,
		-- and leaving him Resting until it next fires would shave that off the
		-- front of the hunt.
		setState("Prowl")
	end

	local dragging = prepareActiveDrag(now)
	if not dragging then
		if now >= nextPerception then
			nextPerception = now + JoelConfig.PerceptionInterval
			refreshPerception(now)
		end

		attackNearby()
		dragging = state == "Dragging" and activeDrag ~= nil
	end

	local clock = Workspace:GetServerTimeNow()
	currentSpeed = JoelConfig.approachSpeed(currentSpeed, desiredSpeed(clock), delta)
	joelHumanoid.WalkSpeed = currentSpeed
	local moveGoal = movementGoal(now)
	if dragging and not monitorDragPath(now, moveGoal) then
		joelHumanoid:MoveTo(joelRoot.Position)
		publishState()
		return
	end

	if moveGoal then
		if not dragging then
			maybeJump(now, moveGoal - joelRoot.Position)
		end
		local travelled = (joelRoot.Position - stuckAnchor).Magnitude
		if travelled >= JoelConfig.StuckDistance then
			stuckAnchor = joelRoot.Position
			stuckSince = now
			if dragging and activeDrag then
				activeDrag.stuckAt = nil
			end
		elseif now - stuckSince >= JoelConfig.StuckWindow then
			if dragging and activeDrag then
				activeDrag.stuckAt = activeDrag.stuckAt or now
			else
				joelHumanoid.Jump = true
			end
			clearPath()
			nextRepath = now
			stuckAnchor = joelRoot.Position
			stuckSince = now
		end
	else
		joelHumanoid:MoveTo(joelRoot.Position)
		stuckAnchor = joelRoot.Position
		stuckSince = now
	end

	publishState()
end)

joelHumanoid.Died:Connect(function()
	endActiveDrag(false, "Joel died")
	task.wait(4)
	joel:PivotTo(spawnPivot)
	joelHumanoid.Health = joelHumanoid.MaxHealth
	currentSpeed = 0
	clearTarget()
end)

print("[JoelService] polished hunter brain online")
