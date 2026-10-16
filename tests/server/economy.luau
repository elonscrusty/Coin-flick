-- Server audit (run by tests/test_m10_server.luau): duplicate and late purchases and sales through the real
-- ShopAction / CollectionAction handlers and the one rubble sale (Economy.sellRubble). No double money, no
-- double levels, a failed purchase keeps funds and ownership, unknown (future) rubble is never sold for nothing.
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
		data.Cash = 5000
	end,
})
local me, Profiles, Config = s.me, s.Profiles, s.Config
local Economy = C.server("EconomyService")
local data = Profiles.get(me)
local function shop(...)
	preview.fireServerAs(me, "ShopAction", ...)
end
local function step(dt: number?)
	preview.advance(dt or 0.1)
end

case("buying a tool twice in one frame charges once", function()
	local cash = data.Cash
	shop("BuyHandheld", "SteelHammer")
	shop("BuyHandheld", "SteelHammer")
	step()
	eq(data.Cash, cash - Config.Handhelds.SteelHammer.Price)
	eq(data.EquipmentOwned.SteelHammer, true)
end)

case("a double tap on a storage or gallery level buys one level", function()
	local cash, cap, disp = data.Cash, data.CapacityTier, data.DisplayCapacity
	shop("BuyCapacity")
	shop("BuyCapacity")
	shop("BuyDisplay")
	shop("BuyDisplay")
	step()
	eq(data.CapacityTier, cap + 1, "one storage level")
	eq(data.DisplayCapacity, disp + 1, "one gallery level")
	eq(data.Cash, cash - Config.Capacity[cap + 1].Price - Config.Display[disp + 1].Price, "charged once each")
end)

case("a level request for a level other than the next one is refused", function()
	step(1.2) -- past the double-tap window
	local cash, cap = data.Cash, data.CapacityTier
	shop("BuyCapacity", cap + 2) -- the shop showed stale data
	step()
	eq(data.CapacityTier, cap)
	eq(data.Cash, cash)
	shop("BuyCapacity", cap + 1)
	step()
	if Config.Capacity[cap + 1] then
		eq(data.CapacityTier, cap + 1, "the right level is bought")
	end
end)

case("a purchase without enough cash keeps cash and ownership", function()
	data.Cash = 10
	local owned = data.EquipmentOwned.Jackhammer
	shop("BuyHandheld", "Jackhammer")
	step()
	eq(data.Cash, 10)
	eq(data.EquipmentOwned.Jackhammer, owned)
	eq(data.EquippedHandheld, "SteelHammer", "equipped tool unchanged")
end)

case("selling rubble twice pays once; unknown future rubble stays in the bag", function()
	data.Cash = 0
	data.RubbleByTier = { Gravel = 10, Volcano = 4 }
	local value = 10 * Config.Tiers.Gravel.CashPerRubble
	Economy.sellRubble(me)
	Economy.sellRubble(me)
	step(1)
	Economy.sellRubble(me) -- late: the bag has nothing this build can sell
	eq(data.Cash, value)
	eq(data.RubbleByTier.Gravel, nil)
	eq(data.RubbleByTier.Volcano, 4, "future tier rubble kept")
	eq(Profiles.rubbleValue(data), 0)
end)

case("selling a specimen twice pays once", function()
	local specs = C.fakeSpecimens(2)
	for _, g in specs do
		g.Favorite = false
		table.insert(data.InventoryGeodes, g)
	end
	data.DisplayAssignments = {}
	local id = specs[1].Id
	local price = math.floor(specs[1].Value * Config.Sell.SpecimenFraction)
	local cash, n = data.Cash, #data.InventoryGeodes
	preview.fireServerAs(me, "CollectionAction", "Sell", { id }, price)
	preview.fireServerAs(me, "CollectionAction", "Sell", { id }, price)
	step()
	eq(data.Cash, cash + price)
	eq(#data.InventoryGeodes, n - 1)
	-- a specimen with a broken value (old or foreign save) is refused, not sold for NaN
	local bad = specs[2]
	bad.Value = "lots"
	step(1.1)
	local cash2 = data.Cash
	preview.fireServerAs(me, "CollectionAction", "Sell", { bad.Id }, 0)
	step()
	eq(data.Cash, cash2)
end)

print("ECONOMY DONE")
