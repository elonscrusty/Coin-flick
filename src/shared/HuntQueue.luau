--!strict
-- Public hunt queue rules (pure: no Roblox services; tested in tests/test_hunt_queue.luau).
-- A lobby has a list of queues. Each queue holds groups (a party, or one player) up to Size players. The first
-- group to enter a queue starts its timer; the queue is due Seconds later (or at once when full and StartWhenFull).
-- A group always joins the earliest queue it fits in; a group that fits nowhere opens a new queue. A group never
-- splits across queues, so a party always hunts together.
-- A player who leaves a counting queue and comes back before it would have started keeps that start time (Held):
-- leaving and rejoining never restarts "HUNT IN 20S" from the top.

local HuntQueue = {}

export type Group = { Key: string, Members: { number } }
export type Queue = { Id: number, Groups: { Group }, StartsAt: number }
export type State = {
	Size: number,
	Seconds: number,
	StartWhenFull: boolean,
	Queues: { Queue },
	NextId: number,
	Held: { [number]: number }, -- userId -> StartsAt of the queue they last left (kept for a rejoin)
}

-- A rejoin into a fresh queue never starts sooner than this (the HUNT IN number must still be readable).
HuntQueue.RejoinMinSeconds = 3

function HuntQueue.new(opts: { Size: number, Seconds: number, StartWhenFull: boolean? }): State
	return {
		Size = opts.Size,
		Seconds = opts.Seconds,
		StartWhenFull = opts.StartWhenFull ~= false,
		Queues = {},
		NextId = 1,
		Held = {},
	}
end

function HuntQueue.count(queue: Queue): number
	local n = 0
	for _, g in queue.Groups do
		n += #g.Members
	end
	return n
end

function HuntQueue.members(queue: Queue): { number }
	local out = {}
	for _, g in queue.Groups do
		for _, uid in g.Members do
			table.insert(out, uid)
		end
	end
	return out
end

-- The queue and group a player is in, if any.
function HuntQueue.find(s: State, uid: number): (Queue?, Group?)
	for _, q in s.Queues do
		for _, g in q.Groups do
			if table.find(g.Members, uid) then
				return q, g
			end
		end
	end
	return nil, nil
end

function HuntQueue.findGroup(s: State, key: string): (Queue?, Group?)
	for _, q in s.Queues do
		for _, g in q.Groups do
			if g.Key == key then
				return q, g
			end
		end
	end
	return nil, nil
end

-- Adds a group. Returns the queue it joined, or nil and a reason:
--   "Empty" no members, "TooBig" more than Size, "AlreadyQueued" a member or the key is queued already.
function HuntQueue.join(s: State, key: string, members: { number }, now: number): (Queue?, string?)
	if #members == 0 then
		return nil, "Empty"
	end
	if #members > s.Size then
		return nil, "TooBig"
	end
	if (HuntQueue.findGroup(s, key)) then
		return nil, "AlreadyQueued"
	end
	for _, uid in members do
		if (HuntQueue.find(s, uid)) then
			return nil, "AlreadyQueued"
		end
	end
	local group: Group = { Key = key, Members = table.clone(members) }
	for _, q in s.Queues do
		if HuntQueue.count(q) + #members <= s.Size then
			for _, uid in members do
				s.Held[uid] = nil
			end
			table.insert(q.Groups, group)
			return q, nil
		end
	end
	-- a new queue: a member who left a still-counting queue keeps that queue's start time
	local startsAt = now + s.Seconds
	for _, uid in members do
		local held = s.Held[uid]
		if held and held > now then
			startsAt = math.min(startsAt, math.max(held, now + HuntQueue.RejoinMinSeconds))
		end
	end
	for _, uid in members do
		s.Held[uid] = nil
	end
	local q: Queue = { Id = s.NextId, Groups = { group }, StartsAt = startsAt }
	s.NextId += 1
	table.insert(s.Queues, q)
	return q, nil
end

