-- Covers the gait curve in LocomotionConfig.
--
-- The ones that genuinely matter are the cross-module bounds. The whole point
-- of the blend is that walking is the walk clip and sprinting is the run clip,
-- and nothing in LocomotionConfig can tell on its own whether that is still
-- true — it depends on SurvivalConfig's speeds, which are tuned for gameplay
-- reasons by somebody who has no reason to think about animation. Retuning
-- BaseWalkSpeed up past RunBlendStart would silently put ordinary walking back
-- into the run clip, which is the exact bug this whole thing exists to fix.

return function()
	-- TestEZ applies its DSL to this function's environment rather than to the
	-- module, so the names only exist once we are inside it. Pulling them into
	-- locals here keeps luau-lsp from reading them as undefined globals.
	local env = getfenv()
	local describe = env.describe
	local it = env.it
	local expect = env.expect

	local Config = require(script.Parent.LocomotionConfig)
	local SurvivalConfig = require(script.Parent.SurvivalConfig)

	describe("the blend band against the movement speeds", function()
		--[[
			Ordinary movement rides the RUN clip, which reads backwards until you
			do the arithmetic. The walk clip's stride is ~2 studs, so carrying 12
			studs/sec on it costs 1.9x playback — 6 steps/sec of frantic little
			paces. The run clip's stride is twice that and carries the same speed
			at 0.94x: 3 steps/sec and no slide. At 12 studs/sec the character is
			running whether or not the clip admits it.
		]]
		it("puts ordinary walking entirely on the run clip", function()
			expect(Config.runWeight(SurvivalConfig.BaseWalkSpeed)).to.equal(1)
		end)

		it("keeps the walk clip for the slow end, where it is honest", function()
			local slowest = SurvivalConfig.walkSpeedFor(0, false)
			expect(Config.runWeight(slowest)).to.equal(0)
		end)

		it("puts sprinting entirely on the run clip", function()
			expect(Config.runWeight(SurvivalConfig.SprintWalkSpeed)).to.equal(1)
		end)

		it("puts even a starving sprint entirely on the run clip", function()
			-- Hunger scales sprint speed down as well, and it must not drag the
			-- sprint back into the walk clip on the way.
			local slowestSprint = SurvivalConfig.walkSpeedFor(0, true)
			expect(Config.runWeight(slowestSprint)).to.equal(1)
		end)

		it("closes the band below ordinary walking and above the starving walk", function()
			-- The band has to finish before BaseWalkSpeed, or ordinary movement
			-- lands mid-blend on a walk clip spinning near its cap — the exact
			-- too-fast, sliding gait this arrangement exists to avoid. It also
			-- has to start above the starving walk so the slow end keeps a real
			-- walk rather than a slowed run.
			local slowestWalk = SurvivalConfig.walkSpeedFor(0, false)
			expect(slowestWalk <= Config.RunBlendStart).to.equal(true)
			expect(Config.RunBlendStart < Config.RunBlendEnd).to.equal(true)
			expect(Config.RunBlendEnd < SurvivalConfig.BaseWalkSpeed).to.equal(true)
		end)

		it("keeps the whole sprint range clear of the band", function()
			-- Hunger scales sprinting down too, so the binding case is the
			-- starving sprint, not SprintWalkSpeed.
			local slowestSprint = SurvivalConfig.walkSpeedFor(0, true)
			expect(Config.RunBlendEnd <= slowestSprint).to.equal(true)
		end)
	end)

	describe("runWeight", function()
		it("holds at the ends", function()
			expect(Config.runWeight(0)).to.equal(0)
			expect(Config.runWeight(Config.RunBlendStart)).to.equal(0)
			expect(Config.runWeight(Config.RunBlendEnd)).to.equal(1)
			expect(Config.runWeight(10000)).to.equal(1)
		end)

		it("never goes backwards", function()
			local previous = -1
			for speed = 0, 30, 0.25 do
				local weight = Config.runWeight(speed)
				expect(weight >= previous).to.equal(true)
				previous = weight
			end
		end)

		it("eases in and out rather than starting at full rate", function()
			-- Smoothstep, so the weight has barely moved a tenth of the way into
			-- the band. A linear ramp would be at 0.1 here and the pace change
			-- would be visible the instant the band is crossed.
			local span = Config.RunBlendEnd - Config.RunBlendStart
			expect(Config.runWeight(Config.RunBlendStart + span * 0.1) < 0.05).to.equal(true)
			expect(Config.runWeight(Config.RunBlendEnd - span * 0.1) > 0.95).to.equal(true)
		end)

		it("is half way across at the middle of the band", function()
			local middle = (Config.RunBlendStart + Config.RunBlendEnd) / 2
			expect(Config.runWeight(middle)).to.be.near(0.5)
		end)
	end)

	describe("playbackRate", function()
		it("matches the stride exactly wherever it is not capped", function()
			-- The uncapped range is the whole promise of the curve: the clip
			-- covers blendedClipSpeed studs per second of playback, so this rate
			-- is the one that keeps the planted foot planted.
			for speed = 1, 30, 0.5 do
				local weight = Config.runWeight(speed)
				local exact = speed / Config.blendedClipSpeed(weight)
				if exact < Config.maxRate(weight) and exact > Config.MinRate then
					expect(Config.playbackRate(speed)).to.be.near(exact)
				end
			end
		end)

		it("never runs a clip backwards or freezes it", function()
			for speed = 0, 60, 0.5 do
				expect(Config.playbackRate(speed) >= Config.MinRate).to.equal(true)
			end
		end)

		it("caps so a speed powerup cannot spin the legs apart", function()
			expect(Config.playbackRate(10000)).to.be.near(Config.MaxRunRate)
		end)

		it("speeds the gait up with the character on either side of the hand-over", function()
			-- Deliberately not asserted *across* the hand-over. The run clip's
			-- stride is twice the walk clip's, so covering the same ground needs
			-- less playback once it takes over and the rate genuinely falls
			-- through the band (1.66 down to 1.29). Lower cadence at a longer
			-- stride is what changing gait means; it is only a transient anyway,
			-- since nothing in the game sustains a speed inside the band.
			local function risesOver(from: number, to: number)
				local previous = -1
				for speed = from, to, 0.25 do
					local rate = Config.playbackRate(speed)
					expect(rate >= previous - 1e-9).to.equal(true)
					previous = rate
				end
			end
			risesOver(Config.MinMoveSpeed + 0.1, Config.RunBlendStart)
			risesOver(Config.RunBlendEnd, SurvivalConfig.SprintWalkSpeed)
		end)
	end)

	describe("footSkate", function()
		it("is nil at a standstill", function()
			expect(Config.footSkate(0)).to.equal(0)
		end)

		it("is nil while sprinting, where the run clip has the stride for it", function()
			expect(Config.footSkate(SurvivalConfig.SprintWalkSpeed)).to.be.near(0)
		end)

		it("stays under a fifth at walking speed", function()
			-- The deliberate compromise: the walk clip is held back to ~1.6x so
			-- it still reads as a walk, and the slide is the price. Past about a
			-- fifth it stops being subtle and starts looking like ice.
			expect(Config.footSkate(SurvivalConfig.BaseWalkSpeed) < 0.2).to.equal(true)
		end)

		it("is nil at the slow end, where the walk clip is exact", function()
			expect(Config.footSkate(Config.WalkClipSpeed)).to.be.near(0)
		end)

		it("is nil across every speed a sprint actually holds", function()
			-- Sprinting is the most visible gait and the run clip has the stride
			-- to cover all of it, so there is no excuse for sliding here.
			local from = SurvivalConfig.walkSpeedFor(0, true)
			for speed = from, SurvivalConfig.SprintWalkSpeed, 0.25 do
				expect(Config.footSkate(speed)).to.be.near(0)
			end
		end)

		it("stays subtle across every speed a walk actually holds", function()
			for speed = SurvivalConfig.walkSpeedFor(0, false), SurvivalConfig.BaseWalkSpeed, 0.25 do
				expect(Config.footSkate(speed) < 0.2).to.equal(true)
			end
		end)

		it("never gets away from us, even mid-transition", function()
			-- The worst point is just past RunBlendStart, where the walk clip is
			-- pinned at its cap and the run clip has not started helping yet.
			for speed = 0, SurvivalConfig.SprintWalkSpeed, 0.25 do
				expect(Config.footSkate(speed) < 0.25).to.equal(true)
			end
		end)
	end)

	describe("stepFrequency", function()
		it("takes more steps per second sprinting than walking", function()
			local walking = Config.stepFrequency(SurvivalConfig.BaseWalkSpeed)
			local sprinting = Config.stepFrequency(SurvivalConfig.SprintWalkSpeed)
			expect(sprinting > walking).to.equal(true)
		end)

		it("keeps the walking gait off the top of the clip's range", function()
			-- Above roughly 5.5 steps/sec the walk clip stops reading as walking
			-- however good the animation is, which is what MaxWalkRate guards.
			expect(Config.stepFrequency(SurvivalConfig.BaseWalkSpeed) < 5.5).to.equal(true)
		end)
	end)

	describe("the animation set", function()
		it("has a walk and a run, since the blend needs both", function()
			expect(Config.Animations.walk).to.be.ok()
			expect(Config.Animations.run).to.be.ok()
		end)

		it("points every entry at a real asset", function()
			for name, id in pairs(Config.Animations) do
				expect(type(id) == "string").to.equal(true)
				if not string.match(id, "^rbxassetid://%d+$") then
					error(string.format("%s is not an rbxassetid: %s", name, id))
				end
			end
		end)
	end)
end
