--!strict
-- Client-side machine motion (cosmetic only; the server owns every claim and every payout).
-- The server builds static models (src/server/MachineModels.luau) and tells us each owner's
-- machine state plus a Start event for every rock it takes (PileView.Claimed, Duration = Config
-- seconds per rock). One Start = one visible cycle of exactly that length, so strokes match the
-- counters:
--   Auto Cracker: jaws close to contact at 50% of the cycle and open again; belt and rollers run.
--   Press: load 0-15%, platen down to contact at 50%, held to 60%, back up; the stone is flattened.
--   Crusher: rollers (counter-rotating) and belt run while cycles keep arriving; dust pools.
-- Idle (no queue), paused, bag full or round over: parts settle open, loops stop.
-- Moving parts never collide (CanCollide/CanQuery are off on the server), so nothing here can
-- push a character. Reserved-rock outlines live in PileView.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local State = require(script.Parent.State)
local Audio = require(script.Parent.Audio)
local Effects = require(script.Parent.Effects)

local MachineView = {}

local V3 = Vector3.new

-- Stone paths in the machine's pad-top frame (-Z toward the pile).
local PATHS = {
	AutoCracker = {
		Start = V3(0, 1.65, -4.4), Roller = V3(0, 2.0, 0.0), Mid = V3(0, 1.7, 2.2), Out = V3(0, 0.95, 4.8), BeltEnd = V3(0, 1.7, -0.7),
	},
	IndustrialCrusher = {
		Start = V3(0, 1.8, -4.5), Roller = V3(0, 3.3, -0.3), Mid = V3(0, 2.0, 1.8), Out = V3(0, 0.95, 4.8), BeltEnd = V3(0, 1.8, -2.3),
	},
	HydraulicPress = {
		Start = V3(0, 1.55, -3.5), Roller = V3(0, 1.65, 0.6), Mid = V3(0, 1.3, 3.0), Out = V3(0, 0.95, 4.35), BeltEnd = V3(0, 1.65, 0.6),
	},
}
local STATE_COLOR = {
	Running = Color3.fromRGB(70, 200, 100),
	Full = Color3.fromRGB(244, 198, 68),
	Paused = Color3.fromRGB(226, 76, 64),
}
local OFF = Color3.fromRGB(92, 98, 106)

type Piece = { Part: BasePart, Base: CFrame }
type Stone = { Part: Part, T0: number, Dur: number, Kind: string, Path: any, Landed: boolean }
type View = {
	Model: Model,
	OwnerId: number,
	Id: string,
	Frame: CFrame,
	Belts: { { Tile: Piece, Chevron: Piece?, Order: number, Count: number, Z0: number, Length: number } },
	Spins: { { Model: Model, Base: CFrame, Dir: number } },
	Jaws: { { Model: Model, Base: CFrame, Dir: number } },
	Plate: { Piece },
	Rod: Piece?,
	RodSize: Vector3,
	Path: any, -- stone path from the kit attachment points (nil: PATHS[Id])
	KitJaws: { { Piece: Piece, Delta: Vector3 } },
	KitPress: { { Piece: Piece, Travel: number } },
	KitRollers: { { Piece: Piece, Pivot: Vector3, Axis: Vector3, Dir: number } },
	KitFill: { BasePart },
	FillShown: boolean,
	Light: BasePart?,
	Beacon: BasePart?,
	Emitters: { ParticleEmitter },
	Speed: number,
	BeltOff: number,
	Angle: number,
	JawT: number,
	CycleAt: number, -- start (os.clock) of the current server rock cycle
	CycleDur: number, -- its length: Config seconds per rock (RoundRocks.machineSeconds), from the Start event
	LastStone: number, -- last cosmetic feed stone spawn (throttles very fast machines)
	Contact: boolean,
	PlateD: number, -- last plate drop applied (skips identical frames)
	Rested: boolean, -- belts/rollers/jaws already settled at speed 0
	Cues: { [string]: boolean }, -- press sounds already played this cycle
	Stones: { Stone },
	State: string,
	BuiltAt: number, -- os.clock() of build (a later streamed-in part rebuilds the view once it is at rest)
}

