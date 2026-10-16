--!strict
-- WaitingForParty state machine for the Match server (pure; time is passed in).
--
--   Idle      nobody has arrived yet (the wait clock has not started)
--   Waiting   some expected members are missing, inside the wait window
--   Ready     every expected member is here: the hunt may begin
--   TimedOut  window over with members missing: the leader may START WITH ARRIVED or RETURN
--   Started   a hunt began for the Roster; later arrivals are only reconnects of roster members
--   Cancelled the leader sent everyone back
--   Empty     everyone who ever arrived has left
-- Arrivals are still accepted while TimedOut (a slow member can still make it), never after
-- Started unless they were on the roster.

local ArrivalGate = {}
ArrivalGate.__index = ArrivalGate

export type Gate = {
	Members: { number },
	TicketLeader: number,
	Wait: number,
	Arrived: { [number]: boolean },
	Roster: { number }?,
	T0: number?,
	Cancelled: boolean,
	arrivedList: (Gate) -> { number },
	missing: (Gate) -> { number },
	leader: (Gate) -> number?,
	status: (Gate, number) -> string,
	remaining: (Gate, number) -> number,
	arrive: (Gate, number, number) -> (boolean, string?),
	leave: (Gate, number) -> (),
	start: (Gate, number?, number) -> ({ number }?, string?),
	cancel: (Gate, number, number) -> (boolean, string?),
}

function ArrivalGate.new(members: { number }, ticketLeader: number, waitSeconds: number): Gate
	local g = {
		Members = table.clone(members),
		TicketLeader = ticketLeader,
		Wait = waitSeconds,
		Arrived = {},
		Roster = nil,
		T0 = nil,
		Cancelled = false,
	}
	return setmetatable(g, ArrivalGate) :: any
end

function ArrivalGate.arrivedList(self: Gate): { number }
	local out = {}
	for _, uid in self.Members do
		if self.Arrived[uid] then
			table.insert(out, uid)
		end
	end
	return out
end

function ArrivalGate.missing(self: Gate): { number }
	local out = {}
	for _, uid in self.Members do
		if not self.Arrived[uid] then
			table.insert(out, uid)
		end
	end
	return out
end

-- Effective leader: the ticket leader while present, else the earliest present member.
function ArrivalGate.leader(self: Gate): number?
	if self.Arrived[self.TicketLeader] then
		return self.TicketLeader
	end
	for _, uid in self.Members do
		if self.Arrived[uid] then
			return uid
		end
	end
	return nil
end

function ArrivalGate.status(self: Gate, now: number): string
	if self.Cancelled then
		return "Cancelled"
	end
	local t0 = self.T0
	if t0 == nil then
		return "Idle"
	end
	if next(self.Arrived) == nil then
		return "Empty"
	end
	if self.Roster then
		return "Started"
	end
	if #self:missing() == 0 then
		return "Ready"
	end
	if now - t0 >= self.Wait then
		return "TimedOut"
	end
	return "Waiting"
end

-- Seconds left in the wait window (the full window before anyone has arrived).
function ArrivalGate.remaining(self: Gate, now: number): number
	local t0 = self.T0
	if t0 == nil then
		return self.Wait
	end
	return math.max(0, self.Wait - (now - t0))
end

function ArrivalGate.arrive(self: Gate, userId: number, now: number): (boolean, string?)
	if self.Cancelled then
		return false, "Cancelled"
	end
	if not table.find(self.Members, userId) then
		return false, "NotExpected"
	end
	local roster = self.Roster
	if roster and not table.find(roster, userId) then
		return false, "Started" -- late: the hunt began without you
	end
	if self.T0 == nil then
		self.T0 = now
	end
	self.Arrived[userId] = true
	return true, nil
end

function ArrivalGate.leave(self: Gate, userId: number)
	self.Arrived[userId] = nil
end

-- Begins the hunt. Ready: the server calls it. TimedOut: only the leader may, and only with at
-- least one arrival. Returns the roster (arrived members, party order) or nil + reason.
function ArrivalGate.start(self: Gate, userId: number?, now: number): ({ number }?, string?)
	local st = self:status(now)
	if st == "Ready" then
		self.Roster = self:arrivedList()
		return self.Roster, nil
	elseif st == "TimedOut" then
		if userId == nil or userId ~= self:leader() then
			return nil, "NotLeader"
		end
		self.Roster = self:arrivedList()
		return self.Roster, nil
	elseif st == "Waiting" or st == "Idle" then
		return nil, "StillWaiting"
	end
	return nil, st
end

-- Leader sends everyone back before the hunt began.
function ArrivalGate.cancel(self: Gate, userId: number, now: number): (boolean, string?)
	local st = self:status(now)
	if st == "Started" or st == "Cancelled" or st == "Empty" or st == "Idle" then
		return false, st
	end
	if userId ~= self:leader() then
		return false, "NotLeader"
	end
	self.Cancelled = true
	return true, nil
end

return ArrivalGate
