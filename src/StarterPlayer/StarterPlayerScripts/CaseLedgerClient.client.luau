--!strict
--[[
	The case ledger: one button, one board.

	Three surfaces used to compete for the same screen. The first-stay objective
	card sat top-centre and overlapped the clue announcement banner; the clue
	incident-file card sat bottom-left above the survival meters; both were
	permanent, and neither could be dismissed. This replaces the two permanent
	cards with a single 54px disc in the corner that opens a board when asked.

	Nothing here is authoritative. ClueService owns the chain and writes it to
	the replicated ClueState folder; CheckInService owns the intro stage and
	writes it to the Player. This script only reads those and draws them, which
	is why it can be opened, closed and ignored without consequence.

	The clue log is assembled client-side by watching CurrentRiddle change.
	ClueState replicates only the riddle in play, not the ones already solved,
	so a player who joins mid-round starts with a partly blank ledger -- their
	entries begin from the first riddle they were present for. Closing that hole
	means ClueService publishing the solved list, which is a server change and a
	larger one than this.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ClueConfig = require(ReplicatedStorage:WaitForChild("ClueConfig"))
local OnboardingConfig = require(ReplicatedStorage:WaitForChild("OnboardingConfig"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local clueState = Workspace:WaitForChild(ClueConfig.StateFolder)

local DOCK_GUI_NAME = "CaseLedgerDock"
local BOARD_GUI_NAME = "CaseLedgerBoard"
local MOUSE_RELEASE_BINDING = "CaseLedgerMouseRelease"

-- The magnifier, drawn for this project and uploaded from the mirror. Tinting
-- is deliberately left off: the art already carries the brass and walnut, and
-- ImageColor3 would multiply it into mud.
local GLASS_IMAGE = "rbxassetid://114718117713017"

-- Paper, from the clue cards.
local INK = Color3.fromRGB(43, 36, 29)
local PAPER = Color3.fromRGB(200, 181, 135)
local PAPER_LIGHT = Color3.fromRGB(226, 211, 172)
local PAPER_DARK = Color3.fromRGB(126, 103, 68)
local BLOOD = Color3.fromRGB(112, 43, 35)
local MOSS = Color3.fromRGB(49, 67, 55)
local SHADOW = Color3.fromRGB(18, 14, 10)

-- Brass over lacquer, from the round plaque. The button wears this rather than
-- paper: the magnifier's own rim is brass and its glass is pale, and both
-- disappear against an aged-paper disc.
local BRASS_LIGHT = Color3.fromRGB(201, 171, 111)
local BRASS = Color3.fromRGB(139, 111, 62)
local BRASS_DEEP = Color3.fromRGB(74, 57, 30)
local PANEL = Color3.fromRGB(47, 28, 25)
local PANEL_DEEP = Color3.fromRGB(23, 13, 12)

local BUTTON_SIZE = 54
local DOCK_LEFT = 24
-- SurvivalHUD owns the lowest 114 pixels on this side. The old incident-file
-- card cleared it by sitting at 134 and the button inherits that clearance.
local DOCK_BOTTOM = 134
local RIBBON_HEIGHT = 28
local RIBBON_WIDTH = 320
local RIBBON_HOLD = 4.5

local BOARD_WIDTH = 600
local BOARD_HEIGHT = 456
local SHEET_TOP = 44
local SHEET_INSET = 16
local ROW_HEIGHT = 62

--[[
	Which other surfaces outrank the ledger.

	A ScreenGui that is merely Enabled is not necessarily showing anything --
	the clue and roulette screens stay enabled all round and toggle a full-screen
	child called Overlay instead -- so the ones with an overlay are asked about
	the overlay. Anything in this list showing means the dock hides and the board
	closes, which is what stops the ledger from becoming the next thing in the
	way.
]]
local BLOCKERS: { { name: string, overlay: string? } } = {
	{ name = "ClueModal", overlay = "Overlay" },
	{ name = "FateRouletteHUD", overlay = "Overlay" },
	{ name = "ProwlerNotice" },
	{ name = "DialogueUI" },
	{ name = "AdminControlPanel" },
}

local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }

for _, existing in playerGui:GetChildren() do
	if existing.Name == DOCK_GUI_NAME or existing.Name == BOARD_GUI_NAME then
		existing:Destroy()
	end
end

-- Building blocks ------------------------------------------------------------

local function corner(object: GuiObject, pixels: number)
	local value = Instance.new("UICorner")
	value.CornerRadius = UDim.new(0, pixels)
	value.Parent = object
end

-- Border mode for the same reason ClueClientUI pins it: Contextual draws around
-- every glyph on anything holding text, which closes up the letterforms.
local function stroke(object: GuiObject, color: Color3, thickness: number, transparency: number?): UIStroke
	local value = Instance.new("UIStroke")
	value.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	value.Color = color
	value.Thickness = thickness
	value.Transparency = transparency or 0
	value.LineJoinMode = Enum.LineJoinMode.Round
	value.Parent = object
	return value
end

local function gradient(parent: GuiObject, top: Color3, bottom: Color3, rotation: number)
	local value = Instance.new("UIGradient")
	value.Color = ColorSequence.new(top, bottom)
	value.Rotation = rotation
	value.Parent = parent
end

local function agedPaper(parent: GuiObject)
	local value = Instance.new("UIGradient")
	value.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, PAPER_LIGHT),
		ColorSequenceKeypoint.new(0.58, PAPER),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(184, 158, 109)),
	})
	value.Rotation = 94
	value.Parent = parent
