-- Leaving mid-game (run by tests/test_save_safe.luau): a player who QUITS (Players.PlayerRemoving) or respawns during a
-- party hunt (carrying eggs), a PvP fight (vs a player and vs a bot), the PvP queue or a tower climb never leaves anyone
-- stuck: the others' round / fight ends correctly, islands and arenas are freed, queues and parties drop the leaver,
-- and the leaver's pets and coins are saved. Drives the real services through their real remotes on the offline mock.
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
	others = { { "Ava", 2 }, { "Ben", 3 }, { "Cal", 4 }, { "Dee", 5 }, { "Eli", 6 } },
	profile = function(data, Config)
		data.TutorialStep = 1
		data.Onboard.Skipped = true
		data.CapacityTier = #Config.Capacity
	end,
})
local me, Profiles, MatchService, PartyService, Config = s.me, s.Profiles, s.MatchService, s.PartyService, s.Config
local ava, ben, cal, dee, eli = s.others[1], s.others[2], s.others[3], s.others[4], s.others[5]
local PvpService = C.server("PvpService")
local SkyIsland = C.server("SkyIsland")
local TowerService = C.server("TowerService")
local PvpConfig = C.shared("PvpConfig")
local RoundRocks = C.shared("RoundRocks")
local store = game:GetService("DataStoreService"):GetDataStore(Config.Save.StoreName)

local function step(dt: number?)
	preview.advance(dt or 0.25)
end
local function until_(fn, limit: number?): boolean
	local t = 0
	while not fn() and t < (limit or 60) do
		step(0.25)
		t += 0.25
	end
	return fn() and true or false
end
for _, p in s.others do
	assert(until_(function()
		return Profiles.isLoaded(p)
	end, 20), "loaded " .. p.Name)
	local d = Profiles.get(p)
	d.TutorialStep = 1
	d.Onboard.Skipped = true
	d.CapacityTier = #Config.Capacity
end
-- three pets each (same shape, own ids) so every PvP pairing is an even match
local base = C.fakeSpecimens(1)[1]
local function givePets(p, tag)
	local d = Profiles.get(p)
	d.InventoryGeodes = {}
	d.EquippedPets = {}
	for i = 1, 3 do
		local g = table.clone(base)
		g.Id = tag .. i
		g.Seed = 1000 + i
		table.insert(d.InventoryGeodes, g)
	end
	Profiles.changed(p)
end
for _, p in { me, ava, ben, cal, dee, eli } do
	givePets(p, p.Name)
end
local function saved(p): any
	return store:GetAsync("u_" .. p.UserId)
end
local function party(p, ...)
	preview.fireServerAs(p, "PartyAction", ...)
end

local got: { [Player]: { any } } = {}
PvpService.onSend = function(p, msg)
	got[p] = got[p] or {}
	table.insert(got[p], msg)
end
local function last(p, kind)
	local list = got[p] or {}
	for i = #list, 1, -1 do
		if list[i].Kind == kind then
			return list[i]
		end
	end
	return nil
end

