-- Server audit (run by tests/test_m10_server.luau): rock contention, duplicate requests, machine vs hand,
-- simultaneous target finishes, one specimen per round, rematch permissions, a leaver with the target queued.
-- Everything goes through the real RockAction / MatchAction / PartyAction handlers of a two-player hunt.
local C = lib("ctr")

local function case(name: string, fn)
	local ok, err = pcall(fn)
	if ok then
		print("CASE " .. name .. " PASS")
	else
		print("[FAIL] CASE " .. name .. ": " .. tostring(err))
	end
end
local function eq(a, b, msg)
	if a ~= b then
		error((msg or "mismatch") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

local s = C.boot({
	others = { { "Ava", 2 } },
	profile = function(data, Config)
		data.TutorialStep = 1
		data.Onboard.Skipped = true
		data.CapacityTier = #Config.Capacity -- a big bag: storage never pauses these hunts
	end,
})
local me, ava = s.me, s.others[1]
local Profiles, MatchService, PartyService = s.Profiles, s.MatchService, s.PartyService
local RockService = C.server("RockService")
local RoundRocks = C.shared("RoundRocks")
local Config = s.Config
do
	local d = Profiles.get(ava)
	if d then
		d.TutorialStep = 1
		d.Onboard.Skipped = true
		d.CapacityTier = #s.Config.Capacity
	end
end

local function step(dt: number?)
	preview.advance(dt or 0.06)
end
local function asMe(remote, ...)
	preview.fireServerAs(me, remote, ...)
end
local function asAva(remote, ...)
	preview.fireServerAs(ava, remote, ...)
end

-- party of two, both ready, leader starts
asMe("PartyAction", "Create")
step(0.3)
local party = PartyService.of(me.UserId)
asMe("PartyAction", "Invite", ava.UserId)
step(0.3)
asAva("PartyAction", "Accept", party and party.Id)
step(0.3)
asMe("PartyAction", "Ready", true)
asAva("PartyAction", "Ready", true)
step(0.3)
asMe("PartyAction", "Start")
step(Config.Match.CountdownSeconds + 0.5)
local m = MatchService.matchFor(me.UserId)
if not m or m.Phase ~= "Searching" then
	print("[FAIL] CASE hunt starts: phase " .. tostring(m and m.Phase))
	print("ROCKS DONE")
	return
end
local core = m.Core

local function standAt(p, localPos: Vector3)
	p.Character:PivotTo(CFrame.new(m.Arena.Center + Vector3.new(localPos.X, 3, localPos.Z)))
end
local function atTable(p)
	standAt(p, RoundRocks.stationPosition(core.Members[p.UserId].Index))
end
local function rock(p, action, id)
	preview.fireServerAs(p, "RockAction", action, m.Round, id)
end
local function holders(id): number
	local n = 0
	for _, mem in core.Members do
		for _, x in mem.Basket do
			n += if x == id then 1 else 0
		end
		for _, x in mem.Queue do
			n += if x == id then 1 else 0
		end
		n += if mem.Current == id then 1 else 0
	end
	return n
end
local function inventoryCount(p): number
	local d = Profiles.get(p)
	return if d then #d.InventoryGeodes else -1
end
-- Puts a rock straight into a member's basket (the target is rarely on the reachable edge of the pile).
local function grab(uid: number, id: number)
	local r = core.Rocks[id]
	if r.State ~= "InPile" then
		return false
	end
	core.Pile:remove(id)
	r.State, r.Carrier, r.Station = "Carried", uid, nil
	table.insert(core.Members[uid].Basket, id)
	return true
end
local function pickableNot(avoid: { [number]: boolean }): number?
	for _, id in core.Pile:pickableIds(Config.Carry.ReachLevels) do
		if not avoid[id] and id ~= core.TargetId then
			return id
		end
	end
	return nil
end

case("two players grabbing the same rock in the same frame: exactly one gets it", function()
	local id = pickableNot({}) :: number
	local lp = core.Pile:localPosition(id) :: Vector3
	standAt(me, lp + Vector3.new(2, 0, 0))
	standAt(ava, lp + Vector3.new(-2, 0, 0))
	step(0.6)
	rock(me, "Pickup", id)
	rock(ava, "Pickup", id) -- same frame, no time passes
	eq(holders(id), 1, "holders")
	eq(core.Rocks[id].State, "Carried")
	local c = core.Rocks[id].Carrier
	assert(c == me.UserId or c == ava.UserId, "carrier is one of them")
	-- a repeated pickup of the same rock by the winner is refused too
	step(0.6)
	rock(if c == me.UserId then me else ava, "Pickup", id)
	eq(holders(id), 1, "holders after repeat")
end)

case("duplicate deposit requests move each rock exactly once", function()
	local mine = core.Members[me.UserId]
	for _ = 1, 4 do
		if #mine.Basket >= 3 then
			break
		end
		local id = pickableNot({})
		if id then
			standAt(me, (core.Pile:localPosition(id) :: Vector3) + Vector3.new(2, 0, 0))
			step(0.6)
			rock(me, "Pickup", id)
		end
	end
	local carried = table.clone(mine.Basket)
	assert(#carried > 0, "basket filled")
	local before = #mine.Queue
	atTable(me)
	step(0.6)
	rock(me, "Deposit")
	rock(me, "Deposit")
	step(0.05)
	rock(me, "Deposit")
	eq(#mine.Basket, 0, "basket emptied")
	eq(#mine.Queue, before + #carried, "queue grew by the basket once")
	for _, id in carried do
		eq(holders(id), 1, "rock " .. id .. " in one place")
		eq(core.Rocks[id].State, "Queued")
	end
end)

case("a manual hit is refused while the machine runs; each rock resolves once", function()
	local mine = core.Members[me.UserId]
	core:setMachine(me.UserId, "AutoCracker")
	core:setMachineRunning(me.UserId, true, os.clock())
	local brokenBefore = core.Broken
	local rubbleBefore = mine.Rubble
	atTable(me)
	for _ = 1, 6 do
		step(0.6)
		rock(me, "Crush") -- refused: Automatic
	end
	step(3)
	-- the machine did the work; hand requests never added extra resolutions
	eq(core.Broken - brokenBefore, mine.Rubble - rubbleBefore, "one rubble per resolved rock")
	local resolved = 0
	for _, r in core.Rocks do
		if r.State == "ResolvedOrdinary" or r.State == "ResolvedGeode" then
			resolved += 1
		end
	end
	eq(resolved, core.Broken, "resolved records = broken counter")
	core:setMachine(me.UserId, nil)
end)

local myInvBefore, avaInvBefore = inventoryCount(me), inventoryCount(ava)
local function stats(p)
	local d = Profiles.get(p)
	return d.Stats.MultiplayerWins, d.Stats.MatchesPlayed
end
local myWins, myPlayed = stats(me)
local avaWins, avaPlayed = stats(ava)
case("two tables finishing in the same frame: one winner, one specimen", function()
	-- target on my plate path, an ordinary rock on Ava's
	local mine, hers = core.Members[me.UserId], core.Members[ava.UserId]
	core:setSpace(me.UserId, 100)
	core:setSpace(ava.UserId, 100)
	-- empty both stations first (hand-crush whatever is queued)
	for _, p in { me, ava } do
		atTable(p)
	end
	local guard = 0
	while (#mine.Queue > 0 or mine.Current or #hers.Queue > 0 or hers.Current) and guard < 200 do
		guard += 1
		step(1.2)
		if #mine.Queue > 0 or mine.Current then
			rock(me, "Crush")
		end
		if #hers.Queue > 0 or hers.Current then
			rock(ava, "Crush")
		end
		assert(core.Phase == "Searching", "the target was not queued yet")
	end
	assert(grab(me.UserId, core.TargetId), "target in my basket")
	local other = pickableNot({}) :: number
	assert(grab(ava.UserId, other), "ordinary rock in Ava's basket")
	step(0.6)
	rock(me, "Deposit")
	rock(ava, "Deposit")
	step(1.2)
	local avaCash = (Profiles.get(ava) :: any).Cash
	local avaRubble = hers.Rubble
	rock(ava, "Crush") -- Ava's ordinary rock (HP 1) finishes first in this frame
	rock(me, "Crush") -- and my hit finishes the target in the same frame
	eq(core.Winner, me.UserId, "winner")
	eq(core.Rocks[core.TargetId].State, "ResolvedGeode")
	eq(hers.Rubble, avaRubble + 1, "Ava's rock that finished first still pays")
	-- a duplicate / late Found report for the same round changes nothing
	RockService.apply(m, { { UserId = ava.UserId, RockId = core.TargetId, Kind = "Found" } })
	RockService.apply(m, { { UserId = me.UserId, RockId = core.TargetId, Kind = "Found" } })
	step(Config.Match.RevealSeconds + 1)
	eq(inventoryCount(me), myInvBefore + 1, "my specimens")
	eq(inventoryCount(ava), avaInvBefore, "Ava's specimens")
	local w1, p1 = stats(me)
	local w2, p2 = stats(ava)
	eq(w1, myWins + 1, "my wins: once")
	eq(w2, avaWins, "Ava's wins")
	eq(p1, myPlayed + 1, "my hunts played: once")
	eq(p2, avaPlayed + 1, "Ava's hunts played: once")
	eq(m.Phase, "Results")
	eq(m.Results.Winner, me.UserId)
	-- prizes for everyone (shared/HuntFun): Ava finished eggs, so her row has a paid medal; the finder's row is 1st
	local rows = {}
	for _, row in m.Results.Members do
		rows[row.UserId] = row
	end
	local ap, mp = rows[ava.UserId].Prize, rows[me.UserId].Prize
	assert(ap and ap.Place == 2 and ap.Medal == "Silver" and ap.Coins > 0, "Ava's silver medal")
	assert(mp and mp.Place == 1 and mp.Coins == 0, "the finder gets the pet, not prize coins")
	assert((Profiles.get(ava) :: any).Cash >= avaCash + ap.Coins, "Ava's prize coins are paid")
end)

case("late requests after the find change nothing", function()
	local snap = {}
	for id, r in core.Rocks do
		snap[id] = r.State
	end
	atTable(me)
	step(0.6)
	rock(me, "Crush")
	rock(ava, "Deposit")
	rock(ava, "Pickup", 1)
	for id, r in core.Rocks do
		eq(r.State, snap[id], "rock " .. id)
	end
end)

case("rematch: only the leader starts, and only once everyone tapped REMATCH", function()
	local round = m.Round
	asAva("MatchAction", "StartRematch") -- not the leader: ignored
	step(0.4)
	eq(m.Round, round, "non-leader cannot start")
	asMe("MatchAction", "StartRematch") -- Ava has not tapped REMATCH
	step(0.4)
	eq(m.Round, round, "leader waits for everyone")
	eq(m.Phase, "Results")
	asAva("MatchAction", "Rematch")
	step(0.4)
	asMe("MatchAction", "StartRematch")
	asMe("MatchAction", "StartRematch") -- double tap
	step(0.4)
	eq(m.Round, round + 1, "exactly one new round")
	eq(m.Phase, "Countdown")
	step(Config.Match.CountdownSeconds + 0.5)
	eq(m.Phase, "Searching")
	core = m.Core
	eq(core.Broken, 0, "fresh round")
end)

case("a member leaves with the target queued: records return and the round stays winnable", function()
	local hers = core.Members[ava.UserId]
	assert(grab(ava.UserId, core.TargetId), "target to Ava")
	local extra = pickableNot({}) :: number
	grab(ava.UserId, extra)
	atTable(ava)
	step(0.6)
	rock(ava, "Deposit")
	eq(core.Rocks[core.TargetId].State, "Queued")
	local pileBefore = core.Pile.Remaining
	asAva("MatchAction", "Return")
	step(0.3)
	eq(hers.Active, false, "Ava is out of the round")
	eq(core.Rocks[core.TargetId].State, "InPile", "target back in the pile")
	eq(core.Rocks[extra].State, "InPile")
	eq(core.Pile.Remaining, pileBefore + 2)
	assert(core.Pile:isPickable(core.TargetId, Config.Carry.ReachLevels), "returned target is reachable")
	local w = C.watchMatch()
	w.last.Init = { Round = m.Round, Tier = core.Tier, Rocks = core.Total, Seed = core.Seed, Stacks = core.Pile:stacks(), Center = m.Arena.Center, Stations = core:stationViews(os.clock()), Tables = RockService.initFields(m).Tables }
	local inv = inventoryCount(me)
	local found = C.crackUntilFound(w, { me }, 600)
	assert(found, "found after the leaver")
	eq(core.Winner, me.UserId)
	step(Config.Match.RevealSeconds + 1)
	eq(inventoryCount(me), inv + 1, "one specimen for this round")
end)

case("teleport check: a jump locks rock actions for a moment, walking does not", function()
	-- the scene boot turns the check off (scenes teleport); this case turns it back on
	asMe("MatchAction", "Rematch")
	step(0.4)
	asMe("MatchAction", "StartRematch")
	step(Config.Match.CountdownSeconds + 0.5)
	eq(m.Phase, "Searching", "new round")
	core = m.Core
	Config.Motion.Enabled = true
	local ok, err = pcall(function()
		local station = RoundRocks.stationPosition(core.Members[me.UserId].Index)
		-- settle beside the table, then walk a short step and deposit: no lock
		local a = pickableNot({}) :: number
		grab(me.UserId, a)
		standAt(me, station + Vector3.new(3, 0, 0))
		RockService.resetMotion(me.UserId)
		step(0.6)
		standAt(me, station + Vector3.new(1, 0, 0))
		step(0.6)
		rock(me, "Deposit")
		step(0.1)
		eq(core.Rocks[a].State, "Queued", "a walked-up deposit works")
		-- leave for the far side of the pile, then jump straight back: the deposit is ignored
		local b = pickableNot({}) :: number
		grab(me.UserId, b)
		standAt(me, station * -1)
		step(0.6)
		step(0.6)
		atTable(me)
		step(0.6)
		rock(me, "Deposit")
		step(0.1)
		eq(core.Rocks[b].State, "Carried", "deposit refused right after a teleport")
		-- after the lock the same deposit goes through
		step(Config.Motion.Lock + 0.2)
		rock(me, "Deposit")
		step(0.1)
		eq(core.Rocks[b].State, "Queued", "deposit works once the lock ends")
	end)
	Config.Motion.Enabled = false
	if not ok then
		error(err, 0)
	end
end)

case("surprise eggs: every 10th egg adds a Lucky Meter point, and every egg pays a prize", function()
	local HuntFun = C.shared("HuntFun")
	local d = Profiles.get(me) :: any
	d.EggPerks.Meter = 0
	d.EggPerks.HuntEggs = 0
	local cash, n = d.Cash, HuntFun.Surprise.EggsPerMeter
	local was = m.Tutorial
	m.Tutorial = false
	for i = 1, n do
		RockService.apply(m, { { UserId = me.UserId, RockId = 9000 + i, Kind = "Cracked", Material = "Common" } })
	end
	m.Tutorial = was
	eq(d.EggPerks.Meter, 1, "one meter point from " .. n .. " eggs")
	eq(d.EggPerks.HuntEggs, 0, "counter wrapped")
	assert(d.Cash > cash, "coin prizes paid")
end)

print("ROCKS DONE")
