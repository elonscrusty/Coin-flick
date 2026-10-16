local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local HudText = require(ReplicatedStorage.Shared.Util.HudText)
local StreakView = require(ReplicatedStorage.Shared.Util.StreakView)

local GOAL = Config.STREAK_GOAL

describe("Streak counter", function()
	it("hidden for the first heads, built up in the middle, dramatic for the last two", function()
		expect(StreakView.stage(0, GOAL)).toBe("idle")
		expect(StreakView.stage(1, GOAL)).toBe("idle")
		expect(StreakView.stage(2, GOAL)).toBe("build")
		expect(StreakView.stage(GOAL - 3, GOAL)).toBe("build")
		expect(StreakView.stage(GOAL - 2, GOAL)).toBe("drama")
		expect(StreakView.stage(GOAL - 1, GOAL)).toBe("drama")
	end)

	it("drama (8+ of 10) shakes the camera harder every step, nothing before", function()
		for n = 0, GOAL - 3 do
			expect(StreakView.shake(n, GOAL)).toBe(0)
		end
		local a = StreakView.shake(GOAL - 2, GOAL)
		local b = StreakView.shake(GOAL - 1, GOAL)
		expect(a > 0).toBeTruthy()
		expect(b > a).toBeTruthy()
		expect(b).toBeAtMost(0.3) -- never nauseating
		expect(StreakView.pop(GOAL - 1, GOAL) > StreakView.pop(3, GOAL)).toBeTruthy()
	end)

	it("says the count and the goal, and 'ONE MORE!' only on the step before the prize", function()
		expect(StreakView.counter(7, 10)).toBe("🔥 7/10 HEADS")
		expect(StreakView.hint(9, 10)).toBe("ONE MORE!")
		expect(StreakView.hint(8, 10)).toBe("")
		expect(StreakView.winTitle(10)).toBe("10 IN A ROW!")
		expect(StreakView.winLine(1500, 50)).toBe("+$1.50K  +🎩50")
	end)

	it("only mourns a streak that got somewhere", function()
		expect(StreakView.worthMourning(2)).toBeFalsy()
		expect(StreakView.worthMourning(3)).toBeTruthy()
		expect(StreakView.lostLine(6)).toBe("Streak over: 6 heads")
	end)
end)

describe("Friend chip and Multi Flip badge", function()
	it("names the friend multiplier from Config", function()
		expect(StreakView.friendChip(Config.FRIEND_CASH_MULT)).toBe("👫 2x cash")
	end)

	it("multi flip badge shows only when a tap flips extra coins", function()
		expect(StreakView.multi(1)).toBe("")
		expect(StreakView.multi(3)).toBe("🌀x3")
		expect(HudText.info(2, 0.5, 1, 1)).toBe("Heads = $2\nLuck 50%")
		expect(HudText.info(2, 0.5, 1, 4)).toBe("Heads = $2\nLuck 50% 🌀x4")
	end)

	it("the Heads card multiplier matches Boosts.cashMult (pass x boost x friend)", function()
		expect(HudText.cashMult(false, false, false)).toBe(1)
		expect(HudText.cashMult(false, false, true)).toBe(Config.FRIEND_CASH_MULT)
		expect(HudText.cashMult(true, true, true)).toBe(
			Config.PASS_CASH_MULT * Config.MEGA_BOOST_MULT * Config.FRIEND_CASH_MULT
		)
		expect(HudText.info(2, 0.5, HudText.cashMult(false, true, true), 1)).toBe(
			`Heads = ${HudText.pay(2 * Config.MEGA_BOOST_MULT * Config.FRIEND_CASH_MULT)}\nLuck 50%`
		)
	end)
end)
