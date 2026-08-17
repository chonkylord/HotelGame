return function()
	local env = getfenv()
	local describe = env.describe
	local it = env.it
	local expect = env.expect

	local ClassClaimRegistry = require(script.Parent.ClassClaimRegistry)

	local function fakePlayer(name)
		local player = Instance.new("Folder")
		player.Name = name
		return player
	end

	describe("ClassClaimRegistry", function()
		it("locks a player to the first class they claim", function()
			local state = ClassClaimRegistry.new("None")
			local player = fakePlayer("PlayerA")
			ClassClaimRegistry.register(state, player)

			expect(ClassClaimRegistry.claim(state, player, "Hacker")).to.equal(true)
			expect(ClassClaimRegistry.claim(state, player, "Muscle")).to.equal(false)
			expect(ClassClaimRegistry.getClass(state, player)).to.equal("Hacker")
		end)

		it("locks a claimed class against every other player", function()
			local state = ClassClaimRegistry.new("None")
			local first = fakePlayer("PlayerA")
			local second = fakePlayer("PlayerB")
			ClassClaimRegistry.register(state, first)
			ClassClaimRegistry.register(state, second)

			expect(ClassClaimRegistry.claim(state, first, "Superman")).to.equal(true)
			expect(ClassClaimRegistry.claim(state, second, "Superman")).to.equal(false)
			expect(ClassClaimRegistry.getClass(state, second)).to.equal("None")
		end)

		it("releases the class only when its player leaves", function()
			local state = ClassClaimRegistry.new("None")
			local first = fakePlayer("PlayerA")
			local second = fakePlayer("PlayerB")
			ClassClaimRegistry.register(state, first)
			ClassClaimRegistry.register(state, second)
			ClassClaimRegistry.claim(state, first, "Muscle")

			ClassClaimRegistry.release(state, first)
			expect(ClassClaimRegistry.claim(state, second, "Muscle")).to.equal(true)
		end)
	end)
end
