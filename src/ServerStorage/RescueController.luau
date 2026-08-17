--!strict
-- Server-owned rescue state, ragdolls, Joel dragging, teammate revives, and
-- shoulder carrying. Callers may request transitions; this module revalidates
-- every character, state, range, and inventory condition before mutating.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local RescueConfig = require(ReplicatedStorage:WaitForChild("RescueConfig"))
local SurvivalConfig = require(ReplicatedStorage:WaitForChild("SurvivalConfig"))
local JoelConfig = require(ReplicatedStorage:WaitForChild("JoelConfig"))

local RescueController = {}

-- Config constants are ordinary string table fields to Luau's inference, so
-- runtime validation stays in RescueConfig while records store that string.
type RescueState = string

type MotorSnapshot = {
	motor: Motor6D,
	enabled: boolean,
}

type AnimationConstraintSnapshot = {
	constraint: AnimationConstraint,
	enabled: boolean,
}

type PartSnapshot = {
	part: BasePart,
	canCollide: boolean,
	canTouch: boolean,
	massless: boolean,
	networkAutomatic: boolean,
	networkOwner: Player?,
}

type RagdollSnapshot = {
	character: Model,
	humanoid: Humanoid,
	requiresNeck: boolean,
	autoRotate: boolean,
	platformStand: boolean,
	breakJointsOnDeath: boolean,
	deadStateEnabled: boolean,
	motors: { MotorSnapshot },
	animationConstraints: { AnimationConstraintSnapshot },
	parts: { PartSnapshot },
	created: { Instance },
	animate: LocalScript?,
	animateEnabled: boolean,
}

type CarryLink = {
	created: { Instance },
	collisions: { [BasePart]: boolean },
	motorPoses: { [Motor6D]: CFrame },
}

export type DragJob = {
	player: Player,
	joel: Model,
	generation: number,
	active: boolean,
	created: { Instance },
	victimPart: BasePart,
	joelPart: BasePart,
}

export type CatchResult = { outcome: "Drag", job: DragJob, dropPosition: Vector3 } | { outcome: "Incapacitated" }

type PlayerRecord = {
	player: Player,
	state: RescueState,
	catches: number,
	generation: number,
	character: Model?,
	humanoid: Humanoid?,
	root: BasePart?,
	ragdoll: RagdollSnapshot?,
	dragJob: DragJob?,
	carrier: PlayerRecord?,
	carriedBody: PlayerRecord?,
	carriedBaseState: RescueState?,
	carryLink: CarryLink?,
	healthGuard: boolean,
	connections: { RBXScriptConnection },
	characterConnections: { RBXScriptConnection },
}

local records: { [Player]: PlayerRecord } = {}
local random = Random.new()

local function disconnectAll(connections: { RBXScriptConnection })
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function destroyAll(instances: { Instance })
	for index = #instances, 1, -1 do
		local instance = instances[index]
		if instance.Parent then
			instance:Destroy()
		end
	end
	table.clear(instances)
end

local function liveParts(record: PlayerRecord): (Model?, Humanoid?, BasePart?)
	local character = record.character
	local humanoid = record.humanoid
	local root = record.root
	if
		not character
		or character ~= record.player.Character
		or not character:IsDescendantOf(Workspace)
		or not humanoid
		or humanoid.Parent ~= character
		or not root
		or root.Parent ~= character
	then
		return nil, nil, nil
	end
	return character, humanoid, root
end

local function bodyAnchor(character: Model): BasePart?
	local candidate = character:FindFirstChild("UpperTorso")
		or character:FindFirstChild("Torso")
		or character:FindFirstChild("HumanoidRootPart")
	return if candidate and candidate:IsA("BasePart") then candidate else nil
end

local function shouldCollideWhileDown(part: BasePart): boolean
	if part.Name == "HumanoidRootPart" then
		return false
	end
	local name = string.lower(part.Name)
	return name == "head"
		or string.find(name, "torso", 1, true) ~= nil
		or string.find(name, "leg", 1, true) ~= nil
		or string.find(name, "foot", 1, true) ~= nil
end

local function getPart(model: Model, names: { string }): BasePart?
	for _, name in names do
		local candidate = model:FindFirstChild(name, true)
		if candidate and candidate:IsA("BasePart") then
			return candidate
		end
	end
	return nil
end

