-- Covers the pure maths in SurvivalConfig — the speed curve is the one piece
-- both SurvivalService and SurvivalClient depend on agreeing about, and it is
-- easy to break by retuning HungerComfort or MinSpeedScale without noticing
-- that full-hunger walking stopped landing on BaseWalkSpeed.

return function()
	-- TestEZ applies its DSL to this function's environment rather than to the
	-- module, so the names only exist once we are inside it. Pulling them into
	-- locals here keeps luau-lsp from reading them as undefined globals.
	local env = getfenv()
	local describe = env.describe
	local it = env.it
	local expect = env.expect

	local Config = require(script.Parent.SurvivalConfig)

	describe("maxHealth", function()
		it("is one heart per HealthPerHeart", function()
			expect(Config.maxHealth()).to.equal(Config.Hearts * Config.HealthPerHeart)
		end)
	end)

	describe("hungerSpeedScale", function()
		it("leaves speed untouched on a full stomach", function()
			expect(Config.hungerSpeedScale(Config.MaxHunger)).to.equal(1)
		end)

		it("still leaves it untouched right down to the comfort threshold", function()
			expect(Config.hungerSpeedScale(Config.HungerComfort)).to.equal(1)
		end)

		it("bottoms out at MinSpeedScale on an empty one", function()
			expect(Config.hungerSpeedScale(0)).to.be.near(Config.MinSpeedScale)
		end)

		it("never drops below MinSpeedScale, even on a negative meter", function()
			expect(Config.hungerSpeedScale(-25)).to.be.near(Config.MinSpeedScale)
		end)

		it("falls off gradually rather than in a step", function()
			local half = Config.hungerSpeedScale(Config.HungerComfort / 2)
			expect(half < 1).to.equal(true)
			expect(half > Config.MinSpeedScale).to.equal(true)
		end)

		it("never speeds anyone up", function()
			for hunger = 0, Config.MaxHunger do
				expect(Config.hungerSpeedScale(hunger) <= 1).to.equal(true)
			end
		end)
	end)

	describe("walkSpeedFor", function()
		it("walks at BaseWalkSpeed when fed", function()
			expect(Config.walkSpeedFor(Config.MaxHunger, false)).to.be.near(Config.BaseWalkSpeed)
		end)

		it("sprints at SprintWalkSpeed when fed", function()
			expect(Config.walkSpeedFor(Config.MaxHunger, true)).to.be.near(Config.SprintWalkSpeed)
		end)

		it("scales the starving walk by MinSpeedScale", function()
			expect(Config.walkSpeedFor(0, false)).to.be.near(Config.BaseWalkSpeed * Config.MinSpeedScale)
		end)

		it("keeps sprinting faster than walking at equal hunger", function()
			for hunger = 0, Config.MaxHunger, 10 do
				expect(Config.walkSpeedFor(hunger, true) > Config.walkSpeedFor(hunger, false)).to.equal(true)
			end
		end)
	end)

	describe("sprintAllowed", function()
		it("requires hunger and available stamina for ordinary players", function()
			expect(Config.sprintAllowed(1, 1, false, false)).to.equal(true)
			expect(Config.sprintAllowed(0, 1, false, false)).to.equal(false)
			expect(Config.sprintAllowed(1, 0, false, false)).to.equal(false)
			expect(Config.sprintAllowed(1, 1, true, false)).to.equal(false)
		end)

		it("keeps an authorised infinite sprint available at every meter state", function()
			expect(Config.sprintAllowed(0, 0, true, true)).to.equal(true)
		end)
	end)

	describe("speedHunger", function()
		it("uses full-fed speed scaling for an authorised infinite sprint", function()
			local effectiveHunger = Config.speedHunger(0, true, true)
			expect(Config.walkSpeedFor(effectiveHunger, true)).to.equal(Config.SprintWalkSpeed)
		end)

		it("preserves hunger scaling for ordinary sprinting and admin walking", function()
			expect(Config.speedHunger(0, true, false)).to.equal(0)
			expect(Config.speedHunger(0, false, true)).to.equal(0)
		end)
	end)
end
