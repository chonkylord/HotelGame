--!strict
--[[
	Area-specific relief from the hotel's global horror grade.

	The lobby is the safe visual anchor: it should still feel like night, but it
	should not require a flashlight just to find the entrance, desk, or elevator.
	Lighting changes made by a LocalScript affect only this player, so entering
	or leaving the lobby can lift the grade without changing what players on
	other floors see.

	Which geometry counts as the lobby is decided by HorrorZones, not here — see
	its notes for why "every instance whose name contains lobby" was quietly
	applying this script's bright profile to two floors it has no business
	touching.

	One zone is not a place at all. While this player is still working through
	the first stay, the Calm profile is applied wherever they are standing and
	the geometry is not consulted — see zoneFor.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local HorrorZones = require(ReplicatedStorage:WaitForChild("HorrorZones"))
local OnboardingConfig = require(ReplicatedStorage:WaitForChild("OnboardingConfig"))
local Profiles = require(ReplicatedStorage:WaitForChild("HorrorGradeProfiles"))

local player = Players.LocalPlayer

-- Fallback measured around HotelLobbyDetails, Tiles Lobby, and the fountain.
-- Named lobby geometry is also discovered below, so the profile follows the
-- actual architecture if the lobby or its entrance is moved in Studio.
local LOBBY_MIN = Vector3.new(-130, -20, 70)
local LOBBY_MAX = Vector3.new(-20, 60, 330)

local TRANSITION = TweenInfo.new(1.15, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
--[[
	The one transition that is not a walk between rooms.

	Leaving Calm is the hotel turning into a horror game, and it happens while
	the player stands still reading a notice that has just faded out. A 1.15s
	crossfade there reads as a lighting bug; four seconds reads as the lights
	going out around them, which is the intended effect and the reason this
	beat exists at all.
]]
local INTRO_EXIT_TRANSITION = TweenInfo.new(4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local grade = Lighting:WaitForChild("HorrorGrade") :: ColorCorrectionEffect

local lightingTween: Tween? = nil
local gradeTween: Tween? = nil
local atmosphereTween: Tween? = nil
-- Which grade is currently applied, so a zone change tweens once rather than
-- every poll. nil forces the next refresh to apply whatever it finds.
type Zone = "Calm" | "Vault" | "Lobby" | "Dark"
local zoneLast: Zone? = nil

type LobbyVolume = {
	min: Vector3,
	max: Vector3,
}

local lobbyVolumes: { LobbyVolume } = {}

local function addVolume(instance: Instance)
	local boundsCFrame: CFrame
	local boundsSize: Vector3
	if instance:IsA("Model") then
		boundsCFrame, boundsSize = instance:GetBoundingBox()
	elseif instance:IsA("BasePart") then
		boundsCFrame, boundsSize = instance.CFrame, instance.Size
	else
		return
	end
	local half = boundsSize / 2 + HorrorZones.LobbyPadding
	table.insert(lobbyVolumes, {
		min = boundsCFrame.Position - half,
		max = boundsCFrame.Position + half,
	})
end

local function scanLobbyGeometry()
	table.clear(lobbyVolumes)
	for _, instance in Workspace:GetDescendants() do
		if HorrorZones.isLobbyGeometry(instance) then
			addVolume(instance)
		end
	end
end

scanLobbyGeometry()
Workspace.DescendantAdded:Connect(function(instance: Instance)
	if HorrorZones.isLobbyGeometry(instance) then
		addVolume(instance)
	end
end)

local function inLobby(position: Vector3): boolean
	local insideFallback = position.X >= LOBBY_MIN.X
		and position.X <= LOBBY_MAX.X
		and position.Y >= LOBBY_MIN.Y
		and position.Y <= LOBBY_MAX.Y
		and position.Z >= LOBBY_MIN.Z
		and position.Z <= LOBBY_MAX.Z
	if insideFallback then
		return true
	end
	for _, volume in lobbyVolumes do
		if
			position.X >= volume.min.X
			and position.X <= volume.max.X
			and position.Y >= volume.min.Y
			and position.Y <= volume.max.Y
			and position.Z >= volume.min.Z
			and position.Z <= volume.max.Z
		then
			return true
		end
	end
	return false
end

local function introActive(): boolean
	return OnboardingConfig.isIntroStage(player:GetAttribute(OnboardingConfig.ATTRIBUTE))
end

--[[
	Four zones now, and only three of them are places.

	This was a boolean — lobby or dark — which was right while the hotel was the
	whole world. The vault is neither: it is a lit strongroom, and inheriting
	"not the lobby, therefore dark" made the destination of the entire clue hunt
	arrive as a black screen. Naming the zone rather than flipping a second flag
	keeps the next space that needs its own grade cheap to add.

	Calm is the one that is not geometry at all, and it is asked first for that
	reason. The first stay runs through the lobby, a lift, a guest corridor and a
	room — three of the zones below, one of them the darkest in the game. Letting
	the building answer during the intro would light Noel's desk brightly and
	then drop the player into a black corridor to find an arrow on the floor,
	which is the exact thing the Calm profile exists to stop. Where they are
	standing does not matter until the intro ends; the next poll hands them
	straight back to the building.

	Vault is tested next, and now it matters more than it did. It used to be a
	depth check nothing else could satisfy, so the order was free; it is now a
	test against the chamber's own box, and the chamber stands at ground level
	among the rest of the building. Asking it before `inLobby` means the exact
	volume wins over a scan of name-matched geometry padded 14 studs outward,
	which is the looser of the two claims.

	Polling this four times a second is fine: HorrorZones caches the chamber's
	box for a few seconds, so this does not walk Workspace per tick.
]]
local function zoneFor(position: Vector3): Zone
	if introActive() then
		return "Calm"
	end
	if HorrorZones.isInVault(position) then
		return "Vault"
	end
	if inLobby(position) then
		return "Lobby"
	end
	return "Dark"
end

--[[
	The haze, which is a separate instance and therefore a separate tween.

	Found rather than created: HorrorLighting reuses whatever Atmosphere the
	place already had and only makes one if there is none, so looking it up each
	time is what keeps this pointing at the same volume the server graded rather
	than at a second one stacked over it.
]]
local function atmosphere(): Atmosphere?
	return Lighting:FindFirstChildOfClass("Atmosphere")
end

local function apply(zone: Zone, from: Zone?)
	if lightingTween then
		lightingTween:Cancel()
	end
	if gradeTween then
		gradeTween:Cancel()
	end
	if atmosphereTween then
		atmosphereTween:Cancel()
	end

	local transition = if from == "Calm" then INTRO_EXIT_TRANSITION else TRANSITION
	local profile = Profiles[zone]
	lightingTween = TweenService:Create(Lighting, transition, profile.lighting)
	gradeTween = TweenService:Create(grade, transition, profile.grade);
	(lightingTween :: Tween):Play();
	(gradeTween :: Tween):Play()

	local haze = atmosphere()
	if haze then
		atmosphereTween = TweenService:Create(haze, transition, profile.atmosphere);
		(atmosphereTween :: Tween):Play()
	end
end

local function refresh()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local zone: Zone = zoneFor(root.Position)
	if zone == zoneLast then
		return
	end
	local previous: Zone? = zoneLast
	zoneLast = zone
	print(string.format("[HorrorVisibilityZones] %s profile active", zone))
	apply(zone, previous)
end

player.CharacterAdded:Connect(function()
	zoneLast = nil
	task.defer(refresh)
end)

-- The intro ending is a state change rather than a movement, so it must not
-- wait for the next quarter-second poll to be noticed: the notice fades out and
-- the lights go with it.
player:GetAttributeChangedSignal(OnboardingConfig.ATTRIBUTE):Connect(refresh)

while true do
	refresh()
	task.wait(0.25)
end