local function effectiveBodyState(record: PlayerRecord): RescueState
	if record.state == RescueConfig.StateCarried and record.carriedBaseState then
		return record.carriedBaseState
	end
	return record.state
end

local function protectedHealth(record: PlayerRecord): number?
	local humanoid = record.humanoid
	if not humanoid then
		return nil
	end
	local state = effectiveBodyState(record)
	if state == RescueConfig.StateDead then
		return 1
	end
	if state == RescueConfig.StateDragging or state == RescueConfig.StateDowned then
		-- SurvivalClient fills eight hearts from Health / MaxHealth. Deriving the
		-- amount from the live maximum keeps this exactly one visible heart even
		-- while a roulette health multiplier is active.
		return math.max(1, humanoid.MaxHealth / SurvivalConfig.Hearts)
	end
	return nil
end

local function enforceProtectedHealth(record: PlayerRecord)
	if record.healthGuard then
		return
	end
	local desired = protectedHealth(record)
	local humanoid = record.humanoid
	if not desired or not humanoid or humanoid.Parent == nil then
		return
	end
	if math.abs(humanoid.Health - desired) <= 0.001 then
		return
	end
	record.healthGuard = true
	humanoid.Health = desired
	record.healthGuard = false
end

local function publishState(record: PlayerRecord, state: RescueState)
	record.state = state
	record.player:SetAttribute(RescueConfig.StateAttribute, state)
	local character = record.character
	if character then
		character:SetAttribute(RescueConfig.StateAttribute, state)
	end
	enforceProtectedHealth(record)
end

local function setServerOwnership(character: Model)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") and not descendant.Anchored then
			pcall(function()
				descendant:SetNetworkOwner(nil)
			end)
		end
	end
end

local function applyRagdoll(record: PlayerRecord): boolean
	local character, humanoid = liveParts(record)
	if not character or not humanoid then
		return false
	end
	if record.ragdoll and record.ragdoll.character == character then
		setServerOwnership(character)
		return true
	end

	local animateInstance = character:FindFirstChild("Animate")
	local animate = if animateInstance and animateInstance:IsA("LocalScript") then animateInstance else nil
	local snapshot: RagdollSnapshot = {
		character = character,
		humanoid = humanoid,
		requiresNeck = humanoid.RequiresNeck,
		autoRotate = humanoid.AutoRotate,
		platformStand = humanoid.PlatformStand,
		breakJointsOnDeath = humanoid.BreakJointsOnDeath,
		deadStateEnabled = humanoid:GetStateEnabled(Enum.HumanoidStateType.Dead),
		motors = {},
		animationConstraints = {},
		parts = {},
		created = {},
		animate = animate,
		animateEnabled = if animate then animate.Enabled else false,
	}
	record.ragdoll = snapshot
	-- Install death protection before disabling Neck (or any other joint).
	-- RequiresNeck is evaluated immediately by Roblox, so doing this after the
	-- motor loop can briefly create a real death and schedule an auto-respawn.
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	if animate then
		animate.Enabled = false
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in animator:GetPlayingAnimationTracks() do
			track:Stop(0.12)
		end
	end

	local staleField = character:FindFirstChild("RescueBodyForceField")
	if staleField then
		staleField:Destroy()
	end
	local forceField = Instance.new("ForceField")
	forceField.Name = "RescueBodyForceField"
	forceField.Visible = false
	forceField.Parent = character
	table.insert(snapshot.created, forceField)

	local bodyParts: { [BasePart]: boolean } = {}
	local jointIndex = 0
	local function addSocket(attachment0: Attachment, attachment1: Attachment, jointName: string)
		local part0 = attachment0.Parent
		local part1 = attachment1.Parent
		if not part0 or not part0:IsA("BasePart") or not part1 or not part1:IsA("BasePart") then
			return
		end
		jointIndex += 1
		bodyParts[part0] = true
		bodyParts[part1] = true

		local socket = Instance.new("BallSocketConstraint")
		socket.Name = `RescueSocket{jointIndex}`
		socket.Attachment0 = attachment0
		socket.Attachment1 = attachment1
		socket.LimitsEnabled = true
		socket.UpperAngle = if string.find(string.lower(jointName), "neck", 1, true) then 38 else 68
		socket.TwistLimitsEnabled = true
		socket.TwistLowerAngle = -45
		socket.TwistUpperAngle = 45
		socket.MaxFrictionTorque = if string.find(string.lower(jointName), "neck", 1, true) then 16 else 6
		socket.Parent = character
		table.insert(snapshot.created, socket)

		local noCollision = Instance.new("NoCollisionConstraint")
		noCollision.Name = `RescueNoCollision{jointIndex}`
		noCollision.Part0 = part0
		noCollision.Part1 = part1
		noCollision.Parent = character
		table.insert(snapshot.created, noCollision)
	end

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("Motor6D") then
			local part0 = descendant.Part0
			local part1 = descendant.Part1
			if not part0 or not part1 then
				continue
			end
			table.insert(snapshot.motors, { motor = descendant, enabled = descendant.Enabled })

			local attachment0 = Instance.new("Attachment")
			attachment0.Name = `RescueMotorJoint{#snapshot.motors}A`
			attachment0.CFrame = descendant.C0
			attachment0.Parent = part0
			table.insert(snapshot.created, attachment0)
			local attachment1 = Instance.new("Attachment")
			attachment1.Name = `RescueMotorJoint{#snapshot.motors}B`
			attachment1.CFrame = descendant.C1
			attachment1.Parent = part1
			table.insert(snapshot.created, attachment1)

			addSocket(attachment0, attachment1, descendant.Name)
			descendant.Enabled = false
		elseif descendant:IsA("AnimationConstraint") then
			local attachment0 = descendant.Attachment0
			local attachment1 = descendant.Attachment1
			if not attachment0 or not attachment1 then
				continue
			end
			table.insert(snapshot.animationConstraints, {
				constraint = descendant,
				enabled = descendant.Enabled,
			})
			addSocket(attachment0, attachment1, descendant.Name)
			descendant.Enabled = false
		end
	end

	for part in bodyParts do
		local automatic = true
		local owner: Player? = nil
		pcall(function()
			automatic = part:GetNetworkOwnershipAuto()
			owner = part:GetNetworkOwner()
		end)
		table.insert(snapshot.parts, {
			part = part,
			canCollide = part.CanCollide,
			canTouch = part.CanTouch,
			massless = part.Massless,
			networkAutomatic = automatic,
			networkOwner = owner,
		})
		part.CanCollide = shouldCollideWhileDown(part)
		part.CanTouch = false
		part.Massless = false
	end

	humanoid.AutoRotate = false
	humanoid.PlatformStand = true
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	setServerOwnership(character)
	return true