local views: { [Model]: View } = {}
local states: { [number]: { State: string, Id: string } } = {}
local stonePool: { Part } = {}
local fxFolder: Folder? = nil
local lastScan = 0
local active = false
-- StreamingEnabled: a machine model can arrive before all of its parts. Each model is watched; a view is built once
-- its parts stop arriving (SETTLE s) and rebuilt, while the machine is at rest, when more parts stream in later.
local SETTLE = 0.6
local addedAt: { [Model]: number } = {}
local watched: { [Model]: RBXScriptConnection } = {}
local function watch(model: Model)
	if watched[model] then
		return
	end
	-- already filled in when first seen (no streaming, or streamed in whole): build right away
	addedAt[model] = if #model:GetChildren() > 0 then os.clock() - SETTLE else os.clock()
	watched[model] = model.DescendantAdded:Connect(function()
		addedAt[model] = os.clock()
	end)
end
local function unwatch(model: Model)
	local c = watched[model]
	if c then
		c:Disconnect()
	end
	watched[model] = nil
	addedAt[model] = nil
end

local function settings(): any
	return State.Profile and State.Profile.Settings or {}
end

local function piece(p: BasePart): Piece
	return { Part = p, Base = p.CFrame }
end

local function build(model: Model): View?
	local frame = model:GetAttribute("Frame")
	local owner = model:GetAttribute("OwnerId")
	local id = model:GetAttribute("MachineId")
	if typeof(frame) ~= "CFrame" or type(owner) ~= "number" or type(id) ~= "string" then
		return nil
	end
	local v: View = {
		Model = model, OwnerId = owner, Id = id, Frame = frame,
		Belts = {}, Spins = {}, Jaws = {}, Plate = {}, Rod = nil, RodSize = Vector3.one,
		Path = nil, KitJaws = {}, KitPress = {}, KitRollers = {}, KitFill = {}, FillShown = false,
		Light = nil, Beacon = nil, Emitters = {}, Speed = 0, BeltOff = 0, Angle = 0, JawT = 0,
		CycleAt = 0, CycleDur = 0, LastStone = 0, Contact = false, PlateD = 0, Rested = false, Cues = {}, Stones = {}, State = "None",
		BuiltAt = os.clock(),
	}
	if model:GetAttribute("Kit") == true then
		local function pt(n: string): Vector3?
			local a = model:GetAttribute(n)
			return if typeof(a) == "Vector3" then a else nil
		end
		local s0, b0, r0, m0, o0 = pt("PathStart"), pt("PathBeltEnd"), pt("PathRoller"), pt("PathMid"), pt("PathOut")
		if s0 and b0 and r0 and m0 and o0 then
			v.Path = { Start = s0, BeltEnd = b0, Roller = r0, Mid = m0, Out = o0 }
		end
	end
	for _, d in model:GetDescendants() do
		local role = d:GetAttribute("Role")
		if d:IsA("Model") and role == "Spin" then
			table.insert(v.Spins, { Model = d, Base = d:GetPivot(), Dir = (d:GetAttribute("Dir") :: number?) or 1 })
		elseif d:IsA("Model") and role == "Jaw" then
			table.insert(v.Jaws, { Model = d, Base = d:GetPivot(), Dir = (d:GetAttribute("Dir") :: number?) or 1 })
		elseif d:IsA("BasePart") then
			if role == "KitJaw" then
				local delta = d:GetAttribute("Delta")
				table.insert(v.KitJaws, { Piece = piece(d), Delta = if typeof(delta) == "Vector3" then delta else Vector3.zero })
			elseif role == "KitPress" then
				table.insert(v.KitPress, { Piece = piece(d), Travel = (d:GetAttribute("Travel") :: number?) or 1.5 })
			elseif role == "KitRoller" then
				local pv, ax = d:GetAttribute("Pivot"), d:GetAttribute("Axis")
				if typeof(pv) == "Vector3" and typeof(ax) == "Vector3" then
					table.insert(v.KitRollers, { Piece = piece(d), Pivot = pv, Axis = ax, Dir = (d:GetAttribute("Dir") :: number?) or 1 })
				end
			elseif role == "KitFill" then
				table.insert(v.KitFill, d)
			elseif role == "Belt" then
				local chev = d:FindFirstChild("Chevron")
				table.insert(v.Belts, {
					Tile = piece(d),
					Chevron = if chev and chev:IsA("BasePart") then piece(chev) else nil,
					Order = (d:GetAttribute("Order") :: number?) or 1,
					Count = (d:GetAttribute("Count") :: number?) or 1,
					Z0 = (d:GetAttribute("Z0") :: number?) or 0,
					Length = (d:GetAttribute("Length") :: number?) or 1,
				})
			elseif role == "Plate" then
				table.insert(v.Plate, piece(d))
				for _, c in d:GetChildren() do
					if c:IsA("BasePart") then
						table.insert(v.Plate, piece(c))
					end
				end
			elseif role == "Piston" then
				v.Rod = piece(d)
				v.RodSize = d.Size
			elseif role == "Light" then
				v.Light = d
			elseif role == "Beacon" then
				v.Beacon = d
			end
		elseif d:IsA("Attachment") and role == "Dust" then
			for _, e in d:GetChildren() do
				if e:IsA("ParticleEmitter") then
					table.insert(v.Emitters, e)
				end
			end
		end
	end
	return v
