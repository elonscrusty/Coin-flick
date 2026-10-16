--!strict
-- Match side of Teleport mode: one private reserved server runs one party's hunts.
--
-- Arrival: every player is checked against the ticket stored for THIS server's PrivateServerId
-- (never against teleport data). Unknown, expired, consumed or duplicate entries are sent back to
-- the lobby and their profile is never touched. Valid arrivals wait on the arena's spawn pads
-- (WaitingForParty): no tool activity, up to Config.Match.WaitForMembersSeconds for the rest.
-- When everyone is here the hunt starts through the normal MatchService round flow. If members
-- are missing after the wait, the leader picks START WITH ARRIVED or RETURN. A member who arrives
-- after the hunt began without them is turned away (no unfair late join); a roster member who
-- reconnects is let back in and watches the current round (no new target, no extra reward).
-- Leader leaving hands the lead to the earliest remaining member. An empty server marks the
-- ticket consumed and Roblox shuts the reservation down.

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local MatchTicket = require(Shared.MatchTicket)
local TeleportBook = require(Shared.TeleportBook)
local ArrivalGate = require(Shared.ArrivalGate)
local Profiles = require(script.Parent.Profiles)
local MatchService = require(script.Parent.MatchService)
local World = require(script.Parent.WorldBuilder)
local Tickets = require(script.Parent.Tickets)

local MatchPlace = {}

local ticket: MatchTicket.Ticket? = nil
local ticketReady = false
local state = MatchTicket.newState()
local gate: ArrivalGate.Gate? = nil
local arena: { [string]: any } = {}
local party: any = nil -- the party table handed to MatchService once the hunt starts
local starting = false
local consumed = false
-- uid -> token of the return in flight (cleared when it fails); a second Return while one is in flight is ignored
local returning: { [number]: number } = {}
local returnSeq = 0
local returnQueue: { Player } = {}
local returnFlushQueued = false
local reconnecting: { [number]: boolean } = {}

local REJECT_TEXT: { [string]: string } = {
	NoTicket = "This match is not available. Going back to the lobby.",
	Unknown = "This match is not available. Going back to the lobby.",
	NotMember = "You are not part of this party. Going back to the lobby.",
	Consumed = "That match is over. Going back to the lobby.",
	Duplicate = "You are already in this match.",
	Expired = "That match invitation ran out. Going back to the lobby.",
	ReconnectLimit = "You have rejoined too many times. Going back to the lobby.",
	Started = "The hunt began without you. Going back to the lobby.",
	NotExpected = "You are not part of this party. Going back to the lobby.",
	Cancelled = "The leader sent the party back. Going back to the lobby.",
}

local function playerOf(uid: number): Player?
	return Players:GetPlayerByUserId(uid)
end

local function nowClock(): number
	return os.clock()
end

local function toast(p: Player, text: string, kind: string?)
	Net.event("Toast"):FireClient(p, text, kind or "info")
end

-- Returning to the lobby ------------------------------------------------------------------------

local function reacquireAll(players: { Player })
	for _, p in players do
		returning[p.UserId] = nil
		if Profiles.isReleased(p) then
			task.spawn(function()
				if not Profiles.reacquire(p) and p.Parent then
					p:Kick("Your save moved to another server. Please rejoin.")
				end
			end)
		end
	end
end