case("party hunt: a member QUITS carrying the pet egg; the eggs go back, the hunt goes on and stays winnable", function()
	party(me, "Create")
	step(0.3)
	local pt = PartyService.of(me.UserId)
	party(me, "Invite", ava.UserId)
	step(0.3)
	party(ava, "Accept", pt and pt.Id)
	step(0.3)
	party(me, "Ready", true)
	party(ava, "Ready", true)
	step(0.3)
	party(me, "Start")
	step(Config.Match.CountdownSeconds + 1)
	local m = MatchService.matchFor(me.UserId)
	assert(m and m.Phase == "Searching", "hunting: " .. tostring(m and m.Phase))
	local core = m.Core
	-- Ava carries the pet egg and one more
	local function grab(uid, id)
		core.Pile:remove(id)
		local r = core.Rocks[id]
		r.State, r.Carrier, r.Station = "Carried", uid, nil
		table.insert(core.Members[uid].Basket, id)
	end
	grab(ava.UserId, core.TargetId)
	local extra
	for _, id in core.Pile:pickableIds(Config.Carry.ReachLevels) do
		if id ~= core.TargetId then
			extra = id
			break
		end
	end
	grab(ava.UserId, extra)
	local pets = #Profiles.get(ava).InventoryGeodes
	preview.removePlayer(ava)
	step(0.5)
	eq(core.Rocks[core.TargetId].State, "InPile", "pet egg back in the pile")
	eq(core.Rocks[extra].State, "InPile")
	assert(core.Pile:isPickable(core.TargetId, Config.Carry.ReachLevels), "and reachable")
	eq(core.Members[ava.UserId].Active, false)
	eq(MatchService.matchFor(ava.UserId), nil, "no hunt entry left for the leaver")
	eq(PartyService.of(ava.UserId), nil, "the leaver is out of the party")
	eq(m.Phase, "Searching", "the hunt goes on")
	eq(MatchService.matchFor(me.UserId), m)
	local rec = saved(ava)
	eq(rec.Lock, nil, "leaver's save released")
	eq(#rec.Data.InventoryGeodes, pets, "leaver's pets saved")
	-- the last one out ends the hunt and unlocks the party
	preview.fireServerAs(me, "MatchAction", "Return")
	step(0.5)
	eq(MatchService.matchFor(me.UserId), nil)
	eq(pt.Locked, false, "party unlocked")
	party(me, "Leave")
	step(0.3)
end)

case("hunt: dying / resetting with eggs in the basket drops them back on the pile", function()
	party(ben, "Solo")
	step(Config.Match.CountdownSeconds + 1)
	local m = MatchService.matchFor(ben.UserId)
	assert(m and m.Phase == "Searching", "hunting")
	local core = m.Core
	local id = core.Pile:pickableIds(Config.Carry.ReachLevels)[1]
	core.Pile:remove(id)
	core.Rocks[id].State, core.Rocks[id].Carrier = "Carried", ben.UserId
	table.insert(core.Members[ben.UserId].Basket, id)
	C.makeCharacter(ben, CFrame.new(0, 0, 0)) -- respawn
	step(0.5)
	eq(core.Rocks[id].State, "InPile", "egg back on the pile")
	eq(#core.Members[ben.UserId].Basket, 0)
	eq(MatchService.matchFor(ben.UserId), m, "still hunting after the respawn")
	-- quitting a solo hunt ends it (arena freed)
	preview.removePlayer(ben)
	step(0.5)
	eq(MatchService.matchFor(ben.UserId), nil)
	local _ = RoundRocks
end)

case("PvP vs a player: the quitter loses, the other wins at once, the island is freed and nobody is stuck", function()
	got = {}
	local islands = SkyIsland.count()
	PvpService.action(cal, { Op = "Queue" })
	PvpService.action(dee, { Op = "Queue" })
	assert(until_(function()
		return PvpService.fightOf(cal) ~= nil
	end, 10), "matched")
	local f = PvpService.fightOf(cal)
	eq(PvpService.fightOf(dee), f, "with each other")
	eq(SkyIsland.count(), islands + 1, "one island")
	step(PvpConfig.CountIn + PvpConfig.ForfeitWinAfter + 1)
	local pets = #Profiles.get(dee).InventoryGeodes
	local losses = Profiles.get(dee).Pvp.Losses
	local wins = Profiles.get(cal).Pvp.Wins
	preview.removePlayer(dee)
	step(0.5)
	eq(PvpService.fightOf(dee), nil, "leaver out of the fight")
	assert(until_(function()
		return last(cal, "Result") ~= nil
	end, PvpConfig.ResultHold + 5), "winner gets a result")
	eq(last(cal, "Result").Result, "Win")
	eq(Profiles.get(cal).Pvp.Wins, wins + 1)
	eq(PvpService.fightOf(cal), nil, "winner back in the lobby")
	eq(cal:GetAttribute("InBattle"), nil)
	eq(SkyIsland.count(), islands, "island freed")
	local rec = saved(dee)
	eq(rec.Lock, nil, "leaver saved")
	eq(#rec.Data.InventoryGeodes, pets, "no pet lost")
	eq(rec.Data.Pvp.Losses, losses + 1, "the loss is on the leaver's record")
end)

case("PvP vs a bot: quitting mid-fight closes the fight and frees the island", function()
	got = {}
	local islands = SkyIsland.count()
	PvpService.action(eli, { Op = "Queue" })
	assert(until_(function()
		return PvpService.fightOf(eli) ~= nil
	end, PvpConfig.BotAfter + 5), "bot fight")
	step(PvpConfig.CountIn + 1)
	preview.removePlayer(eli)
	step(0.5)
	eq(SkyIsland.count(), islands, "island freed at once")
	eq(PvpService.fightOf(eli), nil)
end)

case("PvP queue: a queued player who quits is never matched; the other gets a bot", function()
	got = {}
	-- Cal queues, a fresh player queues and quits before the pairing tick
	local fay = preview.addPlayer("Fay", 7)
	C.makeCharacter(fay, CFrame.new(0, 0, 20))
	preview.playerJoined(fay)
	assert(until_(function()
		return Profiles.isLoaded(fay)
	end, 20), "loaded")
	givePets(fay, "Fay")
	PvpService.action(fay, { Op = "Queue" })
	preview.removePlayer(fay)
	PvpService.action(cal, { Op = "Queue" })
	step(1)
	eq(PvpService.fightOf(cal), nil, "not matched with the leaver")
	assert(until_(function()
		return PvpService.fightOf(cal) ~= nil
	end, PvpConfig.BotAfter + 5), "a bot steps in")
	local f = PvpService.fightOf(cal)
	eq(f.BotSide, 2, "vs a bot")
	PvpService.action(cal, { Op = "Leave" })
	step(PvpConfig.ResultHold + 1)
	eq(PvpService.fightOf(cal), nil)
end)

case("PvP: the winner quits during the cheer: the win is saved and the island freed at once", function()
	got = {}
	local islands = SkyIsland.count()
	local jo = preview.addPlayer("Jo", 11)
	C.makeCharacter(jo, CFrame.new(0, 0, 30))
	preview.playerJoined(jo)
	assert(until_(function()
		return Profiles.isLoaded(jo)
	end, 20), "loaded")
	givePets(jo, "Jo")
	PvpService.action(cal, { Op = "Queue" })
	PvpService.action(jo, { Op = "Queue" })
	assert(until_(function()
		return PvpService.fightOf(cal) ~= nil and PvpService.fightOf(cal) == PvpService.fightOf(jo)
	end, 10), "matched")
	step(PvpConfig.CountIn + 1)
	local wins = Profiles.get(cal).Pvp.Wins
	PvpService.action(jo, { Op = "Leave" }) -- Jo gives up: Cal wins, the cheer starts
	step(0.3)
	eq(PvpService.fightOf(cal).Phase, "Cheer")
	preview.removePlayer(cal)
	step(0.3)
	eq(SkyIsland.count(), islands, "island freed at once")
	local rec = saved(cal)
	eq(rec.Data.Pvp.Wins, wins + 1, "the win is in the leaver's save")
	preview.removePlayer(jo)
	step(0.3)
end)

case("tower: quitting mid-climb closes the run and frees the tower arena", function()
	local towerAction = game:GetService("ReplicatedStorage"):WaitForChild("TowerNet"):WaitForChild("TowerAction")
	towerAction.OnServerEvent:_fire(me, { Op = "Start" })
	step(1)
	eq(TowerService.inTower(me), true, "climbing")
	-- a fresh climber quits: the run closes, its arena is destroyed and its slot goes back to the free list
	local TowerBuilder = C.server("TowerBuilder")
	local claimed = {}
	local real = TowerBuilder.claim
	TowerBuilder.claim = function(...)
		local slot, a, b = real(...)
		table.insert(claimed, { Slot = slot, Arena = a })
		return slot, a, b
	end
	local ok, err = pcall(function()
		local gus = preview.addPlayer("Gus", 8)
		C.makeCharacter(gus, CFrame.new(0, 0, 24))
		preview.playerJoined(gus)
		assert(until_(function()
			return Profiles.isLoaded(gus)
		end, 20), "loaded")
		givePets(gus, "Gus")
		towerAction.OnServerEvent:_fire(gus, { Op = "Start" })
		step(1)
		eq(TowerService.inTower(gus), true, "Gus climbing")
		local his = claimed[#claimed]
		assert(his and his.Arena.Parent ~= nil, "his arena is built")
		step(3)
		local pets = #Profiles.get(gus).InventoryGeodes
		preview.removePlayer(gus)
		step(0.5)
		eq(TowerService.inTower(gus), false, "run closed")
		eq(his.Arena.Parent, nil, "his arena is gone")
		eq(TowerService.inTower(me), true, "the other climber is untouched")
		eq(#saved(gus).Data.InventoryGeodes, pets, "no pet lost")
		-- the next climb reuses his slot (no leaked slot)
		local hal2 = preview.addPlayer("Ivy", 10)
		C.makeCharacter(hal2, CFrame.new(0, 0, 26))
		preview.playerJoined(hal2)
		assert(until_(function()
			return Profiles.isLoaded(hal2)
		end, 20), "loaded")
		givePets(hal2, "Ivy")
		towerAction.OnServerEvent:_fire(hal2, { Op = "Start" })
		step(1)
		eq(claimed[#claimed].Slot, his.Slot, "slot reused")
		preview.removePlayer(hal2)
		step(0.5)
	end)
	TowerBuilder.claim = real
	towerAction.OnServerEvent:_fire(me, { Op = "Leave" })
	step(1)
	if not ok then
		error(err, 0)
	end
end)

case("party: the leader quits during the countdown; the member leads and is not stuck", function()
	local hal = preview.addPlayer("Hal", 9)
	C.makeCharacter(hal, CFrame.new(0, 0, 28))
	preview.playerJoined(hal)
	assert(until_(function()
		return Profiles.isLoaded(hal)
	end, 20), "loaded")
	local d = Profiles.get(hal)
	d.TutorialStep = 1
	d.Onboard.Skipped = true
	party(hal, "Create")
	step(0.3)
	local pt = PartyService.of(hal.UserId)
	party(hal, "Invite", me.UserId)
	step(0.3)
	party(me, "Accept", pt and pt.Id)
	step(0.3)
	party(hal, "Ready", true)
	party(me, "Ready", true)
	step(0.3)
	party(hal, "Start")
	step(0.5)
	assert(MatchService.matchFor(me.UserId), "countdown: members " .. #pt.Members .. ", blockers " .. table.concat(PartyService.blockers(pt, hal.UserId), "/") .. " " .. table.concat(PartyService.blockers(pt, me.UserId), "/"))
	preview.removePlayer(hal)
	step(0.5)
	eq(PartyService.of(hal.UserId), nil)
	eq(pt.Leader, me.UserId, "the member leads now")
	-- the member can always get out
	preview.fireServerAs(me, "MatchAction", "Return")
	step(0.5)
	eq(MatchService.matchFor(me.UserId), nil, "back in the lobby")
	eq(pt.Locked, false)
end)

print("LEAVE_MIDGAME DONE")
