--!strict
-- Renders Noel's speech bubble: an aged-paper card that floats over his head
-- and types out whatever CheckInService sent. Purely presentational — the room
-- number and code are decided on the server.
--
-- The bubble is built client-side and parented to this player's PlayerGui, so
-- one guest's room code is never visible to anyone standing nearby.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local checkInEvent = ReplicatedStorage:WaitForChild("ReceptionRemotes"):WaitForChild("CheckInEvent") :: RemoteEvent

local BUBBLE_NAME = "NoelDialogue"

-- Nothing should be on screen until the player presses E, so clear any bubble a
-- previous session left behind before wiring anything up.
for _, existing in playerGui:GetChildren() do
	if existing.Name == BUBBLE_NAME then
		existing:Destroy()
	end
end

local INK = Color3.fromRGB(52, 36, 22)
local INK_SOFT = Color3.fromRGB(122, 96, 66)
local EDGE = Color3.fromRGB(74, 52, 33)
local PAPER_LOW = Color3.fromRGB(219, 200, 160)

-- At 330 wide the longest line Noel says still wraps to two rows (40px of the
-- 90px the body gets, measured off TextBounds at TextSize 20), leaving a row of
-- slack for a long display name without the bubble looking half empty.
local BUBBLE_WIDTH = 330
local BUBBLE_HEIGHT = 140
local TAIL_DROP = 20 -- room reserved under the bubble for the tail
-- A radius this large is what separates "speech bubble" from "panel with
-- rounded corners" — two thirds of the way to a capsule. It still leaves
-- ~230px of flat bottom edge for the tail to meet.
local BUBBLE_CORNER = 48
local PAD_X = 26
local PAD_TOP = 20
local PAD_BOTTOM = 30 -- keeps the body clear of the press-E hint
local TYPE_INTERVAL = 0.022
local WALK_AWAY_DISTANCE = 22

type Dialogue = {
	gui: BillboardGui,
	body: TextLabel,
	prompt: ProximityPrompt?,
	adornee: BasePart,
	lines: { string },
	index: number,
	revealing: boolean,
	token: number,
	watcher: RBXScriptConnection?,
}

local active: Dialogue? = nil
local tokenCounter = 0

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

-- MaxVisibleGraphemes counts rendered characters, so the markup tags this text
-- carries must not be counted when working out how long the reveal runs.
local function visibleLength(text: string): number
	local plain = (text:gsub("<[^>]->", ""))
	return utf8.len(plain) or #plain
end

local function buildBubble(adornee: BasePart): (BillboardGui, TextLabel)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = BUBBLE_NAME
	billboard.Adornee = adornee
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 80
	billboard.ResetOnSpawn = false
	billboard.Size = UDim2.fromOffset(BUBBLE_WIDTH, BUBBLE_HEIGHT + TAIL_DROP)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.4, 0)
	-- The card is layered by ZIndex among siblings (shadow < tail < card < seam),
	-- so don't inherit whatever behaviour the place happens to default to.
	billboard.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local root = Instance.new("Frame")
	root.BackgroundTransparency = 1
	root.Rotation = -1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = billboard

	local shadow = Instance.new("Frame")
	shadow.BackgroundColor3 = Color3.fromRGB(30, 20, 12)
	shadow.BackgroundTransparency = 0.72
	shadow.BorderSizePixel = 0
	shadow.Position = UDim2.fromOffset(4, 5)
	shadow.Size = UDim2.new(1, 0, 1, -TAIL_DROP)
	shadow.ZIndex = 1
	corner(shadow, BUBBLE_CORNER)
	shadow.Parent = root

	-- Tail sits behind the card so the card's fill hides its upper half; only the
	-- two outer edges read, which is what makes it look like one drawn shape.
	local tail = Instance.new("Frame")
	tail.AnchorPoint = Vector2.new(0.5, 0.5)
	tail.BackgroundColor3 = PAPER_LOW
	tail.BorderSizePixel = 0
	tail.Position = UDim2.new(0.5, 0, 1, -TAIL_DROP)
	tail.Rotation = 45
	tail.Size = UDim2.fromOffset(28, 28)
	tail.ZIndex = 2
	-- Softens the point just enough that it reads as drawn rather than snipped.
	corner(tail, 3)
	stroke(tail, EDGE, 3)
	tail.Parent = root

	local card = Instance.new("Frame")
	card.BackgroundColor3 = Color3.fromRGB(238, 224, 190)
	card.BorderSizePixel = 0
	card.Size = UDim2.new(1, 0, 1, -TAIL_DROP)
	card.ZIndex = 3
	corner(card, BUBBLE_CORNER)
	stroke(card, EDGE, 3)
	card.Parent = root

	local aged = Instance.new("UIGradient")
	aged.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(247, 238, 213)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(236, 222, 189)),
		ColorSequenceKeypoint.new(1, PAPER_LOW),
	})
	aged.Rotation = 90
	aged.Parent = card

	-- Paints over the card's bottom border where the tail meets it, so the two
	-- shapes join instead of showing a line ruled across the tail's base.
	local seam = Instance.new("Frame")
	seam.AnchorPoint = Vector2.new(0.5, 0.5)
	seam.BackgroundColor3 = PAPER_LOW
	seam.BorderSizePixel = 0
	seam.Position = UDim2.new(0.5, 0, 1, -TAIL_DROP)
	-- Just tall enough to bury the 3px stroke; any more and the flat patch starts
	-- reading as a band across the tail.
	seam.Size = UDim2.fromOffset(30, 7)
	seam.ZIndex = 4
	seam.Parent = root

	-- No name plate: the bubble is pinned over Noel's head with a tail pointing
	-- at him, and his Humanoid already carries the DisplayName. A heading would
	-- only restate that in a typeface nothing else here uses.
	local body = Instance.new("TextLabel")
	body.BackgroundTransparency = 1
	body.Font = Enum.Font.Garamond
	body.Position = UDim2.fromOffset(PAD_X, PAD_TOP)
	body.RichText = true
	body.Size = UDim2.new(1, -PAD_X * 2, 1, -(TAIL_DROP + PAD_TOP + PAD_BOTTOM))
	body.Text = ""
	body.TextColor3 = INK
	body.TextSize = 20
	body.TextWrapped = true
	body.TextXAlignment = Enum.TextXAlignment.Left
	-- Centred vertically so a short line sits in the middle of the bubble rather
	-- than clinging to the top. MaxVisibleGraphemes lays the whole string out up
	-- front, so the block does not shift around as it types.
	body.TextYAlignment = Enum.TextYAlignment.Center
	body.ZIndex = 6
	body.Parent = root

	local hint = Instance.new("TextLabel")
	hint.AnchorPoint = Vector2.new(1, 1)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.Garamond
	hint.Position = UDim2.new(1, -PAD_X, 1, -(TAIL_DROP + 8))
	hint.Size = UDim2.fromOffset(140, 16)
	hint.Text = "press E"
	hint.TextColor3 = INK_SOFT
	hint.TextSize = 14
	hint.TextXAlignment = Enum.TextXAlignment.Right
	hint.ZIndex = 6
	hint.Parent = root

	TweenService:Create(hint, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		TextTransparency = 0.65,
	}):Play()

	billboard.Parent = playerGui
	return billboard, body
