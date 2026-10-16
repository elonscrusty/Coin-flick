--!strict
-- Pet Tower juice (client only, pure presentation): a short camera shake, a red boss glow, the boss's coin and
-- sparkle burst, the gate light when a floor is cleared, the compact floor / theme title card, and a distinct
-- look per combat move (TowerFx.hit / TowerFx.special).
-- Every piece cleans itself up (Debris / tween end), counts are capped, and the viewer's settings apply:
-- Reduce Motion drops the shake, slides and bounces; Low Effects halves the pieces.

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local State = require(script.Parent.State)
local UI = require(script.Parent.ui.UI)
local PetStyle = require(script.Parent.ui.PetStyle)

local TowerFx = {}

local function setting(key: string): boolean
	local p = State.Profile
	return p ~= nil and p.Settings ~= nil and p.Settings[key] == true
end

local function folder(): Folder
	local f = Workspace:FindFirstChild("TowerFx")
	if f and f:IsA("Folder") then
		return f
	end
	local nf = Instance.new("Folder")
	nf.Name = "TowerFx"
	nf.Parent = Workspace
	return nf
end

-- Camera shake: a decaying offset added after the camera scripts each frame (so it never accumulates).
-- Small on purpose (at most ~0.35 stud); off with Reduce Motion.
local shakeUntil, shakeStart, shakePower = 0, 0, 0
local shakeBound = false
local SHAKE_NAME = "CTR_TowerShake"
function TowerFx.shake(power: number, duration: number)
	if setting("ReducedMotion") then
		return
	end
	if setting("LowEffects") then
		power *= 0.5 -- Low Effects: half the camera shake
		duration *= 0.6
	end
	local now = os.clock()
	shakeStart = now
	shakeUntil = now + duration
	shakePower = math.min(math.max(power, shakePower * math.max(0, (shakeUntil - now) / duration)), 0.35)
	if shakeBound then
		return
	end
	shakeBound = true
	RunService:BindToRenderStep(SHAKE_NAME, Enum.RenderPriority.Camera.Value + 1, function()
		local t = os.clock()
		local cam = Workspace.CurrentCamera
		if t >= shakeUntil or cam == nil then
			shakeBound = false
			shakePower = 0
			RunService:UnbindFromRenderStep(SHAKE_NAME)
			return
		end
		local k = 1 - (t - shakeStart) / math.max(shakeUntil - shakeStart, 0.01)
		local a = shakePower * k
		cam.CFrame = cam.CFrame * CFrame.new(math.sin(t * 61) * a, math.sin(t * 47 + 1.3) * a, 0) * CFrame.Angles(0, 0, math.sin(t * 39) * a * 0.02)
	end)
end

-- Boss entrance glow: a red outline and light that flare up, then settle to a faint menace glow.
function TowerFx.bossGlow(model: Model, color: Color3?)
	local c = color or Color3.fromRGB(255, 40, 30)
	local h = Instance.new("Highlight")
	h.Name = "BossGlow"
	h.FillColor = c
	h.OutlineColor = c
	h.FillTransparency = 0.35
	h.OutlineTransparency = 0
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Adornee = model
	h.Parent = model
	-- textured mesh pets ignore Color, so the glow itself carries the "angry red" (TowerView marks them TexturedBoss)
	local settle = if model:GetAttribute("TexturedBoss") then 0.55 else 0.85
	TweenService:Create(h, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FillTransparency = settle, OutlineTransparency = 0.5 }):Play()
	local body = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if body and not setting("LowEffects") then -- Low Effects keeps the red outline but drops the dynamic light
		local l = Instance.new("PointLight")
		l.Name = "BossLight"
		l.Color = c
		l.Range = 22
		l.Brightness = 6
		l.Parent = body
		TweenService:Create(l, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 1.2, Range = 14 }):Play()
	end
end

local COIN = Color3.fromRGB(255, 200, 50)
local liveCoins = 0
local MAX_COINS = 24