local function sendBack(players: { Player }, attempt: number?)
	local list: { Player } = {}
	returnSeq += 1
	local token = returnSeq
	-- a player already on their way back is skipped: a second teleport would race the first, and its
	-- failure path would take the save lock back while the first teleport is still landing
	local byId: { [number]: Player } = {}
	local ids: { number } = {}
	for _, p in players do
		if p.Parent then
			table.insert(ids, p.UserId)
			byId[p.UserId] = p
		end
	end
	for _, uid in TeleportBook.takeReturns(returning, ids, token, attempt ~= nil) do
		table.insert(list, byId[uid])
	end
	if #list == 0 then
		return
	end
	-- Hand the saves over first. If a release fails the player still leaves with the normal
	-- release-on-leave save, so the teleport goes ahead (the lobby waits on the lock, bounded).
	for _, p in list do
		if Profiles.isLoaded(p) then
			local ok = Profiles.releaseForTeleport(p)
			if not ok then
				warn("[MatchPlace] release before return failed for", p.UserId)
			end
		end
		Net.event("LaunchEvent"):FireClient(p, "Returning", { Message = "Heading back to the lobby..." })
	end
	local try = attempt or 1
	local options = Instance.new("TeleportOptions")
	local t = ticket
	if try == 1 and t and t.LobbyJobId ~= "" then
		options.ServerInstanceId = t.LobbyJobId -- same lobby server, so the party lands together
	end
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(Config.Places.LobbyPlaceId, list, options)
	end)
	if ok then
		task.delay(Config.Teleport.ReturnWatchdog, function()
			local stuck: { Player } = {}
			for _, p in list do
				if p.Parent and TeleportBook.stillOwns(returning, p.UserId, token) then
					table.insert(stuck, p)
				end
			end
			if #stuck > 0 then
				reacquireAll(stuck)
				for _, p in stuck do
					toast(p, "Could not go back yet. Tap LOBBY to try again.", "warn")
					Net.event("LaunchEvent"):FireClient(p, "ReturnFailed", {})
				end
			end
		end)
		return
	end
	warn("[MatchPlace] return teleport failed:", err)
	if try == 1 then
		sendBack(list, 2) -- one retry without pinning a lobby server (it may be gone)
		return
	end
	reacquireAll(list)
	for _, p in list do
		toast(p, "Could not go back yet. Tap LOBBY to try again.", "warn")
		Net.event("LaunchEvent"):FireClient(p, "ReturnFailed", {})
	end
end

local function queueReturn(p: Player)
	table.insert(returnQueue, p)
	if returnFlushQueued then
		return
	end
	returnFlushQueued = true
	task.defer(function()
		returnFlushQueued = false
		local batch = returnQueue
		returnQueue = {}
		sendBack(batch)
	end)
end

-- Waiting UI ---------------------------------------------------------------------------------------

local function broadcast(force: string?)
	local g, t = gate, ticket
	if not g or not t then
		return
	end
	local now = nowClock()
	local st = g:status(now)
	if not force and (st == "Started" or st == "Cancelled" or st == "Empty" or st == "Idle") then
		return
	end
	local leader = g:leader() or t.Leader
	local members = {}
	for i, uid in t.Members do
		local p = playerOf(uid)
		table.insert(members, {
			UserId = uid,
			Name = if p then p.DisplayName else (t.Names[i] or "?"),
			Arrived = g.Arrived[uid] == true,
			Leader = uid == leader,
		})
	end
	local status = force or st
	if st == "Ready" then
		status = "Loading"
	end
	for uid in g.Arrived do
		local p = playerOf(uid)
		if p then
			Net.event("LaunchEvent"):FireClient(p, "Waiting", {
				Members = members,
				Leader = leader,
				Status = status, -- Waiting | TimedOut | Loading
				Remaining = math.ceil(g:remaining(now)),
				CanStart = st == "TimedOut" and uid == leader,
				CanReturnAll = uid == leader,
				Tier = t.Tier,
			})
		end
	end
end

-- Admission (called by Profiles before it touches a save) ----------------------------------------

local function reject(player: Player, reason: string)
	warn("[MatchPlace] rejected", player.UserId, reason)
	Net.event("LaunchEvent"):FireClient(player, "Rejected", { Message = REJECT_TEXT[reason] or "Going back to the lobby." })
	task.delay(2.5, function()
		if player.Parent then
			sendBack({ player })
		end
	end)
	task.delay(15, function()
		if player.Parent then
			player:Kick("This match is not available for you.")
		end
	end)
end

