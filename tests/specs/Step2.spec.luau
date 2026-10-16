local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local ProfileSchema = require(ReplicatedStorage.Shared.Util.ProfileSchema)
local GameLogic = require(ServerScriptService.Server.Util.GameLogic)
local MegaCoin = require(ServerScriptService.Server.Util.MegaCoin)

describe("Chain flips (combo)", function()
	it("quick taps grow the combo, a slow tap starts over", function()
		local combo = GameLogic.nextCombo(0, 0, 100)
		expect(combo).toBe(1)
		combo = GameLogic.nextCombo(combo, 100, 100.5)
		expect(combo).toBe(2)
		combo = GameLogic.nextCombo(combo, 100.5, 100.5 + Config.COMBO_WINDOW)
		expect(combo).toBe(3)
		combo = GameLogic.nextCombo(combo, 102, 102 + Config.COMBO_WINDOW + 0.01)
		expect(combo).toBe(1)
	end)

	it("combo bonus is +10% a step and stops at 3x", function()
		expect(Economy.comboMult(0)).toBe(1)
		expect(Economy.comboMult(1)).toBe(1)
		expect(math.abs(Economy.comboMult(5) - 1.4) < 1e-9).toBeTruthy()
		expect(Economy.comboMult(21)).toBe(3)
		expect(Economy.comboMult(500)).toBe(3)
	end)

	it("combo multiplies heads cash and records the best combo", function()
		local p = ProfileSchema.default()
		p.upgrades.bigCoins = 8 -- 5 cash per heads
		local base = Economy.cashPerHeads(p)
		local out = GameLogic.applyFlip(p, 0, nil, 1, 11)
		expect(out.cash).toBe(math.floor(base * 2 + 0.5))
		expect(p.stats.bestCombo).toBe(11)
		GameLogic.applyFlip(p, 0, nil, 1, 3)
		expect(p.stats.bestCombo).toBe(11)
	end)

	it("boosts stack with combo and rare coins, but never on skulls", function()
		local p = ProfileSchema.default()
		local out = GameLogic.applyFlip(p, 0, Economy.rarityRollFor("gold"), 2, 1)
		expect(out.cash).toBe(Economy.cashPerHeads(p) * 10 * 2)
		expect(p.stats.rares).toBe(1)
		local skull = GameLogic.applyFlip(p, 0.99, nil, 4, 21)
		expect(skull.cash).toBe(0)
		expect(skull.hats).toBe(1)
	end)
end)

