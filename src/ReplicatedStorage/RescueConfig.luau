--!strict
-- Shared names and tuning for the server-owned two-strike rescue loop. The
-- client reads replicated state only; RescueController owns every transition.

local RescueConfig = {}

export type State = "Healthy" | "Dragging" | "Downed" | "Carried" | "Dead"
export type CatchOutcome = "Drag" | "Incapacitated"

-- State ----------------------------------------------------------------------

RescueConfig.StateHealthy = "Healthy"
RescueConfig.StateDragging = "Dragging"
RescueConfig.StateDowned = "Downed"
RescueConfig.StateCarried = "Carried"
RescueConfig.StateDead = "Dead"

RescueConfig.StateAttribute = "RescueState"
RescueConfig.CatchCountAttribute = "RescueCatchCount"
RescueConfig.BandageCountAttribute = "BandageCount"
RescueConfig.CarrierUserIdAttribute = "RescueCarrierUserId"
RescueConfig.CarryingUserIdAttribute = "RescueCarryingUserId"
RescueConfig.CarrySpeedMultiplierAttribute = "RescueCarrySpeedMultiplier"

-- Networking -----------------------------------------------------------------

RescueConfig.RemotesFolder = "RescueRemotes"
RescueConfig.CarryToggleEvent = "RescueCarryToggle"
RescueConfig.FeedbackEvent = "RescueFeedback"

-- World contracts ------------------------------------------------------------

RescueConfig.DropZoneTag = "RescueDropZone"
RescueConfig.DropZoneFloorAttribute = "RescueFloorId"
RescueConfig.BandagePickupTag = "BandagePickup"
RescueConfig.BandageClaimedAttribute = "RescueBandageClaimed"
RescueConfig.BandagePromptName = "BandagePrompt"
RescueConfig.RevivePromptName = "RevivePrompt"

-- Tuning ---------------------------------------------------------------------

RescueConfig.ReviveHoldSeconds = 4
RescueConfig.ReviveRange = 8
RescueConfig.BandagePickupRange = 9
RescueConfig.BodyPickupRange = 9
RescueConfig.CarryBreakDistance = 16
RescueConfig.DragBreakDistance = 24
RescueConfig.CarrySpeedMultiplier = 0.62
RescueConfig.MaxBandages = 3
RescueConfig.RequestCooldownSeconds = 0.2

-- Pure helpers ---------------------------------------------------------------

function RescueConfig.isState(value: any): boolean
	return value == RescueConfig.StateHealthy
		or value == RescueConfig.StateDragging
		or value == RescueConfig.StateDowned
		or value == RescueConfig.StateCarried
		or value == RescueConfig.StateDead
end

function RescueConfig.isImmobilized(state: any): boolean
	return state == RescueConfig.StateDragging
		or state == RescueConfig.StateDowned
		or state == RescueConfig.StateCarried
		or state == RescueConfig.StateDead
end

function RescueConfig.canPickUp(state: any): boolean
	return state == RescueConfig.StateDowned or state == RescueConfig.StateDead
end

function RescueConfig.catchOutcome(previousCatches: number): CatchOutcome
	return if previousCatches < 1 then "Drag" else "Incapacitated"
end

return RescueConfig