end

local function label(parent: GuiObject, font: Enum.Font, size: number, color: Color3): TextLabel
	local value = Instance.new("TextLabel")
	value.BackgroundTransparency = 1
	value.Font = font
	value.Text = ""
	value.TextColor3 = color
	value.TextSize = size
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.Parent = parent
	return value
end

local function rule(parent: GuiObject, y: number, width: number, transparency: number)
	local value = Instance.new("Frame")
	value.BackgroundColor3 = PAPER_DARK
	value.BackgroundTransparency = transparency
	value.BorderSizePixel = 0
	value.Position = UDim2.fromOffset(0, y)
	value.Size = UDim2.fromOffset(width, 1)
	value.Parent = parent
end

-- Dock -----------------------------------------------------------------------

local dockGui = Instance.new("ScreenGui")
dockGui.Name = DOCK_GUI_NAME
-- Above every meter (SackHud 4, SurvivalHUD 6, RescueHUD 8, RoundTimer 9) and
-- well below the CRT overlay at 45, so static still washes over it.
dockGui.DisplayOrder = 30
dockGui.IgnoreGuiInset = false
dockGui.ResetOnSpawn = false
dockGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
dockGui.Parent = playerGui

local buttonShadow = Instance.new("Frame")
buttonShadow.Name = "ButtonShadow"
buttonShadow.AnchorPoint = Vector2.new(0, 1)
buttonShadow.BackgroundColor3 = SHADOW
buttonShadow.BackgroundTransparency = 0.45
buttonShadow.BorderSizePixel = 0
buttonShadow.Position = UDim2.new(0, DOCK_LEFT + 3, 1, -(DOCK_BOTTOM - 4))
buttonShadow.Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE)
corner(buttonShadow, 999)
buttonShadow.Parent = dockGui

local button = Instance.new("TextButton")
button.Name = "CaseLedgerButton"
button.Active = true
button.AnchorPoint = Vector2.new(0, 1)
button.AutoButtonColor = false
button.BackgroundColor3 = PANEL
button.BorderSizePixel = 0
button.Position = UDim2.new(0, DOCK_LEFT, 1, -DOCK_BOTTOM)
button.Rotation = -3
button.Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE)
button.Text = ""
corner(button, 999)
gradient(button, PANEL, PANEL_DEEP, 90)
local buttonEdge = stroke(button, BRASS, 2, 0.1)
button.Parent = dockGui

local buttonScale = Instance.new("UIScale")
buttonScale.Parent = button

-- The round plaque wears four brass rivets and this disc used to copy them, but
-- at 54px they landed as four pale dots in a square around the glass -- read as
-- an artefact rather than as hardware. The brass rim carries the same idea
-- without competing with the one thing the button is trying to say.

local glass = Instance.new("ImageLabel")
glass.Name = "Magnifier"
glass.AnchorPoint = Vector2.new(0.5, 0.5)
glass.BackgroundTransparency = 1
glass.Image = GLASS_IMAGE
glass.Position = UDim2.fromScale(0.5, 0.5)
-- Sized against the disc, not the rim: the art has its own transparent margin,
-- so the glass reads smaller than this number suggests. Much past this and it
-- starts crowding the brass edge.
glass.Size = UDim2.fromScale(0.78, 0.78)
glass.ZIndex = 2
glass.Parent = button

--[[
	The wax seal is the unread mark, not decoration.

	Permanently present it would be a red dot in the corner of the eye for the
	whole round, which is exactly the kind of thing this rework exists to remove.
	It appears when the hotel writes something into the ledger while the board is
	shut, and it goes when the player opens it.
]]
local seal = Instance.new("Frame")
seal.Name = "UnreadSeal"
seal.AnchorPoint = Vector2.new(0.5, 0.5)
seal.BackgroundColor3 = BLOOD
seal.BorderSizePixel = 0
seal.Position = UDim2.fromScale(0.86, 0.86)
seal.Size = UDim2.fromOffset(15, 15)
seal.Visible = false
seal.ZIndex = 4
corner(seal, 999)
stroke(seal, Color3.fromRGB(78, 28, 22), 1.5)
seal.Parent = button

local ribbonShadow = Instance.new("Frame")
ribbonShadow.AnchorPoint = Vector2.new(0, 1)
ribbonShadow.BackgroundColor3 = SHADOW
ribbonShadow.BackgroundTransparency = 0.5
ribbonShadow.BorderSizePixel = 0
ribbonShadow.Position =
	UDim2.new(0, DOCK_LEFT + BUTTON_SIZE + 13, 1, -(DOCK_BOTTOM + (BUTTON_SIZE - RIBBON_HEIGHT) / 2 - 4))
