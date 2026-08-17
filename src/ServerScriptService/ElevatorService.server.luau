--!strict
-- Every working elevator in the hotel. Links today:
--   Lobby  -> Rooms       (ONE WAY: the lobby sends guests to the hotel /
--                          apartment room floor, with no ride back)
--   Suite <-> Amenities   (suite floor <-> the ballroom/restaurant floor)
--
-- Links are directional: a cab travels to its Partner, and the return trip
-- exists only if that partner names this cab back. A cab with no Partner at all
-- is a terminus - its button still works its doors, it just goes nowhere. That
-- is how Rooms is a dead end: guests can still open up and walk out, but the
-- button will not take them back down to the lobby.
--
-- The cab button is the whole interface. Press it with the doors open and the
-- cab "travels" - the doors shut, then everyone still standing inside is moved
-- to the partner cab, which is also shut. Press it again and the doors open
-- onto the other floor. Because the move happens behind closed doors, the ride
-- reads as one elevator rather than two rooms with a teleport between them.
--
-- This replaced the per-cab free-model scripts. Those paired cabs by reaching
-- for a sibling ("script.Parent.Parent.TP2") that only ever existed in the
-- OTHER model, so every one of them threw on click and no elevator worked.
--
-- Wiring is by tag + attribute, so renaming a cab does not break the link:
--   ElevatorCab    - the cab Model. "CabId" is its unique id, "Partner" is the
--                    CabId it travels to (omit Partner for a terminus). Ids are
--                    used rather than model names because two different cabs
--                    are both named "Elevator 1" (the lobby is duplicated in
--                    this place).
--   ElevatorArrive - invisible Part marking where riders land, at
--                    HumanoidRootPart height and facing the doors. Drag it in
--                    Studio to retune the landing spot; no code change.
--
-- Each cab needs ButtonDoor.{Button.ClickDetector, Door1, Door2}, and must be
-- SAVED WITH ITS DOORS SHUT - that pose is captured as the closed position at
-- startup. Doors slide apart along their own look axis, matching the original
-- door script.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local OnboardingConfig = require(ReplicatedStorage:WaitForChild("OnboardingConfig"))

local DOOR_SLIDE = 4
local DOOR_TIME = 2
local RIDER_SPACING = 2

local DOOR_TWEEN = TweenInfo.new(DOOR_TIME, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)

type Cab = {
	id: string,
	model: Model,
	arrive: BasePart,
	door1: BasePart,
	door2: BasePart,
	shut1: CFrame,
	shut2: CFrame,
	openSound: Sound?,
	closeSound: Sound?,
	partnerId: string?,
	isOpen: boolean,
	busy: boolean,
}

local cabs: { [string]: Cab } = {}
local connections: { [Model]: { RBXScriptConnection } } = {}

local function findArrive(root: Instance): BasePart?
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") and CollectionService:HasTag(descendant, "ElevatorArrive") then
			return descendant
		end
	end
	return nil
end

-- Yields for the length of the slide so callers can sequence "shut, then move".
local function setDoors(cab: Cab, open: boolean)
	local goal1 = if open then cab.shut1 + cab.shut1.LookVector * DOOR_SLIDE else cab.shut1
	local goal2 = if open then cab.shut2 + cab.shut2.LookVector * DOOR_SLIDE else cab.shut2

	local sound = if open then cab.openSound else cab.closeSound
	if sound then
		sound:Play()
	end

	TweenService:Create(cab.door1, DOOR_TWEEN, { CFrame = goal1 }):Play()
	TweenService:Create(cab.door2, DOOR_TWEEN, { CFrame = goal2 }):Play()
	task.wait(DOOR_TIME)

	cab.isOpen = open
end

local function ridersIn(cab: Cab): { Player }
	local pivot, size = cab.model:GetBoundingBox()
	local half = size / 2

	local riders = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local offset = pivot:PointToObjectSpace(root.Position)
			if math.abs(offset.X) <= half.X and math.abs(offset.Y) <= half.Y and math.abs(offset.Z) <= half.Z then
				table.insert(riders, player)
			end
		end
	end
	return riders
end

local function sendRiders(riders: { Player }, source: Cab, destination: Cab)
	for index, player in ipairs(riders) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if character and humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
			-- Fan riders out so a full cab does not land stacked on one stud.
			local column = (index - 1) % 3 - 1
			local row = math.floor((index - 1) / 3)

			humanoid.Sit = false
			character:PivotTo(destination.arrive.CFrame * CFrame.new(column * RIDER_SPACING, 0, row * RIDER_SPACING))
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero

			if
				source.id == OnboardingConfig.LOBBY_CAB_ID
				and destination.id == OnboardingConfig.ROOMS_CAB_ID
				and player:GetAttribute(OnboardingConfig.ATTRIBUTE) == OnboardingConfig.ENTER_ELEVATOR
			then
				player:SetAttribute(OnboardingConfig.ATTRIBUTE, OnboardingConfig.ENTER_ROOM)
			end
		end
	end
