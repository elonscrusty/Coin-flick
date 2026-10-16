--!strict
-- The ONE authoritative service for the V3 loop (docs/V3_LOOP.md): pickup, deposit, crush and
-- machine ticks all go through here, on top of the pure rules in src/shared/RoundRocks.luau.
-- MatchService owns the lifecycle (arenas, countdown, reveal, results, saves) and calls in.
--
-- Clients send intents only: RockAction(action, roundId, rockId?). The server reads the player's
-- position itself, derives the station from round membership (never from the client), checks the
-- round id, phase, cadence, range and entitlement, and replicates opaque ids + states only. The
-- target rock is never sent anywhere before it is crushed. The old pile "Strike" remote is gone.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local HuntLedger = require(Shared.HuntLedger)
local SightRules = require(Shared.SightRules)
local ProgressConfig = require(Shared.ProgressConfig)
local HuntFun = require(Shared.HuntFun)
local EggPerks = require(Shared.EggPerks)
local Profiles = require(script.Parent.Profiles)
local EggEvents = require(script.Parent.EggEvents)

local RockService = {}
-- Set by PvpService: called once per egg a player finishes in a hunt (found = the egg with the pet inside).
RockService.onCracked = nil :: ((Player, boolean) -> ())?
-- Set by PvpService: gives `amount` pet XP to each pet following the player (surprise eggs, shared/HuntFun).
RockService.onPetXp = nil :: ((Player, number) -> ())?

local surpriseRng = Random.new()

local ACTIONS = { Pickup = true, Deposit = true, Crush = true, ToggleMachine = true }
local MIN_GAP = 0.03 -- any RockAction faster than ~33/s is dropped before it costs anything
local TOGGLE_GAP = 0.4
local REPLY_GAP = 0.15

local lastAny: { [Player]: number } = {}
local lastToggle: { [Player]: number } = {}
local lastReply: { [Player]: number } = {}

-- Motion sanity check (Config.Motion). Character positions are owned by the client, so a cheat can
-- teleport between the pile and its table. The server keeps one TRUSTED point per member (the last position
-- it judged reachable, and when). Every check (the scheduler each step, and every rock action on the LIVE
-- position) compares against it: a horizontal move farther than walking allows since then
-- (WalkSpeed * SpeedFactor * elapsed + Slack) is refused and locks that member's rock actions for a moment.
-- An impossible position never becomes trusted; it is accepted only once enough time has passed that walking
-- there would have been possible, so a fling or a lag spike heals by itself. The trusted point moves forward at
-- most every Anchor seconds, so the Slack is forgiven once per Anchor, not once per sample. Vertical moves
-- (jumps, falls) are not judged.
type Motion = { Pos: Vector3, T: number, LockUntil: number, GraceUntil: number }
local motion: { [number]: Motion } = {}

-- A server move (spawn, respawn, round start) is not a teleport: for Grace seconds the trusted point simply
-- follows the avatar (the client may still report the old spot for a moment), then checks start fresh.
function RockService.resetMotion(uid: number)
	local s = motion[uid]
	local grace = os.clock() + Config.Motion.Grace
	if s then
		s.GraceUntil = grace
	else
		motion[uid] = { Pos = Vector3.zero, T = -math.huge, LockUntil = 0, GraceUntil = grace }
	end
end

-- Judges `pos` (world) at time `t` (os.clock) against the trusted point. False for an impossible jump.
local function judgeMotion(uid: number, pos: Vector3, walkSpeed: number, t: number): boolean
	local cfg = Config.Motion
	local s = motion[uid]
	if not s then
		motion[uid] = { Pos = pos, T = t, LockUntil = 0, GraceUntil = 0 }
		return true
	end
	if t < s.GraceUntil or s.T == -math.huge then
		s.Pos, s.T = pos, t
		return true
	end
	local dt = math.max(0, t - s.T)
	local d = Vector2.new(pos.X - s.Pos.X, pos.Z - s.Pos.Z).Magnitude
	local allowed = math.max(walkSpeed, 16) * cfg.SpeedFactor * dt + cfg.Slack
	if d > allowed then
		s.LockUntil = math.max(s.LockUntil, t + cfg.Lock)
		return false -- the trusted point stays where it was
	end
	if dt >= cfg.Anchor then
		s.Pos, s.T = pos, t
	end
	return true
