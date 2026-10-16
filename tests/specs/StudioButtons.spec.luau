local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ProfileSchema = require(ReplicatedStorage.Shared.Util.ProfileSchema)
local GameLogic = require(ServerScriptService.Server.Util.GameLogic)
local MegaCoin = require(ServerScriptService.Server.Util.MegaCoin)

describe("Studio test buttons", function()
	it("RARE: a heads roll of 0 always lands heads, for every rarity", function()
		local Economy = require(ReplicatedStorage.Shared.Util.Economy)
		for _, id in { "silver", "gold", "rainbow", "giant" } do
			local p = ProfileSchema.default()
			local result, cash = Economy.resolveFlip(p, 0, Economy.rarityRollFor(id), 1)
			expect(result).toBe("heads")
			expect(cash).toBeAtLeast(1)
		end
	end)

	it("MEGA: first press charges the coin 3 taps short, second press flips", function()
		expect(MegaCoin.debugStep(0, 90, 3)).toBe("charge")
		expect(MegaCoin.debugStep(86, 90, 3)).toBe("charge")
		expect(MegaCoin.debugStep(87, 90, 3)).toBe("flip")
		expect(MegaCoin.debugStep(95, 90, 3)).toBe("flip")
	end)

	it("AWAY: pretending to be gone 3 hours pays helper money once", function()
		local p = ProfileSchema.default()
		p.crew = { buddy = 1 }
		p.team = { "buddy" }
		local now = 1000000
		p.lastSeen = now - 3 * 60 * 60
		local cash = GameLogic.applyOffline(p, now)
		expect(cash).toBeAtLeast(1)
		expect(p.cash).toBe(cash)
		expect(p.lastSeen).toBe(now)
		-- Pressing again right away gives nothing more.
		expect(GameLogic.applyOffline(p, now)).toBe(0)
	end)
end)
