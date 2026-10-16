--!strict
-- What happens to a player's save when they flip, buy, or reset.
-- Pure: takes the profile and plain values, no Roblox objects. Every input
-- that came from a client is `unknown` and is checked here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)

type Profile = Types.Profile
type FlipResult = Types.FlipResult
type Snapshot = Types.Snapshot

local GameLogic = {}

-- A tapped coin number from the client -> a safe index, or nil.
function GameLogic.validateCoinIndex(index: unknown, coinCount: number): number?
	if typeof(index) ~= "number" then
		return nil
	end
	if index ~= index or index ~= math.floor(index) then
		return nil -- NaN, infinity or a fraction
	end
	if index < 1 or index > coinCount then
		return nil
	end
	return index
end

export type FlipOutcome = { result: FlipResult, cash: number, hats: number }

function GameLogic.applyFlip(profile: Profile, roll: number): FlipOutcome
	local result, cash, hats = Economy.resolveFlip(profile, roll)
	profile.cash += cash
	profile.hatPoints += hats
	profile.stats.flips += 1
	if result == "heads" then
		profile.stats.heads += 1
	else
		profile.stats.skulls += 1
	end
	if cash > profile.stats.biggestFlip then
		profile.stats.biggestFlip = cash
	end
	return { result = result, cash = cash, hats = hats }
end

function GameLogic.buyUpgrade(profile: Profile, id: unknown): (boolean, string?)
	if not Economy.isUpgradeId(id) then
		return false, "unknown upgrade"
	end
	local upgradeId = id :: Types.UpgradeId
	local level = profile.upgrades[upgradeId]
	local cost = Economy.upgradeCost(upgradeId, level)
	if not cost then
		return false, "maxed"
	end
	if profile.cash < cost then
		return false, "not enough cash"
	end
	profile.cash -= cost
	profile.upgrades[upgradeId] = level + 1
	return true, nil
end

function GameLogic.buyHelper(profile: Profile): (boolean, string?)
	local cost = Economy.helperCost(profile.helpers)
	if not cost then
		return false, "no free helper slot"
	end
	if profile.cash < cost then
		return false, "not enough cash"
	end
	profile.cash -= cost
	profile.helpers += 1
	return true, nil
end

-- Reset (prestige): table must be full. You lose cash + upgrades, and keep
-- helpers, hat points and stats. You gain a permanent cash bonus and a new look.
function GameLogic.reset(profile: Profile): (boolean, string?)
	if not Economy.isTableFull(profile) then
		return false, "table not full"
	end
	profile.resets += 1
	profile.cash = 0
	profile.upgrades.moreCoins = 0
	profile.upgrades.bigCoins = 0
	profile.upgrades.luck = 0
	profile.upgrades.speed = 0
	return true, nil
end

-- Offline helper bonus on join. Returns cash given. Also stamps lastSeen.
function GameLogic.applyOffline(profile: Profile, now: number): number
	local earned = 0
	if profile.lastSeen > 0 then
		earned = Economy.offlineEarnings(profile, now - profile.lastSeen)
	end
	profile.cash += earned
	profile.lastSeen = now
	return earned
end

function GameLogic.snapshot(profile: Profile): Snapshot
	return {
		cash = profile.cash,
		hatPoints = profile.hatPoints,
		upgrades = table.clone(profile.upgrades),
		helpers = profile.helpers,
		resets = profile.resets,
		flips = profile.stats.flips,
		biggestFlip = profile.stats.biggestFlip,
		coinCount = Economy.coinCount(profile),
		tableFull = Economy.isTableFull(profile),
		cashPerHeads = Economy.cashPerHeads(profile),
		headsChance = Economy.headsChance(profile.upgrades.luck),
		resetBonus = Economy.resetMultiplier(profile.resets + 1),
	}
end

-- Studio QA only (Cheats system): fill the table so reset can be tested fast.
function GameLogic.fillTable(profile: Profile)
	profile.upgrades.moreCoins = Config.MAX_COINS - Config.START_COINS
end

return GameLogic
