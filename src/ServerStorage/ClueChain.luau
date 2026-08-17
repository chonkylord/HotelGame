--!strict
--[[
	Pure, server-owned construction and progress rules for the shared clue chain.
	The service supplies an explicit Random and owns all world interactions; this
	module only transforms ordinary tables. Keeping route safety here makes an
	unreachable shuffle impossible regardless of which service or test builds it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClueConfig = require(ReplicatedStorage:WaitForChild("ClueConfig"))

local ClueChain = {}

type NodeKind = "Note" | "Cipher" | "Lever" | "Search" | "Carry"

export type Node = {
	siteId: string,
	kind: NodeKind,
	digit: string,
	solved: boolean,
	riddle: string,
}

export type State = {
	nodes: { Node },
	index: number,
	code: string,
	exitCode: string,
	phase: string,
}

local ROUTE_ATTEMPTS = 64
local KIND_ATTEMPTS = 32

local IS_RIDDLE: { [string]: boolean } = {
	Note = true,
	Cipher = true,
	Lever = false,
	Search = false,
	Carry = false,
}

local function asNodeKind(kind: string): NodeKind
	if kind == "Note" then
		return "Note"
	elseif kind == "Cipher" then
		return "Cipher"
	elseif kind == "Lever" then
		return "Lever"
	elseif kind == "Search" then
		return "Search"
	elseif kind == "Carry" then
		return "Carry"
	end
	error(`Unknown clue kind "{kind}"`)
end

-- Route construction ---------------------------------------------------------

local function shuffledStrings(source: { string }, rng: Random): { string }
	local result = table.clone(source)
	for index = #result, 2, -1 do
		local replacement = rng:NextInteger(1, index)
		result[index], result[replacement] = result[replacement], result[index]
	end
	return result
end

local function shuffledKinds(source: { NodeKind }, rng: Random): { NodeKind }
	local result = table.clone(source)
	for index = #result, 2, -1 do
		local replacement = rng:NextInteger(1, index)
		result[index], result[replacement] = result[replacement], result[index]
	end
	return result
end

local function takeRoute(source: { string }): { string }
	local route = table.create(ClueConfig.ChainLength)
	for index = 1, ClueConfig.ChainLength do
		route[index] = source[index]
	end
	return route
end

function ClueChain.routeIsReachable(siteIds: { string }): boolean
	local hasLeftLobby = false
	for _, siteId in siteIds do
		if ClueConfig.LobbySiteIds[siteId] then
			if hasLeftLobby then
				return false
			end
		else
			hasLeftLobby = true
		end
	end
	return true
end

local function routeSupportsPuzzleMix(route: { string }): boolean
	local riddleSiteCount = 0
	local physicalSiteCount = 0
	for _, siteId in route do
		local site = ClueConfig.findSite(siteId)
		if not site then
			return false
		end
		local supportsRiddle = false
		local supportsPhysical = false
		for _, kind in site.allowedKinds do
			if IS_RIDDLE[kind] then
				supportsRiddle = true
			else
				supportsPhysical = true
			end
		end
		riddleSiteCount += if supportsRiddle then 1 else 0
		physicalSiteCount += if supportsPhysical then 1 else 0
	end
	return riddleSiteCount >= 2 and physicalSiteCount >= 2
end

local function forceReachable(source: { string }): { string }
	local lobby = table.create(#source)
	local hotel = table.create(#source)
	for _, siteId in source do
		if ClueConfig.LobbySiteIds[siteId] then
			table.insert(lobby, siteId)
		else
			table.insert(hotel, siteId)
		end
	end

	local route = table.create(ClueConfig.ChainLength)
	for _, siteId in lobby do
		if #route >= ClueConfig.ChainLength then
			break
		end
		table.insert(route, siteId)
	end
	for _, siteId in hotel do
		if #route >= ClueConfig.ChainLength then
			break
		end
		table.insert(route, siteId)
	end
	assert(
		#route == ClueConfig.ChainLength and routeSupportsPuzzleMix(route),
		"ClueChain could not construct a reachable route with two riddle and two physical-capable sites"
	)
	return route
end

local function buildRoute(siteIds: { string }, rng: Random): { string }
	local fallbackSource = shuffledStrings(siteIds, rng)
	local fallback = takeRoute(fallbackSource)
	if ClueChain.routeIsReachable(fallback) and routeSupportsPuzzleMix(fallback) then
		return fallback
	end

	for _ = 2, ROUTE_ATTEMPTS do
		local candidateSource = shuffledStrings(siteIds, rng)
		local candidate = takeRoute(candidateSource)
		if ClueChain.routeIsReachable(candidate) and routeSupportsPuzzleMix(candidate) then
			return candidate
		end
		fallbackSource = candidateSource
	end

	-- A bounded retry protects startup from a future pool whose topology makes
	-- the random constraint vanishingly rare. Stable partitioning keeps lobby
	-- clues first; the per-site compatibility profile still controls footprint.
	return forceReachable(fallbackSource)
end

-- Kind composition -----------------------------------------------------------

local function allowedKindsForSite(siteId: string): { NodeKind }
	local site = ClueConfig.findSite(siteId)
	assert(site, `ClueChain cannot assign a kind to unknown site "{siteId}"`)
	return site.allowedKinds
end

local function randomKinds(route: { string }, rng: Random): { NodeKind }
	local kinds: { NodeKind } = {}
	for index, siteId in route do
		local allowed = allowedKindsForSite(siteId)
		kinds[index] = allowed[rng:NextInteger(1, #allowed)]
	end
	return kinds
end

local function compositionIsValid(route: { string }, kinds: { NodeKind }): boolean
	local riddleCount = 0
	local physicalCount = 0
	for index, rawKind in kinds do
		local kind = asNodeKind(rawKind)
		if not ClueConfig.siteAllowsKind(route[index], kind) then
			return false
		end
		if IS_RIDDLE[kind] then
			riddleCount += 1
		else
			physicalCount += 1
		end
	end
	return riddleCount >= 2 and physicalCount >= 2
end

local function forceValidKinds(route: { string }, rng: Random): { NodeKind }
	local assigned: { string? } = table.create(#route)

	local function assign(index: number, riddleCount: number, physicalCount: number): boolean
		if index > #route then
			return riddleCount >= 2 and physicalCount >= 2
		end

		local remainingAfter = #route - index
		for _, rawKind in shuffledKinds(allowedKindsForSite(route[index]), rng) do
			local kind = asNodeKind(rawKind)
			local nextRiddles = riddleCount + if IS_RIDDLE[kind] then 1 else 0
			local nextPhysical = physicalCount + if IS_RIDDLE[kind] then 0 else 1
			if nextRiddles + remainingAfter < 2 or nextPhysical + remainingAfter < 2 then
				continue
			end
			assigned[index] = kind
			if assign(index + 1, nextRiddles, nextPhysical) then
				return true
			end
		end
		assigned[index] = nil
		return false
	end

	assert(assign(1, 0, 0), "ClueChain site compatibility cannot satisfy the required two-riddle/two-physical mix")
	local kinds: { NodeKind } = {}
	for index = 1, #route do
		local kind = assigned[index]
		assert(kind, `ClueChain fallback did not assign node {index}`)
		kinds[index] = asNodeKind(kind)
	end
	return kinds
end

local function buildKinds(route: { string }, rng: Random): { NodeKind }
	for _ = 1, KIND_ATTEMPTS do
		local kinds = randomKinds(route, rng)
		if compositionIsValid(route, kinds) then
			return kinds
		end
	end
	return forceValidKinds(route, rng)
end

local function randomCode(length: number, rng: Random): string
	local digits = table.create(length)
	for index = 1, length do
		digits[index] = tostring(rng:NextInteger(0, 9))
	end
	return table.concat(digits)
end

-- Public state operations ----------------------------------------------------

function ClueChain.build(siteIds: { string }, rng: Random): State
	local eligible = table.create(#siteIds)
	local seen: { [string]: boolean } = {}
	for _, siteId in siteIds do
		local site = ClueConfig.findSite(siteId)
		if site and site.actOne and not seen[siteId] then
			seen[siteId] = true
			table.insert(eligible, siteId)
		end
	end

	assert(
		#eligible >= ClueConfig.ChainLength,
		`ClueChain needs {ClueConfig.ChainLength} distinct Act I sites, but received {#eligible}`
	)

	local route = buildRoute(eligible, rng)
	local kinds = buildKinds(route, rng)
	local code = randomCode(ClueConfig.ChainLength, rng)
	local nodes = table.create(ClueConfig.ChainLength)

	for index, siteId in route do
		local site = ClueConfig.findSite(siteId)
		assert(site, `ClueChain selected unknown site "{siteId}"`)
		nodes[index] = {
			siteId = siteId,
			kind = kinds[index],
			digit = string.sub(code, index, index),
			solved = false,
			riddle = site.riddle,
		}
	end

	return {
		nodes = nodes,
		index = 1,
		code = code,
		exitCode = randomCode(ClueConfig.ExitCodeLength, rng),
		phase = ClueConfig.PhaseHunt,
	}
end

function ClueChain.currentNode(state: State): Node?
	return state.nodes[state.index]
end

function ClueChain.solve(state: State, nodeIndex: number): boolean
	if nodeIndex ~= state.index then
		return false
	end

	local node = state.nodes[nodeIndex]
	if not node or node.solved then
		return false
	end

	node.solved = true
	state.index += 1
	return true
end

function ClueChain.digitsKnown(state: State): string
	local revealed = table.create(#state.nodes, false)
	for index, node in state.nodes do
		revealed[index] = node.solved
	end
	return ClueConfig.maskedDigits(state.code, revealed)
end

function ClueChain.isComplete(state: State): boolean
	return state.index > #state.nodes
end

return ClueChain
