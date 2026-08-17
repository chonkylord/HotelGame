--!strict
-- Converts the anchored props accepted by the sack into stable world physics
-- assemblies. Kept separate from SackService so the assembly rules can be
-- tested without players or RemoteEvents.

local SackPhysics = {}

SackPhysics.BodyName = "SackDropBody"

local PHYSICAL_PROPERTIES = PhysicalProperties.new(0.7, 0.6, 0.15, 1, 1)

local function baseParts(instance: Instance): { BasePart }
	local found: { BasePart } = {}
	if instance:IsA("BasePart") then
		table.insert(found, instance)
	end
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(found, descendant)
		end
	end
	return found
end

-- Stop an already-dropped item before moving it out of Workspace. Apart from
-- preventing stale velocity on the next drop, anchoring here makes the vault a
-- safe place even if a future Roblox physics change simulates stored parts.
function SackPhysics.freeze(instance: Instance)
	for _, part in baseParts(instance) do
		part.AssemblyLinearVelocity = Vector3.zero
		part.AssemblyAngularVelocity = Vector3.zero
		part.Anchored = true
	end
end

function SackPhysics.positionAt(instance: Instance, dropCFrame: CFrame)
	if instance:IsA("Model") then
		instance:PivotTo(dropCFrame)
	elseif instance:IsA("BasePart") then
		instance.CFrame = dropCFrame
	end
end

-- Turn a parked prop into one physical assembly. A transparent, non-queryable
-- body supplies simple collision while the visible meshes remain clickable;
-- using every detailed food mesh as a collider makes small objects jitter.
function SackPhysics.makePhysical(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		instance.Anchored = false
		instance.CanCollide = true
		instance.CanTouch = true
		instance.Massless = false
		instance.CustomPhysicalProperties = PHYSICAL_PROPERTIES
		return instance
	end
	if not instance:IsA("Model") then
		return nil
	end

	local body = instance:FindFirstChild(SackPhysics.BodyName)
	if body and not body:IsA("BasePart") then
		body:Destroy()
		body = nil
	end

	if not body then
		local boundsCFrame, boundsSize = instance:GetBoundingBox()
		local created = Instance.new("Part")
		created.Name = SackPhysics.BodyName
		created.CFrame = boundsCFrame
		created.Size =
			Vector3.new(math.max(boundsSize.X, 0.2), math.max(boundsSize.Y, 0.2), math.max(boundsSize.Z, 0.2))
		created.Transparency = 1
		created.CastShadow = false
		created.CanQuery = false
		created.Parent = instance
		body = created

		for _, part in baseParts(instance) do
			if part ~= created then
				local weld = Instance.new("WeldConstraint")
				weld.Name = "SackDropWeld"
				weld.Part0 = created
				weld.Part1 = part
				weld.Parent = created
			end
		end
	end

	local physicsBody = body :: BasePart
	for _, part in baseParts(instance) do
		part.Anchored = false
		part.CanCollide = part == physicsBody
		part.CanTouch = part == physicsBody
		part.Massless = part ~= physicsBody
	end
	physicsBody.Transparency = 1
	physicsBody.CastShadow = false
	physicsBody.CanQuery = false
	physicsBody.CustomPhysicalProperties = PHYSICAL_PROPERTIES
	return physicsBody
end

return SackPhysics
