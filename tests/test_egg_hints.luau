-- Egg wobble hint (src/shared/EggHints.luau): only pile eggs wobble, the pet egg is picked at roughly the
-- tuned chance while it is in the pile, every other pile egg is picked uniformly, and one egg left still works.
return function(t)
	local test, shared = t.test, t.shared
	local EggHints = shared("EggHints")
	local EggConfig = shared("EggConfig")
	local Random = t.Random

	local function assertEq(a, b, msg)
		if a ~= b then
			error((msg or "mismatch") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
		end
	end

	test("egg hints: pileIds keeps only InPile eggs, sorted", function()
		local rocks = {
			[5] = { State = "InPile" },
			[2] = { State = "Carried" },
			[9] = { State = "Queued" },
			[1] = { State = "InPile" },
			[7] = { State = "Processing" },
			[3] = { State = "ResolvedOrdinary" },
		}
		local ids = EggHints.pileIds(rocks)
		assertEq(#ids, 2)
		assertEq(ids[1], 1)
		assertEq(ids[2], 5)
	end)

	test("egg hints: never picks a non-pile egg, nil on an empty pile", function()
		local rng = Random.new(7)
		assertEq(EggHints.pick(rng, {}, 3, 0.25), nil, "empty pile")
		local pile = { 2, 4, 6, 8 }
		local inPile = { [2] = true, [4] = true, [6] = true, [8] = true }
		for _ = 1, 4000 do
			-- target outside the pile (already carried): never returned
			local id = EggHints.pick(rng, pile, 5, 0.9)
			assert(id and inPile[id], "picked a non-pile egg: " .. tostring(id))
			local id2 = EggHints.pick(rng, pile, 4, 0.25)
			assert(id2 and inPile[id2], "picked a non-pile egg: " .. tostring(id2))
		end
	end)

	test("egg hints: target chance and uniform others over many picks", function()
		local rng = Random.new(12345)
		local pile = {}
		for i = 1, 20 do
			table.insert(pile, i)
		end
		local chance = EggConfig.Wobble.TargetChance
		local runs = 40000
		local hits = {}
		for _ = 1, runs do
			local id = EggHints.pick(rng, pile, 11, chance) :: number
			hits[id] = (hits[id] or 0) + 1
		end
		local rate = (hits[11] or 0) / runs
		assert(math.abs(rate - chance) < 0.015, "target rate " .. rate)
		local each = (1 - chance) / 19
		for i = 1, 20 do
			if i ~= 11 then
				local r = (hits[i] or 0) / runs
				assert(math.abs(r - each) < 0.01, "other rate " .. i .. " " .. r)
				assert(r < rate, "pet egg should wobble more than any one other egg")
			end
		end
	end)

	test("egg hints: target unknown or not in pile -> uniform", function()
		local rng = Random.new(99)
		local pile = { 1, 2, 3, 4 }
		local hits = {}
		for _ = 1, 20000 do
			local id = EggHints.pick(rng, pile, nil, 0.25) :: number
			hits[id] = (hits[id] or 0) + 1
		end
		for i = 1, 4 do
			assert(math.abs(hits[i] / 20000 - 0.25) < 0.02, "uniform " .. i)
		end
	end)

	test("egg hints: one egg left", function()
		local rng = Random.new(3)
		for _ = 1, 50 do
			assertEq(EggHints.pick(rng, { 42 }, 42, 0.25), 42, "only the target left")
			assertEq(EggHints.pick(rng, { 17 }, 42, 0.25), 17, "only a non-target left")
			assertEq(EggHints.pick(rng, { 17 }, nil, 0.25), 17, "target unknown")
		end
	end)

	test("egg hints: every zone mixes decoys; the Meadow is slower with a higher pet chance; wobbles go on without the pet egg", function()
		local rng = Random.new(2024)
		local pile = { 1, 2, 3, 4, 5, 6 }
		assert(EggHints.slowTier("Gravel"), "Meadow is slow")
		for _, tier in { "Quarry", "Cavern", "Volcanic", "Meteor" } do
			assert(not EggHints.slowTier(tier), tier .. " is not slow")
		end
		assert(not EggHints.slowTier(nil), "unknown tier is not slow")
		for _, tier in { "Gravel", "Quarry" } do
			local decoys, target = 0, 0
			for _ = 1, 4000 do
				local id = EggHints.pickForTier(rng, pile, 4, tier) :: number
				assert(table.find(pile, id), tier .. " pick in pile")
				if id == 4 then
					target += 1
				else
					decoys += 1
				end
			end
			assert(decoys > 0 and target > 0, tier .. " mixes decoys and the pet egg")
			assert(math.abs(target / 4000 - EggHints.targetChance(tier)) < 0.03, tier .. " target rate")
			-- pet egg already taken (or unknown, e.g. practice): decoys still wobble
			for _ = 1, 200 do
				local id = EggHints.pickForTier(rng, pile, 9, tier)
				assert(id and table.find(pile, id), tier .. ": pet egg out of the pile, a decoy still wobbles")
				assert(EggHints.pickForTier(rng, pile, nil, tier), tier .. ": target unknown still wobbles")
			end
		end
		assert(EggHints.targetChance("Gravel") > EggHints.targetChance("Quarry"), "Meadow pet chance a bit higher")
		assert(EggHints.targetChance("Gravel") < 0.5, "Meadow pet chance still small")
	end)

	test("egg hints: Meadow wobbles less often than later zones", function()
		local mlo, mhi = EggHints.gapRange("Gravel")
		local flo, fhi = EggHints.gapRange("Quarry")
		assertEq(flo, EggConfig.Wobble.MinGap)
		assertEq(fhi, EggConfig.Wobble.MaxGap)
		assertEq(mlo, EggConfig.Wobble.MeadowMinGap)
		assertEq(mhi, EggConfig.Wobble.MeadowMaxGap)
		assert(mlo > flo and mhi > fhi and mhi >= mlo, "Meadow gap is longer")
	end)

	test("egg hints: chirps come from decoys too, never on the egg, jitter wider than half the radius", function()
		local V3 = t.Vector3
		local c = EggConfig.Chirp
		local rng = Random.new(77)
		local egg = V3.new(10, 3, -4)
		assertEq(EggHints.chirpPoint(rng, nil, egg, c.Radius, c.JitterMin, c.JitterMax), nil, "no source")
		assertEq(EggHints.chirpPoint(rng, egg, egg + V3.new(c.Radius + 0.5, 0, 0), c.Radius, c.JitterMin, c.JitterMax), nil, "too far")
		for _ = 1, 2000 do
			local listener = egg + V3.new(rng:NextNumber(-5, 5), 0, rng:NextNumber(-5, 5))
			local at = EggHints.chirpPoint(rng, egg, listener, c.Radius, c.JitterMin, c.JitterMax)
			assert(at, "close enough must chirp")
			local off = at - egg
			assert(math.abs(off.Y) < 1e-6, "flat jitter")
			local d = off.Magnitude
			assert(d >= c.JitterMin - 1e-6 and d <= c.JitterMax + 1e-6, "jitter distance " .. d)
		end
		-- a row of eggs 2 studs apart; the pet egg is id 5 at x = 8
		local eggs = {}
		for i = 1, 20 do
			table.insert(eggs, { Id = i, Pos = V3.new((i - 1) * 2, 0, 0) })
		end
		local petPos = eggs[5].Pos
		-- nothing near: no source
		assertEq(EggHints.chirpSource(rng, eggs, V3.new(0, 0, 100), c.Radius, 5, c.TargetChance), nil, "no egg near")
		-- the pet egg far away: a decoy near the listener still chirps (a chirp does not mean "pet egg near")
		local farFromPet = V3.new(34, 0, 0)
		for _ = 1, 500 do
			local src = EggHints.chirpSource(rng, eggs, farFromPet, c.Radius, 5, c.TargetChance)
			assert(src and src ~= petPos, "decoy source")
			assert((src - farFromPet).Magnitude <= c.Radius + 1e-6, "source near the listener")
		end
		-- the pet egg near: it is the source only at about TargetChance
		local pet = 0
		for _ = 1, 4000 do
			if EggHints.chirpSource(rng, eggs, petPos, c.Radius, 5, c.TargetChance) == petPos then
				pet += 1
			end
		end
		assert(math.abs(pet / 4000 - c.TargetChance) < 0.03, "pet chirp rate " .. pet / 4000)
		assert(c.TargetChance < 0.5 and c.Chance > 0 and c.Chance <= 1, "chirp chances")
		assert((c.JitterMin + c.JitterMax) / 2 > c.Radius / 2 and c.JitterMin > 0, "jitter wider than half the radius on average")
		assert(c.MinGap > 0 and c.MaxGap >= c.MinGap, "chirp gaps")
		assertEq(c.SoundId, shared("PetSoundIds").EggChirp, "chirp sound comes from PetSoundIds.EggChirp")
	end)

	test("egg config: sane tuning", function()
		local w, b = EggConfig.Wobble, EggConfig.Boots
		assert(w.TargetChance > 0 and w.TargetChance < 0.5, "small target chance")
		assert(w.MinGap > 0 and w.MaxGap >= w.MinGap, "gaps")
		assert(b.Chance > 0 and b.Chance < 0.2 and b.Seconds > 0 and b.Bonus > 0 and b.Bonus < 1, "boots")
	end)
	test("egg hints: patch wobbles a small area, the anchor is usually outside its own patch", function()
		local V3 = t.Vector3
		local w = EggConfig.Wobble
		local rng = Random.new(7)
		-- a 14 x 14 grid of eggs, one egg size (2.2 studs) apart
		local eggs = {}
		for x = 0, 13 do
			for z = 0, 13 do
				table.insert(eggs, { Id = x * 14 + z + 1, Pos = V3.new(x * 2.2, 0, z * 2.2) })
			end
		end
		local anchorId = 7 * 14 + 7 + 1
		local anchor = V3.new(7 * 2.2, 0, 7 * 2.2)
		local hit = 0
		for _ = 1, 2000 do
			local ids = EggHints.patch(rng, anchor, eggs, w.PatchRadius, w.PatchJitterMin, w.PatchJitterMax, w.PatchMax)
			assert(#ids >= 2 and #ids <= w.PatchMax, "patch size " .. #ids)
			for i = 2, #ids do
				assert(ids[i - 1] < ids[i], "sorted by id, no duplicates")
			end
			if table.find(ids, anchorId) then
				hit += 1
			end
		end
		assert(hit > 0, "the anchor is sometimes in its patch")
		assert(hit / 2000 < 0.5, "the anchor is outside its own patch most of the time: " .. hit / 2000)
		assertEq(#EggHints.patch(rng, V3.new(100, 0, 100), eggs, w.PatchRadius, w.PatchJitterMin, w.PatchJitterMax, w.PatchMax), 0)
		assert(w.PatchRadius > 0 and w.PatchJitterMax > w.PatchRadius and w.PatchJitterMin < w.PatchRadius and w.PatchMax >= 2, "jitter range crosses the radius")
	end)

	test("egg hints: intersecting wobble patches does not name the pet egg (Meadow and Forest)", function()
		local V3 = t.Vector3
		local w = EggConfig.Wobble
		local rng = Random.new(4242)
		-- a 12 x 12 pile (dense like a stacked mound, and one egg size apart); the pet egg sits in the middle
		for _, spacing in { 1.2, 2.2 } do
			local eggs, posOf, pile = {}, {}, {}
			for x = 0, 11 do
				for z = 0, 11 do
					local id = x * 12 + z + 1
					local pos = V3.new(x * spacing, 0, z * spacing)
					table.insert(eggs, { Id = id, Pos = pos })
					posOf[id] = pos
					table.insert(pile, id)
				end
			end
			local target = 6 * 12 + 6 + 1
			for _, tier in { "Gravel", "Quarry" } do
				local trials, named = 1500, 0
				for _ = 1, trials do
					-- an attacker keeps the running intersection of three wobbles in a row
					local inter: { [number]: boolean }? = nil
					for _ = 1, 3 do
						local anchorId = EggHints.pickForTier(rng, pile, target, tier) :: number
						local ids = EggHints.patch(rng, posOf[anchorId], eggs, w.PatchRadius, w.PatchJitterMin, w.PatchJitterMax, w.PatchMax)
						local nextInter: { [number]: boolean } = {}
						for _, id in ids do
							if inter == nil or inter[id] then
								nextInter[id] = true
							end
						end
						inter = nextInter
					end
					local count, hasTarget = 0, false
					for id in inter :: { [number]: boolean } do
						count += 1
						hasTarget = hasTarget or id == target
					end
					if count == 1 and hasTarget then
						named += 1
					end
				end
				print(("  intersect check: spacing %.1f %s named %.2f%%"):format(spacing, tier, 100 * named / trials))
				assert(named / trials < 0.02, tier .. ": three intersected wobbles name the pet egg too often: " .. named / trials)
			end
		end
	end)
end
