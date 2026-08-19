--!strict
--[[
	Client presentation for the shared hotel clue chain. ClueService owns every
	answer, digit, phase, and deadline; this module reads the replicated case-file
	state, asks the server to grade typed answers, and frees the mouse only while
	a clue is open.

	What is left here is the part a player cannot dismiss: the clue itself when
	the hotel hands them one, and the banner announcing what somebody found. The
	always-on card that used to sit in the bottom-left corner is gone --
	CaseLedgerClient owns the standing readout now, behind a button, because two
	permanent paper cards plus a banner in the same screen was more paper than
	the screen had room for. This module still owns the state; it just no longer
	keeps a copy of it pinned to the corner.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ClueConfig = require(ReplicatedStorage:WaitForChild("ClueConfig"))

local remotes = ReplicatedStorage:WaitForChild(ClueConfig.RemotesFolder)
local openEvent = remotes:WaitForChild(ClueConfig.OpenEvent) :: RemoteEvent
local submitEvent = remotes:WaitForChild(ClueConfig.SubmitEvent) :: RemoteEvent
local resultEvent = remotes:WaitForChild(ClueConfig.ResultEvent) :: RemoteEvent
local announceEvent = remotes:WaitForChild(ClueConfig.AnnounceEvent) :: RemoteEvent

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local MODAL_GUI_NAME = "ClueModal"
local MOUSE_RELEASE_BINDING = "ClueModalMouseRelease"

local INK = Color3.fromRGB(43, 36, 29)
local PAPER = Color3.fromRGB(200, 181, 135)
local PAPER_LIGHT = Color3.fromRGB(226, 211, 172)
local PAPER_DARK = Color3.fromRGB(126, 103, 68)
local BLOOD = Color3.fromRGB(112, 43, 35)
local MOSS = Color3.fromRGB(49, 67, 55)
local SHADOW = Color3.fromRGB(18, 14, 10)

for _, existing in playerGui:GetChildren() do
	if existing.Name == MODAL_GUI_NAME then
		existing:Destroy()
	end
end

local function corner(object: GuiObject, pixels: number)
	local value = Instance.new("UICorner")
	value.CornerRadius = UDim.new(0, pixels)
	value.Parent = object
end

--[[
	Outlines the object's edge, never its text.

	UIStroke defaults to ApplyStrokeMode.Contextual, which means "border" on a
	Frame but "draw around every glyph" on a TextLabel, TextButton or TextBox.
	Every caller here is framing a panel, a field or a button, so the contextual
	default silently did the wrong thing on the three that happen to hold text —
	most visibly the announcement toast, whose 2px blood outline was thick enough
	at 21px Garamond to close up the counters of the letters and leave the banner
	looking like a solid red smear.

	Pinning Border mode fixes all of them at once and keeps the aesthetic: the
	paper cards still have their inked edge, the words on them are just words.
]]
local function stroke(object: GuiObject, color: Color3, thickness: number, transparency: number?)
	local value = Instance.new("UIStroke")
	value.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	value.Color = color
	value.Thickness = thickness
	value.Transparency = transparency or 0
	value.LineJoinMode = Enum.LineJoinMode.Round
	value.Parent = object
end

local function agedPaper(parent: GuiObject)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, PAPER_LIGHT),
		ColorSequenceKeypoint.new(0.58, PAPER),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(184, 158, 109)),
	})
	gradient.Rotation = 94
	gradient.Parent = parent
end

-- Modal ----------------------------------------------------------------------

local modalGui = Instance.new("ScreenGui")
modalGui.Name = MODAL_GUI_NAME
modalGui.DisplayOrder = 41
modalGui.IgnoreGuiInset = true
modalGui.ResetOnSpawn = false
modalGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
modalGui.Parent = playerGui

local overlay = Instance.new("TextButton")
overlay.Name = "Overlay"
overlay.Active = true
overlay.AutoButtonColor = false
overlay.BackgroundColor3 = Color3.new(0, 0, 0)
overlay.BackgroundTransparency = 0.28
overlay.BorderSizePixel = 0
overlay.Modal = true
overlay.Size = UDim2.fromScale(1, 1)
overlay.Text = ""
overlay.Visible = false
overlay.Parent = modalGui

