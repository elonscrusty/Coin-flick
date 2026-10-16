--!strict
-- Pure rules of the V3 loop for ONE round (no Roblox services, so tests drive it directly):
--   shared pile -> pickup into a basket -> deposit at your own crushing table -> crush there.
-- The server owns one RoundRocks per round (src/server/RockService.luau). Clients never see
-- which rock is the target; they only get opaque rock ids, states, queues and counters.
--
-- Every rock has exactly one record and one state:
--   InPile -> Carried (basket) -> Queued (station tray) -> Processing (on the plate)
--          -> ResolvedOrdinary | ResolvedGeode
-- All transitions happen inside the validated operations below, so a rock can never exist in two
-- places, be claimed twice or be resolved twice. Times are `now` seconds on one monotonic clock
-- chosen by the caller (the server passes os.clock()). Positions are relative to the pile centre
-- and are read by the server, never sent by clients. docs/V3_LOOP.md has the full protocol.

local Config = require(script.Parent.Config)
local Pile = require(script.Parent.Pile)
local Materials = require(script.Parent.Materials)

local RoundRocks = {}
RoundRocks.__index = RoundRocks

export type Rock = {
	Id: number, -- opaque, round-scoped (the pile layout index; carries no information about the target)
	State: string, -- InPile | Carried | Queued | Processing | ResolvedOrdinary | ResolvedGeode
	Carrier: number?, -- user id while Carried
	Station: number?, -- owner user id while Queued / Processing
	Hp: number, -- hit points left (full whenever the rock is not being processed)
}

export type Member = {
	UserId: number,
	Index: number, -- station index 1..Config.Station.Count
	Tool: string,
	HelpRate: number, -- pet helper crack speed multiplier (1 = no helper; shared/HuntFun.Helper)
	Active: boolean,
	Basket: { number },
	Queue: { number },
	CarryCap: number, -- basket size for this member (basket upgrades; Config.Carry.Capacity to start)
	QueueCap: number, -- nest tray size for this member (nest upgrades; Config.Station.QueueCapacity to start)
	Current: number?, -- the rock on the plate
	Reserved: boolean, -- storage for one ordinary result is held for Current
	Machine: string?,
	Running: boolean,
	Complete: number?, -- machine: when Current finishes
	Remaining: number?, -- machine paused: seconds still needed
	ReadyAt: number, -- machine: when the previous rock finished (keeps the cadence exact)
	NextPick: number,
	NextDeposit: number,
	NextHit: number,
	Space: number, -- rubble storage left (the server refreshes it from the profile)
	Cracked: number,
	Rubble: number,
}

export type Event = {
	Kind: string, -- Pick | Return | Move | Deposit | Start | Hit | Done | Found
	UserId: number?,
	Id: number?,
	Ids: { number }?,
	Col: number?,
	From: number?, -- Move: the column the rock left
	Progress: number?,
	Duration: number?,
	Mat: string?, -- Done only: the material of the rock that just finished (told after completion, never before)
}

export type Result = {
	UserId: number,
	RockId: number,
	Kind: string, -- Hit | Cracked | Found
	Progress: number?,
	Material: string?, -- Cracked only: Materials.pick for this rock in this round
}

export type Core = typeof(setmetatable(
	{} :: {
		MatchKey: string,
		RoundId: number,
		Tier: string,
		Seed: number,
		Pile: Pile.Pile,
		Rocks: { Rock },
		Total: number,
		MaxHp: number,
		TargetId: number?, -- server-only, never rerolled
		MatSalt: number, -- server-only, fixes every rock's material for the round
		TutorialBreak: number?, -- practice only: the geode is the Nth rock crushed
		Practice: boolean,
		Broken: number, -- rocks resolved (crushed to completion)
		Phase: string,
		Winner: number?,
		Members: { [number]: Member },
		Order: { number }, -- user ids by station index
		Events: { Event },
	},
	RoundRocks
))

export type Options = {
	MatchKey: string,
	RoundId: number,
	Tier: string,
	Seed: number, -- public layout seed
	TargetRng: Random, -- server-only
	-- Carry / Queue: this member's basket and nest tray sizes (upgrades); omitted = the Config sizes.
	Members: { { UserId: number, Tool: string, Machine: string?, Station: number, Carry: number?, Queue: number? } },
	Tutorial: boolean?,
}

