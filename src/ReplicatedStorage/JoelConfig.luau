--!strict
-- All tuning shared by Joel's server brain and its tests.

local SurvivalConfig = require(script.Parent.SurvivalConfig)
local RescueConfig = require(script.Parent.RescueConfig)
local HorrorZones = require(script.Parent.HorrorZones)

local JoelConfig = {}

-- Locomotion -----------------------------------------------------------------

JoelConfig.ProwlSpeed = math.max(8, SurvivalConfig.BaseWalkSpeed * 0.7)
JoelConfig.InvestigateSpeed = SurvivalConfig.BaseWalkSpeed + 1
JoelConfig.SearchSpeed = SurvivalConfig.BaseWalkSpeed

-- During a chase Joel reads the victim's live WalkSpeed. This keeps him
-- threatening when hunger, sprinting, or another system changes player speed.
JoelConfig.SpeedAdvantage = 3
JoelConfig.SprintPeriod = 5
JoelConfig.SprintDuration = 2.6
JoelConfig.SprintBonus = 5

-- WalkSpeed is eased toward the requested speed instead of snapping. Starting
-- from a prowl, Joel takes roughly two seconds to reach a full player sprint.
JoelConfig.ChaseAcceleration = 10
JoelConfig.ChaseDeceleration = 16

-- Combat ---------------------------------------------------------------------

-- A four-stud sphere around Joel's root is sampled every server heartbeat.
JoelConfig.CatchRadius = 4
JoelConfig.CatchRequiresLineOfSight = true
JoelConfig.ContactDamageEnabled = true

--[[
	A closet is real cover, not decoration.

	FurnitureInteractionService already teleports you inside a wardrobe and flags
	you with this attribute, but nothing on Joel's side ever read it, so closets
	only worked by accident: the geometry happened to block his sight ray while
	his hearing — which passes through walls at 34 studs, 62 if you sprinted in —
	found you anyway. Hiding from him in the one piece of furniture built for
	hiding was therefore close to useless.

	Reading it here makes the closet the one guaranteed safe place in the hotel.
	That is deliberate: with the rescue system in play a catch now costs a
	teammate a trip across the map, so somewhere to break a chase has to exist.
	The cost is that you are stationary, blind and making no progress on the
	clue hunt while the hunger clock keeps running.

	The attribute is written as a bare string in FurnitureInteractionService and
	FurnitureHideClient; this is the only reader, so the name is pinned here
	rather than in a new shared config.
]]
JoelConfig.HidingAttribute = "HidingInCloset"

-- Catching no longer kills outright. The first strike is a slow, upright drag
-- to a safe point chosen by RescueController; a later catch is permanent.
JoelConfig.RescueStateAttribute = RescueConfig.StateAttribute
JoelConfig.RescueHealthyState = RescueConfig.StateHealthy
JoelConfig.RescueDraggingState = RescueConfig.StateDragging
JoelConfig.DragSpeed = SurvivalConfig.BaseWalkSpeed
JoelConfig.DragArrivalRadius = 5
JoelConfig.DragTimeoutSeconds = 35
JoelConfig.DragPathFailureSeconds = 4
JoelConfig.DragDropStandHeight = 3

-- The Sunstone does not make Joel mortal. It interrupts the hunt for exactly
-- one escape window, long enough for a coordinated server to make the lobby
-- door without turning the climax into a permanent victory lap.
JoelConfig.DownedSeconds = 120
JoelConfig.DefeatRange = 24
JoelConfig.DefeatHoldSeconds = 3

-- Hunt cycle -----------------------------------------------------------------

--[[
	Joel hunts in windows rather than for the whole round.

	Unbroken pursuit left the round nowhere to breathe. The clue chain wants
	players crossing open corridors to read riddles and carry relics, and a
	hunter who never stands down turns every crossing into the same coin flip —
	so the sensible play was always to wait, which is the one thing a horror
	round cannot afford to reward. Cutting the hunt into a window followed by a
	shorter stand-down gives the round a pulse: a stretch where moving is
	suicide, then one where it is the only thing worth doing.

	It is also the first thing about Joel a player can actually read. Nothing
	else he does is legible from across the map, and the plaque at the top of
	the screen can only count this down because the cycle is a published clock
	rather than a mood.

	Five against one is deliberately lopsided, and the order matters: the hunt
	is the long window and the stand-down is the short one. Inverting them —
	five minutes of safety punctuated by a minute of danger — makes waiting the
	correct play again, which is the exact failure the cycle exists to remove.
	The stand-down is not half the round, it is the minute you plan around:
	bank the clue you are carrying, cross the corridor you have been staring
	at, get a teammate off the floor. Long enough to spend on one errand and
	nothing like long enough to finish the hunt in.

	The cycle does not run from server start. JoelService arms it when the first
	player leaves their first stay, because that is when the round actually
	begins; until then Joel is dormant and the plaque is off every screen.
]]
JoelConfig.HuntWindowSeconds = 300
JoelConfig.RestWindowSeconds = 60

