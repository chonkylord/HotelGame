--!strict
-- Compact local presentation for the server-owned admin attributes. This
-- module never grants a privilege: buttons submit a requested boolean and the
-- panel redraws from Player attributes replicated back by AdminService.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")

local AdminConfig = require(ReplicatedStorage:WaitForChild("AdminConfig"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- AdminService may initialize after StarterPlayerScripts. Never create the UI
-- from the replicated allowlist alone; wait for the server's authorization bit.
local authorizationDeadline = os.clock() + 10
while player:GetAttribute(AdminConfig.AuthorizedAttribute) == nil and os.clock() < authorizationDeadline do
	task.wait(0.1)
end
if player:GetAttribute(AdminConfig.AuthorizedAttribute) ~= true then
	return false
end

local remotes = ReplicatedStorage:WaitForChild(AdminConfig.RemotesFolder)
local toggleEvent = remotes:WaitForChild(AdminConfig.ToggleEvent) :: RemoteEvent
local resultEvent = remotes:WaitForChild(AdminConfig.ResultEvent) :: RemoteEvent

local GUI_NAME = "AdminControlPanel"
local PANEL_WIDTH = 252
local COLLAPSED_HEIGHT = 38
local EXPANDED_HEIGHT = 190
local BACKGROUND = Color3.fromRGB(20, 22, 26)
local SURFACE = Color3.fromRGB(33, 36, 42)
local SURFACE_HOVER = Color3.fromRGB(43, 47, 54)
local BORDER = Color3.fromRGB(90, 96, 108)
local TEXT = Color3.fromRGB(235, 237, 241)
local MUTED = Color3.fromRGB(156, 162, 174)
local ENABLED = Color3.fromRGB(70, 148, 103)
local ENABLED_TEXT = Color3.fromRGB(223, 255, 234)
local DISABLED = Color3.fromRGB(72, 76, 86)
local ERROR = Color3.fromRGB(222, 111, 111)

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
	value.Parent = object
end

local screen = Instance.new("ScreenGui")
screen.Name = GUI_NAME
screen.DisplayOrder = 70
screen.IgnoreGuiInset = false
screen.ResetOnSpawn = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(1, 0.5)
panel.BackgroundColor3 = BACKGROUND
panel.BorderSizePixel = 0
-- The stock player list occupies the upper-right corner. Keep this tab midway
-- down the edge so it does not sit on top of that list or the survival HUD.
panel.Position = UDim2.new(1, -18, 0.5, 0)
panel.Size = UDim2.fromOffset(PANEL_WIDTH, EXPANDED_HEIGHT)
corner(panel, 7)
stroke(panel, BORDER, 1, 0.25)
panel.Parent = screen

local header = Instance.new("TextButton")
header.Name = "Header"
header.AutoButtonColor = false
header.BackgroundColor3 = SURFACE
header.BorderSizePixel = 0
header.Size = UDim2.new(1, 0, 0, COLLAPSED_HEIGHT)
header.Text = ""
corner(header, 7)
header.Parent = panel

local headerMask = Instance.new("Frame")
headerMask.BackgroundColor3 = SURFACE
headerMask.BorderSizePixel = 0
headerMask.Position = UDim2.new(0, 0, 1, -7)
headerMask.Size = UDim2.new(1, 0, 0, 7)
headerMask.Parent = header

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.Position = UDim2.fromOffset(12, 0)
title.Size = UDim2.new(1, -48, 1, 0)
title.Text = "ADMIN CONTROL  //  DRAG"
title.TextColor3 = TEXT
title.TextSize = 12
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header

local collapseGlyph = Instance.new("TextLabel")
collapseGlyph.BackgroundTransparency = 1
collapseGlyph.Font = Enum.Font.GothamBold
collapseGlyph.Position = UDim2.new(1, -34, 0, 0)
collapseGlyph.Size = UDim2.fromOffset(24, COLLAPSED_HEIGHT)
collapseGlyph.Text = "-"
collapseGlyph.TextColor3 = MUTED
collapseGlyph.TextSize = 18
collapseGlyph.Parent = header

local body = Instance.new("Frame")
body.Name = "Body"
body.BackgroundTransparency = 1
body.Position = UDim2.fromOffset(0, COLLAPSED_HEIGHT)
body.Size = UDim2.new(1, 0, 1, -COLLAPSED_HEIGHT)
body.Parent = panel

type FeatureRow = {
	button: TextButton,
	stateLabel: TextLabel,
}

local rows: { [string]: FeatureRow } = {}
local pending: { [string]: boolean } = {}
local requestSerial: { [string]: number } = {}
local connections: { RBXScriptConnection } = {}
local destroyed = false
local collapsed = true

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "Status"
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.Gotham
statusLabel.Position = UDim2.new(0, 12, 1, -27)
statusLabel.Size = UDim2.new(1, -24, 0, 17)
statusLabel.Text = "Server-authorized controls"
statusLabel.TextColor3 = MUTED
statusLabel.TextSize = 10
statusLabel.TextTruncate = Enum.TextTruncate.AtEnd
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Parent = body

local function featureEnabled(feature: AdminConfig.Feature): boolean
	return player:GetAttribute(feature.attribute) == true
end

local function refreshFeature(feature: AdminConfig.Feature)
	local row = rows[feature.id]
	if not row then
		return
	end

	local enabled = featureEnabled(feature)
	local waiting = pending[feature.id] == true
	row.button.BackgroundColor3 = if enabled then Color3.fromRGB(38, 56, 48) else SURFACE
	row.button.TextColor3 = if waiting then MUTED else TEXT
	row.stateLabel.BackgroundColor3 = if enabled then ENABLED else DISABLED
	row.stateLabel.TextColor3 = if enabled then ENABLED_TEXT else TEXT
	row.stateLabel.Text = if waiting then "..." else if enabled then "ON" else "OFF"
end

for index, feature in AdminConfig.Features do
	local featureForRow: AdminConfig.Feature = feature
	local button = Instance.new("TextButton")
	button.Name = feature.id
	button.AutoButtonColor = false
	button.BackgroundColor3 = SURFACE
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamMedium
	button.Position = UDim2.fromOffset(10, 10 + (index - 1) * 38)
	button.Size = UDim2.new(1, -20, 0, 32)
	button.Text = feature.label
	button.TextColor3 = TEXT
	button.TextSize = 12
	button.TextXAlignment = Enum.TextXAlignment.Left
	corner(button, 5)
	button.Parent = body

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 9)
	padding.Parent = button

	local stateLabel = Instance.new("TextLabel")
	stateLabel.Name = "State"
	stateLabel.AnchorPoint = Vector2.new(1, 0.5)
	stateLabel.BackgroundColor3 = DISABLED
	stateLabel.BorderSizePixel = 0
	stateLabel.Font = Enum.Font.GothamBold
	stateLabel.Position = UDim2.fromScale(1, 0.5)
	stateLabel.Size = UDim2.fromOffset(42, 20)
	stateLabel.Text = "OFF"
	stateLabel.TextColor3 = TEXT
	stateLabel.TextSize = 10
	corner(stateLabel, 10)
	stateLabel.Parent = button

	rows[feature.id] = {
		button = button,
		stateLabel = stateLabel,
	}

	table.insert(
		connections,
		button.MouseEnter:Connect(function()
			if pending[featureForRow.id] ~= true and not featureEnabled(featureForRow) then
				button.BackgroundColor3 = SURFACE_HOVER
			end
		end)
	)
	table.insert(
		connections,
		button.MouseLeave:Connect(function()
			refreshFeature(featureForRow)
		end)
	)
	table.insert(
		connections,
		button.Activated:Connect(function()
			if pending[featureForRow.id] == true then
				return
			end

			local serial = (requestSerial[featureForRow.id] or 0) + 1
			requestSerial[featureForRow.id] = serial
			pending[featureForRow.id] = true
			statusLabel.Text = `Requesting {string.lower(featureForRow.label)}...`
			statusLabel.TextColor3 = MUTED
			refreshFeature(featureForRow)
			toggleEvent:FireServer(featureForRow.id, not featureEnabled(featureForRow))

			task.delay(2, function()
				if destroyed or requestSerial[featureForRow.id] ~= serial or pending[featureForRow.id] ~= true then
					return
				end
				pending[featureForRow.id] = nil
				statusLabel.Text = "Server response timed out"
				statusLabel.TextColor3 = ERROR
				refreshFeature(featureForRow)
			end)
		end)
	)
	table.insert(
		connections,
		player:GetAttributeChangedSignal(feature.attribute):Connect(function()
			refreshFeature(featureForRow)
		end)
	)
end

local function setCollapsed(nextCollapsed: boolean)
	collapsed = nextCollapsed
	body.Visible = not collapsed
	panel.Size = UDim2.fromOffset(PANEL_WIDTH, if collapsed then COLLAPSED_HEIGHT else EXPANDED_HEIGHT)
	headerMask.Visible = not collapsed
	collapseGlyph.Text = if collapsed then "+" else "-"
end

--[[
	Summoned, not resident.

	The panel used to sit permanently against the right edge for anyone the
	server had authorized, which put a piece of staff furniture on screen for the
	whole session. It is now hidden until asked for: `/admin` in chat toggles it,
	and F8 does the same for anyone who would rather not open the chat bar during
	a chase.

	Registering the command from this module is what scopes it. The module has
	already returned `false` for anyone the server did not authorize (see the top
	of the file), so a non-admin never reaches this line and `/admin` is simply
	not a command that exists on their client.
]]
local adminCommand: TextChatCommand? = nil

local function setPanelVisible(visible: boolean)
	screen.Enabled = visible
	if visible then
		-- You asked for it, so show it open rather than as a collapsed stub.
		setCollapsed(false)
	end
end

local function cleanup()
	if destroyed then
		return
	end
	destroyed = true
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	if adminCommand then
		adminCommand:Destroy()
		adminCommand = nil
	end
	screen:Destroy()
end

-- TextChatCommands is a default child of TextChatService under the current chat
-- system; guard anyway so a place with the legacy chat still gets the panel and
-- its F8 shortcut rather than erroring out of the whole module.
local chatCommands = TextChatService:FindFirstChild("TextChatCommands")
if chatCommands then
	local command = Instance.new("TextChatCommand")
	command.Name = "AdminPanelCommand"
	command.PrimaryAlias = "/admin"
	command.AutocompleteVisible = true
	command.Parent = chatCommands
	adminCommand = command
	table.insert(
		connections,
		command.Triggered:Connect(function()
			setPanelVisible(not screen.Enabled)
		end)
	)
else
	warn("[AdminClientUI] TextChatCommands missing; /admin unavailable, use F8")
end

-- Dragging -------------------------------------------------------------------

--[[
	Move the panel by its header.

	The header is also the collapse button, so a press has to resolve to one or
	the other. Anything that travels further than DRAG_SLOP is a drag and
	suppresses the click that Roblox fires afterwards; anything under it is a
	click and toggles the body as before.

	Note the panel is dragged with the mouse Ctrl-released (see CrosshairClient) —
	the place runs first person and pins the pointer otherwise.
]]
local DRAG_SLOP = 4

local dragging = false
local dragMoved = false
local dragStart = Vector2.zero
local dragOrigin = panel.Position

-- Keeps the panel reachable: a header dragged past the edge cannot be grabbed
-- again, and the only recovery would be rejoining. Resolves to pure offsets so
-- repeated drags compose cleanly.
local function clampToScreen(candidate: UDim2): UDim2
	local viewport = screen.AbsoluteSize
	local size = panel.AbsoluteSize
	local anchor = panel.AnchorPoint
	local left = candidate.X.Scale * viewport.X + candidate.X.Offset - anchor.X * size.X
	local top = candidate.Y.Scale * viewport.Y + candidate.Y.Offset - anchor.Y * size.Y
	left = math.clamp(left, 0, math.max(0, viewport.X - size.X))
	top = math.clamp(top, 0, math.max(0, viewport.Y - size.Y))
	return UDim2.fromOffset(left + anchor.X * size.X, top + anchor.Y * size.Y)
end

table.insert(
	connections,
	header.InputBegan:Connect(function(input: InputObject)
		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end
		dragging = true
		dragMoved = false
		dragStart = Vector2.new(input.Position.X, input.Position.Y)
		dragOrigin = panel.Position
	end)
)

table.insert(
	connections,
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if not dragging then
			return
		end
		if
			input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end
		local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStart
		if delta.Magnitude > DRAG_SLOP then
			dragMoved = true
		end
		panel.Position = clampToScreen(
			UDim2.new(
				dragOrigin.X.Scale,
				dragOrigin.X.Offset + delta.X,
				dragOrigin.Y.Scale,
				dragOrigin.Y.Offset + delta.Y
			)
		)
	end)
)