local STATE_IN_PILE, STATE_CARRIED, STATE_QUEUED, STATE_PROCESSING = "InPile", "Carried", "Queued", "Processing"
local STATE_ORDINARY, STATE_GEODE = "ResolvedOrdinary", "ResolvedGeode"
RoundRocks.States = { STATE_IN_PILE, STATE_CARRIED, STATE_QUEUED, STATE_PROCESSING, STATE_ORDINARY, STATE_GEODE }

-- Upgrade sizes are whole numbers in a sane range; anything else falls back to the base size.
local MAX_CAP = 64
local function capOf(v: any, default: number): number
	if type(v) ~= "number" or v ~= v or v < 1 then
		return default
	end
	return math.min(math.floor(v), MAX_CAP)
end

-- Station table centre relative to the pile centre: four evenly spaced on one circle, so every
-- table is the same distance from the pile and from its neighbours.
function RoundRocks.stationAngle(index: number): number
	return (index - 0.5) / Config.Station.Count * math.pi * 2
end

function RoundRocks.stationPosition(index: number): Vector3
	local a = RoundRocks.stationAngle(index)
	return Vector3.new(math.cos(a) * Config.Station.Radius, 0, math.sin(a) * Config.Station.Radius)
end

-- Seconds one rock takes in a machine.
function RoundRocks.machineSeconds(machineId: string): number
	local cfg = Config.Machines[machineId]
	return cfg.BatchSeconds / cfg.RocksPerBatch
end

function RoundRocks.new(opts: Options): Core
	local tier = Config.Tiers[opts.Tier]
	assert(tier, "unknown tier")
	local count = if opts.Tutorial then Config.Tutorial.Rocks else tier.Rocks
	local pile = Pile.new(count, tier.RockSize, tier.Radius, opts.Seed)
	local maxHp = if opts.Tutorial then 1 else tier.HP
	local rocks: { Rock } = {}
	for id = 1, count do
		rocks[id] = { Id = id, State = STATE_IN_PILE, Carrier = nil, Station = nil, Hp = maxHp }
	end
	local members: { [number]: Member } = {}
	local order: { number } = {}
	for _, m in opts.Members do
		-- Practice rounds never run machines (they would skip the lesson).
		local machine = if not opts.Tutorial and m.Machine and Config.Machines[m.Machine] then m.Machine else nil
		members[m.UserId] = {
			UserId = m.UserId,
			Index = m.Station,
			Tool = m.Tool,
			HelpRate = 1,
			Active = true,
			Basket = {},
			Queue = {},
			CarryCap = capOf(m.Carry, Config.Carry.Capacity),
			QueueCap = capOf(m.Queue, Config.Station.QueueCapacity),
			Current = nil,
			Reserved = false,
			Machine = machine,
			Running = true,
			Complete = nil,
			Remaining = nil,
			ReadyAt = -math.huge,
			NextPick = -math.huge,
			NextDeposit = -math.huge,
			NextHit = -math.huge,
			Space = math.huge,
			Cracked = 0,
			Rubble = 0,
		}
		table.insert(order, m.UserId)
	end
	table.sort(order, function(a, b)
		return members[a].Index < members[b].Index
	end)
	local self = setmetatable({
		MatchKey = opts.MatchKey,
		RoundId = opts.RoundId,
		Tier = opts.Tier,
		Seed = opts.Seed,
		Pile = pile,
		Rocks = rocks,
		Total = count,
		MaxHp = maxHp,
		TargetId = nil :: number?,
		MatSalt = 0,
		TutorialBreak = nil :: number?,
		Practice = opts.Tutorial == true,
		Broken = 0,
		Phase = "Waiting",
		Winner = nil :: number?,
		Members = members,
		Order = order,
		Events = {},
	}, RoundRocks)
	if opts.Tutorial then
		-- Practice only: the geode is one of the first few rocks CRUSHED (picking up does not count).
		self.TutorialBreak = opts.TargetRng:NextInteger(math.min(Config.Tutorial.TargetFrom, count), math.min(Config.Tutorial.TargetWithin, count))
	else
		-- Fixed for the whole round, chosen uniformly from every record. Never rerolled.
		self.TargetId = opts.TargetRng:NextInteger(1, count)
	end
	-- Server-only salt for Materials.pick, drawn after the target so the target sequence is unchanged.
	self.MatSalt = opts.TargetRng:NextInteger(1, 2 ^ 30)
	return self
