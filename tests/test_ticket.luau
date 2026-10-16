return function(t)
	local test, shared = t.test, t.shared
	local MatchTicket = shared("MatchTicket")
	local ArrivalGate = shared("ArrivalGate")
	local PlaceRole = shared("PlaceRole")

	local function mk(members, leader, now)
		local ticket, err = MatchTicket.create({
			Id = "srv-1",
			Leader = leader or members[1],
			Members = members,
			Tier = "Gravel",
			Now = now or 1000,
			ArriveSeconds = 120,
			LifetimeSeconds = 3600,
			MaxMembers = 4,
		})
		assert(ticket, tostring(err))
		return ticket, MatchTicket.newState()
	end

	test("ticket: bad rosters are refused at creation", function()
		local base = { Id = "x", Tier = "Gravel", Now = 0, ArriveSeconds = 1, LifetimeSeconds = 1, MaxMembers = 4 }
		local function try(members, leader)
			local o = table.clone(base)
			o.Members, o.Leader = members, leader
			local tk, err = MatchTicket.create(o)
			return tk, err
		end
		assert(select(2, try({}, 1)) == "BadSize")
		assert(select(2, try({ 1, 2, 3, 4, 5 }, 1)) == "BadSize")
		assert(select(2, try({ 1, 1 }, 1)) == "BadMember")
		assert(select(2, try({ 1, 2 }, 9)) == "LeaderNotMember")
		assert(try({ 1, 2 }, 2) ~= nil)
	end)

	test("ticket: unknown user rejected, members accepted", function()
		local tk, st = mk({ 11, 22 })
		assert(MatchTicket.validate(tk, st, 11, 1010, 3).Ok)
		local v = MatchTicket.validate(tk, st, 99, 1010, 3)
		assert(not v.Ok and v.Reason == "NotMember")
		assert(MatchTicket.validate(tk, st, "11", 1010, 3).Reason == "Unknown")
		assert(MatchTicket.validate(nil, st, 11, 1010, 3).Reason == "NoTicket")
	end)

	test("ticket: expired ticket rejected (first arrival window and lifetime)", function()
		local tk, st = mk({ 11, 22 }, 11, 1000)
		assert(MatchTicket.validate(tk, st, 11, 1120, 3).Ok, "inside the arrive window")
		assert(MatchTicket.validate(tk, st, 11, 1121, 3).Reason == "Expired", "late first arrival")
		-- a member who arrived in time may still reconnect until the ticket dies
		MatchTicket.recordArrive(st, 22)
		MatchTicket.recordLeave(st, 22)
		assert(MatchTicket.validate(tk, st, 22, 3000, 3).Ok)
		assert(MatchTicket.validate(tk, st, 22, 4601, 3).Reason == "Expired")
	end)

	test("ticket: consumed ticket rejected for everyone", function()
		local tk, st = mk({ 11, 22 })
		MatchTicket.close(tk, st)
		assert(MatchTicket.validate(tk, st, 11, 1001, 3).Reason == "Consumed")
		assert(MatchTicket.validate(tk, st, 22, 1001, 3).Reason == "Consumed")
		-- a stored ticket flagged consumed (old server gone) is refused by a fresh server
		local tk2, st2 = mk({ 11 })
		tk2.Consumed = true
		assert(MatchTicket.validate(tk2, st2, 11, 1001, 3).Reason == "Consumed")
	end)

	test("ticket: duplicate while present rejected; reconnect allowed once", function()
		local tk, st = mk({ 11, 22 })
		local v = MatchTicket.validate(tk, st, 11, 1001, 1)
		assert(v.Ok and not v.Reconnect)
		MatchTicket.recordArrive(st, 11)
		assert(MatchTicket.validate(tk, st, 11, 1002, 1).Reason == "Duplicate")
		MatchTicket.recordLeave(st, 11)
		local r = MatchTicket.validate(tk, st, 11, 1003, 1)
		assert(r.Ok and r.Reconnect, "first reconnect allowed")
		MatchTicket.recordArrive(st, 11)
		MatchTicket.recordLeave(st, 11)
		assert(MatchTicket.validate(tk, st, 11, 1004, 1).Reason == "ReconnectLimit", "second reconnect refused")
		-- the other member is unaffected
		assert(MatchTicket.validate(tk, st, 22, 1004, 1).Ok)
	end)

	test("gate: everyone arrives -> Ready -> start", function()
		local g = ArrivalGate.new({ 1, 2, 3 }, 1, 30)
		assert(g:status(0) == "Idle")
		assert(g:arrive(2, 5))
		assert(g:status(6) == "Waiting")
		assert(g:arrive(1, 7))
		assert(g:arrive(3, 9))
		assert(g:status(10) == "Ready")
		local roster = g:start(nil, 10)
		assert(roster and #roster == 3 and roster[1] == 1)
		assert(g:status(11) == "Started")
	end)

	test("gate: partial arrival waits 30 s, then only the leader may start with arrived", function()
		local g = ArrivalGate.new({ 1, 2, 3 }, 1, 30)
		g:arrive(1, 100)
		g:arrive(3, 101)
		assert(g:status(120) == "Waiting")
		assert(select(2, g:start(1, 120)) == "StillWaiting", "no unfair early start")
		assert(g:status(130) == "TimedOut")
		assert(select(2, g:start(3, 130)) == "NotLeader")
		local roster = g:start(1, 130)
		assert(roster and #roster == 2 and roster[1] == 1 and roster[2] == 3)
		-- the slow member is late: the hunt began without them
		local ok, why = g:arrive(2, 140)
		assert(not ok and why == "Started")
		-- strangers are never accepted
		local ok2, why2 = g:arrive(9, 140)
		assert(not ok2 and why2 == "NotExpected")
	end)

	test("gate: a slow member can still make it after the timeout, before start", function()
		local g = ArrivalGate.new({ 1, 2 }, 1, 30)
		g:arrive(1, 0)
		assert(g:status(31) == "TimedOut")
		assert(g:arrive(2, 32))
		assert(g:status(32) == "Ready")
	end)

	test("gate: leader leaves -> earliest remaining member leads; everyone leaves -> Empty", function()
		local g = ArrivalGate.new({ 1, 2, 3 }, 2, 30)
		g:arrive(1, 0)
		g:arrive(2, 1)
		g:arrive(3, 2)
		assert(g:leader() == 2)
		g:leave(2)
		assert(g:leader() == 1, "earliest remaining member")
		g:leave(1)
		assert(g:leader() == 3)
		g:leave(3)
		assert(g:leader() == nil)
		assert(g:status(5) == "Empty")
	end)

	test("gate: leader return cancels; reconnect of a roster member allowed after start", function()
		local g = ArrivalGate.new({ 1, 2 }, 1, 30)
		g:arrive(1, 0)
		assert(select(2, g:cancel(2, 1)) == "NotLeader")
		local g2 = ArrivalGate.new({ 1, 2 }, 1, 30)
		g2:arrive(1, 0)
		g2:arrive(2, 1)
		g2:start(nil, 2)
		g2:leave(2)
		assert(g2:status(3) == "Started")
		assert(g2:arrive(2, 4), "roster member reconnects")
		assert(select(2, g2:cancel(1, 5)) == "Started", "cannot cancel a running hunt")
		assert(g:cancel(1, 2))
		assert(g:status(3) == "Cancelled")
		local ok = g:arrive(2, 3)
		assert(not ok)
	end)

	test("place role: SinglePlace by default, Teleport only when both ids are set", function()
		assert(PlaceRole.resolve("SinglePlace", 5, 5, 6) == "Single")
		assert(PlaceRole.resolve("Teleport", 5, 0, 0) == "Single")
		assert(PlaceRole.resolve("Teleport", 5, 5, 0) == "Single")
		assert(PlaceRole.resolve("Teleport", 5, 5, 5) == "Single")
		assert(PlaceRole.resolve("Teleport", 5, 5, 6) == "Lobby")
		assert(PlaceRole.resolve("Teleport", 6, 5, 6) == "Match")
		assert(PlaceRole.resolve("Teleport", 0, 5, 6) == "Single", "Studio / unpublished place")
	end)
end
