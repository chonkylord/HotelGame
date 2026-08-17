--!strict
-- Server authority for the spinner hidden under Room 2's bed. Muscle reveals
-- it by lifting the bed; only then may Superman consult or sack it.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ClassConfig = require(ReplicatedStorage:WaitForChild("ClassDefinitions"))
local RouletteConfig = require(ReplicatedStorage:WaitForChild("RouletteConfig"))

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

local remotes = ensure(ReplicatedStorage, RouletteConfig.RemotesFolder, "Folder")
local openEvent = ensure(remotes, RouletteConfig.OpenEvent, "RemoteEvent") :: RemoteEvent
local spinEvent = ensure(remotes, RouletteConfig.SpinEvent, "RemoteEvent") :: RemoteEvent
local resultEvent = ensure(remotes, RouletteConfig.ResultEvent, "RemoteEvent") :: RemoteEvent

local random = Random.new()
local nextRollAt: { [Player]: number } = {}
local activeTable: { [Player]: Instance } = {}
local promptConnections: { [ProximityPrompt]: RBXScriptConnection } = {}
local liftConnections: { [ProximityPrompt]: RBXScriptConnection } = {}

local function isSuperman(player: Player): boolean
	return ClassConfig.hasClass(player, ClassConfig.SUPERMAN)
end

local function isMuscle(player: Player): boolean
	return ClassConfig.hasClass(player, ClassConfig.MUSCLE)
end

