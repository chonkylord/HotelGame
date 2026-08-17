--!strict
--[[
	Puts the Rthro animation set on every character as it spawns.

	Roblox inserts its default `Animate` LocalScript into each character, and
	that script reads its clips from container objects parented to itself —
	`Animate.walk.WalkAnim` and friends. Swapping those is the supported way to
	change how a character moves, and it is the only way that reaches other
	players: the Animator replicates whatever the owning client plays, so the
	clips have to be chosen before that client picks them up, not corrected
	afterwards. Posing joints directly would never leave the machine that did it
	(and could not work here anyway — this place's player rigs join with
	AnimationConstraints rather than Motor6Ds, so their C0s are read-only; see
	FlashlightAim for where that was found the hard way).

	This runs on the server so every character gets the same set regardless of
	who is looking, and so a client cannot decline it.

	The clips are *replaced* rather than retargeted. Assigning a new AnimationId
	to the existing Animation object does reach the Animate script — it watches
	each one's Changed — but its switchToAnim only reloads a track when the
	Animation *instance* differs from the one already playing, so an in-place
	edit can leave the old clip running until the pose next changes. Swapping the
	instance sidesteps that entirely.

	Everything not named in LocomotionConfig.Animations is left alone, so tool
	holds, sitting and the emotes stay stock.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("LocomotionConfig"))

-- The Animate script names its clips per pose. Nothing reads these names — it
-- iterates every Animation child of the container — but matching the stock
-- names keeps the Explorer legible for anyone debugging a character.
local CLIP_NAMES: { [string]: string } = {
	idle = "Animation1",
	walk = "WalkAnim",
	run = "RunAnim",
	jump = "JumpAnim",
	fall = "FallAnim",
	climb = "ClimbAnim",
	swim = "Swim",
}

-- Long enough to cover a slow spawn, short enough that a character which is
-- never going to have an Animate script does not leak a waiting thread.
local ANIMATE_TIMEOUT = 10

local warnedMissing = false

--[[
	The container the Animate script looks for is a StringValue named after the
	pose, holding that pose's Animation children. If a pose has no container the
	script falls back to its own defaults, so creating one is what opts that
	pose in — and `Animate.ChildAdded` makes it reconfigure when we do.
]]
local function containerFor(animate: Instance, pose: string): Instance
	local existing = animate:FindFirstChild(pose)
	if existing then
		return existing
	end
	local created = Instance.new("StringValue")
	created.Name = pose
	created.Value = pose
	created.Parent = animate
	return created
end

local function installPose(animate: Instance, pose: string, animationId: string)
	local container = containerFor(animate, pose)

	-- Clearing first matters for idle, which ships two weighted variants: leave
	-- them in place and the character keeps rolling the stock clip half the time.
	for _, child in container:GetChildren() do
		if child:IsA("Animation") then
			child:Destroy()
		end
	end

	local animation = Instance.new("Animation")
	animation.Name = CLIP_NAMES[pose] or pose
	animation.AnimationId = animationId
	animation.Parent = container
end

local function applyTo(character: Model)
	local animate = character:WaitForChild("Animate", ANIMATE_TIMEOUT)
	if not animate then
		if not warnedMissing then
			warnedMissing = true
			warn(
				"[LocomotionAnimService] no Animate script on "
					.. character.Name
					.. "; characters will keep Roblox's default animation set"
			)
		end
		return
	end

	for pose, animationId in Config.Animations do
		installPose(animate, pose, animationId)
	end
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		applyTo(character)
	end)
	-- A character that already exists when we connect (Studio play solo can
	-- spawn one before this script runs) would otherwise never be touched.
	local existing = player.Character
	if existing then
		task.spawn(applyTo, existing)
	end
end

for _, player in Players:GetPlayers() do
	onPlayer(player)
end
Players.PlayerAdded:Connect(onPlayer)
