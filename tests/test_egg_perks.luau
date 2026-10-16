-- Reasons to want eggs (shared/EggPerks): Lucky Meter, Pet Book pages, free eggs. The server routes (meter in the
-- hatch, banked free eggs opening, page bonuses on coins and XP) are tested in tests/server/robux.luau.
return function(t)
	local test, shared, Random = t.test, t.shared, t.Random
	local Config = shared("Config")
	local RobuxConfig = shared("RobuxConfig")
	local EggPerks = shared("EggPerks")
	local GeodeGen = shared("GeodeGen")

	test("egg perks: lucky meter fills by egg kind, caps, and an Epic+ empties it", function()
		local need = EggPerks.Meter.Need
		local m = 0
		for _ = 1, need - 1 do
			m = EggPerks.meterAfter(m, "BasicEgg", "Common")
		end
		assert(not EggPerks.full(m), "29 basic eggs: not full")
		m = EggPerks.meterAfter(m, "BasicEgg", "Rare")
		assert(EggPerks.full(m) and m == need, "30th basic egg fills it")
		assert(EggPerks.meterAfter(m, "MythicEgg", "Common") == need, "never above Need")
		assert(EggPerks.meterAfter(m, "BasicEgg", "Epic") == 0, "Epic empties")
		assert(EggPerks.meterAfter(17, "RareEgg", "Legendary") == 0, "Legendary empties")
		assert(EggPerks.meterAfter(0, "RareEgg", "Common") == 3 and EggPerks.meterAfter(0, "MythicEgg", "Uncommon") == 8, "points")
		assert(EggPerks.meterAfter(0, "SomethingNew", "Common") == 1, "unknown egg = 1 point")
	end)

	test("egg perks: a pity egg is Epic+ and keeps the egg's own Legendary chance (1 in 1000 stays 1 in 1000)", function()
		for _, egg in RobuxConfig.Eggs do
			local base = RobuxConfig.eggRarity(egg)
			local sum = 0
			for _, r in Config.Rarities do
				sum += base[r]
			end
			local w = EggPerks.pityWeights(base)
			assert(w.Common == 0 and w.Uncommon == 0 and w.Rare == 0, egg.Id .. ": nothing below Epic")
			assert(math.abs(w.Epic + w.Legendary - 100) < 1e-9, egg.Id .. ": sums to 100")
			assert(math.abs(w.Legendary - 100 * base.Legendary / sum) < 1e-9, egg.Id .. ": Legendary unchanged")
		end
		assert(math.abs(EggPerks.pityWeights(nil).Legendary - 0.1) < 1e-9, "Basic: Void Dragon 1 in 1000")
		-- rolled through the real GeodeGen: 2000 pity rolls, never below Epic
		local rng = Random.new(7)
		for i = 1, 2000 do
			local pet = GeodeGen.roll(rng, "Meteor", "id" .. i, "k" .. i, os.time(), true, 0, EggPerks.pityWeights(nil))
			assert(pet.Rarity == "Epic" or pet.Rarity == "Legendary", "pity roll " .. pet.Rarity)
		end
	end)

	test("egg perks: pet book pages need every normal pet of the zone (no chase, weekly or tower pets)", function()
		local meadow = EggPerks.pageSpecies("Gravel")
		assert(#meadow > 0, "meadow page has pets")
		for _, id in meadow do
			local sp = Config.Minerals[id]
			assert(not sp.Chase and not sp.Weekly and not sp.TowerOnly, id .. " belongs on the page")
		end
		assert(not table.find(meadow, "SunpetalDrake"), "chase pet not needed")
		assert(not table.find(EggPerks.pageSpecies("Meteor"), "CosmicDragon"), "Void Dragon not needed")
		assert(#EggPerks.pageSpecies("Nope") == 0, "unknown zone")
		local index = {}
		assert(EggPerks.pagesDone(index) == 0 and EggPerks.coinMult(index) == 1 and EggPerks.xpMult(index) == 1, "empty book")
		for i, id in meadow do
			index[id] = 1
			local just = EggPerks.pageJustDone(index, id)
			if i < #meadow then
				assert(just == nil, "not done yet")
			else
				assert(just and just.Tier == "Gravel" and just.Done, "last meadow pet completes the page")
			end
		end
		assert(EggPerks.pagesDone(index) == 1, "one page")
		assert(math.abs(EggPerks.coinMult(index) - 1.1) < 1e-9 and math.abs(EggPerks.xpMult(index) - 1.1) < 1e-9, "+10%")
		index[meadow[1]] = 2
		assert(EggPerks.pageJustDone(index, meadow[1]) == nil, "a second copy does not complete it again")
		for _, tid in Config.TierOrder do
			for _, id in EggPerks.pageSpecies(tid) do
				index[id] = 1
			end
		end
		assert(EggPerks.pagesDone(index) == #Config.TierOrder, "every page")
		assert(math.abs(EggPerks.coinMult(index) - 1.5) < 1e-9, "+50% with all five pages")
		assert(EggPerks.pagesDone("bad") == 0, "bad index")
	end)

	test("egg perks: a full egg bank never eats a fight or quest egg (it is paid once there is room)", function()
		local s = EggPerks.empty()
		for _ = 1, EggPerks.Free.BankMax do
			EggPerks.bankAdd(s, "BasicEgg")
		end
		local per = EggPerks.Free.FightWinsPerEgg
		for _ = 1, per - 1 do
			assert(EggPerks.fightWin(s) == nil)
		end
		assert(EggPerks.fightWin(s) == nil, "bank full: no egg yet")
		assert(EggPerks.winsToEgg(s) == 1, "the egg win is still owed")
		assert(EggPerks.questsDone(s, 200) == nil, "bank full: quest egg not paid")
		EggPerks.bankTake(s)
		EggPerks.bankTake(s)
		assert(EggPerks.fightWin(s) == EggPerks.Free.FightEgg, "room again: next win pays the egg")
		assert(EggPerks.questsDone(s, 200) == EggPerks.Free.QuestEgg, "room again: today's quest egg pays")
		assert(EggPerks.questsDone(s, 200) == nil, "still once a day")
	end)

	test("egg perks: free eggs from fights and quests bank, cap, and open best first", function()
		local s = EggPerks.empty()
		assert(EggPerks.fightWin(s) == nil and EggPerks.fightWin(s) == nil, "wins 1, 2: nothing")
		assert(EggPerks.winsToEgg(s) == 1, "one win to go")
		assert(EggPerks.fightWin(s) == "BasicEgg", "3rd win: basic egg")
		assert(EggPerks.winsToEgg(s) == 3, "counter restarts")
		assert(EggPerks.questsDone(s, 100) == "RareEgg", "all quests: rare egg")
		assert(EggPerks.questsDone(s, 100) == nil, "once per day")
		assert(EggPerks.questsDone(s, 101) == "RareEgg", "next day again")
		assert(EggPerks.bankCount(s) == 3, "three banked")
		assert(EggPerks.bankTake(s) == "RareEgg" and EggPerks.bankTake(s) == "RareEgg" and EggPerks.bankTake(s) == "BasicEgg", "best first")
		assert(EggPerks.bankTake(s) == nil, "empty")
		for _ = 1, EggPerks.Free.BankMax do
			assert(EggPerks.bankAdd(s, "BasicEgg"), "room")
		end
		assert(not EggPerks.bankAdd(s, "BasicEgg"), "bank is capped")
		assert(not EggPerks.bankAdd(EggPerks.empty(), "GoldenEgg"), "unknown egg never banks")
		assert(EggPerks.eggName("RareEgg") == "Rare Egg", "names")
	end)

	test("egg perks: sanitize repairs saves and keeps banked eggs", function()
		local e = EggPerks.sanitize(nil)
		assert(e.Meter == 0 and EggPerks.bankCount(e) == 0, "nil -> empty")
		local s = EggPerks.sanitize({ Meter = 999, Bank = { RareEgg = 2, BasicEgg = "x", Fake = 4 }, FightWins = -3, QuestDay = 0 / 0 })
		assert(s.Meter == EggPerks.Meter.Need, "meter clamped")
		assert(s.Bank.RareEgg == 2 and s.Bank.BasicEgg == nil and s.Bank.Fake == nil, "bank repaired")
		assert(s.FightWins == 0 and s.QuestDay == 0, "counters repaired")
		local v = EggPerks.view(s, {})
		assert(v.MeterNeed == EggPerks.Meter.Need and v.Bank == 2 and #v.Pages == #Config.TierOrder, "view")
	end)
end