end

-- Helpers ------------------------------------------------------------------------------------

local function emit(self: Core, ev: Event)
	table.insert(self.Events, ev)
end

local function validId(self: Core, id: any): boolean
	return type(id) == "number" and id == id and id % 1 == 0 and id >= 1 and id <= self.Total
end

local function flat(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function validPos(pos: any): boolean
	return typeof(pos) == "Vector3" and pos.X == pos.X and pos.Z == pos.Z and math.abs(pos.X) < 1e6 and math.abs(pos.Z) < 1e6
end

-- Round, phase and membership gate shared by every action.
local function gate(self: Core, uid: number, roundId: any): (Member?, string?)
	if roundId ~= self.RoundId then
		return nil, "StaleRound"
	end
	if self.Phase ~= "Searching" then
		return nil, "NotSearching"
	end
	local m = self.Members[uid]
	if not m or not m.Active then
		return nil, "NotMember"
	end
	return m, nil
end

local function available(m: Member): number
	return m.Space - (if m.Reserved then 1 else 0)
end

function RoundRocks.setPhase(self: Core, phase: string)
	self.Phase = phase
	if phase ~= "Searching" then
		-- Round over (found, ended): every pending machine job stops and pays nothing.
		for _, m in self.Members do
			m.Complete = nil
			m.Remaining = nil
		end
	end
end

function RoundRocks.setTool(self: Core, userId: number, tool: string)
	local m = self.Members[userId]
	if m and Config.Handhelds[tool] then
		m.Tool = tool
	end
end

-- The pet helper's crack speed bonus for a member (share, 0 = none; the server reads it from the helper pet).
function RoundRocks.setHelper(self: Core, userId: number, rateBonus: number)
	local m = self.Members[userId]
	if m and rateBonus == rateBonus then
		m.HelpRate = 1 + math.clamp(rateBonus, 0, 1)
	end
end

function RoundRocks.setSpace(self: Core, userId: number, space: number)
	local m = self.Members[userId]
	if m and space == space then
		m.Space = space
	end
end

-- A member's basket and nest tray sizes (the server reads them from the profile's upgrade levels). A smaller
-- size never takes rocks away: the basket and tray just accept no more until they are below it.
function RoundRocks.setCaps(self: Core, userId: number, carry: any, queue: any)
	local m = self.Members[userId]
	if m then
		m.CarryCap = capOf(carry, m.CarryCap)
		m.QueueCap = capOf(queue, m.QueueCap)
	end
end

function RoundRocks.activeCount(self: Core): number
	local n = 0
	for _, m in self.Members do
		if m.Active then
			n += 1
		end
	end
	return n
end

-- Counters. Unopened = every unresolved rock (pile, baskets, trays, plates); it only drops when a
-- rock is crushed to completion. Pile = rocks lying in the pile. Carrying = this member's basket.
-- Rubble (ordinary results in storage) is NOT here: it lives in the profile.
function RoundRocks.counters(self: Core, userId: number?): { [string]: number }
	local m = if userId then self.Members[userId] else nil
	return {
		Unopened = self.Total - self.Broken,
		Pile = self.Pile.Remaining,
		Carrying = if m then #m.Basket else 0,
		CarryCapacity = if m then m.CarryCap else Config.Carry.Capacity,
		Queue = if m then #m.Queue else 0, -- tray only; the plate is separate
		OnPlate = if m and m.Current then 1 else 0,
		QueueCapacity = if m then m.QueueCap else Config.Station.QueueCapacity,
	}
end

-- Pickup ---------------------------------------------------------------------------------------