table.insert(
	connections,
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = false
		end
	end)
)

table.insert(
	connections,
	header.Activated:Connect(function()
		-- Roblox fires Activated at the end of a drag too; swallow that one.
		if dragMoved then
			dragMoved = false
			return
		end
		setCollapsed(not collapsed)
	end)
)

table.insert(
	connections,
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.F8 then
			setPanelVisible(not screen.Enabled)
		end
	end)
)

table.insert(
	connections,
	resultEvent.OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end

		local rawFeatureId = payload.featureId
		if typeof(rawFeatureId) == "string" then
			pending[rawFeatureId] = nil
			local feature = AdminConfig.findFeature(rawFeatureId)
			if feature then
				refreshFeature(feature)
			end
		end

		local ok = payload.ok == true
		local message = payload.message
		statusLabel.Text = if typeof(message) == "string" then message else if ok then "Updated" else "Request denied"
		statusLabel.TextColor3 = if ok then MUTED else ERROR
	end)
)

table.insert(
	connections,
	player:GetAttributeChangedSignal(AdminConfig.AuthorizedAttribute):Connect(function()
		if player:GetAttribute(AdminConfig.AuthorizedAttribute) ~= true then
			cleanup()
		end
	end)
)

for _, feature in AdminConfig.Features do
	refreshFeature(feature)
end
-- Built, wired and parented, but dark until `/admin` (or F8) asks for it. The
-- ScreenGui still exists so the feature buttons stay subscribed to their
-- attributes and the panel is correct the instant it is shown.
setCollapsed(false)
screen.Enabled = false
screen.Parent = playerGui

return true
