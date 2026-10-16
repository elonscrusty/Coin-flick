--!strict
-- Local pile and the hunt's contextual action (V3 loop, docs/V3_LOOP.md).
--
-- Pile: rebuilds the server's deterministic layout (Pile + the Init stacks, the same positions the
-- server uses for range checks) and draws ONE Model per collectible rock (twelve silhouettes from
-- GeodeModel.rockShell, picked from the opaque id and the round seed only, so nothing about a rock
-- says whether it hides the geode). Rocks inside the mound are single-part fillers; rocks on the
-- surface are full models. Nothing decorative lies around the base (the arena floor shows through).
-- Every part is anchored and never collides, so the mound cannot trap or launch anyone.
--
-- Targeting: exactly one restrained yellow outline on the pickable rock nearest the avatar
-- (facing preferred), the same id the PICK UP request sends and the server validates.
--
-- Action: one contextual button (Hud) and E / gamepad. `PileView.context()` decides what the button
-- means from the server snapshot (basket, tray, machine, bag), the avatar's position and the rocks in
-- reach, using the same ranges as the server, which still has the last word. Holding repeats at the
-- server cadence (pickup 0.45 s, crush at the tool's rate). The action is latched when the press
-- starts, so finishing a deposit never turns into a crush while the finger is still down.
-- Nothing is ever cracked at the pile.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Pile = require(Shared.Pile)
local EggFall = require(Shared.EggFall)
local GeodeModel = require(Shared.GeodeModel)
local Net = require(Shared.Net)
local State = require(script.Parent.State)
local Anim = require(script.Parent.Anim)
local ToolAnim = require(script.Parent.ToolAnim)
local CarryView = require(script.Parent.CarryView)
local StationView = require(script.Parent.StationView)
local GuideArrow = require(script.Parent.GuideArrow)
local UI = require(script.Parent.ui.UI)
local Audio = require(script.Parent.Audio)
local ActionRules = require(Shared.ActionRules)
local AimResolve = require(Shared.AimResolve)
local HuntFun = require(Shared.HuntFun)
local CameraMode = require(script.Parent.CameraMode)
local CameraGuard = require(script.Parent.CameraGuard)

local player = Players.LocalPlayer
local PileView = {}

local pile: Pile.Pile? = nil
local center = Vector3.zero
local round = 0
local seed = 1
local folder: Folder? = nil
local gritFolder: Folder? = nil
local rocks: { [number]: Model } = {}
local kind: { [number]: number } = {} -- 0 filler, 1 full, 2 full and pickable
local posCache: { [number]: Vector3 } = {}
local selected: number? = nil
local manual: number? = nil -- rock the player tapped (kept while valid and in reach)
local holding = 0
local heldAction: string? = nil
local lastSolid: { Id: string, Arrow: string?, Target: number?, At: number }? = nil -- last stable action (context jitter guard)
local heldCancelled = false -- the current press lost its meaning; ignored until released
local lastSent: { [string]: number } = {}
local highlight: Highlight
local active = false
local hoppers: { BasePart } = {}
local epoch = 0
local autoCache = { Epoch = -1, At = 0, Pos = Vector3.zero, Look = Vector3.zero, Result = nil :: number? }
local selClock = 0
local ctxCache: any = nil
local ctxAt = 0
local aimed = false -- first person: the reticle ray is on a tagged target (a rock, the own table, a sell hopper)
local mouseHolds: { [InputObject]: boolean } = {}

PileView.Selected = Instance.new("BindableEvent")
PileView.Struck = Instance.new("BindableEvent") -- (rockId) a pickup was sent
PileView.Cracked = Instance.new("BindableEvent") -- (rockId, byMe, removedByMachine, removerUserId)
PileView.Claimed = Instance.new("BindableEvent") -- (ownerUserId, rockIds, seconds) a machine started a rock
PileView.Notice = Instance.new("BindableEvent") -- (text, kind) a hint for the toast line

local function settings()
	return State.Profile and State.Profile.Settings or {}
end

local function notice(text: string, k: string?)
	PileView.Notice:Fire(text, k or "info")
end

local function root(): BasePart?
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Pile drawing ---------------------------------------------------------------------------------

-- Where and how big an egg is drawn: the server position plus a small seeded offset (no lattice) and a seeded size.
-- Eggs lie on their side, long axis along the mound's ring (owner video: upright eggs clipped into each other, since a
-- layer is only 0.62 egg sizes tall and the columns are one egg size apart). Lying, an egg is 0.78 x its length tall,
-- about one layer, and its length runs between its ring neighbours. The server only ever sees its own position.
local function placement(id: number): (CFrame, number)
	local p = pile :: Pile.Pile
	local rock = p.Rocks[id]
	local s = p.RockSize
	local pos = (p:localPosition(id) :: Vector3)
	local r = Random.new(seed % 100000 * 131 + id * 17)
	local off = Vector3.new(r:NextNumber(-0.04, 0.04) * s, r:NextNumber(-0.04, 0.02) * s, r:NextNumber(-0.04, 0.04) * s)
	local size = s * math.min(rock.Scale, 1.05) * r:NextNumber(0.7, 0.8)
	local _, _, yaw = GeodeModel.rockLook(id, seed)
	local radial = Vector3.new(pos.X, 0, pos.Z)
	local heading = if radial.Magnitude > 0.2 * s then math.atan2(-radial.X, -radial.Z) else math.rad(yaw)
	-- long axis (the egg's local Y) tangent to the ring, a little seeded play so the rows never look machined
	local lay = CFrame.Angles(0, heading + math.rad(r:NextNumber(-14, 14)), 0) * CFrame.Angles(0, 0, math.rad(90 + r:NextNumber(-10, 10)))
	return CFrame.new(center + pos + off) * lay * CFrame.Angles(0, math.rad(yaw), 0), size
end

local function wantKind(id: number): number
	local p = pile :: Pile.Pile
	if not p:isExposed(id) then
		return 0
	end
	return if p:isPickable(id, Config.Carry.ReachLevels) then 2 else 1
end

local function dropModel(id: number)
	local m = rocks[id]
	if m then
		m:Destroy()
		rocks[id] = nil
	end
	kind[id] = nil
	posCache[id] = nil
	epoch += 1
end

local function buildModel(id: number, k: number, cf: CFrame, size: number): Model
	local variant, tint = GeodeModel.rockLook(id, seed)
	local m = GeodeModel.rockShell(variant, size, tostring(id), { Tint = tint, Low = k == 0, Interactive = k == 2 })
	m:PivotTo(cf)
	m.Parent = folder
	return m
end

-- Gravity (carter 2026-10-16): an egg that moves on the pile falls with EggFall: it speeds up, lands, bounces once.
-- Sideways moves (the gold overtime egg, a returned egg) hop over the mound first. A newer move of the same egg wins.
local falling: { [Model]: number } = {}
local function fall(model: Model, from: CFrame, goal: CFrame)
	local p = pile :: Pile.Pile
	local plan = EggFall.plan(from.Position, goal.Position, Config.Match.EggGravity, p.RockSize * 0.12, p.RockSize * 0.5, p.RockSize * 2.5)
	local token = (falling[model] or 0) + 1
	falling[model] = token
	local spin = from.Rotation
	local spinTo = goal.Rotation
	Anim.run(plan.Dur, function(k)
		if model.Parent and falling[model] == token then
			local t = k * plan.Dur
			model:PivotTo(CFrame.new(EggFall.at(plan, t)) * spin:Lerp(spinTo, EggFall.turn(plan, t)))
		end
	end, function()
		if falling[model] == token then
			falling[model] = nil
		end
	end)
end

local function renderColumn(ci: number, animate: boolean)
	local p = pile :: Pile.Pile
	for _, id in p.Columns[ci].Stack do
		local k = wantKind(id)
		local cf, size = placement(id)
		local m: Model? = rocks[id]
		if m and kind[id] ~= k then
			-- exposure changed: swap the filler for a full model (or back)
			dropModel(id)
			m = nil
		end
		if not m then
			rocks[id] = buildModel(id, k, cf, size)
			kind[id] = k
			posCache[id] = cf.Position
			epoch += 1
		elseif (m:GetPivot().Position - cf.Position).Magnitude > 0.05 then
			posCache[id] = cf.Position
			if animate and not settings().ReducedMotion then
				fall(m, m:GetPivot(), cf)
			else
				m:PivotTo(cf)
			end
		end
	end
end

local function refreshAround(ci: number)
	local p = pile :: Pile.Pile
	renderColumn(ci, true)
	for _, nb in p.Columns[ci].Neighbors do
		renderColumn(nb, true)
	end
end

local priorityId: number? = nil -- the gold overtime egg (PileView.setPriority)

local function clear()
	priorityId = nil
	if folder then
		folder:Destroy()
	end
	if gritFolder then
		gritFolder:Destroy()
	end
	folder, gritFolder = nil, nil
	table.clear(rocks)
	table.clear(kind)
	table.clear(posCache)
	table.clear(hoppers)
	epoch += 1
	pile = nil
	selected, manual = nil, nil
	highlight.Adornee = nil
	highlight.Enabled = false
	ctxCache = nil
	lastSolid = nil
	holding, heldAction, heldCancelled = 0, nil, false
	table.clear(lastSent)
end

-- Pickup dust: a couple of chips only (the rock itself flies to the basket).
local function puff(pos: Vector3)
	if settings().LowEffects then
		return
	end
	local rng = Random.new(math.floor(pos.X * 10 + pos.Z * 7))
	for _ = 1, 3 do
		local c = GeodeModel.grit(rng, 0.25)
		c.Parent = gritFolder or Workspace
		local goal = pos + Vector3.new(rng:NextNumber(-1, 1), -pos.Y + 0.1, rng:NextNumber(-1, 1))
		Anim.run(0.35, function(k)
			c.CFrame = CFrame.new(Anim.arc(pos, goal, 0.6, Anim.easeOut(k)))
			c.Transparency = k * k
		end, function()
			c:Destroy()
		end)
	end
end

-- Selection --------------------------------------------------------------------------------------

local function reachRange(): number
	local s = if pile then (pile :: Pile.Pile).RockSize else 2
	return Config.Carry.PickupRange + s * 0.5 - 0.8 -- a little inside the server's limit
end

-- The gold overtime egg (EggFx sets it with the glow): picked first whenever it is in reach (HuntFun.pickTarget).
function PileView.setPriority(id: number?)
	if priorityId ~= id then
		priorityId = id
		epoch += 1
	end
end

local function validTarget(id: number?): boolean
	return id ~= nil and pile ~= nil and (rocks[id] :: Model?) ~= nil and not (pile :: Pile.Pile).Removed[id] and (pile :: Pile.Pile):isPickable(id, Config.Carry.ReachLevels)
end

local function inReach(id: number): boolean
	local r = root()
	local pos = posCache[id]
	if not r or not pos then
		return false
	end
	return flat(pos, r.Position) <= reachRange()
end

-- Nearest pickable rock in reach, the one the avatar (and camera) faces preferred. Reused for
-- 0.15 s while the rock set is unchanged and the avatar has barely moved or turned.
local function autoTarget(): number?
	local r = root()
	if not r or not pile then
		return nil
	end
	local rp = r.Position
	local look = r.CFrame.LookVector
	local now = os.clock()
	local c = autoCache
	if c.Epoch == epoch and now - c.At < 0.15 and (rp - c.Pos).Magnitude < 0.5 and look:Dot(c.Look) > 0.99 then
		return c.Result
	end
	local cam = Workspace.CurrentCamera
	local camLook = if cam then Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z) else Vector3.zero
	if camLook.Magnitude > 0.01 then
		camLook = camLook.Unit
	end
	local cands: { HuntFun.TargetCand } = {}
	for id, k in kind do
		local pos = posCache[id]
		if k == 2 and pos then
			table.insert(cands, { Id = id, Pos = pos })
		end
	end
	local best = HuntFun.pickTarget(cands, rp, look, camLook, reachRange(), priorityId)
	c.Epoch, c.At, c.Pos, c.Look, c.Result = epoch, now, rp, look, best
	return best