end

local function closeDialogue(completed: boolean?)
	local dialogue = active
	if not dialogue then
		return
	end
	active = nil
	dialogue.token += 1

	if dialogue.watcher then
		dialogue.watcher:Disconnect()
	end
	-- Set locally only, so E drives the dialogue instead of re-firing the prompt.
	-- Restoring it here hands the prompt back to the player.
	if dialogue.prompt and dialogue.prompt.Parent then
		dialogue.prompt.Enabled = true
	end
	dialogue.gui:Destroy()
	if completed then
		checkInEvent:FireServer("DialogueComplete")
	end
end

local function showLine(dialogue: Dialogue)
	local text = dialogue.lines[dialogue.index]
	if not text then
		closeDialogue()
		return
	end

	tokenCounter += 1
	dialogue.token = tokenCounter
	local myToken = tokenCounter

	dialogue.revealing = true
	dialogue.body.Text = text
	-- Noel's final hand-off can be a longer authored riddle. Give it a little
	-- more room without making every short check-in line permanently tiny.
	local length = visibleLength(text)
	dialogue.body.TextSize = if length > 105 then 16 elseif length > 78 then 18 else 20
	dialogue.body.MaxVisibleGraphemes = 0

	task.spawn(function()
		for i = 1, length do
			if dialogue.token ~= myToken or active ~= dialogue then
				return
			end
			dialogue.body.MaxVisibleGraphemes = i
			task.wait(TYPE_INTERVAL)
		end
		if dialogue.token == myToken and active == dialogue then
			dialogue.body.MaxVisibleGraphemes = -1
			dialogue.revealing = false
		end
	end)
end

local function advance()
	local dialogue = active
	if not dialogue then
		return
	end

	if dialogue.revealing then
		-- Second press on a line still typing shows the rest of it at once.
		dialogue.token += 1
		dialogue.revealing = false
		dialogue.body.MaxVisibleGraphemes = -1
		return
	end

	dialogue.index += 1
	if dialogue.index > #dialogue.lines then
		closeDialogue(true)
	else
		showLine(dialogue)
	end
end

local function openDialogue(payload: any)
	if typeof(payload) ~= "table" or typeof(payload.lines) ~= "table" or #payload.lines == 0 then
		return
	end
	local adornee = payload.adornee
	if not (typeof(adornee) == "Instance" and adornee:IsA("BasePart")) then
		return
	end

	closeDialogue()

	local gui, body = buildBubble(adornee)
	local dialogue: Dialogue = {
		gui = gui,
		body = body,
		prompt = if typeof(payload.prompt) == "Instance" and payload.prompt:IsA("ProximityPrompt")
			then payload.prompt
			else nil,
		adornee = adornee,
		lines = payload.lines,
		index = 1,
		revealing = false,
		token = 0,
		watcher = nil,
	}
	active = dialogue

	if dialogue.prompt then
		dialogue.prompt.Enabled = false
	end

	dialogue.watcher = RunService.Heartbeat:Connect(function()
		if active ~= dialogue then
			return
		end
		if not adornee.Parent then
			closeDialogue()
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (root and root:IsA("BasePart")) then
			closeDialogue()
			return
		end
		if (root.Position - adornee.Position).Magnitude > WALK_AWAY_DISTANCE then
			closeDialogue()
		end
	end)

	showLine(dialogue)
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed or not active then
		return
	end
	if
		input.KeyCode == Enum.KeyCode.E
		or input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
	then
		advance()
	end
end)

checkInEvent.OnClientEvent:Connect(openDialogue)
