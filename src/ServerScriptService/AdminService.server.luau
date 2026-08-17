--!strict
-- Server authority for the private admin panel. Authorization is checked from
-- the immutable Player.Name on every request; replicated attributes are output
-- state for gameplay services and UI, never proof supplied by the client.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AdminConfig = require(ReplicatedStorage:WaitForChild("AdminConfig"))
local RescueConfig = require(ReplicatedStorage:WaitForChild("RescueConfig"))

local function ensureChild(parent: Instance, name: string, className: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		if existing:IsA(className) then
			return existing
		end
		warn(`[AdminService] replacing {existing:GetFullName()}; expected {className}`)
		existing:Destroy()
	end

	local created = Instance.new(className)
	created.Name = name
	created.Parent = parent
	return created
end

local remotes = ensureChild(ReplicatedStorage, AdminConfig.RemotesFolder, "Folder")
local toggleEvent = ensureChild(remotes, AdminConfig.ToggleEvent, "RemoteEvent") :: RemoteEvent
local resultEvent = ensureChild(remotes, AdminConfig.ResultEvent, "RemoteEvent") :: RemoteEvent

type PlayerState = {
	generation: number,
	guardedCharacter: Model?,
	guardConnections: { RBXScriptConnection },
	lifecycleConnections: { RBXScriptConnection },
	restoringHealth: boolean,
	lastToggleAt: number,
}

local states: { [Player]: PlayerState } = {}

local function disconnectAll(connections: { RBXScriptConnection })
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function removeAdminForceField(character: Model?)
	if not character then
		return
	end
	for _, child in character:GetChildren() do
		if child.Name == AdminConfig.ForceFieldName then
			child:Destroy()
		end
	end
end

local function ensureAdminForceField(character: Model): ForceField
	local kept: ForceField? = nil
	for _, child in character:GetChildren() do
		if child.Name == AdminConfig.ForceFieldName then
			if not kept and child:IsA("ForceField") then
				kept = child
			else
				child:Destroy()
			end
		end
	end

	if kept then
		kept.Visible = false
		return kept
	end

	local forceField = Instance.new("ForceField")
	forceField.Name = AdminConfig.ForceFieldName
	forceField.Visible = false
	forceField.Parent = character
	return forceField
end

local function clearCharacterGuard(state: PlayerState)
	state.generation += 1
	disconnectAll(state.guardConnections)
	state.guardedCharacter = nil
	state.restoringHealth = false
end

local function shouldGuard(player: Player, state: PlayerState, character: Model, generation: number): boolean
	return states[player] == state
		and state.generation == generation
		and state.guardedCharacter == character
		and player.Character == character
		and AdminConfig.isAuthorizedUsername(player.Name)
		and player:GetAttribute(AdminConfig.InvincibleAttribute) == true
end

local function guardCharacter(player: Player, state: PlayerState, character: Model)
	local previousCharacter = state.guardedCharacter
	clearCharacterGuard(state)
	if previousCharacter and previousCharacter ~= character then
		removeAdminForceField(previousCharacter)
	end

	state.guardedCharacter = character
	local generation = state.generation
	local forceField = ensureAdminForceField(character)

	-- If another system replaces the character's children, restore only this
	-- service's named field and only while the same body is still protected.
	table.insert(
		state.guardConnections,
		character.ChildRemoved:Connect(function(child: Instance)
			if child ~= forceField and child.Name ~= AdminConfig.ForceFieldName then
				return
			end
			task.defer(function()
				if shouldGuard(player, state, character, generation) then
					forceField = ensureAdminForceField(character)
				end
			end)
		end)
	)

	task.spawn(function()
		local humanoidInstance = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
		if not humanoidInstance or not humanoidInstance:IsA("Humanoid") then
			return
		end
		local humanoid = humanoidInstance :: Humanoid
		if not shouldGuard(player, state, character, generation) then
			return
		end

		local function restoreHealth()
			if state.restoringHealth or not shouldGuard(player, state, character, generation) then
				return
			end
			-- RescueController deliberately holds an incapacitated body at one
			-- heart (or its inert-body epsilon). Its state must win until a real
			-- revive/reset, even if an admin enables invincibility afterwards.
			if RescueConfig.isImmobilized(player:GetAttribute(RescueConfig.StateAttribute)) then
				return
			end
			if humanoid.Parent ~= character then
				return
			end

			local maximum = humanoid.MaxHealth
			if maximum <= 0 or maximum ~= maximum or maximum == math.huge or humanoid.Health >= maximum then
				return
			end

			state.restoringHealth = true
			local ok, message = pcall(function()
				humanoid.Health = maximum
			end)
			state.restoringHealth = false
			if not ok then
				warn(`[AdminService] could not restore {player.Name}'s health: {message}`)
			end
		end

		table.insert(state.guardConnections, humanoid.HealthChanged:Connect(restoreHealth))
		table.insert(state.guardConnections, humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(restoreHealth))
		restoreHealth()
	end)
end

local function applyInvincibility(player: Player, state: PlayerState, enabled: boolean)
	player:SetAttribute(AdminConfig.InvincibleAttribute, enabled)
	if enabled then
		local character = player.Character
		if character then
			guardCharacter(player, state, character)
		end
		return
	end

	local guardedCharacter = state.guardedCharacter
	clearCharacterGuard(state)
	removeAdminForceField(guardedCharacter)
	if player.Character ~= guardedCharacter then
		removeAdminForceField(player.Character)
	end
end

local function sendResult(player: Player, ok: boolean, featureId: string?, enabled: boolean?, message: string)
	resultEvent:FireClient(player, {
		ok = ok,
		featureId = featureId,
		enabled = enabled,
		message = message,
	})
end

local function onCharacterAdded(player: Player, state: PlayerState, character: Model)
	if player:GetAttribute(AdminConfig.InvincibleAttribute) == true then
		guardCharacter(player, state, character)
	else
		removeAdminForceField(character)
	end
end

local function onPlayerAdded(player: Player)
	local oldState = states[player]
	if oldState then
		disconnectAll(oldState.lifecycleConnections)
		clearCharacterGuard(oldState)
	end

	local authorized = AdminConfig.isAuthorizedUsername(player.Name)
	player:SetAttribute(AdminConfig.AuthorizedAttribute, authorized)
	player:SetAttribute(AdminConfig.InvincibleAttribute, false)
	player:SetAttribute(AdminConfig.AllClassesAttribute, false)
	player:SetAttribute(AdminConfig.InfiniteSprintAttribute, false)

	if not authorized then
		removeAdminForceField(player.Character)
		states[player] = nil
		return
	end

	local state: PlayerState = {
		generation = 0,
		guardedCharacter = nil,
		guardConnections = {},
		lifecycleConnections = {},
		restoringHealth = false,
		lastToggleAt = -math.huge,
	}
	states[player] = state

	table.insert(
		state.lifecycleConnections,
		player.CharacterAdded:Connect(function(character: Model)
			onCharacterAdded(player, state, character)
		end)
	)
	table.insert(
		state.lifecycleConnections,
		player.CharacterRemoving:Connect(function(character: Model)
			if state.guardedCharacter == character then
				clearCharacterGuard(state)
			end
			removeAdminForceField(character)
		end)
	)

	if player.Character then
		task.spawn(onCharacterAdded, player, state, player.Character)
	end
end

toggleEvent.OnServerEvent:Connect(function(player: Player, rawFeatureId: any, rawEnabled: any)
	-- The attribute is replicated for presentation, not trusted for access.
	if not AdminConfig.isAuthorizedUsername(player.Name) then
		sendResult(player, false, nil, nil, "Not authorized")
		return
	end

	local state = states[player]
	if not state or player:GetAttribute(AdminConfig.AuthorizedAttribute) ~= true then
		sendResult(player, false, nil, nil, "Admin state is not ready")
		return
	end
	if typeof(rawFeatureId) ~= "string" or typeof(rawEnabled) ~= "boolean" then
		sendResult(player, false, nil, nil, "Invalid toggle request")
		return
	end

	local feature = AdminConfig.findFeature(rawFeatureId)
	if not feature then
		sendResult(player, false, rawFeatureId, nil, "Unknown admin feature")
		return
	end

	local now = os.clock()
	if now - state.lastToggleAt < AdminConfig.ToggleCooldownSeconds then
		sendResult(player, false, feature.id, player:GetAttribute(feature.attribute) == true, "Please wait")
		return
	end
	state.lastToggleAt = now

	if feature.id == AdminConfig.InvincibilityFeature then
		applyInvincibility(player, state, rawEnabled)
	else
		player:SetAttribute(feature.attribute, rawEnabled)
	end

	sendResult(player, true, feature.id, player:GetAttribute(feature.attribute) == true, "Updated")
end)

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	local state = states[player]
	if not state then
		return
	end
	states[player] = nil
	disconnectAll(state.lifecycleConnections)
	local guardedCharacter = state.guardedCharacter
	clearCharacterGuard(state)
	removeAdminForceField(guardedCharacter)
end)

print("[AdminService] ready for 2 authorized usernames")
