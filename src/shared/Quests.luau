--!strict
-- Daily gift and daily quests as pure rules (no Roblox services; tests/test_progress.luau drives them).
-- The server (src/server/QuestService.luau) owns the state in the profile (`Daily`) and decides every reward;
-- clients only see Quests.view and send "claim" intents.
--
-- Days are whole UTC days since the Unix epoch (Quests.day(os.time())). Each player gets one race (egg hunt), one
-- tower and one pet quest per day, picked deterministically from (user id, day), so a rejoin or another server shows the same quests.
-- Progress resets when the day changes; nothing carries over.

local ProgressConfig = require(script.Parent.ProgressConfig)
local Retention = require(script.Parent.Retention)

local Quests = {}

export type Daily = {
	Day: number, -- the day Progress / Claimed belong to
	Progress: { number },
	Claimed: { boolean },
	GiftDay: number, -- last day the gift was claimed (0 = never)
	Streak: number, -- consecutive gift days up to GiftDay
	Shields: number, -- streak shields (Retention.Streak): each one saves the streak after one missed day
}

export type Quest = { Index: number, Kind: string, Group: string, Goal: number, Reward: number, Text: string }

function Quests.day(unixTime: number): number
	return math.floor(unixTime / 86400)
end

function Quests.empty(): Daily
	return { Day = 0, Progress = {}, Claimed = {}, GiftDay = 0, Streak = 0, Shields = 0 }
end

-- Small deterministic generator (Park-Miller), independent of Roblox's Random so the same quests come out everywhere.
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