-- Boss faint: gold coins fly out and bounce down, plus a sparkle puff and a flash. Capped, gone in ~1.6 s.
function TowerFx.bossBurst(at: Vector3, groundY: number)
	local low = setting("LowEffects")
	local count = if low then 6 else 14
	local f = folder()
	-- flash + sparkles (one emitter, burst once)
	local a = Instance.new("Part")
	a.Name = "BossBurst"
	a.Anchored = true
	a.CanCollide = false
	a.CanQuery = false
	a.CanTouch = false
	a.Transparency = 1
	a.Size = Vector3.one
	a.Position = at
	a.Parent = f
	if not low then
		local light = Instance.new("PointLight")
		light.Color = COIN
		light.Range = 24
		light.Brightness = 8
		light.Parent = a
		TweenService:Create(light, TweenInfo.new(0.9), { Brightness = 0 }):Play()
	end
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(Color3.new(1, 1, 1), COIN)
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) })
	pe.Transparency = NumberSequence.new(0, 1)
	pe.Lifetime = NumberRange.new(0.6, 1.1)
	pe.Speed = NumberRange.new(8, 18)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Rate = 0
	pe.Parent = a
	pe:Emit(if low then 12 else 30)
	Debris:AddItem(a, 1.6)
	-- coins
	for i = 1, count do
		if liveCoins >= MAX_COINS then
			break
		end
		liveCoins += 1
		local c = Instance.new("Part")
		c.Name = "Coin"
		c.Shape = Enum.PartType.Cylinder
		c.Size = Vector3.new(0.25, 1.1, 1.1)
		c.Color = COIN
		c.Material = Enum.Material.Neon
		c.Anchored = true
		c.CanCollide = false
		c.CanQuery = false
		c.CanTouch = false
		c.CastShadow = false
		local ang = (i / count) * math.pi * 2 + math.random() * 0.4
		local out = Vector3.new(math.cos(ang), 0, math.sin(ang)) * (4 + math.random() * 5)
		c.CFrame = CFrame.new(at) * CFrame.Angles(0, ang, 0)
		c.Parent = f
		local up = at + out * 0.5 + Vector3.new(0, 4 + math.random() * 3, 0)
		local down = Vector3.new(at.X + out.X, groundY + 0.6, at.Z + out.Z)
		local spin = CFrame.Angles(math.rad(math.random(200, 520)), ang, 0)
		TweenService:Create(c, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(up) * spin }):Play()
		task.delay(0.35, function()
			if c.Parent then
				TweenService:Create(c, TweenInfo.new(0.5, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), { CFrame = CFrame.new(down) * spin * CFrame.Angles(0, 0, math.rad(90)) }):Play()
				TweenService:Create(c, TweenInfo.new(0.4, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, 0.7), { Transparency = 1 }):Play()
			end
		end)
		task.delay(1.5, function()
			liveCoins = math.max(liveCoins - 1, 0)
			c:Destroy()
		end)
	end
end

