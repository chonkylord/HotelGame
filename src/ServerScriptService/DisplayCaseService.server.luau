--!strict
--[[
	The treasury's display cases: what a hit on one means.

	Four vitrines stand in the vault — two against the rear wall and two on the
	plinths by the door. Each is a Model tagged VaultDisplayCase holding one
	opaque Base and five panes tagged BreakableGlass. They are authored, saved
	instances; this service never builds them, it binds behaviour to the tags.

	The seam with MalletService is one ServerStorage BindableEvent. MalletService
	knows how a swing works and decides that one connected; this service knows
	what a vitrine is and decides whether the glass goes and what that opens up.
	Neither has to know how the other does its half, and a future crowbar or
	thrown chair can break the same glass by firing the same event.

	Server authority: the event carries a player and a part, and both are
	re-checked here — the part must still be tagged glass, still be in the world,
	and the player must still be standing next to it. Taking an exhibit out of an
	opened case is checked the same way. Nothing in this file trusts a client,
	because nothing in this file talks to one.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local BreakableGlass = require(ServerStorage:WaitForChild("BreakableGlass"))
local ClassDefinitions = require(ReplicatedStorage:WaitForChild("ClassDefinitions"))
local DisplayCaseConfig = require(ReplicatedStorage:WaitForChild("DisplayCaseConfig"))
local SackConfig = require(ReplicatedStorage:WaitForChild("SackConfig"))

local TAKE_PROMPT_NAME = "TakeExhibit"

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

local struckEvent = ensure(ServerStorage, DisplayCaseConfig.StruckEvent, "BindableEvent") :: BindableEvent

-- The same folder and remote MalletService ensures, reached the same way: both
-- files hang notices on the same plaque, and whichever starts first creates it.
local remotes = ensure(ReplicatedStorage, DisplayCaseConfig.RemotesFolder, "Folder")
local refusedEvent = ensure(remotes, DisplayCaseConfig.RefusalEvent, "RemoteEvent") :: RemoteEvent

-- Contents --------------------------------------------------------------------

--[[
	The case an instance belongs to, if any.

	Declared up here rather than beside the breaking code because taking an
	exhibit needs it as much as hitting one does: both have to answer "which
	vitrine is this, and is it open yet?"
]]
local function caseFor(part: Instance): Model?
	local node: Instance? = part
	while node and node ~= Workspace do
		if node:IsA("Model") and CollectionService:HasTag(node, DisplayCaseConfig.CaseTag) then
			return node
		end
		node = node.Parent
	end
	return nil
end

local function playerRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

--[[
	Hand an exhibit over.

	The Sun Sword sits anchored on its mounts, which is the only way a Tool can
	be part of a display rather than a thing lying on the floor waiting to be
	walked into — and it is also exactly what stops it working once it is in a
	hand, because an anchored Handle cannot follow the grip weld. Unanchoring at
	the moment of the handover is the whole fix.
]]
local function takeExhibit(player: Player, tool: Tool, prompt: ProximityPrompt)
	if not tool:IsDescendantOf(Workspace) then
		return
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = playerRoot(player)
	local handle = tool:FindFirstChild("Handle")
	if not backpack or not humanoid or not root or not handle or not handle:IsA("BasePart") then
		return
	end
	if (root.Position - handle.Position).Magnitude > DisplayCaseConfig.PromptDistance + 4 then
		return
	end

	-- The glass first, always. A prompt only exists because armContents ran, and
	-- armContents only runs on a shatter -- but existence is not authority. A
	-- prompt saved into the place by a Studio run that broke a case, or a client
	-- asking to trigger one it should not have, both arrive here looking exactly
	-- like a legitimate press. An exhibit standing loose in the world, in no case
	-- at all, is unaffected: there is no glass for it to be behind.
	local owningCase = caseFor(tool)
	if owningCase and owningCase:GetAttribute(DisplayCaseConfig.CaseOpenedAttribute) ~= true then
		return
	end

	-- Range is checked before entitlement, as in MalletService: a refusal has to
	-- appear over an exhibit the player is genuinely standing at, not across the
	-- treasury. An exhibit with no ExhibitClass belongs to whoever gets there.
	local required = tool:GetAttribute(DisplayCaseConfig.ExhibitClassAttribute)
	if typeof(required) == "string" and not ClassDefinitions.hasClass(player, required) then
		local key = tool:GetAttribute(DisplayCaseConfig.ExhibitRefusalAttribute)
		refusedEvent:FireClient(
			player,
			handle,
			if typeof(key) == "string" then key else DisplayCaseConfig.RefusalExhibit
		)
		return
	end

	prompt:Destroy()
	for _, part in tool:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.Massless = true
		end
	end
	handle.CanTouch = true -- see sealExhibit: it is a normal tool from here on
	tool.Parent = backpack
	humanoid:EquipTool(tool)
	print(`[DisplayCaseService] {player.Name} took {tool.Name} out of a broken case`)
end

local function armTool(tool: Tool)
	local handle = tool:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") or handle:FindFirstChild(TAKE_PROMPT_NAME) then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = TAKE_PROMPT_NAME
	prompt.ActionText = "Take"
	prompt.ObjectText = tool.Name
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0.15
	prompt.MaxActivationDistance = DisplayCaseConfig.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = handle
	prompt.Triggered:Connect(function(player: Player)
		takeExhibit(player, tool, prompt)
	end)
end

--[[
	Arm what the broken glass just exposed.

	Only Tools and Models count as exhibits — every part the case is built from
	is a bare BasePart, so ignoring those needs no name matching and cannot be
	fooled by a pane being renamed. A Model exhibit becomes ordinary sack loot; a
	Tool gets a prompt, because the sack stores BaseParts and Models and would
	quietly refuse a Tool.
]]
local function armContents(case: Model): number
	local armed = 0
	for _, child in case:GetChildren() do
		if child:IsA("Tool") then
			armTool(child)
			armed += 1
		elseif child:IsA("Model") then
			-- Carry the exhibit's own gate onto the sack before tagging it.
			-- Without this, a class-locked Model exhibit is locked against E and
			-- wide open to F, which is the same hole SackConfig.RequiredClass
			-- exists to close for the mallet.
			local required = child:GetAttribute(DisplayCaseConfig.ExhibitClassAttribute)
			if typeof(required) == "string" then
				child:SetAttribute(SackConfig.RequiredClassAttribute, required)
			end
			if not CollectionService:HasTag(child, SackConfig.CollectableTag) then
				CollectionService:AddTag(child, SackConfig.CollectableTag)
			end
			armed += 1
		end
	end
	return armed
end

-- Breaking --------------------------------------------------------------------

struckEvent.Event:Connect(function(player: any, pane: any, impact: any)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
		return
	end
	if typeof(pane) ~= "Instance" or not pane:IsA("BasePart") then
		return
	end
	if not CollectionService:HasTag(pane, DisplayCaseConfig.GlassTag) or not pane:IsDescendantOf(Workspace) then
		return
	end

	local root = playerRoot(player)
	if not root then
		return
	end
	local nearest = BreakableGlass.closestPoint(pane, root.Position)
	if (root.Position - nearest).Magnitude > DisplayCaseConfig.StrikeRange then
		return
	end

	local point = if typeof(impact) == "Vector3" then impact else nearest
	-- Glass leaves the frame in the direction the swing was travelling. Flat,
	-- because a mallet swung by a standing player is a horizontal blow.
	local away = point - root.Position
	local push = Vector3.new(away.X, 0, away.Z)
	push = if push.Magnitude > 0.1 then push.Unit else root.CFrame.LookVector

	local case = caseFor(pane)
	if not case then
		local shards = BreakableGlass.shatterPane(pane, point, push)
		if shards > 0 then
			print(`[DisplayCaseService] {player.Name} broke {pane:GetFullName()} — {shards} pieces`)
		end
		return
	end

	local shards = BreakableGlass.shatterCase(case, point, push)
	if shards == 0 then
		return
	end
	local armed = armContents(case)
	print(
		`[DisplayCaseService] {player.Name} smashed {case.Name} — {shards} pieces, {armed} exhibit(s) now takeable`
	)
end)

-- Startup ---------------------------------------------------------------------

--[[
	Take the touch pickup off an exhibit.

	A Tool sitting in Workspace carries a TouchInterest, so brushing its handle
	equips it — which was harmless while the case was sealed and is not once the
	glass can go: the sword is anchored to its mounts, and an anchored handle
	cannot follow a grip weld, so a touch pickup hands you a sword that stays
	hovering in the case. Clearing CanTouch leaves the prompt as the only way in,
	and the prompt unanchors before it hands anything over.
]]
local function sealExhibit(tool: Tool)
	local handle = tool:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") then
		handle.CanTouch = false
		-- A prompt is a runtime thing that should never have reached the place
		-- file, but a Studio run that smashed a case and was then saved puts one
		-- there, and it would offer E on a sealed vitrine from the first frame.
		local stale = handle:FindFirstChild(TAKE_PROMPT_NAME)
		if stale then
			stale:Destroy()
		end
	end
end

--[[
	Re-assert the glass tag from the part name.

	Tags travel with a Clone, so copying a case in Studio keeps its panes
	breakable — but a pane rebuilt by hand, or one pasted from an older save,
	arrives with the geometry and no tag and would silently be unbreakable. One
	pass at startup turns that into a non-issue, the same trick VaultDoorService
	uses to re-tag loot from its LootValue attribute.
]]
local cases, panes, retagged = 0, 0, 0
for _, case in CollectionService:GetTagged(DisplayCaseConfig.CaseTag) do
	if not case:IsA("Model") or not case:IsDescendantOf(Workspace) then
		continue
	end
	cases += 1
	local glass = 0
	for _, part in case:GetDescendants() do
		if part:IsA("BasePart") and string.find(part.Name, "Glass", 1, true) then
			if not CollectionService:HasTag(part, DisplayCaseConfig.GlassTag) then
				CollectionService:AddTag(part, DisplayCaseConfig.GlassTag)
				retagged += 1
			end
			glass += 1
		end
	end
	for _, child in case:GetChildren() do
		if child:IsA("Tool") then
			sealExhibit(child)
		end
	end
	panes += glass
	if glass == 0 then
		warn(`[DisplayCaseService] {case:GetFullName()} is tagged as a display case but has no glass panes`)
	end
end

print(
	`[DisplayCaseService] ready — {cases} display case(s), {panes} breakable panes ({retagged} re-tagged)`
)
