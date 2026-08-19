--!strict
--[[
	The notice that goes up when the door has finished holding the player in.

	Presentation only. IntroSealService decides when this is shown and owns every
	clock around it — this script draws for CARD_FADE_IN/HOLD/FADE_OUT and says
	nothing back, because the server is not waiting to hear from it.

	It is built out of Frames rather than dropped in as an image, and that is the
	whole design of the thing. A texture would have to be authored somewhere,
	uploaded, moderated, and would then be one fixed resolution stretched across
	every screen the game runs on — and the pass that produces one quickly is
	exactly the pass that produces something that looks like it was produced
	quickly. Paper does not have an even tone, a straight torn edge, evenly
	spaced blemishes, or perfectly opaque ink, so none of those appear here:

	  * the sheet is toned by three gradients crossing at unrelated angles, so no
	    part of it matches any other part
	  * its edges are ragged, built from ~150 slivers of paper of varying depth
	    that break the rectangle's silhouette
	  * the edges are darker than the middle, the way handled paper is
	  * foxing spots, grain and two fold creases are scattered by a seeded
	    generator — seeded, so the same sheet appears every time rather than a
	    fresh scramble that would give the whole thing away as generated
	  * the headline is printed three times at decreasing opacity and a pixel or
	    two apart, which is what ink spreading into a fibre does and what a
	    single crisp label conspicuously does not

	Nothing here is random at runtime and nothing is fetched. The one thing it
	does reach for is the blur, so the world behind the notice falls out of
	focus while it is up.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local OnboardingConfig = require(ReplicatedStorage:WaitForChild("OnboardingConfig"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GUI_NAME = "ProwlerNotice"
local NOTICE_TEXT = "HE IS PROWLING"

-- Design size. Everything below is authored against this and then scaled to the
-- viewport in one place, so the sheet's proportions never change with a window.
local CARD_WIDTH = 660
local CARD_HEIGHT = 392

-- Paper, in the order it ages: the lit tone, the settled tone, the shadowed
-- tone at the bottom of the sheet, and the brown that stains and foxes it.
local PAPER_HIGH = Color3.fromRGB(233, 219, 189)
local PAPER_MID = Color3.fromRGB(214, 197, 163)
local PAPER_LOW = Color3.fromRGB(186, 167, 132)
local STAIN = Color3.fromRGB(122, 92, 55)
local INK = Color3.fromRGB(26, 19, 14)
local INK_SOFT = Color3.fromRGB(74, 56, 38)

local VEIL_TARGET = 0.42
local BLUR_SIZE = 14

--[[
	A seeded generator, so this sheet is the same sheet every time.

	`math.random` would re-scatter the stains on every showing, and a player who
	sees the notice twice would watch the paper reprint itself. The constants are
	the usual 32-bit LCG pair; the quality of the randomness does not matter at
	all here, only that it is fixed and does not repeat visibly across a few
	hundred draws.
]]
local function generator(seed: number): () -> number
	local state = seed % 2147483647
	return function(): number
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
end

-- What each element fades to. The notice fades as one object, so every
-- transparency in it is driven from a single alpha rather than from its own
-- tween — 300-odd tweens would be both wasteful and, because they would not
-- land on the same frame, visibly uneven.
type Fadeable = {
	instance: Instance,
	property: string,
	target: number,
}

local fadeables: { Fadeable } = {}

local function fades(instance: Instance, property: string, target: number)
	table.insert(fadeables, { instance = instance, property = property, target = target })
end

local function setAlpha(alpha: number)
	for _, entry in fadeables do
		(entry.instance :: any)[entry.property] = 1 + (entry.target - 1) * alpha
	end
end

-- Build ------------------------------------------------------------------------

for _, existing in playerGui:GetChildren() do
	if existing.Name == GUI_NAME then
		existing:Destroy()
	end
end

local gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
-- Above the HUD, the objective card and the CRT overlay: for these seven
-- seconds the notice is the only thing on screen that matters.
gui.DisplayOrder = 70
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false
gui.Parent = playerGui

local veil = Instance.new("Frame")
veil.Name = "Veil"
veil.BackgroundColor3 = Color3.fromRGB(4, 3, 2)
veil.BackgroundTransparency = 1
veil.BorderSizePixel = 0
veil.Size = UDim2.fromScale(1, 1)
veil.ZIndex = 1
veil.Parent = gui
fades(veil, "BackgroundTransparency", VEIL_TARGET)

local holder = Instance.new("Frame")
holder.Name = "Notice"
holder.AnchorPoint = Vector2.new(0.5, 0.5)
holder.BackgroundTransparency = 1
holder.Position = UDim2.fromScale(0.5, 0.5)
holder.Size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT)
-- Nailed up crooked, because nothing is ever nailed up straight.
holder.Rotation = -1.1
holder.ZIndex = 2
holder.Parent = gui

local scale = Instance.new("UIScale")
scale.Parent = holder

-- The sheet is not flush against the dark: it throws a soft shadow, which is
-- most of what stops a flat-coloured rectangle reading as a flat-coloured
-- rectangle.
local shadow = Instance.new("Frame")
shadow.Name = "Shadow"
shadow.AnchorPoint = Vector2.new(0.5, 0.5)
shadow.BackgroundColor3 = Color3.fromRGB(6, 4, 3)
shadow.BorderSizePixel = 0
shadow.Position = UDim2.new(0.5, 5, 0.5, 9)
shadow.Size = UDim2.new(1, 30, 1, 30)
shadow.ZIndex = 2
shadow.Parent = holder
local shadowCorner = Instance.new("UICorner")
shadowCorner.CornerRadius = UDim.new(0, 14)
shadowCorner.Parent = shadow
fades(shadow, "BackgroundTransparency", 0.58)

local sheet = Instance.new("Frame")
sheet.Name = "Sheet"
sheet.BackgroundColor3 = PAPER_MID
sheet.BorderSizePixel = 0
sheet.Size = UDim2.fromScale(1, 1)
sheet.ZIndex = 3
sheet.Parent = holder
fades(sheet, "BackgroundTransparency", 0)

--[[
	The ragged edge.

	Slivers of paper standing proud of the sheet's straight boundary, each a
	different depth, so the silhouette against the dark is broken rather than
	ruled. They only ever add paper — there is no way to cut a notch out of a
	frame — but a torn edge reads from its high points, and the darkening pass
	below sits over the join so the two do not separate.

	They carry the tone of the edge they stand on rather than the sheet's
	gradient, which does not reach them: lighter at the top of the sheet, heavier
	at the bottom, which is the direction the paper ages in anyway.
]]
local function deckle(edge: string, count: number, seed: number)
	local random = generator(seed)
	local horizontal = edge == "Top" or edge == "Bottom"
	local span = if horizontal then CARD_WIDTH else CARD_HEIGHT
	local step = span / count
	local tone = if edge == "Bottom" then PAPER_LOW elseif edge == "Top" then PAPER_HIGH else PAPER_MID

	for index = 0, count - 1 do
		local depth = 2 + random() * 7
		local sliver = Instance.new("Frame")
		sliver.Name = `Deckle{edge}{index}`
		sliver.BackgroundColor3 = tone
		sliver.BorderSizePixel = 0
		sliver.ZIndex = 3
		if horizontal then
			sliver.Size = UDim2.fromOffset(math.ceil(step) + 1, depth)
			sliver.Position = if edge == "Top"
				then UDim2.fromOffset(index * step, -depth)
				else UDim2.new(0, index * step, 1, 0)
		else
			sliver.Size = UDim2.fromOffset(depth, math.ceil(step) + 1)
			sliver.Position = if edge == "Left"
				then UDim2.fromOffset(-depth, index * step)
				else UDim2.new(1, 0, 0, index * step)
		end
		sliver.Parent = sheet
		fades(sliver, "BackgroundTransparency", 0)
	end
end

deckle("Top", 46, 8123)
deckle("Bottom", 46, 5501)
deckle("Left", 28, 3307)
deckle("Right", 28, 9931)

--[[
	Tone.

	Three gradients at angles that share no common factor, so the light and dark
	patches they produce never line up into a pattern. The first is the sheet's
	overall aging, top to bottom; the other two are laid over it as translucent
	washes, which is what gives the middle of the paper its blotches.
]]
local aging = Instance.new("UIGradient")
aging.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, PAPER_HIGH),
	ColorSequenceKeypoint.new(0.42, PAPER_MID),
	ColorSequenceKeypoint.new(1, PAPER_LOW),
})
aging.Rotation = 96
aging.Parent = sheet

