local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local PlayGifts = require(ReplicatedStorage.Shared.Util.PlayGifts)
local Badges = require(ReplicatedStorage.Shared.Util.Badges)
local WeeklyBoard = require(ReplicatedStorage.Shared.Util.WeeklyBoard)
local WeekendEvents = require(ReplicatedStorage.Shared.Util.WeekendEvents)
local ProfileSchema = require(ReplicatedStorage.Shared.Util.ProfileSchema)

local DAY = 86400
-- 2026-10-12 00:00 UTC is a Monday.
local MONDAY = 1791763200

local function play(s, today, seconds)
	for _ = 1, math.ceil(seconds / Config.PlayGifts.MAX_STEP) do
		PlayGifts.add(s, today, math.min(seconds, Config.PlayGifts.MAX_STEP))
		seconds -= Config.PlayGifts.MAX_STEP
	end
end

describe("Play-time gifts", function()
	local today = math.floor(MONDAY / DAY)

	it("a gift is ready after its minutes, not before", function()
		local s = PlayGifts.empty()
		play(s, today, 299)
		local _, why = PlayGifts.claim(s, today, 1)
		expect(why).toBe("NotYet")
		play(s, today, 1)
		local reward = PlayGifts.claim(s, today, 1)
		expect(reward.flips).toBe(Config.PlayGifts.Gifts[1].flips)
	end)

	it("each gift pays once a day", function()
		local s = PlayGifts.empty()
		play(s, today, 400)
		expect(PlayGifts.claim(s, today, 1) ~= nil).toBe(true)
		local _, why = PlayGifts.claim(s, today, 1)
		expect(why).toBe("Claimed")
		local _, why2 = PlayGifts.claim(s, today, 2)
		expect(why2).toBe("NotYet")
	end)

	it("bad slots are refused", function()
		local s = PlayGifts.empty()
		play(s, today, 4000)
		for _, bad in { 0, 5, -1, 1.5, "1", true, {}, 0 / 0 } do
			local reward, why = PlayGifts.claim(s, today, bad)
			expect(reward).toBeNil()
			expect(why).toBe("BadGift")
		end
		local reward = PlayGifts.claim(s, today, nil)
		expect(reward).toBeNil()
	end)

	it("one tick can only add a small step", function()
		local s = PlayGifts.empty()
		PlayGifts.add(s, today, 1e9)
		expect(s.seconds).toBe(Config.PlayGifts.MAX_STEP)
		PlayGifts.add(s, today, -50)
		PlayGifts.add(s, today, 0 / 0)
		expect(s.seconds).toBe(Config.PlayGifts.MAX_STEP)
	end)

	it("a gift you did not claim stays waiting after midnight, never lost", function()
		local s = PlayGifts.empty()
		play(s, today, 1000) -- gifts 1 and 2 ready
		expect(PlayGifts.claimable(s)).toBe(2)
		PlayGifts.rollover(s, today + 1)
		expect(s.seconds).toBe(0)
		expect(PlayGifts.claimable(s)).toBe(2)
		expect(PlayGifts.claim(s, today + 1, 1) ~= nil).toBe(true)
		local _, why = PlayGifts.claim(s, today + 1, 1)
		expect(why).toBe("NotYet") -- paid once, new day starts at zero
		expect(PlayGifts.claim(s, today + 1, 2) ~= nil).toBe(true)
	end)

	it("a day with a claim then a new day lets you earn it again", function()
		local s = PlayGifts.empty()
		play(s, today, 400)
		PlayGifts.claim(s, today, 1)
		play(s, today + 1, 400)
		expect(PlayGifts.claim(s, today + 1, 1) ~= nil).toBe(true)
	end)

	it("a clock that ran ahead keeps everything and pays nothing extra", function()
		local s = PlayGifts.empty()
		play(s, today + 5, 400)
		PlayGifts.claim(s, today + 5, 1)
		PlayGifts.rollover(s, today) -- earlier day than saved
		expect(s.seconds).toBe(400)
		local _, why = PlayGifts.claim(s, today, 1)
		expect(why).toBe("Claimed")
	end)

	it("the view says waiting, ready or claimed and counts down", function()
		local s = PlayGifts.empty()
		play(s, today, 400)
		PlayGifts.claim(s, today, 1)
		local v = PlayGifts.view(s, today, 10)
		expect(#v.gifts).toBe(#Config.PlayGifts.Gifts)
		expect(v.gifts[1].state).toBe("claimed")
		expect(v.gifts[2].state).toBe("waiting")
		expect(v.gifts[2].left).toBe(15 * 60 - 400)
		expect(v.gifts[1].cash).toBe(Config.PlayGifts.Gifts[1].flips * 10)
		expect(v.claimable).toBe(0)
		play(s, today, 600)
		expect(PlayGifts.view(s, today, 10).claimable).toBe(1)
	end)

	it("bad saved data is cleaned", function()
		local s = PlayGifts.sanitize({ day = -4, seconds = 1e12, claimed = { true, "x" }, owed = { true, true, 7 } })
		expect(s.day).toBe(0)
		expect(s.seconds).toBe(86400)
		expect(s.claimed[1]).toBe(true)
		expect(s.owed[1]).toBe(false) -- claimed wins, never both
		expect(s.owed[2]).toBe(true)
		expect(s.owed[3]).toBe(false)
		expect(#PlayGifts.sanitize("junk").claimed).toBe(#Config.PlayGifts.Gifts)
	end)
end)

describe("Badges", function()
	it("never uses a made-up badge id", function()
		for _, def in Config.Badges do
			expect(def.badgeId).toBe(0)
		end
		expect(#Config.Badges).toBe(4)
	end)

	it("each badge needs its goal", function()
		local p = ProfileSchema.default()
		expect(#Badges.award(p)).toBe(0)
		p.stats.bestStreak = 9
		expect(Badges.met("streak10", p)).toBe(false)
		p.stats.bestStreak = 10
		expect(Badges.met("streak10", p)).toBe(true)
		p.stats.flips = 999999
		expect(Badges.met("flips1m", p)).toBe(false)
		p.stats.flips = 1000000
		expect(Badges.met("flips1m", p)).toBe(true)
		expect(Badges.met("firstReset", p)).toBe(false)
		p.resets = 1
		expect(Badges.met("firstReset", p)).toBe(true)
		expect(Badges.met("nope", p)).toBe(false)
	end)

	it("all helpers needs every helper", function()
		local p = ProfileSchema.default()
		for i, def in Config.HelperTypes do
			expect(Badges.met("allHelpers", p)).toBe(false)
			p.crew[def.id] = 1
			if i == #Config.HelperTypes then
				expect(Badges.met("allHelpers", p)).toBe(true)
			end
		end
	end)

	it("a badge is awarded once and kept", function()
		local p = ProfileSchema.default()
		p.resets = 1
		p.stats.bestStreak = 10
		local first = Badges.award(p)
		expect(#first).toBe(2)
		expect(#Badges.award(p)).toBe(0)
		p.resets = 0 -- never taken back
		expect(p.badges.firstReset).toBe(true)
		expect(Badges.view(p).earned).toBe(2)
	end)

	it("bad saved badges are cleaned", function()
		local b = Badges.sanitize({ streak10 = true, fake = true, flips1m = "yes", firstReset = false })
		expect(b.streak10).toBe(true)
		expect(b.fake).toBeNil()
		expect(b.flips1m).toBeNil()
		expect(b.firstReset).toBeNil()
		expect(next(Badges.sanitize(5))).toBeNil()
	end)

	it("old saves get the new fields", function()
		local p = ProfileSchema.migrate({ version = 3, cash = 5 })
		expect(next(p.badges)).toBeNil()
		expect(p.play.seconds).toBe(0)
		expect(p.week.week).toBe(0)
	end)
end)

describe("Weekly top 10", function()
	it("weeks start on Monday 00:00 UTC", function()
		local w = WeeklyBoard.week(MONDAY)
		expect(WeeklyBoard.startOf(w)).toBe(MONDAY)
		expect(WeeklyBoard.week(MONDAY - 1)).toBe(w - 1)
		expect(WeeklyBoard.week(MONDAY + 7 * DAY - 1)).toBe(w)
		expect(WeeklyBoard.week(MONDAY + 7 * DAY)).toBe(w + 1)
		expect(WeeklyBoard.nextReset(MONDAY + 3 * DAY)).toBe(MONDAY + 7 * DAY)
		expect(WeeklyBoard.nextReset(MONDAY)).toBe(MONDAY + 7 * DAY)
	end)

	it("score is flips since the week began, and restarts every Monday", function()
		local s = WeeklyBoard.empty()
		local w = WeeklyBoard.week(MONDAY)
		expect(WeeklyBoard.sync(s, w, 500)).toBe(true)
		expect(WeeklyBoard.sync(s, w, 900)).toBe(false)
		expect(WeeklyBoard.score(s, w, 900)).toBe(400)
		expect(WeeklyBoard.sync(s, w + 1, 1300)).toBe(true)
		expect(WeeklyBoard.score(s, w + 1, 1300)).toBe(0)
		expect(WeeklyBoard.score(s, w + 1, 1350)).toBe(50)
		expect(WeeklyBoard.score(s, w, 1350)).toBe(0) -- old week
	end)

	it("a clock that ran ahead does not rewind the week", function()
		local s = { week = 10, base = 100 }
		expect(WeeklyBoard.sync(s, 9, 5000)).toBe(false)
		expect(s.week).toBe(10)
	end)

	it("each week is its own store, bad values cleaned", function()
		expect(WeeklyBoard.storeName("T_", "weekFlips", 12)).toBe("T_weekFlips_w12_v1")
		local s = WeeklyBoard.sanitize({ week = -3, base = 0 / 0 })
		expect(s.week).toBe(0)
		expect(s.base).toBe(0)
		expect(WeeklyBoard.sanitize("x").week).toBe(0)
		expect(Config.WEEKLY_LEADERBOARDS[1]).toBe("weekFlips")
	end)
end)

describe("Weekend events", function()
	it("weekend is Saturday and Sunday UTC only", function()
		expect(WeekendEvents.isWeekend(MONDAY)).toBe(false)
		expect(WeekendEvents.isWeekend(MONDAY + 4 * DAY + 86399)).toBe(false) -- Friday
		expect(WeekendEvents.isWeekend(MONDAY + 5 * DAY)).toBe(true) -- Saturday 00:00
		expect(WeekendEvents.isWeekend(MONDAY + 6 * DAY + 86399)).toBe(true) -- Sunday night
		expect(WeekendEvents.isWeekend(MONDAY + 7 * DAY)).toBe(false)
	end)

	it("no event on a weekday, and it says when the weekend starts", function()
		local v = WeekendEvents.status(MONDAY + 2 * DAY)
		expect(v.weekend).toBe(false)
		expect(v.luckMult).toBe(1)
		expect(v.cashMult).toBe(1)
		expect(v.rain).toBe(false)
		expect(v.startsAt).toBe(MONDAY + 5 * DAY)
		expect(v.weekEndsAt).toBe(MONDAY + 7 * DAY)
	end)

	it("weekend has luck x2 and a rain every ten minutes", function()
		local sat = MONDAY + 5 * DAY
		local v = WeekendEvents.status(sat + 10)
		expect(v.weekend).toBe(true)
		expect(v.luckMult).toBe(Config.Events.LUCK_MULT)
		expect(v.rain).toBe(true)
		expect(v.cashMult).toBe(Config.Events.RAIN_MULT)
		expect(v.rainEndsAt).toBe(sat + Config.Events.RAIN_SECONDS)
		expect(v.endsAt).toBe(sat + 2 * DAY)
		local dry = WeekendEvents.status(sat + 100)
		expect(dry.rain).toBe(false)
		expect(dry.cashMult).toBe(1)
		expect(dry.luckMult).toBe(Config.Events.LUCK_MULT)
		expect(dry.nextRainAt).toBe(sat + Config.Events.RAIN_EVERY)
		expect(WeekendEvents.status(sat + Config.Events.RAIN_EVERY + 1).rain).toBe(true)
	end)

	it("no rain is promised after the weekend ends", function()
		local last = MONDAY + 7 * DAY - 30
		expect(WeekendEvents.status(last).nextRainAt).toBe(0)
	end)

	it("luck x2 makes every rare twice as likely and changes nothing at x1", function()
		expect(WeekendEvents.luckRoll(0.4, 1)).toBe(0.4)
		expect(WeekendEvents.luckRoll(0.4, 2)).toBe(0.2)
		-- rarity is chosen by a roll under each edge: chance doubles when the roll halves
		local Economy = require(ReplicatedStorage.Shared.Util.Economy)
		local total, boosted = 0, 0
		for i = 0, 99999 do
			local roll = (i + 0.5) / 100000
			if Economy.rollRarity(roll) ~= "normal" then
				total += 1
			end
			if Economy.rollRarity(WeekendEvents.luckRoll(roll, 2)) ~= "normal" then
				boosted += 1
			end
		end
		expect(boosted / total).toBeNear(2, 0.05)
	end)

	it("only broadcasts when something changed", function()
		local a = WeekendEvents.status(MONDAY + 5 * DAY + 10)
		local b = WeekendEvents.status(MONDAY + 5 * DAY + 11)
		expect(WeekendEvents.changed(nil, a)).toBe(true)
		expect(WeekendEvents.changed(a, b)).toBe(false)
		expect(WeekendEvents.changed(a, WeekendEvents.status(MONDAY + 5 * DAY + 100))).toBe(true)
	end)
end)
