-- Pet effects rules: aura tiers climb to the Void Dragon, Golden / Rainbow variants, burst LOD, particle budget,
-- happy bounce squash curve, fight hit sparks.
return function(t)
	local test, shared = t.test, t.shared
	local Config = shared("Config")
	local R = shared("PetFxRules")

	local function assertEq(a, b, msg)
		if a ~= b then
			error((msg or "mismatch") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
		end
	end

	test("pet fx: tiers climb Common to Void Dragon", function()
		local prev = -1
		for _, r in Config.Rarities do
			local tr = R.tier(r, "Raptor", nil)
			assert(tr > prev, "tier climbs at " .. r)
			prev = tr
		end
		assertEq(R.tier("Legendary", "CosmicDragon", nil), R.TOP_TIER, "void dragon is the top tier")
		for id, sp in Config.Minerals do
			if sp.Chase and id ~= "CosmicDragon" then
				assertEq(R.tier("Legendary", id, nil), 5, "chase pet " .. id)
			end
		end
		assertEq(R.tier("Nope", nil, nil), 0, "unknown rarity")
	end)

	test("pet fx: every aura piece grows (never shrinks) with the tier", function()
		local function lookAt(tier)
			if tier == 6 then
				return R.look("Legendary", "CosmicDragon", nil)
			elseif tier == 5 then
				for id, sp in Config.Minerals do
					if sp.Chase and id ~= "CosmicDragon" then
						return R.look("Legendary", id, nil)
					end
				end
			end
			return R.look(Config.Rarities[tier + 1], "Raptor", nil)
		end
		local prev = lookAt(0)
		assertEq(prev.Ring, 0, "common has no ring")
		assertEq(prev.Trail, 0, "common has no walk sparkles")
		for tier = 1, R.TOP_TIER do
			local l = lookAt(tier)
			assertEq(l.Tier, tier, "tier " .. tier)
			for _, k in { "Ring", "Motes", "Orbs", "Light", "Trail" } do
				assert(l[k] >= prev[k], k .. " shrank at tier " .. tier)
			end
			assert(l.Alpha <= prev.Alpha, "ring got fainter at tier " .. tier)
			prev = l
		end
		assert(prev.Void and prev.Pillar, "void dragon has the void look and pillar")
	end)

	test("pet fx: Golden and Rainbow variants", function()
		local g = R.look("Common", "Raptor", "Golden")
		assert(g.Ring > 0 and g.Trail > 0, "golden common still shows a ring and trail")
		assert(g.Color ~= Config.RarityColors.Common, "golden recolours")
		local r = R.look("Epic", "Raptor", "Rainbow")
		assert(r.Rainbow, "rainbow flag")
		assertEq(r.Tier, 3, "variant keeps the tier")
		assert(not R.look("Epic", "Raptor", nil).Rainbow, "plain is not rainbow")
	end)

	test("pet fx: bursts shrink with distance and Low Effects", function()
		assertEq(R.lod(10), 1, "near")
		assertEq(R.lod(60), 0.5, "mid")
		assertEq(R.lod(200), 0, "far skipped")
		assert(R.lod(10, true) < 1, "low effects smaller")
		assertEq(R.scaled(18, 0), 0, "skip")
		assertEq(R.scaled(18, 1), 18, "full")
		assert(R.scaled(1, 0.1) == 1, "at least one when shown")
	end)

	test("pet fx: particle budget caps a brawl", function()
		local b = R.newBudget(100, 50)
		local total = 0
		for i = 0, 99 do -- 100 hits in one second, 18 particles each
			total += R.spend(b, 18, i / 100)
		end
		assert(total <= 50 + 100 + 1, "budget held: " .. total)
		assertEq(R.spend(b, 0, 1), 0, "nothing asked")
		local b2 = R.newBudget(100, 50)
		assertEq(R.spend(b2, 10, 0), 10, "fresh budget gives all")
		assertEq(R.spend(b2, 100, 0), 40, "then only what is left")
		assertEq(R.spend(b2, 30, 0.2), 20, "refills over time")
	end)

	test("pet fx: happy bounce squash keeps volume and ends at rest", function()
		local h0, x0, y0 = R.squash(0)
		assertEq(h0, 0, "start height")
		assertEq(x0, 1, "start x")
		assertEq(y0, 1, "start y")
		local h1, x1, y1 = R.squash(1)
		assert(h1 == 0 and x1 == 1 and y1 == 1, "ends at rest")
		local sawStretch, sawSquash = false, false
		for i = 1, 199 do
			local h, sx, sy = R.squash(i / 200)
			assert(h >= 0 and h <= 1, "height bounded")
			assert(sy > 0.75 and sy < 1.2, "up scale bounded " .. sy)
			assert(math.abs(sx * sx * sy - 1) < 1e-6, "volume kept")
			sawStretch = sawStretch or sy > 1.05
			sawSquash = sawSquash or sy < 0.95
		end
		assert(sawStretch and sawSquash, "both stretch and squash happen")
	end)

	test("pet fx: crits are bigger and pop", function()
		local n, c = R.hit("Fire", false), R.hit("Fire", true)
		assert(c.Count > n.Count and c.Size > n.Size and c.Flash > n.Flash, "crit bigger")
		assert(c.Pop and not n.Pop, "only crits pop")
		assertEq(R.hit("Fire").Color, R.ELEMENT_COLORS.Fire, "element colour")
		assert(R.hit("Nope").Color ~= nil, "unknown element falls back")
	end)
end
