-- The one thing about this file that cannot be checked by looking at it.
--
-- HorrorVisibilityZones tweens Lighting from one profile to another. A tween
-- only writes the properties it is given, so a key that appears in one profile
-- and not in another is not a default, it is a leak: leaving Calm without a
-- Brightness in Dark leaves the hotel at Calm's Brightness forever, and the
-- symptom shows up two rooms later as "the horror grade looks wrong" rather
-- than as anything pointing at the profile that is missing a line.
--
-- Nothing catches that by eye — the profiles are three screens apart and the
-- values are all plausible numbers. This does.

return function()
	-- TestEZ applies its DSL to this function's environment rather than to the
	-- module, so the names only exist once we are inside it. Pulling them into
	-- locals here keeps luau-lsp from reading them as undefined globals.
	local env = getfenv()
	local describe = env.describe
	local it = env.it
	local expect = env.expect

	local Profiles = require(script.Parent.HorrorGradeProfiles)

	local TABLES = { "lighting", "grade", "atmosphere" }

	local function names(): { string }
		local found = {}
		for name in pairs(Profiles) do
			table.insert(found, name)
		end
		table.sort(found)
		return found
	end

	describe("every profile", function()
		it("is one of the four the zones ask for", function()
			local expected = { "Calm", "Dark", "Lobby", "Vault" }
			expect(table.concat(names(), ",")).to.equal(table.concat(expected, ","))
		end)

		it("carries all three property tables", function()
			for _, name in names() do
				for _, group in TABLES do
					expect(type(Profiles[name][group])).to.equal("table")
				end
			end
		end)

		--[[
			The test this file exists for.

			Compared against Dark rather than against a written-down list of keys,
			because Dark is the profile the server applies at startup and is
			therefore the one that defines what "the hotel's lighting" consists
			of. A property added there has to be added everywhere or leaving that
			zone will not restore it; a property added elsewhere and not to Dark
			would never be put back at all.
		]]
		it("sets exactly the keys Dark sets, in every table", function()
			for _, group in TABLES do
				for key in pairs(Profiles.Dark[group]) do
					for _, name in names() do
						if Profiles[name][group][key] == nil then
							error(`{name}.{group} is missing {key}, which Dark.{group} sets`)
						end
					end
				end
			end

			for _, name in names() do
				for _, group in TABLES do
					for key in pairs(Profiles[name][group]) do
						if Profiles.Dark[group][key] == nil then
							error(`{name}.{group} sets {key}, which Dark.{group} never restores`)
						end
					end
				end
			end
		end)

		it("gives every key a value TweenService can interpolate", function()
			for _, name in names() do
				for _, group in TABLES do
					for key, value in pairs(Profiles[name][group]) do
						local kind = typeof(value)
						if kind ~= "number" and kind ~= "Color3" then
							error(`{name}.{group}.{key} is a {kind}, which a tween cannot move`)
						end
					end
				end
			end
		end)
	end)

	describe("Calm", function()
		--[[
			The whole point of the profile, asserted as a direction rather than as
			numbers so that retuning either end is free and inverting them is not.
			A "calm" grade that is darker than the horror grade would mean the
			intro reads as the scare and the game proper reads as the relief.
		]]
		it("is lighter than the hotel it replaces", function()
			local calm = Profiles.Calm.lighting.Ambient
			local dark = Profiles.Dark.lighting.Ambient
			expect(calm.R + calm.G + calm.B > dark.R + dark.G + dark.B).to.equal(true)
			expect(Profiles.Calm.lighting.FogEnd > Profiles.Dark.lighting.FogEnd).to.equal(true)
			expect(Profiles.Calm.atmosphere.Haze < Profiles.Dark.atmosphere.Haze).to.equal(true)
		end)

		it("is lighter than the lobby, which is only relief and not daylight", function()
			local calm = Profiles.Calm.lighting.Ambient
			local lobby = Profiles.Lobby.lighting.Ambient
			expect(calm.R + calm.G + calm.B > lobby.R + lobby.G + lobby.B).to.equal(true)
		end)

		it("does not grade the picture the way the horror profiles do", function()
			expect(Profiles.Calm.grade.Saturation >= 0).to.equal(true)
			expect(Profiles.Dark.grade.Saturation < 0).to.equal(true)
		end)
	end)
end
