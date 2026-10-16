-- Zone arena themes (shared/ZoneThemes): every tier has its own look and landmark, the Meadow theme reproduces the
-- built arena, and every landmark spot stands outside the play octagon, clear of the pile, tables, bays and the road.
return function(t)
	local test, shared = t.test, t.shared
	local Config = shared("Config")
	local ZoneThemes = shared("ZoneThemes")
	local RoundRocks = shared("RoundRocks")
	local Vector3 = t.Vector3

	local function assertEq(a, b, msg)
		if a ~= b then
			error((msg or "mismatch") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
		end
	end

	test("zone themes: one theme per tier in Config.TierOrder, own landmark, known materials", function()
		local landmarks = {}
		local KNOWN = { Flowers = true, BigTree = true, IceRocks = true, LavaRocks = true, Crystals = true }
		for _, id in Config.TierOrder do
			local th = ZoneThemes.Themes[id]
			assert(th, "theme for " .. id)
			assertEq(th.Id, id, "theme id")
			assertEq(ZoneThemes.get(id), th, "lookup")
			assertEq(th.Zone, Config.Tiers[id].Name, "zone name matches the tier name")
			assert(KNOWN[th.Landmark], id .. " landmark " .. tostring(th.Landmark))
			assert(not landmarks[th.Landmark], "landmark shared by two zones: " .. th.Landmark)
			landmarks[th.Landmark] = true
			for _, key in { "FloorMaterial", "BenchMaterial", "BandMaterial", "PathMaterial", "HillMaterial", "LeafMaterial", "RockMaterial" } do
				assert(ZoneThemes.Materials[th[key]], id .. "." .. key .. " = " .. tostring(th[key]))
			end
			for _, key in { "HillMix", "LeafMix", "TrunkMix" } do
				assert(th[key] >= 0 and th[key] <= 1, id .. "." .. key)
			end
		end
		local n = 0
		for _ in ZoneThemes.Themes do
			n += 1
		end
		assertEq(n, #Config.TierOrder, "no stray themes")
	end)

	test("zone themes: unknown or missing tier falls back to the Meadow", function()
		assertEq(ZoneThemes.get(nil).Id, "Gravel")
		assertEq(ZoneThemes.get("Nope").Id, "Gravel")
		assertEq(ZoneThemes.Default, Config.Tutorial.Tier, "tutorial pile is the meadow")
	end)

	test("zone themes: Meadow keeps the built arena look (no tint, flowers kept)", function()
		local m = ZoneThemes.get("Gravel")
		assertEq(m.HillMix, 0)
		assertEq(m.LeafMix, 0)
		assertEq(m.TrunkMix, 0)
		assert(m.KeepMeadowFlowers, "meadow keeps its flower beds")
		assertEq(m.FloorMaterial, "Grass")
		local f = m.Floor
		assertEq(math.floor(f.R * 255 + 0.5) * 65536 + math.floor(f.G * 255 + 0.5) * 256 + math.floor(f.B * 255 + 0.5), 112 * 65536 + 190 * 256 + 84, "ArenaKit C.Floor")
		for _, id in Config.TierOrder do
			if id ~= "Gravel" then
				assert(not ZoneThemes.get(id).KeepMeadowFlowers, id .. " hides the meadow flowers")
			end
		end
	end)

	test("zone themes: landmark spots stand outside the play octagon and off the road", function()
		local L = ZoneThemes.Layout
		local spots = ZoneThemes.ringSpots()
		assertEq(#spots, #ZoneThemes.RingAngles)
		table.insert(spots, ZoneThemes.HeroSpot)
		-- the farthest thing inside the play area: machine bays behind the tables (radius 32.75 + half a bay)
		local inner = math.max(Config.Station.Radius, 32.75 + 5)
		for _, tier in Config.TierOrder do
			inner = math.max(inner, Config.Tiers[tier].Radius) -- pile mound
		end
		for i, s in spots do
			local flat = Vector3.new(s.X, 0, s.Z).Magnitude
			assert(flat > L.Apothem + 3, "spot " .. i .. " inside the octagon (" .. flat .. ")")
			assert(flat > inner + 8, "spot " .. i .. " too close to the play ring")
			assert(not (math.abs(s.X) < L.RoadHalfWidth and s.Z < 0), "spot " .. i .. " on the north road")
			assertEq(s.Y, if s.X > L.DropX then L.BenchY else 0, "spot " .. i .. " ground height")
		end
		-- every table stays far from every spot (tables sit on the Config.Station.Radius circle)
		for st = 1, Config.Station.Count do
			local tp = RoundRocks.stationPosition(st)
			for i, s in spots do
				assert((Vector3.new(s.X, 0, s.Z) - Vector3.new(tp.X, 0, tp.Z)).Magnitude > 15, "spot " .. i .. " near table " .. st)
			end
		end
		assert(ZoneThemes.HeroSpot.X > L.DropX, "hero landmark on the lower bench")
	end)
end
