--!strict
-- Party system configuration. Change this one value to choose the destination game.
-- It must be the Roblox PLACE ID (not the universe ID) that this experience can teleport to.
local DESTINATION_PLACE_ID = 0 -- TODO: replace 0 with your destination place ID before publishing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local TextChatService = game:GetService("TextChatService")

local remotes = ReplicatedStorage:FindFirstChild("PartyRemotes") :: Folder?
if not remotes then
	local newRemotes = Instance.new("Folder")
	newRemotes.Name = "PartyRemotes"
	newRemotes.Parent = ReplicatedStorage
	remotes = newRemotes
end
local remotesFolder = remotes :: Folder

local partyEvent = remotesFolder:FindFirstChild("PartyEvent") :: RemoteEvent?
if not partyEvent then
	local newPartyEvent = Instance.new("RemoteEvent")
	newPartyEvent.Name = "PartyEvent"
	newPartyEvent.Parent = remotesFolder
	partyEvent = newPartyEvent
end
local partyRemote = partyEvent :: RemoteEvent

type Party = {
	leader: Player,
	members: { [number]: Player },
	pending: { [number]: Player },
}

local parties: { [number]: Party } = {}
local membership: { [number]: number } = {}

local function fire(player: Player, action: string, payload: any?)
	partyRemote:FireClient(player, action, payload)
end

local function partyState(party: Party)
	local members = {}
	for _, player in party.members do
		table.insert(members, { userId = player.UserId, name = player.DisplayName })
	end
	table.sort(members, function(a, b)
		return a.name < b.name
	end)

	local pendingCount = 0
	for _ in party.pending do
		pendingCount += 1
	end

	return {
		memberCount = #members,
		members = members,
		pendingCount = pendingCount,
		readyToStart = pendingCount == 0,
	}
end

local function updateLeader(party: Party)
	if party.leader.Parent == Players then
		fire(party.leader, "PartyState", partyState(party))
	end
end

local function getOrCreateParty(leader: Player): Party?
	local existingLeader = membership[leader.UserId]
	if existingLeader and existingLeader ~= leader.UserId then
		fire(leader, "Error", "Leave your current party before creating a new one.")
		return nil
	end

	local party = parties[leader.UserId]
	if not party then
		party = {
			leader = leader,
			members = { [leader.UserId] = leader },
			pending = {},
		}
		parties[leader.UserId] = party
		membership[leader.UserId] = leader.UserId
	end
	return party
end

local function openPartyMenu(player: Player)
	if membership[player.UserId] and membership[player.UserId] ~= player.UserId then
		fire(player, "Error", "You are already in another player's party.")
		return
	end
	fire(player, "OpenInviteUI")
end

local function sendInvites(leader: Player, userIds: any)
	if typeof(userIds) ~= "table" then
		return
	end

	local party = getOrCreateParty(leader)
	if not party then
		return
	end

	local seen: { [number]: boolean } = {}
	local invited = 0
	for _, userId in userIds do
		if typeof(userId) == "number" and not seen[userId] and userId ~= leader.UserId then
			seen[userId] = true
			local target = Players:GetPlayerByUserId(userId)
			if target and not membership[userId] and not party.pending[userId] then
				party.pending[userId] = target
				invited += 1
				fire(target, "PartyInvite", {
					leaderUserId = leader.UserId,
					inviter = leader.DisplayName,
				})
			end
		end
	end

	updateLeader(party)
	if invited == 0 then
		fire(leader, "Notice", "No new players were available to invite.")
	else
		fire(leader, "Notice", "Invitations sent. Waiting for responses...")
	end
end

local function respondToInvite(player: Player, leaderUserId: any, accepted: any)
	if typeof(leaderUserId) ~= "number" or typeof(accepted) ~= "boolean" then
		return
	end
	local party = parties[leaderUserId]
	if not party or party.pending[player.UserId] ~= player then
		return
	end

	party.pending[player.UserId] = nil
	if accepted and not membership[player.UserId] then
		party.members[player.UserId] = player
		membership[player.UserId] = leaderUserId
		fire(player, "Notice", `You joined {party.leader.DisplayName}'s party.`)
	else
		fire(player, "Notice", "Party invitation ignored.")
	end
	updateLeader(party)
end

local function startParty(leader: Player)
	local party = parties[leader.UserId]
	if not party or party.leader ~= leader then
		fire(leader, "Error", "Create a party through the receptionist first.")
		return
	end
	if next(party.pending) ~= nil then
		fire(leader, "Error", "Wait for every invited player to join or ignore first.")
		return
	end
	if DESTINATION_PLACE_ID <= 0 then
		fire(leader, "Error", "The developer has not set DESTINATION_PLACE_ID in PartyService yet.")
		return
	end

	local travelers = {}
	for _, player in party.members do
		if player.Parent == Players then
			table.insert(travelers, player)
		end
	end

	local success, err = pcall(function()
		TeleportService:TeleportAsync(DESTINATION_PLACE_ID, travelers)
	end)
	if not success then
		warn("[PartyService] Teleport failed:", err)
		fire(leader, "Error", "Teleport failed. Please try again.")
	end
end

partyRemote.OnServerEvent:Connect(function(player: Player, action: any, payload: any)
	if action == "SendInvites" then
		sendInvites(player, payload)
	elseif action == "RespondToInvite" and typeof(payload) == "table" then
		respondToInvite(player, payload.leaderUserId, payload.accepted)
	elseif action == "StartParty" then
		startParty(player)
	end
end)

task.spawn(function()
	local receptionist = workspace:WaitForChild("Receptionist", 30)
	if not receptionist then
		return
	end
	-- PartyPrompt is parented to a body part, so it is a descendant rather than
	-- a direct child of the model. Poll briefly to accommodate script startup order.
	local prompt = receptionist:FindFirstChild("PartyPrompt", true)
	local timeout = os.clock() + 30
	while not prompt and os.clock() < timeout do
		task.wait(0.1)
		prompt = receptionist:FindFirstChild("PartyPrompt", true)
	end
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Triggered:Connect(function(player: Player)
			local bubbleTarget = prompt.Parent
			if bubbleTarget and (bubbleTarget:IsA("BasePart") or bubbleTarget:IsA("Attachment")) then
				pcall(function()
					TextChatService:DisplayBubble(bubbleTarget, "Who would you like to invite to your party?")
				end)
			end
			openPartyMenu(player)
		end)
		print("[PartyService] Receptionist party prompt connected.")
	else
		warn("[PartyService] Receptionist PartyPrompt was not found.")
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	local leaderUserId = membership[player.UserId]
	if leaderUserId then
		local party = parties[leaderUserId]
		if party then
			party.members[player.UserId] = nil
			membership[player.UserId] = nil
			if player == party.leader then
				for _, member in party.members do
					membership[member.UserId] = nil
					fire(member, "Notice", "The party leader left, so the party was disbanded.")
				end
				parties[leaderUserId] = nil
			else
				updateLeader(party)
			end
		end
	end

	for _, party in parties do
		if party.pending[player.UserId] then
			party.pending[player.UserId] = nil
			updateLeader(party)
		end
	end
end)