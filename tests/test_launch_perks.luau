-- Launch picks (shared/LaunchPerks + the RobuxConfig money additions): day 7 egg, spin wheel, shiny pets, lucky hour,
-- VIP luck, starter pack and limited egg lookups, the Open 3 Eggs gate, the WOW / shiny rare-hatch lines.
return function(t)
	local test, shared = t.test, t.shared
	local Config = shared("Config")
	local RobuxConfig = shared("RobuxConfig")
	local LuckEvents = shared("LuckEvents")
	local GeodeGen = shared("GeodeGen")
	local LaunchPerks = shared("LaunchPerks")
	local PetFlair = shared("PetFlair")
	local EggPerks = shared("EggPerks")

	test("launch: day 7 of the streak banks a free Rare Egg, other days nothing", function()
		for d = 1, 6 do
			assert(LaunchPerks.streakEgg(d) == nil, "day " .. d)
		end
		assert(LaunchPerks.streakEgg(7) == "RareEgg", "day 7")
		assert(table.find(EggPerks.Free.Order, LaunchPerks.StreakEgg.Egg), "the bank takes that egg")
	end)

	test("launch: shiny is about 1 in 100, decided by the seed alone, and doubles value", function()
		local n, N = 0, 200000
		for seed = 1, N do
			if LaunchPerks.shinyFromSeed(seed) then
				n += 1
			end
		end
		local rate = n / N
		assert(rate > 0.008 and rate < 0.012, "rate " .. rate)
		assert(LaunchPerks.shinyFromSeed(12345) == LaunchPerks.shinyFromSeed(12345), "same seed same answer")
		assert(not LaunchPerks.shinyFromSeed(nil) and not LaunchPerks.shinyFromSeed(0 / 0), "bad seeds are not shiny")
		local k = 0
		for seed = 1, 20000 do
			if LaunchPerks.shinyFromSeed(seed, 10) then
				k += 1
			end
		end
		assert(k / 20000 > 0.08 and k / 20000 < 0.12, "1 in 10 egg")
		assert(GeodeGen.value("Gravel", "Rare", "Natural", 2, true) == math.floor(2 * (Config.Tiers.Gravel.GeodeBase * Config.RarityMult.Rare * 1.25)), "2x value")
	end)

	test("launch: shiny never changes the other rolls, and shows in the name", function()
		local shinies = 0
		for i = 1, 3000 do
			local a = GeodeGen.roll(t.Random.new(i), "Gravel", "x", "k", 0, true)
			local b = GeodeGen.roll(t.Random.new(i), "Gravel", "x", "k", 0, true, 0, nil, 1) -- every pet shiny
			assert(a.Rarity == b.Rarity and a.Mineral == b.Mineral and a.Modifier == b.Modifier and a.Mass == b.Mass and a.Seed == b.Seed, "same rolls")
			assert(b.Shiny == true and b.Value == math.floor(GeodeGen.value("Gravel", b.Rarity, b.Modifier, b.Mass) * 2) or b.Value == GeodeGen.value("Gravel", b.Rarity, b.Modifier, b.Mass, true), "shiny value")
			if a.Shiny then
				shinies += 1
				assert(string.sub(GeodeGen.displayName(a), 1, 6) == "Shiny ", "name")
			else
				assert(a.Shiny == nil, "not shiny = no field")
			end
		end
		assert(shinies > 10 and shinies < 60, "about 30 shinies in 3000: " .. shinies)
		assert(GeodeGen.public({ Shiny = true } :: any).Shiny == true, "public view carries it")
	end)

	test("launch: rare hatch announces shiny pets of any rarity and says WOW for a Legendary", function()
		assert(PetFlair.payload("Ava", "Shiny Bunny", "Common") ~= nil, "shiny common announced")
		assert(PetFlair.payload("Ava", "Bunny", "Common") == nil, "plain common not")
		local p = PetFlair.payload("Ava", "Void Dragon", "Legendary") :: any
		assert(string.sub(PetFlair.bannerLine(p), 1, 4) == "WOW!", "WOW line")
		assert(string.sub(PetFlair.bannerLine(PetFlair.payload("Ava", "Fox", "Rare") :: any), 1, 3) == "Ava", "plain line")
	end)

	test("launch: spin wheel pays one slice every 4 hours, weights sum to 100", function()
		local total = 0
		for _, sl in LaunchPerks.Spin.Slices do
			total += sl.Weight
			assert(sl.Kind == "Coins" or sl.Kind == "Potion" or sl.Kind == "Egg", sl.Id)
			if sl.Kind == "Egg" then
				assert(RobuxConfig.egg(sl.Egg) and table.find(EggPerks.Free.Order, sl.Egg), sl.Id .. " bankable egg")
			end
		end
		assert(math.abs(total - 100) < 1e-9, "weights " .. total)
		local s = LaunchPerks.empty()
		local now = 1791590400
		local sl, why = LaunchPerks.spin(s, now, 0)
		assert(sl and why == nil and sl.Id == LaunchPerks.Spin.Slices[1].Id, "first spin free, r=0 = first slice")
		assert(LaunchPerks.spin(s, now + 3600, 0.5) == nil, "too soon")
		assert(LaunchPerks.spinLeft(s, now + 3600) == 3 * 3600, "3 h left")
		local last = LaunchPerks.spin(s, now + 4 * 3600, 0.9999999)
		assert(last and last.Id == LaunchPerks.Spin.Slices[#LaunchPerks.Spin.Slices].Id and s.Spins == 2, "r near 1 = last slice")
		-- coins grow with the zone and never round to 0
		local small = LaunchPerks.slice("CoinsS")
		assert(small and LaunchPerks.sliceCoins(small, "Gravel") >= 10, "meadow coins")
		local tiers = {}
		for id, tier in Config.Tiers do
			table.insert(tiers, { id, tier.Order })
		end
		table.sort(tiers, function(a, b)
			return a[2] < b[2]
		end)
		local prev = 0
		for _, row in tiers do
			local c = LaunchPerks.sliceCoins(small :: any, row[1])
			assert(c >= prev, row[1] .. " coins grow")
			prev = c
		end
		assert(LaunchPerks.sanitize({ SpinAt = "x", Spins = -3, AutoEgg = 5 }).Spins == 0, "sanitize")
	end)

	test("launch: lucky hour is on at the set UTC hours and adds luck", function()
		local day = 1791590400 + 2 * 86400 -- a Monday (no weekend luck)
		for _, h in RobuxConfig.Events.LuckyHours do
			local at = day + h * 3600 + 60
			assert(LaunchPerks.luckyHourUntil(at) == day + h * 3600 + RobuxConfig.Events.LuckyHourMinutes * 60, "on at " .. h)
			assert(LuckEvents.timed(at, 0, 0).Hour == RobuxConfig.Events.LuckyHourLuck, "timed source")
			assert(LaunchPerks.nextLuckyHour(at) == 0, "on now")
		end
		local quiet = day + 3 * 3600
		assert(LaunchPerks.luckyHourUntil(quiet) == 0 and LuckEvents.timed(quiet, 0, 0).Hour == 0, "off at 3 am")
		assert(LaunchPerks.nextLuckyHour(quiet) == (RobuxConfig.Events.LuckyHours[1] - 3) * 3600, "next one counts down")
		assert(LuckEvents.total({ Hour = 1, Vip = RobuxConfig.VipLuck }) == 1 + RobuxConfig.VipLuck, "hour + VIP add up")
	end)

	test("launch: VIP luck, Open 3 gate and starter pack lookups", function()
		assert(RobuxConfig.vipLuck({ Passes = { VIP = true } }) == RobuxConfig.VipLuck and RobuxConfig.vipLuck({ Passes = {} }) == 0, "VIP")
		-- 3x / 10x coin eggs need the Open 3 Eggs pass once it has an id; with id 0 nobody is locked out
		local passId = RobuxConfig.Passes.TripleHatch.PassId
		assert(passId == 2036792742, "carter's Open 3 Eggs pass id")
		assert(RobuxConfig.countPass(3) == "TripleHatch" and RobuxConfig.countPass(10) == "TripleHatch" and RobuxConfig.countPass(1) == nil, "gated")
		RobuxConfig.Passes.TripleHatch.PassId = 0
		assert(RobuxConfig.countPass(3) == nil and RobuxConfig.countPass(10) == nil, "id 0: not gated")
		RobuxConfig.Passes.TripleHatch.PassId = passId
		for _, key in RobuxConfig.PassOrder do
			assert(RobuxConfig.Passes[key], key .. " exists")
		end
		assert(RobuxConfig.StarterPack.ProductId == 3718841132, "carter's Starter Pack product id")
		assert(RobuxConfig.productKind(0) == nil, "id 0 sells nothing")
		assert(RobuxConfig.productKind(3718841132) == "Pack", "pack receipt route")
		local kind, e, n = RobuxConfig.productKind(3718841562)
		assert(kind == "Egg" and e and e.Id == "SpookyEgg" and n == 3, "Spooky Egg x3 receipt route")
		assert(RobuxConfig.sanitize({}).StarterPack == false, "fresh state")
		local st = RobuxConfig.emptyState()
		RobuxConfig.addPotion(st, 1000, 300)
		assert(st.LuckUntil == 1300, "free potion minutes")
	end)

	test("launch: limited egg is hidden until its end time is set and never worse than race odds", function()
		local egg = RobuxConfig.egg("SpookyEgg")
		assert(egg and egg.Limited, "found by id")
		local ends = egg.EndsAt
		assert(ends == 1793577600, "on sale until 2026-11-02 00:00 UTC")
		egg.EndsAt = 0
		assert(not RobuxConfig.eggOnSale(egg, os.time()), "EndsAt 0 = not on sale")
		assert(LaunchPerks.limitedEgg(os.time()) == nil, "no card")
		egg.EndsAt = 2000
		assert(RobuxConfig.eggOnSale(egg, 1999) and not RobuxConfig.eggOnSale(egg, 2000), "sold until EndsAt")
		local e2, left = LaunchPerks.limitedEgg(1500)
		assert(e2 == egg and left == 500, "card with time left")
		egg.EndsAt = ends
		local w = RobuxConfig.eggRarity(egg)
		local race = Config.RarityWeights :: any
		for i = 1, #Config.Rarities do
			local mine, base = 0, 0
			for j = i, #Config.Rarities do
				mine += w[Config.Rarities[j]]
				base += race[Config.Rarities[j]]
			end
			assert(mine >= base - 1e-9, Config.Rarities[i] .. " or better")
		end
		local carters = { [1] = 3718841224, [3] = 3718841562, [10] = 3718841645 }
		for _, n in RobuxConfig.EggCounts do
			assert(egg.Products[n] == carters[n], "carter's Spooky Egg product id x" .. n)
		end
		assert(RobuxConfig.CoinEggs.Rounds.SpookyEgg == nil, "Robux only (no coin price)")
		local v = LaunchPerks.view(LaunchPerks.empty(), { StarterPack = true }, ends)
		assert(v.StarterPack == true and v.SpinIn == 0 and v.Limited == nil, "view (sale over)")
	end)

	test("spin: no prize line (and no empty green bar) until the wheel lands", function()
		assert(LaunchPerks.spinWon(nil) == nil and LaunchPerks.spinWon("") == nil and LaunchPerks.spinWon("  ") == nil, "nothing yet")
		assert(LaunchPerks.spinWon("+500 coins") == "YOU WON +500 COINS!", "the prize line")
		local fs = require("@lune/fs")
		local panel = fs.readFile("src/client/ui/SpinPanel.luau")
		assert(string.find(panel, 'Name = "Result", Size = UDim2.new(1, 0, 0, 48), BackgroundColor3 = K.Lime, LayoutOrder = 3, Visible = false', 1, true), "the pill starts hidden")
		assert(string.find(panel, "pill.Visible = line ~= nil", 1, true), "shown only with a prize line")
	end)
end