end

-- First person: the camera-centre ray (docs/m6/FIRST_PERSON.md section 3) -------------------------------

-- Is the straight line from the eye to a tagged target free of real world geometry? The pile itself, the
-- avatars and decorative trim (CameraGuard.ignorable) never block; the target's own model is skipped.
local function sightClear(from: Vector3, to: Vector3, own: Instance?): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local skip: { Instance } = {}
	for _, plr in Players:GetPlayers() do
		if plr.Character then
			table.insert(skip, plr.Character)
		end
	end
	for _, name in { "CT_Rocks_LocalPile", "CT_Rocks_Grit", "CT_Rocks_Guide", "CT_Rocks_Selection" } do
		local f = Workspace:FindFirstChild(name)
		if f then
			table.insert(skip, f)
		end
	end
	if Workspace.CurrentCamera then
		table.insert(skip, Workspace.CurrentCamera)
	end
	if own then
		table.insert(skip, own)
	end
	local delta = to - from
	local dist = delta.Magnitude
	if dist < 0.5 then
		return true
	end
	for _ = 1, 6 do
		params.FilterDescendantsInstances = skip
		local hit = Workspace:Raycast(from, delta, params)
		if not hit then
			return true
		end
		if (hit.Position - from).Magnitude >= dist - 0.6 then
			return true
		end
		if not CameraGuard.ignorable(hit.Instance) then
			return false
		end
		table.insert(skip, hit.Instance)
	end
	return true
