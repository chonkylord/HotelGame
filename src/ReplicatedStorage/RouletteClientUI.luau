--!strict
-- Client presentation module for the Room 2 fate table. It locally enables its
-- E prompt, renders the hotel-branded wheel, animates the server-chosen face,
-- and keeps the four-minute cooldown off every other player's screen.

local AssetService = game:GetService("AssetService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ClassConfig = require(ReplicatedStorage:WaitForChild("ClassDefinitions"))
local RouletteConfig = require(ReplicatedStorage:WaitForChild("RouletteConfig"))

local remotes = ReplicatedStorage:WaitForChild(RouletteConfig.RemotesFolder)
local openEvent = remotes:WaitForChild(RouletteConfig.OpenEvent) :: RemoteEvent
local spinEvent = remotes:WaitForChild(RouletteConfig.SpinEvent) :: RemoteEvent
local resultEvent = remotes:WaitForChild(RouletteConfig.ResultEvent) :: RemoteEvent

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GUI_NAME = "FateRouletteHUD"
local INK = Color3.fromRGB(38, 30, 25)
local DEEP_INK = Color3.fromRGB(15, 13, 12)
local PAPER = Color3.fromRGB(219, 202, 157)
local PAPER_LIGHT = Color3.fromRGB(235, 220, 178)
local PAPER_DARK = Color3.fromRGB(154, 126, 77)
local BLOOD = Color3.fromRGB(111, 38, 32)
local MOSS = Color3.fromRGB(53, 75, 57)
local MUTED = Color3.fromRGB(143, 126, 101)
local CURSE = Color3.fromRGB(139, 47, 39)
local GOOD = Color3.fromRGB(56, 91, 65)

for _, existing in playerGui:GetChildren() do
	if existing.Name == GUI_NAME then
		existing:Destroy()
	end
end

local function corner(object: GuiObject, pixels: number)
	local value = Instance.new("UICorner")
	value.CornerRadius = UDim.new(0, pixels)
	value.Parent = object
end

local function stroke(object: GuiObject, color: Color3, thickness: number, transparency: number?)
	local value = Instance.new("UIStroke")
	value.Color = color
	value.Thickness = thickness
	value.Transparency = transparency or 0
	value.LineJoinMode = Enum.LineJoinMode.Round
	value.Parent = object
end

local screen = Instance.new("ScreenGui")
screen.Name = GUI_NAME
screen.DisplayOrder = 40
screen.IgnoreGuiInset = true
screen.ResetOnSpawn = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

-- The only persistent piece: visible during a cooldown, and only while this
-- local player is Superman.
local cooldown = Instance.new("Frame")
cooldown.Name = "SupermanCooldown"
cooldown.AnchorPoint = Vector2.new(1, 0)
cooldown.BackgroundColor3 = PAPER
cooldown.BackgroundTransparency = 0.02
cooldown.BorderSizePixel = 0
cooldown.Position = UDim2.new(1, -24, 0, 24)
cooldown.Size = UDim2.fromOffset(238, 58)
cooldown.Visible = false
corner(cooldown, 2)
stroke(cooldown, INK, 2, 0.05)
cooldown.Parent = screen

local cooldownRule = Instance.new("Frame")
cooldownRule.BackgroundColor3 = BLOOD
cooldownRule.BorderSizePixel = 0
cooldownRule.Size = UDim2.fromOffset(5, 58)
cooldownRule.Parent = cooldown

local cooldownTitle = Instance.new("TextLabel")
cooldownTitle.BackgroundTransparency = 1
cooldownTitle.Font = Enum.Font.GothamBold
cooldownTitle.Position = UDim2.fromOffset(18, 8)
cooldownTitle.Size = UDim2.fromOffset(206, 19)
cooldownTitle.Text = "FATE RESETS // 04:00"
cooldownTitle.TextColor3 = INK
cooldownTitle.TextSize = 15
cooldownTitle.TextXAlignment = Enum.TextXAlignment.Left
cooldownTitle.Parent = cooldown

local cooldownEffect = Instance.new("TextLabel")
cooldownEffect.BackgroundTransparency = 1
cooldownEffect.Font = Enum.Font.Garamond
cooldownEffect.Position = UDim2.fromOffset(18, 29)
cooldownEffect.Size = UDim2.fromOffset(206, 19)
cooldownEffect.Text = ""
cooldownEffect.TextColor3 = BLOOD
cooldownEffect.TextSize = 15
cooldownEffect.TextXAlignment = Enum.TextXAlignment.Left
cooldownEffect.Parent = cooldown

local overlay = Instance.new("TextButton")
overlay.Name = "Overlay"
overlay.Active = true
overlay.AutoButtonColor = false
overlay.BackgroundColor3 = Color3.new(0, 0, 0)
overlay.BackgroundTransparency = 0.2
overlay.BorderSizePixel = 0
overlay.Modal = true
overlay.Size = UDim2.fromScale(1, 1)
overlay.Text = ""
overlay.Visible = false
overlay.Parent = screen

local vignette = Instance.new("UIGradient")
vignette.Color = ColorSequence.new(DEEP_INK, Color3.fromRGB(45, 35, 27))
vignette.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.02),
	NumberSequenceKeypoint.new(0.5, 0.42),
	NumberSequenceKeypoint.new(1, 0.02),
})
vignette.Parent = overlay

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.BackgroundColor3 = DEEP_INK
panel.BorderSizePixel = 0
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(720, 720)
corner(panel, 3)
stroke(panel, PAPER_DARK, 2, 0.1)
panel.Parent = overlay

