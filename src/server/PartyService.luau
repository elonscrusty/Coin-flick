--!strict
-- Parties in the shared lobby. Invite-only; standing somewhere never enrols anyone.
-- Leader picks the tier and starts once every member is ready and has no blockers.
-- Any roster or tier change clears readiness. The roster is locked while a hunt is running.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local HuntQueue = require(Shared.HuntQueue)
local QueueConfig = require(Shared.QueueConfig)
local Profiles = require(script.Parent.Profiles)

local PartyService = {}

export type Party = {
	Id: string,
	Leader: number,
	Members: { number }, -- UserIds, join order
	Ready: { [number]: boolean },
	Tier: string,
	Locked: boolean,
	MatchKey: string?,
	-- Public hunts (lobby queue): a party object built for one hunt and never registered here. GroupOf maps each
	-- member to the group they queued with (a real party id, or "u:<id>" alone) (informational: the friend bonus counts Roblox friends in the server, server/FriendBonus).
	Public: boolean?,
	GroupOf: { [number]: string }?,
}

local parties: { [string]: Party } = {}
local partyOf: { [number]: string } = {}
local invites: { [number]: { [string]: { From: number, Expires: number } } } = {} -- invitee -> partyId -> info

local inviteCooldown: { [string]: number } = {} -- "from:to" -> os.clock() of last invite
local startHandler: ((Party) -> (boolean, string?))? = nil
local isBusy: ((number) -> boolean)? = nil
local keepOnLeave: ((number) -> boolean)? = nil

local function playerOf(userId: number): Player?
	return Players:GetPlayerByUserId(userId)
end

local function toast(player: Player, text: string, kind: string?)
	Net.event("Toast"):FireClient(player, text, kind or "info")
end
PartyService.toast = toast

function PartyService.get(id: string): Party?
	return parties[id]
end

function PartyService.of(userId: number): Party?
	local id = partyOf[userId]
	return if id then parties[id] else nil
end

-- Reasons a member cannot start the chosen tier. Empty table = good to go.
function PartyService.blockers(party: Party, userId: number): { string }
	local out = {}
	local p = playerOf(userId)
	local data = p and Profiles.get(p)
	if not data then
		table.insert(out, "Loading profile")
		return out
	end
	if p and p:GetAttribute("InTower") then
		table.insert(out, "In the pet tower") -- TowerService sets InTower while they climb
	end
	if p and p:GetAttribute("InBattle") then
		table.insert(out, "In a pet battle") -- PvpService sets InBattle while they fight
	end
	if not data.UnlockedTiers[party.Tier] then
		table.insert(out, party.Tier .. " locked")
	end
	if #data.InventoryGeodes >= Profiles.petCapacity(data) then
		table.insert(out, "Pet Book full (" .. Profiles.petCapacity(data) .. ")")
	end
	return out
end

local function view(party: Party)
	local members = {}
	for _, uid in party.Members do
		local p = playerOf(uid)
		local data = p and Profiles.get(p)
		table.insert(members, {
			UserId = uid,
			Name = if p then p.DisplayName else "?",
			Leader = uid == party.Leader,
			Ready = party.Ready[uid] == true,
			Tool = if data then data.EquippedHandheld else "Hammer",
			Blockers = PartyService.blockers(party, uid),
		})
	end
	local reason: string? = nil
	for _, m in members do
		if #m.Blockers > 0 then
			reason = m.Name .. ": " .. m.Blockers[1]
			break
		end
		if not m.Ready then
			reason = "Waiting for " .. m.Name .. " to ready"
			break
		end
	end
	if party.Locked then
		reason = "Hunt in progress"
	end
	local tier = Config.Tiers[party.Tier]
	local tutorial = false
	if #party.Members == 1 then
		local p = playerOf(party.Members[1])
		local data = p and Profiles.get(p)
		tutorial = data ~= nil and data.TutorialStep == 0
	end
	return {
		Id = party.Id,
		Leader = party.Leader,
		Members = members,
		Tier = party.Tier,
		TierRocks = if tutorial then Config.Tutorial.Rocks else tier.Rocks,
		Recommended = tier.Recommended,
		Tutorial = tutorial,
		Locked = party.Locked,
		CanStart = reason == nil,
		Reason = reason,
		Max = Config.Party.MaxSize,
	}
end
PartyService.view = view

