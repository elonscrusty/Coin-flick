-- Pet Battle balance: thousands of fights played with the real rules (PvpRules.newFight / step / useSpecial).
-- Bots must match the player's team (a new player wins most bot fights, never a stomp either way), no species or
-- side always wins, fights last a sensible time, and rewards / trophies add up fairly.
return function(t)
	local test, shared = t.test, t.shared
	local PvpConfig = shared("PvpConfig")
	local PvpRules = shared("PvpRules")
	local TowerConfig = shared("TowerConfig")
	local PetStats = shared("PetStats")

	local function stream(seed: number)
		local s = seed % 2147483646 + 1
		return function()
			s = (s * 48271) % 2147483647
			return s / 2147483647
		end
	end

	-- every egg species a player can own and fight with (bots draw from the same pool)
	local species = {}
	do
		local towerOnly = {}
		for _, tp in TowerConfig.TowerPets do
			towerOnly[tp.Id] = true
		end
		for id in TowerConfig.Species do
			if not towerOnly[id] then
				table.insert(species, id)
			end
		end
		table.sort(species)
	end

	-- A player team: 3 pets of the given rarities, levelled to `lvl` share of their cap (0 = fresh, 1 = maxed).
	local function playerTeam(rand, rarities: { string }, lvl: number)
		local out = {}
		for i, r in rarities do
			local pet = { Mineral = species[math.floor(rand() * #species) + 1], Rarity = r, Modifier = "Natural", Seed = math.floor(rand() * 2 ^ 30) + 1 }
			local cap = PetStats.cap(pet)
			local level = math.max(1, math.floor(cap * lvl + 0.5))
			table.insert(out, { Id = "1:" .. i, Xp = PetStats.xpForLevel(level), Pet = pet })
		end
		return out
	end

	-- One fight as the server plays it: the player (side 1) fires SPECIAL `react` seconds after it fills, the bot
	-- (side 2) after PvpConfig.BotSpecialDelay. Returns winner, seconds, timed out.
	local function play(a, b, rand, react: number, botDelay: number?)
		local f = PvpRules.newFight(a, b)
		local ready: { number? } = { nil, nil }
		local delay = { react, botDelay or PvpConfig.BotSpecialDelay }
		local timedOut = false
		while f.State == "Fighting" do
			for _, e in PvpRules.step(f, TowerConfig.Tick, rand) do
				if e.Kind == "TimeUp" then
					timedOut = true
				end
			end
			for side = 1, 2 do
				if f.State == "Fighting" and PvpRules.meterFull(f, side) then
					ready[side] = ready[side] or (f.Time + delay[side])
					if f.Time >= (ready[side] :: number) then
						ready[side] = nil
						PvpRules.useSpecial(f, side, rand())
					end
				end
			end
		end
		return f.Winner, f.Time, timedOut
	end

	-- Player profiles across the game: who they are, their team's rarities and how far trained.
	local PROFILES = {
		{ Name = "new (starter + commons, fresh)", Rarities = { "Rare", "Common", "Common" }, Lvl = 0 },
		{ Name = "new (all common, fresh)", Rarities = { "Common", "Common", "Common" }, Lvl = 0 },
		{ Name = "early (uncommon mix, a bit trained)", Rarities = { "Uncommon", "Uncommon", "Common" }, Lvl = 0.3 },
		{ Name = "mid (rare / epic, half trained)", Rarities = { "Epic", "Rare", "Rare" }, Lvl = 0.5 },
		{ Name = "late (epic / legendary, maxed)", Rarities = { "Legendary", "Epic", "Epic" }, Lvl = 1 },
		{ Name = "top (legendary, maxed)", Rarities = { "Legendary", "Legendary", "Legendary" }, Lvl = 1 },
	}
	local FIGHTS = 300 -- per profile (1800 bot fights in all)

	local results: { [string]: { Wins: number, Losses: number, Draws: number, Times: { number }, TimeUps: number, Stomps: number } } = {}
	local function botFights()
		if next(results) then
			return results
		end
		for pi, prof in PROFILES do
			local r = { Wins = 0, Losses = 0, Draws = 0, Times = {}, TimeUps = 0, Stomps = 0 }
			for n = 1, FIGHTS do
				local rand = stream(pi * 100003 + n * 7919)
				local me = playerTeam(rand, prof.Rarities, prof.Lvl)
				local bot = PvpRules.botTeam(me, rand)
				for i, tp in bot do
					tp.Id = "2:" .. i
				end
				local f = PvpRules.newFight(me, bot)
				local _ = f
				local w, secs, up = play(me, bot, rand, 0.6)
				if w == 1 then
					r.Wins += 1
				elseif w == 2 then
					r.Losses += 1
				else
					r.Draws += 1
				end
				table.insert(r.Times, secs)
				if up then
					r.TimeUps += 1
				end
			end
			table.sort(r.Times)
			results[prof.Name] = r
			print(string.format("    pvp balance %-38s win %4.1f%%  loss %4.1f%%  draw %4.1f%%  median %4.1f s  p90 %4.1f s  time-ups %4.1f%%",
				prof.Name, 100 * r.Wins / FIGHTS, 100 * r.Losses / FIGHTS, 100 * r.Draws / FIGHTS,
				r.Times[FIGHTS // 2], r.Times[math.floor(FIGHTS * 0.9)], 100 * r.TimeUps / FIGHTS))
		end
		return results
	end

	test("pvp balance: bots match every player's power: new players win 55-70%, nobody wins or loses almost always", function()
		local res = botFights()
		for _, prof in PROFILES do
			local r = res[prof.Name]
			local rate = r.Wins / FIGHTS
			if prof.Lvl == 0 then
				assert(rate >= 0.55 and rate <= 0.70, prof.Name .. ": new player's win rate vs bots " .. rate)
			else
				assert(rate >= 0.50 and rate <= 0.75, prof.Name .. ": win rate vs bots " .. rate)
			end
		end
	end)

	test("pvp balance: fights last a sensible time (median 15-40 s) and rarely run out the clock", function()
		local res = botFights()
		for _, prof in PROFILES do
			local r = res[prof.Name]
			local median = r.Times[FIGHTS // 2]
			assert(median >= 15 and median <= 40, prof.Name .. ": median fight " .. median .. " s")
			-- stomps (over in under 8 s) are rare: only a chase pet (Void Dragon, its own level cap) can outgrow its bot
			local quick = 0
			for _, s in r.Times do
				if s < 8 then
					quick += 1
				end
			end
			assert(quick / FIGHTS <= 0.03, prof.Name .. ": stomps " .. quick .. " of " .. FIGHTS)
			assert(r.TimeUps / FIGHTS <= 0.15, prof.Name .. ": time-ups " .. r.TimeUps / FIGHTS)
		end
	end)

	test("pvp balance: mirror fights split evenly between the two sides (no side edge)", function()
		local wins = { 0, 0, [0] = 0 }
		local N = 600
		for n = 1, N do
			local rand = stream(900001 + n * 31)
			local rar = { "Common", "Rare", "Epic", "Legendary" }
			local r = rar[(n % #rar) + 1]
			local a = playerTeam(rand, { r, r, r }, (n % 3) / 2)
			local b = {}
			for i, tp in a do
				-- the same pets on the other side
				table.insert(b, { Id = "2:" .. i, Xp = tp.Xp, Pet = table.clone(tp.Pet) })
			end
			local w = play(a, b, rand, 0.6, 0.6)
			wins[w] += 1
		end
		print(string.format("    pvp balance mirror: side 1 %d, side 2 %d, draws %d of %d", wins[1], wins[2], wins[0], N))
		local share = wins[1] / math.max(wins[1] + wins[2], 1)
		assert(share >= 0.42 and share <= 0.58, "side 1 share in mirror fights " .. share)
	end)

	-- Same rarity and the same level (10, every rarity's cap reaches it); the chase species with their own higher cap
	-- (TowerConfig.CapSpecies, the 1 in 1000 Void Dragon) are meant to be the best and are left out.
	local fair = {}
	for _, id in species do
		if not TowerConfig.CapSpecies[id] then
			table.insert(fair, id)
		end
	end
	local function sameLevelTeam(rand, rar: string)
		local out = {}
		for i = 1, 3 do
			local pet = { Mineral = fair[math.floor(rand() * #fair) + 1], Rarity = rar, Modifier = "Natural", Seed = math.floor(rand() * 2 ^ 30) + 1 }
			table.insert(out, { Id = "1:" .. i, Xp = PetStats.xpForLevel(10), Pet = pet })
		end
		return out
	end

	test("pvp balance: no species always wins (equal rarity and level, random teams)", function()
		local played: { [string]: number } = {}
		local won: { [string]: number } = {}
		local N = 1500
		for n = 1, N do
			local rand = stream(500009 + n * 13)
			local rar = ({ "Common", "Rare", "Epic", "Legendary" })[(n % 4) + 1]
			local a = sameLevelTeam(rand, rar)
			local b = sameLevelTeam(rand, rar)
			for i, tp in b do
				tp.Id = "2:" .. i
			end
			local w = play(a, b, rand, 0.6, 0.6)
			for side, tm in { a, b } do
				for _, tp in tm do
					local s = tp.Pet.Mineral
					played[s] = (played[s] or 0) + 1
					if w == side then
						won[s] = (won[s] or 0) + 1
					end
				end
			end
		end
		local worst, best = 1, 0
		local worstS, bestS = "", ""
		for s, n in played do
			if n >= 40 then
				local rate = (won[s] or 0) / n
				if rate < worst then
					worst, worstS = rate, s
				end
				if rate > best then
					best, bestS = rate, s
				end
			end
		end
		print(string.format("    pvp balance species: best %s %.0f%%, worst %s %.0f%%", bestS, best * 100, worstS, worst * 100))
		assert(best <= 0.72, "species " .. bestS .. " wins " .. best)
		assert(worst >= 0.28, "species " .. worstS .. " wins only " .. worst)
	end)

	test("pvp balance: rewards and trophies are fair (bot wins pay less trophies; a 60% player climbs slowly, a 40% one does not sink fast)", function()
		local R = PvpConfig.Rewards
		-- trophies per fight at a given win rate
		local function drift(rate: number, bot: boolean): number
			local w = PvpRules.outcome("Win", 1000, 0, bot).Trophies
			local l = PvpRules.outcome("Loss", 1000, 0, bot).Trophies
			return rate * w + (1 - rate) * l
		end
		assert(drift(0.5, false) > 0, "a 50% player still climbs a little (losses cost less than wins)")
		assert(drift(0.6, true) > 0 and drift(0.6, true) < drift(0.6, false), "bot farming climbs slower than real fights")
		assert(R.BotWinTrophies < R.WinTrophies and R.BotLossTrophies <= R.LossTrophies)
		-- coins: a win always pays more than a loss, a loss still pays something
		local win, loss = PvpRules.outcome("Win", 0, 0, true), PvpRules.outcome("Loss", 0, 0, true)
		assert(win.Coins > loss.Coins and loss.Coins > 0)
		-- the streak bonus is capped
		local long = PvpRules.outcome("Win", 0, 100, false)
		assert(long.Coins == R.WinCoins + R.StreakCoins * R.StreakCap, "streak cap")
		-- with the measured bot win rate of a new player, coins per minute stay in a sane band (fight + count-in + cheer)
		local res = botFights()
		local r = res[PROFILES[1].Name]
		local rate = r.Wins / FIGHTS
		local secs = r.Times[FIGHTS // 2] + PvpConfig.CountIn + PvpConfig.ResultHold + 6 -- queue / card taps
		local perMin = (rate * win.Coins + (1 - rate) * loss.Coins) * 60 / secs
		print(string.format("    pvp balance coins: new player ~%d coins / min vs bots", math.floor(perMin)))
		assert(perMin >= 40 and perMin <= 200, "coins per minute " .. perMin)
	end)
end
