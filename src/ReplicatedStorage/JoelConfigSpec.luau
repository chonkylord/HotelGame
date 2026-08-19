-- Covers Joel's tuning.
--
-- As with LocomotionConfigSpec, the tests that genuinely earn their keep are the
-- cross-module ones. Joel's whole design rests on a promise — that he is always
-- faster than the player he is chasing — and JoelConfig cannot verify that on
-- its own, because the player's speed lives in SurvivalConfig and is tuned for
-- survival reasons by somebody with no cause to think about Joel. Doubling
-- SprintWalkSpeed for a balance pass would quietly make him outrunnable and
-- nothing else in the codebase would notice.

return function()
	-- TestEZ applies its DSL to this function's environment rather than to the
	-- module, so the names only exist once we are inside it. Pulling them into
	-- locals here keeps luau-lsp from reading them as undefined globals.
	local env = getfenv()
	local describe = env.describe
	local it = env.it
	local expect = env.expect

	local Config = require(script.Parent.JoelConfig)
	local ClueConfig = require(script.Parent.ClueConfig)
	local HorrorZones = require(script.Parent.HorrorZones)
	local SurvivalConfig = require(script.Parent.SurvivalConfig)

	describe("the speed promise against the player's real speeds", function()
		--[[
			The load-bearing one. Every state the survival system can put a
			player in has to leave Joel faster, or "you cannot outrun him"
			becomes a lie and the whole chase design changes character.
		]]
		it("beats every player speed the survival system can produce", function()
			for hunger = 0, SurvivalConfig.MaxHunger, 5 do
				for _, sprinting in ipairs({ false, true }) do
					local playerSpeed = SurvivalConfig.walkSpeedFor(hunger, sprinting)
					local joelSpeed = Config.speedFor(playerSpeed, false)
					expect(joelSpeed > playerSpeed).to.equal(true)
				end
			end
		end)

		it("beats a fed sprinter by exactly the advantage", function()
			local sprinter = SurvivalConfig.walkSpeedFor(SurvivalConfig.MaxHunger, true)
			expect(Config.speedFor(sprinter, false)).to.equal(sprinter + Config.SpeedAdvantage)
		end)

		it("adds the burst on top of the advantage", function()
			local walker = SurvivalConfig.walkSpeedFor(SurvivalConfig.MaxHunger, false)
			local cruise = Config.speedFor(walker, false)
			expect(Config.speedFor(walker, true)).to.equal(cruise + Config.SprintBonus)
		end)

		it("still moves when it has nobody to chase", function()
			expect(Config.speedFor(nil, false) > 0).to.equal(true)
		end)

		it("accelerates toward chase speed instead of snapping to it", function()
			local goal = 28
			local afterOneFrame = Config.approachSpeed(Config.ProwlSpeed, goal, 1 / 60)
			expect(afterOneFrame > Config.ProwlSpeed).to.equal(true)
			expect(afterOneFrame < goal).to.equal(true)
		end)

		it("never overshoots while accelerating or slowing down", function()
			expect(Config.approachSpeed(27.9, 28, 1)).to.equal(28)
			expect(Config.approachSpeed(8.1, 8, 1)).to.equal(8)
		end)
	end)

	describe("the sprint cycle", function()
		it("is on for SprintDuration and off for the rest of the period", function()
			expect(Config.isSprinting(0)).to.equal(true)
			expect(Config.isSprinting(Config.SprintDuration - 0.01)).to.equal(true)
			expect(Config.isSprinting(Config.SprintDuration + 0.01)).to.equal(false)
			expect(Config.isSprinting(Config.SprintPeriod - 0.01)).to.equal(false)
		end)

		it("repeats on the period", function()
			expect(Config.isSprinting(Config.SprintPeriod)).to.equal(true)
			expect(Config.isSprinting(Config.SprintPeriod * 7)).to.equal(true)
		end)

		--[[
			There has to be a gap. A burst with no recovery is just a higher
			constant speed with extra steps, and the moment of "he dropped
			back — I might make it" is the only rhythm the chase has.
		]]
		it("leaves a recovery gap", function()
			expect(Config.SprintDuration < Config.SprintPeriod).to.equal(true)
		end)
	end)

	describe("interception", function()
		--[[
			The anti-juke property, stated as a test: against a target moving
			across him, he must aim somewhere other than where they are. An
			implementation that returned targetPosition here is a tail-chaser
			and can be circle-strafed forever.
		]]
		it("leads a moving target", function()
			local joel = Vector3.new(0, 0, 0)
			local target = Vector3.new(30, 0, 0)
			local velocity = Vector3.new(0, 0, 20)
			local aim = Config.interceptPoint(joel, target, velocity, 20)
			expect(aim.Z > target.Z).to.equal(true)
		end)

		it("does not lead a target who is barely moving", function()
			local target = Vector3.new(30, 0, 0)
			local crawl = Vector3.new(0, 0, Config.MinLeadSpeed - 0.1)
			local aim = Config.interceptPoint(Vector3.new(0, 0, 0), target, crawl, 20)
			expect(aim).to.equal(target)
		end)

		--[[
			Extrapolating a Roblox character more than about a second out is
			fiction — they will have turned or hit a wall — and an NPC aiming at
			that fiction walks into the wall you are about to turn along. So the
			lead is capped no matter how far away he is.
		]]
		it("caps the lead however distant the target", function()
			local speed = 20
			local velocity = Vector3.new(0, 0, 10)
			local target = Vector3.new(5000, 0, 0)
			local aim = Config.interceptPoint(Vector3.new(0, 0, 0), target, velocity, speed)
			local led = (aim - target).Magnitude
			expect(led <= velocity.Magnitude * Config.MaxLeadSeconds + 1e-6).to.equal(true)
		end)

		it("ignores vertical velocity, so a jumping target is not aimed at the ceiling", function()
			local target = Vector3.new(30, 0, 0)
			local jumping = Vector3.new(0, 50, 0)
			local aim = Config.interceptPoint(Vector3.new(0, 0, 0), target, jumping, 20)
			expect(aim.Y).to.equal(target.Y)
		end)
	end)

	describe("perception", function()
		--[[
			He has to notice you before he can catch you. If the catch radius
			ever grew past the range at which he registers you at all, players
			would die to something that had not reacted to them yet.
		]]
		it("notices further than it catches", function()
			expect(Config.noticeRange(false) > Config.CatchRadius).to.equal(true)
			expect(Config.SightRange > Config.CatchRadius).to.equal(true)
		end)

		it("hears a sprinter from further than a walker", function()
			expect(Config.noticeRange(true) > Config.noticeRange(false)).to.equal(true)
		end)

		it("uses the requested four-stud attack AOE", function()
			expect(Config.CatchRadius).to.equal(4)
		end)

		it("updates hearing less often than vision", function()
			expect(Config.HearingUpdateInterval > Config.PerceptionInterval).to.equal(true)
		end)
	end)

	describe("two-strike rescue catches", function()
		it("keeps contact catches enabled", function()
			expect(Config.ContactDamageEnabled).to.equal(true)
		end)

		it("only hunts players whom RescueController marks healthy", function()
			expect(Config.canTargetRescueState(Config.RescueHealthyState)).to.equal(true)
			expect(Config.canTargetRescueState("Downed")).to.equal(false)
			expect(Config.canTargetRescueState(Config.RescueDraggingState)).to.equal(false)
			expect(Config.canTargetRescueState(nil)).to.equal(false)
		end)

		it("uses an ordinary upright walking speed during a drag", function()
			expect(Config.DragSpeed).to.equal(SurvivalConfig.BaseWalkSpeed)
		end)

		it("requires controller drop points to stay on Joel's current floor", function()
			expect(Config.isSameFloorDrop(Vector3.new(215, 36, 10), Vector3.new(250, 32.7, -5))).to.equal(true)
			expect(Config.isSameFloorDrop(Vector3.new(215, 36, 10), Vector3.new(250, 22, -5))).to.equal(false)
			expect(Config.isSameFloorDrop(Vector3.new(560, 37, 20), Vector3.new(560, 33.7, -5))).to.equal(true)
			expect(Config.isSameFloorDrop(Vector3.new(560, 37, 20), Vector3.new(250, 32.7, -5))).to.equal(false)
		end)

		it("bounds an unreachable drag instead of leaving a player stuck forever", function()
			expect(Config.DragArrivalRadius > 0).to.equal(true)
			expect(Config.DragPathFailureSeconds > 0).to.equal(true)
			expect(Config.DragTimeoutSeconds > Config.DragPathFailureSeconds).to.equal(true)
			expect(Config.hasReachedDragDrop(Vector3.zero, Vector3.new(Config.DragArrivalRadius, 0, 0))).to.equal(true)
			expect(Config.hasReachedDragDrop(Vector3.zero, Vector3.new(Config.DragArrivalRadius + 0.01, 0, 0))).to.equal(
				false
			)
			expect(Config.dragTimedOut(10, 10 + Config.DragTimeoutSeconds - 0.01)).to.equal(false)
			expect(Config.dragTimedOut(10, 10 + Config.DragTimeoutSeconds)).to.equal(true)
			expect(Config.dragFailureExpired(20, 20 + Config.DragPathFailureSeconds - 0.01)).to.equal(false)
			expect(Config.dragFailureExpired(20, 20 + Config.DragPathFailureSeconds)).to.equal(true)
		end)
	end)

	describe("floor bands", function()
		--[[
			Measured off the real geometry: the guest rooms sit at Y 17.5..33
			and the amenities floor above them at Y 32.6..52, with the lobby off
			on its own in X. Only used to pick a destination — whether he can
			actually walk there is always decided by the pathfinder.
		]]
		it("separates the amenities floor from the rooms below it", function()
			expect(Config.floorOf(Vector3.new(215, 36, 10))).to.equal("Amenities")
			expect(Config.floorOf(Vector3.new(260, 22, -30))).to.equal("Rooms")
		end)

		it("keeps the elevator-separated suite out of amenities", function()
			expect(Config.floorOf(Vector3.new(613, 42, 0))).to.equal("Suite")
			expect(Config.floorOf(Vector3.new(Config.SuiteSplitX, 36, 0))).to.equal("Suite")
			expect(Config.floorOf(Vector3.new(Config.SuiteSplitX - 1, 36, 0))).to.equal("Amenities")
		end)

		it("puts the lobby on its own", function()
			expect(Config.floorOf(Vector3.new(-99, 26, 152))).to.equal("Lobby")
		end)

		--[[
			The vault is the one band that is not a number in JoelConfig, so these
			read its volume back from HorrorZones rather than restating world
			coordinates. The whole reason it stopped being a depth test is that the
			chamber is now a model somebody can drag around in Studio; a spec with
			960 written into it would go red the first time it moved, which is the
			exact failure being fixed.

			`vaultVolume()` returning nil is a real state — a place whose chamber
			and anchor have not replicated — and the documented answer there is
			that nothing is the vault and the ordinary bands still work, so it is
			asserted rather than skipped.
		]]
		it("classifies the vault by its footprint rather than by depth", function()
			local vault = HorrorZones.vaultVolume()
			if not vault then
				expect(Config.floorOf(Vector3.new(960, 36, 10))).to.equal("Suite")
				return
			end
			expect(Config.floorOf(vault.cframe.Position)).to.equal("Vault")
			-- One full chamber-width off its flank is clear of it whichever way the
			-- chamber has been turned, which an axis-aligned offset would not be.
			local beside = (vault.cframe * CFrame.new(vault.size.X, 0, 0)).Position
			expect(Config.floorOf(beside) == "Vault").to.equal(false)
		end)

		--[[
			The regression this change introduces, on its own.

			The chamber's floor is at Y 19 and its ceiling at Y 52, against guest
			rooms at 17.5..33 and the amenities floor at 32.6..52. Standing height
			in the strongroom is no longer distinguishable by Y from standing height
			in the hotel, and the chamber sits past SuiteSplitX besides — so a
			classifier that consults any band before it consults the footprint hands
			back "Suite" for a player stood in front of the vault door.
		]]
		it("calls a standing height inside the footprint the vault, not a hotel floor", function()
			local vault = HorrorZones.vaultVolume()
			if not vault then
				expect(Config.floorOf(Vector3.new(960, 36, 10))).to.equal("Suite")
				return
			end
			-- Four studs above the chamber's own floor: where a player actually is.
			local standHeight = -vault.size.Y / 2 + 4
			local standing = (vault.cframe * CFrame.new(0, standHeight, 0)).Position
			expect(Config.floorOf(standing)).to.equal("Vault")
			-- The same height, one chamber-width to the side, is a hotel band. That
			-- pair is the whole statement: height stopped deciding this, place does.
			local outside = (vault.cframe * CFrame.new(vault.size.X, standHeight, 0)).Position
			expect(Config.floorOf(outside) == "Vault").to.equal(false)
		end)

		--[[
			The other half of the old test being wrong. `position.Y < -80` claimed
			the whole void under the map, so a player who clipped through a floor
			was classified as being in the treasury the entire way down.
		]]
		it("no longer answers Vault for anything that merely falls below the map", function()
			expect(Config.floorOf(Vector3.new(960, -137, 0)) == "Vault").to.equal(false)
			expect(Config.floorOf(Vector3.new(0, -500, 0)) == "Vault").to.equal(false)
		end)

		it("leaves the hotel's own bands alone", function()
			expect(Config.floorOf(Vector3.new(215, 36, 10))).to.equal("Amenities")
			expect(Config.floorOf(Vector3.new(260, 22, -30))).to.equal("Rooms")
			expect(Config.floorOf(Vector3.new(-99, 26, 152))).to.equal("Lobby")
			expect(Config.floorOf(Vector3.new(613, 42, 0))).to.equal("Suite")
		end)
	end)

	describe("the hunt and rest cycle", function()
		local length = Config.cycleLength()

		it("is the two windows and nothing else", function()
			expect(length).to.equal(Config.HuntWindowSeconds + Config.RestWindowSeconds)
			expect(Config.HuntWindowSeconds > 0).to.equal(true)
			expect(Config.RestWindowSeconds > 0).to.equal(true)
		end)

		it("opens on a full hunt window", function()
			local phase, remaining = Config.cycleAt(0)
			expect(phase).to.equal(Config.PhaseHunt)
			expect(remaining).to.equal(Config.HuntWindowSeconds)
		end)

		it("hunts right up to the boundary and rests on it", function()
			local lastPhase = Config.cycleAt(Config.HuntWindowSeconds - 0.01)
			expect(lastPhase).to.equal(Config.PhaseHunt)

			local phase, remaining = Config.cycleAt(Config.HuntWindowSeconds)
			expect(phase).to.equal(Config.PhaseRest)
			expect(remaining).to.equal(Config.RestWindowSeconds)
		end)

		it("repeats without drifting", function()
			for cycle = 0, 40 do
				local base = cycle * length
				local phase, remaining = Config.cycleAt(base + 3)
				expect(phase).to.equal(Config.PhaseHunt)
				expect(remaining).to.equal(Config.HuntWindowSeconds - 3)

				local restPhase, restRemaining = Config.cycleAt(base + Config.HuntWindowSeconds + 3)
				expect(restPhase).to.equal(Config.PhaseRest)
				expect(restRemaining).to.equal(Config.RestWindowSeconds - 3)
			end
		end)

		--[[
			The plaque renders whatever comes back here, so a remaining that goes
			negative or past its own window is a visible lie on every screen in
			the server rather than a quiet arithmetic slip.
		]]
		it("never reports a countdown outside the window it names", function()
			for step = -400, 2400 do
				local elapsed = step * 0.37
				local phase, remaining = Config.cycleAt(elapsed)
				local window = if phase == Config.PhaseHunt then Config.HuntWindowSeconds else Config.RestWindowSeconds
				expect(remaining > 0).to.equal(true)
				expect(remaining <= window).to.equal(true)
			end
		end)

		--[[
			The cross-module one. A stand-down shorter than Joel's memory would not
			break a chase, it would postpone one: he would forget you at second 12,
			be handed his eyes back at second 15, and still be standing outside the
			door you ran through. Fifteen against twelve is the margin that makes
			the window worth spending, and LoseInterestSeconds is tuned by whoever
			is thinking about pursuit, not about the round's pulse.
		]]
		it("stands down for longer than Joel remembers you", function()
			expect(Config.RestWindowSeconds > Config.LoseInterestSeconds).to.equal(true)
		end)

		--[[
			Direction, not just ratio. Swapping the two numbers still gives a
			cycle that ticks over correctly and reads fine on the plaque, and it
			quietly restores the design this replaced: if safety is the long
			window, waiting it out is the correct play again.
		]]
		it("leaves more of the round dangerous than safe", function()
			expect(Config.HuntWindowSeconds > Config.RestWindowSeconds).to.equal(true)
			expect(Config.HuntWindowSeconds >= Config.RestWindowSeconds * 3).to.equal(true)
		end)

		--[[
			The plaque ceils the remaining seconds, so a window of 300.5 would show
			05:01 for half a second and then 05:00 for a second and a half. Whole
			seconds keep every tick the same length.
		]]
		it("is authored in whole seconds, which is what the plaque counts", function()
			expect(Config.HuntWindowSeconds % 1).to.equal(0)
			expect(Config.RestWindowSeconds % 1).to.equal(0)
		end)

		--[[
			The stand-down is the window players plan an errand around, so it has
			to be long enough to spend on one. A starving walker — the slowest the
			survival system can make anybody — has to be able to cross the guest
			wing and back inside it, or the safe window is only safe for whoever
			was already standing where they needed to be.
		]]
		it("is long enough for the slowest player to actually go somewhere", function()
			local crawl = SurvivalConfig.walkSpeedFor(0, false)
			local wingDiagonal = math.sqrt(134 * 134 + 169 * 169)
			expect(crawl * Config.RestWindowSeconds > wingDiagonal * 2).to.equal(true)
		end)
	end)

	describe("the Sunstone interruption", function()
		it("matches the authored escape window", function()
			expect(Config.DownedSeconds).to.equal(ClueConfig.EscapeWindowSeconds)
			expect(Config.DownedSeconds > ClueConfig.EscapeWindowSeconds).to.equal(false)
		end)

		it("requires a deliberate close-range hold", function()
			expect(Config.DefeatRange > Config.CatchRadius).to.equal(true)
			expect(Config.DefeatHoldSeconds > 0).to.equal(true)
			expect(Config.NoiseInvestigateWeight > 0).to.equal(true)
		end)
	end)
end