JoelConfig.PhaseHunt = "Hunt"
JoelConfig.PhaseRest = "Rest"
JoelConfig.PhaseDowned = "Downed"

-- Two attributes on one folder, and every client derives its own seconds from
-- them. See JoelConfig.cycleAt below and RoundTimerClient.
JoelConfig.StateFolder = "JoelState"
JoelConfig.CyclePhaseAttribute = "HuntCyclePhase"
JoelConfig.CycleEndsAtAttribute = "HuntCycleEndsAt"

-- Perception and memory -------------------------------------------------------

JoelConfig.SightRange = 140
JoelConfig.NoticeRange = 34
JoelConfig.SprintNoticeRange = 62
JoelConfig.PerceptionInterval = 0.1
JoelConfig.LoseInterestSeconds = 12
JoelConfig.TargetSwitchMargin = 22

-- Hearing is deliberately intermittent and imprecise. Once a player turns a
-- corner Joel pursues their last seen position, then occasionally gets a rough
-- sound cue instead of reading their live position through the wall.
JoelConfig.HearingUpdateInterval = 0.9
JoelConfig.HearingPositionError = 5
JoelConfig.LostSightCommitSeconds = 0.3
JoelConfig.NoiseInvestigateWeight = 1

-- Interception ---------------------------------------------------------------

JoelConfig.MaxLeadSeconds = 0.8
JoelConfig.MinLeadSpeed = 4

-- Navigation -----------------------------------------------------------------

JoelConfig.RepathInterval = 0.4
JoelConfig.RepathTargetDrift = 8
JoelConfig.WaypointReached = 3.5
JoelConfig.MaxWaypointSkip = 5
JoelConfig.DirectChaseDistance = 10

--[[
	How far Joel will idly wander from where he was placed.

	Prowl used to pick a point 24-66 studs away in a random direction with no
	validation of any kind. Inside a corridor that reads as patrolling, because
	the walls do the containing. The moment he stepped through an exit it became
	a random walk across the Baseplate — which is 2048 studs square with its top
	surface at Y 17, the same height as the guest-room floor, so it is a
	perfectly walkable and effectively endless plane. Each new goal was measured
	from wherever he already stood, so there was no force pulling him back: a
	playtest found him at Z -276 and still going, ~150 studs beyond the south
	end of the hotel and permanently out of the game.

	Leashing to his spawn pivot rather than to a hard-coded box means the patrol
	area is set by dragging him in Studio, which is the knob that was already
	being used to move him around. 220 studs comfortably covers the whole guest
	wing (134 x 169) and the amenities floor stacked above it from a spawn
	anywhere inside them.

	This binds idle wandering ONLY. Chase, Investigate and Search all follow the
	player wherever they go, including through lifts and across floors — being
	led out of your patrol area by someone you are hunting is the point.
]]
JoelConfig.ProwlLeashRadius = 220

JoelConfig.SearchPointInterval = 1.1
JoelConfig.SearchRadiusMin = 7
JoelConfig.SearchRadiusMax = 20

JoelConfig.StuckWindow = 0.9
JoelConfig.StuckDistance = 2.25
JoelConfig.JumpProbeDistance = 4.5
JoelConfig.JumpProbeHeight = 2.2
JoelConfig.JumpCooldown = 0.45

-- Floor transitions ----------------------------------------------------------

JoelConfig.FloorSplitY = 33
-- There is deliberately no VaultSplitY beside these. The vault used to be a
-- sublevel and a Y split described it; now it stands at ground level in the same
-- band as the rooms and amenities floors, so nothing about it is a split at all.
-- HorrorZones.isInVault owns that question, and floorOf below asks it, so Joel's
-- floor classifier and the lighting that brightens the vault cannot disagree.
JoelConfig.SuiteSplitX = 450
JoelConfig.TeleportCooldown = 14
JoelConfig.TeleportMinTargetDistance = 60
JoelConfig.TeleportArriveMin = 38
JoelConfig.TeleportArriveMax = 68
JoelConfig.TeleportMaxObserverDistance = 190
JoelConfig.StartGraceSeconds = 5

-- Pure helpers ---------------------------------------------------------------

function JoelConfig.isSprinting(clock: number): boolean
	if JoelConfig.SprintPeriod <= 0 then
		return false
	end
	return (clock % JoelConfig.SprintPeriod) < JoelConfig.SprintDuration
end

