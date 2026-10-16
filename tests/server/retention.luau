-- Server audit (run by tests/test_m10_server.luau): first five minutes and comeback hooks through the real server.
-- Play-time gifts via RetentionAction, the away nest on a fresh join, the Void Dragon statue in the lobby, and the
-- practice bots on a new player's first hunt (bot characters from a test factory: the mock has no avatar service).
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
	profile = function(data)
		data.TutorialStep = 0
		data.Onboard.Skipped = false
	end,
})
local me, Profiles = s.me, s.Profiles
local Retention = C.shared("Retention")
local RetentionService = C.server("RetentionService")
local PracticeBots = C.server("PracticeBots")
local data = Profiles.get(me)
local function step(dt: number?)
	preview.advance(dt or 0.2)
end

local notices = {}
local ev = game:GetService("ReplicatedStorage").Remotes:FindFirstChild("Retention")
ev.OnClientEvent:Connect(function(kind, payload)
	table.insert(notices, { kind, payload })
end)
preview.fireServerAs(me, "RetentionAction", "Ready")
step()

case("play gift: refused before 1 minute, opens after, pays coins once", function()
	data.Retention.Play = { Day = 0, Seconds = 0, Claimed = 0 }
	local cash = data.Cash
	preview.fireServerAs(me, "RetentionAction", "Gift")
	step(0.5)
	eq(data.Cash, cash, "too early")
	for _ = 1, 4 do
		RetentionService.tick(15)
	end
	eq(Retention.readyGifts(data.Retention, Retention.day(os.time())), 1)
	preview.fireServerAs(me, "RetentionAction", "Gift")
	step(0.5)
	eq(data.Cash, cash + Retention.PlayGifts.Coins[1], "gift paid")
	preview.fireServerAs(me, "RetentionAction", "Gift")
	step(0.5)
	eq(data.Cash, cash + Retention.PlayGifts.Coins[1], "not twice")
	local got = false
	for _, n in notices do
		if n[1] == "Gift" and n[2].Coins == Retention.PlayGifts.Coins[1] then
			got = true
		end
	end
	assert(got, "the client is told (coin burst)")
	local view = Profiles.publicView(me, false)
	eq(view.Gifts.NextGift, 2, "the timer moves to the 3 minute gift")
end)