-- Moves one rock from the pile into the member's basket. Returns nil on success or a reason.
function RoundRocks.pickup(self: Core, uid: number, roundId: any, rockId: any, pos: Vector3, now: number): string?
	local m, why = gate(self, uid, roundId)
	if not m then
		return why
	end
	if not validId(self, rockId) or not validPos(pos) then
		return "BadRock"
	end
	local cfg = Config.Carry
	if now < m.NextPick - cfg.PickupTolerance then
		return "TooFast"
	end
	local rock = self.Rocks[rockId :: number]
	if rock.State ~= STATE_IN_PILE then
		return "Gone" -- someone else has it (or it is resolved): never two owners
	end
	if #m.Basket >= m.CarryCap then
		return "BasketFull"
	end
	if not self.Pile:isPickable(rock.Id, cfg.ReachLevels) then
		return "Unreachable"
	end
	local rp = self.Pile:localPosition(rock.Id) :: Vector3
	if flat(rp, pos) > cfg.PickupRange + self.Pile.RockSize * 0.5 then
		return "TooFar"
	end
	if pos.Y ~= pos.Y or math.abs(rp.Y - pos.Y) > cfg.PickupHeight then
		return "TooFar" -- flying or perched far above (or below) the mound
	end
	m.NextPick = math.max(now, m.NextPick) + cfg.PickupInterval
	self.Pile:remove(rock.Id)
	rock.State = STATE_CARRIED
	rock.Carrier = uid
	rock.Station = nil
	table.insert(m.Basket, rock.Id)
	emit(self, { Kind = "Pick", UserId = uid, Id = rock.Id })
	return nil
end

-- Deposit -------------------------------------------------------------------------------------

export type DepositResult = { Moved: { number }, Left: number, Queue: number }

