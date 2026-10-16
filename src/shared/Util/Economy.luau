--!strict
-- All money math, in one pure module (numbers in, numbers out).
-- The server's answer is the real one; the client uses this only to show prices.

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)

type Profile = Types.Profile
type FlipResult = Types.FlipResult
type Rarity = Types.Rarity

local Economy = {}

function Economy.isUpgradeId(id: unknown): boolean
	return typeof(id) == "string" and Config.Upgrades[id] ~= nil
end

-- Cost to go from `level` to `level + 1`, or nil when already maxed.
function Economy.upgradeCost(id: string, level: number): number?
	local def = Config.Upgrades[id]
	if not def or level >= def.maxLevel then
		return nil
	end
	return math.floor(def.baseCost * def.growth ^ level + 0.5)
end

-- Helper slots: the free one, one more at each slot reset, plus Robux slots.
function Economy.maxHelpers(profile: Profile): number
	local slots = Config.MAX_HELPERS
	for _, needed in Config.HELPER_SLOT_RESETS do
		if profile.resets >= needed then
			slots += 1
		end
	end
	return slots + math.min(profile.helperSlots, Config.MAX_EXTRA_HELPER_SLOTS)
end

function Economy.helperDef(id: unknown): Config.HelperDef?
	for _, def in Config.HelperTypes do
		if def.id == id then
			return def
		end
	end
	return nil
end

-- Cash to go from `level` to `level + 1`, or nil at max level.
function Economy.helperLevelCost(def: Config.HelperDef, level: number): number?
	if level >= Config.HELPER_MAX_LEVEL then
		return nil
	end
	return math.floor(def.cost * Config.HELPER_LEVEL_COST * Config.HELPER_LEVEL_GROWTH ^ (level - 1) + 0.5)
end

-- Seconds between this helper's flips.
function Economy.helperInterval(def: Config.HelperDef, level: number): number
	return def.interval * Config.HELPER_LEVEL_SPEED ^ (level - 1)
end

function Economy.helperCashMult(def: Config.HelperDef, level: number): number
	return def.mult * (1 + Config.HELPER_LEVEL_CASH * (level - 1))
end

function Economy.coinCount(profile: Profile): number
	return math.min(Config.MAX_COINS, Config.START_COINS + profile.upgrades.moreCoins)
end

-- Coin spots on the table that are still empty (shown as faint "+" circles).
function Economy.emptySlots(profile: Profile): number
	return Config.MAX_COINS - Economy.coinCount(profile)
end

function Economy.isTableFull(profile: Profile): boolean
	return Economy.coinCount(profile) >= Config.MAX_COINS
end

function Economy.headsChance(luckLevel: number): number
	return math.min(Config.MAX_HEADS_CHANCE, Config.BASE_HEADS_CHANCE + Config.HEADS_CHANCE_PER_LEVEL * luckLevel)
end

-- Coins one tap flips: the one you tapped plus one more per Multi Flip level.
function Economy.flipsPerTap(profile: Profile): number
	return 1 + math.clamp(profile.upgrades.multiFlip, 0, Config.Upgrades.multiFlip.maxLevel)
end

-- What a streak of 10 heads pays: cash (heads worth) and hat points.
-- `boost` is the cash boost (2x pass, mega boost); it only multiplies the cash.
function Economy.streakPrize(profile: Profile, boost: number?): (number, number)
	local cash = Economy.cashPerHeads(profile) * Config.STREAK_PRIZE_FLIPS * math.max(1, boost or 1)
	return math.floor(cash + 0.5), Config.STREAK_PRIZE_HATS
end

function Economy.flipTime(speedLevel: number): number
	return math.max(Config.MIN_FLIP_TIME, Config.BASE_FLIP_TIME - Config.FLIP_TIME_PER_LEVEL * speedLevel)
end

function Economy.coinDiameter(bigLevel: number): number
	return Config.COIN_BASE_DIAMETER + Config.COIN_DIAMETER_PER_LEVEL * bigLevel
end

-- Permanent bonus from resets: 1.0, 1.5, 2.0, ...
function Economy.resetMultiplier(resets: number): number
	return 1 + Config.RESET_CASH_BONUS * resets
end

function Economy.cashPerHeads(profile: Profile): number
	local size = 1 + Config.CASH_PER_BIG_LEVEL * profile.upgrades.bigCoins
	local value = Config.BASE_CASH * size * Economy.resetMultiplier(profile.resets)
	return math.max(1, math.floor(value + 0.5))
end

