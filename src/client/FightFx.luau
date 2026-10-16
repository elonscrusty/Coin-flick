--!strict
-- Big pet fight moments (client only, cosmetic; the server decides every hit, crit and KO). Built from the egg hatch
-- show's techniques (client HatchShow): field of view slam, decaying shake, white-then-colour screen flash, colour
-- correction pop, bloom spike, ground shockwave rings, blast spheres, hand-animated debris, light beams, slow motion.
--
--   FightFx.play(kind, opts)   kind: "hit" | "advantage" | "crit" | "special" | "ko" | "levelup" (FightFxRules)
--     opts.Target    the pet that is hit (Model) or a spot (Vector3); levelup: the pet levelling up
--     opts.Attacker  the attacking pet (special: the beam starts here, the charge glows here)
--     opts.Element   the attack element (Fire, Ice, Nature, Storm, Earth, Cosmic): colours sparks, rings, debris
--     opts.Color     overrides the colour (e.g. the winner's rarity colour)
--     opts.Damage    shows the number
--     opts.Mine      the local player's pet is in this moment: only then the screen effects play (camera, flash,
--                    colour, banner, slow motion). Everyone else nearby sees the world effects.
--     opts.Winner    ko: the winning pet gets the showcase (sky beam, confetti stars, happy bounce, WINNER! banner,
--                    and for the winner's owner a short camera push-in when opts.Cinematic is true)
--     opts.WinnerMine ko: false when the winner belongs to the rival (no WINNER! banner for the loser)
--     opts.Level     levelup: the new level
--     opts.OnImpact  special: called at the moment the beam lands (FightFx.SPECIAL_CHARGE seconds after play)
--   FightFx.speed()  1, or below 1 during slow motion: battle code scales its own pet movement by it.
--
-- Phone-cheap: every world piece is a few anchored parts with one tween each, debris comes from one pool of
-- FightFxRules.MAX_CHUNKS parts and one RenderStepped that stops when nothing flies, particles go through PetFx's
-- pool and budget, screen effects are gated (FightFxRules.takeScreen) and nothing plays far from the camera.
-- Reduce Motion: no camera moves, shake or slow motion, softer flash. Low Effects: half the debris, rings and stars.
-- No pet mouth opening or roar (owner rule); pets are only squashed (PetFx) and never re-rigged.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Rules = require(Shared.FightFxRules)
local PetFxRules = require(Shared.PetFxRules)
local PetFx = require(script.Parent.PetFx)
local CameraFx = require(script.Parent.CameraFx)
local CameraMode = require(script.Parent.CameraMode)
local State = require(script.Parent.State)
local UI = require(script.Parent.ui.UI)

local FightFx = {}

FightFx.SPECIAL_CHARGE = 0.7 -- s from play("special") to the impact
local WORLD_RANGE = 140 -- studs from the camera; further away nothing is built
local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(255, 205, 70)
local DUST = Color3.fromRGB(236, 228, 210)

local player = Players.LocalPlayer
local speed = 1
local gate = Rules.newGate()

local function settings(): { [string]: any }
	return (State.Profile and State.Profile.Settings) or {}
end

local function reduced(): boolean
	return UI.Reduced or settings().ReducedMotion == true
end

local function lowFx(): boolean
	return settings().LowEffects == true
end

function FightFx.speed(): number
	return speed
end

-- A tween whose length follows the slow motion at the moment it starts.
-- (Capped at one extra second, so a piece started in slow motion does not hang around long after it.)
local function stretched(t: number): number
	return math.min(t / math.max(speed, 0.05), t + 1)
end

local function tw(obj: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween
	local tween = TweenService:Create(obj, TweenInfo.new(stretched(t), style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tween:Play()
	return tween
end

-- Waits `t` seconds of fight time (longer in slow motion).
local function wait_(t: number)
	local left = t
	while left > 0 do
		left -= RunService.Heartbeat:Wait() * speed
	end
end

local fxFolder: Folder? = nil
local function folder(): Folder
	if fxFolder and fxFolder.Parent then
		return fxFolder
	end
	local f = Instance.new("Folder")
	f.Name = "CT_FightFx"
	f.Parent = Workspace
	fxFolder = f
	return f
end

local function neon(shape: Enum.PartType, color: Color3, size: Vector3, cf: CFrame, alpha: number, mat: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Shape = shape
	p.Material = mat or Enum.Material.Neon
	p.Color = color
	p.Size = size
	p.CFrame = cf
	p.Transparency = alpha
	p.Parent = folder()
	return p
end

-- Destroys a part after `t` seconds of fight time.
local function later(p: Instance, t: number)
	task.delay(stretched(t) + 0.1, function()
		p:Destroy()
	end)
end

local FLAT = CFrame.Angles(0, 0, math.rad(90))

local function centreOf(target: Model | Vector3): Vector3
	if typeof(target) == "Vector3" then
		return target
	end
	local m = target :: Model
	local h = m:GetAttribute("Height")
	return m:GetPivot().Position + Vector3.new(0, (if type(h) == "number" then h else 2) * 0.5, 0)
end

local function feetOf(target: Model | Vector3): Vector3
	if typeof(target) == "Vector3" then
		return target - Vector3.new(0, 1, 0)
	end
	return (target :: Model):GetPivot().Position
end

local function near(at: Vector3): boolean
	local cam = Workspace.CurrentCamera
	return cam == nil or (cam.CFrame.Position - at).Magnitude < WORLD_RANGE
end

-- Ground shockwave: a ring of glowing chips that races outwards and fades (a ring, never a filled glowing plate).
local RING_BITS = 14
local function shockwave(feet: Vector3, color: Color3, size: number, t: number, y: number?)
	local h = feet.Y + (y or 0.2)
	local r0 = 0.8
	local r1 = size / 2
	local bit = math.clamp(size / RING_BITS * 0.9, 0.5, 2.6)
	for i = 1, RING_BITS do
		local a = (i - 1) / RING_BITS * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local function place(r: number): CFrame
			local pos = Vector3.new(feet.X, h, feet.Z) + dir * r
			return CFrame.lookAt(pos, pos + dir)
		end
		local p = neon(Enum.PartType.Block, color, Vector3.new(bit * 0.5, 0.18, 0.25), place(r0), 0.05)
		tw(p, t, { CFrame = place(r1), Size = Vector3.new(bit, 0.08, 0.5), Transparency = 1 }, Enum.EasingStyle.Quart)
		later(p, t)
	end
end

-- A glowing sphere that swells and fades, plus a soft outer shell (kept small enough never to swallow the camera).
local function blast(at: Vector3, color: Color3, size: number)
	local a = neon(Enum.PartType.Ball, color, Vector3.one * 1.5, CFrame.new(at), 0.15)
	tw(a, 0.4, { Size = Vector3.one * size, Transparency = 1 }, Enum.EasingStyle.Quart)
	later(a, 0.4)
	local b = neon(Enum.PartType.Ball, WHITE, Vector3.one, CFrame.new(at), 0.4, Enum.Material.ForceField)
	tw(b, 0.6, { Size = Vector3.one * size * 1.2, Transparency = 1 }, Enum.EasingStyle.Quart)
	later(b, 0.7)
end

-- A light beam from a to b: fat and bright, then thin and gone.
local function beam(a: Vector3, b: Vector3, color: Color3, width: number, t: number)
	local len = (b - a).Magnitude
	if len < 0.1 then
		return
	end
	local cf = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0) -- cylinder axis along the beam
	local outer = neon(Enum.PartType.Cylinder, color, Vector3.new(len, width, width), cf, 0.25)
	local core = neon(Enum.PartType.Cylinder, WHITE, Vector3.new(len, width * 0.35, width * 0.35), cf, 0.05)
	tw(outer, t, { Size = Vector3.new(len, width * 0.15, width * 0.15), Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tw(core, t * 0.8, { Size = Vector3.new(len, 0.05, 0.05), Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	later(outer, t)
	later(core, t)
end

-- A pillar of light rising from the feet into the sky; it lingers `hold` seconds, then fades. See-through enough that
-- the pet standing in it stays visible (the fight camera's hero shot frames the winner inside it).
local function pillar(feet: Vector3, color: Color3, hold: number)
	local h = 60
	local outer = neon(Enum.PartType.Cylinder, color, Vector3.new(2, 4, 4), CFrame.new(feet + Vector3.new(0, 1, 0)) * FLAT, 0.7)
	local core = neon(Enum.PartType.Cylinder, WHITE, Vector3.new(2, 1.2, 1.2), CFrame.new(feet + Vector3.new(0, 1, 0)) * FLAT, 0.55)
	tw(outer, 0.35, { Size = Vector3.new(h, 3.2, 3.2), CFrame = CFrame.new(feet + Vector3.new(0, h / 2, 0)) * FLAT })
	tw(core, 0.35, { Size = Vector3.new(h, 0.9, 0.9), CFrame = CFrame.new(feet + Vector3.new(0, h / 2, 0)) * FLAT })
	task.delay(hold, function()
		if outer.Parent then
			tw(outer, 0.8, { Transparency = 1, Size = Vector3.new(h, 0.6, 0.6) })
			tw(core, 0.8, { Transparency = 1, Size = Vector3.new(h, 0.1, 0.1) })
		end
	end)
	later(outer, hold + 1)
	later(core, hold + 1)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Debris: pooled wedge chunks, hand-animated (FightFxRules.chunkStep) so slow motion slows them too.
type Chunk = { Part: Part, Pos: Vector3, Vel: Vector3, Rot: CFrame, Spin: Vector3, Alive: boolean, Ground: number, Rest: number }
local chunkPool: { Chunk } = {}
local chunkConn: RBXScriptConnection? = nil

local function chunkFrame(dt: number)
	local d = dt * speed
	local now = os.clock()
	local any = false
	for _, c in chunkPool do
		if c.Alive then
			any = true
			if c.Rest > 0 then
				if now > c.Rest then
					c.Alive = false
					c.Part.Transparency = 1
				else
					c.Part.Transparency = math.clamp(1 - (c.Rest - now) / 0.4, 0, 1)
				end
			else
				local settled
				c.Pos, c.Vel, settled = Rules.chunkStep(c.Pos, c.Vel, d, c.Ground)
				if settled then
					c.Rest = now + 1.2 -- lie a moment, then fade over the last 0.4 s
				else
					c.Rot *= CFrame.Angles(c.Spin.X * d, c.Spin.Y * d, c.Spin.Z * d)
				end
				c.Part.CFrame = CFrame.new(c.Pos) * c.Rot
			end
		end
	end
	if not any and chunkConn then
		chunkConn:Disconnect()
		chunkConn = nil
	end
end

local function debris(at: Vector3, color: Color3, n: number, ground: number, power: number)
	local made = 0
	for i = 1, Rules.MAX_CHUNKS do
		if made >= n then
			break
		end
		local c = chunkPool[i]
		if not c then
			local p = neon(Enum.PartType.Wedge, color, Vector3.one, CFrame.new(at), 1, Enum.Material.SmoothPlastic)
			c = { Part = p, Pos = at, Vel = Vector3.zero, Rot = CFrame.identity, Spin = Vector3.zero, Alive = false, Ground = 0, Rest = 0 }
			chunkPool[i] = c
		end
		if not c.Alive then
			made += 1
			local a = math.random() * math.pi * 2
			local s = 0.35 + math.random() * 0.45
			c.Part.Size = Vector3.new(s, s * (0.6 + math.random() * 0.6), s)
			c.Part.Color = if made % 3 == 0 then DUST else color
			c.Part.Transparency = 0
			c.Pos = at
			c.Vel = Vector3.new(math.cos(a) * (6 + math.random() * 10), 12 + math.random() * 14, math.sin(a) * (6 + math.random() * 10)) * power
			c.Rot = CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
			c.Spin = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 16
			c.Ground = ground + c.Part.Size.Y * 0.4
			c.Rest = 0
			c.Alive = true
		end
	end
	if made > 0 and not chunkConn then
		chunkConn = RunService.RenderStepped:Connect(chunkFrame)
	end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Screen effects (only the local player's own moments): flash frame, colour correction, bloom, banner.
local flashGui: ScreenGui? = nil
local flashFrame: Frame? = nil
local cc: ColorCorrectionEffect? = nil
local bloom: BloomEffect? = nil

local function screen(): (Frame, ColorCorrectionEffect, BloomEffect)
	if not (flashGui and flashGui.Parent) then
		local g = Instance.new("ScreenGui")
		g.Name = "CT_FightFlash"
		g.IgnoreGuiInset = true
		g.ResetOnSpawn = false
		g.DisplayOrder = 40
		local f = Instance.new("Frame")
		f.Size = UDim2.fromScale(1, 1)
		f.BorderSizePixel = 0
		f.BackgroundColor3 = WHITE
		f.BackgroundTransparency = 1
		f.Parent = g
		g.Parent = player:WaitForChild("PlayerGui")
		flashGui, flashFrame = g, f
	end
	if not (cc and cc.Parent) then
		local e = Instance.new("ColorCorrectionEffect")
		e.Name = "CT_FightColor"
		e.Parent = Lighting
		cc = e
	end
	if not (bloom and bloom.Parent) then
		local b = Instance.new("BloomEffect")
		b.Name = "CT_FightBloom"
		b.Intensity = 0
		b.Size = 24
		b.Threshold = 1.4
		b.Parent = Lighting
		bloom = b
	end
	return flashFrame :: Frame, cc :: ColorCorrectionEffect, bloom :: BloomEffect
end

-- The egg show's colour pop: white for a frame, then the moment's colour, fading out; colour grade and bloom spike.
local function screenPop(m: Rules.Moment, color: Color3)
	local f, e, b = screen()
	if m.Flash > 0 then
		-- never a full white frame (a K.O. in Studio washed the whole scene out): the colour, half towards white
		f.BackgroundColor3 = color:Lerp(WHITE, 0.5)
		f.BackgroundTransparency = 1 - math.min(m.Flash, Rules.MAX_FLASH)
		task.delay(0.05, function()
			f.BackgroundColor3 = color
			f.BackgroundTransparency = 1 - math.min(m.Flash, Rules.MAX_FLASH) * 0.8
			TweenService:Create(f, TweenInfo.new(0.55), { BackgroundTransparency = 1 }):Play()
		end)
	end
	if m.Tint > 0 then
		e.Brightness = 0.12 * m.Tint
		e.Contrast = 0.3 * m.Tint
		e.Saturation = 0.45 * m.Tint
		e.TintColor = color:Lerp(WHITE, 1 - 0.55 * m.Tint)
		TweenService:Create(e, TweenInfo.new(0.7), { Brightness = 0, Contrast = 0, Saturation = 0, TintColor = WHITE }):Play()
	end
	if m.Bloom > 0 then
		b.Intensity = math.min(m.Bloom, Rules.MAX_BLOOM)
		TweenService:Create(b, TweenInfo.new(0.5), { Intensity = 0 }):Play()
	end
	if m.Fov > 0 then
		CameraFx.punch(m.Fov, 0.55 + m.Rank * 0.05)
	end
	if m.Shake > 0 then
		CameraFx.shake(m.Shake, 0.25 + m.Shake * 0.45)
	end
end

-- A big word that slams onto the screen and slides away (K.O.!, SPECIAL!, LEVEL UP!, WINNER!).
local function banner(text: string, color: Color3, hold: number?)
	local g = Instance.new("ScreenGui")
	g.Name = "CT_FightBanner"
	g.IgnoreGuiInset = true
	g.ResetOnSpawn = false
	g.DisplayOrder = 41
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.3)
	holder.Size = UDim2.new(0.9, 0, 0, 90)
	holder.Parent = g
	local scale = Instance.new("UIScale")
	scale.Scale = if reduced() then 1 else 2.2
	scale.Parent = holder
	local label = UI.text(holder, text, {
		Font = UI.Head, TextSize = 64, Outline = "Strong", TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 1, 0),
	})
	g.Parent = player:WaitForChild("PlayerGui")
	if not reduced() then
		TweenService:Create(scale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	local stay = hold or 1.1
	task.delay(stay, function()
		TweenService:Create(holder, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromScale(0.5, 0.2) }):Play()
		TweenService:Create(label, TweenInfo.new(0.35), { TextTransparency = 1 }):Play()
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, TweenInfo.new(0.35), { Transparency = 1 }):Play()
		end
	end)
	task.delay(stay + 0.5, function()
		g:Destroy()
	end)
end

-- Slow motion for `real` seconds of real time at time scale k (newest call wins).
local slowToken = 0
local function slowmo(k: number, real: number)
	slowToken += 1
	local my = slowToken
	speed = k
	PetFx.setTimeScale(k)
	local e = cc
	if e and e.Parent then
		e.Saturation = -0.35
	end
	task.delay(real, function()
		if slowToken == my then
			speed = 1
			PetFx.setTimeScale(1)
			if e and e.Parent then
				TweenService:Create(e, TweenInfo.new(0.3), { Saturation = 0 }):Play()
			end
		end
	end)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Winner showcase camera (the winner's owner only, opts.Cinematic): a short push-in and slow orbit, then back.
local function showcaseCamera(winner: Model)
	local cam = Workspace.CurrentCamera
	if not cam or reduced() or cam:GetAttribute("CT_Cinematic") == true then
		return
	end
	local from = cam.CFrame
	local fov = cam.FieldOfView
	local focus = centreOf(winner)
	local flat = Vector3.new(from.Position.X - focus.X, 0, from.Position.Z - focus.Z)
	if flat.Magnitude < 1 then
		flat = Vector3.new(0, 0, 1)
	end
	local off = flat.Unit * 11 + Vector3.new(0, 3.5, 0)
	local ok = pcall(function()
		CameraMode.cinematic("FightWin", true)
		cam:SetAttribute("CT_Cinematic", true)
		cam.CameraType = Enum.CameraType.Scriptable
		TweenService:Create(cam, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
			CFrame = CFrame.lookAt(focus + off, focus), FieldOfView = 55,
		}):Play()
		task.wait(0.72)
		local t0 = os.clock()
		while os.clock() - t0 < 2 do
			local a = (os.clock() - t0) * 0.35
			cam.CFrame = CFrame.lookAt(focus + CFrame.Angles(0, a, 0) * off, focus)
			RunService.RenderStepped:Wait()
		end
		local back = TweenService:Create(cam, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { CFrame = from, FieldOfView = fov })
		back:Play()
		back.Completed:Wait()
	end)
	cam:SetAttribute("CT_Cinematic", nil)
	cam.CameraType = Enum.CameraType.Custom
	CameraMode.cinematic("FightWin", false)
	if not ok then
		CameraMode.restore()
	end
end

-- ---------------------------------------------------------------------------------------------------------------
export type Opts = {
	Target: (Model | Vector3)?,
	Attacker: Model?,
	Element: string?,
	Color: Color3?,
	Damage: number?,
	Quiet: boolean?, -- no CRIT! / number pops on the target (Pet Battle: TowerView already pops them)
	Mine: boolean?,
	Winner: Model?,
	WinnerColor: Color3?,
	Cinematic: boolean?,
	WinnerMine: boolean?, -- ko: false = the winner is the rival's (the loser never gets the WINNER! banner)
	Level: number?,
	OnImpact: (() -> ())?,
}

local function colorOf(o: Opts): Color3
	if o.Color then
		return o.Color
	end
	local c = (PetFxRules.ELEMENT_COLORS :: any)[tostring(o.Element)]
	return c or GOLD
end

local function impact(kind: string, m: Rules.Moment, o: Opts, at: Vector3, feet: Vector3, color: Color3)
	local mine = o.Mine == true
	local useScreen = mine and Rules.takeScreen(gate, m.Rank, os.clock(), m.SlowTime + 0.3)
	if useScreen then
		screenPop(m, color)
		if m.Slow < 1 then
			slowmo(m.Slow, m.SlowTime)
		end
		if m.Banner and kind ~= "levelup" then
			banner(m.Banner, if kind == "ko" then Color3.fromRGB(255, 110, 100) else color, if kind == "ko" then 1.3 else 0.9)
		end
	end
	if m.Chunks > 0 or m.Rings > 0 then
		blast(at, color, 3 + m.Rank * 0.9)
	end
	for i = 1, m.Rings do
		shockwave(feet, if i == 1 then WHITE elseif i % 2 == 0 then color else color:Lerp(WHITE, 0.4), 8 + i * 6 + m.Rank, 0.5 + i * 0.2, 0.1 + i * 0.06)
	end
	if m.Chunks > 0 then
		debris(at, color, m.Chunks, feet.Y, 0.7 + m.Rank * 0.08)
	end
	if m.Stars > 0 then
		PetFx.stars(at, m.Stars, WHITE, color, 10 + m.Rank * 3, 0.5 + m.Rank * 0.05)
	end
	if m.Pop then
		PetFx.pop(at + Vector3.new(0, 2, 0), m.Pop, color, true)
	end
end

local function playNow(kind: string, o: Opts)
	local m = Rules.moment(kind, lowFx(), reduced())
	local target: Model | Vector3 = o.Target or (o.Attacker :: any) or Vector3.zero
	local at = centreOf(target)
	if not near(at) then
		return
	end
	local feet = feetOf(target)
	local color = colorOf(o)
	local mine = o.Mine == true

	if kind == "hit" then
		PetFx.hit(target, { Element = o.Element, Damage = o.Damage, Quiet = o.Quiet })
		if mine and Rules.takeScreen(gate, m.Rank, os.clock()) then
			CameraFx.shake(m.Shake, 0.2)
		end
		return
	elseif kind == "advantage" or kind == "crit" then
		PetFx.hit(target, { Element = o.Element, Crit = kind == "crit", Damage = o.Damage, Quiet = o.Quiet })
		impact(kind, m, o, at, feet, color)
		return
	elseif kind == "levelup" then
		if typeof(target) == "Instance" then
			PetFx.levelUp(target :: Model, o.Level or 1)
			PetFx.happy(target :: Model)
		end
		pillar(feet, color, 1.2)
		impact(kind, m, o, at, feet, color) -- the words come from PetFx.levelUp over the pet (no second banner)
		return
	elseif kind == "special" then
		-- charge: the attacker glows, sparks rush in, a ring tightens at its feet, the world dims a little
		local src = if o.Attacker then centreOf(o.Attacker) else at + Vector3.new(0, 0, 6)
		local srcFeet = if o.Attacker then feetOf(o.Attacker) else feet
		local orb = neon(Enum.PartType.Ball, color, Vector3.one * 0.6, CFrame.new(src), 0.1)
		tw(orb, FightFx.SPECIAL_CHARGE, { Size = Vector3.one * 3.2, Transparency = 0.35 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local ring = neon(Enum.PartType.Cylinder, color, Vector3.new(0.12, 9, 9), CFrame.new(srcFeet + Vector3.new(0, 0.12, 0)) * FLAT, 0.3)
		tw(ring, FightFx.SPECIAL_CHARGE, { Size = Vector3.new(0.12, 2, 2), Transparency = 0.05 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		if o.Attacker then
			PetFx.squash(o.Attacker)
		end
		if mine and not reduced() then
			local _, e = screen()
			TweenService:Create(e, TweenInfo.new(FightFx.SPECIAL_CHARGE), { Brightness = -0.15, Contrast = 0.15 }):Play()
			CameraFx.shake(0.25, FightFx.SPECIAL_CHARGE)
		end
		for i = 1, 3 do
			task.delay((i - 1) * FightFx.SPECIAL_CHARGE / 3, function()
				PetFx.stars(src + Vector3.new(math.random() * 4 - 2, math.random() * 3, math.random() * 4 - 2), 6, WHITE, color, 3, 0.35)
			end)
		end
		wait_(FightFx.SPECIAL_CHARGE)
		orb:Destroy()
		ring:Destroy()
		-- release: a fat beam to the target and a big impact
		beam(src, at, color, 2.4, 0.45)
		if o.OnImpact then
			task.spawn(o.OnImpact)
		end
		PetFx.hit(target, { Element = o.Element, Crit = true, Damage = o.Damage, Quiet = o.Quiet })
		impact(kind, m, o, at, feet, color)
		return
	elseif kind == "ko" then
		PetFx.ko(target, mine) -- the owner sees the big K.O.! banner instead of the small pop
		impact(kind, m, o, at, feet, color)
		local w = o.Winner
		if w then
			wait_(m.SlowTime * m.Slow + 0.2) -- right after the slow motion
			local wc = o.WinnerColor or GOLD
			local wf = feetOf(w)
			pillar(wf, wc, 1.2) -- short: the hero shot that follows wants the winner itself
			shockwave(wf, wc, 22, 0.9)
			PetFx.happy(w)
			PetFx.stars(centreOf(w) + Vector3.new(0, 1, 0), 40, WHITE, wc, 14, 0.7)
			task.delay(0.35, function()
				PetFx.stars(centreOf(w) + Vector3.new(0, 2, 0), 30, Color3.fromRGB(255, 120, 200), Color3.fromRGB(120, 200, 255), 16, 0.6)
				if w.Parent then
					PetFx.happy(w)
				end
			end)
			if mine and o.WinnerMine ~= false then
				banner("WINNER!", GOLD, 1.6)
				if o.Cinematic then
					showcaseCamera(w)
				end
			end
		end
		return
	end
end

-- Plays one fight moment (see the top of this file). Returns at once; the moment runs on its own.
function FightFx.play(kind: string, opts: Opts?)
	local o: Opts = opts or {}
	task.spawn(function()
		local ok, err = pcall(function()
			playNow(kind, o)
		end)
		if not ok then
			warn("[FightFx] " .. tostring(err))
			speed = 1
			PetFx.setTimeScale(1)
		end
	end)
end

return FightFx