end

local function sampleMotion(uid: number, t: number)
	local p = Players:GetPlayerByUserId(uid)
	local char = p and p.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not root or not hum then
		return
	end
	judgeMotion(uid, root.Position, hum.WalkSpeed, t)
end

-- True while the member's rock actions are refused: the LIVE position `pos` (world) is farther from the
-- trusted point than walking allows right now, or a recent impossible jump still locks them.
local function motionLocked(uid: number, pos: Vector3, walkSpeed: number, t: number): boolean
	if Config.Motion.Enabled == false then
		return false
	end
	local live = judgeMotion(uid, pos, walkSpeed, t)
	local s = motion[uid]
	return not live or (s ~= nil and t < s.LockUntil)
end

local foundHandler: ((any, number, number) -> ())? = nil

-- MatchService registers what happens when the geode rock is crushed (finishRound).
function RockService.onFound(fn: (any, number, number) -> ())
	foundHandler = fn
end

local function playerOf(uid: number): Player?
	return Players:GetPlayerByUserId(uid)
end

-- Rubble storage left for a member, straight from the profile (sales change it at any time), and the member's
-- basket and nest tray sizes from the upgrade levels (ProgressConfig). MatchService calls this for every member
-- right after the round core is made, and every action and scheduler step refreshes it.
function RockService.refreshSpace(m: any, uid: number)
	local p = playerOf(uid)
	local data = p and Profiles.get(p)
	if data and m.Core then
		m.Core:setSpace(uid, Profiles.capacity(data) - Profiles.rubbleTotal(data))
		local help = RockService.helperOf(m, uid)
		m.Core:setCaps(uid, ProgressConfig.carry(data.BasketLevel) + (if help then help.Carry else 0), ProgressConfig.queue(data.NestLevel))
		m.Core:setHelper(uid, if help then help.Rate else 0)
	end
end

-- The pet helper step of a member for this round (shared/HuntFun.Helper), decided once per round from the pet that
-- follows them (pets cannot be changed during a hunt). None in the practice round, for bots or without a found pet.
function RockService.helperOf(m: any, uid: number): HuntFun.HelperStep?
	if m.HelperRound ~= m.Round then
		m.HelperRound = m.Round
		m.Helpers = {}
	end
	local cached = m.Helpers[uid]
	if cached ~= nil then
		return if cached == false then nil else cached
	end
	local p = playerOf(uid)
	local data = p and Profiles.get(p)
	if not data then
		return nil -- not cached: a profile still loading gets its helper on a later step
	end
	local step: HuntFun.HelperStep? = nil
	if not m.Tutorial then
		local pet, power = Profiles.huntHelper(data)
		step = if pet then HuntFun.helperStep(power) else nil
	end
	m.Helpers[uid] = step or false
	return step
end

-- Surprise eggs (shared/HuntFun.Surprise): one prize per ordinary egg, paid at once, plus a Lucky Meter point every
-- EggsPerMeter-th egg. Adds what to show to `out`.
local function surprise(m: any, p: Player, data: any, tierId: string, out: { HuntFun.Surprise })
	if not HuntFun.Surprise.Enabled or m.Tutorial then
		return
	end
	local s = HuntFun.surprise(surpriseRng, tierId)
	if s.Kind == "Coins" or s.Kind == "Jackpot" then
		data.Cash += s.Amount
	elseif s.Kind == "Xp" then
		if RockService.onPetXp then
			RockService.onPetXp(p, s.Amount)
		end
	end
	table.insert(out, s)
	local perks = EggPerks.sanitize(data.EggPerks)
	data.EggPerks = perks
	local count, tick = HuntFun.meterTick(perks.HuntEggs)
	perks.HuntEggs = count
	if tick and not EggPerks.full(perks.Meter) then
		perks.Meter = math.min(perks.Meter + 1, EggPerks.Meter.Need)
		table.insert(out, { Kind = "Meter", Amount = 1 })
	end
end

