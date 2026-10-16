--!strict
-- The words and numbers behind the heads-in-a-row counter, the prize pop, the
-- "welcome back" card and the friend chip. Pure, so Lune can check them.

local Format = require(script.Parent.Format)

local StreakView = {}

StreakView.SHOW_FROM = 2 -- the counter appears from this many heads in a row
StreakView.DRAMA_BEFORE_GOAL = 2 -- the last two heads before the prize are dramatic

export type Stage = "idle" | "build" | "drama"

function StreakView.stage(streak: number, goal: number): Stage
	if streak < StreakView.SHOW_FROM then
		return "idle"
	elseif streak >= goal - StreakView.DRAMA_BEFORE_GOAL then
		return "drama"
	end
	return "build"
end

function StreakView.counter(streak: number, goal: number): string
	return `🔥 {streak}/{goal} HEADS`
end

-- Camera shake power for a streak step (0 = none): grows toward the goal.
function StreakView.shake(streak: number, goal: number): number
	if StreakView.stage(streak, goal) ~= "drama" then
		return 0
	end
	return 0.08 * (streak - (goal - StreakView.DRAMA_BEFORE_GOAL) + 1)
end

-- How big the counter pops on each new heads (UIScale), bigger when dramatic.
function StreakView.pop(streak: number, goal: number): number
	local stage = StreakView.stage(streak, goal)
	if stage == "drama" then
		return 1.25 + 0.1 * (streak - (goal - StreakView.DRAMA_BEFORE_GOAL))
	end
	return 1.12
end

-- A hint line under the counter for the last step.
function StreakView.hint(streak: number, goal: number): string
	if streak == goal - 1 then
		return "ONE MORE!"
	end
	return ""
end

function StreakView.winTitle(goal: number): string
	return `{goal} IN A ROW!`
end

function StreakView.winLine(cash: number, hats: number): string
	return `+${Format.short(math.floor(cash))}  +🎩{Format.short(math.floor(hats))}`
end

function StreakView.lostLine(streak: number): string
	return `Streak over: {streak} heads`
end

-- Only a lost streak that got somewhere is worth a message.
function StreakView.worthMourning(streak: number): boolean
	return streak >= 3
end

function StreakView.friendChip(mult: number): string
	return `👫 {mult}x cash`
end

-- "Multi Flip" badge text on the info card: only when a tap flips extra coins.
function StreakView.multi(flipsPerTap: number): string
	return if flipsPerTap > 1 then `🌀x{flipsPerTap}` else ""
end

return StreakView
