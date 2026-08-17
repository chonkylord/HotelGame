--!strict
-- Authority for the survival loop: hearts, hunger, sprint stamina, walk speed.
--
-- Everything that can be cheated lives here. The client only tells us whether
-- shift is held; this script decides whether that counts as sprinting, spends
-- the stamina, drains hunger, and owns Humanoid.WalkSpeed. SurvivalClient is
-- handed the resulting numbers purely so it has something to draw.
--
-- Food is tag driven — see SurvivalConfig.FoodAttributes. Tag anything "Food"
-- and it is bound automatically, whether it is a Tool or a plate on a table.
-- World food is eaten by clicking it (ClickDetector); Tools are eaten on use.
-- Other server code can also fire ServerStorage.SurvivalFeed to top a player up.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage:WaitForChild("SurvivalConfig"))
local RescueConfig = require(ReplicatedStorage:WaitForChild("RescueConfig"))
local RouletteConfig = require(ReplicatedStorage:WaitForChild("RouletteConfig"))

local MAX_HEALTH = Config.maxHealth()
local MAX_STAMINA = Config.SprintSeconds
local ATTR = Config.FoodAttributes
local ADMIN_INFINITE_SPRINT_ATTRIBUTE = "AdminInfiniteSprint"
local ADMIN_INVINCIBLE_ATTRIBUTE = "AdminInvincible"

-- Remotes --------------------------------------------------------------------

