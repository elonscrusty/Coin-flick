local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local ProfileSchema = require(ReplicatedStorage.Shared.Util.ProfileSchema)

describe("Economy", function()
	it("new players have 1 coin and a non-full table", function()
		local p = ProfileSchema.default()
		expect(Economy.coinCount(p)).toBe(1)
		expect(Economy.isTableFull(p)).toBeFalsy()
	end)

	it("table is full after buying every More Coins level", function()
		local p = ProfileSchema.default()
		p.upgrades.moreCoins = Config.Upgrades.moreCoins.maxLevel
		expect(Economy.coinCount(p)).toBe(Config.MAX_COINS)
		expect(Economy.isTableFull(p)).toBeTruthy()
	end)

	it("upgrade costs always go up and stop at max level", function()
		for id, def in Config.Upgrades do
			local last = 0
			for level = 0, def.maxLevel - 1 do
				local cost = Economy.upgradeCost(id, level)
				expect(cost).toBeAtLeast(last + 1)
				last = cost
			end
			expect(Economy.upgradeCost(id, def.maxLevel)).toBeNil()
		end
	end)

	it("unknown upgrade ids are rejected", function()
		expect(Economy.isUpgradeId("moreCoins")).toBeTruthy()
		expect(Economy.isUpgradeId("freeMoney")).toBeFalsy()
		expect(Economy.isUpgradeId(5)).toBeFalsy()
		expect(Economy.isUpgradeId(nil)).toBeFalsy()
		expect(Economy.upgradeCost("freeMoney", 0)).toBeNil()
	end)

	it("heads chance starts at 50% and never passes the cap", function()
		expect(Economy.headsChance(0)).toBeNear(0.5)
		for level = 0, 100 do
			expect(Economy.headsChance(level)).toBeAtMost(Config.MAX_HEADS_CHANCE)
		end
	end)

	it("flip time gets faster but never below the minimum", function()
		local last = math.huge
		for level = 0, 10 do
			local t = Economy.flipTime(level)
			expect(t).toBeAtMost(last)
			expect(t).toBeAtLeast(Config.MIN_FLIP_TIME)
			last = t
		end
		expect(Economy.flipTime(1000)).toBe(Config.MIN_FLIP_TIME)
	end)

	it("heads pays cash, skull pays a hat point", function()
		local p = ProfileSchema.default()
		local r1, cash1, hats1 = Economy.resolveFlip(p, 0.1)
		expect(r1).toBe("heads")
		expect(cash1).toBe(1)
		expect(hats1).toBe(0)
		local r2, cash2, hats2 = Economy.resolveFlip(p, 0.9)
		expect(r2).toBe("skull")
		expect(cash2).toBe(0)
		expect(hats2).toBe(1)
	end)

	it("bigger coins and resets both raise cash per heads", function()
		local p = ProfileSchema.default()
		local base = Economy.cashPerHeads(p)
		p.upgrades.bigCoins = 4
		local bigger = Economy.cashPerHeads(p)
		expect(bigger).toBeAtLeast(base + 1)
		p.resets = 2
		expect(Economy.cashPerHeads(p)).toBeAtLeast(bigger + 1)
	end)

	it("about the right share of flips are heads (100k seeded rolls)", function()
		local p = ProfileSchema.default()
		p.upgrades.luck = 5
		local seed = 12345
		local function roll()
			-- simple LCG so the test is the same every run
			seed = (seed * 1103515245 + 12345) % 2147483648
			return seed / 2147483648
		end
		local heads = 0
		for _ = 1, 100000 do
			if Economy.resolveFlip(p, roll()) == "heads" then
				heads += 1
			end
		end
		local share = heads / 100000
		expect(share).toBeNear(Economy.headsChance(5), 0.01)
	end)

	it("offline bonus is zero without helpers", function()
		local p = ProfileSchema.default()
		expect(Economy.offlineEarnings(p, 3600)).toBe(0)
	end)

	it("offline bonus is capped and ignores bad clocks", function()
		local p = ProfileSchema.default()
		p.helpers = 1
		local capped = Economy.offlineEarnings(p, Config.OFFLINE_CAP_SECONDS)
		expect(capped).toBeAtLeast(1)
		expect(Economy.offlineEarnings(p, Config.OFFLINE_CAP_SECONDS * 50)).toBe(capped)
		expect(Economy.offlineEarnings(p, -500)).toBe(0)
		expect(Economy.offlineEarnings(p, 0 / 0)).toBe(0)
	end)

	it("each reset picks the next table look and loops around", function()
		local n = #Config.TableLooks
		expect(Economy.tableLook(0)).toBe(1)
		expect(Economy.tableLook(1)).toBe(2)
		expect(Economy.tableLook(n)).toBe(1)
	end)

	it("only one helper slot in the first build", function()
		expect(Economy.helperCost(0)).toBe(Config.HELPER_COST)
		expect(Economy.helperCost(1)).toBeNil()
	end)
end)
