--!strict
-- Positional threat audio for Joel. JoelService publishes IsHunting;
-- this service turns that state into a 3D chase theme and respawn-safe kill sound.
-- Adds a proximity-based ambient "dread" sound that grows louder as Joel approaches.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CHASE_SOUND_ID = "rbxassetid://1839924741" -- Running Chase A, APM Music
local CHASE_SOUND_VOLUME = 0.82
local CHASE_SOUND_MIN_DISTANCE = 9
local CHASE_SOUND_MAX_DISTANCE = 115
local CHASE_SOUND_FADE_SECONDS = 1.15

local ATTACK_SCREAM_SOUND_ID = "rbxassetid://9043346124" -- HORROR SCREAM 11
local ATTACK_SCREAM_VOLUME = 1.35
local ATTACK_SCREAM_MIN_DISTANCE = 14
local ATTACK_SCREAM_MAX_DISTANCE = 135
local ATTACK_SCREAM_COOLDOWN = 0.35
local ATTACK_DETECTION_RADIUS = 4.5

--[[
	Proximity ambient (dread) sound: plays constantly, volume scales with distance.

	Was rbxassetid://1841641983, which is not an audio asset any more — Studio
	logged "Asset type does not match requested type" on every join and the sound
	silently never played. Since this drone is the only continuous cue for how
	close Joel is (the chase theme starts only once he is actually hunting), the
	game had no ambient warning at all: he arrived in silence.

	Replaced with APM's Moving Drone 29, verified loading at 124.81s. Two reasons
	for this one over the several horror-ambience tracks that also load:

	  * It is a drone — sustained and featureless. This sound's *volume* is the
	    information, so anything with melody or stings would both fight the chase
	    theme layered over it and make distance harder to read by ear.
	  * APM is the same licensed library as CHASE_SOUND_ID above (1839924741),
	    so the two are mastered alike and sit together. The dead id sat between
	    them numerically, so APM is almost certainly where the original came from.

	If you swap this, keep it long, loopable and eventless, and check
	Sound.IsLoaded is true rather than trusting the id.
]]
local DREAD_SOUND_ID = "rbxassetid://1843995698" -- Moving Drone 29, APM Music
local DREAD_MAX_VOLUME = 0.65
local DREAD_MIN_DISTANCE = 8     -- Volume starts fading in at this distance
local DREAD_MAX_DISTANCE = 140   -- Fully faded out at this distance
local DREAD_ROLLOFF_MIN = 10
local DREAD_ROLLOFF_MAX = 160

local function findJoel(): Model?
	for _, tagged in ipairs(CollectionService:GetTagged("JoelHunter")) do
		if tagged:IsA("Model") and tagged:IsDescendantOf(Workspace) then
			return tagged
		end
	end
	local direct = Workspace:FindFirstChild("Joel")
	return if direct and direct:IsA("Model") then direct else nil
end

local joel = findJoel()
if not joel then
	warn("[JoelAudio] no model tagged JoelHunter")
	return
end

local rootInstance = joel:FindFirstChild("HumanoidRootPart")
if not rootInstance or not rootInstance:IsA("BasePart") then
	warn("[JoelAudio] Joel needs a HumanoidRootPart")
	return
end
local joelRoot: BasePart = rootInstance

local function createPositionalSound(
	name: string,
	soundId: string,
	volume: number,
	minDistance: number,
	maxDistance: number,
	looped: boolean
): Sound
	local existing = joelRoot:FindFirstChild(name)
	local sound: Sound
	if existing and existing:IsA("Sound") then
		sound = existing
	else
		sound = Instance.new("Sound")
		sound.Name = name
		sound.Parent = joelRoot
	end

	sound.SoundId = soundId
	sound.Volume = volume
	sound.Looped = looped
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = minDistance
	sound.RollOffMaxDistance = maxDistance
	return sound
end

local chaseSound =
	createPositionalSound("ChaseTheme", CHASE_SOUND_ID, 0, CHASE_SOUND_MIN_DISTANCE, CHASE_SOUND_MAX_DISTANCE, true)
local attackScream = createPositionalSound(
	"AttackScream",
	ATTACK_SCREAM_SOUND_ID,
	ATTACK_SCREAM_VOLUME,
	ATTACK_SCREAM_MIN_DISTANCE,
	ATTACK_SCREAM_MAX_DISTANCE,
	false
)

