-- Pet Battle + training rules (shared/PvpRules, shared/PvpConfig).
return function(t)
	local test, shared = t.test, t.shared
	local PvpConfig = shared("PvpConfig")
	local PvpRules = shared("PvpRules")
	local TowerConfig = shared("TowerConfig")
	local PetStats = shared("PetStats")

	local function assertEq(a, b, msg)
		if a ~= b then
			error((msg or "mismatch") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
		end
	end
	local function stream(seed)
		local s = seed
		return function()
			s = (s * 48271) % 2147483647
			return s / 2147483647
		end
	end
	local function team(prefix, list)
		local out = {}
		for i, p in list do
			table.insert(out, { Id = prefix .. i, Xp = p[4], Pet = { Mineral = p[1], Rarity = p[2], Modifier = "Natural", Seed = p[3] } })
		end
		return out
	end

	test("pvp: every battle search exit reason has one plain line (audit F24)", function()
		for _, why in { "Cancel", "Hunt", "Busy", "NoTeam" } do
			local line = PvpRules.unqueueText(why)
			assert(type(line) == "string" and #line > 0, why)
		end
		assertEq(PvpRules.unqueueText(nil), nil)
		assertEq(PvpRules.unqueueText("Weird"), nil)
	end)

	test("pvp: power number is one stable number per pet and grows with training", function()
		local pet = { Mineral = "Raptor", Rarity = "Common", Modifier = "Natural", Seed = 777 }
		assertEq(PvpRules.power(pet, 0), PvpRules.power(pet, 0))
		assert(PvpRules.power(pet, 5000) > PvpRules.power(pet, 0), "trained pet is stronger")
		local gold = table.clone(pet)
		gold.Modifier = "Golden"
		assert(PvpRules.power(gold, 0) > PvpRules.power(pet, 0), "golden is stronger")
		local a = team("a", { { "Raptor", "Common", 1 }, { "Mammoth", "Rare", 2 } })
		assertEq(PvpRules.teamPower(a), PvpRules.power(a[1].Pet) + PvpRules.power(a[2].Pet))
	end)

	test("pvp: match window widens while waiting", function()
		assert(PvpRules.canMatch(1000, 0, 1100, 0), "10% apart matches at once")
		assert(not PvpRules.canMatch(1000, 0, 1500, 0), "33% apart does not match at once")
		assert(PvpRules.canMatch(1000, 7, 1500, 0), "33% apart matches after 7 s")
		assert(PvpRules.window(PvpConfig.BotAfter) > PvpRules.window(0))
	end)

	test("pvp: bot team mirrors rarity, picks other species, lands near the player's power", function()
		local me = team("a", { { "LavaTRex", "Epic", 11, 800 }, { "Phoenix", "Rare", 22, 300 }, { "Griffin", "Common", 33, 0 } })
		local mine = PvpRules.teamPower(me)
		for seed = 1, 40 do
			local bot = PvpRules.botTeam(me, stream(seed * 97 + 5))
			assertEq(#bot, 3)
			for i, b in bot do
				assertEq(b.Pet.Rarity, me[i].Pet.Rarity)
				assertEq(b.Xp, me[i].Xp)
				for _, tp in TowerConfig.TowerPets do
					assert(b.Pet.Mineral ~= tp.Id, "no tower-only pets for bots")
				end
			end
			local p = PvpRules.teamPower(bot)
			assert(math.abs(p - mine * PvpConfig.BotPower) / mine < 0.2, "bot power near target: " .. p .. " vs " .. mine)
		end
	end)

	test("pvp: fight ends with one winner, KO event, no pet below 0 hp, deterministic", function()
		local a = team("a", { { "Raptor", "Rare", 5 }, { "Mammoth", "Rare", 6 }, { "Phoenix", "Rare", 7 } })
		local b = team("b", { { "DireWolf", "Rare", 8 }, { "FrostWyvern", "Rare", 9 }, { "Ostrich", "Rare", 10 } })
		local f1 = PvpRules.newFight(a, b)
		local w1 = PvpRules.simulate(f1, stream(42))
		local f2 = PvpRules.newFight(a, b)
		local w2 = PvpRules.simulate(f2, stream(42))
		assertEq(w1, w2, "same seed same winner")
		assertEq(f1.State, "Done")
		for _, u in f1.Units do
			assert(u.Hp >= 0 and u.Hp <= u.Max, "hp in range")
		end
		if w1 ~= 0 then
			assertEq(#PvpRules.alive(f1, 3 - w1), 0, "loser has no pets standing")
		end
	end)

	test("pvp: much stronger team wins almost always; equal teams split", function()
		local strong = team("a", { { "CosmicDragon", "Legendary", 1, 20000 }, { "LavaTRex", "Legendary", 2, 20000 }, { "Phoenix", "Legendary", 3, 20000 } })
		local weak = team("b", { { "Raptor", "Common", 4 }, { "Ostrich", "Common", 5 }, { "Mammoth", "Common", 6 } })
		local wins = 0
		for seed = 1, 30 do
			if PvpRules.simulate(PvpRules.newFight(strong, weak), stream(seed)) == 1 then
				wins += 1
			end
		end
		assertEq(wins, 30, "strong team wins")
		local sideOne = 0
		local same = team("x", { { "Griffin", "Rare", 50 }, { "Mammoth", "Rare", 51 }, { "Phoenix", "Rare", 52 } })
		local copy = team("y", { { "Griffin", "Rare", 50 }, { "Mammoth", "Rare", 51 }, { "Phoenix", "Rare", 52 } })
		for seed = 1, 60 do
			if PvpRules.simulate(PvpRules.newFight(same, copy), stream(seed * 13)) == 1 then
				sideOne += 1
			end
		end
		assert(sideOne >= 15 and sideOne <= 45, "mirror match is fair-ish: side 1 won " .. sideOne .. "/60")
	end)

	test("pvp: type advantage pops Strong, crits flagged, pets aim at the foe they beat", function()
		local fire = team("a", { { "LavaTRex", "Common", 1 } })
		local foes = team("b", { { "Mammoth", "Common", 2 }, { "Raptor", "Common", 3 } }) -- Earth first, Nature second
		local f = PvpRules.newFight(fire, foes)
		local strong, crit, hitRaptorFirst = false, false, nil
		for _ = 1, 400 do
			for _, e in PvpRules.step(f, 0.1, stream(9)) do
				if e.Kind == "Hit" and e.From == "a1" then
					if hitRaptorFirst == nil then
						hitRaptorFirst = e.To == "b2"
					end
					strong = strong or e.Id == "Strong"
				end
				crit = crit or e.Crit == true
			end
			if f.State ~= "Fighting" then
				break
			end
		end
		assert(hitRaptorFirst, "fire pet hits the nature pet first")
		assert(strong, "strong hit seen")
		local f2 = PvpRules.newFight(fire, foes)
		local r = stream(3)
		local always = function()
			return 0.01 -- below CritChance: every hit crits
		end
		local critSeen = false
		for _ = 1, 30 do
			for _, e in PvpRules.step(f2, 0.1, always) do
				critSeen = critSeen or (e.Kind == "Hit" and e.Crit == true)
			end
		end
		local _ = r
		assert(critSeen, "crit flagged")
	end)

	test("pvp: time-up gives the win to the side with more health left", function()
		local a = team("a", { { "Mammoth", "Common", 1 } })
		local b = team("b", { { "Mammoth", "Common", 1 } })
		local f = PvpRules.newFight(a, b)
		f.Units[2].Hp = math.floor(f.Units[2].Max / 2)
		f.Time = PvpConfig.FightTime
		local ev = PvpRules.step(f, 0.1, stream(1))
		assertEq(f.Winner, 1)
		assertEq(ev[1].Kind, "TimeUp")
	end)

	test("pvp: SPECIAL needs a full meter and hits the other side", function()
		local a = team("a", { { "Mammoth", "Epic", 3 } })
		local b = team("b", { { "Raptor", "Common", 4 } })
		local f = PvpRules.newFight(a, b)
		local ok = PvpRules.useSpecial(f, 1, 0.5)
		assert(not ok, "empty meter refused")
		assert(not (PvpRules.useSpecial(f, 3, 0.5)), "bad side refused")
		f.Meters[1] = PvpConfig.SpecialCharge
		local ok2, ev = PvpRules.useSpecial(f, 1, 0.5)
		assert(ok2, "full meter fires")
		assertEq(f.Meters[1], 0)
		assertEq(ev[1].Kind, "Special")
		local sp = PetStats.special(f.Units[1].Special)
		if sp and (sp.Kind == "Stomp" or sp.Kind == "Dash" or sp.Kind == "Crit" or sp.Kind == "Chain") then
			assert(f.Units[2].Hp < f.Units[2].Max, "special damaged the foe")
		end
	end)

	test("pvp: rewards, streak, trophies never below 0, ranks", function()
		local w = PvpRules.outcome("Win", 100, 0, false)
		assertEq(w.Streak, 1)
		assertEq(w.Coins, PvpConfig.Rewards.WinCoins)
		assertEq(w.Trophies, PvpConfig.Rewards.WinTrophies)
		local w5 = PvpRules.outcome("Win", 100, 9, false)
		assertEq(w5.Coins, PvpConfig.Rewards.WinCoins + PvpConfig.Rewards.StreakCoins * PvpConfig.Rewards.StreakCap, "streak bonus capped")
		local l = PvpRules.outcome("Loss", 3, 4, false)
		assertEq(l.Streak, 0)
		assertEq(l.Trophies, -3, "never below 0")
		local bot = PvpRules.outcome("Win", 0, 0, true)
		assert(bot.Trophies < w.Trophies, "bots give fewer trophies")
		local d = PvpRules.outcome("Draw", 50, 2, false)
		assertEq(d.Trophies, 0)
		assertEq(d.Streak, 2)
		assertEq(PvpRules.rank(0).Name, "Bronze")
		assertEq(PvpRules.rank(450).Name, "Gold")
		local top, nxt = PvpRules.rank(99999)
		assertEq(top.Name, "Champion")
		assertEq(nxt, nil)
	end)

	test("rarity caps: Common 10, Rare 20, Epic 30, Legendary 50, Void Dragon 100; stats stop at the cap", function()
		local function cap(sp, r)
			return PetStats.cap({ Mineral = sp, Rarity = r })
		end
		assertEq(cap("Raptor", "Common"), 10)
		assertEq(cap("Raptor", "Rare"), 20)
		assertEq(cap("Raptor", "Epic"), 30)
		assertEq(cap("Raptor", "Legendary"), 50)
		assertEq(cap("CosmicDragon", "Legendary"), 100)
		local common = { Mineral = "Raptor", Rarity = "Common", Modifier = "Natural", Seed = 5 }
		assertEq(PetStats.roll(common, 1e7).Level, 10, "level stops at cap")
		assertEq(PvpRules.power(common, 1e7), PvpRules.power(common, 1e8), "no power past the cap")
		assert(PvpRules.maxed(common, 1e7) and not PvpRules.maxed(common, 0))
		local legend = { Mineral = "Raptor", Rarity = "Legendary", Modifier = "Natural", Seed = 5 }
		assert(PvpRules.power(legend, 0) > PvpRules.power(common, 0), "legendary starts stronger")
		assert(PvpRules.power(legend, 1e8) > PvpRules.power(common, 1e8), "maxed legendary beats maxed common")
		-- carter 2026-10-14: a maxed Common slightly beats a Lv 1 Legendary; a maxed Legendary wins (same species, seed)
		for _, sp in { "Raptor", "Mammoth", "Phoenix", "DireWolf" } do
			for seed = 1, 40 do
				local c = { Mineral = sp, Rarity = "Common", Modifier = "Natural", Seed = seed }
				local l = { Mineral = sp, Rarity = "Legendary", Modifier = "Natural", Seed = seed }
				local maxedCommon, freshLegend = PvpRules.power(c, 1e7), PvpRules.power(l, 0)
				assert(maxedCommon > freshLegend, sp .. " " .. seed .. ": maxed Common beats Lv 1 Legendary")
				assert(maxedCommon < freshLegend * 1.15, sp .. " " .. seed .. ": only slightly")
				assert(PvpRules.power(l, 1e8) > maxedCommon * 2, sp .. " " .. seed .. ": maxed Legendary wins by far")
			end
		end
	end)

	test("pvp: only Epic+ pets bring a SPECIAL", function()
		local low = team("a", { { "Raptor", "Rare", 1 }, { "Mammoth", "Common", 2 } })
		local high = team("b", { { "Raptor", "Epic", 3 } })
		local f = PvpRules.newFight(low, high)
		assert(not PvpRules.hasSpecial(f, 1), "no Epic+ on side 1")
		assert(PvpRules.hasSpecial(f, 2), "Epic on side 2")
		f.Meters[1], f.Meters[2] = PvpConfig.SpecialCharge, PvpConfig.SpecialCharge
		assert(not (PvpRules.useSpecial(f, 1, 0.5)), "refused without Epic+")
		assert((PvpRules.useSpecial(f, 2, 0.5)), "Epic fires")
	end)

	test("train: XP raises the level and the power number", function()
		local before, after, xp = PvpRules.train(0, 1000)
		assertEq(before, 1)
		assert(after > 1, "levelled up")
		assertEq(xp, 1000)
		local _, same = PvpRules.train(0, PvpConfig.Train.TapXp)
		assertEq(same, 1, "one tap is not a level")
	end)
	test("evolve: needs the cap and 2 free copies; raises cap, stats and stage", function()
		local function pet(id, extra)
			local g = { Id = id, Mineral = "Raptor", Rarity = "Common", Modifier = "Natural", Seed = 40 + #id }
			for k, v in extra or {} do
				g[k] = v
			end
			return g
		end
		local main = pet("m")
		local inv = { main, pet("c1"), pet("c22"), pet("fav", { Favorite = true }), pet("rare", { Rarity = "Rare" }), pet("evo", { Evolve = 1 }) }
		local xp = { m = 1e7, c1 = 50, c22 = 10 }
		local function xpOf(id)
			return xp[id] or 0
		end
		local ok, why, use = PvpRules.evolveCheck(main, xpOf, inv, {})
		assert(ok, tostring(why))
		assertEq(#use, 2)
		assertEq(use[1], "c22", "lowest XP copy used first")
		-- a following / displayed copy is never used up
		ok, why = PvpRules.evolveCheck(main, xpOf, inv, { c1 = true })
		assertEq(ok, false)
		assertEq(why, "Copies")
		-- not at the cap yet
		xp.m = 0
		ok, why = PvpRules.evolveCheck(main, xpOf, inv, {})
		assertEq(why, "Level")
		xp.m = 1e7
		local cap0, power0 = PetStats.cap(main), PvpRules.power(main, 1e7)
		main.Evolve = 1
		assertEq(PetStats.cap(main), cap0 + TowerConfig.Evolve.CapBonus, "cap goes up")
		assert(PvpRules.power(main, 1e7) > power0, "evolved pet is stronger")
		assert(not PvpRules.maxed(main, 0), "can train again")
		main.Evolve = TowerConfig.Evolve.MaxStage
		ok, why = PvpRules.evolveCheck(main, xpOf, inv, {})
		assertEq(why, "Stage", "last stage")
		assertEq(PetStats.stage({ Evolve = 99 }), TowerConfig.Evolve.MaxStage)
		assertEq(PetStats.stage({ Evolve = "x" }), 0)
		assertEq(PetStats.cap({ Mineral = "CosmicDragon", Rarity = "Legendary", Evolve = 2 }), TowerConfig.Levels.Max, "never past Max")
	end)
	test("arena board: the day's biggest win is the biggest upset; a new day starts over", function()
		local a = { Winner = "A", Loser = "B", WinnerPower = 300, LoserPower = 450, Day = 10 }
		local b = { Winner = "C", Loser = "D", WinnerPower = 500, LoserPower = 400, Day = 10 }
		local c = { Winner = "E", Loser = "F", WinnerPower = 100, LoserPower = 300, Day = 10 }
		assertEq(PvpRules.biggerWin(nil, b), b)
		assertEq(PvpRules.biggerWin(b, a), a, "an upset beats a plain win")
		assertEq(PvpRules.biggerWin(a, b), a)
		assertEq(PvpRules.biggerWin(a, c), c, "a bigger upset")
		local same = { Winner = "G", Loser = "H", WinnerPower = 300, LoserPower = 450, Day = 10 }
		assertEq(PvpRules.biggerWin(a, same), a, "ties keep the older")
		local tomorrow = { Winner = "I", Loser = "J", WinnerPower = 500, LoserPower = 100, Day = 11 }
		assertEq(PvpRules.biggerWin(c, tomorrow), tomorrow, "new day")
	end)
	test("one power number: battle power is the Pet Book POWER; xpForLevel reaches the cap", function()
		local pet = { Mineral = "Raptor", Rarity = "Rare", Modifier = "Natural", Seed = 31 }
		assertEq(PvpRules.power(pet, 500), PetStats.powerOfPet(pet, 500))
		local cap = PetStats.cap(pet)
		assertEq((PetStats.level(PetStats.xpForLevel(cap), cap)), cap, "xpForLevel(cap) is max")
		assertEq((PetStats.level(PetStats.xpForLevel(cap) - 1, cap)), cap - 1, "one short is not")
		assertEq(PetStats.xpForLevel(1), 0)
	end)
	test("pvp: the stadium layout keeps the two teams well apart, inside the floor (Studio: pets overlapped at +-6)", function()
		local L = shared("PvpConfig").Layouts.LiveBig
		assert(L.FoeZ - L.PetZ >= 20, "team lines at least 20 studs apart")
		assert(L.PetGap >= 8 and L.FoeGap >= 8, "pets in a line do not touch")
		assert(math.abs(L.StandZ) > math.abs(L.PetZ) + 6, "the player stands behind their own pets")
		assert(math.abs(L.StandZ) < 30 - 3, "and inside the 30-stud fight radius")
		assert(L.PetZ + L.FoeZ == 0, "the two sides mirror about the arena centre")
	end)
	test("pvp: two waiting players are matched before either gets a bot, whatever their power", function()
		local R = shared("PvpRules")
		local B = shared("PvpConfig").BotAfter
		assert(not R.canMatch(100, 1, 5000, 1), "a huge gap waits a little first")
		assert(R.canMatch(100, B, 5000, B - 3), "when the bot would step in, the other player is taken instead")
		assert(R.canMatch(5000, B - 3, 100, B), "either side's wait counts")
		assert(R.canMatch(100, 0, 110, 0), "close powers match at once")
	end)

	test("pvp: a rival who quits in the count-in or the first seconds gives a draw, not a win (no win-feeding)", function()
		assert(PvpRules.forfeitResult("CountIn", 0) == "Draw")
		assert(PvpRules.forfeitResult("Fighting", PvpConfig.ForfeitWinAfter - 0.1) == "Draw")
		assert(PvpRules.forfeitResult("Fighting", PvpConfig.ForfeitWinAfter) == "Win")
		local d = PvpRules.outcome("Draw", 100, 2, false)
		assert(d.Trophies == 0 and d.Streak == 2, "a draw gives no trophies and keeps the streak")
		local fs = require("@lune/fs")
		local src = fs.readFile("src/server/PvpService.luau")
		assert(string.find(src, "PvpRules.forfeitResult(f.ForfeitAt.Phase, f.ForfeitAt.Time)", 1, true), "settle pays the stayer by the rule")
		assert(string.find(src, "f.ForfeitAt = { Phase = f.Phase :: string, Time = f.Rules.Time }", 1, true), "forfeit records when")
	end)

	test("pvp: the fight splash power is the same POWER as the BATTLE card", function()
		local fs = require("@lune/fs")
		local src = fs.readFile("src/server/PvpService.luau")
		assert(not string.find(src, "u.Max / PvpConfig.HealthMult", 1, true), "no rebuilt (inflated) power")
		assert(string.find(src, "info.Power", 1, true))
		-- the inflation it removes: a levelled pet's unit HP carries speed growth, so rebuilding power overstated it
		local pet = { Id = "x", Mineral = "Raptor", Rarity = "Rare", Seed = 7 }
		local xp = 4000
		local tp = { Id = "1:1", Pet = pet, Xp = xp, Side = 1 }
		local ok, u = pcall(PvpRules.unit, tp :: any, 1)
		if ok and type(u) == "table" and u.Max then
			local rebuilt = PvpRules.petPower({ Power = u.Power, Health = u.Max / PvpConfig.HealthMult, Speed = u.Speed })
			assert(rebuilt >= PvpRules.power(pet, xp), "rebuilt power was never lower")
		end
	end)
end