end

local function restoreRagdoll(record: PlayerRecord)
	local snapshot = record.ragdoll
	if not snapshot then
		return
	end
	record.ragdoll = nil

	for _, saved in snapshot.motors do
		if saved.motor.Parent then
			saved.motor.Enabled = saved.enabled
		end
	end
	for _, saved in snapshot.animationConstraints do
		if saved.constraint.Parent then
			saved.constraint.Enabled = saved.enabled
		end
	end
	destroyAll(snapshot.created)
	for _, saved in snapshot.parts do
		local part = saved.part
		if part.Parent then
			part.CanCollide = saved.canCollide
			part.CanTouch = saved.canTouch
			part.Massless = saved.massless
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
			pcall(function()
				if saved.networkAutomatic then
					part:SetNetworkOwnershipAuto()
				else
					part:SetNetworkOwner(saved.networkOwner)
				end
			end)
		end
	end

	local humanoid = snapshot.humanoid
	if humanoid.Parent then
		humanoid.RequiresNeck = snapshot.requiresNeck
		humanoid.BreakJointsOnDeath = snapshot.breakJointsOnDeath
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, snapshot.deadStateEnabled)
		humanoid.AutoRotate = snapshot.autoRotate
		humanoid.PlatformStand = snapshot.platformStand
		if snapshot.animate and snapshot.animate.Parent then
			snapshot.animate.Enabled = snapshot.animateEnabled
		end
		if humanoid.Health > 0 then
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end
end

local function releaseCreated(instances: { Instance })
	destroyAll(instances)
end