local function invitesFor(userId: number)
	local out = {}
	local now = os.clock()
	local mine = invites[userId]
	if not mine then
		return out
	end
	for pid, inv in mine do
		local party = parties[pid]
		local from = playerOf(inv.From)
		if party and inv.Expires > now and from then
			table.insert(out, { PartyId = pid, From = from.DisplayName })
		end
	end
	return out
end

function PartyService.sync(userId: number)
	local p = playerOf(userId)
	if not p then
		return
	end
	local party = PartyService.of(userId)
	Net.event("PartyState"):FireClient(p, if party then view(party) else nil, invitesFor(userId))
	PartyService.sendQueue(p)
end

function PartyService.syncParty(party: Party)
	for _, uid in party.Members do
		PartyService.sync(uid)
	end
end

local function clearReady(party: Party)
	table.clear(party.Ready)
end

local function create(userId: number): Party
	local party: Party = {
		Id = HttpService:GenerateGUID(false),
		Leader = userId,
		Members = { userId },
		Ready = {},
		Tier = "Gravel",
		Locked = false,
	}
	parties[party.Id] = party
	partyOf[userId] = party.Id
	return party
end

function PartyService.leave(userId: number)
	local party = PartyService.of(userId)
	if not party then
		return
	end
	local idx = table.find(party.Members, userId)
	if idx then
		table.remove(party.Members, idx)
	end
	partyOf[userId] = nil
	party.Ready[userId] = nil
	if #party.Members == 0 then
		parties[party.Id] = nil
		for _, inv in invites do
			inv[party.Id] = nil
		end
	else
		if party.Leader == userId then
			party.Leader = party.Members[1] -- earliest remaining member
		end
		if not party.Locked then
			clearReady(party)
		end
		PartyService.syncParty(party)
	end
	PartyService.sync(userId)
end

function PartyService.setLocked(party: Party, locked: boolean, matchKey: string?)
	party.Locked = locked
	party.MatchKey = matchKey
	clearReady(party)
	PartyService.syncParty(party)
end

function PartyService.onStart(fn: (Party) -> (boolean, string?))
	startHandler = fn
end

-- Teleport mode: a member who leaves this server because the party is teleporting keeps their
-- seat (the party comes back together later). Return true to keep the seat.
function PartyService.setKeepOnLeave(fn: (number) -> boolean)
	keepOnLeave = fn
end

function PartyService.setBusyCheck(fn: (number) -> boolean)
	isBusy = function(uid: number): boolean
		-- a player climbing the pet tower (TowerService sets InTower) is busy like a hunter
		local p = playerOf(uid)
		if p and (p:GetAttribute("InTower") or p:GetAttribute("InBattle")) then
			return true
		end
		return fn(uid)
	end
end


local joinToastAt: { [number]: number } = {} -- userId -> os.clock() of the last "joined the queue" toast

-- Public hunt queue (lobby portal pads and the PLAY button) -----------------------------------------------------
-- Rules live in shared/HuntQueue (tested). A player or a whole party joins; the hunt starts QueueConfig.Seconds
-- after the first join with whoever is there (1..Size); a joiner who does not fit opens the next queue.

local queue = HuntQueue.new({ Size = QueueConfig.Size, Seconds = QueueConfig.Seconds, StartWhenFull = QueueConfig.StartWhenFull })
PartyService.Queue = queue -- read-only for offline tests

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function groupKey(uid: number): string
	local party = PartyService.of(uid)
	return if party then party.Id else "u:" .. uid
end

-- What one player's PLAY button shows: their queue (Mine) or the queue a new joiner would land in (Open).
function PartyService.sendQueue(p: Player)
	local now = serverNow()
	local mine = HuntQueue.find(queue, p.UserId)
	Net.event("LaunchEvent"):FireClient(p, "Queue", {
		Mine = HuntQueue.view(queue, mine, now),
		Open = HuntQueue.view(queue, HuntQueue.openQueue(queue), now),
	})
end

-- Coalesced: queue changes mark it dirty and the 0.25 s loop sends once, so button spam cannot fan out per call.
local queueDirty = false
local function broadcastQueue()
	queueDirty = true
end
local function flushQueue()
	if not queueDirty then
		return
	end
	queueDirty = false
	for _, p in Players:GetPlayers() do
		PartyService.sendQueue(p)
	end
end

