-- Pet flair rules: rarity size / sparkle, pet index reward + title, rare hatch payload and rate limit, name tag lines.
return function(t)
	local test, shared = t.test, t.shared
	local Config = shared("Config")
	local PetFlair = shared("PetFlair")
	local SoundConfig = shared("SoundConfig")

	local function assertEq(a, b, msg)
		if a ~= b then
			error((msg or "mismatch") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
		end
	end

	test("rarer pets are never smaller", function()
		local prev = 0
		for _, r in Config.Rarities do
			local s = PetFlair.rarityScale(r)
			assert(s >= prev and s >= 1 and s <= 1.5, "scale " .. r)
			prev = s
		end
		assertEq(PetFlair.rarityScale("Nope"), 1, "unknown rarity")
		assertEq(PetFlair.rarityScale(nil), 1, "nil rarity")
	end)

	test("sparkles: Rare and better only, off with Low Effects", function()
		assert(PetFlair.sparkle("Common") == nil, "common")
		assert(PetFlair.sparkle("Uncommon") == nil, "uncommon")
		for _, r in { "Rare", "Epic", "Legendary" } do
			assert(PetFlair.sparkle(r) ~= nil, r)
			assert(PetFlair.sparkle(r, true) == nil, r .. " low effects")
		end
	end)

	test("first find reward pays once per known species", function()
		local index = {}
		assertEq(PetFlair.firstFindReward(index, "Phoenix"), Config.PetIndex.FirstFindCoins, "first")
		index.Phoenix = 1 -- the hatch is counted in the same write
		assertEq(PetFlair.firstFindReward(index, "Phoenix"), 0, "second")
		assertEq(PetFlair.firstFindReward(index, "Unknown"), 0, "unknown species")
		assertEq(PetFlair.firstFindReward(nil, "Phoenix"), 0, "no index")
		index.Mammoth = 0
		assertEq(PetFlair.firstFindReward(index, "Mammoth"), Config.PetIndex.FirstFindCoins, "zero row")
	end)

	test("every released species gives the Pet Master title", function()
		local species = PetFlair.species()
		assertEq(#species, 39, "species count (released hunt pets; Star Pterodactyl retired, Turtle back)")
		for _, id in species do
			assert(not (Config.Minerals :: any)[id].Retired, "retired species never count toward the title: " .. id)
		end
		for tierId, tier in Config.Tiers :: any do
			for _, id in tier.Minerals do
				assert(not (Config.Minerals :: any)[id].Retired, "retired species is still in an egg pool: " .. tierId .. "/" .. id)
			end
		end
		local index = { OldGeode = 5 } -- unknown ids do not count
		for i, id in species do
			assertEq(PetFlair.title(index), "", "title before " .. i)
			index[id] = 1
			assertEq(PetFlair.foundCount(index), i, "count")
		end
		assert(PetFlair.allFound(index), "all found")
		assertEq(PetFlair.title(index), "Pet Master", "title")
	end)

	test("found count: only released hunt species (no tower-only, no unreleased weekly); earned title stays", function()
		local species = PetFlair.species()
		local inList = {}
		for _, id in species do
			inList[id] = true
		end
		local extra = {}
		local towerOnly, weekly = 0, 0
		for id, m in Config.Minerals do
			if not inList[id] then
				extra[id] = 3 -- tower-only pets and weekly pets that are not out yet
				if m.TowerOnly then
					towerOnly += 1
				else
					weekly += 1
				end
			end
		end
		assert(towerOnly >= 5, "tower-only pets exist in the config")
		assertEq(PetFlair.foundCount(extra), 0, "outside species never count")
		-- every listed species but one, plus all the outside ones: still no title, and never more than the total
		local index = table.clone(extra)
		for i = 1, #species - 1 do
			index[species[i]] = 1
		end
		assertEq(PetFlair.foundCount(index), #species - 1, "count ignores tower/unreleased")
		assert(not PetFlair.allFound(index), "no early Pet Master")
		assertEq(PetFlair.title(index), "", "no title yet")
		-- a saved Pet Master flag keeps the title even if a newly released weekly pet is still missing
		assertEq(PetFlair.title(index, true), "Pet Master", "earned flag keeps the title")
		assertEq(PetFlair.title({}, false), "", "flag false = derived")
		index[species[#species]] = 1
		assertEq(PetFlair.foundCount(index), #species, "count reaches the total, never past it")
	end)

	test("announce payload: rarity gate, only three fields, sanitised", function()
		assert(PetFlair.payload("Ava", "Void Dragon", "Common") == nil, "common not announced")
		assert(PetFlair.payload("Ava", "Void Dragon", "Uncommon") == nil, "uncommon not announced")
		local p = PetFlair.payload("  Ava\n", "Golden Void Dragon", "Legendary")
		assert(p, "legendary")
		assertEq(p.Name, "Ava", "trimmed")
		local n = 0
		for _ in p do
			n += 1
		end
		assertEq(n, 3, "fields")
		assert(PetFlair.payload("", "X", "Rare") == nil, "empty name")
		assert(PetFlair.payload("Ava", 5, "Rare") == nil, "bad pet")
		local long = PetFlair.payload(string.rep("é", 40), "X", "Epic")
		assert(long and #long.Name <= Config.RareHatch.NameMax, "capped")
		assert(utf8.len(long.Name) ~= nil, "valid utf8 after cut")
		assertEq(PetFlair.bannerLine({ Name = "Ava", Pet = "Void Dragon", Rarity = "Epic" }), "Ava hatched an EPIC Void Dragon!", "line")
		assertEq(PetFlair.bannerLine({ Name = "Ben", Pet = "Nova Ptera", Rarity = "Rare" }), "Ben hatched a RARE Nova Ptera!", "line a")
	end)

	test("rate limiter: global gap and per key gap", function()
		local l = PetFlair.newLimiter(6, 30)
		assert(PetFlair.allow(l, "1", 0), "first")
		assert(not PetFlair.allow(l, "2", 3), "global gap")
		assert(PetFlair.allow(l, "2", 7), "other key after gap")
		assert(not PetFlair.allow(l, "1", 20), "same key within 30")
		assert(PetFlair.allow(l, "1", 31), "same key after 30")
		local g = PetFlair.newLimiter(4)
		assert(PetFlair.allow(g, "all", 100), "g1")
		assert(not PetFlair.allow(g, "all", 102), "g2")
		assert(PetFlair.allow(g, "all", 104), "g3")
	end)

	test("name tag lines", function()
		assertEq(#PetFlair.tagLines(0, ""), 0, "none")
		assertEq(PetFlair.battleLine(0, 0, 0), nil, "no battle line for a new player")
		assertEq(PetFlair.battleLine(1240, 412, 2), "\u{26A1}1240  \u{1F3C6}412", "power and trophies")
		assertEq(PetFlair.battleLine(1240, 412, 5), "\u{26A1}1240  \u{1F3C6}412  \u{1F451}5 streak", "crown from 3 wins in a row")
		assertEq(#PetFlair.tagLines(12, "Pet Master", "x"), 3, "battle line added last")
		local l = PetFlair.tagLines(12, "Pet Master")
		assertEq(l[1], "Pet Master", "title first")
		assertEq(l[2], "Best floor 12", "floor")
		assertEq(#PetFlair.tagLines(3.7, nil), 1, "floor only")
		assertEq(PetFlair.tagLines(3.7, nil)[1], "Best floor 3", "floored")
	end)

	test("sound config: no invented ids, and pets never roar", function()
		for name, id in SoundConfig.Ids do
			assert(type(id) == "number" and id >= 0 and id == math.floor(id), name)
		end
		for _, key in { "EggCrunch", "EggPop", "HatchChoir" } do
			assert(SoundConfig.Ids[key] ~= nil, key .. " listed")
		end
		assert(SoundConfig.Roar == nil, "no roar table (owner rule: pets never roar)")
	end)

	test("hatch timing: commons about 2 s, Rare+ about 6 s slow motion with glow", function()
		local c = PetFlair.hatchTiming("Common")
		local u = PetFlair.hatchTiming("Uncommon")
		assert(math.abs(c.Total - 2) <= 0.3 and not c.Glow and not c.SlowMo, "common ~2 s")
		assertEq(u.Total, c.Total, "uncommon like common")
		for _, r in { "Rare", "Epic", "Legendary" } do
			local h = PetFlair.hatchTiming(r)
			assert(math.abs(h.Total - 6) <= 0.5 and h.Glow and h.SlowMo, r .. " ~6 s")
			local A = PetFlair.HatchAnim
			assert(h.Slow > (A.SlowTo - A.SlowFrom), r .. " slow motion")
			assert(PetFlair.hatchPopAt(h) >= 2 and PetFlair.hatchPopAt(h) < h.Total, r .. " pop after build-up")
		end
		assert(PetFlair.revealSeconds("Legendary") > PetFlair.revealSeconds("Common"), "server reveal follows rarity")
		assertEq(PetFlair.longestReveal(), PetFlair.revealSeconds("Legendary"), "longest")
		for _, h in { c, PetFlair.hatchTiming("Epic") } do
			local prev = -1
			for i = 0, 100 do
				local a = PetFlair.hatchWarp(h, h.Total * i / 100)
				assert(a >= prev - 1e-9, "monotonic")
				prev = a
			end
			assertEq(PetFlair.hatchWarp(h, 0), 0, "start")
			assertEq(PetFlair.hatchWarp(h, h.Total + 1), PetFlair.HatchAnim.End, "end")
			assert(math.abs(PetFlair.hatchWarp(h, PetFlair.hatchPopAt(h)) - PetFlair.HatchAnim.Pop) < 1e-6, "pop maps to Pop")
		end
	end)
end
