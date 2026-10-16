--!strict
-- Reasons to want eggs (owner ask 2026-10-15: "we need a reason for players to want to buy and earn eggs").
-- Pure rules, tested in tests/test_egg_perks.luau; saved per player in profile EggPerks (Profiles reconciles it).
--
--   Lucky Meter  every shop egg (Robux, coins or free) fills the meter: Basic 1, Rare 3, Mythic 8 points. Full (Need)
--                = the next egg is EPIC or better. Any Epic+ hatch empties it. The pity egg keeps the egg's own
--                Legendary chance, so the 1 in 1000 Void Dragon stays exactly as rare as the odds card says; only
--                Common / Uncommon / Rare turn into Epic. Shown on the egg card (disclosed with the odds).
--   Pet Book pages  one page per zone: every normal pet of that zone (not the chase pet, not weekly pets, so a page
--                can never be lost again). A full page = +10% coins from shells and +10% pet training XP, forever.
--   Free eggs    earned, never bought: every 3rd Pet Battle win = a free Basic Egg; claiming all of today's quests =
--                a free Rare Egg. Banked eggs hatch on their own (same hatch show) as soon as the Pet Book has room.
-- Nothing here changes which hunt egg hides the pet or who finds it.

local Config = require(script.Parent.Config)
local RobuxConfig = require(script.Parent.RobuxConfig)

local EggPerks = {}

EggPerks.Meter = {
	Need = 30,
	Points = { BasicEgg = 1, RareEgg = 3, MythicEgg = 8 } :: { [string]: number }, -- Basic every 30, Rare 10, Mythic 4
	ResetRarity = "Epic", -- a hatch of this rarity or better empties the meter
}
EggPerks.Pages = { CoinsPerPage = 0.1, XpPerPage = 0.1 }
EggPerks.Free = {
	FightWinsPerEgg = 3,
	FightEgg = "BasicEgg",
	QuestEgg = "RareEgg",
	BankMax = 20, -- banked eggs beyond this are not added (a full Pet Book for weeks)
	Order = { "MythicEgg", "RareEgg", "BasicEgg" }, -- best banked egg opens first
}

export type State = { Meter: number, Bank: { [string]: number }, FightWins: number, QuestDay: number, HuntEggs: number? }

function EggPerks.empty(): State
	return { Meter = 0, Bank = {}, FightWins = 0, QuestDay = 0 }
end

local function whole(v: any, lo: number, hi: number): number
	local n = tonumber(v)
	if not n or n ~= n then
		return lo
	end
	return math.clamp(math.floor(n), lo, hi)
end

-- Repairs a saved state IN PLACE (missing or wrong-typed fields) and returns it, so every holder of the table keeps
-- seeing the live state; a non-table becomes a fresh state. Keeps every banked egg of a known kind.
function EggPerks.sanitize(s: any): State
	if type(s) ~= "table" then
		return EggPerks.empty()
	end
	local bank = {}
	if type(s.Bank) == "table" then
		for _, id in EggPerks.Free.Order do
			local n = whole(s.Bank[id], 0, EggPerks.Free.BankMax)
			if n > 0 then
				bank[id] = n
			end
		end
	end
	s.Meter = whole(s.Meter, 0, EggPerks.Meter.Need)
	s.Bank = bank
	s.FightWins = whole(s.FightWins, 0, 1e9)
	s.QuestDay = whole(s.QuestDay, 0, 1e9)
	s.HuntEggs = whole(s.HuntEggs, 0, 1e9) -- hunt eggs toward the next Lucky Meter point (shared/HuntFun)
	return s :: State
end

-- Lucky Meter -------------------------------------------------------------------------------------------------------

local function rank(rarity: any): number
	return table.find(Config.Rarities, rarity) or 0
end

function EggPerks.full(meter: number): boolean
	return meter >= EggPerks.Meter.Need
end

-- The rarity table of a pity egg: Legendary keeps its share of `base` (nil = the race egg odds), everything below
-- Epic becomes Epic. Sums to 100.
function EggPerks.pityWeights(base: { [string]: number }?): { [string]: number }
	local w: any = base or Config.RarityWeights
	local sum = 0
	for _, r in Config.Rarities do
		sum += tonumber(w[r]) or 0
	end
	local legend = if sum > 0 then 100 * (tonumber(w.Legendary) or 0) / sum else 0
	local out: { [string]: number } = {}
	for _, r in Config.Rarities do
		out[r] = 0
	end
	out.Legendary = legend
	out.Epic = 100 - legend
	return out
end

-- The meter after hatching a pet of `rarity` from egg `eggId`.
function EggPerks.meterAfter(meter: number, eggId: string, rarity: string): number
	if rank(rarity) >= rank(EggPerks.Meter.ResetRarity) then
		return 0
	end
	return math.min(meter + (EggPerks.Meter.Points[eggId] or 1), EggPerks.Meter.Need)
end

