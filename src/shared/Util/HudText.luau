--!strict
-- The words on the always-on HUD strips and side buttons. Pure so tests can
-- check the wording and numbers match what the game really pays.

local Config = require(script.Parent.Parent.Config)
local Format = require(script.Parent.Format)
local StreakView = require(script.Parent.StreakView)

local HudText = {}

-- What one heads pays. Whole amounts show whole ($2); a bonus like x1.5 shows
-- its one decimal ($1.5) so the bar matches the "x1.5" the reset popup promised.
function HudText.pay(cashPerHeads: number): string
	if cashPerHeads >= 1000 then
		return Format.short(math.floor(cashPerHeads + 0.5))
	end
	local tenths = math.floor(cashPerHeads * 10 + 0.5)
	if tenths % 10 == 0 then
		return tostring(tenths // 10)
	end
	return string.format("%d.%d", tenths // 10, tenths % 10)
end

-- The same extra cash multiplier the server applies to every heads
-- (Boosts.cashMult): 2x pass, server-wide mega boost, friend bonus, and the
-- weekend coin rain.
function HudText.cashMult(doublePass: boolean, megaBoost: boolean, friendHere: boolean, eventMult: number?): number
	local mult = 1
	if doublePass then
		mult *= Config.PASS_CASH_MULT
	end
	if megaBoost then
		mult *= Config.MEGA_BOOST_MULT
	end
	if friendHere then
		mult *= Config.FRIEND_CASH_MULT
	end
	return mult * math.max(1, eventMult or 1)
end

-- Two short labelled lines (the info card is narrow). The coin count lives in
-- the RESET button's bar, so it is not repeated here. `cashMult` is the
-- extra multiplier right now (HudText.cashMult), so the card shows what a
-- heads really pays; `flipsPerTap` adds the Multi Flip badge when a tap flips more
-- than one coin.
function HudText.info(cashPerHeads: number, headsChance: number, cashMult: number?, flipsPerTap: number?): string
	local multi = StreakView.multi(flipsPerTap or 1)
	local luck = `Luck {Format.percent(headsChance)}`
	if multi ~= "" then
		luck = `{luck} {multi}`
	end
	return `Heads = ${HudText.pay(cashPerHeads * (cashMult or 1))}\n{luck}`
end

-- Right-band chips. The mega count stays up after a mega flip (progress
-- never vanishes); the 2x timer has its own chip below it.
function HudText.mega(taps: number, goal: number): string
	return if taps > 0 then `🌟 {taps}/{goal}` else ""
end

function HudText.boost(boostLeft: number): string
	local left = math.ceil(boostLeft)
	if left > 0 then
		return `⚡ 2x  {left // 60}:{string.format("%02d", left % 60)}`
	end
	return ""
end

-- RESET button word: RESET until it is ready, then RESET!
function HudText.reset(full: boolean): string
	return if full then "RESET!" else "RESET"
end

-- The progress bar inside the RESET button.
function HudText.resetCount(coins: number, maxCoins: number): string
	return `{coins}/{maxCoins}`
end

return HudText
