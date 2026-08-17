local part = script.Parent
local debounce = false

part.Touched:Connect(function(hit)
	if hit.Parent:FindFirstChild("Humanoid") and debounce == false then
		debounce = true
		hit.Parent.Humanoid:TakeDamage(40)
		wait(10)
		debounce = false
	end
end)


