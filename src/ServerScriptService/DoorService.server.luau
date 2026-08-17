--!strict
--[[
	Automatic sliding doors.

	Server-authoritative: the server owns every door's state and validates each
	call-button press against the presser's real position, so a client cannot
	open a door it is nowhere near. Clients only ever observe the tween.

	Panels are tagged "AutoDoorPanel" and carry attributes:
	  DoorId      string   groups panels belonging to the same door
	  OpenOffset  Vector3  displacement from closed to fully open

	OpenOffset is a vector rather than an axis + distance because the entrance
	leaves do not retract along a single axis. That wall is solid across the
	doorway, so a leaf is only visible at all because it sits 0.22 studs proud of
	the wall face; it therefore has to slide sideways WHILE sinking into the wall,
	otherwise it is either visible when open or invisible when closed.

	Call buttons are tagged "AutoDoorCallButton" and carry DoorId.

	Both doors in this place were originally a single slab with a cosmetic seam
	plate faking a join; DoorService expects the two real leaves produced by the
	build pass, and closed positions are captured at run time from wherever the
	leaves sit in the saved place.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local PANEL_TAG = "AutoDoorPanel"
local BUTTON_TAG = "AutoDoorCallButton"

-- How often the proximity sweep runs. 10 Hz is well under the tween duration,
-- so it never looks late, and costs nothing at this door count.
local POLL_INTERVAL = 0.1

type Mode = "proximity" | "call"

type Config = {
	mode: Mode,
	-- proximity only: how close a player must be to trigger an open
	triggerRadius: number,
	openTime: number,
	closeTime: number,
	-- seconds to stay open after the trigger clears
	holdOpen: number,
	-- never close while someone is this close to the threshold
	blockRadius: number,
	openStyle: Enum.EasingStyle,
}

local CONFIG: { [string]: Config } = {
	-- Storefront doors: snappy, they should already be moving as you approach.
	Entrance = {
		mode = "proximity",
		triggerRadius = 13,
		openTime = 0.45,
		closeTime = 0.60,
		holdOpen = 1.20,
		blockRadius = 7,
		openStyle = Enum.EasingStyle.Quart,
	},
	-- Elevator: heavier and slower, and it waits properly before closing.
	Elevator = {
		mode = "call",
		triggerRadius = 0,
		openTime = 1.15,
		closeTime = 1.35,
		holdOpen = 4.50,
		blockRadius = 6,
		openStyle = Enum.EasingStyle.Sine,
	},
}

type Panel = {
	part: BasePart,
	closed: CFrame,
	opened: CFrame,
	tween: Tween?,
}

type Door = {
	id: string,
	config: Config,
	panels: { Panel },
	centre: Vector3,
	isOpen: boolean,
	closeAt: number?,
}

local doors: { [string]: Door } = {}

local function attrString(inst: Instance, name: string): string?
	local v = inst:GetAttribute(name)
	return if type(v) == "string" then v else nil
end

local function attrVector3(inst: Instance, name: string): Vector3?
	local v = inst:GetAttribute(name)
	return if typeof(v) == "Vector3" then v else nil
end

local function registerPanel(inst: Instance)
	if not inst:IsA("BasePart") then
		return
	end
	local part = inst :: BasePart

	local id = attrString(part, "DoorId")
	if not id then
		warn(`[DoorService] {part:GetFullName()} is tagged but has no DoorId attribute`)
		return
	end

	local config = CONFIG[id]
	if not config then
		warn(`[DoorService] no config for DoorId "{id}" ({part:GetFullName()})`)
		return
	end

	local offset = attrVector3(part, "OpenOffset")
	if not offset then
		warn(`[DoorService] {part:GetFullName()} has no OpenOffset Vector3 attribute; it will not move`)
		return
	end
	if offset.Magnitude < 0.01 then
		warn(`[DoorService] {part:GetFullName()} has a zero OpenOffset; it will not move`)
	end

	local door = doors[id]
	if not door then
		door = {
			id = id,
			config = config,
			panels = {},
			centre = Vector3.zero,
			isOpen = false,
			closeAt = nil,
		}
		doors[id] = door
	end
	assert(door, "door was just created")

	local closed = part.CFrame
	table.insert(door.panels, {
		part = part,
		closed = closed,
		opened = closed + offset,
		tween = nil,
	})

	local sum = Vector3.zero
	for _, panel in door.panels do
		sum += panel.closed.Position
	end
	door.centre = sum / #door.panels
end

local function setOpen(door: Door, open: boolean)
	if door.isOpen == open then
		return
	end
	door.isOpen = open

	local config = door.config
	local info = TweenInfo.new(
		if open then config.openTime else config.closeTime,
		if open then config.openStyle else Enum.EasingStyle.Sine,
		if open then Enum.EasingDirection.Out else Enum.EasingDirection.InOut
	)

	for _, panel in door.panels do
		-- Cancel rather than let two tweens fight over CFrame mid-travel.
		local existing = panel.tween
		if existing then
			existing:Cancel()
		end
		local goal = if open then panel.opened else panel.closed
		local tween = TweenService:Create(panel.part, info, { CFrame = goal })
		panel.tween = tween
		tween:Play()
	end
end

local function nearestPlayerDistance(point: Vector3): number
	local best = math.huge
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character.PrimaryPart
		if root then
			local distance = (root.Position - point).Magnitude
			if distance < best then
				best = distance
			end
		end
	end
	return best
end

local function registerButton(inst: Instance)
	if not inst:IsA("BasePart") then
		return
	end
	local part = inst :: BasePart

	local id = attrString(part, "DoorId")
	if not id then
		warn(`[DoorService] call button {part:GetFullName()} has no DoorId attribute`)
		return
	end

	local detector = part:FindFirstChildOfClass("ClickDetector")
	if not detector then
		local created = Instance.new("ClickDetector")
		created.MaxActivationDistance = 14
		created.Parent = part
		detector = created
	end
	assert(detector, "detector exists")

	local baseColour = part.Color
	local flashing = false
	local function acknowledge()
		if flashing then
			return
		end
		flashing = true
		local lift = TweenService:Create(part, TweenInfo.new(0.10), { Color = Color3.new(1, 1, 1) })
		lift.Completed:Connect(function()
			TweenService:Create(part, TweenInfo.new(0.45), { Color = baseColour }):Play()
			flashing = false
		end)
		lift:Play()
	end

	detector.MouseClick:Connect(function(player: Player)
		-- A ClickDetector fires on the server, but the click itself is the only
		-- thing we know is real -- re-derive proximity from the character.
		local character = player.Character
		local root = character and character.PrimaryPart
		if not root then
			return
		end
		if (root.Position - part.Position).Magnitude > detector.MaxActivationDistance + 6 then
			return
		end

		local door = doors[id]
		if not door then
			return
		end
		door.closeAt = os.clock() + door.config.holdOpen
		setOpen(door, true)
		acknowledge()
	end)
end

for _, panel in CollectionService:GetTagged(PANEL_TAG) do
	registerPanel(panel)
end
for _, button in CollectionService:GetTagged(BUTTON_TAG) do
	registerButton(button)
end
CollectionService:GetInstanceAddedSignal(PANEL_TAG):Connect(registerPanel)
CollectionService:GetInstanceAddedSignal(BUTTON_TAG):Connect(registerButton)

local accumulator = 0
RunService.Heartbeat:Connect(function(deltaTime: number)
	accumulator += deltaTime
	if accumulator < POLL_INTERVAL then
		return
	end
	accumulator = 0

	local now = os.clock()
	for _, door in doors do
		if #door.panels == 0 then
			continue
		end
		local config = door.config
		local nearest = nearestPlayerDistance(door.centre)

		if config.mode == "proximity" then
			if nearest <= config.triggerRadius then
				door.closeAt = nil
				setOpen(door, true)
			elseif door.isOpen then
				local closeAt = door.closeAt
				if closeAt == nil then
					door.closeAt = now + config.holdOpen
				elseif now >= closeAt then
					door.closeAt = nil
					setOpen(door, false)
				end
			end
		else
			local closeAt = door.closeAt
			if door.isOpen and closeAt ~= nil and now >= closeAt then
				if nearest <= config.blockRadius then
					-- Someone is still in the doorway; hold it like a real lift.
					door.closeAt = now + 1.5
				else
					door.closeAt = nil
					setOpen(door, false)
				end
			end
		end
	end
end)

do
	local summary = {}
	for id, door in doors do
		table.insert(summary, `{id}({#door.panels} panels, {door.config.mode})`)
	end
	table.sort(summary)
	print(`[DoorService] ready: {if #summary > 0 then table.concat(summary, ", ") else "NO DOORS FOUND"}`)
end
