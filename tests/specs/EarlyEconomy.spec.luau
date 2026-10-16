local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local ProfileSchema = require(ReplicatedStorage.Shared.Util.ProfileSchema)
local GameLogic = require(ServerScriptService.Server.Util.GameLogic)

-- A casual player who taps `tapsPerSec` times a second, flips the first idle
-- coin, and always buys the cheapest upgrade they can afford (no helpers, no
-- Multi Flip). Returns coins at each minute mark, cash earned, and when the
-- table filled up. Deterministic.
local function playSession(tapsPerSec: number, seconds: number)
	local seed = 777
	local function roll()
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end
	local p = ProfileSchema.default()
	local busy: { number } = {}
	local earned = 0
	local coinsAt: { [number]: number } = {}
	local fullAt = nil
	local tapAcc = 0
	local step = 0.1
	local t = 0
	while t < seconds do
		t += step
		tapAcc += tapsPerSec * step
		while tapAcc >= 1 do
			tapAcc -= 1
			for i = 1, Economy.coinCount(p) do
				if (busy[i] or 0) <= t then
					local before = p.cash
					GameLogic.applyFlip(p, roll())
					earned += p.cash - before
					busy[i] = t + Economy.flipTime(p.upgrades.speed)
					break
				end
			end
		end
		local bestId, bestCost = nil, nil
		for _, id in { "moreCoins", "bigCoins", "luck", "speed" } do
			local cost = Economy.upgradeCost(id, p.upgrades[id])
			if cost and p.cash >= cost and (not bestCost or cost < bestCost) then
				bestId, bestCost = id, cost
			end
		end
		if bestId then
			GameLogic.buyUpgrade(p, bestId)
		end
		if Economy.isTableFull(p) and not fullAt then
			fullAt = t
		end
		for _, mark in { 60, 180, 300, 600 } do
			if math.abs(t - mark) < step / 2 then
				coinsAt[mark] = Economy.coinCount(p)
			end
		end
	end
	return coinsAt, earned, fullAt
end

describe("Early game at 35% heads still feels good", function()
	-- Reference: the old 50% start with the old prices, same player, same seed:
	-- 3 coins at 1 min, 5 at 3 min, 6 at 5 min, 2852 cash in 10 min, full table at 1188 s.
	it("a fast tapper (3/s) gets a 2nd coin quickly and keeps pace with the old 50% game", function()
		local coins, earned, fullAt = playSession(3, 1200)
		expect(coins[60]).toBeAtLeast(3)
		expect(coins[180]).toBeAtLeast(5)
		expect(coins[300]).toBeAtLeast(6)
		expect(earned).toBeAtLeast(0.75 * 2852) -- measured: about 2400 at 10 min
		expect(fullAt ~= nil).toBeTruthy()
		expect(fullAt).toBeAtMost(1188)
	end)
	it("a slow tapper (1.5/s) still has 5 coins by 5 minutes and 6 by 10", function()
		local coins = playSession(1.5, 600)
		expect(coins[60]).toBeAtLeast(3)
		expect(coins[300]).toBeAtLeast(5)
		expect(coins[600]).toBeAtLeast(6)
	end)
	it("first extra coin costs 7, so about 7 heads", function()
		expect(Economy.upgradeCost("moreCoins", 0)).toBe(7)
	end)
end)

describe("Streak prize and the 2x cash pass", function()
	it("the pass (boost) doubles the prize cash but not the hat points", function()
		local p = ProfileSchema.default()
		local plainCash, plainHats = Economy.streakPrize(p)
		local boostedCash, boostedHats = Economy.streakPrize(p, 2)
		expect(boostedCash).toBe(plainCash * 2)
		expect(boostedHats).toBe(plainHats)
	end)
	it("a boosted win pays the boosted cash into the save", function()
		local p = ProfileSchema.default()
		local streak = 0
		local out
		for _ = 1, Config.STREAK_GOAL do
			out = GameLogic.applyStreak(p, streak, "heads", 2)
			streak = out.nextStreak
		end
		local plain = Economy.streakPrize(ProfileSchema.default())
		expect(out.won).toBeTruthy()
		expect(out.cash).toBe(plain * 2)
		expect(p.cash).toBe(plain * 2)
	end)
	it("a boost below 1 or a missing boost never shrinks the prize", function()
		local p = ProfileSchema.default()
		local plain = Economy.streakPrize(p)
		expect(Economy.streakPrize(p, 0.1)).toBe(plain)
		expect(Economy.streakPrize(p, nil)).toBe(plain)
	end)
end)
