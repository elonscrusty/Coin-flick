-- First five minutes and comeback hooks: starter egg odds, play-time gifts, away nest, friend / group gifts, the
-- growing daily streak with its shield, hunter levels and the practice bots' loop (all pure shared rules).
return function(t)
	local test, shared = t.test, t.shared
	local Retention = shared("Retention")
	local Quests = shared("Quests")
	local ProgressConfig = shared("ProgressConfig")
	local GeodeGen = shared("GeodeGen")
	local SpeciesPool = shared("SpeciesPool")
	local Config = shared("Config")
	local BotRules = shared("BotRules")
	local Random = t.Random

	local function eq(a, b, msg)
		if a ~= b then
			error((msg or "mismatch") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
		end
	end
	local DAY = 20375
	local NOW = DAY * 86400 + 3600

	test("void statue source line is true: the Space zone holds the chase dragon at 1 in 1000 base odds (audit F22)", function()
		local tier = Config.Tiers[Retention.DreamZone]
		assert(tier and tier.Name == "Space", "dream zone is Space")
		assert(string.find(string.upper(Retention.DreamSource), string.upper(tier.Name), 1, true), "source names the zone")
		assert(table.find(tier.Minerals, Retention.DreamSpecies), "Space eggs hold the Void Dragon")
		local sp = Config.Minerals[Retention.DreamSpecies]
		assert(sp and sp.Chase == true and sp.Name == "Void Dragon", "it is the zone's chase pet")
		local total = 0
		for _, w in Config.RarityWeights do
			total += w
		end
		eq(math.floor(total / Config.RarityWeights.Legendary + 0.5), 1000, "Legendary base odds are 1 in 1000")
	end)

	test("starter egg: always Rare or Epic, never Common and never the 1 in 1000 chase pet", function()
		local st = Retention.Starter
		eq(st.Weights.Legendary, nil, "no Legendary weight")
		local rng = Random.new(5)
		local seen = { Rare = 0, Epic = 0 }
		for i = 1, 2000 do
			local s = GeodeGen.roll(rng, st.Tier, "id" .. i, "starter", NOW, true, 0, st.Weights)
			assert(seen[s.Rarity] ~= nil, "rarity " .. tostring(s.Rarity))
			seen[s.Rarity] += 1
			assert(SpeciesPool.rarityAllowed(s.Mineral, s.Rarity), "species fits its rarity: " .. s.Mineral)
			local m = Config.Minerals[s.Mineral]
			assert(m and m.Chase ~= true, "never a chase pet: " .. s.Mineral)
		end
		assert(seen.Rare > seen.Epic and seen.Epic > 0, "mostly Rare, some Epic")
	end)

	test("play gifts: 1, 3, 5 and 10 minutes; claimed in order; reset each day", function()
		local s = Retention.empty()
		local i, left = Retention.nextGift(s, DAY)
		eq(i, 1)
		eq(left, 60)
		local _, _, why = Retention.claimGift(s, DAY)
		eq(why, "NotYet", "too early")
		local became = false
		for _ = 1, 12 do -- 12 x 5 s = 60 s
			became = Retention.tickPlay(s, DAY, 5) or became
		end
		assert(became, "the tick reports the gift turning ready")
		eq(Retention.readyGifts(s, DAY), 1)
		local coins, idx = Retention.claimGift(s, DAY)
		eq(coins, Retention.PlayGifts.Coins[1])
		eq(idx, 1)
		eq(Retention.readyGifts(s, DAY), 0)
		local _, left2 = Retention.nextGift(s, DAY)
		eq(left2, 120, "the 3 minute gift is 2 minutes away")
		-- a stalled server cannot jump the clock: one tick adds at most TickMax
		Retention.tickPlay(s, DAY, 9999)
		eq(s.Play.Seconds, 60 + Retention.PlayGifts.TickMax)
		for _ = 1, 200 do
			Retention.tickPlay(s, DAY, 5)
		end
		eq(Retention.readyGifts(s, DAY), 3, "the other three waiting")
		local total = coins
		for _ = 1, 3 do
			total += (Retention.claimGift(s, DAY))
		end
		eq(total, 50 + 100 + 150 + 400)
		local none, _, why2 = Retention.claimGift(s, DAY)
		eq(none, nil)
		eq(why2, "AllClaimed")
		eq(Retention.view(s, DAY).NextGift, nil, "no timer once every gift is opened")
		-- next day starts over
		eq(Retention.view(s, DAY + 1).NextGift, 1)
		eq(Retention.view(s, DAY + 1).NextIn, 60)
		Retention.tickPlay(s, DAY + 1, 5)
		eq(s.Play.Claimed, 0)
		eq(s.Play.Seconds, 5)
	end)

	test("away nest: nothing for short breaks or new players; eggs, coins, a pet and welcome back grow with time", function()
		eq(Retention.away(0, NOW), nil, "a brand-new player has no nest yet")
		eq(Retention.away(NOW - 600, NOW), nil, "10 minutes is not away")
		eq(Retention.away(NOW + 100, NOW), nil, "a clock that went backwards pays nothing")
		local a = Retention.Away
		local r1 = Retention.away(NOW - 3600, NOW)
		eq(r1.Eggs, 1)
		eq(r1.Coins, a.CoinsPerEgg)
		eq(r1.Pet, false)
		local r2 = Retention.away(NOW - 9 * 3600, NOW)
		eq(r2.Eggs, 2)
		eq(r2.Pet, true, "8 hours or more hatches a pet")
		local r3 = Retention.away(NOW - 30 * 3600, NOW)
		eq(r3.Eggs, a.MaxEggs, "capped")
		eq(r3.WelcomeBack, false)
		local r4 = Retention.away(NOW - 4 * 86400, NOW)
		eq(r4.WelcomeBack, true)
		eq(r4.Coins, a.MaxEggs * a.CoinsPerEgg + a.WelcomeBackCoins)
	end)

	test("friend gift: once per friend per day, a few friends a day; group gift off until the owner sets an id", function()
		local s = Retention.empty()
		eq(Retention.friendGift(s, DAY, 11), Retention.Friend.Coins)
		eq(Retention.friendGift(s, DAY, 11), 0, "same friend again")
		eq(Retention.friendGift(s, DAY, 12), Retention.Friend.Coins)
		eq(Retention.friendGift(s, DAY, 13), Retention.Friend.Coins)
		eq(Retention.friendGift(s, DAY, 14), 0, "daily cap")
		eq(Retention.friendGift(s, DAY + 1, 11), Retention.Friend.Coins, "a new day")
		eq(Retention.Group.Id, 0, "REPLACE: off until the owner pastes the group id")
		eq(Retention.groupGift(s, DAY, true), 0)
		local saved = Retention.Group.Id
		Retention.Group.Id = 123
		eq(Retention.groupGift(s, DAY, false), 0, "members only")
		eq(Retention.groupGift(s, DAY, true), Retention.Group.Coins)
		eq(Retention.groupGift(s, DAY, true), 0, "once a day")
		Retention.Group.Id = saved
	end)

	test("sanitize repairs bad saves without inventing progress", function()
		local s = Retention.sanitize({ LastSeen = "x", Play = { Day = 0 / 0, Seconds = -5, Claimed = 99 }, Friend = 5 })
		eq(s.LastSeen, 0)
		eq(s.Play.Seconds, 0)
		eq(s.Play.Claimed, #Retention.PlayGifts.Marks)
		eq(type(s.Friend.Ids), "table")
		eq(Retention.sanitize(nil).GroupDay, 0)
	end)

	test("daily streak grows past day 7 (bigger gifts each week) and a shield saves one missed day", function()
		local d = Quests.empty()
		local paid = {}
		for i = 0, 13 do
			local c = Quests.claimGift(d, DAY + i)
			paid[i + 1] = c
		end
		eq(d.Streak, 14)
		eq(paid[1], ProgressConfig.DailyGift[1], "week 1 pays the table")
		eq(paid[8], math.floor(ProgressConfig.DailyGift[1] * 1.25), "week 2 pays 25% more")
		eq(d.Shields, Retention.Streak.MaxShields, "a shield was earned on day 7 (one at most)")
		-- miss one day: the shield keeps the streak
		local _, _, _, used = Quests.claimGift(d, DAY + 15)
		eq(used, true)
		eq(d.Streak, 15)
		eq(d.Shields, 0)
		-- miss one day again without a shield: back to day 1
		Quests.claimGift(d, DAY + 17)
		eq(d.Streak, 1)
		-- the multiplier is capped
		eq(Retention.streakMult(1000), Retention.Streak.MaxMult)
		local v = Quests.view(d, 1, DAY + 18)
		eq(v.Gift.Streak, 2)
		eq(v.Gift.Mult, 1)
	end)

	test("hunter level: XP from cracks, hunts and finds; each level needs a bit more", function()
		eq(Retention.level(0), 1)
		eq(Retention.level(24), 1)
		eq(Retention.level(25), 2)
		eq(Retention.level(75), 3)
		local lv, into, need = Retention.level(80)
		eq(lv, 3)
		eq(into, 5)
		eq(need, 75)
		eq(Retention.xp({ RocksCracked = 10, MatchesPlayed = 2, SoloFinds = 1, MultiplayerWins = 1 }), 10 + 20 + 40)
		eq(Retention.xp(nil), 0)
	end)

	test("next goal: the Void Dragon's power is far above any starter pet; the bar shows a sliver, never empty or full", function()
		local PetStats = shared("PetStats")
		local dream = Retention.dreamPower()
		assert(dream > 300, "dream power " .. dream)
		local rng = Random.new(9)
		for i = 1, 200 do
			local spec = GeodeGen.roll(rng, Retention.Starter.Tier, "g" .. i, "starter", NOW, true, 0, Retention.Starter.Weights)
			local p = PetStats.roll(spec, 0).Power
			assert(p < dream, "starter " .. p .. " < " .. dream)
			local f = Retention.dreamProgress(p)
			assert(f > 0 and f < 0.6, "progress " .. f)
		end
		eq(Retention.dreamProgress(dream * 4), 1, "clamped")
		eq(Retention.dreamProgress(-5), 0)
	end)

	test("practice bots: one per free nest (at most 3), they loop pile -> grab -> nest -> crack and carry in between", function()
		local rng = Random.new(3)
		eq(#BotRules.make(0, rng, 0), 0)
		eq(#BotRules.make(2, rng, 0), 2)
		local bots = BotRules.make(9, rng, 0)
		eq(#bots, BotRules.Count)
		eq(bots[1].Name ~= bots[2].Name, true, "different names")
		local b = bots[1]
		local seq = {}
		local now = 0
		for _ = 1, 8 do
			now = b.Until + 0.01
			assert(BotRules.advance(b, now, false, rng), "moves on when the step is over")
			table.insert(seq, b.Step .. (if b.Carry then "+egg" else ""))
		end
		eq(table.concat(seq, ","), "ToPile,Grab,ToNest+egg,Crack+egg,ToPile,Grab,ToNest+egg,Crack+egg")
		eq(BotRules.advance(b, now, false, rng), false, "nothing changes before the step ends")
		-- a walk ends early on arrival
		local w = BotRules.make(1, rng, 0)[1]
		BotRules.advance(w, w.Until, false, rng)
		eq(w.Step, "ToPile")
		assert(BotRules.advance(w, w.Until - 5, true, rng), "arrived early")
		eq(w.Step, "Grab")
	end)

	test("practice bots wear pet onesies, not default avatars: a different outfit each, with ears or spikes and a tail", function()
		local Color3 = t.Color3
		local seen = {}
		for i = 1, BotRules.Count do
			local o = BotRules.outfit(i)
			assert(not seen[o.Name], "different outfit for bot " .. i)
			seen[o.Name] = true
			assert(o.Body ~= Color3.fromRGB(163, 162, 165) and o.Legs ~= Color3.fromRGB(13, 105, 172), "not noob grey / blue")
			local tail, head = false, false
			for _, p in o.Parts do
				tail = tail or p.Name == "Tail"
				head = head or p.Attach == "Head"
				assert(p.Size[1] > 0 and p.Size[2] > 0 and p.Size[3] > 0, p.Name .. " size")
				assert(math.abs(p.Offset[1]) < 1.5 and math.abs(p.Offset[2]) < 1.5 and math.abs(p.Offset[3]) < 2, p.Name .. " stays on the body")
			end
			assert(tail and head, o.Name .. " has a tail and a head piece")
		end
		eq(BotRules.outfit(BotRules.Count + 1).Name, BotRules.outfit(1).Name, "wraps around")
	end)
	test("retention: welcome cards wait until the player is out of a hunt, tower or Pet Battle", function()
		local R = shared("Retention")
		assert(R.calm({}), "free in the lobby")
		assert(not R.calm({ InBattle = true }), "not over a Pet Battle")
		assert(not R.calm({ InTower = true }), "not in the tower")
		assert(not R.calm({ MatchKey = "m1" }), "not in a hunt")
		assert(not R.calm({ Match = {} }), "not while a round is open")
	end)
	test("dev auto pet (Studio): waits for the starter egg so a fresh save still gets its first hatch", function()
		local R = shared("Retention")
		assert(not R.freePetReady(nil), "no profile yet")
		assert(not R.freePetReady({ StarterPet = false }), "fresh save: starter egg not hatched")
		assert(R.freePetReady({ StarterPet = true }), "after the starter hatch")
		local src = require("@lune/fs").readFile("src/server/DevPets.server.luau")
		assert(string.find(src, "Retention.freePetReady(Profiles.get(player))", 1, true), "DevPets waits on the rule")
		-- every free pet grant on the server (kind "Gift" / "Bought" without a purchase) other than the starter egg
		-- itself checks the rule first, so no gift can be a fresh save's first pet
		local fs = require("@lune/fs")
		for _, name in fs.readDir("src/server") do
			local file = "src/server/" .. name
			if fs.isFile(file) then
				local lines = string.split(fs.readFile(file), "\n")
				for i, line in lines do
					local key = string.match(line, 'grantSpecimen%(player, "([%w]+):')
					if key and key ~= "starter" and key ~= "dev" and string.find(line, '"Gift"', 1, true) or (key == "devauto") then
						local near = table.concat(lines, "\n", math.max(1, i - 12), i)
						assert(string.find(near, "freePetReady", 1, true), file .. ":" .. i .. " gives a free pet without Retention.freePetReady")
					end
				end
			end
		end
	end)
	test("studio: practice bots print once per bot (first loop), not every step; /findpet ends the round like /endround", function()
		local fs = require("@lune/fs")
		local pb = fs.readFile("src/server/PracticeBots.luau")
		local prints = 0
		for _ in string.gmatch(pb, "print%(") do
			prints += 1
		end
		eq(prints, 1, "one print in PracticeBots")
		assert(string.find(pb, 'step == "Crack" and live.Cycles == 1', 1, true), "only on the first finished loop")
		local dc = fs.readFile("src/server/DevCommands.server.luau")
		assert(string.find(dc, 'if cmd == "findpet" then\n\t\tcmd = "endround"', 1, true), "/findpet = /endround")
	end)
end