end

local function aimRay(): (Vector3?, Vector3?)
	local cam = Workspace.CurrentCamera
	if not cam then
		return nil, nil
	end
	return cam.CFrame.Position, cam.CFrame.LookVector
end

-- The pickable rock in reach the reticle is on (the one that is outlined and sent), or nil.
local function fpRockTarget(): number?
	local origin, dir = aimRay()
	if not origin or not dir or not pile then
		return nil
	end
	local radius = (pile :: Pile.Pile).RockSize * 0.5
	local cands: { AimResolve.Candidate } = {}
	for id, k in kind do
		if k == 2 and inReach(id) then
			local pos = posCache[id]
			if pos then
				table.insert(cands, { Key = id, Kind = "rock", Pos = pos, Radius = radius })
			end
		end
	end
	local pid = priorityId
	if pid and kind[pid] == 2 and inReach(pid) and posCache[pid] and sightClear(origin, posCache[pid] :: Vector3, nil) then
		return pid -- the gold overtime egg in reach: no need to aim at it exactly
	end
	for _ = 1, 3 do
		local c = AimResolve.pick(origin, dir, cands, Config.Camera.Reach, Config.Camera.Slack)
		if not c then
			return nil
		end
		if sightClear(origin, c.Pos, nil) then
			return c.Key :: number
		end
		table.remove(cands, table.find(cands, c) :: number)
	end
	return nil
end

-- Is the ray on a rock that exists but is out of reach (a "move closer" is worth saying)?
local function fpFarRock(): boolean
	local origin, dir = aimRay()
	if not origin or not dir or not pile then
		return false
	end
	local radius = (pile :: Pile.Pile).RockSize * 0.5
	local cands: { AimResolve.Candidate } = {}
	for id, k in kind do
		if k ~= 0 then
			local pos = posCache[id]
			if pos then
				table.insert(cands, { Key = id, Kind = "rock", Pos = pos, Radius = radius })
			end
		end
	end
	return AimResolve.pick(origin, dir, cands, Config.Camera.FarReach, Config.Camera.Slack) ~= nil
end

-- Is the ray on a tagged static target (own table surface, a sell hopper)?
local function fpAimAt(pos: Vector3, radius: number, reach: number, own: Instance?): boolean
	local origin, dir = aimRay()
	if not origin or not dir then
		return false
	end
	local c = AimResolve.pick(origin, dir, { { Key = "t", Kind = "target", Pos = pos, Radius = radius } }, reach, Config.Camera.Slack)
	return c ~= nil and sightClear(origin, pos, own)
end

function PileView.aimedAtSomething(): boolean
	return aimed
end

local function setSelected(id: number?)
	if selected == id then
		return
	end
	selected = id
	local m: Instance? = if id then rocks[id] else nil
	highlight.Adornee = m
	highlight.Enabled = m ~= nil
	PileView.Selected:Fire(id)
end

function PileView.clearSelection()
	manual = nil
	setSelected(nil)
end

-- The rock an action would take right now (outlined), or nil.
local function currentTarget(): number?
	if CameraMode.firstPerson() then
		manual = nil -- first person aims with the reticle; there is no tap-to-select
		return fpRockTarget()
	end
	if manual and validTarget(manual) and inReach(manual :: number) then
		return manual
	end
	manual = nil
	local a = autoTarget()
	return a
end

function PileView.selectedId(): number?
	return selected
