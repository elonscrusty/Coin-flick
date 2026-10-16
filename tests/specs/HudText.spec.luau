local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HudText = require(ReplicatedStorage.Shared.Util.HudText)

describe("HUD words", function()
	it("info strip shows what one heads really pays", function()
		expect(HudText.info(1, 0.5, 3, 25)).toBe("Heads = $1  •  🍀 50% luck  •  🪙 3/25")
		-- x1.5 bonus on $1: a heads pays $2 (rounded like Economy), so say $2
		expect(HudText.info(1.5, 0.5, 3, 25)).toBe("Heads = $2  •  🍀 50% luck  •  🪙 3/25")
		expect(HudText.info(1.4, 0.8, 25, 25)).toBe("Heads = $1  •  🍀 80% luck  •  🪙 25/25")
		expect(HudText.info(123456, 0.62, 10, 25)).toBe("Heads = $123K  •  🍀 62% luck  •  🪙 10/25")
	end)

	it("boost strip hides when nothing is going on", function()
		expect(HudText.boost(0, 90, 0)).toBe("")
		expect(HudText.boost(5, 90, 0)).toBe("🌟 Mega coin 5/90  •  tap it together!")
		expect(HudText.boost(5, 90, 61.2)).toBe("⚡ 2x CASH  1:02")
		expect(HudText.boost(0, 90, 9)).toBe("⚡ 2x CASH  0:09")
	end)

	it("reset button counts coins until the table is full", function()
		expect(HudText.reset(1, 10, false)).toBe("1/10")
		expect(HudText.reset(10, 10, true)).toBe("RESET!")
	end)
end)
