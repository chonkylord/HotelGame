local tool = script.Parent
local Players = game:GetService("Players")

-- ================= CUSTOMIZABLE SETTINGS =================
local DASH_DISTANCE = 20 -- How many studs forward you go
local COOLDOWN = 10    -- Cooldown in seconds
-- =========================================================

local isOnCooldown = false

local function onActivated()
	-- Check if the tool is on cooldown
	if isOnCooldown then return end

	-- The character is the parent of the tool when it is equipped
	local character = tool.Parent
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")

	-- Ensure the player is alive and has a physics root
	if humanoid and rootPart and humanoid.Health > 0 then
		isOnCooldown = true

		-- Calculate the new position: Current position + (Facing Direction * Distance)
		local forwardDirection = rootPart.CFrame.LookVector
		rootPart.CFrame = rootPart.CFrame + (forwardDirection * DASH_DISTANCE)

		-- Wait for the cooldown to finish
		task.wait(COOLDOWN)
		isOnCooldown = false
	end
end

tool.Activated:Connect(onActivated)
