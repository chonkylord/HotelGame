local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local SUPERMAN_TEAM_NAME = "SuperHero"
local CAPE_TEMPLATE = ServerStorage:WaitForChild("Cape")

-- Track which characters currently have a cape so we can clean up.
local equippedCharacters = {}

local function getTorso(character)
	-- R15 uses UpperTorso, R6 uses Torso
	return character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
end

local function attachCape(character)
	local torso = getTorso(character)
	if not torso then
		return false
	end

	-- Clone the cape model
	local cape = CAPE_TEMPLATE:Clone()
	cape.Name = "SupermanCapeEquipped"

	-- Determine the back offset based on rig type
	local isR15 = character:FindFirstChild("UpperTorso") ~= nil
	local backOffset
	if isR15 then
		backOffset = CFrame.new(0, -0.7, 0.1) * CFrame.Angles(math.rad(0), math.rad(-90), math.rad(0))
	else
		backOffset = CFrame.new(0, 0, 0.7) * CFrame.Angles(math.rad(0), math.rad(0), math.rad(0))
	end

	-- Move the cape to the torso's back
	cape:PivotTo(torso.CFrame * backOffset)

	-- Parent to the character so it moves with them
	cape.Parent = character

	-- Weld every part in the cape to the torso so it stays attached
	for _, descendant in ipairs(cape:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			local weld = Instance.new("WeldConstraint")
			weld.Name = "CapeWeld"
			weld.Part0 = descendant
			weld.Part1 = torso
			weld.Parent = descendant
		end
	end

	equippedCharacters[character] = cape
	return true
end

local function removeCape(character)
	local cape = equippedCharacters[character]
	if cape then
		cape:Destroy()
		equippedCharacters[character] = nil
	end
end

local function updateCape(player, character)
	if not character then return end

	local function check()
		-- Wait a moment for character to fully load
		local torso = getTorso(character)
		if not torso then
			return
		end

		local onSupermanTeam = player.Team and player.Team.Name == SUPERMAN_TEAM_NAME

		if onSupermanTeam and not equippedCharacters[character] then
			attachCape(character)
		elseif not onSupermanTeam and equippedCharacters[character] then
			removeCape(character)
		end
	end

	-- Check immediately
	check()

	-- Also check when the player changes teams
	local teamConn
	teamConn = player:GetPropertyChangedSignal("Team"):Connect(function()
		if character and character.Parent then
			check()
		end
	end)

	-- Clean up when character is removed
	character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(game) then
			removeCape(character)
			if teamConn then
				teamConn:Disconnect()
			end
		end
	end)
end

local function onPlayerAdded(player)
	player.CharacterAdded:Connect(function(character)
		updateCape(player, character)
	end)

	-- Handle the case where the character already exists
	if player.Character then
		updateCape(player, player.Character)
	end
end

-- Connect for new players
Players.PlayerAdded:Connect(onPlayerAdded)

-- Handle players already in the game
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end