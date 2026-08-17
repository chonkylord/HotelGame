--> LOCAL VARIABLES
local Module = script.Parent
local LightPart = Module:WaitForChild("Light"):WaitForChild("LightPart")
local Light = LightPart:WaitForChild("SpotLight")
local LightModule = Module:WaitForChild("LightSwitch")
local SwitchPart = LightModule:WaitForChild("ClickPart")
local Switch_On = LightModule:WaitForChild("Switch_On")
local Switch_Off = LightModule:WaitForChild("Switch_Off")
local Brightness = Module:WaitForChild("LightBrightness").Value
local Range = Module:WaitForChild("LightRange").Value
local Switched_On = false

--> LIGHT SETUP
Light.Brightness = Brightness
Light.Range = Range

--> FUNCTIONS
SwitchPart.ClickDetector.MouseClick:Connect(function()
	if not Switched_On then
		Switched_On = true
		Switch_On.Sound:Play()
		Switch_On.Transparency = 1
		Switch_Off.Transparency = 0
		LightPart.Material = "Neon"
		LightPart.SpotLight.Enabled = true
	else
		Switched_On = false
		Switch_On.Sound:Play()
		Switch_On.Transparency = 0
		Switch_Off.Transparency = 1
		LightPart.Material = "Glass"
		LightPart.SpotLight.Enabled = false
	end
end)