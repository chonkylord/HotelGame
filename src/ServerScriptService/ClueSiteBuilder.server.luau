--!strict
--[[
	Owns the only hard-coded clue coordinates in the game. Runtime clue systems
	resolve these anchors by tag and SiteId, so a designer can drag a marker in
	Studio without teaching gameplay code about the hotel's geometry. Existing
	markers win over defaults; generated duplicates are the only things this
	builder is allowed to remove.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ClueConfig = require(ReplicatedStorage:WaitForChild("ClueConfig"))

type SitePlacement = {
	id: string,
	cframe: CFrame,
}

local function facing(position: Vector3, direction: Vector3): CFrame
	return CFrame.lookAt(position, position + direction)
end

-- These positions were measured against the live Bricklayer place. CFrames
-- sit on a walkable surface beside the named landmark rather than inside its
-- decorative geometry. ClueConfig limits each anchor to prop footprints that
-- make spatial and narrative sense there.
local placements: { SitePlacement } = {
	{
		id = "ReceptionDesk",
		cframe = facing(Vector3.new(-58, 18.05, 141.5), Vector3.new(0, 0, 1)),
	},
	{
		id = "ClassPodiums",
		cframe = facing(Vector3.new(-87.8, 18.05, 78.35), Vector3.new(-1, 0, 0)),
	},
	{
		id = "Room2Bed",
		cframe = facing(Vector3.new(238, 18.05, 27.5), Vector3.new(-1, 0, 0)),
	},
	{
		id = "StorageBreaker",
		cframe = facing(Vector3.new(282.5, 32.7, 56), Vector3.new(-1, 0, 0)),
	},
	{
		id = "RestaurantBuffet",
		cframe = facing(Vector3.new(218.1, 32.75, 23), Vector3.new(0, 0, 1)),
	},
	{
		id = "BallroomStage",
		cframe = facing(Vector3.new(319.4, 33.4, 27.45), Vector3.new(0, 0, -1)),
	},
	{
		id = "SuiteA_Midnight",
		cframe = facing(Vector3.new(550, 33.8, 14), Vector3.new(-1, 0, 0)),
	},
	{
		id = "SuiteB_Garnet",
		cframe = facing(Vector3.new(570, 33.8, 14), Vector3.new(1, 0, 0)),
	},
	{
		id = "SuiteC_Presidential",
		cframe = facing(Vector3.new(560, 33.8, -45), Vector3.new(0, 0, -1)),
	},
	{
		id = "LobbyElevator",
		cframe = facing(Vector3.new(-89, 18.05, 152.1), Vector3.new(-1, 0, 0)),
	},
	{
		id = "CorridorPanels",
		cframe = facing(Vector3.new(260.35, 18.05, -91), Vector3.new(0, 0, -1)),
	},
	{
		id = "ProjectMirror",
		cframe = facing(Vector3.new(612.9, 33.8, 6.5), Vector3.new(0, 0, 1)),
	},
	{
		id = "WaterFountain",
		cframe = facing(Vector3.new(-79, 18.05, 106), Vector3.new(0, 0, 1)),
	},
	{
		id = "VaultFacade",
		-- Rode up with the vault when it moved from the sealed sublevel to the
		-- surface: 0.1 above the anchor's floor, same as it always sat.
		cframe = facing(Vector3.new(960, 19.1, 6), Vector3.new(0, 0, 1)),
	},
}

local placementById: { [string]: SitePlacement } = {}
for _, placement in placements do
	placementById[placement.id] = placement
end

-- Prefer anything authored by hand over a generated fallback. This is what
-- makes moving a marker in Studio durable across a server restart.
local markerById: { [string]: BasePart } = {}

local function consider(marker: BasePart)
	local rawId = marker:GetAttribute(ClueConfig.SiteIdAttribute)
	if typeof(rawId) ~= "string" or not placementById[rawId] then
		if marker:GetAttribute(ClueConfig.GeneratedSiteAttribute) == true then
			marker:Destroy()
		end
		return
	end

	local existing = markerById[rawId]
	if not existing then
		markerById[rawId] = marker
		return
	end

	local existingGenerated = existing:GetAttribute(ClueConfig.GeneratedSiteAttribute) == true
	local markerGenerated = marker:GetAttribute(ClueConfig.GeneratedSiteAttribute) == true
	if existingGenerated and not markerGenerated then
		existing:Destroy()
		markerById[rawId] = marker
	elseif markerGenerated then
		marker:Destroy()
	else
		warn(`[ClueSiteBuilder] duplicate authored ClueSite for "{rawId}"; preserving both`)
	end
end

for _, instance in CollectionService:GetTagged(ClueConfig.SiteTag) do
	if instance:IsA("BasePart") and instance:IsDescendantOf(Workspace) then
		consider(instance)
	end
end

-- A generated marker whose tag was removed in Studio is still recoverable.
-- Re-tag it rather than stacking a second invisible marker in the same place.
for _, instance in Workspace:GetDescendants() do
	if
		instance:IsA("BasePart")
		and instance:GetAttribute(ClueConfig.GeneratedSiteAttribute) == true
		and instance.Parent
		and not CollectionService:HasTag(instance, ClueConfig.SiteTag)
	then
		local rawId = instance:GetAttribute(ClueConfig.SiteIdAttribute)
		if typeof(rawId) == "string" and placementById[rawId] and not markerById[rawId] then
			CollectionService:AddTag(instance, ClueConfig.SiteTag)
			markerById[rawId] = instance
		else
			instance:Destroy()
		end
	end
end

local siteParent: Instance = Workspace
local existingFolder = Workspace:FindFirstChild("ClueSites")
if existingFolder and existingFolder:IsA("Folder") then
	siteParent = existingFolder
elseif not existingFolder then
	local folder = Instance.new("Folder")
	folder.Name = "ClueSites"
	folder.Parent = Workspace
	siteParent = folder
else
	warn("[ClueSiteBuilder] Workspace.ClueSites is not a Folder; placing markers in Workspace")
end

local createdCount = 0
for _, site in ClueConfig.Sites do
	if not markerById[site.id] then
		local placement = placementById[site.id]
		if not placement then
			warn(`[ClueSiteBuilder] no measured placement for configured site "{site.id}"`)
			continue
		end

		local marker = Instance.new("Part")
		marker.Name = `ClueSite_{site.id}`
		marker.Anchored = true
		marker.CanCollide = false
		marker.CanQuery = false
		marker.CanTouch = false
		marker.CastShadow = false
		marker.Size = Vector3.new(1, 0.2, 1)
		marker.CFrame = placement.cframe
		marker.Transparency = 1
		marker:SetAttribute(ClueConfig.SiteIdAttribute, site.id)
		marker:SetAttribute(ClueConfig.GeneratedSiteAttribute, true)
		marker.Parent = siteParent
		CollectionService:AddTag(marker, ClueConfig.SiteTag)
		markerById[site.id] = marker
		createdCount += 1
	end
end

print(`[ClueSiteBuilder] ready — {#ClueConfig.Sites} sites ({createdCount} generated this run)`)