local modalShadow = Instance.new("Frame")
modalShadow.AnchorPoint = Vector2.new(0.5, 0.5)
modalShadow.BackgroundColor3 = SHADOW
modalShadow.BackgroundTransparency = 0.26
modalShadow.BorderSizePixel = 0
modalShadow.Position = UDim2.new(0.5, 8, 0.5, 9)
modalShadow.Size = UDim2.fromOffset(610, 430)
corner(modalShadow, 8)
modalShadow.Parent = overlay

local modalShadowScale = Instance.new("UIScale")
modalShadowScale.Parent = modalShadow

local panel = Instance.new("Frame")
panel.Name = "CluePaper"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.BackgroundColor3 = PAPER
panel.BorderSizePixel = 0
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Rotation = -0.35
panel.Size = UDim2.fromOffset(610, 430)
corner(panel, 8)
stroke(panel, INK, 3, 0.04)
agedPaper(panel)
panel.Parent = overlay

local panelScale = Instance.new("UIScale")
panelScale.Parent = panel

local modalTitle = Instance.new("TextLabel")
modalTitle.BackgroundTransparency = 1
modalTitle.Font = Enum.Font.SpecialElite
modalTitle.Position = UDim2.fromOffset(42, 26)
modalTitle.Size = UDim2.fromOffset(526, 34)
modalTitle.Text = "THE GRAND HOTEL  /  INCIDENT FILE"
modalTitle.TextColor3 = BLOOD
modalTitle.TextSize = 25
modalTitle.TextXAlignment = Enum.TextXAlignment.Center
modalTitle.Parent = panel

local modalKind = Instance.new("TextLabel")
modalKind.BackgroundTransparency = 1
modalKind.Font = Enum.Font.RobotoMono
modalKind.Position = UDim2.fromOffset(42, 65)
modalKind.Size = UDim2.fromOffset(526, 18)
modalKind.Text = "CLUE  ·  READ CAREFULLY"
modalKind.TextColor3 = PAPER_DARK
modalKind.TextSize = 12
modalKind.TextXAlignment = Enum.TextXAlignment.Center
modalKind.Parent = panel

local modalRiddle = Instance.new("TextLabel")
modalRiddle.BackgroundTransparency = 1
modalRiddle.Font = Enum.Font.SpecialElite
modalRiddle.Position = UDim2.fromOffset(58, 103)
modalRiddle.Size = UDim2.fromOffset(494, 145)
modalRiddle.Text = ""
modalRiddle.TextColor3 = INK
modalRiddle.TextSize = 25
modalRiddle.TextWrapped = true
modalRiddle.TextXAlignment = Enum.TextXAlignment.Center
modalRiddle.TextYAlignment = Enum.TextYAlignment.Center
modalRiddle.Parent = panel

local answerBox = Instance.new("TextBox")
answerBox.Name = "Answer"
answerBox.BackgroundColor3 = Color3.fromRGB(235, 221, 181)
answerBox.BorderSizePixel = 0
answerBox.ClearTextOnFocus = false
answerBox.Font = Enum.Font.RobotoMono
answerBox.PlaceholderColor3 = Color3.fromRGB(124, 104, 75)
answerBox.PlaceholderText = "TYPE WHAT THE HOTEL SHOWED YOU"
answerBox.Position = UDim2.fromOffset(86, 267)
answerBox.Size = UDim2.fromOffset(438, 48)
answerBox.Text = ""
answerBox.TextColor3 = INK
answerBox.TextSize = 22
answerBox.TextXAlignment = Enum.TextXAlignment.Center
answerBox.Visible = false
corner(answerBox, 4)
stroke(answerBox, PAPER_DARK, 2, 0.15)
answerBox.Parent = panel

local resultLabel = Instance.new("TextLabel")
resultLabel.BackgroundTransparency = 1
resultLabel.Font = Enum.Font.RobotoMono
resultLabel.Position = UDim2.fromOffset(58, 323)
resultLabel.Size = UDim2.fromOffset(494, 22)
resultLabel.Text = ""
resultLabel.TextColor3 = BLOOD
resultLabel.TextSize = 13
resultLabel.TextWrapped = true
resultLabel.TextXAlignment = Enum.TextXAlignment.Center
resultLabel.Parent = panel

local submitButton = Instance.new("TextButton")
submitButton.AutoButtonColor = false
submitButton.BackgroundColor3 = BLOOD
submitButton.BorderSizePixel = 0
submitButton.Font = Enum.Font.RobotoMono
submitButton.Position = UDim2.fromOffset(194, 360)
submitButton.Size = UDim2.fromOffset(222, 43)
submitButton.Text = "SUBMIT TO THE DESK"
submitButton.TextColor3 = PAPER_LIGHT
submitButton.TextSize = 14
submitButton.Visible = false
corner(submitButton, 4)
stroke(submitButton, INK, 1, 0.18)
submitButton.Parent = panel