local function placeBodyBesideCarrier(carrier: PlayerRecord, body: PlayerRecord)
	local carrierCharacter, _, carrierRoot = liveParts(carrier)
	local bodyCharacter = body.character
	if not carrierCharacter or not carrierRoot or not bodyCharacter or not bodyCharacter:IsDescendantOf(Workspace) then
		return
	end
	local candidate = carrierRoot.Position
		- carrierRoot.CFrame.LookVector * 2.8
		+ carrierRoot.CFrame.RightVector * 2.4
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { carrierCharacter, bodyCharacter }
	local floor = Workspace:Raycast(candidate + Vector3.new(0, 6, 0), Vector3.new(0, -18, 0), params)
	local position = if floor then floor.Position + Vector3.new(0, 2.7, 0) else candidate
	local pivot = bodyCharacter:GetPivot()
	bodyCharacter:PivotTo(CFrame.new(position) * pivot.Rotation)
	for _, descendant in bodyCharacter:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function validDropZones(joel: Model): { BasePart }
	local origin = joel:GetPivot().Position
	local floorId = JoelConfig.floorOf(origin)
	local zones: { BasePart } = {}
	for _, instance in CollectionService:GetTagged(RescueConfig.DropZoneTag) do
		if
			instance:IsA("BasePart")
			and instance:IsDescendantOf(Workspace)
			and instance:GetAttribute(RescueConfig.DropZoneFloorAttribute) == floorId
		then
			table.insert(zones, instance)
		end
	end
	return zones
end

local function createDragJob(record: PlayerRecord, joel: Model): DragJob?
	local character = record.character
	if not character then
		return nil
	end
	local joelPart = getPart(joel, { "RightHand", "Right Arm", "HumanoidRootPart" })
	local victimPart = getPart(character, { "LeftFoot", "LeftLowerLeg", "Left Leg", "HumanoidRootPart" })
	if not joelPart or not victimPart then
		return nil
	end

	local created: { Instance } = {}
	local handAttachment = Instance.new("Attachment")
	handAttachment.Name = "RescueDragHand"
	handAttachment.Position = Vector3.new(0, -joelPart.Size.Y * 0.45, 0)
	handAttachment.Parent = joelPart
	table.insert(created, handAttachment)

	local ankleAttachment = Instance.new("Attachment")
	ankleAttachment.Name = "RescueDragAnkle"
	ankleAttachment.Position = Vector3.new(0, -victimPart.Size.Y * 0.42, 0)
	ankleAttachment.Parent = victimPart
	table.insert(created, ankleAttachment)

	local align = Instance.new("AlignPosition")
	align.Name = "RescueDragAlign"
	align.Attachment0 = ankleAttachment
	align.Attachment1 = handAttachment
	align.ApplyAtCenterOfMass = false
	align.MaxForce = 100000
	align.MaxVelocity = JoelConfig.DragSpeed * 1.35
	align.Responsiveness = 17
	align.RigidityEnabled = false
	align.ReactionForceEnabled = false
	align.Parent = victimPart
	table.insert(created, align)

	-- The ragdoll still collides with the hotel floor, but never with Joel's
	-- own rig. Without this pairwise suppression a shoulder or knee can wedge
	-- under him and fling both assemblies while the ankle constraint pulls.
	for _, victimDescendant in character:GetDescendants() do
		if not victimDescendant:IsA("BasePart") or not shouldCollideWhileDown(victimDescendant) then
			continue
		end
		for _, joelDescendant in joel:GetDescendants() do
			if joelDescendant:IsA("BasePart") then
				local noCollision = Instance.new("NoCollisionConstraint")
				noCollision.Name = "RescueDragNoCollision"
				noCollision.Part0 = victimDescendant
				noCollision.Part1 = joelDescendant
				noCollision.Parent = victimDescendant
				table.insert(created, noCollision)
			end
		end
	end

	return {
		player = record.player,
		joel = joel,
		generation = record.generation,
		active = true,
		created = created,
		victimPart = victimPart,
		joelPart = joelPart,
	}
end

local function dropCarryRecord(carrier: PlayerRecord): boolean
	local body = carrier.carriedBody
	if not body then
		return false
	end
	carrier.carriedBody = nil
	body.carrier = nil
	carrier.player:SetAttribute(RescueConfig.CarryingUserIdAttribute, 0)
	carrier.player:SetAttribute(RescueConfig.CarrySpeedMultiplierAttribute, 1)
	body.player:SetAttribute(RescueConfig.CarrierUserIdAttribute, 0)

	local link = body.carryLink
	body.carryLink = nil
	if link then
		releaseCreated(link.created)
		for motor, c0 in link.motorPoses do
			if motor.Parent then
				motor.C0 = c0
			end
		end
		placeBodyBesideCarrier(carrier, body)
		for part, canCollide in link.collisions do
			if part.Parent then
				part.CanCollide = canCollide
			end
		end
	end

	local baseState = body.carriedBaseState
	body.carriedBaseState = nil
	if body.state == RescueConfig.StateCarried and baseState then
		publishState(body, baseState)
	end
	if body.character then
		setServerOwnership(body.character)
	end
	return true
