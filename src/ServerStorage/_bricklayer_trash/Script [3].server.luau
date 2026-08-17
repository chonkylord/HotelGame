open = false

door1 = script.Parent.Parent.Parent.Door1

door2 = script.Parent.Parent.Parent.Door2

local TweenService = game:GetService("TweenService")

local part = script.Parent

local tweenInfo = TweenInfo.new(2, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, 0)

local Door1Open = { CFrame = door1.CFrame + door1.CFrame.lookVector * 4 }

local Door2Open = { CFrame = door2.CFrame + door2.CFrame.lookVector * 4 }

local Door1Close = { CFrame = door1.CFrame }

local Door2Close = { CFrame = door2.CFrame }

local Open1 = TweenService:Create(door1, tweenInfo, Door1Open)

local Open2 = TweenService:Create(door2, tweenInfo, Door2Open)

local Close1 = TweenService:Create(door1, tweenInfo, Door1Close)

local Close2 = TweenService:Create(door2, tweenInfo, Door2Close)

script.Parent.MouseClick:connect(function()
	if open == false then
		Open1:Play()

		Open2:Play()

		script.Parent.Parent.Parent.open.Playing = true

		wait(2)

		open = true
	else
		Close1:Play()

		Close2:Play()

		script.Parent.Parent.Parent.close.Playing = true

		wait(2)

		open = false
	end
end)
