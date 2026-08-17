--!strict

return function()
	local env = getfenv()
	local describe = env.describe
	local it = env.it
	local expect = env.expect

	-- TestEZ runs inside a persistent Studio plugin VM, where a ModuleScript
	-- required by an earlier test can remain cached after its source syncs.
	-- A clone has a fresh require identity and exercises the current source.
	local configModule = script.Parent.ClassDefinitions:Clone()
	configModule:SetAttribute("bl_id", nil)
	configModule.Parent = script
	local requireFresh = require :: any
	local ClassConfig = requireFresh(configModule)
	configModule:Destroy()

	describe("Door smash permissions", function()
		it("lets Muscle force only broken and jammed doors", function()
			expect(ClassConfig.SmashableStates.Broken).to.equal(true)
			expect(ClassConfig.SmashableStates.Jammed).to.equal(true)
			expect(ClassConfig.SmashableStates.Normal).to.equal(false)
			expect(ClassConfig.SmashableStates.Smashed).to.equal(false)

			local enabled = 0
			for _, canSmash in ClassConfig.SmashableStates do
				if canSmash then
					enabled += 1
				end
			end
			expect(enabled).to.equal(2)
		end)
	end)
end