end

local function createCarryLink(carrier: PlayerRecord, body: PlayerRecord): CarryLink?
	local carrierCharacter = carrier.character
	local bodyCharacter = body.character
	if not carrierCharacter or not bodyCharacter then
		return nil
	end
	local carrierTorso = bodyAnchor(carrierCharacter)
	local bodyTorso = bodyAnchor(bodyCharacter)
	if not carrierTorso or not bodyTorso then
		return nil
	end

	local created: { Instance } = {}
	local collisions: { [BasePart]: boolean } = {}
	local motorPoses: { [Motor6D]: CFrame } = {}
	for _, descendant in bodyCharacter:GetDescendants() do
		if descendant:IsA("BasePart") then
			collisions[descendant] = descendant.CanCollide
			descendant.CanCollide = false
		end
	end

	local shoulder = Instance.new("Attachment")
	shoulder.Name = "RescueShoulderTarget"
	shoulder.CFrame = CFrame.new(0, 1.3, 0.15) * CFrame.Angles(0, 0, math.rad(90))
	shoulder.Parent = carrierTorso
	table.insert(created, shoulder)

	local bodyAttachment = Instance.new("Attachment")
	bodyAttachment.Name = "RescueBodyCarry"
	bodyAttachment.Parent = bodyTorso
	table.insert(created, bodyAttachment)

	local position = Instance.new("AlignPosition")
	position.Name = "RescueCarryPosition"
	position.Attachment0 = bodyAttachment
	position.Attachment1 = shoulder
	position.MaxForce = 120000
	position.MaxVelocity = 16
	position.Responsiveness = 13
	position.RigidityEnabled = false
	position.ReactionForceEnabled = false
	position.Parent = bodyTorso
	table.insert(created, position)

	local orientation = Instance.new("AlignOrientation")
	orientation.Name = "RescueCarryOrientation"
	orientation.Attachment0 = bodyAttachment
	orientation.Attachment1 = shoulder
	orientation.MaxTorque = 120000
	orientation.MaxAngularVelocity = 9
	orientation.Responsiveness = 11
	orientation.RigidityEnabled = false
	orientation.ReactionTorqueEnabled = false
	orientation.Parent = bodyTorso
	table.insert(created, orientation)

	local carrierHumanoid = carrier.humanoid
	local upperTorso = getPart(carrierCharacter, { "UpperTorso" })
	if carrierHumanoid and upperTorso then
		-- R15 arms brace the body instead of continuing their stock walk swing.
		-- IK stays local to this carry link and blends in/out through SmoothTime.
		for _, side in { "Left", "Right" } do
			local upperArm = getPart(carrierCharacter, { `{side}UpperArm` })
			local hand = getPart(carrierCharacter, { `{side}Hand` })
			if not upperArm or not hand then
				continue
			end
			local handTarget = Instance.new("Attachment")
			handTarget.Name = `Rescue{side}CarryHandTarget`
			handTarget.CFrame = CFrame.new(if side == "Left" then -0.72 else 0.72, 0.34, 0.28)
			handTarget.Parent = upperTorso
			table.insert(created, handTarget)

			local ik = Instance.new("IKControl")
			ik.Name = `Rescue{side}CarryArm`
			ik.Type = Enum.IKControlType.Position
			ik.ChainRoot = upperArm
			ik.EndEffector = hand
			ik.Target = handTarget
			ik.SmoothTime = 0.16
			ik.Weight = 0.82
			ik.Priority = 12
			ik.Enabled = true
			ik.Parent = carrierHumanoid
			table.insert(created, ik)
		end
	else
		-- R6 has no arm chain for IKControl, so preserve and temporarily rotate
		-- its two shoulder bases into a braced carry silhouette.
		for _, pose in {
			{ name = "Left Shoulder", angle = -42 },
			{ name = "Right Shoulder", angle = 42 },
		} do
			local joint = carrierTorso:FindFirstChild(pose.name)
			if joint and joint:IsA("Motor6D") then
				motorPoses[joint] = joint.C0
				joint.C0 = joint.C0 * CFrame.Angles(0, 0, math.rad(pose.angle))
			end
		end
	end

	setServerOwnership(bodyCharacter)
	return { created = created, collisions = collisions, motorPoses = motorPoses }
