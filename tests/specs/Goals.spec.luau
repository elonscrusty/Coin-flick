local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local GoalsConfig = require(ReplicatedStorage.Shared.GoalsConfig)
local Goals = require(ReplicatedStorage.Shared.Util.Goals)
local ProfileSchema = require(ReplicatedStorage.Shared.Util.ProfileSchema)

local MONDAY = 345600 + 7 * 2900 * 86400 -- 1970-01-05 was a Monday; this is 2900 weeks later
local DAY = 86400

describe("Goals: save and clean-up", function()
	it("a new player starts with empty goals", function()
		local p = ProfileSchema.default()
		expect(p.ladderSkin).toBe("")
		expect(p.challenges.week).toBe(0)
		expect(#p.challenges.progress).toBe(3)
		expect(next(p.book.found)).toBe(nil)
	end)

	it("an old save gets empty goals and keeps its best streak", function()
		local p = ProfileSchema.migrate({ version = 3, stats = { bestStreak = 6 } })
		expect(p.stats.bestStreak).toBe(6)
		expect(p.challenges.bonusClaimed).toBeFalsy()
		expect(p.ladderSkin).toBe("")
	end)

	it("bad goal data is cleaned, nothing invented", function()
		local p = ProfileSchema.migrate({
			version = 3,
			stats = { bestStreak = 4 },
			ladderSkin = "crown", -- not reached
			challenges = {
				week = -5,
				progress = { "x", 1e308 * 10, 7 },
				claimed = { true, "no" },
				bonusClaimed = "yes",
			},
			book = { found = { silver = 2, ghost = 9, gold = 0 }, paid = { silver = true, giant = true, all = true } },
		})
		expect(p.ladderSkin).toBe("")
		expect(p.challenges.week).toBe(0)
		expect(p.challenges.progress[1]).toBe(0)
		expect(p.challenges.progress[2]).toBe(0)
		expect(p.challenges.progress[3]).toBe(7)
		expect(p.challenges.claimed[1]).toBeTruthy()
		expect(p.challenges.claimed[2]).toBeFalsy()
		expect(p.challenges.bonusClaimed).toBeFalsy()
		expect(p.book.found.silver).toBe(2)
		expect(p.book.found.ghost).toBe(nil)
		expect(p.book.found.gold).toBe(nil)
		expect(p.book.paid.silver).toBe(true)
		expect(p.book.paid.giant).toBe(nil) -- never found, so never "paid"
		expect(p.book.paid.all).toBe(nil)
	end)

	it("goals survive a save round trip", function()
		local p = ProfileSchema.default()
		p.stats.bestStreak = 7
		p.ladderSkin = "neon"
		Goals.bumpChallenge(p.challenges, 2900, "flip", 5)
		Goals.recordRare(p.book, "gold")
		local back = ProfileSchema.migrate(p)
		expect(back.ladderSkin).toBe("neon")
		expect(back.challenges.week).toBe(2900)
		expect(back.book.found.gold).toBe(1)
		expect(back.book.paid.gold).toBe(true)
	end)
end)

describe("Goals: streak ladder", function()
	it("rungs go up and the top rung is the streak goal", function()
		local last = 0
		for _, rung in GoalsConfig.Ladder do
			expect(rung.need > last).toBeTruthy()
			last = rung.need
		end
		expect(last).toBe(Config.STREAK_GOAL)
	end)

	it("a rung is earned by best streak and a skull never takes it back", function()
		local p = ProfileSchema.default()
		expect(Goals.rungsOwned(p)).toBe(0)
		p.stats.bestStreak = 3
		expect(Goals.ownsRung(p, "bronze")).toBeTruthy()
		expect(Goals.ownsRung(p, "pearl")).toBeFalsy()
		p.stats.bestStreak = 10
		expect(Goals.rungsOwned(p)).toBe(4)
	end)

	it("you can only wear a rung you reached; wearing puts the Robux skin away", function()
		local p = ProfileSchema.default()
		p.stats.bestStreak = 5
		p.skin = "candy"
		for _, bad in { "crown", "nope", 5, {}, false } do
			expect(Goals.wearRung(p, bad)).toBeFalsy()
		end
		expect(p.ladderSkin).toBe("")
		expect(p.skin).toBe("candy")
		expect(Goals.wearRung(p, "pearl")).toBeTruthy()
		expect(p.ladderSkin).toBe("pearl")
		expect(p.skin).toBe("")
		expect(Goals.wearRung(p, "")).toBeTruthy()
		expect(p.ladderSkin).toBe("")
	end)
end)

describe("Goals: weekly challenges", function()
	it("weeks start on Monday 00:00 UTC", function()
		expect(Goals.week(MONDAY)).toBe(Goals.week(MONDAY + 6 * DAY + 86399))
		expect(Goals.week(MONDAY + 7 * DAY)).toBe(Goals.week(MONDAY) + 1)
		expect(Goals.week(MONDAY - 1)).toBe(Goals.week(MONDAY) - 1)
		expect(Goals.secondsLeft(MONDAY)).toBe(7 * DAY)
		expect(Goals.secondsLeft(MONDAY + 7 * DAY - 10)).toBe(10)
	end)

	it("three different challenges a week, the same for everyone, every kind comes round", function()
		local seen = {}
		for week = 100, 105 do
			local list = Goals.challengesFor(week)
			expect(#list).toBe(3)
			expect(list[1].kind ~= list[2].kind and list[2].kind ~= list[3].kind and list[1].kind ~= list[3].kind).toBeTruthy()
			for _, ch in list do
				seen[ch.kind] = true
			end
		end
		local kinds = 0
		for _ in seen do
			kinds += 1
		end
		expect(kinds).toBe(#GoalsConfig.Challenges)
		expect(Goals.challengesFor(100)[1].text).toBe(Goals.challengesFor(100)[1].text)
	end)

	it("progress counts only matching kinds and stops at the goal", function()
		local c = Goals.emptyChallenges()
		local week = 100
		local ch = Goals.challengesFor(week)[1]
		expect(Goals.bumpChallenge(c, week, ch.kind, 1)).toBeTruthy()
		expect(c.progress[1]).toBe(1)
		Goals.bumpChallenge(c, week, ch.kind, ch.goal * 3)
		expect(c.progress[1]).toBe(ch.goal)
		expect(Goals.bumpChallenge(c, week, "nonsense", 1)).toBeFalsy()
		expect(Goals.bumpChallenge(c, week, ch.kind, 0)).toBeFalsy()
		expect(Goals.bumpChallenge(c, week, ch.kind, -4)).toBeFalsy()
	end)

	local function finish(c, week)
		for _, ch in Goals.challengesFor(week) do
			Goals.bumpChallenge(c, week, ch.kind, ch.goal)
		end
	end

	it("claim pays once, only when done, bad slots are refused", function()
		local c = Goals.emptyChallenges()
		local week = 100
		local ch = Goals.challengesFor(week)[2]
		local r, why = Goals.claimChallenge(c, week, 2)
		expect(r).toBe(nil)
		expect(why).toBe("NotDone")
		finish(c, week)
		local reward = Goals.claimChallenge(c, week, 2)
		expect(reward.flips).toBe(ch.flips)
		expect(reward.hats).toBe(ch.hats)
		local again, why2 = Goals.claimChallenge(c, week, 2)
		expect(again).toBe(nil)
		expect(why2).toBe("Claimed")
		for _, bad in { 0, 4, -1, 1.5, "1", {}, false, 0 / 0 } do
			expect((Goals.claimChallenge(c, week, bad))).toBe(nil)
		end
	end)

	it("the all-three bonus needs all three claimed and pays once", function()
		local c = Goals.emptyChallenges()
		local week = 100
		finish(c, week)
		expect((Goals.claimChallengeBonus(c, week))).toBe(nil)
		Goals.claimChallenge(c, week, 1)
		Goals.claimChallenge(c, week, 2)
		expect((Goals.claimChallengeBonus(c, week))).toBe(nil) -- 2 of 3 is not enough
		Goals.claimChallenge(c, week, 3)
		local bonus = Goals.claimChallengeBonus(c, week)
		expect(bonus.flips).toBe(GoalsConfig.CHALLENGE_BONUS.flips)
		expect((Goals.claimChallengeBonus(c, week))).toBe(nil)
	end)

	it("a new week starts fresh: progress and claims reset", function()
		local c = Goals.emptyChallenges()
		finish(c, 100)
		Goals.claimChallenge(c, 100, 1)
		Goals.bumpChallenge(c, 101, "flip", 1)
		expect(c.week).toBe(101)
		expect(c.claimed[1]).toBeFalsy()
		expect(c.bonusClaimed).toBeFalsy()
	end)

	it("you cannot claim last week's finished challenge in a new week", function()
		local c = Goals.emptyChallenges()
		finish(c, 100)
		local r = Goals.claimChallenge(c, 101, 1)
		expect(r).toBe(nil)
	end)
end)

describe("Goals: coin book", function()
	it("every rare coin has a page prize; normal coins are not in the book", function()
		for _, def in Config.Rarities do
			expect(GoalsConfig.Book.rewards[def.id] ~= nil).toBeTruthy()
		end
		local b = Goals.emptyBook()
		local page, all = Goals.recordRare(b, "normal")
		expect(page).toBe(nil)
		expect(all).toBe(nil)
		expect((Goals.recordRare(b, "bogus"))).toBe(nil)
		expect(next(b.found)).toBe(nil)
	end)

	it("first find pays, finding it again only counts", function()
		local b = Goals.emptyBook()
		local page = Goals.recordRare(b, "silver")
		expect(page.flips).toBe(GoalsConfig.Book.rewards.silver.flips)
		expect((Goals.recordRare(b, "silver"))).toBe(nil)
		expect(b.found.silver).toBe(2)
	end)

	it("a full book pays the big prize exactly once", function()
		local b = Goals.emptyBook()
		local bigs = 0
		for round = 1, 3 do
			for _, def in Config.Rarities do
				local _, all = Goals.recordRare(b, def.id)
				if all then
					bigs += 1
				end
			end
		end
		expect(bigs).toBe(1)
		expect(Goals.bookComplete(b)).toBeTruthy()
		expect(b.paid.all).toBe(true)
	end)
end)

describe("Goals: what the client draws", function()
	it("view shows ladder, this week's challenges and the book", function()
		local p = ProfileSchema.default()
		p.stats.bestStreak = 5
		p.ladderSkin = "bronze"
		local v = Goals.view(p, MONDAY, 10)
		expect(#v.ladder.rungs).toBe(4)
		expect(v.ladder.rungs[1].worn).toBeTruthy()
		expect(v.ladder.rungs[2].owned).toBeTruthy()
		expect(v.ladder.rungs[3].owned).toBeFalsy()
		expect(v.ladder.nextNeed).toBe(7)
		expect(#v.challenges.items).toBe(3)
		expect(v.challenges.items[1].progress).toBe(0)
		expect(v.challenges.secondsLeft).toBe(7 * DAY)
		expect(v.challenges.bonus.ready).toBeFalsy()
		expect(#v.book.pages).toBe(#Config.Rarities)
		expect(v.book.pages[1].id).toBe("silver") -- easiest first
		expect(v.book.found).toBe(0)
	end)

	it("view turns flips into cash and never shows last week's progress", function()
		local p = ProfileSchema.default()
		local week = Goals.week(MONDAY)
		Goals.bumpChallenge(p.challenges, week - 1, "flip", 3)
		local v = Goals.view(p, MONDAY, 10)
		for _, item in v.challenges.items do
			expect(item.progress).toBe(0)
		end
		expect(v.challenges.items[1].cash).toBe(Goals.challengesFor(week)[1].flips * 10)
	end)

	it("view says the bonus is ready once all three are claimed", function()
		local p = ProfileSchema.default()
		local week = Goals.week(MONDAY)
		for _, ch in Goals.challengesFor(week) do
			Goals.bumpChallenge(p.challenges, week, ch.kind, ch.goal)
		end
		expect(Goals.view(p, MONDAY, 1).challenges.claimable).toBe(3)
		for slot = 1, 3 do
			Goals.claimChallenge(p.challenges, week, slot)
		end
		expect(Goals.view(p, MONDAY, 1).challenges.bonus.ready).toBeTruthy()
		Goals.claimChallengeBonus(p.challenges, week)
		local v = Goals.view(p, MONDAY, 1)
		expect(v.challenges.bonus.ready).toBeFalsy()
		expect(v.challenges.bonus.claimed).toBeTruthy()
	end)
end)
