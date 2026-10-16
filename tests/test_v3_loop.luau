-- V3 loop rules (docs/V3_LOOP.md): pickup -> basket -> deposit at own station -> crush there.
-- Acceptance checks A-K of the owner's revision, driven through the pure RoundRocks module.
return function(t)
	local test, shared = t.test, t.shared
	local Config = shared("Config")
	local RoundRocks = shared("RoundRocks")
	local Random, Vector3, Vector2 = t.Random, t.Vector3, t.Vector2

	local function assertEq(a, b, msg)
		if a ~= b then
			error((msg or "mismatch") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
		end
	end

	-- members: list of { uid, machine? , tool? }; station index = list position. Returns a Searching core.
	local function make(members, tier: string?, seed: number?, tutorial: boolean?, roundId: number?)
		local list = {}
		for i, m in members do
			table.insert(list, { UserId = m[1], Tool = m.tool or "Hammer", Machine = m[2], Station = i })
		end
		local core = RoundRocks.new({
			MatchKey = "k",
			RoundId = roundId or 1,
			Tier = tier or "Gravel",
			Seed = seed or 21,
			TargetRng = Random.new((seed or 21) + 1),
			Members = list,
			Tutorial = tutorial,
		})
		core:setPhase("Searching")
		return core
	end

	local clock = 0
	local function tick(dt: number?)
		clock += dt or 1
		return clock
	end

	local function atStation(core, uid)
		return RoundRocks.stationPosition(core.Members[uid].Index)
	end

	local function atRock(core, id)
		local p = core.Pile:localPosition(id) or Vector3.zero
		return Vector3.new(p.X, 3, p.Z)
	end

	-- Picks pickable rocks other than `avoid` until the basket holds n (or nothing is left).
	local function fill(core, uid, n, avoid)
		local got = {}
		for _, id in core.Pile:pickableIds(Config.Carry.ReachLevels) do
			if #got >= n then
				break
			end
			if id ~= avoid then
				local err = core:pickup(uid, core.RoundId, id, atRock(core, id), tick(0.5))
				if err == nil then
					table.insert(got, id)
				end
			end
		end
		return got
	end

	-- Moves rocks from the pile to the member's tray: fills, deposits, repeats.
	local function queueUp(core, uid, n, avoid)
		local total = 0
		while total < n do
			local got = fill(core, uid, math.min(5, n - total), avoid)
			assert(#got > 0, "nothing to pick")
			local res, why = core:deposit(uid, core.RoundId, atStation(core, uid), tick(0.5))
			assert(res, "deposit: " .. tostring(why))
			total += #res.Moved
		end
	end

	local function crush(core, uid)
		return core:crush(uid, core.RoundId, atStation(core, uid), tick(1.2))
	end

	local function otherThan(core, id)
		-- a rock id that is not the target
		return if id ~= core.TargetId then id else (id % core.Total) + 1
	end

	-- A ---------------------------------------------------------------------------------------
	test("v3 A: pickup moves one rock into the basket and grants no rubble", function()
		local core = make({ { 1 } })
		local before = core:counters(1)
		local id = core.Pile:pickableIds(3)[1]
		assertEq(core:pickup(1, 1, id, atRock(core, id), tick()), nil)
		local rock = core.Rocks[id]
		assertEq(rock.State, "Carried")
		assertEq(rock.Carrier, 1)
		assert(core.Pile.Removed[id], "rock left the pile")
		local after = core:counters(1)
		assertEq(after.Carrying, 1)
		assertEq(after.Pile, before.Pile - 1)
		assertEq(after.Unopened, before.Unopened, "unopened only drops when a rock is crushed")
		assertEq(core.Members[1].Rubble, 0)
		assertEq(core.Members[1].Cracked, 0)
	end)

	-- B ---------------------------------------------------------------------------------------
	test("v3 B: basket stops when full; extra requests are rejected and no rock is lost", function()
		local cap = Config.Carry.Capacity -- Find The Pet: 3 eggs to start (owner)
		local core = make({ { 1 } })
		local got = fill(core, 1, cap)
		assertEq(#got, cap)
		local pile = core.Pile.Remaining
		local extra = core.Pile:pickableIds(3)[1]
		assertEq(core:pickup(1, 1, extra, atRock(core, extra), tick()), "BasketFull")
		assertEq(core.Rocks[extra].State, "InPile")
		assertEq(core.Pile.Remaining, pile)
		assertEq(core:counters(1).Carrying, cap)
		assertEq(core.Total - core.Broken, core.Total, "unopened untouched")
		assertEq(Config.Carry.Capacity, 3)
	end)

	test("v3: pickup cadence, range and reach are enforced", function()
		local core = make({ { 1 } })
		local ids = core.Pile:pickableIds(3)
		assertEq(core:pickup(1, 1, ids[1], atRock(core, ids[1]), 10), nil)
		assertEq(core:pickup(1, 1, ids[2], atRock(core, ids[2]), 10.1), "TooFast", "faster than 0.45 s")
		assertEq(core:pickup(1, 1, ids[2], atRock(core, ids[2]), 10.46), nil)
		-- too far
		assertEq(core:pickup(1, 1, ids[3], Vector3.new(400, 3, 0), 12), "TooFar")
		-- right above the rock but far overhead (flying) is too far as well
		local above = atRock(core, ids[3])
		assertEq(core:pickup(1, 1, ids[3], Vector3.new(above.X, above.Y + Config.Carry.PickupHeight + 20, above.Z), 12), "TooFar")
		-- a rock high in the mound (exposed on top but out of reach) cannot be picked
		local high
		for _, col in core.Pile.Columns do
			if #col.Stack > Config.Carry.ReachLevels then
				high = col.Stack[#col.Stack]
				break
			end
		end
		if high then
			assertEq(core:pickup(1, 1, high, atRock(core, high), 14), "Unreachable")
		end
		-- junk input
		assertEq(core:pickup(1, 1, 0 / 0, Vector3.zero, 16), "BadRock")
		assertEq(core:pickup(1, 1, 9999, Vector3.zero, 16), "BadRock")
		assertEq(core:pickup(1, 1, 1.5, Vector3.zero, 16), "BadRock")
	end)

	-- C: deposit ----------------------------------------------------------------------------------
	test("v3 C: deposit-all is partial when the tray is nearly full and keeps the overflow", function()
		local core = make({ { 1 } })
		local cap = Config.Carry.Capacity
		queueUp(core, 1, 8)
		assertEq(#core.Members[1].Queue, 8)
		local got = fill(core, 1, cap)
		assertEq(#got, cap)
		local res = core:deposit(1, 1, atStation(core, 1), tick())
		assert(res)
		assertEq(#res.Moved, 2, "only 2 fit (cap 10)")
		assertEq(res.Left, cap - 2)
		assertEq(res.Queue, 10)
		assertEq(#core.Members[1].Basket, cap - 2, "overflow stays in the basket")
		for _, id in core.Members[1].Basket do
			assertEq(core.Rocks[id].State, "Carried")
		end
		local none, why = core:deposit(1, 1, atStation(core, 1), tick())
		assertEq(none, nil)
		assertEq(why, "QueueFull")
		assertEq(#core.Members[1].Basket, cap - 2)
		local e, why2 = make({ { 1 } }):deposit(1, 1, Vector3.new(RoundRocks.stationPosition(1).X, 0, RoundRocks.stationPosition(1).Z), 1)
		assertEq(e, nil)
		assertEq(why2, "BasketEmpty")
	end)

	-- D: crush only at own station -----------------------------------------------------------------
	test("v3 D: hitting at the pile does nothing; crushing works only at your own station", function()
		local core = make({ { 1 } })
		queueUp(core, 1, 3, core.TargetId)
		local atPile = Vector3.new(2, 3, 2)
		local res, why = core:crush(1, 1, atPile, tick(1.2))
		assertEq(#res, 0)
		assertEq(why, "TooFar")
		assertEq(core.Members[1].Rubble, 0)
		assertEq(core.Members[1].Current, nil, "nothing started")
		local id0 = core.Members[1].Queue[1]
		assertEq(core.Rocks[id0].State, "Queued")
		-- no remote or method exists that damages a pile rock: a pile rock keeps full HP
		for _, id in core.Pile:pickableIds(3) do
			assertEq(core.Rocks[id].Hp, core.MaxHp)
		end
		local ok = crush(core, 1)
		assertEq(ok[1].Kind, "Cracked") -- Gravel: 1 HP
	end)

	-- D2: ordinary resolves once ---------------------------------------------------------------------
	test("v3 D: an ordinary rock resolves once: rubble, unopened and queue advance exactly once", function()
		local core = make({ { 1 } })
		core.TargetId = 0
		queueUp(core, 1, 3)
		local first = core.Members[1].Queue[1]
		local before = core:counters(1)
		local res = crush(core, 1)
		assertEq(#res, 1)
		assertEq(res[1].Kind, "Cracked")
		assertEq(res[1].RockId, first)
		assertEq(core.Rocks[first].State, "ResolvedOrdinary")
		assertEq(core.Members[1].Rubble, 1)
		assertEq(core.Members[1].Cracked, 1)
		assertEq(core:counters(1).Unopened, before.Unopened - 1)
		assertEq(#core.Members[1].Queue, 2, "queue advanced")
		assertEq(core.Members[1].Current, nil)
		local res2 = crush(core, 1)
		assert(res2[1].RockId ~= first, "a resolved rock is never processed again")
		assertEq(core.Members[1].Rubble, 2)
		assertEq(core.Rocks[first].State, "ResolvedOrdinary")
	end)

	test("v3: multi-HP rocks take several hits with growing progress", function()
		local core = make({ { 1 } }, "Quarry") -- HP 2, Hammer damage 1
		core.TargetId = 0
		queueUp(core, 1, 1)
		local r1 = crush(core, 1)
		assertEq(r1[1].Kind, "Hit")
		assertEq(r1[1].Progress, 0.5)
		assertEq(core.Members[1].Rubble, 0)
		local r2 = crush(core, 1)
		assertEq(r2[1].Kind, "Cracked")
		-- cadence: two hits at the same instant are rejected
		queueUp(core, 1, 2)
		local c = tick(2)
		assertEq(#select(1, core:crush(1, 1, atStation(core, 1), c)), 1)
		local _, why = core:crush(1, 1, atStation(core, 1), c + 0.01)
		assertEq(why, "TooFast")
	end)

	-- E: two pickers, foreign stations ---------------------------------------------------------------
	test("v3 E: two players picking the same rock: exactly one gets it", function()
		local core = make({ { 1 }, { 2 } })
		local id = core.Pile:pickableIds(3)[1]
		local e1 = core:pickup(1, 1, id, atRock(core, id), tick())
		local e2 = core:pickup(2, 1, id, atRock(core, id), tick())
		assertEq(e1, nil)
		assertEq(e2, "Gone")
		assertEq(#core.Members[1].Basket, 1)
		assertEq(#core.Members[2].Basket, 0)
		assertEq(core.Rocks[id].Carrier, 1)
	end)

	test("v3 E: nobody can deposit into or crush at another station", function()
		local core = make({ { 1 }, { 2 } })
		core.TargetId = 0
		queueUp(core, 1, 2)
		fill(core, 2, 2)
		-- member 2 stands at member 1's table
		local at1 = atStation(core, 1)
		local dep, why = core:deposit(2, 1, at1, tick())
		assertEq(dep, nil)
		assertEq(why, "TooFar")
		local res, why2 = core:crush(2, 1, at1, tick(1.2))
		assertEq(#res, 0)
		assertEq(why2, "TooFar")
		assertEq(#core.Members[1].Queue, 2, "member 1 queue untouched")
		assertEq(#core.Members[2].Basket, 2)
		-- an outsider is not a member at all
		assertEq(core:pickup(99, 1, 1, Vector3.zero, tick()), "NotMember")
		assertEq(select(2, core:deposit(99, 1, at1, tick())), "NotMember")
		assertEq(select(2, core:crush(99, 1, at1, tick())), "NotMember")
	end)

	-- F: stations ---------------------------------------------------------------------------------------
	test("v3 F: four stations are evenly spaced and equally far from the pile", function()
		local d = Config.Station.Radius
		local ps = {}
		for i = 1, Config.Station.Count do
			ps[i] = RoundRocks.stationPosition(i)
			assert(math.abs(ps[i].Magnitude - d) < 1e-6, "radius " .. i)
		end
		local side = (ps[1] - ps[2]).Magnitude
		for i = 1, 4 do
			local j = i % 4 + 1
			assert(math.abs((ps[i] - ps[j]).Magnitude - side) < 1e-6, "neighbour spacing")
		end
		assert(math.abs((ps[1] - ps[3]).Magnitude - side * math.sqrt(2)) < 1e-6)
	end)

	test("v3 F: four players share one pile, each with an own tray and plate", function()
		local core = make({ { 1 }, { 2 }, { 3 }, { 4 } }, "Quarry", 8)
		core.TargetId = 0
		for uid = 1, 4 do
			local got = fill(core, uid, 3)
			assertEq(#got, 3)
			assert(core:deposit(uid, 1, atStation(core, uid), tick()))
		end
		local seen = {}
		for uid = 1, 4 do
			for _, id in core.Members[uid].Queue do
				assert(not seen[id], "rock in two trays")
				seen[id] = true
			end
		end
		assertEq(core.Pile.Remaining, Config.Tiers.Quarry.Rocks - 12)
		assertEq(core:counters(1).Unopened, Config.Tiers.Quarry.Rocks)
	end)

	-- G: machines ----------------------------------------------------------------------------------------
	test("v3 G: a machine crushes only its own station queue and never touches the pile", function()
		local core = make({ { 1, "AutoCracker" }, { 2 } })
		core.TargetId = 0
		queueUp(core, 1, 4)
		queueUp(core, 2, 3)
		local pileBefore = core.Pile.Remaining
		local q2 = table.clone(core.Members[2].Queue)
		-- manual hits are ignored on an automatic station
		local res, why = crush(core, 1)
		assertEq(#res, 0)
		assertEq(why, "Automatic")
		local t0 = tick(10)
		core:tickMachines(t0)
		local out = {}
		local now = t0
		for _ = 1, 600 do
			now += 1 / 60
			for _, r in core:tickMachines(now) do
				table.insert(out, r)
			end
		end
		assertEq(#out, 4, "all four queued rocks crushed")
		assertEq(core.Members[1].Rubble, 4)
		assertEq(core.Pile.Remaining, pileBefore, "machine never takes rocks from the pile")
		assertEq(#core.Members[2].Queue, 3, "other queue untouched")
		for i, id in q2 do
			assertEq(core.Members[2].Queue[i], id)
			assertEq(core.Rocks[id].State, "Queued")
		end
		assertEq(core.Members[2].Rubble, 0)
		-- the owner can collect more while the machine runs
		local more = fill(core, 1, 2)
		assertEq(#more, 2)
	end)

	test("v3 G: machine rate follows Config.Machines (one rock at a time)", function()
		for _, id in Config.MachineOrder do
			local core = make({ { 1, id } })
			core.TargetId = 0
			queueUp(core, 1, 10)
			local per = RoundRocks.machineSeconds(id)
			assertEq(per, Config.Machines[id].BatchSeconds / Config.Machines[id].RocksPerBatch)
			local now = tick(100)
			core:tickMachines(now)
			local done = 0
			local limit = now + 2.001
			while now < limit do
				now += 1 / 120
				done += #core:tickMachines(now)
			end
			local expect = math.min(10, math.floor(2 / per))
			assert(math.abs(done - expect) <= 1, id .. " crushed " .. done .. " expected about " .. expect)
			-- never more than one rock on the plate
			assert(core.Members[1].Current == nil or core.Rocks[core.Members[1].Current].State == "Processing")
		end
	end)

	test("v3 G: pausing a machine freezes its rock; resuming finishes it", function()
		local core = make({ { 1, "AutoCracker" } })
		core.TargetId = 0
		queueUp(core, 1, 2)
		local now = tick(50)
		core:tickMachines(now)
		now += 0.3
		core:tickMachines(now)
		core:setMachineRunning(1, false, now)
		assertEq(core:machineState(1), "Paused")
		for _ = 1, 100 do
			now += 0.1
			assertEq(#core:tickMachines(now), 0)
		end
		-- paused machine: the hand tool is the active mechanism
		core:setMachineRunning(1, true, now)
		now += 0.1
		assertEq(#core:tickMachines(now), 0, "0.2 s still left")
		now += 0.25
		assertEq(#core:tickMachines(now), 1)
	end)

	test("v3 G: with a paused machine the hand tool works on the same plate (never both)", function()
		local core = make({ { 1, "AutoCracker" } })
		core.TargetId = 0
		queueUp(core, 1, 2)
		core:setMachineRunning(1, false, tick())
		local res = crush(core, 1)
		assertEq(res[1].Kind, "Cracked")
		core:setMachineRunning(1, true, tick())
		assertEq(select(2, crush(core, 1)), "Automatic")
	end)

	-- H: target hidden -----------------------------------------------------------------------------------
	test("v3 H: the target can be picked and queued early; it wins only when crushed", function()
		local core = make({ { 1 }, { 2 } })
		local target = core.TargetId
		local err = core:pickup(1, 1, target, atRock(core, target), tick())
		if err == "Unreachable" then
			-- bury-proof the test: make the target reachable by clearing rocks above it
			core.Pile:remove(target)
			core.Pile:restore(target, Vector2.new(0, 0), 3)
			err = core:pickup(1, 1, target, atRock(core, target), tick())
		end
		assertEq(err, nil, "target picked")
		assertEq(core.Phase, "Searching", "picking up never wins")
		assertEq(core.Winner, nil)
		local filler = fill(core, 1, Config.Carry.Capacity - 1, target)
		assertEq(#filler, Config.Carry.Capacity - 1)
		local dep = core:deposit(1, 1, atStation(core, 1), tick())
		assert(dep)
		assertEq(core.Phase, "Searching", "depositing never wins")
		assertEq(core.Rocks[target].State, "Queued")
		-- nothing replicated mentions the target
		for _, v in core:stationViews(tick()) do
			for k in v do
				assert(not string.find(string.lower(k), "target") and not string.find(string.lower(k), "geode"), "leaky field " .. k)
			end
		end
		for k in core:counters(1) do
			assert(not string.find(string.lower(k), "target"), "leaky counter")
		end
		-- crush in order: the target is first in the tray (picked first)
		assertEq(core.Members[1].Queue[1], target)
		local res = crush(core, 1)
		assertEq(res[1].Kind, "Found")
		assertEq(core.Winner, 1)
		assertEq(core.Phase, "RewardPending")
		assertEq(core.Rocks[target].State, "ResolvedGeode")
		assertEq(core.Members[1].Rubble, 0, "the geode pays no rubble")
		-- exactly one geode: nothing else can resolve now
		assertEq(select(2, crush(core, 1)), "NotSearching")
		assertEq(select(2, core:crush(2, 1, atStation(core, 2), tick())), "NotSearching")
	end)

	test("v3 H: the target is uniform over the records and fixed for the round", function()
		local n = Config.Tiers.Gravel.Rocks
		local hits = {}
		for s = 1, 4000 do
			local core = make({ { 1 } }, "Gravel", s * 7)
			local b = math.ceil(core.TargetId / n * 4)
			hits[b] = (hits[b] or 0) + 1
		end
		for b = 1, 4 do
			assert(hits[b] > 850 and hits[b] < 1150, "bucket " .. b .. " = " .. tostring(hits[b]))
		end
		local core = make({ { 1 } })
		local t0 = core.TargetId
		fill(core, 1, 5)
		core:resetMember(1)
		assertEq(core.TargetId, t0, "never rerolled")
	end)

	-- I: leaving ----------------------------------------------------------------------------------------
	test("v3 I: disconnect returns carried, queued and processing rocks; the target stays winnable", function()
		local core = make({ { 1 }, { 2 } }, "Quarry", 31) -- HP 2: the plate rock survives one hit
		local target = core.TargetId
		core.Pile:remove(target)
		core.Rocks[target].State = "Carried"
		core.Rocks[target].Carrier = 1
		table.insert(core.Members[1].Basket, target)
		queueUp(core, 1, 5, target)
		assertEq(core.Members[1].Queue[1], target)
		local res = crush(core, 1)
		assertEq(res[1].Kind, "Hit", "target is on the plate, damaged")
		assertEq(core.Members[1].Current, target)
		assert(#fill(core, 1, 3, target) == 3, "plus a full-ish basket")
		local held = #core.Members[1].Queue + 1 + #core.Members[1].Basket
		local pileBefore = core.Pile.Remaining
		core:setSpace(1, 50)
		core:removeMember(1)
		assertEq(core.Pile.Remaining, pileBefore + held, "everything unresolved is back in the pile")
		assertEq(core.Members[1].Active, false)
		assertEq(core.Members[1].Current, nil)
		assertEq(#core.Members[1].Queue + #core.Members[1].Basket, 0)
		assertEq(core.Members[1].Reserved, false)
		assertEq(core.Rocks[target].State, "InPile")
		assertEq(core.Rocks[target].Hp, core.MaxHp, "progress is discarded: returned at full HP")
		assert(core.Pile:isPickable(target, 3), "returned target is reachable")
		-- Return events carry the column and no one else's data
		local returns = 0
		for _, e in core:drainEvents() do
			if e.Kind == "Return" then
				returns += 1
				assert(e.Col ~= nil)
			end
		end
		assertEq(returns, held)
		-- the remaining player can still find it: pick everything, crush everything
		local won
		local guard = 0
		while core.Phase == "Searching" and guard < 3000 do
			guard += 1
			if #core.Members[2].Queue == 0 and core.Members[2].Current == nil then
				local got = fill(core, 2, 5)
				assert(#got > 0, "nothing left to pick but round not over")
				local d = core:deposit(2, 1, atStation(core, 2), tick())
				assert(d)
			end
			local r = crush(core, 2)
			if r[1] and r[1].Kind == "Found" then
				won = r[1].RockId
			end
		end
		assertEq(won, target)
		assertEq(core.Winner, 2)
	end)

	test("v3 I: leaving after the round is decided changes nothing; reset drops only the basket", function()
		local core = make({ { 1 } }, "Quarry", 4)
		core.TargetId = 0
		queueUp(core, 1, 4)
		local got = fill(core, 1, 3)
		assertEq(core:dropCarried(1), 3)
		assertEq(#core.Members[1].Basket, 0)
		assertEq(#core.Members[1].Queue, 4, "tray stays on the table")
		for _, id in got do
			assertEq(core.Rocks[id].State, "InPile")
		end
		core:setPhase("RewardPending")
		core:removeMember(1)
		assertEq(#core.Members[1].Queue, 4, "no returns once the round is over")
	end)

	-- J: storage ------------------------------------------------------------------------------------------
	test("v3 J: a full rubble bag pauses every rock alike and keeps queue and progress", function()
		local core = make({ { 1 } }, "Quarry", 14)
		local target = core.TargetId
		core:setSpace(1, 0)
		queueUp(core, 1, 5, target)
		-- target first in line vs ordinary first in line: same answer, nothing changes
		local reasons = {}
		for _ = 1, 2 do
			local res, why = crush(core, 1)
			assertEq(#res, 0)
			table.insert(reasons, why)
		end
		assertEq(reasons[1], "StorageFull")
		assertEq(reasons[2], "StorageFull")
		assertEq(core.Members[1].Current, nil)
		assertEq(#core.Members[1].Queue, 5, "records preserved")
		local core2 = make({ { 1 } }, "Quarry", 14)
		core2:setSpace(1, 0)
		core2.Pile:remove(core2.TargetId)
		core2.Rocks[core2.TargetId].State = "Carried"
		table.insert(core2.Members[1].Basket, core2.TargetId)
		queueUp(core2, 1, 3, core2.TargetId)
		assertEq(select(2, crush(core2, 1)), "StorageFull", "even with the target first in the tray")
		assertEq(core2.Phase, "Searching")
	end)

	test("v3 J: one slot is reserved before a rock starts; ordinary consumes it, the geode releases it", function()
		local core = make({ { 1 } }, "Quarry", 6)
		core.TargetId = 0
		core:setSpace(1, 1)
		queueUp(core, 1, 3)
		local r1 = crush(core, 1)
		assertEq(r1[1].Kind, "Hit")
		assertEq(core.Members[1].Reserved, true)
		-- the plate rock finishes against its reservation even though storage looks exhausted
		local r2 = crush(core, 1)
		assertEq(r2[1].Kind, "Cracked")
		assertEq(core.Members[1].Space, 0, "ordinary consumed the slot")
		assertEq(core.Members[1].Reserved, false)
		assertEq(select(2, crush(core, 1)), "StorageFull")
		core:setSpace(1, 3) -- sold some rubble
		assertEq(crush(core, 1)[1].Kind, "Hit", "resumes after the sale")
		-- geode path
		local c2 = make({ { 1 } }, "Gravel", 9)
		c2:setSpace(1, 1)
		local id = c2.TargetId
		c2.Pile:remove(id)
		c2.Rocks[id].State = "Carried"
		table.insert(c2.Members[1].Basket, id)
		assert(c2:deposit(1, 1, atStation(c2, 1), tick()))
		local res = crush(c2, 1)
		assertEq(res[1].Kind, "Found")
		assertEq(c2.Members[1].Reserved, false, "geode released the reservation")
		assertEq(c2.Members[1].Space, 1, "geode used no storage")
	end)

	test("v3 J: a machine pauses on a full bag, keeps its queue and resumes after a sale", function()
		local core = make({ { 1, "AutoCracker" } })
		core.TargetId = 0
		core:setSpace(1, 2)
		queueUp(core, 1, 5)
		local now = tick(20)
		local done = 0
		for _ = 1, 300 do
			now += 1 / 60
			done += #core:tickMachines(now)
		end
		assertEq(done, 2, "two ordinary results fit")
		assertEq(core:machineState(1), "Full")
		assertEq(#core.Members[1].Queue, 3, "queue preserved")
		assertEq(core.Members[1].Current, nil)
		core:setSpace(1, 10)
		for _ = 1, 300 do
			now += 1 / 60
			done += #core:tickMachines(now)
		end
		assertEq(done, 5)
	end)

	-- K: round end and rematch ------------------------------------------------------------------------------
	test("v3 K: the geode ends the round: stations stop, queued machine work is invalidated, one winner", function()
		local core = make({ { 1, "AutoCracker" }, { 2, "IndustrialCrusher" } })
		local target = core.TargetId
		-- member 1's machine gets the target, member 2's crusher gets ordinary rocks
		core.Pile:remove(target)
		core.Rocks[target].State = "Carried"
		table.insert(core.Members[1].Basket, target)
		queueUp(core, 1, 4, target)
		queueUp(core, 2, 6, target)
		local now = tick(30)
		local found = 0
		local rubble2 = 0
		for _ = 1, 400 do
			now += 1 / 60
			for _, r in core:tickMachines(now) do
				if r.Kind == "Found" then
					found += 1
				end
			end
		end
		assertEq(found, 1, "exactly one geode")
		assertEq(core.Winner, 1)
		assertEq(core.Phase, "RewardPending")
		local r2 = core.Members[2].Rubble
		local r1 = core.Members[1].Rubble
		assertEq(r1, 0, "target was first in the tray: nothing else crushed by the winner")
		-- everything halted
		for _ = 1, 100 do
			now += 0.1
			assertEq(#core:tickMachines(now), 0)
		end
		assertEq(core.Members[2].Rubble, r2, "no more ordinary results after the end")
		assertEq(core:pickup(2, 1, 1, Vector3.zero, tick()), "NotSearching")
		assertEq(select(2, core:deposit(2, 1, atStation(core, 2), tick())), "NotSearching")
		assertEq(select(2, core:crush(2, 1, atStation(core, 2), tick())), "NotSearching")
		for _, m in core.Members do
			assertEq(m.Complete, nil, "machine timers invalidated")
		end
		-- others keep ordinary rubble they already earned (member 2 crushed some before the find)
		assert(r2 >= 0)
	end)

	test("v3 K: two machines finishing in the same instant still give one winner", function()
		for seed = 1, 20 do
			local core = make({ { 1, "AutoCracker" }, { 2, "AutoCracker" } }, "Gravel", seed * 13)
			local target = core.TargetId
			core.Pile:remove(target)
			core.Rocks[target].State = "Carried"
			table.insert(core.Members[1].Basket, target)
			queueUp(core, 1, 1, target)
			queueUp(core, 2, 3, target)
			local now = tick(5)
			core:tickMachines(now)
			local results = core:tickMachines(now + 5) -- one late tick: both stations are due
			local founds = 0
			for _, r in results do
				if r.Kind == "Found" then
					founds += 1
				end
			end
			assertEq(founds, 1)
			assertEq(core.Winner, 1)
		end
	end)

	test("v3 K: rematch starts fresh; ids and requests of the old round are rejected", function()
		local old = make({ { 1 } }, "Gravel", 5, false, 1)
		local id = old.Pile:pickableIds(3)[1]
		assertEq(old:pickup(1, 1, id, atRock(old, id), tick()), nil)
		local new = make({ { 1 } }, "Gravel", 6, false, 2)
		assertEq(new:pickup(1, 1, id, atRock(new, id), tick()), "StaleRound", "old round id")
		assertEq(select(2, new:deposit(1, 1, atStation(new, 1), tick())), "StaleRound")
		assertEq(select(2, new:crush(1, 1, atStation(new, 1), tick())), "StaleRound")
		assertEq(#new.Members[1].Basket, 0)
		assertEq(new.Pile.Remaining, new.Total)
		assertEq(new:counters(1).Unopened, new.Total)
		for _, r in new.Rocks do
			assertEq(r.State, "InPile")
		end
		assertEq(new:pickup(1, "2", id, atRock(new, id), tick()), "StaleRound", "round id must match exactly")
		assertEq(new:pickup(1, 2, id, atRock(new, id), tick()), nil)
	end)

	-- tutorial -----------------------------------------------------------------------------------------------
	test("v3: practice round has 12 rocks and the geode is among rocks 2-6 CRUSHED (picking does not count)", function()
		for s = 1, 100 do
			local core = make({ { 1 } }, "Gravel", s, true)
			assertEq(core.Total, Config.Tutorial.Rocks)
			assertEq(core.TargetId, nil)
			-- picking all rocks and depositing cannot end the round
			local crushed = 0
			local found
			local guard = 0
			while core.Phase == "Searching" and guard < 200 do
				guard += 1
				if #core.Members[1].Queue == 0 and core.Members[1].Current == nil then
					local got = fill(core, 1, 5)
					assert(#got > 0)
					assert(core:deposit(1, 1, atStation(core, 1), tick()))
					assertEq(core.Phase, "Searching")
				end
				local r = crush(core, 1)
				if r[1] then
					crushed += 1
					if r[1].Kind == "Found" then
						found = crushed
					end
				end
			end
			assert(found and found >= Config.Tutorial.TargetFrom and found <= Config.Tutorial.TargetWithin, "found at crush " .. tostring(found))
			assert(core.Members[1].Rubble >= 1, "practice pays rubble first")
		end
	end)

	test("v3: practice rounds never run machines", function()
		local core = make({ { 1, "IndustrialCrusher" } }, "Gravel", 3, true)
		assertEq(core.Members[1].Machine, nil)
		core:setMachine(1, "AutoCracker")
		assertEq(core.Members[1].Machine, nil)
	end)

	test("v3: the event stream has no target data and orders Pick, Deposit, Start, Hit, Done", function()
		local core = make({ { 1 } }, "Quarry", 12)
		core.TargetId = 0
		queueUp(core, 1, 1)
		crush(core, 1)
		crush(core, 1)
		local kinds = {}
		for _, e in core:drainEvents() do
			table.insert(kinds, e.Kind)
			for k in e do
				assert(not string.find(string.lower(k), "target") and not string.find(string.lower(k), "geode"), "leaky event field " .. k)
			end
		end
		assertEq(table.concat(kinds, ","), "Pick,Deposit,Start,Hit,Done")
		assertEq(#core:drainEvents(), 0, "drained")
	end)

	test("v3: a character reset after the round ended drops nothing and a bad phase gates every action", function()
		local core = make({ { 1 } })
		fill(core, 1, 2)
		core:setPhase("Countdown")
		assertEq(core:dropCarried(1), 0)
		local id = core.Pile:pickableIds(3)[1]
		assertEq(core:pickup(1, 1, id, atRock(core, id), tick()), "NotSearching")
		core:setPhase("Searching")
		assertEq(core:dropCarried(1), 2)
	end)

	test("v3: counters keep unopened, pile, carrying and queue separate", function()
		local core = make({ { 1 } })
		core.TargetId = 0
		fill(core, 1, 3)
		local c = core:counters(1)
		assertEq(c.Unopened, Config.Tiers.Gravel.Rocks)
		assertEq(c.Pile, Config.Tiers.Gravel.Rocks - 3)
		assertEq(c.Carrying, 3)
		core:deposit(1, 1, atStation(core, 1), tick())
		c = core:counters(1)
		assertEq(c.Carrying, 0)
		assertEq(c.Queue, 3)
		assertEq(c.Unopened, Config.Tiers.Gravel.Rocks)
		crush(core, 1)
		c = core:counters(1)
		assertEq(c.Unopened, Config.Tiers.Gravel.Rocks - 1)
		assertEq(c.Pile, Config.Tiers.Gravel.Rocks - 3)
		assertEq(c.Queue, 2)
	end)

	-- Master Prompt 4 section 21: conservation. At every step each record is in exactly one place and the
	-- counters stay distinct: carry (baskets), queue (trays + plates), unresolved (Unopened), earned rubble.
	local function checkConserved(core, label)
		local where: { [number]: string } = {}
		local function put(id, place)
			if where[id] then
				error(label .. ": rock " .. id .. " is in two places: " .. where[id] .. " and " .. place)
			end
			where[id] = place
		end
		for _, col in core.Pile.Columns do
			for _, id in col.Stack do
				put(id, "pile")
			end
		end
		local carried, queued, processing = 0, 0, 0
		local cracked, rubble = 0, 0
		for _, m in core.Members do
			for _, id in m.Basket do
				put(id, "basket")
				carried += 1
			end
			for _, id in m.Queue do
				put(id, "queue")
				queued += 1
			end
			if m.Current then
				put(m.Current, "plate")
				processing += 1
			end
			assertEq(m.Reserved, m.Current ~= nil, label .. ": a slot is reserved exactly while a rock is on the plate")
			cracked += m.Cracked
			rubble += m.Rubble
		end
		local ordinary, geode = 0, 0
		for id, rock in core.Rocks do
			local st = rock.State
			if st == "ResolvedOrdinary" then
				ordinary += 1
				put(id, "resolved")
			elseif st == "ResolvedGeode" then
				geode += 1
				put(id, "resolved")
			end
			assertEq(where[id] ~= nil, true, label .. ": rock " .. id .. " is nowhere")
			local expect = ({ pile = "InPile", basket = "Carried", queue = "Queued", plate = "Processing", resolved = st })[where[id]]
			assertEq(st, expect, label .. ": record state matches its location")
		end
		assertEq(core.Pile.Remaining, core.Total - carried - queued - processing - core.Broken, label .. ": pile count")
		assertEq(ordinary + geode, core.Broken, label .. ": resolved records = Broken")
		assertEq(cracked, core.Broken, label .. ": members' cracked counts add up to Broken")
		assertEq(rubble, ordinary, label .. ": earned rubble = resolved ordinary records")
		local c = core:counters(nil)
		assertEq(c.Unopened, core.Total - core.Broken, label .. ": unopened counts every unresolved record")
		assertEq(c.Unopened, core.Pile.Remaining + carried + queued + processing, label .. ": unresolved = pile + baskets + queues + plates")
	end

	test("v3 G: one mechanism per station: hand hits, pauses, resumes and machine swaps never resolve a rock twice", function()
		-- Interleaves hand crushes, ToggleMachine, ticks and a machine swap on ONE station; after every step
		-- every record is in exactly one place and resolved == Broken == Cracked == rubble (a double
		-- resolution would break it), and a running machine always refuses hand hits.
		local resolved = 0
		for seed = 1, 5 do
			local core = make({ { 1, "AutoCracker" } }, "Gravel", seed * 7)
			core.TargetId = 0
			core:setSpace(1, 1000)
			local rng = Random.new(seed)
			local m = core.Members[1]
			for step = 1, 300 do
				if core.Phase ~= "Searching" then
					break
				end
				local r = rng:NextInteger(1, 100)
				if r <= 25 then
					fill(core, 1, 5, nil)
					core:deposit(1, core.RoundId, atStation(core, 1), tick(0.3))
				elseif r <= 50 then
					local res, why = core:crush(1, core.RoundId, atStation(core, 1), tick(0.5))
					if m.Machine and m.Running then
						assertEq(why, "Automatic", "a running machine refuses hand hits")
						assertEq(#res, 0)
					end
				elseif r <= 70 then
					core:tickMachines(tick(rng:NextNumber(0.1, 1.5)))
				elseif r <= 90 then
					core:setMachineRunning(1, not m.Running, tick(0.05))
				else
					core:setMachine(1, if m.Machine then nil else "AutoCracker")
				end
				checkConserved(core, "mechanism seed " .. seed .. " step " .. step)
			end
			resolved += core.Broken
		end
		assert(resolved > 20, "the scenario crushed something: " .. resolved)
	end)

	test("v3 conservation: random pickups, deposits, crushes, machines, resets and a leaver never lose or duplicate a rock", function()
		local crushed, picked = 0, 0
		for seed = 1, 6 do
			local core = make({ { 1 }, { 2, "AutoCracker" }, { 3, "HydraulicPress" } }, "Gravel", seed * 13)
			for uid = 1, 3 do
				core:setSpace(uid, 1000)
			end
			local rng = Random.new(seed)
			local removed = false
			for step = 1, 400 do
				if core.Phase ~= "Searching" then
					break
				end
				local uid = rng:NextInteger(1, 3)
				local r = rng:NextInteger(1, 100)
				if r <= 40 then
					local ids = core.Pile:pickableIds(Config.Carry.ReachLevels)
					if #ids > 0 then
						local id = ids[rng:NextInteger(1, #ids)]
						if core:pickup(uid, core.RoundId, id, atRock(core, id), tick(0.5)) == nil then
							picked += 1
						end
					end
				elseif r <= 62 then
					core:deposit(uid, core.RoundId, atStation(core, uid), tick(0.3))
				elseif r <= 82 then
					core:crush(uid, core.RoundId, atStation(core, uid), tick(1.2))
				elseif r <= 92 then
					core:tickMachines(tick(rng:NextNumber(1, 6)))
				elseif r <= 95 then
					core:dropCarried(uid)
				elseif r <= 97 and not removed and step > 100 then
					removed = true
					core:removeMember(uid)
				else
					-- requests with a wrong round id or from outside never change anything
					core:pickup(uid, core.RoundId + 1, 1, atRock(core, 1), tick(0.5))
					core:deposit(uid, core.RoundId, Vector3.new(0, 3, 0), tick(0.3))
				end
				checkConserved(core, "seed " .. seed .. " step " .. step)
				crushed = math.max(crushed, core.Broken)
			end
		end
		assertEq(picked > 100, true, "the random run really picked rocks up")
		assertEq(crushed > 3, true, "the random run really crushed rocks")
	end)
end
