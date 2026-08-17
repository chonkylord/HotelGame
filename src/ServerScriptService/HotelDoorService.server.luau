--!strict
-- Drives every door tagged "HotelDoor".
--
-- Each tagged model looks like:
--   Room<N>Door            attributes: RoomLabel (string), Code (string),
--                                      State (string), ExitPrompt (boolean)
--     Leaf/Hinge           anchored pivot; the rest of the leaf is welded to it
--     Keypad/Display       Neon part with a SurfaceGui TextLabel named "Text"
--     Keypad/LED           status light
--     Keypad/Buttons/B0..B9, BC, BE   each a part with a ClickDetector
--     ExitButton           room-side release plate. Which side of the leaf it
--                          sits on is what defines "inside" for that door.
--
-- State decides what a door can do:
--   Normal   punch the code on the corridor keypad to get in
--   Broken   the keypad reads ERROR and takes no input; the door never opens
--   Jammed   the keypad is gone and the leaf hangs ajar against whatever is
--            wedged in the gap; the door never opens
--   Smashed  a Muscle player put a shoulder through it; it hangs open for good
--
-- "Never opens" is by its own mechanism. Two classes get past that anyway:
--   Muscle   forces only Broken or Jammed doors, permanently
--   Hacker   bypasses the keypad on any state in ClassConfig.HackableStates
--
-- The two are not the same key. Smashing is destructive and final — the leaf
-- ends up hanging open for the rest of the round, for everybody. Hacking leaves
-- the door intact: it swings open, auto-closes behind whoever went through, and
-- the keypad drops back to ERROR, so the room is only ever open to the Hacker
-- who is standing there.
--
-- ExitPrompt controls the room-side release plate, and is OFF unless a door
-- asks for it. The plate is deliberately one-way: it only answers a player who
-- is already standing on the room side of the closed leaf, so it is a way out
-- and never a second way in. The keypad stays the only thing that opens a door
-- from the corridor. Two separate mechanisms carry that: the leaf and the wall
-- it hangs in hide the prompt from the corridor (RequiresLineOfSight), and
-- atExit refuses the corridor outright, on the server, which is the half that
-- actually counts.
--
-- Consequence worth knowing before leaving it off on a new door: a Normal door
-- with no exit prompt has no interior control at all, and it auto-closes
-- AUTO_CLOSE_AFTER seconds after a grant. Whoever walked in is shut in until
-- somebody outside punches the code again. That is intended for most of the
-- rooms here; give a door ExitPrompt = true if it should not behave that way.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ClassConfig = require(ReplicatedStorage:WaitForChild("ClassDefinitions"))
-- Only for the two vault relic attribute names; doors know nothing else about
-- the clue hunt.
local ClueConfig = require(ReplicatedStorage:WaitForChild("ClueConfig"))
local OnboardingConfig = require(ReplicatedStorage:WaitForChild("OnboardingConfig"))

local TAG = "HotelDoor"
local DEFAULT_CODE = "0000"
local MAX_INPUT = 8
local OPEN_ANGLE = 90 -- swings away from the corridor, into the room
-- Far enough to read as "this one is stuck open", tight enough that the gap is
-- still a gap rather than a doorway you could walk through.
local AJAR_ANGLE = 11
local SWING = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local AUTO_CLOSE_AFTER = 8

-- The room-side release plate.
--
-- The reach is short because the plate is something you walk up to. It is not
-- what makes the plate one-way, though, and it cannot be: the keypad hangs on
-- the corridor face of the same wall the plate is screwed to, about three and a
-- half studs away through the brick, so anyone at the keypad is already closer
-- to the plate than a guest crossing their own room. The side test below is the
-- part that separates them.
local EXIT_DISTANCE = 8
-- How far past the plane of the closed leaf a player has to have got before the
-- door counts as being behind them. A character pressed up against the door
-- sits roughly two studs off it from either side, so a stud splits the corridor
-- from the room with room to spare, while still letting somebody who has only
-- just stepped over the threshold get back out.
local EXIT_INSIDE_DEPTH = 1

local STATE_NORMAL = "Normal"
local STATE_JAMMED = "Jammed"
local STATE_BROKEN = "Broken"
local STATE_SMASHED = "Smashed"