describe("Mega coin", function()
	it("fills at the goal and rewards everyone who tapped once", function()
		local mega = MegaCoin.new()
		expect(mega:tap(1, 3)).toBeFalsy()
		expect(mega:tap(2, 3)).toBeFalsy()
		expect(mega:tap(1, 3)).toBeTruthy()
		local helpers = mega:finish()
		expect(#helpers).toBe(2)
		expect(helpers[1]).toBe(1)
		expect(helpers[2]).toBe(2)
		expect(mega.taps).toBe(0)
		expect(#mega:finish()).toBe(0)
	end)

	it("players who leave get no reward but their taps still count", function()
		local mega = MegaCoin.new()
		mega:tap(7, 10)
		mega:tap(8, 10)
		mega:forget(7)
		expect(mega.taps).toBe(2)
		local helpers = mega:finish()
		expect(#helpers).toBe(1)
		expect(helpers[1]).toBe(8)
	end)

	it("goal grows with players, reward is cash and hats", function()
		expect(Economy.megaGoal(1)).toBe(Config.MEGA_BASE_TAPS + Config.MEGA_TAPS_PER_PLAYER)
		expect(Economy.megaGoal(0)).toBe(Economy.megaGoal(1))
		expect(Economy.megaGoal(8) > Economy.megaGoal(2)).toBeTruthy()
		local p = ProfileSchema.default()
		local cash, hats = GameLogic.megaReward(p)
		expect(cash).toBe(Economy.cashPerHeads(p) * Config.MEGA_REWARD_FLIPS)
		expect(p.cash).toBe(cash)
		expect(p.hatPoints).toBe(hats)
	end)
end)

describe("Hats", function()
	it("buying takes hat points and puts the hat on", function()
		local p = ProfileSchema.default()
		local def = Config.Hats[1]
		p.hatPoints = def.cost + 2
		expect(GameLogic.buyHat(p, def.id)).toBeTruthy()
		expect(p.hatPoints).toBe(2)
		expect(p.hats[def.id]).toBe(true)
		expect(p.hat).toBe(def.id)
	end)

	it("can't buy twice, without points, or a made-up hat", function()
		local p = ProfileSchema.default()
		local def = Config.Hats[2]
		local ok, why = GameLogic.buyHat(p, def.id)
		expect(ok).toBeFalsy()
		expect(why).toBe("not enough hat points")
		p.hatPoints = 10000
		GameLogic.buyHat(p, def.id)
		local again, why2 = GameLogic.buyHat(p, def.id)
		expect(again).toBeFalsy()
		expect(why2).toBe("already owned")
		expect(p.hatPoints).toBe(10000 - def.cost)
		for _, bad in { "flag", "", 5, nil, {} } do
			expect(GameLogic.buyHat(p, bad)).toBeFalsy()
		end
	end)

	it("you can only wear hats you own, and take them off", function()
		local p = ProfileSchema.default()
		expect(GameLogic.wearHat(p, "crown")).toBeFalsy()
		p.hats.crown = true
		expect(GameLogic.wearHat(p, "crown")).toBeTruthy()
		expect(p.hat).toBe("crown")
		expect(GameLogic.wearHat(p, "")).toBeTruthy()
		expect(p.hat).toBe("")
	end)

	it("every hat has a price and costs go up", function()
		local last = 0
		for _, def in Config.Hats do
			expect(def.cost).toBeAtLeast(last + 1)
			last = def.cost
		end
	end)
end)

describe("Robux extras", function()
	it("no product or pass id is made up (all 0 until carter sets them)", function()
		for _, id in Config.Products do
			expect(id).toBe(0)
		end
		for _, skin in Config.Skins do
			expect(skin.passId).toBe(0)
		end
	end)

	it("a helper slot purchase is granted once, even if Roblox retries", function()
		local p = ProfileSchema.default()
		expect(GameLogic.grantProduct(p, "abc", "helperSlot")).toBe("granted")
		expect(GameLogic.grantProduct(p, "abc", "helperSlot")).toBe("duplicate")
		expect(p.helperSlots).toBe(1)
		expect(Economy.maxHelpers(p)).toBe(Config.MAX_HELPERS + 1)
		expect(GameLogic.grantProduct(p, "xyz", "mystery")).toBe("unknown")
	end)

	it("extra slots let more helpers work, up to the cap", function()
		local p = ProfileSchema.default()
		p.cash = 1e12
		p.resets = 1
		GameLogic.unlockHelper(p, "buddy")
		GameLogic.unlockHelper(p, "zippy")
		p.crew.chompy = 1
		expect(GameLogic.setTeam(p, "chompy", true)).toBeFalsy()
		GameLogic.grantProduct(p, "r1", "helperSlot")
		expect(GameLogic.setTeam(p, "chompy", true)).toBeTruthy()
		expect(#p.team).toBe(3)
		for i = 2, Config.MAX_EXTRA_HELPER_SLOTS + 2 do
			GameLogic.grantProduct(p, `r{i}`, "helperSlot")
		end
		expect(p.helperSlots).toBe(Config.MAX_EXTRA_HELPER_SLOTS)
	end)

	it("skins need the pass", function()
		local p = ProfileSchema.default()
		local skin = Config.Skins[1]
		expect(GameLogic.chooseSkin(p, skin.id, false)).toBeFalsy()
		expect(p.skin).toBe("")
		expect(GameLogic.chooseSkin(p, skin.id, true)).toBeTruthy()
		expect(p.skin).toBe(skin.id)
		expect(GameLogic.chooseSkin(p, "fake", true)).toBeFalsy()
		expect(GameLogic.chooseSkin(p, "", false)).toBeTruthy()
		expect(p.skin).toBe("")
	end)
end)

describe("New save fields", function()
	it("old saves get the new fields filled in", function()
		local p = ProfileSchema.migrate({ version = 1, cash = 5, stats = { flips = 3 } })
		expect(p.cash).toBe(5)
		expect(p.stats.flips).toBe(3)
		expect(p.stats.bestCombo).toBe(0)
		expect(p.hat).toBe("")
		expect(p.helperSlots).toBe(0)
		expect(#p.receipts).toBe(0)
	end)

	it("bad hat, skin and slot values are cleaned", function()
		local p = ProfileSchema.migrate({
			version = 1,
			hats = { party = true, flag = true, crown = "yes" },
			hat = "crown", -- not really owned
			skin = "gold-bars",
			helperSlots = 99,
			receipts = { "a", 5, "b" },
		})
		expect(p.hats.party).toBe(true)
		expect(p.hats.flag).toBeNil()
		expect(p.hats.crown).toBeNil()
		expect(p.hat).toBe("")
		expect(p.skin).toBe("")
		expect(p.helperSlots).toBe(Config.MAX_EXTRA_HELPER_SLOTS)
		expect(#p.receipts).toBe(2)
	end)

	it("keeps only the newest receipts", function()
		local list = {}
		for i = 1, Config.MAX_SAVED_RECEIPTS + 10 do
			list[i] = `r{i}`
		end
		local p = ProfileSchema.migrate({ version = 1, receipts = list })
		expect(#p.receipts).toBe(Config.MAX_SAVED_RECEIPTS)
		expect(p.receipts[1]).toBe("r11")
	end)
end)

describe("Leaderboards", function()
	it("values are safe whole numbers", function()
		expect(Economy.leaderboardValue(12.7)).toBe(12)
		expect(Economy.leaderboardValue(-5)).toBe(0)
		expect(Economy.leaderboardValue(0 / 0)).toBe(0)
		expect(Economy.leaderboardValue(math.huge)).toBe(2 ^ 53)
	end)

	it("snapshot carries hats, skin, slots and passes", function()
		local p = ProfileSchema.default()
		p.hats.duck = true
		p.hat = "duck"
		local s = GameLogic.snapshot(p, { doubleCash = true })
		expect(#s.hats).toBe(1)
		expect(s.hats[1]).toBe("duck")
		expect(s.hat).toBe("duck")
		expect(s.maxHelpers).toBe(Config.MAX_HELPERS)
		expect(s.passes.doubleCash).toBe(true)
	end)
end)