end

-- Context --------------------------------------------------------------------------------------

local function myStation(): any?
	local m = State.Match
	for _, st in (m and m.Stations) or {} do
		if st.UserId == player.UserId then
			return st
		end
	end
	return nil
end

local function myTablePos(): Vector3?
	return StationView.tablePosition(player.UserId)
end

local function nearHopper(): boolean
	local r = root()
	if not r then
		return false
	end
	for _, b in hoppers do
		if b.Parent and flat(b.Position, r.Position) <= 10 then
			return true
		end
	end
	return false
end

local function toolId(st: any?): string
	return (st and st.Tool) or (State.Profile and State.Profile.EquippedHandheld) or "Hammer"
end

-- Taps per second on the nest: the tool's rate times the pet helper's bonus (server snapshot; HuntFun.Helper).
local function crushRate(st: any?): number
	local tool = Config.Handhelds[toolId(st)] or Config.Handhelds.Hammer
	local help = if st and type(st.Help) == "number" and st.Help >= 1 then st.Help else 1
	return tool.Rate * help
end

-- What the primary action means right now. Returns
--   { Id, Arrow = "table"|"pile"|nil, Target = rock id (pickup) }
-- Ids: wait securing none (no button) and pickup take deposit crush machine collect sell bagfull closer.
-- The decision itself is the pure ActionRules.decide (tested); this function only gathers its inputs from the
-- server snapshot and the avatar's position, and keeps the previous answer for a moment while the avatar
-- jitters across a boundary (large overlapping bounds of mound and table), but never past a round change.
local STICKY = { pickup = true, take = true, deposit = true, crush = true, machine = true, collect = true, bagfull = true }
local STICKY_SECONDS = 0.35

local function nearestPileRock(): number
	local r = root()
	if not r then
		return math.huge
	end
	local best = math.huge
	for id, k in kind do
		if k == 2 then
			local pos = posCache[id]
			if pos then
				best = math.min(best, flat(pos, r.Position))
			end
		end
	end
	return best
end

function PileView.context(force: boolean?): any
	local now = os.clock()
	if ctxCache and not force and now - ctxAt < 0.08 then
		return ctxCache
	end
	local m = State.Match
	local st = myStation()
	local out: any
	local ctx: ActionRules.Context
	if not m or m.Phase ~= "Searching" or not active or not st then
		ctx = ActionRules.decide({
			Phase = if m then m.Phase else nil, Active = active, HasStation = st ~= nil,
			Basket = 0, Capacity = Config.Carry.Capacity, Queue = 0, QueueCapacity = Config.Station.QueueCapacity, Current = false,
			Machine = false, MachineFull = false, Rubble = 0, RubbleFull = false, NearHopper = false,
			AtTable = false, NearTable = false, HasTarget = false, NearPile = false,
		})
		lastSolid = nil
		aimed = false
		out = { Id = ctx.Id, Arrow = ctx.Arrow }
	else
		local r = root()
		local prof = State.Profile
		local basket = #st.Basket
		local tp = myTablePos()
		local dTable = if r and tp then flat(tp, r.Position) else math.huge
		local wasAtTable = lastSolid ~= nil and (lastSolid.Id == "deposit" or lastSolid.Id == "crush" or lastSolid.Id == "machine" or lastSolid.Id == "collect" or lastSolid.Id == "bagfull")
		local atRange = Config.Station.CrushRange - (if wasAtTable then 0.1 else 0.8)
		local target = if r then currentTarget() else nil
		local atTable = dTable <= atRange
		local nearTable = dTable <= Config.Station.CrushRange + 8
		local nearPile = nearestPileRock() <= reachRange() + 9
		local hopper = nearHopper()
		aimed = target ~= nil
		if CameraMode.firstPerson() and r then
			-- One context from the reticle: a pile rock the ray is on wins over a distant table; the sell hopper and the
			-- "move closer" hints appear only when the ray is on them (never for scenery).
			local tableAimed = false
			if tp then
				-- aim at the egg on the plate (the ring used to open on the nest below it)
				local at = StationView.aimPoint(player.UserId) or (tp + Vector3.new(0, 2.6, 0))
				tableAimed = fpAimAt(at, 3.2, Config.Camera.FarReach, StationView.ownModel())
			end
			if target ~= nil and dTable > Config.Camera.WorkRadius then
				atTable = false
			end
			nearTable = tableAimed and dTable <= Config.Station.CrushRange + 8
			nearPile = target == nil and fpFarRock() and nearestPileRock() <= reachRange() + 9
			if hopper then
				local close = false
				local aimedHopper = false
				for _, b in hoppers do
					if b.Parent then
						if flat(b.Position, r.Position) <= 3.5 then
							close = true
						end
						if not aimedHopper and fpAimAt(b.Position, 3.2, 14, b.Parent) then
							aimedHopper = true
						end
					end
				end
				hopper = close or aimedHopper
			end
			aimed = target ~= nil or tableAimed or (hopper and (prof ~= nil and prof.Rubble > 0))
		end
		ctx = ActionRules.decide({
			Phase = m.Phase, Active = active, HasStation = true,
			Basket = basket, Capacity = st.CarryCap or Config.Carry.Capacity, -- per player (basket / nest upgrades)
			Queue = #st.Queue, QueueCapacity = st.QueueCap or Config.Station.QueueCapacity, Current = st.Current ~= nil,
			Machine = st.Machine ~= nil and st.State ~= "Paused", MachineFull = st.State == "Full",
			Rubble = if prof then prof.Rubble else 0, RubbleFull = prof ~= nil and prof.Rubble >= prof.Capacity,
			NearHopper = hopper,
			AtTable = atTable, NearTable = nearTable,
			HasTarget = target ~= nil, NearPile = nearPile,
		})
		out = { Id = ctx.Id, Arrow = ctx.Arrow, Target = if ctx.Id == "pickup" then target else nil }
		if (ctx.Id == "closer" or ctx.Id == "none") and lastSolid and STICKY[lastSolid.Id] and now - lastSolid.At < STICKY_SECONDS then
			-- brief jitter across a boundary: keep what the button said (a pickup keeps its still-valid target)
			if lastSolid.Id ~= "pickup" or (lastSolid.Target ~= nil and validTarget(lastSolid.Target)) then
				out = { Id = lastSolid.Id, Arrow = lastSolid.Arrow, Target = lastSolid.Target }
			end
		elseif STICKY[ctx.Id] then
			lastSolid = { Id = ctx.Id :: string, Arrow = ctx.Arrow, Target = out.Target :: number?, At = now }
		end
		out.Basket = basket
		out.Queued = #st.Queue + (if st.Current then 1 else 0)
		out.Auto = st.Machine ~= nil and st.State ~= "Paused"
		if out.Id == "crush" and out.Queued == 0 then
			-- no egg on the plate and none in the tray (a held "crush" across a boundary, or the last egg just
			-- cracked): CRACK! would do nothing, so the button says where the next eggs are instead
			local here = ctx.Id == "crush" -- only a held (sticky) CRACK can get here from away from the nest
			out = { Id = if here then "collect" else "none", Arrow = if here then "pile" else ctx.Arrow, Basket = out.Basket, Queued = 0, Auto = out.Auto }
			lastSolid = nil
		end
	end
	ctxCache = out
	ctxAt = now
	return out
