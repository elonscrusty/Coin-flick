-- Robux shop receipts (run by tests/test_m10_server.luau): the real RobuxService route behind StoreService's one
-- ProcessReceipt, on the offline mock. A replayed receipt grants nothing more; a 10x egg is ten pets under one
-- receipt; a missing profile or an unknown product is answered NotProcessedYet; the potion timer stacks; the buy
-- request refuses a batch the Pet Book has no room for (no prompt); ids at 0 never prompt.
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
		data.TutorialStep = 1
		data.Onboard.Skipped = true
	end,
})
local me, Profiles = s.me, s.Profiles
local RobuxConfig = C.shared("RobuxConfig")
local MarketplaceService = game:GetService("MarketplaceService")
local data = Profiles.get(me)
local Granted, NotYet = Enum.ProductPurchaseDecision.PurchaseGranted, Enum.ProductPurchaseDecision.NotProcessedYet
local function step(dt: number?)
	preview.advance(dt or 0.1)
end

-- test-only product ids (never shipped: the config keeps 0 + REPLACE)
local mythic = RobuxConfig.egg("MythicEgg")
mythic.Products[1], mythic.Products[10] = 9101, 9110
RobuxConfig.Potion.ProductId = 9200
local receipt = MarketplaceService.ProcessReceipt
assert(type(receipt) == "function", "ProcessReceipt installed")