-- Takes a group out of the queue (cancel, roster change, someone started another hunt).
local function unqueueGroup(key: string, why: string?)
	local members = HuntQueue.leaveGroup(queue, key)
	if #members == 0 then
		return
	end
	for _, uid in members do
		local p = playerOf(uid)
		if p and why then
			toast(p, why, "info")
		end
	end
	broadcastQueue()
end

local function unqueuePlayer(uid: number)
	if HuntQueue.leave(queue, uid) then
		broadcastQueue()
	end
end
PartyService.unqueue = unqueuePlayer

-- Why a player cannot be queued right now (nil = fine). Zone locks never block: the public hunt runs in the
-- highest zone everyone in it has unlocked.
local function queueBlocker(uid: number): string?
	local p = playerOf(uid)
	local data = p and Profiles.get(p)
	if not p or not data then
		return "Loading profile"
	end
	if isBusy and isBusy(uid) then
		return "Still in a hunt"
	end
	if #data.InventoryGeodes >= Profiles.petCapacity(data) then
		return "Pet Book full (" .. Profiles.petCapacity(data) .. ")"
	end
	return nil
end

local soloAction: ((Player) -> ())? = nil -- set below: the existing Solo path (first-time practice)

-- Join the public queue. Returns true when the player is queued (or already was).
local function queueJoin(player: Player, fromPortal: boolean): boolean
	local uid = player.UserId
	if (HuntQueue.find(queue, uid)) then
		return true
	end
	local data = Profiles.get(player)
	if not data then
		if not fromPortal then
			toast(player, "Loading your profile...", "info")
		end
		return false
	end
	-- First-time players get the practice pile, exactly as SOLO HUNT does.
	if data.TutorialStep == 0 then
		local solo = soloAction
		if solo then
			solo(player)
		end
		return false
	end
	local party = PartyService.of(uid)
	local members = { uid }
	if party then
		if party.Locked then
			toast(player, "Your party is still hunting.", "warn")
			return false
		end
		if #party.Members > 1 and party.Leader ~= uid then
			toast(player, "Your party leader joins the hunt for the whole party.", "info")
			return false
		end
		members = table.clone(party.Members)
	end
	for _, m in members do
		local why = queueBlocker(m)
		if why then
			local mp = playerOf(m)
			toast(player, (if m == uid or not mp then "" else mp.DisplayName .. ": ") .. why, "warn")
			return false
		end
	end
	local q, why = HuntQueue.join(queue, groupKey(uid), members, serverNow())
	if not q then
		if why == "AlreadyQueued" then
			toast(player, "Someone in your party is already queued.", "info")
		end
		return false
	end
	for _, m in members do
		local mp = playerOf(m)
		-- once per join: a re-join a few seconds later (portal pad touched again, PLAY tapped again after a leave)
		-- does not pop the same toast again while the HUNT IN countdown runs
		if mp and os.clock() - (joinToastAt[m] or -math.huge) > 15 then
			joinToastAt[m] = os.clock()
			toast(mp, "You joined the hunt queue!", "ok")
		end
	end
	broadcastQueue()
	return true
end

-- Starts a due queue's hunt. A single real party keeps its own party (and tier); mixed groups hunt as a public
-- party in the highest zone they all unlocked. A failed start waits RetrySeconds and tries again.
local function launch(q: HuntQueue.Queue)
	local groupOf: { [number]: string } = {}
	local members: { number } = {}
	for _, g in q.Groups do
		for i = #g.Members, 1, -1 do
			local uid = g.Members[i]
			local p = playerOf(uid)
			local why = queueBlocker(uid)
			if why or not p or not p.Character then
				table.remove(g.Members, i)
				if p then
					toast(p, "You were taken out of the hunt queue (" .. (why or "still spawning") .. ").", "warn")
				end
			end
		end
		for _, uid in g.Members do
			table.insert(members, uid)
			groupOf[uid] = g.Key
		end
	end
	if #members == 0 or not startHandler then
		return
	end
	local unlocked = {}
	for _, uid in members do
		local p = playerOf(uid)
		local data = p and Profiles.get(p)
		table.insert(unlocked, if data then data.UnlockedTiers else {})
	end
	local tier = HuntQueue.commonTier(Config.TierOrder, unlocked)
	local only = if #q.Groups == 1 then parties[q.Groups[1].Key] else nil
	local party: Party
	if only and not only.Locked and #only.Members == #members then
		party = only
		local ok = true
		for _, set in unlocked do
			ok = ok and set[party.Tier] == true
		end
		if not ok then
			party.Tier = tier
		end
	else
		party = {
			Id = "public:" .. HttpService:GenerateGUID(false),
			Leader = members[1],
			Members = members,
			Ready = {},
			Tier = tier,
			Locked = false,
			Public = true,
			GroupOf = groupOf,
		}
	end
	local start = startHandler :: (Party) -> (boolean, string?)
	local ok, err = start(party)
	if not ok then
		for _, uid in members do
			local p = playerOf(uid)
			if p then
				toast(p, (err or "Could not start the hunt.") .. " Trying again...", "warn")
			end
		end
		HuntQueue.restore(queue, q, serverNow() + QueueConfig.RetrySeconds)
	end
