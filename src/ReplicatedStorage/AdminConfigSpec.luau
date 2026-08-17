return function()
	local env = getfenv()
	local describe = env.describe
	local it = env.it
	local expect = env.expect

	local AdminConfig = require(script.Parent.AdminConfig)

	describe("admin authorization", function()
		it("allows only the two configured account names, case-insensitively", function()
			expect(AdminConfig.isAuthorizedUsername("lordadudes")).to.equal(true)
			expect(AdminConfig.isAuthorizedUsername("LORDADUDES")).to.equal(true)
			expect(AdminConfig.isAuthorizedUsername("Kakusa3000")).to.equal(true)
			expect(AdminConfig.isAuthorizedUsername("lordadudes2")).to.equal(false)
			expect(AdminConfig.isAuthorizedUsername("kakusa3000 ")).to.equal(false)
			expect(AdminConfig.isAuthorizedUsername("Display Name")).to.equal(false)
		end)
	end)

	describe("admin features", function()
		it("exposes exactly the three server-controlled toggles", function()
			local invincibility = assert(AdminConfig.findFeature("invincibility"))
			local allClasses = assert(AdminConfig.findFeature("allClasses"))
			local infiniteSprint = assert(AdminConfig.findFeature("infiniteSprint"))

			expect(#AdminConfig.Features).to.equal(3)
			expect(invincibility.attribute).to.equal("AdminInvincible")
			expect(allClasses.attribute).to.equal("AdminAllClasses")
			expect(infiniteSprint.attribute).to.equal("AdminInfiniteSprint")
			expect(AdminConfig.findFeature("unknown")).to.equal(nil)
		end)
	end)
end
