--!strict
-- Robux shop tuning (owner decision 2026-10-11): paid pet eggs, 15-minute luck potions and three game passes, plus
-- the free luck events (2x luck every UTC weekend, random server-wide "luck storms"). Everything the owner may want
-- to tune is in this file. The pure helpers below (receipt ledger, pass effects, product lookup) are shared by the
-- server (RobuxService, Profiles) and the shop panel, and are tested offline (tests/test_robux.luau).
--
-- IDS: every ProductId / PassId is 0 until the owner creates the product or pass on the Creator Hub and pastes its id
-- here (docs/OWNER_STEPS.md, "Robux shop"). An id of 0 is never prompted or granted; the shop shows "NOT FOR SALE
-- YET". Prices are never written here: the shop reads them from Roblox (MarketplaceService:GetProductInfo).

local Config = require(script.Parent.Config)

local RobuxConfig = {}

-- Paid eggs (owner, 2026-10-11): Basic, Rare and Mythic, each sold as 1x, 3x and 10x (a separate Developer Product per
-- count). Every egg hatches pets of the buyer's best unlocked zone (its species pool, equal chance) with their normal
-- boost, through GeodeGen.roll: same variant, pose and size odds as a race egg. Rarity: Basic uses the race egg odds
-- (Config.RarityWeights, Legendary 1 in 1000); Rare and Mythic use the better tables below (every rarity can still roll,
-- each table sums to 100). The shop prints the full odds on the egg card above the buy buttons.
-- A 3x / 10x buy is ONE receipt that grants 3 / 10 rolls; it is refused before the prompt if the Pet Book has no room.
-- Image: an owner picture of the egg for the shop (asset id; 0 / nil = the drawn 3D egg).
-- Limited eggs (owner pick 2026-10-15, idea 46): Limited = true, sold only while os.time() < EndsAt (0 = not on sale;
-- the shop hides it). ShinyOneIn: this egg's shiny chance (1 in N; nil = LaunchPerks.Shiny.OneIn).
export type Egg = {
	Id: string,
	Name: string,
	Rarity: { [string]: number }?,
	Products: { [number]: number },
	Image: number?,
	Limited: boolean?,
	EndsAt: number?,
	ShinyOneIn: number?,
}
RobuxConfig.EggCounts = { 1, 3, 10 }
RobuxConfig.Eggs = {
	-- Rarity = nil: the race egg odds (Config.RarityWeights)
	{ Id = "BasicEgg", Name = "Basic Egg", Rarity = nil, Products = { [1] = 0, [3] = 0, [10] = 0 } }, -- REPLACE the three Developer Product ids
	{
		Id = "RareEgg", Name = "Rare Egg",
		Rarity = { Common = 30, Uncommon = 35, Rare = 25, Epic = 9.5, Legendary = 0.5 },
		Products = { [1] = 0, [3] = 0, [10] = 0 }, -- REPLACE
	},
	{
		Id = "MythicEgg", Name = "Mythic Egg",
		Rarity = { Common = 11, Uncommon = 25, Rare = 40, Epic = 23, Legendary = 1 }, -- Legendary 1 in 100 (owner pick)
		Products = { [1] = 0, [3] = 0, [10] = 0 }, -- REPLACE
	},
} :: { Egg }

-- Limited-time eggs (idea 46), kept out of RobuxConfig.Eggs so the normal shop cards stay as they are; the shop shows
-- one as its own timed card (LaunchPerks.limitedView). RobuxConfig.egg / productKind find them too.
RobuxConfig.LimitedEggs = {
	-- Limited-time egg (idea 46): the Rare Egg's odds (never worse than race odds) plus a 1 in 10 shiny chance, sold
	-- only until EndsAt (unix seconds, UTC; 0 keeps it hidden). Product ids: carter's Creator Hub (2026-10-15).
	{
		Id = "SpookyEgg", Name = "Spooky Egg",
		Rarity = { Common = 30, Uncommon = 35, Rare = 25, Epic = 9.5, Legendary = 0.5 },
		Products = { [1] = 3718841224, [3] = 3718841562, [10] = 3718841645 },
		Limited = true,
		-- 1793577600 = 2026-11-02 00:00 UTC, the day after Halloween (default end, no date given by carter yet)
		EndsAt = 1793577600,
		ShinyOneIn = 10,
	},
} :: { Egg }

