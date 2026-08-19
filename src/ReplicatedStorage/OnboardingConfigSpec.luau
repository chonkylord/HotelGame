-- Covers the two things in OnboardingConfig that are decisions rather than
-- names: which stages count as "still in the intro", and what happens to a
-- stage nobody recognises.
--
-- isIntroStage is read by four unrelated systems — the grade, the fixtures, the
-- ambience, and Joel's single huntability gate — so the direction it fails in
-- is a gameplay decision and not a detail. Getting it backwards makes a player
-- the server has not classified yet permanently invisible to Joel, which is
-- silent, survives a playtest, and is exactly what these tests pin down.

return function()
	-- TestEZ applies its DSL to this function's environment rather than to the
	-- module, so the names only exist once we are inside it. Pulling them into
	-- locals here keeps luau-lsp from reading them as undefined globals.
	local env = getfenv()
	local describe = env.describe
	local it = env.it
	local expect = env.expect

	local Config = require(script.Parent.OnboardingConfig)

	describe("isIntroStage", function()
		it("claims every stage the first stay passes through", function()
			expect(Config.isIntroStage(Config.TALK_TO_NOEL)).to.equal(true)
			expect(Config.isIntroStage(Config.ENTER_ELEVATOR)).to.equal(true)
			expect(Config.isIntroStage(Config.ENTER_ROOM)).to.equal(true)
			expect(Config.isIntroStage(Config.SEALED)).to.equal(true)
		end)

		it("lets go the moment the notice is over", function()
			expect(Config.isIntroStage(Config.COMPLETE)).to.equal(false)
		end)

		--[[
			The failure direction, stated as a test because it is invisible in
			play. An unset attribute has to read as NOT the intro: a player the
			server never classified is then huntable and sees the normal hotel,
			where the other reading leaves them un-hunted for the whole round with
			nothing on screen to say why.
		]]
		it("treats an unclassified player as out of the intro, not in it", function()
			expect(Config.isIntroStage(nil)).to.equal(false)
			expect(Config.isIntroStage("")).to.equal(false)
			expect(Config.isIntroStage("Whatever")).to.equal(false)
			expect(Config.isIntroStage(3)).to.equal(false)
			expect(Config.isIntroStage(true)).to.equal(false)
		end)
	end)

	--[[
		objectiveFor decides what the case ledger writes on its OBJECTIVE page and
		what it pins to the ribbon beside its button, and the ledger tells the two
		apart by exactly one thing: whether this returns nil. A stage that answers
		with a line is the intro still asking the question, and the ribbon stays
		pinned so a first-time player who has not found the button yet can still
		read what to do. nil hands the question to the clue phase.

		So the boundary below is not cosmetic — a stray line on SEALED or COMPLETE
		would pin the ribbon open for the rest of the round, which is the failure
		this whole rework exists to remove.
	]]
	describe("objectiveFor", function()
		it("gives a line for each stage the player is being steered through", function()
			expect(Config.objectiveFor(Config.TALK_TO_NOEL)).to.equal("Talk to Noel")
			expect(Config.objectiveFor(Config.ENTER_ELEVATOR)).to.equal("Enter the elevator")
			expect(Config.objectiveFor(Config.ENTER_ROOM)).to.equal("Enter your room")
		end)

		it("goes quiet once the steering is done", function()
			-- SEALED is still an intro stage, but the player is locked in a room
			-- being told a story; there is nothing to walk toward.
			expect(Config.objectiveFor(Config.SEALED)).to.equal(nil)
			expect(Config.objectiveFor(Config.COMPLETE)).to.equal(nil)
		end)

		it("says nothing for a stage it does not recognise", function()
			expect(Config.objectiveFor(nil)).to.equal(nil)
			expect(Config.objectiveFor("")).to.equal(nil)
			expect(Config.objectiveFor("Whatever")).to.equal(nil)
			expect(Config.objectiveFor(7)).to.equal(nil)
		end)

		--[[
			Every stage that gets an arrow drawn on the floor must also get words.
			OnboardingClient picks its highlight target from the stage and the
			ledger picks the text from the same stage; a stage with one and not the
			other is an arrow pointing at something the player was never told to
			look for.
		]]
		it("covers every stage that OnboardingClient draws a target for", function()
			for _, stage in { Config.TALK_TO_NOEL, Config.ENTER_ELEVATOR, Config.ENTER_ROOM } do
				expect(type(Config.objectiveFor(stage))).to.equal("string")
			end
		end)
	end)

	describe("the sealed-room beat", function()
		-- The server sleeps CARD_TOTAL and then flips the player to Complete,
		-- while the client animates the three parts separately. If they stop
		-- agreeing, the lights change while the notice is still on screen.
		it("gives the server the same total the client draws", function()
			expect(Config.CARD_TOTAL).to.be.near(Config.CARD_FADE_IN + Config.CARD_HOLD + Config.CARD_FADE_OUT)
		end)

		it("holds the door long enough to be a beat and not a stutter", function()
			expect(Config.SEAL_SECONDS >= 5).to.equal(true)
		end)

		it("reads the notice before turning the hotel over", function()
			-- Both are non-zero, so "fades in, is read, fades out" is a sequence
			-- rather than a cut.
			expect(Config.CARD_FADE_IN > 0).to.equal(true)
			expect(Config.CARD_HOLD > 0).to.equal(true)
			expect(Config.CARD_FADE_OUT > 0).to.equal(true)
		end)
	end)
end