local function prune(s: State)
	for i = #s.Queues, 1, -1 do
		local q = s.Queues[i]
		for j = #q.Groups, 1, -1 do
			if #q.Groups[j].Members == 0 then
				table.remove(q.Groups, j)
			end
		end
		if #q.Groups == 0 then
			table.remove(s.Queues, i)
		end
	end
end

-- One player leaves (their group stays queued without them). Returns the queue they left.
-- A queue left empty is dropped: its timer is gone, the next joiner starts a fresh one.
function HuntQueue.leave(s: State, uid: number): Queue?
	local q, g = HuntQueue.find(s, uid)
	if not q or not g then
		return nil
	end
	local i = table.find(g.Members, uid)
	if i then
		table.remove(g.Members, i)
	end
	s.Held[uid] = q.StartsAt
	prune(s)
	return q
end

-- A whole group leaves (the party leader cancelled, the party changed). Returns the members that were queued.
function HuntQueue.leaveGroup(s: State, key: string): { number }
	local q, g = HuntQueue.findGroup(s, key)
	if not q or not g then
		return {}
	end
	local out = table.clone(g.Members)
	for _, uid in out do
		s.Held[uid] = q.StartsAt
	end
	table.clear(g.Members)
	prune(s)
	return out
end

-- Drops a player's kept start time (they left the server, or their hunt started).
function HuntQueue.forget(s: State, uid: number)
	s.Held[uid] = nil
end

function HuntQueue.isDue(s: State, q: Queue, now: number): boolean
	return now >= q.StartsAt or (s.StartWhenFull and HuntQueue.count(q) >= s.Size)
end

-- Removes and returns every queue whose hunt should start now (oldest first).
function HuntQueue.popDue(s: State, now: number): { Queue }
	local out = {}
	for i = 1, #s.Queues do
		local q = s.Queues[i]
		if HuntQueue.isDue(s, q, now) then
			table.insert(out, q)
		end
	end
	for _, q in out do
		local i = table.find(s.Queues, q)
		if i then
			table.remove(s.Queues, i)
		end
	end
	-- a queue that started frees every kept start time that pointed at it or earlier (they have all run out)
	for uid, at in s.Held do
		if at <= now then
			s.Held[uid] = nil
		end
	end
	return out
end

-- Puts a queue whose start failed back at the front, due again at `startsAt`. Members who joined another queue in
-- the meantime are not duplicated.
function HuntQueue.restore(s: State, q: Queue, startsAt: number)
	for _, g in q.Groups do
		for i = #g.Members, 1, -1 do
			if (HuntQueue.find(s, g.Members[i])) then
				table.remove(g.Members, i)
			end
		end
	end
	q.StartsAt = startsAt
	table.insert(s.Queues, 1, q)
	prune(s)
end

-- What a player sees: their queue's count and start time, or the next open queue's (to show "2/4 waiting").
function HuntQueue.view(s: State, q: Queue?, now: number): { Count: number, Max: number, StartsAt: number, Remaining: number }?
	if not q then
		return nil
	end
	return {
		Count = HuntQueue.count(q),
		Max = s.Size,
		StartsAt = q.StartsAt,
		Remaining = math.max(0, math.ceil(q.StartsAt - now)),
	}
end

-- The queue a new single joiner would land in (nil when every queue is full or there is none).
function HuntQueue.openQueue(s: State): Queue?
	for _, q in s.Queues do
		if HuntQueue.count(q) < s.Size then
			return q
		end
	end
	return nil
end

-- The highest zone every member has unlocked (order: lowest first). Falls back to the first zone.
function HuntQueue.commonTier(order: { string }, unlocked: { { [string]: boolean } }): string
	local best = order[1]
	for _, tier in order do
		local all = true
		for _, set in unlocked do
			if not set[tier] then
				all = false
				break
			end
		end
		if all then
			best = tier
		end
	end
	return best
end

-- Whether a non-finder may roll for a bonus common pet.
function HuntQueue.bonusEligible(cracked: number, isFinder: boolean, practice: boolean, minCracked: number): boolean
	return not isFinder and not practice and cracked >= minCracked
end

return HuntQueue
