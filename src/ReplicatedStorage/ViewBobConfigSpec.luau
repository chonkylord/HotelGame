-- Covers the pure curves in ViewBobConfig.
--
-- The one that genuinely matters is the phase convention. ViewBobClient fires
-- the impact spring on every StepPhase boundary and trusts that boundary to be
-- the bottom of the dip. Swapping the cos for a sin in gaitOffset would still
-- look like a bob in isolation, but every footfall impact would land a quarter
-- stride away from the step it belongs to. Nothing but a test catches that.

return function()
	-- TestEZ applies its DSL to this function's environment rather than to the
	-- module, so the names only exist once we are inside it. Pulling them into
	-- locals here keeps luau-lsp from reading them as undefined globals.
	local env = getfenv()
	local describe = env.describe
	local it = env.it
	local expect = env.expect

	local Config = require(script.Parent.ViewBobConfig)

	describe("stepFrequency", function()
		--[[
			The one that matters. Camera and body have to bob at the same rate or
			they beat against each other, and the beat is what players see as the
			held item trembling — it is not visible as two separate motions. Any
			retune that reintroduces an independent cadence here has to fail.
		]]
		it("bobs at exactly the rate the body walks at", function()
			local LocomotionConfig = require(script.Parent.LocomotionConfig)
			for speed = Config.MinBobSpeed + 0.5, 24, 0.5 do
				expect(Config.stepFrequency(speed)).to.be.near(LocomotionConfig.stepFrequency(speed))
			end
		end)

		it("stands still at a standstill", function()
			expect(Config.stepFrequency(0)).to.equal(0)
			expect(Config.stepFrequency(Config.MinBobSpeed)).to.equal(0)
		end)

		it("speeds up with speed", function()
			expect(Config.stepFrequency(24) > Config.stepFrequency(16)).to.equal(true)
		end)

		it("lengthens the stride rather than scaling the step rate with speed", function()
			-- Sub-linear: doubling speed must add well under double the steps,
			-- or a sprint reads as a scurry instead of longer strides.
			local doubled = Config.stepFrequency(Config.ReferenceSpeed * 2)
			expect(doubled < Config.stepFrequency(Config.ReferenceSpeed) * 2).to.equal(true)
		end)
	end)

	describe("gaitIntensity", function()
		it("ignores speeds below the threshold", function()
			expect(Config.gaitIntensity(0)).to.equal(0)
			expect(Config.gaitIntensity(Config.MinBobSpeed)).to.equal(0)
		end)

		it("is at full strength once properly walking", function()
			expect(Config.gaitIntensity(Config.FullBobSpeed)).to.equal(1)
			expect(Config.gaitIntensity(Config.ReferenceSpeed)).to.equal(1)
		end)

		it("ramps in between rather than switching on", function()
			local midpoint = (Config.MinBobSpeed + Config.FullBobSpeed) / 2
			expect(Config.gaitIntensity(midpoint)).to.be.near(0.5)
		end)
	end)

	describe("amplitudeScale", function()
		it("is unity at the reference speed", function()
			expect(Config.amplitudeScale(Config.ReferenceSpeed)).to.be.near(1)
		end)

		it("caps so a speed buff cannot throw the camera around", function()
			expect(Config.amplitudeScale(10000)).to.be.near(Config.MaxAmplitudeScale)
		end)
	end)

	describe("gaitOffset", function()
		it("puts the bottom of the dip exactly on the footfall", function()
			-- ViewBobClient impulses the spring at multiples of StepPhase, so
			-- that phase has to be the lowest point of the curve.
			local atFootfall = Config.gaitOffset(0, 1, 1).Y
			expect(atFootfall).to.be.near(-Config.VerticalAmplitude)

			for _, fraction in { 0.1, 0.25, 0.5, 0.75, 0.9 } do
				local elsewhere = Config.gaitOffset(Config.StepPhase * fraction, 1, 1).Y
				expect(elsewhere > atFootfall).to.equal(true)
			end
		end)

		it("dips on both footfalls of a stride", function()
			expect(Config.gaitOffset(0, 1, 1).Y).to.be.near(-Config.VerticalAmplitude)
			expect(Config.gaitOffset(Config.StepPhase, 1, 1).Y).to.be.near(-Config.VerticalAmplitude)
		end)

		it("is centred at each footfall, because heel strike is double support", function()
			expect(Config.gaitOffset(0, 1, 1).X).to.be.near(0)
			expect(Config.gaitOffset(Config.StepPhase, 1, 1).X).to.be.near(0)
		end)

		it("peaks the sway mid-step and alternates sides", function()
			-- Full sway is at mid-stance, where the weight is entirely over the
			-- stance leg, and it goes the other way on the following step. That
			-- alternation is what makes it a stride rather than a wobble.
			local firstStep = Config.gaitOffset(Config.StepPhase * 0.5, 1, 1).X
			local secondStep = Config.gaitOffset(Config.StepPhase * 1.5, 1, 1).X
			expect(firstStep).to.be.near(Config.LateralAmplitude)
			expect(secondStep).to.be.near(-Config.LateralAmplitude)
		end)

		it("repeats exactly once per stride, so the phase wrap is seamless", function()
			local start = Config.gaitOffset(0.7, 1, 1)
			local wrapped = Config.gaitOffset(0.7 + Config.StridePhase, 1, 1)
			expect(wrapped.X).to.be.near(start.X)
			expect(wrapped.Y).to.be.near(start.Y)
		end)

		it("vanishes when the gait does", function()
			local still = Config.gaitOffset(1.3, 0, 1)
			expect(still.X).to.be.near(0)
			expect(still.Y).to.be.near(0)
		end)
	end)

	describe("strafeRoll", function()
		it("leans the opposite way to the sidestep", function()
			expect(Config.strafeRoll(1) < 0).to.equal(true)
			expect(Config.strafeRoll(-1) > 0).to.equal(true)
		end)

		it("stays level running straight ahead", function()
			expect(Config.strafeRoll(0)).to.be.near(0)
		end)

		it("clamps past a full sidestep", function()
			expect(Config.strafeRoll(5)).to.be.near(Config.strafeRoll(1))
		end)
	end)

	describe("springStep", function()
		it("settles back to rest", function()
			local value, velocity = 0.4, 0
			for _ = 1, 400 do
				value, velocity = Config.springStep(value, velocity, 1 / 60)
			end
			expect(math.abs(value) < 1e-3).to.equal(true)
		end)

		it("rebounds rather than crawling home", function()
			-- Underdamped on purpose: the small overshoot is what gives a
			-- footfall its weight. A critically damped spring never crosses zero.
			local value, velocity = 0, -Config.FootfallImpulse
			local crossed = false
			for _ = 1, 200 do
				value, velocity = Config.springStep(value, velocity, 1 / 60)
				if value > 0 then
					crossed = true
					break
				end
			end
			expect(crossed).to.equal(true)
		end)

		it("cannot be blown up by a long frame", function()
			-- Explicit Euler diverges if dt outruns the stiffness, and frame
			-- hitches happen. The clamp inside springStep is the only guard.
			local value, velocity = 0.3, -5
			for _ = 1, 200 do
				value, velocity = Config.springStep(value, velocity, 1.5)
			end
			expect(value == value).to.equal(true) -- not NaN
			expect(math.abs(value) < 1).to.equal(true)
		end)
	end)

	describe("landingImpulse", function()
		it("ignores a step off a kerb", function()
			expect(Config.landingImpulse(0)).to.equal(0)
			expect(Config.landingImpulse(Config.LandingMinSpeed)).to.equal(0)
		end)

		it("grows with the drop", function()
			expect(Config.landingImpulse(40) > Config.landingImpulse(20)).to.equal(true)
		end)

		it("caps so a long fall cannot slam the view through the floor", function()
			expect(Config.landingImpulse(100000)).to.be.near(Config.LandingMaxImpulse)
		end)
	end)

	describe("breathOffset", function()
		it("only breathes while standing still", function()
			local walking = Config.breathOffset(1.7, 0)
			expect(walking.Y).to.be.near(0)
		end)

		it("stays within its amplitude", function()
			for step = 0, 60 do
				local offset = Config.breathOffset(step * 0.25, 1)
				expect(math.abs(offset.Y) <= Config.BreathAmplitude + 1e-6).to.equal(true)
			end
		end)
	end)
end