ribbonShadow.Size = UDim2.fromOffset(RIBBON_WIDTH, RIBBON_HEIGHT)
ribbonShadow.Visible = false
corner(ribbonShadow, 3)
ribbonShadow.Parent = dockGui

local ribbon = Instance.new("TextLabel")
ribbon.Name = "PeekRibbon"
ribbon.AnchorPoint = Vector2.new(0, 1)
ribbon.BackgroundColor3 = PAPER
ribbon.BorderSizePixel = 0
ribbon.Font = Enum.Font.Garamond
ribbon.Position = UDim2.new(0, DOCK_LEFT + BUTTON_SIZE + 10, 1, -(DOCK_BOTTOM + (BUTTON_SIZE - RIBBON_HEIGHT) / 2))
ribbon.Rotation = -0.6
ribbon.Size = UDim2.fromOffset(RIBBON_WIDTH, RIBBON_HEIGHT)
ribbon.Text = ""
ribbon.TextColor3 = INK
ribbon.TextSize = 17
ribbon.TextTruncate = Enum.TextTruncate.AtEnd
ribbon.Visible = false
corner(ribbon, 3)
stroke(ribbon, INK, 1, 0.3)
agedPaper(ribbon)
ribbon.Parent = dockGui

local ribbonPad = Instance.new("UIPadding")
ribbonPad.PaddingLeft = UDim.new(0, 12)
ribbonPad.PaddingRight = UDim.new(0, 10)
ribbonPad.Parent = ribbon

-- Board ----------------------------------------------------------------------

local boardGui = Instance.new("ScreenGui")
boardGui.Name = BOARD_GUI_NAME
-- Under the clue modal at 41: if the hotel hands you a clue while the ledger is
-- open, the clue is the thing that matters and it should land on top.
boardGui.DisplayOrder = 38
boardGui.IgnoreGuiInset = true
boardGui.ResetOnSpawn = false
boardGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
boardGui.Parent = playerGui

local overlay = Instance.new("TextButton")
overlay.Name = "Overlay"
overlay.Active = true
overlay.AutoButtonColor = false
overlay.BackgroundColor3 = Color3.new(0, 0, 0)
overlay.BackgroundTransparency = 0.35
overlay.BorderSizePixel = 0
overlay.Modal = true
overlay.Size = UDim2.fromScale(1, 1)
overlay.Text = ""
overlay.Visible = false
overlay.Parent = boardGui

local boardShadow = Instance.new("Frame")
boardShadow.AnchorPoint = Vector2.new(0.5, 0.5)
boardShadow.BackgroundColor3 = SHADOW
boardShadow.BackgroundTransparency = 0.3
boardShadow.BorderSizePixel = 0
boardShadow.Position = UDim2.new(0.5, 9, 0.5, 11)
boardShadow.Size = UDim2.fromOffset(BOARD_WIDTH, BOARD_HEIGHT)
corner(boardShadow, 8)
boardShadow.Parent = overlay

local boardShadowScale = Instance.new("UIScale")
boardShadowScale.Parent = boardShadow

local board = Instance.new("Frame")
board.Name = "Clipboard"
board.AnchorPoint = Vector2.new(0.5, 0.5)
board.BackgroundColor3 = PANEL
board.BorderSizePixel = 0
board.Position = UDim2.fromScale(0.5, 0.5)
board.Rotation = -0.4
board.Size = UDim2.fromOffset(BOARD_WIDTH, BOARD_HEIGHT)
corner(board, 8)
gradient(board, PANEL, PANEL_DEEP, 90)
stroke(board, BRASS, 2.5, 0.08)
board.Parent = overlay

local boardScale = Instance.new("UIScale")
boardScale.Parent = board

-- The brass clip that makes it a clipboard rather than a window.
local clip = Instance.new("Frame")
clip.AnchorPoint = Vector2.new(0.5, 0)
clip.BackgroundColor3 = BRASS
clip.BorderSizePixel = 0
clip.Position = UDim2.new(0.5, 0, 0, -11)
clip.Size = UDim2.fromOffset(104, 26)
clip.ZIndex = 6
corner(clip, 4)
gradient(clip, BRASS_LIGHT, BRASS_DEEP, 90)
stroke(clip, BRASS_DEEP, 1.5)
clip.Parent = board

local clipMouth = Instance.new("Frame")
clipMouth.AnchorPoint = Vector2.new(0.5, 1)
clipMouth.BackgroundColor3 = PANEL_DEEP
clipMouth.BorderSizePixel = 0
clipMouth.Position = UDim2.new(0.5, 0, 1, -4)
clipMouth.Size = UDim2.fromOffset(72, 4)
clipMouth.ZIndex = 7
corner(clipMouth, 2)
clipMouth.Parent = clip

local closeButton = Instance.new("TextButton")
closeButton.Name = "Close"
closeButton.AutoButtonColor = false
closeButton.BackgroundTransparency = 1
closeButton.Font = Enum.Font.GothamBold
closeButton.Position = UDim2.new(1, -42, 0, 8)
closeButton.Size = UDim2.fromOffset(30, 30)
closeButton.Text = "×"
closeButton.TextColor3 = BRASS_LIGHT
closeButton.TextSize = 24
closeButton.ZIndex = 8
closeButton.Parent = board

