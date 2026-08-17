--!strict
-- Presents the rescue state and forwards one intent: carry/drop with T. The
-- server owns target selection, distances, bandages, state transitions, and
-- every physical constraint.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local RescueConfig = require(ReplicatedStorage:WaitForChild("RescueConfig"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild(RescueConfig.RemotesFolder)
local carryToggleEvent = remotes:WaitForChild(RescueConfig.CarryToggleEvent) :: RemoteEvent
local feedbackEvent = remotes:WaitForChild(RescueConfig.FeedbackEvent) :: RemoteEvent

local GUI_NAME = "RescueHUD"
local CARRY_ACTION = "RescueCarryOrDrop"
local connections: { RBXScriptConnection } = {}

local INK = Color3.fromRGB(32, 29, 27)
local PAPER = Color3.fromRGB(221, 208, 171)
local PAPER_DIM = Color3.fromRGB(170, 157, 127)
local MEDICAL_RED = Color3.fromRGB(161, 49, 43)
local SAFE_GREEN = Color3.fromRGB(103, 161, 115)
local WARNING = Color3.fromRGB(222, 165, 79)

for _, existing in playerGui:GetChildren() do
	if existing.Name == GUI_NAME then
		existing:Destroy()
	end
end

local screen = Instance.new("ScreenGui")
screen.Name = GUI_NAME
screen.DisplayOrder = 8
screen.IgnoreGuiInset = false
screen.ResetOnSpawn = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- A narrow inventory tag in the otherwise unused lower-right corner. It does
-- not compete with the survival meters or the case file in the lower-left.
local bandageCard = Instance.new("Frame")
bandageCard.Name = "Bandages"
bandageCard.AnchorPoint = Vector2.new(1, 1)
bandageCard.BackgroundColor3 = INK
bandageCard.BackgroundTransparency = 0.14
bandageCard.BorderSizePixel = 0
bandageCard.Position = UDim2.new(1, -22, 1, -22)
bandageCard.Size = UDim2.fromOffset(194, 54)
bandageCard.Parent = screen

local bandageCorner = Instance.new("UICorner")
bandageCorner.CornerRadius = UDim.new(0, 4)
bandageCorner.Parent = bandageCard

local bandageStroke = Instance.new("UIStroke")
bandageStroke.Color = Color3.fromRGB(87, 76, 63)
bandageStroke.Transparency = 0.22
bandageStroke.Thickness = 1
bandageStroke.Parent = bandageCard

local cross = Instance.new("Frame")
cross.Name = "MedicalCross"
cross.BackgroundColor3 = MEDICAL_RED
cross.BorderSizePixel = 0
cross.Position = UDim2.fromOffset(20, 12)
cross.Size = UDim2.fromOffset(10, 30)
cross.Parent = bandageCard

local crossbar = Instance.new("Frame")
crossbar.BackgroundColor3 = MEDICAL_RED
crossbar.BorderSizePixel = 0
crossbar.Position = UDim2.fromOffset(-10, 10)
crossbar.Size = UDim2.fromOffset(30, 10)
crossbar.Parent = cross

local bandageCount = Instance.new("TextLabel")
bandageCount.Name = "Count"
bandageCount.BackgroundTransparency = 1
bandageCount.Font = Enum.Font.Antique
bandageCount.Position = UDim2.fromOffset(50, 4)
bandageCount.Size = UDim2.fromOffset(134, 27)
bandageCount.TextColor3 = PAPER
bandageCount.TextSize = 17
bandageCount.TextXAlignment = Enum.TextXAlignment.Left
bandageCount.Text = "BANDAGES  0 / 3"
bandageCount.Parent = bandageCard

local carryHint = Instance.new("TextLabel")
carryHint.Name = "CarryHint"
carryHint.BackgroundTransparency = 1
carryHint.Font = Enum.Font.Code
carryHint.Position = UDim2.fromOffset(50, 29)
carryHint.Size = UDim2.fromOffset(134, 18)
carryHint.TextColor3 = PAPER_DIM
carryHint.TextSize = 12
carryHint.TextXAlignment = Enum.TextXAlignment.Left
carryHint.Text = "T  CARRY NEARBY BODY"
carryHint.Parent = bandageCard

-- Incapacitation is the only time this larger strip appears. At that point the
-- local player cannot move, so clarity matters more than preserving that small
-- area of the view. It remains above both the hotbar and bottom-left meters.
local statusCard = Instance.new("Frame")
statusCard.Name = "Status"
statusCard.AnchorPoint = Vector2.new(0.5, 1)
statusCard.BackgroundColor3 = INK
statusCard.BackgroundTransparency = 0.1
statusCard.BorderSizePixel = 0
statusCard.Position = UDim2.new(0.5, 0, 1, -126)
statusCard.Size = UDim2.new(0.44, 0, 0, 76)
statusCard.Visible = false
statusCard.Parent = screen

local statusConstraint = Instance.new("UISizeConstraint")
statusConstraint.MinSize = Vector2.new(270, 76)
statusConstraint.MaxSize = Vector2.new(480, 76)
statusConstraint.Parent = statusCard

local statusCorner = Instance.new("UICorner")
statusCorner.CornerRadius = UDim.new(0, 5)
statusCorner.Parent = statusCard

local statusStripe = Instance.new("Frame")
statusStripe.Name = "Stripe"
statusStripe.BackgroundColor3 = MEDICAL_RED
statusStripe.BorderSizePixel = 0
statusStripe.Size = UDim2.fromOffset(6, 76)
statusStripe.Parent = statusCard

local statusTitle = Instance.new("TextLabel")
statusTitle.Name = "Title"
statusTitle.BackgroundTransparency = 1
statusTitle.Font = Enum.Font.Antique
statusTitle.Position = UDim2.fromOffset(20, 8)
statusTitle.Size = UDim2.new(1, -34, 0, 27)
statusTitle.TextColor3 = PAPER
statusTitle.TextSize = 21
statusTitle.TextXAlignment = Enum.TextXAlignment.Left
statusTitle.Text = ""
statusTitle.Parent = statusCard

local statusDetail = Instance.new("TextLabel")
statusDetail.Name = "Detail"
statusDetail.BackgroundTransparency = 1
statusDetail.Font = Enum.Font.SourceSans
statusDetail.Position = UDim2.fromOffset(20, 36)
statusDetail.Size = UDim2.new(1, -34, 0, 31)
statusDetail.TextColor3 = PAPER_DIM
statusDetail.TextSize = 16
statusDetail.TextWrapped = true
statusDetail.TextXAlignment = Enum.TextXAlignment.Left
statusDetail.TextYAlignment = Enum.TextYAlignment.Top
statusDetail.Text = ""
statusDetail.Parent = statusCard

local toast = Instance.new("CanvasGroup")
toast.Name = "Feedback"
toast.AnchorPoint = Vector2.new(0.5, 1)
toast.BackgroundColor3 = INK
toast.BackgroundTransparency = 0.08
toast.BorderSizePixel = 0
toast.GroupTransparency = 1
toast.Position = UDim2.new(0.5, 0, 1, -218)
toast.Size = UDim2.new(1, -32, 0, 40)
toast.Visible = false
toast.Parent = screen

local toastConstraint = Instance.new("UISizeConstraint")
toastConstraint.MaxSize = Vector2.new(340, 40)
toastConstraint.MinSize = Vector2.new(220, 40)
toastConstraint.Parent = toast

local toastCorner = Instance.new("UICorner")
toastCorner.CornerRadius = UDim.new(0, 4)
toastCorner.Parent = toast

local toastText = Instance.new("TextLabel")
toastText.BackgroundTransparency = 1
toastText.Font = Enum.Font.SourceSansSemibold
toastText.Position = UDim2.fromOffset(12, 0)
toastText.Size = UDim2.new(1, -24, 1, 0)
toastText.TextColor3 = PAPER
toastText.TextSize = 16
toastText.TextWrapped = true
toastText.Text = ""
toastText.Parent = toast

screen.Parent = playerGui

local viewportConnection: RBXScriptConnection? = nil
local compactLayout = false

local function applyViewportLayout()
	local camera = Workspace.CurrentCamera
	local width = if camera then camera.ViewportSize.X else 1280
	local compact = width < 600 or (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
	compactLayout = compact
	if compact then
		-- The lower edge belongs to the survival bars and case file on a phone.
		-- Stack these immediately above that fixed cluster; feedback temporarily
		-- replaces the bandage tag so the three panels never cover one another.
		bandageCard.AnchorPoint = Vector2.new(1, 1)
		bandageCard.Position = UDim2.new(1, -12, 1, -270)
		bandageCard.Size = UDim2.fromOffset(194, 54)
		statusCard.AnchorPoint = Vector2.new(0.5, 1)
		statusCard.Position = UDim2.new(0.5, 0, 1, -336)
		statusCard.Size = UDim2.new(1, -48, 0, 76)
		toast.AnchorPoint = Vector2.new(0.5, 1)
		toast.Position = UDim2.new(0.5, 0, 1, -264)
	else
		bandageCard.AnchorPoint = Vector2.new(1, 1)
		bandageCard.Position = UDim2.new(1, -22, 1, -22)
		bandageCard.Size = UDim2.fromOffset(194, 54)
		statusCard.AnchorPoint = Vector2.new(0.5, 1)
		statusCard.Position = UDim2.new(0.5, 0, 1, -126)
		statusCard.Size = UDim2.new(0.44, 0, 0, 76)
		toast.AnchorPoint = Vector2.new(0.5, 1)
		toast.Position = UDim2.new(0.5, 0, 1, -218)
	end
	bandageCard.Visible = not (compactLayout and toast.Visible)
	local touchButton = ContextActionService:GetButton(CARRY_ACTION)
	if touchButton then
		if compactLayout then
			touchButton.AnchorPoint = Vector2.new(0, 1)
			touchButton.Position = UDim2.new(0, 12, 1, -270)
		else
			touchButton.AnchorPoint = Vector2.new(0.5, 0.5)
			touchButton.Position = UDim2.new(1, -116, 0.66, 0)
		end
	end
end

local function bindViewport()
	if viewportConnection then
		viewportConnection:Disconnect()
		viewportConnection = nil
	end
	local camera = Workspace.CurrentCamera
	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyViewportLayout)
	end
	applyViewportLayout()
end

table.insert(connections, Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindViewport))

local toastRevision = 0

local function showFeedback(message: string, tone: string?)
	if message == "" then
		return
	end
	toastRevision += 1
	local revision = toastRevision
	toastText.Text = message
	toastText.TextColor3 = if tone == "danger"
		then Color3.fromRGB(239, 126, 112)
		elseif tone == "success" then SAFE_GREEN
		elseif tone == "warning" then WARNING
		else PAPER
	toast.Visible = true
	bandageCard.Visible = not compactLayout
	toast.GroupTransparency = 1
	TweenService:Create(toast, TweenInfo.new(0.14), { GroupTransparency = 0 }):Play()
	task.delay(2.6, function()
		if toastRevision ~= revision or not toast.Parent then
			return
		end
		local tween = TweenService:Create(toast, TweenInfo.new(0.25), { GroupTransparency = 1 })
		tween:Play()
		tween.Completed:Once(function()
			if toastRevision == revision then
				toast.Visible = false
				bandageCard.Visible = true
			end
		end)
	end)
end

table.insert(
	connections,
	feedbackEvent.OnClientEvent:Connect(function(payload: any)
		if typeof(payload) == "string" then
			showFeedback(payload)
		elseif typeof(payload) == "table" and typeof(payload.text) == "string" then
			showFeedback(payload.text, if typeof(payload.tone) == "string" then payload.tone else nil)
		end
	end)
)

local resetRevision = 0

local function setResetEnabled(enabled: boolean)
	resetRevision += 1
	local revision = resetRevision
	task.spawn(function()
		-- SetCore can reject calls for a short time while CoreScripts start.
		for _ = 1, 16 do
			if resetRevision ~= revision then
				return
			end
			local ok = pcall(function()
				StarterGui:SetCore("ResetButtonCallback", enabled)
			end)
			if ok then
				return
			end
			task.wait(0.25)
		end
	end)
end

local function carryingUserId(): number
	local value = player:GetAttribute(RescueConfig.CarryingUserIdAttribute)
	return if typeof(value) == "number" then value else 0
end

local function inputHint(): string
	local lastInput = UserInputService:GetLastInputType()
	if string.find(lastInput.Name, "Gamepad", 1, true) then
		return "Y  CARRY NEARBY BODY"
	elseif UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "CARRY BUTTON  •  NEARBY BODY"
	end
	return "T  CARRY NEARBY BODY"
end

local function updateTouchButton(carrying: boolean, enabled: boolean)
	ContextActionService:SetTitle(CARRY_ACTION, if carrying then "DROP" else "CARRY")
	local button = ContextActionService:GetButton(CARRY_ACTION)
	if button then
		button.Name = "CarryBodyButton"
		button.Visible = enabled
		button.Size = UDim2.fromOffset(68, 68)
		button.ImageColor3 = INK
		button.ImageTransparency = 0.12
		if compactLayout then
			button.AnchorPoint = Vector2.new(0, 1)
			button.Position = UDim2.new(0, 12, 1, -270)
		else
			button.AnchorPoint = Vector2.new(0.5, 0.5)
			button.Position = UDim2.new(1, -116, 0.66, 0)
		end
	end
end

local function redraw()
	local rawBandages = player:GetAttribute(RescueConfig.BandageCountAttribute)
	local count = if typeof(rawBandages) == "number"
		then math.clamp(math.floor(rawBandages), 0, RescueConfig.MaxBandages)
		else 0
	local state = player:GetAttribute(RescueConfig.StateAttribute)
	local rawCatches = player:GetAttribute(RescueConfig.CatchCountAttribute)
	local catches = if typeof(rawCatches) == "number" then rawCatches else 0
	local carrying = carryingUserId() > 0

	bandageCount.Text = `BANDAGES  {count} / {RescueConfig.MaxBandages}`
	bandageCount.TextColor3 = if count > 0 then PAPER else PAPER_DIM
	carryHint.Text = if state ~= RescueConfig.StateHealthy
		then "WAIT FOR TEAMMATE"
		elseif carrying then (string.split(inputHint(), "  ")[1] .. "  DROP BODY")
		else inputHint()
	updateTouchButton(carrying, state == RescueConfig.StateHealthy)

	statusCard.Visible = state ~= RescueConfig.StateHealthy or carrying
	statusStripe.BackgroundColor3 = MEDICAL_RED
	if state == RescueConfig.StateDragging then
		statusTitle.Text = "JOEL HAS YOU"
		statusDetail.Text = "He is dragging you elsewhere in the hotel."
	elseif state == RescueConfig.StateDowned then
		statusTitle.Text = "DOWNED — ONE HEART"
		statusDetail.Text = "A teammate with a bandage must hold E near you."
	elseif state == RescueConfig.StateCarried and catches >= 2 then
		statusTitle.Text = "NO REVIVES LEFT"
		statusDetail.Text = "A teammate is carrying your body to safety."
	elseif state == RescueConfig.StateCarried then
		statusTitle.Text = "BEING CARRIED"
		statusDetail.Text = "A teammate can still use a bandage to revive you."
	elseif state == RescueConfig.StateDead then
		statusTitle.Text = "NO REVIVES LEFT"
		statusDetail.Text = "A teammate can press T nearby to carry your body."
	elseif carrying then
		statusStripe.BackgroundColor3 = WARNING
		statusTitle.Text = "CARRYING A TEAMMATE"
		statusDetail.Text = "You move slower. Use the carry control to put them down."
	else
		statusCard.Visible = false
	end

	setResetEnabled(not RescueConfig.isImmobilized(state))
end

local function carryAction(
	_actionName: string,
	inputState: Enum.UserInputState,
	_inputObject: InputObject
): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if UserInputService:GetFocusedTextBox() then
		return Enum.ContextActionResult.Pass
	end
	if player:GetAttribute(RescueConfig.StateAttribute) ~= RescueConfig.StateHealthy then
		showFeedback("You cannot carry anyone while incapacitated.", "warning")
		return Enum.ContextActionResult.Sink
	end
	carryToggleEvent:FireServer()
	return Enum.ContextActionResult.Sink
end

ContextActionService:BindActionAtPriority(
	CARRY_ACTION,
	carryAction,
	true,
	Enum.ContextActionPriority.Medium.Value,
	Enum.KeyCode.T,
	Enum.KeyCode.ButtonY
)
bindViewport()

for _, attribute in
	{
		RescueConfig.StateAttribute,
		RescueConfig.CatchCountAttribute,
		RescueConfig.BandageCountAttribute,
		RescueConfig.CarryingUserIdAttribute,
	}
do
	table.insert(connections, player:GetAttributeChangedSignal(attribute):Connect(redraw))
end

table.insert(
	connections,
	UserInputService.LastInputTypeChanged:Connect(function()
		redraw()
	end)
)

script.Destroying:Connect(function()
	if viewportConnection then
		viewportConnection:Disconnect()
	end
	for _, connection in connections do
		connection:Disconnect()
	end
	ContextActionService:UnbindAction(CARRY_ACTION)
	pcall(function()
		StarterGui:SetCore("ResetButtonCallback", true)
	end)
	if screen.Parent then
		screen:Destroy()
	end
end)

redraw()