local function anchorPart(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
	end
	return instance:FindFirstChildWhichIsA("BasePart", true)
end

local function tableFor(prompt: ProximityPrompt): Instance?
	local node: Instance? = prompt
	while node and node ~= Workspace do
		if CollectionService:HasTag(node, RouletteConfig.TableTag) then
			return node
		end
		node = node.Parent
	end
	return nil
end

local function inRange(player: Player, tableInstance: Instance): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local anchor = anchorPart(tableInstance)
	if not (root and root:IsA("BasePart") and anchor) then
		return false
	end
	return (root.Position - anchor.Position).Magnitude <= RouletteConfig.InteractionDistance + 4
end

local function clearEffect(player: Player)
	player:SetAttribute(RouletteConfig.EffectIdAttribute, "")
	player:SetAttribute(RouletteConfig.EffectExpiresAttribute, 0)
	player:SetAttribute(RouletteConfig.SpeedMultiplierAttribute, 1)
	player:SetAttribute(RouletteConfig.HealthMultiplierAttribute, 1)
	player:SetAttribute(RouletteConfig.JumpMultiplierAttribute, 1)
	player:SetAttribute(RouletteConfig.RegenAttribute, 0)
end

local function applyEffect(player: Player, outcome: RouletteConfig.Outcome, expiresAt: number)
	player:SetAttribute(RouletteConfig.EffectIdAttribute, outcome.id)
	player:SetAttribute(RouletteConfig.EffectExpiresAttribute, expiresAt)
	player:SetAttribute(RouletteConfig.SpeedMultiplierAttribute, outcome.speedMultiplier or 1)
	player:SetAttribute(RouletteConfig.HealthMultiplierAttribute, outcome.healthMultiplier or 1)
	player:SetAttribute(RouletteConfig.JumpMultiplierAttribute, outcome.jumpMultiplier or 1)
	player:SetAttribute(RouletteConfig.RegenAttribute, outcome.regenPerSecond or 0)
end

local function sendOpen(player: Player, tableInstance: Instance)
	activeTable[player] = tableInstance
	openEvent:FireClient(player, {
		table = tableInstance,
		nextRollAt = nextRollAt[player] or 0,
		effectId = player:GetAttribute(RouletteConfig.EffectIdAttribute),
		effectExpiresAt = player:GetAttribute(RouletteConfig.EffectExpiresAttribute),
	})
end

local function wirePrompt(instance: Instance)
	if not instance:IsA("ProximityPrompt") or promptConnections[instance] then
		return
	end

	promptConnections[instance] = instance.Triggered:Connect(function(player: Player)
		local tableInstance = tableFor(instance)
		if not tableInstance or not tableInstance:IsDescendantOf(Workspace) then
			return
		end
		if tableInstance:GetAttribute(RouletteConfig.UnlockedAttribute) ~= true then
			return
		end
		if not isSuperman(player) or not inRange(player, tableInstance) then
			return
		end
		sendOpen(player, tableInstance)
	end)

	instance.Destroying:Connect(function()
		local connection = promptConnections[instance]
		if connection then
			connection:Disconnect()
			promptConnections[instance] = nil
		end
	end)
end

for _, instance in CollectionService:GetTagged(RouletteConfig.PromptTag) do
	wirePrompt(instance)
end
CollectionService:GetInstanceAddedSignal(RouletteConfig.PromptTag):Connect(wirePrompt)

local function bedFor(prompt: ProximityPrompt): Model?
	local node: Instance? = prompt
	while node and node ~= Workspace do
		if node:IsA("Model") and node:GetAttribute("RouletteBed") == true then
			return node
		end
		node = node.Parent
	end
	return nil
end

local function roomSpinner(): Instance?
	for _, instance in CollectionService:GetTagged(RouletteConfig.TableTag) do
		if instance:GetAttribute("RoomNumber") == 2 then
			return instance
		end
	end
	return nil
end

local function revealSpinner(spinner: Instance)
	spinner:SetAttribute(RouletteConfig.UnlockedAttribute, true)
	spinner:SetAttribute("SackLocked", false)
end

local function liftBed(bed: Model, prompt: ProximityPrompt)
	if
		bed:GetAttribute(RouletteConfig.BedLiftedAttribute) == true
		or bed:GetAttribute("RouletteBedLifting") == true
	then
		return
	end
	bed:SetAttribute("RouletteBedLifting", true)

	for _, descendant in bed:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end

	local start = bed:GetPivot()
	local target = CFrame.new(start.Position + Vector3.new(0, 4.2, 0))
		* start.Rotation
		* CFrame.Angles(math.rad(-12), 0, 0)
	local driver = Instance.new("CFrameValue")
	driver.Value = start
	local changed = driver:GetPropertyChangedSignal("Value"):Connect(function()
		if bed.Parent then
			bed:PivotTo(driver.Value)
		end
	end)
	local tween = TweenService:Create(driver, TweenInfo.new(1.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Value = target,
	})
	tween:Play()
	tween.Completed:Wait()
	changed:Disconnect()
	driver:Destroy()

	bed:SetAttribute("RouletteBedLifting", false)
	bed:SetAttribute(RouletteConfig.BedLiftedAttribute, true)
	local spinner = roomSpinner()
	if spinner then
		revealSpinner(spinner)
	end
	if prompt.Parent then
		prompt:Destroy()
	end
end

local function wireLiftPrompt(instance: Instance)
	if not instance:IsA("ProximityPrompt") or liftConnections[instance] then
		return
	end
	liftConnections[instance] = instance.Triggered:Connect(function(player: Player)
		local bed = bedFor(instance)
		if not bed or not isMuscle(player) or not inRange(player, bed) then
			return
		end
		task.spawn(liftBed, bed, instance)
	end)
	instance.Destroying:Connect(function()
		local connection = liftConnections[instance]
		if connection then
			connection:Disconnect()
			liftConnections[instance] = nil
		end
	end)
end

for _, instance in CollectionService:GetTagged(ClassConfig.BED_LIFT_PROMPT_TAG) do
	wireLiftPrompt(instance)
end
CollectionService:GetInstanceAddedSignal(ClassConfig.BED_LIFT_PROMPT_TAG):Connect(wireLiftPrompt)

local function reject(player: Player, reason: string)
	resultEvent:FireClient(player, {
		ok = false,
		reason = reason,
		nextRollAt = nextRollAt[player] or 0,
	})
end

spinEvent.OnServerEvent:Connect(function(player: Player)
	if not isSuperman(player) then
		reject(player, "The hidden spinner answers only to Superman.")
		return
	end

	local tableInstance = activeTable[player]
	if
		not tableInstance
		or not tableInstance:IsDescendantOf(Workspace)
		or not CollectionService:HasTag(tableInstance, RouletteConfig.TableTag)
		or tableInstance:GetAttribute(RouletteConfig.UnlockedAttribute) ~= true
		or not inRange(player, tableInstance)
	then
		reject(player, "The wheel has slipped out of reach.")
		return
	end

	local now = Workspace:GetServerTimeNow()
	local readyAt = nextRollAt[player] or 0
	if now < readyAt then
		reject(player, "Fate has not reset yet.")
		return
	end

	local index = random:NextInteger(1, #RouletteConfig.Outcomes)
	local outcome = RouletteConfig.Outcomes[index]
	readyAt = now + RouletteConfig.CooldownSeconds
	local expiresAt = now + RouletteConfig.EffectDurationSeconds
	nextRollAt[player] = readyAt
	player:SetAttribute(RouletteConfig.NextRollAttribute, readyAt)
	applyEffect(player, outcome, expiresAt)

	resultEvent:FireClient(player, {
		ok = true,
		index = index,
		id = outcome.id,
		name = outcome.name,
		description = outcome.description,
		good = outcome.good,
		nextRollAt = readyAt,
		effectExpiresAt = expiresAt,
	})
end)

local function watchPlayer(player: Player)
	nextRollAt[player] = 0
	player:SetAttribute(RouletteConfig.NextRollAttribute, 0)
	clearEffect(player)

	local function refreshClassEntitlement()
		if not isSuperman(player) then
			activeTable[player] = nil
			clearEffect(player)
		end
	end
	player:GetAttributeChangedSignal(ClassConfig.ATTRIBUTE):Connect(refreshClassEntitlement)
	player:GetAttributeChangedSignal(ClassConfig.ADMIN_ALL_CLASSES_ATTRIBUTE):Connect(refreshClassEntitlement)
end

for _, player in Players:GetPlayers() do
	watchPlayer(player)
end
Players.PlayerAdded:Connect(watchPlayer)

Players.PlayerRemoving:Connect(function(player: Player)
	nextRollAt[player] = nil
	activeTable[player] = nil
end)

local expiryAccumulator = 0
RunService.Heartbeat:Connect(function(deltaTime: number)
	expiryAccumulator += deltaTime
	if expiryAccumulator < 0.25 then
		return
	end
	expiryAccumulator = 0

	local now = Workspace:GetServerTimeNow()
	for _, player in Players:GetPlayers() do
		local expiresAt = player:GetAttribute(RouletteConfig.EffectExpiresAttribute)
		if typeof(expiresAt) == "number" and expiresAt > 0 and now >= expiresAt then
			clearEffect(player)
		end
	end
end)

print("[RouletteService] ready — Muscle reveals Room 2's spinner for Superman")
