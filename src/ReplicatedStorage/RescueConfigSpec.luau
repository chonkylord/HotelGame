return function()
	-- TestEZ applies its DSL to this function's environment rather than to the
	-- module, so the names only exist once we are inside it. Pulling them into
	-- locals here keeps luau-lsp from reading them as undefined globals.
	local env = getfenv()
	local describe = env.describe
	local it = env.it
	local expect = env.expect

	local Config = require(script.Parent.RescueConfig)

	describe("rescue states", function()
		it("recognizes exactly the five replicated states", function()
			for _, state in {
				Config.StateHealthy,
				Config.StateDragging,
				Config.StateDowned,
				Config.StateCarried,
				Config.StateDead,
			} do
				expect(Config.isState(state)).to.equal(true)
			end
			expect(Config.isState("Respawning")).to.equal(false)
		end)

		it("only lets inert floor bodies be picked up", function()
			expect(Config.canPickUp(Config.StateDowned)).to.equal(true)
			expect(Config.canPickUp(Config.StateDead)).to.equal(true)
			expect(Config.canPickUp(Config.StateHealthy)).to.equal(false)
			expect(Config.canPickUp(Config.StateDragging)).to.equal(false)
			expect(Config.canPickUp(Config.StateCarried)).to.equal(false)
		end)
	end)

	describe("two-strike catches", function()
		it("drags the first catch and incapacitates every later catch", function()
			expect(Config.catchOutcome(0)).to.equal("Drag")
			expect(Config.catchOutcome(1)).to.equal("Incapacitated")
			expect(Config.catchOutcome(2)).to.equal("Incapacitated")
		end)
	end)

	describe("rescue tuning", function()
		it("keeps every interaction server-checkable and carry slower", function()
			expect(Config.ReviveHoldSeconds > 0).to.equal(true)
			expect(Config.ReviveRange > 0).to.equal(true)
			expect(Config.BodyPickupRange > 0).to.equal(true)
			expect(Config.CarrySpeedMultiplier > 0 and Config.CarrySpeedMultiplier < 1).to.equal(true)
			expect(Config.MaxBandages >= 1).to.equal(true)
		end)
	end)
end
