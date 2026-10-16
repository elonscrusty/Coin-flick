local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local ProfileSchema = require(ReplicatedStorage.Shared.Util.ProfileSchema)
local GameLogic = require(ServerScriptService.Server.Util.GameLogic)

describe("Helper crew", function()
	it("every helper unlocks later and costs more than the one before", function()
		local lastCost, lastResets = 0, -1
		for _, def in Config.HelperTypes do
			expect(def.cost).toBeAtLeast(lastCost + 1)
			expect(def.resets).toBeAtLeast(lastResets)
			lastCost, lastResets = def.cost, def.resets
		end
	end)

	it("you need enough resets and cash to unlock", function()
		local p = ProfileSchema.default()
		p.cash = 1e9
		local ok, why = GameLogic.unlockHelper(p, "zippy")
		expect(ok).toBeFalsy()
		expect(why).toBe("needs more resets")
		p.resets = 1
		p.cash = 10
		local ok2, why2 = GameLogic.unlockHelper(p, "zippy")
		expect(ok2).toBeFalsy()
		expect(why2).toBe("not enough cash")
		for _, bad in { "boss", "", 3, nil, {} } do
			expect(GameLogic.unlockHelper(p, bad)).toBeFalsy()
		end
	end)

	it("a new helper rests if every spot is taken", function()
		local p = ProfileSchema.default()
		p.cash = 1e9
		p.resets = 2 -- 2 spots
		GameLogic.unlockHelper(p, "buddy")
		GameLogic.unlockHelper(p, "zippy")
		GameLogic.unlockHelper(p, "chompy")
		expect(#p.team).toBe(2)
		expect(p.crew.chompy).toBe(1)
		expect(table.find(p.team, "chompy")).toBeNil()
		-- swap: rest Buddy, put Chompy to work
		expect(GameLogic.setTeam(p, "buddy", false)).toBeTruthy()
		expect(GameLogic.setTeam(p, "chompy", true)).toBeTruthy()
		expect(table.find(p.team, "chompy") ~= nil).toBeTruthy()
		expect(#p.team).toBe(2)
	end)

	it("only owned helpers can work, and bad input is refused", function()
		local p = ProfileSchema.default()
		expect(GameLogic.setTeam(p, "buddy", true)).toBeFalsy()
		p.crew.buddy = 1
		expect(GameLogic.setTeam(p, "buddy", "yes")).toBeFalsy()
		expect(GameLogic.setTeam(p, "buddy", true)).toBeTruthy()
		expect(GameLogic.setTeam(p, "buddy", true)).toBeTruthy() -- already working: no double
		expect(#p.team).toBe(1)
	end)

	it("levels cost more each time, make him faster and richer, and stop at max", function()
		local def = Config.HelperTypes[1]
		local p = ProfileSchema.default()
		p.crew.buddy = 1
		p.cash = 1e12
		local lastCost = 0
		for level = 1, Config.HELPER_MAX_LEVEL - 1 do
			local cost = Economy.helperLevelCost(def, level)
			expect(cost).toBeAtLeast(lastCost + 1)
			lastCost = cost
			expect(GameLogic.levelHelper(p, "buddy")).toBeTruthy()
		end
		expect(p.crew.buddy).toBe(Config.HELPER_MAX_LEVEL)
		local ok, why = GameLogic.levelHelper(p, "buddy")
		expect(ok).toBeFalsy()
		expect(why).toBe("maxed")
		expect(Economy.helperInterval(def, 10) < Economy.helperInterval(def, 1)).toBeTruthy()
		expect(Economy.helperCashMult(def, 10) > Economy.helperCashMult(def, 1)).toBeTruthy()
		expect(GameLogic.levelHelper(p, "king")).toBeFalsy()
	end)

	it("only working helpers earn while you're away", function()
		local p = ProfileSchema.default()
		p.crew.buddy = 1
		expect(Economy.helperCashPerSecond(p)).toBe(0)
		p.team = { "buddy" }
		local one = Economy.helperCashPerSecond(p)
		expect(one > 0).toBeTruthy()
		p.crew.buddy = 5
		expect(Economy.helperCashPerSecond(p) > one).toBeTruthy()
	end)

	it("old saves: a v1 helper becomes Buddy on the team", function()
		local p = ProfileSchema.migrate({ version = 1, cash = 3, helpers = 1 })
		expect(p.version).toBe(2)
		expect(p.crew.buddy).toBe(1)
		expect(p.team[1]).toBe("buddy")
		local q = ProfileSchema.migrate({ version = 1, helpers = 0 })
		expect(#q.team).toBe(0)
	end)

	it("bad crew and team values are cleaned, team never beats the spots", function()
		local p = ProfileSchema.migrate({
			version = 2,
			crew = { buddy = 99, zippy = 2, ghost = 4, chompy = "lots" },
			team = { "buddy", "buddy", "ghost", "zippy", "chompy" },
		})
		expect(p.crew.buddy).toBe(Config.HELPER_MAX_LEVEL)
		expect(p.crew.ghost).toBeNil()
		expect(p.crew.chompy).toBeNil()
		expect(#p.team).toBe(1) -- 0 resets = 1 spot
		expect(p.team[1]).toBe("buddy")
	end)
end)
