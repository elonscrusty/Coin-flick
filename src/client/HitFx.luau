--!strict
-- Contact feedback for manual cracking (presentation only; the server decides every hit).
--  * crack stages: stageOf(progress) gives 0..4; the same neutral dark crack lines for every rock, so
--    the picture says "how far along" and never what the rock is.
--  * contact(): a small dust puff and 2 to 4 chips at the point where the tool met the rock.
--  * dust(): the lighter, rate-limited puff for a jackhammer held on the rock.
--  * split(): a quick break into a few chunks that settle and fade.
--  * poof(): the empty egg's little cloud: a ring of soft puffs that rise and fade (after split()).
--  * feathers(): a few pale flecks that flutter down after poof() (the empty egg's feather dust).
--  * nest(): a straw puff and a few straw bits where an egg lands in the nest (tray or plate).
--  * glowCracks(): the pale crack edges glow softly (StationView pulses them between taps).
--  * trail(): a rate-limited foot puff (speed boots dust trail, EggFx).
--  * bump(): a short camera kick for the local player's own last tap (Humanoid.CameraOffset, back to rest).
-- Everything comes from fixed pools (no per-hit allocation), one Heartbeat connection that drops itself
-- when nothing is alive, and LowEffects / ReducedMotion settings shrink or skip it. clear() frees all.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local State = require(script.Parent.State)

local HitFx = {}

local MAX_PUFFS, MAX_CHIPS = 12, 18
local CLOUD = Color3.fromRGB(240, 238, 232)
local DUST = Color3.fromRGB(176, 168, 156)
local CHIP = Color3.fromRGB(122, 118, 112)
local CRACK = Color3.fromRGB(24, 25, 29)
local CRACK_EDGE = Color3.fromRGB(206, 202, 192)
local GLOW_DIM = Color3.fromRGB(150, 122, 78)
local GLOW_HOT = Color3.fromRGB(255, 224, 150)
local STRAW = Color3.fromRGB(222, 190, 112)
local FEATHER = Color3.fromRGB(250, 248, 240)
local MAX_FEATHERS = 8

-- progress thresholds for stage 1..4
local STAGES = { 0.001, 0.25, 0.55, 0.8 }

type Fx = { Part: Part, Alive: boolean, T0: number, Dur: number, From: Vector3, Vel: Vector3, Size: number, Spin: Vector3, Kind: number }

local folder: Folder? = nil
local puffs: { Fx } = {}
local chips: { Fx } = {}
local feathers: { Fx } = {}
local conn: RBXScriptConnection? = nil
local lastDust = 0
local bumpToken = 0

local function settings(): any
	return (State.Profile and State.Profile.Settings) or {}
end

local function reduced(): boolean
	return settings().ReducedMotion == true
end

local function low(): boolean
	return settings().LowEffects == true
end

function HitFx.stageOf(progress: number): number
	local s = 0
	for i, t in STAGES do
		if progress >= t then
			s = i
		end
	end
	return s
end

local function ensure(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = "CT_Rocks_HitFx"
	f.Parent = Workspace
	folder = f
	table.clear(puffs)
	table.clear(chips)
	table.clear(feathers)
	return f
end

local function newPart(shape: Enum.PartType, color: Color3, mat: Enum.Material): Part
	local p = Instance.new("Part")
	p.Shape = shape
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = mat
	p.Color = color
	p.Transparency = 1
	p.Size = Vector3.one * 0.1
	p.Parent = ensure()
	return p
end

local function take(pool: { Fx }, max: number, kind: number): Fx?
	for _, fx in pool do
		if not fx.Alive then
			return fx
		end
	end
	if #pool >= max then
		return nil
	end
	local part = if kind == 1 then newPart(Enum.PartType.Ball, DUST, Enum.Material.SmoothPlastic) else newPart(Enum.PartType.Block, CHIP, Enum.Material.Slate)
	local fx: Fx = { Part = part, Alive = false, T0 = 0, Dur = 1, From = Vector3.zero, Vel = Vector3.zero, Size = 0.3, Spin = Vector3.zero, Kind = kind }
	table.insert(pool, fx)
	return fx
end

-- Chip colour: the shell of the egg being hit (the nearest model in the nest folder, its biggest part), so the
-- bits match the egg. Falls back to the fixed grey when no egg is near.
local lastEgg = CHIP -- the final split happens after the plate is cleared: reuse the colour of the taps before it
local function eggColor(pos: Vector3): Color3
	local nests = Workspace:FindFirstChild("CT_Rocks_StationFx")
	if not nests then
		return lastEgg
	end
	local best: Model? = nil
	local bestD = 4
	for _, m in nests:GetChildren() do
		if m:IsA("Model") and m:GetAttribute("PlateEgg") then
			local d = (m:GetPivot().Position - pos).Magnitude
			if d < bestD then
				best, bestD = m, d
			end
		end
	end
	if not best then
		return lastEgg
	end
	local big: BasePart? = nil
	local bigV = 0
	for _, d in best:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.5 then
			local v = d.Size.X * d.Size.Y * d.Size.Z
			if v > bigV then
				big, bigV = d, v
			end
		end
	end
	if big then
		lastEgg = big.Color
	end
	return lastEgg
end

-- Ballistic height with one small bounce on the surface the chip left (FLOOR below the contact point).
local CHIP_FLOOR = 0.4
local function chipY(y0: number, vy: number, t: number): number
	local g = 18
	local y = y0 + vy * t - 0.5 * g * t * t
	local floorY = y0 - CHIP_FLOOR
	if y >= floorY then
		return y
	end
	local tHit = (vy + math.sqrt(vy * vy + 2 * g * CHIP_FLOOR)) / g
	local vb = (g * tHit - vy) * 0.35 -- bounce speed: a third of the impact
	local t2 = t - tHit
	return math.max(floorY, floorY + vb * t2 - 0.5 * g * t2 * t2)
end

local function step()
	local now = os.clock()
	local any = false
	for _, pool in { puffs, chips, feathers } do
		for _, fx in pool do
			if fx.Alive then
				local k = (now - fx.T0) / fx.Dur
				if k >= 1 or not fx.Part.Parent then
					fx.Alive = false
					fx.Part.Transparency = 1
				else
					any = true
					local t = now - fx.T0
					if fx.Kind == 1 then
						local s = fx.Size * (0.5 + 1.1 * k)
						fx.Part.Size = Vector3.one * s
						fx.Part.Position = fx.From + fx.Vel * t
						fx.Part.Transparency = 0.45 + 0.55 * k
					elseif fx.Kind == 3 then
						-- feather: pops up a little, then drifts down slowly, swaying and rocking
						local sway = math.sin(t * 7 + fx.Spin.Y)
						local y = math.max(fx.From.Y - 0.6, fx.From.Y + fx.Vel.Y * t - 0.9 * t * t)
						local pos = Vector3.new(fx.From.X + fx.Vel.X * t, y, fx.From.Z + fx.Vel.Z * t) + Vector3.new(fx.Spin.X, 0, fx.Spin.Z) * (sway * 0.15)
						fx.Part.CFrame = CFrame.new(pos) * CFrame.Angles(0, fx.Spin.Y + t, sway * 0.6)
						fx.Part.Transparency = math.max(0.1, (k - 0.55) / 0.45)
					else
						-- ballistic chip, settles on its landing height and fades
						local pos = Vector3.new(fx.From.X + fx.Vel.X * t, chipY(fx.From.Y, fx.Vel.Y, t), fx.From.Z + fx.Vel.Z * t)
						fx.Part.CFrame = CFrame.new(pos) * CFrame.Angles(fx.Spin.X * t, fx.Spin.Y * t, fx.Spin.Z * t)
						fx.Part.Transparency = math.max(0, (k - 0.6) / 0.4)
					end
				end
			end
		end
	end
	if not any and conn then
		conn:Disconnect()
		conn = nil
	end
end

local function wake()
	if not conn then
		conn = RunService.Heartbeat:Connect(step)
	end
end

local rng = Random.new(7)

local function puff(pos: Vector3, size: number, lift: number, dur: number, color: Color3?, drift: Vector3?)
	local fx = take(puffs, MAX_PUFFS, 1)
	if not fx then
		return
	end
	fx.Alive, fx.T0, fx.Dur, fx.From, fx.Size = true, os.clock(), dur, pos, size
	fx.Part.Color = color or DUST
	fx.Vel = (drift or Vector3.zero) + Vector3.new(rng:NextNumber(-0.25, 0.25), lift, rng:NextNumber(-0.25, 0.25))
	fx.Part.Size = Vector3.one * size * 0.5
	fx.Part.Position = pos
	fx.Part.Transparency = 0.45
	wake()
end

-- One tool contact at `pos` (world), `strong` for the heavier hammer.
function HitFx.contact(pos: Vector3, strong: boolean?)
	if reduced() then
		puff(pos, 0.4, 0.2, 0.3)
		return
	end
	puff(pos, if strong then 1.1 else 0.9, 0.7, 0.5)
	local n = if low() then 2 else (if strong then 4 else 3)
	local col = eggColor(pos)
	for _ = 1, n do
		local fx = take(chips, MAX_CHIPS, 2)
		if not fx then
			break
		end
		local a = rng:NextNumber(0, math.pi * 2)
		local sp = rng:NextNumber(1.6, 3.2)
		fx.Alive, fx.T0, fx.Dur, fx.From = true, os.clock(), rng:NextNumber(0.35, 0.5), pos
		fx.Vel = Vector3.new(math.cos(a) * sp, rng:NextNumber(2.2, 3.6), math.sin(a) * sp)
		fx.Spin = Vector3.new(rng:NextNumber(-9, 9), rng:NextNumber(-9, 9), rng:NextNumber(-9, 9))
		fx.Part.Size = Vector3.new(0.14, 0.1, 0.12) * rng:NextNumber(0.8, 1.5)
		fx.Part.Color = col
		fx.Part.Transparency = 0
		fx.Part.Position = pos
	end
	wake()
end

-- Light contact dust for a jackhammer held on the rock: at most ~7 a second.
function HitFx.dust(pos: Vector3)
	local now = os.clock()
	if now - lastDust < 0.14 or reduced() then
		return
	end
	lastDust = now
	puff(pos, 0.5, 0.45, 0.4)
end

-- Quick break: a few chunks fly out a little, settle and fade; plus one bigger puff.
function HitFx.split(pos: Vector3)
	puff(pos, 1.5, 0.6, 0.6)
	local n = if reduced() then 0 elseif low() then 3 else 5
	local col = eggColor(pos)
	for _ = 1, n do
		local fx = take(chips, MAX_CHIPS, 2)
		if not fx then
			break
		end
		local a = rng:NextNumber(0, math.pi * 2)
		local sp = rng:NextNumber(1, 2.2)
		fx.Alive, fx.T0, fx.Dur, fx.From = true, os.clock(), 0.55, pos
		fx.Vel = Vector3.new(math.cos(a) * sp, rng:NextNumber(1.6, 2.6), math.sin(a) * sp)
		fx.Spin = Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(-6, 6), rng:NextNumber(-6, 6))
		fx.Part.Size = Vector3.new(0.26, 0.2, 0.24) * rng:NextNumber(0.8, 1.3)
		fx.Part.Color = col
		fx.Part.Transparency = 0
		fx.Part.Position = pos
	end
	wake()
end

-- The empty egg's little cloud: a soft pale ring that swells outward and drifts up, then fades.
function HitFx.poof(pos: Vector3)
	if reduced() then
		return
	end
	local n = if low() then 3 else 5
	local a0 = rng:NextNumber(0, math.pi * 2)
	for i = 1, n do
		local a = a0 + (i / n) * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		puff(pos + dir * 0.25 + Vector3.new(0, 0.15, 0), rng:NextNumber(0.8, 1.05), 0.9, 0.75, CLOUD, dir * 0.9)
	end
	HitFx.feathers(pos)
end

-- Feather dust: a few small pale flecks pop out of the cloud and flutter down (none with Reduced Motion).
function HitFx.feathers(pos: Vector3)
	if reduced() then
		return
	end
	for _ = 1, if low() then 2 else 4 do
		local fx = take(feathers, MAX_FEATHERS, 3)
		if not fx then
			break
		end
		local a = rng:NextNumber(0, math.pi * 2)
		local sp = rng:NextNumber(0.4, 0.9)
		fx.Alive, fx.T0, fx.Dur, fx.From = true, os.clock(), rng:NextNumber(1, 1.3), pos + Vector3.new(0, 0.3, 0)
		fx.Vel = Vector3.new(math.cos(a) * sp, rng:NextNumber(1, 1.5), math.sin(a) * sp)
		fx.Spin = Vector3.new(math.sin(a), rng:NextNumber(0, math.pi * 2), -math.cos(a)) -- sway axis (x, z) and phase (y)
		fx.Part.Size = Vector3.new(0.17, 0.02, 0.07) * rng:NextNumber(0.85, 1.2)
		fx.Part.Color = FEATHER
		fx.Part.Material = Enum.Material.SmoothPlastic
		fx.Part.Transparency = 0.1
		fx.Part.Position = fx.From
	end
	wake()
end

-- An egg lands in the nest (tray slot or plate): a small straw-coloured puff and a few straw bits.
-- `big` for the plate (the egg drops onto it); the tray gets a lighter one.
function HitFx.nest(pos: Vector3, big: boolean?)
	if reduced() then
		return
	end
	puff(pos, if big then 0.8 else 0.55, 0.35, 0.45, STRAW)
	local n = if low() then 0 elseif big then 4 else 2
	for _ = 1, n do
		local fx = take(chips, MAX_CHIPS, 2)
		if not fx then
			break
		end
		local a = rng:NextNumber(0, math.pi * 2)
		local sp = rng:NextNumber(0.8, 1.6)
		fx.Alive, fx.T0, fx.Dur, fx.From = true, os.clock(), rng:NextNumber(0.35, 0.45), pos
		fx.Vel = Vector3.new(math.cos(a) * sp, rng:NextNumber(1.6, 2.4), math.sin(a) * sp)
		fx.Spin = Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(-8, 8), rng:NextNumber(-8, 8))
		fx.Part.Size = Vector3.new(0.24, 0.04, 0.05) * rng:NextNumber(0.8, 1.3)
		fx.Part.Color = STRAW
		fx.Part.Transparency = 0
		fx.Part.Position = pos
	end
	wake()
