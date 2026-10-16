-- Remote cheat check (run by tests/test_save_safe.luau): every client -> server remote, fired the way an exploit client
-- would (junk types, other players' ids, spam, faked purchase events, dev commands in a live game), changes nothing it
-- must not. Drives the REAL handlers on the offline mock (a live, non-Studio server: RunService:IsStudio() is false).
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
local me, ava, Profiles, Config = s.me, s.others[1], s.Profiles, s.Config
for _ = 1, 50 do
	if Profiles.isLoaded(ava) then
		break
	end
	preview.advance(0.1)
end
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local RobuxConfig = C.shared("RobuxConfig")
local Net = C.shared("Net")
local PvpService = C.server("PvpService")
local mine, hers = Profiles.get(me), Profiles.get(ava)
local function step(dt: number?)
	preview.advance(dt or 0.1)
end
local base = C.fakeSpecimens(1)[1]
local function petFor(data, id: string, extra: { [string]: any }?)
	local g = table.clone(base)
	g.Id = id
	g.Favorite = false
	for k, v in extra or {} do
		g[k] = v
	end
	table.insert(data.InventoryGeodes, g)
	return g
end
petFor(hers, "ava-pet")
petFor(mine, "my-pet")
mine.Cash = 1000
local function snapshot(data)
	local ids = {}
	for _, g in data.InventoryGeodes do
		table.insert(ids, g.Id)
	end
	table.sort(ids)
	return data.Cash .. "|" .. table.concat(ids, ",")
end

case("game pass: a faked 'purchase finished' event grants nothing unless Roblox says the pass is owned", function()
	local pass = RobuxConfig.Passes.PetStorage
	pass.PassId = 9301 -- test-only id (the config keeps 0 + REPLACE)
	local owns = false
	preview.setPassLookup(function(_, passId)
		return owns and passId == 9301
	end)
	preview.marketEvent("PromptGamePassPurchaseFinished", me, 9301, true)
	step(25)
	eq(RobuxConfig.hasPass(mine.Robux, "PetStorage"), false, "an unverified event grants nothing")
	owns = true
	preview.marketEvent("PromptGamePassPurchaseFinished", me, 9301, true)
	step(3)
	eq(RobuxConfig.hasPass(mine.Robux, "PetStorage"), true, "a real purchase is granted")
	preview.setPassLookup(nil)
	pass.PassId = 0
end)

case("selling, equipping, evolving, renaming or displaying another player's pet does nothing", function()
	local before, herBefore = snapshot(mine), snapshot(hers)
	step(1.1)
	preview.fireServerAs(me, "CollectionAction", "Sell", { "ava-pet" }, 0)
	preview.fireServerAs(me, "CollectionAction", "Sell", { "ava-pet" }, math.floor(base.Value * Config.Sell.SpecimenFraction))
	preview.fireServerAs(me, "CollectionAction", "Display", "ava-pet", true)
	preview.fireServerAs(me, "CollectionAction", "DisplayAt", "ava-pet", 1)
	preview.fireServerAs(me, "CollectionAction", "Favorite", "ava-pet", true)
	step(0.4)
	preview.fireServerAs(me, "CollectionAction", "EquipPet", "ava-pet")
	step(0.4)
	preview.fireServerAs(me, "CollectionAction", "RenamePet", "ava-pet", "Mine")
	PvpService.action(me, { Op = "Evolve", Pet = "ava-pet" })
	PvpService.action(me, { Op = "Train", Pet = "ava-pet" })
	PvpService.action(me, { Op = "SetTeam", Pets = { "ava-pet" } })
	step(1)
	eq(snapshot(mine), before, "my inventory and coins")
	eq(snapshot(hers), herBefore, "her inventory and coins")
	eq(table.find(mine.EquippedPets, "ava-pet"), nil, "not following me")
	eq(table.find(mine.DisplayAssignments, "ava-pet"), nil, "not on my plot")
	local _, g = Profiles.findGeode(hers, "ava-pet")
	eq(g.Favorite, false)
	eq(g.Nickname, nil)
	eq(type(mine.TowerXP) == "table" and mine.TowerXP["ava-pet"] or nil, nil, "no XP row")
end)

case("evolve and sell in the same frame never use one copy twice", function()
	local TC = C.shared("TowerConfig")
	TC.Evolve.Enabled = true -- evolve is off for now (carter 2026-10-16); the race guard is kept for when it returns
	for _, order in { "SellFirst", "EvolveFirst" } do
		mine.InventoryGeodes = {}
		mine.EquippedPets, mine.DisplayAssignments, mine.RoamPets = {}, {}, {}
		mine.TowerXP = {}
		local main = petFor(mine, order .. "-main")
		local c1 = petFor(mine, order .. "-c1")
		petFor(mine, order .. "-c2")
		mine.TowerXP[main.Id] = 1e7
		local price = math.floor(Profiles.priceValue(c1) * Config.Sell.SpecimenFraction)
		local cash = mine.Cash
		step(1.2)
		if order == "SellFirst" then
			preview.fireServerAs(me, "CollectionAction", "Sell", { c1.Id }, price)
			PvpService.action(me, { Op = "Evolve", Pet = main.Id })
		else
			PvpService.action(me, { Op = "Evolve", Pet = main.Id })
			preview.fireServerAs(me, "CollectionAction", "Sell", { c1.Id }, price)
		end
		step(0.2)
		local sold = mine.Cash == cash + price
		local evolved = (main.Evolve or 0) >= 1
		assert(sold ~= evolved, order .. ": exactly one of sell / evolve went through (sold " .. tostring(sold) .. ", evolved " .. tostring(evolved) .. ")")
		eq(#mine.InventoryGeodes, if sold then 2 else 1, order .. ": pets left")
	end
	TC.Evolve.Enabled = false
end)

case("daily gift: claiming twice (spam) pays once", function()
	local cash = mine.Cash
	step(1.1)
	preview.fireServerAs(me, "ShopAction", "ClaimGift")
	preview.fireServerAs(me, "ShopAction", "ClaimGift")
	step(1.1)
	preview.fireServerAs(me, "ShopAction", "ClaimGift")
	step(0.5)
	local paid = mine.Cash - cash
	assert(paid > 0, "the first claim pays")
	local cash2 = mine.Cash
	step(1.1)
	preview.fireServerAs(me, "ShopAction", "ClaimGift")
	step(0.5)
	eq(mine.Cash, cash2, "no second payment the same day")
end)

case("dev commands and the dev pet spawner do not exist in a live game", function()
	eq(ReplicatedStorage:FindFirstChild("DevCommand"), nil, "no DevCommand remote")
	eq(ReplicatedStorage:FindFirstChild("DevSpawnPet"), nil, "no DevSpawnPet remote")
	local cash = mine.Cash
	me.Chatted:_fire("/coins 9999999")
	me.Chatted:_fire("/maxpet")
	step(1)
	eq(mine.Cash, cash, "chat /coins does nothing")
	eq(me:GetAttribute("DevPets"), nil, "no dev pet menu")
end)

case("junk on every remote (wrong types, NaN, huge strings, odd tables) throws nothing and changes nothing", function()
	local errors = preview.errorCount()
	local mineBefore, hersBefore = snapshot(mine), snapshot(hers)
	local big = string.rep("x", 20000)
	local junk = { nil, 0 / 0, math.huge, -1, 1e300, true, {}, { 1, 2, 3 }, { Op = 5 }, { Op = "Train", Pet = {} }, { Op = "SetTeam", Pets = { {}, 0 / 0 } }, { Op = "Evolve", Pet = big }, big, { [{}] = true } }
	local names = {}
	for i = 1, 12 do -- the client -> server names at the top of Net.Events
		table.insert(names, Net.Events[i])
	end
	local pvp = ReplicatedStorage:FindFirstChild("PvpNet") and ReplicatedStorage.PvpNet:FindFirstChild("PvpAction")
	local tower = ReplicatedStorage:FindFirstChild("TowerNet") and ReplicatedStorage.TowerNet:FindFirstChild("TowerAction")
	local verbs = { "Sell", "Buy", "Equip", "Display", "DisplayAt", "BuyEggCoins", "UnlockTier", "BuyCapacity", "Invite", "Accept", "Pickup", "Deposit" }
	for round = 1, 2 do
		for _, name in names do
			for _, a in junk do
				for _, b in { nil, 0 / 0, big, {}, -5 } do
					preview.fireServerAs(me, name, a, b, a)
				end
			end
			for _, v in verbs do
				for _, b in junk do
					preview.fireServerAs(me, name, v, b, b)
				end
			end
			step(0.05)
		end
		for _, a in junk do
			if pvp then
				pvp.OnServerEvent:_fire(me, a)
			end
			if tower then
				tower.OnServerEvent:_fire(me, a)
			end
		end
		step(1.2 * round)
	end
	step(2)
	eq(preview.errorCount(), errors, "no handler threw")
	eq(snapshot(mine), mineBefore, "my coins and pets unchanged")
	eq(snapshot(hers), hersBefore, "her coins and pets unchanged")
end)

print("CHEAT_CHECK DONE")
