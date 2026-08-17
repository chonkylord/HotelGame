-- The shared hunt cannot be repaired after players receive an unreachable
-- route. These tests drive the pure registry across many seeded rounds so its
-- topology, puzzle mix, and ordered progress stay true at the construction edge.

return function()
	-- TestEZ applies its DSL to this function's environment rather than to the
	-- module, so the names only exist once we are inside it. Pulling them into
	-- locals here keeps luau-lsp from reading them as undefined globals.
	local env = getfenv()
	local describe = env.describe
	local it = env.it
	local expect = env.expect

	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Config = require(ReplicatedStorage.ClueConfig)
	local ClueChain = require(script.Parent.ClueChain)

	local physicalKinds = {
		Lever = true,
		Search = true,
		Carry = true,
	}

	local riddleKinds = {
		Note = true,
		Cipher = true,
	}

	local function siteIds()
		local result = {}
		for _, site in Config.Sites do
			table.insert(result, site.id)
		end
		return result
	end

	local function actOneSiteIds()
		local result = {}
		for _, site in Config.Sites do
			if site.actOne then
				table.insert(result, site.id)
			end
		end
		return result
	end

	local function routeKey(state)
		local route = {}
		for _, node in state.nodes do
			table.insert(route, node.siteId)
		end
		return table.concat(route, "|")
	end

	describe("seeded clue construction", function()
		--[[
			A single happy seed says very little about a shuffle. This sweep catches
			composition and reachability failures throughout the random branches while
			remaining perfectly reproducible when one fails.
		]]
		it("builds two riddles and two physical puzzles on reachable, distinct sites", function()
			local candidates = siteIds()
			for seed = 1, 200 do
				local state = ClueChain.build(candidates, Random.new(seed))
				local seen = {}
				local route = {}
				local physicalCount = 0
				local riddleCount = 0
				local assembledCode = {}

				expect(#state.nodes).to.equal(Config.ChainLength)
				expect(#state.code).to.equal(Config.ChainLength)
				expect(string.match(state.code, "^%d+$") ~= nil).to.equal(true)
				expect(#state.exitCode).to.equal(Config.ExitCodeLength)
				expect(string.match(state.exitCode, "^%d+$") ~= nil).to.equal(true)

				for _, node in state.nodes do
					expect(seen[node.siteId] == nil).to.equal(true)
					expect(node.siteId == "VaultFacade").to.equal(false)
					expect(node.solved).to.equal(false)
					expect(string.match(node.riddle, "%S") ~= nil).to.equal(true)
					local authoredSite = Config.findSite(node.siteId)
					expect(authoredSite ~= nil and node.riddle == authoredSite.riddle).to.equal(true)

					seen[node.siteId] = true
					table.insert(route, node.siteId)
					table.insert(assembledCode, node.digit)
					expect(Config.siteAllowsKind(node.siteId, node.kind)).to.equal(true)
					if node.kind == "Lever" then
						expect(node.siteId).to.equal("StorageBreaker")
					end
					if physicalKinds[node.kind] then
						physicalCount += 1
					elseif riddleKinds[node.kind] then
						riddleCount += 1
					end
				end

				expect(physicalCount >= 2).to.equal(true)
				expect(riddleCount >= 2).to.equal(true)
				expect(table.concat(assembledCode)).to.equal(state.code)
				expect(ClueChain.routeIsReachable(route)).to.equal(true)
				expect(state.index).to.equal(1)
				expect(state.phase).to.equal(Config.PhaseHunt)
			end
		end)

		it("uses different routes for different seeds", function()
			local candidates = siteIds()
			local first = ClueChain.build(candidates, Random.new(1001))
			local second = ClueChain.build(candidates, Random.new(2002))
			expect(routeKey(first) == routeKey(second)).to.equal(false)
		end)

		it("filters duplicate, unknown, and Act II-only candidates", function()
			local candidates = siteIds()
			table.insert(candidates, "ReceptionDesk")
			table.insert(candidates, "VaultFacade")
			table.insert(candidates, "NotARealSite")
			local state = ClueChain.build(candidates, Random.new(81))
			local seen = {}
			for _, node in state.nodes do
				expect(seen[node.siteId] == nil).to.equal(true)
				expect(node.siteId == "VaultFacade").to.equal(false)
				expect(node.siteId == "NotARealSite").to.equal(false)
				seen[node.siteId] = true
			end
		end)

		it("keeps bulky puzzle props out of public landmarks", function()
			local candidates = siteIds()
			for seed = 1, 200 do
				local state = ClueChain.build(candidates, Random.new(seed))
				for _, node in state.nodes do
					if Config.LobbySiteIds[node.siteId] then
						expect(node.kind ~= "Lever" and node.kind ~= "Search").to.equal(true)
					end
					expect(node.kind ~= "Lever" or node.siteId == "StorageBreaker").to.equal(true)
					expect(
						node.kind ~= "Search"
							or node.siteId == "Room2Bed"
							or node.siteId == "RestaurantBuffet"
							or node.siteId == "BallroomStage"
					).to.equal(true)
				end
			end
		end)

		it("finds a compatible two-riddle/two-physical mix for every five-site selection", function()
			local candidates = actOneSiteIds()
			local selected = {}
			local checked = 0

			local function visit(startIndex)
				if #selected == Config.ChainLength then
					checked += 1
					local state = ClueChain.build(table.clone(selected), Random.new(10000 + checked))
					local riddleCount = 0
					local physicalCount = 0
					for _, node in state.nodes do
						expect(Config.siteAllowsKind(node.siteId, node.kind)).to.equal(true)
						if riddleKinds[node.kind] then
							riddleCount += 1
						elseif physicalKinds[node.kind] then
							physicalCount += 1
						end
					end
					expect(riddleCount >= 2).to.equal(true)
					expect(physicalCount >= 2).to.equal(true)
					return
				end

				local remaining = Config.ChainLength - #selected
				for index = startIndex, #candidates - remaining + 1 do
					table.insert(selected, candidates[index])
					visit(index + 1)
					table.remove(selected)
				end
			end

			visit(1)
			expect(checked).to.equal(1287)
		end)

		it("keeps the authored storage marker attached to its breaker panel", function()
			local candidates = siteIds()
			local sawStorage = false
			for seed = 1, 200 do
				local state = ClueChain.build(candidates, Random.new(seed))
				for _, node in state.nodes do
					if node.siteId == "StorageBreaker" then
						sawStorage = true
						expect(node.kind).to.equal("Lever")
					end
				end
			end
			expect(sawStorage).to.equal(true)
		end)
	end)

	describe("the one-way lobby boundary", function()
		--[[
			Lobby -> Rooms exists, but Rooms -> Lobby does not. Treating lobby nodes
			as a prefix also covers an indirect hotel-side detour that later attempts
			to return to reception.
		]]
		it("accepts a lobby prefix and rejects any return to it", function()
			expect(ClueChain.routeIsReachable({ "ReceptionDesk", "ClassPodiums", "Room2Bed", "BallroomStage" })).to.equal(
				true
			)
			expect(ClueChain.routeIsReachable({ "Room2Bed", "ReceptionDesk" })).to.equal(false)
			expect(ClueChain.routeIsReachable({ "Room2Bed", "BallroomStage", "ProjectMirror" })).to.equal(false)
		end)

		it("treats the live suite-floor mirror as hotel-side, not lobby-side", function()
			expect(Config.LobbySiteIds.ProjectMirror == nil).to.equal(true)
			expect(ClueChain.routeIsReachable({ "ReceptionDesk", "ProjectMirror" })).to.equal(true)
			expect(ClueChain.routeIsReachable({ "ProjectMirror", "ReceptionDesk" })).to.equal(false)
		end)
	end)

	describe("ordered clue progress", function()
		it("masks digits until each node is solved in order", function()
			local state = ClueChain.build(siteIds(), Random.new(404))
			expect(ClueChain.digitsKnown(state)).to.equal(string.rep("_", Config.ChainLength))
			expect(ClueChain.currentNode(state)).to.equal(state.nodes[1])
			expect(ClueChain.isComplete(state)).to.equal(false)

			for nodeIndex = 1, Config.ChainLength do
				expect(ClueChain.solve(state, nodeIndex)).to.equal(true)
				local expected = string.sub(state.code, 1, nodeIndex) .. string.rep("_", Config.ChainLength - nodeIndex)
				expect(ClueChain.digitsKnown(state)).to.equal(expected)
			end

			expect(ClueChain.isComplete(state)).to.equal(true)
			expect(ClueChain.currentNode(state) == nil).to.equal(true)
		end)

		it("rejects future, repeated, and out-of-range solves without mutation", function()
			local state = ClueChain.build(siteIds(), Random.new(505))
			expect(ClueChain.solve(state, 2)).to.equal(false)
			expect(ClueChain.solve(state, 0)).to.equal(false)
			expect(state.index).to.equal(1)

			expect(ClueChain.solve(state, 1)).to.equal(true)
			local known = ClueChain.digitsKnown(state)
			expect(state.index).to.equal(2)
			expect(ClueChain.solve(state, 1)).to.equal(false)
			expect(ClueChain.solve(state, Config.ChainLength + 1)).to.equal(false)
			expect(state.index).to.equal(2)
			expect(ClueChain.digitsKnown(state)).to.equal(known)
		end)
	end)
end