-- Entitlement: the tool / machine in a round must be one the profile owns and has equipped.
local function syncEntitlements(m: any, player: Player)
	local core = m.Core
	local mem = core.Members[player.UserId]
	local data = Profiles.get(player)
	if not mem or not data then
		return
	end
	local tool = data.EquippedHandheld
	if type(tool) == "string" and data.EquipmentOwned[tool] and mem.Tool ~= tool then
		core:setTool(player.UserId, tool)
	end
	if mem.Machine and not data.EquipmentOwned[mem.Machine] then
		core:setMachine(player.UserId, nil)
	end
end

local function reply(m: any, player: Player, action: string, ok: boolean, reason: string?, extra: { [string]: any }?)
	if reason == "TooFast" or reason == "StaleRound" then
		return -- silent: normal for held input and for requests that crossed a round change
	end
	local t = os.clock()
	if t - (lastReply[player] or 0) < REPLY_GAP then
		return
	end
	lastReply[player] = t
	local payload: { [string]: any } = { Round = m.Round, Action = action, Ok = ok, Reason = reason }
	if extra then
		for k, v in extra do
			payload[k] = v
		end
	end
	Net.event("MatchEvent"):FireClient(player, "RockReply", payload)
end

-- Pickup line of sight (SightRules, pure): a ray from the root part up to the head (so a head pushed into a wall is
-- caught), then from the head to just before the rock's shell. Characters,
-- decor (CameraIgnore), non-collidable and see-through parts are walked through, so only real world geometry refuses.
-- An arena with no geometry in the way passes. A cast that errors refuses the pick (fails closed) and warns once, so a
-- broken check shows up in the server log instead of quietly letting picks through walls.
local sightWarned = false
local function hasSight(m: any, char: Model, root: BasePart, rockLocal: Vector3, rockSize: number): boolean
	local head = char:FindFirstChild("Head") :: BasePart?
	local eye = SightRules.eye(root.Position, if head then head.Position else nil)
	local target = SightRules.target(eye, m.Arena.Center + rockLocal, rockSize)
	local skip: { Instance } = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(skip, p.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = skip
	params.IgnoreWater = true
	local ok, res = pcall(SightRules.clearFrom, root.Position, eye, target, function(origin: Vector3, dir: Vector3): SightRules.Hit?
		local hit = workspace:Raycast(origin, dir, params)
		if not hit then
			return nil
		end
		local inst = hit.Instance
		return {
			Distance = hit.Distance,
			Part = {
				CanCollide = inst.CanCollide,
				CameraIgnore = inst:GetAttribute("CameraIgnore") == true,
				Character = false,
				Transparency = inst.Transparency,
			},
		}
	end)
	if not ok then
		if not sightWarned then
			sightWarned = true
			warn("[RockService] line-of-sight check failed, pickup refused:", res)
		end
		return false
	end
	return res == true
end

-- Applies finished rocks to the profiles. Hits need nothing here (the event stream carries them).
function RockService.apply(m: any, results: { any })
	local core = m.Core
	local tier = Config.Tiers[core.Tier]
	-- Material discoveries from this batch, per player: told once at the end (a fast machine can finish
	-- many rocks in one step; the client never gets one message per rock).
	local news: { [number]: { string } } = {}
	local pops: { [number]: { HuntFun.Surprise } } = {} -- surprise eggs per player, sent once per batch
	-- One Profiles.changed per player per batch (it fans out to every listener), not one per egg; the profile is
	-- marked dirty all the same, so nothing is lost from the save.
	local touched: { [Player]: boolean } = {}
	local found: any = nil
	for _, r in results do
		if r.Kind == "Cracked" then
			local p = playerOf(r.UserId)
			local data = p and Profiles.get(p)
			if data then
				data.RubbleByTier[tier.Id] = (data.RubbleByTier[tier.Id] or 0) + 1
				HuntLedger.crushed(m.Ledger, r.UserId, true)
				data.Stats.RocksCracked += 1
				if RockService.onCracked then
					RockService.onCracked(p :: Player, false) -- the pets following them earn hunt XP (PvpService)
				end
				-- The material is decided by the core (Materials.pick) and only counted here, for the player who
				-- finished the rock; the key makes a repeated completion of the same rock a no-op.
				local counted, isNew = Profiles.recordMaterial(p :: Player, m.Key .. ":" .. m.Round .. ":" .. r.RockId, r.Material)
				if counted then
					if isNew then
						news[r.UserId] = news[r.UserId] or {}
						table.insert(news[r.UserId], r.Material)
					end
				end
				pops[r.UserId] = pops[r.UserId] or {}
				surprise(m, p :: Player, data, tier.Id, pops[r.UserId])
				touched[p :: Player] = true
				Profiles.onboard(p :: Player, "Cracked")
				EggEvents.cracked(m, r.UserId) -- maybe speed boots
			end
		elseif r.Kind == "Found" and found == nil then
			found = r -- handled after the loop, so the rest of the batch is still credited
		end
	end
	for p in touched do
		Profiles.changed(p, true)
	end
	-- One award per round, whatever path reports it (a late duplicate result is ignored).
	if found and m.FoundRound ~= m.Round then
		m.FoundRound = m.Round
		-- The finder's pet egg is an egg they finished too: the results (core Cracked) count it, so the quest stat does.
		local fp = playerOf(found.UserId)
		local fdata = fp and Profiles.get(fp)
		if fdata then
			fdata.Stats.RocksCracked += 1
			if RockService.onCracked then
				RockService.onCracked(fp :: Player, true)
			end
			Profiles.changed(fp :: Player, true)
		end
		HuntLedger.crushed(m.Ledger, found.UserId, false)
		RockService.flush(m)
		if foundHandler then
			foundHandler(m, found.UserId, found.RockId)
		end
	end
	for uid, list in pops do
		local p = playerOf(uid)
		local data = p and Profiles.get(p)
		if p and data and #list > 0 then
			Net.event("MatchEvent"):FireClient(p, "Surprise", { Round = m.Round, List = list, Meter = data.EggPerks.Meter, MeterNeed = EggPerks.Meter.Need, MeterEggs = data.EggPerks.HuntEggs, EggsPerMeter = HuntFun.Surprise.EggsPerMeter })
		end
	end
	for uid, list in news do
		local p = playerOf(uid)
		if p then
			Net.event("MatchEvent"):FireClient(p, "MaterialFound", { Round = m.Round, New = list })
		end
	end
end

-- One client intent. `m` is the caller's match (MatchService looked it up from its own tables).
function RockService.action(m: any, player: Player, action: any, roundId: any, rockId: any)
	if type(action) ~= "string" or not ACTIONS[action] or type(roundId) ~= "number" then
		return
	end
	local t = os.clock()
	if t - (lastAny[player] or 0) < MIN_GAP then
		return
	end
	lastAny[player] = t
	local core = m.Core
	if not core or roundId ~= m.Round or m.Phase ~= "Searching" or not m.Present[player.UserId] then
		return
	end
	local uid = player.UserId
	if action == "ToggleMachine" then
		if t - (lastToggle[player] or 0) < TOGGLE_GAP then
			return
		end
		lastToggle[player] = t
		local mem = core.Members[uid]
		if mem and mem.Active and mem.Machine then
			core:setMachineRunning(uid, not mem.Running, t)
		end
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then
		return
	end
	if motionLocked(uid, root.Position, hum.WalkSpeed, t) then
		return -- just teleported: ignored for a moment (Config.Motion); silent like other dropped input
	end
	local pos = root.Position - m.Arena.Center
	RockService.refreshSpace(m, uid)
	syncEntitlements(m, player)
	if action == "Pickup" then
		-- Line of sight only for a request the core would otherwise accept on range: a rock that is still in the
		-- pile (a taken rock keeps reporting Gone) and within reach of the player. The pick itself stays atomic in the core.
		if type(rockId) == "number" and core.Rocks[rockId] then
			local rl = core.Pile:localPosition(rockId)
			if rl and Vector2.new(rl.X - pos.X, rl.Z - pos.Z).Magnitude <= Config.Carry.PickupRange + core.Pile.RockSize * 0.5 then
				if Config.Carry.SightCheck ~= false and not hasSight(m, char :: Model, root, rl, core.Pile.RockSize) then
					reply(m, player, action, false, "NoSight")
					return
				end
			end
		end
		local err = core:pickup(uid, roundId, rockId, pos, t)
		if err then
			reply(m, player, action, false, err)
		else
			Profiles.onboard(player, "PickedUp")
		end
	elseif action == "Deposit" then
		local res, err = core:deposit(uid, roundId, pos, t)
		if res then
			Profiles.onboard(player, "Deposited")
			reply(m, player, action, true, nil, { Moved = #res.Moved, Left = res.Left, Queue = res.Queue })
		else
			reply(m, player, action, false, err)
		end
	elseif action == "Crush" then
		-- Machines first, up to this instant, so a hit never jumps ahead of a rock that finished earlier.
		RockService.apply(m, core:tickMachines(t))
		if m.Phase ~= "Searching" or core.Phase ~= "Searching" then
			return
		end
		local results, err = core:crush(uid, roundId, pos, t)
		if err then
			reply(m, player, action, false, err)
			if err == "StorageFull" and t - (m.FullWarned[uid] or 0) > 4 then
				m.FullWarned[uid] = t
				Net.event("Toast"):FireClient(player, "Candy bag full! Sell candy at the candy stand.", "warn")
			end
		else
			RockService.apply(m, results)
		end
	end
end

-- Scheduler step for one Searching match: machines, storage refresh, batched replication.
function RockService.step(m: any, t: number)
	local core = m.Core
	for uid in m.Present do
		RockService.refreshSpace(m, uid)
		sampleMotion(uid, t)
	end
	RockService.apply(m, core:tickMachines(t))
	if m.Phase == "Searching" and t - m.LastFlush >= 0.1 then
		m.LastFlush = t
		RockService.flush(m)
	end
end

-- Sends the batched rock events (ids only) with a fresh station snapshot and the shared counters.
function RockService.flush(m: any)
	local core = m.Core
	if not core then
		return
	end
	local ev = core:drainEvents()
	if #ev == 0 then
		return
	end
	local removed = {}
	for _, e in ev do
		if e.Kind == "Pick" then
			table.insert(removed, { e.Id, e.UserId }) -- legacy shape for the pre-V3 client view
		end
	end
	local payload = {
		Round = m.Round,
		Ev = ev,
		Removed = removed,
		Hits = {},
		Res = {},
		Stations = core:stationViews(os.clock()),
		Counts = core:counters(),
	}
	local remote = Net.event("MatchEvent")
	for uid in m.Present do
		local p = playerOf(uid)
		if p then
			remote:FireClient(p, "Rocks", payload)
		end
	end
end

-- A member leaves (return to lobby, disconnect): everything unresolved they hold goes back to the pile.
function RockService.leave(m: any, uid: number)
	motion[uid] = nil
	if m.Core then
		RockService.apply(m, m.Core:removeMember(uid, os.clock()))
		RockService.flush(m)
	end
end

-- A character respawn drops the basket back on the pile (the tray stays on the table).
function RockService.characterReset(m: any, uid: number)
	RockService.resetMotion(uid)
	if m.Core and m.Phase == "Searching" then
		if m.Core:dropCarried(uid) > 0 then
			RockService.flush(m)
		end
	end
end

-- The pile + station part of the Init / resync payload (ids and states only).
function RockService.initFields(m: any): { [string]: any }
	local core = m.Core
	local tables = {}
	for i = 1, Config.Station.Count do
		local cf = m.Arena.Tables and m.Arena.Tables[i] and m.Arena.Tables[i].PrimaryPart and m.Arena.Tables[i].PrimaryPart.CFrame
		local owner = 0
		for uid, mem in core.Members do
			if mem.Active and mem.Index == i then
				owner = uid
			end
		end
		table.insert(tables, { Index = i, Position = if cf then cf.Position else nil, Owner = owner })
	end
	return {
		Rocks = core.Total,
		MaxHp = core.MaxHp,
		Removed = core:removedIds(),
		Stacks = core.Pile:stacks(),
		Stations = core:stationViews(os.clock()),
		Tables = tables,
		Counts = core:counters(),
	}
end

function RockService.forget(player: Player)
	lastAny[player] = nil
	lastToggle[player] = nil
	lastReply[player] = nil
	motion[player.UserId] = nil
end

return RockService
