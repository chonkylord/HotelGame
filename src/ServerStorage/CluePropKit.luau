--!strict
--[[
	Shared physical vocabulary for clue nodes. ClueService owns every answer,
	lockout, and round transition; this module only builds recognisable props and
	exposes their prompts and ContainerKit animation state. Keeping the mechanics
	thin here lets the same note, crate, panel, and carry object be placed at any
	tagged site without creating a second source of gameplay authority.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClueConfig = require(ReplicatedStorage:WaitForChild("ClueConfig"))
local ContainerKit = require(script.Parent:WaitForChild("ContainerKit"))

local CluePropKit = {}

local PAPER = Color3.fromRGB(219, 202, 157)
local PAPER_DARK = Color3.fromRGB(154, 126, 77)
local INK = Color3.fromRGB(38, 30, 25)
local BLOOD = Color3.fromRGB(111, 38, 32)
local STEEL_DARK = Color3.fromRGB(39, 46, 53)
local STEEL_MID = Color3.fromRGB(82, 91, 98)
local STEEL_EDGE = Color3.fromRGB(154, 164, 169)
local WOOD = Color3.fromRGB(82, 57, 36)
local WOOD_DARK = Color3.fromRGB(49, 34, 24)
local AMBER = Color3.fromRGB(255, 183, 62)
local GREEN = Color3.fromRGB(78, 255, 157)
local LED_OFF = Color3.fromRGB(32, 18, 12)

export type BreakerLever = {
	index: number,
	part: BasePart,
	prompt: ProximityPrompt,
	animated: ContainerKit.AnimatedSet,
	led: BasePart,
}

export type Panel = {
	model: Model,
	levers: { BreakerLever },
	handle: BasePart,
	handlePrompt: ProximityPrompt,
	hatch: BasePart,
	hatchAnimated: ContainerKit.AnimatedSet,
}

local function addLabel(
	part: BasePart,
	face: Enum.NormalId,
	text: string,
	textColor: Color3,
	font: Enum.Font,
	canvasSize: Vector2?
): TextLabel
	local surface = Instance.new("SurfaceGui")
	surface.Name = "Label"
	surface.Face = face
	surface.CanvasSize = canvasSize or Vector2.new(480, 160)
	surface.LightInfluence = 0
	surface.PixelsPerStud = 90
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.ZOffset = 1
	surface.Parent = part

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = font
	label.Text = text
	label.TextColor3 = textColor
	label.TextScaled = true
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.85
	label.Parent = surface
	return label
end

local function registered(options: ContainerKit.RegisterOptions): ContainerKit.AnimatedSet
	local animated = ContainerKit.register(options)
	assert(animated, "CluePropKit supplied invalid ContainerKit animation geometry")
	return animated
end

-- Notes ----------------------------------------------------------------------

function CluePropKit.makeNote(parent: Instance, cframe: CFrame, objectText: string): (Model, ProximityPrompt)
	local model = Instance.new("Model")
	model.Name = "ClueNote"
	model.Parent = parent

	local paper = ContainerKit.makePart(
		model,
		"Paper",
		Vector3.new(3.6, 0.09, 2.5),
		cframe * CFrame.new(0, 0.08, 0) * CFrame.Angles(0, math.rad(-4), 0),
		PAPER,
		Enum.Material.Fabric,
		false
	)
	paper.CastShadow = false

	local edge = ContainerKit.makePart(
		model,
		"TornEdge",
		Vector3.new(3.45, 0.035, 0.12),
		paper.CFrame * CFrame.new(0, 0.065, 1.08) * CFrame.Angles(0, math.rad(2), 0),
		PAPER_DARK,
		Enum.Material.Fabric,
		false
	)
	edge.CastShadow = false

	local seal = ContainerKit.makePart(
		model,
		"WaxSeal",
		Vector3.new(0.48, 0.12, 0.48),
		paper.CFrame * CFrame.new(1.2, 0.11, 0.72),
		BLOOD,
		Enum.Material.SmoothPlastic,
		false
	)
	seal.Shape = Enum.PartType.Cylinder
	seal.CFrame *= CFrame.Angles(0, 0, math.rad(90))

	addLabel(paper, Enum.NormalId.Top, "EVIDENCE  ·  READ ME", INK, Enum.Font.Garamond, Vector2.new(600, 300))

	local prompt = ContainerKit.makePrompt(paper, "Read", objectText, ClueConfig.InteractionDistance)
	prompt.Name = "ReadCluePrompt"
	prompt.HoldDuration = 0.2
	CollectionService:AddTag(prompt, ClueConfig.PromptTag)

	model.PrimaryPart = paper
	return model, prompt
end

-- Breaker panel --------------------------------------------------------------

function CluePropKit.makeBreakerPanel(parent: Instance, cframe: CFrame, leverCount: number): Panel
	assert(leverCount >= 1 and leverCount <= 6, "breaker panels support one to six levers")

	local model = Instance.new("Model")
	model.Name = "ClueBreakerPanel"
	model.Parent = parent

	local body = ContainerKit.makePart(
		model,
		"PanelBody",
		Vector3.new(9, 8.6, 0.72),
		cframe * CFrame.new(0, 4.4, 0),
		STEEL_MID,
		Enum.Material.Metal,
		true
	)
	local backing = ContainerKit.makePart(
		model,
		"PanelBacking",
		Vector3.new(9.7, 9.25, 0.34),
		cframe * CFrame.new(0, 4.4, 0.5),
		STEEL_DARK,
		Enum.Material.DiamondPlate,
		true
	)
	backing.CanQuery = false

	local title = ContainerKit.makePart(
		model,
		"TitlePlate",
		Vector3.new(7.2, 0.75, 0.12),
		cframe * CFrame.new(0, 7.95, -0.43),
		STEEL_EDGE,
		Enum.Material.Metal,
		false
	)
	addLabel(title, Enum.NormalId.Front, "SERVICE BREAKER  ·  01—06", INK, Enum.Font.GothamBold)

	local recess = ContainerKit.makePart(
		model,
		"HatchRecess",
		Vector3.new(5.9, 1.42, 0.12),
		cframe * CFrame.new(0, 1.02, -0.45),
		Color3.fromRGB(10, 13, 15),
		Enum.Material.SmoothPlastic,
		false
	)
	recess.CastShadow = false

	local hatch = ContainerKit.makePart(
		model,
		"RevealHatch",
		Vector3.new(5.65, 1.18, 0.2),
		cframe * CFrame.new(0, 1.02, -0.58),
		STEEL_DARK,
		Enum.Material.DiamondPlate,
		false
	)
	local hatchAnimated = registered({
		parts = { hatch },
		opened = { ContainerKit.slid(cframe, CFrame.new(0, -1.35, 0), hatch) },
		promptParts = {},
		objectText = "Breaker hatch",
	})
	hatchAnimated.locked = true

	local levers: { BreakerLever } = {}
	for index = 1, leverCount do
		local column = (index - 1) % 3
		local row = math.floor((index - 1) / 3)
		local x = (column - 1) * 2.35
		local y = 6.15 - row * 2.35

		local lever = ContainerKit.makePart(
			model,
			`Lever_{index}`,
			Vector3.new(0.38, 1.72, 0.42),
			cframe * CFrame.new(x, y, -0.73) * CFrame.Angles(math.rad(-32), 0, 0),
			STEEL_EDGE,
			Enum.Material.Metal,
			false
		)
		lever:SetAttribute(ClueConfig.LeverIndexAttribute, index)
		CollectionService:AddTag(lever, ClueConfig.LeverTag)

		local grip = ContainerKit.makePart(
			model,
			`LeverGrip_{index}`,
			Vector3.new(0.72, 0.62, 0.65),
			lever.CFrame * CFrame.new(0, 0.84, 0),
			BLOOD,
			Enum.Material.SmoothPlastic,
			false
		)
		grip.CanQuery = false

		local led = ContainerKit.makePart(
			model,
			`LeverLED_{index}`,
			Vector3.new(0.42, 0.42, 0.15),
			cframe * CFrame.new(x + 0.85, y + 0.2, -0.55),
			LED_OFF,
			Enum.Material.Neon,
			false
		)
		led.CastShadow = false
		led.CanQuery = false

		local hinge = cframe * CFrame.new(x, y - 0.78, -0.55)
		local animated = registered({
			parts = { lever, grip },
			opened = {
				ContainerKit.hinged(hinge, CFrame.Angles(math.rad(68), 0, 0), lever),
				ContainerKit.hinged(hinge, CFrame.Angles(math.rad(68), 0, 0), grip),
			},
			promptParts = { lever },
			objectText = `Breaker switch {index}`,
			openText = "Raise",
			closeText = "Lower",
			promptDistance = ClueConfig.InteractionDistance,
		})
		local prompt = animated.prompts[1]
		assert(prompt, "breaker lever registration did not create a prompt")
		prompt.Name = "LeverPrompt"
		prompt.HoldDuration = 0.16
		prompt:SetAttribute(ClueConfig.LeverIndexAttribute, index)
		animated.onStateChanged = function(isRaised: boolean)
			led.Color = if isRaised then GREEN else LED_OFF
		end

		table.insert(levers, {
			index = index,
			part = lever :: BasePart,
			prompt = prompt,
			animated = animated,
			led = led :: BasePart,
		})
	end

	local handleMount = ContainerKit.makePart(
		model,
		"HandleMount",
		Vector3.new(1.05, 3.3, 0.48),
		cframe * CFrame.new(4.7, 4.3, -0.12),
		STEEL_DARK,
		Enum.Material.DiamondPlate,
		true
	)
	local handle = ContainerKit.makePart(
		model,
		"PullHandle",
		Vector3.new(0.42, 2.25, 0.62),
		cframe * CFrame.new(4.7, 4.3, -0.62) * CFrame.Angles(math.rad(-18), 0, 0),
		AMBER,
		Enum.Material.Metal,
		false
	)
	handleMount.CanQuery = false
	local handlePrompt =
		ContainerKit.makePrompt(handle, "Pull", "Breaker master handle", ClueConfig.InteractionDistance)
	handlePrompt.Name = "PullHandlePrompt"
	handlePrompt.HoldDuration = 5
	CollectionService:AddTag(handlePrompt, ClueConfig.PromptTag)

	model.PrimaryPart = body
	return {
		model = model,
		levers = levers,
		handle = handle,
		handlePrompt = handlePrompt,
		hatch = hatch,
		hatchAnimated = hatchAnimated,
	}
end

-- Search container -----------------------------------------------------------

function CluePropKit.makeSearchContainer(
	parent: Instance,
	cframe: CFrame,
	objectText: string
): (Model, ProximityPrompt, ContainerKit.AnimatedSet)
	local model = Instance.new("Model")
	model.Name = "ClueSearchCrate"
	model.Parent = parent

	local base = ContainerKit.makePart(
		model,
		"CrateBody",
		Vector3.new(5, 2.35, 3.8),
		cframe * CFrame.new(0, 1.18, 0),
		WOOD,
		Enum.Material.WoodPlanks,
		true
	)
	local lid = ContainerKit.makePart(
		model,
		"CrateLid",
		Vector3.new(5.2, 0.38, 4),
		cframe * CFrame.new(0, 2.55, 0),
		WOOD_DARK,
		Enum.Material.WoodPlanks,
		true
	)
	local latch = ContainerKit.makePart(
		model,
		"Latch",
		Vector3.new(0.8, 0.78, 0.18),
		cframe * CFrame.new(0, 2.05, -1.98),
		STEEL_EDGE,
		Enum.Material.Metal,
		false
	)
	local stencil = ContainerKit.makePart(
		model,
		"SearchStencil",
		Vector3.new(3.55, 0.72, 0.08),
		cframe * CFrame.new(0, 1.18, -1.96),
		PAPER_DARK,
		Enum.Material.Fabric,
		false
	)
	addLabel(stencil, Enum.NormalId.Front, "HOTEL STORES  ·  UNLOGGED", INK, Enum.Font.GothamBold)

	local hinge = cframe * CFrame.new(0, 2.42, 1.9)
	local animated = registered({
		parts = { lid },
		opened = { ContainerKit.hinged(hinge, CFrame.Angles(math.rad(102), 0, 0), lid) },
		promptParts = { latch },
		objectText = objectText,
		openText = "Open",
		closeText = "Close",
		promptDistance = ClueConfig.InteractionDistance,
	})

	local searchPrompt = ContainerKit.makePrompt(base, "Search", objectText, ClueConfig.InteractionDistance)
	searchPrompt.Name = "SearchCluePrompt"
	searchPrompt.HoldDuration = 1.1
	searchPrompt.Enabled = false
	CollectionService:AddTag(searchPrompt, ClueConfig.PromptTag)
	animated.onStateChanged = function(isOpen: boolean)
		searchPrompt.Enabled = isOpen
	end

	model.PrimaryPart = base
	return model, searchPrompt, animated
end

-- Carry puzzle ---------------------------------------------------------------

function CluePropKit.makeReceptacle(parent: Instance, cframe: CFrame, carryId: string): (Part, ProximityPrompt)
	local receptacle = ContainerKit.makePart(
		parent,
		"ClueReceptacle",
		Vector3.new(3.1, 2.4, 1.15),
		cframe * CFrame.new(0, 1.2, 0),
		STEEL_DARK,
		Enum.Material.DiamondPlate,
		true
	)
	receptacle:SetAttribute(ClueConfig.CarryIdAttribute, carryId)
	CollectionService:AddTag(receptacle, ClueConfig.ReceptacleTag)

	local slot = ContainerKit.makePart(
		receptacle,
		"Slot",
		Vector3.new(1.85, 0.34, 0.12),
		receptacle.CFrame * CFrame.new(0, 0.25, -0.62),
		Color3.fromRGB(8, 10, 12),
		Enum.Material.SmoothPlastic,
		false
	)
	slot.CastShadow = false
	addLabel(receptacle, Enum.NormalId.Front, "SERVICE INPUT", AMBER, Enum.Font.GothamBold)

	local prompt = ContainerKit.makePrompt(receptacle, "Insert", "Service receptacle", ClueConfig.InteractionDistance)
	prompt.Name = "InsertCarryPrompt"
	prompt.HoldDuration = 5
	prompt.Enabled = false
	prompt:SetAttribute(ClueConfig.CarryIdAttribute, carryId)
	CollectionService:AddTag(prompt, ClueConfig.PromptTag)
	return receptacle, prompt
end

function CluePropKit.makeCarryItem(parent: Instance, cframe: CFrame, carryId: string, displayName: string): Model
	local model = Instance.new("Model")
	model.Name = displayName
	model:SetAttribute(ClueConfig.CarryIdAttribute, carryId)

	local isCard = string.find(string.lower(displayName), "card", 1, true) ~= nil
	local body = ContainerKit.makePart(
		model,
		"CarryBody",
		if isCard then Vector3.new(2.2, 0.16, 1.35) else Vector3.new(2.25, 0.72, 0.72),
		cframe * CFrame.new(0, if isCard then 0.16 else 0.42, 0),
		if isCard then PAPER_DARK else STEEL_EDGE,
		if isCard then Enum.Material.SmoothPlastic else Enum.Material.Metal,
		true
	)

	if isCard then
		local stripe = ContainerKit.makePart(
			model,
			"MagneticStripe",
			Vector3.new(1.8, 0.04, 0.28),
			body.CFrame * CFrame.new(0, 0.1, 0.35),
			INK,
			Enum.Material.SmoothPlastic,
			false
		)
		stripe.CastShadow = false
		addLabel(body, Enum.NormalId.Top, "SERVICE  ·  KEYCARD", INK, Enum.Font.GothamBold)
	else
		body.Shape = Enum.PartType.Cylinder
		for side = -1, 1, 2 do
			local cap = ContainerKit.makePart(
				model,
				if side < 0 then "FuseCapA" else "FuseCapB",
				Vector3.new(0.32, 0.82, 0.82),
				body.CFrame * CFrame.new(side * 1.08, 0, 0),
				AMBER,
				Enum.Material.Metal,
				false
			)
			cap.Shape = Enum.PartType.Cylinder
		end
	end

	model.PrimaryPart = body
	model.Parent = parent
	CollectionService:AddTag(model, ClueConfig.CarryItemTag)
	CollectionService:AddTag(model, ClueConfig.CollectableTag)
	return model
end

return CluePropKit
