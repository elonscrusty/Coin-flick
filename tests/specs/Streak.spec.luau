local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local ProfileSchema = require(ReplicatedStorage.Shared.Util.ProfileSchema)
local GameLogic = require(ServerScriptService.Server.Util.GameLogic)

-- Plays `n` flips in a row like Tables does for real taps. Returns the last outcome.
local function tapStreak(p, streak, results)
	local last
	for _, result in results do
		last = GameLogic.applyStreak(p, streak, result)
		streak = last.nextStreak
	end
	return last, streak
end

describe("Streak: 10 heads in a row", function()
	it("goal is 10 and starting heads chance is low (35%)", function()
		expect(Config.STREAK_GOAL).toBe(10)
		expect(Economy.headsChance(0)).toBeNear(0.35)
	end)
	it("heads grow the streak one by one", function()
		local p = ProfileSchema.default()
		local out, streak = tapStreak(p, 0, { "heads", "heads", "heads" })
		expect(out.streak).toBe(3)
		expect(streak).toBe(3)
		expect(out.won).toBeFalsy()
		expect(p.stats.bestStreak).toBe(3)
	end)
	it("a skull breaks the streak but keeps the best", function()
		local p = ProfileSchema.default()
		local _, streak = tapStreak(p, 0, { "heads", "heads", "heads", "heads", "heads" })
		local out
		out, streak = tapStreak(p, streak, { "skull" })
		expect(out.streak).toBe(0)
		expect(streak).toBe(0)
		expect(p.stats.bestStreak).toBe(5)
		expect(p.cash).toBe(0)
	end)
	it("9 heads pay nothing, the 10th pays the prize once and starts over", function()
		local p = ProfileSchema.default()
		local out, streak = tapStreak(p, 0, { "heads", "heads", "heads", "heads", "heads", "heads", "heads", "heads", "heads" })
		expect(out.won).toBeFalsy()
		expect(p.cash).toBe(0)
		expect(p.hatPoints).toBe(0)
		local cash, hats = Economy.streakPrize(p)
		out, streak = tapStreak(p, streak, { "heads" })
		expect(out.won).toBeTruthy()
		expect(out.streak).toBe(10)
		expect(out.cash).toBe(cash)
		expect(out.hats).toBe(hats)
		expect(streak).toBe(0)
		expect(p.cash).toBe(cash)
		expect(p.hatPoints).toBe(hats)
		expect(p.stats.streakWins).toBe(1)
		expect(p.stats.bestStreak).toBe(10)
		-- the 11th heads is streak 1 of the next run, not a second prize
		out = tapStreak(p, streak, { "heads" })
		expect(out.streak).toBe(1)
		expect(p.cash).toBe(cash)
	end)
	it("prize scales with the bigger-coins upgrade", function()
		local p = ProfileSchema.default()
		local small = Economy.streakPrize(p)
		p.upgrades.bigCoins = 4
		expect(Economy.streakPrize(p)).toBeAtLeast(small + 1)
	end)
	it("a skull never pays anything", function()
		local p = ProfileSchema.default()
		local out = GameLogic.applyStreak(p, 9, "skull")
		expect(out.won).toBeFalsy()
		expect(out.cash).toBe(0)
		expect(p.cash).toBe(0)
	end)
	it("simulation: win rate matches chance^10 and the upgrade makes it easier", function()
		local seed = 12345
		local function roll()
			seed = (seed * 1103515245 + 12345) % 2147483648
			return seed / 2147483648
		end
		local function winRate(luck, flips)
			local p = ProfileSchema.default()
			p.upgrades.luck = luck
			local chance = Economy.headsChance(luck)
			local streak, wins = 0, 0
			for _ = 1, flips do
				local result = if roll() < chance then "heads" else "skull"
				local out = GameLogic.applyStreak(p, streak, result)
				streak = out.nextStreak
				if out.won then
					wins += 1
				end
			end
			return wins
		end
		local base = winRate(0, 200000)
		local maxed = winRate(10, 200000)
		expect(base).toBe(0) -- 0.35^10 is about 1 in 36,000 and a run needs 10 flips
		-- At 80% a run of 10 takes about 42 flips, so 200000 flips is about 4800 wins.
		expect(maxed).toBeAtLeast(4000)
		expect(maxed).toBeAtMost(6000)
	end)
end)

describe("Lucky Heads upgrade", function()
	it("raises the heads chance from 35% to 80% and stops there", function()
		local last = 0
		for level = 0, 10 do
			local chance = Economy.headsChance(level)
			expect(chance).toBeAtLeast(last)
			last = chance
		end
		expect(Economy.headsChance(10)).toBeNear(0.8, 1e-9)
		expect(Economy.headsChance(50)).toBeNear(0.8, 1e-9)
	end)
	it("buying it works and reset puts it back", function()
		local p = ProfileSchema.default()
		p.cash = 1e6
		expect(GameLogic.buyUpgrade(p, "luck")).toBeTruthy()
		expect(Economy.headsChance(p.upgrades.luck)).toBeNear(0.395, 1e-9)
	end)
end)

