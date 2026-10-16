--!strict
-- Pure match-ticket rules. The lobby server creates a ticket (stored by the reserved server's
-- PrivateServerId, never trusted from teleport data); the Match server validates every arrival
-- against it. No Roblox services in here, so tests drive it directly.
--
-- Ticket (immutable once stored, plain data): who may enter, which tier, who leads, when the
-- first arrival must happen and when the whole ticket dies. Consumed = the match is over.
-- State (Match server memory only): who is present, how often each user came back.

local MatchTicket = {}

export type Ticket = {
	Id: string, -- ticket id (equals the reserved server's PrivateServerId)
	Leader: number,
	Members: { number }, -- UserIds, party order
	Names: { string }, -- display names parallel to Members (shown while waiting)
	Tier: string,
	Created: number, -- os.time()
	ArriveBy: number, -- first arrivals must happen before this
	Expires: number, -- reconnects must happen before this
	Consumed: boolean,
	LobbyJobId: string, -- lobby server to return to ("" = any)
}

export type State = {
	Present: { [number]: boolean },
	Arrivals: { [number]: number }, -- times each user has entered (1 = first arrival)
	Closed: boolean,
}

export type Verdict = { Ok: boolean, Reason: string?, Reconnect: boolean }

function MatchTicket.create(opts: {
	Id: string,
	Leader: number,
	Members: { number },
	Names: { string }?,
	Tier: string,
	Now: number,
	ArriveSeconds: number,
	LifetimeSeconds: number,
	MaxMembers: number,
	LobbyJobId: string?,
}): (Ticket?, string?)
	if opts.Id == "" then
		return nil, "NoId"
	end
	local n = #opts.Members
	if n < 1 or n > opts.MaxMembers then
		return nil, "BadSize"
	end
	local seen: { [number]: boolean } = {}
	for _, uid in opts.Members do
		if type(uid) ~= "number" or uid ~= uid or seen[uid] then
			return nil, "BadMember"
		end
		seen[uid] = true
	end
	if not seen[opts.Leader] then
		return nil, "LeaderNotMember"
	end
	local ticket: Ticket = {
		Id = opts.Id,
		Leader = opts.Leader,
		Members = table.clone(opts.Members),
		Names = table.clone(opts.Names or {}),
		Tier = opts.Tier,
		Created = opts.Now,
		ArriveBy = opts.Now + opts.ArriveSeconds,
		Expires = opts.Now + opts.LifetimeSeconds,
		Consumed = false,
		LobbyJobId = opts.LobbyJobId or "",
	}
	return ticket, nil
end

function MatchTicket.newState(): State
	return { Present = {}, Arrivals = {}, Closed = false }
end

function MatchTicket.isMember(ticket: Ticket, userId: number): boolean
	return table.find(ticket.Members, userId) ~= nil
end

-- Decides whether userId may enter now. Does not change anything (call recordArrive after).
-- Reasons: NoTicket, Unknown, NotMember, Consumed, Duplicate, Expired, ReconnectLimit.
function MatchTicket.validate(ticket: Ticket?, state: State, userId: any, now: number, maxReconnects: number): Verdict
	local function no(reason: string): Verdict
		return { Ok = false, Reason = reason, Reconnect = false }
	end
	if ticket == nil then
		return no("NoTicket")
	end
	local t = ticket :: Ticket
	if type(userId) ~= "number" then
		return no("Unknown")
	end
	if t.Consumed or state.Closed then
		return no("Consumed")
	end
	if not MatchTicket.isMember(t, userId) then
		return no("NotMember")
	end
	if state.Present[userId] then
		return no("Duplicate")
	end
	if now > t.Expires then
		return no("Expired")
	end
	local before = state.Arrivals[userId] or 0
	if before == 0 then
		if now > t.ArriveBy then
			return no("Expired")
		end
		return { Ok = true, Reason = nil, Reconnect = false }
	end
	if before - 1 >= maxReconnects then
		return no("ReconnectLimit")
	end
	return { Ok = true, Reason = nil, Reconnect = true }
end

function MatchTicket.recordArrive(state: State, userId: number)
	state.Present[userId] = true
	state.Arrivals[userId] = (state.Arrivals[userId] or 0) + 1
end

function MatchTicket.recordLeave(state: State, userId: number)
	state.Present[userId] = nil
end

-- Marks the whole ticket used up (match over or abandoned): nobody may enter again.
function MatchTicket.close(ticket: Ticket?, state: State)
	state.Closed = true
	if ticket then
		(ticket :: Ticket).Consumed = true
	end
end

return MatchTicket