local sheet = Instance.new("Frame")
sheet.Name = "Sheet"
sheet.BackgroundColor3 = PAPER
sheet.BorderSizePixel = 0
sheet.Position = UDim2.fromOffset(SHEET_INSET, SHEET_TOP)
sheet.Size = UDim2.fromOffset(BOARD_WIDTH - SHEET_INSET * 2, BOARD_HEIGHT - SHEET_TOP - SHEET_INSET)
sheet.ZIndex = 2
corner(sheet, 3)
stroke(sheet, INK, 1, 0.3)
agedPaper(sheet)
sheet.Parent = board

local SHEET_WIDTH = BOARD_WIDTH - SHEET_INSET * 2
local SHEET_HEIGHT = BOARD_HEIGHT - SHEET_TOP - SHEET_INSET
local CONTENT_WIDTH = SHEET_WIDTH - 56
local PAGE_TOP = 62

--[[
	Swallows clicks that land on the board.

	The overlay behind it closes the ledger when clicked, which is the behaviour
	everyone expects of a dimmed backdrop -- but a Frame is not Active, so
	without this every click on the board itself would fall straight through to
	the backdrop and shut the thing the player was reading.
]]
local clickShield = Instance.new("TextButton")
clickShield.Name = "ClickShield"
clickShield.Active = true
clickShield.AutoButtonColor = false
clickShield.BackgroundTransparency = 1
clickShield.Size = UDim2.fromScale(1, 1)
clickShield.Text = ""
clickShield.ZIndex = 1
clickShield.Parent = board

local spine = Instance.new("Frame")
spine.BackgroundColor3 = BLOOD
spine.BorderSizePixel = 0
spine.Size = UDim2.new(0, 3, 1, 0)
spine.ZIndex = 3
spine.Parent = sheet

local sheetTitle = label(sheet, Enum.Font.SpecialElite, 19, BLOOD)
sheetTitle.Position = UDim2.fromOffset(28, 14)
sheetTitle.Size = UDim2.fromOffset(CONTENT_WIDTH, 24)
sheetTitle.Text = "THE GRAND HOTEL  /  CASE LEDGER"
sheetTitle.ZIndex = 3

local hint = label(sheet, Enum.Font.RobotoMono, 10, PAPER_DARK)
hint.Position = UDim2.fromOffset(28, 38)
hint.Size = UDim2.fromOffset(CONTENT_WIDTH, 12)
hint.Text = "J OR ESC TO CLOSE"
hint.TextXAlignment = Enum.TextXAlignment.Right
hint.ZIndex = 3

-- Folder tabs, sitting on the lacquer above the sheet.
local tabs: { [string]: TextButton } = {}
local activePage = "Objective"

local function makeTab(name: string, text: string, x: number): TextButton
	local tab = Instance.new("TextButton")
	tab.Name = name .. "Tab"
	tab.AutoButtonColor = false
	tab.BackgroundColor3 = PAPER
	tab.BorderSizePixel = 0
	tab.Font = Enum.Font.RobotoMono
	tab.Position = UDim2.fromOffset(x, 16)
	tab.Size = UDim2.fromOffset(132, 30)
	tab.Text = text
	tab.TextColor3 = INK
	tab.TextSize = 12
	tab.ZIndex = 3
	corner(tab, 3)
	stroke(tab, INK, 1, 0.35)
	tab.Parent = board
	tabs[name] = tab
	return tab
end

makeTab("Objective", "OBJECTIVE", SHEET_INSET + 12)
makeTab("Clues", "CLUE LOG", SHEET_INSET + 152)

local objectivePage = Instance.new("Frame")
objectivePage.Name = "ObjectivePage"
objectivePage.BackgroundTransparency = 1
objectivePage.Position = UDim2.fromOffset(28, PAGE_TOP)
objectivePage.Size = UDim2.fromOffset(CONTENT_WIDTH, SHEET_HEIGHT - PAGE_TOP - SHEET_INSET)
objectivePage.ZIndex = 3
objectivePage.Parent = sheet

local objectiveHeading = label(objectivePage, Enum.Font.RobotoMono, 11, PAPER_DARK)
objectiveHeading.Position = UDim2.fromOffset(0, 0)
objectiveHeading.Size = UDim2.fromOffset(CONTENT_WIDTH, 14)
objectiveHeading.Text = "CURRENT OBJECTIVE"
objectiveHeading.ZIndex = 3

local objectiveText = label(objectivePage, Enum.Font.Garamond, 27, INK)
objectiveText.Position = UDim2.fromOffset(0, 18)
objectiveText.Size = UDim2.fromOffset(CONTENT_WIDTH, 34)
objectiveText.ZIndex = 3

rule(objectivePage, 62, CONTENT_WIDTH, 0.4)

local entryLabel = label(objectivePage, Enum.Font.RobotoMono, 13, INK)
entryLabel.Position = UDim2.fromOffset(0, 74)
entryLabel.Size = UDim2.fromOffset(200, 18)
entryLabel.ZIndex = 3

