return function(t)
	local test, shared = t.test, t.shared
	local Config = shared("Config")
	local Pile = shared("Pile")
	local GeodeGen = shared("GeodeGen")
	local Random, Vector3, Vector2 = t.Random, t.Vector3, t.Vector2

	local function assertEq(a, b, msg)
		if a ~= b then
			error((msg or "mismatch") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
		end
	end

	test("pile has exact rock count for every tier and the tutorial", function()
		for _, id in Config.TierOrder do
			local tier = Config.Tiers[id]
			local p = Pile.new(tier.Rocks, tier.RockSize, tier.Radius, 42)
			assertEq(#p.Rocks, tier.Rocks, id)
			local n = 0
			for _, c in p.Columns do
				n += #c.Stack
			end
			assertEq(n, tier.Rocks, id .. " stacks")
		end
		local p = Pile.new(Config.Tutorial.Rocks, 3, 13, 7)
		assertEq(#p.Rocks, Config.Tutorial.Rocks, "tutorial")
	end)

	test("meadow mound (150 eggs) is about 18-23 studs wide and 5-8 tall", function()
		local tier = Config.Tiers.Gravel
		local p = Pile.new(tier.Rocks, tier.RockSize, tier.Radius, 21)
		local maxR, top = 0, 0
		for _, c in p.Columns do
			maxR = math.max(maxR, c.Pos.Magnitude)
			top = math.max(top, #c.Stack * p.Layer)
		end
		local width = 2 * maxR + tier.RockSize
		assert(width >= 17 and width <= 23, "width " .. width)
		assert(top >= 4.5 and top <= 8.5, "height " .. top)
	end)

	test("pile footprint stays inside the tier radius and peak height is sane", function()
		for _, id in Config.TierOrder do
			local tier = Config.Tiers[id]
			local p = Pile.new(tier.Rocks, tier.RockSize, tier.Radius, 3)
			local top = 0
			for _, c in p.Columns do
				assert(c.Pos.Magnitude <= tier.Radius + 0.01, id .. " column outside radius")
				top = math.max(top, #c.Stack * p.Layer)
			end
			assert(top <= 24, id .. " peak too tall: " .. top)
		end
	end)

	test("layout is deterministic from the seed", function()
		local a = Pile.new(220, 2.6, 14, 99)
		local b = Pile.new(220, 2.6, 14, 99)
		for i = 1, 220 do
			assertEq(a.Rocks[i].Column, b.Rocks[i].Column)
			assert(a.Rocks[i].Rot == b.Rocks[i].Rot, "rot differs")
		end
	end)

	test("a new seed gives a new layout (positions and id slots differ between rounds)", function()
		local a = Pile.new(120, 2.6, 14, 1001)
		local b = Pile.new(120, 2.6, 14, 2002)
		local sameSlot, moved = 0, 0
		for i = 1, 120 do
			assert(a.Rocks[i] and a.Rocks[i].Id == i, "dense ids")
			local pa, pb = a:localPosition(i) :: Vector3, b:localPosition(i) :: Vector3
			if (pa - pb).Magnitude > 1 then
				moved += 1
			end
			if a.Rocks[i].Column == b.Rocks[i].Column then
				sameSlot += 1
			end
		end
		assert(moved > 100, "most eggs should move between seeds: " .. moved)
		assert(sameSlot < 40, "ids should land in other columns: " .. sameSlot)
		-- every column stack lists exactly the rocks that name it
		local seen = 0
		for ci, c in a.Columns do
			for _, id in c.Stack do
				assertEq(a.Rocks[id].Column, ci)
				seen += 1
			end
		end
		assertEq(seen, 120)
	end)

	test("every rock is reachable: removing exposed rocks always empties the pile", function()
		for _, id in Config.TierOrder do
			local tier = Config.Tiers[id]
			local p = Pile.new(tier.Rocks, tier.RockSize, tier.Radius, 11)
			local rng = Random.new(5)
			local guard = 0
			while p.Remaining > 0 do
				local exposed = p:exposedIds()
				assert(#exposed > 0, id .. " stuck with " .. p.Remaining .. " buried rocks")
				p:remove(exposed[rng:NextInteger(1, #exposed)])
				guard += 1
				assert(guard <= tier.Rocks, "loop")
			end
		end
	end)

	test("pickable rocks: low and exposed only, and the pile can always be emptied by pickups", function()
		for _, id in Config.TierOrder do
			local tier = Config.Tiers[id]
			local p = Pile.new(tier.Rocks, tier.RockSize, tier.Radius, 17)
			local reach = Config.Carry.ReachLevels
			local first = p:pickableIds(reach)
			assert(#first > 0 and #first < tier.Rocks, id .. " pickable count " .. #first)
			for _, rid in first do
				assert(p:levelOf(rid) <= reach, "pickable rock above reach")
				assert(p:isExposed(rid), "pickable rock must be exposed")
			end
			local rng = Random.new(9)
			local guard = 0
			while p.Remaining > 0 do
				local list = p:pickableIds(reach)
				assert(#list > 0, id .. " stuck with " .. p.Remaining .. " rocks and nothing pickable")
				p:remove(list[rng:NextInteger(1, #list)])
				guard += 1
				assert(guard <= tier.Rocks, "loop")
			end
		end
	end)

	test("restoring rocks puts them back on a low edge column; stacks round-trip", function()
		local p = Pile.new(80, 2.2, 10, 5)
		local rng = Random.new(3)
		local taken = {}
		for _ = 1, 20 do
			local list = p:pickableIds(3)
			local rid = list[rng:NextInteger(1, #list)]
			p:remove(rid)
			table.insert(taken, rid)
		end
		for i = 1, 10 do
			local col = p:restore(taken[i], Vector2.new(10, 0), 3)
			assert(col ~= nil, "restore")
			assert(p:isExposed(taken[i]), "restored rock is on top")
			assert(not p.Removed[taken[i]])
		end
		assertEq(p.Remaining, 80 - 10, "remaining after restores")
		local q = Pile.new(80, 2.2, 10, 5)
		q:setStacks(p:stacks())
		assertEq(q.Remaining, p.Remaining, "stacks remaining")
		for id = 1, 80 do
			assertEq(q.Removed[id] == true, p.Removed[id] == true, "removed " .. id)
		end
		assertEq(p:restore(taken[1]), nil, "a rock already in the pile cannot be restored")
	end)

	test("buried rocks are not exposed at the start of a big pile", function()
		local tier = Config.Tiers.Meteor
		local p = Pile.new(tier.Rocks, tier.RockSize, tier.Radius, 1)
		local exposed = #p:exposedIds()
		assert(exposed < tier.Rocks * 0.6, "too many exposed: " .. exposed)
		assert(exposed > 0)
	end)

	test("geode rolls follow the configured weights", function()
		local rng = Random.new(1234)
		local counts, mods, big = {}, {}, 0
		local N = 50000
		for i = 1, N do
			local s = GeodeGen.roll(rng, "Gravel", tostring(i), "k", 0, false)
			counts[s.Rarity] = (counts[s.Rarity] or 0) + 1
			mods[s.Modifier] = (mods[s.Modifier] or 0) + 1
			if s.Mass > 12 then
				big += 1
			end
			assert(s.Mass >= 0.5 and s.Mass <= 30, "mass")
			assert(math.abs(s.Mass * 100 - math.floor(s.Mass * 100 + 0.5)) < 1e-6, "2dp")
		end
		local function near(n, pct, tol)
			return math.abs(n / N * 100 - pct) <= tol
		end
		assert(near(counts.Common, 60, 1.5), "common " .. counts.Common)
		assert(near(counts.Legendary, 0.1, 0.06), "legendary (1 in 1000) " .. counts.Legendary)
		assert(near(mods.Natural, 90, 1), "natural")
		assert(near(mods.Rainbow or 0, 0.8, 0.25), "rainbow")
		assert(near(big, 1, 0.3), "mass >12kg " .. big)
	end)

	test("geode value formula", function()
		assertEq(GeodeGen.value("Gravel", "Common", "Natural", 1), 40)
		assertEq(GeodeGen.value("Meteor", "Legendary", "SilverCosmic", 30), math.floor(4000 * 12 * 5 * 8.25))
		assertEq(GeodeGen.value("Quarry", "Rare", "Golden", 2.5), math.floor(150 * 3 * 1.5 * 1.375))
	end)

	test("pets: every zone hatches its own species and luck only lifts Rare and better", function()
		for _, t in Config.TierOrder do
			for _, sp in Config.Tiers[t].Minerals do
				local def = Config.Minerals[sp]
				assert(def and def.Kind and def.BoostKind and Config.Pets.KindCap[def.BoostKind], "species " .. sp)
			end
			local s = GeodeGen.roll(Random.new(7), t, "x", "k", 0, false, 0.5)
			assert(table.find(Config.Tiers[t].Minerals, s.Mineral), "zone species " .. t)
		end
		local plain, lucky = GeodeGen.rarityWeights(0), GeodeGen.rarityWeights(0.5)
		assertEq(lucky.Common, plain.Common)
		assertEq(lucky.Uncommon, plain.Uncommon)
		assert(math.abs(lucky.Legendary - plain.Legendary * 1.5) < 1e-9, "legendary x1.5")
		assertEq(GeodeGen.rarityWeights(50).Rare, plain.Rare * (1 + shared("RobuxConfig").MaxLuck)) -- luck is clamped
		assertEq(plain.Legendary / 100, 0.001) -- owner: rarest pet 1 in 1000
	end)
end
