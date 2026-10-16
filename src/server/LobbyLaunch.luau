--!strict
-- Lobby side of Teleport mode: turns "leader taps START" into a ticketed teleport of the whole
-- party to a private (reserved) Match server.
--
-- Order matters and every step can fail without losing anything:
--   1. reserve a server (ReserveServer) and store an expiring ticket keyed by its PrivateServerId
--   2. save + release every profile (bounded retries; a profile that cannot be released stops the
--      launch, nobody is sent with a locked save)
--   3. TeleportAsync with the reserved access code (teleport data is only a hint)
--   4. failures (TeleportInitFailed, a throw, or a member still here after a watchdog): take the
--      profile lock back, keep the party and the ticket, show RETRY (once per member) / CANCEL
-- Members who did leave stay seated in the party for Config.Teleport.AwayHoldSeconds so the party
-- can come back together; the party stays locked until they are back or the hold runs out.
-- Teleports cannot run in Studio: this path is verified by offline tests of the pure rules only.

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local MatchTicket = require(Shared.MatchTicket)
local TeleportBook = require(Shared.TeleportBook)
local Profiles = require(script.Parent.Profiles)
local PartyService = require(script.Parent.PartyService)
local Tickets = require(script.Parent.Tickets)

local LobbyLaunch = {}

type Launch = {
	Id: string,
	Party: PartyService.Party,
	Ticket: MatchTicket.Ticket?,
	Code: string?,
	Phase: string, -- Preparing | Teleporting | Failed | Partial | Done
	Message: string,
	Sent: { [number]: boolean }, -- teleport requested for this member
	Away: { [number]: boolean }, -- member has left this server (is in the Match place)
	Failed: { [number]: string },
	Retries: { [number]: number },
	Reacquiring: { [number]: boolean },
	AwayDeadline: number,
	Gen: number, -- bumps on every send so old watchdogs do nothing
}

local launches: { [string]: Launch } = {} -- by party id
local launchOf: { [number]: string } = {} -- user id -> party id

local function playerOf(uid: number): Player?
	return Players:GetPlayerByUserId(uid)
end

local function nameOf(uid: number): string
	local p = playerOf(uid)
	return if p then p.DisplayName else "?"
end

-- UI -----------------------------------------------------------------------------------------

local function memberStates(l: Launch): { any }
	local out = {}
	for _, uid in l.Party.Members do
		local state = "Pending"
		if l.Away[uid] then
			state = "Away"
		elseif l.Failed[uid] then
			state = "Failed"
		elseif l.Sent[uid] then
			state = "Sent"
		end
		table.insert(out, { UserId = uid, Name = nameOf(uid), State = state, Reason = l.Failed[uid] })
	end
	return out
end

local function pushTo(l: Launch, uid: number)
	local p = playerOf(uid)
	if not p then
		return
	end
	local isLeader = l.Party.Leader == uid
	local canRetry = false
	if l.Phase == "Failed" or l.Phase == "Partial" then
		if isLeader then
			for fu in l.Failed do
				if (l.Retries[fu] or 0) < Config.Teleport.MaxRetries then
					canRetry = true
				end
			end
		else
			canRetry = l.Failed[uid] ~= nil and (l.Retries[uid] or 0) < Config.Teleport.MaxRetries
		end
		local ticket = l.Ticket
		if ticket and os.time() > ticket.ArriveBy - 10 then
			canRetry = false -- too late to enter the Match place with this ticket
		end
	end
	Net.event("LaunchEvent"):FireClient(p, "Launch", {
		Phase = l.Phase,
		Message = l.Message,
		Members = memberStates(l),
		Leader = l.Party.Leader,
		CanRetry = canRetry,
		CanCancel = l.Phase == "Failed" or l.Phase == "Partial" or l.Phase == "Done",
		Tier = l.Party.Tier,
	})
end

local function push(l: Launch)
	for _, uid in l.Party.Members do
		pushTo(l, uid)
	end
end

local function hideFor(uid: number)
	local p = playerOf(uid)
	if p then
		Net.event("LaunchEvent"):FireClient(p, "Hide", {})
	end
end

-- Ending a launch ------------------------------------------------------------------------------

local function dissolve(l: Launch, dropAway: boolean)
	launches[l.Party.Id] = nil
	-- every entry of this launch, not just the current roster: a member who left the party (seat dropped
	-- mid-prepare, CANCEL, server leave) would otherwise keep a stale entry that blocks their next START
	TeleportBook.dissolve(launchOf, l.Party.Id)
	local party = l.Party
	if dropAway then
		for uid in l.Away do
			if PartyService.of(uid) == party then
				PartyService.leave(uid)
			end
		end
	end
	if PartyService.get(party.Id) == party then
		PartyService.setLocked(party, false, nil)
	end
	for _, uid in table.clone(party.Members) do
		hideFor(uid)
	end