end

-- Speed boots: a small dust puff at the feet (the caller paces it per avatar; the shared pool caps the total).
function HitFx.trail(pos: Vector3)
	if reduced() then
		return
	end
	puff(pos, if low() then 0.45 else 0.6, 0.35, 0.45)
end

-- A short camera kick (studs, mostly down) for the local player's own big moment. Off with Reduced Motion.
-- Uses the Humanoid's CameraOffset, which nothing else in the game sets, and always ends back at zero.
function HitFx.bump(strength: number)
	if reduced() then
		return
	end
	local char = game:GetService("Players").LocalPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	bumpToken += 1
	local my = bumpToken
	local t0 = os.clock()
	local c: RBXScriptConnection? = nil
	c = RunService.RenderStepped:Connect(function()
		local k = (os.clock() - t0) / 0.22
		if my ~= bumpToken or k >= 1 or not hum.Parent then
			if c then
				c:Disconnect()
			end
			if my == bumpToken and hum.Parent then
				hum.CameraOffset = Vector3.zero
			end
			return
		end
		local a = math.sin(k * math.pi * 3) * (1 - k) * strength
		hum.CameraOffset = Vector3.new(a * 0.35, -math.abs(a), 0)
	end)
end

-- Crack lines on a plate rock -----------------------------------------------------------------------
-- Lines are listed per stage as { direction on the rock (unit, local), spin, length fraction }. Every
-- rock gets the same set, laid on a sphere of 0.5 * size around `centre`, so they read as damage only.
type Line = { Dir: Vector3, Spin: number, Len: number }
local LINES: { [number]: { Line } } = {
	[1] = { { Dir = Vector3.new(0.1, 0.8, -0.6), Spin = 20, Len = 0.45 } },
	[2] = { { Dir = Vector3.new(-0.5, 0.7, -0.5), Spin = -50, Len = 0.4 }, { Dir = Vector3.new(0.5, 0.45, -0.75), Spin = 80, Len = 0.35 } },
	[3] = { { Dir = Vector3.new(0.0, 0.3, -1), Spin = 5, Len = 0.6 }, { Dir = Vector3.new(0.8, 0.5, -0.3), Spin = 35, Len = 0.45 }, { Dir = Vector3.new(-0.8, 0.4, -0.4), Spin = -25, Len = 0.45 } },
	[4] = { { Dir = Vector3.new(0.3, 1, -0.2), Spin = 110, Len = 0.7 }, { Dir = Vector3.new(-0.25, 0.2, -1), Spin = 70, Len = 0.6 }, { Dir = Vector3.new(0.9, 0.1, -0.5), Spin = -70, Len = 0.55 } },
}

