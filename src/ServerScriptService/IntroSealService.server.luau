--!strict
--[[
	The moment the hotel stops being a hotel.

	A first-time guest is walked through check-in by Noel, up in the lift and
	along the corridor under normal light — see HorrorGradeProfiles.Calm for why
	the intro is lit at all. This service owns what happens the instant they step
	into room 1 with the door open behind them:

	    the leaf slams and holds for SEAL_SECONDS
	    a notice fades up, says what is coming, and fades out
	    the player goes Complete, and the place turns

	Every clock here is the server's. The card is fired at the client to be
	drawn, not to be timed: this script waits CARD_TOTAL itself and then flips
	the attribute, so a player whose GUI failed to build, who reset mid-notice,
	or who is running a modified client still ends up in the same state as
	everybody else. Nothing the client sends back is trusted, because nothing is
	asked of it.

	The stage attribute is what actually turns the game on. Setting it to
	Complete is simultaneously: the horror grade (HorrorVisibilityZones), the
	fixtures beginning to fail (LightFlicker), the ambience coming up
	(AmbientMusic), and Joel being allowed to see this player at all
	(JoelService). None of those four know about this file — they all read the
	one attribute — which is why the beat can be retimed here without touching
	any of them.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local HorrorZones = require(ReplicatedStorage:WaitForChild("HorrorZones"))
local OnboardingConfig = require(ReplicatedStorage:WaitForChild("OnboardingConfig"))

-- Fast enough that the slam lands while the player is still in the doorway
-- rather than halfway across the room, cheap enough to run forever: it is a
-- box test per player, and only for players still in the intro.
local POLL = 0.15

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

local remotes = ensure(ReplicatedStorage, OnboardingConfig.REMOTE_FOLDER, "Folder")
local cardEvent = ensure(remotes, OnboardingConfig.CARD_EVENT, "RemoteEvent") :: RemoteEvent

--[[
	Room 1's door, preferring the tag over the path.

	The tag is what HotelDoorService itself keys off, so finding the door the
	same way means this service and that one can never end up holding different
	models — sealing a door nothing is driving would set an attribute and slam
	nothing at all.
]]
local function roomDoor(): Model?
	for _, tagged in CollectionService:GetTagged("HotelDoor") do
		if
			tagged:IsA("Model")
			and tagged.Name == OnboardingConfig.ROOM_DOOR_NAME
			and tagged:IsDescendantOf(Workspace)
		then
			return tagged
		end
	end
	local wing = Workspace:FindFirstChild("HotelWing")
	local doors = wing and wing:FindFirstChild("Doors")
	local door = doors and doors:FindFirstChild(OnboardingConfig.ROOM_DOOR_NAME)
	return if door and door:IsA("Model") then door else nil
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function stageOf(player: Player): any
	return player:GetAttribute(OnboardingConfig.ATTRIBUTE)
end

-- Who is standing in room 1 right now and has not been through this yet.
-- Players who finished the intro in an earlier life are not swept up by
-- somebody else's beat: they get no card and no second Complete.
local function newcomersInRoom(stage: string): { Player }
	local found: { Player } = {}
	for _, player in Players:GetPlayers() do
		if stageOf(player) ~= stage then
			continue
		end
		local root = rootOf(player)
		if root and HorrorZones.isInRoomOne(root.Position) then
			table.insert(found, player)
		end
	end
	return found
end

local running = false

local function runSequence(door: Model?, first: { Player })
	--[[
		Sealed is a stage of its own rather than a flag beside the old one.

		It has to be: the objective card reads the same attribute, and leaving
		these players on EnterRoom would keep "Enter your room" and a guide arrow
		on screen while they stand in the room with the door shut behind them.
		An unrecognised stage draws nothing, which is what this beat wants.
	]]
	local group: { [Player]: true } = {}
	local function admit(player: Player)
		if group[player] then
			return
		end
		group[player] = true
		player:SetAttribute(OnboardingConfig.ATTRIBUTE, OnboardingConfig.SEALED)
	end

	for _, player in first do
		admit(player)
	end

	if door then
		door:SetAttribute(OnboardingConfig.SEAL_ATTRIBUTE, true)
		print(`[IntroSeal] room 1 sealed for {OnboardingConfig.SEAL_SECONDS}s`)
	end

	--[[
		Kept polling while the door is shut, for the straggler.

		A second player a step behind the first is inside the room when the leaf
		comes across — they crossed the threshold during the slam, or they were
		already in and only just spawned. They are shut in either way, so they
		are owed the notice and the stage change. The door is closed, so nobody
		new can arrive after this.
	]]
	local heldUntil = os.clock() + OnboardingConfig.SEAL_SECONDS
	while os.clock() < heldUntil do
		task.wait(POLL)
		for _, player in newcomersInRoom(OnboardingConfig.ENTER_ROOM) do
			admit(player)
		end
	end

	if door then
		door:SetAttribute(OnboardingConfig.SEAL_ATTRIBUTE, false)
	end

	for player in group do
		if player.Parent then
			cardEvent:FireClient(player)
		end
	end

	task.wait(OnboardingConfig.CARD_TOTAL)

	--[[
		The stage is only advanced from Sealed.

		A player who left and rejoined during the beat is a new arrival back at
		TalkToNoel, and writing Complete over that would strand them with no
		objective and no way to earn one. Anything that moved them off Sealed
		while this ran outranks the beat that started before it.
	]]
	for player in group do
		if player.Parent and stageOf(player) == OnboardingConfig.SEALED then
			player:SetAttribute(OnboardingConfig.ATTRIBUTE, OnboardingConfig.COMPLETE)
		end
	end
	print("[IntroSeal] notice finished; the hotel is live")
end

--[[
	The intro cannot be a place to hide.

	Joel does not hunt a player who is still in it, which is right — the notice
	promising he is prowling should not arrive after he has already caught you —
	and which, left alone, is an immunity anybody can keep by simply never
	walking into their room. It is also the only way this beat can strand
	somebody: the stage used to advance when the keypad accepted the code, and it
	now advances when the room is entered, so a player who opens the door and
	wanders off is otherwise on the calm grade, unhunted, for the rest of the
	round.

	Both are the same bug and this is the one answer to it. Long enough that
	nobody doing the tutorial at a reasonable pace ever meets it, short enough
	that it is not worth exploiting.
]]
local INTRO_GRACE = 300

local introSince: { [Player]: number } = {}

Players.PlayerRemoving:Connect(function(player: Player)
	introSince[player] = nil
end)

-- Players who have been in the intro too long are handed the hotel as it is,
-- without the beat. They keep their objective card, so a player who was simply
-- slow can still finish the tutorial; what they lose is the exemption.
local function expireStragglers()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local stage = stageOf(player)
		if not OnboardingConfig.isIntroStage(stage) or stage == OnboardingConfig.SEALED then
			introSince[player] = nil
			continue
		end
		local since = introSince[player]
		if not since then
			introSince[player] = now
			continue
		end
		if now - since >= INTRO_GRACE then
			introSince[player] = nil
			player:SetAttribute(OnboardingConfig.ATTRIBUTE, OnboardingConfig.COMPLETE)
			warn(
				`[IntroSeal] {player.Name} spent {INTRO_GRACE}s in the intro without reaching room 1; the hotel is live for them anyway`
			)
		end
	end
end

task.spawn(function()
	--[[
		The zone is wanted, not required.

		HorrorZones falls back to the door's own bay when Room1Zone is missing.
		That fallback is loose — it claims space beyond the room's east wall and
		misses the southern half of the floor — but it is loose in a direction
		that cannot misfire here: it only answers yes past the plane of the door,
		which is to say inside, and the doorway itself is in the half it does
		cover. Refusing to run without the zone would be the worse failure by far,
		because the stage that turns the whole game on is the one this service
		advances: no beat would mean no horror grade and no Joel, for everybody,
		for the rest of the round.
	]]
	if not HorrorZones.roomOneZoneExists() then
		task.wait(10)
		if not HorrorZones.roomOneZoneExists() then
			warn("[IntroSeal] no Room1Zone part in the place; falling back to the door's approximate bay")
		end
	end

	while true do
		task.wait(POLL)
		if running then
			continue
		end
		expireStragglers()

		local waiting = newcomersInRoom(OnboardingConfig.ENTER_ROOM)
		if #waiting == 0 then
			continue
		end

		local door = roomDoor()
		if not door then
			-- No door means no slam, and the notice runs anyway. The alternative
			-- is refusing to advance anybody, which leaves the game switched off.
			warn(`[IntroSeal] {OnboardingConfig.ROOM_DOOR_NAME} is not in the place; the notice runs without the seal`)
		end

		--[[
			Wrapped, because of the two things this coroutine is holding.

			An error thrown anywhere in the sequence would otherwise take the loop
			down with it and the beat would never run again for anybody — and,
			worse, it would leave the door sealed, which is a room nobody can get
			out of for the rest of the round. Both are undone here whatever
			happened.
		]]
		running = true
		local ok, err = pcall(function(): any?
			runSequence(door, waiting)
			return nil
		end)
		running = false
		if not ok then
			if door then
				door:SetAttribute(OnboardingConfig.SEAL_ATTRIBUTE, false)
			end
			warn(`[IntroSeal] the sealed-room beat failed and the door was released: {err}`)
		end
	end
end)
