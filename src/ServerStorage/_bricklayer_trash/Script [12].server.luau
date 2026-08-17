local Teams = game:GetService("Teams")
local Players = game:GetService("Players")

local pad = script.Parent
local targetTeam = Teams:WaitForChild("SuperHero")

pad.Touched:Connect(function(hit)
	local character = hit.Parent
	local player = Players:GetPlayerFromCharacter(character)

	if player then
		-- Check if the player is already on this team
		if player.Team == targetTeam then return end

		-- Check if the team is available
		local currentPlayers = targetTeam:GetPlayers()
		if #currentPlayers < 1 then
			player.Team = targetTeam
		end
	end
end)