end

local function alive(l: Launch): boolean
	return launches[l.Party.Id] == l
end

local function reacquireAsync(l: Launch, uid: number)
	local p = playerOf(uid)
	if not p or l.Reacquiring[uid] then
		return
	end
	l.Reacquiring[uid] = true
	task.spawn(function()
		local ok = Profiles.reacquire(p)
		l.Reacquiring[uid] = nil
		if not ok and p.Parent then
			p:Kick("Your save moved to another server. Please rejoin.")
		end
	end)
end

-- The launch ended (CANCEL, someone left mid-prepare) while a save step was yielding: give back
-- any profile that step released, nobody is sent.
local function handBack(l: Launch, uids: { number })
	for _, uid in uids do
		local p = playerOf(uid)
		if p and Profiles.isReleased(p) then
			reacquireAsync(l, uid)
		end
	end
end

local function abort(l: Launch, message: string)
	-- before anyone was sent: hand every profile back and unlock the party
	for _, uid in l.Party.Members do
		local p = playerOf(uid)
		if p and Profiles.isReleased(p) then
			reacquireAsync(l, uid)
		end
		local pl = playerOf(uid)
		if pl then
			PartyService.toast(pl, message, "warn")
		end
	end
	dissolve(l, false)
end

-- Sent / failed bookkeeping --------------------------------------------------------------------

local function settle(l: Launch)
	-- Preparing counts too: a failed save on a retry must land on Failed / Partial, not hang
	if l.Phase == "Done" or not alive(l) then
		return
	end
	local pending = false
	local failed = false
	local away = false
	for _, uid in l.Party.Members do
		if l.Away[uid] then
			away = true
		elseif l.Failed[uid] then
			failed = true
		else
			pending = true
		end
	end
	if pending then
		return
	end
	if failed then
		l.Phase = if away then "Partial" else "Failed"
		l.Message = if away then "Some of your party could not make it. Try again, or cancel." else "The teleport did not work. Nothing was lost."
	else
		l.Phase = "Done"
		l.Message = "Your party is in the hunt."
	end
	push(l)
end

local function markFailed(l: Launch, uid: number, reason: string)
	if l.Away[uid] or l.Failed[uid] then
		return
	end
	l.Failed[uid] = reason
	l.Sent[uid] = nil
	reacquireAsync(l, uid)
	settle(l)
	push(l)
end

local function teleportMembers(l: Launch, uids: { number })
	local ticket, code = l.Ticket, l.Code
	if not ticket or not code then
		return
	end
	local players: { Player } = {}
	for _, uid in uids do
		local p = playerOf(uid)
		if p then
			table.insert(players, p)
			l.Sent[uid] = true
		else
			l.Away[uid] = true
		end
	end
	if #players == 0 then
		settle(l)
		return
	end
	l.Gen += 1
	local gen = l.Gen
	l.Phase = "Teleporting"
	l.Message = "Heading to the hunt..."
	push(l)

	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = code
	-- A hint for the client only. The Match server never trusts it; it reads the ticket by PrivateServerId.
	options:SetTeleportData({ TicketId = ticket.Id, Hint = true })
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(Config.Places.MatchPlaceId, players, options)
	end)
	if not ok then
		warn("[LobbyLaunch] TeleportAsync failed:", err)
		for _, p in players do
			markFailed(l, p.UserId, "Teleport failed")
		end
		return
	end
	-- Anyone still here after the watchdog was not sent (TeleportInitFailed covers loud failures).
	task.delay(Config.Teleport.SentWatchdog, function()
		if l.Gen ~= gen or launches[l.Party.Id] ~= l then
			return
		end
		for _, p in players do
			if p.Parent and not l.Away[p.UserId] and not l.Failed[p.UserId] then
				markFailed(l, p.UserId, "Timed out")
			end
		end
	end)
end

-- Starting --------------------------------------------------------------------------------------

local function releaseAll(l: Launch, uids: { number }): (boolean, string?)
	for _, uid in uids do
		local p = playerOf(uid)
		if not p then
			return false, "A party member left."
		end
		local ok, why = Profiles.releaseForTeleport(p)
		if not ok then
			return false, nameOf(uid) .. ": " .. tostring(why or "save failed")
		end
	end
	return true, nil
end

-- Saving yields: a member can leave the server (or the party) while another member's save runs, after
-- releaseAll already checked them. Re-check right before the teleport so nobody gone is marked as sent.
local function stillHere(l: Launch, uids: { number }): (boolean, string?)
	return TeleportBook.stillHere(l.Party.Members, uids, function(uid)
		return playerOf(uid) ~= nil
	end)
