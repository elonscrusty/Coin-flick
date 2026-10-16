-- Grind speed (item 14): a deterministic model of one kid playing solo, built from the REAL tuning (Config, ProgressConfig,
-- RobuxConfig coin eggs, TowerConfig / TowerRules, PvpConfig, Retention, EggConfig.Overtime). It answers: is the next
-- coin goal always a few minutes away early on, and never a wall later; how long until a pet reaches each level cap.
--
-- The kid's loop (repeated): 3 hunts in the best unlocked zone, 1 tower run, 2 pet battles, 1 minute of tap training.
-- Every coin is spent greedily on the cheapest one-time upgrade it can afford (tool, basket, nest, candy bag, display,
-- machine, zone unlock); pets are kept, never sold. Model assumptions (not measured in Studio, tune here if a playtest
-- disagrees):
--   * per egg: 0.6 s to pick it up (Carry.PickupInterval 0.45), the tool's crack time (HP / damage, at least one hit, at
--     the tool's rate; 0.3 s with a machine at the nest), and a 4 s round trip to the nest (Station.Radius 25 studs at
--     walk speed 16) shared by the basket's eggs; a full candy bag costs a 10 s walk
--     to the candy stand.
--   * a solo hunt ends when the pet egg is cracked: on average after half the pile (Tier.Rocks / 2 eggs), but never
--     later than the Overtime glow (EggConfig.Overtime.RoundSeconds) + 15 s; plus 35 s of countdown / reveal / results.
--   * tower run: one floor a minute from the checkpoint up to the band's boss, who falls every second run.
--   * battles: 90 s each (queue, count-in, fight, result), won 3 times in 5 (bots aim at 95% of the player's power).
--   * tap training: 3 taps a second for one minute per loop (PvpConfig.Train caps at TapsPerSecond).
--   * day one: the daily gift (day 1), the play-time gifts, and the middle reward of each of the 3 daily quests.
-- Targets: first coin upgrade within 5 min; 5+ coin goals and something new (upgrade, new species, first tower run /
-- battle / training) at most 6 min apart in the first 30 min; coin goals at most 20 min apart up to 2 h, 40 min to 4 h.
return function(t)
	local test, shared = t.test, t.shared
	local Config = shared("Config")
	local ProgressConfig = shared("ProgressConfig")
	local RobuxConfig = shared("RobuxConfig")
	local TowerRules = shared("TowerRules")
	local PvpConfig = shared("PvpConfig")
	local Retention = shared("Retention")
	local EggConfig = shared("EggConfig")
	local PetStats = shared("PetStats")
	local TowerConfig = shared("TowerConfig")

	local function simulate(minutes: number)
		local now = 0 -- seconds of play
		local cash = 0
		local events: { { T: number, What: string, Coin: boolean } } = {}
		local function event(what: string, coin: boolean?)
			table.insert(events, { T = now, What = what, Coin = coin ~= false })
		end
		local lv = { Handheld = 1, Basket = 1, Nest = 1, Capacity = 1, Display = 1, Machine = 0 }
		local unlocked = { Gravel = true }
		local finds = 0
		local seen: { [string]: boolean } = {}
		local xp = 0 -- the kid's main pet (follows them, leads the team)
		local towerBest = 0
		local giftsPaid = 0
		local function zone(): string
			local best = "Gravel"
			for _, id in Config.TierOrder do
				if unlocked[id] then
					best = id
				end
			end
			return best
		end
		local function playGifts()
			local P = Retention.PlayGifts
			while giftsPaid < #P.Marks and now >= P.Marks[giftsPaid + 1] do
				giftsPaid += 1
				cash += P.Coins[giftsPaid]
			end
		end
		-- the cheapest one-time upgrade the kid can buy now (nil = none affordable)
		local function shop()
			local bought = true
			while bought do
				bought = false
				local offers: { { Price: number, Buy: () -> (), Name: string } } = {}
				local h = Config.Handhelds[Config.HandheldOrder[lv.Handheld + 1] or ""]
				if h then
					table.insert(offers, { Price = h.Price, Name = h.Name, Buy = function() lv.Handheld += 1 end })
				end
				local b = ProgressConfig.Baskets[lv.Basket + 1]
				if b then
					table.insert(offers, { Price = b.Price, Name = b.Name, Buy = function() lv.Basket += 1 end })
				end
				local n = ProgressConfig.Nests[lv.Nest + 1]
				if n then
					table.insert(offers, { Price = n.Price, Name = n.Name, Buy = function() lv.Nest += 1 end })
				end
				local c = Config.Capacity[lv.Capacity + 1]
				if c then
					table.insert(offers, { Price = c.Price, Name = "Candy bag " .. c.Size, Buy = function() lv.Capacity += 1 end })
				end
				local d = Config.Display[lv.Display + 1]
				if d then
					table.insert(offers, { Price = d.Price, Name = "Display " .. d.Slots, Buy = function() lv.Display += 1 end })
				end
				local mid = Config.MachineOrder[lv.Machine + 1]
				if mid and Config.MachinesEnabled then
					table.insert(offers, { Price = Config.Machines[mid].Price, Name = Config.Machines[mid].Name, Buy = function() lv.Machine += 1 end })
				end
				for _, id in Config.TierOrder do
					local tier = Config.Tiers[id]
					if not unlocked[id] and finds >= tier.UnlockFinds then
						table.insert(offers, { Price = tier.UnlockCash, Name = tier.Name .. " unlock", Buy = function() unlocked[id] = true end })
						break
					end
				end
				table.sort(offers, function(a, b2)
					return a.Price < b2.Price
				end)
				local o = offers[1]
				if o and o.Price <= cash then
					cash -= o.Price
					o.Buy()
					event(o.Name)
					bought = true
				end
			end
		end
		local function spend(sec: number)
			now += sec
			xp += math.floor(sec / PvpConfig.Train.IdleEvery) * PvpConfig.Train.IdleXp
			playGifts()
		end
		local function hunt()
			local tier = Config.Tiers[zone()]
			local tool = Config.Handhelds[Config.HandheldOrder[lv.Handheld]]
			local crack = if lv.Machine > 0 then 0.3 else math.max(math.ceil(tier.HP / tool.Damage), 1) / tool.Rate
			local carry = ProgressConfig.carry(lv.Basket)
			local bag = Config.Capacity[lv.Capacity].Size
			local perEgg = 0.6 + crack + 4 / carry + 10 / bag
			local cap = EggConfig.Overtime.RoundSeconds
			local eggs = math.min(tier.Rocks / 2, math.floor(cap / perEgg))
			spend(eggs * perEgg + (if eggs < tier.Rocks / 2 then 15 else 0) + 35)
			cash += eggs * tier.CashPerRubble
			xp += eggs * PvpConfig.Hunt.CrackXp + PvpConfig.Hunt.FoundXp
			finds += 1
			-- species of the zone at equal chance: expected first-find coins (PetIndex) of this find
			local list = tier.Minerals
			local new = 0
			for _, s in list do
				if not seen[s] then
					new += 1
				end
			end
			cash += Config.PetIndex.FirstFindCoins * new / #list
			for _, s in list do -- deterministic stand-in: the next unseen species is the one found
				if not seen[s] then
					seen[s] = true
					if new == #list or new * 2 >= #list then -- counted as new while at least half the zone is unseen
						event("new pet " .. s, false)
					end
					break
				end
			end
		end
		local firsts: { [string]: boolean } = {}
		local function first(what: string)
			if not firsts[what] then
				firsts[what] = true
				event(what, false)
			end
		end
		local towerRuns = 0
		local function tower()
			-- a run starts at the checkpoint (TowerRules.checkpoint) and climbs to the band's boss; the boss falls
			-- every second run (the pets need the levels from the run before)
			towerRuns += 1
			local from = TowerRules.checkpoint(towerBest)
			for f = from, from + TowerConfig.BossEvery - 1 do
				spend(60)
				local cleared = not TowerRules.isBoss(f) or towerRuns % 2 == 0
				if cleared then
					cash += TowerRules.reward(f)
					towerBest = math.max(towerBest, f)
				end
				xp += TowerRules.xp(f, cleared)
				if not cleared then
					break
				end
			end
			first("first tower run")
		end
		local function battle()
			spend(90)
			local R = PvpConfig.Rewards
			cash += 0.6 * R.WinCoins + 0.4 * R.LossCoins
			xp += 0.6 * R.WinXp + 0.4 * R.LossXp
			first("first battle")
		end
		local function train()
			spend(60)
			xp += 60 * math.min(3, PvpConfig.Train.TapsPerSecond) * PvpConfig.Train.TapXp
			first("first training")
		end
		-- day one: the login gift and the middle reward of each daily quest group (paid over the first loop)
		cash += ProgressConfig.DailyGift[1]
		local questCoins = 0
		for _, g in ProgressConfig.QuestGroups do
			local sum, n = 0, 0
			for _, k in ProgressConfig.QuestKinds do
				if k.Group == g then
					sum += k.Reward[math.ceil(#k.Reward / 2)]
					n += 1
				end
			end
			questCoins += sum / n
		end
		local questsPaid = false
		local capAt: { [number]: number } = {}
		local caps = { 10, 15, 20, 30, 50, 100 }
		while now < minutes * 60 do
			for _, step in { hunt, hunt, hunt, tower, battle, battle, train } do
				step()
				if not questsPaid and now >= 15 * 60 then -- the three quests are done during the first loop
					questsPaid = true
					cash += questCoins
				end
				for _, c in caps do
					if not capAt[c] and xp >= PetStats.xpForLevel(c) then
						capAt[c] = now
					end
				end
				shop()
			end
		end
		return events, capAt, { cash = cash, unlocked = unlocked, finds = finds, xp = xp }
	end

	local function gaps(events, from: number, to: number, coinOnly: boolean): number
		local last, worst = from, 0
		for _, e in events do
			if e.T > from and e.T <= to and (e.Coin or not coinOnly) then
				worst = math.max(worst, e.T - last)
				last = e.T
			end
		end
		return math.max(worst, to - last)
	end

	test("grind speed: something new every few minutes early, never a wall later (coin goals)", function()
		local events = simulate(240)
		local text = "see the timeline above"
		local coinLog = {}
		for _, e in events do
			if e.Coin then
				table.insert(coinLog, ("%.0f %s"):format(e.T / 60, e.What))
			end
		end
		print("    grind speed (min, coin goals): " .. table.concat(coinLog, ", "))
		local firstBuy = nil
		for _, e in events do
			if e.Coin and not firstBuy then
				firstBuy = e
			end
		end
		assert(firstBuy and firstBuy.T <= 5 * 60, "the first upgrade comes within 5 minutes\n" .. text)
		local early = 0
		for _, e in events do
			if e.Coin and e.T <= 30 * 60 then
				early += 1
			end
		end
		assert(early >= 5, ("only %d coin goals reached in the first 30 minutes\n%s"):format(early, text))
		local g30 = gaps(events, 0, 30 * 60, false)
		assert(g30 <= 6 * 60, ("a %.1f min wait in the first 30 minutes\n%s"):format(g30 / 60, text))
		local g120 = gaps(events, 30 * 60, 120 * 60, true)
		assert(g120 <= 20 * 60, ("a %.1f min wait between 30 min and 2 h\n%s"):format(g120 / 60, text))
		local g240 = gaps(events, 120 * 60, 240 * 60, true)
		assert(g240 <= 40 * 60, ("a %.1f min wall between 2 h and 4 h\n%s"):format(g240 / 60, text))
		local function at(name: string): number?
			for _, e in events do
				if e.What == name then
					return e.T / 60
				end
			end
			return nil
		end
		local forest = at(Config.Tiers.Quarry.Name .. " unlock")
		assert(forest and forest >= 10 and forest <= 40, ("Forest opens at %s min (want 10-40)\n%s"):format(tostring(forest), text))
		local snow = at(Config.Tiers.Cavern.Name .. " unlock")
		assert(snow and snow >= 45 and snow <= 150, ("Snow opens at %s min (want 45-150)\n%s"):format(tostring(snow), text))
	end)

	test("grind speed: a pet reaches each rarity's level cap in a sensible time (C10 ... Void 100)", function()
		assert(TowerConfig.LevelCaps.Common == 10 and TowerConfig.LevelCaps.Legendary == 50 and TowerConfig.CapSpecies.CosmicDragon == 100)
		local _, capAt = simulate(60 * 60)
		-- hours of play to reach each cap: [cap] = { min, max }
		local want = {
			[10] = { 0.1, 0.75 },
			[15] = { 0.25, 1.5 },
			[20] = { 0.4, 2.5 },
			[30] = { 1, 6 },
			[50] = { 3, 15 },
			[100] = { 10, 60 },
		}
		local line = {}
		for _, c in { 10, 15, 20, 30, 50, 100 } do
			table.insert(line, ("Lv%d %.1f h"):format(c, (capAt[c] or math.huge) / 3600))
		end
		print("    grind speed (hours of play to each level cap): " .. table.concat(line, ", "))
		local prev = 0
		for _, c in { 10, 15, 20, 30, 50, 100 } do
			local h = if capAt[c] then capAt[c] / 3600 else math.huge
			assert(h >= want[c][1] and h <= want[c][2], ("level %d after %.2f h of play (want %.2f-%.2f h)"):format(c, h, want[c][1], want[c][2]))
			assert(h >= prev, "caps in order")
			prev = h
		end
	end)
end
