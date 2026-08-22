--!strict
--[[
	Keeps a claimed relic on the body that claimed it.

	ClueService writes MuscleRelic or HackerRelic onto the Player and considers
	the job done, which is correct -- it owns the round, not the wardrobe. This
	watches those two attributes and makes the character match: the laptop goes
	onto the Hacker's left hand the frame the Cipher is claimed, the gauntlet
	onto the Muscle's, and both go back on after a death because a fresh
	character arrives wearing nothing.

	The attribute is the single source of truth in both directions. Nothing here
	remembers who claimed what; it reads the Player every time it is asked to
	act. That is what makes it safe to re-enter -- a respawn, a late join, a
	Studio re-run mid-round all take the same path -- and it is why clearing the
	attribute by hand in Studio takes the regalia off, which is the behaviour you
	want when you are testing.

	Attaching is server-side and welded, so the piece replicates to everyone:
	other players see the Hacker carrying the laptop, which is the whole reason
	for putting a relic on a body rather than in a HUD.
]]

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local RelicRegalia = require(ServerStorage:WaitForChild("RelicRegalia"))

-- Long enough for a character to finish assembling on a slow join, short enough
-- that a rig which is never going to have the limb gives up rather than parking
-- a thread forever.
local LIMB_TIMEOUT = 10

local connections: { [Player]: { RBXScriptConnection } } = {}

local function characterReady(character: Model): boolean
	if not character:IsDescendantOf(workspace) then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = character:WaitForChild("Humanoid", LIMB_TIMEOUT) :: Humanoid?
	end
	return humanoid ~= nil
end

--[[
	Make one character match one attribute.

	Runs in its own thread because the limb may not exist yet on a character that
	was created this frame, and a claim must not be made to wait on a rig.
]]
local function apply(player: Player, spec: RelicRegalia.Spec)
	local character = player.Character
	if not character then
		return
	end
	local wanted = player:GetAttribute(spec.attribute) == true
	if not wanted then
		RelicRegalia.detach(character, spec)
		return
	end

	task.spawn(function()
		if not characterReady(character) then
			return
		end
		-- Re-read rather than trusting the value this thread started with: a
		-- round can reset while we are waiting on a limb.
		if character ~= player.Character or player:GetAttribute(spec.attribute) ~= true then
			return
		end
		if not RelicRegalia.attach(character, spec) then
			warn(
				`[RelicRegaliaService] no {spec.templateName} template in ServerStorage.{RelicRegalia.FolderName} `
					.. `(or no "{RelicRegalia.RootName}" part in it) — {player.Name} keeps the ability, not the object`
			)
		end
	end)
end

local function applyAll(player: Player)
	for _, spec in RelicRegalia.SPECS do
		apply(player, spec)
	end
end

local function watch(player: Player)
	if connections[player] then
		return
	end
	local bound: { RBXScriptConnection } = {}
	connections[player] = bound

	for _, spec in RelicRegalia.SPECS do
		table.insert(
			bound,
			player:GetAttributeChangedSignal(spec.attribute):Connect(function()
				apply(player, spec)
			end)
		)
	end
	table.insert(
		bound,
		player.CharacterAdded:Connect(function()
			-- Deferred so the character is parented and its limbs have begun
			-- arriving before the first FindFirstChild.
			task.defer(applyAll, player)
		end)
	)

	if player.Character then
		applyAll(player)
	end
end

local function unwatch(player: Player)
	local bound = connections[player]
	if bound then
		for _, connection in bound do
			connection:Disconnect()
		end
	end
	connections[player] = nil
end

for _, player in Players:GetPlayers() do
	watch(player)
end
Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(unwatch)

local names = {}
for _, spec in RelicRegalia.SPECS do
	table.insert(names, `{spec.templateName} -> {string.lower(spec.side)} hand`)
end
print(`[RelicRegaliaService] ready — {table.concat(names, ", ")}`)
