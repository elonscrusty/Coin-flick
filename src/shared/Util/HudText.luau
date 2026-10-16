--!strict
-- The words on the always-on HUD strips and side buttons. Pure so tests can
-- check the wording and numbers match what the game really pays.

local Format = require(script.Parent.Format)

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

-- Two short lines (the info card is narrow): pay, then luck and coin count.
function HudText.info(cashPerHeads: number, headsChance: number, coins: number, maxCoins: number): string
	return `Heads = ${HudText.pay(cashPerHeads)}\n🍀 {Format.percent(headsChance)}  🪙 {coins}/{maxCoins}`
end

-- Boost strip: the 2x timer while it runs, the mega coin count once someone
-- has started tapping it, else nothing (strip hidden).
function HudText.boost(taps: number, goal: number, boostLeft: number): string
	local left = math.ceil(boostLeft)
	if left > 0 then
		return `⚡ 2x CASH  {left // 60}:{string.format("%02d", left % 60)}`
	elseif taps > 0 then
		return `🌟 Mega {taps}/{goal}`
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
