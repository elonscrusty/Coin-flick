--!strict
-- The words on the always-on HUD strips and side buttons. Pure so tests can
-- check the wording and numbers match what the game really pays.

local Format = require(script.Parent.Format)

local HudText = {}

-- Heads pay is rounded the same way Economy.flip rounds it, so the strip
-- shows exactly what one heads gives you.
function HudText.info(cashPerHeads: number, headsChance: number, coins: number, maxCoins: number): string
	local pay = math.floor(cashPerHeads + 0.5)
	return `Heads = ${Format.short(pay)}  •  🍀 {Format.percent(headsChance)} luck  •  🪙 {coins}/{maxCoins}`
end

-- Boost strip: the 2x timer while it runs, the mega coin count once someone
-- has started tapping it, else nothing (strip hidden).
function HudText.boost(taps: number, goal: number, boostLeft: number): string
	local left = math.ceil(boostLeft)
	if left > 0 then
		return `⚡ 2x CASH  {left // 60}:{string.format("%02d", left % 60)}`
	elseif taps > 0 then
		return `🌟 Mega coin {taps}/{goal}  •  tap it together!`
	end
	return ""
end

-- RESET side button word: shows how full the table is until it can reset.
function HudText.reset(coins: number, maxCoins: number, full: boolean): string
	return if full then "RESET!" else `{coins}/{maxCoins}`
end

return HudText
