local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local HACKER_TEAM_NAME = "Hacker"
local BACKPACK_TEMPLATE = ServerStorage:WaitForChild("HACKER BACKPACK")

-- Track which characters currently have a backpack so we can clean up.
local equippedCharacters = {}

local function getTorso(character)
	-- R15 uses UpperTorso, R6 uses Torso
	return character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
end

local function attachBackpack(character)
	local torso = getTorso(character)
	if not torso then
		return false
	end

	-- Clone the backpack model
	local backpack = BACKPACK_TEMPLATE:Clone()
	backpack.Name = "HackerBackpackEquipped"

	-- Determine the back offset based on rig type
	local isR15 = character:FindFirstChild("UpperTorso") ~= nil
	local backOffset = isR15 and CFrame.new(0, 0, 1.2) or CFrame.new(0, 0, -1.2)
	-- For R15 UpperTorso, the back face is +Z; for R6 Torso, the back face is -Z
	if isR15 then
		backOffset = CFrame.new(0, 0, 0.7) * CFrame.Angles(math.rad(180),math.rad(-90),math.rad(90))
	else
		backOffset = CFrame.new(0, 0, 0.7) * CFrame.Angles(math.rad(180),math.rad(-90),math.rad(90))
	end

	-- Move the backpack to the torso's back
	backpack:PivotTo(torso.CFrame * backOffset)

	-- Parent to the character so it moves with them
	backpack.Parent = character

	-- Weld every part in the backpack to the torso so it stays attached
	for _, descendant in ipairs(backpack:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			local weld = Instance.new("WeldConstraint")
			weld.Name = "BackpackWeld"
			weld.Part0 = descendant
			weld.Part1 = torso
			weld.Parent = descendant
		end
	end

	equippedCharacters[character] = backpack
	return true
end

local function removeBackpack(character)
	local backpack = equippedCharacters[character]
	if backpack then
		backpack:Destroy()
		equippedCharacters[character] = nil
	end
end

local function updateBackpack(player, character)
	if not character then return end

	local function check()
		-- Wait a moment for character to fully load
		local torso = getTorso(character)
		if not torso then
			return
		end

		local onHackerTeam = player.Team and player.Team.Name == HACKER_TEAM_NAME

		if onHackerTeam and not equippedCharacters[character] then
			attachBackpack(character)
		elseif not onHackerTeam and equippedCharacters[character] then
			removeBackpack(character)
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
			removeBackpack(character)
			if teamConn then
				teamConn:Disconnect()
			end
		end
	end)
end

local function onPlayerAdded(player)
	player.CharacterAdded:Connect(function(character)
		updateBackpack(player, character)
	end)

	-- Handle the case where the character already exists
	if player.Character then
		updateBackpack(player, player.Character)
	end
end

-- Connect for new players
Players.PlayerAdded:Connect(onPlayerAdded)

-- Handle players already in the game
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end