end

-- Lobby board and pads (built by the lobby builder; any of them may be missing).
local board: TextLabel? = nil
local pads: { BasePart } = {}
local padLook: { [BasePart]: { Color: Color3, Material: Enum.Material } } = {}
local lastBoard = ""

local function findBoard(): TextLabel?
	if board and board.Parent then
		return board
	end
	local part = Workspace:FindFirstChild("QueueBoard", true)
	local label = part and part:FindFirstChild("QueueText", true)
	board = if label and label:IsA("TextLabel") then label else nil
	return board
end

local function updateBoard()
	local first = queue.Queues[1]
	local text = QueueConfig.Board.Idle
	local count = 0
	if first then
		count = HuntQueue.count(first)
		local left = math.max(0, math.ceil(first.StartsAt - serverNow()))
		text = string.format(QueueConfig.Board.Counting, left, count, queue.Size)
	end
	local label = findBoard()
	if label and text ~= lastBoard then
		label.Text = text
	end
	lastBoard = if label then text else ""
	for i, pad in pads do
		local look = padLook[pad]
		if pad.Parent and look then
			local lit = i <= count
			pad.Color = if lit then QueueConfig.Board.PadLit else look.Color
			pad.Material = if lit then Enum.Material.Neon else look.Material
		end
	end
end

local portalLast: { [Player]: number } = {}
-- Players who tapped LEAVE: the portal pads do not queue them again until they step off (audit F02: standing on a
-- pad re-joined at the next touch, so one LEAVE looked like "You left the hunt queue. x2").
local padHold: { [Player]: true? } = {}

local function onPortalTouch(hit: BasePart)
	local model = hit:FindFirstAncestorOfClass("Model")
	local player = model and Players:GetPlayerFromCharacter(model)
	if not player then
		return
	end
	local t = os.clock()
	if t - (portalLast[player] or -math.huge) < QueueConfig.TouchDebounce then
		return
	end
	if padHold[player] then
		return
	end
	portalLast[player] = t
	if (isBusy and isBusy(player.UserId)) or not Profiles.isLoaded(player) then
		return
	end
	if not queueJoin(player, true) then
		portalLast[player] = t + 4 -- a refusal toast once, not on every step while standing on the pad
	end
end

local watched: { [BasePart]: boolean } = {}
local function watchPortal(inst: Instance)
	if not inst:IsA("BasePart") or watched[inst] or inst:GetAttribute("HuntPortal") ~= true then
		return
	end
	watched[inst] = true
	inst.Touched:Connect(onPortalTouch)
	if inst.Name ~= "HuntPortal" then
		-- the glowing pads in front of the portal light up one per queued player
		padLook[inst] = { Color = inst.Color, Material = inst.Material }
		table.insert(pads, inst)
		table.sort(pads, function(a, b)
			local ia, ib = a:GetAttribute("PadIndex"), b:GetAttribute("PadIndex")
			if type(ia) == "number" and type(ib) == "number" and ia ~= ib then
				return ia < ib
			end
			if a.Name ~= b.Name then
				return a.Name < b.Name
			end
			return a.Position.X < b.Position.X
		end)
	end
end

-- True when `player` stands on or right next to a hunt portal / queue pad (QueueConfig.PadClear studs around it).
local function onAPad(player: Player): boolean
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	local m = QueueConfig.PadClear
	for part in watched do
		if part.Parent then
			local rel = part.CFrame:PointToObjectSpace(root.Position)
			local half = part.Size / 2
			if math.abs(rel.X) <= half.X + m and math.abs(rel.Z) <= half.Z + m and math.abs(rel.Y) <= half.Y + 8 then
				return true
			end
		end
	end
	return false