-- Dread ambient sound: always playing, volume controlled by proximity
local dreadSound = createPositionalSound(
	"DreadAmbience",
	DREAD_SOUND_ID,
	0, -- Start at 0, we'll control via script
	DREAD_ROLLOFF_MIN,
	DREAD_ROLLOFF_MAX,
	true
)
dreadSound:Play()

-- Proximity-based volume update for dread sound
local function updateDreadVolume()
	local closestDistance = math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character then
			local root = character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				local dist = (root.Position - joelRoot.Position).Magnitude
				if dist < closestDistance then
					closestDistance = dist
				end
			end
		end
	end

	if closestDistance == math.huge then
		dreadSound.Volume = 0
		return
	end

	-- Inverse linear falloff: max volume at DREAD_MIN_DISTANCE, zero at DREAD_MAX_DISTANCE
	if closestDistance <= DREAD_MIN_DISTANCE then
		dreadSound.Volume = DREAD_MAX_VOLUME
	elseif closestDistance >= DREAD_MAX_DISTANCE then
		dreadSound.Volume = 0
	else
		local t = (closestDistance - DREAD_MIN_DISTANCE) / (DREAD_MAX_DISTANCE - DREAD_MIN_DISTANCE)
		dreadSound.Volume = DREAD_MAX_VOLUME * (1 - t)
	end
end

RunService.Heartbeat:Connect(updateDreadVolume)

local chaseSoundActive = false
local chaseRevision = 0
local chaseTween: Tween? = nil
local lastScreamAt = -math.huge

local function setChaseSoundActive(active: boolean)
	if chaseSoundActive == active then
		return
	end

	chaseSoundActive = active
	chaseRevision += 1
	local revision = chaseRevision
	if chaseTween then
		chaseTween:Cancel()
	end
	if active and not chaseSound.Playing then
		chaseSound.Volume = 0
		chaseSound:Play()
	end

	local tween = TweenService:Create(
		chaseSound,
		TweenInfo.new(CHASE_SOUND_FADE_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ Volume = if active then CHASE_SOUND_VOLUME else 0 }
	)
	chaseTween = tween
	tween:Play()

	if not active then
		task.delay(CHASE_SOUND_FADE_SECONDS, function()
			if revision == chaseRevision and not chaseSoundActive then
				chaseSound:Stop()
				chaseSound.TimePosition = 0
			end
		end)
	end
end

local function playAttackScream()
	local now = os.clock()
	if now - lastScreamAt < ATTACK_SCREAM_COOLDOWN then
		return
	end
	lastScreamAt = now

	attackScream.PlaybackSpeed = 0.92 + math.random() * 0.16
	attackScream:Stop()
	attackScream.TimePosition = 0
	attackScream:Play()
end

joel:GetAttributeChangedSignal("IsHunting"):Connect(function()
	setChaseSoundActive(joel:GetAttribute("IsHunting") == true)
end)
setChaseSoundActive(joel:GetAttribute("IsHunting") == true)

local deathConnections: { [Player]: RBXScriptConnection } = {}
local characterGenerations: { [Player]: number } = {}

local function bindCharacter(player: Player, character: Model)
	characterGenerations[player] = (characterGenerations[player] or 0) + 1
	local generation = characterGenerations[player]
	local oldConnection = deathConnections[player]
	if oldConnection then
		oldConnection:Disconnect()
		deathConnections[player] = nil
	end

	task.spawn(function()
		local humanoid = character:WaitForChild("Humanoid", 10)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if characterGenerations[player] ~= generation or player.Character ~= character then
			return
		end
		if not humanoid or not humanoid:IsA("Humanoid") or not root or not root:IsA("BasePart") then
			return
		end

		deathConnections[player] = humanoid.Died:Connect(function()
			if
				root:IsDescendantOf(Workspace)
				and (root.Position - joelRoot.Position).Magnitude <= ATTACK_DETECTION_RADIUS
			then
				playAttackScream()
			end
		end)
	end)
end

local function connectPlayer(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		bindCharacter(player, character)
	end)
	if player.Character then
		bindCharacter(player, player.Character)
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	connectPlayer(player)
end
Players.PlayerAdded:Connect(connectPlayer)
Players.PlayerRemoving:Connect(function(player: Player)
	characterGenerations[player] = (characterGenerations[player] or 0) + 1
	local connection = deathConnections[player]
	if connection then
		connection:Disconnect()
		deathConnections[player] = nil
	end
end)
