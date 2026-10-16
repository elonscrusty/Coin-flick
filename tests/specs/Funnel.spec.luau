local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Funnel = require(ReplicatedStorage.Shared.Util.Funnel)
local ProfileSchema = require(ReplicatedStorage.Shared.Util.ProfileSchema)

local function fresh()
	return ProfileSchema.default()
end

describe("Funnel (where players quit)", function()
	it("a brand new player has only reached Joined", function()
		local got = Funnel.newlyReached(fresh(), {})
		expect(#got).toBe(1)
		expect(Funnel.steps[got[1]].name).toBe("Joined")
	end)

	it("steps are reported once and in order as the player progresses", function()
		local p = fresh()
		local reached = {}
		for _, i in Funnel.newlyReached(p, reached) do
			reached[i] = true
		end
		p.stats.flips = 12
		local got = Funnel.newlyReached(p, reached)
		expect(#got).toBe(2) -- Flip 1 and Flips 10
		expect(got[1] < got[2]).toBe(true)
		for _, i in got do
			reached[i] = true
		end
		expect(#Funnel.newlyReached(p, reached)).toBe(0)
	end)

	it("a player can skip ahead (reset before 1000 flips)", function()
		local p = fresh()
		p.resets = 1
		local names = {}
		for _, i in Funnel.newlyReached(p, {}) do
			names[Funnel.steps[i].name] = true
		end
		expect(names["First reset"]).toBe(true)
		expect(names["Flips 1000"]).toBe(nil)
	end)

	it("furthest step and minute marks", function()
		expect(Funnel.furthest({})).toBe(0)
		expect(Funnel.furthest({ [2] = true, [5] = true })).toBe(5)
		expect(Funnel.minuteMark(30)).toBe(0)
		expect(Funnel.minuteMark(60)).toBe(1)
		expect(Funnel.minuteMark(5 * 60 + 10)).toBe(5)
		expect(Funnel.minuteMark(99 * 60)).toBe(40)
	end)
end)
