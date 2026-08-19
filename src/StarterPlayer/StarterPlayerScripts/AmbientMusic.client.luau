--!strict
-- Persistent, non-positional hotel ambience. StarterPlayerScripts survives
-- character respawns, so the music is not restarted every time a player dies.
--
-- It does not, however, run at the same level throughout. The track is called
-- "Horrors in a dark backroom" and it does exactly what it says, which is wrong
-- over a check-in desk: the first stay is deliberately an ordinary hotel — see
-- HorrorGradeProfiles.Calm — and dread scored under it gives away the turn
-- before the notice does. So it plays low enough during the intro to read as a
-- lobby somewhere having music on, and comes up to full when the player's
-- OnboardingStage goes Complete, alongside the lights dropping.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local OnboardingConfig = require(ReplicatedStorage:WaitForChild("OnboardingConfig"))

local player = Players.LocalPlayer

local SOUND_NAME = "HotelAmbientMusic"
local SOUND_ID = "rbxassetid://133461633339935" -- Horrors in a dark backroom
local TARGET_VOLUME = 0.32
-- Present but not readable as menace. Below this it is simply inaudible, which
-- would make the intro silent rather than ordinary.
local INTRO_VOLUME = 0.07
local FADE_IN_SECONDS = 4
-- Matches the grade's own exit tween in HorrorVisibilityZones, so the hotel
-- goes dark and gets loud as one movement rather than two.
local TURN_SECONDS = 4

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

local function wantedVolume(): number
	local stage = player:GetAttribute(OnboardingConfig.ATTRIBUTE)
	return if OnboardingConfig.isIntroStage(stage) then INTRO_VOLUME else TARGET_VOLUME
end

local currentTween: Tween? = nil

local function fadeTo(volume: number, seconds: number)
	if currentTween then
		currentTween:Cancel()
	end
	local tween = TweenService:Create(
		ambience,
		TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ Volume = volume }
	)
	currentTween = tween
	tween:Play()
end

-- Wait for Roblox to authorize and buffer the asset before fading it in. This
-- prevents the fade from finishing silently on a slow first load.
task.spawn(function()
	if not ambience.IsLoaded then
		ambience.Loaded:Wait()
	end
	if not ambience:IsDescendantOf(game) then
		return
	end

	fadeTo(wantedVolume(), FADE_IN_SECONDS)
end)

player:GetAttributeChangedSignal(OnboardingConfig.ATTRIBUTE):Connect(function()
	-- Only once the track is actually up: firing this mid-load would cancel the
	-- fade above and leave the ambience sitting at whatever it had reached.
	if ambience.IsLoaded then
		fadeTo(wantedVolume(), TURN_SECONDS)
	end
end)
