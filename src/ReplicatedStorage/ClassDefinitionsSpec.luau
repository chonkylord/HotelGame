return function()
	-- TestEZ applies its DSL to this function's environment rather than to the
	-- module, so the names only exist once we are inside it. Pulling them into
	-- locals here keeps luau-lsp from reading them as undefined globals.
	local env = getfenv()
	local describe = env.describe
	local it = env.it
	local expect = env.expect

	-- Clone for a fresh require identity: Studio can retain the old return value
	-- after ClassDefinitions source syncs while the TestEZ plugin stays loaded.
	local configModule = script.Parent.ClassDefinitions:Clone()
	configModule:SetAttribute("bl_id", nil)
	configModule.Parent = script
	local ClassDefinitions = require(configModule)
	configModule:Destroy()

	describe("class entitlements", function()
		it("overlays every playable class without replacing the selection", function()
			local subject = Instance.new("Folder")
			subject:SetAttribute(ClassDefinitions.ATTRIBUTE, ClassDefinitions.HACKER)

			expect(ClassDefinitions.ADMIN_ALL_CLASSES_ATTRIBUTE).to.equal("AdminAllClasses")
			expect(ClassDefinitions.hasClass(subject, ClassDefinitions.HACKER)).to.equal(true)
			expect(ClassDefinitions.hasClass(subject, ClassDefinitions.MUSCLE)).to.equal(false)
			expect(ClassDefinitions.hasClass(subject, ClassDefinitions.SUPERMAN)).to.equal(false)

			subject:SetAttribute(ClassDefinitions.ADMIN_ALL_CLASSES_ATTRIBUTE, true)
			expect(ClassDefinitions.hasClass(subject, ClassDefinitions.HACKER)).to.equal(true)
			expect(ClassDefinitions.hasClass(subject, ClassDefinitions.MUSCLE)).to.equal(true)
			expect(ClassDefinitions.hasClass(subject, ClassDefinitions.SUPERMAN)).to.equal(true)
			expect(ClassDefinitions.hasClass(subject, "SuperHero")).to.equal(true)
			expect(subject:GetAttribute(ClassDefinitions.ATTRIBUTE)).to.equal(ClassDefinitions.HACKER)

			subject:SetAttribute(ClassDefinitions.ADMIN_ALL_CLASSES_ATTRIBUTE, false)
			expect(ClassDefinitions.hasClass(subject, ClassDefinitions.HACKER)).to.equal(true)
			expect(ClassDefinitions.hasClass(subject, ClassDefinitions.MUSCLE)).to.equal(false)
			expect(ClassDefinitions.hasClass(subject, ClassDefinitions.SUPERMAN)).to.equal(false)
			expect(subject:GetAttribute(ClassDefinitions.ATTRIBUTE)).to.equal(ClassDefinitions.HACKER)
			subject:Destroy()
		end)
	end)
end
