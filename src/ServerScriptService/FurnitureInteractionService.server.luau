--!strict
--[[
	Real, server-authoritative hotel furniture interactions.

	The original furniture contains a mixture of useful models and solid placeholder
	blocks. At runtime this service replaces the placeholder nightstands, dressers,
	and wardrobes with complete furniture: hollow carcasses, full drawer boxes,
	visible drawer contents, hinged doors, and usable hiding interiors.
]]

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local FoodPantry = require(ServerStorage:WaitForChild("FoodPantry"))

-- Decides which drawers get a snack in them. Seeded fresh each run so two
-- servers do not hide the food in exactly the same places.
local contentsRng = Random.new()

local RUNTIME_FOLDER_NAME = "RuntimeFurnitureInteractions"
local PROMPT_DISTANCE = 7.5
local OPEN_INFO = TweenInfo.new(0.48, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local CLOSE_INFO = TweenInfo.new(0.36, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

type AnimatedSet = {
	parts: { BasePart },
	closed: { CFrame },
	opened: { CFrame },
	prompts: { ProximityPrompt },
	isOpen: boolean,
	busy: boolean,
	locked: boolean,
	serial: number,
	objectText: string,
	openSound: Sound?,
	closeSound: Sound?,
	onStateChanged: ((boolean) -> ())?,
}

type CharacterState = {
	humanoid: Humanoid,
	root: BasePart,
	walkSpeed: number,
	jumpPower: number,
	jumpHeight: number,
	autoRotate: boolean,
	rootAnchored: boolean,
	cameraOffset: Vector3,
	collisions: { [BasePart]: boolean },
}

type HideSpot = {
	prompt: ProximityPrompt,
	anchor: BasePart,
	hideCFrame: CFrame,
	exitCFrame: CFrame,
	doors: AnimatedSet?,
	occupant: Player?,
	savedState: CharacterState?,
}

local oldRuntime = Workspace:FindFirstChild(RUNTIME_FOLDER_NAME)
if oldRuntime then
	oldRuntime:Destroy()
end

local runtimeFolder = Instance.new("Folder")
runtimeFolder.Name = RUNTIME_FOLDER_NAME
runtimeFolder.Parent = Workspace

local hideSpots: { HideSpot } = {}

local function lowerName(instance: Instance): string
	return string.lower(instance.Name)
end

local function playerRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function playerHumanoid(player: Player): Humanoid?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid
end

local function isPlayerNear(player: Player, part: BasePart, maxDistance: number): boolean
	local root = playerRoot(player)
	return root ~= nil and (root.Position - part.Position).Magnitude <= maxDistance
end

local function makePrompt(parent: BasePart, actionText: string, objectText: string): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "FurniturePrompt"
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0.12
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.Parent = parent
	return prompt
end

local function findSound(source: Instance, wantedName: string): Sound?
	local wanted = string.lower(wantedName)
	for _, descendant in source:GetDescendants() do
		if descendant:IsA("Sound") and string.lower(descendant.Name) == wanted then
			return descendant
		end
	end
	return nil
end

local function drawerSoundTemplate(): Sound?
	local drawer = Workspace:FindFirstChild("Drawer")
	local body = drawer and drawer:FindFirstChild("Body")
	return if body then body:FindFirstChildOfClass("Sound") else nil
end

local function cloneSound(template: Sound?, parent: Instance, speed: number): Sound?
	if not template then
		return nil
	end
	local sound = template:Clone()
	sound.PlaybackSpeed = speed
	sound.Parent = parent
	return sound
end

local function updatePromptText(animated: AnimatedSet)
	for _, prompt in animated.prompts do
		prompt.ActionText = if animated.isOpen then "Close" else "Open"
		prompt.ObjectText = animated.objectText
		prompt.Enabled = not animated.locked
	end
end

local function setOpen(animated: AnimatedSet, shouldOpen: boolean)
	if animated.busy or animated.isOpen == shouldOpen then
		return
	end

	animated.busy = true
	animated.isOpen = shouldOpen
	animated.serial += 1
	local serial = animated.serial
	local tweenInfo = if shouldOpen then OPEN_INFO else CLOSE_INFO

	for index, part in animated.parts do
		if part.Parent then
			local goal = if shouldOpen then animated.opened[index] else animated.closed[index]
			TweenService:Create(part, tweenInfo, { CFrame = goal }):Play()
		end
	end

	local sound = if shouldOpen then animated.openSound else animated.closeSound
	if sound then
		sound:Play()
	end

	updatePromptText(animated)
	if animated.onStateChanged then
		animated.onStateChanged(shouldOpen)
	end

	task.delay(tweenInfo.Time + 0.05, function()
		if animated.serial == serial then
			animated.busy = false
		end
	end)
end

local function registerAnimatedSet(
	parts: { BasePart },
	opened: { CFrame },
	promptParts: { BasePart },
	objectText: string,
	openSound: Sound?,
	closeSound: Sound?
): AnimatedSet?
	if #parts == 0 or #parts ~= #opened then
		return nil
	end

	local closed: { CFrame } = {}
	for index, part in parts do
		closed[index] = part.CFrame
	end

	local animated: AnimatedSet = {
		parts = parts,
		closed = closed,
		opened = opened,
		prompts = {},
		isOpen = false,
		busy = false,
		locked = false,
		serial = 0,
		objectText = objectText,
		openSound = openSound,
		closeSound = closeSound,
		onStateChanged = nil,
	}

	for _, promptPart in promptParts do
		local prompt = makePrompt(promptPart, "Open", objectText)
		table.insert(animated.prompts, prompt)
		prompt.Triggered:Connect(function(player)
			if animated.locked or not isPlayerNear(player, promptPart, prompt.MaxActivationDistance + 2) then
				return
			end
			setOpen(animated, not animated.isOpen)
		end)
	end

	return animated
end

local function makePart(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	colour: Color3,
	material: Enum.Material?,
	canCollide: boolean?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = if canCollide == nil then true else canCollide
	part.CanTouch = false
	part.CanQuery = true
	part.CastShadow = true
	part.Material = material or Enum.Material.WoodPlanks
	part.Color = colour
	part.Size = size
	part.CFrame = cframe
	part.Parent = parent
	return part
end

local function sampleAppearance(source: Instance): (Color3, Enum.Material)
	local best: BasePart? = nil
	local bestVolume = -1
	if source:IsA("BasePart") and source.Transparency < 0.9 then
		best = source
		bestVolume = source.Size.X * source.Size.Y * source.Size.Z
	end
	for _, descendant in source:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Transparency < 0.9 then
			local volume = descendant.Size.X * descendant.Size.Y * descendant.Size.Z
			if descendant.Material == Enum.Material.Metal then
				volume *= 0.25
			end
			if volume > bestVolume then
				best = descendant
				bestVolume = volume
			end
		end
	end
	if best then
		return best.Color, best.Material
	end
	return Color3.fromRGB(102, 73, 50), Enum.Material.WoodPlanks
end

local function hideSource(source: Instance)
	if source:IsA("BasePart") then
		source.Transparency = 1
		source.CanCollide = false
		source.CanQuery = false
	end
	for _, descendant in source:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Transparency = 1
			descendant.CanCollide = false
			descendant.CanQuery = false
		end
		if descendant:IsA("ProximityPrompt") then
			descendant.Enabled = false
		elseif descendant:IsA("ClickDetector") then
			descendant.MaxActivationDistance = 0
		end
	end
end

local function targetFrameAndSize(source: Instance): (CFrame, Vector3)
	if source:IsA("BasePart") then
		return source.CFrame, source.Size
	end

	assert(source:IsA("Model"))
	local boxCF, boxSize = source:GetBoundingBox()
	local topPart: BasePart? = nil
	local bestScore = -math.huge

	for _, descendant in source:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Transparency < 0.9 then
			local horizontalArea = descendant.Size.X * descendant.Size.Z
			local thinness = math.max(descendant.Size.Y, 0.05)
			local score = horizontalArea / thinness + descendant.Position.Y * 0.01
			if descendant.CFrame.UpVector.Y > 0.8 and score > bestScore then
				topPart = descendant
				bestScore = score
			end
		end
	end

	if not topPart then
		return boxCF, boxSize
	end

	local width = topPart.Size.X
	local depth = topPart.Size.Z
	local rotation = topPart.CFrame.Rotation
	if depth > width then
		width, depth = depth, width
		rotation *= CFrame.Angles(0, math.rad(90), 0)
	end
	local centre = Vector3.new(topPart.Position.X, boxCF.Position.Y, topPart.Position.Z)
	return CFrame.new(centre) * rotation, Vector3.new(width, boxSize.Y, depth)
end

local function localGoal(rootCF: CFrame, part: BasePart, offset: CFrame): CFrame
	return rootCF * offset * rootCF:ToObjectSpace(part.CFrame)
end

--[[
	Whether a piece of furniture belongs to the suite floor.

	Asked of the *source* instance rather than the drawer we build, because the
	functional cabinet is reparented into runtimeFolder and loses the ancestry
	that answers this. The original never moves, so it stays the honest witness.
]]
local function isSuiteFurniture(source: Instance): boolean
	local node: Instance? = source
	while node and node ~= Workspace do
		if node.Name == "SuiteFloor" then
			return true
		end
		node = node.Parent
	end
	return false
end

--[[
	Suite drawers are stocked better than the rest of the hotel's.

	The suite floor is the furthest space from the lobby, the only one you reach
	by lift, and the darkest room in the game — its fixtures take LightFlicker's
	GUEST_ROOM profile, the dimmest of the five, on top of the Dark grade's
	(7,8,12) ambient. Getting there and searching it is a real commitment with
	Joel loose, and stocking it at the same one-in-three, single-bar rate as a
	corridor nightstand made that trip a bad trade.

	Two bars rather than one is the part that matters: a suite drawer is worth
	opening, not just worth noting. The rest of the hotel is untouched, so the
	suites read as the place worth the walk instead of everywhere being generous.
]]
local SUITE_SNACK_CHANCE = 0.72
local SUITE_SNACK_BARS = 2
local HOTEL_SNACK_CHANCE = 0.34
local HOTEL_SNACK_BARS = 1

local function drawerContents(
	parent: Instance,
	rootCF: CFrame,
	centre: Vector3,
	width: number,
	depth: number,
	index: number,
	generous: boolean?
): { BasePart }
	local contents: { BasePart } = {}
	local bottomY = centre.Y - 0.18

	-- Roughly every third drawer has something edible in it — closer to three in
	-- four up in the suites. The parts are returned to the caller so they join
	-- the drawer's moving set and ride out with it; the "Food" tag is withheld
	-- until the drawer is actually opened, otherwise you could eat through a shut
	-- drawer front.
	if contentsRng:NextNumber() < (if generous then SUITE_SNACK_CHANCE else HOTEL_SNACK_CHANCE) then
		local snack = FoodPantry.place({
			menu = "snack",
			position = (rootCF * CFrame.new(centre.X, bottomY - 0.1, centre.Z)).Position,
			parent = parent,
			rng = contentsRng,
			bars = if generous then SUITE_SNACK_BARS else HOTEL_SNACK_BARS,
			targetSize = math.clamp(math.min(width, depth) * 0.6, 0.35, 1.0),
			armNow = false,
		})
		if snack then
			for _, part in snack:GetDescendants() do
				if part:IsA("BasePart") then
					table.insert(contents, part)
				end
			end
			return contents
		end
	end

	if index % 3 == 1 then
		local cloth = makePart(
			parent,
			"FoldedTowel",
			Vector3.new(width * 0.54, 0.18, depth * 0.42),
			rootCF * CFrame.new(centre.X - width * 0.12, bottomY, centre.Z + depth * 0.08),
			Color3.fromRGB(117, 137, 148),
			Enum.Material.Fabric,
			false
		)
		table.insert(contents, cloth)
	elseif index % 3 == 2 then
		local paper = makePart(
			parent,
			"GuestNote",
			Vector3.new(width * 0.58, 0.035, depth * 0.52),
			rootCF * CFrame.new(centre.X, bottomY - 0.03, centre.Z),
			Color3.fromRGB(231, 222, 196),
			Enum.Material.SmoothPlastic,
			false
		)
		paper.CFrame *= CFrame.Angles(0, math.rad(7), 0)
		table.insert(contents, paper)
	else
		local box = makePart(
			parent,
			"SmallKeepsakeBox",
			Vector3.new(width * 0.42, 0.3, depth * 0.38),
			rootCF * CFrame.new(centre.X + width * 0.14, bottomY + 0.08, centre.Z + depth * 0.05),
			Color3.fromRGB(67, 48, 39),
			Enum.Material.Wood,
			false
		)
		table.insert(contents, box)
	end
	return contents
end

local function horizontalUnit(vector: Vector3): Vector3?
	local horizontal = Vector3.new(vector.X, 0, vector.Z)
	if horizontal.Magnitude < 0.01 then
		return nil
	end
	return horizontal.Unit
end

local function modelHandleDirection(source: Model, centre: Vector3): Vector3?
	local handlePosition = Vector3.zero
	local handleCount = 0
	for _, descendant in source:GetDescendants() do
		if descendant:IsA("BasePart") then
			local name = lowerName(descendant)
			local isNamedHandle = string.find(name, "handle", 1, true) ~= nil
			local isImportedHandle = descendant:IsA("IntersectOperation")
				and descendant.Material == Enum.Material.SmoothPlastic
			if isNamedHandle or isImportedHandle then
				handlePosition += descendant.Position
				handleCount += 1
			end
		end
	end
	if handleCount == 0 then
		return nil
	end
	return horizontalUnit(handlePosition / handleCount - centre)
end

local function buildDrawerCabinet(source: Instance, label: string, columns: number, rows: number, flipFront: boolean?)
	local rootCF, sourceSize = targetFrameAndSize(source)
	local detectedFront = if source:IsA("Model") then modelHandleDirection(source, rootCF.Position) else nil
	if detectedFront then
		rootCF = CFrame.lookAt(rootCF.Position, rootCF.Position + detectedFront)
	elseif flipFront then
		rootCF *= CFrame.Angles(0, math.rad(180), 0)
	end
	local width = math.max(sourceSize.X, 1.8)
	local height = math.max(sourceSize.Y, 1.8)
	local depth = math.max(sourceSize.Z, 1.7)
	local colour, material = sampleAppearance(source)
	local darkColour = colour:Lerp(Color3.fromRGB(22, 17, 14), 0.58)
	local thickness = math.clamp(math.min(width, height, depth) * 0.045, 0.08, 0.18)
	local frontZ = -depth / 2
	-- Read before hideSource: the source keeps its ancestry either way, but the
	-- answer belongs to this cabinet for the rest of its life, so take it once.
	local generous = isSuiteFurniture(source)

	hideSource(source)

	local cabinet = Instance.new("Model")
	cabinet.Name = "Functional_" .. label
	cabinet:SetAttribute("FurnitureType", "DrawerCabinet")
	cabinet.Parent = runtimeFolder

	makePart(
		cabinet,
		"LeftSide",
		Vector3.new(thickness, height, depth),
		rootCF * CFrame.new(-width / 2 + thickness / 2, 0, 0),
		colour,
		material
	)
	makePart(
		cabinet,
		"RightSide",
		Vector3.new(thickness, height, depth),
		rootCF * CFrame.new(width / 2 - thickness / 2, 0, 0),
		colour,
		material
	)
	makePart(
		cabinet,
		"Back",
		Vector3.new(width - thickness * 2, height - thickness * 2, thickness),
		rootCF * CFrame.new(0, 0, depth / 2 - thickness / 2),
		darkColour,
		material
	)
	makePart(
		cabinet,
		"Top",
		Vector3.new(width, thickness, depth),
		rootCF * CFrame.new(0, height / 2 - thickness / 2, 0),
		colour,
		material
	)
	makePart(
		cabinet,
		"Bottom",
		Vector3.new(width, thickness, depth),
		rootCF * CFrame.new(0, -height / 2 + thickness / 2, 0),
		colour,
		material
	)

	for divider = 1, columns - 1 do
		local x = -width / 2 + width * divider / columns
		makePart(
			cabinet,
			"VerticalDivider",
			Vector3.new(thickness, height - thickness * 2, depth - thickness),
			rootCF * CFrame.new(x, 0, thickness / 2),
			darkColour,
			material
		)
	end
	for divider = 1, rows - 1 do
		local y = -height / 2 + height * divider / rows
		makePart(
			cabinet,
			"DrawerDivider",
			Vector3.new(width - thickness * 2, thickness, depth - thickness),
			rootCF * CFrame.new(0, y, thickness / 2),
			darkColour,
			material
		)
	end

	local cellWidth = (width - thickness * (columns + 1)) / columns
	local cellHeight = (height - thickness * (rows + 1)) / rows
	local drawerDepth = depth - thickness * 2.5
	local soundTemplate = drawerSoundTemplate()
	local drawerIndex = 0

	for row = 1, rows do
		for column = 1, columns do
			drawerIndex += 1
			local x = -width / 2 + thickness + cellWidth / 2 + (column - 1) * (cellWidth + thickness)
			local y = height / 2 - thickness - cellHeight / 2 - (row - 1) * (cellHeight + thickness)
			local centre = Vector3.new(x, y, thickness * 0.2)
			local drawer = Instance.new("Model")
			drawer.Name = string.format("Drawer_%02d", drawerIndex)
			drawer:SetAttribute("ContainsLoot", true)
			drawer.Parent = cabinet

			local moving: { BasePart } = {}
			local bottom = makePart(
				drawer,
				"DrawerBottom",
				Vector3.new(cellWidth - thickness, thickness, drawerDepth),
				rootCF * CFrame.new(x, y - cellHeight / 2 + thickness / 2, centre.Z),
				darkColour,
				material
			)
			local left = makePart(
				drawer,
				"DrawerSide",
				Vector3.new(thickness, cellHeight * 0.78, drawerDepth),
				rootCF * CFrame.new(x - cellWidth / 2 + thickness / 2, y - cellHeight * 0.08, centre.Z),
				colour,
				material
			)
			local right = makePart(
				drawer,
				"DrawerSide",
				Vector3.new(thickness, cellHeight * 0.78, drawerDepth),
				rootCF * CFrame.new(x + cellWidth / 2 - thickness / 2, y - cellHeight * 0.08, centre.Z),
				colour,
				material
			)
			local back = makePart(
				drawer,
				"DrawerBack",
				Vector3.new(cellWidth, cellHeight * 0.78, thickness),
				rootCF * CFrame.new(x, y - cellHeight * 0.08, depth / 2 - thickness * 1.4),
				colour,
				material
			)
			local front = makePart(
				drawer,
				"DrawerFront",
				Vector3.new(cellWidth + thickness * 0.45, cellHeight - thickness * 0.3, thickness * 1.35),
				rootCF * CFrame.new(x, y, frontZ - thickness * 0.55),
				colour,
				material
			)
			local handle = makePart(
				drawer,
				"Handle",
				Vector3.new(math.min(cellWidth * 0.42, 1.15), math.max(0.09, thickness * 0.65), thickness * 0.7),
				rootCF * CFrame.new(x, y, frontZ - thickness * 1.65),
				Color3.fromRGB(53, 46, 40),
				Enum.Material.Metal,
				false
			)

			for _, part in { bottom, left, right, back, front, handle } do
				table.insert(moving, part)
			end
			for _, content in drawerContents(drawer, rootCF, centre, cellWidth, drawerDepth, drawerIndex, generous) do
				table.insert(moving, content)
			end

			local travel = math.clamp(depth * 0.72, 1.25, 3.4)
			local opened: { CFrame } = {}
			for index, part in moving do
				opened[index] = localGoal(rootCF, part, CFrame.new(0, 0, -travel))
			end
			local animated = registerAnimatedSet(
				moving,
				opened,
				{ front },
				label .. " Drawer",
				cloneSound(soundTemplate, front, 0.94),
				cloneSound(soundTemplate, front, 0.84)
			)
			if animated then
				-- Anything edible in here only becomes edible once it is in view.
				animated.onStateChanged = function(isOpen: boolean)
					if isOpen then
						FoodPantry.serveInside(drawer)
					end
				end
			end
		end
	end
end

local function isDeskDrawerFront(part: BasePart, modelHeight: number): boolean
	local isWood = part.Material == Enum.Material.Wood or part.Material == Enum.Material.WoodPlanks
	return isWood
		and part.Transparency < 0.9
		and part.Size.X > 0.9
		and part.Size.Y > modelHeight * 0.16
		and part.Size.Y < modelHeight * 0.38
		and part.Size.Z < 0.16
end

local function deskOutwardDirection(desk: Model, origin: Vector3, modelNormal: Vector3): Vector3
	local normal = horizontalUnit(modelNormal) or Vector3.zAxis
	local deskCentre = select(1, desk:GetBoundingBox()).Position
	local closestChairPosition: Vector3? = nil
	local closestDistance = math.huge

	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("Model") and string.find(lowerName(descendant), "chair", 1, true) then
			local chairCentre = select(1, descendant:GetBoundingBox()).Position
			local distance = (chairCentre - deskCentre).Magnitude
			if distance < 10 and distance < closestDistance then
				closestChairPosition = chairCentre
				closestDistance = distance
			end
		end
	end

	if closestChairPosition then
		local towardChair = horizontalUnit(closestChairPosition - origin)
		if towardChair and normal:Dot(towardChair) < 0 then
			return -normal
		end
	end
	return normal
end

local function buildDeskDrawers(desk: Model)
	local _, boxSize = desk:GetBoundingBox()
	local fronts: { BasePart } = {}
	local handles: { BasePart } = {}
	local pedestal: BasePart? = nil
	local pedestalVolume = -1

	for _, child in desk:GetChildren() do
		if child:IsA("BasePart") then
			if isDeskDrawerFront(child, boxSize.Y) then
				table.insert(fronts, child)
			elseif
				child.Material == Enum.Material.SmoothPlastic
				and child.Size.X > 0.25
				and child.Size.Y < 0.16
				and child.Size.Z < 0.16
			then
				table.insert(handles, child)
			end

			local volume = child.Size.X * child.Size.Y * child.Size.Z
			if
				child.Size.Y > boxSize.Y * 0.62
				and child.Size.X > 1.1
				and child.Size.Z > 1.1
				and volume > pedestalVolume
			then
				pedestal = child
				pedestalVolume = volume
			end
		end
	end

	if #fronts < 2 then
		return
	end
	table.sort(fronts, function(a, b)
		return a.Position.Y > b.Position.Y
	end)

	local colour, material = sampleAppearance(pedestal or desk)
	local darkColour = colour:Lerp(Color3.fromRGB(20, 16, 13), 0.55)
	local width = 0
	local topY = -math.huge
	local bottomY = math.huge
	local centrePosition = Vector3.zero
	for _, front in fronts do
		width = math.max(width, front.Size.X)
		topY = math.max(topY, front.Position.Y + front.Size.Y / 2)
		bottomY = math.min(bottomY, front.Position.Y - front.Size.Y / 2)
		centrePosition += front.Position
	end
	centrePosition /= #fronts
	centrePosition = Vector3.new(centrePosition.X, (topY + bottomY) / 2, centrePosition.Z)

	local height = topY - bottomY
	local depth = math.clamp(width * 0.95, 1.65, 2.65)
	local thickness = math.clamp(width * 0.045, 0.075, 0.13)
	local outwardDirection = deskOutwardDirection(desk, centrePosition, fronts[1].CFrame.LookVector)
	local faceCF = CFrame.lookAt(centrePosition, centrePosition + outwardDirection)

	if pedestal then
		pedestal.Transparency = 1
		pedestal.CanCollide = false
		pedestal.CanQuery = false
	end

	local cabinet = Instance.new("Model")
	cabinet.Name = "Functional_" .. desk.Name .. "Drawers"
	cabinet:SetAttribute("FurnitureType", "DeskDrawers")
	cabinet.Parent = runtimeFolder

	makePart(
		cabinet,
		"LeftSide",
		Vector3.new(thickness, height, depth),
		faceCF * CFrame.new(-width / 2 + thickness / 2, 0, depth / 2),
		colour,
		material
	)
	makePart(
		cabinet,
		"RightSide",
		Vector3.new(thickness, height, depth),
		faceCF * CFrame.new(width / 2 - thickness / 2, 0, depth / 2),
		colour,
		material
	)
	makePart(
		cabinet,
		"Back",
		Vector3.new(width - thickness * 2, height, thickness),
		faceCF * CFrame.new(0, 0, depth - thickness / 2),
		darkColour,
		material
	)
	makePart(
		cabinet,
		"CabinetTop",
		Vector3.new(width, thickness, depth),
		faceCF * CFrame.new(0, height / 2 - thickness / 2, depth / 2),
		colour,
		material
	)
	makePart(
		cabinet,
		"CabinetBottom",
		Vector3.new(width, thickness, depth),
		faceCF * CFrame.new(0, -height / 2 + thickness / 2, depth / 2),
		colour,
		material
	)

	for index = 1, #fronts - 1 do
		local dividerY = (
			(fronts[index].Position.Y - centrePosition.Y) + (fronts[index + 1].Position.Y - centrePosition.Y)
		) / 2
		makePart(
			cabinet,
			"DrawerDivider",
			Vector3.new(width - thickness * 2, thickness, depth),
			faceCF * CFrame.new(0, dividerY, depth / 2),
			darkColour,
			material
		)
	end

	local usedHandles: { [BasePart]: boolean } = {}
	local soundTemplate = drawerSoundTemplate()
	for drawerIndex, front in fronts do
		local drawer = Instance.new("Model")
		drawer.Name = string.format("DeskDrawer_%02d", drawerIndex)
		drawer:SetAttribute("ContainsLoot", true)
		drawer.Parent = cabinet

		local moving: { BasePart } = { front }
		local closestHandle: BasePart? = nil
		local closestDistance = math.huge
		for _, handle in handles do
			if not usedHandles[handle] then
				local distance = (handle.Position - front.Position).Magnitude
				if distance < closestDistance then
					closestHandle = handle
					closestDistance = distance
				end
			end
		end
		if closestHandle and closestDistance < math.max(front.Size.X, 1.4) then
			usedHandles[closestHandle] = true
			table.insert(moving, closestHandle)
		end

		local drawerWidth = front.Size.X - thickness * 1.4
		local drawerHeight = front.Size.Y * 0.78
		local drawerDepth = depth - thickness * 1.8
		local drawerCF = CFrame.lookAt(front.Position, front.Position + outwardDirection)
		local bottom = makePart(
			drawer,
			"DrawerBottom",
			Vector3.new(drawerWidth, thickness, drawerDepth),
			drawerCF * CFrame.new(0, -drawerHeight / 2 + thickness / 2, drawerDepth / 2),
			darkColour,
			material
		)
		local left = makePart(
			drawer,
			"DrawerSide",
			Vector3.new(thickness, drawerHeight, drawerDepth),
			drawerCF * CFrame.new(-drawerWidth / 2 + thickness / 2, 0, drawerDepth / 2),
			colour,
			material
		)
		local right = makePart(
			drawer,
			"DrawerSide",
			Vector3.new(thickness, drawerHeight, drawerDepth),
			drawerCF * CFrame.new(drawerWidth / 2 - thickness / 2, 0, drawerDepth / 2),
			colour,
			material
		)
		local back = makePart(
			drawer,
			"DrawerBack",
			Vector3.new(drawerWidth, drawerHeight, thickness),
			drawerCF * CFrame.new(0, 0, drawerDepth - thickness / 2),
			colour,
			material
		)
		local contentsColour = if drawerIndex % 2 == 0
			then Color3.fromRGB(226, 217, 191)
			else Color3.fromRGB(94, 112, 124)
		local contents = makePart(
			drawer,
			if drawerIndex % 2 == 0 then "DeskPapers" else "DeskCloth",
			Vector3.new(drawerWidth * 0.58, 0.05, drawerDepth * 0.48),
			drawerCF
				* CFrame.new(
					if drawerIndex % 2 == 0 then -drawerWidth * 0.08 else drawerWidth * 0.1,
					-drawerHeight / 2 + thickness + 0.04,
					drawerDepth * 0.47
				)
				* CFrame.Angles(0, math.rad(if drawerIndex % 2 == 0 then -6 else 5), 0),
			contentsColour,
			if drawerIndex % 2 == 0 then Enum.Material.SmoothPlastic else Enum.Material.Fabric,
			false
		)
		for _, part in { bottom, left, right, back, contents } do
			table.insert(moving, part)
		end

		-- Desk drawers get the same chance of a snack as the dresser drawers do.
		if contentsRng:NextNumber() < 0.34 then
			local snack = FoodPantry.place({
				menu = "snack",
				position = (drawerCF * CFrame.new(0, -drawerHeight / 2 + thickness, drawerDepth * 0.45)).Position,
				parent = drawer,
				rng = contentsRng,
				bars = 1,
				targetSize = math.clamp(math.min(drawerWidth, drawerDepth) * 0.5, 0.35, 1.0),
				armNow = false,
			})
			if snack then
				for _, part in snack:GetDescendants() do
					if part:IsA("BasePart") then
						table.insert(moving, part)
					end
				end
			end
		end

		local travel = math.clamp(depth * 0.72, 1.35, 2.5)
		local outward = outwardDirection * travel
		local opened: { CFrame } = {}
		for movingIndex, part in moving do
			opened[movingIndex] = CFrame.new(outward) * part.CFrame
		end
		local animated = registerAnimatedSet(
			moving,
			opened,
			{ front },
			desk.Name .. " Drawer",
			cloneSound(soundTemplate, front, 0.94),
			cloneSound(soundTemplate, front, 0.84)
		)
		if animated then
			animated.onStateChanged = function(isOpen: boolean)
				if isOpen then
					FoodPantry.serveInside(drawer)
				end
			end
		end
	end
end

local function saveCharacterState(player: Player): CharacterState?
	local humanoid = playerHumanoid(player)
	local root = playerRoot(player)
	local character = player.Character
	if not humanoid or not root or not character then
		return nil
	end

	local collisions: { [BasePart]: boolean } = {}
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			collisions[descendant] = descendant.CanCollide
			descendant.CanCollide = false
		end
	end

	local state: CharacterState = {
		humanoid = humanoid,
		root = root,
		walkSpeed = humanoid.WalkSpeed,
		jumpPower = humanoid.JumpPower,
		jumpHeight = humanoid.JumpHeight,
		autoRotate = humanoid.AutoRotate,
		rootAnchored = root.Anchored,
		cameraOffset = humanoid.CameraOffset,
		collisions = collisions,
	}

	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false
	humanoid.CameraOffset = Vector3.new(0, -0.55, 0)
	root.Anchored = true
	return state
end

local function restoreCharacterState(state: CharacterState)
	if not state.humanoid.Parent or not state.root.Parent then
		return
	end
	state.root.Anchored = state.rootAnchored
	state.humanoid.WalkSpeed = state.walkSpeed
	state.humanoid.JumpPower = state.jumpPower
	state.humanoid.JumpHeight = state.jumpHeight
	state.humanoid.AutoRotate = state.autoRotate
	state.humanoid.CameraOffset = state.cameraOffset
	for part, canCollide in state.collisions do
		if part.Parent then
			part.CanCollide = canCollide
		end
	end
end

local function updateHidePrompt(spot: HideSpot)
	spot.prompt.ActionText = if spot.occupant then "Exit" else "Hide"
	spot.prompt.ObjectText = if spot.occupant then "Occupied Closet" else "Closet"
	spot.prompt.Enabled = spot.doors == nil or spot.occupant ~= nil or (spot.doors :: AnimatedSet).isOpen
end

local function leaveHideSpot(spot: HideSpot, player: Player)
	if spot.occupant ~= player then
		return
	end

	if spot.doors and not spot.doors.isOpen then
		setOpen(spot.doors, true)
		task.wait(OPEN_INFO.Time * 0.72)
	end

	local state = spot.savedState
	if state and state.root.Parent then
		state.root.CFrame = spot.exitCFrame
		restoreCharacterState(state)
	end

	spot.occupant = nil
	spot.savedState = nil
	player:SetAttribute("HidingInCloset", false)
	if spot.doors then
		spot.doors.locked = false
		updatePromptText(spot.doors)
	end
	updateHidePrompt(spot)

	if spot.doors then
		task.delay(1.15, function()
			if not spot.occupant and spot.doors and spot.doors.isOpen then
				setOpen(spot.doors, false)
			end
		end)
	end
end

local function enterHideSpot(spot: HideSpot, player: Player)
	if spot.occupant then
		spot.prompt.ObjectText = "Closet Occupied"
		task.delay(1, function()
			if spot.prompt.Parent then
				updateHidePrompt(spot)
			end
		end)
		return
	end
	if spot.doors and not spot.doors.isOpen then
		return
	end

	local state = saveCharacterState(player)
	if not state then
		return
	end

	spot.occupant = player
	spot.savedState = state
	state.root.CFrame = spot.hideCFrame
	player:SetAttribute("HidingInCloset", true)
	if spot.doors then
		spot.doors.locked = true
		updatePromptText(spot.doors)
		task.delay(OPEN_INFO.Time + 0.08, function()
			if spot.occupant == player and spot.doors and spot.doors.isOpen then
				setOpen(spot.doors, false)
			end
		end)
	end
	updateHidePrompt(spot)
end

local function registerHideSpot(anchor: BasePart, hideCFrame: CFrame, exitCFrame: CFrame, doors: AnimatedSet?): HideSpot
	local spot: HideSpot = {
		prompt = makePrompt(anchor, "Hide", "Closet"),
		anchor = anchor,
		hideCFrame = hideCFrame,
		exitCFrame = exitCFrame,
		doors = doors,
		occupant = nil,
		savedState = nil,
	}
	table.insert(hideSpots, spot)

	spot.prompt.MaxActivationDistance = 5.5
	spot.prompt.Triggered:Connect(function(player)
		if spot.occupant == player then
			leaveHideSpot(spot, player)
		elseif isPlayerNear(player, anchor, spot.prompt.MaxActivationDistance + 2) then
			enterHideSpot(spot, player)
		end
	end)
	updateHidePrompt(spot)
	return spot
end

local function buildWardrobe(source: Model)
	local rootCF, sourceSize = targetFrameAndSize(source)
	local width = math.max(sourceSize.X, 4.6)
	local height = math.max(sourceSize.Y, 6.2)
	local depth = math.max(sourceSize.Z, 3.15)
	local colour, material = sampleAppearance(source)
	local interiorColour = colour:Lerp(Color3.fromRGB(18, 14, 12), 0.62)
	local thickness = math.clamp(math.min(width, depth) * 0.045, 0.12, 0.2)
	local doorThickness = math.max(0.13, thickness * 0.9)
	local frontZ = -depth / 2 - doorThickness / 2

	local openSoundTemplate = findSound(source, "Open")
	local closeSoundTemplate = findSound(source, "Close")
	hideSource(source)

	local wardrobe = Instance.new("Model")
	wardrobe.Name = "Functional_" .. source.Name
	wardrobe:SetAttribute("FurnitureType", "HidingCloset")
	wardrobe.Parent = runtimeFolder

	makePart(
		wardrobe,
		"Back",
		Vector3.new(width, height, thickness),
		rootCF * CFrame.new(0, 0, depth / 2 - thickness / 2),
		interiorColour,
		material
	)
	makePart(
		wardrobe,
		"LeftSide",
		Vector3.new(thickness, height, depth),
		rootCF * CFrame.new(-width / 2 + thickness / 2, 0, 0),
		colour,
		material
	)
	makePart(
		wardrobe,
		"RightSide",
		Vector3.new(thickness, height, depth),
		rootCF * CFrame.new(width / 2 - thickness / 2, 0, 0),
		colour,
		material
	)
	makePart(
		wardrobe,
		"Top",
		Vector3.new(width, thickness, depth),
		rootCF * CFrame.new(0, height / 2 - thickness / 2, 0),
		colour,
		material
	)
	makePart(
		wardrobe,
		"Floor",
		Vector3.new(width, thickness, depth),
		rootCF * CFrame.new(0, -height / 2 + thickness / 2, 0),
		interiorColour,
		material
	)
	makePart(
		wardrobe,
		"Shelf",
		Vector3.new(width - thickness * 2, thickness, depth - thickness * 1.4),
		rootCF * CFrame.new(0, height * 0.27, thickness * 0.2),
		interiorColour,
		material
	)

	local rail = makePart(
		wardrobe,
		"ClothesRail",
		Vector3.new(width - thickness * 3, 0.11, 0.11),
		rootCF * CFrame.new(0, height * 0.12, 0),
		Color3.fromRGB(67, 65, 62),
		Enum.Material.Metal,
		false
	)
	rail.Shape = Enum.PartType.Cylinder

	for coatIndex = -1, 1 do
		local coatColour = if coatIndex == 0 then Color3.fromRGB(77, 57, 47) else Color3.fromRGB(34, 39, 44)
		makePart(
			wardrobe,
			"HangingCoat",
			Vector3.new(width * 0.2, height * 0.35, 0.16),
			rootCF * CFrame.new(coatIndex * width * 0.23, -height * 0.09, depth * 0.16),
			coatColour,
			Enum.Material.Fabric,
			false
		)
	end

	local doorWidth = width / 2 - thickness * 0.65
	local doorHeight = height - thickness * 1.35
	local leftX = -width / 4
	local rightX = width / 4
	local leftDoor = makePart(
		wardrobe,
		"LeftDoor",
		Vector3.new(doorWidth, doorHeight, doorThickness),
		rootCF * CFrame.new(leftX, 0, frontZ),
		colour,
		material
	)
	local rightDoor = makePart(
		wardrobe,
		"RightDoor",
		Vector3.new(doorWidth, doorHeight, doorThickness),
		rootCF * CFrame.new(rightX, 0, frontZ),
		colour,
		material
	)
	local panelColour = colour:Lerp(Color3.fromRGB(255, 255, 255), 0.07)
	local leftInset = makePart(
		wardrobe,
		"LeftDoorInset",
		Vector3.new(doorWidth * 0.72, doorHeight * 0.78, doorThickness * 0.3),
		rootCF * CFrame.new(leftX, 0, frontZ - doorThickness * 0.66),
		panelColour,
		material,
		false
	)
	local rightInset = makePart(
		wardrobe,
		"RightDoorInset",
		Vector3.new(doorWidth * 0.72, doorHeight * 0.78, doorThickness * 0.3),
		rootCF * CFrame.new(rightX, 0, frontZ - doorThickness * 0.66),
		panelColour,
		material,
		false
	)
	local leftHandle = makePart(
		wardrobe,
		"LeftHandle",
		Vector3.new(0.1, 0.74, 0.12),
		rootCF * CFrame.new(-thickness * 0.75, 0, frontZ - doorThickness * 0.9),
		Color3.fromRGB(47, 42, 38),
		Enum.Material.Metal,
		false
	)
	local rightHandle = makePart(
		wardrobe,
		"RightHandle",
		Vector3.new(0.1, 0.74, 0.12),
		rootCF * CFrame.new(thickness * 0.75, 0, frontZ - doorThickness * 0.9),
		Color3.fromRGB(47, 42, 38),
		Enum.Material.Metal,
		false
	)

	local leftHinge = rootCF * CFrame.new(-width / 2 + thickness * 0.45, 0, frontZ)
	local rightHinge = rootCF * CFrame.new(width / 2 - thickness * 0.45, 0, frontZ)
	local moving: { BasePart } = { leftDoor, leftInset, leftHandle, rightDoor, rightInset, rightHandle }
	local opened: { CFrame } = {}
	for index, part in moving do
		local hinge = if index <= 3 then leftHinge else rightHinge
		local angle = if index <= 3 then math.rad(104) else math.rad(-104)
		opened[index] = hinge * CFrame.Angles(0, angle, 0) * hinge:ToObjectSpace(part.CFrame)
	end

	local doors = registerAnimatedSet(
		moving,
		opened,
		{ leftDoor, rightDoor },
		"Wardrobe",
		cloneSound(openSoundTemplate or drawerSoundTemplate(), leftDoor, 0.9),
		cloneSound(closeSoundTemplate or drawerSoundTemplate(), rightDoor, 0.82)
	)
	if not doors then
		return
	end

	local hideAnchor = makePart(
		wardrobe,
		"HidePoint",
		Vector3.new(width * 0.5, 2.6, 0.25),
		rootCF * CFrame.new(0, -height / 2 + 2.45, depth * 0.3),
		interiorColour,
		Enum.Material.SmoothPlastic,
		false
	)
	hideAnchor.Transparency = 1
	hideAnchor.CanQuery = false
	local spot = registerHideSpot(
		hideAnchor,
		rootCF * CFrame.new(0, -height / 2 + 3, depth * 0.08),
		rootCF * CFrame.new(0, -height / 2 + 3, -depth / 2 - 2.6),
		doors
	)
	doors.onStateChanged = function()
		updateHidePrompt(spot)
	end
end

local function setupLegacyDrawer()
	local drawer = Workspace:FindFirstChild("Drawer")
	if not drawer or not drawer:IsA("Model") then
		return
	end

	local body = drawer:FindFirstChild("Body")
	local soundTemplate = if body then body:FindFirstChildOfClass("Sound") else nil
	for _, child in drawer:GetChildren() do
		if child:IsA("BasePart") and child.Name == "Interact" then
			for _, oldPrompt in child:GetChildren() do
				if oldPrompt:IsA("ClickDetector") or oldPrompt:IsA("ProximityPrompt") then
					oldPrompt:Destroy()
				end
			end
			registerAnimatedSet(
				{ child },
				{ child.CFrame * CFrame.new(0, 0, -2.25) },
				{ child },
				"Drawer",
				cloneSound(soundTemplate, child, 0.95),
				cloneSound(soundTemplate, child, 0.83)
			)
		end
	end
end

local function setupServerCabinets()
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("Model") and string.find(lowerName(descendant), "cabinet", 1, true) then
			local rootCF, size = targetFrameAndSize(descendant)
			local moving: { BasePart } = {}
			for _, part in descendant:GetDescendants() do
				if part:IsA("BasePart") then
					local name = lowerName(part)
					if string.find(name, "door", 1, true) or string.find(name, "glass", 1, true) then
						table.insert(moving, part)
					end
				end
			end
			if #moving > 0 then
				local hinge = rootCF * CFrame.new(-size.X / 2, 0, -size.Z / 2)
				local opened: { CFrame } = {}
				for index, part in moving do
					opened[index] = hinge * CFrame.Angles(0, math.rad(105), 0) * hinge:ToObjectSpace(part.CFrame)
				end
				registerAnimatedSet(moving, opened, { moving[1] }, "Display Cabinet", nil, nil)
			end
		end
	end
end

local function setupDrawerCabinets()
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("Model") then
			local name = lowerName(descendant)
			if string.find(name, "nightstand", 1, true) then
				buildDrawerCabinet(descendant, descendant.Name, 1, 2, true)
			end
		end
	end

	local suiteFloor = Workspace:FindFirstChild("SuiteFloor")
	local furniture = suiteFloor and suiteFloor:FindFirstChild("Furniture")
	if not furniture then
		return
	end

	for _, descendant in furniture:GetDescendants() do
		if descendant:IsA("BasePart") then
			local name = lowerName(descendant)
			if name == "nightstand" then
				buildDrawerCabinet(descendant, descendant.Name, 1, 2, true)
			elseif string.find(name, "beddresser", 1, true) and not string.find(name, "top", 1, true) then
				buildDrawerCabinet(descendant, descendant.Name, 3, 2)
			end
		end
	end
end

local function setupDesks()
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("Model") and string.match(lowerName(descendant), "^r%d+_desk$") then
			buildDeskDrawers(descendant)
		end
	end
end

local function setupWardrobes()
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("Model") and string.find(lowerName(descendant), "wardrobe", 1, true) then
			buildWardrobe(descendant)
		end
	end
end

local function setupWalkInClosets()
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("BasePart") and string.find(lowerName(descendant), "closetbench", 1, true) then
			local anchor = makePart(
				runtimeFolder,
				"WalkInClosetHidePoint",
				Vector3.new(2.5, 2.5, 0.25),
				descendant.CFrame * CFrame.new(0, descendant.Size.Y / 2 + 1.35, 0),
				Color3.new(),
				Enum.Material.SmoothPlastic,
				false
			)
			anchor.Transparency = 1
			anchor.CanQuery = false
			registerHideSpot(
				anchor,
				descendant.CFrame * CFrame.new(0, descendant.Size.Y / 2 + 2.8, 0),
				descendant.CFrame * CFrame.new(0, descendant.Size.Y / 2 + 2.8, -descendant.Size.Z / 2 - 2.5),
				nil
			)
		end
	end
end

local function clearPlayerFromHideSpot(player: Player)
	for _, spot in hideSpots do
		if spot.occupant == player then
			if spot.savedState then
				restoreCharacterState(spot.savedState)
			end
			spot.occupant = nil
			spot.savedState = nil
			if spot.doors then
				spot.doors.locked = false
				updatePromptText(spot.doors)
			end
			updateHidePrompt(spot)
		end
	end
	player:SetAttribute("HidingInCloset", false)
end

setupLegacyDrawer()
setupServerCabinets()
setupDrawerCabinets()
setupDesks()
setupWardrobes()
setupWalkInClosets()

for _, player in Players:GetPlayers() do
	player:SetAttribute("HidingInCloset", false)
	player.CharacterRemoving:Connect(function()
		clearPlayerFromHideSpot(player)
	end)
end
Players.PlayerAdded:Connect(function(player: Player)
	player:SetAttribute("HidingInCloset", false)
	player.CharacterRemoving:Connect(function()
		clearPlayerFromHideSpot(player)
	end)
end)
Players.PlayerRemoving:Connect(function(player: Player)
	clearPlayerFromHideSpot(player)
end)

print(string.format("[FurnitureInteractionService] ready: %d hiding spots", #hideSpots))
