--!strict
-- Noel's front-desk check-in dialogue.
--
-- The server owns the room assignment and the words Noel says; CheckInClient
-- only renders what it is handed. Room and code are constants for now, so they
-- have to stay in sync with the matching HotelDoor model's Code attribute
-- (Workspace.HotelWing.Doors.Room1Door is "0000" today). When real per-guest
-- allocation arrives, replace roomFor() and nothing on the client changes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ClueConfig = require(ReplicatedStorage:WaitForChild("ClueConfig"))
local OnboardingConfig = require(ReplicatedStorage:WaitForChild("OnboardingConfig"))

local ROOM_NUMBER = "1"
local ROOM_CODE = "0000"

local PROMPT_NAME = "TalkPrompt"
local TALK_COOLDOWN = 0.5
local DIALOGUE_SESSION_LENGTH = 120
local COMPLETION_DISTANCE = 24

local remotesFolder = ReplicatedStorage:FindFirstChild("ReceptionRemotes")
if not remotesFolder then
	local folder = Instance.new("Folder")
	folder.Name = "ReceptionRemotes"
	folder.Parent = ReplicatedStorage
	remotesFolder = folder
end

local existingEvent = remotesFolder:FindFirstChild("CheckInEvent")
if not existingEvent then
	local event = Instance.new("RemoteEvent")
	event.Name = "CheckInEvent"
	event.Parent = remotesFolder
	existingEvent = event
end
local checkInEvent = existingEvent :: RemoteEvent

-- Display names are moderated, but this text is handed to a RichText label, so
-- neutralise the markup characters rather than trusting that.
local function escapeRichText(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function roomFor(_player: Player): (string, string)
	return ROOM_NUMBER, ROOM_CODE
end

local function linesFor(player: Player, room: string, code: string): { string }
	local lines = {
		`Good evening, {escapeRichText(player.DisplayName)}. Welcome to the hotel.`,
		`I have you down for <b>Room {room}</b> — just along the wing, past the lift.`,
		`The keypad code is <b>{code}</b>. Tap it in on the door panel, then press E to confirm.`,
		"Enjoy your stay. I'll be right here at the desk if you need anything.",
		"And don't be a stranger — you'll likely see me about the halls.",
	}

	local clueState = Workspace:FindFirstChild(ClueConfig.StateFolder)
	local firstRiddle = clueState and clueState:GetAttribute(ClueConfig.CurrentRiddleAttribute)
	if typeof(firstRiddle) == "string" and firstRiddle ~= "" then
		table.insert(lines, "Oh — and the last guest left a note at my desk. Do read it. They didn't.")
		table.insert(lines, `<i>{escapeRichText(firstRiddle)}</i>`)
	else
		table.insert(lines, "Oh — and if you find one of the notes, do read it. The last guest didn't.")
	end
	return lines
end

local receptionist = workspace:WaitForChild("Noel", 30)
if not receptionist or not receptionist:IsA("Model") then
	warn("[CheckIn] Noel's model was not found; the talk prompt was not created.")
	return
end

-- The head reads as the place a speech bubble comes from, and it keeps this
-- prompt off whatever part ReceptionistService picked for the party prompt.
local anchor = receptionist:FindFirstChild("Head") or receptionist.PrimaryPart
if not (anchor and anchor:IsA("BasePart")) then
	for _, descendant in receptionist:GetDescendants() do
		if descendant:IsA("BasePart") then
			anchor = descendant
			break
		end
	end
end

if not (anchor and anchor:IsA("BasePart")) then
	warn("[CheckIn] Noel has no BasePart to hang the talk prompt on.")
	return
end

local oldPrompt = anchor:FindFirstChild(PROMPT_NAME)
if oldPrompt then
	oldPrompt:Destroy()
end

local prompt = Instance.new("ProximityPrompt")
prompt.Name = PROMPT_NAME
prompt.ActionText = "Talk"
prompt.ObjectText = "Noel"
prompt.KeyboardKeyCode = Enum.KeyCode.E
prompt.HoldDuration = 0
prompt.MaxActivationDistance = 12
prompt.RequiresLineOfSight = false
prompt.UIOffset = Vector2.new(0, -14)
prompt.Parent = anchor

local lastTalk: { [Player]: number } = {}
local dialogueIssuedAt: { [Player]: number } = {}

local function initialisePlayer(player: Player)
	if player:GetAttribute(OnboardingConfig.ATTRIBUTE) == nil then
		player:SetAttribute(OnboardingConfig.ATTRIBUTE, OnboardingConfig.TALK_TO_NOEL)
	end
end

Players.PlayerAdded:Connect(initialisePlayer)
for _, player in ipairs(Players:GetPlayers()) do
	initialisePlayer(player)
end

prompt.Triggered:Connect(function(player: Player)
	local now = os.clock()
	if now - (lastTalk[player] or 0) < TALK_COOLDOWN then
		return
	end
	lastTalk[player] = now
	dialogueIssuedAt[player] = now

	local room, code = roomFor(player)
	checkInEvent:FireClient(player, {
		prompt = prompt,
		adornee = anchor,
		room = room,
		code = code,
		lines = linesFor(player, room, code),
	})
end)

checkInEvent.OnServerEvent:Connect(function(player: Player, action: any)
	if action ~= "DialogueComplete" then
		return
	end
	if player:GetAttribute(OnboardingConfig.ATTRIBUTE) ~= OnboardingConfig.TALK_TO_NOEL then
		return
	end

	local issuedAt = dialogueIssuedAt[player]
	if not issuedAt or os.clock() - issuedAt > DIALOGUE_SESSION_LENGTH then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) or (root.Position - anchor.Position).Magnitude > COMPLETION_DISTANCE then
		return
	end

	dialogueIssuedAt[player] = nil
	player:SetAttribute(OnboardingConfig.ATTRIBUTE, OnboardingConfig.ENTER_ELEVATOR)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	lastTalk[player] = nil
	dialogueIssuedAt[player] = nil
end)

print("[CheckIn] Noel's talk prompt is ready.")