-- Floor clear: the far gate (TowerBuilder's GateL/GateR/GateTop arch) fills with light, then fades.
-- REPLACE: when the arena gets a real door model, open it here as well (light only for now).
function TowerFx.gateLight(origin: CFrame)
	local f = folder()
	local cf = origin * CFrame.new(0, 6, 31) -- arch centre: TowerBuilder RADIUS - 3, between the 12-stud posts
	local p = Instance.new("Part")
	p.Name = "GateLight"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(255, 240, 180)
	p.Transparency = 1
	p.Size = Vector3.new(9, if setting("ReducedMotion") then 12 else 0.2, 0.3)
	p.CFrame = cf * CFrame.new(0, if setting("ReducedMotion") then 0 else -5.9, 0)
	p.Parent = f
	local l = Instance.new("SurfaceLight")
	l.Face = Enum.NormalId.Back -- toward the arena centre (-Z of the gate)
	l.Color = p.Color
	l.Range = 30
	l.Angle = 120
	l.Brightness = 0
	l.Parent = p
	local open = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(p, open, { Transparency = 0.25, Size = Vector3.new(9, 12, 0.3), CFrame = cf }):Play()
	TweenService:Create(l, open, { Brightness = 5 }):Play()
	task.delay(2.6, function()
		if p.Parent then
			TweenService:Create(p, TweenInfo.new(0.8), { Transparency = 1 }):Play()
			TweenService:Create(l, TweenInfo.new(0.8), { Brightness = 0 }):Play()
		end
	end)
	Debris:AddItem(p, 3.6)
end

-- Theme title pill ("JUNGLE  ·  FLOORS 1-10"): one short line in a small pill under the tower HUD's floor card and
-- LEAVE, the same size family as the floor card, so it never covers the pets (bug 238). Drops in, holds, fades.
local card: Frame? = nil
-- True from the floor's first hit until the floor ends: the title pill never shows over pets that are fighting
-- (Studio 2026-10-14: "JUNGLE FLOORS" sat on top of the fight). The server holds a new theme's first wave
-- TowerConfig.TitleHold seconds so the pill has its moment before the first hit.
local fightOn = false
local CARD_Y = UI.T.Edge + 100 -- below the floor card and LEAVE (TowerPanel: LEAVE ends at T.Edge + 46 + 44)
function TowerFx.titleCard(title: string, sub: string, color: Color3)
	if fightOn then
		return -- the pets already fight (a late title, e.g. after the entry camera turn): the HUD floor label says it
	end
	if card then
		card:Destroy()
		card = nil
	end
	local reduced = setting("ReducedMotion")
	-- a glossy pill in the theme's colour (PetStyle.pill look, no button): lighter top, darker edge, outlined words
	local g = UI.frame(UI.noticeLayer(), {
		Name = "TowerTitleCard", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, if reduced then CARD_Y else CARD_Y - 16),
		Size = UDim2.new(0.7, 0, 0, 34), BackgroundColor3 = color,
	})
	card = g
	local lim = Instance.new("UISizeConstraint")
	lim.MaxSize = Vector2.new(260, 34)
	lim.Parent = g
	local edgeColor = color:Lerp(PetStyle.K.Ink, 0.5)
	PetStyle.round(g, 999)
	PetStyle.vgrad(g, color:Lerp(PetStyle.K.White, 0.45), color)
	PetStyle.edge(g, edgeColor, 2.5)
	PetStyle.words(g, if sub ~= "" then title .. "  \u{00B7}  " .. sub else title, UI.T.Body, {
		Name = "Title", Position = UDim2.fromOffset(10, 3), Size = UDim2.new(1, -20, 1, -6), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 2,
		OutlineColor = edgeColor, OutlineThick = 2.4,
	})
	if not reduced then
		TweenService:Create(g, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0, CARD_Y) }):Play()
	end
	task.delay(1.6, function()
		if card ~= g then
			return
		end
		local out = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		if not reduced then
			TweenService:Create(g, out, { Position = UDim2.new(0.5, 0, 0, CARD_Y - 12) }):Play()
		end
		TweenService:Create(g, out, { BackgroundTransparency = 1 }):Play()
		for _, d in g:GetDescendants() do
			if d:IsA("TextLabel") then
				TweenService:Create(d, out, { TextTransparency = 1 }):Play()
			elseif d:IsA("UIStroke") then
				TweenService:Create(d, out, { Transparency = 1 }):Play()
			end
		end
		task.delay(0.45, function()
			if card == g then
				card = nil
			end
			g:Destroy()
		end)
	end)
end

-- The floor's fight has started (first hit): the title goes at once and no late one shows.
function TowerFx.fightStarted()
	fightOn = true
	TowerFx.hideTitle()
end

-- The floor is over (floor-end card, revive, leaving): the next floor may show its title again.
function TowerFx.fightStopped()
	fightOn = false
end

-- Takes the title card down at once (a floor-end card or leaving the tower must never sit under it).
function TowerFx.hideTitle()
	if card then
		card:Destroy()
		card = nil
	end
end

-- Move looks (client only): every hit and SPECIAL gets its own short procedural effect, keyed by the attacker's
-- type and the hit grade, so moves read apart at a glance. Built-in particle textures only, a handful of anchored
-- neon parts each, every piece gone within ~0.6 s (Debris), live pieces capped for phones (Low Effects: fewer).
--   Fire   = ember bolt flying in + flame puff      Nature = green slash arc + leaf sparks
--   Earth  = ground shockwave ring + rock chunks     Storm  = zigzag bolt from above + yellow sparks
--   Ice    = shard star bursting out + frost ring    Cosmic = purple star burst + glow sphere
--   mobs / no type = small white impact puff
--   Strong = bigger, plus a ring in the attacker's colour; Weak = small and dim; Crit = gold star flash
local FIRE_TEX = "rbxasset://textures/particles/fire_main.dds"
local SPARK_TEX = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE_TEX = "rbxasset://textures/particles/smoke_main.dds"
local FX_LIFE = 0.55
local MAX_FX = 36 -- move-effect parts alive at once
local LOW_MAX_FX = 16
local liveFx = 0

