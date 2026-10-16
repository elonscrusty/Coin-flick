-- Lobby hangout server checks (run by tests/test_hangout_server.luau) through the REAL modules on the offline mock:
-- hidden eggs, lookout, sit spots, whack-a-rock, the removed pet race and egg toss, the three hourly events, daily plot likes with
-- the crown and glow, and the group gift.
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
local Hangout = C.shared("Hangout")
local LH = C.server("LobbyHangout")
local Games = C.server("LobbyGames")
local Events = C.server("LobbyEvents")
local Gallery = C.server("GalleryService")
local data = Profiles.get(me)
local pps = game:GetService("ProximityPromptService")
local function step(dt: number?)
	preview.advance(dt or 0.2)
end
local root = me.Character:FindFirstChild("HumanoidRootPart") :: BasePart
local base = root.Position

-- a little hook map next to the player
local map = Instance.new("Folder")
map.Name = "HangoutTestMap"
local function part(name: string, offset: Vector3, parent: Instance?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = Vector3.new(2, 1, 2)
	p.Position = base + offset
	p.Parent = parent or map
	return p
end
part("HiddenEgg1", Vector3.new(3, 0, 0))
local far = part("HiddenEgg2", Vector3.new(200, 0, 0))
part("LookoutChest", Vector3.new(0, 0, 3))
part("Bench1", Vector3.new(-3, 0, 0))
local stump = Instance.new("Model")
stump.Name = "WhackStump"
part("Top", Vector3.new(0, 0, -5), stump)
stump.Parent = map
local toss = Instance.new("Model")
toss.Name = "EggToss"
part("ThrowSpot", Vector3.new(5, 0, 5), toss)
part("Target", Vector3.new(5, 0, 25), toss)
toss.Parent = map
local track = Instance.new("Model")
track.Name = "RaceTrack"
part("RaceStart", Vector3.new(-5, 0, 5), track)
track.Parent = map
map.Parent = workspace
LH.adopt(map)
Games.adopt(map)

local function promptOn(p: Instance): ProximityPrompt
	return p:FindFirstChildWhichIsA("ProximityPrompt", true) :: ProximityPrompt
end
local function trigger(p: Instance, who: Player?)
	pps.PromptTriggered:_fire(promptOn(p), who or me)
	step(0.3)
end

case("hidden egg: coins once, refused out of range", function()
	local cash = data.Cash
	trigger(map.HiddenEgg1)
	eq(data.Cash, cash + Hangout.Secrets.Coins, "first find pays")
	trigger(map.HiddenEgg1)
	eq(data.Cash, cash + Hangout.Secrets.Coins, "second time pays nothing")
	trigger(far)
	eq(data.Hangout.Secrets.HiddenEgg2, nil, "far egg not taken")
	-- the client is told which eggs to hide for this player (audit F25)
	eq(me:GetAttribute(Hangout.Secrets.FoundAttr), "HiddenEgg1", "found egg published to the player")
	for _ = 1, 5 do
		trigger(map.HiddenEgg1) -- tap spam after the find
	end
	eq(data.Cash, cash + Hangout.Secrets.Coins, "tap spam pays nothing more")
end)

case("lookout chest: coins once per day", function()
	local cash = data.Cash
	trigger(map.LookoutChest)
	eq(data.Cash, cash + Hangout.Secrets.LookoutCoins)
	trigger(map.LookoutChest)
	eq(data.Cash, cash + Hangout.Secrets.LookoutCoins, "again today pays nothing")
end)

case("sit spot: a bench gets a seat with a Sit prompt", function()
	local seat = map.Bench1:FindFirstChild("HangoutSeat")
	assert(seat and seat:IsA("Seat"), "seat made")
	local pp = promptOn(seat)
	assert(pp and pp.ActionText == "Sit" and pp:GetAttribute("Hangout") == "Sit")
end)

case("whack-a-rock: only the player's rock taps count; prize paid at the end", function()
	local cash, cap = data.Cash, data.Hangout.GameCoins
	trigger(stump.Top)
	local hits = 0
	for _ = 1, 8 do
		local rock = Games.whackRock()
		if rock then
			local cd = rock:FindFirstChildWhichIsA("ClickDetector")
			cd.MouseClick:_fire(ava) -- not ava's game
			step(0.05)
			assert(Games.whackRock() == rock, "another player's tap does nothing")
			cd.MouseClick:_fire(me)
			hits += 1
		end
		step(0.5)
	end
	assert(hits >= 4, "rocks kept popping up: " .. hits)
	step(Hangout.Games.Whack.Seconds + 2)
	eq(data.Cash, cash + Hangout.whackPrize(hits), "prize")
	eq(data.Hangout.GameCoins, cap + Hangout.whackPrize(hits), "counted in the daily cap")
end)

case("pet race and egg toss removed: leftover RaceTrack / EggToss cleared, no race remote", function()
	eq(track.Parent, nil, "the old race track is removed from the lobby")
	eq(toss.Parent, nil, "the old egg toss is removed from the lobby")
	eq(Hangout.Games.Toss, nil, "no toss tuning left")
	eq(Hangout.Games.Race, nil, "no race tuning left")
	eq(game:GetService("ReplicatedStorage"):FindFirstChild("HangoutAction", true), nil, "no race tap remote")
end)

case("coin rain: a coin pays once, up to the per-player cap", function()
	data.Hangout.GameCoins = 0
	assert(Events.run("CoinRain"))
	assert(not Events.run("GoldenRock"), "one event at a time")
	step(2)
	local cur = Events.current()
	local coin
	for _, p in cur.Parts do
		if p.Name == "RainCoin" then
			coin = p
		end
	end
	assert(coin, "coins falling")
	local cash = data.Cash
	eq(Events.collect(me, coin), Hangout.Events.CoinRain.CoinValue)
	eq(Events.collect(ava, coin), 0, "taken coin pays nothing")
	eq(data.Cash, cash + Hangout.Events.CoinRain.CoinValue)
	step(Hangout.Events.CoinRain.Seconds + 4)
	eq(Events.current(), nil, "rain over")
end)

case("golden rock: everyone who hit it gets the prize when it cracks", function()
	assert(Events.run("GoldenRock"))
	step(0.5)
	local need = Hangout.rockHits(#game:GetService("Players"):GetPlayers())
	local cashMe, cashAva = data.Cash, Profiles.get(ava).Cash
	assert(Events.hitRock(ava))
	assert(not Events.hitRock(ava), "too fast")
	for _ = 1, need - 1 do
		step(Hangout.Events.GoldenRock.HitGap + 0.01)
		Events.hitRock(me)
	end
	eq(Events.current(), nil, "cracked")
	eq(data.Cash, cashMe + Hangout.Events.GoldenRock.Prize)
	eq(Profiles.get(ava).Cash, cashAva + Hangout.Events.GoldenRock.Prize)
end)

case("mystery egg: the first opener gets a pet, nobody else", function()
	local gifts = {}
	Events.setGift(function(p, egg, key)
		table.insert(gifts, { p, egg, key })
		return { Id = "pet" }
	end)
	assert(Events.run("MysteryEgg"))
	step(0.5)
	assert(Events.openEgg(ava))
	assert(not Events.openEgg(me), "already opened")
	eq(#gifts, 1)
	eq(gifts[1][1], ava)
	eq(gifts[1][2], Hangout.Events.MysteryEgg.Egg)
end)

case("plot likes: saved per day, crown and glow on the top plot", function()
	local plotIdx = me:GetAttribute("Plot")
	local pp
	for _, d in workspace:GetDescendants() do
		if d:IsA("ProximityPrompt") and d:GetAttribute("LikePlot") == plotIdx then
			pp = d
		end
	end
	assert(pp, "my plot's like prompt")
	local at = if pp.Parent:IsA("BasePart") then pp.Parent.Position else pp.Parent.WorldPosition
	C.place(ava, CFrame.new(at + Vector3.new(0, 0, 2)))
	step(0.6)
	pps.PromptTriggered:_fire(pp, ava)
	step(0.6)
	eq(data.Hangout.LikesToday, 1, "saved in my profile")
	eq(Gallery.crownOwner(), me.UserId, "crown on my plot")
	local glow = workspace:FindFirstChild("CT_TopPlotGlow", true)
	assert(glow and glow:IsA("Highlight"), "gold glow on the top plot")
	pps.PromptTriggered:_fire(pp, ava)
	step(0.6)
	eq(data.Hangout.LikesToday, 1, "a second like today does not count")
end)

case("group reward (merged): one free pet ever + daily coins once a day + luck flag, off without an id", function()
	local gifts = 0
	local Retention = C.shared("Retention")
	local cashBefore = data.Cash
	data.Retention = Retention.sanitize(data.Retention)
	data.Retention.GroupDay = 0
	LH.setGift(function()
		gifts += 1
		return { Id = "g" }
	end)
	LH.setGroupCheck(function()
		return { { Id = 77 } }
	end)
	LH.checkGroup(me)
	eq(gifts, 0, "off while the id is 0")
	C.shared("Retention").Group.Id = 77
	LH.checkGroup(me)
	eq(gifts, 1)
	eq(data.Hangout.GroupGift, true)
	eq(me:GetAttribute("GroupMember"), true)
	eq(data.Cash, cashBefore + Retention.Group.Coins, "daily group coins paid once")
	LH.checkGroup(me)
	eq(gifts, 1, "pet never twice")
	eq(data.Cash, cashBefore + Retention.Group.Coins, "coins not twice the same day")
	C.shared("Retention").Group.Id = 0
end)

case("book sign: skipped over a hidden ShopBook, built over a visible one", function()
	local MapHooks = C.server("MapHooks")
	local function try(transparency: number): boolean
		local m = Instance.new("Model")
		local shop = Instance.new("Model")
		shop.Name = "ShopBook"
		local p = Instance.new("Part")
		p.Anchored = true
		p.Size = Vector3.new(8, 4, 6)
		p.Position = Vector3.new(300, 2, 300)
		p.Transparency = transparency
		p.Parent = shop
		shop.Parent = m
		m.Parent = workspace
		local lobby = Instance.new("Folder")
		lobby.Parent = workspace
		MapHooks.ensureBookSign(m, lobby)
		local made = lobby:FindFirstChild("BookSign", true) ~= nil
		m:Destroy()
		lobby:Destroy()
		return made
	end
	eq(try(1), false, "hidden ShopBook: no sign in front of the Void Dragon")
	eq(try(0), true, "visible ShopBook keeps its sign")
end)

case("leaderboard tree: top pets by POWER on the branches, signs, BATTLE pad, saved cards", function()
	local Tree = C.server("TreeBoardService")
	local TB = C.shared("TreeBoard")
	local LB = C.server("LeaderboardService")
	local folder = Instance.new("Folder")
	folder.Name = "TreeTestMap"
	local spot = Instance.new("Part")
	spot.Name = "LeaderboardTreeSpot"
	spot.Anchored = true
	spot.Size = Vector3.new(20, 1, 20)
	spot.Position = Vector3.new(-300, 0, -300)
	spot.Parent = folder
	folder.Parent = workspace
	local saved, offline = {}, nil
	local GeodeGen = C.shared("GeodeGen")
	data.InventoryGeodes = C.fakeSpecimens(2)
	Profiles.changed(me)
	local specs = C.fakeSpecimens(1)
	offline = TB.card(specs[1], 777)
	Tree.setStore(function(uid)
		if uid == 4242 then
			return offline
		end
		return nil
	end, function(uid, card)
		saved[uid] = card
	end)
	TB.Config.Enabled = true -- the lobby has no tree now (off by config); the service itself still works
	Tree.start({ folder })
	TB.Config.Enabled = false
	local t, branches = Tree.tree()
	assert(t and #branches >= 3, "stand-in tree with branches")
	local pad = t:FindFirstChild("BattlePad", true)
	assert(pad and pad:GetAttribute("PvpPad") == true, "BATTLE pad")
	-- the Void Dragon perches on top of the tree: one statue, no plinth, standing at the perch
	local perch = t:FindFirstChild("DragonPerch", true) :: Attachment
	assert(perch, "stand-in tree has a DragonPerch")
	local top = spot.Position + Vector3.new(0, spot.Size.Y / 2, 0)
	local rel = perch.WorldPosition - top
	assert(math.abs(rel.X) < 1 and math.abs(rel.Z) < 1 and rel.Y > 40, "the perch is on the top of the tree, over the spot")
	for _, b in branches do
		local d = b.Position - top
		assert(Vector2.new(d.X, d.Z).Magnitude < 30 and d.Y > 10, "branches hug the tree")
	end
	local statues = 0
	for _, d in workspace:GetDescendants() do
		if d.Name == "VoidDragonStatue" then
			statues += 1
		end
	end
	eq(statues, 1, "one Void Dragon statue")
	local statue = folder:FindFirstChild("VoidDragonStatue") :: Model
	assert(statue and statue:FindFirstChild("Plinth") == nil, "statue on the tree, no plinth")
	local dragon = statue:FindFirstChild("Dragon") :: Model
	assert(dragon and (dragon:GetPivot().Position - perch.WorldPosition).Magnitude < 1, "dragon stands on the perch")
	assert(Tree.noteChange(me), "my card saved")
	local _, myPower = TB.bestPet(data)
	eq(saved[me.UserId].Power, myPower)
	assert(not Tree.noteChange(me), "unchanged card not saved again")
	-- the Power board: me, an offline player with a card, one with no card
	local Config = C.shared("Config")
	local ods = game:GetService("DataStoreService"):GetOrderedDataStore(Config.Leaderboards.StorePrefix .. "Power")
	ods:SetAsync(tostring(me.UserId), myPower)
	ods:SetAsync("4242", 777)
	ods:SetAsync("5555", 5)
	LB.refreshAll()
	step(2)
	local plan = Tree.draw()
	eq(#plan, 3, "three ranked players")
	local pets = t:FindFirstChild("TreePets", true)
	local withPet, signs = 0, 0
	for _, h in pets:GetChildren() do
		if h:FindFirstChild("TreePet") then
			withPet += 1
		end
		if h:FindFirstChild("TreeSign") then
			signs += 1
		end
	end
	eq(signs, 3, "every rank has a sign")
	eq(withPet, 2, "pets for me (live) and the offline card; none for the player without a card")
	folder:Destroy()
	local _ = GeodeGen
end)

print("HANGOUT DONE")
