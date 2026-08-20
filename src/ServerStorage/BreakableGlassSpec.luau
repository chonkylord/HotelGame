-- Tests the geometry a shatter depends on, without a mallet or a player.
--
-- Both things covered here are silent when they are wrong. A pane cut on the
-- wrong pair of axes still produces a cloud of parts that falls convincingly —
-- it is only side-on that you see the shards are thin in the wrong direction,
-- and the vitrines have panes on three different axes so two of the three would
-- still look right. And closestPoint is what both the swing and the server's
-- range re-check measure against: get the clamp wrong and a five-stud sheet of
-- glass is judged by where its middle is, which quietly puts one side of every
-- case out of reach.

return function()
	-- TestEZ applies its DSL to this function's environment rather than to the
	-- module, so the names only exist once we are inside it.
	local env = getfenv()
	local describe = env.describe
	local it = env.it
	local expect = env.expect

	local BreakableGlass = require(script.Parent.BreakableGlass)

	-- Shards are unanchored and land somewhere; a scratch folder well away from
	-- the hotel keeps a test run from raining glass on the lobby.
	local function scratch(): Folder
		local folder = Instance.new("Folder")
		folder.Name = "BreakableGlassSpecScratch"
		folder.Parent = workspace
		return folder
	end

	local function pane(size: Vector3, folder: Folder): Part
		local part = Instance.new("Part")
		part.Anchored = true
		part.Size = size
		part.CFrame = CFrame.new(0, 6000, 0)
		part.Transparency = 0.57
		part.Parent = folder
		return part
	end

	local function shards(): { BasePart }
		local folder = workspace:FindFirstChild("GlassShards")
		local found: { BasePart } = {}
		if folder then
			for _, child in folder:GetChildren() do
				if child:IsA("BasePart") then
					table.insert(found, child)
				end
			end
		end
		return found
	end

	local function clearShards()
		local folder = workspace:FindFirstChild("GlassShards")
		if folder then
			folder:ClearAllChildren()
		end
	end

	describe("closestPoint", function()
		it("clamps to the surface of a wide pane, not to its centre", function()
			local folder = scratch()
			-- A vitrine side: thin in X, five studs across in Z.
			local glass = pane(Vector3.new(0.2, 2.45, 5.35), folder)
			local offToOneSide = glass.Position + Vector3.new(3, 0, 2.5)

			local point = BreakableGlass.closestPoint(glass, offToOneSide)
			expect(point.X).to.be.near(glass.Position.X + 0.1)
			expect(point.Z).to.be.near(glass.Position.Z + 2.5)
			-- Measured to the edge it is 3 studs away; measured to the centre it
			-- would be 3.9, and the strike range check would disagree with what
			-- the player can see they are standing next to.
			expect((offToOneSide - point).Magnitude).to.be.near(2.9)

			folder:Destroy()
		end)

		it("returns a point inside the part for a point inside the part", function()
			local folder = scratch()
			local glass = pane(Vector3.new(4, 4, 4), folder)
			local inside = glass.Position + Vector3.new(1, -1, 0.5)
			local point = BreakableGlass.closestPoint(glass, inside)
			expect((point - inside).Magnitude).to.be.near(0)
			folder:Destroy()
		end)
	end)

	describe("shatterPane", function()
		it("keeps the pane's thickness on the pane's own thin axis", function()
			local folder = scratch()
			-- One of each orientation the four vitrines actually use.
			local cases = {
				{ size = Vector3.new(0.2, 2.45, 5.35), thin = "X" },
				{ size = Vector3.new(5.35, 0.2, 5.5), thin = "Y" },
				{ size = Vector3.new(5.35, 2.45, 0.2), thin = "Z" },
			}
			for _, entry in cases do
				clearShards()
				local glass = pane(entry.size, folder)
				BreakableGlass.shatterPane(glass, glass.Position, Vector3.new(0, 0, -1))
				local pieces = shards()
				expect(#pieces > 1).to.equal(true)
				for _, shard in pieces do
					local axis = if entry.thin == "X"
						then shard.Size.X
						elseif entry.thin == "Y" then shard.Size.Y
						else shard.Size.Z
					expect(axis).to.be.near(0.2)
					-- and the two face axes are cut down, not left whole
					expect(shard.Size.Magnitude < entry.size.Magnitude).to.equal(true)
				end
			end
			clearShards()
			folder:Destroy()
		end)

		it("covers the pane it came from", function()
			local folder = scratch()
			clearShards()
			local glass = pane(Vector3.new(0.2, 2.45, 5.35), folder)
			local origin = glass.Position
			BreakableGlass.shatterPane(glass, origin, Vector3.new(0, 0, -1))

			-- Every piece starts inside the volume the sheet occupied. A grid
			-- built off the wrong extents still makes shards, but they appear
			-- somewhere other than where the glass was.
			for _, shard in shards() do
				local offset = shard.Position - origin
				expect(math.abs(offset.Y) <= 2.45 / 2).to.equal(true)
				expect(math.abs(offset.Z) <= 5.35 / 2).to.equal(true)
			end

			clearShards()
			folder:Destroy()
		end)

		it("hides the sheet and stops it blocking the way in", function()
			local folder = scratch()
			clearShards()
			local glass = pane(Vector3.new(0.2, 2.45, 5.35), folder)
			BreakableGlass.shatterPane(glass, glass.Position, Vector3.new(0, 0, -1))

			-- Hidden rather than destroyed: the vitrines are authored parts
			-- saved in the place, and a server that deleted them would hand the
			-- next Studio session a treasury nobody edited.
			expect(glass.Parent).to.equal(folder)
			expect(glass.Transparency).to.equal(1)
			expect(glass.CanCollide).to.equal(false)
			expect(glass.CanQuery).to.equal(false)

			clearShards()
			folder:Destroy()
		end)

		it("cannot be broken twice", function()
			local folder = scratch()
			clearShards()
			local glass = pane(Vector3.new(0.2, 2.45, 5.35), folder)
			local first = BreakableGlass.shatterPane(glass, glass.Position, Vector3.new(0, 0, -1))
			local second = BreakableGlass.shatterPane(glass, glass.Position, Vector3.new(0, 0, -1))
			expect(first > 0).to.equal(true)
			expect(second).to.equal(0)

			clearShards()
			folder:Destroy()
		end)
	end)
end