end

local function press(cab: Cab)
	if cab.busy then
		return
	end
	local partnerId = cab.partnerId
	local partner = if partnerId then cabs[partnerId] else nil
	local reservedPartner: Cab? = nil
	if cab.isOpen and partner and partner.busy then
		return
	end
	cab.busy = true
	-- Reserve both ends before either door starts moving. Without a shared
	-- reservation, simultaneous button presses can close both cabs and transfer
	-- both rider sets through each other.
	if cab.isOpen and partner then
		partner.busy = true
		reservedPartner = partner
	end

	if not cab.isOpen then
		setDoors(cab, true)
	else
		setDoors(cab, false)

		if partner then
			-- Riders are collected only once the doors are shut, so whoever
			-- stepped back out during the slide is left behind.
			local riders = ridersIn(cab)

			-- The far cab has to be shut too, or riders arrive staring straight
			-- out at the destination floor and the illusion breaks.
			if partner.isOpen then
				setDoors(partner, false)
			end

			sendRiders(riders, cab, partner)
		end
	end

	if reservedPartner then
		reservedPartner.busy = false
	end
	cab.busy = false
end

local function register(model: Model)
	if connections[model] then
		return
	end
	local id = model:GetAttribute("CabId")
	if type(id) ~= "string" then
		warn(`[ElevatorService] {model:GetFullName()} is tagged ElevatorCab but has no CabId attribute`)
		return
	end
	-- Partner is optional; without it this cab is a terminus (doors only).
	local rawPartner = model:GetAttribute("Partner")
	local partnerId = if type(rawPartner) == "string" then rawPartner else nil
	if cabs[id] then
		warn(`[ElevatorService] duplicate CabId "{id}" on {model:GetFullName()}`)
		return
	end

	local buttonDoor = model:FindFirstChild("ButtonDoor")
	local door1 = buttonDoor and buttonDoor:FindFirstChild("Door1")
	local door2 = buttonDoor and buttonDoor:FindFirstChild("Door2")
	if not (buttonDoor and door1 and door1:IsA("BasePart") and door2 and door2:IsA("BasePart")) then
		warn(`[ElevatorService] {model:GetFullName()} is missing ButtonDoor.Door1 / ButtonDoor.Door2`)
		return
	end

	local arrive = findArrive(model)
	if not arrive then
		warn(`[ElevatorService] {model:GetFullName()} has no ElevatorArrive part to land riders on`)
		return
	end

	local openSound = buttonDoor:FindFirstChild("open")
	local closeSound = buttonDoor:FindFirstChild("close")

	cabs[id] = {
		id = id,
		model = model,
		arrive = arrive,
		door1 = door1,
		door2 = door2,
		shut1 = door1.CFrame,
		shut2 = door2.CFrame,
		openSound = if openSound and openSound:IsA("Sound") then openSound else nil,
		closeSound = if closeSound and closeSound:IsA("Sound") then closeSound else nil,
		partnerId = partnerId,
		isOpen = false,
		busy = false,
	}
	local modelConnections: { RBXScriptConnection } = {}
	connections[model] = modelConnections

	local button = buttonDoor and buttonDoor:FindFirstChild("Button")
	local detector = button and button:FindFirstChildOfClass("ClickDetector")
	if detector then
		table.insert(
			modelConnections,
			detector.MouseClick:Connect(function()
				local cab = cabs[id]
				if cab and cab.model == model then
					press(cab)
				end
			end)
		)
	else
		warn(`[ElevatorService] cab "{id}" has no ButtonDoor.Button.ClickDetector`)
	end

	table.insert(
		modelConnections,
		model:GetAttributeChangedSignal("Partner"):Connect(function()
			local cab = cabs[id]
			if not cab or cab.model ~= model then
				return
			end
			local partner = model:GetAttribute("Partner")
			cab.partnerId = if typeof(partner) == "string" and partner ~= "" then partner else nil
		end)
	)
end

local function setup(instance: Instance)
	if instance:IsA("Model") then
		register(instance)
	end
end

local function teardown(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	local modelConnections = connections[instance]
	if modelConnections then
		for _, connection in modelConnections do
			connection:Disconnect()
		end
		connections[instance] = nil
	end
	local id = instance:GetAttribute("CabId")
	if typeof(id) == "string" then
		local cab = cabs[id]
		if cab and cab.model == instance then
			cabs[id] = nil
		end
	end
end

for _, instance in CollectionService:GetTagged("ElevatorCab") do
	setup(instance)
end
CollectionService:GetInstanceAddedSignal("ElevatorCab"):Connect(setup)
CollectionService:GetInstanceRemovedSignal("ElevatorCab"):Connect(teardown)
