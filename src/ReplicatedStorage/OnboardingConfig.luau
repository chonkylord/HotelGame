--!strict
-- Shared names for the first-stay tutorial. Progress lives on the Player as an
-- attribute so the server remains authoritative while every client can render
-- its own arrows and highlights without creating anything in the world.
--
-- The stages are also what decides how the hotel LOOKS. Everything up to and
-- including the sealed room runs the Calm grade — Noel's cues are a check-in,
-- not a horror scene, and a player following an arrow through a black corridor
-- cannot see the arrow. `Complete` is the moment the place turns: the lights
-- drop to the horror grade, the fixtures start failing again, and Joel is
-- allowed to hunt. Nothing else in the game gates on this attribute, so the
-- switch happens in exactly one place.

local TALK_TO_NOEL = "TalkToNoel"
local ENTER_ELEVATOR = "EnterElevator"
local ENTER_ROOM = "EnterRoom"
local SEALED = "Sealed"
local COMPLETE = "Complete"

--[[
	Which stages count as "still in the intro".

	Deliberately a list of the intro stages rather than `stage ~= Complete`, so
	an unset attribute reads as NOT in the intro. That is the safe direction for
	every caller: a player the server has not classified yet is huntable and
	sees the normal grade, where the other reading would leave them permanently
	invisible to Joel if CheckInService ever failed to run (it bails out when
	Noel's model is missing, which is exactly when this would bite).
]]
local INTRO_STAGES: { [string]: boolean } = {
	[TALK_TO_NOEL] = true,
	[ENTER_ELEVATOR] = true,
	[ENTER_ROOM] = true,
	[SEALED] = true,
}

local function isIntroStage(stage: any): boolean
	return type(stage) == "string" and INTRO_STAGES[stage] == true
end

--[[
	The one line describing what the player is being asked to do right now, or
	nil once the intro is over and the clue chain takes the question over.

	It lives in the shared config rather than in the client that draws it
	because two surfaces now need exactly these words: the case ledger's
	OBJECTIVE page and the pinned ribbon beside the ledger button. When the
	strings lived in OnboardingClient, giving a second surface the same text
	meant copying them, and a copy is a thing that drifts.
]]
local function objectiveFor(stage: any): string?
	if stage == TALK_TO_NOEL then
		return "Talk to Noel"
	elseif stage == ENTER_ELEVATOR then
		return "Enter the elevator"
	elseif stage == ENTER_ROOM then
		return "Enter your room"
	end
	return nil
end

-- The sealed-room beat: how long the leaf stays shut, and how long the notice
-- that follows it is on screen. The server owns both clocks — it fires the card
-- and it flips the player to Complete CARD_TOTAL seconds later — so the client
-- animates against these numbers rather than reporting back when it is done.
local CARD_FADE_IN = 1.7
local CARD_HOLD = 3.6
local CARD_FADE_OUT = 1.7

local Config = {
	ATTRIBUTE = "OnboardingStage",

	TALK_TO_NOEL = TALK_TO_NOEL,
	ENTER_ELEVATOR = ENTER_ELEVATOR,
	ENTER_ROOM = ENTER_ROOM,
	SEALED = SEALED,
	COMPLETE = COMPLETE,

	isIntroStage = isIntroStage,
	objectiveFor = objectiveFor,

	LOBBY_CAB_ID = "Lobby",
	ROOMS_CAB_ID = "Rooms",
	ROOM_DOOR_NAME = "Room1Door",

	--[[
		Set on a HotelDoor model to slam it and hold it shut.

		HotelDoorService owns what sealing DOES — the fast swing, the slam, the
		panel refusing everybody, the release plate going out of service. This
		attribute is the whole interface, so IntroSealService drives the beat
		without reaching into the door's internals, and any other scripted
		moment that needs a door held shut gets it for free.
	]]
	SEAL_ATTRIBUTE = "Sealed",
	SEAL_SECONDS = 15,

	REMOTE_FOLDER = "ReceptionRemotes",
	CARD_EVENT = "IntroCardEvent",

	CARD_FADE_IN = CARD_FADE_IN,
	CARD_HOLD = CARD_HOLD,
	CARD_FADE_OUT = CARD_FADE_OUT,
	CARD_TOTAL = CARD_FADE_IN + CARD_HOLD + CARD_FADE_OUT,
}

return table.freeze(Config)
