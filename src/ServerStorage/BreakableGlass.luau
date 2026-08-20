--turning broken glass into falling glass pieces, 

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local DisplayCaseConfig = require(ReplicatedStorage:WaitForChild("DisplayCaseConfig"))

local BreakableGlass = {}

local SHARD_FOLDER = "GlassShards"

-- Light, barely elastic, low friction: pieces skitter a little when they land
-- and then stop. Density well under 1 keeps a shard that lands on a player from
-- shoving them around.
local SHARD_PHYSICS = PhysicalProperties.new(0.35, 0.3, 0.08, 1, 1)

local rng = Random.new()

local function shardFolder(): Folder
	local existing = Workspace:FindFirstChild(SHARD_FOLDER)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = SHARD_FOLDER
	created.Parent = Workspace
	return created
end

--defining gemonety for the

local function thinAxis(size: Vector3): number
	local axis = 1
	local smallest = size.X
	if size.Y < smallest then
		axis, smallest = 2, size.Y
	end
	if size.Z < smallest then
		axis = 3
	end
	return axis
end

local function faceExtents(size: Vector3, thin: number): (number, number, number)
	if thin == 1 then
		return size.X, size.Y, size.Z
	elseif thin == 2 then
		return size.Y, size.X, size.Z
	end
	return size.Z, size.X, size.Y
end

local function compose(thin: number, thickness: number, u: number, v: number): Vector3
	if thin == 1 then
		return Vector3.new(thickness, u, v)
	elseif thin == 2 then
		return Vector3.new(u, thickness, v)
	end
	return Vector3.new(u, v, thickness)
end

local function cuts(extent: number): number
	local wanted = math.floor(extent / DisplayCaseConfig.ShardTargetSize + 0.5)
	return math.clamp(wanted, 1, DisplayCaseConfig.ShardMaxPerAxis)
end

-- The point on a part's surface nearest some other point. Used both for aiming
-- a swing and for re-checking range on the server: a wide pane is within reach
-- when its edge is, not when its centre is.
function BreakableGlass.closestPoint(part: BasePart, point: Vector3): Vector3
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local half = part.Size / 2
	return part.CFrame:PointToWorldSpace(Vector3.new(
		math.clamp(localPoint.X, -half.X, half.X),
		math.clamp(localPoint.Y, -half.Y, half.Y),
		math.clamp(localPoint.Z, -half.Z, half.Z)
	))
end

-- sound of brek glas

function BreakableGlass.playAt(part: BasePart, soundId: string, volume: number, pitch: number)
	local sound = Instance.new("Sound")
	sound.Name = "GlassSound"
	sound.SoundId = soundId
	sound.Volume = volume
	sound.PlaybackSpeed = pitch
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 8
	sound.RollOffMaxDistance = 130
	sound.Parent = part
	sound:Play()
	Debris:AddItem(sound, 10)
end

