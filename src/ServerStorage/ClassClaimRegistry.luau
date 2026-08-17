--!strict

-- Pure, server-owned reservation state for class podiums. Keeping this logic
-- separate makes both sides of the exclusivity rule directly testable.
local ClassClaimRegistry = {}

export type State = {
	none: string,
	classByPlayer: { [Player]: string },
	ownerByClass: { [string]: Player },
}

function ClassClaimRegistry.new(none: string): State
	return {
		none = none,
		classByPlayer = {},
		ownerByClass = {},
	}
end

function ClassClaimRegistry.register(state: State, player: Player): boolean
	if state.classByPlayer[player] ~= nil then
		return false
	end
	state.classByPlayer[player] = state.none
	return true
end

function ClassClaimRegistry.getClass(state: State, player: Player): string
	return state.classByPlayer[player] or state.none
end

function ClassClaimRegistry.claim(state: State, player: Player, class: string): boolean
	if ClassClaimRegistry.getClass(state, player) ~= state.none then
		return false
	end
	if state.ownerByClass[class] then
		return false
	end

	-- Neither operation yields, so the player and class become reserved as one
	-- atomic step before any gear is applied.
	state.ownerByClass[class] = player
	state.classByPlayer[player] = class
	return true
end

function ClassClaimRegistry.release(state: State, player: Player)
	local class = state.classByPlayer[player]
	if class and state.ownerByClass[class] == player then
		state.ownerByClass[class] = nil
	end
	state.classByPlayer[player] = nil
end

return ClassClaimRegistry