end

local function run(l: Launch)
	l.Phase = "Preparing"
	l.Message = "Saving and getting your hunt ready..."
	push(l)
	local party = l.Party
	if not l.Ticket then
		local okR, code, privateId = pcall(function()
			return TeleportService:ReserveServer(Config.Places.MatchPlaceId)
		end)
		if not okR or type(code) ~= "string" or type(privateId) ~= "string" then
			warn("[LobbyLaunch] ReserveServer failed:", code)
			abort(l, "Could not start the hunt. Try again in a moment.")
			return
		end
		local names = {}
		for i, uid in party.Members do
			names[i] = nameOf(uid)
		end
		local ticket, why = MatchTicket.create({
			Id = privateId,
			Leader = party.Leader,
			Members = party.Members,
			Names = names,
			Tier = party.Tier,
			Now = os.time(),
			ArriveSeconds = Config.Teleport.ArriveSeconds,
			LifetimeSeconds = Config.Teleport.TicketSeconds,
			MaxMembers = Config.Places.MatchMaxPlayers,
			LobbyJobId = game.JobId,
		})
		if not ticket then
			abort(l, "Could not set up the match (" .. tostring(why) .. ").")
			return
		end
		local stored, serr = Tickets.put(ticket)
		if not stored then
			warn("[LobbyLaunch] ticket store failed:", serr)
			abort(l, "Could not set up the match. Try again in a moment.")
			return
		end
		l.Ticket, l.Code = ticket, code
		if not alive(l) then
			return -- aborted while reserving; nothing was released yet
		end
	end
	-- Members that still need sending: everyone not already away.
	local targets: { number } = {}
	for _, uid in party.Members do
		if not l.Away[uid] then
			table.insert(targets, uid)
		end
	end
	local ok, why = releaseAll(l, targets)
	if not alive(l) then
		handBack(l, targets)
		return
	end
	if ok then
		ok, why = stillHere(l, targets)
	end
	if not ok then
		-- first attempt: nothing was sent, so stop and hand everything back
		local anySent = next(l.Away) ~= nil
		if anySent then
			for _, uid in targets do
				if not l.Failed[uid] then
					l.Failed[uid] = why or "save failed"
				end
				reacquireAsync(l, uid)
			end
			settle(l)
			push(l)
		else
			abort(l, why or "Could not save safely. Try again in a moment.")
		end
		return
	end
	teleportMembers(l, targets)
end

function LobbyLaunch.startParty(party: PartyService.Party): (boolean, string?)
	if Config.Places.MatchPlaceId == 0 then
		return false, "Match place is not set up yet."
	end
	if launches[party.Id] then
		return false, "Already launching."
	end
	for _, uid in party.Members do
		local p = playerOf(uid)
		if not p or not Profiles.isLoaded(p) then
			return false, "Waiting for every member to load."
		end
		local held = launchOf[uid]
		if held and launches[held] then
			return false, "Someone is still away from a hunt."
		elseif held then
			launchOf[uid] = nil -- left over from a launch that already ended
		end
	end
	local l: Launch = {
		Id = HttpService:GenerateGUID(false),
		Party = party,
		Ticket = nil,
		Code = nil,
		Phase = "Preparing",
		Message = "",
		Sent = {},
		Away = {},
		Failed = {},
		Retries = {},
		Reacquiring = {},
		AwayDeadline = os.clock() + Config.Teleport.AwayHoldSeconds,
		Gen = 0,
	}
	launches[party.Id] = l
	for _, uid in party.Members do
		launchOf[uid] = party.Id
	end
	PartyService.setLocked(party, true, l.Id) -- roster locked for the launch
	task.spawn(run, l)
	return true, nil
end

-- Player actions (RETRY / CANCEL) -----------------------------------------------------------------

