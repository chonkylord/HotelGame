--!strict
--[[
	Shared building blocks for openable furniture.

	FurnitureInteractionService grew its own copies of these helpers while it was
	the only thing building hinged doors and sliding drawers. StorageRoomLootService
	needs the same machinery, so the generic parts live here: build a part, build a
	prompt, group a set of parts into something that tweens between a closed and an
	opened pose, and borrow a sound off an existing model.

	Nothing in here knows what a box or a wardrobe is — callers supply the opened
	CFrames and this module owns the state, the tween, and the prompt text.
]]

local TweenService = game:GetService("TweenService")

local ContainerKit = {}

ContainerKit.OpenInfo = TweenInfo.new(0.48, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
ContainerKit.CloseInfo = TweenInfo.new(0.36, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

export type AnimatedSet = {
	parts: { BasePart },
	closed: { CFrame },
	opened: { CFrame },
	prompts: { ProximityPrompt },
	isOpen: boolean,
	busy: boolean,
	locked: boolean,
	serial: number,
	objectText: string,
	openText: string,
	closeText: string,
	openSound: Sound?,
	closeSound: Sound?,
	onStateChanged: ((boolean) -> ())?,
}

-- Parts ----------------------------------------------------------------------

function ContainerKit.makePart(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	colour: Color3,
	material: Enum.Material,
	canCollide: boolean?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = if canCollide == nil then true else canCollide
	part.CanTouch = false
	part.CanQuery = true
	part.CastShadow = true
	part.Material = material
	part.Color = colour
	part.Size = size
	part.CFrame = cframe
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Prompts --------------------------------------------------------------------

function ContainerKit.makePrompt(
	parent: BasePart,
	actionText: string,
	objectText: string,
	maxDistance: number
): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ContainerPrompt"
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0.12
	prompt.MaxActivationDistance = maxDistance
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.Parent = parent
	return prompt
end

-- Sound ----------------------------------------------------------------------

function ContainerKit.findSound(source: Instance, wantedName: string): Sound?
	local wanted = string.lower(wantedName)
	for _, descendant in source:GetDescendants() do
		if descendant:IsA("Sound") and string.lower(descendant.Name) == wanted then
			return descendant
		end
	end
	return nil
end

function ContainerKit.cloneSound(template: Sound?, parent: Instance, speed: number, volume: number?): Sound?
	if not template then
		return nil
	end
	local sound = template:Clone()
	sound.PlaybackSpeed = speed
	if volume then
		sound.Volume = volume
	end
	sound.Parent = parent
	return sound
end

-- Open / close ---------------------------------------------------------------

function ContainerKit.updatePromptText(animated: AnimatedSet)
	for _, prompt in animated.prompts do
		prompt.ActionText = if animated.isOpen then animated.closeText else animated.openText
		prompt.ObjectText = animated.objectText
		prompt.Enabled = not animated.locked
	end
end

function ContainerKit.setOpen(animated: AnimatedSet, shouldOpen: boolean)
	if animated.busy or animated.isOpen == shouldOpen then
		return
	end

	animated.busy = true
	animated.isOpen = shouldOpen
	animated.serial += 1
	local serial = animated.serial
	local tweenInfo = if shouldOpen then ContainerKit.OpenInfo else ContainerKit.CloseInfo

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

	ContainerKit.updatePromptText(animated)
	if animated.onStateChanged then
		animated.onStateChanged(shouldOpen)
	end

	-- Guard against a later toggle finishing first and unlocking early.
	task.delay(tweenInfo.Time + 0.05, function()
		if animated.serial == serial then
			animated.busy = false
		end
	end)
end

export type RegisterOptions = {
	parts: { BasePart },
	opened: { CFrame },
	promptParts: { BasePart },
	objectText: string,
	openText: string?,
	closeText: string?,
	promptDistance: number?,
	openSound: Sound?,
	closeSound: Sound?,
	onTriggered: ((Player, AnimatedSet) -> ())?,
}

function ContainerKit.register(options: RegisterOptions): AnimatedSet?
	local parts = options.parts
	local opened = options.opened
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
		objectText = options.objectText,
		openText = options.openText or "Open",
		closeText = options.closeText or "Close",
		openSound = options.openSound,
		closeSound = options.closeSound,
		onStateChanged = nil,
	}

	local distance = options.promptDistance or 7.5
	for _, promptPart in options.promptParts do
		local prompt = ContainerKit.makePrompt(promptPart, animated.openText, animated.objectText, distance)
		table.insert(animated.prompts, prompt)
		prompt.Triggered:Connect(function(player: Player)
			if animated.locked then
				return
			end
			-- Re-check range on the server: the client can fire a prompt it has
			-- no business reaching.
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not root or not root:IsA("BasePart") then
				return
			end
			if (root.Position - promptPart.Position).Magnitude > distance + 2 then
				return
			end
			if options.onTriggered then
				options.onTriggered(player, animated)
			else
				ContainerKit.setOpen(animated, not animated.isOpen)
			end
		end)
	end

	return animated
end

-- Geometry -------------------------------------------------------------------

-- Opened pose for a part swinging about a hinge line, e.g. a lid or a door.
function ContainerKit.hinged(hinge: CFrame, rotation: CFrame, part: BasePart): CFrame
	return hinge * rotation * hinge:ToObjectSpace(part.CFrame)
end

-- Opened pose for a part sliding along an offset in its own frame, e.g. a drawer.
function ContainerKit.slid(root: CFrame, offset: CFrame, part: BasePart): CFrame
	return root * offset * root:ToObjectSpace(part.CFrame)
end

return ContainerKit