local panelScale = Instance.new("UIScale")
panelScale.Parent = panel

local innerLine = Instance.new("Frame")
innerLine.BackgroundTransparency = 1
innerLine.Position = UDim2.fromOffset(7, 7)
innerLine.Size = UDim2.new(1, -14, 1, -14)
corner(innerLine, 2)
stroke(innerLine, Color3.fromRGB(86, 68, 48), 1, 0.25)
innerLine.Parent = panel

local header = Instance.new("TextLabel")
header.BackgroundTransparency = 1
header.Font = Enum.Font.Garamond
header.Position = UDim2.fromOffset(60, 18)
header.Size = UDim2.new(1, -120, 0, 39)
header.Text = "THE HOTEL'S HIDDEN LOT"
header.TextColor3 = PAPER_LIGHT
header.TextSize = 32
header.TextXAlignment = Enum.TextXAlignment.Center
header.Parent = panel

local subheader = Instance.new("TextLabel")
subheader.BackgroundTransparency = 1
subheader.Font = Enum.Font.Garamond
subheader.Position = UDim2.fromOffset(34, 57)
subheader.Size = UDim2.new(1, -68, 0, 22)
subheader.Text = "ROOM II  ·  EIGHT NAMES  ·  ONE DEBT"
subheader.TextColor3 = PAPER_DARK
subheader.TextSize = 15
subheader.TextXAlignment = Enum.TextXAlignment.Center
subheader.Parent = panel

local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.AutoButtonColor = false
closeButton.BackgroundColor3 = Color3.fromRGB(48, 39, 32)
closeButton.BorderSizePixel = 0
closeButton.Position = UDim2.new(1, -58, 0, 24)
closeButton.Size = UDim2.fromOffset(30, 30)
closeButton.Font = Enum.Font.GothamBold
closeButton.Text = "×"
closeButton.TextColor3 = PAPER_DARK
closeButton.TextSize = 22
corner(closeButton, 2)
closeButton.Parent = panel

local paperShadow = Instance.new("Frame")
paperShadow.AnchorPoint = Vector2.new(0.5, 0)
paperShadow.BackgroundColor3 = Color3.new(0, 0, 0)
paperShadow.BackgroundTransparency = 0.48
paperShadow.BorderSizePixel = 0
paperShadow.Position = UDim2.new(0.5, 7, 0, 96)
paperShadow.Size = UDim2.fromOffset(446, 446)
corner(paperShadow, 223)
paperShadow.Parent = panel

local wheel = Instance.new("Frame")
wheel.Name = "Wheel"
wheel.AnchorPoint = Vector2.new(0.5, 0)
wheel.BackgroundColor3 = PAPER
wheel.BorderSizePixel = 0
wheel.ClipsDescendants = true
wheel.Position = UDim2.new(0.5, 0, 0, 90)
wheel.Size = UDim2.fromOffset(446, 446)
corner(wheel, 223)
stroke(wheel, INK, 7, 0)
wheel.Parent = panel