-- Every possible day: one (kind, goal) option per quest group (ProgressConfig.QuestGroups: Race, Tower, Pet),
-- in group order. Built once.
type Option = { Kind: number, Goal: number }
local combos: { { Option } } = {}
do
	local perGroup: { { Option } } = {}
	for gi, group in ProgressConfig.QuestGroups do
		perGroup[gi] = {}
		for ki, k in ProgressConfig.QuestKinds do
			if k.Group == group then
				for g = 1, #k.Goals do
					table.insert(perGroup[gi], { Kind = ki, Goal = g })
				end
			end
		end
		assert(#perGroup[gi] > 0, "quest group without quests: " .. group)
	end
	local pick: { Option } = {}
	local function walk(gi: number)
		if gi > #perGroup then
			table.insert(combos, table.clone(pick))
			return
		end
		for _, o in perGroup[gi] do
			pick[gi] = o
			walk(gi + 1)
		end
		pick[gi] = nil
	end
	walk(1)
end

local function shift(userId: number, day: number): number
	local uid = math.abs(math.floor(userId)) % 2147483647
	return if rng((uid * 7919 + day * 104729 + 17) % 2147483647)() < 0.5 then 0 else 1
end

-- The quests of `userId` on `day`: one race, one tower and one pet quest, in that order. The day walks through every
-- combination: day d uses combination (base + 3d + s(d)) with s(d) in {0, 1}, so two days in a row are 2 to 4 steps
-- apart and never the same day (there are dozens of combinations).
function Quests.forDay(userId: number, day: number): { Quest }
	local uid = math.abs(math.floor(userId)) % 2147483647
	local count = #combos
	local base = uid % count
	local combo = combos[((base + 3 * day + shift(uid, day)) % count) + 1]
	local out: { Quest } = {}
	for i, o in combo do
		local k = ProgressConfig.QuestKinds[o.Kind]
		local goal = k.Goals[o.Goal]
		table.insert(out, {
			Index = i,
			Kind = k.Kind,
			Group = k.Group,
			Goal = goal,
			Reward = k.Reward[o.Goal],
			Text = if goal == 1 and k.One then k.One else string.format(k.Text, goal),
		})
	end
	return out
end

local function num(v: any, default: number): number
	return if type(v) == "number" and v == v and v > -math.huge and v < math.huge then v else default
end

-- Repairs a stored Daily (old save, hand edit) in place and returns it. Never invents progress.
function Quests.sanitize(d: any): Daily
	if type(d) ~= "table" then
		return Quests.empty()
	end
	d.Day = math.floor(num(d.Day, 0))
	d.GiftDay = math.floor(num(d.GiftDay, 0))
	d.Streak = math.max(0, math.floor(num(d.Streak, 0)))
	d.Shields = math.clamp(math.floor(num(d.Shields, 0)), 0, Retention.Streak.MaxShields)
	if type(d.Progress) ~= "table" then
		d.Progress = {}
	end
	if type(d.Claimed) ~= "table" then
		d.Claimed = {}
	end
	for i = 1, ProgressConfig.QuestsPerDay do
		d.Progress[i] = math.max(0, math.floor(num(d.Progress[i], 0)))
		d.Claimed[i] = d.Claimed[i] == true
	end
	return d :: Daily
end

-- Moves the quest state to `today` (fresh progress on a new day). Returns true when it changed.
function Quests.rollover(d: Daily, today: number): boolean
	if d.Day == today then
		return false
	end
	d.Day = today
	d.Progress = {}
	d.Claimed = {}
	for i = 1, ProgressConfig.QuestsPerDay do
		d.Progress[i] = 0
		d.Claimed[i] = false
	end
	return true
end

-- Counts `n` toward every unfinished quest of `kind` today. Returns true when any progress changed.
function Quests.bump(d: Daily, userId: number, today: number, kind: string, n: number?): boolean
	local add = math.floor(num(n, 1))
	if add <= 0 then
		return false
	end
	local changed = Quests.rollover(d, today)
	for i, q in Quests.forDay(userId, today) do
		if q.Kind == kind and not d.Claimed[i] and d.Progress[i] < q.Goal then
			d.Progress[i] = math.min(q.Goal, d.Progress[i] + add)
			changed = true
		end
	end
	return changed
end

-- Claims quest `index` for today. Returns (coins, nil) or (nil, reason). Each quest pays once.
function Quests.claim(d: Daily, userId: number, today: number, index: any): (number?, string?)
	Quests.rollover(d, today)
	if type(index) ~= "number" or index ~= index or index % 1 ~= 0 then
		return nil, "BadQuest"
	end
	local q = Quests.forDay(userId, today)[index]
	if not q then
		return nil, "BadQuest"
	end
	if d.Claimed[index] then
		return nil, "Claimed"
	end
	if d.Progress[index] < q.Goal then
		return nil, "NotDone"
	end
	d.Claimed[index] = true
	return q.Reward, nil
end

-- The streak the next gift claim would reach on `today`, and whether a streak shield would be used for it.
-- One missed day (last claim two days ago) keeps the streak when a shield is left (Retention.Streak).
local function nextStreak(d: Daily, today: number): (number, boolean)
	if d.GiftDay == today - 1 then
		return d.Streak + 1, false
	elseif d.GiftDay == today - 2 and d.Streak > 0 and (d.Shields or 0) > 0 then
		return d.Streak + 1, true
	end
	return 1, false
end
Quests.nextStreak = nextStreak

-- The streak day (1..7) the next gift claim would pay, as seen on `today`.
function Quests.giftStreakDay(d: Daily, today: number): number
	local cycle = #ProgressConfig.DailyGift
	if d.GiftDay == today then
		return ((math.max(d.Streak, 1) - 1) % cycle) + 1 -- already claimed: the day just paid
	end
	local streak = nextStreak(d, today)
	return ((streak - 1) % cycle) + 1
end

-- Coins the gift pays on streak day `streak` (the 7-day table times the growing streak multiplier).
function Quests.giftCoins(streak: number): number
	local cycle = #ProgressConfig.DailyGift
	local sd = ((math.max(streak, 1) - 1) % cycle) + 1
	return math.floor(ProgressConfig.DailyGift[sd] * Retention.streakMult(streak))
end

-- Claims today's gift. Returns (coins, streakDay, nil, shieldUsed) or (nil, nil, reason). Once per UTC day.
-- Every Retention.Streak.ShieldEvery streak days earn a shield (up to MaxShields).
function Quests.claimGift(d: Daily, today: number): (number?, number?, string?, boolean?)
	if d.GiftDay == today then
		return nil, nil, "Claimed"
	end
	if d.GiftDay > today then
		return nil, nil, "Clock" -- a save from a server whose clock ran ahead: wait for that day
	end
	local streak, shield = nextStreak(d, today)
	if shield then
		d.Shields -= 1
	end
	d.Streak = streak
	d.GiftDay = today
	local st = Retention.Streak
	if streak % st.ShieldEvery == 0 and (d.Shields or 0) < st.MaxShields then
		d.Shields = (d.Shields or 0) + 1
	end
	local sd = ((d.Streak - 1) % #ProgressConfig.DailyGift) + 1
	return Quests.giftCoins(streak), sd, nil, shield
end

export type View = {
	Day: number,
	NextReset: number, -- unix time the quests and gift turn over (UTC midnight)
	Quests: { { Text: string, Kind: string, Group: string, Goal: number, Progress: number, Reward: number, Claimed: boolean, Done: boolean } },
	-- Streak = the streak this claim reaches (or reached today), Shields = streak shields left, Mult = gift multiplier
	Gift: { Ready: boolean, StreakDay: number, Reward: number, Rewards: { number }, Streak: number, Shields: number, Mult: number },
	Claimable: number, -- quests done and unclaimed, plus 1 when the gift is ready (HUD dot)
}

-- What the client sees (no seeds, nothing it could use to cheat; it is all the player's own data anyway).
function Quests.view(d: Daily, userId: number, today: number): View
	local fresh = d.Day ~= today
	local list = {}
	local claimable = 0
	for i, q in Quests.forDay(userId, today) do
		local p = if fresh then 0 else math.min(q.Goal, d.Progress[i] or 0)
		local claimed = not fresh and d.Claimed[i] == true
		local done = p >= q.Goal
		if done and not claimed then
			claimable += 1
		end
		table.insert(list, { Text = q.Text, Kind = q.Kind, Group = q.Group, Goal = q.Goal, Progress = p, Reward = q.Reward, Claimed = claimed, Done = done })
	end
	local ready = d.GiftDay < today
	if ready then
		claimable += 1
	end
	local sd = Quests.giftStreakDay(d, today)
	local streak = if ready then (nextStreak(d, today)) else math.max(d.Streak, 1)
	return {
		Day = today,
		NextReset = (today + 1) * 86400,
		Quests = list,
		Gift = {
			Ready = ready,
			StreakDay = sd,
			Reward = Quests.giftCoins(streak),
			Rewards = table.clone(ProgressConfig.DailyGift),
			Streak = streak,
			Shields = d.Shields or 0,
			Mult = Retention.streakMult(streak),
		},
		Claimable = claimable,
	}
end

return Quests
