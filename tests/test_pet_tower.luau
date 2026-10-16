-- Pet Tower (project file plans/pet-tower.md): seed-derived pet stats and the deterministic fight rules.
return function(t)
	local test, shared = t.test, t.shared
	local TowerConfig = shared("TowerConfig")
	local PetStats = shared("PetStats")
	local TowerRules = shared("TowerRules")

	local function assertEq(a, b, msg)
		if a ~= b then
			error((msg or "mismatch") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
		end
	end
	local function pet(species, rarity, seed, modifier)
		return { Mineral = species, Rarity = rarity, Modifier = modifier or "Natural", Seed = seed }
	end
	local function team(owner, pets)
		local out = {}
		for i, p in pets do
			table.insert(out, { Owner = owner, Id = owner .. "_" .. i, Pet = p })
		end
		return out
	end
	-- Worst-quality pet of a species among many seeds, so balance checks cover bad rolls.
	local function worst(species, rarity)
		local best, bestQ = nil, 2
		for seed = 1, 400 do
			local s = PetStats.roll(pet(species, rarity, seed))
			if s.Quality < bestQ then
				best, bestQ = seed, s.Quality
			end
		end
		return pet(species, rarity, best)
	end
	local function climb(run)
		while run.State ~= "Lost" do
			if TowerRules.simulate(run) ~= "Cleared" then
				break
			end
			if run.Floor >= 200 then
				return run.Floor
			end
			TowerRules.startFloor(run, run.Floor + 1)
		end
		return run.Floor - 1
	end

	test("tower: same pet always gets the same stats; rolls stay in range", function()
		local a = PetStats.roll(pet("Raptor", "Common", 12345))
		local b = PetStats.roll(pet("Raptor", "Common", 12345))
		assertEq(a.Power, b.Power)
		assertEq(a.Health, b.Health)
		assertEq(a.Speed, b.Speed)
		assertEq(a.Special, b.Special)
		local base = TowerConfig.Species.Raptor
		local grades = {}
		for seed = 1, 500 do
			local s = PetStats.roll(pet("Raptor", "Common", seed * 7919))
			assert(s.Power >= math.floor(base.Power * 0.8) and s.Power <= math.ceil(base.Power * 1.2), "power range")
			assert(s.Health >= math.floor(base.Health * 0.8) and s.Health <= math.ceil(base.Health * 1.2), "health range")
			assert(PetStats.special(s.Special), "special exists")
			grades[s.Grade] = true
		end
		assert(grades.S and grades.A and grades.B and grades.C, "all grades appear")
	end)

	test("tower: rarer pets are stronger and only rare pets roll big specials", function()
		local c = PetStats.roll(pet("Griffin", "Common", 99))
		local l = PetStats.roll(pet("Griffin", "Legendary", 99))
		assert(l.Power > c.Power and l.Health > c.Health, "legendary beats common with the same rolls")
		for seed = 1, 300 do
			local s = PetStats.roll(pet("Ostrich", "Common", seed))
			assert(PetStats.special(s.Special).MinRarity == 1, "common gets only basic specials")
		end
		-- Specials match the pet's type: no Ice Breath on an Earth pet, no Fire Puff on a Storm pet.
		for id, base in TowerConfig.Species do
			for _, rarity in TowerConfig.Rarities do
				for seed = 1, 40 do
					local s = PetStats.roll(pet(id, rarity, seed * 131))
					local sp = PetStats.special(s.Special)
					assert(sp, "special exists")
					assert(sp.Element == nil or sp.Element == base.Element, id .. " rolled off-type " .. sp.Id)
				end
			end
		end
		assertEq(PetStats.special(PetStats.roll(pet("Oakmaw", "Common", 3)).Special).Element, "Earth")
		local unknown = PetStats.roll(pet("SomeOldRock", "Rare", 5))
		assert(unknown.Power > 0 and unknown.Basic == TowerConfig.DefaultSpecies.Basic, "unknown species falls back")
	end)

	test("tower: Pokemon-style types, moves and rarity", function()
		assertEq(PetStats.effect("Fire", "Nature"), TowerConfig.Strong)
		assertEq(PetStats.effect("Nature", "Fire"), TowerConfig.Weak)
		assertEq(PetStats.effect("Ice", "Fire"), TowerConfig.Strong)
		assertEq(PetStats.effect("Fire", "Storm"), 1)
		assertEq(PetStats.effect("Cosmic", "Ice"), TowerConfig.CosmicBonus)
		assertEq(PetStats.effect("Cosmic", "Cosmic"), 1)
		for id, sp in TowerConfig.Species do
			assert(TowerConfig.TypeMoves[sp.Element], "species type has moves")
			assert(TowerConfig.PetNames[id], "display name for " .. id)
		end
		for _, m in TowerConfig.Mobs do
			assert(table.find(TowerConfig.TypeCircle, m.Element), "mob type " .. m.Id)
		end
		local first = TowerConfig.TypeMoves.Fire[1].Name
		local rareMoves = {}
		for seed = 1, 300 do
			assertEq(PetStats.roll(pet("Phoenix", "Common", seed)).Move, first, "common gets the first move")
			rareMoves[PetStats.roll(pet("Phoenix", "Rare", seed)).Move] = true
		end
		for _, mv in TowerConfig.TypeMoves.Fire do
			assert(rareMoves[mv.Name], "rare can roll " .. mv.Name)
		end
	end)

	test("tower: floors, bosses, checkpoints, rewards", function()
		for f = 1, 90 do
			local waves = TowerRules.waves(f)
			assert(#waves >= 1, "floor has waves")
			for _, w in waves do
				for _, id in w do
					assert(TowerConfig.Mobs[id], "mob exists " .. id)
				end
			end
			if TowerRules.isBoss(f) then
				assert(TowerConfig.Mobs[waves[#waves][1]].Boss, "boss last on floor " .. f)
			end
		end
		assertEq(TowerRules.waves(30)[2][1], "BossLavaTRex")
		assertEq(TowerRules.waves(35)[2][1], "BossRaptor", "bands repeat after floor 30")
		assert(TowerConfig.Mobs.BossRaptor.Pet == "Raptor", "bosses are giant pets")
		local m30 = TowerRules.mobStats("Slime", 30, 1)
		local m90 = TowerRules.mobStats("Slime", 90, 1)
		assert(m90 > m30, "endless floors keep getting harder")
		assertEq(TowerRules.theme(1).Id, "Jungle")
		assertEq(TowerRules.theme(10).Id, "Jungle")
		assertEq(TowerRules.theme(11).Id, "Lava")
		assertEq(TowerRules.theme(25).Id, "Ice")
		assertEq(TowerRules.theme(40).Id, "Space")
		assertEq(TowerRules.theme(41).Id, "Jungle", "themes loop")
		assertEq(TowerRules.checkpoint(0), 1)
		assertEq(TowerRules.checkpoint(4), 1)
		assertEq(TowerRules.checkpoint(5), 6)
		assertEq(TowerRules.checkpoint(12), 11)
		assertEq(TowerRules.checkpoint(30), 31)
		assertEq(TowerRules.checkpoint(73), 71)
		assertEq(TowerRules.reward(1), 15)
		assertEq(TowerRules.reward(5), 75 + 150)
	end)

	test("tower: XP levels, revive, tower-only pet drops", function()
		assertEq((PetStats.level(0)), 1)
		assertEq((PetStats.level(39)), 1)
		assertEq((PetStats.level(40)), 2)
		assertEq((PetStats.level(40 + 65)), 3)
		assertEq((PetStats.level(1e9)), TowerConfig.Levels.Max)
		local p = pet("Raptor", "Common", 77)
		local lv1, lv10 = PetStats.roll(p, 0), PetStats.roll(p, 5000)
		assert(lv10.Level > 1 and lv10.Power > lv1.Power and lv10.Health > lv1.Health, "levels make pets stronger")
		assertEq(lv10.Special, lv1.Special, "level never changes moves")
		assert(TowerRules.xp(10, true) > TowerRules.xp(10, false), "a loss earns less")
		assertEq(TowerRules.dropChance(4), 0)
		assert(TowerRules.dropChance(5) > 0 and TowerRules.dropChance(5000) <= TowerConfig.Drop.Max, "drop chance capped")
		assertEq(TowerRules.dropSpecies(4, 0.5), nil)
		assertEq(TowerRules.dropSpecies(5, 0.99), "Thornback", "only unlocked species")
		local seen = {}
		for i = 0, 999 do
			seen[TowerRules.dropSpecies(40, i / 1000) or "?"] = true
		end
		for _, tp in TowerConfig.TowerPets do
			assert(seen[tp.Id], "can drop " .. tp.Id)
			assert(TowerConfig.Species[tp.Id] and TowerConfig.PetNames[tp.Id], "tower pet has stats and name")
		end
		local run = TowerRules.newRun(team(1, { pet("Raptor", "Common", 1) }), 60)
		assertEq(TowerRules.simulate(run), "Lost", "floor 60 beats a lone common")
		assert(TowerRules.revive(run), "revive works after a loss")
		assertEq(run.State, "Fighting")
		assert(run.Pets[1].Hp > 0, "pet is back")
		assert(not TowerRules.revive(run), "no revive while fighting")
	end)

	test("tower: team limits (solo, 3 pets)", function()
		local list = {}
		for owner = 1, 5 do
			for _, p in team(owner, { pet("Raptor", "Common", 1), pet("Raptor", "Common", 2), pet("Raptor", "Common", 3), pet("Raptor", "Common", 4) }) do
				table.insert(list, p)
			end
		end
		local run = TowerRules.newRun(list, 1)
		assertEq(#run.Pets, 3, "solo: one player's 3 pets")
		assertEq(run.Players, 1)
		assertEq(TowerRules.newRun({}, 1).State, "Lost")
	end)

	test("tower: special needs a full meter and resets it", function()
		local run = TowerRules.newRun(team(7, { pet("Raptor", "Common", 3) }), 1)
		local ok = TowerRules.useSpecial(run, 7)
		assert(not ok, "empty meter")
		run.Meters[7] = TowerConfig.SpecialCharge
		local ok2, events = TowerRules.useSpecial(run, 7, 0)
		assert(ok2 and events[1].Kind == "Special", "fires when full")
		assertEq(run.Meters[7], 0)
		assert(not TowerRules.useSpecial(run, 99), "stranger cannot fire")
	end)

	test("tower balance: one bad Common Raptor clears floor 1; a legendary team climbs higher", function()
		local run = TowerRules.newRun(team(1, { worst("Raptor", "Common") }), 1)
		assertEq(TowerRules.simulate(run), "Cleared", "day-one player wins floor 1")
		local commons = TowerRules.newRun(team(1, { worst("Raptor", "Common"), worst("Ostrich", "Common"), worst("DireWolf", "Common") }), 1)
		local top = climb(commons)
		assert(top >= 3 and top < 200, "commons reach " .. top)
		local legends = TowerRules.newRun(
			team(1, { pet("CosmicDragon", "Legendary", 11), pet("Phoenix", "Legendary", 12), pet("LavaTRex", "Legendary", 13) }),
			1
		)
		assert(climb(legends) > top, "legendary team climbs higher")
	end)

	test("tower: pity drops, new pets favoured, all 5 owned by about floor 60-80", function()
		-- chance rises with misses, then is certain
		local base = TowerRules.dropChance(5)
		assert(TowerRules.dropChance(5, 1) > base, "a miss raises the next boss chance")
		assertEq(TowerRules.dropChance(5, TowerConfig.Pity.GuaranteeAfter), 1, "guaranteed after the pity limit")
		assertEq(TowerRules.dropChance(4, 99), 0, "pity never makes a normal floor drop")
		assertEq(TowerRules.pityAfter(3, true), 0, "a drop resets pity")
		assertEq(TowerRules.pityAfter(nil, false), 1, "a miss counts")
		-- a pet never owned is favoured; owned ones only drop once every allowed pet is owned
		for i = 0, 99 do
			assertEq(TowerRules.dropSpecies(40, i / 100, { Thornback = 2, Frostbyte = 1, Voltwing = 1, Embergeist = 1 }), "AstralKitsune", "last new pet")
			local sp = TowerRules.dropSpecies(12, i / 100, { Thornback = 1 })
			assertEq(sp, "Frostbyte", "only the new pet allowed on floor 12")
		end
		local all = { Thornback = 1, Frostbyte = 1, Voltwing = 1, Embergeist = 1, AstralKitsune = 1 }
		local dup = {}
		for i = 0, 999 do
			dup[TowerRules.dropSpecies(40, i / 1000, all) or "?"] = true
		end
		assert(dup.Thornback and dup.AstralKitsune and not dup["?"], "duplicates once all are owned")
		assertEq(TowerRules.dropSpecies(5, 0.5, {}), "Thornback")
		-- price zone: best unlocked
		assertEq(TowerRules.dropTier({ "A", "B", "C" }, { A = true, B = true }), "B")
		assertEq(TowerRules.dropTier({ "A", "B", "C" }, nil), "A")
		-- simulate steady climbers (every boss floor cleared once, in order); seeded LCG so the test is stable
		local s = 12345
		local function rnd()
			s = (s * 48271) % 2147483647
			return s / 2147483647
		end
		local finish = {}
		for _ = 1, 2000 do
			local owned, misses, at = {}, 0, 1000
			for floor = 5, 300, 5 do
				local dropped = rnd() < TowerRules.dropChance(floor, misses)
				if dropped then
					local sp = TowerRules.dropSpecies(floor, rnd(), owned)
					if sp then
						owned[sp] = (owned[sp] or 0) + 1
					end
				end
				misses = TowerRules.pityAfter(misses, dropped)
				local n = 0
				for _ in owned do
					n += 1
				end
				if n == #TowerConfig.TowerPets then
					at = floor
					break
				end
			end
			table.insert(finish, at)
		end
		table.sort(finish)
		local median, p90 = finish[1000], finish[1800]
		print(string.format("    tower pity: all 5 tower pets owned by floor median %d, 90%% by %d", median, p90))
		assert(median >= 50 and median <= 80, "median floor for all 5: " .. median)
		assert(p90 <= 110, "90% own all 5 by floor " .. p90)
	end)
	test("tower: only a new theme's first wave waits for its title (TitleHold), every other wave starts at once", function()
		local TC = shared("TowerConfig")
		assert(TowerRules.introHold(1, 1) == TC.TitleHold and TC.TitleHold >= 1.9, "floor 1 held past the 1.9 s title")
		assert(TowerRules.introHold(1 + TC.ThemeEvery, 1) == TC.TitleHold, "next theme held")
		assert(TowerRules.introHold(1, 2) == 0, "wave 2 not held")
		assert(TowerRules.introHold(2, 1) == 0, "mid-theme floor not held")
	end)
end