export type Cracks = { Parts: { Part }, Edges: { Part }, Stage: number, Glow: number }

function HitFx.newCracks(): Cracks
	return { Parts = {}, Edges = {}, Stage = 0, Glow = 0 }
end

-- Brings the lines up to the stage of `progress` (never fewer lines; they only widen). `frame` is the
-- rock's CFrame (the table frame, so "-Z" points at the player), `size` its diameter, `parent` where
-- the lines live (they die with the rock).
function HitFx.setCracks(c: Cracks, parent: Instance, frame: CFrame, centre: Vector3, size: number, progress: number): { Part }
	local made: { Part } = {}
	local stage = HitFx.stageOf(progress)
	if stage <= c.Stage then
		return made
	end
	-- crack lines are a darker shade of the egg's own colour (the fixed dark grey when no egg is found)
	local egg = eggColor(centre)
	local crackDark = if egg == CHIP then CRACK else egg:Lerp(Color3.new(0, 0, 0), 0.62)
	for s = c.Stage + 1, stage do
		for _, def in LINES[s] do
			local dir = def.Dir.Unit
			local world = frame:VectorToWorldSpace(dir)
			local at = centre + world * (size * 0.64)
			local len = size * def.Len * 0.6
			local w = size * (0.028 + 0.007 * s)
			-- lay it flat on the surface (its up is the surface normal), turned about the normal
			local up = world
			local ref = if math.abs(up.Y) > 0.95 then Vector3.xAxis else Vector3.yAxis
			local right = ref:Cross(up).Unit
			local cf = CFrame.fromMatrix(at, right, up) * CFrame.Angles(0, math.rad(def.Spin), 0)
			-- a dark ribbon with a thinner pale fracture edge on it: reads on dark and on pale rocks alike
			for layer = 1, 2 do
				local p = Instance.new("Part")
				p.Name = "Crack"
				p.Anchored = true
				p.CanCollide = false
				p.CanQuery = false
				p.CanTouch = false
				p.CastShadow = false
				p.Material = Enum.Material.SmoothPlastic
				p.Color = if layer == 1 then crackDark else CRACK_EDGE
				p.Size = if layer == 1 then Vector3.new(len, w, w) else Vector3.new(len * 0.85, w * 0.4, w * 0.4)
				p.CFrame = if layer == 1 then cf else cf * CFrame.new(0, w * 0.35, 0)
				p.Parent = parent
				table.insert(c.Parts, p)
				table.insert(made, p)
				if layer == 2 then
					table.insert(c.Edges, p)
				end
			end
		end
	end
	c.Stage = stage
	return made
end

function HitFx.clearCracks(c: Cracks)
	for _, p in c.Parts do
		p:Destroy()
	end
	table.clear(c.Parts)
	table.clear(c.Edges)
	c.Stage = 0
	c.Glow = 0
end

-- Soft glow on the pale crack edges: level 0 = the plain edge, up to 1 = a warm glow. Same for every egg.
function HitFx.glowCracks(c: Cracks, level: number)
	level = math.clamp(level, 0, 1)
	if level == c.Glow then
		return
	end
	c.Glow = level
	for _, p in c.Edges do
		if level <= 0 then
			p.Material = Enum.Material.SmoothPlastic
			p.Color = CRACK_EDGE
		else
			p.Material = Enum.Material.Neon
			p.Color = GLOW_DIM:Lerp(GLOW_HOT, level)
		end
	end
end

function HitFx.clear()
	if conn then
		conn:Disconnect()
		conn = nil
	end
	if folder then
		folder:Destroy()
	end
	folder = nil
	table.clear(puffs)
	table.clear(chips)
	table.clear(feathers)
end

return HitFx
