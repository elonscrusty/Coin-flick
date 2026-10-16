--!strict
-- Weekly top 10 rules (tests/specs/WeeklyBoard.spec.luau). A week runs Monday 00:00 UTC to the next
-- Monday 00:00 UTC. The weekly score is flips since the week began for the player, kept as a
-- baseline in profile.week (so no flip code has to change). The server writes the score to an
-- ordered store whose name has the week number in it, so every Monday a fresh, empty board starts.

local Types = require(script.Parent.Parent.Types)

type WeekState = Types.WeekState

local WeeklyBoard = {}

-- 1970-01-01 was a Thursday, so shift 3 days to make weeks start on Monday.
local OFFSET_DAYS = 3

function WeeklyBoard.week(unixTime: number): number
	return math.floor((math.floor(unixTime / 86400) + OFFSET_DAYS) / 7)
end

-- Unix time when `week` starts.
function WeeklyBoard.startOf(week: number): number
	return (week * 7 - OFFSET_DAYS) * 86400
end

-- Unix time the board that is running at `unixTime` resets (next Monday 00:00 UTC).
function WeeklyBoard.nextReset(unixTime: number): number
	return WeeklyBoard.startOf(WeeklyBoard.week(unixTime) + 1)
end

function WeeklyBoard.empty(): WeekState
	return { week = 0, base = 0 }
end

local function num(value: unknown): number
	if typeof(value) == "number" and value == value and value > -math.huge and value < math.huge then
		return math.max(0, math.floor(value))
	end
	return 0
end

function WeeklyBoard.sanitize(raw: unknown): WeekState
	if typeof(raw) ~= "table" then
		return WeeklyBoard.empty()
	end
	local t = raw :: { [string]: any }
	return { week = num(t.week), base = num(t.base) }
end

-- Starts the player's week when it changed: the baseline becomes their total flips now.
-- Returns true when it moved to a new week.
function WeeklyBoard.sync(s: WeekState, week: number, totalFlips: number): boolean
	if s.week == week then
		return false
	end
	if s.week > week then
		return false -- saved by a server whose clock ran ahead: keep that week
	end
	s.week = week
	s.base = num(totalFlips)
	return true
end

-- Flips this week (0 when the saved week is not this one).
function WeeklyBoard.score(s: WeekState, week: number, totalFlips: number): number
	if s.week ~= week then
		return 0
	end
	return math.max(0, num(totalFlips) - s.base)
end

-- Name of the ordered store for `week`, so a new week is a new, empty board.
function WeeklyBoard.storeName(prefix: string, key: string, week: number): string
	return `{prefix}{key}_w{week}_v1`
end

return WeeklyBoard
