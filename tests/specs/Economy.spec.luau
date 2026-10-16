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
		p.crew.buddy = 1
		p.team = { "buddy" }
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

	it("helper slots: 1 to start, more after resets 1 and 3", function()
		local p = ProfileSchema.default()
		expect(Economy.maxHelpers(p)).toBe(1)
		p.resets = 1
		expect(Economy.maxHelpers(p)).toBe(2)
		p.resets = 3
		expect(Economy.maxHelpers(p)).toBe(3)
		p.resets = 50
		expect(Economy.maxHelpers(p)).toBe(3)
	end)
end)

describe("Rare coins", function()
	it("each rare coin has its exact odds", function()
		local chances = {}
		for _, def in Config.Rarities do
			chances[def.id] = def.chance
		end
		expect(chances.giant).toBe(1 / 10000)
		expect(chances.rainbow).toBe(1 / 1000)
		expect(chances.gold).toBe(1 / 100)
		expect(chances.silver).toBe(1 / 20)
	end)

	it("rolls map to the right coin, rarest at the bottom", function()
		expect(Economy.rollRarity(0)).toBe("giant")
		expect(Economy.rollRarity(0.00009)).toBe("giant")
		expect(Economy.rollRarity(0.0002)).toBe("rainbow")
		expect(Economy.rollRarity(0.005)).toBe("gold")
		expect(Economy.rollRarity(0.03)).toBe("silver")
		expect(Economy.rollRarity(0.5)).toBe("normal")
		expect(Economy.rollRarity(0.9999)).toBe("normal")
	end)

	it("rarityRollFor lands exactly on that coin", function()
		for _, def in Config.Rarities do
			expect(Economy.rollRarity(Economy.rarityRollFor(def.id))).toBe(def.id)
		end
		expect(Economy.rollRarity(Economy.rarityRollFor("normal"))).toBe("normal")
	end)

	it("rare heads multiply cash, rare skulls multiply hats", function()
		local p = ProfileSchema.default()
		local base = Economy.cashPerHeads(p)
		local _, cash, hats, rarity = Economy.resolveFlip(p, 0, 0)
		expect(rarity).toBe("giant")
		expect(cash).toBe(base * 500)
		expect(hats).toBe(0)
		local result, cash2, hats2, rarity2 = Economy.resolveFlip(p, 0.99, Economy.rarityRollFor("gold"))
		expect(result).toBe("skull")
		expect(rarity2).toBe("gold")
		expect(cash2).toBe(0)
		expect(hats2).toBe(10)
	end)

	it("no rarity roll means a normal coin", function()
		local p = ProfileSchema.default()
		local _, cash, _, rarity = Economy.resolveFlip(p, 0)
		expect(rarity).toBe("normal")
		expect(cash).toBe(Economy.cashPerHeads(p))
	end)

	it("spread evenly over every roll, the odds come out exact", function()
		local counts = { normal = 0, silver = 0, gold = 0, rainbow = 0, giant = 0 }
		local n = 100000
		for i = 0, n - 1 do
			local r = Economy.rollRarity((i + 0.5) / n)
			counts[r] += 1
		end
		expect(counts.giant).toBe(10)
		expect(counts.rainbow).toBe(100)
		expect(counts.gold).toBe(1000)
		expect(counts.silver).toBe(5000)
		expect(counts.normal).toBe(n - 6110)
	end)
end)
