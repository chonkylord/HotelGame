--!strict
--[[
	Shows the class prompts to the players they belong to.

	A ProximityPrompt has one Enabled flag for the whole server, so the doors
	create theirs switched off and this turns them on locally for a player whose
	class actually has a use for them. Setting Enabled from a LocalScript does
	not replicate, so nobody else's screen changes.

	This is presentation, not permission. HotelDoorService re-checks the class on
	the server when a prompt fires — for a bypass, both when the hold starts and
	when it completes — so a client that enables every prompt it can find still
	gets nothing out of them.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClassConfig = require(ReplicatedStorage:WaitForChild("ClassDefinitions"))

local player = Players.LocalPlayer

-- Prompt tag -> the class that gets to see it.
local promptOwner: { [string]: string } = {
	[ClassConfig.SMASH_PROMPT_TAG] = ClassConfig.MUSCLE,
	[ClassConfig.HACK_PROMPT_TAG] = ClassConfig.HACKER,
	[ClassConfig.BED_LIFT_PROMPT_TAG] = ClassConfig.MUSCLE,
}

--[[
	Holding the class is necessary but no longer sufficient for a smash prompt.

	HotelDoorService now builds a SmashPrompt on every intact door rather than
	only the Broken and Jammed ones, because the Ironhand relic is claimed from
	the vault long after doors are set up and a prompt cannot be created later.
	That means the tag alone would put "Smash open" on every Normal door in the
	hotel and it would silently do nothing when pressed -- the worst kind of bug,
	indistinguishable from a broken game.

	So the smash prompt is shown only when it would actually work: the door is in
	a state Muscle can already force, or the player is carrying the Ironhand.
	The server re-checks both regardless; this is purely so the prompt does not
	lie.
]]
local function doorStateFor(prompt: Instance): string?
	local node: Instance? = prompt
	while node do
		local state = node:GetAttribute(ClassConfig.DOOR_STATE_ATTRIBUTE or "State")
		if type(state) == "string" then
			return state
		end
		node = node.Parent
	end
	return nil
end

local function smashUsable(prompt: Instance): boolean
	if player:GetAttribute("MuscleRelic") == true then
		return true
	end
	local state = doorStateFor(prompt)
	return state ~= nil and ClassConfig.SmashableStates[state] == true
end

local function apply(prompt: Instance, enabled: boolean)
	if not prompt:IsA("ProximityPrompt") then
		return
	end
	if enabled and CollectionService:HasTag(prompt, ClassConfig.SMASH_PROMPT_TAG) then
		enabled = smashUsable(prompt)
	end
	prompt.Enabled = enabled
end

local function refresh()
	for tag, owner in promptOwner do
		local enabled = ClassConfig.hasClass(player, owner)
		for _, prompt in CollectionService:GetTagged(tag) do
			apply(prompt, enabled)
		end
	end
end

-- Doors are set up by the server, so their prompts can arrive after this runs
-- and after the class is chosen; both directions have to be covered.
for tag, owner in promptOwner do
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(prompt)
		apply(prompt, ClassConfig.hasClass(player, owner))
	end)
end

player:GetAttributeChangedSignal(ClassConfig.ATTRIBUTE):Connect(refresh)
player:GetAttributeChangedSignal(ClassConfig.ADMIN_ALL_CLASSES_ATTRIBUTE):Connect(refresh)
-- Claiming the Ironhand mid-round has to light up every door at once.
player:GetAttributeChangedSignal("MuscleRelic"):Connect(refresh)

refresh()
