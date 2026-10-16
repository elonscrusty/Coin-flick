--!strict
-- Daily gift + daily jobs as pure rules (no Roblox services; tests/specs/Daily.spec.luau drives them).
-- The server (Systems/Daily) owns the state in the profile and decides every reward; the client only
-- sees Daily.view and sends "claim" intents.
--
-- Days are whole UTC days since the Unix epoch. Every player gets 3 jobs a day, picked from
-- (user id, day) so a rejoin or another server shows the same jobs. Job progress resets with the day.
-- The 7-day gift never punishes a missed day: it just pays the next gift day on the next claim.

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)
local Plural = require(script.Parent.Plural)

type DailyState = Types.DailyState
type DailyView = Types.DailyView

local Daily = {}

export type Job = { slot: number, kind: string, goal: number, flips: number, hats: number, text: string }
export type Reward = { flips: number, hats: number }

local JOBS = Config.Daily.JOBS_PER_DAY

function Daily.day(unixTime: number): number
	return math.floor(unixTime / 86400)
end

function Daily.empty(): DailyState
	local progress, claimed = {}, {}
	for i = 1, JOBS do
		progress[i] = 0
		claimed[i] = false
	end
	return { day = 0, progress = progress, claimed = claimed, giftDay = 0, giftClaims = 0 }
end

-- Small deterministic generator (Park-Miller), so the same jobs come out on every server.
local function rng(seed: number): () -> number
	local s = seed % 2147483647
	if s <= 0 then
		s += 2147483646
	end
	for _ = 1, 4 do
		s = (s * 48271) % 2147483647
	end
	return function(): number
		s = (s * 48271) % 2147483647
		return s / 2147483647
	end
end

