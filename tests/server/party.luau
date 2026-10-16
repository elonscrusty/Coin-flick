-- Server audit (run by tests/test_m10_server.luau): party rules through the real PartyAction / MatchAction
-- handlers. Four-player limit (also with invites pending), leader permissions, leader leaving, member leaving
-- mid-hunt, double Start / double Solo never opening two hunts.
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
	others = { { "Ava", 2 }, { "Ben", 3 }, { "Cal", 4 }, { "Dee", 5 } },
	profile = function(data, Config)
		data.TutorialStep = 1
		data.Onboard.Skipped = true
		data.CapacityTier = #Config.Capacity -- a big bag: storage never pauses these hunts
	end,
})
local me = s.me
local ava, ben, cal, dee = s.others[1], s.others[2], s.others[3], s.others[4]
local Profiles, MatchService, PartyService, Config = s.Profiles, s.MatchService, s.PartyService, s.Config
for _, p in s.others do
	local d = Profiles.get(p)
	if d then
		d.TutorialStep = 1
		d.Onboard.Skipped = true
		d.CapacityTier = #s.Config.Capacity
	end
end
local function step(dt: number?)
	preview.advance(dt or 0.3)
end
local function act(p, ...)
	preview.fireServerAs(p, "PartyAction", ...)
end
local function members(party): { number }
	return if party then party.Members else {}
end

