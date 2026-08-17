local Tool = script.Parent;

enabled = true




function onActivated()
	if not enabled  then
		return
	end

	enabled = false
	Tool.GripForward = Vector3.new(0,-.759,-.651)
	Tool.GripPos = Vector3.new(1.5,-.5,.3)
	Tool.GripRight = Vector3.new(1,0,0)
	Tool.GripUp = Vector3.new(0,.651,-.759)


	Tool.Handle.DrinkSound:Play()

	wait(3)
	
	local h = Tool.Parent:FindFirstChild("Humanoid")
	if (h ~= nil) then
		if (h.MaxHealth > h.Health + 100) then
			h.Health = h.Health + 100
			
		else	
			h.Health = h.MaxHealth
		end
	end

	Tool.GripForward = Vector3.new(-.976,0,-0.217)
	Tool.GripPos = Vector3.new(0.03,0,0)
	Tool.GripRight = Vector3.new(.217,0,-.976)
	Tool.GripUp = Vector3.new(0,1,0)

	enabled = true

end

	function onEquipped()
		Tool.Handle.OpenSound:play()
	end

	script.Parent.Activated:connect(onActivated)
	script.Parent.Equipped:connect(onEquipped)


	local Debris = game:GetService("Debris")
	local tool = script.Parent

	local function onActivated()
		
		-- 2. Clean up and destroy the tool permanently after 5 seconds
		Debris:AddItem(tool, 4
		)
	end

	tool.Activated:Connect(onActivated)