local closeButton = Instance.new("TextButton")
closeButton.AutoButtonColor = false
closeButton.BackgroundTransparency = 1
closeButton.Font = Enum.Font.GothamBold
closeButton.Position = UDim2.new(1, -54, 0, 18)
closeButton.Size = UDim2.fromOffset(34, 34)
closeButton.Text = "×"
closeButton.TextColor3 = INK
closeButton.TextSize = 25
closeButton.Parent = panel

-- Announcement toast --------------------------------------------------------

local toastShadow = Instance.new("Frame")
toastShadow.AnchorPoint = Vector2.new(0.5, 0)
toastShadow.BackgroundColor3 = SHADOW
toastShadow.BackgroundTransparency = 0.42
toastShadow.BorderSizePixel = 0
toastShadow.Size = UDim2.fromOffset(520, 58)
toastShadow.Visible = false
corner(toastShadow, 5)
toastShadow.Parent = modalGui

local toast = Instance.new("TextLabel")
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.BackgroundColor3 = PAPER
toast.BackgroundTransparency = 0.02
toast.BorderSizePixel = 0
-- Garamond's regular weight, unstroked, on high-contrast ink. The banner is read
-- at a glance mid-chase, so it gets a touch more size than the card body and
-- nothing else competing with the letterforms.
toast.Font = Enum.Font.Garamond
toast.Size = UDim2.fromOffset(520, 58)
toast.Text = ""
toast.TextColor3 = INK
toast.TextSize = 23
toast.TextWrapped = true
toast.Visible = false
corner(toast, 5)
-- Thin: it is the card's edge, not an outline around the words.
stroke(toast, BLOOD, 1.5, 0.25)
agedPaper(toast)
toast.Parent = modalGui

-- The round plaque owns the row above this one. Its ScreenGui lets Roblox apply
-- the topbar inset; this one cannot, because it also carries the full-screen
-- modal overlay, so the inset is added back by hand here. A constant offset
-- would sit correctly on a desktop client and underneath the plaque in a Studio
-- viewport or on a notched phone, where the inset is larger.
local BANNER_ROW = 90

local function layoutBanner()
	local top = GuiService:GetGuiInset().Y + BANNER_ROW
	toast.Position = UDim2.new(0.5, 0, 0, top)
	toastShadow.Position = UDim2.new(0.5, 4, 0, top + 5)
end

layoutBanner()
GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(layoutBanner)

-- Behaviour ------------------------------------------------------------------

local isOpen = false
local waitingForServer = false
local previousCameraMode = player.CameraMode
local previousMouseIcon = UserInputService.MouseIconEnabled
local previousMouseBehavior = UserInputService.MouseBehavior
local previousCrosshairEnabled: boolean? = nil
local toastRevision = 0

local function enforceReleasedMouse()
	player.CameraMode = Enum.CameraMode.Classic
	UserInputService.MouseIconEnabled = true
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
end

local function releaseMouse()
	previousCameraMode = player.CameraMode
	previousMouseIcon = UserInputService.MouseIconEnabled
	previousMouseBehavior = UserInputService.MouseBehavior
	local crosshair = playerGui:FindFirstChild("Crosshair")
	if crosshair and crosshair:IsA("ScreenGui") then
		previousCrosshairEnabled = crosshair.Enabled
		crosshair.Enabled = false
	else
		previousCrosshairEnabled = nil
	end
	RunService:BindToRenderStep(MOUSE_RELEASE_BINDING, Enum.RenderPriority.Last.Value, enforceReleasedMouse)
	enforceReleasedMouse()
end

local function restoreMouse()
	RunService:UnbindFromRenderStep(MOUSE_RELEASE_BINDING)
	player.CameraMode = previousCameraMode
	UserInputService.MouseIconEnabled = previousMouseIcon
	UserInputService.MouseBehavior = previousMouseBehavior
	local crosshair = playerGui:FindFirstChild("Crosshair")
	if crosshair and crosshair:IsA("ScreenGui") and previousCrosshairEnabled ~= nil then
		crosshair.Enabled = previousCrosshairEnabled
	end
end