function JoelConfig.speedFor(targetSpeed: number?, sprinting: boolean): number
	if not targetSpeed or targetSpeed <= 0 then
		return JoelConfig.ProwlSpeed
	end
	return targetSpeed + JoelConfig.SpeedAdvantage + (if sprinting then JoelConfig.SprintBonus else 0)
end

function JoelConfig.approachSpeed(current: number, goal: number, delta: number): number
	local rate = if goal > current then JoelConfig.ChaseAcceleration else JoelConfig.ChaseDeceleration
	local step = math.max(0, rate * delta)
	if current < goal then
		return math.min(current + step, goal)
	end
	return math.max(current - step, goal)
end

function JoelConfig.noticeRange(targetSprinting: boolean): number
	return if targetSprinting then JoelConfig.SprintNoticeRange else JoelConfig.NoticeRange
end

function JoelConfig.interceptPoint(
	joelPosition: Vector3,
	targetPosition: Vector3,
	targetVelocity: Vector3,
	joelSpeed: number
): Vector3
	local flatVelocity = Vector3.new(targetVelocity.X, 0, targetVelocity.Z)
	if flatVelocity.Magnitude < JoelConfig.MinLeadSpeed or joelSpeed <= 0 then
		return targetPosition
	end
	local distance = (targetPosition - joelPosition).Magnitude
	local leadTime = math.min(distance / joelSpeed, JoelConfig.MaxLeadSeconds)
	return targetPosition + flatVelocity * leadTime
end

--[[
	The one classifier here that is not pure: the vault's whereabouts live in the
	place, not in this file, so HorrorZones has to go and look. That is the price
	of the vault being draggable, and it is worth it — the alternative is a copy
	of its coordinates in here that silently rots the first time it moves.

	The vault is asked about BEFORE any band comparison, which used to be an
	accident of it being the deepest thing in the world and is now the load-
	bearing part of this function. At Y 19..52 and X 915..1005 the chamber is
	inside the amenities band and past SuiteSplitX, so every test below would
	happily claim it: ask them first and the vault comes back "Suite".
]]
function JoelConfig.floorOf(position: Vector3): string
	if HorrorZones.isInVault(position) then
		return "Vault"
	end
	if position.X < 100 then
		return "Lobby"
	end
	if position.X >= JoelConfig.SuiteSplitX then
		return "Suite"
	end
	return if position.Y >= JoelConfig.FloorSplitY then "Amenities" else "Rooms"
end

function JoelConfig.canTargetRescueState(rescueState: any): boolean
	return rescueState == JoelConfig.RescueHealthyState
end

-- Anything other than a literal `true` reads as "not in a closet", so a missing
-- or cleared attribute leaves the player huntable rather than accidentally safe.
function JoelConfig.canTargetHidingState(hiding: any): boolean
	return hiding ~= true
end

function JoelConfig.isSameFloorDrop(origin: Vector3, destination: Vector3): boolean
	-- RescueDropZone markers sit on the walking surface while HumanoidRootParts
	-- sit above it. Classify the stand position so an amenities marker at Y 32.7
	-- is not mistaken for the rooms floor below Joel.
	local standPosition = destination + Vector3.new(0, JoelConfig.DragDropStandHeight, 0)
	return JoelConfig.floorOf(origin) == JoelConfig.floorOf(standPosition)
end

function JoelConfig.hasReachedDragDrop(position: Vector3, destination: Vector3): boolean
	return (position - destination).Magnitude <= JoelConfig.DragArrivalRadius
end

function JoelConfig.dragTimedOut(startedAt: number, now: number): boolean
	return now - startedAt >= JoelConfig.DragTimeoutSeconds
end

function JoelConfig.dragFailureExpired(failedAt: number, now: number): boolean
	return now - failedAt >= JoelConfig.DragPathFailureSeconds
end

function JoelConfig.cycleLength(): number
	return JoelConfig.HuntWindowSeconds + JoelConfig.RestWindowSeconds
end

--[[
	Which window `elapsed` seconds past the cycle epoch falls in, and how much of
	it is left.

	Deriving the phase from an epoch instead of accumulating a counter is what
	lets the server publish two numbers that never change between transitions
	while every client still agrees to the frame, including one that joined
	eleven seconds into a window.

	Luau's `%` is floored, so a negative elapsed — a client whose clock momentarily
	reads behind the published epoch — wraps to the end of the cycle rather than
	returning a negative offset and reporting a window that has not started.
]]
function JoelConfig.cycleAt(elapsed: number): (string, number)
	local length = JoelConfig.cycleLength()
	if length <= 0 then
		return JoelConfig.PhaseHunt, math.huge
	end
	local into = elapsed % length
	if into < JoelConfig.HuntWindowSeconds then
		return JoelConfig.PhaseHunt, JoelConfig.HuntWindowSeconds - into
	end
	return JoelConfig.PhaseRest, length - into
end

return JoelConfig
