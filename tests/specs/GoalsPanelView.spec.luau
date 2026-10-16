local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Config = require(ReplicatedStorage.Shared.Config)
local GoalsConfig = require(ReplicatedStorage.Shared.GoalsConfig)
local Goals = require(ReplicatedStorage.Shared.Util.Goals)
local GoalsPanelView = require(ReplicatedStorage.Shared.Util.GoalsPanelView)
local PanelView = require(ReplicatedStorage.Shared.Util.PanelView)
local ProfileSchema = require(ReplicatedStorage.Shared.Util.ProfileSchema)
local GameLogic = require(ServerScriptService.Server.Util.GameLogic)

local WEEK_START = 345600 + 7 * 2900 * 86400

local function fresh(best)
	local p = ProfileSchema.default()
	p.stats.bestStreak = best or 0
	return p
end

local function viewOf(p, now)
	return Goals.view(p, now or WEEK_START + 3600, 2)
end

describe("GOALS tab: streak ladder", function()
	it("a new player sees 4 locked looks and what is next", function()
		local v = viewOf(fresh(0))
		local rows = GoalsPanelView.ladderRows(v)
		expect(#rows).toBe(#GoalsConfig.Ladder)
		for _, row in rows do
			expect(row.action).toBe("none")
			expect(row.button.look).toBe("poor")
		end
		expect(rows[1].button.text).toBe(`0/{GoalsConfig.Ladder[1].need}`)
		expect(GoalsPanelView.ladderHeader(v)).toBe(`Best streak: 0 heads. Next look at {GoalsConfig.Ladder[1].need}!`)
	end)

	it("a reached look can be worn, and taken off", function()
		local p = fresh(5)
		local rows = GoalsPanelView.ladderRows(viewOf(p))
		expect(rows[1].action).toBe("wear")
		expect(rows[1].button.look).toBe("buy")
		expect(rows[3].action).toBe("none")
		Goals.wearRung(p, "bronze")
		rows = GoalsPanelView.ladderRows(viewOf(p))
		expect(rows[1].action).toBe("off")
		expect(rows[1].button.text).toBe("TAKE OFF")
		expect(rows[1].worn).toBe(true)
	end)

	it("all looks won says so", function()
		local text = GoalsPanelView.ladderHeader(viewOf(fresh(10)))
		expect(text).toBe("Best streak: 10 heads. All looks won!")
	end)
end)

describe("GOALS tab: weekly challenges", function()
	it("3 challenges plus the bonus (slot 0), NOT YET at the start", function()
		local rows = GoalsPanelView.challengeRows(viewOf(fresh()))
		expect(#rows).toBe(4)
		expect(rows[4].slot).toBe(0)
		for _, row in rows do
			expect(row.button.text).toBe("NOT YET")
			expect(row.canClaim).toBe(false)
		end
	end)

	it("a finished challenge reads CLAIM!, then DONE; the bonus follows all three", function()
		local p = fresh()
		local week = Goals.week(WEEK_START + 3600)
		Goals.rolloverChallenges(p.challenges, week)
		local list = Goals.challengesFor(week)
		p.challenges.progress[1] = list[1].goal
		local rows = GoalsPanelView.challengeRows(viewOf(p))
		expect(rows[1].button.text).toBe("CLAIM!")
		expect(rows[1].canClaim).toBe(true)
		expect(rows[1].frac).toBe(1)
		for slot = 1, 3 do
			p.challenges.progress[slot] = list[slot].goal
			Goals.claimChallenge(p.challenges, week, slot)
		end
		rows = GoalsPanelView.challengeRows(viewOf(p))
		expect(rows[1].button.text).toBe("DONE")
		expect(rows[4].button.text).toBe("CLAIM!")
		expect(rows[4].canClaim).toBe(true)
		expect(rows[4].count).toBe("3/3")
		Goals.claimChallengeBonus(p.challenges, week)
		rows = GoalsPanelView.challengeRows(viewOf(p))
		expect(rows[4].button.text).toBe("DONE")
	end)

	it("the clock counts down to Monday", function()
		local v = viewOf(fresh(), WEEK_START + 7 * 86400 - 3 * 86400 - 3600)
		expect(GoalsPanelView.weekTimer(v, 0)).toBe("New challenges in 3d 01h")
		expect(GoalsPanelView.longTime(90)).toBe("1m")
		expect(GoalsPanelView.longTime(7500)).toBe("2h 05m")
		expect(GoalsPanelView.weekTimer(v, 3600)).toBe("New challenges in 3d 00h")
	end)

	it("the red dot follows what can be claimed", function()
		local p = fresh()
		expect(GoalsPanelView.dot(viewOf(p))).toBe(false)
		local week = Goals.week(WEEK_START + 3600)
		Goals.rolloverChallenges(p.challenges, week)
		p.challenges.progress[2] = Goals.challengesFor(week)[2].goal
		expect(GoalsPanelView.dot(viewOf(p))).toBe(true)
		expect(GoalsPanelView.dot(nil)).toBe(false)
	end)
end)

describe("GOALS tab: coin book", function()
	it("every rare coin has a page; unfound ones stay a mystery", function()
		local p = fresh()
		local rows = GoalsPanelView.pageRows(viewOf(p))
		expect(#rows).toBe(#Config.Rarities)
		expect(rows[1].title).toBe("???")
		expect(rows[1].state).toBe("hidden")
		local summary = GoalsPanelView.bookSummary(viewOf(p))
		expect(summary.frac).toBe(0)
		expect(summary.text).toBe(`0/{#Config.Rarities} pages`)
	end)

	it("a found coin shows its name, count and the prize that was paid", function()
		local p = fresh()
		local easiest = Config.Rarities[#Config.Rarities]
		Goals.recordRare(p.book, easiest.id)
		Goals.recordRare(p.book, easiest.id)
		local rows = GoalsPanelView.pageRows(viewOf(p))
		expect(rows[1].title).toBe(easiest.name)
		expect(rows[1].line).toBe("Found 2 times")
		expect(rows[1].prize).toBe("Prize got ✔")
		expect(rows[1].state).toBe("paid")
		expect(GoalsPanelView.bookSummary(viewOf(p)).frac > 0).toBe(true)
	end)
end)

describe("Ladder coin look", function()
	it("snapshot carries the worn look", function()
		local p = fresh(10)
		Goals.wearRung(p, "crown")
		expect(GameLogic.snapshot(p).ladderSkin).toBe("crown")
	end)

	it("a worn ladder look dresses the coins; a Robux skin still wins", function()
		local p = fresh(10)
		expect(GameLogic.coinSkin(p, false)).toBeNil()
		Goals.wearRung(p, "crown")
		local look = GameLogic.coinSkin(p, false)
		expect(look.coin).toBe(GoalsConfig.Ladder[4].coin)
		expect(look.text).toBe(GoalsConfig.Ladder[4].text)
		p.skin = "candy"
		local skin = GameLogic.coinSkin(p, true)
		expect(skin.coin).toBe(Config.Skins[1].coin)
		-- pass lost: falls back to the ladder look
		expect(GameLogic.coinSkin(p, false).coin).toBe(GoalsConfig.Ladder[4].coin)
	end)

	it("a look you have not reached never shows", function()
		local p = fresh(2)
		p.ladderSkin = "crown"
		expect(GameLogic.coinSkin(p, false)).toBeNil()
	end)

	it("GOALS is a shop tab", function()
		expect(table.find(PanelView.TAB_ORDER, "goals") ~= nil).toBe(true)
		expect(PanelView.TAB_LABEL.goals).toBe(GoalsPanelView.TAB_LABEL)
	end)
end)

describe("THIS WEEK board, badges, play gifts", function()
	local GiftPetView = require(ReplicatedStorage.Shared.Util.GiftPetView)

	it("THIS WEEK is a top 10 tab with a reset clock", function()
		local found = false
		for _, tab in PanelView.BOARD_TABS do
			if tab[1] == "weekFlips" then
				found = true
				expect(tab[2]).toBe("THIS WEEK")
			end
		end
		expect(found).toBe(true)
		expect(PanelView.boardNote("weekFlips", 1000 + 3 * 86400 + 4 * 3600, 1000)).toBe("Resets in 3d 4h")
		expect(PanelView.boardNote("flips", 5000, 1000)).toBe("")
		expect(PanelView.boardNote("weekFlips", nil, 1000)).toBe("")
	end)

	it("your weekly number comes from the weekly board", function()
		local rows = { { name = "Ava", value = 500 }, { name = "Me", value = 1234 } }
		expect(PanelView.weekValueOf(rows, "Me")).toBe(1234)
		expect(PanelView.weekValueOf(rows, "Zed")).toBe(0)
		expect(PanelView.weekValueOf(nil, "Me")).toBe(0)
		local snap: any = { flips = 99999, biggestFlip = 0, resets = 0 }
		expect(PanelView.myValue("weekFlips", snap, 1234)).toBe("1.23K")
	end)

	it("badges: header counts, earned ones come first", function()
		local view = {
			earned = 1,
			badges = {
				{ id = "a", name = "A", text = "Do A", earned = false },
				{ id = "b", name = "B", text = "Do B", earned = true },
			},
		}
		expect(GoalsPanelView.badgeHeader(view)).toBe("BADGES 1/2")
		local cards = GoalsPanelView.badgeCards(view)
		expect(cards[1].id).toBe("b")
		expect(cards[2].id).toBe("a")
		expect(cards[2].text).toBe("Do A")
	end)

	it("play gifts: waiting shows a countdown, ready says CLAIM!, claimed says DONE", function()
		local view = {
			seconds = 100,
			claimable = 1,
			gifts = {
				{ slot = 1, minutes = 5, cash = 10, hats = 1, state = "claimed", left = 0 },
				{ slot = 2, minutes = 10, cash = 20, hats = 2, state = "ready", left = 0 },
				{ slot = 3, minutes = 20, cash = 40, hats = 3, state = "waiting", left = 125 },
			},
		}
		local rows = GiftPetView.playGiftRows(view, 0)
		expect(rows[1].button.text).toBe("DONE")
		expect(rows[2].button.text).toBe("CLAIM!")
		expect(rows[2].canClaim).toBe(true)
		expect(rows[3].button.text).toBe("Next gift 2:05")
		expect(rows[3].button.look).toBe("poor")
		expect(rows[3].text).toBe("Play 20 min")
		expect(GiftPetView.playGiftRows(view, 130)[3].button.text).toBe("CLAIM!")
		expect(GiftPetView.dailyDot(nil, view)).toBe(true)
	end)
end)

describe("Round 10 polish", function()
	local GiftPetView = require(ReplicatedStorage.Shared.Util.GiftPetView)
	local EventText = require(ReplicatedStorage.Shared.Util.EventText)

	it("goal texts agree: 1 head, 2 times", function()
		expect(PanelView.fixCount("Get 1 heads")).toBe("Get 1 head")
		expect(PanelView.fixCount("Get 250 heads")).toBe("Get 250 heads")
		expect(PanelView.fixCount("Hit the 10 heads streak 2 time")).toBe("Hit the 10 heads streak 2 times")
		expect(PanelView.fixCount("Hit the 10 heads streak 1 time")).toBe("Hit the 10 heads streak 1 time")
		expect(PanelView.fixCount("Help flip the MEGA coin 1 times")).toBe("Help flip the MEGA coin 1 time")
		expect(PanelView.fixCount("Flip 1 rare coins")).toBe("Flip 1 rare coin")
		expect(PanelView.fixCount("Flip 3 rare coins")).toBe("Flip 3 rare coins")
		expect(PanelView.fixCount("Buy 1 upgrades")).toBe("Buy 1 upgrade")
	end)

	it("every real job and challenge text reads right", function()
		for _, kind in Config.Daily.JobKinds do
			for _, goal in kind.goals do
				local text = PanelView.fixCount(string.format(kind.text, goal))
				expect(string.find(text, "1 heads", 1, true)).toBeNil()
				expect(string.find(text, "1 times", 1, true)).toBeNil()
			end
		end
	end)

	it("one gift timer wording for the HUD chip and the GIFTS tab", function()
		expect(EventText.giftWait(231)).toBe("Next gift 3:51")
		local view = {
			seconds = 0,
			claimable = 0,
			gifts = { { slot = 1, minutes = 5, cash = 10, hats = 1, state = "waiting", left = 231 } },
		}
		expect(GiftPetView.playGiftRows(view, 0)[1].button.text).toBe("Next gift 3:51")
		local chip = EventText.gift(view, 0)
		expect(chip).toBe("Next gift 3:51")
	end)

	it("a claimed daily gift shows the same countdown, not a blue blank", function()
		local Daily = require(ReplicatedStorage.Shared.Util.Daily)
		local d = Daily.empty()
		Daily.claimGift(d, 20000)
		local v = Daily.view(d, 1, 20000, 2)
		local rows = GiftPetView.dailyRows(v, 20000 * 86400 + 3600)
		expect(rows.gift.text).toBe("Next gift 23h 00m")
		expect(rows.gift.look).toBe("done")
	end)

	it("goal progress buttons use the dim grey look, never the purple locked one", function()
		local rows = GoalsPanelView.ladderRows(viewOf(fresh(0)))
		for _, row in rows do
			expect(row.button.look).toBe("poor")
		end
	end)

	it("all four ladder icons are plain emoji every phone can draw", function()
		for _, rung in GoalsConfig.Ladder do
			expect(#rung.icon > 0).toBe(true)
			for _, cp in utf8.codes(rung.icon) do
				expect(cp < 0x1FA00).toBe(true) -- 🫧 (U+1FAE7) showed blank
			end
		end
	end)

	it("pet and badge unlocks are one banner: title, name, picture", function()
		local title, name, icon = PanelView.unlockBanner("pet", "New pet! 🐷 Piggy is yours!")
		expect(title).toBe("NEW PET!")
		expect(name).toBe("Piggy")
		expect(icon).toBe("🐷")
		local t2, n2, i2 = PanelView.unlockBanner("badge", "Badge: Full Crew!")
		expect(t2).toBe("NEW BADGE!")
		expect(n2).toBe("Full Crew")
		expect(i2).toBe("🏅")
		expect(PanelView.unlockBanner("bought", "x")).toBeNil()
	end)

	it("reset and away words say crew", function()
		local lines = PanelView.resetLines({ resetBonus = 2, tableFull = true, coinCount = 3 } :: any)
		expect(lines[2].text).toBe("KEEP: crew + 🎩 hats")
	end)
end)

describe("Menu art pass", function()
	it("every tab has a picture", function()
		for _, key in PanelView.TAB_ORDER do
			expect(PanelView.TAB_ICON[key] ~= nil).toBe(true)
		end
		for _, tab in PanelView.BOARD_TABS do
			expect(PanelView.TAB_ICON[tab[1]] ~= nil).toBe(true)
		end
	end)

	it("tab widths fill the whole row, the picked tab is widest", function()
		for count = 1, 7 do
			for picked = 1, count do
				local sizes = PanelView.tabWeights(count, picked, 6)
				local scale, offset = 0, 0
				for i, s in sizes do
					scale += s[1]
					offset += s[2]
					if i ~= picked and count > 1 then
						expect(s[1] < sizes[picked][1]).toBe(true)
					end
				end
				expect(math.abs(scale - 1)).toBeAtMost(1e-9)
				expect(math.abs(offset + 6 * (count - 1))).toBeAtMost(1e-9)
			end
		end
	end)

	it("on a 7 tab phone row the picked tab says its word, the others show a picture", function()
		local row = 440 -- px
		local sizes = PanelView.tabWeights(7, 3, 6)
		for i, s in sizes do
			local px = row * s[1] + s[2]
			local text = PanelView.tabText("X", "WORD", px, i == 3)
			if i == 3 then
				expect(text).toBe("X WORD")
				expect(px >= 100).toBe(true)
			else
				expect(text).toBe("X")
				expect(px >= 40).toBe(true) -- a thumb-sized tab
			end
		end
		expect(PanelView.tabText("X", "WORD", 140, false)).toBe("X WORD")
	end)
end)

describe("Round 11 polish", function()
	local GiftPetView = require(ReplicatedStorage.Shared.Util.GiftPetView)
	local EventText = require(ReplicatedStorage.Shared.Util.EventText)
	local Daily = require(ReplicatedStorage.Shared.Util.Daily)
	local Plural = require(ReplicatedStorage.Shared.Util.Plural)

	it("the daily gift button and the HUD chip show the same next-gift number", function()
		local d = Daily.empty()
		Daily.claimGift(d, 20000)
		local daily = Daily.view(d, 1, 20000, 2)
		local now = 20000 * 86400 + 3600
		local play = {
			seconds = 0,
			claimable = 0,
			gifts = { { slot = 1, minutes = 5, cash = 10, hats = 1, state = "waiting", left = 224 } },
		}
		local rows = GiftPetView.dailyRows(daily, now, play, 0)
		expect(rows.gift.text).toBe("Next gift 3:44")
		expect(rows.gift.text).toBe((EventText.gift(play, 0)))
		-- 10 seconds later both tick down together
		expect(GiftPetView.dailyRows(daily, now, play, 10).gift.text).toBe("Next gift 3:34")
		expect((EventText.gift(play, 10))).toBe("Next gift 3:34")
		-- no play gift waiting: the wait for tomorrow
		expect(GiftPetView.dailyRows(daily, now, nil, 0).gift.text).toBe("Next gift 23h 00m")
		expect(rows.timer).toBe("Daily gifts reset in 23h 00m")
	end)

	it("no job or challenge text ever says '1 heads', '2 time' or 'time(s)'", function()
		for day = 20000, 20040 do
			for userId = 1, 40 do
				for _, job in Daily.jobsFor(userId, day) do
					expect(string.find(job.text, "(s)", 1, true)).toBeNil()
					expect(string.find(job.text, "1 heads", 1, true)).toBeNil()
					expect(string.find(job.text, "1 times", 1, true)).toBeNil()
					expect(string.find(job.text, "%f[%d][2-9]%d* time%f[%W]")).toBeNil()
				end
			end
			for _, ch in Goals.challengesFor(day // 7) do
				expect(string.find(ch.text, "(s)", 1, true)).toBeNil()
				expect(string.find(ch.text, "1 heads", 1, true)).toBeNil()
			end
		end
		for _, kind in Config.Daily.JobKinds do
			expect(string.find(kind.text, "(s)", 1, true)).toBeNil()
		end
		expect(Plural.fix("Help flip the mega coin 2 time")).toBe("Help flip the mega coin 2 times")
	end)

	it("a locked streak look is a bright bar with its number, not a button", function()
		local rows = GoalsPanelView.ladderRows(viewOf(fresh(1)))
		expect(rows[1].action).toBe("none")
		expect(rows[1].count).toBe("1/3")
		expect(math.abs(rows[1].frac - 1 / 3)).toBeAtMost(0.001)
		expect(rows[4].count).toBe("1/10")
		local reached = GoalsPanelView.ladderRows(viewOf(fresh(5)))
		expect(reached[1].action).toBe("wear")
		expect(reached[1].frac).toBe(1)
		expect(reached[3].count).toBe("5/7")
	end)
end)