-- The jobs of `userId` on `day`: JOBS different kinds (one kind is left out each day), each with an
-- easy / medium / hard goal.
function Daily.jobsFor(userId: number, day: number): { Job }
	local uid = math.abs(math.floor(userId)) % 2147483647
	local roll = rng((uid * 7919 + day * 104729 + 17) % 2147483647)
	local kinds = Config.Daily.JobKinds
	local left = math.floor(roll() * #kinds) + 1
	local jobs: { Job } = {}
	for i, def in kinds do
		if i ~= left or #kinds <= JOBS then
			local tier = math.clamp(math.floor(roll() * #def.goals) + 1, 1, #def.goals)
			local goal = def.goals[tier]
			table.insert(jobs, {
				slot = #jobs + 1,
				kind = def.kind,
				goal = goal,
				flips = def.flips[tier],
				hats = def.hats[tier],
				text = Plural.fix(string.format(def.text, goal)),
			})
		end
		if #jobs >= JOBS then
			break
		end
	end
	return jobs
end

local function num(value: unknown, default: number): number
	if typeof(value) == "number" and value == value and value > -math.huge and value < math.huge then
		return value
	end
	return default
end

-- A clean DailyState from anything saved (old save, bad value). Never invents progress.
function Daily.sanitize(raw: unknown): DailyState
	local d = Daily.empty()
	if typeof(raw) ~= "table" then
		return d
	end
	local t = raw :: { [string]: any }
	d.day = math.max(0, math.floor(num(t.day, 0)))
	d.giftDay = math.max(0, math.floor(num(t.giftDay, 0)))
	d.giftClaims = math.max(0, math.floor(num(t.giftClaims, 0)))
	local progress = if typeof(t.progress) == "table" then t.progress else {}
	local claimed = if typeof(t.claimed) == "table" then t.claimed else {}
	for i = 1, JOBS do
		d.progress[i] = math.max(0, math.floor(num(progress[i], 0)))
		d.claimed[i] = claimed[i] == true
	end
	return d
end

-- Moves the state to `today` (fresh job progress on a new day). True when it changed.
function Daily.rollover(d: DailyState, today: number): boolean
	if d.day == today then
		return false
	end
	d.day = today
	for i = 1, JOBS do
		d.progress[i] = 0
		d.claimed[i] = false
	end
	return true
end

-- Counts `n` toward every unfinished job of `kind` today. True when any progress changed.
function Daily.bump(d: DailyState, userId: number, today: number, kind: string, n: number?): boolean
	local add = if n == nil then 1 else math.floor(num(n, 0))
	if add <= 0 then
		return false
	end
	local changed = Daily.rollover(d, today)
	for i, job in Daily.jobsFor(userId, today) do
		if job.kind == kind and not d.claimed[i] and d.progress[i] < job.goal then
			d.progress[i] = math.min(job.goal, d.progress[i] + add)
			changed = true
		end
	end
	return changed
end

-- Claims job `slot` for today. Returns (reward, nil) or (nil, reason). Each job pays once.
function Daily.claimJob(d: DailyState, userId: number, today: number, slot: unknown): (Reward?, string?)
	Daily.rollover(d, today)
	if typeof(slot) ~= "number" or slot ~= slot or slot % 1 ~= 0 then
		return nil, "BadJob"
	end
	local job = Daily.jobsFor(userId, today)[slot]
	if not job then
		return nil, "BadJob"
	end
	if d.claimed[slot] then
		return nil, "Claimed"
	end
	if d.progress[slot] < job.goal then
		return nil, "NotDone"
	end
	d.claimed[slot] = true
	return { flips = job.flips, hats = job.hats }, nil
end

-- Which of the 7 gift days (1..7) is next. After a claim today it is still the day just paid.
function Daily.giftIndex(d: DailyState, today: number): number
	local cycle = #Config.Daily.Gift
	if d.giftDay == today and d.giftClaims > 0 then
		return ((d.giftClaims - 1) % cycle) + 1
	end
	return (d.giftClaims % cycle) + 1
end

-- Claims today's gift. Returns (reward, dayIndex, nil) or (nil, nil, reason). Once per UTC day.
-- A missed day costs nothing: giftClaims just carries on.
function Daily.claimGift(d: DailyState, today: number): (Reward?, number?, string?)
	if d.giftDay == today then
		return nil, nil, "Claimed"
	end
	if d.giftDay > today then
		return nil, nil, "Clock" -- saved by a server whose clock ran ahead: wait for that day
	end
	local index = d.giftClaims % #Config.Daily.Gift + 1
	d.giftClaims += 1
	d.giftDay = today
	local reward = Config.Daily.Gift[index]
	return { flips = reward.flips, hats = reward.hats }, index, nil
end

-- Heads-worth reward -> cash at the player's current cash per heads.
function Daily.cash(reward: Reward, cashPerHeads: number): number
	return reward.flips * math.max(1, cashPerHeads)
end

-- What the client draws. cashPerHeads turns "flips" into cash.
function Daily.view(d: DailyState, userId: number, today: number, cashPerHeads: number): DailyView
	local fresh = d.day ~= today
	local jobs = {}
	local claimable = 0
	for i, job in Daily.jobsFor(userId, today) do
		local progress = if fresh then 0 else math.min(job.goal, d.progress[i] or 0)
		local claimed = not fresh and d.claimed[i] == true
		local done = progress >= job.goal
		if done and not claimed then
			claimable += 1
		end
		table.insert(jobs, {
			text = job.text,
			kind = job.kind,
			goal = job.goal,
			progress = progress,
			cash = Daily.cash(job, cashPerHeads),
			hats = job.hats,
			done = done,
			claimed = claimed,
		})
	end
	local ready = d.giftDay < today
	if ready then
		claimable += 1
	end
	local index = Daily.giftIndex(d, today)
	local gift = Config.Daily.Gift[index]
	local cycle = {}
	for _, g in Config.Daily.Gift do
		table.insert(cycle, { flips = g.flips, hats = g.hats })
	end
	return {
		day = today,
		nextReset = (today + 1) * 86400,
		gift = {
			ready = ready,
			dayIndex = index,
			flips = gift.flips,
			cash = Daily.cash(gift, cashPerHeads),
			hats = gift.hats,
			cycle = cycle,
		},
		jobs = jobs,
		claimable = claimable,
	}
end

return Daily
