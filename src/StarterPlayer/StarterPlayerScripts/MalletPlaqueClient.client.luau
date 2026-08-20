--!strict
--[[
	The notice that hangs over the mallet when you are not allowed to lift it.

	Same brass-over-lacquer sign as the round plaque in RoundTimerClient, and
	deliberately so: the hotel already speaks in engraved signage, so a refusal
	that arrives as a brass notice screwed above the thing you touched reads as
	part of the building rather than as a system message. The palette, the bevel,
	the rivets, the Antique header and the Garamond body are all the same
	vocabulary at the same sizes.

	Two differences from the round plaque, both because this one is in the world:

	  * it is a BillboardGui adorned to the mallet, not a ScreenGui, so it sits
	    over the object it is talking about;
	  * its Size is pure pixel offset, which for a BillboardGui means a constant
	    size on screen rather than one that shrinks with distance. The plaque is
	    a paragraph, not a marker — it has to stay readable, and the prompt that
	    triggers it only reaches nine studs anyway.

	This draws and nothing else. The server decides who may lift the mallet and
	fires the reason; there is no client -> server direction on the remote, so
	nothing here can hand anybody a mallet.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local DisplayCaseConfig = require(ReplicatedStorage:WaitForChild("DisplayCaseConfig"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotes = ReplicatedStorage:WaitForChild(DisplayCaseConfig.RemotesFolder)
local refusedEvent = remotes:WaitForChild(DisplayCaseConfig.RefusalEvent) :: RemoteEvent

local GUI_NAME = "MalletPlaque"

-- Lifted wholesale from RoundTimerClient. Two signs in one hotel that are
-- nearly the same brass would look like a mistake; the same brass looks like a
-- building.
local BRASS_LIGHT = Color3.fromRGB(201, 171, 111)
local BRASS = Color3.fromRGB(139, 111, 62)
local BRASS_DEEP = Color3.fromRGB(74, 57, 30)
local PANEL = Color3.fromRGB(47, 28, 25)
local PANEL_MID = Color3.fromRGB(36, 21, 19)
local PANEL_DEEP = Color3.fromRGB(23, 13, 12)
local ENGRAVED = Color3.fromRGB(224, 212, 189)
local ENGRAVED_SOFT = Color3.fromRGB(199, 185, 159)
local BLOOD = Color3.fromRGB(227, 122, 96)

local PLAQUE_WIDTH = 344
local PLAQUE_HEIGHT = 78

-- Where it floats, and where it starts from. Three studs clears both the mallet
-- and the ProximityPrompt bubble hanging off it at the nine studs the prompt
-- reaches, and lands about eye level for someone standing at the table. The
-- plaque rises the last third of a stud as it fades in, which is the difference
-- between a sign appearing and a sign being noticed.
local RESTING_LIFT = 3
local ENTRY_LIFT = 2.65

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

--[[
	Engrave at the authored size, but never off the edge of the plaque.

	The refusal line as written measures 290px inside a 304px label — it fits,
	with fourteen pixels to spare. That is close enough that a reworded line
	silently wraps to a second row the label has no height for and loses its
	bottom half. TextScaled plus a maximum is the pair that holds: the cap keeps
	the current copy at exactly the size it was designed at, and anything longer
	shrinks to fit instead of being cut.
]]
local function engrave(label: TextLabel, size: number)
	label.TextSize = size
	label.TextScaled = true
	label.TextWrapped = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = size
	limit.MinTextSize = 11
	limit.Parent = label
end

for _, existing in ipairs(playerGui:GetChildren()) do
	if existing.Name == GUI_NAME then
		existing:Destroy()
	end
end

-- Build ------------------------------------------------------------------------

local billboard = Instance.new("BillboardGui")
billboard.Name = GUI_NAME
billboard.AlwaysOnTop = true
billboard.Enabled = false
billboard.LightInfluence = 0
billboard.MaxDistance = 60
billboard.ResetOnSpawn = false
billboard.Size = UDim2.fromOffset(PLAQUE_WIDTH, PLAQUE_HEIGHT)
billboard.StudsOffsetWorldSpace = Vector3.new(0, RESTING_LIFT, 0)
billboard.Parent = playerGui

-- One CanvasGroup around the whole sign, so the fade is a single property
-- rather than a tween per frame, stroke and label.
local group = Instance.new("CanvasGroup")
group.Name = "Fade"
group.BackgroundTransparency = 1
group.GroupTransparency = 1
group.Size = UDim2.fromScale(1, 1)
group.Parent = billboard

local plaque = Instance.new("Frame")
plaque.Name = "Plaque"
plaque.BackgroundColor3 = BRASS
plaque.BorderSizePixel = 0
plaque.Size = UDim2.fromScale(1, 1)
corner(plaque, 7)
stroke(plaque, BRASS_DEEP, 2)
plaque.Parent = group

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

--[[
	The rivets and engraved rules sit level with the header rather than at the
	middle of the field, which is where the round plaque puts them.

	That plaque's middle holds five numerals with room either side. This one
	holds a sentence across the full width, and a rule reaching inward at that
	height would run straight through the words.
]]
local HEADER_ROW = 11

local function rivet(xScale: number, xOffset: number)
	local head = Instance.new("Frame")
	head.Name = "Rivet"
	head.AnchorPoint = Vector2.new(0.5, 0.5)
	head.BackgroundColor3 = BRASS_LIGHT
	head.BorderSizePixel = 0
	head.Position = UDim2.new(xScale, xOffset, 0, HEADER_ROW)
	head.Size = UDim2.fromOffset(6, 6)
	corner(head, 3)
	stroke(head, BRASS_DEEP, 1)
	head.Parent = field
end

rivet(0, 12)
rivet(1, -12)

local function rule(xScale: number, xOffset: number, pointsRight: boolean)
	local line = Instance.new("Frame")
	line.Name = "Rule"
	line.AnchorPoint = Vector2.new(if pointsRight then 0 else 1, 0.5)
	line.BackgroundColor3 = ENGRAVED_SOFT
	line.BackgroundTransparency = 0.55
	line.BorderSizePixel = 0
	line.Position = UDim2.new(xScale, xOffset, 0, HEADER_ROW)
	line.Size = UDim2.fromOffset(26, 1)
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

-- Antique for the header and Garamond for the body, for exactly the reasons
-- RoundTimerClient sets out: Antique is the heaviest serif available and holds
-- at label size on dark lacquer, Garamond carries the line underneath it where
-- there is room for its contrast.
local header = Instance.new("TextLabel")
header.Name = "Header"
header.AnchorPoint = Vector2.new(0.5, 0.5)
header.BackgroundTransparency = 1
header.Font = Enum.Font.Antique
header.Position = UDim2.new(0.5, 0, 0, HEADER_ROW)
header.Size = UDim2.new(1, -70, 0, 17)
header.Text = ""
header.TextColor3 = BLOOD
header.Parent = field
engrave(header, 15)
stroke(header, PANEL_DEEP, 1.5, 0.25)

local line = Instance.new("TextLabel")
line.Name = "Line"
line.AnchorPoint = Vector2.new(0.5, 0)
line.BackgroundTransparency = 1
line.Font = Enum.Font.Garamond
line.Position = UDim2.new(0.5, 0, 0, 24)
line.Size = UDim2.new(1, -22, 0, 30)
line.Text = ""
line.TextColor3 = ENGRAVED
line.Parent = field
engrave(line, 21)
-- A dark outline, not a glow: the words should read as cut into the lacquer.
stroke(line, PANEL_DEEP, 1.5, 0.35)

-- Show --------------------------------------------------------------------------

local ACCENT: { [string]: Color3 } = {
	warn = BLOOD,
	calm = ENGRAVED_SOFT,
}

local fadeIn = TweenInfo.new(DisplayCaseConfig.RefusalFadeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local fadeOut = TweenInfo.new(DisplayCaseConfig.RefusalFadeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

-- Bumped on every notice. A second refusal while the first is still up has to
-- cancel the first one's pending fade, or the new plaque disappears on the old
-- one's timer.
local showing = 0

local function hide(revision: number)
	if revision ~= showing then
		return
	end
	local tween = TweenService:Create(group, fadeOut, { GroupTransparency = 1 })
	tween:Play()
	-- Only Enabled goes off. The Adornee is left pointing at whatever it was
	-- last hung on, which costs nothing and saves the next notice a frame of
	-- the plaque appearing at the origin before it is re-adorned.
	tween.Completed:Connect(function()
		if revision == showing then
			billboard.Enabled = false
		end
	end)
end

local function show(adornee: BasePart, refusal: DisplayCaseConfig.Refusal)
	showing += 1
	local revision = showing

	header.Text = refusal.header
	header.TextColor3 = ACCENT[refusal.accent] or BLOOD
	line.Text = refusal.line

	billboard.Adornee = adornee
	billboard.Enabled = true
	billboard.StudsOffsetWorldSpace = Vector3.new(0, ENTRY_LIFT, 0)
	group.GroupTransparency = 1
	TweenService:Create(group, fadeIn, { GroupTransparency = 0 }):Play()
	TweenService:Create(billboard, fadeIn, { StudsOffsetWorldSpace = Vector3.new(0, RESTING_LIFT, 0) }):Play()

	task.delay(DisplayCaseConfig.RefusalSeconds, function()
		hide(revision)
	end)
end

refusedEvent.OnClientEvent:Connect(function(adornee: any, reason: any)
	-- The remote is server-authored, but a client can fire OnClientEvent on
	-- itself in some setups and this costs two lines.
	if typeof(adornee) ~= "Instance" or not adornee:IsA("BasePart") then
		return
	end
	local refusal = if typeof(reason) == "string" then DisplayCaseConfig.Refusals[reason] else nil
	if not refusal then
		return
	end
	show(adornee, refusal)
end)