-- Render a real eight-slice wheel into one image. Each pixel belongs to one
-- pie sector, so there are no rotated rectangles or off-centre spokes that can
-- cross one another. The muted palette keeps every slice on aged paper.
local wheelPaper = Instance.new("ImageLabel")
wheelPaper.Name = "PaperSectors"
wheelPaper.BackgroundTransparency = 1
wheelPaper.Size = UDim2.fromScale(1, 1)
wheelPaper.ZIndex = 1
wheelPaper.Parent = wheel

local wheelEditableImage: EditableImage? = nil
local imageCreated, imageError = pcall(function()
	local imageSize = 448
	local center = (imageSize - 1) / 2
	local radius = center
	local segmentAngle = math.pi * 2 / #RouletteConfig.Outcomes
	local halfSegment = segmentAngle / 2
	local segmentColors: { Color3 } = {
		Color3.fromRGB(214, 198, 153),
		Color3.fromRGB(203, 174, 111),
		Color3.fromRGB(164, 178, 157),
		Color3.fromRGB(193, 151, 105),
		Color3.fromRGB(159, 172, 138),
		Color3.fromRGB(136, 151, 113),
		Color3.fromRGB(151, 128, 140),
		Color3.fromRGB(165, 108, 91),
	}
	local pixels = buffer.create(imageSize * imageSize * 4)

	for y = 0, imageSize - 1 do
		for x = 0, imageSize - 1 do
			local dx = x - center
			local dy = y - center
			local distance = math.sqrt(dx * dx + dy * dy)
			local offset = (y * imageSize + x) * 4

			if distance <= radius then
				local angle = math.atan2(dx, -dy)
				if angle < 0 then
					angle += math.pi * 2
				end
				local shiftedAngle = (angle + halfSegment) % (math.pi * 2)
				local sectorIndex = math.floor(shiftedAngle / segmentAngle) + 1
				local angleInsideSector = shiftedAngle % segmentAngle
				local boundaryDistance = math.min(angleInsideSector, segmentAngle - angleInsideSector)
					* math.max(distance, 1)
				local onDivider = boundaryDistance <= 1.65
				local onInnerRing = math.abs(distance - (radius - 16)) <= 1.2

				local color = if onDivider or onInnerRing then INK else segmentColors[sectorIndex]
				local hash = (x * 19 + y * 37 + (x * y) % 97) % 17
				local grain = if onDivider or onInnerRing then 0 else hash - 8
				local edgeAge = if onDivider or onInnerRing
					then 0
					else math.floor(math.max(0, distance / radius - 0.7) * 34)
				local speckle = if not onDivider and not onInnerRing and (x * 13 + y * 29) % 307 == 0 then 28 else 0

				buffer.writeu8(
					pixels,
					offset,
					math.clamp(math.floor(color.R * 255 + grain - edgeAge - speckle), 0, 255)
				)
				buffer.writeu8(
					pixels,
					offset + 1,
					math.clamp(math.floor(color.G * 255 + grain - edgeAge - speckle), 0, 255)
				)
				buffer.writeu8(
					pixels,
					offset + 2,
					math.clamp(math.floor(color.B * 255 + grain - edgeAge - speckle), 0, 255)
				)
				buffer.writeu8(pixels, offset + 3, 255)
			else
				buffer.writeu8(pixels, offset + 3, 0)
			end
		end
	end

	local editableImage = AssetService:CreateEditableImage({ Size = Vector2.new(imageSize, imageSize) })
	editableImage:WritePixelsBuffer(Vector2.zero, Vector2.new(imageSize, imageSize), pixels)
	wheelEditableImage = editableImage
	wheelPaper.ImageContent = Content.fromObject(editableImage)
end)

if not imageCreated then
	warn("[RouletteClientUI] paper sector render failed: " .. tostring(imageError))
end

screen.Destroying:Connect(function()
	local editableImage = wheelEditableImage
	if editableImage then
		editableImage:Destroy()
		wheelEditableImage = nil
	end
end)

-- Uneven translucent stains make the wheel read as a physical sheet of old
-- paper rather than a clean digital disc.
local function addStain(position: UDim2, size: number, color: Color3, transparency: number)
	local stain = Instance.new("Frame")
	stain.BackgroundColor3 = color
	stain.BackgroundTransparency = transparency
	stain.BorderSizePixel = 0
	stain.Position = position
	stain.Size = UDim2.fromOffset(size, size)
	stain.ZIndex = 2
	corner(stain, size)
	stain.Parent = wheel