local function ensureChild(parent: Instance, name: string, className: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end
	local created = Instance.new(className)
	created.Name = name
	created.Parent = parent
	return created
end

local remotes = ensureChild(ReplicatedStorage, Config.RemotesFolder, "Folder")
local statsEvent = ensureChild(remotes, Config.StatsEvent, "RemoteEvent") :: RemoteEvent
local sprintEvent = ensureChild(remotes, Config.SprintEvent, "RemoteEvent") :: RemoteEvent
local feedEvent = ensureChild(ServerStorage, "SurvivalFeed", "BindableEvent") :: BindableEvent

-- Player state ---------------------------------------------------------------

type State = {
	hunger: number,
	stamina: number,
	wantsSprint: boolean,
	exhausted: boolean,
	sprinting: boolean,
	blocked: boolean,
	lastSprintAt: number,
	appliedSpeed: number,
	baseJumpPower: number,
	baseJumpHeight: number,
	sinceBroadcast: number,
}

local states: { [Player]: State } = {}

local function newState(): State
	return {
		hunger = Config.HungerOnSpawn,
		stamina = MAX_STAMINA,
		wantsSprint = false,
		exhausted = false,
		sprinting = false,
		blocked = false,
		lastSprintAt = 0,
		appliedSpeed = -1,
		baseJumpPower = 50,
		baseJumpHeight = 7.2,
		sinceBroadcast = math.huge,
	}
end

local function positiveAttribute(player: Player, name: string, fallback: number): number
	local value = player:GetAttribute(name)
	if typeof(value) ~= "number" or value <= 0 then
		return fallback
	end
	return value
end

local function nonNegativeAttribute(player: Player, name: string): number
	local value = player:GetAttribute(name)
	if typeof(value) ~= "number" or value < 0 then
		return 0
	end
	return value
end

local function livingHumanoid(player: Player): Humanoid?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

local function broadcast(player: Player, state: State)
	state.sinceBroadcast = 0
	statsEvent:FireClient(player, {
		hunger = state.hunger,
		stamina = if player:GetAttribute(ADMIN_INFINITE_SPRINT_ATTRIBUTE) == true then MAX_STAMINA else state.stamina,
		sprinting = state.sprinting,
		blocked = state.blocked,
	})
end

local function onCharacterAdded(player: Player, character: Model)
	local state = states[player]
	if not state then
		return
	end

	-- Fresh body, fresh meters. Hunger surviving death would mean respawning
	-- straight into the slow walk, which reads as a bug rather than a penalty.
	state.hunger = Config.HungerOnSpawn
	state.stamina = MAX_STAMINA
	state.exhausted = false
	state.wantsSprint = false
	state.sprinting = false
	state.blocked = false
	state.appliedSpeed = -1

	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not (humanoid and humanoid:IsA("Humanoid")) then
		warn(`[Survival] {player.Name} spawned without a Humanoid; meters are idle.`)
		return
	end

	-- Order matters: raising MaxHealth first would leave Health sitting at the
	-- old value and the hearts starting the round part empty.
	state.baseJumpPower = humanoid.JumpPower
	state.baseJumpHeight = humanoid.JumpHeight

	local healthMultiplier = positiveAttribute(player, RouletteConfig.HealthMultiplierAttribute, 1)
	local speedMultiplier = positiveAttribute(player, RouletteConfig.SpeedMultiplierAttribute, 1)
	local jumpMultiplier = positiveAttribute(player, RouletteConfig.JumpMultiplierAttribute, 1)
	humanoid.MaxHealth = MAX_HEALTH * healthMultiplier
	humanoid.Health = humanoid.MaxHealth
	humanoid.WalkSpeed = Config.BaseWalkSpeed * speedMultiplier
	if humanoid.UseJumpPower then
		humanoid.JumpPower = state.baseJumpPower * jumpMultiplier
	else
		humanoid.JumpHeight = state.baseJumpHeight * jumpMultiplier
	end

	broadcast(player, state)
end

local function onPlayerAdded(player: Player)
	states[player] = newState()

	player.CharacterAdded:Connect(function(character: Model)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	states[player] = nil
end)

-- Sprint input ---------------------------------------------------------------

-- The client is only ever trusted for "shift is down". Whether that turns into
-- speed is decided in the step below.
sprintEvent.OnServerEvent:Connect(function(player: Player, held: any)
	local state = states[player]
	if not state or typeof(held) ~= "boolean" then
		return
	end
	if held and RescueConfig.isImmobilized(player:GetAttribute(RescueConfig.StateAttribute)) then
		return
	end
	state.wantsSprint = held
end)

-- Simulation -----------------------------------------------------------------

local function step(player: Player, state: State, dt: number)
	local humanoid = livingHumanoid(player)
	if not humanoid then
		state.sprinting = false
		state.blocked = false
		return
	end
	local rescueState = player:GetAttribute(RescueConfig.StateAttribute)
	local immobilized = RescueConfig.isImmobilized(rescueState)
	if immobilized then
		state.wantsSprint = false
	end

	local infiniteSprint = player:GetAttribute(ADMIN_INFINITE_SPRINT_ATTRIBUTE) == true
	if infiniteSprint then
		state.stamina = MAX_STAMINA
		state.exhausted = false
	end
	local sprintAllowed = not immobilized
		and Config.sprintAllowed(state.hunger, state.stamina, state.exhausted, infiniteSprint)
	-- Standing still with shift held should not burn the bar down.
	local moving = not immobilized and humanoid.MoveDirection.Magnitude > 0.1

	state.sprinting = state.wantsSprint and moving and sprintAllowed
	state.blocked = state.wantsSprint and not sprintAllowed

	if state.sprinting then
		state.lastSprintAt = os.clock()
		if not infiniteSprint then
			state.stamina -= dt
			if state.stamina <= 0 then
				state.stamina = 0
				-- Bottoming out locks sprint until the bar has recovered a little,
				-- otherwise you could tap shift at empty and keep going.
				state.exhausted = true
				state.sprinting = false
				state.blocked = state.wantsSprint
			end
		end
	elseif not infiniteSprint and state.stamina < MAX_STAMINA then
		if os.clock() - state.lastSprintAt >= Config.SprintRegenDelay then
			state.stamina = math.min(MAX_STAMINA, state.stamina + Config.SprintRegenPerSecond * dt)
		end
	end

	if state.exhausted and state.stamina >= MAX_STAMINA * Config.SprintRecoveryFraction then
		state.exhausted = false
	end

	if not immobilized then
		local drain = Config.HungerDrainPerSecond * (if state.sprinting then Config.SprintHungerMultiplier else 1)
		state.hunger = math.max(0, state.hunger - drain * dt)
	end

	if
		not immobilized
		and state.hunger <= 0
		and Config.StarveDamagePerSecond > 0
		and player:GetAttribute(ADMIN_INVINCIBLE_ATTRIBUTE) ~= true
	then
		humanoid:TakeDamage(Config.StarveDamagePerSecond * dt)
	end

	-- Roulette modifiers are Player attributes written only by RouletteService.
	-- Keeping their application here matters because this service already owns
	-- WalkSpeed and MaxHealth; two independent scripts writing either property
	-- would make the last heartbeat win and effects would flicker or disappear.
	local healthMultiplier = positiveAttribute(player, RouletteConfig.HealthMultiplierAttribute, 1)
	local desiredMaxHealth = MAX_HEALTH * healthMultiplier
	if math.abs(humanoid.MaxHealth - desiredMaxHealth) > 0.01 then
		local previousMaxHealth = humanoid.MaxHealth
		local healthFraction = if previousMaxHealth > 0 then humanoid.Health / previousMaxHealth else 1
		humanoid.MaxHealth = desiredMaxHealth
		humanoid.Health = if immobilized
			then math.clamp(humanoid.Health, 0, desiredMaxHealth)
			else math.clamp(healthFraction * desiredMaxHealth, 0, desiredMaxHealth)
	end

	local regen = nonNegativeAttribute(player, RouletteConfig.RegenAttribute)
	if not immobilized and regen > 0 and humanoid.Health < humanoid.MaxHealth then
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + regen * dt)
	end

	local jumpMultiplier = positiveAttribute(player, RouletteConfig.JumpMultiplierAttribute, 1)
	if humanoid.UseJumpPower then
		local desired = if immobilized then 0 else state.baseJumpPower * jumpMultiplier
		if math.abs(humanoid.JumpPower - desired) > 0.01 then
			humanoid.JumpPower = desired
		end
	else
		local desired = if immobilized then 0 else state.baseJumpHeight * jumpMultiplier
		if math.abs(humanoid.JumpHeight - desired) > 0.01 then
			humanoid.JumpHeight = desired
		end
	end

	local speedMultiplier = positiveAttribute(player, RouletteConfig.SpeedMultiplierAttribute, 1)
	local carrySpeedMultiplier = positiveAttribute(player, RescueConfig.CarrySpeedMultiplierAttribute, 1)
	local speedHunger = Config.speedHunger(state.hunger, state.sprinting, infiniteSprint)
	local speed = if immobilized
		then 0
		else Config.walkSpeedFor(speedHunger, state.sprinting) * speedMultiplier * carrySpeedMultiplier
	if math.abs(speed - state.appliedSpeed) > 0.01 then
		state.appliedSpeed = speed
		humanoid.WalkSpeed = speed
	end