local function onAction(player: Player, action: any)
	local pid = launchOf[player.UserId]
	local l = pid and launches[pid]
	if not l then
		return
	end
	local uid = player.UserId
	local isLeader = l.Party.Leader == uid
	if action == "Retry" then
		if l.Phase ~= "Failed" and l.Phase ~= "Partial" then
			return
		end
		local ticket = l.Ticket
		if not ticket or os.time() > ticket.ArriveBy - 10 then
			PartyService.toast(player, "That hunt spot ran out. Start again.", "warn")
			return
		end
		local targets: { number } = {}
		for fu in l.Failed do
			if (isLeader or fu == uid) and (l.Retries[fu] or 0) < Config.Teleport.MaxRetries then
				table.insert(targets, fu)
			end
		end
		if #targets == 0 then
			return
		end
		for _, fu in targets do
			l.Retries[fu] = (l.Retries[fu] or 0) + 1
			l.Failed[fu] = nil
		end
		-- Preparing right away: CANCEL is refused from here until the retry lands, so a cancel can
		-- no longer dissolve the launch while this retry goes on to release saves and teleport.
		l.Phase = "Preparing"
		l.Message = "Trying again..."
		push(l)
		task.spawn(function()
			-- let a running lock re-acquire finish before releasing again
			local t0 = os.clock()
			while os.clock() - t0 < 10 do
				local busy = false
				for _, fu in targets do
					busy = busy or l.Reacquiring[fu] == true
				end
				if not busy then
					break
				end
				task.wait(0.25)
			end
			if not alive(l) then
				return
			end
			local ok, why = releaseAll(l, targets)
			if not alive(l) then
				handBack(l, targets)
				return
			end
			if ok then
				ok, why = stillHere(l, targets)
			end
			if not ok then
				for _, fu in targets do
					l.Failed[fu] = why or "save failed"
					reacquireAsync(l, fu)
				end
				settle(l)
				push(l)
				return
			end
			teleportMembers(l, targets)
		end)
	elseif action == "Cancel" then
		if l.Phase == "Preparing" or l.Phase == "Teleporting" then
			return
		end
		if isLeader then
			-- everyone still in this lobby is free again; members already in the Match place are
			-- dropped from the party (the ticket simply runs out there)
			dissolve(l, true)
		else
			l.Failed[uid] = nil
			PartyService.leave(uid)
			launchOf[uid] = nil
			hideFor(uid)
			settle(l)
		end
	end
end

-- Teleport failures ---------------------------------------------------------------------------------

local function onInitFailed(player: Player, result: any, message: any)
	local pid = launchOf[player.UserId]
	local l = pid and launches[pid]
	if not l or not l.Sent[player.UserId] then
		return
	end
	warn("[LobbyLaunch] TeleportInitFailed", player.UserId, tostring(result), tostring(message))
	markFailed(l, player.UserId, "Teleport failed")
end

-- Members leaving / returning ----------------------------------------------------------------------

local function onRemoving(player: Player)
	local uid = player.UserId
	local pid = launchOf[uid]
	local l = pid and launches[pid]
	if not l then
		return
	end
	if l.Sent[uid] and not l.Failed[uid] and l.Phase ~= "Preparing" then
		l.Away[uid] = true
		l.Sent[uid] = nil
		settle(l)
		push(l)
	elseif l.Phase == "Preparing" then
		-- left mid-prepare (party seat is dropped by PartyService): stop and hand profiles back
		task.defer(function()
			if launches[l.Party.Id] == l then
				abort(l, nameOf(uid) .. " left. Launch cancelled.")
			end
		end)
	elseif l.Phase ~= "Teleporting" then
		-- Left a Failed / Partial / Done launch without being sent: this member is gone, not in the Match place.
		-- Forget them, and end the launch once nobody of it is left on this server and nobody is away (a launch
		-- with members away is ended by the AwayDeadline loop in start()).
		if launchOf[uid] == pid then
			launchOf[uid] = nil
		end
		task.defer(function()
			if launches[l.Party.Id] ~= l or next(l.Away) ~= nil then
				return
			end
			for _, m in l.Party.Members do
				if m ~= uid and playerOf(m) ~= nil then
					return
				end
			end
			dissolve(l, false)
		end)
	end
end

local function onAdded(player: Player)
	local uid = player.UserId
	local pid = launchOf[uid]
	local l = pid and launches[pid]
	if not l or not l.Away[uid] then
		return
	end
	l.Away[uid] = nil
	l.Sent[uid] = nil
	l.Failed[uid] = nil
	if next(l.Away) == nil then
		dissolve(l, false)
	else
		pushTo(l, uid)
	end
end

function LobbyLaunch.start()
	PartyService.onStart(LobbyLaunch.startParty)
	PartyService.setKeepOnLeave(function(uid)
		local pid = launchOf[uid]
		local l = pid and launches[pid]
		return l ~= nil and l.Phase ~= "Preparing" and (l.Sent[uid] == true or l.Away[uid] == true)
	end)
	Net.event("LaunchAction").OnServerEvent:Connect(onAction)
	TeleportService.TeleportInitFailed:Connect(onInitFailed)
	Players.PlayerRemoving:Connect(onRemoving)
	Players.PlayerAdded:Connect(onAdded)
	task.spawn(function()
		while true do
			task.wait(5)
			for _, l in table.clone(launches) do
				if os.clock() > l.AwayDeadline and next(l.Away) ~= nil then
					dissolve(l, true) -- the party never came back: free everyone left here
				end
			end
		end
	end)
end

return LobbyLaunch
