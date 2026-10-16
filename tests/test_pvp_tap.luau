-- Tap to fight: TAP combos, BLOCK rings and PERFECT blocks (shared/PvpRules.tap / block, PvpConfig.Tap / Block).
return function(t)
	local test, shared = t.test, t.shared
	local PvpConfig = shared("PvpConfig")
	local PvpRules = shared("PvpRules")
	local TowerConfig = shared("TowerConfig")

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
	local function mirror(xpA, xpB)
		local a = team("a", { { "Raptor", "Rare", 1, xpA }, { "Mammoth", "Rare", 2, xpA }, { "Griffin", "Rare", 3, xpA } })
		local b = team("b", { { "Raptor", "Rare", 1, xpB }, { "Mammoth", "Rare", 2, xpB }, { "Griffin", "Rare", 3, xpB } })
		return PvpRules.newFight(a, b)
	end
	local function kinds(list)
		local out = {}
		for _, e in list do
			out[e.Kind] = (out[e.Kind] or 0) + 1
		end
		return out
	end

	-- One fight where each side taps `taps` times a second and blocks a share `blocks` of the rings it sees.
	local function play(f, rand, taps, blocks)
		local acc = { 0, 0 }
		local dt = TowerConfig.Tick
		while f.State == "Fighting" do
			for _, e in PvpRules.step(f, dt, rand) do
				if e.Kind == "Warn" and rand() < blocks[e.Side] then
					PvpRules.block(f, e.Side)
				end
			end
			for side = 1, 2 do
				acc[side] += dt * taps[side]
				while acc[side] >= 1 and f.State == "Fighting" do
					acc[side] -= 1
					PvpRules.tap(f, side)
				end
				PvpRules.useSpecial(f, side, rand())
			end
		end
		return f.Winner
	end

	test("pvp tap: a tap hits a rival pet and fills the SPECIAL meter", function()
		local f = mirror(0, 0)
		local ok, ev = PvpRules.tap(f, 1)
		assert(ok, "tap works in a fight")
		assertEq(ev[1].Kind, "Tap")
		assertEq(ev[1].Side, 1)
		assertEq(ev[1].Combo, 1)
		assert(string.sub(ev[1].To, 1, 1) == "b", "tap lands on the rival team")
		assert(ev[1].Amount >= 1, "tap does damage")
		assert(f.Meters[1] > 0, "tap fills the meter")
		assertEq(f.Meters[2], 0)
		assert(not PvpRules.tap(f, 3), "no third side")
	end)

	test("pvp tap: quick taps grow a combo that hits harder, capped; a pause resets it", function()
		local f = mirror(0, 0)
		local amounts = {}
		for i = 1, PvpConfig.Tap.ComboMax + 5 do
			f.Time += 0.1
			local _, ev = PvpRules.tap(f, 1)
			assertEq(ev[1].Combo, i)
			amounts[i] = ev[1].Amount
		end
		assert(amounts[PvpConfig.Tap.ComboMax + 1] > amounts[1], "combo hits harder")
		assertEq(amounts[PvpConfig.Tap.ComboMax + 1], amounts[PvpConfig.Tap.ComboMax + 5], "combo bonus is capped")
		f.Time += PvpConfig.Tap.ComboGap + 0.1
		local _, ev = PvpRules.tap(f, 1)
		assertEq(ev[1].Combo, 1, "a pause resets the combo")
	end)

	test("pvp tap: no taps once the fight is over", function()
		local f = mirror(0, 0)
		PvpRules.simulate(f, stream(3))
		assert(f.State == "Done")
		assert(not PvpRules.tap(f, 1))
		assert(not PvpRules.block(f, 1))
	end)

	test("pvp block: every type move gets a ring first; a BLOCK in time makes it PERFECT", function()
		local f = mirror(0, 0)
		local rand = stream(11)
		local warned, moves, perfect = {}, 0, 0
		local hpBefore
		while f.State == "Fighting" and f.Time < 20 do
			for _, e in PvpRules.step(f, TowerConfig.Tick, rand) do
				if e.Kind == "Warn" then
					assert(warned[e.From] == nil, "one ring per move")
					warned[e.From] = e
					if e.Side == 1 then
						local before = f.Meters[1]
						assert(PvpRules.block(f, 1), "block with a ring up works")
						assertEq(f.Meters[1], before, "the meter bonus waits for the move")
					end
				elseif e.Kind == "Perfect" then
					perfect += 1
					assertEq(e.Side, 1, "only side 1 blocked")
					assert(warned[e.From] ~= nil, "the blocked move had a ring")
				elseif e.Kind == "Hit" then
					local u
					for _, x in f.Units do
						if x.Id == e.From then
							u = x
						end
					end
					if u and u.Swing % 2 == 0 then
						moves += 1
						assert(warned[e.From] ~= nil, "a type move without a ring: " .. e.From)
						warned[e.From] = nil
					end
				end
			end
			for side = 1, 2 do
				PvpRules.useSpecial(f, side, rand())
			end
		end
		assert(moves >= 6, "fight had type moves: " .. moves)
		assert(perfect >= 2, "perfect blocks happened: " .. perfect)
	end)

	test("pvp block: PERFECT cuts the move's damage and adds meter", function()
		local function run(block)
			local f = mirror(0, 0)
			local rand = stream(5)
			while true do
				for _, e in PvpRules.step(f, TowerConfig.Tick, rand) do
					if e.Kind == "Warn" and e.Side == 1 and block then
						PvpRules.block(f, 1)
					end
				end
				if f.Time > 15 then
					return PvpRules.healthShare(f, 1), f.Meters[1]
				end
			end
		end
		local guarded = run(true)
		local open = run(false)
		assert(guarded > open, string.format("blocking keeps more health: %.3f vs %.3f", guarded, open))
	end)

	test("pvp block: a BLOCK with no ring misses and locks BLOCK for a moment", function()
		local f = mirror(0, 0)
		local ok, ev = PvpRules.block(f, 1)
		assert(not ok, "no ring, no block")
		assertEq(kinds(ev).BlockMiss, 1)
		-- a ring comes up while locked: still refused
		local u = f.Units[4]
		u.Warned = true
		f.Time += PvpConfig.Block.MissLock * 0.5
		assert(not PvpRules.block(f, 1), "locked")
		assert(not u.Guarded)
		f.Time += PvpConfig.Block.MissLock
		assert(PvpRules.block(f, 1), "lock wears off")
		assert(u.Guarded)
		assert(not PvpRules.block(f, 1), "the only ring is already blocked: miss")
	end)

	-- every egg species a player can own (as tests/test_pvp_balance.luau)
	local PetStats = shared("PetStats")
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
	local function playerTeam(rand, lvl)
		local out = {}
		for i, r in { "Rare", "Uncommon", "Common" } do
			local pet = { Mineral = species[math.floor(rand() * #species) + 1], Rarity = r, Modifier = "Natural", Seed = math.floor(rand() * 2 ^ 30) + 1 }
			local level = math.max(1, math.floor(PetStats.cap(pet) * lvl + 0.5))
			table.insert(out, { Id = "1:" .. i, Xp = PetStats.xpForLevel(level), Pet = pet })
		end
		return out
	end

	test("pvp balance: vs bots, playing along wins more, watching only still wins some, training beats tapping", function()
		local bot = { taps = PvpConfig.Tap.BotTaps, block = PvpConfig.Block.BotBlock }
		-- the player's team (a bit trained) vs a bot team of its power; `strong` = the bot copies a maxed team
		local function rate(taps, block, strong, n)
			local wins = 0
			for seed = 1, n do
				local rand = stream(seed * 7919 + 13)
				local mine = playerTeam(rand, 0.3)
				local foe = PvpRules.botTeam(if strong then playerTeam(stream(seed * 31 + 1), 1) else mine, rand)
				for i, tp in foe do
					tp.Id = "2:" .. i
				end
				if play(PvpRules.newFight(mine, foe), rand, { taps, bot.taps }, { block, bot.block }) == 1 then
					wins += 1
				end
			end
			return wins / n
		end
		local n = 150
		local good = rate(5, 0.6, false, n) -- a kid tapping fast and catching most rings
		local idle = rate(0, 0, false, n) -- a kid who only watches
		local stronger = rate(PvpConfig.Tap.PerSecond, 0.9, true, n) -- great play vs a maxed team
		print(string.format("    tap balance: good %.0f%%, idle %.0f%%, great vs maxed %.0f%%", good * 100, idle * 100, stronger * 100))
		assert(good >= 0.7 and good <= 0.95, "playing along should matter, not decide everything")
		assert(idle >= 0.25, "watching only is not hopeless")
		assert(stronger <= 0.25, "tapping must not beat real training")
	end)

	test("pvp balance: tap fights still last a while", function()
		local total, n = 0, 20
		for seed = 1, n do
			local f = mirror(400, 400)
			play(f, stream(seed * 13 + 1), { PvpConfig.Tap.PerSecond, PvpConfig.Tap.BotTaps }, { 0.9, PvpConfig.Block.BotBlock })
			total += f.Time
		end
		print(string.format("    tap fight length: %.1f s", total / n))
		assert(total / n >= 12, "fights are not over in a flash")
	end)
end
