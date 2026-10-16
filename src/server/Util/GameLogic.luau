--!strict
-- What happens to a player's save when they flip, buy, or reset.
-- Pure: takes the profile and plain values, no Roblox objects. Every input
-- that came from a client is `unknown` and is checked here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local Format = require(ReplicatedStorage.Shared.Util.Format)
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
	local outcome: FlipOutcome =
		{ result = result :: FlipResult, cash = cash, hats = hats, rarity = rarity :: Types.Rarity }
	return outcome
end

export type StreakOutcome = {
	streak: number, -- heads in a row to show after this flip
	nextStreak: number, -- what the table remembers (0 after a win)
	won: boolean,
	cash: number,
	hats: number,
}

-- Call once per flip of the player's OWN tap, in flip order, after applyFlip.
-- Heads grows the streak, a skull breaks it. Hitting the goal pays the prize
-- once and starts over. The server decides; nothing here is random.
function GameLogic.applyStreak(profile: Profile, streak: number, result: FlipResult, boost: number?): StreakOutcome
	if result ~= "heads" then
		return { streak = 0, nextStreak = 0, won = false, cash = 0, hats = 0 }
	end
	local count = streak + 1
	if count > profile.stats.bestStreak then
		profile.stats.bestStreak = math.min(count, Config.STREAK_GOAL)
	end
	if count < Config.STREAK_GOAL then
		return { streak = count, nextStreak = count, won = false, cash = 0, hats = 0 }
	end
	local cash, hats = Economy.streakPrize(profile, boost)
	profile.cash += cash
	profile.hatPoints += hats
	profile.stats.streakWins += 1
	return { streak = count, nextStreak = 0, won = true, cash = cash, hats = hats }
end

-- Multi Flip: which coins one tap flips. The tapped coin first, then the next
-- idle coins in table order (wrapping), up to `count` in all.
function GameLogic.pickTapCoins(tapped: number, busyUntil: { number }, now: number, count: number): { number }
	local picked = { tapped }
	local total = #busyUntil
	for step = 1, total - 1 do
		if #picked >= count then
			break
		end
		local index = (tapped - 1 + step) % total + 1
		if now >= busyUntil[index] then
			table.insert(picked, index)
		end
	end
	return picked
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

-- Unlock a new helper guy with cash. He joins the team if a slot is free.
function GameLogic.unlockHelper(profile: Profile, id: unknown): (boolean, string?)
	local def = Economy.helperDef(id)
	if not def then
		return false, "unknown helper"
	end
	if profile.crew[def.id] then
		return false, "already owned"
	end
	if profile.resets < def.resets then
		return false, "needs more resets"
	end
	if profile.cash < def.cost then
		return false, "not enough cash"
	end
	profile.cash -= def.cost
	profile.crew[def.id] = 1
	if #profile.team < Economy.maxHelpers(profile) then
		table.insert(profile.team, def.id)
	end
	return true, nil
end

function GameLogic.levelHelper(profile: Profile, id: unknown): (boolean, string?)
	local def = Economy.helperDef(id)
	local level = def and profile.crew[def.id]
	if not def or not level then
		return false, "not owned"
	end
	local cost = Economy.helperLevelCost(def, level)
	if not cost then
		return false, "maxed"
	end
	if profile.cash < cost then
		return false, "not enough cash"
	end
	profile.cash -= cost
	profile.crew[def.id] = level + 1
	return true, nil
end

-- Put a helper you own on the team (needs a free slot), or take him off.
function GameLogic.setTeam(profile: Profile, id: unknown, on: unknown): (boolean, string?)
	if typeof(id) ~= "string" or not profile.crew[id] or typeof(on) ~= "boolean" then
		return false, "not owned"
	end
	local at = table.find(profile.team, id)
	if not on then
		if at then
			table.remove(profile.team, at)
		end
		return true, nil
	end
	if at then
		return true, nil
	end
	if #profile.team >= Economy.maxHelpers(profile) then
		return false, "no free slot"
	end
	table.insert(profile.team, id)
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
	profile.upgrades.multiFlip = 0
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
		crew = table.clone(profile.crew),
		team = table.clone(profile.team),
		resets = profile.resets,
		flips = profile.stats.flips,
		biggestFlip = profile.stats.biggestFlip,
		coinCount = Economy.coinCount(profile),
		tableFull = Economy.isTableFull(profile),
		cashPerHeads = Economy.cashPerHeads(profile),
		headsChance = Economy.headsChance(profile.upgrades.luck),
		resetBonus = Economy.resetMultiplier(profile.resets + 1),
		bestCombo = profile.stats.bestCombo,
		bestStreak = profile.stats.bestStreak,
		streakGoal = Config.STREAK_GOAL,
		flipsPerTap = Economy.flipsPerTap(profile),
		hats = owned,
		hat = profile.hat,
		skin = profile.skin,
		maxHelpers = Economy.maxHelpers(profile),
		helperSlots = profile.helperSlots,
		passes = if passes then table.clone(passes) else {},
	}
end

-- Studio QA only (Cheats system): fill the table so reset can be tested fast.
function GameLogic.fillTable(profile: Profile)
	profile.upgrades.moreCoins = Config.MAX_COINS - Config.START_COINS
end

-- The shout for a rare flip, or nil for a normal coin. RAINBOW and GIANT go to the
-- whole server (`everyone`); SILVER and GOLD only label the flipper's own coin.
function GameLogic.shoutNotice(displayName: string, userId: number, outcome: FlipOutcome): Types.Notice?
	local def = Economy.rarityDef(outcome.rarity)
	if not def then
		return nil
	end
	local prize = if outcome.cash > 0 then `+${Format.short(outcome.cash)}` else `+{outcome.hats} 🎩`
	return {
		kind = "shout",
		text = `{displayName} flipped a {def.name} coin! {prize}`,
		rarity = outcome.rarity,
		ownerId = userId,
		everyone = def.shout,
	}
end

-- "Welcome back" notice for helper earnings, or nil when it would read $0.
function GameLogic.offlineNotice(cash: number): Types.Notice?
	if math.floor(cash) < 1 then
		return nil
	end
	return { kind = "offline", text = `Your helpers earned ${Format.short(math.floor(cash))} while you were away!` }
end

return GameLogic
