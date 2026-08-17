--!strict
-- A mild old-television texture over the final game image. This is entirely
-- client-side UI: it cannot block input and creates no world parts or items.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local GUI_NAME = "CRTStatic"
local UPDATE_RATE = 14
local SCANLINE_COUNT = 160
local GRAIN_COUNT = 140
local INTERFERENCE_COUNT = 3

local existing = playerGui:FindFirstChild(GUI_NAME)
if existing then
	existing:Destroy()
end

local screen = Instance.new("ScreenGui")
screen.Name = GUI_NAME
screen.DisplayOrder = 45 -- over the HUD, under the aiming dot
screen.IgnoreGuiInset = true
screen.ResetOnSpawn = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

local root = Instance.new("Frame")
root.Name = "Overlay"
root.BackgroundColor3 = Color3.fromRGB(9, 13, 18)
root.BackgroundTransparency = 0.992
root.BorderSizePixel = 0
root.Size = UDim2.fromScale(1, 1)
root.Active = false
root.Selectable = false
root.Parent = screen

-- The almost-invisible full-screen wash is the part that makes the entire
-- image breathe with static rather than limiting the effect to isolated dots.
local wash = Instance.new("Frame")
wash.Name = "SignalNoise"
wash.BackgroundColor3 = Color3.fromRGB(210, 220, 228)
wash.BackgroundTransparency = 0.996
wash.BorderSizePixel = 0
wash.Size = UDim2.fromScale(1, 1)
wash.ZIndex = 1
wash.Parent = root

local scanlines = Instance.new("Frame")
scanlines.Name = "Scanlines"
scanlines.BackgroundTransparency = 1
scanlines.BorderSizePixel = 0
scanlines.Size = UDim2.fromScale(1, 1)
scanlines.ZIndex = 2
scanlines.Parent = root

for index = 1, SCANLINE_COUNT do
	local line = Instance.new("Frame")
	line.Name = "Line"
	line.BackgroundColor3 = Color3.fromRGB(0, 2, 5)
	line.BackgroundTransparency = 0.965
	line.BorderSizePixel = 0
	line.Position = UDim2.fromScale(0, (index - 0.5) / SCANLINE_COUNT)
	line.Size = UDim2.new(1, 0, 0, 1)
	line.ZIndex = 2
	line.Parent = scanlines
end

local grainLayer = Instance.new("Frame")
grainLayer.Name = "Grain"
grainLayer.BackgroundTransparency = 1
grainLayer.BorderSizePixel = 0
grainLayer.Size = UDim2.fromScale(1, 1)
grainLayer.ZIndex = 3
grainLayer.Parent = root

local grain: { Frame } = {}
for _ = 1, GRAIN_COUNT do
	local speck = Instance.new("Frame")
	speck.Name = "Noise"
	speck.BorderSizePixel = 0
	speck.ZIndex = 3
	speck.Parent = grainLayer
	table.insert(grain, speck)
end

local interference: { Frame } = {}
for _ = 1, INTERFERENCE_COUNT do
	local band = Instance.new("Frame")
	band.Name = "Interference"
	band.BackgroundColor3 = Color3.fromRGB(190, 210, 220)
	band.BackgroundTransparency = 1
	band.BorderSizePixel = 0
	band.ZIndex = 4
	band.Parent = root
	table.insert(interference, band)
end

local random = Random.new()
local accumulator = 0
local scanlineOffset = 0

local function redrawNoise()
	-- Less than one percent of luminance movement: felt as an unstable signal,
	-- but never enough to change whether something is visible in the dark.
	local brightFrame = random:NextNumber() > 0.48
	wash.BackgroundColor3 = if brightFrame then Color3.fromRGB(220, 228, 235) else Color3.fromRGB(2, 5, 9)
	wash.BackgroundTransparency = random:NextNumber(0.987, 0.990)

	scanlineOffset = 1 - scanlineOffset
	scanlines.Position = UDim2.fromOffset(0, scanlineOffset)

	for _, speck in grain do
		local value = random:NextInteger(145, 235)
		local cool = random:NextInteger(0, 10)
		speck.BackgroundColor3 = Color3.fromRGB(value - cool, value, math.min(value + cool, 255))
		speck.BackgroundTransparency = random:NextNumber(0.84, 0.95)
		speck.Position = UDim2.fromScale(random:NextNumber(), random:NextNumber())
		speck.Size = UDim2.fromOffset(random:NextInteger(1, 7), random:NextInteger(1, 2))
	end

	for _, band in interference do
		if random:NextNumber() < 0.045 then
			local dark = random:NextNumber() < 0.55
			band.BackgroundColor3 = if dark then Color3.fromRGB(0, 4, 9) else Color3.fromRGB(180, 205, 218)
			band.BackgroundTransparency = random:NextNumber(0.94, 0.98)
			band.Position = UDim2.new(0, random:NextInteger(-8, 8), random:NextNumber(), 0)
			band.Size = UDim2.new(1, random:NextInteger(0, 18), 0, random:NextInteger(1, 6))
		else
			band.BackgroundTransparency = 1
		end
	end
end

redrawNoise()

RunService.RenderStepped:Connect(function(deltaTime: number)
	accumulator += deltaTime
	if accumulator < 1 / UPDATE_RATE then
		return
	end
	accumulator %= 1 / UPDATE_RATE
	redrawNoise()
end)
