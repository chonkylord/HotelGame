local part = script.Parent
local players = game:GetService("Players")
local debounce = false

part.Touched:Connect(function(hit)
	local character = hit.Parent
	local humanoid = character and character:FindFirstChild("Humanoid")
	local player = if character then players:GetPlayerFromCharacter(character) else nil
	if humanoid and debounce == false and not (player and player:GetAttribute("AdminInvincible") == true) then
		debounce = true
		humanoid:TakeDamage(40)
		task.wait(10)
		debounce = false
	end
end)