function BreakableGlass.shatterPane(pane: BasePart, impact: Vector3, push: Vector3): number
	if pane:GetAttribute(DisplayCaseConfig.PaneBrokenAttribute) == true then
		return 0
	end
	pane:SetAttribute(DisplayCaseConfig.PaneBrokenAttribute, true)

	local thin = thinAxis(pane.Size)
	local thickness, uExtent, vExtent = faceExtents(pane.Size, thin)
	local columns, rows = cuts(uExtent), cuts(vExtent)
	local du, dv = uExtent / columns, vExtent / rows
	local folder = shardFolder()
	local settle = DisplayCaseConfig.ShardSettleSeconds
	local fade = DisplayCaseConfig.ShardFadeSeconds
	local bias = if push.Magnitude > 0.01 then push.Unit else Vector3.yAxis
	local made = 0

	for column = 1, columns do
		for row = 1, rows do
			local u = -uExtent / 2 + (column - 0.5) * du
			local v = -vExtent / 2 + (row - 0.5) * dv

			local shard = Instance.new("Part")
			shard.Name = "Shard"
			-- Slightly undersized and unevenly so: a grid of exactly touching
			-- boxes reads as a wall that fell over, not as broken glass.
			shard.Size =
				compose(thin, thickness, du * rng:NextNumber(0.68, 0.92), dv * rng:NextNumber(0.68, 0.92))
			shard.CFrame = pane.CFrame * CFrame.new(compose(thin, 0, u, v))
			shard.Color = pane.Color
			shard.Material = Enum.Material.Glass
			-- A shard is a smaller thing than the sheet it came from, so it
			-- needs to be less see-through to read at all while it is falling.
			shard.Transparency = math.clamp(pane.Transparency - 0.2, 0.15, 0.85)
			shard.Reflectance = math.min(pane.Reflectance + 0.12, 1)
			shard.CastShadow = false
			shard.CanQuery = false
			shard.CanTouch = false
			shard.CanCollide = true
			shard.Anchored = false
			shard.CustomPhysicalProperties = SHARD_PHYSICS
			shard.TopSurface = Enum.SurfaceType.Smooth
			shard.BottomSurface = Enum.SurfaceType.Smooth
			shard.Parent = folder

			local away = shard.Position - impact
			local spray = if away.Magnitude > 0.15 then away.Unit else bias
			local direction = (spray * 0.55 + bias * 0.8)
			direction = if direction.Magnitude > 0.01 then direction.Unit else bias
			shard.AssemblyLinearVelocity = direction * rng:NextNumber(4, 11)
				+ Vector3.new(0, rng:NextNumber(1, 4.5), 0)
			shard.AssemblyAngularVelocity =
				Vector3.new(rng:NextNumber(-9, 9), rng:NextNumber(-9, 9), rng:NextNumber(-9, 9))

			-- Debris is the backstop; the tween is the look. If the piece is
			-- already gone when the delay fires, the tween is simply not made.
			Debris:AddItem(shard, settle + fade + 0.35)
			task.delay(settle, function()
				if shard.Parent then
					TweenService
						:Create(shard, TweenInfo.new(fade, Enum.EasingStyle.Linear), { Transparency = 1 })
						:Play()
				end
			end)

			made += 1
		end
	end

	pane.Transparency = 1
	pane.CanCollide = false
	pane.CanQuery = false
	pane.CanTouch = false
	pane.CastShadow = false
	return made
end
--essentially making the broken panes disappear, into the abysss

function BreakableGlass.shatterCase(case: Model, impact: Vector3, push: Vector3): number
	if case:GetAttribute(DisplayCaseConfig.CaseOpenedAttribute) == true then
		return 0
	end
	case:SetAttribute(DisplayCaseConfig.CaseOpenedAttribute, true)

	local centre = case:GetBoundingBox().Position
	local anchor: BasePart? = case.PrimaryPart
	local total = 0

	for _, pane in case:GetDescendants() do
		if pane:IsA("BasePart") and CollectionService:HasTag(pane, DisplayCaseConfig.GlassTag) then
			anchor = anchor or pane
			local away = pane.Position - centre
			local outward = if away.Magnitude > 0.2 then away.Unit else Vector3.yAxis
			total += BreakableGlass.shatterPane(pane, impact, outward * 0.7 + push * 0.6)
		end
	end

	if anchor then
		local sourcePart = anchor
		BreakableGlass.playAt(
			sourcePart,
			DisplayCaseConfig.ShatterSoundId,
			1,
			rng:NextNumber(0.94, 1.06)
		)
		task.delay(DisplayCaseConfig.TinkleDelay, function()
			if sourcePart.Parent then
				BreakableGlass.playAt(
					sourcePart,
					DisplayCaseConfig.TinkleSoundId,
					0.5,
					rng:NextNumber(1, 1.15)
				)
			end
		end)
	end

	return total
end

return BreakableGlass