end

local function scan()
	for model in watched do
		if model.Parent == nil then
			unwatch(model)
		end
	end
	for model, v in views do
		local now = os.clock()
		local atRest = (v.Rested or v.Id == "HydraulicPress") and #v.Stones == 0 and now > v.CycleAt + v.CycleDur + 0.5
		local late = (addedAt[model] or 0) > v.BuiltAt and now - (addedAt[model] or 0) >= SETTLE and atRest
		if model.Parent == nil or late then
			for _, s in v.Stones do
				s.Part.Parent = nil
				table.insert(stonePool, s.Part)
			end
			views[model] = nil -- a late one is built again below with all its parts
		end
	end
	for _, arena in Workspace:GetChildren() do
		if string.sub(arena.Name, 1, 15) == "CT_Rocks_Arena_" then
			local f = arena:FindFirstChild("CT_Rocks_Machines")
			if f then
				for _, model in f:GetChildren() do
					if model:IsA("Model") then
						watch(model)
					end
					if model:IsA("Model") and not views[model] and os.clock() - (addedAt[model] or 0) >= SETTLE then
						local v = build(model)
						if v then
							views[model] = v
						end
					end
				end
			end
		end
	end
end

local function viewOf(uid: number): View?
	for _, v in views do
		if v.OwnerId == uid then
			return v
		end
	end
	return nil
end

-- Feed stones (pooled, <= 1 s each) --------------------------------------------------------

local function newStone(): Part
	local p = table.remove(stonePool)
	if p then
		return p
	end
	local s = Instance.new("Part")
	s.Name = "FeedStone"
	s.Anchored = true
	s.CanCollide = false
	s.CanQuery = false
	s.CanTouch = false
	s.CastShadow = false
	s.Material = Enum.Material.Slate
	return s
end

local function spawnStone(v: View, delay: number, dur: number)
	if #v.Stones >= 6 then
		return
	end
	local path = v.Path or PATHS[v.Id]
	if not path then
		return
	end
	if not fxFolder then
		local f = Instance.new("Folder")
		f.Name = "CT_Rocks_MachineFx"
		f.Parent = Workspace
		fxFolder = f
	end
	local part = newStone()
	part.Color = Config.Palette.Rock:Lerp(Color3.fromRGB(88, 94, 102), math.random())
	part.Size = Vector3.new(0.8, 0.6, 0.8)
	part.Transparency = 1
	part.Parent = fxFolder
	table.insert(v.Stones, { Part = part, T0 = os.clock() + delay, Dur = dur, Kind = v.Id, Path = path, Landed = false })
end

local function lerp(a: Vector3, b: Vector3, t: number): Vector3
	return a:Lerp(b, math.clamp(t, 0, 1))
end

