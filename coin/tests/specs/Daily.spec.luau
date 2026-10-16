local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Daily = require(ReplicatedStorage.Shared.Util.Daily)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local ProfileSchema = require(ReplicatedStorage.Shared.Util.ProfileSchema)

local DAY = 20000

describe("Daily gift", function()
	it("pays the 7 days in order, once per day", function()
		local d = Daily.empty()
		for i = 1, 7 do
			local reward, index, why = Daily.claimGift(d, DAY + i)
			expect(why).toBeNil()
			expect(index).toBe(i)
			expect(reward.flips).toBe(Config.Daily.Gift[i].flips)
			local again, _, why2 = Daily.claimGift(d, DAY + i)
			expect(again).toBeNil()
			expect(why2).toBe("Claimed")
		end
		local _, wrapped = Daily.claimGift(d, DAY + 8)
		expect(wrapped).toBe(1)
	end)

	it("missing days does not punish: the next claim pays the next gift day", function()
		local d = Daily.empty()
		Daily.claimGift(d, DAY)
		Daily.claimGift(d, DAY + 1)
		local _, index = Daily.claimGift(d, DAY + 30) -- a month away
		expect(index).toBe(3)
	end)

	it("a clock that ran ahead cannot be farmed", function()
		local d = Daily.empty()
		Daily.claimGift(d, DAY + 5)
		local reward, _, why = Daily.claimGift(d, DAY + 2)
		expect(reward).toBeNil()
		expect(why).toBe("Clock")
	end)

	it("day 7 is the biggest gift", function()
		local best = 0
		for i, g in Config.Daily.Gift do
			if i < #Config.Daily.Gift then
				best = math.max(best, g.flips)
			end
		end
		expect(Config.Daily.Gift[#Config.Daily.Gift].flips).toBeAtLeast(best + 1)
	end)
end)

describe("Daily jobs", function()
	it("same player + day = same 3 different jobs", function()
		local a = Daily.jobsFor(12345, DAY)
		local b = Daily.jobsFor(12345, DAY)
		expect(#a).toBe(3)
		local seen = {}
		for i, job in a do
			expect(job.kind).toBe(b[i].kind)
			expect(job.goal).toBe(b[i].goal)
			expect(seen[job.kind]).toBeNil()
			seen[job.kind] = true
			expect(job.goal).toBeAtLeast(1)
		end
	end)

	it("every kind shows up across players and days", function()
		local kinds = {}
		for uid = 1, 40 do
			for day = DAY, DAY + 10 do
				for _, job in Daily.jobsFor(uid * 977, day) do
					kinds[job.kind] = true
				end
			end
		end
		for _, def in Config.Daily.JobKinds do
			expect(kinds[def.kind]).toBe(true)
		end
	end)

	it("progress counts only matching jobs, caps at the goal, then pays once", function()
		local uid = 777
		local d = Daily.empty()
		local job = Daily.jobsFor(uid, DAY)[1]
		expect(Daily.bump(d, uid, DAY, job.kind, job.goal + 50)).toBe(true)
		expect(d.progress[1]).toBe(job.goal)
		expect(Daily.bump(d, uid, DAY, "nonsense", 1)).toBe(false)
		local reward, why = Daily.claimJob(d, uid, DAY, 1)
		expect(why).toBeNil()
		expect(reward.flips).toBe(job.flips)
		local again, why2 = Daily.claimJob(d, uid, DAY, 1)
		expect(again).toBeNil()
		expect(why2).toBe("Claimed")
	end)

	it("cannot claim an unfinished or made-up job", function()
		local d = Daily.empty()
		expect(select(2, Daily.claimJob(d, 5, DAY, 1))).toBe("NotDone")
		for _, bad in { 0, 4, 1.5, "1", -1, 0 / 0, true } do
			expect(select(2, Daily.claimJob(d, 5, DAY, bad))).toBe("BadJob")
		end
		expect(select(2, Daily.claimJob(d, 5, DAY, nil))).toBe("BadJob")
	end)

	it("a new day starts fresh", function()
		local uid = 31
		local d = Daily.empty()
		local job = Daily.jobsFor(uid, DAY)[1]
		Daily.bump(d, uid, DAY, job.kind, job.goal)
		Daily.claimJob(d, uid, DAY, 1)
		expect(Daily.rollover(d, DAY + 1)).toBe(true)
		expect(d.progress[1]).toBe(0)
		expect(d.claimed[1]).toBe(false)
		expect(Daily.rollover(d, DAY + 1)).toBe(false)
	end)

	it("bad numbers never add progress", function()
		local d = Daily.empty()
		local kind = Daily.jobsFor(9, DAY)[1].kind
		Daily.bump(d, 9, DAY, kind, 0)
		Daily.bump(d, 9, DAY, kind, -3)
		Daily.bump(d, 9, DAY, kind, 0 / 0)
		expect(d.progress[1]).toBe(0)
	end)
end)

describe("Daily view + save cleanup", function()
	it("view shows a ready gift and counts the red dot", function()
		local d = Daily.empty()
		local v = Daily.view(d, 1, DAY, 10)
		expect(v.gift.ready).toBe(true)
		expect(v.gift.cash).toBe(Config.Daily.Gift[1].flips * 10)
		expect(v.claimable).toBe(1)
		expect(#v.jobs).toBe(3)
		Daily.claimGift(d, DAY)
		local after = Daily.view(d, 1, DAY, 10)
		expect(after.gift.ready).toBe(false)
		expect(after.gift.dayIndex).toBe(1)
		expect(after.claimable).toBe(0)
		expect(after.nextReset).toBe((DAY + 1) * 86400)
	end)

	it("sanitize repairs junk without inventing progress", function()
		local d = Daily.sanitize({
			day = "x",
			progress = { -4, 0 / 0, 1e9 },
			claimed = { "yes" },
			giftClaims = -2,
			giftDay = 1.9,
		})
		expect(d.day).toBe(0)
		expect(d.progress[1]).toBe(0)
		expect(d.progress[2]).toBe(0)
		expect(d.claimed[1]).toBe(false)
		expect(d.giftClaims).toBe(0)
		expect(d.giftDay).toBe(1)
		expect(#Daily.sanitize(nil).progress).toBe(3)
	end)

	it("old v2 saves migrate to v3 with an empty daily; daily survives a round trip", function()
		local p = ProfileSchema.migrate({ version = 2, cash = 5 })
		expect(p.version).toBe(3)
		expect(p.daily.giftClaims).toBe(0)
		p.daily.giftClaims = 4
		p.daily.giftDay = DAY
		local q = ProfileSchema.migrate(p)
		expect(q.daily.giftClaims).toBe(4)
		expect(q.daily.giftDay).toBe(DAY)
	end)

	it("reward cash follows the player's cash per heads", function()
		local p = ProfileSchema.default()
		p.resets = 2
		local cph = Economy.cashPerHeads(p)
		expect(Daily.cash({ flips = 20, hats = 0 }, cph)).toBe(20 * cph)
	end)
end)
