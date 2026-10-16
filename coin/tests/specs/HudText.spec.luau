local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HudText = require(ReplicatedStorage.Shared.Util.HudText)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local ProfileSchema = require(ReplicatedStorage.Shared.Util.ProfileSchema)

describe("HUD words", function()
	it("the Heads card shows exactly what a normal heads pays (after resets, big coins, 2x)", function()
		for resets = 0, 5 do
			for big = 0, 4 do
				local p = ProfileSchema.default()
				p.resets = resets
				p.upgrades.bigCoins = big
				local shown = Economy.cashPerHeads(p)
				local _, paid = Economy.resolveFlip(p, 0, 1, 1)
				expect(HudText.pay(shown)).toBe(HudText.pay(paid))
				local _, paid2 = Economy.resolveFlip(p, 0, 1, 2)
				expect(HudText.pay(shown * 2)).toBe(HudText.pay(paid2))
				expect(HudText.info(shown, 0.5, 2)).toBe(`Heads = ${HudText.pay(paid2)}\nLuck 50%`)
			end
		end
	end)

	it("heads pay shows a decimal only when it is not whole", function()
		expect(HudText.pay(1)).toBe("1")
		expect(HudText.pay(1.5)).toBe("1.5")
		expect(HudText.pay(2.25)).toBe("2.3")
		expect(HudText.pay(3.0000001)).toBe("3")
		expect(HudText.pay(0)).toBe("0")
		expect(HudText.pay(999.96)).toBe("1000")
		expect(HudText.pay(123456)).toBe("123K")
	end)

	it("info card is two labelled lines", function()
		expect(HudText.info(1, 0.5)).toBe("Heads = $1\nLuck 50%")
		-- x1.5 after a reset: the card says $1.5, matching the popup
		expect(HudText.info(1.5, 0.5)).toBe("Heads = $1.5\nLuck 50%")
		expect(HudText.info(123456, 0.62)).toBe("Heads = $123K\nLuck 62%")
	end)

	it("boost strip hides when nothing is going on", function()
		expect(HudText.boost(0)).toBe("")
		expect(HudText.mega(0, 90)).toBe("")
		expect(HudText.mega(5, 90)).toBe("🌟 5/90")
		expect(HudText.boost(61.2)).toBe("⚡ 2x  1:02")
		expect(HudText.boost(9)).toBe("⚡ 2x  0:09")
		-- both chips can show at once: progress stays while the timer runs
		expect(HudText.mega(87, 90)).toBe("🌟 87/90")
	end)

	it("reset button says RESET, then RESET! when ready; bar counts coins", function()
		expect(HudText.reset(false)).toBe("RESET")
		expect(HudText.reset(true)).toBe("RESET!")
		expect(HudText.resetCount(1, 10)).toBe("1")
		expect(HudText.resetCount(24, 25)).toBe("24")
		expect(HudText.resetCount(10, 10)).toBe("GO!")
	end)
end)