-- Pet Book pages ----------------------------------------------------------------------------------------------------

-- The pets a zone's page needs: its normal species (not chase, weekly or tower-only), in the zone's order.
function EggPerks.pageSpecies(tierId: string): { string }
	local tier = (Config.Tiers :: any)[tierId]
	local out = {}
	if not tier then
		return out
	end
	for _, id in tier.Minerals do
		local sp: any = (Config.Minerals :: any)[id]
		if sp and not sp.Chase and not sp.Weekly and not sp.TowerOnly then
			table.insert(out, id)
		end
	end
	return out
end

export type Page = { Tier: string, Name: string, Found: number, Need: number, Done: boolean }

function EggPerks.pages(index: any): { Page }
	local out = {}
	for _, tierId in Config.TierOrder do
		local need = EggPerks.pageSpecies(tierId)
		local found = 0
		for _, id in need do
			local v = if type(index) == "table" then index[id] else nil
			if type(v) == "number" and v > 0 then
				found += 1
			end
		end
		table.insert(out, { Tier = tierId, Name = (Config.Tiers :: any)[tierId].Name, Found = found, Need = #need, Done = #need > 0 and found >= #need })
	end
	return out
end

function EggPerks.pagesDone(index: any): number
	local n = 0
	for _, p in EggPerks.pages(index) do
		if p.Done then
			n += 1
		end
	end
	return n
end

function EggPerks.coinMult(index: any): number
	return 1 + EggPerks.Pages.CoinsPerPage * EggPerks.pagesDone(index)
end

function EggPerks.xpMult(index: any): number
	return 1 + EggPerks.Pages.XpPerPage * EggPerks.pagesDone(index)
end

-- The page that `species` just completed (read AFTER its first hatch was counted), or nil.
function EggPerks.pageJustDone(index: any, species: string): Page?
	if type(index) ~= "table" or index[species] ~= 1 then
		return nil
	end
	for _, p in EggPerks.pages(index) do
		if p.Done and table.find(EggPerks.pageSpecies(p.Tier), species) then
			return p
		end
	end
	return nil
end

function EggPerks.eggName(id: string): string
	local e = RobuxConfig.egg(id)
	return if e then e.Name else "Egg"
end

-- Free eggs -----------------------------------------------------------------------------------------------------------

function EggPerks.bankCount(s: State): number
	local n = 0
	for _, v in s.Bank do
		n += v
	end
	return n
end

-- Banks one free egg; false when the bank is full.
function EggPerks.bankAdd(s: State, eggId: string): boolean
	if not table.find(EggPerks.Free.Order, eggId) or EggPerks.bankCount(s) >= EggPerks.Free.BankMax then
		return false
	end
	s.Bank[eggId] = (s.Bank[eggId] or 0) + 1
	return true
end

-- Takes the best banked egg (nil = none).
function EggPerks.bankTake(s: State): string?
	for _, id in EggPerks.Free.Order do
		local n = s.Bank[id]
		if n and n > 0 then
			local bank: { [string]: number? } = s.Bank
			bank[id] = if n > 1 then n - 1 else nil
			return id
		end
	end
	return nil
end

-- A Pet Battle win: the free egg it earns (banked), or nil.
function EggPerks.fightWin(s: State): string?
	s.FightWins += 1
	if s.FightWins % EggPerks.Free.FightWinsPerEgg == 0 then
		if EggPerks.bankAdd(s, EggPerks.Free.FightEgg) then
			return EggPerks.Free.FightEgg
		end
		s.FightWins -= 1 -- bank full: this win doesn't count yet, so the next win earns the egg instead of losing it
	end
	return nil
end

-- Wins still needed for the next fight egg (1..FightWinsPerEgg).
function EggPerks.winsToEgg(s: State): number
	local n = EggPerks.Free.FightWinsPerEgg
	return n - s.FightWins % n
end

-- Every quest of `day` claimed: the free egg it earns (once per day, banked), or nil.
function EggPerks.questsDone(s: State, day: number): string?
	if s.QuestDay == day then
		return nil
	end
	if not EggPerks.bankAdd(s, EggPerks.Free.QuestEgg) then
		return nil -- bank full: today's egg stays unclaimed, so a later call can still pay it
	end
	s.QuestDay = day
	return EggPerks.Free.QuestEgg
end

-- What the client shows (egg cards, Pet Book, battle card).
function EggPerks.view(s: State, index: any): { [string]: any }
	return {
		Meter = s.Meter,
		MeterNeed = EggPerks.Meter.Need,
		MeterPoints = EggPerks.Meter.Points,
		Bank = EggPerks.bankCount(s),
		WinsToEgg = EggPerks.winsToEgg(s),
		QuestEggToday = s.QuestDay,
		Pages = EggPerks.pages(index),
		CoinMult = EggPerks.coinMult(index),
		XpMult = EggPerks.xpMult(index),
	}
end

return EggPerks