local function placeOnPad(player: Player)
	local t = ticket
	local spawns = arena.Spawns
	if not t or not spawns then
		return
	end
	local idx = table.find(t.Members, player.UserId) or 1
	local char = player.Character
	if char then
		char:PivotTo(spawns[((idx - 1) % #spawns) + 1])
	end
end

local function admit(player: Player): boolean
	local t0 = os.clock()
	while not ticketReady and os.clock() - t0 < 60 do
		task.wait(0.2)
	end
	local g = gate
	local verdict = MatchTicket.validate(ticket, state, player.UserId, os.time(), Config.Teleport.MaxReconnects)
	if not verdict.Ok or not g then
		reject(player, verdict.Reason or "NoTicket")
		return false
	end
	local ok, why = g:arrive(player.UserId, nowClock())
	if not ok then
		reject(player, why or "NotExpected")
		return false
	end
	MatchTicket.recordArrive(state, player.UserId)
	if verdict.Reconnect then
		reconnecting[player.UserId] = true
	end
	player.CharacterAdded:Connect(function()
		task.wait()
		if MatchService.isBusy(player.UserId) then
			return -- MatchService places players in a running hunt
		end
		placeOnPad(player)
	end)
	if player.Character then
		task.defer(placeOnPad, player)
	end
	Net.event("LaunchEvent"):FireClient(player, "Mode", { Teleport = true })
	broadcast()
	-- Reconnect to a running hunt: come back as a watcher once the save has loaded.
	if g:status(nowClock()) == "Started" then
		task.spawn(function()
			local w = os.clock()
			while player.Parent and not Profiles.isLoaded(player) and os.clock() - w < 40 do
				task.wait(0.25)
			end
			if not player.Parent then
				return
			end
			if Profiles.isLoaded(player) and MatchService.rejoin(player.UserId) then
				Net.event("LaunchEvent"):FireClient(player, "Hide", {})
				toast(player, "Welcome back. You join again from the next round.", "info")
			else
				toast(player, "That hunt is over. Going back to the lobby.", "warn")
				sendBack({ player })
			end
		end)
	end
	return true
end

-- Starting the hunt -----------------------------------------------------------------------------------

local function beginHunt(by: number?)
	local g, t = gate, ticket
	if not g or not t or starting then
		return
	end
	local roster, why = g:start(by, nowClock())
	if not roster then
		if by then
			local p = playerOf(by)
			if p then
				toast(p, if why == "NotLeader" then "Only the party leader can do that." else "Not ready yet.", "warn")
			end
		end
		return
	end
	starting = true
	broadcast("Loading")
	task.spawn(function()
		-- members need their saves (tool, storage) before the countdown; those that fail are kicked
		-- by Profiles and simply drop out
		local w = os.clock()
		while os.clock() - w < 30 do
			local waiting = false
			for _, uid in roster do
				local p = playerOf(uid)
				if p and not Profiles.isLoaded(p) then
					waiting = true
				end
			end
			if not waiting then
				break
			end
			task.wait(0.25)
		end
		local members: { number } = {}
		for _, uid in roster do
			local p = playerOf(uid)
			if p and Profiles.isLoaded(p) then
				table.insert(members, uid)
			end
		end
		if #members == 0 then
			starting = false
			return
		end
		party = {
			Id = t.Id,
			Leader = g:leader() or members[1],
			Members = members,
			Ready = {},
			Tier = t.Tier,
			Locked = false,
			MatchKey = nil,
		}
		for _, uid in members do
			local p = playerOf(uid)
			if p then
				Net.event("LaunchEvent"):FireClient(p, "Hide", {})
			end
		end
		local started, err = false, nil
		for _ = 1, 12 do
			started, err = MatchService.startParty(party)
			if started then
				break
			end
			task.wait(1)
		end
		if not started then
			warn("[MatchPlace] could not start:", err)
			local ps: { Player } = {}
			for _, uid in members do
				local p = playerOf(uid)
				if p then
					toast(p, "Could not start the hunt. Going back to the lobby.", "warn")
					table.insert(ps, p)
				end
			end
			sendBack(ps)
		end
		starting = false
	end)
end

-- Actions from the waiting screen -------------------------------------------------------------------

local function onAction(player: Player, action: any)
	local g = gate
	if not g or not state.Present[player.UserId] then
		return
	end
	local uid = player.UserId
	if action == "Return" then
		if MatchService.isBusy(uid) then
			return -- inside a hunt: the normal LOBBY button (MatchAction) handles it
		end
		sendBack({ player })
	elseif action == "StartWithArrived" then
		if g:status(nowClock()) == "TimedOut" then
			beginHunt(uid)
		end
	elseif action == "ReturnAll" then
		local st = g:status(nowClock())
		if st == "Started" then
			if uid ~= g:leader() then
				return
			end
			local ph = MatchService.phaseOf(uid)
			if ph ~= nil and ph ~= "Results" then
				toast(player, "Finish or leave the round first.", "warn")
				return
			end
			local list: { Player } = {}
			for u in table.clone(state.Present) do
				local p = playerOf(u)
				if p then
					MatchService.removePlayer(u)
					table.insert(list, p)
				end
			end
			sendBack(list)
		else
			local ok = g:cancel(uid, nowClock())
			if ok then
				local list: { Player } = {}
				for u in state.Present do
					local p = playerOf(u)
					if p then
						table.insert(list, p)
					end
				end
				sendBack(list)
			end
		end
	end
end

-- Leaving ---------------------------------------------------------------------------------------------

local function closeTicket()
	if consumed then
		return
	end
	consumed = true
	local t = ticket
	MatchTicket.close(t, state)
	if t then
		Tickets.consume(t.Id)
	end
end

local function onRemoving(player: Player)
	local uid = player.UserId
	returning[uid] = nil
	reconnecting[uid] = nil
	local g = gate
	if not g or not state.Present[uid] then
		return
	end
	MatchTicket.recordLeave(state, uid)
	g:leave(uid)
	if party then
		local lead = g:leader()
		if lead then
			party.Leader = lead -- earliest remaining member
		end
	end
	if next(state.Present) == nil then
		task.spawn(closeTicket) -- empty server: nobody can start a new hunt on this reservation
	else
		broadcast()
	end
end

function MatchPlace.start()
	World.useOriginArena()
	Profiles.setLoadAttempts(Config.Teleport.LoadAttempts)
	Profiles.setJoinGate(admit)
	MatchService.setReturnHandler(queueReturn)
	arena = MatchService.prepareArena(1)
	local spawns = arena.Spawns
	if spawns and spawns[1] then
		local pad = Instance.new("SpawnLocation")
		pad.Name = "CT_Rocks_ReadyPad"
		pad.Anchored = true
		pad.CanCollide = false
		pad.Transparency = 1
		pad.Neutral = true
		pad.Size = Vector3.new(6, 1, 6)
		pad.CFrame = (spawns[1] :: CFrame) * CFrame.new(0, -2.5, 0)
		pad.Parent = workspace
	end

	task.spawn(function()
		local id = game.PrivateServerId
		local t = Tickets.get(id)
		ticket = t
		if t then
			gate = ArrivalGate.new(t.Members, t.Leader, Config.Match.WaitForMembersSeconds)
		else
			warn("[MatchPlace] no ticket for this server (PrivateServerId '" .. id .. "'): refusing everyone")
		end
		ticketReady = true
	end)

	local limit: { [Player]: number } = {}
	Net.event("LaunchAction").OnServerEvent:Connect(function(player, action)
		local t = os.clock()
		if t - (limit[player] or 0) < 0.4 then
			return
		end
		limit[player] = t
		onAction(player, action)
	end)
	Players.PlayerRemoving:Connect(function(player)
		limit[player] = nil
		onRemoving(player)
	end)
	TeleportService.TeleportInitFailed:Connect(function(player, result, message)
		if returning[player.UserId] then
			warn("[MatchPlace] return TeleportInitFailed", player.UserId, tostring(result), tostring(message))
			reacquireAll({ player })
			toast(player, "Could not go back yet. Tap LOBBY to try again.", "warn")
			Net.event("LaunchEvent"):FireClient(player, "ReturnFailed", {})
		end
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			local g = gate
			if g then
				local st = g:status(nowClock())
				if st == "Ready" then
					beginHunt(nil)
				elseif st == "Waiting" or st == "TimedOut" then
					broadcast()
				end
			end
		end
	end)

	game:BindToClose(function()
		if ticket and not consumed then
			closeTicket()
		end
	end)
end

return MatchPlace
