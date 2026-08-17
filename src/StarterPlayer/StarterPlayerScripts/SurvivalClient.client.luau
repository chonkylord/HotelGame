--!strict
-- Draws the survival HUD and reports the sprint key. Nothing here decides
-- anything: hunger and stamina arrive from SurvivalService, health is read off
-- the Humanoid, and shift is forwarded as a plain "held / not held".
--
-- Bottom-left cluster, top to bottom: eight skull hearts, the hunger meter, and
-- the sprint meter. The sprint meter is kept in the layout at all times and only
-- fades its transparency, so the rest of the HUD never shifts under the player.
--
-- Everything is drawn in the hearts' visual language — hard pixel edges, black
-- outlines, discrete segments, no text. Smooth rounded bars next to pixel-art
-- skulls read as two different HUDs bolted together.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("SurvivalConfig"))
local RescueConfig = require(ReplicatedStorage:WaitForChild("RescueConfig"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotes = ReplicatedStorage:WaitForChild(Config.RemotesFolder)
local statsEvent = remotes:WaitForChild(Config.StatsEvent) :: RemoteEvent
local sprintEvent = remotes:WaitForChild(Config.SprintEvent) :: RemoteEvent

local GUI_NAME = "SurvivalHUD"

-- Layout ---------------------------------------------------------------------
local HEART_SIZE = 30
local HEART_GAP = 3
local ROW_WIDTH = Config.Hearts * HEART_SIZE + (Config.Hearts - 1) * HEART_GAP -- 261

local ICON_SIZE = 22
local ICON_GAP = 13
local BORDER = 2
local CELLS = Config.HungerSegments
local CELL_WIDTH = 12
local CELL_GAP = 2
local CELL_HEIGHT = 14
-- 16 cells of 12 with 2 between them lands the bar exactly under the last skull.
local BAR_INNER = CELLS * CELL_WIDTH + (CELLS - 1) * CELL_GAP -- 222
local BAR_OUTER = BAR_INNER + BORDER * 2 -- 226
local BAR_HEIGHT = CELL_HEIGHT + BORDER * 2 -- 18
local METER_HEIGHT = ICON_SIZE
local HIGHLIGHT = 5 -- lit cells get a lighter band across the top

local HUNGER_Y = HEART_SIZE + 10
local SPRINT_Y = HUNGER_Y + METER_HEIGHT + 6
local MARGIN = 24

-- Palette --------------------------------------------------------------------
-- OUTLINE matches the black the skull art is drawn with, so the bars and the
-- hearts look struck from the same sheet.
local OUTLINE = Color3.fromRGB(28, 26, 32)
-- Kept clearly lighter than OUTLINE: spent segments have to read as empty
-- slots, not merge into the black ruling between them.
local SLOT = Color3.fromRGB(78, 73, 90)
local BONE = Color3.fromRGB(240, 236, 228)
local BONE_LOW = Color3.fromRGB(206, 66, 52)
local HEART_SPENT = Color3.fromRGB(48, 46, 54)

local HUNGER_BASE = Color3.fromRGB(198, 120, 38)
local HUNGER_LIGHT = Color3.fromRGB(244, 178, 76)
local SPRINT_BASE = Color3.fromRGB(58, 156, 190)
local SPRINT_LIGHT = Color3.fromRGB(124, 220, 242)
local ALARM_BASE = Color3.fromRGB(168, 48, 36)
local ALARM_LIGHT = Color3.fromRGB(214, 84, 60)

-- Below this the hunger meter flips to the alarm palette outright. A gradual
-- colour fade would undercut the deliberately stepped look of the segments.
local HUNGER_ALARM_AT = 0.25

-- The default health bar would sit above our hearts saying the same thing, and
-- it can refuse the call for a moment right after joining — hence the retry.
task.spawn(function()
	for _ = 1, 20 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
		end)
		if ok then
			return
		end
		task.wait(0.5)
	end
end)

for _, existing in playerGui:GetChildren() do
	if existing.Name == GUI_NAME then
		existing:Destroy()
	end
end

-- Build ----------------------------------------------------------------------

local screen = Instance.new("ScreenGui")
screen.Name = GUI_NAME
screen.DisplayOrder = 6
screen.IgnoreGuiInset = false
screen.ResetOnSpawn = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local root = Instance.new("Frame")
root.AnchorPoint = Vector2.new(0, 1)
root.BackgroundTransparency = 1
root.Position = UDim2.new(0, MARGIN, 1, -MARGIN)
root.Size = UDim2.fromOffset(ROW_WIDTH, SPRINT_Y + METER_HEIGHT)
root.Parent = screen

local heartsRow = Instance.new("Frame")
heartsRow.BackgroundTransparency = 1
heartsRow.Size = UDim2.fromOffset(ROW_WIDTH, HEART_SIZE)
heartsRow.Parent = root

type Heart = { spent: ImageLabel, filled: ImageLabel, clip: Frame }
local hearts: { Heart } = {}

for index = 1, Config.Hearts do
	local slot = Instance.new("Frame")
	slot.BackgroundTransparency = 1
	slot.Position = UDim2.fromOffset((index - 1) * (HEART_SIZE + HEART_GAP), 0)
	slot.Size = UDim2.fromOffset(HEART_SIZE, HEART_SIZE)
	slot.Parent = heartsRow

	-- The art is a white skull with a black outline, so ImageColor3 multiplies
	-- down to a dark skull for the spent state and leaves the outline alone.
	local spent = Instance.new("ImageLabel")
	spent.BackgroundTransparency = 1
	spent.Image = Config.HeartImage
	spent.ImageColor3 = HEART_SPENT
	spent.ImageTransparency = 0.35
	spent.ResampleMode = Enum.ResamplerMode.Pixelated
	spent.Size = UDim2.fromScale(1, 1)
	spent.ZIndex = 1
	spent.Parent = slot

	-- Clipping a fixed-size skull is what gives partial hearts; the image inside
	-- must stay at full size or it would squash instead of being cut off.
	local clip = Instance.new("Frame")
	clip.BackgroundTransparency = 1
	clip.ClipsDescendants = true
	clip.Size = UDim2.fromScale(1, 1)
	clip.ZIndex = 2
	clip.Parent = slot

	local filled = Instance.new("ImageLabel")
	filled.BackgroundTransparency = 1
	filled.Image = Config.HeartImage
	filled.ImageColor3 = BONE
	filled.ResampleMode = Enum.ResamplerMode.Pixelated
	filled.Size = UDim2.fromOffset(HEART_SIZE, HEART_SIZE)
	filled.ZIndex = 2
	filled.Parent = clip

	hearts[index] = { spent = spent, filled = filled, clip = clip }
end

type Cell = { body: Frame, top: Frame }
type Meter = { group: CanvasGroup, icon: ImageLabel, cells: { Cell } }

-- A CanvasGroup so the sprint meter can fade as one object; setting
-- transparency on forty separate frames would drift out of step.
local function buildMeter(image: string, y: number): Meter
	local group = Instance.new("CanvasGroup")
	group.BackgroundTransparency = 1
	group.Position = UDim2.fromOffset(0, y)
	group.Size = UDim2.fromOffset(ROW_WIDTH, METER_HEIGHT)
	group.Parent = root

	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.Image = image
	icon.ResampleMode = Enum.ResamplerMode.Pixelated
	icon.Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
	icon.Parent = group

	-- The outer frame IS the border: a black rectangle with the track inset two
	-- pixels inside it. Cheaper than a UIStroke and it stays pixel-crisp.
	local outer = Instance.new("Frame")
	outer.BackgroundColor3 = OUTLINE
	outer.BorderSizePixel = 0
	outer.Position = UDim2.fromOffset(ICON_SIZE + ICON_GAP, (METER_HEIGHT - BAR_HEIGHT) // 2)
	outer.Size = UDim2.fromOffset(BAR_OUTER, BAR_HEIGHT)
	outer.Parent = group

	-- Also black, so the two-pixel gaps between cells read as ruled lines.
	local inner = Instance.new("Frame")
	inner.BackgroundColor3 = OUTLINE
	inner.BorderSizePixel = 0
	inner.Position = UDim2.fromOffset(BORDER, BORDER)
	inner.Size = UDim2.fromOffset(BAR_INNER, CELL_HEIGHT)
	inner.Parent = outer

	local cells: { Cell } = {}
	for index = 1, CELLS do
		local body = Instance.new("Frame")
		body.BackgroundColor3 = SLOT
		body.BorderSizePixel = 0
		body.Position = UDim2.fromOffset((index - 1) * (CELL_WIDTH + CELL_GAP), 0)
		body.Size = UDim2.fromOffset(CELL_WIDTH, CELL_HEIGHT)
		body.Parent = inner

		-- Flat lighter band along the top of a lit cell — the standard way a
		-- pixel-art bar suggests a rounded surface without any curves.
		local top = Instance.new("Frame")
		top.BackgroundColor3 = SLOT
		top.BorderSizePixel = 0
		top.Size = UDim2.fromOffset(CELL_WIDTH, HIGHLIGHT)
		top.Visible = false
		top.Parent = body

		cells[index] = { body = body, top = top }
	end

	return { group = group, icon = icon, cells = cells }
end

local hungerMeter = buildMeter(Config.HungerIcon, HUNGER_Y)
local sprintMeter = buildMeter(Config.SprintIcon, SPRINT_Y)

screen.Parent = playerGui

-- Segments are deliberately discrete: any hunger left keeps at least one cell
-- lit, so an almost-empty meter never looks the same as a dead one.
local function paint(meter: Meter, fraction: number, base: Color3, light: Color3)
	local lit = if fraction <= 0 then 0 else math.max(1, math.floor(fraction * CELLS + 0.5))
	for index, cell in meter.cells do
		local on = index <= lit
		cell.body.BackgroundColor3 = if on then base else SLOT
		cell.top.BackgroundColor3 = light
		cell.top.Visible = on
	end
	meter.icon.ImageColor3 = light
end

-- Sprint input ---------------------------------------------------------------

local sprintHeld = false

local function setSprint(held: boolean)
	if held and RescueConfig.isImmobilized(player:GetAttribute(RescueConfig.StateAttribute)) then
		return
	end
	if held == sprintHeld then
		return
	end
	sprintHeld = held
	sprintEvent:FireServer(held)
end

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		setSprint(true)
	end
end)

-- Deliberately ignores gameProcessed: a release must always get through, or the
-- player keeps sprinting because the key-up landed on a text box.
UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		setSprint(false)
	end
end)

