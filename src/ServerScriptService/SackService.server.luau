--!strict
--[[
	The sack: ten slots you fill by hovering something and pressing F.

	The model is the Dead Rails sack from the Creator Marketplace. The system
	around it is written here rather than taken from that asset, because the
	asset's version stored items by reparenting them from a LocalScript — a
	change that never leaves the client — and its server half looked objects up
	by GetDebugId() while walking the whole of Workspace on every request.

	Everything that matters is decided here:

	  * the client may ask to bag an instance, but the server checks the sack is
	    actually equipped, the item is really tagged collectable, it is still in
	    the world, and the player is close enough to it;
	  * a bagged item is not destroyed, it is parked in ServerStorage, so putting
	    it back down gives you the same mesh, the same attributes and the same
	    tags — which is what lets you drop food and then click it to eat, exactly
	    as if you had never picked it up.

	There is no "use from the sack". The readout is a counter with no slots to
	select, so eating means dropping the item and clicking it, the same as any
	other food in the hotel. Dropping is a real server-side toss: models get one
	invisible collision body, fall under gravity, bounce a little, and keep all
	of their edible/collectable state after they settle.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local ClassDefinitions = require(ReplicatedStorage:WaitForChild("ClassDefinitions"))
local ClueConfig = require(ReplicatedStorage:WaitForChild("ClueConfig"))
local SackConfig = require(ReplicatedStorage:WaitForChild("SackConfig"))
local SackPhysics = require(ServerStorage:WaitForChild("SackPhysics"))

local template = ServerStorage:FindFirstChild("SackTemplate")
if not template or not template:IsA("Tool") then
	warn("[SackService] ServerStorage.SackTemplate is missing — no sacks handed out")
	return
end

-- Remotes ---------------------------------------------------------------------

local function ensure(parent: Instance, name: string, className: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end
	local created = Instance.new(className)
	created.Name = name
	created.Parent = parent
	return created
end

local remotes = ensure(ReplicatedStorage, SackConfig.RemotesFolder, "Folder")
local storeEvent = ensure(remotes, SackConfig.StoreEvent, "RemoteEvent") :: RemoteEvent
local dropEvent = ensure(remotes, SackConfig.DropEvent, "RemoteEvent") :: RemoteEvent
local updateEvent = ensure(remotes, SackConfig.UpdateEvent, "RemoteEvent") :: RemoteEvent

-- Where bagged items wait. Out of Workspace so they stop rendering and stop
-- being clickable, but still alive so they can be put back exactly as they were.
local vault = ensure(ServerStorage, "SackVault", "Folder")
local consumeEvent = ensure(ServerStorage, ClueConfig.SackConsumeEvent, "BindableEvent") :: BindableEvent

type Entry = {
	name: string,
	instance: Instance,
}

local packs: { [Player]: { Entry } } = {}

local DROP_FORWARD_OFFSET = 3.25
local DROP_UP_OFFSET = 1
local DROP_FORWARD_SPEED = 9
local DROP_UP_SPEED = 4.5
local DROP_SPIN_SPEED = 5

-- Helpers ---------------------------------------------------------------------

local function displayName(instance: Instance): string
	return instance.Name
end

local function anchorPart(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function holdingSack(player: Player): boolean
	local character = player.Character
	if not character then
		return false
	end
	local tool = character:FindFirstChild(SackConfig.ToolName)
	return tool ~= nil and tool:IsA("Tool")
end

local function describe(player: Player): { SackConfig.Slot }
	local list: { SackConfig.Slot } = {}
	local pack: { Entry } = packs[player] or {}
	for _, entry in pack do
		table.insert(list, { name = entry.name })
	end
	return list
end

local function push(player: Player)
	updateEvent:FireClient(player, describe(player))
end

-- ClueService owns whether a carried quest object has satisfied its
-- receptacle; SackService owns the private pack table. A server-only event is
-- the narrow bridge between those authorities, so consuming a keycard cannot
-- leave a dead entry occupying one of the player's ten slots.
consumeEvent.Event:Connect(function(player: any, carryId: any)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or typeof(carryId) ~= "string" then
		return
	end
	local pack = packs[player]
	if not pack then
		return
	end

	for index = #pack, 1, -1 do
		local entry = pack[index]
		if entry.instance:GetAttribute(ClueConfig.CarryIdAttribute) == carryId then
			table.remove(pack, index)
			if entry.instance.Parent then
				entry.instance:Destroy()
			end
			push(player)
			return
		end
	end
end)

local function vaultFor(player: Player): Folder
	local existing = vault:FindFirstChild(tostring(player.UserId))
	if existing then
		return existing :: Folder
	end
	local created = Instance.new("Folder")
	created.Name = tostring(player.UserId)
	created.Parent = vault
	return created
end

-- Storing ---------------------------------------------------------------------

storeEvent.OnServerEvent:Connect(function(player: Player, target: any)
	if typeof(target) ~= "Instance" then
		return
	end
	if not holdingSack(player) then
		return
	end

	local pack = packs[player]
	if not pack then
		return
	end
	if #pack >= SackConfig.Capacity then
		return
	end

	-- It must be a real, tagged, in-world item. A client asking for anything
	-- else — a wall, a player, something already bagged — gets nothing.
	if not CollectionService:HasTag(target, SackConfig.CollectableTag) then
		return
	end
	if target:GetAttribute(SackConfig.LockedAttribute) == true then
		return
	end
	local requiredClass = target:GetAttribute(SackConfig.RequiredClassAttribute)
	if typeof(requiredClass) == "string" and not ClassDefinitions.hasClass(player, requiredClass) then
		return
	end
	if not target:IsDescendantOf(Workspace) then
		return
	end

	local part = anchorPart(target)
	local character = player.Character
	if not character then
		return
	end
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not part or not root or not root:IsA("BasePart") then
		return
	end
	if (root.Position - part.Position).Magnitude > SackConfig.Reach + 4 then
		return
	end

	local entry: Entry = {
		name = displayName(target),
		instance = target,
	}

	-- Parked, not destroyed: dropping it later gives back the same mesh.
	SackPhysics.freeze(target)
	target.Parent = vaultFor(player)
	table.insert(pack, entry)
	push(player)
end)

-- Dropping --------------------------------------------------------------------

dropEvent.OnServerEvent:Connect(function(player: Player, slot: any)
	if typeof(slot) ~= "number" then
		return
	end
	if not holdingSack(player) then
		return
	end
	local pack = packs[player]
	if not pack then
		return
	end
	local index = math.floor(slot)
	local entry = pack[index]
	if not entry then
		return
	end

	local character = player.Character
	if not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end

	local item = entry.instance
	table.remove(pack, index)

	if item and item.Parent then
		SackPhysics.freeze(item)

		-- Keep the toss on the player's side of a nearby wall. The character is
		-- excluded so the ray starts inside it without immediately hitting it.
		local look = root.CFrame.LookVector
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = { character }
		local obstruction = Workspace:Raycast(root.Position, look * DROP_FORWARD_OFFSET, rayParams)
		local forward = if obstruction then math.max(obstruction.Distance - 0.75, 0.75) else DROP_FORWARD_OFFSET
		local origin = root.Position + look * forward + Vector3.new(0, DROP_UP_OFFSET, 0)
		local orientation = root.CFrame.Rotation
			* CFrame.Angles(math.rad(-12), math.rad(math.random(-18, 18)), math.rad(math.random(-8, 8)))

		item.Parent = Workspace
		SackPhysics.positionAt(item, CFrame.new(origin) * orientation)
		local physicsBody = SackPhysics.makePhysical(item)
		if physicsBody then
			physicsBody.AssemblyLinearVelocity = root.AssemblyLinearVelocity
				+ look * DROP_FORWARD_SPEED
				+ Vector3.new(0, DROP_UP_SPEED, 0)
			physicsBody.AssemblyAngularVelocity = Vector3.new(
				math.random(-DROP_SPIN_SPEED, DROP_SPIN_SPEED),
				math.random(-DROP_SPIN_SPEED, DROP_SPIN_SPEED),
				math.random(-DROP_SPIN_SPEED, DROP_SPIN_SPEED)
			)
		end
	end
	push(player)
end)

-- Handing out the sack --------------------------------------------------------

local function giveTo(player: Player)
	local gear = player:FindFirstChildOfClass("StarterGear")
	if gear and not gear:FindFirstChild(SackConfig.ToolName) then
		local stored = template:Clone()
		stored.Name = SackConfig.ToolName
		stored.Parent = gear
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	local character = player.Character
	local held = character ~= nil and character:FindFirstChild(SackConfig.ToolName) ~= nil
	if backpack and not backpack:FindFirstChild(SackConfig.ToolName) and not held then
		local copy = template:Clone()
		copy.Name = SackConfig.ToolName
		copy.Parent = backpack
	end
end

local function watch(player: Player)
	packs[player] = packs[player] or {}
	giveTo(player)
	push(player)
	player.CharacterAdded:Connect(function()
		task.defer(function()
			giveTo(player)
			push(player) -- the sack survives death; the UI needs telling again
		end)
	end)
end

for _, player in Players:GetPlayers() do
	watch(player)
end
Players.PlayerAdded:Connect(watch)

Players.PlayerRemoving:Connect(function(player: Player)
	packs[player] = nil
	local folder = vault:FindFirstChild(tostring(player.UserId))
	if folder then
		folder:Destroy()
	end
end)

print(string.format("[SackService] ready — %d slots, F to bag what you are looking at", SackConfig.Capacity))