local function wash(rotation: number, colour: Color3, keypoints: { NumberSequenceKeypoint }, zIndex: number)
	local frame = Instance.new("Frame")
	frame.Name = "Wash"
	frame.BackgroundColor3 = colour
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)
	frame.ZIndex = zIndex
	frame.Parent = sheet

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation
	gradient.Transparency = NumberSequence.new(keypoints)
	gradient.Parent = frame
	fades(frame, "BackgroundTransparency", 0.72)
end

wash(23, STAIN, {
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.34, 0.62),
	NumberSequenceKeypoint.new(0.61, 0.94),
	NumberSequenceKeypoint.new(1, 0.7),
}, 4)
wash(-64, STAIN, {
	NumberSequenceKeypoint.new(0, 0.78),
	NumberSequenceKeypoint.new(0.28, 0.97),
	NumberSequenceKeypoint.new(0.72, 0.6),
	NumberSequenceKeypoint.new(1, 0.99),
}, 4)

--[[
	Handling.

	The rim of a sheet that has been carried, pinned and moved is darker than its
	middle — dirt from fingers, and light that has reached the face but not the
	edge. Four strips, each fading inward to nothing, do it more convincingly
	than a stroke because there is no line where they stop.
]]
local function burn(rotation: number, size: UDim2, position: UDim2, anchor: Vector2)
	local strip = Instance.new("Frame")
	strip.Name = "EdgeBurn"
	strip.AnchorPoint = anchor
	strip.BackgroundColor3 = STAIN
	strip.BorderSizePixel = 0
	strip.Position = position
	strip.Size = size
	strip.ZIndex = 5
	strip.Parent = sheet

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.34),
		NumberSequenceKeypoint.new(0.55, 0.86),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = strip
	fades(strip, "BackgroundTransparency", 0.5)