UserInputService.WindowFocusReleased:Connect(function()
	setSprint(false)
end)

player:GetAttributeChangedSignal(RescueConfig.StateAttribute):Connect(function()
	if RescueConfig.isImmobilized(player:GetAttribute(RescueConfig.StateAttribute)) then
		setSprint(false)
	end
end)

-- Phones have no shift key, so give touch players a thumb button rather than a
-- meter they can never fill.
if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(1, 1)
	button.AutoButtonColor = false
	button.BackgroundColor3 = OUTLINE
	button.BackgroundTransparency = 0.2
	button.BorderSizePixel = 0
	button.Position = UDim2.new(1, -MARGIN, 1, -(MARGIN + 96))
	button.Size = UDim2.fromOffset(76, 76)
	button.Text = ""
	button.Parent = screen

	local glyph = Instance.new("ImageLabel")
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.BackgroundTransparency = 1
	glyph.Image = Config.SprintIcon
	glyph.ImageColor3 = SPRINT_LIGHT
	glyph.ResampleMode = Enum.ResamplerMode.Pixelated
	glyph.Position = UDim2.fromScale(0.5, 0.5)
	glyph.Size = UDim2.fromOffset(44, 44)
	glyph.Parent = button

	button.MouseButton1Down:Connect(function()
		setSprint(true)
	end)
	button.MouseButton1Up:Connect(function()
		setSprint(false)
	end)
	button.MouseLeave:Connect(function()
		setSprint(false)
	end)
