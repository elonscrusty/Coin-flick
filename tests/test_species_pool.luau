-- SpeciesPool: weekly pets, chase (Legendary-only) pets and the printed species odds.
return function(t)
	local test, shared = t.test, t.shared
	local Config = shared("Config")
	local SpeciesPool = shared("SpeciesPool")
	local GeodeGen = shared("GeodeGen")
	local Random = t.Random

	test("species pool: every zone has one chase pet, Void Dragon is Space's", function()
		for _, tid in Config.TierOrder do
			local n = 0
			for _, id in Config.Tiers[tid].Minerals do
				local sp = Config.Minerals[id]
				assert(sp, "known species " .. id)
				assert(not sp.TowerOnly, "no tower-only pet in a pile")
				if sp.Chase then
					n += 1
				end
			end
			assert(n == 1, "one chase pet in " .. tid)
		end
		local _, chase = SpeciesPool.available("Meteor", 0)
		assert(chase == "CosmicDragon", "Void Dragon is the Space chase pet")
	end)

	test("species pool: weekly pets stay hidden until their week", function()
		local w = Config.WeeklyPets
		for _, id in w.Order do
			assert(Config.Minerals[id] and Config.Minerals[id].Weekly, "weekly order lists weekly pets: " .. id)
			if w.Start <= 0 then
				assert(not SpeciesPool.released(id, os.time()), "hidden while Start is unset: " .. id)
			end
		end
		for id, sp in Config.Minerals do
			if sp.Weekly then
				assert(table.find(w.Order, id), "weekly pet has a week: " .. id)
			end
		end
		local old = w.Start
		w.Start = 1000
		assert(SpeciesPool.released(w.Order[1], 1000), "week 1 out at Start")
		assert(not SpeciesPool.released(w.Order[2], 1000), "week 2 not yet")
		assert(SpeciesPool.released(w.Order[2], 1000 + w.Days * 86400), "week 2 out a week later")
		w.Start = old
	end)

	test("species pool: chase pet only on Legendary, printed odds match the roll", function()
		local rng = Random.new(5)
		for _, r in Config.Rarities do
			local id = SpeciesPool.pick(rng, "Meteor", r, 0)
			assert((id == "CosmicDragon") == (r == "Legendary"), "chase iff Legendary: " .. r .. " " .. id)
		end
		local rp = { Common = 0.6, Uncommon = 0.25, Rare = 0.11, Epic = 0.039, Legendary = 0.001 }
		local sum = 0
		for _, id in SpeciesPool.list("Gravel", 0) do
			sum += SpeciesPool.chance("Gravel", id, 0, rp)
		end
		assert(math.abs(sum - 1) < 1e-9, "species odds sum to 1")
		assert(math.abs(SpeciesPool.chance("Meteor", "CosmicDragon", 0, rp) - 0.001) < 1e-12, "Void Dragon 1 in 1000")
		-- the real roll: never a Legendary normal pet, never a non-Legendary chase pet
		for i = 1, 3000 do
			local s = GeodeGen.roll(rng, "Meteor", "p" .. i, "m", 0, true, 3)
			assert(SpeciesPool.rarityAllowed(s.Mineral, s.Rarity), "chase pet rarity")
			assert((s.Mineral == "CosmicDragon") == (s.Rarity == "Legendary"), "Legendary Space = Void Dragon")
		end
	end)
	test("species pool: pick's fallback never returns an unreleased or tower-only species", function()
		local tier = Config.Tiers.Gravel
		local old = tier.Minerals
		-- a zone whose only species is tower-only (bad config): available() is empty, the fallback must look elsewhere
		local towerOnly
		for id, sp in Config.Minerals do
			if sp.TowerOnly then
				towerOnly = id
				break
			end
		end
		assert(towerOnly, "a tower-only species exists")
		tier.Minerals = { towerOnly }
		local ok, got = pcall(SpeciesPool.pick, Random.new(1), "Gravel", "Common", 0)
		tier.Minerals = old
		assert(ok, tostring(got))
		local sp = Config.Minerals[got]
		assert(sp and not sp.TowerOnly, "not tower-only: " .. tostring(got))
		assert(SpeciesPool.released(got, 0), "released: " .. tostring(got))
	end)
end
