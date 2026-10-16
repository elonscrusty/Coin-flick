-- M5 rules audit (docs/m5/RULES_AUDIT.md): adversarial checks of the round rules in RoundRocks and HuntLedger.
-- Brief V6 sections 21, 25, 46, 48, 56 and V7 section 0: every rock resolves once, one target and one winner,
-- leavers never strand the target, manual tool and machine never both finish a rock, storage is reserved
-- before a rock starts, rematches are fresh, and the results figures agree with what really happened.
--
-- The three cases that first failed (F1-F3) were fixed in the final acceptance pass; see docs/m5/RULES_AUDIT.md.
return function(t)
	local test, shared = t.test, t.shared
	local Config = shared("Config")
	local RoundRocks = shared("RoundRocks")
	local Ledger = shared("HuntLedger")
	local Random, Vector3 = t.Random, t.Vector3
	
	local function assertEq(a, b, msg)
		if a ~= b then
			error((msg or "mismatch") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
		end
	end

	local MACHINES = {}
	for id in Config.Machines do
		table.insert(MACHINES, id)
	end
	table.sort(MACHINES)

	-- members: list of { uid, machine?, tool = ? }; station index = list position. Returns a Searching core.
	local function make(members, tier: string?, seed: number?, roundId: number?)
		local list = {}
		for i, m in members do
			table.insert(list, { UserId = m[1], Tool = m.tool or "Hammer", Machine = m[2], Station = i })
		end
		local core = RoundRocks.new({
			MatchKey = "audit",
			RoundId = roundId or 1,
			Tier = tier or "Gravel",
			Seed = seed or 7,
			TargetRng = Random.new((seed or 7) * 3 + 1),
			Members = list,
		})
		core:setPhase("Searching")
		return core
	end

	local clock = 1000
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

	local function fill(core, uid, n, avoid)
		local got = {}
		for _, id in core.Pile:pickableIds(Config.Carry.ReachLevels) do
			if #got >= n then
				break
			end
			if id ~= avoid then
				if core:pickup(uid, core.RoundId, id, atRock(core, id), tick(0.5)) == nil then
					table.insert(got, id)
				end
			end
		end
		return got
	end

	local function deposit(core, uid)
		return core:deposit(uid, core.RoundId, atStation(core, uid), tick(0.5))
	end

	local function queueUp(core, uid, n, avoid)
		local total = 0
		while total < n do
			local got = fill(core, uid, math.min(Config.Carry.Capacity, n - total), avoid)
			assert(#got > 0, "nothing to pick")
			local res, why = deposit(core, uid)
			assert(res, "deposit: " .. tostring(why))
			total += #res.Moved
		end
	end

	-- Puts a specific rock (usually the target) in a member's basket the way the existing suite does: the
	-- target is rarely on the reachable edge of the seeded pile, and we want it in hand deterministically.
	local function grab(core, uid, id)
		if core.Pile:isPickable(id, Config.Carry.ReachLevels) then
			assertEq(core:pickup(uid, core.RoundId, id, atRock(core, id), tick(0.5)), nil, "pickup target")
			return
		end
		core.Pile:remove(id)
		local rock = core.Rocks[id]
		rock.State, rock.Carrier, rock.Station = "Carried", uid, nil
		table.insert(core.Members[uid].Basket, id)
	end

	local function crush(core, uid)
		return core:crush(uid, core.RoundId, atStation(core, uid), tick(1.2))
	end

	local function countKind(results, kind)
		local n = 0
		for _, r in results do
			if r.Kind == kind then
				n += 1
			end
		end
		return n
	end

	-- Full conservation / single-location invariant (brief V6 section 21). `seen` (optional) remembers resolved
	-- rocks across calls so a resolved record can never change state again.
	local function check(core, seen)
		local where: { [number]: string } = {}
		local function place(id, label)
			assert(where[id] == nil, ("rock %d in two places: %s and %s"):format(id, tostring(where[id]), label))
			where[id] = label
		end
		for uid, m in core.Members do
			for _, id in m.Basket do
				place(id, "basket" .. uid)
				local r = core.Rocks[id]
				assertEq(r.State, "Carried", "basket rock state")
				assertEq(r.Carrier, uid, "basket rock carrier")
				assert(core.Pile.Removed[id], "basket rock still in pile")
			end
			for _, id in m.Queue do
				place(id, "queue" .. uid)
				local r = core.Rocks[id]
				assertEq(r.State, "Queued", "queued rock state")
				assertEq(r.Station, uid, "queued rock station")
			end
			if m.Current then
				place(m.Current, "plate" .. uid)
				assertEq(core.Rocks[m.Current].State, "Processing", "plate rock state")
			end
			if not m.Active and core.Phase == "Searching" then
				assert(#m.Basket == 0 and #m.Queue == 0 and m.Current == nil, "a leaver still holds rocks mid-round")
			end
		end
		local inPile, ordinary, geode, rubble, cracked = 0, 0, 0, 0, 0
		for id, r in core.Rocks do
			if r.State == "InPile" then
				inPile += 1
				assert(not core.Pile.Removed[id] and core.Pile:levelOf(id) ~= nil, "InPile rock missing from the pile")
				assert(where[id] == nil, "InPile rock also held")
				assertEq(r.Hp, core.MaxHp, "pile rocks are always at full HP")
			elseif r.State == "ResolvedOrdinary" or r.State == "ResolvedGeode" then
				assert(where[id] == nil, "resolved rock still held")
				assert(core.Pile.Removed[id], "resolved rock back in the pile")
				if r.State == "ResolvedGeode" then
					geode += 1
					assertEq(id, core.TargetId, "geode is the target")
				else
					ordinary += 1
				end
			else
				assert(where[id] ~= nil, ("rock %d is %s but nobody holds it"):format(id, r.State))
			end
			if seen then
				if seen[id] then
					assertEq(r.State, seen[id], "a resolved rock changed state")
				elseif r.State == "ResolvedOrdinary" or r.State == "ResolvedGeode" then
					seen[id] = r.State
				end
			end
		end
		for _, m in core.Members do
			rubble += m.Rubble
			cracked += m.Cracked
		end
		assertEq(inPile, core.Pile.Remaining, "pile count")
		assertEq(ordinary + geode, core.Broken, "broken = resolved")
		assertEq(cracked, core.Broken, "per-member cracked sums to broken")
		assertEq(rubble, ordinary, "one rubble per ordinary rock, none for the geode")
		assert(geode <= 1, "two geodes")
		assertEq(geode == 1, core.Winner ~= nil, "winner iff geode")
		local c = core:counters(nil)
		assertEq(c.Unopened, core.Total - core.Broken, "unopened counter")
	end

	-- Drives one active member until the round is won (hand tool, unlimited storage). Returns the winner.
	local function playOut(core, uid, limit: number?)
		core:setMachine(uid, nil)
		core:setSpace(uid, math.huge)
		local guard = 0
		while core.Phase == "Searching" and guard < (limit or 5000) do
			guard += 1
			local m = core.Members[uid]
			if #m.Queue == 0 and m.Current == nil then
				if #m.Basket == 0 then
					local got = fill(core, uid, Config.Carry.Capacity)
					assert(#got > 0, "round still on but nothing left to pick (target stranded?)")
				end
				local d, why = deposit(core, uid)
				assert(d, "deposit: " .. tostring(why))
			end
			crush(core, uid)
		end
		return core.Winner
	end

	-- 1. Every rock resolves once ------------------------------------------------------------------------------
	test("audit 1: random fuzz (machines, swaps, pauses, sales, resets, leavers, junk requests) never loses or doubles a rock", function()
		local junkIds = { 0, -1, 1.5, 0 / 0, math.huge, "3", nil :: any, 10 ^ 9 }
		for seed = 1, 30 do
			local rng = Random.new(seed * 97)
			local core = make({ { 1, "AutoCracker" }, { 2 }, { 3, "HydraulicPress" }, { 4, tool = "Jackhammer" } }, "Quarry", seed)
			local seen = {}
			local left = 0
			for _ = 1, 900 do
				if core.Phase ~= "Searching" then
					break
				end
				local uid = rng:NextInteger(1, 4)
				local op = rng:NextInteger(1, 16)
				local m = core.Members[uid]
				if op <= 4 then
					local ids = core.Pile:pickableIds(Config.Carry.ReachLevels)
					if #ids > 0 then
						local id = ids[rng:NextInteger(1, #ids)]
						core:pickup(uid, core.RoundId, id, atRock(core, id), tick(0.5))
					end
				elseif op == 5 then
					local id = junkIds[rng:NextInteger(1, #junkIds)]
					core:pickup(uid, core.RoundId, id, Vector3.zero, tick(0.5))
				elseif op <= 7 then
					deposit(core, uid)
				elseif op == 8 then -- deposit / crush at someone else's table
					local other = (uid % 4) + 1
					core:deposit(uid, core.RoundId, atStation(core, other), tick(0.3))
					core:crush(uid, core.RoundId, atStation(core, other), tick(0.3))
				elseif op <= 11 then
					crush(core, uid)
				elseif op == 12 then
					core:tickMachines(tick(rng:NextNumber(0, 3)))
				elseif op == 13 then
					local pick = rng:NextInteger(0, #MACHINES)
					core:setMachine(uid, if pick == 0 then nil else MACHINES[pick])
					core:setMachineRunning(uid, rng:NextInteger(0, 1) == 1, clock)
				elseif op == 14 then
					core:setSpace(uid, if rng:NextInteger(0, 3) == 0 then 0 else rng:NextInteger(1, 40))
				elseif op == 15 then
					core:dropCarried(uid)
				elseif op == 16 then
					-- stale-round requests change nothing
					assertEq(core:pickup(uid, core.RoundId + 1, 1, Vector3.zero, tick(0.1)), "StaleRound")
					if left < 2 and uid ~= 2 and m.Active and rng:NextInteger(1, 6) == 1 then
						core:removeMember(uid)
						left += 1
					end
				end
				check(core, seen)
			end
			-- member 2 never leaves: the round must stay winnable whatever happened above
			if core.Phase == "Searching" then
				for uid, m in core.Members do
					if uid ~= 2 and m.Active then
						core:removeMember(uid)
					end
				end
				check(core, seen)
				assertEq(playOut(core, 2), 2, "the remaining player finds the geode")
			end
			check(core, seen)
			assertEq(core.Rocks[core.TargetId].State, "ResolvedGeode")
		end
	end)

	test("audit 1: after the find, every request and machine step is inert (no rubble, no second resolution)", function()
		local core = make({ { 1, "AutoCracker" }, { 2 } }, "Gravel", 11)
		local target = core.TargetId
		grab(core, 2, target)
		deposit(core, 2)
		queueUp(core, 1, 6, target)
		queueUp(core, 2, 4, target)
		local res = crush(core, 2)
		assertEq(countKind(res, "Found"), 1)
		local snap = {}
		for id, r in core.Rocks do
			snap[id] = r.State
		end
		local rubble1, rubble2, broken = core.Members[1].Rubble, core.Members[2].Rubble, core.Broken
		for _ = 1, 20 do
			assertEq(#core:tickMachines(tick(5)), 0)
			assertEq(select(2, crush(core, 2)), "NotSearching")
			assertEq(select(2, crush(core, 1)), "NotSearching")
			assertEq(select(2, deposit(core, 1)), "NotSearching")
			core:setMachineRunning(1, false, clock)
			core:setMachineRunning(1, true, clock)
		end
		for id, r in core.Rocks do
			assertEq(r.State, snap[id], "rock state frozen after the find")
		end
		assertEq(core.Members[1].Rubble, rubble1)
		assertEq(core.Members[2].Rubble, rubble2)
		assertEq(core.Broken, broken)
		assertEq(core.Winner, 2)
	end)

	-- 2. One target, one winner --------------------------------------------------------------------------------
	test("audit 2: two hand tables finishing on the same timestamp give one winner; the loser keeps its rock", function()
		local core = make({ { 1 }, { 2 } }, "Gravel", 23)
		local target = core.TargetId
		grab(core, 1, target)
		deposit(core, 1)
		queueUp(core, 2, 1, target)
		local now = tick(2)
		-- both requests arrive with the same clock value; the server applies them in arrival order
		local r1 = core:crush(1, core.RoundId, atStation(core, 1), now)
		local r2, why2 = core:crush(2, core.RoundId, atStation(core, 2), now)
		assertEq(countKind(r1, "Found"), 1)
		assertEq(#r2, 0)
		assertEq(why2, "NotSearching")
		assertEq(core.Winner, 1)
		assertEq(core.Rocks[core.Members[2].Queue[1] or core.Members[2].Current].State ~= "ResolvedOrdinary", true)
		check(core)
	end)

	test("audit 2: hand win and machine completion at the same instant give exactly one winner, in either order", function()
		for _, handFirst in { true, false } do
			local core = make({ { 1 }, { 2, "AutoCracker" } }, "Gravel", 29)
			local target = core.TargetId
			grab(core, 1, target)
			deposit(core, 1)
			queueUp(core, 2, 3, target)
			local now = tick(1)
			core:tickMachines(now) -- arms station 2
			local due = now + RoundRocks.machineSeconds("AutoCracker")
			local founds = 0
			if handFirst then
				founds += countKind(core:crush(1, core.RoundId, atStation(core, 1), due), "Found")
				founds += countKind(core:tickMachines(due), "Found")
			else
				founds += countKind(core:tickMachines(due), "Found")
				founds += countKind(core:crush(1, core.RoundId, atStation(core, 1), due), "Found")
			end
			assertEq(founds, 1)
			assertEq(core.Winner, 1)
			check(core)
		end
	end)

	test("audit 2: four machines due together on a long frame: one Found, completion order, no work after it", function()
		for seed = 1, 15 do
			local core = make({ { 1, "AutoCracker" }, { 2, "HydraulicPress" }, { 3, "IndustrialCrusher" }, { 4, "AutoCracker" } }, "Quarry", seed)
			local target = core.TargetId
			local holder = (seed % 4) + 1
			grab(core, holder, target)
			deposit(core, holder)
			for uid = 1, 4 do
				queueUp(core, uid, 3, target)
			end
			core:tickMachines(tick(0.01))
			local results = core:tickMachines(tick(30))
			assertEq(countKind(results, "Found"), 1)
			assertEq(results[#results].Kind, "Found", "nothing is processed after the find")
			assertEq(core.Winner, holder)
			check(core)
		end
	end)

	test("audit 2: a machine rock due BEFORE a winning hand hit still pays (crush does not tick machines first)", function()
		local core = make({ { 1 }, { 2, "AutoCracker" } }, "Gravel", 31)
		local target = core.TargetId
		grab(core, 1, target)
		deposit(core, 1)
		queueUp(core, 2, 2, target)
		local now = tick(1)
		core:tickMachines(now)
		local due = now + RoundRocks.machineSeconds("AutoCracker")
		-- station 2's rock is finished at `due`; the winning hit lands 10 ms later, before the next Heartbeat
		core:crush(1, core.RoundId, atStation(core, 1), due + 0.01)
		core:tickMachines(due + 0.02)
		assertEq(core.Members[2].Rubble, 1, "rock completed before the win was never paid")
	end)

	-- 3. Leaving while carrying or queued ----------------------------------------------------------------------
	test("audit 3: the target holder leaves with it in the basket; the others can still win", function()
		local core = make({ { 1 }, { 2 }, { 3 } }, "Gravel", 41)
		local target = core.TargetId
		grab(core, 1, target)
		fill(core, 1, Config.Carry.Capacity - 1, target)
		core:removeMember(1)
		assertEq(core.Rocks[target].State, "InPile")
		check(core)
		local winner = playOut(core, 3)
		assertEq(winner, 3)
		check(core)
	end)

	test("audit 3: the target holder leaves with it queued behind a running machine; still winnable, nothing paid", function()
		local core = make({ { 1, "IndustrialCrusher" }, { 2 } }, "Gravel", 43)
		local target = core.TargetId
		queueUp(core, 1, 4, target)
		grab(core, 1, target)
		deposit(core, 1)
		core:setSpace(1, 0) -- machine paused on a full bag: the target sits in the queue
		core:tickMachines(tick(10))
		assertEq(core.Rocks[target].State, "Queued")
		local paid = core.Members[1].Rubble
		core:removeMember(1)
		assertEq(core.Members[1].Rubble, paid, "earned rubble is kept, nothing extra")
		assertEq(core.Rocks[target].State, "InPile")
		core:tickMachines(tick(10))
		check(core)
		assertEq(playOut(core, 2), 2)
	end)

	test("audit 3: every member leaves one after another, each holding rocks; the last one standing wins", function()
		for seed = 1, 10 do
			local core = make({ { 1 }, { 2, "AutoCracker" }, { 3 }, { 4 } }, "Gravel", 50 + seed)
			local seen = {}
			for uid = 1, 3 do
				queueUp(core, uid, 3)
				crush(core, uid)
				fill(core, uid, 2)
			end
			core:tickMachines(tick(0.3))
			if core.Phase == "Searching" then
				for uid = 1, 3 do
					core:removeMember(uid)
					check(core, seen)
				end
				assertEq(core:activeCount(), 1)
				assertEq(playOut(core, 4), 4)
			end
			check(core, seen)
		end
	end)

	test("audit 3: a reset (drop basket) followed by leaving never double-returns a rock", function()
		local core = make({ { 1 }, { 2 } }, "Gravel", 61)
		queueUp(core, 1, 4)
		fill(core, 1, 3)
		local before = core.Pile.Remaining
		assertEq(core:dropCarried(1), 3)
		assertEq(core:dropCarried(1), 0, "second reset drops nothing")
		core:removeMember(1)
		core:removeMember(1) -- duplicate leave notification
		assertEq(core.Pile.Remaining, before + 3 + 4)
		check(core)
	end)

	-- 4. Manual tool and machine on the same rock --------------------------------------------------------------
	test("audit 4: hand hits are refused while the machine runs; a paused machine plate is finished once by hand", function()
		local core = make({ { 1, "AutoCracker", tool = "SteelHammer" } }, "Quarry", 71) -- HP 2
		core.TargetId = 0 -- keep the round going (no target among these rocks)
		queueUp(core, 1, 3)
		local now = tick(1)
		core:tickMachines(now)
		local plate = core.Members[1].Current
		assert(plate, "machine took a rock")
		assertEq(select(2, crush(core, 1)), "Automatic")
		core:setMachineRunning(1, false, now + 0.1)
		local res = crush(core, 1) -- steel hammer: damage 2 >= HP 2, finishes the paused plate rock
		assertEq(countKind(res, "Cracked"), 1)
		assertEq(core.Rocks[plate].State, "ResolvedOrdinary")
		core:setMachineRunning(1, true, clock)
		local after = core:tickMachines(tick(5))
		for _, r in after do
			assert(r.RockId ~= plate, "the machine finished a rock the hand already finished")
		end
		assertEq(core.Members[1].Rubble, core.Members[1].Cracked)
		check(core)
	end)

	test("audit 4: unequipping or swapping a machine mid-rock never resolves that rock twice or for free", function()
		local core = make({ { 1, "HydraulicPress" } }, "Quarry", 73)
		core.TargetId = 0
		queueUp(core, 1, 4)
		core:tickMachines(tick(0.01))
		local plate = core.Members[1].Current
		core:setMachine(1, "IndustrialCrusher") -- re-timed from scratch
		local r = core:tickMachines(clock + 0.001)
		assertEq(#r, 0, "a swap gives no instant completion")
		core:setMachine(1, nil) -- now manual
		local hits = 0
		while core.Rocks[plate].State == "Processing" and hits < 10 do
			crush(core, 1)
			hits += 1
		end
		assertEq(core.Rocks[plate].State, "ResolvedOrdinary")
		assertEq(hits, core.MaxHp, "hand needs full HP: the machine left no hidden damage")
		check(core)
	end)

	-- 5. Selling during processing / 6. full rubble bag --------------------------------------------------------
	test("audit 5: a sale while a rock is on the plate keeps the reservation and pays exactly once", function()
		local core = make({ { 1, tool = "Hammer" } }, "Quarry", 81) -- HP 2: two hits per rock
		core.TargetId = 0
		queueUp(core, 1, 3)
		core:setSpace(1, 1)
		crush(core, 1) -- rock on the plate, the one free slot reserved
		assertEq(core.Members[1].Reserved, true)
		assertEq(core:machineState(1), "None")
		core:setSpace(1, 10) -- hopper sale mid-processing: the server refreshes Space from the profile
		assertEq(core.Members[1].Reserved, true, "still reserved after the sale")
		crush(core, 1)
		assertEq(core.Members[1].Rubble, 1)
		assertEq(core.Members[1].Space, 9, "one slot consumed by the one result")
		assertEq(core.Members[1].Reserved, false)
		check(core)
	end)

	test("audit 6: bag full with the target next in a machine queue: nothing starts, nothing leaks; a sale resumes it", function()
		local core = make({ { 1, "AutoCracker" }, { 2 } }, "Gravel", 83)
		local target = core.TargetId
		grab(core, 1, target)
		deposit(core, 1)
		core:setSpace(1, 0)
		for _ = 1, 5 do
			assertEq(#core:tickMachines(tick(1)), 0)
		end
		assertEq(core.Rocks[target].State, "Queued", "a full bag never singles out the target")
		assertEq(core:machineState(1), "Full")
		assertEq(core.Winner, nil)
		core:setSpace(1, 1)
		local results = core:tickMachines(tick(0.01))
		assertEq(#results, 0, "no back-dated instant finish after waiting on a full bag")
		results = core:tickMachines(tick(1))
		assertEq(countKind(results, "Found"), 1)
		assertEq(core.Members[1].Space, 1, "the geode pays no rubble and releases its slot")
		check(core)
	end)

	test("audit 6: storage of exactly N lets exactly N ordinary rocks finish, by hand and machine alike", function()
		for _, machine in { false, true } do
			local core = make({ { 1, if machine then "IndustrialCrusher" else nil } }, "Gravel", 85)
			core.TargetId = 0
			queueUp(core, 1, 10)
			core:setSpace(1, 4)
			for _ = 1, 30 do
				if machine then
					core:tickMachines(tick(1))
				else
					crush(core, 1)
				end
			end
			assertEq(core.Members[1].Rubble, 4)
			assertEq(core.Members[1].Space, 0)
			assertEq(#core.Members[1].Queue, 6, "the rest waits in the tray")
			check(core)
		end
	end)

	-- 7. Rematch ----------------------------------------------------------------------------------------------
	test("audit 7: rematch after a win is a fresh round; late requests and machine ticks for the old round do nothing", function()
		local old = make({ { 1, "AutoCracker" }, { 2 } }, "Gravel", 91, 1)
		grab(old, 2, old.TargetId)
		deposit(old, 2)
		queueUp(old, 1, 5, old.TargetId)
		crush(old, 2)
		assertEq(old.Winner, 2)
		old:setPhase("Ended")
		local new = make({ { 1, "AutoCracker" }, { 2 } }, "Gravel", 92, 2)
		for uid, m in new.Members do
			assertEq(#m.Basket + #m.Queue, 0)
			assertEq(m.Current, nil)
			assertEq(m.Rubble, 0)
			assertEq(m.Cracked, 0)
			assertEq(m.Reserved, false)
			assertEq(new:counters(uid).Unopened, new.Total)
		end
		assertEq(new.Winner, nil)
		assertEq(new.Broken, 0)
		-- the old core keeps ticking somewhere: it must not produce anything
		assertEq(#old:tickMachines(tick(10)), 0)
		-- requests carrying the old round id are rejected by the new round
		local id = new.Pile:pickableIds(3)[1]
		assertEq(new:pickup(1, 1, id, atRock(new, id), tick()), "StaleRound")
		assertEq(select(2, new:deposit(2, 1, atStation(new, 2), tick())), "StaleRound")
		assertEq(select(2, new:crush(2, 1, atStation(new, 2), tick())), "StaleRound")
		check(new)
		assertEq(playOut(new, 2), 2)
	end)

	test("audit 7: a fresh HuntLedger per round; a closed ledger ignores late events", function()
		local l1 = Ledger.new()
		Ledger.crushed(l1, 1, true)
		Ledger.sold(l1, 1, 5, 10)
		Ledger.close(l1)
		Ledger.crushed(l1, 1, true) -- a late machine Done after the results froze
		Ledger.sold(l1, 1, 3, 6)
		local s1 = Ledger.snapshot(l1, 1, { Count = 0, Capacity = 30, Value = 0 })
		assertEq(s1.Processed, 1)
		assertEq(s1.RubbleEarned, 1)
		assertEq(s1.RubbleSold, 5)
		assertEq(s1.SoldCash, 10)
		local l2 = Ledger.new()
		local s2 = Ledger.snapshot(l2, 1, { Count = 0, Capacity = 30, Value = 0 })
		assertEq(s2.Processed + s2.RubbleEarned + s2.RubbleSold + s2.SoldCash, 0, "rematch starts at zero")
	end)

	-- 8. Results numbers ---------------------------------------------------------------------------------------
	-- A server stand-in: profile (bag + cash), the round core, and the ledger, wired the way RockService /
	-- EconomyService use them. Checks the figures the results screen shows against what really happened.
	test("audit 8: results figures (processed, earned, sold, cash, bag) agree with the round and the profile", function()
		for seed = 1, 12 do
			local rate = Config.Tiers.Gravel.CashPerRubble
			local core = make({ { 1, "AutoCracker" }, { 2 } }, "Gravel", 100 + seed)
			local ledger = Ledger.new()
			local prof = {
				[1] = { Bag = 7, Cap = 30, Cash = 50 },
				[2] = { Bag = 29, Cap = 30, Cash = 0 },
			}
			local start = { [1] = { Bag = 7, Cash = 50 }, [2] = { Bag = 29, Cash = 0 } }
			local function refresh(uid)
				core:setSpace(uid, prof[uid].Cap - prof[uid].Bag)
			end
			local function apply(results)
				for _, r in results do
					if r.Kind == "Cracked" then
						prof[r.UserId].Bag += 1
						assert(prof[r.UserId].Bag <= prof[r.UserId].Cap, "bag over capacity")
						Ledger.crushed(ledger, r.UserId, true)
					elseif r.Kind == "Found" then
						Ledger.crushed(ledger, r.UserId, false)
					end
					refresh(r.UserId)
				end
			end
			local function sell(uid)
				local n = prof[uid].Bag
				if n > 0 then
					prof[uid].Bag = 0
					prof[uid].Cash += n * rate
					Ledger.sold(ledger, uid, n, n * rate)
					refresh(uid)
				end
			end
			refresh(1)
			refresh(2)
			local rng = Random.new(seed)
			local guard = 0
			while core.Phase == "Searching" and guard < 4000 do
				guard += 1
				for uid = 1, 2 do
					local m = core.Members[uid]
					if #m.Queue == 0 and m.Current == nil then
						fill(core, uid, Config.Carry.Capacity)
						deposit(core, uid)
					end
				end
				apply((crush(core, 2)))
				apply(core:tickMachines(tick(0.2)))
				if rng:NextInteger(1, 25) == 1 then
					sell(rng:NextInteger(1, 2)) -- selling during processing
				end
				if core.Members[2].Space <= 0 and rng:NextInteger(1, 3) == 1 then
					sell(2) -- member 2 starts with a nearly full bag
				end
			end
			assert(core.Winner, "round finished")
			Ledger.close(ledger)
			sell(1) -- a sale after the results froze: bag/cash change, hunt figures do not
			for uid = 1, 2 do
				local m = core.Members[uid]
				local p = prof[uid]
				local snap = Ledger.snapshot(ledger, uid, { Count = p.Bag, Capacity = p.Cap, Value = p.Bag * rate })
				assertEq(snap.Processed, m.Cracked, "processed = rocks this member finished")
				assertEq(snap.RubbleEarned, m.Rubble, "earned = ordinary rocks this member finished")
				assertEq(snap.Processed - snap.RubbleEarned, if core.Winner == uid then 1 else 0, "only the geode is unpaid")
				assertEq(snap.SoldCash, snap.RubbleSold * rate, "sold cash = sold rubble x rate")
				if uid == 2 then
					-- no post-results sale for member 2: the bag is fully explained by the hunt figures
					assertEq(p.Bag, start[uid].Bag + snap.RubbleEarned - snap.RubbleSold, "bag = start + earned - sold")
					assertEq(p.Cash, start[uid].Cash + snap.SoldCash, "cash = start + sold cash")
				end
				assertEq(snap.BagCount, p.Bag)
				assertEq(snap.BagValue, p.Bag * rate)
			end
			check(core)
		end
	end)

	test("audit 8: ledger rejects junk counts (NaN, negative, inf, fractions) and never goes negative", function()
		local l = Ledger.new()
		Ledger.sold(l, 1, 0 / 0, 10)
		Ledger.sold(l, 1, -4, 10)
		Ledger.sold(l, 1, math.huge, 10)
		Ledger.sold(l, 1, 2.9, 0 / 0)
		Ledger.sold(l, 1, 3, -5)
		local s = Ledger.snapshot(l, 1, { Count = -2, Capacity = 0 / 0, Value = math.huge })
		assertEq(s.RubbleSold, 5)
		assertEq(s.SoldCash, 0)
		assertEq(s.BagCount, 0)
		assertEq(s.BagCapacity, 0)
		assertEq(s.BagValue, 0)
	end)

	-- Queue display bound (brief V6 section 25, V7 section 0: table queue capacity ten) -------------------------
	test("audit 25: the station queue counter never exceeds its capacity (tray 10 + plate)", function()
		local core = make({ { 1 } }, "Quarry", 121) -- HP 2 so the plate rock stays on the plate
		core.TargetId = 0
		queueUp(core, 1, Config.Station.QueueCapacity)
		crush(core, 1) -- first rock moves to the plate: tray 9 queued, so deposit accepts one more
		fill(core, 1, 2)
		deposit(core, 1)
		local c = core:counters(1)
		assert(c.Queue <= c.QueueCapacity, ("queue shows %d/%d"):format(c.Queue, c.QueueCapacity))
	end)

	test("audit 21: a leaver whose machine already finished the target (not yet ticked) is not robbed of the win", function()
		local core = make({ { 1, "AutoCracker" }, { 2 } }, "Gravel", 131)
		local target = core.TargetId
		grab(core, 1, target)
		deposit(core, 1)
		local now = tick(1)
		core:tickMachines(now)
		assertEq(core.Members[1].Current, target)
		-- the machine completes at now + 0.5; the player disconnects at now + 0.6, before the next tick
		core:removeMember(1, now + 0.6)
		assertEq(core.Winner, 1, "the machine had finished the geode before the owner left")
	end)
end