end

-- State ----------------------------------------------------------------------

local MAX_STAMINA = Config.SprintSeconds

local targetHunger = Config.MaxHunger
local targetStamina = MAX_STAMINA
local sprinting = false
local blocked = false

local shownHunger = 1
local shownStamina = 1
local shownHealth = 1
local sprintAlpha = 0
local sprintHoldUntil = 0

statsEvent.OnClientEvent:Connect(function(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	targetHunger = tonumber(payload.hunger) or targetHunger
	targetStamina = tonumber(payload.stamina) or targetStamina
	sprinting = payload.sprinting == true
	blocked = payload.blocked == true
end)

local humanoid: Humanoid? = nil

local function bindCharacter(character: Model)
	local found = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if found and found:IsA("Humanoid") then
		humanoid = found
	end
end

player.CharacterAdded:Connect(bindCharacter)
if player.Character then
	task.spawn(bindCharacter, player.Character)
end

-- Render ---------------------------------------------------------------------

-- Frame-rate independent approach to a target: at rate 12 a bar covers most of
-- the remaining distance in about a tenth of a second, which smooths the 10 Hz
-- updates without lagging visibly behind a hit.
local function approach(current: number, goal: number, rate: number, dt: number): number
	return current + (goal - current) * (1 - math.exp(-rate * dt))
end

RunService.RenderStepped:Connect(function(dt: number)
	local now = os.clock()

	-- With no Humanoid to read — the gap before the first spawn, and again
	-- between death and respawn — hold the last figure rather than treating it
	-- as zero, which would drain the hearts and refill them for no reason. A
	-- dead player still has their Humanoid, so death itself reads as 0 here.
	local healthGoal = shownHealth
	if humanoid and humanoid.Parent and humanoid.MaxHealth > 0 then
		local rescueState = player:GetAttribute(RescueConfig.StateAttribute)
		local catchCount = player:GetAttribute(RescueConfig.CatchCountAttribute)
		local permanentlyDead = rescueState == RescueConfig.StateDead
			or (rescueState == RescueConfig.StateCarried and typeof(catchCount) == "number" and catchCount >= 2)
		healthGoal = if permanentlyDead then 0 else math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
	end

	shownHealth = approach(shownHealth, healthGoal, 14, dt)
	shownHunger = approach(shownHunger, math.clamp(targetHunger / Config.MaxHunger, 0, 1), 10, dt)
	shownStamina = approach(shownStamina, math.clamp(targetStamina / MAX_STAMINA, 0, 1), 16, dt)

	-- Hearts. Low health gets a slow pulse so it reads at a glance while the
	-- player is busy looking at something else.
	local pulse = 0
	if healthGoal > 0 and healthGoal <= 0.25 then
		pulse = (math.sin(now * 5) + 1) / 2
	end
	local filledColor = BONE:Lerp(BONE_LOW, pulse * 0.85)

	local heartsLit = shownHealth * Config.Hearts
	for index, heart in hearts do
		heart.clip.Size = UDim2.fromScale(math.clamp(heartsLit - (index - 1), 0, 1), 1)
		heart.filled.ImageColor3 = filledColor
	end

	if shownHunger <= HUNGER_ALARM_AT then
		paint(hungerMeter, shownHunger, ALARM_BASE, ALARM_LIGHT)
	else
		paint(hungerMeter, shownHunger, HUNGER_BASE, HUNGER_LIGHT)
	end

	if blocked then
		paint(sprintMeter, shownStamina, ALARM_BASE, ALARM_LIGHT)
	else
		paint(sprintMeter, shownStamina, SPRINT_BASE, SPRINT_LIGHT)
	end

	-- Sprint meter is only on screen when it has something to say: while
	-- sprinting, while refilling, or when a sprint was refused.
	if sprinting or blocked or shownStamina < 0.999 then
		sprintHoldUntil = now + 0.8
	end
	sprintAlpha = approach(sprintAlpha, if now < sprintHoldUntil then 1 else 0, 9, dt)

	sprintMeter.group.GroupTransparency = 1 - sprintAlpha
	sprintMeter.group.Visible = sprintAlpha > 0.01
end)
