--!strict
-- Client presentation for the first-stay tutorial. The server advances the
-- Player's OnboardingStage; this script only turns that state into a rustic
-- objective card, a ground guide arrow, and local-only silhouettes.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local OnboardingConfig = require(ReplicatedStorage:WaitForChild("OnboardingConfig"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GUI_NAME = "FirstStayOnboarding"
local TARGET_REFRESH_INTERVAL = 0.75

local INK = Color3.fromRGB(52, 36, 22)
local INK_SOFT = Color3.fromRGB(122, 96, 66)
local EDGE = Color3.fromRGB(74, 52, 33)
local PAPER = Color3.fromRGB(238, 224, 190)
local PAPER_LOW = Color3.fromRGB(219, 200, 160)
local GUIDE = Color3.fromRGB(231, 194, 103)
local GROUND_ARROW_IMAGE = "rbxassetid://122620264598060"

type Target = {
	highlight: Instance,
	arrow: BasePart,
}

local function corner(instance: GuiObject, radius: number)
	local ui = Instance.new("UICorner")
	ui.CornerRadius = UDim.new(0, radius)
	ui.Parent = instance
end

local function stroke(instance: GuiObject, color: Color3, thickness: number, transparency: number?): UIStroke
	local line = Instance.new("UIStroke")
	line.Color = color
	line.Thickness = thickness
	line.Transparency = transparency or 0
	line.LineJoinMode = Enum.LineJoinMode.Round
	line.Parent = instance
	return line
end

for _, existing in ipairs(playerGui:GetChildren()) do
	if existing.Name == GUI_NAME then
		existing:Destroy()
	end
end

local gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
gui.DisplayOrder = 46
gui.IgnoreGuiInset = false
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local shadow = Instance.new("Frame")
shadow.Name = "ObjectiveShadow"
shadow.AnchorPoint = Vector2.new(0.5, 0)
shadow.BackgroundColor3 = Color3.fromRGB(22, 14, 8)
shadow.BackgroundTransparency = 0.48
shadow.BorderSizePixel = 0
shadow.Position = UDim2.new(0.5, 5, 0, 26)
shadow.Size = UDim2.fromOffset(430, 78)
shadow.Visible = false
shadow.ZIndex = 1
corner(shadow, 18)
shadow.Parent = gui

local card = Instance.new("Frame")
card.Name = "ObjectiveCard"
card.AnchorPoint = Vector2.new(0.5, 0)
card.BackgroundColor3 = PAPER
card.BorderSizePixel = 0
card.Position = UDim2.new(0.5, 0, 0, 20)
card.Rotation = -0.5
card.Size = UDim2.fromOffset(430, 78)
card.Visible = false
card.ZIndex = 2
corner(card, 18)
stroke(card, EDGE, 3)
card.Parent = gui

local aged = Instance.new("UIGradient")
aged.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(247, 238, 213)),
	ColorSequenceKeypoint.new(0.55, Color3.fromRGB(236, 222, 189)),
	ColorSequenceKeypoint.new(1, PAPER_LOW),
})
aged.Rotation = 90
aged.Parent = card

local inner = Instance.new("Frame")
inner.BackgroundTransparency = 1
inner.Position = UDim2.fromOffset(7, 7)
inner.Size = UDim2.new(1, -14, 1, -14)
inner.ZIndex = 3
corner(inner, 12)
stroke(inner, INK_SOFT, 1, 0.5)
inner.Parent = card

local heading = Instance.new("TextLabel")
heading.BackgroundTransparency = 1
heading.Font = Enum.Font.Garamond
heading.Position = UDim2.fromOffset(24, 11)
heading.Size = UDim2.new(1, -48, 0, 18)
heading.Text = "CURRENT OBJECTIVE"
heading.TextColor3 = INK_SOFT
heading.TextSize = 13
heading.TextXAlignment = Enum.TextXAlignment.Center
heading.ZIndex = 4
heading.Parent = card

local divider = Instance.new("Frame")
divider.AnchorPoint = Vector2.new(0.5, 0)
divider.BackgroundColor3 = INK_SOFT
divider.BackgroundTransparency = 0.42
divider.BorderSizePixel = 0
divider.Position = UDim2.new(0.5, 0, 0, 31)
divider.Size = UDim2.new(1, -82, 0, 1)
divider.ZIndex = 4
divider.Parent = card

local objective = Instance.new("TextLabel")
objective.Name = "ObjectiveText"
objective.BackgroundTransparency = 1
objective.Font = Enum.Font.Garamond
objective.Position = UDim2.fromOffset(24, 34)
objective.Size = UDim2.new(1, -48, 0, 33)
objective.Text = ""
objective.TextColor3 = INK
objective.TextSize = 23
objective.TextXAlignment = Enum.TextXAlignment.Center
objective.TextYAlignment = Enum.TextYAlignment.Center
objective.ZIndex = 4
objective.Parent = card

-- One slim, filled graphic: it sits in 3D like a floor decal, but uses the
-- player's root as its Adornee so no invisible Part is added to the map.
local groundArrow = Instance.new("ImageHandleAdornment")
groundArrow.Name = "GuideGroundArrow"
groundArrow.AlwaysOnTop = false
groundArrow.Color3 = Color3.new(1, 1, 1)
groundArrow.Image = GROUND_ARROW_IMAGE
groundArrow.Size = Vector2.new(3.2, 6.2)
groundArrow.Transparency = 0.04
groundArrow.Visible = false
groundArrow.ZIndex = 2
groundArrow.Parent = gui

local activeHighlight: Highlight? = nil
local arrowTarget: BasePart? = nil
local lastTargetRefresh = 0