end

local function startQueue()
	for _, d in Workspace:GetDescendants() do
		watchPortal(d)
	end
	Workspace.DescendantAdded:Connect(watchPortal)
	Players.PlayerRemoving:Connect(function(player)
		portalLast[player] = nil
		padHold[player] = nil
		joinToastAt[player.UserId] = nil
		unqueuePlayer(player.UserId)
		HuntQueue.forget(queue, player.UserId) -- no kept HUNT IN time for someone who left the server
	end)
	task.spawn(function()
		while true do
			task.wait(0.25)
			for p in padHold do
				if not p.Parent or not onAPad(p) then
					padHold[p] = nil
				end
			end
			local due = HuntQueue.popDue(queue, serverNow())
			for _, q in due do
				launch(q)
			end
			if #due > 0 then
				broadcastQueue()
			end
			flushQueue()
			updateBoard()
		end
	end)
end

local function handle(player: Player, action: any, arg: any)
	if type(action) ~= "string" then
		return
	end
	local uid = player.UserId
	local party = PartyService.of(uid)
	if isBusy and isBusy(uid) and action ~= "Sync" then
		toast(player, "Tap LOBBY to leave the hunt first.", "warn")
		return
	end
	-- Someone who already went back to the lobby can still leave a party that is hunting.
	if party and party.Locked and action ~= "Sync" and action ~= "Leave" then
		toast(player, "Your party is still hunting. Leave the party to start a new one.", "warn")
		return
	end

	local kind: string = tostring(action) -- a plain string copy (the guards above over-narrow `action`)
	-- Public queue intents (PLAY button). The portal pads call queueJoin directly.
	if kind == "Queue" then
		queueJoin(player, false)
		return
	elseif kind == "Unqueue" then
		local _, g = HuntQueue.find(queue, uid)
		if g then
			padHold[player] = onAPad(player) or nil
			unqueueGroup(g.Key, "You left the hunt queue.")
		end
		return
	end
	-- Starting another hunt or changing the roster takes the group out of the queue.
	if kind == "Solo" or kind == "Start" then
		local _, g = HuntQueue.find(queue, uid)
		if g then
			unqueueGroup(g.Key, nil)
		end
	elseif kind == "Leave" or kind == "Accept" then
		unqueuePlayer(uid)
		-- only a real invite may pull a queued group out (a forged id must not kick other players)
		if kind == "Accept" and type(arg) == "string" and invites[uid] and invites[uid][arg] then
			unqueueGroup(arg, "Your party changed. Join the hunt queue again.")
		end
	elseif kind == "Kick" and type(arg) == "number" and arg ~= uid and party and party.Leader == uid and table.find(party.Members, arg) then
		-- only a member of the caller's own party: a forged id must not pull strangers out of the queue
		unqueuePlayer(arg)
	end

	if action == "Sync" then
		-- nothing, sync below
	elseif action == "Create" then
		if not party then
			party = create(uid)
		end
	elseif action == "Solo" then
		-- One-member party that starts right away when nothing blocks it.
		if party and #party.Members > 1 then
			PartyService.leave(uid)
			party = nil
		end
		local solo = party or create(uid)
		solo.Ready[uid] = true
		local v = view(solo)
		if v.CanStart and startHandler then
			local ok, err = startHandler(solo)
			if not ok then
				toast(player, err or "Could not start the hunt.", "warn")
			end
		elseif v.Reason then
			toast(player, v.Reason, "warn")
		end
		party = solo
	elseif action == "Leave" then
		PartyService.leave(uid)
		return
	elseif action == "Invite" then
		local target = if type(arg) == "number" then playerOf(arg) else nil
		if not party then
			party = create(uid)
		end
		local pt = party :: Party
		if pt.Leader ~= uid then
			toast(player, "Only the leader can invite.", "warn")
		elseif not target or target == player then
			toast(player, "That player is not in this lobby.", "warn")
		elseif #pt.Members >= Config.Party.MaxSize then
			toast(player, "Party is full (" .. Config.Party.MaxSize .. ").", "warn")
		elseif PartyService.of(target.UserId) == pt then
			toast(player, target.DisplayName .. " is already in your party.", "info")
		elseif os.clock() - (inviteCooldown[uid .. ":" .. target.UserId] or -math.huge) < 10 then
			toast(player, "Invite already sent. Wait a few seconds.", "info")
		else
			inviteCooldown[uid .. ":" .. target.UserId] = os.clock()
			invites[target.UserId] = invites[target.UserId] or {}
			invites[target.UserId][pt.Id] = { From = uid, Expires = os.clock() + Config.Party.InviteSeconds }
			PartyService.sync(target.UserId)
			toast(player, "Invite sent to " .. target.DisplayName .. ".", "ok")
			toast(target, player.DisplayName .. " invited you to a pet hunt party.", "info")
		end
	elseif action == "Accept" or action == "Decline" then
		local pid = if type(arg) == "string" then arg else ""
		local inv = invites[uid] and invites[uid][pid]
		if invites[uid] then
			invites[uid][pid] = nil
		end
		if action == "Accept" then
			local target = parties[pid]
			if not inv or inv.Expires < os.clock() or not target then
				toast(player, "That invite expired.", "warn")
			elseif target.Locked then
				toast(player, "That party is already hunting.", "warn")
			elseif #target.Members >= Config.Party.MaxSize then
				toast(player, "That party is full.", "warn")
			else
				if party then
					PartyService.leave(uid)
				end
				table.insert(target.Members, uid)
				partyOf[uid] = target.Id
				clearReady(target)
				PartyService.syncParty(target)
				return
			end
		end
	elseif action == "Kick" then
		if party and party.Leader == uid and type(arg) == "number" and arg ~= uid and table.find(party.Members, arg) then
			PartyService.leave(arg)
			local kicked = playerOf(arg)
			if kicked then
				toast(kicked, "You were removed from the party.", "info")
			end
		end
	elseif action == "Ready" then
		if party then
			party.Ready[uid] = arg == true
			PartyService.syncParty(party)
			return
		end
	elseif action == "Tier" then
		if party and party.Leader == uid and type(arg) == "string" and Config.Tiers[arg] then
			party.Tier = arg
			clearReady(party)
			PartyService.syncParty(party)
			return
		end
	elseif action == "Start" then
		if not party or party.Leader ~= uid then
			toast(player, "Only the party leader can start.", "warn")
		else
			local v = view(party)
			if not v.CanStart then
				toast(player, v.Reason or "Not ready", "warn")
			elseif startHandler then
				local ok, err = startHandler(party)
				if not ok then
					toast(player, err or "Could not start the hunt.", "warn")
				end
			end
		end
	end
	PartyService.sync(uid)
