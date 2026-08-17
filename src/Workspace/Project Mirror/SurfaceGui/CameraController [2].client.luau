--Script Edit by Dragonfire1710
--Credits to boatbomber for the ViewportFrame Handler


workspace:WaitForChild("Mirror")
local ViewportHandler = require(script.ViewportHandler)

local Frame = script.Parent.ViewportFrame
wait(1)
local c = Instance.new("Camera")
	c.CFrame = workspace.Mirror.Part.Cam1.CFrame
	Frame.CurrentCamera = c

local VF_Handler = ViewportHandler.new(Frame)

-- Render the map at 0FPS (static since we know it doesn't change)

	--for i,d in pairs(workspace.Map:GetDescendants()) do
--		if d:IsA("BasePart") then
	--		local mapObj_Handler = VF_Handler:RenderObject(d)
	--	end
--	end

-- Render other objects at medium FPS

	for i,d in pairs(workspace:GetDescendants()) do
		if d.Name ~= "Terrain" and game.Players:FindFirstChild(d.Parent.Name) == nil and game.Players:FindFirstChild(d.Name) == nil and d.Parent.Name ~= "Mirror" then
		if d:IsA("BasePart") then
			local ball_Handler = VF_Handler:RenderObject(d, 30)			
		end
		end
	end

-- Render players (Will run at max FPS)

	-- initial players
	for i,plr in pairs(game.Players:GetPlayers()) do
		local plr_Handler = VF_Handler:RenderHumanoid(plr.Character or plr.CharacterAdded:Wait())
	end
	
	-- joining players
	game.Players.PlayerAdded:Connect(function(plr)
		local plr_Handler = VF_Handler:RenderHumanoid(plr.Character or plr.CharacterAdded:Wait())
	end)

-- Put us by the screen so we can see it's working
--local c = game.Players.LocalPlayer.Character or game.game.Players.LocalPlayer.CharacterAdded:Wait()
--c.HumanoidRootPart.CFrame = CFrame.new(workspace.Screen.Position+Vector3.new(5,0,0))