end

RunService.Heartbeat:Connect(function(dt: number)
	for player, state in states do
		step(player, state, dt)
		state.sinceBroadcast += dt
		if state.sinceBroadcast >= Config.BroadcastInterval then
			broadcast(player, state)
		end
	end
end)

-- Food -----------------------------------------------------------------------

local function feed(player: Player, hunger: number, health: number, stamina: number)
	local state = states[player]
	if not state then
		return
	end

	if hunger ~= 0 then
		state.hunger = math.clamp(state.hunger + hunger, 0, Config.MaxHunger)
	end
	if health > 0 and not RescueConfig.isImmobilized(player:GetAttribute(RescueConfig.StateAttribute)) then
		local humanoid = livingHumanoid(player)
		if humanoid then
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + health)
		end
	end
	if stamina > 0 then
		state.stamina = math.min(MAX_STAMINA, state.stamina + stamina)
		-- An energy drink should hand sprint straight back rather than leaving
		-- the player locked out with a full bar.
		if state.stamina >= MAX_STAMINA * Config.SprintRecoveryFraction then
			state.exhausted = false
		end
	end
	broadcast(player, state)
end

feedEvent.Event:Connect(function(player: any, hunger: any, health: any, stamina: any)
	if typeof(player) == "Instance" and player:IsA("Player") then
		feed(player, tonumber(hunger) or 0, tonumber(health) or 0, tonumber(stamina) or 0)
	end
end)

