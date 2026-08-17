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
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local HorrorZones = require(ReplicatedStorage:WaitForChild("HorrorZones"))
local Profiles = require(ReplicatedStorage:WaitForChild("HorrorGradeProfiles"))

local player = Players.LocalPlayer

-- Fallback measured around HotelLobbyDetails, Tiles Lobby, and the fountain.
-- Named lobby geometry is also discovered below, so the profile follows the
-- actual architecture if the lobby or its entrance is moved in Studio.
local LOBBY_MIN = Vector3.new(-130, -20, 70)
local LOBBY_MAX = Vector3.new(-20, 60, 330)

local TRANSITION = TweenInfo.new(1.15, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
local grade = Lighting:WaitForChild("HorrorGrade") :: ColorCorrectionEffect

local lightingTween: Tween? = nil
local gradeTween: Tween? = nil
-- Which grade is currently applied, so a zone change tweens once rather than
-- every poll. nil forces the next refresh to apply whatever it finds.
type Zone = "Vault" | "Lobby" | "Dark"
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

--[[
	Three zones now, not two.

	This was a boolean — lobby or dark — which was right while the hotel was the
	whole world. The vault is neither: it is a lit strongroom, and inheriting
	"not the lobby, therefore dark" made the destination of the entire clue hunt
	arrive as a black screen. Naming the zone rather than flipping a second flag
	keeps the next space that needs its own grade cheap to add.

	Vault is still tested first, and now it matters more than it did. It used to
	be a depth check nothing else could satisfy, so the order was free; it is now
	a test against the chamber's own box, and the chamber stands at ground level
	among the rest of the building. Asking it first means the exact volume wins
	over `inLobby`, which is a scan of name-matched geometry padded 14 studs
	outward and is therefore the looser of the two claims.

	Polling this four times a second is fine: HorrorZones caches the chamber's
	box for a few seconds, so this does not walk Workspace per tick.
]]
local function zoneFor(position: Vector3): Zone
	if HorrorZones.isInVault(position) then
		return "Vault"
	end
	if inLobby(position) then
		return "Lobby"
	end
	return "Dark"
end

local function apply(zone: Zone)
	if lightingTween then
		lightingTween:Cancel()
	end
	if gradeTween then
		gradeTween:Cancel()
	end

	local profile = Profiles[zone]
	lightingTween = TweenService:Create(Lighting, TRANSITION, profile.lighting)
	gradeTween = TweenService:Create(grade, TRANSITION, profile.grade)
	;(lightingTween :: Tween):Play()
	;(gradeTween :: Tween):Play()
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
	zoneLast = zone
	print(string.format("[HorrorVisibilityZones] %s profile active", zone))
	apply(zone)
end

player.CharacterAdded:Connect(function()
	zoneLast = nil
	task.defer(refresh)
end)

while true do
	refresh()
	task.wait(0.25)
end