local digitsLabel = label(objectivePage, Enum.Font.RobotoMono, 18, MOSS)
digitsLabel.Position = UDim2.fromOffset(CONTENT_WIDTH - 220, 71)
digitsLabel.Size = UDim2.fromOffset(220, 22)
digitsLabel.TextXAlignment = Enum.TextXAlignment.Right
digitsLabel.ZIndex = 3

local riddleHeading = label(objectivePage, Enum.Font.RobotoMono, 11, PAPER_DARK)
riddleHeading.Position = UDim2.fromOffset(0, 104)
riddleHeading.Size = UDim2.fromOffset(CONTENT_WIDTH, 14)
riddleHeading.Text = "THE ENTRY IN FRONT OF YOU"
riddleHeading.ZIndex = 3

local riddleText = label(objectivePage, Enum.Font.SpecialElite, 19, INK)
riddleText.Position = UDim2.fromOffset(0, 124)
riddleText.Size = UDim2.fromOffset(CONTENT_WIDTH, 120)
riddleText.TextWrapped = true
riddleText.TextYAlignment = Enum.TextYAlignment.Top
riddleText.ZIndex = 3

local statusLabel = label(objectivePage, Enum.Font.RobotoMono, 13, PAPER_DARK)
statusLabel.Position = UDim2.fromOffset(0, 254)
statusLabel.Size = UDim2.fromOffset(CONTENT_WIDTH, 18)
statusLabel.ZIndex = 3

local cluesPage = Instance.new("ScrollingFrame")
cluesPage.Name = "CluesPage"
cluesPage.Active = true
cluesPage.AutomaticCanvasSize = Enum.AutomaticSize.Y
cluesPage.BackgroundTransparency = 1
cluesPage.BorderSizePixel = 0
cluesPage.CanvasSize = UDim2.fromOffset(0, 0)
cluesPage.Position = UDim2.fromOffset(28, PAGE_TOP)
cluesPage.ScrollBarImageColor3 = PAPER_DARK
cluesPage.ScrollBarThickness = 4
cluesPage.Size = UDim2.fromOffset(CONTENT_WIDTH, SHEET_HEIGHT - PAGE_TOP - SHEET_INSET)
cluesPage.Visible = false
cluesPage.ZIndex = 3
cluesPage.Parent = sheet

local cluesLayout = Instance.new("UIListLayout")
cluesLayout.Padding = UDim.new(0, 6)
cluesLayout.SortOrder = Enum.SortOrder.LayoutOrder
cluesLayout.Parent = cluesPage

-- State ----------------------------------------------------------------------

local isOpen = false
local ribbonRevision = 0
-- Whether what is on the ribbon right now is pinned (stays until the state
-- that put it there goes away) or transient (fades on its own timer).
local ribbonPinned = false
local knownRiddles: { [number]: string } = {}
local lastDigits = ""
local previousCameraMode = player.CameraMode
local previousMouseIcon = UserInputService.MouseIconEnabled
local previousMouseBehavior = UserInputService.MouseBehavior
local previousCrosshairEnabled: boolean? = nil

local function attributeNumber(name: string, fallback: number): number
	local value = clueState:GetAttribute(name)
	return if typeof(value) == "number" then math.floor(value) else fallback
end

local function attributeString(name: string): string?
	local value = clueState:GetAttribute(name)
	return if typeof(value) == "string" and value ~= "" then value else nil
end

local function chainLength(): number
	return math.max(1, attributeNumber(ClueConfig.ChainLengthAttribute, ClueConfig.ChainLength))
end

local function nodeIndex(): number
	return math.clamp(attributeNumber(ClueConfig.NodeIndexAttribute, 1), 1, chainLength())
end

local function digitsKnown(): string
	local value = clueState:GetAttribute(ClueConfig.DigitsKnownAttribute)
	return if typeof(value) == "string" then value else string.rep("_", chainLength())
end

