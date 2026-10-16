-- Material Discoveries (docs/m6/DISCOVERIES.md): data-driven categories, deterministic server-side choice per
-- rock + round, told only on completion, safe profile defaults. Presentation only: no value / capacity change.
return function(t)
	local test, shared = t.test, t.shared
	local Config = shared("Config")
	local Materials = shared("Materials")
	local RoundRocks = shared("RoundRocks")
	local Random, Vector3 = t.Random, t.Vector3

	local function assertEq(a, b, msg)
		if a ~= b then
			error((msg or "mismatch") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
		end
	end

	test("materials: data-driven set, weights 80/15/5, no economy fields", function()
		assertEq(#Config.MaterialOrder, 3)
		local total = 0
		for _, id in Config.MaterialOrder do
			local m = Config.Materials[id]
			assert(m and m.Id == id and m.Name and m.Desc and m.Look, id)
			assert(m.Value == nil and m.Price == nil and m.Cash == nil and m.Capacity == nil and m.Speed == nil, "presentation only")
			total += m.Weight
		end
		assertEq(Config.Materials.CommonStone.Weight, 80)
		assertEq(Config.Materials.QuartzFragment.Weight, 15)
		assertEq(Config.Materials.MetallicSpecks.Weight, 5)
		assertEq(total, 100)
	end)

	test("materials: pick is deterministic and depends only on salt, round and rock", function()
		for rock = 1, 200 do
			assertEq(Materials.pick(777, 3, rock), Materials.pick(777, 3, rock), "same inputs, same material")
		end
		local differs = 0
		for rock = 1, 200 do
			if Materials.pick(777, 3, rock) ~= Materials.pick(778, 3, rock) then
				differs += 1
			end
		end
		assert(differs > 0, "the salt matters")
		for rock = 1, 50 do
			local m = Materials.pick(5, 1, rock)
			assert(Config.Materials[m], "known id")
		end
	end)

	test("materials: distribution over many rocks matches the weights", function()
		local n = {}
		local N = 40000
		for i = 1, N do
			local id = Materials.pick(123457 + (i // 1600) * 7919, 1 + (i // 4000), i % 1600 + 1)
			n[id] = (n[id] or 0) + 1
		end
		assert(math.abs(n.CommonStone / N - 0.80) < 0.012, "common " .. n.CommonStone / N)
		assert(math.abs(n.QuartzFragment / N - 0.15) < 0.012, "quartz " .. n.QuartzFragment / N)
		assert(math.abs(n.MetallicSpecks / N - 0.05) < 0.008, "metal " .. n.MetallicSpecks / N)
	end)

	local function make(seed: number, tool: string?, roundId: number?)
		local core = RoundRocks.new({
			MatchKey = "k",
			RoundId = roundId or 1,
			Tier = "Gravel",
			Seed = seed,
			TargetRng = Random.new(seed + 1),
			Members = { { UserId = 1, Tool = tool or "Hammer", Machine = nil, Station = 1 } },
		})
		core:setPhase("Searching")
		return core
	end

	local clock = 0
	local function tick(dt)
		clock += dt
		return clock
	end

	-- crushes up to n non-target rocks one by one, returns the Cracked results
	local function crackSome(core, n)
		local out = {}
		local stationPos = RoundRocks.stationPosition(1)
		for _, id in core.Pile:pickableIds(Config.Carry.ReachLevels) do
			if #out >= n then
				break
			end
			if id ~= core.TargetId then
				local p = core.Pile:localPosition(id) or Vector3.zero
				if core:pickup(1, core.RoundId, id, Vector3.new(p.X, 3, p.Z), tick(0.6)) == nil then
					local res = core:deposit(1, core.RoundId, stationPos, tick(0.5))
					assert(res, "deposit")
					for _ = 1, #res.Moved do
						local results = core:crush(1, core.RoundId, stationPos, tick(1.5))
						for _, r in results do
							if r.Kind == "Cracked" then
								table.insert(out, r)
							end
						end
					end
				end
			end
		end
		return out
	end

	test("materials: the core fixes a rock's material once, equal to Materials.pick, whoever and whatever cracks it", function()
		local a, b = make(31, "Hammer"), make(31, "Jackhammer")
		assertEq(a.MatSalt, b.MatSalt, "salt comes from the server-only rng")
		assertEq(a.TargetId, Random.new(32):NextInteger(1, a.Total), "drawing the salt after the target leaves the target unchanged")
		local ra, rb = crackSome(a, 12), crackSome(b, 12)
		assert(#ra >= 8 and #rb >= 8)
		local byRock = {}
		for _, r in ra do
			assertEq(r.Material, Materials.pick(a.MatSalt, a.RoundId, r.RockId), "result material is the pure pick")
			byRock[r.RockId] = r.Material
		end
		for _, r in rb do
			if byRock[r.RockId] then
				assertEq(r.Material, byRock[r.RockId], "tool change cannot reroll")
			end
		end
	end)

	test("materials: the target rock is not special-cased and the geode result carries no material", function()
		local core = make(44)
		local stationPos = RoundRocks.stationPosition(1)
		local id = core.TargetId
		local p = core.Pile:localPosition(id) or Vector3.zero
		-- pick the target up (it may be out of reach in a dense mound: skip then)
		if core:pickup(1, 1, id, Vector3.new(p.X, 3, p.Z), tick(1)) == nil then
			core:deposit(1, 1, stationPos, tick(1))
			local found
			for _ = 1, 4 do
				for _, r in core:crush(1, 1, stationPos, tick(1.5)) do
					if r.Kind == "Found" then
						found = r
					end
				end
			end
			assert(found, "target crushed")
			assertEq(found.Material, nil, "no material on the geode result")
			assertEq(core.Members[1].Rubble, 0, "a geode pays no rubble")
		end
	end)

	test("materials: nothing about an uncracked rock carries a material (rocks, counters, events, snapshots)", function()
		local core = make(52)
		local stationPos = RoundRocks.stationPosition(1)
		for _, rock in core.Rocks do
			for k in rock do
				assert(k ~= "Mat" and k ~= "Material", "rock record leaks " .. k)
			end
			break
		end
		local picked = 0
		for _, id in core.Pile:pickableIds(Config.Carry.ReachLevels) do
			if picked >= 3 then
				break
			end
			local p = core.Pile:localPosition(id) or Vector3.zero
			if core:pickup(1, 1, id, Vector3.new(p.X, 3, p.Z), tick(0.6)) == nil then
				picked += 1
			end
		end
		core:deposit(1, 1, stationPos, tick(0.5))
		for _, view in core:stationViews(tick(0.1)) do
			for k in view do
				assert(k ~= "Mat" and k ~= "Material", "station view leaks " .. k)
			end
		end
		for k in core:counters(1) do
			assert(k ~= "Mat" and k ~= "Material")
		end
		for _, e in core:drainEvents() do
			assertEq(e.Mat, nil, "no event before completion names a material (" .. e.Kind .. ")")
		end
		-- completion events do
		core:crush(1, 1, stationPos, tick(1.5))
		local seenDone = false
		for _, e in core:drainEvents() do
			if e.Kind == "Done" then
				seenDone = true
				assert(Config.Materials[e.Mat], "Done names a configured material")
			end
		end
		assert(seenDone)
	end)

	test("materials: record counts a completion and flags only the first of a category", function()
		local s = Materials.empty()
		local counted, isNew = Materials.record(s, "QuartzFragment")
		assert(counted and isNew)
		counted, isNew = Materials.record(s, "QuartzFragment")
		assert(counted and not isNew)
		assertEq(s.Counts.QuartzFragment, 2)
		counted, isNew = Materials.record(s, "FutureStone")
		assert(not counted and not isNew, "unknown ids are ignored, no crash")
		assertEq(s.Counts.FutureStone, nil)
		local have, total = Materials.progress(s)
		assertEq(have, 1)
		assertEq(total, 3)
	end)

	test("materials: old or damaged profile data gets safe defaults and keeps unknown future ids", function()
		local fresh = Materials.normalize(nil)
		assertEq(next(fresh.Found), nil)
		local weird = Materials.normalize({ Found = { CommonStone = true, Future = true, Bad = "yes" }, Counts = { CommonStone = 4.7, Future = 2, Neg = -3, Nan = 0 / 0, Str = "7" } })
		assertEq(weird.Counts.CommonStone, 4)
		assertEq(weird.Counts.Future, 2, "future ids survive")
		assertEq(weird.Counts.Neg, nil)
		assertEq(weird.Counts.Nan, nil)
		assertEq(weird.Counts.Str, nil)
		assertEq(weird.Found.Bad, nil)
		assertEq(weird.Found.Future, true)
		local have, total = Materials.progress(weird)
		assertEq(have, 1, "only configured ids count toward n/N")
		assertEq(total, 3)
		local pub = Materials.publicView(weird)
		assertEq(pub.Found.Future, nil, "the client never sees unknown ids")
		assertEq(pub.Counts.CommonStone, 4)
		local partial = Materials.normalize({ Found = {} })
		assertEq(type(partial.Counts), "table")
	end)
end