end

-- Points the route hint where the context says (the Hud calls this a few times a second). Only one
-- target at a time, only when it helps: a table hint always (rocks are waiting to be deposited), a pile hint
-- for players still learning the loop (`tutorial`) or anyone who has wandered far from the pile (bug 244).
-- Nothing outside a live Searching phase.
local PILE_FAR = 40 -- studs from the pile centre: beyond this the pile hint shows for everyone
function PileView.updateGuide(ctx: any, show: boolean, tutorial: boolean?)
	if not show or not ctx or not ctx.Arrow or not pile then
		GuideArrow.clear()
		return
	end
	if ctx.Arrow == "table" then
		local tp = myTablePos()
		if tp then
			GuideArrow.set(tp, "NEST", center.Y)
			return
		end
	elseif ctx.Arrow == "pile" then
		local r = root()
		if not tutorial and not (r and flat(r.Position, center) > PILE_FAR) then
			GuideArrow.clear()
			return
		end
		GuideArrow.set(center, "PILE", center.Y)
		return
	end
	GuideArrow.clear()
end

-- The server refused something: drop a pickup target that is gone or unreachable so the outline and the
-- next press move on to another rock instead of retrying the same one.
function PileView.onReply(data: any)
	if data.Action == "Pickup" and not data.Ok then
		manual = nil
		if data.Reason == "Gone" or data.Reason == "Unreachable" or data.Reason == "BadRock" then
			epoch += 1
			ctxCache = nil
		end
	end
end

-- Doing it ---------------------------------------------------------------------------------------

local function due(key: string, gap: number): boolean
	local t = os.clock()
	if t - (lastSent[key] or 0) < gap then
		return false
	end
	lastSent[key] = t
	return true
end

-- A small buzz per crack sent (owner pick). Phones / gamepads that support it only; every call is pcall'd (a
-- device without a motor does nothing). Reduced Motion turns it off (there is no separate vibration setting).
local buzzToken = 0
local function crackBuzz()
	local prof = State.Profile
	if prof and prof.Settings and prof.Settings.ReducedMotion == true then
		return
	end
	local input = if UserInputService.TouchEnabled then Enum.UserInputType.Touch else UserInputService:GetLastInputType()
	if input ~= Enum.UserInputType.Touch and string.sub(input.Name, 1, 7) ~= "Gamepad" then
		return
	end
	buzzToken += 1
	local my = buzzToken
	local ok = pcall(function()
		local hs = game:GetService("HapticService")
		if not hs:IsVibrationSupported(input) or not hs:IsMotorSupported(input, Enum.VibrationMotor.Small) then
			error("unsupported")
		end
		hs:SetMotor(input, Enum.VibrationMotor.Small, 0.5)
	end)
	if ok then
		task.delay(0.07, function()
			if my == buzzToken then
				pcall(function()
					game:GetService("HapticService"):SetMotor(input, Enum.VibrationMotor.Small, 0)
				end)
			end
		end)
	end
end

-- The `due` key and gap an action id would use when pressed (mirrors the branches in perform).
local function dueKey(id: string): (string, number)
	if id == "pickup" then
		return "pickup", Config.Carry.PickupInterval + 0.03
	elseif id == "deposit" then
		return "deposit", Config.Station.DepositInterval + 0.12
	elseif id == "crush" then
		return "crush", 1 / crushRate(myStation()) + 0.03
	elseif id == "sell" then
		return "sell", 0.8
	end
	return "hint", 1.2
end

