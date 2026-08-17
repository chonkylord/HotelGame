--!strict
-- Persistent, non-positional hotel ambience. StarterPlayerScripts survives
-- character respawns, so the music is not restarted every time a player dies.

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local SOUND_NAME = "HotelAmbientMusic"
local SOUND_ID = "rbxassetid://133461633339935" -- Horrors in a dark backroom
local TARGET_VOLUME = 0.32
local FADE_IN_SECONDS = 4

local existing = SoundService:FindFirstChild(SOUND_NAME)
local ambience: Sound

if existing and existing:IsA("Sound") then
	ambience = existing
else
	ambience = Instance.new("Sound")
	ambience.Name = SOUND_NAME
	ambience.Parent = SoundService
end

ambience.SoundId = SOUND_ID
ambience.Looped = true
ambience.PlaybackSpeed = 1
ambience.Volume = 0
ambience:Play()

-- Wait for Roblox to authorize and buffer the asset before fading it in. This
-- prevents the fade from finishing silently on a slow first load.
task.spawn(function()
	if not ambience.IsLoaded then
		ambience.Loaded:Wait()
	end
	if not ambience:IsDescendantOf(game) then
		return
	end

	TweenService:Create(
		ambience,
		TweenInfo.new(FADE_IN_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ Volume = TARGET_VOLUME }
	):Play()
end)