local FxColor = {
	Fire = Color3.fromRGB(255, 120, 40),
	Nature = Color3.fromRGB(110, 225, 90),
	Earth = Color3.fromRGB(170, 120, 70),
	Storm = Color3.fromRGB(255, 230, 80),
	Ice = Color3.fromRGB(150, 225, 255),
	Cosmic = Color3.fromRGB(190, 120, 255),
} :: { [string]: Color3 }
local GOLD = Color3.fromRGB(255, 215, 70)
local WHITE = Color3.new(1, 1, 1)

local function room(n: number): boolean
	return liveFx + n <= (if setting("LowEffects") then LOW_MAX_FX else MAX_FX)
end

local function fxPart(shape: Enum.PartType, size: Vector3, cf: CFrame, color: Color3, life: number?): Part
	local p = Instance.new("Part")
	p.Name = "MoveFx"
	p.Shape = shape
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = folder()
	liveFx += 1
	p.Destroying:Once(function()
		liveFx = math.max(liveFx - 1, 0)
	end)
	Debris:AddItem(p, life or FX_LIFE)
	return p
end

local function tween(i: Instance, t: number, goal: { [string]: any }, style: Enum.EasingStyle?)
	TweenService:Create(i, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
end

-- Flat ring on the ground (or around a point) that widens and fades.
local function ring(at: Vector3, color: Color3, r0: number, r1: number, t: number)
	if not room(1) then
		return
	end
	local p = fxPart(Enum.PartType.Cylinder, Vector3.new(0.15, r0 * 2, r0 * 2), CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90)), color)
	p.Transparency = 0.2
	tween(p, t, { Size = Vector3.new(0.05, r1 * 2, r1 * 2), Transparency = 1 })
end

-- Glow ball that swells and fades.
local function orb(at: Vector3, color: Color3, d0: number, d1: number, t: number)
	if not room(1) then
		return
	end
	local p = fxPart(Enum.PartType.Ball, Vector3.one * d0, CFrame.new(at), color)
	p.Transparency = 0.3
	tween(p, t, { Size = Vector3.one * d1, Transparency = 1 })
end

