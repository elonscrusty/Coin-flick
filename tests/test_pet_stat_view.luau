-- Pet stats in plain words (src/shared/PetStatView.luau): one "bigger = better" POWER number per pet, arrows against
-- the followed pet, the real hunt bonus, and the MORE page.
return function(t)
	local test, shared = t.test, t.shared
	local Config = shared("Config")
	local TowerConfig = shared("TowerConfig")
	local PetStats = shared("PetStats")
	local PetStatView = shared("PetStatView")

	local function assertEq(a, b, msg)
		if a ~= b then
			error((msg or "mismatch") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
		end
	end
	local function pet(id, species, rarity, seed, modifier, xp)
		return { Id = id, Mineral = species, Rarity = rarity, Modifier = modifier or "Natural", Seed = seed, TowerXP = xp }
	end

	test("POWER: rarer, Golden / Rainbow and higher level pets are always bigger", function()
		local order = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }
		for seed = 1, 80 do
			local last = 0
			for _, r in order do
				local p = PetStatView.power(pet("a", "Raptor", r, seed))
				assert(p > last, "rarity did not raise POWER")
				last = p
			end
			local plain = PetStatView.power(pet("a", "Griffin", "Rare", seed))
			local gold = PetStatView.power(pet("a", "Griffin", "Rare", seed, "Golden"))
			local rainbow = PetStatView.power(pet("a", "Griffin", "Rare", seed, "Rainbow"))
			assert(plain < gold and gold < rainbow, "variant order")
			assert(PetStatView.power(pet("a", "Griffin", "Rare", seed, nil, 2000)) > plain, "level did not raise POWER")
		end
	end)

	test("POWER matches the server's tower-team weights (TowerService.score) and the roster row", function()
		local g = pet("a", "DireWolf", "Epic", 99, "Golden", 500)
		local s = PetStats.roll(g, 500)
		assertEq(PetStatView.power(g), math.floor(s.Power * 3 + s.Health * 0.5 + s.Speed * 0.2 + 0.5))
		assertEq(PetStatView.powerOf({ Power = s.Power, Health = s.Health, Speed = s.Speed }), PetStatView.power(g))
		assertEq(PetStatView.power(g), shared("PvpRules").power(g, 500), "the same number PvP uses")
	end)

	test("arrows: up when stronger than the followed pet, down when weaker, none for itself or unknown", function()
		local weak = pet("w", "Raptor", "Common", 3)
		local strong = pet("s", "Raptor", "Legendary", 3, "Golden")
		assertEq(PetStatView.compare(strong, weak), 1)
		assertEq(PetStatView.compare(weak, strong), -1)
		assertEq(PetStatView.compare(strong, strong), 0)
		assertEq(PetStatView.compare(strong, nil), 0)
		assertEq(PetStatView.compare(strong, { Id = "x", Mineral = "Raptor", Rarity = "Rare" }), 0, "no seed = no arrow")
		assertEq(PetStatView.power({ Id = "x", Mineral = "Raptor", Rarity = "Rare" }), nil)
	end)

	test("hunt bonus is the real one (KindScale applied, like Profiles.petBoosts) and never over the cap", function()
		-- Raptor is a Speed pet: Uncommon 0.06 x KindScale 0.4 = 2.4%
		local kind, amt = PetStatView.bonus(pet("a", "Raptor", "Uncommon", 1))
		assertEq(kind, "Speed")
		assertEq(amt, 0.024)
		assertEq(PetStatView.bonusText(pet("a", "Raptor", "Uncommon", 1)), "+2.4% speed")
		assertEq(PetStatView.bonusText(pet("b", "Ostrich", "Rare", 1)), "+10% coins")
		for k, cap in Config.Pets.KindCap do
			for id, sp in Config.Minerals do
				if sp.BoostKind == k then
					local _, a = PetStatView.bonus(pet("x", id, "Legendary", 1))
					assert(a <= cap + 1e-9, id .. " over cap")
				end
			end
		end
	end)

	test("level shows with its rarity cap (Lv 7/20); XP past the cap stays at the cap", function()
		assertEq(PetStatView.levelText(7, 20), "Lv 7/20")
		assertEq(PetStatView.levelText(50, 50), "Lv 50 MAX")
		local lv, cap = PetStatView.levelOf(pet("a", "Raptor", "Common", 1, nil, 1e7))
		assertEq(cap, TowerConfig.LevelCaps.Common)
		assertEq(lv, cap)
		local _, lcap = PetStatView.levelOf(pet("a", "Raptor", "Legendary", 1))
		assert(lcap > cap, "Legendary grows higher than Common")
		local found = false
		for _, l in PetStatView.more(pet("a", "Raptor", "Common", 1, nil, 1e7)) do
			if string.find(l.Head, "Level " .. cap .. " of " .. cap .. " (MAX)", 1, true) then
				found = true
			end
		end
		assert(found, "MORE says MAX at the cap")
	end)

	test("MORE starts with POWER and spells out variant and rarity multipliers", function()
		local lines = PetStatView.more(pet("a", "Raptor", "Rare", 4, "Golden"))
		assert(string.find(lines[1].Head, "^POWER %d+"), lines[1].Head)
		local all = {}
		for _, l in lines do
			table.insert(all, l.Head .. ": " .. l.Text)
		end
		local text = table.concat(all, "\n")
		assert(string.find(text, "Golden: x1.5 Attack and Health", 1, true), text)
		assert(string.find(text, "Rare: x1.45 Attack and Health", 1, true), text)
		assert(string.find(text, "Attack speed", 1, true), text)
		assertEq(PetStatView.variantTag(pet("a", "Raptor", "Rare", 4, "Rainbow")), "Rainbow x" .. TowerConfig.VariantStat.Rainbow)
		assertEq(PetStatView.variantTag(pet("a", "Raptor", "Rare", 4)), nil)
	end)
end