-- One cosmetic stone per server rock cycle. Its stages are fractions of the cycle (s.Dur), so it
-- reaches the platen / rollers exactly when the machine parts do.
local function updateStone(v: View, s: Stone, now: number): boolean
	local k = (now - s.T0) / s.Dur
	if k < 0 then
		return true
	end
	if k >= 1 then
		if not s.Landed and s.Kind ~= "HydraulicPress" then
			s.Landed = true
			if not settings().LowEffects then
				for _, em in v.Emitters do
					em:Emit(2)
				end
			end
		end
		return false
	end
	local P = s.Path
	local pos: Vector3
	local size = Vector3.new(0.8, 0.6, 0.8)
	local alpha = 0
	if s.Kind == "HydraulicPress" then
		if k < 0.2 then
			pos = lerp(P.Start, P.Roller, k / 0.2) -- load onto the bed
		elseif k < 0.5 then
			pos = P.Roller -- waits under the open platen
		elseif k < 0.6 then
			pos = P.Roller -- flattened under the platen
			size = Vector3.new(1.1, 0.2, 1.1)
		else
			local u = (k - 0.6) / 0.4
			pos = lerp(P.Roller, P.Out, u) -- unload to the recovery chute
			size = Vector3.new(0.7, 0.3, 0.7)
			alpha = math.clamp((u - 0.6) / 0.4, 0, 1)
		end
	elseif k < 0.55 then
		pos = lerp(P.Start, P.BeltEnd, k / 0.55)
		pos = pos:Lerp(P.Roller, math.clamp((k - 0.4) / 0.15, 0, 1) * 0.5)
	elseif k < 0.7 then
		local u = (k - 0.55) / 0.15
		pos = P.Roller
		size = Vector3.new(0.8, 0.6, 0.8) * (1 - 0.45 * u)
	else
		local u = (k - 0.7) / 0.3
		pos = if u < 0.5 then lerp(P.Roller, P.Mid, u * 2) else lerp(P.Mid, P.Out, (u - 0.5) * 2)
		size = Vector3.new(0.45, 0.35, 0.45)
		alpha = math.clamp((u - 0.7) / 0.3, 0, 1)
	end
	s.Part.Size = size
	s.Part.CFrame = v.Frame * CFrame.new(pos)
	s.Part.Transparency = alpha
	return true
end

-- Animation --------------------------------------------------------------------------------

-- All curves take the cycle phase p (0..1 of ONE server rock cycle) and return 0..1.
local function smooth(k: number): number
	k = math.clamp(k, 0, 1)
	return k * k * (3 - 2 * k)
end

-- Press platen: open and loading to 0.15, down to contact at 0.5, held to 0.6, back up by 1.
local function pressK(p: number): number
	if p < 0.15 then
		return 0
	elseif p < 0.5 then
		local k = (p - 0.15) / 0.35
		return k * k
	elseif p < 0.6 then
		return 1
	end
	return 1 - smooth((p - 0.6) / 0.4)
end

-- Auto Cracker jaws: close to contact at 0.5, open again by 1.
local function jawK(p: number): number
	if p < 0.5 then
		return smooth(p / 0.5)
	end
	return 1 - smooth((p - 0.5) / 0.5)
end

local PRESS_FALLBACK_DROP = 4.1 -- the Part stand-in press drops this far

local function setPlate(v: View, k: number)
	for _, kp in v.KitPress do
		-- kit press: platen and piston slide down their Travel together
		kp.Piece.Part.CFrame = CFrame.new(kp.Piece.Base.Position + Vector3.new(0, -k * kp.Travel, 0)) * kp.Piece.Base.Rotation
	end
	local d = k * PRESS_FALLBACK_DROP
	for _, pc in v.Plate do
		pc.Part.CFrame = CFrame.new(pc.Base.Position + Vector3.new(0, -d, 0)) * pc.Base.Rotation
	end
	local rod = v.Rod
	if rod then
		local len = v.RodSize.X + d
		rod.Part.Size = Vector3.new(len, v.RodSize.Y, v.RodSize.Z)
		rod.Part.CFrame = CFrame.new(rod.Base.Position + Vector3.new(0, -d / 2, 0)) * rod.Base.Rotation
	end
end