-- Forcing a door: how long the prompt is held, how hard the leaf goes over, and
-- how far past 90 degrees it carries before it settles.
local SMASH_HOLD = 0.8
local SMASH_DISTANCE = 12
local SMASH_ANGLE = 106
local SMASH_SETTLE_ANGLE = 97
local SMASH_SWING = TweenInfo.new(0.26, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local SMASH_SETTLE = TweenInfo.new(0.9, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)

--[[
	Bypassing a door: what the panel walks through while it is being worked on.

	The trace is paced to fill ClassConfig.HACK_HOLD exactly, so it doubles as
	the progress bar for the hold — the player reads how far along they are off
	the panel rather than off the prompt's own ring, which is behind them at that
	range. Deriving the step from the hold rather than hard-coding it means
	retuning the hold cannot silently leave the trace finishing early and the
	panel sitting on ROOT for a second while nothing happens.
]]
local HACK_TRACE = { "BYPASS", "..LINK", "0x1F", "..SYS", "0x7C", "..MEM", "0xA3", "..ACL", "0xD9", "ROOT" }
local HACK_STEP = ClassConfig.HACK_HOLD / #HACK_TRACE

local LED_LOCKED = Color3.fromRGB(255, 60, 60)
local LED_OPEN = Color3.fromRGB(90, 255, 120)
local LED_DEAD = Color3.fromRGB(28, 8, 8) -- nothing lit behind it any more
local TEXT_IDLE = Color3.fromRGB(120, 255, 160)
local TEXT_BAD = Color3.fromRGB(255, 110, 100)
local TEXT_ERROR = Color3.fromRGB(255, 78, 64)
-- The panel talking to somebody who is not supposed to be talking to it.
local TEXT_HACK = Color3.fromRGB(120, 255, 235)
local LED_HACK = Color3.fromRGB(80, 240, 220)

-- Engraved-brass plate: dark lettering when the release behind it still works,
-- washed out when it does not.
local PLATE_LIVE = Color3.fromRGB(60, 40, 12)
local PLATE_DEAD = Color3.fromRGB(104, 92, 74)

-- Everything a bypass has to put back on the player it pinned. Captured rather
-- than assumed: the speed someone walks at here comes out of their hunger, so
-- there is no constant to restore them to.
type Frozen = {
	humanoid: Humanoid,
	root: BasePart,
	walkSpeed: number,
	jumpPower: number,
	jumpHeight: number,
	autoRotate: boolean,
	anchored: boolean,
}

type Door = {
	model: Model,
	state: string,
	hinge: BasePart,
	closedCF: CFrame,
	display: TextLabel?,
	led: BasePart?,
	input: string,
	isOpen: boolean,
	busy: boolean,
	session: number,
	smashPrompt: ProximityPrompt?,
	hackPrompt: ProximityPrompt?,
	-- Set once a Hacker has talked this door's lock into opening. The state
	-- stays Broken — the keypad is still broken, and still refuses everyone —
	-- but the leaf itself is now allowed to move, which is what lets the normal
	-- open/auto-close path run on a door that otherwise has no working
	-- mechanism at all.
	bypassed: boolean,
	hacking: boolean,
	-- Who is holding E on this panel right now, and what they were before they
	-- started. Held on the door rather than per-player because the door is what
	-- has to let go of them if anything interrupts it.
	hackPlayer: Player?,
	hackFrozen: Frozen?,
	hackStartedAt: number,
	hackDied: RBXScriptConnection?,
}

local doors: { [Model]: Door } = {}
local connections: { [Model]: { RBXScriptConnection } } = {}

-- Captured the first time a door is seen and kept across teardowns. A jammed
-- door is parked ajar, so re-reading the hinge on a later setup would mistake
-- that ajar pose for the closed one and the leaf would creep a little further
-- open every time the door's State changed.
local closedFrames: { [Model]: CFrame } = {}

local teardown: (inst: Instance) -> ()

local function setDisplay(door: Door, text: string, colour: Color3)
	local label = door.display
	if label then
		label.Text = text
		label.TextColor3 = colour
	end
end

local function setLed(door: Door, colour: Color3)
	if door.led then
		door.led.Color = colour
	end
end

--[[
	What the panel says when nothing is happening to it.

	A broken keypad that a Hacker got through is still a broken keypad, so it
	drops back to ERROR rather than to the prompt a working one shows. Getting
	this wrong is what would make a bypassed door look repaired.
]]
local function idle(door: Door)
	if door.state == STATE_BROKEN then
		setDisplay(door, "ERROR", TEXT_ERROR)
	else
		setDisplay(door, "ENTER CODE", TEXT_IDLE)
	end
end

-- Likewise the status light: a dead panel goes back to dead, not to locked.
local function restLed(door: Door)
	setLed(door, if door.state == STATE_NORMAL then LED_LOCKED else LED_DEAD)
end

local function setOpen(door: Door, open: boolean)
	-- A jammed or broken door has no working mechanism left. Guarding here
	-- rather than at each caller means nothing added later can open one by
	-- accident. A bypassed door is the one exception: a Hacker has taken the
	-- lock out of the equation, so the leaf is free to move even though the
	-- keypad in front of it is still dead.
	if door.state ~= STATE_NORMAL and not door.bypassed then
		return
	end
	if door.isOpen == open or door.busy then
		return
	end
	door.busy = true
	door.isOpen = open

	local goal = if open then door.closedCF * CFrame.Angles(0, math.rad(OPEN_ANGLE), 0) else door.closedCF
	TweenService:Create(door.hinge, SWING, { CFrame = goal }):Play()
	if open then
		setLed(door, if door.bypassed then LED_HACK else LED_OPEN)
	else
		restLed(door)
	end

	task.delay(SWING.Time, function()
		door.busy = false
	end)
end

local function closeLater(door: Door)
	door.session += 1
	local mySession = door.session
	task.delay(AUTO_CLOSE_AFTER, function()
		if door.session == mySession and door.isOpen then
			setOpen(door, false)
			idle(door)
		end
	end)
end

local function grant(door: Door)
	setDisplay(door, "GRANTED", TEXT_IDLE)
	setOpen(door, true)
	closeLater(door)
end

local function deny(door: Door)
	setDisplay(door, "DENIED", TEXT_BAD)
	door.input = ""
	local mySession = door.session
	task.delay(1.2, function()
		if door.session == mySession and not door.isOpen then
			setDisplay(door, "ENTER CODE", TEXT_IDLE)
		end
	end)
end

--[[
	A broken keypad still answers a press — the display blinks and settles back
	on ERROR — it just never gets anywhere. A panel that did nothing at all
	would read as the game having failed rather than the door being dead, and
	the player would keep pushing buttons waiting for it to wake up.
]]
local function refuse(door: Door)
	door.session += 1
	local mySession = door.session
	setDisplay(door, "", TEXT_ERROR)
	task.delay(0.09, function()
		if door.session == mySession then
			setDisplay(door, "ERROR", TEXT_ERROR)
		end
	end)
end

--[[
	Pinning the hacker where they stand.

	Anchoring the root is the part that actually holds them; everything else here
	is belt and braces. SurvivalService owns Humanoid.WalkSpeed and rewrites it
	from hunger and stamina whenever its own computed value moves, so a freeze
	built on WalkSpeed alone would come undone partway through a five-second hold
	with nothing to show for it — hunger drains the whole time, and the write
	lands the moment the derived speed shifts by more than a hundredth. An
	anchored root does not care who writes what.
	FurnitureInteractionService anchors for the same reason.

	The saved values are restored rather than assumed, because the speed a player
	walks at here is not a constant — it comes out of their hunger.
]]
local function freeze(player: Player): Frozen?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not humanoid:IsA("Humanoid") or not root or not root:IsA("BasePart") then
		return nil
	end
	if humanoid.Health <= 0 then
		return nil
	end

	--[[
		The Master Cipher buys the Hacker out of the anchor.

		Standing still, facing a wall, at speed zero is the entire price of the
		bypass -- the comment further down notes those five seconds are "precisely
		when Joel catches people". The vault relic pays that price off: the trace
		still takes HACK_HOLD to run, so the door is no faster to open, but the
		player keeps their feet and can watch the corridor while it does.

		Returning a Frozen with the current values means releaseHack restores
		exactly what it found and every unwind path keeps working unchanged.
	]]
	if player:GetAttribute(ClueConfig.HackerRelicAttribute) == true then
		return {
			humanoid = humanoid,
			root = root,
			walkSpeed = humanoid.WalkSpeed,
			jumpPower = humanoid.JumpPower,
			jumpHeight = humanoid.JumpHeight,
			autoRotate = humanoid.AutoRotate,
			anchored = root.Anchored,
		}
	end

	local frozen: Frozen = {
		humanoid = humanoid,
		root = root,
		walkSpeed = humanoid.WalkSpeed,
		jumpPower = humanoid.JumpPower,
		jumpHeight = humanoid.JumpHeight,
		autoRotate = humanoid.AutoRotate,
		anchored = root.Anchored,
	}

	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	-- Left facing the panel they are working on, which is also what puts their
	-- back to the corridor.
	humanoid.AutoRotate = false
	root.Anchored = true
	return frozen
end

--[[
	Always safe to call twice, and safe to call on a character that has since
	died or respawned — the parent checks are what make dying mid-hack land the
	player back on their feet rather than anchored to the spot they died on.
]]
local function thaw(frozen: Frozen?)
	if not frozen then
		return
	end
	if not frozen.humanoid.Parent or not frozen.root.Parent then
		return
	end
	frozen.root.Anchored = frozen.anchored
	frozen.humanoid.WalkSpeed = frozen.walkSpeed
	frozen.humanoid.JumpPower = frozen.jumpPower
	frozen.humanoid.JumpHeight = frozen.jumpHeight
	frozen.humanoid.AutoRotate = frozen.autoRotate
end

--[[
	Talking a dead lock open.

	The five seconds are the prompt's own hold, not a delay bolted on after it,
	so releasing E gives the time back and abandons the attempt. That is the
	whole cost of the class: for the length of the hold the Hacker is anchored,
	facing a wall, at walking speed zero, with their back to whatever is coming
	down the corridor.

	`bypassed` is set before the leaf is asked to move, because setOpen refuses a
	Broken door that has not been bypassed. Once set it stays set — but the state
	stays Broken too, so the keypad goes on refusing everybody and getting back
	in means holding E again. Nobody inherits this door by walking past it later.
]]
--[[
	Lets go of the player, however the attempt ended.

	Every exit from a bypass runs through here — finished, abandoned, died,
	door re-read underneath it. Keeping it in one place is deliberate: the
	failure this guards against is a player left anchored to a corridor with
	nothing holding the other end, and that is exactly the bug that appears when
	one of several unwind paths forgets a line.

	Idempotent, so the watchdog and the real ending can both call it.
]]
local function releaseHack(door: Door)
	if not door.hacking then
		return
	end
	door.hacking = false
	thaw(door.hackFrozen)
	if door.hackDied then
		door.hackDied:Disconnect()
		door.hackDied = nil
	end
	door.hackFrozen = nil
	door.hackPlayer = nil
end

local function abortHack(door: Door, message: string?)
	if not door.hacking then
		return
	end
	releaseHack(door)

	door.session += 1
	local mySession = door.session
	if message then
		setDisplay(door, message, TEXT_BAD)
	end
	restLed(door)
	task.delay(0.9, function()
		if door.session == mySession and not door.isOpen then
			idle(door)
		end
	end)
end

local function beginHack(door: Door, player: Player)
	-- Already open, or somebody is already on it. Two players holding E on the
	-- same panel must not both get a freeze and a trace.
	if door.hacking or door.isOpen or door.busy then
		return
	end

	local frozen = freeze(player)
	if not frozen then
		return
	end

	door.hacking = true
	door.hackPlayer = player
	door.hackFrozen = frozen
	door.hackStartedAt = os.clock()

	--[[
		Dying mid-hold is not an edge case here, it is the point of the class —
		five seconds anchored with your back to the corridor is precisely when
		Joel catches people. So it is handled directly rather than left to the
		watchdog below: the panel drops back to ERROR as the player goes down.
	]]
	door.hackDied = frozen.humanoid.Died:Connect(function()
		if door.hackPlayer == player then
			abortHack(door)
		end
	end)

	door.session += 1
	local mySession = door.session

	task.spawn(function()
		for _, line in ipairs(HACK_TRACE) do
			-- Anything else that touches this door bumps the session, which is
			-- the signal to abandon the trace rather than keep writing over
			-- whatever took it over.
			if door.session ~= mySession or not door.hacking then
				return
			end
			setDisplay(door, line, TEXT_HACK)
			setLed(door, LED_HACK)
			task.wait(HACK_STEP)
		end
	end)

	--[[
		Backstop for the ways a hold can stop without the prompt ever saying so:
		the player disconnects, or their character is rebuilt underneath them.
		Either leaves `hacking` set, and a door stuck mid-bypass can never be
		hacked again. Set past the point a legitimate hold would have finished,
		so it cannot race one.
	]]
	task.delay(ClassConfig.HACK_HOLD + 2, function()
		if door.hacking and door.session == mySession then
			abortHack(door)
		end
	end)
end

--[[
	The hold ran its full length. Trusting the prompt on the timing is fine —
	it is the class and the reach that matter, and both are re-checked on the
	server at the call site.
]]
local function finishHack(door: Door)
	if not door.hacking then
		return
	end
	releaseHack(door)

	door.session += 1
	door.bypassed = true
	setDisplay(door, "GRANTED", TEXT_HACK)
	setOpen(door, true)
	closeLater(door)
end

local function press(door: Door, key: string, player: Player)
	if key == "C" then
		door.input = ""
		setDisplay(door, "ENTER CODE", TEXT_IDLE)
		return
	end

	if key == "E" then
		local code = door.model:GetAttribute("Code")
		local expected = if type(code) == "string" then code else DEFAULT_CODE
		if door.input == expected then
			door.input = ""
			grant(door)
			if
				door.model.Name == OnboardingConfig.ROOM_DOOR_NAME
				and player:GetAttribute(OnboardingConfig.ATTRIBUTE) == OnboardingConfig.ENTER_ROOM
			then
				player:SetAttribute(OnboardingConfig.ATTRIBUTE, OnboardingConfig.COMPLETE)
			end
		else
			deny(door)
		end
		return
	end

	if #door.input >= MAX_INPUT then
		door.input = ""
	end
	door.input ..= key
	setDisplay(door, string.rep("*", #door.input), TEXT_IDLE)
end

--[[
	Splits the leaf where the lock was and drops a little of it on the floor.

	The cracks are welded to the leaf rather than anchored in place: the door is
	about to swing, and damage that stayed behind in the doorway would give the
	whole thing away. The splinters are deliberately NOT welded — they are the
	part that comes off, and letting them fall costs nothing.
]]
local function crack(door: Door)
	local leaf = door.model:FindFirstChild("Leaf")
	local core = leaf and leaf:FindFirstChild("Core")
	if not leaf or not core or not core:IsA("BasePart") then
		return
	end

	local damage = Instance.new("Model")
	damage.Name = "Smashed"
	damage.Parent = leaf

	local dark = Color3.fromRGB(24, 18, 13)
	local raw = Color3.fromRGB(120, 92, 60)
	local face = core.Size.Z / 2 + 0.012

	-- Radiating out from the lock on the handle edge, on both faces so the
	-- break reads from inside the room as well as from the corridor.
	local seams: { { size: Vector3, at: CFrame } } = {
		{ size = Vector3.new(1.95, 0.10, 0.02), at = CFrame.new(1.20, 0.20, 0) * CFrame.Angles(0, 0, math.rad(-26)) },
		{ size = Vector3.new(1.30, 0.075, 0.02), at = CFrame.new(1.70, -0.80, 0) * CFrame.Angles(0, 0, math.rad(35)) },
		{ size = Vector3.new(0.95, 0.06, 0.02), at = CFrame.new(0.80, 1.05, 0) * CFrame.Angles(0, 0, math.rad(13)) },
		{ size = Vector3.new(0.72, 0.05, 0.02), at = CFrame.new(1.95, 0.62, 0) * CFrame.Angles(0, 0, math.rad(-59)) },
	}
	for side = -1, 1, 2 do
		for i, seam in ipairs(seams) do
			local p = Instance.new("Part")
			p.Name = `Seam{i}{if side < 0 then "B" else "A"}`
			p.Size = seam.size
			p.CFrame = core.CFrame * seam.at * CFrame.new(0, 0, face * side)
			p.Anchored = false
			p.CanCollide = false
			p.CanQuery = false
			p.Massless = true
			p.Color = dark
			p.Material = Enum.Material.Wood
			p.Parent = damage

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = core
			weld.Part1 = p
			weld.Parent = p
		end
	end

	for i = 1, 3 do
		local chip = Instance.new("Part")
		chip.Name = `Splinter{i}`
		chip.Size = Vector3.new(0.55 - i * 0.1, 0.09, 0.22)
		chip.CFrame = core.CFrame
			* CFrame.new(1.4 + i * 0.25, 0.5 - i * 0.6, face * 1.6)
			* CFrame.Angles(math.rad(i * 24), math.rad(i * 17), math.rad(i * 40))
		chip.Color = raw
		chip.Material = Enum.Material.Wood
		chip.CanCollide = true
		chip.Parent = damage
	end
end

--[[
	Whatever was holding a jammed door shut stops holding it. Unanchoring is
	enough — the leaf is already on its way through, and the brace falls the way
	it was leaning.
]]
local function releaseJam(door: Door)
	local jam = door.model:FindFirstChild("Jam")
	if not jam then
		return
	end
	for _, name in ipairs({ "Brace", "Chock" }) do
		local piece = jam:FindFirstChild(name)
		if piece and piece:IsA("BasePart") then
			piece.Anchored = false
			piece.CanCollide = true
		end
	end
end

local function smash(door: Door)
	if door.state == STATE_SMASHED then
		return
	end

	-- Taken before the state changes, because a jammed leaf is resting ajar and
	-- the impact has to shudder around where it actually is.
	local rest = door.hinge.CFrame

	door.session += 1
	door.state = STATE_SMASHED
	door.isOpen = true
	door.busy = true
	door.model:SetAttribute("State", STATE_SMASHED)

	local prompt = door.smashPrompt
	if prompt then
		prompt:Destroy()
		door.smashPrompt = nil
	end

	setLed(door, LED_DEAD)
	setDisplay(door, "", TEXT_ERROR)
	crack(door)
	releaseJam(door)

	task.spawn(function()
		-- Two shoulders before the frame lets go, then it goes over hard and
		-- swings back to hang open.
		for _ = 1, 2 do
			door.hinge.CFrame = rest * CFrame.Angles(0, math.rad(3.2), 0)
			task.wait(0.05)
			door.hinge.CFrame = rest
			task.wait(0.06)
		end

		TweenService:Create(door.hinge, SMASH_SWING, {
			CFrame = door.closedCF * CFrame.Angles(0, math.rad(SMASH_ANGLE), 0),
		}):Play()
		task.wait(SMASH_SWING.Time)
		TweenService:Create(door.hinge, SMASH_SETTLE, {
			CFrame = door.closedCF * CFrame.Angles(0, math.rad(SMASH_SETTLE_ANGLE), 0),
		}):Play()
		door.busy = false
	end)
end

--[[
	Which way "into the room" points for this door.

	Worked out from the door's own parts rather than carried as an attribute: the
	release plate is by definition on the room side, so whichever side of the
	closed leaf it sits on is the inside. A door that gets moved, rotated, or
	re-hung the other way round in Studio keeps a correct exit gate with nothing
	to remember to update by hand.

	Measured against closedCF rather than the leaf's live pose because the leaf
	swings: once the door is open its own frame says nothing about where the
	doorway is.

	nil when the plate is sitting in the plane of the leaf itself. That is a
	build mistake rather than a state, and it is the one case where guessing is
	worse than doing nothing — a plate that cannot tell the corridor from the
	room is exactly the free way in this whole mechanism exists to deny.
]]
local function insideDirection(door: Door, exit: BasePart): Vector3?
	local axis = door.closedCF.LookVector
	local reach = (exit.Position - door.closedCF.Position):Dot(axis)
	if math.abs(reach) < 0.25 then
		return nil
	end
	return if reach > 0 then axis else -axis
end

--[[
	Is this player in the room, within reach of the plate?

	Both halves are re-measured here on the server for the same reason the smash
	and bypass prompts re-measure theirs: MaxActivationDistance is enforced by
	the client that owns the prompt, and RequiresLineOfSight only decides whether
	the thing draws. Neither is load-bearing. This is — it is the only reason the
	plate is not a keypad-free way into the room.
]]
local function atExit(door: Door, exit: BasePart, inside: Vector3, player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	if (root.Position - exit.Position).Magnitude > EXIT_DISTANCE + 6 then
		return false
	end
	return (root.Position - door.closedCF.Position):Dot(inside) >= EXIT_INSIDE_DEPTH
end

local function stateOf(inst: Instance): string
	local raw = inst:GetAttribute("State")
	if raw == STATE_JAMMED or raw == STATE_BROKEN or raw == STATE_SMASHED then
		return raw :: string
	end
	return STATE_NORMAL
end

local function setup(inst: Instance)
	if not inst:IsA("Model") or doors[inst] then
		return
	end

	local leaf = inst:FindFirstChild("Leaf")
	local hinge = leaf and leaf:FindFirstChild("Hinge")
	if not hinge or not hinge:IsA("BasePart") then
		return
	end

	local keypad = inst:FindFirstChild("Keypad")
	local displayPart = keypad and keypad:FindFirstChild("Display")
	local ledPart = keypad and keypad:FindFirstChild("LED")

	local closedCF = closedFrames[inst]
	if not closedCF then
		closedCF = hinge.CFrame
		closedFrames[inst] = closedCF
	end

	local door: Door = {
		model = inst,
		state = stateOf(inst),
		hinge = hinge,
		closedCF = closedCF,
		display = if displayPart then displayPart:FindFirstChild("Text", true) :: TextLabel? else nil,
		led = if ledPart and ledPart:IsA("BasePart") then ledPart else nil,
		input = "",
		isOpen = false,
		busy = false,
		session = 0,
		bypassed = false,
		hacking = false,
		hackStartedAt = 0,
	}
	doors[inst] = door

	local conns: { RBXScriptConnection } = {}

	-- A jammed door's keypad has been torn off the wall, so there is normally
	-- nothing here to wire. The state check covers the case where one is left
	-- in place while a build is in progress.
	local buttons = keypad and keypad:FindFirstChild("Buttons")
	if buttons and door.state ~= STATE_JAMMED then
		for _, button in buttons:GetChildren() do
			local detector = button:FindFirstChildOfClass("ClickDetector")
			local key = string.sub(button.Name, 2)
			if detector and key ~= "" then
				table.insert(
					conns,
					detector.MouseClick:Connect(function(player: Player)
						-- A bypass in progress owns the panel. Without this,
						-- anyone poking a button mid-hold bumps the session and
						-- kills the trace out from under the player holding E.
						if door.hacking then
							return
						end
						if door.state == STATE_BROKEN then
							refuse(door)
						else
							press(door, key, player)
						end
					end)
				)
			end
		end
	end

	local exit = inst:FindFirstChild("ExitButton")
	if exit and exit:IsA("BasePart") then
		local existing = exit:FindFirstChildOfClass("ProximityPrompt")
		local asked = inst:GetAttribute("ExitPrompt") == true
		local inside = insideDirection(door, exit)
		local wantsPrompt = asked and door.state == STATE_NORMAL and inside ~= nil

		if asked and not inside then
			warn(
				`[HotelDoorService] {inst:GetFullName()}: ExitButton sits in the plane of the leaf, `
					.. `so there is no room side to check a player against. Exit prompt withheld — `
					.. `move the plate onto the room face of the wall.`
			)
		end

		-- The plate is a physical sign screwed to the wall. It should not go on
		-- promising a way out once the release behind it is gone — being shut in
		-- is meant to land as "this one is dead", not as a missing prompt.
		local plate = exit:FindFirstChild("Text", true)
		if plate and plate:IsA("TextLabel") then
			plate.Text = if wantsPrompt then "EXIT" else "OUT OF SERVICE"
			plate.TextColor3 = if wantsPrompt then PLATE_LIVE else PLATE_DEAD
		end

		if wantsPrompt and inside then
			local roomSide: Vector3 = inside
			local prompt: ProximityPrompt
			if existing then
				prompt = existing
			else
				prompt = Instance.new("ProximityPrompt")
			end
			--[[
				Applied on both paths, not just to a freshly created prompt. A
				prompt saved into the place by hand would otherwise keep whatever
				reach and sight rule it was built with, and these two are the
				difference between a plate you find by being in the room and one
				that advertises itself down the corridor.

				Line of sight is what does the hiding: with the leaf shut, the
				wall the plate is mounted on is between it and anyone outside, so
				the prompt simply does not draw for them. Cosmetic — atExit is
				what refuses them — but it keeps the door from looking as though
				holding E out there might work.
			]]
			prompt.ActionText = "Exit"
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = EXIT_DISTANCE
			prompt.RequiresLineOfSight = true
			local label = inst:GetAttribute("RoomLabel")
			prompt.ObjectText = if type(label) == "string" then label else "Door"
			prompt.Parent = exit
			table.insert(
				conns,
				prompt.Triggered:Connect(function(player)
					-- The plate releases the door for whoever is behind it. It
					-- never opens one for the corridor, however the trigger got
					-- here — a spoofed fire, a prompt someone enabled for
					-- themselves, or standing in an open doorway looking in.
					if not atExit(door, exit, roomSide, player) then
						return
					end
					if door.isOpen then
						setOpen(door, false)
					else
						setOpen(door, true)
						closeLater(door)
					end
				end)
			)
		elseif existing then
			-- Covers a prompt saved into the place by hand as well as one this
			-- script created before the door's State changed under it.
			existing:Destroy()
		end
	end

	--[[
		The forcing prompt.

		Created disabled and tagged; ClassClient switches it on locally for
		Muscle players, because a ProximityPrompt is on or off for the whole
		server and there is no per-player version of it. That is cosmetic —
		anyone who enables one for themselves still has to get past the class
		check below, which runs here on the server.
	]]
	--[[
		Built on every intact door, not only the ones Muscle can currently force.

		A ProximityPrompt is created once at setup, but the Ironhand is claimed
		from the vault much later, so gating creation on SmashableStates meant a
		Normal door had no prompt to enable when the relic finally arrived. The
		prompt now exists on anything not already smashed and stays disabled; the
		class check and the state check below still decide whether it does
		anything, and ClassClient still only shows it to Muscle.
	]]
	local leafCore = leaf and leaf:FindFirstChild("Core")
	if door.state ~= STATE_SMASHED and leafCore and leafCore:IsA("BasePart") then
		local smashPrompt = Instance.new("ProximityPrompt")
		smashPrompt.Name = "SmashPrompt"
		smashPrompt.ActionText = "Smash open"
		local label = inst:GetAttribute("RoomLabel")
		smashPrompt.ObjectText = if type(label) == "string" then label else "Door"
		smashPrompt.HoldDuration = SMASH_HOLD
		smashPrompt.MaxActivationDistance = SMASH_DISTANCE
		smashPrompt.RequiresLineOfSight = false
		smashPrompt.Enabled = false
		smashPrompt.Parent = leafCore
		CollectionService:AddTag(smashPrompt, ClassConfig.SMASH_PROMPT_TAG)
		door.smashPrompt = smashPrompt

		table.insert(
			conns,
			smashPrompt.Triggered:Connect(function(player)
				if not ClassConfig.hasClass(player, ClassConfig.MUSCLE) then
					return
				end
				--[[
					Re-check the live state here as well as at prompt creation. A
					delayed/stale prompt must never turn Muscle into a key for a
					normal locked room.

					The Ironhand is the one thing that does turn them into exactly
					that, and it is meant to: it is claimed from an open vault,
					which means the code hunt is already finished and the doors it
					protected no longer have anything to protect. Smashed is still
					excluded, because a door hanging off its hinges cannot be
					smashed twice.
				]]
				local ironhand = player:GetAttribute(ClueConfig.MuscleRelicAttribute) == true
				if not ClassConfig.SmashableStates[door.state] and not (ironhand and door.state ~= STATE_SMASHED) then
					return
				end
				-- The prompt's own range is enforced on the client that owns it,
				-- so the reach is re-measured here before anything gives way.
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if not root or not root:IsA("BasePart") then
					return
				end
				if (root.Position - leafCore.Position).Magnitude > SMASH_DISTANCE + 6 then
					return
				end
				smash(door)
			end)
		)
	end

	--[[
		The bypass prompt.

		Same disabled-and-tagged trick as the forcing prompt, and the same
		caveat: ClassClient turning one on is presentation, and the class is
		re-checked on the server both when the hold starts and when it completes.

		Hosted on the keypad rather than on the leaf. That is the whole fiction
		of the class — a Hacker beats the panel, not the door — and it also puts
		the trace they are reading directly in front of them while they are
		pinned in place.
	]]
	if ClassConfig.HackableStates[door.state] and displayPart and displayPart:IsA("BasePart") then
		local hackPrompt = Instance.new("ProximityPrompt")
		hackPrompt.Name = "HackPrompt"
		hackPrompt.ActionText = "Hack"
		local label = inst:GetAttribute("RoomLabel")
		hackPrompt.ObjectText = if type(label) == "string" then label else "Keypad"
		hackPrompt.HoldDuration = ClassConfig.HACK_HOLD
		hackPrompt.MaxActivationDistance = ClassConfig.HACK_DISTANCE
		hackPrompt.RequiresLineOfSight = false
		hackPrompt.Enabled = false
		hackPrompt.Parent = displayPart
		CollectionService:AddTag(hackPrompt, ClassConfig.HACK_PROMPT_TAG)
		door.hackPrompt = hackPrompt

		local function allowed(player: Player): boolean
			if not ClassConfig.hasClass(player, ClassConfig.HACKER) then
				return false
			end
			-- The prompt's own range is enforced on the client that owns it, so
			-- the reach is re-measured here.
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not root or not root:IsA("BasePart") then
				return false
			end
			return (root.Position - displayPart.Position).Magnitude <= ClassConfig.HACK_DISTANCE + 6
		end

		table.insert(
			conns,
			hackPrompt.PromptButtonHoldBegan:Connect(function(player)
				if allowed(player) then
					beginHack(door, player)
				end
			end)
		)

		--[[
			Fires when the key comes up — which includes the hold that ran its
			course, not just the one that was given up on. Whether Triggered
			lands before or after this is not something to bet the class on, so
			the two cases are told apart by the clock instead: a hold that got
			within a fraction of the full duration is a finished bypass, and
			finishHack either has already run or is about to.
		]]
		table.insert(
			conns,
			hackPrompt.PromptButtonHoldEnded:Connect(function(player)
				if not door.hacking or door.hackPlayer ~= player then
					return
				end
				if os.clock() - door.hackStartedAt >= ClassConfig.HACK_HOLD - 0.25 then
					return
				end
				abortHack(door, "ABORTED")
			end)
		)

		table.insert(
			conns,
			hackPrompt.Triggered:Connect(function(player)
				if door.hackPlayer ~= player or not allowed(player) then
					return
				end
				finishHack(door)
			end)
		)
	end

	-- Re-read the door when it is re-flagged in Studio, so States can be tried
	-- without restarting the place.
	table.insert(
		conns,
		inst:GetAttributeChangedSignal("State"):Connect(function()
			teardown(inst)
			setup(inst)
		end)
	)

	connections[inst] = conns

	if door.state == STATE_SMASHED then
		-- Already forced, and it stays that way: a door that was re-set up
		-- (a State edit, a re-tag) must not quietly swing itself shut again.
		hinge.CFrame = closedCF * CFrame.Angles(0, math.rad(SMASH_SETTLE_ANGLE), 0)
		door.isOpen = true
		setLed(door, LED_DEAD)
		setDisplay(door, "", TEXT_ERROR)
	elseif door.state == STATE_JAMMED then
		-- Parked here rather than saved into the place because the leaf is
		-- welded to the hinge with WeldConstraints, which only pull at run
		-- time: posing the hinge in Studio would leave the door behind it.
		hinge.CFrame = closedCF * CFrame.Angles(0, math.rad(AJAR_ANGLE), 0)
		setLed(door, LED_DEAD)
	elseif door.state == STATE_BROKEN then
		hinge.CFrame = closedCF
		setLed(door, LED_DEAD)
		setDisplay(door, "ERROR", TEXT_ERROR)
	else
		hinge.CFrame = closedCF
		setLed(door, LED_LOCKED)
		setDisplay(door, "ENTER CODE", TEXT_IDLE)
	end
end

function teardown(inst: Instance)
	if not inst:IsA("Model") then
		return
	end

	-- Whoever was mid-bypass gets their legs back. A door being re-read (a State
	-- edit in Studio, a re-tag) must never be able to leave a player anchored to
	-- the corridor with nothing left holding the other end.
	local existing = doors[inst]
	if existing then
		releaseHack(existing)
		if existing.smashPrompt then
			existing.smashPrompt:Destroy()
			existing.smashPrompt = nil
		end
		if existing.hackPrompt then
			existing.hackPrompt:Destroy()
			existing.hackPrompt = nil
		end
	end

	local conns = connections[inst]
	if conns then
		for _, c in conns do
			c:Disconnect()
		end
		connections[inst] = nil
	end
	doors[inst] = nil
end

for _, inst in CollectionService:GetTagged(TAG) do
	setup(inst)
end
CollectionService:GetInstanceAddedSignal(TAG):Connect(setup)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(teardown)
