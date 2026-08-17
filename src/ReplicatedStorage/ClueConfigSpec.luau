-- The clue hunt is authored content as well as code. These tests keep a typo,
-- duplicate marker id, or casual tuning change from creating an unreachable
-- round or teaching the client a different contract from the server.

return function()
	-- TestEZ applies its DSL to this function's environment rather than to the
	-- module, so the names only exist once we are inside it. Pulling them into
	-- locals here keeps luau-lsp from reading them as undefined globals.
	local env = getfenv()
	local describe = env.describe
	local it = env.it
	local expect = env.expect

	local Config = require(script.Parent.ClueConfig)
	local validKinds = {
		Note = true,
		Cipher = true,
		Lever = true,
		Search = true,
		Carry = true,
	}

	describe("the clue content", function()
		--[[
			Site ids join authored riddles to invisible world markers. A duplicate
			would make the selected destination depend on discovery order, while an
			empty riddle would advance the chain without telling players where to go.
		]]
		it("defines fourteen unique, non-empty sites with one Act II terminus", function()
			local seen = {}
			local actOneCount = 0
			for _, site in Config.Sites do
				expect(seen[site.id] == nil).to.equal(true)
				expect(string.match(site.riddle, "%S") ~= nil).to.equal(true)
				seen[site.id] = true
				if site.actOne then
					actOneCount += 1
				end
			end

			expect(#Config.Sites).to.equal(14)
			expect(actOneCount).to.equal(13)
			local vault = Config.findSite("VaultFacade")
			expect(vault ~= nil and vault.actOne == false).to.equal(true)
		end)

		it("stores cipher answers in their canonical form", function()
			for _, cipher in Config.Ciphers do
				expect(Config.normaliseAnswer(cipher.answer)).to.equal(cipher.answer)
			end
		end)

		it("gives every site a valid, duplicate-free compatibility profile", function()
			for _, site in Config.Sites do
				expect(#site.allowedKinds > 0).to.equal(true)
				local seenKinds = {}
				for _, kind in site.allowedKinds do
					expect(validKinds[kind] == true).to.equal(true)
					expect(seenKinds[kind] == nil).to.equal(true)
					expect(Config.siteAllowsKind(site.id, kind)).to.equal(true)
					seenKinds[kind] = true
				end
			end
			expect(Config.siteAllowsKind("NotARealSite", "Note")).to.equal(false)
		end)

		it("reserves large props for landmarks that can actually contain them", function()
			for _, site in Config.Sites do
				if site.id == "StorageBreaker" then
					expect(#site.allowedKinds).to.equal(1)
					expect(site.allowedKinds[1]).to.equal("Lever")
				else
					expect(Config.siteAllowsKind(site.id, "Lever")).to.equal(false)
				end
			end

			local searchSites = {
				Room2Bed = true,
				RestaurantBuffet = true,
				BallroomStage = true,
			}
			for _, site in Config.Sites do
				expect(Config.siteAllowsKind(site.id, "Search")).to.equal(searchSites[site.id] == true)
			end
		end)
	end)

	describe("answer grading", function()
		it("ignores case and whitespace", function()
			expect(Config.answerMatches("  PreSiDenTial\t", "presidential")).to.equal(true)
			expect(Config.answerMatches("presi den tial", "presidential")).to.equal(true)
		end)

		it("accepts English number words in place of digits", function()
			expect(Config.answerMatches(" three ", "3")).to.equal(true)
			expect(Config.answerMatches("TEN", "10")).to.equal(true)
			expect(Config.answerMatches("twelve", "12")).to.equal(true)
		end)

		it("still rejects a genuinely different answer", function()
			expect(Config.answerMatches("five", "3")).to.equal(false)
		end)
	end)

	describe("replicated progress helpers", function()
		it("masks zero, some, or all sequential digits", function()
			expect(Config.maskedDigits("41789", 0)).to.equal("_____")
			expect(Config.maskedDigits("41789", 2)).to.equal("41___")
			expect(Config.maskedDigits("41789", 5)).to.equal("41789")
		end)

		it("can represent individually revealed digits", function()
			expect(Config.maskedDigits("41789", { true, false, true, false, false })).to.equal("4_7__")
		end)

		it("never reports a negative cooldown", function()
			expect(Config.remaining(100, 90)).to.equal(0)
			expect(Config.remaining(100, 106)).to.equal(6)
		end)
	end)

	describe("the authored tuning", function()
		it("pins the five-node hunt and breaker composition", function()
			expect(Config.ChainLength).to.equal(5)
			expect(Config.LeverCount).to.equal(6)
			expect(Config.LeverRequired).to.equal(3)
			expect(Config.LeverLockoutSeconds).to.equal(6)
		end)

		it("makes mistakes louder than successful solves", function()
			expect(Config.NoiseRadiusSolve).to.equal(45)
			expect(Config.NoiseRadiusWrong).to.equal(80)
			expect(Config.NoiseRadiusWrong > Config.NoiseRadiusSolve).to.equal(true)
		end)

		it("uses the intended interaction and escape windows", function()
			expect(Config.InteractionDistance).to.equal(12)
			expect(Config.WrongAnswerCooldown).to.equal(6)
			expect(Config.EscapeWindowSeconds).to.equal(120)
		end)
	end)
end
