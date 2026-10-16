local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local Friends = require(ReplicatedStorage.Shared.Util.Friends)
local ProfileSchema = require(ReplicatedStorage.Shared.Util.ProfileSchema)
local GameLogic = require(ServerScriptService.Server.Util.GameLogic)

describe("Friend bonus", function()
	it("friends in the server both get the bonus, strangers do not", function()
		local pairs = { ["1:2"] = true }
		local flags = Friends.flags({ 1, 2, 3 }, function(a, b)
			return pairs[`{math.min(a, b)}:{math.max(a, b)}`] == true
		end)
		expect(flags[1]).toBe(true)
		expect(flags[2]).toBe(true)
		expect(flags[3]).toBeNil()
	end)

	it("one friend is enough, and a lone player never gets it", function()
		local flags = Friends.flags({ 7 }, function()
			return true
		end)
		expect(flags[7]).toBeNil()
		local all = Friends.flags({ 1, 2, 3 }, function()
			return true
		end)
		expect(all[1] and all[2] and all[3]).toBe(true)
	end)

	it("each pair is asked once", function()
		local asked = 0
		Friends.flags({ 1, 2, 3, 4 }, function()
			asked += 1
			return false
		end)
		expect(asked).toBe(6)
	end)

	it("the bonus is a real 2x on heads cash", function()
		expect(Friends.multiplier(false)).toBe(1)
		expect(Friends.multiplier(true)).toBe(Config.FRIEND_CASH_MULT)
		local solo = ProfileSchema.default()
		local duo = ProfileSchema.default()
		local a = GameLogic.applyFlip(solo, 0, nil, Friends.multiplier(false), 0)
		local b = GameLogic.applyFlip(duo, 0, nil, Friends.multiplier(true), 0)
		expect(a.result).toBe("heads")
		expect(b.cash).toBe(a.cash * 2)
	end)
end)

describe("Offline coin pile", function()
	it("keeps piling for 8 hours, then stops", function()
		local p = ProfileSchema.default()
		p.crew = { buddy = 1 }
		p.team = { "buddy" }
		expect(Config.OFFLINE_CAP_SECONDS).toBe(8 * 3600)
		local eight = Economy.offlineEarnings(p, 8 * 3600)
		expect(eight).toBeAtLeast(1)
		expect(Economy.offlineEarnings(p, 4 * 3600)).toBeAtMost(math.ceil(eight / 2) + 1)
		expect(Economy.offlineEarnings(p, 20 * 3600)).toBe(eight)
	end)
end)
