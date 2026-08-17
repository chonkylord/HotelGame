-- Tests the sack's physics conversion without needing a player or remotes.

return function()
	local env = getfenv()
	local describe = env.describe
	local it = env.it
	local expect = env.expect

	local SackPhysics = require(script.Parent.SackPhysics)

	describe("makePhysical", function()
		it("turns an anchored model into one collision assembly", function()
			local model = Instance.new("Model")
			local first = Instance.new("Part")
			first.Anchored = true
			first.CanCollide = false
			first.Parent = model
			local second = Instance.new("Part")
			second.Anchored = true
			second.CanCollide = false
			second.Position = Vector3.new(1, 0, 0)
			second.Parent = model

			local body = SackPhysics.makePhysical(model)
			expect(body ~= nil).to.equal(true)
			if not body then
				model:Destroy()
				return
			end

			expect(first.Anchored).to.equal(false)
			expect(second.Anchored).to.equal(false)
			expect(first.CanCollide).to.equal(false)
			expect(second.CanCollide).to.equal(false)
			expect(body.CanCollide).to.equal(true)
			expect(body.CanQuery).to.equal(false)
			expect(#body:GetChildren()).to.equal(2)

			-- Re-bagging and dropping the same item reuses its body and welds.
			local again = SackPhysics.makePhysical(model)
			expect(again).to.equal(body)
			expect(#body:GetChildren()).to.equal(2)
			model:Destroy()
		end)

		it("uses a single part directly", function()
			local part = Instance.new("Part")
			part.Anchored = true
			part.CanCollide = false

			local body = SackPhysics.makePhysical(part)
			expect(body).to.equal(part)
			expect(part.Anchored).to.equal(false)
			expect(part.CanCollide).to.equal(true)
			part:Destroy()
		end)
	end)

	describe("freeze", function()
		it("anchors every part before vaulting an item", function()
			local model = Instance.new("Model")
			local first = Instance.new("Part")
			first.Anchored = false
			first.Parent = model
			local second = Instance.new("Part")
			second.Anchored = false
			second.Parent = model

			SackPhysics.freeze(model)
			expect(first.Anchored).to.equal(true)
			expect(second.Anchored).to.equal(true)
			model:Destroy()
		end)
	end)
end