-- Is this egg sold right now? Every normal egg is; a limited egg only before its EndsAt.
function RobuxConfig.eggOnSale(egg: Egg, now: number): boolean
	if not egg.Limited then
		return true
	end
	return type(egg.EndsAt) == "number" and now < (egg.EndsAt :: number)
end

-- COIN eggs at the lobby EGG SHRINE (the hatch stand; owner choice 2026-10-14). The same three eggs (same odds, same
-- best-zone pets, same hatch show) for in-game coins. Robux never buys coins, so this never lets Robux buy pets
-- another way; the Robux eggs above stay as they are.
--
-- Price reasoning (Config.Tiers, Config.RarityWeights / RarityMult / ModifierMult / MassBands):
--   * A round's pay = the shells of the eggs you crack + the pet you find. The 150-egg pile hides the pet egg
--     anywhere, so on average it turns up about halfway: a solo hunter cracks about RoundEggs = 75 eggs, worth
--     75 x CashPerRubble coins (Meadow 150, Forest 375, Snow 900, Volcano 1875, Space 3750), and finds one race pet
--     worth on average GeodeBase x 1.55 (rarity) x 1.08 (variant) x 1.49 (size) = about 2.5 x GeodeBase if sold
--     (Meadow ~100, Space ~10000). So one round pays about: Meadow 250, Forest 750, Snow 2150, Volcano 5600,
--     Space 13700 coins (a party splits the shells, so party rounds pay less each).
--   * Upgrades for scale: Treat Bag 150, Forest unlock 500, Pet Whistle 1200, Snow unlock 3000, Auto Nest
--     6000, Volcano 25000, Space 100000, Mega Incubator 180000 (tests/test_grind_speed.luau paces them). A tower run to floor 10 pays about 15 x 55 = 825 + bosses.
--   * Basic egg = 1.5 rounds, Rare = 5x Basic, Mythic = 15x Basic (Rounds below), priced for the zone the egg hatches
--     from (the buyer's best zone, eggTier), rounded to two significant digits. Prices per egg:
--         zone     Basic   Rare     Mythic
--         Meadow     370    1,900    5,600
--         Forest   1,100    5,600   17,000
--         Snow     3,200   16,000   48,000
--         Volcano  8,400   42,000  130,000
--         Space   21,000  100,000  310,000
--     Every egg costs more than its pet sells for on average (the sell price is the pet's Value), so buying eggs to
--     sell the pets loses coins (checked in tests/test_coin_eggs.luau). 3x / 10x cost exactly 3 / 10 eggs (no bulk
--     discount, no surprises).
RobuxConfig.CoinEggs = {
	Panel = "EggShrine", -- client panel the shrine prompt opens (Main.client panels table)
	Counts = { 1, 3, 10 },
	RoundEggs = 75, -- eggs a solo hunter cracks in an average round (half the 150-egg pile)
	Rounds = { BasicEgg = 1.5, RareEgg = 7.5, MythicEgg = 22.5 }, -- rounds of coins per egg (Basic x1, x5, x15)
}

-- false: a bought egg uses the plain odds (exactly the odds printed on the card). true: the buyer's current luck
-- (pets, potion, weekend, storm; never friends luck) applies too, and the card shows the odds with that luck.
RobuxConfig.EggsUseLuck = false

-- Public hatch stand (owner pick): every bought egg is cracked at the stand by the shop (a part with attribute
-- HatchStand = true and an Attachment "HatchPoint") for everyone to watch, one show after another.
RobuxConfig.Show = {
	Seconds = 6, -- one show (egg wobble, crack, pet reveal) before the next one starts
	QueueMax = 25, -- shows waiting beyond this are skipped (the pets are granted anyway)
}

-- Luck potion: each one adds Seconds of potion time (stacking purchases extend the timer). The timer is server time
-- (os.time, UTC) saved in the profile, so it keeps running while the player is offline.
RobuxConfig.Potion = {
	Id = "LuckPotion",
	Name = "Luck Potion",
	ProductId = 0, -- REPLACE with the Developer Product id
	Seconds = 15 * 60,
	Luck = 1, -- +1 luck = Rare and better pets twice as likely (GeodeGen.rarityWeights)
	MaxStackSeconds = 6 * 60 * 60, -- no new potion can be bought while more than this is left
}

-- Game passes. Owned passes are remembered in the profile (Robux.Passes) and re-checked on join.
export type Pass = { Key: string, Name: string, PassId: number, Desc: string }
RobuxConfig.Passes = {
	DoubleCoins = { Key = "DoubleCoins", Name = "2x Coins", PassId = 0, Desc = "Candy sells for twice the coins." }, -- REPLACE
	ExtraPlots = { Key = "ExtraPlots", Name = "Extra Plots", PassId = 0, Desc = "10 more pet display spots on your plot." }, -- REPLACE
	PetStorage = { Key = "PetStorage", Name = "Pet Storage+", PassId = 0, Desc = "Keep more pets in your Pet Book." }, -- REPLACE
} :: { [string]: Pass }
RobuxConfig.Passes.VIP = { Key = "VIP", Name = "VIP", PassId = 2039996496, Desc = "Gold VIP name tag and +50% luck on every pet." }
RobuxConfig.Passes.AutoHatch = { Key = "AutoHatch", Name = "Auto Hatch", PassId = 2040326268, Desc = "The Egg Shrine keeps hatching your egg for you." }
RobuxConfig.Passes.TripleHatch = { Key = "TripleHatch", Name = "Open 3 Eggs", PassId = 2036792742, Desc = "Hatch 3 or 10 coin eggs at once." }
RobuxConfig.PassOrder = { "VIP", "DoubleCoins", "TripleHatch", "AutoHatch", "PetStorage", "ExtraPlots" }
RobuxConfig.VipLuck = 0.5 -- VIP: +0.5 luck (Rare and better pets 1.5x as likely), added like any other luck source

-- Coin egg counts that need a pass (idea 44). While that pass is still unsold (PassId 0) nobody is locked out.
RobuxConfig.CountPass = { [3] = "TripleHatch", [10] = "TripleHatch" } :: { [number]: string }

-- Auto hatch (idea 43): with the pass, the shrine re-buys the same coin egg every Show.Seconds while the player stays
-- near it, has the coins and Pet Book room. Stops after MaxHatches buys, on any refusal or when the player walks away.
RobuxConfig.Auto = { Every = 6, MaxHatches = 200 }

-- Starter pack (idea 41): one Developer Product, one buy per player (the shop hides it once bought; a receipt that
-- still arrives is granted anyway). 3 Rare Eggs (hatched like bought eggs) + 30 minutes of luck potion.
RobuxConfig.StarterPack = {
	Id = "StarterPack",
	Name = "Starter Pack",
	ProductId = 3718841132, -- carter's Creator Hub (2026-10-15)
	Eggs = { RareEgg = 3 } :: { [string]: number },
	PotionSeconds = 30 * 60,
}
RobuxConfig.CoinMult = 2 -- DoubleCoins: shell sell cash x2 (after the pet Coins boost)
RobuxConfig.ExtraPetSlots = 250 -- PetStorage: Pet Book holds Config.Inventory.Max + this
RobuxConfig.ExtraDisplaySlots = 10 -- ExtraPlots: display spots on the player's plot beyond the bought Config.Display level

-- Free luck events (LuckEvents). Luck is the GeodeGen "luck" number: +1 doubles the odds of Rare and better.
RobuxConfig.Events = {
	WeekendLuck = 1, -- every Saturday and Sunday (UTC): 2x luck for everyone
	StormLuck = 1, -- a luck storm: 2x luck for everyone on this server
	StormSeconds = 15 * 60,
	StormGapMin = 45 * 60, -- quiet time between storms (random in [min, max])
	StormGapMax = 120 * 60,
	FirstStormMin = 10 * 60, -- the first storm of a fresh server
	-- Lucky hour (idea 45): 2x luck for everyone, every day at these UTC hours (17 = 1 pm US East, 23 = 7 pm US East)
	LuckyHours = { 17, 23 },
	LuckyHourLuck = 1,
	LuckyHourMinutes = 60,
}

-- All luck sources add up (pets + friends + potion + weekend + storm) and the total is clamped here.
-- 4 = Rare and better weights at most 5x (owner pick: weekend + storm + potion = 3, so pet and friends luck still
-- count on top). Common/Uncommon weights don't scale, so Legendary at best is about 1 in 300, not 1 in 200.
RobuxConfig.MaxLuck = 4

RobuxConfig.ReceiptsKept = 300 -- newest PurchaseIds remembered per profile (Roblox retries recent receipts only)

-- Pure helpers -------------------------------------------------------------------------------------------------------

function RobuxConfig.emptyState(): { [string]: any }
	return { Receipts = {}, ReceiptOrder = {}, LuckUntil = 0, Passes = {}, EggsBought = 0, PotionsBought = 0, StarterPack = false }
end

-- Repairs a saved Robux table (missing or wrong-typed fields); never drops a receipt or an owned pass.
function RobuxConfig.sanitize(state: any): { [string]: any }
	local def = RobuxConfig.emptyState()
	if type(state) ~= "table" then
		return def
	end
	for k, v in def do
		if type(state[k]) ~= type(v) or (type(v) == "number" and state[k] ~= state[k]) then
			state[k] = v
		end
	end
	for k, v in state.Passes do
		if type(k) ~= "string" or v ~= true then
			state.Passes[k] = nil
		end
	end
	return state
end

function RobuxConfig.egg(id: any): Egg?
	for _, e in RobuxConfig.Eggs do
		if e.Id == id then
			return e
		end
	end
	for _, e in RobuxConfig.LimitedEggs do
		if e.Id == id then
			return e
		end
	end
	return nil
end

-- Base rarity weights of an egg (nil Rarity = the race egg odds).
function RobuxConfig.eggRarity(egg: Egg): { [string]: number }
	return egg.Rarity or (Config.RarityWeights :: any)
end

-- The zone a bought egg hatches from: the buyer's best unlocked zone (highest Order), Meadow when none.
function RobuxConfig.eggTier(unlocked: any): string
	local best, bestOrder = "Gravel", -math.huge
	for id, t in Config.Tiers :: any do
		if type(unlocked) == "table" and unlocked[id] and t.Order > bestOrder then
			best, bestOrder = id, t.Order
		end
	end
	return best
end

-- Coin eggs ------------------------------------------------------------------------------------------------------------

local function weightedMean(weights: { [string]: number }, mult: { [string]: number }): number
	local sum, total = 0, 0
	for k, w in weights do
		sum += w * (mult[k] or 1)
		total += w
	end
	return if total > 0 then sum / total else 1
end

-- Average sell value of a pet from an egg with these rarity weights in this zone (GeodeGen.value averaged over the
-- rarity, variant and size rolls).
function RobuxConfig.petMeanValue(tierId: string, rarity: { [string]: number }?): number
	local tier = (Config.Tiers :: any)[tierId]
	if not tier then
		return 0
	end
	local massW, mass = 0, 0
	for _, b in Config.MassBands do
		massW += b.Weight
		mass += b.Weight * (b.Min + b.Max) / 2
	end
	local meanMass = if massW > 0 then mass / massW else 1
	return tier.GeodeBase
		* weightedMean(rarity or (Config.RarityWeights :: any), Config.RarityMult :: any)
		* weightedMean(Config.ModifierWeights :: any, Config.ModifierMult :: any)
		* (0.75 + 0.25 * meanMass)
end

-- Coins an average solo round in this zone pays: the shells of RoundEggs eggs plus the race pet's average value.
function RobuxConfig.roundCoins(tierId: string): number
	local tier = (Config.Tiers :: any)[tierId]
	if not tier then
		return 0
	end
	return RobuxConfig.CoinEggs.RoundEggs * tier.CashPerRubble + RobuxConfig.petMeanValue(tierId, nil)
end

-- x rounded to two significant digits (374 -> 370, 20576 -> 21000).
local function nice(x: number): number
	if x <= 0 then
		return 0
	end
	local step = 10 ^ math.max(0, math.floor(math.log10(x)) - 1)
	return math.floor(x / step + 0.5) * step
end

-- Coin price of `count` eggs of this kind hatching from zone tierId; nil for an unknown egg / zone or a count the
-- shrine does not sell.
function RobuxConfig.eggCoinPrice(eggId: any, tierId: string, count: any): number?
	local rounds = RobuxConfig.CoinEggs.Rounds[eggId]
	if type(rounds) ~= "number" or not RobuxConfig.egg(eggId) or not (Config.Tiers :: any)[tierId] then
		return nil
	end
	if type(count) ~= "number" or not table.find(RobuxConfig.CoinEggs.Counts, count) then
		return nil
	end
	return count * nice(rounds * RobuxConfig.roundCoins(tierId))
end

-- The Pet Book refusal shared by both egg shops (nil = room for n more pets).
function RobuxConfig.roomRefusal(room: number, n: number): string?
	if room >= n then
		return nil
	end
	return if room <= 0 then "Your Pet Book is full." else "Your Pet Book only has room for " .. room .. " more pets."
end

-- Checks a coin egg buy (everything but the PolicyService gate, which the server checks first). Returns the price, or
-- nil and the refusal text (nil text = a malformed request, refused silently).
function RobuxConfig.coinEggCheck(eggId: any, count: any, tierId: string, cash: number, room: number): (number?, string?)
	local price = RobuxConfig.eggCoinPrice(eggId, tierId, count)
	if not price then
		return nil, nil
	end
	local full = RobuxConfig.roomRefusal(room, count)
	if full then
		return nil, full
	end
	if not (type(cash) == "number" and cash >= price) then
		return nil, "Need " .. (price - (if type(cash) == "number" then cash else 0)) .. " more coins."
	end
	return price, nil
end

-- The label, enabled flag and style of one coin buy button (client panel): "3x 1,500", a pending dots, "NO ROOM", or
-- "NEED N" (how many more coins) in gray. `fmt` formats numbers (UI.num).
function RobuxConfig.coinButton(count: number, price: number, cash: number, room: number, pending: boolean, fmt: (number) -> string): (string, boolean, string)
	if pending then
		return "\u{2026}", false, "gold"
	elseif room < count then
		return count .. "x  NO ROOM", false, "gold"
	elseif cash < price then
		return count .. "x  NEED " .. fmt(price - cash), true, "gray"
	end
	return count .. "x  " .. fmt(price), true, "gold"
end

-- What a Developer Product id buys: ("Egg", egg, count) | ("Potion", potion, 1) | nil. Id 0 (not created yet)
-- matches nothing.
-- Retired product ids whose late receipts must still grant: [oldId] = { Kind = "Egg", Egg = <egg id>, Count = n } or
-- { Kind = "Potion" }. Empty until an id is ever changed (only ever filled with ids the owner really used).
RobuxConfig.LegacyProducts = {} :: { [number]: { Kind: string, Egg: string?, Count: number? } }

function RobuxConfig.productKind(productId: any): (string?, any, number)
	if type(productId) ~= "number" or productId <= 0 then
		return nil, nil, 0
	end
	for _, list in { RobuxConfig.Eggs, RobuxConfig.LimitedEggs } do
		for _, e in list do
			for _, n in RobuxConfig.EggCounts do
				if e.Products[n] == productId then
					return "Egg", e, n
				end
			end
		end
	end
	if RobuxConfig.Potion.ProductId == productId then
		return "Potion", RobuxConfig.Potion, 1
	end
	if RobuxConfig.StarterPack.ProductId == productId then
		return "Pack", RobuxConfig.StarterPack, 1
	end
	local old = RobuxConfig.LegacyProducts[productId]
	if old then
		if old.Kind == "Potion" then
			return "Potion", RobuxConfig.Potion, 1
		end
		local egg = if old.Egg then RobuxConfig.egg(old.Egg) else nil
		if egg and old.Count and table.find(RobuxConfig.EggCounts, old.Count) then
			return "Egg", egg, old.Count
		end
	end
	return nil, nil, 0
end

function RobuxConfig.passKey(passId: any): string?
	if type(passId) ~= "number" or passId <= 0 then
		return nil
	end
	for key, p in RobuxConfig.Passes do
		if p.PassId == passId then
			return key
		end
	end
	return nil
end

-- Receipt ledger: true if this PurchaseId was already granted. remember() keeps the newest ReceiptsKept ids.
function RobuxConfig.granted(state: any, purchaseId: string): boolean
	return state.Receipts[purchaseId] == true
end

function RobuxConfig.remember(state: any, purchaseId: string)
	if state.Receipts[purchaseId] then
		return
	end
	state.Receipts[purchaseId] = true
	table.insert(state.ReceiptOrder, purchaseId)
	while #state.ReceiptOrder > RobuxConfig.ReceiptsKept do
		local old = table.remove(state.ReceiptOrder, 1)
		if old then
			state.Receipts[old] = nil
		end
	end
end

-- The pass a coin egg count needs, or nil (free for everyone, or that pass is not on sale yet).
function RobuxConfig.countPass(count: number): string?
	local key = RobuxConfig.CountPass[count]
	local pass = if key then RobuxConfig.Passes[key] else nil
	return if pass and pass.PassId > 0 then key else nil
end

function RobuxConfig.vipLuck(state: any): number
	return if RobuxConfig.hasPass(state, "VIP") then RobuxConfig.VipLuck else 0
end

-- One potion: the timer runs from now (or from the current end if one is still running).
function RobuxConfig.addPotion(state: any, now: number, seconds: number?)
	state.LuckUntil = math.max(state.LuckUntil or 0, now) + (seconds or RobuxConfig.Potion.Seconds)
	state.PotionsBought = (state.PotionsBought or 0) + 1
end

function RobuxConfig.potionLeft(state: any, now: number): number
	return math.max(0, (if type(state) == "table" then tonumber(state.LuckUntil) or 0 else 0) - now)
end

function RobuxConfig.hasPass(state: any, key: string): boolean
	return type(state) == "table" and type(state.Passes) == "table" and state.Passes[key] == true
end

function RobuxConfig.coinMult(state: any): number
	return if RobuxConfig.hasPass(state, "DoubleCoins") then RobuxConfig.CoinMult else 1
end

function RobuxConfig.inventoryMax(base: number, state: any): number
	return base + (if RobuxConfig.hasPass(state, "PetStorage") then RobuxConfig.ExtraPetSlots else 0)
end

-- Plot display spots: the bought display level plus the ExtraPlots pass (extra pets stand in the plot yard).
function RobuxConfig.displaySlots(base: number, state: any): number
	return base + (if RobuxConfig.hasPass(state, "ExtraPlots") then RobuxConfig.ExtraDisplaySlots else 0)
end

return RobuxConfig