-- Moves the basket into the member's OWN station tray, in basket order, as many as fit. The rest
-- stays in the basket (Left). Returns (result, nil) or (nil, reason).
function RoundRocks.deposit(self: Core, uid: number, roundId: any, pos: Vector3, now: number): (DepositResult?, string?)
	local m, why = gate(self, uid, roundId)
	if not m then
		return nil, why
	end
	if not validPos(pos) then
		return nil, "BadPosition"
	end
	local cfg = Config.Station
	if flat(RoundRocks.stationPosition(m.Index), pos) > cfg.DepositRange then
		return nil, "TooFar"
	end
	if #m.Basket == 0 then
		return nil, "BasketEmpty"
	end
	if now < m.NextDeposit - cfg.DepositTolerance then
		return nil, "TooFast"
	end
	local free = m.QueueCap - #m.Queue
	if free <= 0 then
		return nil, "QueueFull"
	end
	m.NextDeposit = math.max(now, m.NextDeposit) + cfg.DepositInterval
	local moved: { number } = {}
	while #moved < free and #m.Basket > 0 do
		local id = table.remove(m.Basket, 1) :: number
		local rock = self.Rocks[id]
		rock.State = STATE_QUEUED
		rock.Carrier = nil
		rock.Station = uid
		table.insert(m.Queue, id)
		table.insert(moved, id)
	end
	emit(self, { Kind = "Deposit", UserId = uid, Ids = table.clone(moved) })
	return { Moved = moved, Left = #m.Basket, Queue = #m.Queue }, nil
end

-- Processing ----------------------------------------------------------------------------------

-- Moves the next queued rock onto the plate. Storage for one ordinary result is reserved FIRST,
-- for every rock alike (the geode included): with no room nothing starts, so a full bag can
-- never single out the target. Returns (true) or (false, reason).
local function tryStart(self: Core, m: Member, duration: number?): (boolean, string?)
	if m.Current then
		return true, nil
	end
	if #m.Queue == 0 then
		return false, "QueueEmpty"
	end
	if available(m) < 1 then
		return false, "StorageFull"
	end
	local id = table.remove(m.Queue, 1) :: number
	local rock = self.Rocks[id]
	rock.State = STATE_PROCESSING
	rock.Hp = self.MaxHp
	m.Current = id
	m.Reserved = true
	m.Complete = nil
	m.Remaining = nil
	emit(self, { Kind = "Start", UserId = m.UserId, Id = id, Duration = duration })
	return true, nil
end

-- The one place a rock is finished (hand hit or machine). Returns true when it was the target:
-- the round stops at once and that member wins.
local function finishRock(self: Core, m: Member, id: number, results: { Result }): boolean
	local rock = self.Rocks[id]
	rock.Hp = 0
	m.Current = nil
	m.Complete = nil
	m.Remaining = nil
	self.Broken += 1
	m.Cracked += 1
	local isTarget = id == self.TargetId or (self.TutorialBreak ~= nil and self.Broken == self.TutorialBreak)
	if isTarget then
		rock.State = STATE_GEODE
		self.TargetId = id
		self.Winner = m.UserId
		m.Reserved = false -- a geode releases the reservation and pays no rubble
		emit(self, { Kind = "Found", UserId = m.UserId, Id = id })
		table.insert(results, { UserId = m.UserId, RockId = id, Kind = "Found" })
		RoundRocks.setPhase(self, "RewardPending")
		return true
	end
	rock.State = STATE_ORDINARY
	m.Reserved = false -- consumed by the rubble below
	m.Rubble += 1
	m.Space -= 1
	local material = Materials.pick(self.MatSalt, self.RoundId, id)
	emit(self, { Kind = "Done", UserId = m.UserId, Id = id, Mat = material })
	table.insert(results, { UserId = m.UserId, RockId = id, Kind = "Cracked", Material = material })
	return false
end

local function isAutomatic(m: Member): boolean
	return m.Machine ~= nil and m.Running
end

local function progressOf(self: Core, m: Member, now: number?): number
	local id = m.Current
	if not id then
		return 0
	end
	if m.Complete and m.Machine and now then
		local dur = RoundRocks.machineSeconds(m.Machine)
		return math.clamp(1 - (m.Complete - now) / dur, 0, 1)
	end
	return math.clamp(1 - self.Rocks[id].Hp / self.MaxHp, 0, 1)
end

-- One hand-tool hit at the member's OWN station. A station with a running machine ignores hits.
-- The first hit puts the next queued rock on the plate. Returns (results, nil) or ({}, reason).
function RoundRocks.crush(self: Core, uid: number, roundId: any, pos: Vector3, now: number): ({ Result }, string?)
	local none: { Result } = {}
	local m, why = gate(self, uid, roundId)
	if not m then
		return none, why
	end
	if not validPos(pos) then
		return none, "BadPosition"
	end
	if isAutomatic(m) then
		return none, "Automatic"
	end
	if flat(RoundRocks.stationPosition(m.Index), pos) > Config.Station.CrushRange then
		return none, "TooFar"
	end
	local tool = Config.Handhelds[m.Tool] or Config.Handhelds.Hammer
	local step = 1 / (tool.Rate * m.HelpRate)
	if now < m.NextHit - Config.Match.CadenceTolerance then
		return none, "TooFast"
	end
	-- A valid hit first catches every machine up to `now`: a rock another station finished earlier is
	-- resolved (and paid) before this hit, and the hit never lands once a machine has found the geode.
	local results: { Result } = RoundRocks.tickMachines(self, now)
	if self.Phase ~= "Searching" then
		return results, nil
	end
	local ok, reason = tryStart(self, m)
	if not ok then
		return results, if #results == 0 then reason else nil
	end
	m.NextHit = math.max(now, m.NextHit) + step
	local id = m.Current :: number
	local rock = self.Rocks[id]
	rock.Hp -= tool.Damage
	if rock.Hp > 0 then
		local p = progressOf(self, m, nil)
		emit(self, { Kind = "Hit", UserId = uid, Id = id, Progress = p })
		table.insert(results, { UserId = uid, RockId = id, Kind = "Hit", Progress = p })
		return results, nil
	end
	finishRock(self, m, id, results)
	return results, nil
end

-- Machines ------------------------------------------------------------------------------------
-- One scheduler step (tickMachines) drives every machine in the round. A machine only ever
-- touches ITS station: it takes rocks from that station's queue, one at a time, and never reads
-- the pile or another station.

function RoundRocks.setMachine(self: Core, userId: number, machine: string?)
	local m = self.Members[userId]
	if not m or not m.Active or self.Practice then
		return
	end
	if machine ~= nil and not Config.Machines[machine] then
		return
	end
	m.Machine = machine
	m.Complete = nil -- a swap re-times the rock on the plate from scratch (no free progress)
	m.Remaining = nil
end

function RoundRocks.setMachineRunning(self: Core, userId: number, running: boolean, now: number)
	local m = self.Members[userId]
	if not m or not m.Machine or m.Running == running then
		return
	end
	if not running and m.Complete then
		m.Remaining = math.max(0, m.Complete - now)
		m.Complete = nil
	end
	m.Running = running
	m.ReadyAt = now -- no back-dated start after a pause
end

-- "None" | "Running" | "Paused" | "Full" (Full = no storage for another ordinary result).
function RoundRocks.machineState(self: Core, userId: number): string
	local m = self.Members[userId]
	if not m or not m.Machine then
		return "None"
	end
	if not m.Running then
		return "Paused"
	end
	if not m.Current and available(m) < 1 then
		return "Full"
	end
	return "Running"
end

-- Puts the next rock on a machine plate and times it. `from` = when the previous rock finished.
local function arm(self: Core, m: Member, now: number, from: number)
	if not m.Active or not m.Machine or not m.Running then
		return
	end
	local dur = RoundRocks.machineSeconds(m.Machine)
	if not m.Current then
		local ok = tryStart(self, m, dur)
		if not ok then
			return
		end
		local startAt = if now - from <= 0.1 then from else now
		m.Complete = startAt + dur
	elseif not m.Complete then
		-- a rock put on the plate by hand, or resumed after a pause
		m.Complete = now + (m.Remaining or dur)
		m.Remaining = nil
	end
end

-- Advances every machine to `now`. Rocks finish in completion order (ties by station index), so
-- two machines finishing together still give one winner. Returns Cracked / Found results.
function RoundRocks.tickMachines(self: Core, now: number): { Result }
	local results: { Result } = {}
	if self.Phase ~= "Searching" then
		return results
	end
	for _, uid in self.Order do
		local m = self.Members[uid]
		if m.Machine and m.Active and m.Running then
			arm(self, m, now, m.ReadyAt)
		end
	end
	local steps: { [number]: number } = {}
	while self.Phase == "Searching" do
		local pick: Member? = nil
		for _, uid in self.Order do
			local m = self.Members[uid]
			local c = m.Complete
			if c and c <= now and m.Active and m.Running and (steps[uid] or 0) < Config.Station.MaxMachineSteps then
				if not pick or c < (pick.Complete :: number) then
					pick = m
				end
			end
		end
		if not pick then
			break
		end
		local m = pick :: Member
		steps[m.UserId] = (steps[m.UserId] or 0) + 1
		local at = m.Complete :: number
		m.ReadyAt = at
		if finishRock(self, m, m.Current :: number, results) then
			break
		end
		arm(self, m, now, at)
	end
	return results
end

-- Leaving, reset, disconnect --------------------------------------------------------------------

-- Returns one rock to the pile near the station. Its damage is reset, so a returned rock is
-- indistinguishable from an untouched one.
local function returnRock(self: Core, id: number, near: Vector2, uid: number)
	local rock = self.Rocks[id]
	if rock.State == STATE_ORDINARY or rock.State == STATE_GEODE or rock.State == STATE_IN_PILE then
		return
	end
	rock.State = STATE_IN_PILE
	rock.Carrier = nil
	rock.Station = nil
	rock.Hp = self.MaxHp
	local col = self.Pile:restore(id, near, Config.Carry.ReachLevels)
	emit(self, { Kind = "Return", UserId = uid, Id = id, Col = col })
end

-- Overtime (EggConfig.Overtime, Studio 2026-10-15): the pet egg glows gold at 3:00 so the race can end, but a glowing
-- egg deep inside the mound could not be picked up, and the hunt ran on past 0:00. This lifts a pile rock that is not
-- pickable onto a reachable edge column (the same placement as a returned rock) and tells clients with a "Move"
-- event. Called only together with the glow, which names the egg anyway. Returns true when it moved.
function RoundRocks.surface(self: Core, id: number): boolean
	local rock = self.Rocks[id]
	if not rock or rock.State ~= STATE_IN_PILE or self.Pile:isPickable(id, Config.Carry.ReachLevels) then
		return false
	end
	local from = self.Pile:remove(id)
	local col = self.Pile:restore(id, nil, Config.Carry.ReachLevels)
	if not col then
		return false
	end
	emit(self, { Kind = "Move", Id = id, Col = col, From = from })
	return true
end

-- Gives back everything the member holds (plate, tray, basket) to reachable pile positions and
-- frees the reservation. Progress on the plate rock is discarded (it returns at full HP). Rubble
-- already resolved stays with the member. Returns how many rocks went back.
function RoundRocks.resetMember(self: Core, userId: number): number
	local m = self.Members[userId]
	if not m then
		return 0
	end
	local sp = RoundRocks.stationPosition(m.Index)
	local near = Vector2.new(sp.X, sp.Z)
	local n = 0
	if m.Current then
		returnRock(self, m.Current, near, userId)
		n += 1
	end
	for _, id in m.Queue do
		returnRock(self, id, near, userId)
		n += 1
	end
	for _, id in m.Basket do
		returnRock(self, id, near, userId)
		n += 1
	end
	m.Current, m.Reserved, m.Complete, m.Remaining = nil, false, nil, nil
	table.clear(m.Queue)
	table.clear(m.Basket)
	return n
end

-- A character reset drops only the basket (the tray is on the table, not on the avatar).
function RoundRocks.dropCarried(self: Core, userId: number): number
	local m = self.Members[userId]
	if not m or self.Phase ~= "Searching" then
		return 0
	end
	local sp = RoundRocks.stationPosition(m.Index)
	local near = Vector2.new(sp.X, sp.Z)
	local n = #m.Basket
	for _, id in m.Basket do
		returnRock(self, id, near, userId)
	end
	table.clear(m.Basket)
	return n
end

-- Rule: work already due at the moment of leaving counts (machines are caught up to `now` first, so a
-- finished rock or geode is paid to the leaver); anything not yet due goes back to the pile.
-- Returns the machine results from the catch-up (empty without `now`).
function RoundRocks.removeMember(self: Core, userId: number, now: number?): { Result }
	local results: { Result } = {}
	local m = self.Members[userId]
	if not m then
		return results
	end
	if now and self.Phase == "Searching" then
		results = RoundRocks.tickMachines(self, now)
	end
	if self.Phase == "Searching" or self.Phase == "Countdown" or self.Phase == "Waiting" then
		RoundRocks.resetMember(self, userId)
	end
	m.Active = false
	m.Machine = nil
	return results
end

-- Views for replication (ids only, never the target) -------------------------------------------

export type StationView = {
	UserId: number,
	Index: number,
	Basket: { number },
	Queue: { number },
	CarryCap: number, -- this member's basket size (the client's pickup / take hint)
	QueueCap: number, -- this member's nest tray size
	Current: number?,
	Progress: number,
	Machine: string?,
	Tool: string,
	Help: number,
	State: string,
	Cracked: number,
}