end

burn(90, UDim2.new(1, 0, 0, 46), UDim2.fromScale(0, 0), Vector2.new(0, 0))
burn(270, UDim2.new(1, 0, 0, 52), UDim2.fromScale(0, 1), Vector2.new(0, 1))
burn(0, UDim2.new(0, 44, 1, 0), UDim2.fromScale(0, 0), Vector2.new(0, 0))
burn(180, UDim2.new(0, 44, 1, 0), UDim2.fromScale(1, 0), Vector2.new(1, 0))

-- Foxing: the rust-coloured spots damp paper grows. Sparse, uneven in size, and
-- kept off the middle of the sheet where the text goes.
do
	local random = generator(41213)
	for index = 1, 22 do
		local size = 3 + random() * 13
		local spot = Instance.new("Frame")
		spot.Name = `Foxing{index}`
		spot.BackgroundColor3 = STAIN
		spot.BorderSizePixel = 0
		spot.Position = UDim2.fromOffset(random() * (CARD_WIDTH - size), random() * (CARD_HEIGHT - size))
		spot.Size = UDim2.fromOffset(size, size * (0.7 + random() * 0.6))
		spot.ZIndex = 6
		spot.Parent = sheet

		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0.5, 0)
		round.Parent = spot
		fades(spot, "BackgroundTransparency", 0.84 + random() * 0.1)
	end
end

