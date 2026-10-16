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

function Economy.helperCost(owned: number): number?
	if owned >= Config.MAX_HELPERS then
		return nil
	end
	return math.floor(Config.HELPER_COST * 4 ^ owned + 0.5)
end

function Economy.coinCount(profile: Profile): number
	return math.min(Config.MAX_COINS, Config.START_COINS + profile.upgrades.moreCoins)
end

function Economy.isTableFull(profile: Profile): boolean
	return Economy.coinCount(profile) >= Config.MAX_COINS
end

function Economy.headsChance(luckLevel: number): number
	return math.min(Config.MAX_HEADS_CHANCE, Config.BASE_HEADS_CHANCE + Config.HEADS_CHANCE_PER_LEVEL * luckLevel)
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
			return def.id :: Rarity
		end
	end
	return "normal"
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

-- `roll` and `rarityRoll` are numbers in [0, 1) from the server's random generator.
-- Returns result, cash, hat points, rarity.
function Economy.resolveFlip(profile: Profile, roll: number, rarityRoll: number?): (FlipResult, number, number, Rarity)
	local heads: FlipResult = "heads"
	local skull: FlipResult = "skull"
	local rarity = Economy.rollRarity(rarityRoll or 1)
	local mult = Economy.rarityMult(rarity)
	if roll < Economy.headsChance(profile.upgrades.luck) then
		return heads, Economy.cashPerHeads(profile) * mult, 0, rarity
	end
	return skull, 0, mult, rarity
end

-- Average cash per second all helpers make together.
function Economy.helperCashPerSecond(profile: Profile): number
	if profile.helpers <= 0 then
		return 0
	end
	local perFlip = Economy.headsChance(profile.upgrades.luck) * Economy.cashPerHeads(profile)
	return profile.helpers * perFlip / Config.HELPER_FLIP_INTERVAL
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
function Economy.tableLook(resets: number): number
	return (resets % #Config.TableLooks) + 1
end

return Economy