-- `rarityRoll` in [0, 1) -> which rare coin (rarest gets the lowest numbers).
function Economy.rollRarity(rarityRoll: number): Rarity
	local edge = 0
	for _, def in Config.Rarities do
		edge += def.chance
		if rarityRoll < edge then
			return (def.id :: any) :: Rarity
		end
	end
	local normal: Rarity = "normal"
	return normal
end

-- The smallest roll that lands on `rarity` (Studio test button only).
function Economy.rarityRollFor(rarity: string): number
	local edge = 0
	for _, def in Config.Rarities do
		if def.id == rarity then
			return edge
		end
		edge += def.chance
	end
	return 1
end

function Economy.rarityDef(rarity: string): Config.RarityDef?
	for _, def in Config.Rarities do
		if def.id == rarity then
			return def
		end
	end
	return nil
end

function Economy.rarityMult(rarity: string): number
	local def = Economy.rarityDef(rarity)
	return if def then def.mult else 1
end

-- Chain flips: combo 1 = x1, each step +10%, capped.
function Economy.comboMult(combo: number): number
	if combo <= 1 then
		return 1
	end
	return math.min(Config.COMBO_MAX_MULT, 1 + Config.COMBO_BONUS_PER_STEP * (combo - 1))
end

-- `roll` and `rarityRoll` are numbers in [0, 1) from the server's random generator.
-- `cashBonus` stacks combo, mega boost and the 2x pass (heads cash only).
-- Returns result, cash, hat points, rarity.
function Economy.resolveFlip(
	profile: Profile,
	roll: number,
	rarityRoll: number?,
	cashBonus: number?
): (FlipResult, number, number, Rarity)
	local heads: FlipResult = "heads"
	local skull: FlipResult = "skull"
	local rarity: Rarity = Economy.rollRarity(rarityRoll or 1)
	local mult = Economy.rarityMult(rarity)
	if roll < Economy.headsChance(profile.upgrades.luck) then
		local bonus = math.max(1, cashBonus or 1)
		return heads, math.floor(Economy.cashPerHeads(profile) * mult * bonus + 0.5), 0, rarity :: Rarity
	end
	return skull, 0, mult, rarity :: Rarity
end

-- Taps the whole server needs to flip the mega coin.
function Economy.megaGoal(playerCount: number): number
	return Config.MEGA_BASE_TAPS + Config.MEGA_TAPS_PER_PLAYER * math.max(1, playerCount)
end

-- What each player who tapped the mega coin gets when it flips.
function Economy.megaReward(profile: Profile): (number, number)
	return Economy.cashPerHeads(profile) * Config.MEGA_REWARD_FLIPS, Config.MEGA_REWARD_HATS
end

function Economy.hatDef(id: unknown): Config.HatDef?
	for _, def in Config.Hats do
		if def.id == id then
			return def
		end
	end
	return nil
end

function Economy.skinDef(id: unknown): Config.SkinDef?
	for _, def in Config.Skins do
		if def.id == id then
			return def
		end
	end
	return nil
end

-- OrderedDataStore only takes whole numbers in a safe range.
function Economy.leaderboardValue(value: number): number
	if value ~= value or value <= 0 then
		return 0
	end
	return math.min(math.floor(value), 2 ^ 53)
end

-- Average cash per second the whole team makes together.
function Economy.helperCashPerSecond(profile: Profile): number
	local perHeads = Economy.headsChance(profile.upgrades.luck) * Economy.cashPerHeads(profile)
	local total = 0
	for _, id in profile.team do
		local def = Economy.helperDef(id)
		local level = profile.crew[id]
		if def and level then
			total += perHeads * Economy.helperCashMult(def, level) / Economy.helperInterval(def, level)
		end
	end
	return total
end

-- Cash earned by helpers while away. Clamped so clock tricks can't farm it.
function Economy.offlineEarnings(profile: Profile, elapsedSeconds: number): number
	if elapsedSeconds ~= elapsedSeconds or elapsedSeconds <= 0 then
		return 0
	end
	local seconds = math.min(elapsedSeconds, Config.OFFLINE_CAP_SECONDS)
	return math.floor(Economy.helperCashPerSecond(profile) * seconds * Config.OFFLINE_RATE)
end

-- Which table look (1-based) a player with `resets` resets gets.
-- Index of the table look called `name` (1 when the name is unknown).
function Economy.tableLookNamed(name: string): number
	for i, look in Config.TableLooks do
		if look.name == name then
			return i
		end
	end
	return 1
end

function Economy.tableLook(resets: number): number
	return (resets % #Config.TableLooks) + 1
end

return Economy
