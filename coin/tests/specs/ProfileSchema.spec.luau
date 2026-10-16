local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProfileSchema = require(ReplicatedStorage.Shared.Util.ProfileSchema)

describe("ProfileSchema", function()
	it("nil means a brand new player", function()
		local p = ProfileSchema.migrate(nil)
		expect(p.cash).toBe(0)
		expect(p.version).toBe(ProfileSchema.CURRENT_VERSION)
		expect(p.upgrades.moreCoins).toBe(0)
	end)

	it("default profiles are separate tables (no shared state)", function()
		local a = ProfileSchema.default()
		local b = ProfileSchema.default()
		a.upgrades.luck = 3
		expect(b.upgrades.luck).toBe(0)
	end)

	it("keeps good saved values", function()
		local p = ProfileSchema.migrate({
			version = 1,
			cash = 1234.5,
			hatPoints = 7,
			upgrades = { moreCoins = 3, bigCoins = 2, luck = 1, speed = 4 },
			helpers = 1,
			resets = 2,
			stats = { flips = 99, heads = 50, skulls = 49, biggestFlip = 12 },
			lastSeen = 1700000000,
		})
		expect(p.cash).toBe(1234.5)
		expect(p.hatPoints).toBe(7)
		expect(p.upgrades.speed).toBe(4)
		expect(p.resets).toBe(2)
		expect(p.stats.flips).toBe(99)
		expect(p.lastSeen).toBe(1700000000)
	end)

	it("fills missing fields and fixes bad numbers", function()
		local p = ProfileSchema.migrate({ version = 1, cash = 0 / 0, hatPoints = -5, upgrades = { luck = "lots" } })
		expect(p.cash).toBe(0)
		expect(p.hatPoints).toBe(0)
		expect(p.upgrades.luck).toBe(0)
		expect(p.upgrades.moreCoins).toBe(0)
		expect(p.stats.flips).toBe(0)
		local q = ProfileSchema.migrate({ version = 1, cash = math.huge })
		expect(q.cash).toBe(0)
	end)

	it("refuses broken saves instead of wiping them", function()
		expect(function()
			ProfileSchema.migrate("garbage")
		end).toThrow()
		expect(function()
			ProfileSchema.migrate({ cash = 5 })
		end).toThrow()
	end)

	it("refuses saves from a NEWER game version (never downgrades)", function()
		expect(function()
			ProfileSchema.migrate({ version = ProfileSchema.CURRENT_VERSION + 1, cash = 5 })
		end).toThrow()
	end)
end)