local function perform()
	if not active or UI.blocked() then
		return
	end
	local m = State.Match
	if not m or m.Phase ~= "Searching" then
		return
	end
	if heldCancelled then
		return
	end
	if not CameraMode.mayAct() then
		-- the input that closed a menu (or any press right after it) must not also act: a fresh press is needed
		heldCancelled = true
		return
	end
	-- A fresh press always reads a fresh context (tap responsiveness). While held (called every Heartbeat), the
	-- short-lived cache is enough until the held action can actually fire again; only then is it recomputed.
	local ctx = PileView.context(heldAction == nil)
	if heldAction then
		local key, gap = dueKey(ctx.Id)
		if os.clock() - (lastSent[key] or 0) < gap then
			if ctx.Id ~= heldAction then
				heldCancelled = true
			end
			return
		end
		ctx = PileView.context(true)
	end
	if not heldAction then
		heldAction = ctx.Id
	end
	if ctx.Id ~= heldAction then
		-- the meaning changed under the finger (basket filled, left range, reached the table): this press is
		-- over. Nothing repeats until the finger is lifted and pressed again.
		heldCancelled = true
		return
	end
	local id = ctx.Id
	local remote = Net.event("RockAction")
	if id == "pickup" then
		if due("pickup", Config.Carry.PickupInterval + 0.03) and ctx.Target then
			setSelected(ctx.Target)
			remote:FireServer("Pickup", round, ctx.Target)
			CarryView.scoop(player.UserId)
			PileView.Struck:Fire(ctx.Target)
		end
	elseif id == "deposit" then
		if due("deposit", Config.Station.DepositInterval + 0.12) then
			remote:FireServer("Deposit", round)
		end
	elseif id == "crush" then
		if due("crush", 1 / crushRate(myStation()) + 0.03) then
			remote:FireServer("Crush", round)
			StationView.localSwing()
			crackBuzz()
		end
	elseif id == "sell" then
		if due("sell", 0.8) then
			Net.event("ShopAction"):FireServer("SellAtHopper")
		end
	elseif due("hint", 1.2) then
		if id == "take" then
			notice("Basket full: take eggs to your nest", "info")
		elseif id == "collect" or id == "machine" then
			notice("Collect more eggs at the pile", "info")
		elseif id == "bagfull" then
			notice("Candy bag full: sell at a candy stand", "warn")
		elseif id == "closer" then
			notice("Move closer", "info")
		end
	end
end

function PileView.holdBegin()
	holding += 1
	if holding == 1 then
		heldAction = nil
		heldCancelled = false
		perform()
	end
end

function PileView.holdEnd()
	holding = math.max(0, holding - 1)
	if holding == 0 then
		heldAction = nil
		heldCancelled = false
	end
end

function PileView.isHolding(): boolean
	return holding > 0
end

function PileView.stopAll()
	holding = 0
	heldAction = nil
	heldCancelled = false
	ctxCache = nil
	local char = player.Character
	if char then
		ToolAnim.stop(char)
	end
end

function PileView.isActive(): boolean
	return active
end

-- Server events --------------------------------------------------------------------------------------

