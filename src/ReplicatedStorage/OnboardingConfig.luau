--!strict
-- Shared names for the first-stay tutorial. Progress lives on the Player as an
-- attribute so the server remains authoritative while every client can render
-- its own arrows and highlights without creating anything in the world.

local Config = {
	ATTRIBUTE = "OnboardingStage",

	TALK_TO_NOEL = "TalkToNoel",
	ENTER_ELEVATOR = "EnterElevator",
	ENTER_ROOM = "EnterRoom",
	COMPLETE = "Complete",

	LOBBY_CAB_ID = "Lobby",
	ROOMS_CAB_ID = "Rooms",
	ROOM_DOOR_NAME = "Room1Door",
}

return table.freeze(Config)
