--!strict
--[[
	The round plaque: a brass hotel sign at the top of the screen counting down
	Joel's hunt and stand-down windows.

	JoelService publishes two attributes — the phase, and the server time it ends
	at — and this derives the seconds locally. Nothing replicates between
	transitions, and every screen in the server reads the same number to the
	frame without a remote firing.

	Where it sits is load-bearing rather than decorative. The plaque is on screen
	for the whole round, so it takes the top centre outright and the two things
	that used to share that space were moved down by its height: the clue
	announcement banner in ClueClientUI and the first-stay objective card in
	OnboardingClient, both shifted by the same amount so they keep the stacking
	they already had with each other. The Superman cooldown keeps the top right
	it was already sitting in and is not touched.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local JoelConfig = require(ReplicatedStorage:WaitForChild("JoelConfig"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local joelState = Workspace:WaitForChild(JoelConfig.StateFolder)

local GUI_NAME = "RoundTimerHUD"

-- Tarnished brass over dark lacquer: the hotel's own signage, not a game HUD.
local BRASS_LIGHT = Color3.fromRGB(201, 171, 111)
local BRASS = Color3.fromRGB(139, 111, 62)
local BRASS_DEEP = Color3.fromRGB(74, 57, 30)
local PANEL = Color3.fromRGB(47, 28, 25)
local PANEL_MID = Color3.fromRGB(36, 21, 19)
local PANEL_DEEP = Color3.fromRGB(23, 13, 12)
local ENGRAVED = Color3.fromRGB(224, 212, 189)
local ENGRAVED_SOFT = Color3.fromRGB(199, 185, 159)
local BLOOD = Color3.fromRGB(227, 122, 96)
local MOSS = Color3.fromRGB(158, 197, 148)

local PLAQUE_WIDTH = 300
local PLAQUE_HEIGHT = 74
-- Wide enough to read from across a corridor without owning the screen. It does
-- not have to dodge the Superman cooldown horizontally: that card was moved to
-- the row below this one, which is the only clearance that holds at every
-- viewport width.
local COMPACT_SCALE = 0.72
local COMPACT_WIDTH = 600
local URGENT_SECONDS = 5

type Presentation = { label: string, accent: Color3 }

-- Roblox has no letter tracking, and the engraved look lives entirely in the
-- gaps between the caps, so the spacing is written into the strings.
local PRESENTATION: { [string]: Presentation } = {
	[JoelConfig.PhaseHunt] = { label = "— H U N T I N G —", accent = BLOOD },
	[JoelConfig.PhaseRest] = { label = "— R E S T I N G —", accent = MOSS },
	[JoelConfig.PhaseDowned] = { label = "— D O W N E D —", accent = ENGRAVED_SOFT },
}

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

for _, existing in ipairs(playerGui:GetChildren()) do
	if existing.Name == GUI_NAME then
		existing:Destroy()
	end
end

local screen = Instance.new("ScreenGui")
screen.Name = GUI_NAME
-- Above the survival, rescue and case-file HUD; below the roulette and clue
-- modals, so a full-screen panel covers the plaque rather than the plaque
-- floating over the panel.
screen.DisplayOrder = 9
-- Not IgnoreGuiInset: letting Roblox's own inset push the plaque clear of the
-- topbar is the only way to be sure it never lands under the chrome on a phone
-- with a notch, where the inset is not the desktop's 36px.
screen.IgnoreGuiInset = false
screen.ResetOnSpawn = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

local plaque = Instance.new("Frame")
plaque.Name = "RoundPlaque"
plaque.AnchorPoint = Vector2.new(0.5, 0)
plaque.BackgroundColor3 = BRASS
plaque.BorderSizePixel = 0
plaque.Position = UDim2.new(0.5, 0, 0, 6)
plaque.Size = UDim2.fromOffset(PLAQUE_WIDTH, PLAQUE_HEIGHT)
plaque.Visible = false
corner(plaque, 7)
stroke(plaque, BRASS_DEEP, 2)
plaque.Parent = screen

-- Everything below is authored at one size and scaled as a unit. UIScale works
-- about the AnchorPoint, so shrinking on a phone keeps the plaque pinned to the
-- top centre instead of drifting.
local plaqueScale = Instance.new("UIScale")
plaqueScale.Parent = plaque

local sheen = Instance.new("UIGradient")
sheen.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, BRASS_LIGHT),
	ColorSequenceKeypoint.new(0.42, BRASS),
	ColorSequenceKeypoint.new(1, BRASS_DEEP),
})
sheen.Rotation = 90
sheen.Parent = plaque

local bevel = Instance.new("Frame")
bevel.Name = "Bevel"
bevel.BackgroundTransparency = 1
bevel.Position = UDim2.fromOffset(3, 3)
bevel.Size = UDim2.new(1, -6, 1, -6)
corner(bevel, 5)
stroke(bevel, BRASS_LIGHT, 1, 0.55)
bevel.Parent = plaque

local field = Instance.new("Frame")
field.Name = "Field"
field.BackgroundColor3 = PANEL
field.BorderSizePixel = 0
field.Position = UDim2.fromOffset(9, 9)
field.Size = UDim2.new(1, -18, 1, -18)
corner(field, 4)
stroke(field, BRASS_DEEP, 2)
field.Parent = plaque

local lacquer = Instance.new("UIGradient")
lacquer.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, PANEL),
	ColorSequenceKeypoint.new(0.6, PANEL_MID),
	ColorSequenceKeypoint.new(1, PANEL_DEEP),
})
lacquer.Rotation = 90
lacquer.Parent = field

