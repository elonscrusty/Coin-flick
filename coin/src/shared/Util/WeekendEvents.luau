--!strict
-- Weekend events as pure rules (tests/specs/WeekendEvents.spec.luau). UTC Saturday 00:00 to Monday
-- 00:00 is the weekend. During it: luck x2 (every rare coin twice as likely, via luckRoll) and a
-- coin rain every RAIN_EVERY seconds that lasts RAIN_SECONDS (heads pay RAIN_MULT x cash).
-- Same answer on every server because it only depends on the clock. Events never change the
-- flip rules for anyone's saved data; they only scale odds and cash while they run.

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)
local WeeklyBoard = require(script.Parent.WeeklyBoard)

type EventView = Types.EventView

local WeekendEvents = {}

local DAY = 86400
local MONDAY_BASED_SATURDAY = 5

-- Day of week, Monday = 0 ... Sunday = 6.
local function weekday(unixTime: number): number
	return (math.floor(unixTime / DAY) + 3) % 7
end

function WeekendEvents.isWeekend(unixTime: number): boolean
	return weekday(unixTime) >= MONDAY_BASED_SATURDAY
end

-- What is going on at `unixTime`.
function WeekendEvents.status(unixTime: number): EventView
	local ev = Config.Events
	local days = math.floor(unixTime / DAY)
	local dow = weekday(unixTime)
	local weekEndsAt = WeeklyBoard.nextReset(unixTime)
	if dow < MONDAY_BASED_SATURDAY then
		return {
			weekend = false,
			luckMult = 1,
			rain = false,
			cashMult = 1,
			endsAt = 0,
			startsAt = (days + (MONDAY_BASED_SATURDAY - dow)) * DAY,
			rainEndsAt = 0,
			nextRainAt = 0,
			weekEndsAt = weekEndsAt,
		}
	end
	local startedAt = (days - (dow - MONDAY_BASED_SATURDAY)) * DAY
	local endsAt = startedAt + 2 * DAY
	local into = unixTime - startedAt
	local slot = math.floor(into / ev.RAIN_EVERY)
	local rainStart = startedAt + slot * ev.RAIN_EVERY
	local raining = unixTime - rainStart < ev.RAIN_SECONDS
	local nextRain = rainStart + ev.RAIN_EVERY
	if nextRain >= endsAt then
		nextRain = 0 -- no more rain this weekend
	end
	return {
		weekend = true,
		luckMult = ev.LUCK_MULT,
		rain = raining,
		cashMult = if raining then ev.RAIN_MULT else 1,
		endsAt = endsAt,
		startsAt = 0,
		rainEndsAt = if raining then rainStart + ev.RAIN_SECONDS else 0,
		nextRainAt = nextRain,
		weekEndsAt = weekEndsAt,
	}
end

-- Turns a rarity roll in [0, 1) into a luckier one: rare coins sit at the low end of the roll,
-- so dividing by the luck multiplier makes every rare `mult` times as likely.
function WeekendEvents.luckRoll(roll: number, luckMult: number): number
	if luckMult <= 1 or roll ~= roll then
		return roll
	end
	return roll / luckMult
end

-- True when two views differ in anything the client shows, so the server only broadcasts changes.
function WeekendEvents.changed(a: EventView?, b: EventView): boolean
	if not a then
		return true
	end
	return a.weekend ~= b.weekend or a.rain ~= b.rain or a.endsAt ~= b.endsAt or a.nextRainAt ~= b.nextRainAt
end

return WeekendEvents
