--!strict

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
local tweenInfo = TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

local gui = Instance.new("ScreenGui")
gui.Name = "ClosetHidingGui"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.Enabled = false
gui.DisplayOrder = 25
gui.Parent = playerGui

local function makeShade(name: string, position: UDim2, size: UDim2, rotation: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Position = position
	frame.Size = size
	frame.BackgroundColor3 = Color3.fromRGB(3, 4, 5)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = frame
	return frame
end

local shades = {
	makeShade("TopShade", UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.22), 90),
	makeShade("BottomShade", UDim2.fromScale(0, 0.78), UDim2.fromScale(1, 0.22), 270),
	makeShade("LeftShade", UDim2.fromScale(0, 0), UDim2.fromScale(0.18, 1), 0),
	makeShade("RightShade", UDim2.fromScale(0.82, 0), UDim2.fromScale(0.18, 1), 180),
}

local status = Instance.new("TextLabel")
status.Name = "Status"
status.AnchorPoint = Vector2.new(0.5, 1)
status.Position = UDim2.fromScale(0.5, 0.94)
status.Size = UDim2.fromOffset(280, 34)
status.BackgroundTransparency = 1
status.Text = "HIDDEN  •  PRESS E TO LEAVE"
status.TextColor3 = Color3.fromRGB(221, 225, 226)
status.TextTransparency = 1
status.Font = Enum.Font.GothamMedium
status.TextSize = 14
status.Parent = gui

local colourEffect = Instance.new("ColorCorrectionEffect")
colourEffect.Name = "ClosetColour"
colourEffect.Brightness = 0
colourEffect.Contrast = 0
colourEffect.Saturation = 0
colourEffect.TintColor = Color3.new(1, 1, 1)
colourEffect.Parent = Workspace.CurrentCamera

local defaultFieldOfView = if Workspace.CurrentCamera then Workspace.CurrentCamera.FieldOfView else 70

local function setHidden(hidden: boolean)
	local camera = Workspace.CurrentCamera
	if hidden then
		if camera then
			defaultFieldOfView = camera.FieldOfView
			colourEffect.Parent = camera
			TweenService:Create(camera, tweenInfo, { FieldOfView = math.max(58, defaultFieldOfView - 8) }):Play()
		end
		gui.Enabled = true
		for _, shade in shades do
			TweenService:Create(shade, tweenInfo, { BackgroundTransparency = 0.16 }):Play()
		end
		TweenService:Create(status, tweenInfo, { TextTransparency = 0.12 }):Play()
		TweenService:Create(colourEffect, tweenInfo, {
			Brightness = -0.08,
			Contrast = 0.12,
			Saturation = -0.28,
			TintColor = Color3.fromRGB(210, 220, 226),
		}):Play()
	else
		if camera then
			TweenService:Create(camera, tweenInfo, { FieldOfView = defaultFieldOfView }):Play()
		end
		for _, shade in shades do
			TweenService:Create(shade, tweenInfo, { BackgroundTransparency = 1 }):Play()
		end
		TweenService:Create(status, tweenInfo, { TextTransparency = 1 }):Play()
		TweenService:Create(colourEffect, tweenInfo, {
			Brightness = 0,
			Contrast = 0,
			Saturation = 0,
			TintColor = Color3.new(1, 1, 1),
		}):Play()
		task.delay(tweenInfo.Time, function()
			if not player:GetAttribute("HidingInCloset") then
				gui.Enabled = false
			end
		end)
	end
end

player:GetAttributeChangedSignal("HidingInCloset"):Connect(function()
	setHidden(player:GetAttribute("HidingInCloset") == true)
end)
setHidden(player:GetAttribute("HidingInCloset") == true)
