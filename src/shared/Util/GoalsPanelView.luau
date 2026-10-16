--!strict
-- What the GOALS shop tab draws (streak ladder, weekly challenges, coin book) as plain data,
-- so tests/specs/GoalsPanelView.spec.luau can check words, bars and buttons offline.
-- The server decides and pays every prize; these views only describe it.

local Format = require(script.Parent.Format)
local Goals = require(script.Parent.Goals)
local PanelView = require(script.Parent.PanelView)

type GoalsView = Goals.GoalsView
type Look = PanelView.Look

local GoalsPanelView = {}

export type Button = { text: string, look: Look }
export type LadderRow = {
	id: string,
	icon: string,
	name: string,
	line: string,
	button: Button,
	action: "wear" | "off" | "none",
	owned: boolean,
	worn: boolean,
}
export type ChallengeRow = {
	slot: number, -- 1..3, 0 = the all-three bonus
	text: string,
	frac: number,
	count: string,
	reward: string,
	button: Button,
	canClaim: boolean,
}
export type PageRow = { id: string, title: string, line: string, prize: string, state: "found" | "paid" | "hidden" }
export type BookSummary = { frac: number, text: string, bonus: string }

GoalsPanelView.TAB_LABEL = "GOALS"
GoalsPanelView.LADDER_HEADER = "STREAK LOOKS"
GoalsPanelView.WEEK_HEADER = "WEEKLY CHALLENGES"
GoalsPanelView.BOOK_HEADER = "COIN BOOK"
GoalsPanelView.BONUS_TEXT = "Finish all 3 for a bonus!"

-- "3d 04h", "5h 20m", "12m".
function GoalsPanelView.longTime(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	if s >= 86400 then
		return string.format("%dd %02dh", s // 86400, (s % 86400) // 3600)
	elseif s >= 3600 then
		return string.format("%dh %02dm", s // 3600, (s % 3600) // 60)
	end
	return string.format("%dm", math.max(1, s // 60))
end

local function reward(cash: number, hats: number): string
	local text = PanelView.money(cash)
	if hats > 0 then
		text ..= ` +🎩{hats}`
	end
	return text
end

function GoalsPanelView.ladderHeader(view: GoalsView): string
	local ladder = view.ladder
	if ladder.nextNeed == 0 then
		return `Best streak: {ladder.best} heads. All looks won!`
	end
	return `Best streak: {ladder.best} heads. Next look at {ladder.nextNeed}!`
end

function GoalsPanelView.ladderRows(view: GoalsView): { LadderRow }
	local rows: { LadderRow } = {}
	for _, rung in view.ladder.rungs do
		local button: Button
		local action: "wear" | "off" | "none"
		if rung.worn then
			button, action = { text = "TAKE OFF", look = "equipped" }, "off"
		elseif rung.owned then
			button, action = { text = "WEAR", look = "buy" }, "wear"
		else
			button, action = { text = `{view.ladder.best}/{rung.need}`, look = "locked" }, "none"
		end
		table.insert(rows, {
			id = rung.id,
			icon = rung.icon,
			name = rung.name,
			line = `{rung.need} heads in a row`,
			button = button,
			action = action,
			owned = rung.owned,
			worn = rung.worn,
		})
	end
	return rows
end

-- `elapsed` = seconds since the view arrived, so the clock keeps counting between updates.
function GoalsPanelView.weekTimer(view: GoalsView, elapsed: number): string
	return `New challenges in {GoalsPanelView.longTime(view.challenges.secondsLeft - elapsed)}`
end

-- The 3 challenges, then the all-three bonus as slot 0.
function GoalsPanelView.challengeRows(view: GoalsView): { ChallengeRow }
	local rows: { ChallengeRow } = {}
	for _, item in view.challenges.items do
		local button: Button = if item.claimed
			then { text = "DONE ✔", look = "owned" }
			elseif item.done then { text = "CLAIM!", look = "buy" }
			else { text = "NOT YET", look = "poor" }
		table.insert(rows, {
			slot = item.slot,
			text = item.text,
			frac = math.clamp(item.progress / math.max(1, item.goal), 0, 1),
			count = `{Format.short(item.progress)}/{Format.short(item.goal)}`,
			reward = reward(item.cash, item.hats),
			button = button,
			canClaim = item.done and not item.claimed,
		})
	end
	local bonus = view.challenges.bonus
	local doneCount = 0
	for _, item in view.challenges.items do
		if item.claimed then
			doneCount += 1
		end
	end
	local total = #view.challenges.items
	table.insert(rows, {
		slot = 0,
		text = GoalsPanelView.BONUS_TEXT,
		frac = if total > 0 then doneCount / total else 0,
		count = `{doneCount}/{total}`,
		reward = reward(bonus.cash, bonus.hats),
		button = if bonus.claimed
			then { text = "DONE ✔", look = "owned" }
			elseif bonus.ready then { text = "CLAIM!", look = "buy" }
			else { text = "NOT YET", look = "poor" },
		canClaim = bonus.ready,
	})
	return rows
end

function GoalsPanelView.bookSummary(view: GoalsView): BookSummary
	local book = view.book
	return {
		frac = if book.total > 0 then book.found / book.total else 0,
		text = `{book.found}/{book.total} pages`,
		bonus = if book.bonusPaid
			then "Full book prize: got it ✔"
			else `Full book prize: {reward(book.bonusCash, book.bonusHats)}`,
	}
end

-- Pages read easiest first. An unfound coin stays a mystery (name hidden), prize shown.
function GoalsPanelView.pageRows(view: GoalsView): { PageRow }
	local rows: { PageRow } = {}
	for _, page in view.book.pages do
		table.insert(rows, {
			id = page.id,
			title = if page.found then page.name else "???",
			line = if page.found
				then `Found {Format.short(page.count)} time{if page.count == 1 then "" else "s"}`
				else "Not found yet",
			prize = if page.paid then "Prize got ✔" else `Prize {reward(page.cash, page.hats)}`,
			state = if page.paid then "paid" elseif page.found then "found" else "hidden",
		})
	end
	return rows
end

-- Red dot on the GOALS tab: a challenge or the bonus can be claimed.
function GoalsPanelView.dot(view: GoalsView?): boolean
	return view ~= nil and (view.challenges.claimable > 0 or view.challenges.bonus.ready)
end

return GoalsPanelView