case("first pet rule: a save that never hatched its starter egg gets the away coins but no free pet", function()
	local starter = data.StarterPet
	data.StarterPet = false
	local cash = data.Cash
	local pets = #data.InventoryGeodes
	data.Retention.LastSeen = os.time() - 9 * 3600
	RetentionService.greet(me, data)
	step()
	eq(#data.InventoryGeodes, pets, "no pet before the first hatch")
	assert(data.Cash > cash, "the away coins are still paid")
	data.StarterPet = starter
	data.Retention.LastSeen = 0
end)

case("away nest: 9 hours away pays coins and hatches a Common pet once; a quick rejoin pays nothing", function()
	data.StarterPet = true
	local cash = data.Cash
	local pets = #data.InventoryGeodes
	data.Retention.LastSeen = os.time() - 9 * 3600
	RetentionService.greet(me, data)
	step()
	local r = Retention.away(os.time() - 9 * 3600, os.time())
	assert(data.Cash >= cash + r.Coins, "coins (plus first-find coins when the pet is a new species)")
	local after = data.Cash
	eq(#data.InventoryGeodes, pets + 1, "one pet hatched")
	eq(data.InventoryGeodes[#data.InventoryGeodes].Rarity, "Common")
	eq(data.Stats.SoloFinds, 0, "a gift is not a find")
	local seen = false
	for _, n in notices do
		if n[1] == "Away" and n[2].Eggs == r.Eggs then
			seen = true
		end
	end
	assert(seen, "the away card is sent")
	RetentionService.greet(me, data)
	step()
	eq(data.Cash, after, "nothing for a quick rejoin")
end)

case("the Void Dragon statue stands in the lobby with 1 in 1000 on it", function()
	local statue = workspace:FindFirstChild("VoidDragonStatue", true)
	assert(statue, "statue built")
	assert(statue:FindFirstChild("Dragon"), "dragon model on the plinth")
	local odds = statue:FindFirstChild("Odds", true)
	assert(odds and odds.Text == "1 in 1000", "odds sign")
	local Retention = C.shared("Retention")
	local src = statue:FindFirstChild("Source", true)
	assert(src and src.Text == Retention.DreamSource, "the sign says where it comes from (audit F22)")
	eq(statue:FindFirstChild("Plinth"):GetAttribute("Hint"), Retention.DreamHint)
end)

case("a VoidStatueSpot with Height 30 and Plinth false: a big dragon on the spot, a beam, the floating sign, no plinth", function()
	local VoidStatue = C.server("VoidStatue")
	local root = Instance.new("Folder")
	root.Name = "StatueTest"
	root.Parent = workspace
	local spot = Instance.new("Part")
	spot.Name = C.shared("MapNames").VoidStatueSpot
	spot.Size = Vector3.new(4, 2, 4)
	spot.CFrame = CFrame.new(0, 10, -135)
	spot:SetAttribute("Height", 30)
	spot:SetAttribute("Plinth", false)
	spot.Parent = root
	local statue = VoidStatue.build(root, nil)
	assert(statue, "built")
	eq(statue:GetAttribute("Height"), 30)
	eq(statue:FindFirstChild("Plinth"), nil, "no code plinth")
	assert(statue:FindFirstChild("Beam1"), "light beam")
	local odds = statue:FindFirstChild("Odds", true)
	assert(odds and odds.Text == "1 in 1000" and odds:FindFirstAncestorOfClass("BillboardGui"), "floating odds sign")
	local src = statue:FindFirstChild("Source", true)
	assert(src and src:FindFirstAncestorOfClass("BillboardGui") and src.Text ~= "", "floating source line (audit F22)")
	-- the sign floats clear of the dragon's head whatever its height (Height 30 clipped with a fixed offset)
	local VS = C.server("VoidStatue")
	local bcf, bsize = statue.Dragon:GetBoundingBox()
	local head = bcf.Position.Y + bsize.Y / 2
	local sign = statue:FindFirstChild("SignAnchor")
	local bb = sign:FindFirstChildOfClass("BillboardGui")
	local bottom = sign.Position.Y - bb.Size.Y.Scale / 2
	assert(bottom >= head + VS.SignGap - 0.01, "sign bottom " .. bottom .. " clears the head " .. head)
	assert(bottom <= head + VS.SignGap + VS.Hover + 1, "sign stays close to the head")
	local home = statue.Dragon:GetAttribute("Home")
	assert(typeof(home) == "CFrame" and math.abs(home.Position.Z + 135) < 1, "the dragon stands on the spot")
	root:Destroy()
end)

case("first hunt: practice bots race at the free nests and leave when the pet is found", function()
	PracticeBots.setFactory(function(name)
		local m = Instance.new("Model")
		m.Name = name
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = Vector3.new(2, 2, 1)
		root.Parent = m
		local head = Instance.new("Part")
		head.Name = "Head"
		head.Size = Vector3.new(1, 1, 1)
		head.Parent = m
		Instance.new("Humanoid").Parent = m
		m.PrimaryPart = root
		return m
	end)
	local w = C.watchMatch()
	C.startSolo(w)
	assert(w.last.Init and w.last.Init.Tutorial, "the first hunt is the practice pile")
	step(1)
	local match = s.MatchService.matchFor(me.UserId)
	assert(match, "in a match")
	eq(PracticeBots.count(match.Key), 3, "three bots at the three free nests")
	local outfits = {}
	for _, b in PracticeBots.peek(match.Key) do
		local model = workspace:FindFirstChild("PracticeBot_" .. b.Name, true)
		assert(model, "bot model " .. b.Name)
		local folder = model:FindFirstChild("Outfit")
		assert(folder and #folder:GetChildren() >= 3, b.Name .. " wears its outfit parts")
		outfits[model:GetAttribute("Outfit")] = true
	end
	assert(outfits.Bunny and outfits.Fox and outfits.Dino, "three different outfits")
	-- the mock's Humanoid:MoveTo does not move anything, so this also proves the stuck nudge walks them along
	local carried = false
	local start: { [string]: any } = {}
	local nearPile: { [string]: boolean } = {}
	local backHome: { [string]: boolean } = {}
	local function flat(a, b)
		return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
	end
	for _ = 1, 300 do -- 60 s
		step(0.2)
		for _, b in PracticeBots.peek(match.Key) do
			carried = carried or b.Carry
			start[b.Name] = start[b.Name] or flat(b.Pos, b.Pile)
			if flat(b.Pos, b.Pile) <= 3 then
				nearPile[b.Name] = true
			end
			if nearPile[b.Name] and flat(b.Pos, b.Nest) <= 3 then
				backHome[b.Name] = true
			end
		end
	end
	assert(carried, "bots carry eggs to their nests")
	for _, b in PracticeBots.peek(match.Key) do
		assert(start[b.Name] > 5, b.Name .. " starts away from the pile")
		assert(nearPile[b.Name], b.Name .. " walked to the pile")
		assert(backHome[b.Name], b.Name .. " walked back to its nest")
		assert(b.Cycles >= 2, b.Name .. " cracked at its nest at least twice: " .. tostring(b.Cycles))
	end
	C.crackUntilFound(w)
	step(1)
	eq(PracticeBots.count(match.Key), 0, "bots gone for the reveal")
	step(1)
	eq(PracticeBots.loops(), 0, "no bot step loop runs after the practice pet is found")
	-- back in the lobby (results over): still no loop, and a group that loses its models stops on its own
	C.fireServer("MatchAction", "Return")
	step(2)
	eq(s.MatchService.matchFor(me.UserId), nil, "back in the lobby")
	eq(PracticeBots.loops(), 0, "no bot step loop runs in the lobby")
	PracticeBots.setFactory(nil)
end)

case("all daily quests claimed: one free Rare Egg a day (EggPerks), hatched right away", function()
	local Quests = C.shared("Quests")
	local EggPerks = C.shared("EggPerks")
	local today = Quests.day(os.time())
	Quests.rollover(data.Daily, today)
	local list = Quests.forDay(me.UserId, today)
	for i, q in list do
		data.Daily.Progress[i] = q.Goal
		data.Daily.Claimed[i] = false
	end
	data.EggPerks.QuestDay = 0
	local n = #data.InventoryGeodes
	for i = 1, #list do
		preview.fireServerAs(me, "ShopAction", "ClaimQuest", i)
		step(0.3)
	end
	step(1)
	eq(data.EggPerks.QuestDay, today, "today's quest egg earned")
	eq(EggPerks.bankCount(data.EggPerks), 0, "and hatched (not left in the bank)")
	local free = 0
	for i = n + 1, #data.InventoryGeodes do
		if string.sub(tostring(data.InventoryGeodes[i].MatchKey), 1, 5) == "free:" then
			free += 1
		end
	end
	eq(free, 1, "one free pet")
	-- claiming again the same day earns nothing more
	preview.fireServerAs(me, "ShopAction", "ClaimQuest", 1)
	step(0.5)
	eq(#data.InventoryGeodes, n + 1, "no second egg")
end)

print("RETENTION DONE")
