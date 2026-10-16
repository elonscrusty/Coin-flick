local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local ProfileSchema = require(ReplicatedStorage.Shared.Util.ProfileSchema)
local TableLayout = require(ReplicatedStorage.Shared.Util.TableLayout)

describe("Empty coin spots on the table", function()
	it("a fresh table (or one right after a reset) shows 9 empty spots", function()
		local p = ProfileSchema.default()
		expect(Economy.emptySlots(p)).toBe(Config.MAX_COINS - Config.START_COINS)
	end)

	it("every coin bought fills one spot; a full table has none", function()
		local p = ProfileSchema.default()
		for level = 0, Config.MAX_COINS - Config.START_COINS do
			p.upgrades.moreCoins = level
			expect(Economy.emptySlots(p) + Economy.coinCount(p)).toBe(Config.MAX_COINS)
		end
		expect(Economy.emptySlots(p)).toBe(0)
	end)

	it("spots never overlap each other (biggest coins fit too)", function()
		local d = Config.COIN_BASE_DIAMETER + Config.COIN_DIAMETER_PER_LEVEL * Config.Upgrades.bigCoins.maxLevel
		for i = 1, Config.MAX_COINS do
			for j = i + 1, Config.MAX_COINS do
				local x1, z1 = TableLayout.coinOffset(i, Config.MAX_COINS)
				local x2, z2 = TableLayout.coinOffset(j, Config.MAX_COINS)
				expect(math.sqrt((x1 - x2) ^ 2 + (z1 - z2) ^ 2)).toBeAtLeast(d)
			end
		end
	end)

	it("every spot stays on the table top", function()
		local d = Config.COIN_BASE_DIAMETER + Config.COIN_DIAMETER_PER_LEVEL * Config.Upgrades.bigCoins.maxLevel
		for i = 1, Config.MAX_COINS do
			local x, z = TableLayout.coinOffset(i, Config.MAX_COINS)
			expect(math.sqrt(x * x + z * z) + d / 2).toBeAtMost(Config.TABLE_RADIUS)
		end
	end)
end)
