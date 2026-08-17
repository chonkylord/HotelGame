local ClickDetector = script.Parent:WaitForChild("ClickDetector")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

-- Change "MyWeaponName" to the exact name of your Tool inside ServerStorage
local TOOL_NAME = "Red Bull" 
local COOLDOWN_TIME = 300 -- 5 minutes in seconds (5 * 60)

-- Table to store the last time each player clicked: { [player] = timestamp }
local playerCooldowns = {}

local function onMouseClick(player)
	local currentTime = os.time()
	local lastClickTime = playerCooldowns[player] or 0

	-- Check if 5 minutes (300 seconds) have passed since this specific player's last click
	if currentTime - lastClickTime < COOLDOWN_TIME then
		local timeRemaining = COOLDOWN_TIME - (currentTime - lastClickTime)
		-- Optional warning in output (you can remove this line if not needed)
		warn(player.Name .. " must wait " .. math.ceil(timeRemaining) .. " more seconds.")
		return
	end

	-- Find the master copy of the tool in ServerStorage
	local masterTool = ServerStorage:FindFirstChild(TOOL_NAME)

	if masterTool then
		-- Check if the player already has this item equipped or in their inventory
		local backpack = player:FindFirstChild("Backpack")
		local character = player.Character

		local alreadyHasTool = (backpack and backpack:FindFirstChild(TOOL_NAME)) or (character and character:FindFirstChild(TOOL_NAME))

		if not alreadyHasTool then
			-- Update the player's cooldown timestamp ONLY when they successfully get the item
			playerCooldowns[player] = currentTime

			-- Clone the tool so the master copy remains in ServerStorage
			local clonedTool = masterTool:Clone()
			-- Put the cloned tool into the player's inventory (Backpack)
			clonedTool.Parent = backpack
		end
	else
		warn("Could not find " .. TOOL_NAME .. " in ServerStorage!")
	end
end

-- Clean up memory when a player leaves the game
Players.PlayerRemoving:Connect(function(player)
	playerCooldowns[player] = nil
end)

ClickDetector.MouseClick:Connect(onMouseClick)
