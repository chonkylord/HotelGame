--!strict
--[[
	Drives the round bank-vault door: the keypad prompt, the swing, and the
	display behind it.

	This used to live at the bottom of BankVaultBuilder, wired up out of the
	local variables that had just built the geometry. That was fine while the
	vault was rebuilt from scratch every server start. It stopped being fine the
	moment the vault became saved place content the user edits: the builder now
	stands down when it finds an authored vault, and everything below its early
	return went with it -- so ClueService would set VaultUnlocked at the end of
	the hunt and nothing would move. The hunt completed onto a sealed door.

	So the split is: the builder owns GEOMETRY and only runs when the place has
	none, while this owns BEHAVIOUR and runs every time against whichever vault
	it finds. One code path for the authored vault and the generated one, which
	also means the behaviour can no longer silently diverge between them.

	Everything is resolved by name from the model rather than passed in, because
	the whole point is that this never saw the vault get built.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ClueConfig = require(ReplicatedStorage:WaitForChild("ClueConfig"))

local BLOOD = Color3.fromRGB(111, 38, 32)
local GREEN = Color3.fromRGB(78, 255, 157)
local AMBER = Color3.fromRGB(255, 183, 62)
local CYAN = Color3.fromRGB(72, 225, 255)

local OPEN_ANGLE = math.rad(102)
local SWING = TweenInfo.new(1.65, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
-- Where the door hangs, in VaultAnchor-local studs. Same figure the builder
-- pivots its own geometry about; kept anchor-relative so dragging the vault
-- around in Studio moves the hinge with it.
local HINGE_LOCAL = Vector3.new(-12.65, 13.2, -0.3)

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

local remotes = ensure(ReplicatedStorage, ClueConfig.RemotesFolder, "Folder")
local openEvent = ensure(remotes, ClueConfig.OpenEvent, "RemoteEvent") :: RemoteEvent

-- Same name fallback ClueService uses, so an authored vault and a generated one
-- are both found by the same rule.
local vault = Workspace:FindFirstChild("BankVault") or Workspace:FindFirstChild("BankVault_Procedural")
if not vault or not vault:IsA("Model") then
	warn("[VaultDoorService] no BankVault in Workspace; vault door is inert")
	return
end

local doorAssembly = vault:FindFirstChild("RoundVaultDoor")
local keypadFace = vault:FindFirstChild("KeypadFace")
local keypadPrompt = keypadFace and keypadFace:FindFirstChild("InspectKeypad")
local displayPart = vault:FindFirstChild("KeypadDisplay")
local displayLabel = displayPart and displayPart:FindFirstChild("Label", true)

if not doorAssembly or not doorAssembly:IsA("Model") or not keypadPrompt or not keypadPrompt:IsA("ProximityPrompt") then
	warn(
		`[VaultDoorService] {vault:GetFullName()} is missing RoundVaultDoor or KeypadFace.InspectKeypad; `
			.. `vault door is inert. If the vault was edited in Studio, those two names are load-bearing.`
	)
	return
end

local anchor = Workspace:FindFirstChild("VaultAnchor")
local origin = if anchor and anchor:IsA("BasePart") then anchor.CFrame else vault:GetPivot()
local hingePivot = origin * CFrame.new(HINGE_LOCAL)

local doorParts: { BasePart } = {}
for _, descendant in doorAssembly:GetDescendants() do
	if descendant:IsA("BasePart") then
		table.insert(doorParts, descendant)
	end
end

--[[
	The saved pose is taken to BE the closed pose.

	Same bargain HotelDoorService makes with its hinges, and the same hazard:
	if the door is left standing open in Studio and the place is saved that way,
	this captures "open" as closed and the door works from the wrong rest
	position forever after. DoorSwingAngle is saved alongside the geometry, so
	when it disagrees with the pose we say so rather than quietly bake in the
	mistake.
]]
local doorAngle = doorAssembly:FindFirstChild("DoorSwingAngle")
if not doorAngle or not doorAngle:IsA("NumberValue") then
	local created = Instance.new("NumberValue")
	created.Name = "DoorSwingAngle"
	created.Value = 0
	created.Parent = doorAssembly
	doorAngle = created
end
local swingValue = doorAngle :: NumberValue
if math.abs(swingValue.Value) > 1e-3 then
	warn(
		`[VaultDoorService] {doorAssembly:GetFullName()}.DoorSwingAngle was saved at {swingValue.Value} rather than 0, `
			.. `so the door was saved part-open. Treating the saved pose as closed; set it back to 0 in Studio with the `
			.. `door shut if that is wrong.`
	)
	swingValue.Value = 0
end

local closedOffsets: { [BasePart]: CFrame } = {}
for _, part in doorParts do
	closedOffsets[part] = hingePivot:ToObjectSpace(part.CFrame)
end

swingValue.Changed:Connect(function(value: number)
	for _, part in doorParts do
		part.CFrame = hingePivot * CFrame.Angles(0, value, 0) * closedOffsets[part]
	end
end)

local function setLabel(text: string, colour: Color3)
	if displayLabel and displayLabel:IsA("TextLabel") then
		displayLabel.Text = text
		displayLabel.TextColor3 = colour
	end
end

local doorIsOpen = false
local doorIsMoving = false

local function setDoorOpen(shouldOpen: boolean)
	if doorIsMoving or doorIsOpen == shouldOpen then
		return
	end
	if shouldOpen and vault:GetAttribute(ClueConfig.VaultUnlockedAttribute) ~= true then
		setLabel("LOCKED", BLOOD)
		task.delay(1.1, function()
			if not doorIsMoving and not doorIsOpen and vault.Parent then
				setLabel("READY", GREEN)
			end
		end)
		return
	end

	doorIsMoving = true
	keypadPrompt.Enabled = false
	setLabel(if shouldOpen then "OPENING" else "SEALING", AMBER)

	local swing = TweenService:Create(swingValue, SWING, { Value = if shouldOpen then OPEN_ANGLE else 0 })
	swing:Play()
	swing.Completed:Once(function()
		doorIsOpen = shouldOpen
		doorIsMoving = false
		-- Once a round unlocks the vault it stays open. There is no interior
		-- keypad, so allowing the exterior prompt to seal it would let one
		-- player trap the rest of the server in the treasury.
		keypadPrompt.Enabled = not doorIsOpen
		keypadPrompt.ActionText = "Open vault"
		setLabel(if doorIsOpen then "ACCESS" else "READY", if doorIsOpen then CYAN else GREEN)
		if shouldOpen and vault:GetAttribute(ClueConfig.VaultUnlockedAttribute) ~= true then
			task.defer(setDoorOpen, false)
		end
	end)
end

keypadPrompt.ActionText = "Open vault"
keypadPrompt.Enabled = true
keypadPrompt.Triggered:Connect(function(player: Player)
	if vault:GetAttribute(ClueConfig.VaultUnlockedAttribute) == true then
		setDoorOpen(true)
		return
	end
	openEvent:FireClient(player, {
		nodeId = "VaultKeypad",
		kind = "Code",
		riddle = "Five marks were gathered upstairs. The steel is waiting for them in order.",
		prompt = "Enter the five-digit vault code.",
	})
end)

vault:GetAttributeChangedSignal(ClueConfig.VaultUnlockedAttribute):Connect(function()
	if vault:GetAttribute(ClueConfig.VaultUnlockedAttribute) == true then
		setDoorOpen(true)
	elseif doorIsOpen then
		setDoorOpen(false)
	end
end)

--[[
	A saved vault carries its loot tags in the place file, but a vault someone
	has edited might not -- adding a bar by copy-paste gets you the geometry and
	the LootValue attribute, and silently loses the tag that makes the Sack able
	to pick it up. Re-asserting the tag from the attribute costs one pass at
	startup and turns that into a non-issue.
]]
local retagged = 0
for _, descendant in vault:GetDescendants() do
	if
		descendant:IsA("BasePart")
		and descendant:GetAttribute(ClueConfig.LootValueAttribute) ~= nil
		and not CollectionService:HasTag(descendant, ClueConfig.CollectableTag)
	then
		CollectionService:AddTag(descendant, ClueConfig.CollectableTag)
		retagged += 1
	end
end

setLabel("READY", GREEN)
print(
	`[VaultDoorService] wired {vault:GetFullName()} — {#doorParts} door parts, `
		.. `{retagged} loot pieces re-tagged, unlocked={vault:GetAttribute(ClueConfig.VaultUnlockedAttribute) == true}`
)