-- Grain: the tooth of the paper. Individually invisible, and the reason the
-- surface does not read as a flat fill when you look at it directly.
do
	local random = generator(77719)
	for index = 1, 170 do
		local dark = random() < 0.62
		local speck = Instance.new("Frame")
		speck.Name = `Grain{index}`
		speck.BackgroundColor3 = if dark then STAIN else PAPER_HIGH
		speck.BorderSizePixel = 0
		speck.Position = UDim2.fromOffset(random() * CARD_WIDTH, random() * CARD_HEIGHT)
		speck.Size = UDim2.fromOffset(1 + math.floor(random() * 2), 1 + math.floor(random() * 2))
		speck.ZIndex = 6
		speck.Parent = sheet
		fades(speck, "BackgroundTransparency", 0.8 + random() * 0.14)
	end
end

-- Two creases, from being folded into a pocket and opened again.
do
	local random = generator(60611)
	for index = 1, 2 do
		local crease = Instance.new("Frame")
		crease.Name = `Crease{index}`
		crease.AnchorPoint = Vector2.new(0.5, 0.5)
		crease.BackgroundColor3 = STAIN
		crease.BorderSizePixel = 0
		crease.Position = UDim2.fromScale(0.5, 0.24 + index * 0.31)
		crease.Rotation = -1.6 + random() * 3.2
		crease.Size = UDim2.new(1, 26, 0, 1)
		crease.ZIndex = 6
		crease.Parent = sheet
		fades(crease, "BackgroundTransparency", 0.84)
	end
end

-- Print ------------------------------------------------------------------------

-- The printed border: a heavy rule with a hairline inside it, which is how a
-- notice of this kind was actually set. Inset unevenly — the sheet was trimmed
-- by hand, so the block does not sit dead centre in it.
local block = Instance.new("Frame")
block.Name = "Block"
block.BackgroundTransparency = 1
block.Position = UDim2.fromOffset(38, 34)
block.Size = UDim2.new(1, -78, 1, -70)
block.ZIndex = 7
block.Parent = sheet

local heavyRule = Instance.new("UIStroke")
heavyRule.Color = INK
heavyRule.Thickness = 3
heavyRule.Parent = block
fades(heavyRule, "Transparency", 0.22)

local hairlineHolder = Instance.new("Frame")
hairlineHolder.BackgroundTransparency = 1
hairlineHolder.Position = UDim2.fromOffset(7, 7)
hairlineHolder.Size = UDim2.new(1, -14, 1, -14)
hairlineHolder.ZIndex = 7
hairlineHolder.Parent = block

local hairline = Instance.new("UIStroke")
hairline.Color = INK_SOFT
hairline.Thickness = 1
hairline.Parent = hairlineHolder
fades(hairline, "Transparency", 0.42)

local function rule(y: number, thickness: number, inset: number, transparency: number)
	local line = Instance.new("Frame")
	line.Name = "Rule"
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.BackgroundColor3 = INK
	line.BorderSizePixel = 0
	line.Position = UDim2.fromScale(0.5, y)
	line.Size = UDim2.new(1, -inset, 0, thickness)
	line.ZIndex = 8
	line.Parent = block
	fades(line, "BackgroundTransparency", transparency)
end

rule(0.235, 3, 96, 0.12)
rule(0.275, 1, 132, 0.34)
rule(0.735, 1, 132, 0.34)
rule(0.775, 3, 96, 0.12)