end

local function nearestCarryTarget(carrier: PlayerRecord): PlayerRecord?
	local _, _, carrierRoot = liveParts(carrier)
	if not carrierRoot then
		return nil
	end
	local nearest: PlayerRecord? = nil
	local nearestDistance = RescueConfig.BodyPickupRange
	for _, candidate in records do
		if candidate == carrier or not RescueConfig.canPickUp(candidate.state) or candidate.carrier then
			continue
		end
		local _, _, candidateRoot = liveParts(candidate)
		if not candidateRoot then
			continue
		end
		local distance = (carrierRoot.Position - candidateRoot.Position).Magnitude
		if distance <= nearestDistance then
			nearest = candidate
			nearestDistance = distance
		end
	end
	return nearest
end

local function clearDrag(record: PlayerRecord, nextState: RescueState?): boolean
	local job = record.dragJob
	if not job then
		return false
	end
	record.dragJob = nil
	job.active = false
	releaseCreated(job.created)
	if nextState and record.state == RescueConfig.StateDragging then
		publishState(record, nextState)
	end
	return true
end

local function clearRelationships(record: PlayerRecord)
	if record.carriedBody then
		dropCarryRecord(record)
	end
	if record.carrier then
		dropCarryRecord(record.carrier)
	end
	clearDrag(record, nil)
end

local function resetRecord(record: PlayerRecord, character: Model?)
	clearRelationships(record)
	restoreRagdoll(record)
	disconnectAll(record.characterConnections)
	record.generation += 1
	record.character = character
	record.humanoid = nil
	record.root = nil
	record.catches = 0
	record.player:SetAttribute(RescueConfig.CatchCountAttribute, 0)
	record.player:SetAttribute(RescueConfig.CarrierUserIdAttribute, 0)
	record.player:SetAttribute(RescueConfig.CarryingUserIdAttribute, 0)
	record.player:SetAttribute(RescueConfig.CarrySpeedMultiplierAttribute, 1)
	publishState(record, RescueConfig.StateHealthy)

	if not character then
		return
	end
	local generation = record.generation
	task.spawn(function()
		local humanoidInstance = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
		local rootInstance = character:FindFirstChild("HumanoidRootPart")
			or character:WaitForChild("HumanoidRootPart", 10)
		if
			record.generation ~= generation
			or character ~= record.player.Character
			or not humanoidInstance
			or not humanoidInstance:IsA("Humanoid")
			or not rootInstance
			or not rootInstance:IsA("BasePart")
		then
			return
		end
		record.humanoid = humanoidInstance
		record.root = rootInstance
		-- resetRecord is also the round-reset path for an existing persistent
		-- ragdoll body. A state-only reset would leave a formerly Dead player at
		-- the hidden one-HP body value while publishing Healthy.
		if humanoidInstance.Health > 0 then
			humanoidInstance.Health = humanoidInstance.MaxHealth
			humanoidInstance.PlatformStand = false
			humanoidInstance.AutoRotate = true
			humanoidInstance:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
		table.insert(
			record.characterConnections,
			humanoidInstance.HealthChanged:Connect(function()
				enforceProtectedHealth(record)
			end)
		)
		table.insert(
			record.characterConnections,
			humanoidInstance:GetPropertyChangedSignal("MaxHealth"):Connect(function()
				enforceProtectedHealth(record)
			end)
		)
	end)
end

function RescueController.initializePlayer(player: Player)
	if records[player] then
		return
	end
	local record: PlayerRecord = {
		player = player,
		state = RescueConfig.StateHealthy,
		catches = 0,
		generation = 0,
		character = nil,
		humanoid = nil,
		root = nil,
		ragdoll = nil,
		dragJob = nil,
		carrier = nil,
		carriedBody = nil,
		carriedBaseState = nil,
		carryLink = nil,
		healthGuard = false,
		connections = {},
		characterConnections = {},
	}
	records[player] = record
	if player:GetAttribute(RescueConfig.BandageCountAttribute) == nil then
		player:SetAttribute(RescueConfig.BandageCountAttribute, 0)
	end
	table.insert(
		record.connections,
		player.CharacterAdded:Connect(function(character)
			resetRecord(record, character)
		end)
	)
	table.insert(
		record.connections,
		player.CharacterRemoving:Connect(function(character)
			if record.character == character then
				resetRecord(record, nil)
			end
		end)
	)
	resetRecord(record, player.Character)