function RoundRocks.stationViews(self: Core, now: number?): { StationView }
	local out: { StationView } = {}
	for _, uid in self.Order do
		local m = self.Members[uid]
		if m.Active then
			table.insert(out, {
				UserId = uid,
				Index = m.Index,
				Basket = table.clone(m.Basket),
				Queue = table.clone(m.Queue),
				CarryCap = m.CarryCap,
				QueueCap = m.QueueCap,
				Current = m.Current,
				Progress = progressOf(self, m, now),
				Machine = m.Machine,
				Tool = m.Tool,
				Help = m.HelpRate, -- pet helper crack speed multiplier (the client paces held taps with it)
				State = RoundRocks.machineState(self, uid),
				Cracked = m.Cracked, -- eggs this member finished this round (race bar); says nothing about the pet egg
			})
		end
	end
	return out
end

-- Ids no longer in the pile (carried, queued, on a plate or resolved). Reconnects replay this.
function RoundRocks.removedIds(self: Core): { number }
	local out = {}
	for id, rock in self.Rocks do
		if rock.State ~= STATE_IN_PILE then
			table.insert(out, id)
		end
	end
	table.sort(out)
	return out
end

function RoundRocks.drainEvents(self: Core): { Event }
	local out = self.Events
	self.Events = {}
	return out
end

return RoundRocks