local function spacedDigits(masked: string): string
	local out = table.create(#masked)
	for index = 1, #masked do
		out[index] = string.sub(masked, index, index)
	end
	return table.concat(out, "  ")
end

local function phaseName(): string
	return attributeString(ClueConfig.PhaseAttribute) or ClueConfig.PhaseHunt
end

local function escapeRemaining(): number?
	local endsAt = clueState:GetAttribute(ClueConfig.EscapeEndsAtAttribute)
	if phaseName() ~= ClueConfig.PhaseEscape or typeof(endsAt) ~= "number" then
		return nil
	end
	return math.max(0, math.ceil(endsAt - Workspace:GetServerTimeNow()))
end

local function clock(seconds: number): string
	return `{math.floor(seconds / 60)}:{string.format("%02d", seconds % 60)}`
end

--[[
	What the player is being asked to do, in one line.

	The intro owns the question until it is over -- following Noel's directions
	is the objective, and the clue chain has not started -- so its stage wins
	whenever it yields a line. After that the phase does.
]]
local function currentObjective(): string
	local intro = OnboardingConfig.objectiveFor(player:GetAttribute(OnboardingConfig.ATTRIBUTE))
	if intro then
		return intro
	end
	local phase = phaseName()
	if phase == ClueConfig.PhaseVault then
		return "Open the vault"
	elseif phase == ClueConfig.PhaseEscape then
		return "Get out of the hotel"
	elseif phase == ClueConfig.PhaseWon then
		return "You are out"
	end
	return `Find the {chainLength()} marks`
end

-- Behaviour ------------------------------------------------------------------

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

local function blockingGuiOpen(): boolean
	for _, blocker in BLOCKERS do
		local gui = playerGui:FindFirstChild(blocker.name)
		if gui and gui:IsA("ScreenGui") and gui.Enabled then
			local overlayName = blocker.overlay
			if not overlayName then
				return true
			end
			local child = gui:FindFirstChild(overlayName)
			if child and child:IsA("GuiObject") and child.Visible then
				return true
			end
		end
	end
	return false
end

local function showRibbon(text: string, color: Color3, pinned: boolean)
	ribbonRevision += 1
	local revision = ribbonRevision
	ribbon.Text = text
	ribbon.TextColor3 = color
	ribbon.TextTransparency = 0
	ribbon.BackgroundTransparency = 0
	ribbon.Visible = true
	ribbonShadow.BackgroundTransparency = 0.5
	ribbonShadow.Visible = true
	ribbonPinned = pinned
	if pinned then
		return
	end
	task.delay(RIBBON_HOLD, function()
		if revision ~= ribbonRevision then
			return
		end
		local fade = TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		TweenService:Create(ribbon, fade, { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		local shadowFade = TweenService:Create(ribbonShadow, fade, { BackgroundTransparency = 1 })
		shadowFade:Play()
		shadowFade.Completed:Once(function()
			if revision == ribbonRevision then
				ribbon.Visible = false
				ribbonShadow.Visible = false
			end
		end)
	end)
end

local function hideRibbon()
	ribbonRevision += 1
	ribbonPinned = false
	ribbon.Visible = false
	ribbonShadow.Visible = false
end

local function markUnread()
	if isOpen then
		return
	end
	-- seal.Visible is the whole of the unread state; nothing else tracks it.
	seal.Visible = true
	seal.Size = UDim2.fromOffset(15, 15)
	TweenService
		:Create(seal, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.fromOffset(17, 17),
		})
		:Play()
end

local function refreshTabs()
	for name, tab in tabs do
		local active = name == activePage
		tab.BackgroundColor3 = if active then PAPER_LIGHT else PAPER_DARK
		tab.TextColor3 = if active then INK else PAPER_LIGHT
		tab.Size = UDim2.fromOffset(132, if active then 32 else 28)
		tab.ZIndex = if active then 4 else 3
	end
	objectivePage.Visible = activePage == "Objective"
	cluesPage.Visible = activePage == "Clues"
end

--[[
	One row per mark in the chain.

	A row the player has never been shown is not left blank -- blank reads as
	"nothing here" -- it is redacted, which reads as "something here you have not
	earned". The digit column fills in from DigitsKnown regardless, because the
	server has already told every client that much.
]]
local function rebuildClueRows()
	for _, child in cluesPage:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local length = chainLength()
	local index = nodeIndex()
	local digits = digitsKnown()
	local phase = phaseName()

	for entry = 1, length do
		local row = Instance.new("Frame")
		row.Name = `Entry{entry}`
		row.BackgroundColor3 = PAPER_LIGHT
		row.BackgroundTransparency = 0.55
		row.BorderSizePixel = 0
		row.LayoutOrder = entry
		row.Size = UDim2.fromOffset(CONTENT_WIDTH - 8, ROW_HEIGHT)
		row.ZIndex = 3
		corner(row, 2)
		row.Parent = cluesPage

		local solved = entry < index or phase ~= ClueConfig.PhaseHunt
		local current = entry == index and phase == ClueConfig.PhaseHunt

		local marker = Instance.new("Frame")
		marker.BackgroundColor3 = if solved then MOSS elseif current then BLOOD else PAPER_DARK
		marker.BorderSizePixel = 0
		marker.Size = UDim2.fromOffset(3, ROW_HEIGHT)
		marker.ZIndex = 4
		marker.Parent = row

		local numeral = label(row, Enum.Font.RobotoMono, 13, PAPER_DARK)
		numeral.Position = UDim2.fromOffset(14, 8)
		numeral.Size = UDim2.fromOffset(50, 16)
		numeral.Text = (ROMAN[entry] or tostring(entry)) .. "."
		numeral.ZIndex = 4

		local digit = string.sub(digits, entry, entry)
		local digitLabel = label(row, Enum.Font.RobotoMono, 22, if digit == "_" then PAPER_DARK else MOSS)
		digitLabel.Position = UDim2.fromOffset(14, 26)
		digitLabel.Size = UDim2.fromOffset(50, 26)
		digitLabel.Text = digit
		digitLabel.ZIndex = 4

		local body = label(row, Enum.Font.SpecialElite, 15, INK)
		body.Position = UDim2.fromOffset(72, 10)
		body.Size = UDim2.fromOffset(CONTENT_WIDTH - 96, ROW_HEIGHT - 20)
		body.TextTruncate = Enum.TextTruncate.AtEnd
		body.TextWrapped = true
		body.TextYAlignment = Enum.TextYAlignment.Top
		body.ZIndex = 4

		local known = knownRiddles[entry]
		if known then
			body.Text = known
			if current then
				local flag = label(row, Enum.Font.RobotoMono, 10, BLOOD)
				flag.AnchorPoint = Vector2.new(1, 1)
				flag.Position = UDim2.new(1, -10, 1, -6)
				flag.Size = UDim2.fromOffset(90, 12)
				flag.Text = "IN HAND"
				flag.TextXAlignment = Enum.TextXAlignment.Right
				flag.ZIndex = 4
			end
		else
			body.Text = ""
			-- Two uneven censor bars: a redaction, not a loading placeholder.
			for bar = 1, 2 do
				local censor = Instance.new("Frame")
				censor.BackgroundColor3 = INK
				censor.BackgroundTransparency = 0.12
				censor.BorderSizePixel = 0
				censor.Position = UDim2.fromOffset(72, 16 + (bar - 1) * 20)
				censor.Rotation = if bar == 1 then -0.4 else 0.3
				censor.Size = UDim2.fromOffset(if bar == 1 then CONTENT_WIDTH - 130 else CONTENT_WIDTH - 210, 13)
				censor.ZIndex = 4
				corner(censor, 1)
				censor.Parent = row
			end
		end
	end
end

local function refreshBoard()
	objectiveText.Text = currentObjective()
	entryLabel.Text = `ENTRY {string.format("%02d", nodeIndex())} / {string.format("%02d", chainLength())}`
	digitsLabel.Text = spacedDigits(digitsKnown())

	local riddle = attributeString(ClueConfig.CurrentRiddleAttribute)
	riddleText.Text = riddle or "The paper is blank. For now."

	local remaining = escapeRemaining()
	if remaining then
		statusLabel.Text = `JOEL RISES IN  /  {clock(remaining)}`
		statusLabel.TextColor3 = BLOOD
	elseif clueState:GetAttribute(ClueConfig.ExitCodeKnownAttribute) == true then
		statusLabel.Text = "STATUS  /  THE EXIT CODE IS KNOWN"
		statusLabel.TextColor3 = MOSS
	else
		statusLabel.Text = `STATUS  /  {string.upper(phaseName())}`
		statusLabel.TextColor3 = PAPER_DARK
	end

	sheetTitle.Text = if phaseName() == ClueConfig.PhaseWon
		then "CASE CLOSED  /  SURVIVOR RECORDED"
		else "THE GRAND HOTEL  /  CASE LEDGER"
	spine.BackgroundColor3 = if phaseName() == ClueConfig.PhaseWon then MOSS else BLOOD
end

--[[
	Redraw everything the open board is showing, rows included.

	Kept apart from refreshBoard because the render loop calls that one ten times
	a second to tick the escape clock, and rebuilding five rows at that rate
	would throw away the player's scroll position on every tick. Rows only need
	rebuilding when the chain actually moves, so only the state signals call this.
]]
local function refreshOpenBoard()
	if not isOpen then
		return
	end
	refreshBoard()
	if cluesPage.Visible then
		rebuildClueRows()
	end
end

local function refreshScale()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	local scale =
		math.clamp(math.min((viewport.X - 32) / BOARD_WIDTH, (viewport.Y - 32) / BOARD_HEIGHT), 0.5, 1)
	boardScale.Scale = scale
	boardShadowScale.Scale = scale

	-- The ribbon is the first thing to give up room on a narrow screen; on a
	-- phone it would otherwise run off the right edge or over the sack counter.
	local available = viewport.X - (DOCK_LEFT + BUTTON_SIZE + 10) - 200
	local width = math.clamp(available, 150, RIBBON_WIDTH)
	ribbon.Size = UDim2.fromOffset(width, RIBBON_HEIGHT)
	ribbonShadow.Size = UDim2.fromOffset(width, RIBBON_HEIGHT)
end

--[[
	Forward declaration.

	Closing the board has to put the pinned ribbon back, but what belongs on the
	ribbon depends on the clue log, which is built further down. Declaring it
	here keeps the reading order (open/close, then log, then ribbon) without
	setOpen reaching for a global that does not exist yet.
]]
local refreshPinnedRibbon: () -> ()

local function setOpen(open: boolean)
	if open == isOpen then
		return
	end
	isOpen = open
	overlay.Visible = open
	if open then
		seal.Visible = false
		refreshScale()
		refreshBoard()
		rebuildClueRows()
		releaseMouse()
		board.Size = UDim2.fromOffset(BOARD_WIDTH, BOARD_HEIGHT)
		boardScale.Scale = boardScale.Scale * 0.96
		TweenService
			:Create(boardScale, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Scale = boardScale.Scale / 0.96,
			})
			:Play()
	else
		restoreMouse()
		-- The dock was hidden while the board was up; whatever should be pinned
		-- has to be put back now that it is visible again.
		refreshPinnedRibbon()
	end
end

--[[
	Fold each riddle into the log as the hotel hands it over.

	CurrentRiddle is the only riddle ClueState carries, so this is the one chance
	to keep a copy -- once the chain moves on, the previous text is gone from the
	client's view of the world entirely.
]]
local function recordRiddle(announce: boolean)
	local riddle = attributeString(ClueConfig.CurrentRiddleAttribute)
	if not riddle then
		return
	end
	local index = nodeIndex()
	if knownRiddles[index] == riddle then
		return
	end
	knownRiddles[index] = riddle
	-- The bootstrap pass seeds whatever the round is already on. That is not
	-- news to the player who just joined, so it neither stamps the seal nor
	-- takes the ribbon away from the intro.
	if not announce then
		return
	end
	markUnread()
	if not isOpen then
		showRibbon(`ENTRY {string.format("%02d", index)}  ·  a new page`, INK, false)
	end
	if cluesPage.Visible then
		rebuildClueRows()
	end
end

local function onDigitsChanged()
	local digits = digitsKnown()
	if digits == lastDigits then
		return
	end
	local hadDigits = lastDigits ~= ""
	lastDigits = digits
	if hadDigits then
		markUnread()
		if not isOpen then
			showRibbon(`MARK FOUND  ·  {spacedDigits(digits)}`, MOSS, false)
		end
	end
	refreshOpenBoard()
end

--[[
	The ribbon's resting state.

	During the intro it is pinned: a first-time player has not learned that the
	button exists yet, so the objective has to be legible without opening
	anything. That was the one job the old top-centre card did well, and this
	keeps it at a twelfth of the area. During the escape it is pinned to the
	countdown, for the same reason -- nobody should have to open a ledger to find
	out how long they have. Otherwise it stays out of the way.
]]
function refreshPinnedRibbon()
	if isOpen then
		return
	end
	local intro = OnboardingConfig.objectiveFor(player:GetAttribute(OnboardingConfig.ATTRIBUTE))
	if intro then
		showRibbon(intro, INK, true)
		return
	end
	local remaining = escapeRemaining()
	if remaining then
		showRibbon(`JOEL RISES IN  {clock(remaining)}`, BLOOD, true)
		return
	end
	-- Nothing left to pin. A transient ribbon is mid-flight and keeps its own
	-- timer; a pinned one has just lost the state that justified it, so it goes.
	if ribbonPinned then
		hideRibbon()
	end
end

-- Wiring ---------------------------------------------------------------------

button.Activated:Connect(function()
	setOpen(not isOpen)
end)
button.MouseEnter:Connect(function()
	buttonEdge.Color = BRASS_LIGHT
	TweenService:Create(buttonScale, TweenInfo.new(0.12), { Scale = 1.06 }):Play()
end)
button.MouseLeave:Connect(function()
	buttonEdge.Color = BRASS
	TweenService:Create(buttonScale, TweenInfo.new(0.12), { Scale = 1 }):Play()
end)

closeButton.MouseButton1Click:Connect(function()
	setOpen(false)
end)
overlay.MouseButton1Click:Connect(function()
	setOpen(false)
end)

for name, tab in tabs do
	tab.MouseButton1Click:Connect(function()
		activePage = name
		refreshTabs()
		if name == "Clues" then
			rebuildClueRows()
		end
	end)
end

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.J or input.KeyCode == Enum.KeyCode.DPadDown then
		if isOpen or not blockingGuiOpen() then
			setOpen(not isOpen)
		end
	elseif isOpen and (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB) then
		setOpen(false)
	end
end)

