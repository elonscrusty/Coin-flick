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
			expect(row.button.look).toBe("locked")
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
		expect(rows[1].button.text).toBe("DONE ✔")
		expect(rows[4].button.text).toBe("CLAIM!")
		expect(rows[4].canClaim).toBe(true)
		expect(rows[4].count).toBe("3/3")
		Goals.claimChallengeBonus(p.challenges, week)
		rows = GoalsPanelView.challengeRows(viewOf(p))
		expect(rows[4].button.text).toBe("DONE ✔")
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
		expect(rows[1].button.text).toBe("DONE ✔")
		expect(rows[2].button.text).toBe("CLAIM!")
		expect(rows[2].canClaim).toBe(true)
		expect(rows[3].button.text).toBe("2m 05s")
		expect(rows[3].button.look).toBe("poor")
		expect(rows[3].text).toBe("Play 20 min")
		expect(GiftPetView.playGiftRows(view, 130)[3].button.text).toBe("CLAIM!")
		expect(GiftPetView.dailyDot(nil, view)).toBe(true)
	end)
end)