end

function RescueController.resetPlayer(player: Player)
	RescueController.initializePlayer(player)
	local record = records[player]
	if record then
		resetRecord(record, player.Character)
	end
end

function RescueController.resetAll()
	for _, record in records do
		resetRecord(record, record.player.Character)
	end
end

RescueController.resetRound = RescueController.resetAll

function RescueController.getState(player: Player): RescueState
	local record = records[player]
	return if record then record.state else RescueConfig.StateHealthy
end

function RescueController.beginCatch(player: Player, joel: Model): CatchResult?
	local record = records[player]
	if
		not record
		or record.state ~= RescueConfig.StateHealthy
		or player:GetAttribute("AdminInvincible") == true
		or not joel:IsDescendantOf(Workspace)
	then
		return nil
	end
	local character = liveParts(record)
	if not character then
		return nil
	end
	if record.carriedBody then
		dropCarryRecord(record)
	end

	local outcome = RescueConfig.catchOutcome(record.catches)
	record.catches += 1
	player:SetAttribute(RescueConfig.CatchCountAttribute, record.catches)
	if outcome == "Incapacitated" then
		if not applyRagdoll(record) then
			record.catches -= 1
			player:SetAttribute(RescueConfig.CatchCountAttribute, record.catches)
			return nil
		end
		publishState(record, RescueConfig.StateDead)
		return { outcome = "Incapacitated" }
	end

	if not applyRagdoll(record) then
		record.catches -= 1
		player:SetAttribute(RescueConfig.CatchCountAttribute, record.catches)
		return nil
	end
	local zones = validDropZones(joel)
	if #zones == 0 then
		publishState(record, RescueConfig.StateDowned)
		warn(`[RescueController] no same-floor rescue drop zone for {player.Name}; downed in place`)
		return nil
	end
	publishState(record, RescueConfig.StateDragging)
	local job = createDragJob(record, joel)
	if not job then
		publishState(record, RescueConfig.StateDowned)
		return nil
	end
	record.dragJob = job
	local zone = zones[random:NextInteger(1, #zones)]
	return { outcome = "Drag", job = job, dropPosition = zone.Position }
end

local function finishJob(job: DragJob): boolean
	if not job.active then
		return false
	end
	local record = records[job.player]
	if not record or record.dragJob ~= job or record.generation ~= job.generation then
		job.active = false
		releaseCreated(job.created)
		return false
	end
	return clearDrag(record, RescueConfig.StateDowned)
end

function RescueController.finishDrag(job: DragJob): boolean
	return finishJob(job)
end

function RescueController.abortDrag(job: DragJob): boolean
	return finishJob(job)
end

function RescueController.dropCarry(carrier: Player): boolean
	local record = records[carrier]
	return if record then dropCarryRecord(record) else false
end

function RescueController.toggleCarry(carrier: Player, requestedTarget: Player?): (boolean, string?)
	local carrierRecord = records[carrier]
	if not carrierRecord then
		return false, "Carrier is not initialized"
	end
	if carrierRecord.carriedBody then
		dropCarryRecord(carrierRecord)
		return true, "Body dropped"
	end
	if carrierRecord.state ~= RescueConfig.StateHealthy then
		return false, "You cannot carry anyone right now"
	end
	local _, carrierHumanoid, carrierRoot = liveParts(carrierRecord)
	if not carrierHumanoid or carrierHumanoid.Health <= 0 or not carrierRoot then
		return false, "Your character is not ready"
	end

	local body = if requestedTarget then records[requestedTarget] else nearestCarryTarget(carrierRecord)
	if not body or body == carrierRecord then
		return false, "No body is close enough"
	end
	if not RescueConfig.canPickUp(body.state) or body.carrier or body.dragJob then
		return false, "That body cannot be carried"
	end
	local _, _, bodyRoot = liveParts(body)
	if not bodyRoot or (carrierRoot.Position - bodyRoot.Position).Magnitude > RescueConfig.BodyPickupRange then
		return false, "That body is out of reach"
	end
	if not applyRagdoll(body) then
		return false, "That body is not ready"
	end
	local link = createCarryLink(carrierRecord, body)
	if not link then
		return false, "Could not lift that body"
	end

	body.carriedBaseState = body.state
	body.carrier = carrierRecord
	body.carryLink = link
	carrierRecord.carriedBody = body
	body.player:SetAttribute(RescueConfig.CarrierUserIdAttribute, carrier.UserId)
	carrier:SetAttribute(RescueConfig.CarryingUserIdAttribute, body.player.UserId)
	carrier:SetAttribute(RescueConfig.CarrySpeedMultiplierAttribute, RescueConfig.CarrySpeedMultiplier)
	publishState(body, RescueConfig.StateCarried)
	return true, "Body lifted"
end

function RescueController.revive(reviver: Player, target: Player): (boolean, string?)
	local reviverRecord = records[reviver]
	local targetRecord = records[target]
	if not reviverRecord or not targetRecord or reviverRecord == targetRecord then
		return false, "Invalid revive target"
	end
	if reviverRecord.state ~= RescueConfig.StateHealthy then
		return false, "You cannot revive anyone right now"
	end
	local targetState = effectiveBodyState(targetRecord)
	if targetState ~= RescueConfig.StateDowned then
		return false, "That teammate cannot be revived"
	end
	local _, reviverHumanoid, reviverRoot = liveParts(reviverRecord)
	local _, targetHumanoid, targetRoot = liveParts(targetRecord)
	if
		not reviverHumanoid
		or reviverHumanoid.Health <= 0
		or not reviverRoot
		or not targetHumanoid
		or not targetRoot
		or (reviverRoot.Position - targetRoot.Position).Magnitude > RescueConfig.ReviveRange
	then
		return false, "That teammate is out of reach"
	end
	local rawBandages = reviver:GetAttribute(RescueConfig.BandageCountAttribute)
	local bandages = if typeof(rawBandages) == "number" then math.max(0, math.floor(rawBandages)) else 0
	if bandages < 1 then
		return false, "A bandage is required"
	end

	-- All validation above is non-yielding. Spend exactly one only after the
	-- transition is known to be possible, and drop both sides before restoring.
	if reviverRecord.carriedBody then
		dropCarryRecord(reviverRecord)
	end
	if targetRecord.carrier then
		dropCarryRecord(targetRecord.carrier)
	end
	reviver:SetAttribute(RescueConfig.BandageCountAttribute, bandages - 1)
	local reviveHealth = math.max(1, targetHumanoid.MaxHealth / SurvivalConfig.Hearts)
	publishState(targetRecord, RescueConfig.StateHealthy)
	restoreRagdoll(targetRecord)
	if targetHumanoid.Parent then
		targetHumanoid.Health = reviveHealth
	end
	return true, "Teammate revived"
end

local function removePlayer(player: Player)
	local record = records[player]
	if not record then
		return
	end
	clearRelationships(record)
	restoreRagdoll(record)
	disconnectAll(record.characterConnections)
	disconnectAll(record.connections)
	records[player] = nil
end

Players.PlayerAdded:Connect(RescueController.initializePlayer)
for _, player in Players:GetPlayers() do
	RescueController.initializePlayer(player)
end
Players.PlayerRemoving:Connect(removePlayer)

RunService.Heartbeat:Connect(function()
	for _, record in records do
		enforceProtectedHealth(record)
		local carriedBody = record.carriedBody
		if carriedBody then
			local _, carrierHumanoid, carrierRoot = liveParts(record)
			local _, _, bodyRoot = liveParts(carriedBody)
			if
				record.state ~= RescueConfig.StateHealthy
				or not carrierHumanoid
				or carrierHumanoid.Health <= 0
				or not carrierRoot
				or not bodyRoot
				or carriedBody.state ~= RescueConfig.StateCarried
				or (carrierRoot.Position - bodyRoot.Position).Magnitude > RescueConfig.CarryBreakDistance
			then
				dropCarryRecord(record)
			end
		end
		local job = record.dragJob
		if
			job
			and (
				not job.joel:IsDescendantOf(Workspace)
				or not job.victimPart:IsDescendantOf(Workspace)
				or not job.joelPart:IsDescendantOf(Workspace)
				or (job.victimPart.Position - job.joelPart.Position).Magnitude > RescueConfig.DragBreakDistance
			)
		then
			finishJob(job)
		end
	end
end)

return RescueController