local hairline = Instance.new("Frame")
hairline.Name = "Hairline"
hairline.BackgroundTransparency = 1
hairline.Position = UDim2.fromOffset(3, 3)
hairline.Size = UDim2.new(1, -6, 1, -6)
corner(hairline, 3)
stroke(hairline, BRASS, 1, 0.62)
hairline.Parent = field

local function rivet(xScale: number, xOffset: number)
	local head = Instance.new("Frame")
	head.Name = "Rivet"
	head.AnchorPoint = Vector2.new(0.5, 0.5)
	head.BackgroundColor3 = BRASS_LIGHT
	head.BorderSizePixel = 0
	head.Position = UDim2.new(xScale, xOffset, 0.5, 0)
	head.Size = UDim2.fromOffset(6, 6)
	corner(head, 3)
	stroke(head, BRASS_DEEP, 1)
	head.Parent = field
end

rivet(0, 12)
rivet(1, -12)

-- The engraved rules that run inward from each rivet toward the numerals. They
-- stop well short of a five-character time at this size.
local function rule(xScale: number, xOffset: number, pointsRight: boolean)
	local line = Instance.new("Frame")
	line.Name = "Rule"
	line.AnchorPoint = Vector2.new(if pointsRight then 0 else 1, 0.5)
	line.BackgroundColor3 = ENGRAVED_SOFT
	line.BackgroundTransparency = 0.55
	line.BorderSizePixel = 0
	line.Position = UDim2.new(xScale, xOffset, 0, 36)
	line.Size = UDim2.fromOffset(46, 1)
	line.Parent = field

	local tip = Instance.new("Frame")
	tip.Name = "Tip"
	tip.AnchorPoint = Vector2.new(0.5, 0.5)
	tip.BackgroundColor3 = ENGRAVED_SOFT
	tip.BackgroundTransparency = 0.3
	tip.BorderSizePixel = 0
	tip.Position = UDim2.fromScale(if pointsRight then 1 else 0, 0.5)
	tip.Rotation = 45
	tip.Size = UDim2.fromOffset(4, 4)
	tip.Parent = line
end

rule(0, 22, true)
rule(1, -22, false)

local header = Instance.new("TextLabel")
header.Name = "Phase"
header.AnchorPoint = Vector2.new(0.5, 0)
header.BackgroundTransparency = 1
-- Antique, not Garamond. Garamond is a thin, high-contrast face: at label size
-- on dark lacquer its hairlines drop out and the word stops reading at a glance,
-- which is the one thing this label has to do. Antique is the heaviest serif
-- available and holds its weight down at this size. The numerals keep Garamond,
-- where the size carries the letterforms and the contrast is an asset.
header.Font = Enum.Font.Antique
header.Position = UDim2.new(0.5, 0, 0, 3)
header.Size = UDim2.new(1, -34, 0, 17)
header.Text = ""
header.TextColor3 = ENGRAVED_SOFT
header.TextSize = 16
header.Parent = field
-- The same cut-into-the-lacquer outline the numerals get. On a label this small
-- it is doing legibility work, not decoration: it separates the strokes from the
-- panel behind them.
stroke(header, PANEL_DEEP, 1.5, 0.25)

local digits = Instance.new("TextLabel")
digits.Name = "Remaining"
digits.AnchorPoint = Vector2.new(0.5, 0)
digits.BackgroundTransparency = 1
digits.Font = Enum.Font.Garamond
digits.Position = UDim2.new(0.5, 0, 0, 19)
digits.Size = UDim2.new(1, -40, 0, 34)
digits.Text = "00:00"
digits.TextColor3 = ENGRAVED
digits.TextSize = 34
digits.Parent = field
-- A dark outline, not a glow: the numerals should read as cut into the lacquer.
stroke(digits, PANEL_DEEP, 1.5, 0.35)

local function timeText(seconds: number): string
	-- Ceil, so the plaque reads 00:01 for the whole of the last second and hits
	-- 00:00 exactly as the window turns over.
	local whole = math.max(0, math.ceil(seconds))
	local minutes = whole // 60
	return string.format("%02d:%02d", minutes, whole - minutes * 60)
end

local function viewportScale(): number
	local camera = Workspace.CurrentCamera
	local width = if camera then camera.ViewportSize.X else 1280
	local compact = width < COMPACT_WIDTH or (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
	return if compact then COMPACT_SCALE else 1
end

local shownPhase = ""
local shownText = ""

RunService.Heartbeat:Connect(function()
	local phase = joelState:GetAttribute(JoelConfig.CyclePhaseAttribute)
	local endsAt = joelState:GetAttribute(JoelConfig.CycleEndsAtAttribute)
	local look = if type(phase) == "string" then PRESENTATION[phase] else nil
	if not look or type(endsAt) ~= "number" then
		-- No cycle published: either the round has not started or the place has
		-- no Joel in it. An empty plaque would be a worse answer than none.
		plaque.Visible = false
		return
	end

	plaque.Visible = true

	local scale = viewportScale()
	if plaqueScale.Scale ~= scale then
		plaqueScale.Scale = scale
	end

	local serverNow = Workspace:GetServerTimeNow()
	local remaining = math.max(0, endsAt - serverNow)

	local text = timeText(remaining)
	if text ~= shownText then
		shownText = text
		digits.Text = text
	end

	if phase ~= shownPhase then
		shownPhase = phase :: string
		header.Text = look.label
		header.TextColor3 = look.accent
	end

	-- The last few seconds of either window are the only ones worth reacting to,
	-- so they are the only thing on the plaque that moves.
	if remaining <= URGENT_SECONDS then
		header.TextTransparency = 0.26 - 0.26 * math.abs(math.cos(serverNow * math.pi * 2))
	elseif header.TextTransparency ~= 0 then
		header.TextTransparency = 0
	end
end)