-- One-shot particle burst from an invisible anchor (one part, one emitter).
local function burst(at: Vector3, color: Color3, tex: string, count: number, speed: number, size: number)
	if not room(1) then
		return
	end
	local a = fxPart(Enum.PartType.Block, Vector3.one * 0.2, CFrame.new(at), color, 0.9)
	a.Transparency = 1
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = tex
	pe.Color = ColorSequence.new(WHITE:Lerp(color, 0.4), color)
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	pe.Transparency = NumberSequence.new(0, 1)
	pe.Lifetime = NumberRange.new(0.25, 0.45)
	pe.Speed = NumberRange.new(speed * 0.5, speed)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Drag = 4
	pe.Rate = 0
	pe.Parent = a
	pe:Emit(if setting("LowEffects") then math.max(count // 2, 2) else count)
end

-- Thin glowing beam between two points that fades.
local function streak(a: Vector3, b: Vector3, color: Color3, thick: number, t: number)
	local len = (b - a).Magnitude
	if len < 0.05 or not room(1) then
		return
	end
	local p = fxPart(Enum.PartType.Block, Vector3.new(thick, thick, len), CFrame.lookAt((a + b) / 2, b), color)
	tween(p, t, { Size = Vector3.new(0.02, 0.02, len), Transparency = 1 })
end

-- Small glowing ball that flies from a to b, then pops.
local function bolt(a: Vector3, b: Vector3, color: Color3, d: number, fly: number, pop: () -> ())
	if not room(1) then
		pop()
		return
	end
	local p = fxPart(Enum.PartType.Ball, Vector3.one * d, CFrame.new(a), color, fly + 0.05)
	tween(p, fly, { CFrame = CFrame.new(b) }, Enum.EasingStyle.Linear)
	task.delay(fly, pop)
end

-- Slash arc: a few thin bars along a tilted arc in front of the target, fading fast.
local function slash(at: Vector3, face: Vector3, color: Color3, r: number)
	local n = if setting("LowEffects") then 3 else 5
	if not room(n) then
		return
	end
	local base = CFrame.lookAt(at, at + face) * CFrame.Angles(0, 0, math.rad(35))
	for i = 1, n do
		local ang = math.rad(-60 + 120 * (i - 1) / (n - 1))
		local cf = base * CFrame.new(math.sin(ang) * r, math.cos(ang) * r * 0.6, 0) * CFrame.Angles(0, 0, -ang)
		local p = fxPart(Enum.PartType.Block, Vector3.new(r * 0.55, 0.18, 0.18), cf, color)
		p.Transparency = 0.1
		task.delay((i - 1) * 0.025, function()
			if p.Parent then
				tween(p, 0.3, { Transparency = 1, Size = Vector3.new(r * 0.7, 0.05, 0.05) })
			end
		end)
	end
end

-- Little blocks thrown out from a point (rock chunks, ice shards, leaves).
local function shards(at: Vector3, color: Color3, n: number, dist: number, size: Vector3, up: number)
	n = if setting("LowEffects") then math.max(n // 2, 2) else n
	if not room(n) then
		return
	end
	local r = math.random() * math.pi
	for i = 1, n do
		local ang = r + (i / n) * math.pi * 2
		local dir = Vector3.new(math.cos(ang), 0, math.sin(ang))
		local p = fxPart(Enum.PartType.Block, size, CFrame.lookAt(at, at + dir), color)
		p.Material = Enum.Material.SmoothPlastic
		local goal = CFrame.lookAt(at + dir * dist + Vector3.new(0, up, 0), at + dir * (dist + 1)) * CFrame.Angles(math.random() * 3, 0, math.random() * 3)
		tween(p, 0.45, { CFrame = goal, Transparency = 1 })
	end
end

-- Zigzag lightning from high above down onto a point.
local function zigzag(to: Vector3, color: Color3, height: number, thick: number)
	local steps = 3
	local prev = to + Vector3.new((math.random() - 0.5) * 2, height, (math.random() - 0.5) * 2)
	for i = 1, steps do
		local nextP = if i == steps then to else prev:Lerp(to, 1 / (steps - i + 1)) + Vector3.new((math.random() - 0.5) * 1.6, 0, (math.random() - 0.5) * 1.6)
		streak(prev, nextP, color, thick, 0.3)
		prev = nextP
	end
end

-- One hit. `from` = attacker body point (nil = unknown), `to` = target body point, `ground` = target floor height.
-- grade: "Strong" | "Weak" | "Crit" | nil (normal). element nil = a mob or untyped hit.
function TowerFx.hit(from: Vector3?, to: Vector3, ground: number, element: string?, grade: string?)
	local k = if grade == "Strong" then 1.4 elseif grade == "Weak" then 0.7 elseif grade == "Crit" then 1.6 else 1
	local color = (element and FxColor[element]) or WHITE
	if grade == "Weak" then
		color = color:Lerp(Color3.fromRGB(150, 150, 160), 0.5)
	end
	local feet = Vector3.new(to.X, ground + 0.15, to.Z)
	local face = if from then (to - from) * Vector3.new(1, 0, 1) else Vector3.zAxis
	face = if face.Magnitude > 0.1 then face.Unit else Vector3.zAxis
	if element == "Fire" then
		local start = from or (to - face * 6)
		bolt(start + Vector3.new(0, 0.5, 0), to, color, 0.7 * k, 0.12, function()
			burst(to, color, FIRE_TEX, 8, 9 * k, 1.6 * k)
			orb(to, Color3.fromRGB(255, 200, 80), 0.8 * k, 3 * k, 0.25)
		end)
	elseif element == "Nature" then
		slash(to, face, color, 1.6 * k)
		burst(to, color, SPARK_TEX, 6, 7 * k, 0.6 * k)
	elseif element == "Earth" then
		ring(feet, color, 0.8, 4 * k, 0.4)
		shards(feet + Vector3.new(0, 0.3, 0), Color3.fromRGB(125, 95, 65), 4, 2.2 * k, Vector3.one * 0.45 * k, 1.6)
	elseif element == "Storm" then
		zigzag(to, color, 7, 0.22 * k)
		burst(to, color, SPARK_TEX, 8, 12 * k, 0.7 * k)
	elseif element == "Ice" then
		shards(to, color, 5, 2.4 * k, Vector3.new(0.18, 0.18, 0.9) * k, 0.4)
		ring(to, WHITE, 0.4, 2.4 * k, 0.3)
	elseif element == "Cosmic" then
		orb(to, color, 0.6 * k, 3.4 * k, 0.35)
		burst(to, Color3.fromRGB(255, 230, 140), SPARK_TEX, 8, 10 * k, 0.9 * k)
	else
		burst(to, WHITE, SMOKE_TEX, 5, 6 * k, 1.2 * k)
	end
	if grade == "Strong" and element then
		ring(to, FxColor[element] or WHITE, 0.6, 3.6, 0.35)
	elseif grade == "Crit" then
		orb(to, GOLD, 1, 5, 0.3)
		burst(to, GOLD, SPARK_TEX, 12, 16, 1.2)
	end
end

-- A SPECIAL by its Kind (TowerConfig.Specials): caster point, the standing mobs' and pets' points, floor height.
--   Burn = flame column on each mob       Slow = frost ring wave across the mob line   Chain = bolts hopping mob to mob
--   Heal = green rings rising on each pet Shield = bubble on each pet                  Stomp = big ground shockwave
--   Dash = speed streak caster -> front mob                                            Crit = gold star flash on the caster
function TowerFx.special(kind: string, caster: Vector3, mobs: { Vector3 }, pets: { Vector3 }, ground: number)
	local floorAt = function(v: Vector3): Vector3
		return Vector3.new(v.X, ground + 0.15, v.Z)
	end
	if kind == "Burn" then
		for _, m in mobs do
			burst(floorAt(m) + Vector3.new(0, 0.5, 0), FxColor.Fire, FIRE_TEX, 10, 10, 2)
			orb(m, Color3.fromRGB(255, 160, 60), 1, 3.5, 0.4)
		end
	elseif kind == "Slow" then
		local mid = Vector3.zero
		for _, m in mobs do
			mid += m
			ring(m, FxColor.Ice, 0.5, 2.8, 0.45)
		end
		if #mobs > 0 then
			ring(floorAt(mid / #mobs), Color3.fromRGB(200, 240, 255), 1, 9, 0.5)
		end
	elseif kind == "Chain" then
		local prev = caster
		for _, m in mobs do
			streak(prev, m, FxColor.Storm, 0.3, 0.35)
			burst(m, FxColor.Storm, SPARK_TEX, 6, 12, 0.8)
			prev = m
		end
	elseif kind == "Heal" then
		for _, p in pets do
			ring(floorAt(p), FxColor.Nature, 0.6, 2.6, 0.45)
			burst(floorAt(p) + Vector3.new(0, 1, 0), Color3.fromRGB(170, 255, 150), SPARK_TEX, 6, 5, 0.8)
		end
	elseif kind == "Shield" then
		for _, p in pets do
			if room(1) then
				local b = fxPart(Enum.PartType.Ball, Vector3.one * 2, CFrame.new(p), Color3.fromRGB(140, 210, 255))
				b.Material = Enum.Material.ForceField
				tween(b, 0.25, { Size = Vector3.one * 5 }, Enum.EasingStyle.Back)
				task.delay(0.3, function()
					if b.Parent then
						tween(b, 0.22, { Transparency = 1 })
					end
				end)
			end
		end
	elseif kind == "Stomp" then
		ring(floorAt(caster), FxColor.Earth, 1, 14, 0.5)
		ring(floorAt(caster), Color3.fromRGB(230, 200, 150), 0.5, 9, 0.4)
		for _, m in mobs do
			shards(floorAt(m) + Vector3.new(0, 0.3, 0), Color3.fromRGB(125, 95, 65), 3, 1.8, Vector3.one * 0.5, 1.8)
		end
		TowerFx.shake(0.18, 0.3)
	elseif kind == "Dash" then
		local front = mobs[1]
		if front then
			streak(caster, front, WHITE, 0.5, 0.25)
			streak(caster + Vector3.new(0, 0.8, 0), front + Vector3.new(0, 0.8, 0), Color3.fromRGB(150, 220, 255), 0.25, 0.35)
			ring(front, WHITE, 0.5, 3.5, 0.3)
		end
	elseif kind == "Crit" then
		orb(caster, GOLD, 1, 4.5, 0.35)
		burst(caster, GOLD, SPARK_TEX, 14, 14, 1.1)
	end
end

function TowerFx.clear()
	local f = Workspace:FindFirstChild("TowerFx")
	if f then
		f:Destroy()
	end
	liveCoins = 0
	liveFx = 0
end

return TowerFx