local party
case("four-player limit holds even with invites outstanding", function()
	act(me, "Create")
	step()
	party = PartyService.of(me.UserId)
	assert(party, "party created")
	for _, p in { ava, ben, cal, dee } do
		act(me, "Invite", p.UserId) -- all four invited while there is room
		step()
	end
	for _, p in { ava, ben, cal } do
		act(p, "Accept", party.Id)
		step()
	end
	eq(#party.Members, Config.Party.MaxSize, "party is full")
	act(dee, "Accept", party.Id) -- the fifth accept arrives after the party filled up
	step()
	eq(#party.Members, Config.Party.MaxSize, "still four")
	eq(PartyService.of(dee.UserId), nil, "Dee is not in it")
	act(me, "Invite", dee.UserId)
	step()
	eq(#party.Members, Config.Party.MaxSize)
end)

case("only the leader can kick, change tier or start", function()
	local tier = party.Tier
	act(ava, "Kick", ben.UserId)
	act(ava, "Tier", "Quarry")
	for _, p in { me, ava, ben, cal } do
		act(p, "Ready", true)
	end
	step()
	act(ava, "Start")
	step()
	eq(#party.Members, 4, "nobody kicked by a member")
	eq(party.Tier, tier, "tier unchanged")
	eq(MatchService.isBusy(me.UserId), false, "no hunt started by a member")
end)

case("leader leaves: the earliest remaining member leads", function()
	act(me, "Leave")
	step()
	eq(PartyService.of(me.UserId), nil, "I left")
	eq(party.Leader, ava.UserId, "Ava leads")
	eq(#party.Members, 3)
	act(ava, "Kick", cal.UserId) -- the new leader's powers work
	step()
	eq(#party.Members, 2)
	eq(PartyService.of(cal.UserId), nil)
end)

case("double Start opens exactly one hunt", function()
	act(ava, "Ready", true)
	act(ben, "Ready", true)
	step()
	act(ava, "Start")
	act(ava, "Start") -- same frame
	step(0.2)
	local m1 = MatchService.matchFor(ava.UserId)
	local m2 = MatchService.matchFor(ben.UserId)
	assert(m1, "hunt started")
	eq(m1, m2, "both in the same hunt")
	eq(party.Locked, true, "roster locked while hunting")
end)

case("roster is locked mid-hunt: no invites, kicks or new members", function()
	act(ava, "Invite", dee.UserId)
	act(ava, "Kick", ben.UserId)
	step()
	act(dee, "Accept", party.Id)
	step()
	eq(#party.Members, 2)
	eq(PartyService.of(dee.UserId), nil)
end)

case("a member leaves mid-hunt: the hunt goes on for the others", function()
	step(Config.Match.CountdownSeconds + 0.5)
	local m = MatchService.matchFor(ava.UserId)
	eq(m and m.Phase, "Searching")
	preview.fireServerAs(ben, "MatchAction", "Return")
	step()
	eq(MatchService.isBusy(ben.UserId), false, "Ben is back in the lobby")
	eq(m.Core.Members[ben.UserId].Active, false)
	eq(m.Present[ava.UserId], true, "Ava still hunting")
	-- Ben may leave the (locked) party from the lobby; he cannot start anything else while it hunts
	act(ben, "Solo")
	step()
	eq(MatchService.isBusy(ben.UserId), false, "no solo hunt while his party is hunting")
	act(ben, "Leave")
	step()
	eq(PartyService.of(ben.UserId), nil)
	eq(#party.Members, 1)
	-- with everyone gone the arena is released and the party unlocked
	preview.fireServerAs(ava, "MatchAction", "Return")
	step()
	eq(MatchService.isBusy(ava.UserId), false)
	eq(party.Locked, false, "party unlocked after the hunt ended")
end)

case("double Solo opens exactly one hunt", function()
	act(dee, "Solo")
	act(dee, "Solo")
	step(0.2)
	local m = MatchService.matchFor(dee.UserId)
	assert(m, "solo hunt started")
	local p = PartyService.of(dee.UserId)
	eq(p and #p.Members, 1)
	act(dee, "Solo") -- while hunting: refused
	step()
	eq(MatchService.matchFor(dee.UserId), m, "still the same hunt")
end)

case("leader returns to the lobby on the results screen: the member left can start the rematch", function()
	act(me, "Create")
	step()
	local p2 = PartyService.of(me.UserId)
	step(11) -- past the 10 s re-invite cooldown from the first case
	act(me, "Invite", cal.UserId)
	step()
	act(cal, "Accept", p2.Id)
	step()
	eq(#p2.Members, 2, "Cal joined")
	act(me, "Ready", true)
	act(cal, "Ready", true)
	step()
	local w = C.watchMatch()
	act(me, "Start")
	step(0.2)
	local init = nil
	for _ = 1, 20 do
		init = w.last.Init
		if init then
			break
		end
		step(0.1)
	end
	local m = MatchService.matchFor(me.UserId)
	assert(m, "hunt started")
	if not init then
		local RockService = C.server("RockService")
		w.last.Init = { Round = m.Round, Tier = m.Core.Tier, Rocks = m.Core.Total, Seed = m.Core.Seed, Center = m.Arena.Center }
		for k, v in RockService.initFields(m) do
			w.last.Init[k] = v
		end
	end
	step(Config.Match.CountdownSeconds + 0.5)
	local ok = C.crackUntilFound(w, { me, cal }, 800)
	assert(ok, "geode found (phase " .. tostring(m.Phase) .. ", broken " .. tostring(m.Core.Broken) .. ", init " .. tostring(init ~= nil) .. ")")
	step(Config.Match.RevealSeconds + 1)
	eq(m.Phase, "Results")
	local round = m.Round
	preview.fireServerAs(me, "MatchAction", "Return") -- the party leader leaves the results screen
	step()
	eq(p2.Leader, me.UserId, "still the party leader in the lobby")
	preview.fireServerAs(cal, "MatchAction", "StartRematch")
	step()
	eq(m.Round, round + 1, "the member still there runs the rematch")
end)


-- Public hunt queue (PLAY button / portal pads), docs: src/shared/HuntQueue.luau. Ava and Ben are in the lobby here.
local QueueConfig = C.shared("QueueConfig")
-- the park's own queue board (QueueBoard / QueueText) when the lobby has one, else a test board
local lobbyBoard = workspace:FindFirstChild("QueueBoard", true)
local lobbyText = lobbyBoard and lobbyBoard:FindFirstChild("QueueText", true)
local boardText: TextLabel
if lobbyText then
	boardText = lobbyText :: TextLabel
else
	local board = Instance.new("Part")
	board.Name = "QueueBoard"
	board.Anchored = true
	local gui = Instance.new("SurfaceGui")
	gui.Parent = board
	boardText = Instance.new("TextLabel")
	boardText.Name = "QueueText"
	boardText.Parent = gui
	board.Parent = workspace
end
local pad1 = Instance.new("Part")
pad1.Name = "QueuePad1"
pad1.Anchored = true
pad1:SetAttribute("HuntPortal", true)
pad1:SetAttribute("PadIndex", 1)
pad1.Material = Enum.Material.Plastic
pad1.Parent = workspace

case("public queue: board idle, two PLAY taps share one countdown and one hunt", function()
	step(0.5)
	eq(boardText.Text, QueueConfig.Board.Idle, "board idle")
	eq(MatchService.isBusy(ava.UserId), false)
	eq(MatchService.isBusy(ben.UserId), false)
	act(ava, "Queue")
	step(0.5)
	act(ben, "Queue")
	step(0.5)
	local q = PartyService.Queue.Queues[1]
	assert(q, "queue open")
	eq(#PartyService.Queue.Queues, 1, "one queue")
	assert(string.find(boardText.Text, "(2/4)", 1, true), "board counts: " .. boardText.Text)
	eq(pad1.Material, Enum.Material.Neon, "pad 1 lit")
	act(ava, "Queue") -- double tap: still one entry
	step(0.5)
	eq(#PartyService.Queue.Queues, 1)
	eq(MatchService.isBusy(ava.UserId), false, "no hunt before the timer")
	step(QueueConfig.Seconds)
	local m = MatchService.matchFor(ava.UserId)
	assert(m, "hunt started after the countdown")
	eq(MatchService.matchFor(ben.UserId), m, "same hunt")
	eq(#PartyService.Queue.Queues, 0, "queue emptied")
	step(0.5)
	eq(boardText.Text, QueueConfig.Board.Idle, "board idle again")
	eq(pad1.Material, Enum.Material.Plastic, "pad back to normal")
	preview.fireServerAs(ava, "MatchAction", "Return")
	preview.fireServerAs(ben, "MatchAction", "Return")
	step()
	eq(MatchService.isBusy(ava.UserId), false)
end)

case("public queue: a leaver mid-countdown is not taken; the other still hunts", function()
	step(1)
	act(ava, "Queue")
	act(ben, "Queue")
	step(5)
	act(ben, "Unqueue")
	step(1)
	eq(PartyService.Queue.Queues[1] and #PartyService.Queue.Queues[1].Groups, 1, "only Ava left queued")
	step(QueueConfig.Seconds)
	assert(MatchService.matchFor(ava.UserId), "Ava hunts alone")
	eq(MatchService.isBusy(ben.UserId), false, "Ben stayed in the lobby")
	preview.fireServerAs(ava, "MatchAction", "Return")
	step()
end)

case("public queue: LEAVE while standing on a pad does not re-join until the player steps off (audit F02)", function()
	step(1)
	pad1.Size = Vector3.new(8, 1, 8)
	pad1.CFrame = CFrame.new(500, 0, 500)
	C.place(ava, CFrame.new(500, 3, 500))
	step(0.5)
	local root = ava.Character and ava.Character:FindFirstChild("HumanoidRootPart")
	assert(root, "Ava has a body")
	local function queued(): boolean
		local q = PartyService.Queue.Queues[1]
		return q ~= nil and #q.Groups > 0
	end
	pad1.Touched:_fire(root)
	step(0.5)
	assert(queued(), "stepping on the pad queues")
	act(ava, "Unqueue")
	step(0.5)
	eq(queued(), false, "LEAVE takes her out")
	step(QueueConfig.TouchDebounce + 0.5)
	pad1.Touched:_fire(root) -- still standing there: the next step must not queue her again
	step(0.5)
	eq(queued(), false, "no re-join while still on the pad")
	act(ava, "Unqueue") -- a second LEAVE when already out does nothing
	step(0.5)
	C.place(ava, CFrame.new(540, 3, 500)) -- walks off
	step(0.6)
	C.place(ava, CFrame.new(500, 3, 500)) -- and back on
	step(QueueConfig.TouchDebounce + 0.5)
	pad1.Touched:_fire(root)
	step(0.5)
	assert(queued(), "stepping back on after walking off queues again")
	act(ava, "Unqueue")
	step(0.5)
	eq(queued(), false)
	C.place(ava, CFrame.new(0, 3, 0))
	step(1)
end)

case("public queue: a party member cannot queue the party; queueing while hunting is refused", function()
	step(1)
	act(ava, "Invite", ben.UserId)
	step()
	local pa = PartyService.of(ava.UserId)
	act(ben, "Accept", pa.Id)
	step()
	act(ben, "Queue")
	step()
	eq(#PartyService.Queue.Queues, 0, "member alone does not queue the party")
	act(ava, "Queue")
	step()
	local q = PartyService.Queue.Queues[1]
	assert(q and #q.Groups == 1 and #q.Groups[1].Members == 2, "whole party queued together")
	act(me, "Queue") -- still hunting
	step()
	eq(#PartyService.Queue.Queues[1].Groups, 1, "busy player not queued")
	step(QueueConfig.Seconds)
	local m = MatchService.matchFor(ava.UserId)
	assert(m and m.Party == pa, "the party hunts as itself")
	eq(MatchService.matchFor(ben.UserId), m)
end)

case("helpers' lucky common: granted as a bonus pet (no win, no find, no auto-follow)", function()
	-- me + Cal (one party) are still on the earlier hunt; back to the lobby, then the leader queues the party
	for _, p in { me, cal, ava, ben } do
		preview.fireServerAs(p, "MatchAction", "Return")
	end
	step(1)
	eq(MatchService.isBusy(me.UserId), false)
	local bonus = QueueConfig.Bonus
	local oldChance, oldMin = bonus.Chance, bonus.MinCracked
	bonus.Chance, bonus.MinCracked = 1, 0 -- force the roll for this case only
	local before = {}
	for _, p in { me, cal } do
		local d = Profiles.get(p)
		before[p.UserId] = { Pets = #d.InventoryGeodes, Wins = d.Stats.MultiplayerWins, Solo = d.Stats.SoloFinds, Eq = table.clone(d.EquippedPets or {}) }
	end
	local w = C.watchMatch()
	act(me, "Queue")
	step(QueueConfig.Seconds + 1)
	local m = MatchService.matchFor(me.UserId)
	assert(m, "party hunt from the queue")
	eq(MatchService.matchFor(cal.UserId), m)
	for _ = 1, 20 do
		if w.last.Init then
			break
		end
		step(0.1)
	end
	step(Config.Match.CountdownSeconds + 0.5)
	local ok = C.crackUntilFound(w, { me, cal }, 800)
	step(1)
	bonus.Chance, bonus.MinCracked = oldChance, oldMin
	assert(ok, "pet found")
	step(Config.Match.RevealSeconds + 1)
	local winner = m.Results and m.Results.Winner
	assert(winner, "results")
	local helper = if winner == me.UserId then cal else me
	local d = Profiles.get(helper)
	local b = before[helper.UserId]
	eq(#d.InventoryGeodes, b.Pets + 1, "helper got one pet")
	eq(d.InventoryGeodes[#d.InventoryGeodes].Rarity, "Common")
	eq(d.Stats.MultiplayerWins, b.Wins, "not a win")
	eq(d.Stats.SoloFinds, b.Solo, "not a find")
	eq(#(d.EquippedPets or {}), #b.Eq, "does not auto-follow")
	local row
	for _, r in m.Results.Members do
		if r.UserId == helper.UserId then
			row = r
		end
	end
	assert(row and type(row.BonusPet) == "string", "results row names the bonus pet")
	eq(m.Results.FriendLuck, 0, "party mates who are not Roblox friends give no friend bonus")
end)

case("friend bonus: +10% luck per Roblox friend in the server, at most 3 friends; a failed check counts none", function()
	local FB = C.server("FriendBonus")
	FB.setCheck(function()
		return true
	end)
	eq(FB.count(me), 4, "four friends in the server")
	eq(FB.luck(me), 0.3, "capped at three friends")
	FB.setCheck(function(a, b)
		return a == ava or b == ava
	end)
	eq(FB.luck(me), 0.1, "one friend")
	eq(FB.luck(ava), 0.3, "Ava is friends with everyone")
	FB.setCheck(function()
		error("Roblox friends service down (test)")
	end)
	eq(FB.luck(me), 0, "a failed check is not counted")
	eq(FB.luck(me, true), 0, "cached-only lookups never yield and count nothing unknown")
	FB.setCheck(function()
		return false
	end)
end)

print("PARTY DONE")