-- Moves one machine. Everything that has a stroke (press platen, cracker jaws, feed stones) follows the
-- server's rock cycle: one Start event = one cycle of CycleDur seconds (Config seconds per rock), so
-- the visible strokes match the counter. Continuous parts (rollers, belt, hum) run only while cycles
-- keep arriving and wind down on their own; with no queue, a pause, a full bag or the round over the
-- machine settles open and silent.
local function animate(v: View, dt: number, now: number)
	local info = states[v.OwnerId]
	local st = if info then info.State else "None"
	v.State = st
	local cycleEnd = v.CycleAt + v.CycleDur
	local inCycle = st == "Running" and v.CycleDur > 0 and now >= v.CycleAt and now < cycleEnd
	local working = st == "Running" and v.CycleDur > 0 and now < cycleEnd + 0.35
	local target = if working then 1 else 0
	v.Speed += (target - v.Speed) * math.min(1, dt * (if working then 8 else 3)) -- winds up fast, down gently
	if v.Speed < 0.01 and target == 0 then
		v.Speed = 0
	end
	local reduced = settings().ReducedMotion
	local sp = v.Speed * (if reduced then 0.5 else 1)
	local p = if inCycle then (now - v.CycleAt) / v.CycleDur else 0

	-- state light
	local color = STATE_COLOR[st] or OFF
	local light = v.Light
	if light then
		light.Color = color
		local pl = light:FindFirstChildOfClass("PointLight")
		if pl then
			pl.Color = color
			pl.Enabled = st ~= "None"
		end
	end

	-- kit rubble pieces (bin / hopper) show while the machine is working
	if working ~= v.FillShown then
		v.FillShown = working
		for _, f in v.KitFill do
			f.Transparency = if working then 0 else 1
		end
	end

	-- sound (Audio owns caps, cooldowns, distance and the Sfx volume; positioned at the machine)
	local mpos = v.Frame.Position
	if working and v.Speed > 0.3 then
		if v.Id == "AutoCracker" then
			Audio.machineActive("m:" .. v.OwnerId, "Conveyor", mpos)
		elseif v.Id == "IndustrialCrusher" then
			Audio.machineActive("m:" .. v.OwnerId, "Crusher", mpos)
		end
	end

	-- stroke parts: platen (press) and jaws (auto cracker) follow the cycle phase
	if v.Id == "HydraulicPress" then
		local k = if inCycle then pressK(p) else 0
		if k ~= v.PlateD then
			v.PlateD = k
			setPlate(v, k)
		end
		if inCycle then
			local cues = v.Cues
			if p >= 0.15 and not cues.Descend then
				cues.Descend = true
				Audio.play("PressDescend", { Pos = mpos, Key = "PressDescend:" .. v.OwnerId })
			end
			if p >= 0.5 and not cues.Impact then
				cues.Impact = true
				Audio.play("PressImpact", { Pos = mpos, Key = "PressImpact:" .. v.OwnerId })
				if not settings().LowEffects then
					for _, em in v.Emitters do
						em:Emit(6)
					end
				end
			end
			if p >= 0.6 and not cues.Retract then
				cues.Retract = true
				Audio.play("PressRetract", { Pos = mpos, Key = "PressRetract:" .. v.OwnerId })
			end
		else
			table.clear(v.Cues)
		end
		if v.Beacon then
			local lamp = inCycle and p < 0.15
			local blink = working and (math.floor(now * 2) % 2 == 0)
			local beacon = v.Beacon :: BasePart
			beacon.Color = if lamp then Color3.fromRGB(255, 190, 60) elseif blink then Color3.fromRGB(190, 110, 30) else OFF
		end
	else
		-- auto cracker jaws: closed on the rock at p = 0.5, open at the cycle edges and whenever idle
		local jk = if inCycle then jawK(p) * (if reduced then 0.6 else 1) else 0
		if jk ~= v.JawT or #v.KitJaws > 0 then
			v.JawT = jk
			for _, j in v.KitJaws do
				j.Piece.Part.CFrame = j.Piece.Base + j.Delta * jk
			end
		end
		if v.Id == "AutoCracker" then
			if inCycle and p >= 0.5 and not v.Contact then
				v.Contact = true
				Audio.play("PressImpact", { Pos = mpos, Key = "JawContact:" .. v.OwnerId, Volume = 0.5 })
				if not settings().LowEffects then
					for _, em in v.Emitters do
						em:Emit(3)
					end
				end
			elseif not inCycle or p < 0.5 then
				v.Contact = false
			end
		end
	end

	-- continuous parts (belt tiles, rollers, flywheel, part-built jaws) only move while working
	if v.Id ~= "HydraulicPress" and not (sp == 0 and v.Rested) then
		v.Rested = sp == 0
		local speed = (if v.Id == "AutoCracker" then 6.3 else 4.0) * sp
		v.BeltOff += dt * speed
		for _, b in v.Belts do
			local pitch = b.Length / b.Count
			local zi = b.Z0 + (b.Order - 0.5) * pitch
			local zn = b.Z0 + ((zi - b.Z0 + v.BeltOff) % b.Length)
			local dz = zn - zi
			b.Tile.Part.CFrame = b.Tile.Base * CFrame.new(0, 0, dz)
			local chev = b.Chevron
			if chev then
				chev.Part.CFrame = chev.Base * CFrame.new(0, 0, dz)
			end
		end
		v.Angle += dt * (if v.Id == "AutoCracker" then 5 else 3.2) * sp
		for _, s in v.Spins do
			s.Model:PivotTo(s.Base * CFrame.Angles(s.Dir * v.Angle, 0, 0))
		end
		for _, r in v.KitRollers do
			r.Piece.Part.CFrame = CFrame.new(r.Pivot) * CFrame.fromAxisAngle(r.Axis, r.Dir * v.Angle) * CFrame.new(-r.Pivot) * r.Piece.Base
		end
		-- part-built jaws swing with the cycle (crusher stand-in), kept small
		local amp = if reduced then 0.05 else 0.12
		for _, j in v.Jaws do
			j.Model:PivotTo(j.Base * CFrame.Angles(0, 0, j.Dir * amp * math.sin(p * math.pi * 2) * (if inCycle then 1 else 0)))
		end
		if v.Id == "IndustrialCrusher" then
			local on = sp > 0.3 and not settings().LowEffects
			for _, em in v.Emitters do
				em.Enabled = on
			end
		end
	end

	-- cosmetic feed stones
	local i = 1
	while i <= #v.Stones do
		local s = v.Stones[i]
		if updateStone(v, s, now) then
			i += 1
		else
			s.Part.Parent = nil
			if #stonePool < 24 then
				table.insert(stonePool, s.Part)
			else
				s.Part:Destroy()
			end
			table.remove(v.Stones, i)
		end
	end