function PileView.init(payload: { [string]: any })
	clear()
	round = payload.Round
	seed = payload.Seed or 1
	center = payload.Center
	local tier = Config.Tiers[payload.Tier]
	pile = Pile.new(payload.Rocks, tier.RockSize, tier.Radius, payload.Seed)
	for _, id in payload.Removed or {} do
		(pile :: Pile.Pile):remove(id)
	end
	if payload.Stacks then
		(pile :: Pile.Pile):setStacks(payload.Stacks)
	end
	local f = Instance.new("Folder")
	f.Name = "CT_Rocks_LocalPile"
	f.Parent = Workspace
	folder = f
	local gf = Instance.new("Folder")
	gf.Name = "CT_Rocks_Grit"
	gf.Parent = Workspace
	gritFolder = gf -- pickup dust only: the grass blobs round the base read as dark green discs (Studio sweep 190)
	for ci in (pile :: Pile.Pile).Columns do
		renderColumn(ci, false)
	end
	-- bug 244: a tall soft light beam over the pile centre, seen from anywhere in the arena. It stands on the
	-- centre point above the top of the mound (never on or near any particular egg) and fades with the pile.
	do
		local top = center.Y
		for _, pos in posCache do
			top = math.max(top, pos.Y)
		end
		local base = top + 4
		local height = 140
		-- a thin soft light (a Beam that fades upward, always facing the camera), not a see-through slab
		local beam = Instance.new("Part")
		beam.Name = "PileBeam"
		beam.Size = Vector3.new(0.2, 0.2, 0.2)
		beam.CFrame = CFrame.new(center.X, base, center.Z)
		beam.Transparency = 1
		beam.Anchored = true
		beam.CanCollide = false
		beam.CanQuery = false
		beam.CanTouch = false
		beam.CastShadow = false
		local a0 = Instance.new("Attachment")
		a0.Parent = beam
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, height, 0)
		a1.Parent = beam
		local light = Instance.new("Beam")
		light.Attachment0 = a0
		light.Attachment1 = a1
		light.FaceCamera = true
		light.Width0 = 1.4
		light.Width1 = 0.6
		light.Color = ColorSequence.new(Color3.fromRGB(255, 226, 140))
		light.LightEmission = 0.8
		light.LightInfluence = 0
		light.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(0.6, 0.75), NumberSequenceKeypoint.new(1, 1) })
		light.Segments = 4
		light.Parent = beam
		beam.Parent = f
	end
	-- sell hoppers in this arena (cached; the HUD asks every 0.2 s)
	for _, arena in Workspace:GetChildren() do
		if string.sub(arena.Name, 1, 15) == "CT_Rocks_Arena_" then
			for _, d in arena:GetDescendants() do
				if d:IsA("Model") and d:GetAttribute("Hopper") then
					local body = d:FindFirstChild("Body")
					if body and body:IsA("BasePart") and flat(body.Position, center) < 120 then
						table.insert(hoppers, body)
					end
				end
			end
		end
	end
	active = true
	StationView.init(payload)
	CarryView.init(payload)
	-- delivery drop during the countdown (cosmetic only, no physics)
	if payload.Phase == "Countdown" and not settings().ReducedMotion then
		-- eggs drop in one after another, bottom of the pile first
		local order: { number } = {}
		for id in rocks do
			if kind[id] ~= 0 then
				table.insert(order, id)
			end
		end
		table.sort(order, function(a, b)
			local pa, pb = posCache[a], posCache[b]
			local ya, yb = if pa then pa.Y else 0, if pb then pb.Y else 0
			if ya ~= yb then
				return ya < yb
			end
			return a < b
		end)
		local total = math.min(#order, 140)
		for n = 1, total do
			local m = rocks[order[n]]
			if m then
				local goal = m:GetPivot()
				local lag = (n - 1) / math.max(total, 1) * 0.7
				local d = 0.7
				m:PivotTo(goal + Vector3.new(0, 9, 0))
				Anim.run(d + 0.7, function(t)
					if m.Parent then
						local k = math.clamp((t * (d + 0.7) - lag) / d, 0, 1)
						m:PivotTo(goal + Vector3.new(0, 9 * (1 - Anim.easeOut(k)), 0))
					end
				end)
			end
		end
	end
end

-- The drawn model of a pile egg (nil when it is not drawn or has left the pile). Used by EggFx (wobble hint).
function PileView.eggModel(id: number): Model?
	local m = rocks[id]
	return if m and m.Parent then m else nil
end

function PileView.roundId(): number
	return round
end

function PileView.reserve(_ids: { number }) end
function PileView.release(_ids: { number }) end
function PileView.clearReserved() end
function PileView.reservedCount(): number
	return 0
end

function PileView.remaining(): number
	return if pile then (pile :: Pile.Pile).Remaining else 0
end

function PileView.onRocks(payload: { [string]: any })
	if not pile or payload.Round ~= round then
		return
	end
	local p = pile :: Pile.Pile
	local touched: { [number]: boolean } = {}
	for _, e in payload.Ev or {} do
		if e.Kind == "Pick" then
			local ci = p:remove(e.Id)
			local m = rocks[e.Id]
			local at = posCache[e.Id]
			rocks[e.Id] = nil
			kind[e.Id] = nil
			posCache[e.Id] = nil
			epoch += 1
			if m then
				if at then
					puff(at)
				end
				local b = m.PrimaryPart
				if b then
					b.CanQuery = false
				end
				if e.UserId ~= player.UserId then
					CarryView.scoop(e.UserId)
				end
				if CarryView.hasAvatar(e.UserId) then
					CarryView.fly(e.UserId, m, e.Id)
				else
					m:Destroy()
				end
			end
			if ci then
				touched[ci] = true
			end
			if e.Id == selected then
				setSelected(nil)
			end
			if e.Id == manual then
				manual = nil
			end
		elseif e.Kind == "Return" then
			if p:restoreTo(e.Id, e.Col) then
				touched[e.Col] = true
				epoch += 1
			end
		elseif e.Kind == "Move" then
			-- overtime: the glowing pet egg is lifted onto a reachable edge column (RoundRocks.surface)
			local from = p:remove(e.Id)
			if from and p:restoreTo(e.Id, e.Col) then
				touched[from] = true
				touched[e.Col] = true
				posCache[e.Id] = nil
				epoch += 1
			end
		elseif e.Kind == "Start" and e.UserId and e.Duration then
			PileView.Claimed:Fire(e.UserId, { e.Id }, e.Duration) -- drives MachineView's cycle for one rock
		elseif e.Kind == "Done" or e.Kind == "Found" then
			local viaMachine = false
			for _, st in payload.Stations or {} do
				if st.UserId == e.UserId and st.Machine ~= nil and st.State ~= "Paused" then
					viaMachine = true
				end
			end
			if e.UserId == player.UserId and e.Kind == "Done" and State.Match then
				State.Match.MyCracked = (State.Match.MyCracked or 0) + 1
			end
			PileView.Cracked:Fire(e.Id, e.UserId == player.UserId, viaMachine, e.UserId)
		end
		StationView.onEvent(e, payload.Stations)
	end
	for ci in touched do
		refreshAround(ci)
	end
	for _, e in payload.Ev or {} do
		if e.Kind == "Return" and rocks[e.Id] then
			-- a returned egg drops back onto the pile from above and lands with gravity
			local m = rocks[e.Id]
			if not settings().ReducedMotion then
				local goal = m:GetPivot()
				fall(m, goal + Vector3.new(0, 3, 0), goal)
			end
		end
	end
	StationView.onStations(payload.Stations)
	CarryView.setStations(payload.Stations or {})
	if State.Match then
		State.Match.Remaining = p.Remaining
		State.Match.Counts = payload.Counts
		State.Match.Stations = payload.Stations
		State.update("Match")
	end
end

-- After the find: the rest of the pile crumbles away cosmetically (it pays nothing). The tables
-- keep their geode on show until the round is left.
function PileView.clearPile()
	active = false
	PileView.stopAll()
	setSelected(nil)
	GuideArrow.clear()
	local f = folder
	if not f then
		return
	end
	local reduced = settings().ReducedMotion
	local fade: { BasePart } = {}
	for _, d in f:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(fade, d)
		end
	end
	if reduced then
		f:Destroy()
		folder = nil
		return
	end
	local orig: { number } = {}
	for i, d in fade do
		orig[i] = d.Transparency
	end
	Anim.run(1.2, function(k)
		for i, d in fade do
			if d.Parent then
				d.Transparency = orig[i] + (1 - orig[i]) * k
			end
		end
	end, function()
		if folder == f then
			f:Destroy()
			folder = nil
		end
	end)
end

function PileView.leave()
	active = false
	PileView.stopAll()
	GuideArrow.clear()
	StationView.clear()
	CarryView.clear()
	clear()
end

-- Setup -------------------------------------------------------------------------------------

function PileView.start()
	highlight = Instance.new("Highlight")
	highlight.FillTransparency = 1 -- outline only, so the rock stays readable
	highlight.OutlineColor = Color3.fromRGB(255, 214, 90)
	highlight.OutlineTransparency = 0.15
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	-- A Highlight with no Adornee outlines its parent; keep it in a plain Folder and only enable it
	-- while a rock is selected.
	highlight.Enabled = false
	local hlFolder = Instance.new("Folder")
	hlFolder.Name = "CT_Rocks_Selection"
	hlFolder.Parent = Workspace
	highlight.Parent = hlFolder
	CarryView.start()

	-- Tap / click selects a rock in the pile; drags (camera turns) do not.
	local downAt: { [InputObject]: { pos: Vector2, t: number } } = {}
	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe or UI.blocked() then
			return
		end
		if CameraMode.firstPerson() and input.UserInputType == Enum.UserInputType.MouseButton1 then
			-- first person with the mouse locked to the view: a click is the action (the same path as E)
			mouseHolds[input] = true
			PileView.holdBegin()
		elseif CameraMode.firstPerson() and input.UserInputType == Enum.UserInputType.Touch then
			-- a touch is the look drag or the action button's own press, never a pickup by itself
			return
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			downAt[input] = { pos = Vector2.new(input.Position.X, input.Position.Y), t = os.clock() }
		elseif input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonR2 then
			PileView.holdBegin()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if mouseHolds[input] then
			mouseHolds[input] = nil
			PileView.holdEnd()
			return
		end
		if input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonR2 then
			PileView.holdEnd()
			return
		end
		local d = downAt[input]
		downAt[input] = nil
		if not d or not active or not folder or UI.blocked() then
			return
		end
		local pos = Vector2.new(input.Position.X, input.Position.Y)
		if (pos - d.pos).Magnitude > 12 or os.clock() - d.t > 0.35 then
			return
		end
		local cam = Workspace.CurrentCamera
		local ray = cam:ScreenPointToRay(pos.X, pos.Y) -- input.Position is in GUI space (below the top bar), not viewport space (audit 19)
		-- Tap the egg on your own nest plate: one crack, the same "Crush" intent as the CRACK button (the server
		-- checks range, plate and tool rate as for any other Crush).
		local plate = StationView.ownPlate()
		if plate then
			local pp = RaycastParams.new()
			pp.FilterType = Enum.RaycastFilterType.Include
			pp.FilterDescendantsInstances = { plate }
			local ph = Workspace:Raycast(ray.Origin, ray.Direction * 200, pp)
			if ph and StationView.isOwnPlatePart(ph.Instance) and PileView.context(true).Id == "crush" then
				PileView.holdBegin()
				PileView.holdEnd()
				return
			end
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { folder :: Folder }
		local hit = Workspace:Raycast(ray.Origin, ray.Direction * 200, params)
		local model = hit and hit.Instance:FindFirstAncestorOfClass("Model")
		local id = model and tonumber(model.Name)
		if id and validTarget(id) and inReach(id) then
			manual = id
			setSelected(id)
		elseif plate and due("miss", 0.25) then
			Audio.play("Button", { Volume = 0.25, Pitch = 0.8, Key = "self:miss" }) -- soft "nothing there" tick
		end
	end)
	-- focus loss / respawn stop holding
	UserInputService.WindowFocusReleased:Connect(function()
		table.clear(mouseHolds)
		PileView.stopAll()
	end)
	-- a panel opening ends any held action at once (the release may never arrive over a menu)
	UI.BlockChanged.Event:Connect(function(blocked)
		if blocked then
			table.clear(mouseHolds)
			PileView.stopAll()
		end
	end)
	player.CharacterAdded:Connect(PileView.stopAll)

	-- First person: the eye can walk into the mound (its eggs never collide, so nobody gets trapped). Eggs right at the
	-- camera fade out locally, so the view is never inside an egg shell while picking.
	local faded: { [number]: Model } = {}
	RunService:BindToRenderStep("CTR_PileFade", Enum.RenderPriority.Camera.Value + 4, function()
		local cam = Workspace.CurrentCamera
		local near = if pile and cam and CameraMode.firstPerson() then (pile :: Pile.Pile).RockSize * 0.95 else 0
		local eye = if cam then cam.CFrame.Position else Vector3.zero
		for id, m in faded do
			local pos = posCache[id]
			if rocks[id] ~= m or not pos or (pos - eye).Magnitude > near * 1.1 then
				faded[id] = nil
				if m.Parent then
					for _, d in m:GetDescendants() do
						if d:IsA("BasePart") then
							d.LocalTransparencyModifier = 0
						end
					end
				end
			end
		end
		if near <= 0 or (eye - center).Magnitude > 40 then
			return
		end
		for id, pos in posCache do
			local m = rocks[id]
			if m and not faded[id] and (pos - eye).Magnitude < near then
				faded[id] = m
				for _, d in m:GetDescendants() do
					if d:IsA("BasePart") then
						d.LocalTransparencyModifier = 1
					end
				end
			end
		end
	end)

	RunService.Heartbeat:Connect(function(dt)
		if active then
			selClock += dt
			if selClock >= 0.1 then
				selClock = 0
				local m = State.Match
				if m and m.Phase == "Searching" and not UI.blocked() then
					local ctx = PileView.context()
					-- outline only while the button would pick up that very rock
					setSelected(if ctx.Id == "pickup" then ctx.Target else nil)
				else
					setSelected(nil)
				end
			end
			if holding > 0 then
				perform()
			end
			StationView.vibrate()
		end
	end)
end

return PileView
