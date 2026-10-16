local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Format = require(ReplicatedStorage.Shared.Util.Format)
local TableLayout = require(ReplicatedStorage.Shared.Util.TableLayout)
local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)

describe("Format.short", function()
	it("keeps numbers short for phone screens", function()
		expect(Format.short(0)).toBe("0")
		expect(Format.short(999)).toBe("999")
		expect(Format.short(1000)).toBe("1.00K")
		expect(Format.short(1234)).toBe("1.23K")
		expect(Format.short(45678)).toBe("45.6K")
		expect(Format.short(999999)).toBe("999K")
		expect(Format.short(2500000)).toBe("2.50M")
		expect(Format.short(0 / 0)).toBe("0")
		for _, n in { 1, 12, 123, 1234, 12345, 123456, 1e7, 1e10, 1e15, 1e30 } do
			expect(#Format.short(n)).toBeAtMost(6)
		end
	end)
	it("percent", function()
		expect(Format.percent(0.5)).toBe("50%")
		expect(Format.percent(0.53)).toBe("53%")
	end)
end)

describe("TableLayout", function()
	it("every coin fits on the table and the biggest coins don't overlap", function()
		local d = Economy.coinDiameter(Config.Upgrades.bigCoins.maxLevel)
		local spots = {}
		for i = 1, Config.MAX_COINS do
			local x, z = TableLayout.coinOffset(i, Config.MAX_COINS)
			expect(math.sqrt(x * x + z * z) + d / 2).toBeAtMost(Config.TABLE_RADIUS)
			table.insert(spots, { x, z })
		end
		for i = 1, #spots do
			for j = i + 1, #spots do
				local dx, dz = spots[i][1] - spots[j][1], spots[i][2] - spots[j][2]
				expect(math.sqrt(dx * dx + dz * dz)).toBeAtLeast(d)
			end
		end
	end)
	it("tables don't overlap each other", function()
		local x1, z1 = TableLayout.plotPosition(1, Config.MAX_PLOTS, Config.PLOT_RING_RADIUS)
		local x2, z2 = TableLayout.plotPosition(2, Config.MAX_PLOTS, Config.PLOT_RING_RADIUS)
		local gap = math.sqrt((x1 - x2) ^ 2 + (z1 - z2) ^ 2)
		expect(gap).toBeAtLeast(Config.TABLE_RADIUS * 2 + 12)
	end)
end)