end
addStain(UDim2.fromOffset(24, 71), 104, Color3.fromRGB(98, 70, 43), 0.9)
addStain(UDim2.fromOffset(305, 42), 126, Color3.fromRGB(111, 54, 40), 0.92)
addStain(UDim2.fromOffset(326, 294), 94, Color3.fromRGB(67, 76, 53), 0.91)
addStain(UDim2.fromOffset(45, 316), 132, Color3.fromRGB(85, 58, 37), 0.93)

local wheelInset = Instance.new("Frame")
wheelInset.AnchorPoint = Vector2.new(0.5, 0.5)
wheelInset.BackgroundTransparency = 1
wheelInset.Position = UDim2.fromScale(0.5, 0.5)
wheelInset.Size = UDim2.fromOffset(414, 414)
corner(wheelInset, 207)
stroke(wheelInset, Color3.fromRGB(92, 67, 43), 2, 0.15)
wheelInset.ZIndex = 5
wheelInset.Parent = wheel

-- Four centred diameters form all eight boundaries. Unlike a rotated
-- half-frame, every divider shares the wheel's exact centre and cannot wander
-- into another sector.
for dividerIndex = 0, 3 do
	local divider = Instance.new("Frame")
	divider.AnchorPoint = Vector2.new(0.5, 0.5)
	divider.BackgroundColor3 = INK
	divider.BackgroundTransparency = 0.04
	divider.BorderSizePixel = 0
	divider.Position = UDim2.fromScale(0.5, 0.5)
	divider.Rotation = 22.5 + dividerIndex * 45
	divider.Size = UDim2.fromOffset(3, 414)
	divider.ZIndex = 3
	divider.Parent = wheel
end

