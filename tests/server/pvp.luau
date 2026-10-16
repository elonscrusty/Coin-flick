-- Pet Battle + training through the real PvpService on the offline mock (run by tests/test_m10_server.luau).
-- Queue -> bot after BotAfter -> fight -> result saved; two players matched by power; leaving mid-fight forfeits;
-- SPECIAL / train taps / junk intents are rate-limited or refused.
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
	profile = function(data)
		data.TutorialStep = 1
		data.Onboard.Skipped = true
	end,
})
local me, ava, Profiles = s.me, s.others[1], s.Profiles
local PvpService = C.server("PvpService")
local PvpConfig = C.shared("PvpConfig")
local mine = Profiles.get(me)
local hers = Profiles.get(ava)
for _ = 1, 30 do
	if hers then
		break
	end
	preview.advance(0.2)
	hers = Profiles.get(ava)
end
-- both have the same three pets (new ids), so they match at once
local GeodeGen = C.shared("GeodeGen")
local base = mine.InventoryGeodes[1] or C.fakeSpecimens(1)[1]
local function copyPets(data, tag)
	data.InventoryGeodes = {}
	data.EquippedPets = {}
	for i = 1, 3 do
		local g = table.clone(base)
		g.Id = tag .. i
		g.Seed = 1000 + i
		table.insert(data.InventoryGeodes, g)
	end
end
local _ = GeodeGen
copyPets(mine, "me")
if hers then
	copyPets(hers, "ava")
	hers.TutorialStep = 1
end

local got: { [Player]: { any } } = { [me] = {}, [ava] = {} }
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
local function act(p, msg)
	PvpService.action(p, msg)
end
local function step(dt)
	preview.advance(dt or 0.25)
end
local function until_(fn, limit)
	local t = 0
	while not fn() and t < (limit or 90) do
		step(0.5)
		t += 0.5
	end
	return fn()
end

