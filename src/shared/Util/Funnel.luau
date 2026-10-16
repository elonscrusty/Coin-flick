--!strict
-- "Where do players quit?" as pure rules (tests/specs/Funnel.spec.luau). A list of first-time-player
-- milestones in order; the server logs each one once to Roblox Analytics (Creator Hub > Analytics >
-- Funnels), so the drop-off between two steps shows where players give up. Plus minute marks of play
-- time. Nothing here changes gameplay or saves anything.

local Types = require(script.Parent.Parent.Types)

type Profile = Types.Profile

local Funnel = {}

export type Step = { name: string, met: (profile: Profile) -> boolean }

local function count(map: { [string]: any }): number
	local n = 0
	for _ in map do
		n += 1
	end
	return n
end

-- In order. The step number (its place in this list) is what Roblox shows, so only ever append.
Funnel.steps = table.freeze({
	{
		name = "Joined",
		met = function()
			return true
		end,
	},
	{
		name = "Flip 1",
		met = function(p: Profile)
			return p.stats.flips >= 1
		end,
	},
	{
		name = "Flips 10",
		met = function(p: Profile)
			return p.stats.flips >= 10
		end,
	},
	{
		name = "Flips 50",
		met = function(p: Profile)
			return p.stats.flips >= 50
		end,
	},
	{
		name = "Heads streak 3",
		met = function(p: Profile)
			return p.stats.bestStreak >= 3
		end,
	},
	{
		name = "Flips 200",
		met = function(p: Profile)
			return p.stats.flips >= 200
		end,
	},
	{
		name = "First hat",
		met = function(p: Profile)
			return count(p.hats) >= 1
		end,
	},
	{
		name = "First helper",
		met = function(p: Profile)
			return count(p.crew) >= 1
		end,
	},
	{
		name = "Flips 1000",
		met = function(p: Profile)
			return p.stats.flips >= 1000
		end,
	},
	{
		name = "First reset",
		met = function(p: Profile)
			return p.resets >= 1
		end,
	},
	{
		name = "Heads streak 7",
		met = function(p: Profile)
			return p.stats.bestStreak >= 7
		end,
	},
	{
		name = "Second reset",
		met = function(p: Profile)
			return p.resets >= 2
		end,
	},
} :: { Step })

-- Minutes of play in one visit that get a "still here" mark.
Funnel.minuteMarks = table.freeze({ 1, 3, 5, 10, 20, 40 })

-- Steps the profile has newly reached: the first unmet step stops the search? No: a player can skip
-- ahead (buy a hat before 200 flips), so every met step not yet in `reached` counts, in list order.
function Funnel.newlyReached(profile: Profile, reached: { [number]: boolean }): { number }
	local out: { number } = {}
	for index, step in Funnel.steps do
		if not reached[index] and step.met(profile) then
			table.insert(out, index)
		end
	end
	return out
end

-- The furthest step reached so far (0 if none), to say where a player was when they left.
function Funnel.furthest(reached: { [number]: boolean }): number
	local best = 0
	for index in reached do
		best = math.max(best, index)
	end
	return best
end

-- Largest minute mark at or below `seconds` of play (0 = under the first mark).
function Funnel.minuteMark(seconds: number): number
	local best = 0
	for _, mark in Funnel.minuteMarks do
		if seconds >= mark * 60 then
			best = mark
		end
	end
	return best
end

return Funnel