for index = 1, #RouletteConfig.Outcomes do
	local angle = (index - 1) * (360 / #RouletteConfig.Outcomes)
	local radians = math.rad(angle)

	local outcome = RouletteConfig.Outcomes[index]
	local face = Instance.new("TextLabel")
	face.AnchorPoint = Vector2.new(0.5, 0.5)
	face.BackgroundTransparency = 1
	face.BorderSizePixel = 0
	face.Position = UDim2.new(0.5, math.sin(radians) * 139, 0.5, -math.cos(radians) * 139)
	face.Rotation = if angle > 90 and angle < 270 then angle + 180 else angle
	face.Size = UDim2.fromOffset(132, 38)
	face.Font = Enum.Font.Garamond
	face.Text = outcome.shortLabel
	face.TextColor3 = if outcome.good then INK else BLOOD
	face.TextSize = 18
	face.TextStrokeTransparency = 1
	face.ZIndex = 4
	face.Parent = wheel

	local sigil = Instance.new("TextLabel")
	sigil.AnchorPoint = Vector2.new(0.5, 0.5)
	sigil.BackgroundTransparency = 1
	sigil.Position = UDim2.new(0.5, math.sin(radians) * 184, 0.5, -math.cos(radians) * 184)
	sigil.Rotation = face.Rotation
	sigil.Size = UDim2.fromOffset(34, 24)
	sigil.Font = Enum.Font.Garamond
	sigil.Text = if outcome.good then "✦" else "X"
	sigil.TextColor3 = if outcome.good then MOSS else BLOOD
	sigil.TextSize = 18
	sigil.ZIndex = 4
	sigil.Parent = wheel
end

for tick = 1, 32 do
	local angle = (tick - 1) * (360 / 32)
	local radians = math.rad(angle)
	local mark = Instance.new("Frame")
	mark.AnchorPoint = Vector2.new(0.5, 0.5)
	mark.BackgroundColor3 = INK
	mark.BackgroundTransparency = if tick % 4 == 1 then 0.05 else 0.46
	mark.BorderSizePixel = 0
	mark.Position = UDim2.new(0.5, math.sin(radians) * 204, 0.5, -math.cos(radians) * 204)
	mark.Rotation = angle
	mark.Size = UDim2.fromOffset(if tick % 4 == 1 then 3 else 2, if tick % 4 == 1 then 13 else 7)
	mark.ZIndex = 5
	mark.Parent = wheel
end

local medallion = Instance.new("Frame")
medallion.AnchorPoint = Vector2.new(0.5, 0.5)
medallion.BackgroundColor3 = Color3.fromRGB(174, 145, 90)
medallion.BorderSizePixel = 0
medallion.Position = UDim2.fromScale(0.5, 0.5)
medallion.Size = UDim2.fromOffset(104, 104)
medallion.ZIndex = 6
corner(medallion, 52)
stroke(medallion, INK, 3, 0.05)
medallion.Parent = wheel

local pin = Instance.new("Frame")
pin.AnchorPoint = Vector2.new(0.5, 0.5)
pin.BackgroundColor3 = BLOOD
pin.BorderSizePixel = 0
pin.Position = UDim2.fromScale(0.5, 0.5)
pin.Size = UDim2.fromOffset(14, 14)
pin.ZIndex = 8
corner(pin, 7)
stroke(pin, INK, 2, 0)
pin.Parent = medallion

local pointer = Instance.new("TextLabel")
pointer.AnchorPoint = Vector2.new(0.5, 0)
pointer.BackgroundTransparency = 1
pointer.Position = UDim2.new(0.5, 0, 0, 75)
pointer.Size = UDim2.fromOffset(52, 49)
pointer.Font = Enum.Font.GothamBold
pointer.Text = "▼"
pointer.TextColor3 = BLOOD
pointer.TextSize = 43
pointer.TextStrokeColor3 = PAPER_LIGHT
pointer.TextStrokeTransparency = 0
pointer.ZIndex = 8
pointer.Parent = panel

local resultCard = Instance.new("Frame")
resultCard.Name = "ResultCard"
resultCard.BackgroundColor3 = Color3.fromRGB(55, 45, 37)
resultCard.BorderSizePixel = 0
resultCard.Position = UDim2.fromOffset(62, 551)
resultCard.Size = UDim2.new(1, -124, 0, 62)
corner(resultCard, 2)
stroke(resultCard, PAPER_DARK, 1, 0.15)
resultCard.Parent = panel

local resultTitle = Instance.new("TextLabel")
resultTitle.BackgroundTransparency = 1
resultTitle.Font = Enum.Font.Garamond
resultTitle.Position = UDim2.fromOffset(18, 8)
resultTitle.Size = UDim2.new(1, -36, 0, 27)
resultTitle.Text = "THE PAPER KNOWS YOUR NAME"
resultTitle.TextColor3 = PAPER_LIGHT
resultTitle.TextSize = 20
resultTitle.TextXAlignment = Enum.TextXAlignment.Center
resultTitle.Parent = resultCard

local resultDescription = Instance.new("TextLabel")
resultDescription.BackgroundTransparency = 1
resultDescription.Font = Enum.Font.Garamond
resultDescription.Position = UDim2.fromOffset(18, 35)
resultDescription.Size = UDim2.new(1, -36, 0, 18)
resultDescription.Text = "The pointer grants five favors and keeps three debts."
resultDescription.TextColor3 = MUTED
resultDescription.TextSize = 15
resultDescription.TextXAlignment = Enum.TextXAlignment.Center
resultDescription.Parent = resultCard

local spinButton = Instance.new("TextButton")
spinButton.Name = "SpinButton"
spinButton.AutoButtonColor = false
spinButton.BackgroundColor3 = BLOOD
spinButton.BorderSizePixel = 0
spinButton.Position = UDim2.new(0.5, -165, 0, 626)
spinButton.Size = UDim2.fromOffset(330, 46)
spinButton.Font = Enum.Font.Garamond
spinButton.Modal = true
spinButton.Text = "TURN THE HIDDEN LOT"
spinButton.TextColor3 = PAPER_LIGHT
spinButton.TextSize = 20
corner(spinButton, 2)
stroke(spinButton, PAPER_DARK, 2, 0.1)
spinButton.Parent = panel

local mouseHint = Instance.new("TextLabel")
mouseHint.BackgroundTransparency = 1
mouseHint.Font = Enum.Font.GothamMedium
mouseHint.Position = UDim2.fromOffset(80, 681)
mouseHint.Size = UDim2.new(1, -160, 0, 18)
mouseHint.Text = "CURSOR RELEASED  ·  CLICK TO TURN  ·  ESC TO CLOSE"
mouseHint.TextColor3 = PAPER_DARK
mouseHint.TextSize = 11
mouseHint.TextXAlignment = Enum.TextXAlignment.Center
mouseHint.Parent = panel

local currentTable: Instance? = nil
local isOpen = false
local waitingForServer = false
local spinning = false
local wheelRotation = 0
local previousCameraMode = player.CameraMode
local previousMouseIcon = UserInputService.MouseIconEnabled
local previousMouseBehavior = UserInputService.MouseBehavior
local previousCrosshairEnabled: boolean? = nil
local MOUSE_RELEASE_BINDING = "FateRouletteMouseRelease"

local function isSuperman(): boolean
	return ClassConfig.hasClass(player, ClassConfig.SUPERMAN)
end

local function secondsText(seconds: number): string
	local whole = math.max(0, math.ceil(seconds))
	return string.format("%02d:%02d", whole // 60, whole % 60)
end

local function readyAt(): number
	local value = player:GetAttribute(RouletteConfig.NextRollAttribute)
	return if typeof(value) == "number" then value else 0
end

local function remaining(): number
	return RouletteConfig.remaining(Workspace:GetServerTimeNow(), readyAt())
end

local function currentOutcome(): RouletteConfig.Outcome?
	local id = player:GetAttribute(RouletteConfig.EffectIdAttribute)
	return if typeof(id) == "string" then RouletteConfig.findOutcome(id) else nil
end

local function spinnerForPrompt(instance: Instance): Instance?
	local node: Instance? = instance
	while node and node ~= Workspace do
		if CollectionService:HasTag(node, RouletteConfig.TableTag) then
			return node
		end
		node = node.Parent
	end
	return nil
end

local function applyPrompt(instance: Instance)
	if instance:IsA("ProximityPrompt") then
		local spinner = spinnerForPrompt(instance)
		instance.Enabled = isSuperman()
			and instance:IsDescendantOf(Workspace)
			and spinner ~= nil
			and spinner:GetAttribute(RouletteConfig.UnlockedAttribute) == true
	end
end

local function refreshPrompts()
	for _, instance in CollectionService:GetTagged(RouletteConfig.PromptTag) do
		applyPrompt(instance)
	end
end

CollectionService:GetInstanceAddedSignal(RouletteConfig.PromptTag):Connect(function(instance: Instance)
	task.defer(applyPrompt, instance)
end)

local function refreshScale()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	panelScale.Scale = math.clamp(math.min(viewport.X / 860, viewport.Y / 780), 0.62, 1)
end

local function refreshSpinButton()
	if spinning or waitingForServer then
		spinButton.Active = false
		spinButton.BackgroundColor3 = Color3.fromRGB(99, 88, 73)
		spinButton.TextColor3 = MUTED
		spinButton.Text = if spinning then "FATE IS TURNING..." else "CALLING THE DESK..."
		return
	end

	local left = remaining()
	if left > 0 then
		spinButton.Active = false
		spinButton.BackgroundColor3 = Color3.fromRGB(99, 88, 73)
		spinButton.TextColor3 = MUTED
		spinButton.Text = "FATE RESETS IN " .. secondsText(left)
	else
		spinButton.Active = true
		spinButton.BackgroundColor3 = BLOOD
		spinButton.TextColor3 = PAPER_LIGHT
		spinButton.Text = "TURN THE HIDDEN LOT"
	end
end

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

local function closeWheel()
	if not isOpen then
		return
	end
	isOpen = false
	currentTable = nil
	overlay.Visible = false
	restoreMouse()
end

local function showExistingEffect()
	local outcome = currentOutcome()
	local expires = player:GetAttribute(RouletteConfig.EffectExpiresAttribute)
	if outcome and typeof(expires) == "number" and expires > Workspace:GetServerTimeNow() then
		resultTitle.Text = (if outcome.good then "ABILITY // " else "CURSE // ") .. string.upper(outcome.name)
		resultTitle.TextColor3 = if outcome.good then GOOD else CURSE
		resultDescription.Text = outcome.description
	else
		resultTitle.Text = "THE PAPER KNOWS YOUR NAME"
		resultTitle.TextColor3 = PAPER_LIGHT
		resultDescription.Text = "The pointer grants five favors and keeps three debts."
	end
end

local function openWheel(payload: any)
	if not isSuperman() or typeof(payload) ~= "table" then
		return
	end
	local tableInstance = payload.table
	if typeof(tableInstance) ~= "Instance" or not tableInstance:IsDescendantOf(Workspace) then
		return
	end

	currentTable = tableInstance
	waitingForServer = false
	if not isOpen then
		isOpen = true
		releaseMouse()
	end
	showExistingEffect()
	refreshSpinButton()
	refreshScale()
	overlay.Visible = true
end

openEvent.OnClientEvent:Connect(openWheel)

local function animateResult(payload: any)
	local index = math.floor(tonumber(payload.index) or 0)
	local outcome = RouletteConfig.Outcomes[index]
	if not outcome then
		waitingForServer = false
		refreshSpinButton()
		return
	end

	waitingForServer = false
	spinning = true
	refreshSpinButton()
	resultTitle.Text = "THE NAMES ARE TURNING"
	resultTitle.TextColor3 = PAPER_LIGHT
	resultDescription.Text = "The hotel has already marked one slice."

	local faces = #RouletteConfig.Outcomes
	local desiredModulo = (360 - (index - 1) * (360 / faces)) % 360
	local currentModulo = wheelRotation % 360
	local delta = (desiredModulo - currentModulo) % 360
	local target = wheelRotation + 5 * 360 + delta
	wheelRotation = target

	local tween = TweenService:Create(wheel, TweenInfo.new(4.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Rotation = target,
	})
	tween:Play()

	task.spawn(function()
		tween.Completed:Wait()
		wheelRotation = desiredModulo
		wheel.Rotation = desiredModulo
		spinning = false
		resultTitle.Text = (if outcome.good then "ABILITY // " else "CURSE // ") .. string.upper(outcome.name)
		resultTitle.TextColor3 = if outcome.good then GOOD else CURSE
		resultDescription.Text = outcome.description .. "  Active for four minutes."
		refreshSpinButton()
	end)
end

resultEvent.OnClientEvent:Connect(function(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	if payload.ok ~= true then
		waitingForServer = false
		spinning = false
		resultTitle.Text = "THE DESK REFUSES THE SPIN"
		resultTitle.TextColor3 = CURSE
		resultDescription.Text = tostring(payload.reason or "The wheel stays still.")
		refreshSpinButton()
		return
	end
	animateResult(payload)
end)

spinButton.MouseButton1Click:Connect(function()
	if not isOpen or waitingForServer or spinning or remaining() > 0 then
		return
	end
	waitingForServer = true
	refreshSpinButton()
	spinEvent:FireServer()
end)

closeButton.MouseButton1Click:Connect(closeWheel)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed or not isOpen then
		return
	end
	if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
		closeWheel()
	end
end)

local function refreshClassEntitlement()
	refreshPrompts()
	if not isSuperman() then
		closeWheel()
	end
end

player:GetAttributeChangedSignal(ClassConfig.ATTRIBUTE):Connect(refreshClassEntitlement)
player:GetAttributeChangedSignal(ClassConfig.ADMIN_ALL_CLASSES_ATTRIBUTE):Connect(refreshClassEntitlement)

player.CharacterAdded:Connect(function()
	closeWheel()
	task.defer(refreshPrompts)
end)

local updateAccumulator = 0
RunService.RenderStepped:Connect(function(deltaTime: number)
	updateAccumulator += deltaTime
	if updateAccumulator < 0.1 then
		return
	end
	updateAccumulator = 0

	refreshScale()
	refreshPrompts()
	local left = remaining()
	local outcome = currentOutcome()
	cooldown.Visible = isSuperman() and left > 0
	cooldownTitle.Text = "FATE RESETS // " .. secondsText(left)
	cooldownEffect.Text = if outcome then outcome.name else "The room card is blank"
	if isOpen then
		refreshSpinButton()
		local tableInstance = currentTable
		if not tableInstance or not tableInstance:IsDescendantOf(Workspace) then
			closeWheel()
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local anchor = if tableInstance:IsA("Model")
			then tableInstance.PrimaryPart or tableInstance:FindFirstChildWhichIsA("BasePart", true)
			else if tableInstance:IsA("BasePart") then tableInstance else nil
		if not (root and root:IsA("BasePart") and anchor) then
			closeWheel()
			return
		end
		if (root.Position - anchor.Position).Magnitude > RouletteConfig.InteractionDistance + 7 then
			closeWheel()
		end
	end
end)

refreshPrompts()
refreshScale()

return true