local function numberAttribute(item: Instance, name: string, default: number): number
	local value = item:GetAttribute(name)
	return if typeof(value) == "number" then value else default
end

-- One serving: top the player up, then spend a use and retire the item if that
-- was the last one.
local function serve(player: Player, item: Instance)
	feed(
		player,
		numberAttribute(item, ATTR.Hunger, Config.DefaultHungerRestore),
		numberAttribute(item, ATTR.Health, 0),
		numberAttribute(item, ATTR.Stamina, 0)
	)

	local remaining = numberAttribute(item, ATTR.Uses, 1) - 1
	if remaining > 0 then
		item:SetAttribute(ATTR.Uses, remaining)
		return false
	end
	return true
end

local function anchorPartOf(item: Instance): BasePart?
	if item:IsA("BasePart") then
		return item
	end
	if item:IsA("Model") then
		local primary = item.PrimaryPart
		if primary then
			return primary
		end
		return item:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local bindings: { [Instance]: { RBXScriptConnection } } = {}

local function bindFood(item: Instance)
	if bindings[item] then
		return
	end
	local connections: { RBXScriptConnection } = {}
	bindings[item] = connections

	if item:IsA("Tool") then
		table.insert(
			connections,
			item.Activated:Connect(function()
				local character = item.Parent
				local player = if character then Players:GetPlayerFromCharacter(character) else nil
				if not player then
					return
				end
				if serve(player, item) then
					item:Destroy()
				end
			end)
		)
		return
	end

	local anchor = anchorPartOf(item)
	if not anchor then
		warn(`[Survival] Food tag on {item:GetFullName()} has no part to click on.`)
		return
	end

	-- Food in the world is eaten by clicking it. Hanging the detector off the
	-- Model rather than one part makes every piece of the model clickable, which
	-- matters for the multi-part meshes in the food pack.
	local host: Instance = if item:IsA("Model") then item else anchor
	local detector = item:FindFirstChildWhichIsA("ClickDetector", true)
	if not detector then
		local created = Instance.new("ClickDetector")
		created.Name = "EatClick"
		created.MaxActivationDistance = Config.FoodClickReach
		created.Parent = host
		detector = created
	end
	local eatClick = detector :: ClickDetector

	table.insert(
		connections,
		eatClick.MouseClick:Connect(function(player: Player)
			-- MouseClick already enforces MaxActivationDistance, but it is the
			-- client that reports the click, so re-check the range here.
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not root or not root:IsA("BasePart") then
				return
			end
			if (root.Position - anchor.Position).Magnitude > eatClick.MaxActivationDistance + 4 then
				return
			end

			if not serve(player, item) then
				return
			end

			local respawn = numberAttribute(item, ATTR.Respawn, 0)
			if respawn <= 0 then
				item:Destroy()
				return
			end

			-- Park it out of the world rather than destroying it, so the same
			-- instance (and its attributes) comes back untouched.
			local home = item.Parent
			local uses = numberAttribute(item, ATTR.Uses, 1)
			eatClick.MaxActivationDistance = 0
			item.Parent = nil
			task.delay(respawn, function()
				if not home or not home.Parent then
					return
				end
				item:SetAttribute(ATTR.Uses, uses)
				item.Parent = home
				eatClick.MaxActivationDistance = Config.FoodClickReach
			end)
		end)
	)
end

local function unbindFood(item: Instance)
	local connections = bindings[item]
	if not connections then
		return
	end
	bindings[item] = nil
	for _, connection in connections do
		connection:Disconnect()
	end
end

for _, item in CollectionService:GetTagged(Config.FoodTag) do
	bindFood(item)
end
CollectionService:GetInstanceAddedSignal(Config.FoodTag):Connect(bindFood)
CollectionService:GetInstanceRemovedSignal(Config.FoodTag):Connect(unbindFood)

print(`[Survival] Online — {Config.Hearts} hearts, {Config.SprintSeconds}s sprint.`)