end

soloAction = function(player: Player)
	handle(player, "Solo", nil)
end

function PartyService.start()
	startQueue()
	local limiter: { [Player]: { n: number, t: number } } = {}
	Net.event("PartyAction").OnServerEvent:Connect(function(player, action, arg)
		local l = limiter[player]
		local now = os.clock()
		if not l or now - l.t > 1 then
			local fresh = { n = 0, t = now }
			limiter[player] = fresh
			l = fresh
		end
		l.n += 1
		if l.n > 8 then
			return
		end
		handle(player, action, arg)
	end)
	Players.PlayerRemoving:Connect(function(player)
		limiter[player] = nil
		invites[player.UserId] = nil
		-- keys are "from:to": drop exactly this player's pairs (a plain substring match also hit other ids)
		local id = tostring(player.UserId)
		for k in table.clone(inviteCooldown) do
			local a, b = string.match(k, "^(%d+):(%d+)$")
			if a == id or b == id then
				inviteCooldown[k] = nil
			end
		end
		local keep = keepOnLeave
		if keep and keep(player.UserId) then
			return
		end
		PartyService.leave(player.UserId)
	end)
	Profiles.onChanged(function(player)
		local party = PartyService.of(player.UserId)
		if party and not party.Locked then
			PartyService.syncParty(party)
		end
	end)
	-- Expire invites.
	task.spawn(function()
		while true do
			task.wait(5)
			local now = os.clock()
			for uid, list in invites do
				local changed = false
				for pid, inv in list do
					if inv.Expires < now or not parties[pid] then
						list[pid] = nil
						changed = true
					end
				end
				if changed then
					PartyService.sync(uid)
				end
			end
		end
	end)
end

return PartyService
