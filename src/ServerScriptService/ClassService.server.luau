--!strict
--[[
	Class selection, and the body that comes with it.

	Server-authoritative: the class lives as an attribute on the Player object,
	which only the server can write. Everything that grants a power — forcing a
	door, for now — reads it there rather than trusting anything the client says
	about itself.

	Picking is physical. Stepping on a floor Pad under Workspace.ClassPodiums claims
	that class. A player can claim only once, and each class can belong to only
	one player at a time. Claims last until the player leaves the server.

	The Muscle build resizes the player rather than re-skinning them; see
	ClassConfig for the three separate things that broke when this was done with
	a catalog body bundle instead. Nothing here touches HumanoidDescription, so
	the player keeps their own parts, clothes, face and accessories throughout —
	which also means there is no web call in the spawn path to fail.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Teams = game:GetService("Teams")

local ClassConfig = require(ReplicatedStorage:WaitForChild("ClassDefinitions"))
local ClassClaimRegistry = require(ServerStorage:WaitForChild("ClassClaimRegistry"))
local HackerGear = require(ServerStorage:WaitForChild("HackerGear"))
local SupermanGear = require(ServerStorage:WaitForChild("SupermanGear"))

--[[
	R15 exposes its proportions as NumberValues parented to the Humanoid.
	Writing them directly is what resizes the character, and unlike the matching
	HumanoidDescription fields they are not clamped to the place's avatar scale
	range — so a build wider than the Game Settings slider allows still works.
]]
local SCALE_VALUES = { "BodyWidthScale", "BodyDepthScale", "BodyHeightScale", "HeadScale" }

--[[
	The proportions the player arrived with, captured fresh on each character
	spawn. The class multiplies these rather than replacing them, and undoing a
	class means restoring them — reverting to a flat 1.0 would quietly resize
	anyone whose own avatar is not stock.
]]
local baseScale: { [Player]: { [string]: number } } = {}

local claims = ClassClaimRegistry.new(ClassConfig.NONE)

local teamNameForClass: { [string]: string } = {
	[ClassConfig.NONE] = "None",
	[ClassConfig.HACKER] = "Hacker",
	[ClassConfig.MUSCLE] = "Muscle",
	[ClassConfig.SUPERMAN] = "SuperHero",
}

local function setTeam(player: Player, class: string)
	local teamName = teamNameForClass[class]
	local team = if teamName then Teams:FindFirstChild(teamName) else nil
	if team and team:IsA("Team") then
		player.Team = team
	else
		player.Neutral = true
		warn(`[ClassService] no Team exists for class {class}`)
	end
end

local function scaleValue(humanoid: Humanoid, name: string): NumberValue?
	local value = humanoid:FindFirstChild(name)
	return if value and value:IsA("NumberValue") then value else nil
end

local function applyBuild(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	--[[
		Kit goes on first, and deliberately above the R15 gate below.

		Accessories weld by attachment name, and R6 heads and torsos carry
		FaceFrontAttachment and BodyBackAttachment just as R15 ones do. There is
		no reason a player who somehow spawned on the wrong rig should lose the
		visor as well as the build — the visor is the half that still works.

		Each kit is evaluated independently because AdminAllClasses grants both
		entitlements at once. Disabling it re-evaluates the unchanged podium class
		and strips only the kits that class does not own.
	]]
	if ClassConfig.hasClass(player, ClassConfig.HACKER) then
		HackerGear.apply(character)
	else
		HackerGear.clear(character)
	end
	if ClassConfig.hasClass(player, ClassConfig.SUPERMAN) then
		SupermanGear.apply(character)
	else
		SupermanGear.clear(character)
	end

	-- Proportion scaling is an R15 idea; R6 has no such NumberValues to write.
	if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		warn(`[ClassService] {player.Name} is on {humanoid.RigType.Name}; the class build needs R15`)
		return
	end

	local base = baseScale[player]
	if not base then
		return
	end

	local isMuscle = ClassConfig.hasClass(player, ClassConfig.MUSCLE)
	for _, name in ipairs(SCALE_VALUES) do
		local value = scaleValue(humanoid, name)
		if value then
			local multiplier = if isMuscle then (ClassConfig.MuscleScale[name] or 1) else 1
			value.Value = base[name] * multiplier
		end
	end
end

local function onCharacterAdded(player: Player, character: Model)
	-- Never let an attribute toggle apply the previous character's captured
	-- proportions to a newly spawning rig.
	baseScale[player] = nil
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end

	-- The scale values are built alongside the character, so they can lag the
	-- Humanoid itself by a frame. Capturing before they exist would record 1.0
	-- for everyone and lose whatever the player actually looks like.
	humanoid:WaitForChild("BodyWidthScale", 5)

	local captured = {}
	for _, name in ipairs(SCALE_VALUES) do
		local value = scaleValue(humanoid, name)
		captured[name] = if value then value.Value else 1
	end
	baseScale[player] = captured

	applyBuild(player, character)
end

local function onPlayerAdded(player: Player)
	if not ClassClaimRegistry.register(claims, player) then
		return
	end

	-- Every player starts unclaimed. Only touching a free podium can change this.
	player:SetAttribute(ClassConfig.ATTRIBUTE, ClassConfig.NONE)
	setTeam(player, ClassConfig.NONE)

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	player:GetAttributeChangedSignal(ClassConfig.ADMIN_ALL_CLASSES_ATTRIBUTE):Connect(function()
		local character = player.Character
		if character then
			applyBuild(player, character)
		end
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

local function choose(player: Player, class: string)
	-- This one non-yielding operation enforces both locks: the player must still
	-- be unclaimed and the class must still be unowned.
	if not ClassClaimRegistry.claim(claims, player, class) then
		return
	end

	player:SetAttribute(ClassConfig.ATTRIBUTE, class)
	setTeam(player, class)

	local character = player.Character
	if character then
		applyBuild(player, character)
	end
end

local function playerFromTouch(hit: BasePart): Player?
	local character = hit:FindFirstAncestorOfClass("Model")
	return if character then Players:GetPlayerFromCharacter(character) else nil
end

local function wirePodium(folder: Instance)
	local class = ClassConfig.PodiumClass[folder.Name]
	if not class then
		return
	end

	local pad = folder:FindFirstChild("Pad")
	if not pad or not pad:IsA("BasePart") then
		warn(`[ClassService] podium {folder.Name} has no floor Pad to touch`)
		return
	end

	-- Class selection is touch-only. Clean up a prompt left by an older copy of
	-- this service, then ensure the floor pad emits touch events.
	for _, descendant in folder:GetDescendants() do
		if descendant:IsA("ProximityPrompt") and descendant.Name == "ChooseClass" then
			descendant:Destroy()
		end
	end
	pad.CanTouch = true

	pad.Touched:Connect(function(hit)
		local player = playerFromTouch(hit)
		if player then
			choose(player, class)
		end
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

Players.PlayerRemoving:Connect(function(player)
	ClassClaimRegistry.release(claims, player)
	baseScale[player] = nil
end)

-- Initialize player locks before waiting for the podium models. This closes a
-- startup race where an existing player could touch a pad before their class
-- had been reset to None.
local podiums = workspace:WaitForChild("ClassPodiums", 20)
if podiums then
	for _, folder in podiums:GetChildren() do
		wirePodium(folder)
	end
else
	warn("[ClassService] Workspace.ClassPodiums is missing; no class can be chosen")
end