case("queue alone: a BOT steps in after BotAfter seconds, never sooner", function()
	act(me, { Op = "Queue" })
	step(0.5)
	assert(last(me, "Queued"), "queued message")
	step(PvpConfig.BotAfter - 2)
	eq(PvpService.fightOf(me), nil, "no fight before BotAfter")
	assert(until_(function()
		return PvpService.fightOf(me) ~= nil
	end, 5), "bot fight started")
	local start = last(me, "Start")
	assert(start, "Start sent")
	eq(start.Foe.Bot, true, "foe is a bot")
	eq(me:GetAttribute("InBattle"), true)
	eq(#start.Units, 6, "3 v 3")
end)

case("SPECIAL refused on an empty meter; junk intents ignored", function()
	local f = PvpService.fightOf(me)
	assert(f, "in a fight")
	act(me, { Op = "Special" })
	act(me, "junk")
	act(me, { Op = 5 })
	act(me, { Op = "SetTeam", Pets = { "me1" } }) -- no team edits mid-fight
	eq(f.Rules.Meters[1] >= 0, true)
end)

case("tap to fight: TAP counts at most Tap.PerSecond, BLOCK answers at once", function()
	local f = PvpService.fightOf(me)
	assert(f, "in a fight")
	assert(until_(function()
		return f.Phase == "Fighting"
	end, PvpConfig.CountIn + 2), "fighting")
	local hp = 0
	for _, u in f.Rules.Units do
		if u.Side == 2 then
			hp += u.Hp
		end
	end
	act(me, { Op = "Tap" })
	act(me, { Op = "Tap" }) -- same instant: dropped
	eq(f.Rules.Combo[1], 1, "one tap counted")
	local after = 0
	for _, u in f.Rules.Units do
		if u.Side == 2 then
			after += u.Hp
		end
	end
	assert(after < hp, "the tap hurt the rival team")
	preview.advance(1 / PvpConfig.Tap.PerSecond)
	act(me, { Op = "Tap" })
	eq(f.Rules.Combo[1], 2, "a tap in time grows the combo")
	got[me] = {}
	act(me, { Op = "Block" })
	local ev = last(me, "Events")
	assert(ev, "BLOCK answered at once")
	local answered = false
	for _, e in ev.List do
		if e.Kind == "Blocked" or e.Kind == "BlockMiss" then
			answered = true
		end
	end
	assert(answered, "Blocked or BlockMiss sent")
end)

case("bot fight ends: result paid once, trophies and streak saved, XP to the team, back to the lobby", function()
	local cash = tonumber(mine.Cash) or 0
	assert(until_(function()
		return last(me, "Result") ~= nil
	end, 90), "result arrived")
	local r = last(me, "Result")
	eq(me:GetAttribute("InBattle"), nil, "left the arena")
	eq(PvpService.fightOf(me), nil)
	eq(mine.Pvp.Wins + mine.Pvp.Losses <= 1, true)
	eq((tonumber(mine.Cash) or 0) - cash, r.Coins, "coins paid once")
	eq(mine.Pvp.Trophies, math.max(r.TrophyChange, 0), "trophies saved")
	eq(mine.TowerXP["me1"] >= r.Xp, true, "team pet earned XP")
	if r.Result == "Win" then
		eq(mine.Pvp.Streak, 1)
	end
end)

case("two players of equal power are matched at once (no bot)", function()
	got[me], got[ava] = {}, {}
	step(PvpConfig.QueueGap + 0.1)
	act(me, { Op = "Queue" })
	act(ava, { Op = "Queue" })
	step(1)
	local a, b = PvpService.fightOf(me), PvpService.fightOf(ava)
	assert(a ~= nil and a == b, "same fight")
	eq(last(me, "Start").Foe.Bot, false)
	eq(last(ava, "Start").MySide, 2)
end)

case("leaving mid-fight: the leaver loses, the other wins", function()
	step(PvpConfig.CountIn + PvpConfig.ForfeitWinAfter + 1)
	local wins = mine.Pvp.Wins
	local fightWins = mine.EggPerks.FightWins
	act(ava, { Op = "Leave" })
	step(0.5)
	eq(ava:GetAttribute("InBattle"), nil, "leaver is out")
	eq(last(ava, "Result").Result, "Loss")
	assert(until_(function()
		return last(me, "Result") ~= nil
	end, 15), "winner result")
	eq(last(me, "Result").Result, "Win")
	eq(mine.Pvp.Wins, wins + 1)
	eq(mine.EggPerks.FightWins, fightWins + 1, "the win counts toward a free egg (EggPerks)")
	eq(PvpService.fightOf(me), nil)
end)

case("a rival who quits in the count-in gives a draw, not a win (no win-feeding with a second account)", function()
	got[me], got[ava] = {}, {}
	step(PvpConfig.QueueGap + 0.1)
	act(me, { Op = "Queue" })
	act(ava, { Op = "Queue" })
	step(1)
	assert(PvpService.fightOf(me) ~= nil and PvpService.fightOf(me) == PvpService.fightOf(ava), "matched again")
	local wins, trophies, fightWins = mine.Pvp.Wins, mine.Pvp.Trophies, mine.EggPerks.FightWins
	act(ava, { Op = "Leave" })
	step(0.5)
	eq(last(ava, "Result").Result, "Loss", "the quitter still loses")
	assert(until_(function()
		return last(me, "Result") ~= nil
	end, 15), "stayer result")
	eq(last(me, "Result").Result, "Draw")
	eq(mine.Pvp.Wins, wins, "no win")
	eq(mine.Pvp.Trophies, trophies, "no trophies")
	eq(mine.EggPerks.FightWins, fightWins, "no free-egg progress")
	eq(PvpService.fightOf(me), nil)
end)

case("two players far apart in power still get each other, not two bots (Studio regression)", function()
	got[me], got[ava] = {}, {}
	local saved = table.clone(hers.TowerXP)
	for id in hers.TowerXP do
		hers.TowerXP[id] = 1e7 -- a maxed team (Studio tester used /maxpet)
	end
	for _, id in hers.EquippedPets do
		hers.TowerXP[id] = 1e7
	end
	step(PvpConfig.QueueGap + 0.1)
	act(me, { Op = "Queue" })
	step(3)
	act(ava, { Op = "Queue" })
	assert(until_(function()
		return PvpService.fightOf(me) ~= nil
	end, PvpConfig.BotAfter + 2), "a fight starts")
	local a, b = PvpService.fightOf(me), PvpService.fightOf(ava)
	assert(a ~= nil and a == b, "the two players fight each other")
	eq(last(me, "Start").Foe.Bot, false, "no bot")
	act(ava, { Op = "Leave" })
	step(0.5)
	assert(until_(function()
		return PvpService.fightOf(me) == nil
	end, 15), "fight closed")
	hers.TowerXP = saved
end)

-- Studio 2-player test: two friends queued a few seconds apart and EACH got a bot. Every gap below BotAfter, both
-- orders, equal and far-apart power: the two real players always fight each other and no bot ever steps in.
case("friend fight matrix: two players queued 0..BotAfter-1 s apart, any order or power, always fight each other", function()
	local savedXp = table.clone(hers.TowerXP)
	-- fights pay prizes (free eggs, pets); put both inventories back so later cases see their own setup
	local myInv, herInv = table.clone(mine.InventoryGeodes), table.clone(hers.InventoryGeodes)
	local gaps = { 0, 0.5, 2, 3, 5, 8, 11, PvpConfig.BotAfter - 1 }
	for _, maxed in { false, true } do
		hers.TowerXP = table.clone(savedXp)
		for _, g in hers.InventoryGeodes do
			g.Rarity = if maxed then "Legendary" else base.Rarity
			g.Evolve = if maxed then 2 else nil
			if maxed then
				hers.TowerXP[g.Id] = 1e7
			end
		end
		if maxed then
			-- the gap must be wider than the matching window ever gets before BotAfter, or this case proves nothing
			local PvpRules = C.shared("PvpRules")
			local function power(data)
				local sum = 0
				for _, g in data.InventoryGeodes do
					sum += PvpRules.power(g, data.TowerXP[g.Id])
				end
				return sum
			end
			local pa, pb = power(mine), power(hers)
			local gapShare = math.abs(pa - pb) / math.max(pa, pb)
			assert(gapShare > PvpRules.window(PvpConfig.BotAfter), "rival far stronger than any window: " .. gapShare)
		end
		for _, herFirst in { false, true } do
			for _, gap in gaps do
				local tag = string.format("gap %.1f s, %s first, %s", gap, if herFirst then "Ava" else "me", if maxed then "maxed rival" else "equal")
				got[me], got[ava] = {}, {}
				step(PvpConfig.QueueGap + 0.1)
				local first, second = if herFirst then ava else me, if herFirst then me else ava
				act(first, { Op = "Queue" })
				if gap > 0 then
					step(gap)
				end
				act(second, { Op = "Queue" })
				assert(until_(function()
					return PvpService.fightOf(me) ~= nil or PvpService.fightOf(ava) ~= nil
				end, PvpConfig.BotAfter + 2), "a fight starts (" .. tag .. ")")
				step(0.6) -- one more matchmaking pass: a second bot fight would start here
				local a, b = PvpService.fightOf(me), PvpService.fightOf(ava)
				assert(a ~= nil and a == b, "the two players fight each other (" .. tag .. ")")
				eq(a.BotSide, nil, "no bot side (" .. tag .. ")")
				act(second, { Op = "Leave" })
				assert(until_(function()
					return PvpService.fightOf(me) == nil and PvpService.fightOf(ava) == nil
				end, 15), "fight closed (" .. tag .. ")")
			end
		end
	end
	hers.TowerXP = savedXp
	mine.InventoryGeodes, hers.InventoryGeodes = myInv, herInv
	for _, g in hers.InventoryGeodes do
		g.Rarity = base.Rarity
		g.Evolve = nil
	end
end)

case("train taps: at most TapsPerSecond count; XP and power go up", function()
	got[me] = {}
	local before = mine.TowerXP["me2"] or 0
	for _ = 1, 30 do
		act(me, { Op = "Train", Pet = "me2" })
	end
	eq((mine.TowerXP["me2"] or 0) - before, PvpConfig.Train.TapsPerSecond * PvpConfig.Train.TapXp, "burst capped")
	step(1)
	act(me, { Op = "Train", Pet = "me2" })
	eq((mine.TowerXP["me2"] or 0) - before, (PvpConfig.Train.TapsPerSecond + 1) * PvpConfig.Train.TapXp, "refills over time")
	act(me, { Op = "Train", Pet = "not-mine" })
	act(me, { Op = "Train", Pet = { "x" } })
	local t = last(me, "Trained")
	assert(t and t.Power > 0, "power shown")
end)

case("train taps: a full Pet Book page gives +10% XP (EggPerks)", function()
	local EggPerks = C.shared("EggPerks")
	local saved = mine.DiscoveryIndex
	local index = {}
	for _, id in EggPerks.pageSpecies("Gravel") do
		index[id] = 1
	end
	mine.DiscoveryIndex = index
	step(2)
	got[me] = {}
	local before = mine.TowerXP["me2"] or 0
	act(me, { Op = "Train", Pet = "me2" })
	local want = math.floor(PvpConfig.Train.TapXp * 1.1 + 0.5)
	eq((mine.TowerXP["me2"] or 0) - before, want, "tap XP with the page bonus")
	local t = last(me, "Trained")
	assert(t and (t.Maxed or t.Gain == want), "the card shows the real gain")
	mine.DiscoveryIndex = saved
end)

case("battle search exits: one Unqueued per real exit, each with a reason; never a silent drop (audit F24)", function()
	local PvpRules = C.shared("PvpRules")
	local function count(p, kind)
		local n = 0
		for _, m in got[p] or {} do
			if m.Kind == kind then
				n += 1
			end
		end
		return n
	end
	step(PvpConfig.QueueGap + 0.1)
	got[me] = {}
	act(me, { Op = "Queue" })
	step(0.5)
	assert(last(me, "Queued"), "queued")
	act(me, { Op = "Cancel" })
	step(0.4)
	act(me, { Op = "Cancel" }) -- already out: nothing more
	step(0.4)
	eq(count(me, "Unqueued"), 1, "one exit, one message")
	eq(last(me, "Unqueued").Why, "Cancel")
	assert(PvpRules.unqueueText("Cancel"), "cancel has a line")
	-- the team goes away mid-search (all pets sold): the search ends with a reason instead of counting forever
	step(PvpConfig.QueueGap + 0.1)
	got[me] = {}
	act(me, { Op = "Queue" })
	step(0.5)
	assert(last(me, "Queued"), "queued again")
	local saved = mine.InventoryGeodes
	mine.InventoryGeodes = {}
	step(1)
	local u = last(me, "Unqueued")
	assert(u, "told the search ended")
	eq(u.Why, "NoTeam")
	assert(PvpRules.unqueueText(u.Why), "NoTeam has a line")
	eq(PvpService.fightOf(me), nil, "no fight")
	mine.InventoryGeodes = saved
	-- walking around while searching keeps the search (no exit message) until the bot steps in
	step(PvpConfig.QueueGap + 0.1)
	got[me] = {}
	act(me, { Op = "Queue" })
	C.place(me, CFrame.new(300, 3, -300))
	assert(until_(function()
		return PvpService.fightOf(me) ~= nil
	end, PvpConfig.BotAfter + 3), "still searching after walking away: the bot fight starts")
	eq(count(me, "Unqueued"), 0, "walking never ends the search")
	act(me, { Op = "Leave" })
	assert(until_(function()
		return PvpService.fightOf(me) == nil
	end, 15), "left the fight")
end)

case("cannot queue while in a hunt", function()
	step(PvpConfig.QueueGap + 0.1)
	me:SetAttribute("MatchKey", "test")
	act(me, { Op = "Queue" })
	step(16)
	eq(PvpService.fightOf(me), nil)
	me:SetAttribute("MatchKey", nil)
end)

case("sky islands: each fight on its own floating island, fighters moved there and back, nobody watches", function()
	got[me], got[ava] = {}, {}
	local SkyIsland = C.server("SkyIsland")
	local FightBoard = C.server("FightBoard")
	FightBoard.ensure(CFrame.new(0, 5, 60)) -- the lobby board (over the BATTLE pad in the real lobby)
	local before = SkyIsland.count()
	local home = CFrame.new(410, 3, 400)
	C.place(me, home)
	C.place(ava, CFrame.new(412, 3, 400)) -- right next to the fighter: still never sees the fight
	step(PvpConfig.QueueGap + 0.1)
	act(me, { Op = "Queue" })
	assert(until_(function()
		return PvpService.fightOf(me) ~= nil
	end, PvpConfig.BotAfter + 3), "bot fight")
	local f = PvpService.fightOf(me)
	eq(SkyIsland.count(), before + 1, "an island for the fight")
	assert(f.Arena and f.Arena.Parent, "island model in the world")
	assert(f.Origin.Position.Y > 300 and f.Origin.Position.Magnitude > 2000, "up in the sky, far from the lobby")
	eq(f.Layout, PvpConfig.Layouts.LiveBig, "stadium-size layout on the island")
	local root = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
	if root then
		local L0 = PvpConfig.Layouts.LiveBig
		local mark = f.Views[1] * Vector3.new(L0.StandX or 0, 0, L0.StandZ)
		local d = (root.Position - mark) * Vector3.new(1, 0, 1)
		assert(d.Magnitude < 1, "fighter teleported to their mark on the island: " .. d.Magnitude)
		-- falls off: put back on the mark
		root.CFrame = root.CFrame + Vector3.new(0, -200, 0)
		step(1)
		d = (root.Position - mark) * Vector3.new(1, 0, 1)
		assert(d.Magnitude < 1 and root.Position.Y > f.Origin.Position.Y, "a fall puts the fighter back on the island")
	end
	-- each side sees the fight from its own end: the two views stand at opposite ends of the arena axis
	local L = PvpConfig.Layouts.LiveBig
	local mine1 = f.Views[1] * Vector3.new(0, 0, L.PetZ)
	local mine2 = f.Views[2] * Vector3.new(0, 0, L.PetZ)
	assert((mine1 - mine2).Magnitude > L.FoeZ - L.PetZ - 0.1, "side 2's own pets are the rival line of side 1")
	assert(((f.Views[1] * Vector3.new(0, 0, L.FoeZ)) - mine2).Magnitude < 0.01, "and the lines match up")
	local board = workspace:FindFirstChild("FightBoard")
	assert(board, "lobby board built")
	local livePart = board:FindFirstChild("Live")
	local live = livePart and livePart:FindFirstChild("Text", true)
	assert(live and string.find(live.Text, " vs ", 1, true), "board shows the fight going on: " .. tostring(live and live.Text))
	step(PvpConfig.CountIn + 2)
	eq(last(ava, "Watch"), nil, "no spectating")
	eq(last(ava, "WatchEvents"), nil, "no spectating")
	-- a second fight at the same time: its own island, far from the first
	act(ava, { Op = "Queue" })
	assert(until_(function()
		return PvpService.fightOf(ava) ~= nil
	end, PvpConfig.BotAfter + 3), "second fight")
	local g = PvpService.fightOf(ava)
	assert(g ~= f and g.Arena ~= f.Arena, "own island")
	assert((g.Origin.Position - f.Origin.Position).Magnitude >= PvpConfig.Island.Spacing - 1, "islands far apart")
	eq(SkyIsland.count(), before + 2)
	assert(until_(function()
		return last(me, "Result") ~= nil
	end, 90), "first fight ends")
	eq(f.Arena.Parent, nil, "its island is gone")
	if root then
		assert((root.Position - home.Position).Magnitude < 6, "the fighter is back in the lobby: " .. tostring(root.Position))
	end
	act(ava, { Op = "Leave" })
	assert(until_(function()
		return SkyIsland.count() == before
	end, 15), "every island freed")
	assert(string.find(live.Text, "Tap BATTLE", 1, true), "board idle after the fights: " .. live.Text)
	if last(me, "Result").Result == "Win" then
		assert(FightBoard.best() ~= nil, "a player win is on the board")
	end
end)

case("hunt XP: each egg cracked gives every following pet XP", function()
	local RockService = C.server("RockService")
	assert(RockService.onCracked, "PvpService hooked RockService")
	mine.EquippedPets = { "me2" }
	local before = mine.TowerXP["me2"] or 0
	RockService.onCracked(me, false)
	RockService.onCracked(me, true)
	eq((mine.TowerXP["me2"] or 0) - before, PvpConfig.Hunt.CrackXp + PvpConfig.Hunt.FoundXp)
	mine.EquippedPets = {}
end)

case("evolve is OFF (carter 2026-10-16): no evolve offer, the server refuses, nothing used", function()
	local TC = C.shared("TowerConfig")
	eq(TC.Evolve.Enabled, false)
	got[me] = {}
	step(1.1)
	mine.TowerXP["me1"] = 1e7
	mine.EquippedPets = {}
	local count = #mine.InventoryGeodes
	act(me, { Op = "Evolve", Pet = "me1" })
	step(0.2)
	eq(last(me, "Evolved"), nil, "no evolve")
	eq(#mine.InventoryGeodes, count, "no copies used")
	local _, g = Profiles.findGeode(mine, "me1")
	eq(g.Evolve or 0, 0)
end)

case("evolve (when switched back on): a maxed pet uses up 2 free copies and steps up a stage; refused when copies are kept safe", function()
	local TC = C.shared("TowerConfig")
	TC.Evolve.Enabled = true
	got[me] = {}
	step(1.1)
	mine.TowerXP["me1"] = 1e7
	mine.EquippedPets = { "me2" } -- following: never used up
	act(me, { Op = "Evolve", Pet = "me1" })
	eq(last(me, "Evolved").Ok, false)
	eq(last(me, "Evolved").Why, "Copies")
	eq(#mine.InventoryGeodes, 3, "nothing used")
	mine.EquippedPets = {}
	step(1.1)
	local count = #mine.InventoryGeodes
	act(me, { Op = "Evolve", Pet = "me1" })
	local ev = last(me, "Evolved")
	eq(ev.Ok, true)
	eq(ev.Stage, 1)
	assert(ev.Power > ev.PowerBefore, "stronger")
	eq(#mine.InventoryGeodes, count - 2, "two copies used up")
	local _, g = Profiles.findGeode(mine, "me1")
	eq(g.Evolve, 1)
	eq(mine.TowerXP["me2"], nil, "used copies' XP gone")
	act(me, { Op = "Evolve", Pet = "me1" }) -- too soon and no copies left
	eq(g.Evolve, 1)
	TC.Evolve.Enabled = false
end)

case("inspect: only a pet the other player has following them; card carries power and level", function()
	local Net = C.shared("Net")
	local cards = {}
	Net.event("Inspect").OnClientEvent:Connect(function(card)
		table.insert(cards, card)
	end)
	hers.EquippedPets = { "ava1" }
	step(1)
	act(me, { Op = "Inspect", UserId = ava.UserId, Pet = "ava2" }) -- not following her: nothing
	step(0.2)
	eq(#cards, 0, "private pet not shown")
	step(1)
	act(me, { Op = "Inspect", UserId = ava.UserId, Pet = "ava1" })
	step(0.2)
	eq(#cards, 1)
	assert(cards[1].Power > 0 and cards[1].Level >= 1, "power and level")
	eq(cards[1].Specimen.Id, "ava1")
	act(me, { Op = "Inspect", UserId = ava.UserId, Pet = "ava1" }) -- too fast
	act(me, { Op = "Inspect", UserId = "x", Pet = 4 })
	step(0.2)
	eq(#cards, 1, "rate limited")
	hers.EquippedPets = {}
end)

case("tower: a new theme's first wave waits TitleHold before the first hit (no title pill over the fight)", function()
	local TowerConfig = C.shared("TowerConfig")
	local TowerService = C.server("TowerService")
	local ev = game:GetService("ReplicatedStorage"):WaitForChild("TowerNet"):WaitForChild("TowerEvent")
	local floorAt, hitAt, floorMsg = nil, nil, nil
	local clock = 0
	local conn = ev.OnClientEvent:Connect(function(msg)
		if type(msg) ~= "table" then
			return
		end
		if msg.Kind == "Floor" and not floorAt then
			floorAt, floorMsg = clock, msg
		elseif msg.Kind == "Events" and floorAt and not hitAt then
			for _, e in msg.List or {} do
				if e.Kind == "Hit" then
					hitAt = clock
				end
			end
		end
	end)
	mine.EquippedPets = {}
	local act0 = game:GetService("ReplicatedStorage").TowerNet.TowerAction
	act0:FireServer({ Op = "Start" })
	for _ = 1, 200 do
		if hitAt then
			break
		end
		step(0.1)
		clock += 0.1
	end
	conn:Disconnect()
	assert(floorMsg, "floor 1 started")
	eq(floorMsg.Floor, 1)
	assert(hitAt, "the pets fight after the hold")
	-- TowerFx.titleCard holds 1.6 s and fades 0.3 s: no hit may land while it is on screen
	assert(hitAt - floorAt >= 1.9, "no hit before the title is gone: " .. tostring(hitAt - floorAt))
	act0:FireServer({ Op = "Leave" })
	step(1)
	local _ = TowerService
end)

case("max level: a maxed team pet's XP goes to its teammates; off-team and raw XP unchanged", function()
	local TowerService = C.server("TowerService")
	local PetStats = C.shared("PetStats")
	local EggPerks = C.shared("EggPerks")
	local saveTeam, saveXp, saveInv = mine.EquippedPets, mine.TowerXP, mine.InventoryGeodes
	copyPets(mine, "me")
	local g1 = mine.InventoryGeodes[1]
	local full = PetStats.xpForLevel(PetStats.cap(g1))
	mine.EquippedPets = { "me1", "me2" }
	mine.TowerXP = { me1 = full, me2 = 0, me3 = 0 }
	local want = math.floor(100 * EggPerks.xpMult(mine.DiscoveryIndex) + 0.5)
	TowerService.addXp(me, "me1", 100)
	eq(TowerService.xpOf(me, "me1"), full, "maxed pet stays at its cap")
	eq(TowerService.xpOf(me, "me2"), want, "teammate gets the spare XP")
	eq(TowerService.xpOf(me, "me3"), 0, "pet off the team gets nothing")
	TowerService.addXp(me, "me3", 100) -- off the team: the old rule
	eq(TowerService.xpOf(me, "me3"), want)
	TowerService.addXp(me, "me1", 7, true) -- dev /xp: exact, no spill
	eq(TowerService.xpOf(me, "me1"), full + 7)
	mine.EquippedPets, mine.TowerXP, mine.InventoryGeodes = saveTeam, saveXp, saveInv
end)

print("PVP DONE")
