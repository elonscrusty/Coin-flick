-- Hunt fun (owner picks 2026-10-15, shared/HuntFun): surprise eggs, the pet helper and prizes for everyone.
-- The server routes (payouts, helper caps, results rows) are covered by tests/server/rocks.luau.
return function(t)
	local test, shared, Random = t.test, t.shared, t.Random
	local Config = shared("Config")
	local HuntFun = shared("HuntFun")
	local RoundRocks = shared("RoundRocks")
	local function eq(a, b, msg)
		if a ~= b then
			error(msg .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
		end
	end

	test("hunt fun: every surprise egg pops a known prize at about the set odds", function()
		local rng = Random.new(7)
		local seen: { [string]: number } = {}
		local n = 20000
		for _ = 1, n do
			local s = HuntFun.surprise(rng, "Gravel")
			assert(HuntFun.Surprise.Weights[s.Kind], "known kind " .. tostring(s.Kind))
			assert(s.Amount > 0, "always something")
			seen[s.Kind] = (seen[s.Kind] or 0) + 1
			if s.Kind == "Coins" then
				local f = Config.Tiers.Gravel.CashPerRubble
				assert(s.Amount >= HuntFun.Surprise.CoinsMin * f and s.Amount <= HuntFun.Surprise.CoinsMax * f, "coins in range")
			end
		end
		local total = 0
		for _, w in HuntFun.Surprise.Weights do
			total += w
		end
		for k, w in HuntFun.Surprise.Weights do
			local want = w / total
			local got = (seen[k] or 0) / n
			assert(math.abs(got - want) < 0.02, k .. " share " .. got .. " vs " .. want)
		end
		assert((seen.Jackpot or 0) > 0, "a jackpot shows up")
		-- richer zones pay more
		local j1 = HuntFun.surprise(Random.new(1), "Meteor")
		assert(j1.Amount >= 1, "space works")
	end)

	test("hunt fun: helper steps grow with power and a Robux pet never helps", function()
		assert(HuntFun.helperStep(nil) == nil, "no pet, no helper")
		local s0 = HuntFun.helperStep(0) :: any
		local s1 = HuntFun.helperStep(260) :: any
		local s4 = HuntFun.helperStep(5000) :: any
		assert(s0 and s0.Carry >= 1 and s0.Rate > 0, "any found pet helps a little")
		assert(s1.Rate > s0.Rate, "stronger pet cracks faster")
		assert(s4.Rate >= s1.Rate and s4.Carry >= s1.Carry, "never weaker when stronger")
		local found = { Id = "a", Mineral = "Raptor", Rarity = "Common", Modifier = "Natural", Seed = 11 }
		local bought = { Id = "b", Mineral = "Raptor", Rarity = "Legendary", Modifier = "Natural", Seed = 12 }
		local pet, power = HuntFun.pickHelper({ { Pet = bought, Xp = 0, Bought = true }, { Pet = found, Xp = 0, Bought = false } })
		assert(pet == found and power > 0, "the bought Legendary is skipped")
		local none = HuntFun.pickHelper({ { Pet = bought, Xp = 0, Bought = true } })
		assert(none == nil, "only bought pets: no helper")
		local strong = { Id = "c", Mineral = "Raptor", Rarity = "Rare", Modifier = "Natural", Seed = 13 }
		local best = HuntFun.pickHelper({ { Pet = found, Xp = 0, Bought = false }, { Pet = strong, Xp = 1e9, Bought = false } })
		assert(best == strong, "the strongest found pet helps")
	end)

	test("hunt fun: the helper speeds up cracking on the server core", function()
		local core = RoundRocks.new({ Tier = "Quarry", Seed = 5, TargetRng = Random.new(3), Members = { { UserId = 1, Station = 1, Tool = "Hammer" } } } :: any)
		local m = core.Members[1]
		assert(m.HelpRate == 1, "no helper by default")
		core:setHelper(1, 0.25)
		assert(math.abs(m.HelpRate - 1.25) < 1e-9, "helper bonus applied")
		core:setHelper(1, 5)
		assert(m.HelpRate == 2, "clamped")
		core:setHelper(1, 0 / 0)
		assert(m.HelpRate == 2, "NaN ignored")
		local view = core:stationViews(0)[1]
		assert(view.Help == 2, "the client sees the pace")
		-- cadence: with the helper the next hit may come sooner
		core:setHelper(1, 0.25)
		local tool = Config.Handhelds.Hammer
		local gapWith = 1 / (tool.Rate * 1.25)
		assert(gapWith < 1 / tool.Rate, "shorter gap")
	end)

	test("hunt fun: everyone who cracked eggs gets a medal, the finder only the pet", function()
		local p = HuntFun.prizes({
			{ UserId = 1, Eggs = 10 },
			{ UserId = 2, Eggs = 30 },
			{ UserId = 3, Eggs = 12 },
			{ UserId = 4, Eggs = 0 },
		}, 1, "Gravel")
		assert(p[1].Place == 1 and p[1].Coins == 0 and p[1].Xp == 0, "finder: gold, pet only")
		assert(p[2].Place == 2 and p[2].Medal == "Silver", "most eggs: silver")
		assert(p[3].Place == 3 and p[3].Medal == "Bronze", "next: bronze")
		assert(p[4] == nil, "no eggs: no prize")
		assert(p[2].Coins > p[3].Coins and p[2].Xp > p[3].Xp, "better place, better prize")
		-- ties share a place
		local tie = HuntFun.prizes({ { UserId = 1, Eggs = 1 }, { UserId = 2, Eggs = 5 }, { UserId = 3, Eggs = 5 }, { UserId = 4, Eggs = 2 } }, 1, "Gravel")
		assert(tie[2].Place == 2 and tie[3].Place == 2 and tie[4].Place == 4, "tie shares 2nd, next is 4th")
		assert(tie[4].Medal == "Star", "4th place medal")
		-- no finder, no prizes
		assert(next(HuntFun.prizes({ { UserId = 1, Eggs = 3 } }, nil, "Gravel")) == nil, "no finder")
		-- egg count is capped, zone pays more
		local big = HuntFun.prizes({ { UserId = 1, Eggs = 1 }, { UserId = 2, Eggs = 1e6 } }, 1, "Gravel")
		local f = Config.Tiers.Gravel.CashPerRubble / 2
		assert(big[2].Coins <= math.floor((HuntFun.Prizes.Coins[2] + HuntFun.Prizes.MaxEggs) * f + 0.5), "capped")
		local space = HuntFun.prizes({ { UserId = 1, Eggs = 1 }, { UserId = 2, Eggs = 10 } }, 1, "Meteor")
		local meadow = HuntFun.prizes({ { UserId = 1, Eggs = 1 }, { UserId = 2, Eggs = 10 } }, 1, "Gravel")
		assert(space[2].Coins > meadow[2].Coins, "richer zone, more coins")
	end)

	test("hunt fun: the Lucky Meter gets a point for sure every 10th egg (Studio: it stayed at 0)", function()
		local per = HuntFun.Surprise.EggsPerMeter
		local count, ticks = 0, 0
		for _ = 1, per * 3 do
			local tick
			count, tick = HuntFun.meterTick(count)
			ticks += if tick then 1 else 0
		end
		assert(ticks == 3, "3 points from " .. per * 3 .. " eggs, got " .. ticks)
		assert(count == 0, "counter wraps")
		local c2 = HuntFun.meterTick(nil)
		assert(c2 == 1, "a missing counter starts at 0")
		assert(HuntFun.Surprise.Weights.Meter == nil, "no random meter roll any more")
		local EggPerks = shared("EggPerks")
		local st = EggPerks.sanitize({ Meter = 3, HuntEggs = "x" })
		assert(st.HuntEggs == 0 and st.Meter == 3, "sanitize keeps the meter and repairs the counter")
	end)

	test("hunt fun: surprise pops sit on screen, clear of the clock card and the crosshair (Studio: overlap)", function()
		-- Juice.floatText: a 160 x 36 label centred on the spot, rising 56 px. Hud's left column (clock card and the
		-- cards under it) is LEFT_W 132 wide from the top-left edge; up to ~300 px tall on the tallest layout.
		for _, scr in { { 1108, 512 }, { 844, 390 }, { 667, 375 }, { 390, 844 }, { 1920, 1080 } } do
			local w, h = scr[1], scr[2]
			for n = 0, 5 do
				local sp = HuntFun.popScreen(n)
				local cx, cy = sp.X * w, sp.Y * h
				local x0, x1, y0, y1 = cx - 80, cx + 80, cy - 18 - 56, cy + 18
				assert(x0 > 20 and x1 < w - 20 and y0 > 20 and y1 < h - 20, "inside the screen " .. w .. "x" .. h)
				assert(x0 > 20 + 132 + 8 or y0 > 300, "clear of the clock card " .. w .. "x" .. h)
				assert(x0 > w / 2 + 30 or x1 < w / 2 - 30 or y1 < h / 2 - 30 or y0 > h / 2 + 30, "clear of the crosshair " .. w .. "x" .. h .. " row " .. n)
			end
		end
		local seen = {}
		for n = 0, #HuntFun.PopSpots - 1 do
			seen[HuntFun.popScreen(n)] = true
		end
		local k = 0
		for _ in seen do
			k += 1
		end
		assert(k == #HuntFun.PopSpots, "pops in one batch take different rows")
	end)

	test("overtime: the gold egg in reach is always the one the pickup takes (Studio: other eggs won)", function()
		local Vector3 = t.Vector3
		-- the Studio case: the gold egg alone at the +X edge, the player 3 studs beside it facing the pile, with an
		-- ordinary egg a little further but straight ahead
		local gold = { Id = 150, Pos = Vector3.new(1209.3, 0.68, -0.78) }
		local rp = Vector3.new(1209.3, 3, -3.78)
		local look = Vector3.new(-1, 0, 0)
		local cands = { { Id = 7, Pos = Vector3.new(1206, 1.2, -3.7) }, { Id = 8, Pos = Vector3.new(1205.8, 2.4, -2.9) }, gold }
		local reach = Config.Carry.PickupRange + 2 * 0.5 - 0.8
		assert(HuntFun.pickTarget(cands, rp, look, look, reach, nil) ~= 150, "without the priority the faced egg wins (the bug)")
		eq(HuntFun.pickTarget(cands, rp, look, look, reach, 150), 150, "with it, the gold egg")
		-- facing away from it, still the gold egg
		eq(HuntFun.pickTarget(cands, rp, -look, -look, reach, 150), 150, "even facing away")
		-- out of reach: the normal choice, never a far egg
		local far = { { Id = 7, Pos = rp + Vector3.new(-2, 0, 0) }, { Id = 150, Pos = rp + Vector3.new(30, 0, 0) } }
		eq(HuntFun.pickTarget(far, rp, look, look, reach, 150), 7, "a far gold egg is not taken")
		eq(HuntFun.pickTarget({}, rp, look, look, reach, 150), nil, "nothing in reach")
	end)

	test("countdown: a new match never keeps the last match's countdown digit up (Studio: a big 1 stayed)", function()
		local IntroRules = shared("IntroRules")
		local k1 = IntroRules.roundKey("arena1", 1)
		assert(IntroRules.onSearching("1", nil, k1) == "GO!", "first hunt: GO")
		-- next match: round numbers restart at 1, but the key differs
		local k2 = IntroRules.roundKey("arena2", 1)
		assert(k2 ~= k1, "rounds of different matches differ")
		assert(IntroRules.onSearching("1", k1, k2) == "GO!", "second match gets its GO")
		assert(IntroRules.onSearching("2", k2, k2) == "", "a digit after GO is cleared, never left up")
		assert(IntroRules.onSearching("GO!", k2, k2) == nil and IntroRules.onSearching("", nil, k2) == nil, "nothing else changes")
	end)

	test("overtime: the glowing pet egg is lifted to a spot that can be picked up", function()
		local RoundRocks = shared("RoundRocks")
		local moved = 0
		for seed = 1, 30 do
			local core = RoundRocks.new({ Tier = "Gravel", Seed = seed, TargetRng = Random.new(seed), Members = { { UserId = 1, Station = 1, Tool = "Hammer" } } } :: any)
			local id = core.TargetId
			local reach = Config.Carry.ReachLevels
			local was = core.Pile:isPickable(id, reach)
			local did = core:surface(id)
			assert(did == not was, "moves only a buried egg")
			assert(core.Pile:isPickable(id, reach), "pickable after (seed " .. seed .. ")")
			assert(core.Rocks[id].State == "InPile", "still in the pile")
			assert(core.Pile.Remaining == core.Total, "nothing lost")
			if did then
				moved += 1
				local ev = core:drainEvents()
				local e = ev[#ev]
				assert(e.Kind == "Move" and e.Id == id and type(e.Col) == "number", "Move event for clients")
			end
			assert(core:surface(id) == false, "second call does nothing")
		end
		assert(moved > 0, "some seeds bury the pet egg")
	end)

	test("hunt fun: the coin pill's +coins text never shows in a hunt or on a hidden pill (Studio: it hit the clock)", function()
		local UiMotion = shared("UiMotion")
		assert(UiMotion.shownChain({ true, true, true }), "all on: drawn")
		assert(not UiMotion.shownChain({ true, false, true }), "a hidden parent: not drawn")
		assert(not UiMotion.shownChain({ true, true, false }), "a disabled ScreenGui: not drawn")
		assert(not UiMotion.shownChain({}), "not under a GUI: not drawn")
		local fs = require("@lune/fs")
		local hud = fs.readFile("src/client/ui/Hud.luau")
		local at = string.find(hud, 'Juice.floatText(refs.Cash, "+"', 1, true)
		assert(at, "the pill float text is still there for the lobby")
		local gate = string.sub(hud, at - 700, at)
		assert(string.find(gate, "State.Match == nil", 1, true), "no pill float text during a hunt")
		assert(string.find(gate, "Juice.onScreen(refs.Cash)", 1, true), "only on a pill that is drawn")
	end)
end