end

-- API --------------------------------------------------------------------------------------

-- The server's machine list for this match: { {UserId, Bay, Id, State} }.
function MachineView.setStates(list: { any })
	table.clear(states)
	for _, e in list do
		states[e.UserId] = { State = e.State, Id = e.Id }
	end
	active = next(states) ~= nil or next(views) ~= nil
	scan()
end

-- The server started one rock on `uid`'s machine (`seconds` = Config seconds per rock). That is one
-- cycle: a cycle that arrives just before the previous one ends continues it seamlessly, a late one starts
-- at once, and a burst of events in one batch (catch-up after lag) never queues extra strokes.
function MachineView.batch(uid: number, count: number, seconds: number)
	local v = viewOf(uid)
	if not v then
		scan()
		v = viewOf(uid)
	end
	if not v or (states[uid] and states[uid].State ~= "Running") then
		return
	end
	local view = v :: View
	local now = os.clock()
	local dur = math.clamp(seconds, 0.05, 3)
	local prevEnd = view.CycleAt + view.CycleDur
	view.CycleAt = if prevEnd > now and prevEnd - now < 0.15 then prevEnd else now
	view.CycleDur = dur
	view.Contact = false
	table.clear(view.Cues)
	-- one cosmetic stone per cycle; machines faster than ~4 rocks/s show a stone every 0.2 s at most
	if view.Id == "HydraulicPress" then
		spawnStone(view, view.CycleAt - now, dur)
	elseif now - view.LastStone >= 0.2 then
		view.LastStone = now
		spawnStone(view, view.CycleAt - now, math.max(dur, 0.45))
	end
end

-- The geode came out of `uid`'s machine: a short glint at its recovery chute. Effects respects
-- Reduced motion and Low effects.
function MachineView.recovered(uid: number)
	local v = viewOf(uid)
	if not v then
		return
	end
	local path = v.Path or PATHS[v.Id]
	if path then
		Effects.glint((v.Frame * CFrame.new(path.Out)).Position)
	end
end

-- Round over / left: machines wind down.
function MachineView.stop()
	for uid in states do
		states[uid].State = "None"
	end
end

function MachineView.clear()
	for uid in states do
		Audio.machineStop("m:" .. uid)
	end
	table.clear(states)
	for model, v in views do
		for _, s in v.Stones do
			s.Part.Parent = nil
		end
		views[model] = nil
	end
	active = false
	for model in watched do
		unwatch(model)
	end
end

function MachineView.start()
	RunService.RenderStepped:Connect(function(dt)
		if not active and next(views) == nil then
			return
		end
		local now = os.clock()
		if now - lastScan > 0.5 then
			lastScan = now
			scan()
		end
		local cam = Workspace.CurrentCamera
		for _, v in views do
			-- far-away arenas (other parties) are not animated
			if not cam or (cam.CFrame.Position - v.Frame.Position).Magnitude < 160 then
				animate(v, math.min(dt, 0.1), now)
			end
		end
	end)
end

return MachineView
