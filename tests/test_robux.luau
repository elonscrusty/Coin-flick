-- Robux shop rules (shared/RobuxConfig, shared/LuckEvents): luck stacking and clamp, weekend detection, egg odds,
-- the receipt ledger, product lookup and pass effects. The real receipt flow is tested in tests/server/robux.luau.
return function(t)
	local test, shared = t.test, t.shared
	local Config = shared("Config")
	local RobuxConfig = shared("RobuxConfig")
	local LuckEvents = shared("LuckEvents")
	local GeodeGen = shared("GeodeGen")
	local SpeciesPool = shared("SpeciesPool")

	local function near(a: number, b: number, msg: string)
		assert(math.abs(a - b) < 1e-9, msg .. ": " .. tostring(a) .. " vs " .. tostring(b))
	end

	test("robux: luck sources add up and clamp to MaxLuck", function()
		near(LuckEvents.total({}), 0, "nothing")
		near(LuckEvents.total({ Pet = 0.3, Friends = 0.1 }), 0.4, "pet + friends")
		near(LuckEvents.total({ Pet = 0.2, Potion = 1, Weekend = 1 }), 2.2, "potion + weekend stack")
		near(LuckEvents.total({ Pet = 2, Friends = 1, Potion = 1, Weekend = 1, Storm = 1 }), RobuxConfig.MaxLuck, "clamped")
		near(LuckEvents.total({ Pet = -5, Potion = 0 / 0, Storm = 1 }), 1, "bad numbers count as 0")
		assert(RobuxConfig.MaxLuck >= 1 and RobuxConfig.MaxLuck <= 5, "sensible cap")
		-- the roll itself never goes past the cap either
		near(GeodeGen.rarityWeights(99).Legendary, Config.RarityWeights.Legendary * (1 + RobuxConfig.MaxLuck), "roll clamp")
	end)

	test("robux: timed sources (potion, weekend UTC, storm)", function()
		local sat = 1791590400 -- Saturday 2026-10-10 00:00 UTC
		assert(LuckEvents.isWeekend(sat), "Saturday")
		assert(LuckEvents.isWeekend(sat + 86400 + 3600), "Sunday")
		assert(not LuckEvents.isWeekend(sat + 2 * 86400 + 60), "Monday")
		assert(not LuckEvents.isWeekend(sat - 60), "Friday 23:59")
		local mon = sat + 2 * 86400 + 3600
		local t0 = LuckEvents.timed(mon, 0, 0)
		assert(t0.Potion == 0 and t0.Weekend == 0 and t0.Storm == 0, "nothing on a Monday")
		local t1 = LuckEvents.timed(mon, mon + 10, mon + 10)
		assert(t1.Potion == RobuxConfig.Potion.Luck and t1.Storm == RobuxConfig.Events.StormLuck, "potion + storm running")
		local t2 = LuckEvents.timed(mon, mon, mon - 1)
		assert(t2.Potion == 0 and t2.Storm == 0, "ended exactly now = off")
		local g = LuckEvents.nextGap(t.Random.new(3))
		assert(g >= RobuxConfig.Events.StormGapMin and g <= RobuxConfig.Events.StormGapMax, "storm gap in range")
	end)

	test("robux: potion stacking extends the timer", function()
		local s = RobuxConfig.emptyState()
		RobuxConfig.addPotion(s, 1000)
		assert(s.LuckUntil == 1000 + RobuxConfig.Potion.Seconds)
		RobuxConfig.addPotion(s, 1100)
		assert(s.LuckUntil == 1000 + 2 * RobuxConfig.Potion.Seconds, "second potion adds to the end")
		assert(RobuxConfig.potionLeft(s, 1100) == 2 * RobuxConfig.Potion.Seconds - 100)
		RobuxConfig.addPotion(s, s.LuckUntil + 500) -- expired: starts again from now
		assert(RobuxConfig.potionLeft(s, s.LuckUntil - RobuxConfig.Potion.Seconds) == RobuxConfig.Potion.Seconds)
	end)

	test("robux: egg odds are the real roll odds and every table is valid", function()
		local basic = RobuxConfig.egg("BasicEgg")
		local o = LuckEvents.eggOdds("Gravel", 0, RobuxConfig.eggRarity(basic))
		local sum = 0
		for _, r in o.Rarity do
			sum += r.P
			if r.Name == "Legendary" then
				near(r.P, 0.001, "Basic = race odds, Legendary 1 in 1000")
			end
		end
		near(sum, 1, "rarity odds sum")
		local vs = 0
		for _, v in o.Variant do
			vs += v.P
		end
		near(vs, 1, "variant odds sum")
		assert(#o.Species == #SpeciesPool.list("Gravel", os.time()), "zone species listed")
		local sp = 0
		for _, row in o.SpeciesP do
			sp += row.P
		end
		near(sp, 1, "species odds sum")
		for _, egg in RobuxConfig.Eggs do
			local w = RobuxConfig.eggRarity(egg)
			local total = 0
			for _, r in Config.Rarities do
				assert((w[r] or 0) > 0, egg.Id .. " can roll " .. r)
				total += w[r]
			end
			near(total, 100, egg.Id .. " sums to 100")
			for _, r in { "Rare", "Epic", "Legendary" } do
				assert(w[r] >= Config.RarityWeights[r], egg.Id .. " at least race odds for " .. r)
			end
			for _, n in RobuxConfig.EggCounts do
				assert(egg.Products[n] == 0, "ids stay 0 until the owner pastes them")
			end
		end
		-- never worse than a race egg: for every rarity, the chance of that rarity OR BETTER is at least the race odds,
		-- and the odds the card prints sum to 100% for every egg in every zone
		local race = Config.RarityWeights :: any
		for _, egg in RobuxConfig.Eggs do
			local w = RobuxConfig.eggRarity(egg)
			for i = 1, #Config.Rarities do
				local mine, base = 0, 0
				for j = i, #Config.Rarities do
					mine += w[Config.Rarities[j]]
					base += race[Config.Rarities[j]]
				end
				assert(mine >= base - 1e-9, ("%s: %s or better %.2f below race %.2f"):format(egg.Id, Config.Rarities[i], mine, base))
			end
			for tierId in Config.Tiers :: any do
				local eo = LuckEvents.eggOdds(tierId, 0, w)
				local s2 = 0
				for _, r in eo.Rarity do
					s2 += r.P
				end
				near(s2, 1, egg.Id .. " " .. tierId .. " printed odds sum to 100%")
			end
		end
		-- every Robux id stays 0 + REPLACE until the owner pastes real ones (never invented here); the pasted ones are
		-- carter's, copied from his Creator Hub screenshots (2026-10-15)
		assert(RobuxConfig.Potion.ProductId == 0, "potion product id stays 0")
		local carters = { VIP = 2039996496, AutoHatch = 2040326268, TripleHatch = 2036792742 }
		for key, pass in RobuxConfig.Passes do
			assert(pass.PassId == (carters[key] or 0), key .. " pass id: carter's or 0")
		end
		assert(next(RobuxConfig.LegacyProducts) == nil, "no legacy ids invented")
		assert(LuckEvents.chanceText(0.001) == "0.1% (1 in 1000)", LuckEvents.chanceText(0.001))
	end)

	test("robux: zone of a bought egg = best unlocked zone", function()
		assert(RobuxConfig.eggTier({ Gravel = true }) == "Gravel")
		assert(RobuxConfig.eggTier({ Gravel = true, Cavern = true, Quarry = true }) == "Cavern")
		assert(RobuxConfig.eggTier(nil) == "Gravel")
	end)

	test("robux: receipt ledger is idempotent and bounded", function()
		local s = RobuxConfig.emptyState()
		assert(not RobuxConfig.granted(s, "A"))
		RobuxConfig.remember(s, "A")
		RobuxConfig.remember(s, "A")
		assert(RobuxConfig.granted(s, "A") and #s.ReceiptOrder == 1, "one entry")
		for i = 1, RobuxConfig.ReceiptsKept + 5 do
			RobuxConfig.remember(s, "r" .. i)
		end
		assert(#s.ReceiptOrder == RobuxConfig.ReceiptsKept, "bounded")
		assert(not RobuxConfig.granted(s, "A") and RobuxConfig.granted(s, "r" .. (RobuxConfig.ReceiptsKept + 5)), "oldest dropped")
	end)

	test("robux: product ids 0 match nothing; real ids map to egg + count", function()
		assert(RobuxConfig.productKind(0) == nil and RobuxConfig.passKey(0) == nil, "id 0 is never a product")
		local egg = RobuxConfig.egg("MythicEgg")
		egg.Products[10] = 777
		local kind, item, n = RobuxConfig.productKind(777)
		egg.Products[10] = 0
		assert(kind == "Egg" and item == egg and n == 10, "10x Mythic")
	end)

	test("robux: pass effects and save repair", function()
		local s = RobuxConfig.emptyState()
		assert(RobuxConfig.coinMult(s) == 1 and RobuxConfig.inventoryMax(500, s) == 500)
		s.Passes.DoubleCoins = true
		s.Passes.PetStorage = true
		assert(RobuxConfig.coinMult(s) == RobuxConfig.CoinMult)
		assert(RobuxConfig.inventoryMax(500, s) == 500 + RobuxConfig.ExtraPetSlots)
		local bad = RobuxConfig.sanitize({ Receipts = "x", LuckUntil = 0 / 0, Passes = { DoubleCoins = true, Junk = 5 } })
		assert(type(bad.Receipts) == "table" and bad.LuckUntil == 0 and bad.Passes.DoubleCoins == true and bad.Passes.Junk == nil)
		assert(type(RobuxConfig.sanitize(nil).ReceiptOrder) == "table")
	end)
	test("hatch odds line: whole numbers only, no line for a common result (no more \"1 in 1.5?\")", function()
		assert(LuckEvents.oneIn(1 / 1.5, "Rare") == nil, "better than 1 in 10: no line")
		assert(LuckEvents.oneIn(0.6, "Uncommon") == nil)
		assert(LuckEvents.oneIn(1 / 250, "Common") == nil, "Common never shows odds")
		assert(LuckEvents.oneIn(1 / 249.6, "Rare") == 250, "rounded to a whole number")
		assert(LuckEvents.oneIn(0.004, "Epic") == 250)
		assert(LuckEvents.oneIn(0, "Rare") == nil and LuckEvents.oneIn(0 / 0, "Rare") == nil)
		for k = 1, 2000 do
			local n = LuckEvents.oneIn(1 / (k * 0.37), "Legendary")
			assert(n == nil or (n == math.floor(n) and n >= 10), "whole and at least 10")
		end
		local src = require("@lune/fs").readFile("src/client/RevealView.luau")
		assert(string.find(src, "LuckEvents.oneIn(p, spec.Rarity)", 1, true), "the reveal uses the rule")
	end)
end
