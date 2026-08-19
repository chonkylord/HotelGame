local TweenService = game:GetService("TweenService")

-- Locate all the necessary parts
local bankVault = workspace:FindFirstChild("BankVault")
local roundVaultDoor = bankVault and bankVault:FindFirstChild("RoundVaultDoor")
local vaultDoor = roundVaultDoor and roundVaultDoor:FindFirstChild("VaultDoor")
local swingAngle = roundVaultDoor and roundVaultDoor:FindFirstChild("DoorSwingAngle")
local hinge = bankVault and bankVault:FindFirstChild("Hinge_2")

if not (bankVault and roundVaultDoor and vaultDoor and swingAngle and hinge) then
	warn("[VaultDoorController] Could not find all required components!")
	return
end

-- The hinge position is the pivot point the door rotates around
local hingePos = hinge.Position

-- Store the closed-position pivot so we can calculate rotations from it
local closedPivot = roundVaultDoor:GetPivot()

-- State tracking
local isOpen = false
local isAnimating = false

local prompt = vaultDoor:FindFirstChildOfClass("ProximityPrompt")
if not prompt then
	warn("[VaultDoorController] No ProximityPrompt found on VaultDoor!")
	return
end

-- Function to rotate the entire door model around the hinge by a given angle (degrees)
local function setDoorAngle(angle)
	local hingeCFrame = CFrame.new(hingePos)
	local rotation = CFrame.Angles(0, math.rad(angle), 0)
	-- Transform: move to hinge space, rotate, move back to world space
	local newPivot = hingeCFrame * rotation * hingeCFrame:Inverse() * closedPivot
	roundVaultDoor:PivotTo(newPivot)
end

-- Update door position whenever the swing angle changes (driven by the tween)
swingAngle.Changed:Connect(function(value)
	setDoorAngle(value)
end)

-- Ensure the door starts in the closed position
swingAngle.Value = 0

-- Handle the player pressing E
prompt.Triggered:Connect(function(player)
	if isAnimating then
		return
	end
	isAnimating = true

	local targetAngle = isOpen and 0 or 90
	local tweenInfo = TweenInfo.new(3, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	local tween = TweenService:Create(swingAngle, tweenInfo, { Value = targetAngle })

	tween:Play()

	tween.Completed:Connect(function()
		isAnimating = false
		isOpen = not isOpen
		prompt.ActionText = isOpen and "Close" or "Open"
	end)
end)

print("[VaultDoorController] Vault door controller initialized successfully.")