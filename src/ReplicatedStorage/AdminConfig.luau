--!strict
-- Shared names for the small admin control surface. The client may request a
-- change, but only AdminService decides whether the request is authorized and
-- writes the replicated Player attributes below.

local AdminConfig = {}

AdminConfig.RemotesFolder = "AdminRemotes"
AdminConfig.ToggleEvent = "AdminToggle"
AdminConfig.ResultEvent = "AdminResult"

AdminConfig.AuthorizedAttribute = "AdminAuthorized"
AdminConfig.InvincibleAttribute = "AdminInvincible"
AdminConfig.AllClassesAttribute = "AdminAllClasses"
AdminConfig.InfiniteSprintAttribute = "AdminInfiniteSprint"

AdminConfig.ForceFieldName = "AdminInvincibilityForceField"
AdminConfig.ToggleCooldownSeconds = 0.12

AdminConfig.InvincibilityFeature = "invincibility"
AdminConfig.AllClassesFeature = "allClasses"
AdminConfig.InfiniteSprintFeature = "infiniteSprint"

export type Feature = {
	id: string,
	label: string,
	attribute: string,
}

local features: { Feature } = {
	{
		id = AdminConfig.InvincibilityFeature,
		label = "Invincibility",
		attribute = AdminConfig.InvincibleAttribute,
	},
	{
		id = AdminConfig.AllClassesFeature,
		label = "All classes",
		attribute = AdminConfig.AllClassesAttribute,
	},
	{
		id = AdminConfig.InfiniteSprintFeature,
		label = "Infinite sprint",
		attribute = AdminConfig.InfiniteSprintAttribute,
	},
}
AdminConfig.Features = features

-- Roblox usernames are unique and case-insensitive. Keep only normalized
-- account names here; display names never participate in authorization.
local authorizedUsernames: { [string]: boolean } = {
	lordadudes = true,
	kakusa3000 = true,
}

function AdminConfig.isAuthorizedUsername(username: string): boolean
	return authorizedUsernames[string.lower(username)] == true
end

function AdminConfig.findFeature(id: string): Feature?
	for _, feature in features do
		if feature.id == id then
			return feature
		end
	end
	return nil
end

return AdminConfig