clueState:GetAttributeChangedSignal(ClueConfig.CurrentRiddleAttribute):Connect(function()
	recordRiddle(true)
	refreshOpenBoard()
end)

clueState:GetAttributeChangedSignal(ClueConfig.DigitsKnownAttribute):Connect(onDigitsChanged)

for _, attribute in
	{
		ClueConfig.ChainLengthAttribute,
		ClueConfig.NodeIndexAttribute,
		ClueConfig.PhaseAttribute,
		ClueConfig.ExitCodeKnownAttribute,
	}
do
	clueState:GetAttributeChangedSignal(attribute):Connect(function()
		refreshPinnedRibbon()
		refreshOpenBoard()
	end)
end

player:GetAttributeChangedSignal(OnboardingConfig.ATTRIBUTE):Connect(function()
	refreshPinnedRibbon()
	refreshOpenBoard()
end)

player.CharacterAdded:Connect(function()
	setOpen(false)
end)

local accumulator = 0
RunService.RenderStepped:Connect(function(delta: number)
	accumulator += delta
	if accumulator < 0.1 then
		return
	end
	accumulator = 0

	refreshScale()

	local blocked = blockingGuiOpen()
	if blocked and isOpen then
		setOpen(false)
	end
	dockGui.Enabled = not blocked and not isOpen

	if escapeRemaining() then
		refreshPinnedRibbon()
	end
	if isOpen then
		refreshBoard()
	end
end)

refreshTabs()
refreshScale()
recordRiddle(false)
lastDigits = digitsKnown()
refreshPinnedRibbon()
refreshBoard()
