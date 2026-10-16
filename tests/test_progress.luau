-- Find The Pet part 2: basket / nest upgrade sizes in the round core, and the daily gift + daily quest rules.
return function(t)
	local test, shared = t.test, t.shared
	local Config = shared("Config")
	local RoundRocks = shared("RoundRocks")
	local ProgressConfig = shared("ProgressConfig")
	local Quests = shared("Quests")
	local Random, Vector3 = t.Random, t.Vector3

	local function assertEq(a, b, msg)
		if a ~= b then
			error((msg or "mismatch") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
		end
	end

	local function make(members)
		local core = RoundRocks.new({
			MatchKey = "k",
			RoundId = 1,
			Tier = "Gravel",
			Seed = 33,
			TargetRng = Random.new(34),
			Members = members,
		})
		core:setPhase("Searching")
		return core
	end

	local clock = 0
	local function tick(dt)
		clock += dt or 0.5
		return clock
	end
	local function atRock(core, id)
		local p = core.Pile:localPosition(id) or Vector3.zero
		return Vector3.new(p.X, 3, p.Z)
	end
	local function fill(core, uid, n)
		local got = 0
		for _, id in core.Pile:pickableIds(Config.Carry.ReachLevels) do
			if got >= n then
				break
			end
			if core:pickup(uid, 1, id, atRock(core, id), tick()) == nil then
				got += 1
			end
		end
		return got
	end
	local function nextPickable(core)
		for _, id in core.Pile:pickableIds(Config.Carry.ReachLevels) do
			if core.Rocks[id].State == "InPile" then
				return id
			end
		end
		return nil
	end

	test("quests: egg-opening and pet-finding quests never read alike (audit 2 #29)", function()
		local by = {}
		for _, k in ProgressConfig.QuestKinds do
			by[k.Kind] = k
		end
		local crack, hatch = by.Crack, by.Hatch
		assert(crack and hatch, "both kinds exist")
		local function verb(text: string): string
			return string.lower(string.match(text, "^(%a+)") or "")
		end
		assert(verb(crack.Text) ~= verb(hatch.Text), "different first word: " .. crack.Text .. " / " .. hatch.Text)
		assert(verb(crack.Text) ~= verb(hatch.One or ""), "and for the one-goal text")
		assert(string.find(string.lower(crack.Text), "egg", 1, true), "egg quest says eggs")
		assert(string.find(string.lower(hatch.Text), "pet", 1, true) and string.find(string.lower(hatch.Text), "hunt", 1, true), "pet quest says it counts pets found in hunts")
	end)

	test("progress: levels start at the Config sizes and grow", function()
		assertEq(ProgressConfig.carry(1), Config.Carry.Capacity)
		assertEq(ProgressConfig.carry(1), 3, "owner: start with 3 eggs")
		assertEq(ProgressConfig.carry(2), 4)
		assertEq(ProgressConfig.carry(3), 5)
		assertEq(ProgressConfig.carry(4), 6)
		assertEq(ProgressConfig.carry(99), 20, "a newer build's level clamps to the biggest known (owner: max 20)")
		local lastCarry, lastPrice = 0, -1
		for _, b in ProgressConfig.Baskets do
			assert(b.Carry > lastCarry and b.Price > lastPrice, "baskets grow and cost more")
			lastCarry, lastPrice = b.Carry, b.Price
		end
		assertEq(lastCarry, 20)
		assertEq(ProgressConfig.carry("x"), 3)
		assertEq(ProgressConfig.queue(1), Config.Station.QueueCapacity)
		local last = 0
		for i, n in ProgressConfig.Nests do
			assert(n.Queue > last, "each nest raises the tray")
			last = n.Queue
			assertEq(n.Price == 0, i == 1, "only the straw nest is free")
		end
		assertEq(ProgressConfig.MaxQueue, last)
		assertEq(ProgressConfig.Nests[1].Id, "Straw")
		assertEq(ProgressConfig.Nests[4].Id, "Gold")
	end)

	test("progress: basket size is per member and enforced by the core", function()
		local core = make({
			{ UserId = 1, Tool = "Hammer", Station = 1 },
			{ UserId = 2, Tool = "Hammer", Station = 2, Carry = 6 },
			{ UserId = 3, Tool = "Hammer", Station = 3, Carry = 20 },
		})
		assertEq(core.Members[3].CarryCap, 20)
		assertEq(fill(core, 3, 30), 20, "the biggest basket takes 20 eggs")
		assertEq(core.Members[1].CarryCap, 3)
		assertEq(core.Members[2].CarryCap, 6)
		assertEq(fill(core, 1, 10), 3)
		local id = nextPickable(core)
		assertEq(core:pickup(1, 1, id, atRock(core, id), tick()), "BasketFull")
		assertEq(fill(core, 2, 10), 6)
		id = nextPickable(core)
		assertEq(core:pickup(2, 1, id, atRock(core, id), tick()), "BasketFull")
		assertEq(core:counters(2).CarryCapacity, 6)
		assertEq(core:counters(1).CarryCapacity, 3)
		-- an upgrade during the round lets the basket take more
		core:setCaps(1, 5, nil)
		assertEq(fill(core, 1, 10), 2)
		assertEq(#core.Members[1].Basket, 5)
		-- views carry the sizes for the client hints
		for _, v in core:stationViews(0) do
			assertEq(v.CarryCap, core.Members[v.UserId].CarryCap)
			assertEq(v.QueueCap, core.Members[v.UserId].QueueCap)
		end
	end)

	test("progress: bad sizes fall back and never go above the core limit", function()
		local core = make({ { UserId = 1, Tool = "Hammer", Station = 1, Carry = 0 / 0, Queue = -4 } })
		assertEq(core.Members[1].CarryCap, Config.Carry.Capacity)
		assertEq(core.Members[1].QueueCap, Config.Station.QueueCapacity)
		core:setCaps(1, "lots", 1e9)
		assertEq(core.Members[1].CarryCap, Config.Carry.Capacity)
		assert(core.Members[1].QueueCap <= 64, "clamped")
		core:setCaps(1, 4.7, 12)
		assertEq(core.Members[1].CarryCap, 4)
		assertEq(core.Members[1].QueueCap, 12)
	end)

	test("progress: nest tray size is per member and enforced on deposit", function()
		local core = make({ { UserId = 1, Tool = "Hammer", Station = 1, Carry = 6, Queue = 12 } })
		local at = RoundRocks.stationPosition(1)
		local total = 0
		for _ = 1, 4 do
			fill(core, 1, 6)
			local res = core:deposit(1, 1, at, tick())
			if res then
				total += #res.Moved
			end
		end
		assertEq(#core.Members[1].Queue, 12, "the wood nest holds 12")
		assertEq(core:counters(1).QueueCapacity, 12)
		local _, why = core:deposit(1, 1, at, tick())
		assertEq(why, "QueueFull")
	end)

	-- Quests --------------------------------------------------------------------------------------
	local DAY = 20000

	test("quests: three different kinds per day, same for the same player and day", function()
		for uid = 1, 40 do
			for d = DAY, DAY + 10 do
				local a = Quests.forDay(uid * 977, d)
				local b = Quests.forDay(uid * 977, d)
				assertEq(#a, 3)
				local seen = {}
				for i, q in a do
					assert(not seen[q.Kind], "kinds differ")
					seen[q.Kind] = true
					assertEq(q.Kind, b[i].Kind, "deterministic")
					assertEq(q.Goal, b[i].Goal, "deterministic")
					assert(q.Reward > 0 and q.Goal > 0, "real goals and rewards")
				end
			end
		end
	end)

	test("quests: every day is one race, one tower and one pet quest, in that order", function()
		local kindsSeen = {}
		for uid = 1, 30 do
			for d = DAY, DAY + 30 do
				local list = Quests.forDay(uid * 31, d)
				assertEq(#list, 3)
				assertEq(list[1].Group, "Race")
				assertEq(list[2].Group, "Tower")
				assertEq(list[3].Group, "Pet")
				assertEq(list[2].Kind, "TowerFloors")
				for _, q in list do
					kindsSeen[q.Kind] = true
				end
			end
		end
		for _, k in ProgressConfig.QuestKinds do
			assert(kindsSeen[k.Kind], "kind never picked: " .. k.Kind)
		end
	end)

	test("badges: launch milestones from saved data", function()
		assertEq(#ProgressConfig.BadgeOrder, 6)
		for _, key in ProgressConfig.BadgeOrder do
			assertEq(ProgressConfig.Badges[key].Id, 0, "ids are owner placeholders")
		end
		local species = ProgressConfig.huntSpecies()
		assertEq(#species, 39, "39 hunt pets out at launch (weekly pets hidden until Config.WeeklyPets.Start; StarPterodactyl retired, Turtle back 10-15)")
		for _, id in species do
			assert(not Config.Minerals[id].TowerOnly, "tower-only pets are not hunt pets")
		end
		local data = { Stats = { SoloFinds = 0, MultiplayerWins = 0 }, DiscoveryIndex = {}, DiscoveryRarity = {}, InventoryGeodes = {}, TowerBest = 24, UnlockedTiers = { Gravel = true } }
		local p = ProgressConfig.badgeProgress(data)
		for _, key in ProgressConfig.BadgeOrder do
			assertEq(p[key].Done, false, key)
		end
		data.Stats.MultiplayerWins = 1
		data.DiscoveryRarity.Raptor = { Epic = 1 }
		data.TowerBest = 25
		data.UnlockedTiers.Quarry = true
		for i = 1, #species - 1 do
			data.DiscoveryIndex[species[i]] = 1
		end
		p = ProgressConfig.badgeProgress(data)
		assertEq(p.FirstHatch.Done, true)
		assertEq(p.FirstRare.Done, true)
		assertEq(p.Tower25.Done, true)
		assertEq(p.Forest.Done, true)
		assertEq(p.AllHuntPets.Done, false)
		assertEq(p.AllHuntPets.Have, #species - 1)
		data.DiscoveryIndex[species[#species]] = 2
		assertEq(ProgressConfig.badgeProgress(data).AllHuntPets.Done, true)
		assertEq(ProgressConfig.badgeProgress(data).SecretEgg.Done, false)
		data.SecretEggFound = true
		assertEq(ProgressConfig.badgeProgress(data).SecretEgg.Done, true)
	end)

	test("quests: the set changes from one day to the next", function()
		for uid = 1, 60 do
			for d = DAY, DAY + 20 do
				local a, b = Quests.forDay(uid, d), Quests.forDay(uid, d + 1)
				local same = true
				for _, q in a do
					local hit = false
					for _, r in b do
						if r.Kind == q.Kind and r.Goal == q.Goal then
							hit = true
						end
					end
					same = same and hit
				end
				assert(not same, "day " .. d .. " repeats for user " .. uid)
			end
		end
	end)

	test("quests: progress, claim once, reset on a new day", function()
		local uid = 4242
		local d = Quests.sanitize(nil)
		local list = Quests.forDay(uid, DAY)
		local q = list[1]
		assertEq(Quests.claim(d, uid, DAY, 1), nil, "not done yet")
		for _ = 1, q.Goal + 5 do
			Quests.bump(d, uid, DAY, q.Kind, 1)
		end
		assertEq(d.Progress[1], q.Goal, "progress stops at the goal")
		local coins, why = Quests.claim(d, uid, DAY, 1)
		assertEq(coins, q.Reward)
		assertEq(why, nil)
		local again, why2 = Quests.claim(d, uid, DAY, 1)
		assertEq(again, nil)
		assertEq(why2, "Claimed")
		assertEq(Quests.claim(d, uid, DAY, 0), nil)
		assertEq(Quests.claim(d, uid, DAY, 4), nil)
		assertEq(Quests.claim(d, uid, DAY, "1"), nil)
		assertEq(Quests.bump(d, uid, DAY, "NoSuchKind", 3), false)
		assertEq(Quests.bump(d, uid, DAY, q.Kind, -5), false, "negative progress is ignored")
		-- the next day: fresh progress, nothing claimed
		local v = Quests.view(d, uid, DAY + 1)
		for _, row in v.Quests do
			assertEq(row.Progress, 0)
			assertEq(row.Claimed, false)
		end
		Quests.bump(d, uid, DAY + 1, "Crack", 1)
		assertEq(d.Day, DAY + 1)
		assertEq(d.Claimed[1], false)
	end)

	test("quests: daily gift once per day, streak to day 7, a missed day starts over", function()
		local d = Quests.sanitize({ Day = "x", Progress = 5, GiftDay = 0 / 0 })
		assertEq(d.GiftDay, 0)
		local paid = {}
		for i = 0, 6 do
			local c, sd = Quests.claimGift(d, DAY + i)
			assertEq(sd, i + 1)
			table.insert(paid, c)
			local again, _, why = Quests.claimGift(d, DAY + i)
			assertEq(again, nil)
			assertEq(why, "Claimed")
		end
		assertEq(paid[7], ProgressConfig.DailyGift[7])
		assert(paid[7] > paid[6], "day 7 gives more")
		local _, sd8 = Quests.claimGift(d, DAY + 7)
		assertEq(sd8, 1, "after day 7 the cycle starts again")
		assertEq(Quests.giftStreakDay(d, DAY + 8), 2)
		assertEq(Quests.giftStreakDay(d, DAY + 10), 1, "missed days reset the streak")
		local _, sd = Quests.claimGift(d, DAY + 10)
		assertEq(sd, 1)
		local none, _, why = Quests.claimGift(d, DAY + 9)
		assertEq(none, nil, "a day in the past cannot be claimed")
		assertEq(why, "Clock")
	end)

	test("quests: view counts what can be claimed", function()
		local uid = 77
		local d = Quests.empty()
		local v = Quests.view(d, uid, DAY)
		assertEq(v.Claimable, 1, "only the gift")
		assertEq(v.Gift.Ready, true)
		assertEq(v.NextReset, (DAY + 1) * 86400)
		Quests.claimGift(d, DAY)
		local q = Quests.forDay(uid, DAY)[2]
		Quests.bump(d, uid, DAY, q.Kind, q.Goal)
		v = Quests.view(d, uid, DAY)
		assertEq(v.Gift.Ready, false)
		assert(v.Claimable >= 1, "a finished quest")
		assertEq(Quests.day(DAY * 86400 + 86399), DAY)
	end)
end
