--!strict
--[[
	The hotel's global horror grade.

	No useful light comes from the sky or from ambient fill. Rooms are shaped by
	their actual fixtures, candles, and player flashlights; long corridors
	disappear into cold haze instead of remaining evenly readable. Fixture
	dimming and flicker live in LightFlicker, the lobby's local reprieve in
	HorrorVisibilityZones, and the torch's beam in the flashlight tool.

	The ambient/exposure/fog half of the grade comes from HorrorGradeProfiles so
	that the lobby script tweens against the same numbers this one applies.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Profiles = require(ReplicatedStorage:WaitForChild("HorrorGradeProfiles"))

-- Night -----------------------------------------------------------------------

Lighting.ClockTime = 12
-- The moon, and nothing else. Every window in the place is a faint blue smear
-- rather than a light source.
Lighting.Brightness = 1
Lighting.ColorShift_Top = Color3.fromRGB(3, 6, 12)
Lighting.ColorShift_Bottom = Color3.fromRGB(0, 0, 0)
-- Image-based fill is the quiet way a dark scene becomes a grey one: it lights
-- surfaces no fixture reaches. Kept well down, but not off — at 0.03 the
-- unlit half of a room had no shape at all, only an edge where the fixture's
-- reach stopped.
Lighting.EnvironmentDiffuseScale = 0.08
Lighting.EnvironmentSpecularScale = 0.09
Lighting.GlobalShadows = true
-- A small penumbra keeps contact shadows legible without turning furniture
-- silhouettes into razor-edged cut-outs.
Lighting.ShadowSoftness = 0.18

Lighting.FogColor = Color3.fromRGB(5, 7, 11)

for property, value in Profiles.Dark.lighting do
	(Lighting :: any)[property] = value
end

local function effect(name: string, className: string): Instance
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local created = Instance.new(className)
	created.Name = name
	created.Parent = Lighting
	return created
end

-- Crushed blacks, cold moonlight, and restrained colour make the warm practical
-- lights stand out without washing every material into grey.
local grade = effect("HorrorGrade", "ColorCorrectionEffect") :: ColorCorrectionEffect
grade.Enabled = true
for property, value in Profiles.Dark.grade do
	(grade :: any)[property] = value
end

-- The place shipped with another warm correction enabled. Stacking it over the
-- horror grade crushed extra midtones and made darkness look muddy rather than
-- deep, so the authored grade is now the only active colour correction.
for _, child in Lighting:GetChildren() do
	if child:IsA("ColorCorrectionEffect") and child ~= grade then
		child.Enabled = false
	end
end

-- Only the hottest bulbs and the flashlight core bloom. The low intensity avoids
-- the soft, glossy look of a modern cinematic filter.
local bloom = effect("HorrorBloom", "BloomEffect") :: BloomEffect
bloom.Enabled = true
bloom.Intensity = 0.18
bloom.Size = 18
bloom.Threshold = 1.55

-- Reuse the place's existing atmosphere instead of stacking two haze volumes.
local foundAtmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
local atmosphere = if foundAtmosphere then foundAtmosphere else effect("HorrorAtmosphere", "Atmosphere") :: Atmosphere
atmosphere.Density = 0.28
atmosphere.Offset = 0.08
atmosphere.Color = Color3.fromRGB(70, 79, 98)
atmosphere.Decay = Color3.fromRGB(10, 13, 22)
atmosphere.Glare = 0
atmosphere.Haze = 1.9

-- Barely-there far focus falloff gives distant halls depth while leaving the
-- flashlight's useful range and everything near the player fully sharp.
local depth = effect("DepthOfField", "DepthOfFieldEffect") :: DepthOfFieldEffect
depth.Enabled = true
depth.FocusDistance = 18
depth.InFocusRadius = 50
depth.NearIntensity = 0
depth.FarIntensity = 0.045

-- Sun shafts reveal too much geometry at night and fight the flashlight cone.
for _, child in Lighting:GetChildren() do
	if child:IsA("SunRaysEffect") then
		child.Enabled = false
	end
end

print("[HorrorLighting] night grade active; fixtures and the flashlight shape every room")