--[[
	The line itself, printed three times.

	Ink laid on rough paper spreads into the fibre, so the mark is darkest where
	the type pressed and lighter a hair's width around it. Two offset copies at
	low opacity under a solid one is the cheapest honest version of that, and it
	is the single detail that most separates this from a text label sitting on a
	coloured box.
]]
local function headline(name: string, offset: Vector2, transparency: number, zIndex: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Creepster
	label.Position = UDim2.new(0.5, offset.X, 0.5, offset.Y)
	label.Size = UDim2.new(1, -54, 0.4, 0)
	label.Text = NOTICE_TEXT
	label.TextColor3 = INK
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.ZIndex = zIndex
	label.Parent = block

	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 92
	limit.Parent = label

	fades(label, "TextTransparency", transparency)
	return label
end

headline("Bleed", Vector2.new(2.5, 2.5), 0.74, 8)
headline("Spread", Vector2.new(-1.5, 1), 0.82, 8)
headline("Line", Vector2.new(0, 0), 0.04, 9)

setAlpha(0)

-- Show --------------------------------------------------------------------------

--[[
	The world falling out of focus behind the notice.

	Created here and left in Lighting at size zero rather than made and destroyed
	per showing: a BlurEffect appearing mid-frame costs a pipeline rebuild, which
	is a visible hitch at exactly the wrong moment. Client-side, so it is this
	player's screen and nobody else's.
]]
local blur = Lighting:FindFirstChild("ProwlerNoticeBlur") :: BlurEffect?
if not blur then
	local created = Instance.new("BlurEffect")
	created.Name = "ProwlerNoticeBlur"
	created.Size = 0
	created.Parent = Lighting
	blur = created
end

local function fitToViewport(): number
	local camera = workspace.CurrentCamera
	local view = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	return math.clamp(math.min(view.X / 1180, view.Y / 700), 0.5, 1.35)
end

local showing = false

local function show()
	if showing then
		return
	end
	showing = true

	local base = fitToViewport()
	gui.Enabled = true
	setAlpha(0)

	local alpha = Instance.new("NumberValue")
	alpha.Value = 0
	local connection = alpha.Changed:Connect(setAlpha)

	-- Settling onto the wall rather than appearing at rest. Small — a notice
	-- that flies in is an animation, and this is meant to be a thing that is
	-- simply there once the player looks.
	scale.Scale = base * 1.045
	TweenService
		:Create(scale, TweenInfo.new(OnboardingConfig.CARD_FADE_IN, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Scale = base,
		})
		:Play()

	local fadeIn = TweenService:Create(
		alpha,
		TweenInfo.new(OnboardingConfig.CARD_FADE_IN, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ Value = 1 }
	)
	TweenService:Create(
		blur :: BlurEffect,
		TweenInfo.new(OnboardingConfig.CARD_FADE_IN, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ Size = BLUR_SIZE }
	):Play()
	fadeIn:Play()

	-- A hanging sheet is never quite still. Slow enough that it is not read as
	-- motion, present enough that the notice is not a decal on the lens.
	local drift = RunService.RenderStepped:Connect(function()
		local clock = os.clock()
		holder.Rotation = -1.1 + math.sin(clock * 0.6) * 0.28
		holder.Position = UDim2.new(0.5, math.sin(clock * 0.45) * 2, 0.5, math.cos(clock * 0.37) * 2)
	end)

	task.delay(OnboardingConfig.CARD_FADE_IN + OnboardingConfig.CARD_HOLD, function()
		TweenService:Create(
			alpha,
			TweenInfo.new(OnboardingConfig.CARD_FADE_OUT, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
			{ Value = 0 }
		):Play()
		TweenService:Create(
			blur :: BlurEffect,
			TweenInfo.new(OnboardingConfig.CARD_FADE_OUT, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
			{ Size = 0 }
		):Play()

		task.delay(OnboardingConfig.CARD_FADE_OUT + 0.1, function()
			drift:Disconnect()
			connection:Disconnect()
			alpha:Destroy()
			gui.Enabled = false
			holder.Rotation = -1.1
			holder.Position = UDim2.fromScale(0.5, 0.5)
			showing = false
		end)
	end)
end

local remotes = ReplicatedStorage:WaitForChild(OnboardingConfig.REMOTE_FOLDER)
local cardEvent = remotes:WaitForChild(OnboardingConfig.CARD_EVENT) :: RemoteEvent
cardEvent.OnClientEvent:Connect(show)
