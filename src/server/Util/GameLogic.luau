--!strict
-- What happens to a player's save when they flip, buy, or reset.
-- Pure: takes the profile and plain values, no Roblox objects. Every input
-- that came from a client is `unknown` and is checked here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local ProfileSchema = require(ReplicatedStorage.Shared.Util.ProfileSchema)

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

export type FlipOutcome = { result: FlipResult, cash: number, hats: number, rarity: Types.Rarity }

-- Chain flips: a tap within the window keeps the combo going, else it restarts at 1.
function GameLogic.nextCombo(combo: number, lastTapAt: number, now: number): number
	if combo > 0 and now - lastTapAt <= Config.COMBO_WINDOW then
		return combo + 1
	end
	return 1
end

-- `combo` is the tap's combo (0 for helper/auto flips); `boost` is mega boost x pass.
function GameLogic.applyFlip(
	profile: Profile,
	roll: number,
	rarityRoll: number?,
	boost: number?,
	combo: number?
): FlipOutcome
	local comboCount = combo or 0
	local bonus = Economy.comboMult(comboCount) * (boost or 1)
	local result, cash, hats, rarity = Economy.resolveFlip(profile, roll, rarityRoll, bonus)
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
	if comboCount > profile.stats.bestCombo then
		profile.stats.bestCombo = comboCount
	end
	if rarity ~= "normal" then
		profile.stats.rares += 1
	end
	local outcome: FlipOutcome = { result = result :: FlipResult, cash = cash, hats = hats, rarity = rarity }
	return outcome
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
	local cost = Economy.helperCost(profile.helpers, Economy.maxHelpers(profile))
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

-- Hats: spend hat points, then wear one (or "" to take it off).
function GameLogic.buyHat(profile: Profile, id: unknown): (boolean, string?)
	local def = Economy.hatDef(id)
	if not def then
		return false, "unknown hat"
	end
	if profile.hats[def.id] then
		return false, "already owned"
	end
	if profile.hatPoints < def.cost then
		return false, "not enough hat points"
	end
	profile.hatPoints -= def.cost
	profile.hats[def.id] = true
	profile.hat = def.id -- put it on right away
	return true, nil
end

function GameLogic.wearHat(profile: Profile, id: unknown): boolean
	if id == "" then
		profile.hat = ""
		return true
	end
	if typeof(id) ~= "string" or not profile.hats[id] then
		return false
	end
	profile.hat = id
	return true
end

-- Coin skins are Robux passes: the server checks `owned` before calling this.
function GameLogic.chooseSkin(profile: Profile, id: unknown, owned: boolean): boolean
	if id == "" then
		profile.skin = ""
		return true
	end
	if not ProfileSchema.isSkinId(id) or not owned then
		return false
	end
	profile.skin = id :: string
	return true
end

export type ReceiptResult = "granted" | "duplicate" | "maxed" | "unknown"

-- A Robux developer product purchase. Recording the receipt id makes a retry
-- from Roblox harmless (it is never granted twice).
function GameLogic.grantProduct(profile: Profile, receiptId: string, product: string): ReceiptResult
	if table.find(profile.receipts, receiptId) then
		return "duplicate"
	end
	if product ~= "helperSlot" then
		return "unknown"
	end
	if profile.helperSlots >= Config.MAX_EXTRA_HELPER_SLOTS then
		-- The server refuses to open this purchase when slots are full, so this
		-- only happens on a race. Record it so Roblox stops retrying; the caller logs it.
		table.insert(profile.receipts, receiptId)
		return "maxed"
	end
	profile.helperSlots += 1
	table.insert(profile.receipts, receiptId)
	while #profile.receipts > Config.MAX_SAVED_RECEIPTS do
		table.remove(profile.receipts, 1)
	end
	return "granted"
end

function GameLogic.megaReward(profile: Profile): (number, number)
	local cash, hats = Economy.megaReward(profile)
	profile.cash += cash
	profile.hatPoints += hats
	return cash, hats
end

function GameLogic.snapshot(profile: Profile, passes: { [string]: boolean }?): Snapshot
	local owned: { string } = {}
	for _, def in Config.Hats do
		if profile.hats[def.id] then
			table.insert(owned, def.id)
		end
	end
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
		bestCombo = profile.stats.bestCombo,
		hats = owned,
		hat = profile.hat,
		skin = profile.skin,
		maxHelpers = Economy.maxHelpers(profile),
		passes = if passes then table.clone(passes) else {},
	}
end

-- Studio QA only (Cheats system): fill the table so reset can be tested fast.
function GameLogic.fillTable(profile: Profile)
	profile.upgrades.moreCoins = Config.MAX_COINS - Config.START_COINS
end

return GameLogic