case("a 10x egg grants ten pets once, even when the receipt is replayed", function()
	local n = #data.InventoryGeodes
	local info = { PlayerId = me.UserId, PurchaseId = "P-10x", ProductId = 9110, CurrencySpent = 1, CurrencyType = Enum.CurrencyType.Robux, PlaceIdWherePurchased = 0 }
	eq(receipt(info), Granted, "first")
	eq(#data.InventoryGeodes, n + 10, "ten pets")
	eq(receipt(info), Granted, "replay still answered granted")
	eq(receipt(info), Granted, "third replay")
	eq(#data.InventoryGeodes, n + 10, "no extra pets")
	eq(data.Robux.EggsBought, 10)
	assert(RobuxConfig.granted(data.Robux, "P-10x"), "receipt recorded in the profile")
	local last = data.InventoryGeodes[#data.InventoryGeodes]
	assert(table.find(s.Config.Tiers.Gravel.Minerals, last.Mineral), "pet of the buyer's zone")
	eq(data.Stats.SoloFinds, 0, "bought pets are not finds")
end)

case("a different receipt for the same product grants again", function()
	local n = #data.InventoryGeodes
	eq(receipt({ PlayerId = me.UserId, PurchaseId = "P-1x", ProductId = 9101 }), Granted)
	eq(#data.InventoryGeodes, n + 1)
end)

case("no player / no profile / unknown product -> NotProcessedYet, nothing granted", function()
	local n = #data.InventoryGeodes
	eq(receipt({ PlayerId = 424242, PurchaseId = "P-away", ProductId = 9101 }), NotYet, "player not here")
	eq(receipt({ PlayerId = me.UserId, PurchaseId = "P-unknown", ProductId = 123456 }), NotYet, "unknown product")
	eq(#data.InventoryGeodes, n)
	-- a player whose profile is not loaded yet
	local late = preview.addPlayer("Late", 777001)
	preview.playerJoined(late)
	if not Profiles.get(late) then
		eq(receipt({ PlayerId = late.UserId, PurchaseId = "P-late", ProductId = 9101 }), NotYet, "profile not loaded")
	end
	for _ = 1, 50 do
		if Profiles.isLoaded(late) then
			break
		end
		step(0.1)
	end
	local ld = Profiles.get(late)
	assert(ld, "late profile loaded")
	assert(not RobuxConfig.granted(ld.Robux, "P-late"), "nothing recorded while it was not loaded")
	eq(receipt({ PlayerId = late.UserId, PurchaseId = "P-late", ProductId = 9101 }), Granted, "retry after load")
end)

case("a failed save answers NotProcessedYet; the retry is granted without a second pet", function()
	local n = #data.InventoryGeodes
	local info = { PlayerId = me.UserId, PurchaseId = "P-savefail", ProductId = 9101 }
	local first, second = nil, nil
	preview.failDataStores(false, true)
	task.spawn(function()
		first = receipt(info)
	end)
	preview.advance(40, 10)
	preview.failDataStores(false, false)
	eq(first, NotYet, "not granted while the save fails")
	task.spawn(function()
		second = receipt(info)
	end)
	preview.advance(5, 10)
	eq(second, Granted, "Roblox's retry is granted once the save lands")
	eq(#data.InventoryGeodes, n + 1, "one pet for one receipt, not two")
	assert(RobuxConfig.granted(data.Robux, "P-savefail"), "receipt recorded")
end)

case("potions stack on the server clock", function()
	local t0 = os.time()
	eq(receipt({ PlayerId = me.UserId, PurchaseId = "P-pot1", ProductId = 9200 }), Granted)
	eq(receipt({ PlayerId = me.UserId, PurchaseId = "P-pot1", ProductId = 9200 }), Granted, "replay")
	eq(receipt({ PlayerId = me.UserId, PurchaseId = "P-pot2", ProductId = 9200 }), Granted)
	local left = RobuxConfig.potionLeft(data.Robux, t0)
	assert(left >= 2 * RobuxConfig.Potion.Seconds - 2 and left <= 2 * RobuxConfig.Potion.Seconds, "two potions, not three: " .. left)
end)

case("buy request: no room for a 10x batch -> refused before the prompt", function()
	step(1)
	local before = #preview.marketPrompts()
	local keep = data.InventoryGeodes
	local full = {}
	for i = 1, Profiles.inventoryMax(data) - 5 do
		full[i] = keep[1]
	end
	data.InventoryGeodes = full
	me:SetAttribute("PaidRandomRestricted", false)
	preview.fireServerAs(me, "RobuxAction", "Buy", "MythicEgg", 10)
	step(0.5)
	eq(#preview.marketPrompts(), before, "no prompt for 10 with room for 5")
	preview.fireServerAs(me, "RobuxAction", "Buy", "MythicEgg", 1)
	step(0.5)
	eq(#preview.marketPrompts(), before + 1, "1x prompts")
	data.InventoryGeodes = keep
	step(1)
	preview.fireServerAs(me, "RobuxAction", "Buy", "BasicEgg", 1)
	step(0.5)
	eq(#preview.marketPrompts(), before + 1, "id 0 never prompts")
	-- PolicyService says paid random items are restricted: no egg and no luck potion prompt
	me:SetAttribute("PaidRandomRestricted", true)
	preview.fireServerAs(me, "RobuxAction", "Buy", "MythicEgg", 1)
	step(0.5)
	preview.fireServerAs(me, "RobuxAction", "Buy", "LuckPotion")
	step(0.5)
	eq(#preview.marketPrompts(), before + 1, "restricted account: no paid random item prompt")
	me:SetAttribute("PaidRandomRestricted", false)
	preview.fireServerAs(me, "RobuxAction", "Buy", "LuckPotion")
	step(0.5)
	eq(#preview.marketPrompts(), before + 2, "allowed again: the potion prompts")
end)

case("egg shrine: coins buy eggs; refusals change nothing", function()
	step(1)
	me:SetAttribute("PaidRandomRestricted", false)
	-- the shrine buy needs the player at the hatch stand
	local root = me.Character and me.Character:FindFirstChild("HumanoidRootPart") :: BasePart
	local stand: BasePart? = nil
	for _, d in workspace:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("HatchStand") == true then
			stand = d
			break
		end
	end
	assert(stand and root, "park hatch stand and player exist")
	root.Position = stand.Position
	local tierId = RobuxConfig.eggTier(data.UnlockedTiers)
	local price = RobuxConfig.eggCoinPrice("BasicEgg", tierId, 3) :: number
	local n, robuxBought, prompts = #data.InventoryGeodes, data.Robux.EggsBought, #preview.marketPrompts()
	data.Cash = price - 1
	preview.fireServerAs(me, "RobuxAction", "BuyEggCoins", "BasicEgg", 3)
	step(0.5)
	eq(#data.InventoryGeodes, n, "too few coins: no pets")
	eq(data.Cash, price - 1, "too few coins: no charge")
	data.Cash = price + 5
	step(0.5)
	preview.fireServerAs(me, "RobuxAction", "BuyEggCoins", "BasicEgg", 2)
	step(0.5)
	eq(#data.InventoryGeodes, n, "count not sold")
	preview.fireServerAs(me, "RobuxAction", "BuyEggCoins", "GoldenEgg", 1)
	step(0.5)
	eq(#data.InventoryGeodes, n, "unknown egg")
	-- 3 at once needs the Open 3 Eggs pass (on sale since 2026-10-15)
	preview.fireServerAs(me, "RobuxAction", "BuyEggCoins", "BasicEgg", 3)
	step(0.5)
	eq(#data.InventoryGeodes, n, "no Open 3 Eggs pass: refused")
	eq(data.Cash, price + 5, "no Open 3 Eggs pass: no charge")
	data.Robux.Passes.TripleHatch = true
	preview.fireServerAs(me, "RobuxAction", "BuyEggCoins", "BasicEgg", 3)
	step(0.5)
	eq(#data.InventoryGeodes, n + 3, "three pets")
	-- charged the zone price once (a species hatched for the first time pays its pet index coins on top)
	local bonus = data.Cash - 5
	local ff = s.Config.PetIndex.FirstFindCoins
	assert(bonus >= 0 and bonus <= 3 * ff and bonus % ff == 0, "charged the zone price once: " .. data.Cash)
	eq(data.Robux.EggsBought, robuxBought, "coin eggs are not Robux eggs")
	eq(#preview.marketPrompts(), prompts, "no Robux prompt")
	local last = data.InventoryGeodes[#data.InventoryGeodes]
	assert(string.sub(last.MatchKey, 1, 6) == "coins:", "coin award key: " .. tostring(last.MatchKey))
	eq(Profiles.priceValue(last), last.Value, "coin pets sell at full value")
	-- a batch the Pet Book has no room for is refused before any coins move
	local keep = data.InventoryGeodes
	local full = {}
	for i = 1, Profiles.inventoryMax(data) - 2 do
		full[i] = keep[1]
	end
	data.InventoryGeodes = full
	data.Cash = 10 * price
	step(0.5)
	preview.fireServerAs(me, "RobuxAction", "BuyEggCoins", "BasicEgg", 3)
	step(0.5)
	eq(#data.InventoryGeodes, #full, "no room for 3")
	eq(data.Cash, 10 * price, "no charge without room")
	data.InventoryGeodes = keep
	-- the paid random item gate covers coin eggs too
	me:SetAttribute("PaidRandomRestricted", true)
	step(0.5)
	preview.fireServerAs(me, "RobuxAction", "BuyEggCoins", "BasicEgg", 1)
	step(0.5)
	eq(#data.InventoryGeodes, #keep, "restricted account: refused")
	eq(data.Cash, 10 * price, "restricted account: no charge")
	me:SetAttribute("PaidRandomRestricted", false)
end)

case("egg shrine: too far from the stand and too fast are refused, nothing is charged", function()
	step(1)
	me:SetAttribute("PaidRandomRestricted", false)
	local root = me.Character and me.Character:FindFirstChild("HumanoidRootPart") :: BasePart
	local stand: BasePart? = nil
	for _, d in workspace:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("HatchStand") == true then
			stand = d
			break
		end
	end
	assert(stand and root, "park hatch stand and player exist")
	local tierId = RobuxConfig.eggTier(data.UnlockedTiers)
	local price = RobuxConfig.eggCoinPrice("BasicEgg", tierId, 1) :: number
	data.Cash = 10 * price
	local n = #data.InventoryGeodes
	-- 300 studs from the stand: far outside the prompt's reach plus the slack
	root.Position = stand.Position + Vector3.new(300, 0, 0)
	step(0.5)
	preview.fireServerAs(me, "RobuxAction", "BuyEggCoins", "BasicEgg", 1)
	step(0.5)
	eq(#data.InventoryGeodes, n, "too far away: no pet")
	eq(data.Cash, 10 * price, "too far away: no charge")
	-- back at the stand: one buy works, a second inside the rate limit window is dropped
	root.Position = stand.Position
	step(1)
	preview.fireServerAs(me, "RobuxAction", "BuyEggCoins", "BasicEgg", 1)
	preview.fireServerAs(me, "RobuxAction", "BuyEggCoins", "BasicEgg", 1)
	step(0.2)
	eq(#data.InventoryGeodes, n + 1, "second buy right away is ignored")
	-- after the window it works again
	step(1)
	preview.fireServerAs(me, "RobuxAction", "BuyEggCoins", "BasicEgg", 1)
	step(0.5)
	eq(#data.InventoryGeodes, n + 2, "buy after the window")
end)

case("egg perks: a full Lucky Meter makes the next coin egg Epic or better, then empties", function()
	local EggPerks = C.shared("EggPerks")
	me:SetAttribute("PaidRandomRestricted", false)
	local root = me.Character and me.Character:FindFirstChild("HumanoidRootPart") :: BasePart
	local stand: BasePart? = nil
	for _, d in workspace:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("HatchStand") == true then
			stand = d
			break
		end
	end
	assert(stand and root, "park hatch stand and player exist")
	root.Position = stand.Position
	local price = RobuxConfig.eggCoinPrice("BasicEgg", RobuxConfig.eggTier(data.UnlockedTiers), 1) :: number
	for round = 1, 5 do
		data.EggPerks.Meter = EggPerks.Meter.Need
		data.Cash = price
		local n = #data.InventoryGeodes
		step(1)
		preview.fireServerAs(me, "RobuxAction", "BuyEggCoins", "BasicEgg", 1)
		step(0.5)
		eq(#data.InventoryGeodes, n + 1, "pity egg " .. round .. " hatched")
		local pet = data.InventoryGeodes[#data.InventoryGeodes]
		assert(pet.Rarity == "Epic" or pet.Rarity == "Legendary", "pity egg is Epic+: " .. pet.Rarity)
		eq(data.EggPerks.Meter, 0, "an Epic+ empties the meter")
	end
	-- a plain egg adds its points
	data.Cash = price
	step(1)
	preview.fireServerAs(me, "RobuxAction", "BuyEggCoins", "BasicEgg", 1)
	step(0.5)
	local last = data.InventoryGeodes[#data.InventoryGeodes]
	local want = if last.Rarity == "Epic" or last.Rarity == "Legendary" then 0 else 1
	eq(data.EggPerks.Meter, want, "basic egg adds 1 point")
end)

case("egg perks: banked free eggs hatch when there is room and wait when the Pet Book is full", function()
	local EggPerks = C.shared("EggPerks")
	local keep = data.InventoryGeodes
	local full = {}
	for i = 1, Profiles.inventoryMax(data) do
		full[i] = keep[1]
	end
	data.InventoryGeodes = full
	data.EggPerks.Bank = { RareEgg = 1, BasicEgg = 1 }
	Profiles.changed(me)
	step(0.5)
	eq(#data.InventoryGeodes, #full, "full book: nothing hatched")
	eq(EggPerks.bankCount(data.EggPerks), 2, "full book: both eggs still banked")
	data.InventoryGeodes = keep
	local n = #keep
	Profiles.changed(me)
	step(0.5)
	eq(#data.InventoryGeodes, n + 2, "room: both banked eggs hatched")
	eq(EggPerks.bankCount(data.EggPerks), 0, "bank empty")
	local key = data.InventoryGeodes[#data.InventoryGeodes].MatchKey
	assert(string.sub(key, 1, 5) == "free:", "free award key: " .. tostring(key))
end)

case("egg perks: one full Lucky Meter pays ONE pity egg even when a banked free egg opens with a bought one", function()
	local EggPerks = C.shared("EggPerks")
	local Net = C.shared("Net")
	local pity = 0
	local conn = Net.event("Toast").OnClientEvent:Connect(function(text)
		if type(text) == "string" and string.find(text, "LUCKY METER full", 1, true) then
			pity += 1
		end
	end)
	me:SetAttribute("PaidRandomRestricted", false)
	local price = RobuxConfig.eggCoinPrice("BasicEgg", RobuxConfig.eggTier(data.UnlockedTiers), 1) :: number
	data.EggPerks.Bank = {}
	data.EggPerks.Meter = EggPerks.Meter.Need
	data.EggPerks.Bank = { BasicEgg = 1 } -- banked while the book was full; the buy below must not hatch it mid-loop
	data.Cash = price
	local n = #data.InventoryGeodes
	step(1)
	preview.fireServerAs(me, "RobuxAction", "BuyEggCoins", "BasicEgg", 1)
	step(0.5)
	conn:Disconnect()
	eq(#data.InventoryGeodes, n + 2, "bought egg + banked free egg both hatched")
	eq(EggPerks.bankCount(data.EggPerks), 0, "bank empty")
	eq(pity, 1, "one full meter = one pity egg")
	local bought = data.InventoryGeodes[n + 1]
	assert(string.sub(bought.MatchKey, 1, 5) ~= "free:", "the bought egg hatches first")
end)

case("egg perks: a full Pet Book page pays +10% on shells", function()
	local EggPerks = C.shared("EggPerks")
	data.RubbleByTier = { Gravel = 100 }
	local saved = data.DiscoveryIndex
	data.DiscoveryIndex = {}
	local before = Profiles.rubbleValue(data)
	local index = {}
	for _, id in EggPerks.pageSpecies("Gravel") do
		index[id] = 1
	end
	data.DiscoveryIndex = index
	local after = Profiles.rubbleValue(data)
	assert(before > 0 and math.abs(after - before * 1.1) <= 1.2, "meadow page: +10%: " .. before .. " -> " .. after)
	data.DiscoveryIndex = saved
	data.RubbleByTier = {}
end)

print("ROBUX DONE")