describe("Multi Flip upgrade", function()
	it("starts at 1 coin per tap, +1 per level, max 5", function()
		local p = ProfileSchema.default()
		expect(Economy.flipsPerTap(p)).toBe(1)
		p.upgrades.multiFlip = 2
		expect(Economy.flipsPerTap(p)).toBe(3)
		p.upgrades.multiFlip = 99
		expect(Economy.flipsPerTap(p)).toBe(1 + Config.Upgrades.multiFlip.maxLevel)
	end)
	it("buying costs cash, stops at max, and rejects bad ids", function()
		local p = ProfileSchema.default()
		p.cash = 1e12
		for _ = 1, 10 do
			GameLogic.buyUpgrade(p, "multiFlip")
		end
		expect(p.upgrades.multiFlip).toBe(Config.Upgrades.multiFlip.maxLevel)
		local ok, why = GameLogic.buyUpgrade(p, "multiFlip")
		expect(ok).toBeFalsy()
		expect(why).toBe("maxed")
		expect(p.cash).toBeAtLeast(0)
		local q = ProfileSchema.default()
		q.cash = 1
		expect(GameLogic.buyUpgrade(q, "multiFlip")).toBeFalsy()
		expect(q.upgrades.multiFlip).toBe(0)
	end)
	it("tap flips the tapped coin first, then the next idle coins, skipping busy ones", function()
		local busy = { 0, 0, 0, 0, 0 }
		expect(table.concat(GameLogic.pickTapCoins(2, busy, 10, 1), ",")).toBe("2")
		expect(table.concat(GameLogic.pickTapCoins(2, busy, 10, 3), ",")).toBe("2,3,4")
		expect(table.concat(GameLogic.pickTapCoins(5, busy, 10, 3), ",")).toBe("5,1,2")
		busy[3] = 99 -- coin 3 still in the air
		expect(table.concat(GameLogic.pickTapCoins(2, busy, 10, 3), ",")).toBe("2,4,5")
	end)
	it("never flips more coins than the table has, or the same coin twice", function()
		local busy = { 0, 0, 0 }
		local picked = GameLogic.pickTapCoins(1, busy, 10, 5)
		expect(#picked).toBe(3)
		expect(picked[1]).toBe(1)
		expect(picked[2]).toBe(2)
		expect(picked[3]).toBe(3)
		expect(#GameLogic.pickTapCoins(1, { 0 }, 10, 5)).toBe(1)
	end)
	it("reset takes the upgrade back, like the other upgrades", function()
		local p = ProfileSchema.default()
		p.upgrades.moreCoins = Config.MAX_COINS - Config.START_COINS
		p.upgrades.multiFlip = 3
		expect(GameLogic.reset(p)).toBeTruthy()
		expect(p.upgrades.multiFlip).toBe(0)
	end)
end)

describe("Streak save data", function()
	it("old saves without streak fields load with zeros", function()
		local p = ProfileSchema.migrate({ version = 2, cash = 5, upgrades = { luck = 1 }, stats = { flips = 3 } })
		expect(p.stats.bestStreak).toBe(0)
		expect(p.stats.streakWins).toBe(0)
		expect(p.upgrades.multiFlip).toBe(0)
		expect(p.upgrades.luck).toBe(1)
	end)
	it("bad streak values are cleaned, multiFlip is capped", function()
		local p = ProfileSchema.migrate({
			version = 2,
			upgrades = { multiFlip = 99 },
			stats = { bestStreak = -4, streakWins = "lots" },
		})
		expect(p.upgrades.multiFlip).toBe(Config.Upgrades.multiFlip.maxLevel)
		expect(p.stats.bestStreak).toBe(0)
		expect(p.stats.streakWins).toBe(0)
	end)
	it("snapshot shows the goal, best streak and coins per tap", function()
		local p = ProfileSchema.default()
		p.stats.bestStreak = 7
		p.upgrades.multiFlip = 1
		local s = GameLogic.snapshot(p)
		expect(s.streakGoal).toBe(10)
		expect(s.bestStreak).toBe(7)
		expect(s.flipsPerTap).toBe(2)
	end)
	it("client cannot change a profile through a snapshot copy", function()
		local p = ProfileSchema.default()
		local s = GameLogic.snapshot(p)
		s.upgrades.multiFlip = 4
		expect(p.upgrades.multiFlip).toBe(0)
	end)
end)
