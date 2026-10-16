local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local ProfileSchema = require(ReplicatedStorage.Shared.Util.ProfileSchema)
local GameLogic = require(ServerScriptService.Server.Util.GameLogic)

describe("GameLogic.validateCoinIndex (what a hacker could send)", function()
	it("accepts real coins", function()
		expect(GameLogic.validateCoinIndex(1, 3)).toBe(1)
		expect(GameLogic.validateCoinIndex(3, 3)).toBe(3)
	end)
	it("rejects everything else", function()
		local bad = { 0, 4, -1, 1.5, 0 / 0, math.huge, -math.huge, "1", nil, true, {}, function() end }
		for _, value in bad do
			expect(GameLogic.validateCoinIndex(value, 3)).toBeNil()
		end
	end)
end)

describe("GameLogic flips", function()
	it("heads adds cash and counts the flip", function()
		local p = ProfileSchema.default()
		local out = GameLogic.applyFlip(p, 0.0)
		expect(out.result).toBe("heads")
		expect(p.cash).toBe(out.cash)
		expect(p.stats.flips).toBe(1)
		expect(p.stats.heads).toBe(1)
		expect(p.stats.biggestFlip).toBe(out.cash)
	end)
	it("skull adds a hat point and no cash", function()
		local p = ProfileSchema.default()
		local out = GameLogic.applyFlip(p, 0.99)
		expect(out.result).toBe("skull")
		expect(p.cash).toBe(0)
		expect(p.hatPoints).toBe(1)
		expect(p.stats.skulls).toBe(1)
	end)
end)

describe("GameLogic shop", function()
	it("buying an upgrade takes the right cash and adds a level", function()
		local p = ProfileSchema.default()
		local cost = Economy.upgradeCost("moreCoins", 0)
		p.cash = cost + 5
		local ok = GameLogic.buyUpgrade(p, "moreCoins")
		expect(ok).toBeTruthy()
		expect(p.cash).toBe(5)
		expect(p.upgrades.moreCoins).toBe(1)
		expect(Economy.coinCount(p)).toBe(2)
	end)
	it("can't buy without enough cash", function()
		local p = ProfileSchema.default()
		p.cash = 1
		local ok, why = GameLogic.buyUpgrade(p, "luck")
		expect(ok).toBeFalsy()
		expect(why).toBe("not enough cash")
		expect(p.cash).toBe(1)
		expect(p.upgrades.luck).toBe(0)
	end)
	it("rejects fake upgrade names and wrong types", function()
		local p = ProfileSchema.default()
		p.cash = 1e9
		for _, bad in { "cash", "__index", 1, nil, {}, "MORECOINS" } do
			local ok = GameLogic.buyUpgrade(p, bad)
			expect(ok).toBeFalsy()
		end
		expect(p.cash).toBe(1e9)
	end)
	it("stops at max level", function()
		local p = ProfileSchema.default()
		p.cash = 1e12
		for _ = 1, 50 do
			GameLogic.buyUpgrade(p, "moreCoins")
		end
		expect(p.upgrades.moreCoins).toBe(Config.Upgrades.moreCoins.maxLevel)
		expect(Economy.coinCount(p)).toBe(Config.MAX_COINS)
	end)
	it("helper: Buddy costs cash and starts working", function()
		local p = ProfileSchema.default()
		local buddy = Config.HelperTypes[1]
		p.cash = buddy.cost
		expect(GameLogic.unlockHelper(p, "buddy")).toBeTruthy()
		expect(p.crew.buddy).toBe(1)
		expect(p.team[1]).toBe("buddy")
		expect(p.cash).toBe(0)
		p.cash = 1e9
		expect(GameLogic.unlockHelper(p, "buddy")).toBeFalsy()
	end)
	it("cash never goes negative from any purchase sequence", function()
		local p = ProfileSchema.default()
		p.cash = 500
		for i = 1, 200 do
			GameLogic.buyUpgrade(p, Config.UPGRADE_ORDER[(i % 4) + 1])
			GameLogic.unlockHelper(p, "buddy")
			GameLogic.levelHelper(p, "buddy")
			expect(p.cash).toBeAtLeast(0)
		end
	end)
end)

describe("GameLogic reset (prestige)", function()
	it("can't reset before the table is full", function()
		local p = ProfileSchema.default()
		p.cash = 100
		local ok = GameLogic.reset(p)
		expect(ok).toBeFalsy()
		expect(p.resets).toBe(0)
		expect(p.cash).toBe(100)
	end)
	it("full table resets: lose cash+upgrades, keep helpers+hats, gain bonus", function()
		local p = ProfileSchema.default()
		GameLogic.fillTable(p)
		p.upgrades.luck = 4
		p.cash = 999
		p.crew.buddy = 3
		p.team = { "buddy" }
		p.hatPoints = 12
		expect(GameLogic.reset(p)).toBeTruthy()
		expect(p.resets).toBe(1)
		expect(p.cash).toBe(0)
		expect(p.upgrades.moreCoins).toBe(0)
		expect(p.upgrades.luck).toBe(0)
		expect(p.crew.buddy).toBe(3)
		expect(p.team[1]).toBe("buddy")
		expect(p.hatPoints).toBe(12)
		expect(Economy.coinCount(p)).toBe(1)
		expect(Economy.resetMultiplier(p.resets)).toBe(1 + Config.RESET_CASH_BONUS)
	end)
	it("you can play a whole run: start -> full table -> reset", function()
		local p = ProfileSchema.default()
		local seed = 7
		local function roll()
			seed = (seed * 1103515245 + 12345) % 2147483648
			return seed / 2147483648
		end
		local flips = 0
		while not Economy.isTableFull(p) and flips < 1000000 do
			GameLogic.applyFlip(p, roll())
			flips += 1
			for _, id in Config.UPGRADE_ORDER do
				GameLogic.buyUpgrade(p, id)
			end
			GameLogic.unlockHelper(p, "buddy")
		end
		expect(Economy.isTableFull(p)).toBeTruthy()
		expect(GameLogic.reset(p)).toBeTruthy()
		print(`        (a full first run took {flips} flips)`)
	end)
end)

describe("GameLogic offline bonus", function()
	it("first join gives nothing and stamps the time", function()
		local p = ProfileSchema.default()
		p.crew.buddy = 1
		p.team = { "buddy" }
		expect(GameLogic.applyOffline(p, 1000)).toBe(0)
		expect(p.lastSeen).toBe(1000)
	end)
	it("coming back later pays helpers' capped earnings", function()
		local p = ProfileSchema.default()
		p.crew.buddy = 1
		p.team = { "buddy" }
		p.lastSeen = 1000
		local earned = GameLogic.applyOffline(p, 1000 + 10 * 24 * 3600)
		expect(earned).toBe(Economy.offlineEarnings(p, Config.OFFLINE_CAP_SECONDS))
		expect(p.cash).toBe(earned)
	end)
	it("a clock going backwards pays nothing", function()
		local p = ProfileSchema.default()
		p.crew.buddy = 1
		p.team = { "buddy" }
		p.lastSeen = 5000
		expect(GameLogic.applyOffline(p, 100)).toBe(0)
	end)
end)

describe("GameLogic.snapshot", function()
	it("has what the HUD needs and is a copy", function()
		local p = ProfileSchema.default()
		local s = GameLogic.snapshot(p)
		expect(s.coinCount).toBe(1)
		expect(s.tableFull).toBeFalsy()
		s.upgrades.luck = 99
		expect(p.upgrades.luck).toBe(0)
	end)
end)
