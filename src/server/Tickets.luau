--!strict
-- Match tickets in MemoryStore (shared by the Lobby and Match servers of this experience).
-- Key = the reserved server's PrivateServerId, so the Match server finds its ticket from a value
-- only Roblox gives it, never from teleport data. Entries expire by themselves.
-- All calls are pcall-wrapped with a few bounded retries; a store outage means "no ticket"
-- (the Match server then refuses everyone safely) and never a made-up ticket.

local MemoryStoreService = game:GetService("MemoryStoreService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local MatchTicket = require(Shared.MatchTicket)

local Tickets = {}

local map: any = nil
local mapOk = pcall(function()
	map = MemoryStoreService:GetHashMap("CTR_Tickets_v1")
end)

local function ttl(): number
	return Config.Teleport.TicketSeconds + 600
end

-- Lobby: store a new ticket. Returns true when it is readable by the Match server.
function Tickets.put(ticket: MatchTicket.Ticket): (boolean, string?)
	if not mapOk or not map then
		return false, "MemoryStore unavailable"
	end
	local lastErr = "unknown"
	for attempt = 1, 3 do
		local ok, err = pcall(function()
			map:SetAsync(ticket.Id, ticket, ttl())
		end)
		if ok then
			return true, nil
		end
		lastErr = tostring(err)
		task.wait(attempt)
	end
	return false, lastErr
end

-- Match: read the ticket for this reserved server. nil = none (or the store failed).
function Tickets.get(id: string): (MatchTicket.Ticket?, string?)
	if not mapOk or not map or id == "" then
		return nil, "MemoryStore unavailable"
	end
	local lastErr = "unknown"
	for attempt = 1, 5 do
		local ok, value = pcall(function()
			return map:GetAsync(id)
		end)
		if ok then
			if type(value) == "table" and type(value.Members) == "table" and type(value.Leader) == "number" then
				return value :: MatchTicket.Ticket, nil
			end
			-- not there (yet): the lobby writes the ticket just before the teleport, so retry a bit
			lastErr = "no ticket"
		else
			lastErr = tostring(value)
		end
		task.wait(attempt)
	end
	return nil, lastErr
end

-- Match: mark the ticket used up so a fresh server on the same reservation starts nothing new.
function Tickets.consume(id: string)
	if not mapOk or not map or id == "" then
		return
	end
	for attempt = 1, 3 do
		local ok = pcall(function()
			map:UpdateAsync(id, function(old: any): any
				if type(old) ~= "table" then
					return nil
				end
				old.Consumed = true
				return old
			end, ttl())
		end)
		if ok then
			return
		end
		task.wait(attempt)
	end
end

return Tickets
