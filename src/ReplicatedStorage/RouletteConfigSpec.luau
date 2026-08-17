return function()
	local env = getfenv()
	local describe = env.describe
	local it = env.it
	local expect = env.expect

	local Config = require(script.Parent.RouletteConfig)

	describe("Superman's fate wheel", function()
		it("has exactly five abilities and three curses", function()
			local good = 0
			local curses = 0
			for _, outcome in Config.Outcomes do
				if outcome.good then
					good += 1
				else
					curses += 1
				end
			end
			expect(good).to.equal(5)
			expect(curses).to.equal(3)
		end)

		it("uses a four-minute roll and effect cycle", function()
			expect(Config.CooldownSeconds).to.equal(240)
			expect(Config.EffectDurationSeconds).to.equal(240)
		end)

		it("contains both requested speed extremes", function()
			local rush = Config.findOutcome("MetropolisRush")
			local drag = Config.findOutcome("KryptoniteDrag")
			assert(rush and drag, "the two speed outcomes must exist")
			expect(rush.speedMultiplier).to.equal(2)
			expect(drag.speedMultiplier).to.equal(0.5)
		end)

		it("never reports a negative cooldown", function()
			expect(Config.remaining(100, 90)).to.equal(0)
			expect(Config.remaining(100, 130)).to.equal(30)
		end)
	end)
end
