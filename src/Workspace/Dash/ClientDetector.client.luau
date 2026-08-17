local tool = script.Parent
local dashEvent = tool:WaitForChild("DashEvent")

tool.Activated:Connect(function() 
	dashEvent:FireServer()
end)