local function firstBasePart(root: Instance?): BasePart?
	if not root then
		return nil
	end
	if root:IsA("BasePart") then
		return root
	end
	if root:IsA("Model") and root.PrimaryPart then
		return root.PrimaryPart
	end
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

local function noelTarget(): Target?
	local noel = workspace:FindFirstChild("Noel")
	local part = firstBasePart(noel and noel:FindFirstChild("Head") or noel)
	if noel and part then
		return { highlight = noel, arrow = part }
	end
	return nil
end

local function elevatorTarget(): Target?
	for _, tagged in ipairs(CollectionService:GetTagged("ElevatorCab")) do
		if tagged:IsA("Model") and tagged:GetAttribute("CabId") == OnboardingConfig.LOBBY_CAB_ID then
			local buttonDoor = tagged:FindFirstChild("ButtonDoor")
			local button = buttonDoor and buttonDoor:FindFirstChild("Button")
			if button and button:IsA("BasePart") then
				return { highlight = button, arrow = button }
			end
		end
	end
	return nil
end

local function roomTarget(): Target?
	for _, tagged in ipairs(CollectionService:GetTagged("HotelDoor")) do
		if tagged:IsA("Model") and tagged.Name == OnboardingConfig.ROOM_DOOR_NAME then
			local keypad = tagged:FindFirstChild("Keypad")
			local part = firstBasePart(keypad)
			if keypad and part then
				return { highlight = keypad, arrow = part }
			end
		end
	end
	return nil
end

local function clearTarget()
	if activeHighlight then
		activeHighlight:Destroy()
		activeHighlight = nil
	end
	arrowTarget = nil
	groundArrow.Visible = false
end

local function targetFor(stage: any): Target?
	if stage == OnboardingConfig.TALK_TO_NOEL then
		return noelTarget()
	elseif stage == OnboardingConfig.ENTER_ELEVATOR then
		return elevatorTarget()
	elseif stage == OnboardingConfig.ENTER_ROOM then
		return roomTarget()
	end
	return nil
end

local function applyTarget(stage: any)
	clearTarget()
	local target = targetFor(stage)
	if not target then
		return
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "OnboardingHighlight"
	highlight.Adornee = target.highlight
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = GUIDE
	highlight.FillTransparency = 0.76
	highlight.OutlineColor = Color3.fromRGB(255, 226, 142)
	highlight.OutlineTransparency = 0.06
	highlight.Parent = gui
	activeHighlight = highlight
	arrowTarget = target.arrow

	TweenService:Create(
		highlight,
		TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ FillTransparency = 0.9, OutlineTransparency = 0.28 }
	):Play()
end

local function objectiveFor(stage: any): string?
	if stage == OnboardingConfig.TALK_TO_NOEL then
		return "Talk to Noel"
	elseif stage == OnboardingConfig.ENTER_ELEVATOR then
		return "Enter the elevator"
	elseif stage == OnboardingConfig.ENTER_ROOM then
		return "Enter your room"
	end
	return nil
end

local function refreshStage()
	local stage = player:GetAttribute(OnboardingConfig.ATTRIBUTE)
	local text = objectiveFor(stage)
	local visible = text ~= nil
	objective.Text = text or ""
	card.Visible = visible
	shadow.Visible = visible
	applyTarget(stage)
	lastTargetRefresh = os.clock()
end

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude

local function updateGroundArrow()
	local target = arrowTarget
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not target or not target.Parent or not root or not root:IsA("BasePart") then
		groundArrow.Visible = false
		return
	end

	local flatOffset = Vector3.new(target.Position.X - root.Position.X, 0, target.Position.Z - root.Position.Z)
	if flatOffset.Magnitude < 2 then
		groundArrow.Visible = false
		return
	end
	local direction = flatOffset.Unit
	local imageRight = Vector3.new(0, 1, 0):Cross(direction)

	raycastParams.FilterDescendantsInstances = { character }
	local camera = workspace.CurrentCamera
	local rawForward = if camera then camera.CFrame.LookVector else root.CFrame.LookVector
	local flatForward = Vector3.new(rawForward.X, 0, rawForward.Z)
	if flatForward.Magnitude < 0.01 then
		flatForward = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	end
	-- Far enough ahead that the whole graphic stays visible even when the
	-- objective is behind the player and the arrow points back toward them.
	local inFront = root.Position + flatForward.Unit * 11
	local groundHit = workspace:Raycast(inFront + Vector3.new(0, 2, 0), Vector3.new(0, -12, 0), raycastParams)
	local ground = if groundHit then groundHit.Position else inFront - Vector3.new(0, 3, 0)
	local arrowPosition = ground + Vector3.new(0, 0.1, 0)
	-- ImageHandleAdornment draws in its local X/Y plane. Local Y follows the
	-- objective, while its front faces upward so the graphic lies on the floor.
	local worldCFrame = CFrame.fromMatrix(arrowPosition, imageRight, direction, -Vector3.yAxis)
	groundArrow.Adornee = root
	groundArrow.CFrame = root.CFrame:ToObjectSpace(worldCFrame)
	groundArrow.Transparency = 0.03 + (math.sin(os.clock() * 4.5) + 1) * 0.035
	groundArrow.Visible = true
end

player:GetAttributeChangedSignal(OnboardingConfig.ATTRIBUTE):Connect(refreshStage)

RunService.RenderStepped:Connect(function()
	updateGroundArrow()

	local stage = player:GetAttribute(OnboardingConfig.ATTRIBUTE)
	if
		objectiveFor(stage) ~= nil
		and (not activeHighlight or not activeHighlight.Adornee or not arrowTarget or not arrowTarget.Parent)
		and os.clock() - lastTargetRefresh >= TARGET_REFRESH_INTERVAL
	then
		applyTarget(stage)
		lastTargetRefresh = os.clock()
	end
end)

refreshStage()