local function closeModal()
	if not isOpen then
		return
	end
	isOpen = false
	waitingForServer = false
	if answerBox:IsFocused() then
		answerBox:ReleaseFocus()
	end
	overlay.Visible = false
	restoreMouse()
end

local function refreshScale()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	local modalScale = math.clamp(math.min((viewport.X - 24) / 610, (viewport.Y - 24) / 430), 0.48, 1)
	panelScale.Scale = modalScale
	modalShadowScale.Scale = modalScale
end

local function showToast(text: string, good: boolean)
	toastRevision += 1
	local revision = toastRevision
	toast.Text = text
	toast.TextColor3 = if good then MOSS else INK
	toast.TextTransparency = 0
	toast.BackgroundTransparency = 0.02
	toast.Visible = true
	toastShadow.BackgroundTransparency = 0.42
	toastShadow.Visible = true

	task.delay(4, function()
		if revision ~= toastRevision then
			return
		end
		local fade = TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		TweenService:Create(toast, fade, { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		local shadowFade = TweenService:Create(toastShadow, fade, { BackgroundTransparency = 1 })
		shadowFade:Play()
		shadowFade.Completed:Once(function()
			if revision == toastRevision then
				toast.Visible = false
				toastShadow.Visible = false
			end
		end)
	end)
end

local function openModal(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	local kind = payload.kind
	local riddle = payload.riddle
	if typeof(kind) ~= "string" or typeof(riddle) ~= "string" then
		return
	end

	modalKind.Text = string.upper(kind) .. "  ·  READ CAREFULLY"
	modalRiddle.Text = riddle
	resultLabel.Text = if typeof(payload.prompt) == "string" then payload.prompt else ""
	resultLabel.TextColor3 = PAPER_DARK
	answerBox.Text = ""
	local typed = kind == "Cipher" or kind == "Code"
	answerBox.Visible = typed
	submitButton.Visible = typed
	submitButton.Active = typed
	submitButton.BackgroundColor3 = BLOOD
	submitButton.Text = "SUBMIT TO THE DESK"
	waitingForServer = false
	refreshScale()

	if not isOpen then
		isOpen = true
		releaseMouse()
	end
	overlay.Visible = true
	if typed then
		task.defer(function()
			answerBox:CaptureFocus()
		end)
	end
end

openEvent.OnClientEvent:Connect(openModal)

resultEvent.OnClientEvent:Connect(function(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	waitingForServer = false
	submitButton.Active = true
	submitButton.BackgroundColor3 = BLOOD
	submitButton.Text = "SUBMIT TO THE DESK"

	local ok = payload.ok == true
	local reason = if typeof(payload.reason) == "string"
		then payload.reason
		else if ok then "The mark is yours." else "The page refuses it."
	resultLabel.Text = reason
	resultLabel.TextColor3 = if ok then MOSS else BLOOD
	if ok and typeof(payload.nextRiddle) == "string" and payload.nextRiddle ~= "" then
		modalRiddle.Text = payload.nextRiddle
		modalKind.Text = "NEXT ENTRY  ·  THE HOTEL MOVES ON"
		answerBox.Visible = false
		submitButton.Visible = false
	end
	if not isOpen then
		showToast(reason, ok)
	end
end)

announceEvent.OnClientEvent:Connect(function(payload: any)
	if typeof(payload) ~= "table" or typeof(payload.text) ~= "string" then
		return
	end
	showToast(payload.text, payload.kind == "Solved" or payload.kind == "Won")
end)

local function submitAnswer()
	if not isOpen or waitingForServer or not answerBox.Visible then
		return
	end
	waitingForServer = true
	submitButton.Active = false
	submitButton.BackgroundColor3 = PAPER_DARK
	submitButton.Text = "THE DESK IS READING..."
	submitEvent:FireServer(answerBox.Text)
end

submitButton.MouseButton1Click:Connect(submitAnswer)
answerBox.FocusLost:Connect(function(enterPressed: boolean)
	if enterPressed then
		submitAnswer()
	end
end)
closeButton.MouseButton1Click:Connect(closeModal)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed or not isOpen then
		return
	end
	if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
		closeModal()
	end
end)

player.CharacterAdded:Connect(function()
	closeModal()
end)

local scaleAccumulator = 0
RunService.RenderStepped:Connect(function(delta: number)
	scaleAccumulator += delta
	if scaleAccumulator < 0.1 then
		return
	end
	scaleAccumulator = 0
	refreshScale()
end)

refreshScale()

return true
