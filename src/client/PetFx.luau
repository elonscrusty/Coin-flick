--!strict
-- Follower pet juice (client only, purely cosmetic; PetFollow calls this for every follower it builds):
--   shadow     a soft dark blob on the ground under each pet that shrinks and fades while the pet hops, flies
--              higher or jumps with its owner
--   aura       the rarity-colour ring under Uncommon+ pets breathes gently (mesh pets get one, the procedural
--              body already has its "Aura" ring)
--   shimmer    Golden / Rainbow pets give off small glints; Rainbow pets slowly cycle their colours
--   element    each pet element (TowerConfig species Element) has a tiny particle trait: Fire embers,
--              Ice snowflakes, Nature leaf motes, Storm sparks, Earth dust, Cosmic twinkles
--   thump      heavy pets (Mass band 2+) puff a dust ring when they land a hop
--   levelUp    ring of light, a star burst, a glow flash and "LEVEL UP" over a pet (PetLevelFx)
--   tiers      PetFxRules.look climbs Common -> Void Dragon: a bigger, brighter soft ground ring (never a glowing
--              plate), rising motes, little orbs circling the pet (Epic+), a soft glow light, a light pillar (chase pets and
--              the Void Dragon). Golden pets glow gold, Rainbow rings cycle their hue.
--   walk       sparkles drop behind Uncommon+ / Golden / Rainbow pets only while they walk
--   squash     happy bounce: two hops with stretch and squash (PetFollow.bounce, PetFx.squash); no bones touched
--   fights     hit(), ko(), pop() for the pet battle and training code: pooled spark bursts, a flash, CRIT! pops
-- Bursts come from a small pool of emitters (no per-hit instances), are skipped far from the camera, shrink with
-- Low Effects and share one particle budget for the whole client (PetFxRules).
-- Particle emitters are tagged "PetSparkle" so Low Effects turns them off (client PetSparkle). Reduce Motion stops the
-- colour cycling, aura breathing and dust rings. Every piece is a child of the pet model or cleaned up with Debris.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local TowerConfig = require(Shared.TowerConfig)
local Rules = require(Shared.PetFxRules)
local State = require(script.Parent.State)
local UI = require(script.Parent.ui.UI)

local PetFx = {}

local BIG_MASS = 4 -- kg: the heavier mass bands thump when they land
local THUMP_GAP = 0.3 -- s between thumps of one pet
local THUMP_RANGE = 60 -- studs from the camera
local MAX_DUST = 6 -- dust rings alive at once (whole client)
local SHIMMER_HZ = 10 -- rainbow colour updates per second

type Tint = { Part: BasePart, H: number, S: number, V: number }
export type Fx = {
	Shadow: BasePart,
	ShadowSize: number,
	Aura: BasePart?,
	AuraBase: number,
	AuraGround: boolean, -- our own ring: lies on the ground under the pet like the shadow (not in the hopping model)
	Rainbow: { Tint }?,
	NextTint: number,
	Big: boolean,
	Scale: number,
	Landings: number,
	NextThump: number,
	Look: Rules.Look,
	Orbs: { BasePart },
	Pillar: BasePart?,
	Step: ParticleEmitter?,
	Walking: boolean,
	Far: boolean,
	Shown: boolean,
}

local dustAlive = 0
local burstAt: (Vector3) -> any
local flash: (Vector3, number, Color3) -> ()

local function settings(): { [string]: any }
	return (State.Profile and State.Profile.Settings) or {}
end

local function reduced(): boolean
	return UI.Reduced or settings().ReducedMotion == true
end

local function lowFx(): boolean
	return settings().LowEffects == true
end

local function plainPart(name: string): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local function bodyOf(m: Model): BasePart?
	local b = m.PrimaryPart or m:FindFirstChild("Body", true)
	if b and b:IsA("BasePart") then
		return b
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "TypeGlow" and d.Name ~= "Aura" then
			return d
		end
	end
	return nil
end

local RunService = game:GetService("RunService")

local function seq(a: Color3, b: Color3): ColorSequence
	return ColorSequence.new(a, b)
end

-- The default ParticleEmitter texture (the engine's built-in sparkle) is used on purpose: no asset ids.
local function emitter(parent: BasePart, name: string, props: { [string]: any })
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.LightInfluence = 0
	e.LockedToPart = false
	for k, v in props do
		(e :: any)[k] = v
	end
	CollectionService:AddTag(e, "PetSparkle") -- Low Effects turns it off (client PetSparkle)
	e.Parent = parent
end

local function elementOf(mineral: any): string
	local sp: any = (TowerConfig.Species :: any)[mineral]
	return if sp and type(sp.Element) == "string" then sp.Element else TowerConfig.DefaultSpecies.Element
end

-- Tiny trait per element; rates are low so a full lobby stays well under a few hundred particles.
local function addElement(body: BasePart, element: string, s: number)
	local n = NumberSequence.new
	if element == "Fire" then
		emitter(body, "Embers", {
			Color = seq(Color3.fromRGB(255, 200, 80), Color3.fromRGB(255, 70, 20)), LightEmission = 1,
			Size = n(0.22 * s, 0), Lifetime = NumberRange.new(0.7, 1.1), Rate = 4, Speed = NumberRange.new(0.6, 1.4),
			SpreadAngle = Vector2.new(25, 25), EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, 2.5, 0),
		})
	elseif element == "Ice" then
		emitter(body, "Snowflakes", {
			Color = seq(Color3.new(1, 1, 1), Color3.fromRGB(180, 225, 255)), LightEmission = 0.4,
			Size = n(0.18 * s), Lifetime = NumberRange.new(1.2, 1.8), Rate = 3, Speed = NumberRange.new(0.2, 0.5),
			SpreadAngle = Vector2.new(180, 180), Acceleration = Vector3.new(0, -1.2, 0), RotSpeed = NumberRange.new(-90, 90),
			Transparency = n(0.1, 0.8),
		})
	elseif element == "Nature" then
		emitter(body, "Leaves", {
			Color = seq(Color3.fromRGB(150, 230, 90), Color3.fromRGB(70, 170, 60)), LightEmission = 0.2,
			Size = n(0.16 * s), Lifetime = NumberRange.new(1.2, 1.6), Rate = 2, Speed = NumberRange.new(0.3, 0.6),
			SpreadAngle = Vector2.new(180, 180), Acceleration = Vector3.new(0, -0.8, 0), RotSpeed = NumberRange.new(-120, 120),
			Transparency = n(0.15, 0.9),
		})
	elseif element == "Storm" then
		emitter(body, "Sparks", {
			Color = seq(Color3.fromRGB(255, 245, 140), Color3.fromRGB(120, 200, 255)), LightEmission = 1,
			Size = n(0.2 * s, 0), Lifetime = NumberRange.new(0.15, 0.3), Rate = 3, Speed = NumberRange.new(2, 3.5),
			SpreadAngle = Vector2.new(180, 180),
		})
	elseif element == "Earth" then
		emitter(body, "Dust", {
			Color = seq(Color3.fromRGB(190, 160, 120), Color3.fromRGB(150, 120, 90)), LightEmission = 0,
			Size = n(0.25 * s, 0.45 * s), Lifetime = NumberRange.new(0.5, 0.8), Rate = 2, Speed = NumberRange.new(0.3, 0.6),
			SpreadAngle = Vector2.new(60, 60), EmissionDirection = Enum.NormalId.Bottom, Transparency = n(0.5, 1),
		})
	elseif element == "Cosmic" then
		emitter(body, "Twinkles", {
			Color = seq(Color3.fromRGB(230, 170, 255), Color3.fromRGB(140, 160, 255)), LightEmission = 1,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.26 * s), NumberSequenceKeypoint.new(1, 0) }),
			Lifetime = NumberRange.new(0.8, 1.1), Rate = 3, Speed = NumberRange.new(0.1, 0.3), SpreadAngle = Vector2.new(180, 180),
		})
	end
end

local FLAT = CFrame.Angles(0, 0, math.rad(90)) -- a Cylinder part lying flat (its axis pointing up)
local PILLAR_H = 7 -- studs per pet scale

local function groundRing(name: string, color: Color3, alpha: number, size: number): Part
	local ring = plainPart(name)
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.SmoothPlastic
	ring.Color = color
	ring.Transparency = alpha
	ring.Size = Vector3.new(0.05, size, size)
	return ring
end

local function sparkleSize(peak: number): NumberSequence
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, peak), NumberSequenceKeypoint.new(1, 0) })
end

-- Tier pieces that live on the pet body: rising motes and a soft glow light (both tagged, so Low Effects and far
-- pets turn them off).
local function addTier(body: BasePart, look: Rules.Look, s: number)
	if look.Motes > 0 then
		emitter(body, "AuraMotes", {
			Color = if look.Rainbow
				then ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromHSV(0, 0.55, 1)),
					ColorSequenceKeypoint.new(0.5, Color3.fromHSV(0.45, 0.55, 1)),
					ColorSequenceKeypoint.new(1, Color3.fromHSV(0.8, 0.55, 1)),
				})
				else seq(look.Accent, look.Color),
			LightEmission = if look.Void then 0.6 else 1, Rate = look.Motes,
			Lifetime = NumberRange.new(1.2, 1.8), Speed = NumberRange.new(0.2, 0.5), SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(0, 1.6, 0), Size = sparkleSize((0.18 + 0.03 * look.Tier) * s),
			Transparency = NumberSequence.new(0.1, 0.6), RotSpeed = NumberRange.new(-80, 80),
		})
	end
	if look.Light > 0 then
		local l = Instance.new("PointLight")
		l.Name = "AuraLight"
		l.Color = look.Color
		l.Brightness = look.Light
		l.Range = 5 + 1.5 * look.Tier
		l.Shadows = false
		CollectionService:AddTag(l, "PetSparkle")
		l.Parent = body
	end
end

-- Walk sparkles: the emitter always exists, update() sets its Rate (0 while standing still).
local function addStep(body: BasePart, look: Rules.Look, s: number): ParticleEmitter?
	if look.Trail <= 0 then
		return nil
	end
	local e = Instance.new("ParticleEmitter")
	e.Name = "WalkSparkle"
	e.LightEmission = 1
	e.LockedToPart = false
	e.Rate = 0
	e.Color = if look.Rainbow
		then ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromHSV(0, 0.6, 1)),
			ColorSequenceKeypoint.new(0.33, Color3.fromHSV(0.15, 0.6, 1)),
			ColorSequenceKeypoint.new(0.66, Color3.fromHSV(0.5, 0.6, 1)),
			ColorSequenceKeypoint.new(1, Color3.fromHSV(0.78, 0.6, 1)),
		})
		else seq(look.Accent, look.Color)
	e.Lifetime = NumberRange.new(0.5, 0.8)
	e.Speed = NumberRange.new(0.2, 0.6)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, -0.6, 0)
	e.Size = sparkleSize(0.24 * s)
	e.RotSpeed = NumberRange.new(-120, 120)
	CollectionService:AddTag(e, "PetSparkle")
	e.Parent = body
	return e
end

-- Builds the extras for one follower. `shadowParent` is the followers folder: the shadow stays on the ground, so it is
-- not part of the hopping model.
function PetFx.attach(m: Model, spec: { [string]: any }, s: number, shadowParent: Instance): Fx
	-- the blob follows the pet's real footprint (mesh pets know their Radius), not just the base scale
	local radius = m:GetAttribute("Radius")
	local shadowSize = if type(radius) == "number" and radius > 0 then math.clamp(radius * 2.1, 1.2, 2.1 * s * 1.6) else 2.1 * s
	local shadow = plainPart("PetShadow")
	shadow.Shape = Enum.PartType.Cylinder
	shadow.Material = Enum.Material.SmoothPlastic
	shadow.Color = Color3.new(0, 0, 0)
	shadow.Transparency = 0.6
	shadow.Size = Vector3.new(0.04, shadowSize, shadowSize)
	shadow.Parent = shadowParent

	-- rarity aura (PetFxRules tiers): reuse the procedural ring, or add one under a mesh pet
	local look = Rules.look(spec.Rarity or "Common", spec.Mineral, spec.Modifier)
	local aura: BasePart? = nil
	local auraGround = false
	local found = m:FindFirstChild("Aura", true)
	if found and found:IsA("BasePart") then
		aura = found
		if spec.Modifier == "Golden" or look.Tier >= 5 then
			found.Color = look.Color
		end
	elseif look.Ring > 0 then
		local ring = groundRing("Aura", look.Color, look.Alpha, look.Ring * s)
		-- soft and flat on the ground, centred under the pet each frame (in the model it leaned and trailed with the hop)
		ring.CFrame = CFrame.new(m:GetPivot().Position) * FLAT
		ring.Parent = shadowParent
		aura = ring
		auraGround = true
	end
	local orbs: { BasePart } = {}
	for i = 1, look.Orbs do
		local o = plainPart("AuraOrb")
		o.Shape = Enum.PartType.Ball
		o.Material = Enum.Material.Neon
		o.Color = if look.Void and i % 2 == 0 then Color3.fromRGB(40, 20, 70) else (if i % 2 == 0 then look.Accent else look.Color)
		o.Transparency = 0.15
		o.Size = Vector3.one * (0.22 + 0.02 * look.Tier) * s
		o.Parent = shadowParent
		table.insert(orbs, o)
	end
	local pillar: BasePart? = nil
	if look.Pillar then
		local pl = plainPart("AuraPillar")
		pl.Shape = Enum.PartType.Cylinder
		pl.Material = Enum.Material.Neon
		pl.Color = look.Color
		pl.Transparency = 0.9
		pl.Size = Vector3.new(PILLAR_H * s, look.Ring * 0.45 * s, look.Ring * 0.45 * s)
		pl.Parent = shadowParent
		pillar = pl
	end

	local body = bodyOf(m)
	local rainbow: { Tint }? = nil
	local step: ParticleEmitter? = nil
	if body then
		addElement(body, elementOf(spec.Mineral), s)
		addTier(body, look, s)
		step = addStep(body, look, s)
		if spec.Modifier == "Golden" or spec.Modifier == "Rainbow" then
			emitter(body, "Shimmer", {
				Color = if spec.Modifier == "Golden"
					then seq(Color3.fromRGB(255, 240, 170), Color3.fromRGB(255, 196, 64))
					else ColorSequence.new({
						ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 120, 120)),
						ColorSequenceKeypoint.new(0.5, Color3.fromRGB(120, 255, 160)),
						ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 140, 255)),
					}),
				LightEmission = 1, Rate = 3, Lifetime = NumberRange.new(0.35, 0.6), Speed = NumberRange.new(0, 0.2),
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, 0.32 * s), NumberSequenceKeypoint.new(1, 0) }),
				RotSpeed = NumberRange.new(-60, 60),
			})
		end
	end
	if spec.Modifier == "Rainbow" then
		-- the Rainbow paint is saturation ~0.55-0.7 at full value (PetModel); eyes and dark pieces never match
		local list: { Tint } = {}
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") and d.Name ~= "Aura" and d.Name ~= "TypeGlow" then
				local h, sat, v = d.Color:ToHSV()
				if sat > 0.45 and sat < 0.8 and v > 0.9 then
					table.insert(list, { Part = d, H = h, S = sat, V = v })
				end
			end
		end
		rainbow = if #list > 0 then list else nil
	end

	return {
		Shadow = shadow,
		ShadowSize = shadowSize,
		Aura = aura,
		AuraBase = if aura then aura.Transparency else 0,
		AuraGround = auraGround,
		Rainbow = rainbow,
		NextTint = 0,
		Big = (tonumber(spec.Mass) or 0) >= BIG_MASS,
		Scale = s,
		Landings = 0,
		NextThump = 0,
		Look = look,
		Orbs = orbs,
		Pillar = pillar,
		Step = step,
		Walking = false,
		Far = false,
		Shown = true,
	}
end

-- The ground pieces that live in the followers folder (not inside the pet model).
local function groundPieces(fx: Fx): { BasePart }
	local list: { BasePart } = { fx.Shadow }
	if fx.AuraGround and fx.Aura then
		table.insert(list, fx.Aura)
	end
	if fx.Pillar then
		table.insert(list, fx.Pillar)
	end
	for _, o in fx.Orbs do
		table.insert(list, o)
	end
	return list
end

function PetFx.destroy(fx: Fx)
	for _, p in groundPieces(fx) do
		p:Destroy()
	end
end

-- Shows or hides the ground pieces with the model (PetFollow parks a model with Parent = nil).
function PetFx.setShown(fx: Fx, shown: boolean, parent: Instance)
	local want: Instance? = if shown then parent else nil
	for _, p in groundPieces(fx) do
		if p.Parent ~= want then
			p.Parent = want
		end
	end
end

-- The orbs and pillar are pure show: hidden far away and with Low Effects.
local function showExtras(fx: Fx, on: boolean)
	fx.Shown = on
	for _, o in fx.Orbs do
		o.Transparency = if on then 0.15 else 1
	end
	if fx.Pillar then
		fx.Pillar.Transparency = if on then 0.9 else 1
	end
end

-- Pets far from the camera (PetFollow decides, with hysteresis) hide their particles, trails, lights and shadow.
-- Restoring honours Low Effects, so a far pet coming back never re-enables what the setting turned off.
function PetFx.setFar(fx: Fx, model: Model, far: boolean)
	local on = not far and not lowFx()
	for _, d in CollectionService:GetTagged("PetSparkle") do
		if d:IsDescendantOf(model) and (d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Light") or d:IsA("Sparkles") or d:IsA("Beam")) then
			(d :: any).Enabled = on
		end
	end
	fx.Shadow.Transparency = if far then 1 else 0.6
	fx.Far = far
	showExtras(fx, on)
end

local function thump(at: Vector3, s: number)
	if dustAlive >= MAX_DUST then
		return
	end
	dustAlive += 1
	local ring = plainPart("PetThump")
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.SmoothPlastic
	ring.Color = Color3.fromRGB(205, 185, 150)
	ring.Transparency = 0.45
	ring.Size = Vector3.new(0.05, 1.2 * s, 1.2 * s)
	ring.CFrame = CFrame.new(at + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = Workspace
	local tw = TweenService:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.05, 3.6 * s, 3.6 * s), Transparency = 1,
	})
	tw:Play()
	task.delay(0.4, function()
		dustAlive -= 1
	end)
	Debris:AddItem(ring, 0.4)
end

-- Per frame. groundPos = the pet's feet on the ground (no hop); hop = current hop height; phase = PetFollow's hop
-- phase (a landing happens each time it passes a multiple of pi); moving = hopping right now; camPos for range checks;
-- rise = extra height above the hop (a flyer's hover, a jump), so the shadow keeps shrinking and fading as it rises.
-- walking = the pet is moving along (any pet, mesh or not): turns the walk sparkles on.
function PetFx.update(fx: Fx, groundPos: Vector3, hop: number, phase: number, moving: boolean, t: number, camPos: Vector3, rise: number?, walking: boolean?)
	local k = math.clamp(hop / 0.55, 0, 1)
	local r = math.clamp((rise or 0) / 2.5, 0, 1)
	local size = fx.ShadowSize * (1 - 0.3 * k) * (1 - 0.4 * r)
	fx.Shadow.Size = Vector3.new(0.04, size, size)
	fx.Shadow.Transparency = math.min(0.95, 0.6 + 0.2 * k + 0.25 * r)
	fx.Shadow.CFrame = CFrame.new(groundPos + Vector3.new(0, 0.03, 0)) * CFrame.Angles(0, 0, math.rad(90))

	local still = reduced()
	if fx.Aura and fx.AuraGround then
		fx.Aura.CFrame = CFrame.new(groundPos + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90))
	end
	if fx.Aura then
		fx.Aura.Transparency = if still then fx.AuraBase else math.clamp(fx.AuraBase + 0.15 * math.sin(t * 2.4), 0, 1)
	end
	local showy = not fx.Far and not lowFx()
	if showy ~= fx.Shown then
		showExtras(fx, showy)
	end
	if fx.Pillar then
		fx.Pillar.CFrame = CFrame.new(groundPos + Vector3.new(0, PILLAR_H * fx.Scale * 0.5, 0)) * FLAT
		if showy then
			fx.Pillar.Transparency = if still then 0.9 else 0.87 + 0.06 * math.sin(t * 1.7)
		end
	end
	local n = #fx.Orbs
	if n > 0 and showy then
		local rad = fx.Look.Ring * fx.Scale * 0.42
		local spinT = if still then 0 else t
		for i, o in fx.Orbs do
			local a = spinT * 1.4 + (i - 1) * (2 * math.pi / n)
			local bob = if still then 0.6 else 0.6 + 0.25 * math.sin(spinT * 2 + i)
			o.CFrame = CFrame.new(groundPos + Vector3.new(math.cos(a) * rad, bob * fx.Scale + (rise or 0) * 0.5, math.sin(a) * rad))
		end
	end
	local walk = walking == true and showy
	if fx.Step and walk ~= fx.Walking then
		fx.Walking = walk
		fx.Step.Rate = if walk then fx.Look.Trail else 0
	end
	local retint = not still and t >= fx.NextTint
	if retint then
		fx.NextTint = t + 1 / SHIMMER_HZ
	end
	if fx.Look.Rainbow and fx.Aura and retint then
		local h = (t * 0.12) % 1
		fx.Aura.Color = Color3.fromHSV(h, 0.6, 1)
	end
	if fx.Rainbow and retint then
		local shift = (t * 0.12) % 1
		for _, tint in fx.Rainbow do
			tint.Part.Color = Color3.fromHSV((tint.H + shift) % 1, tint.S, tint.V)
		end
	end

	local landings = math.floor(phase / math.pi)
	if landings ~= fx.Landings then
		fx.Landings = landings
		if fx.Big and moving and t >= fx.NextThump and not still and not lowFx() and (groundPos - camPos).Magnitude < THUMP_RANGE then
			fx.NextThump = t + THUMP_GAP
			thump(groundPos, fx.Scale)
		end
	end
end

-- Ring of light + "LEVEL UP" over a pet (PetLevelFx). Lives about 1.6 s, then Debris removes it.
function PetFx.levelUp(model: Model, level: number)
	local pivot = model:GetPivot()
	local feet = pivot.Position
	local h = model:GetAttribute("Height")
	local height = if type(h) == "number" then h else 2
	local gold = Color3.fromRGB(255, 214, 90)
	local still = reduced()
	local centre = feet + Vector3.new(0, height * 0.5, 0)
	local n = PetFx.spend(centre, Rules.LEVEL_COUNT)
	if n > 0 then
		local b = burstAt(centre)
		b.Star.Color = seq(Color3.fromRGB(255, 250, 210), gold)
		b.Star.Size = sparkleSize(0.55)
		b.Star.Speed = NumberRange.new(6, 11)
		b.Star:Emit(n)
		flash(centre, 2 + height * 0.6, gold)
	end

	for i = 1, 2 do
		local ring = plainPart("LevelRing")
		ring.Shape = Enum.PartType.Cylinder
		ring.Material = Enum.Material.Neon
		ring.Color = gold
		ring.Transparency = 0.2
		ring.Size = Vector3.new(0.06, 1.5, 1.5)
		ring.CFrame = CFrame.new(feet + Vector3.new(0, 0.08 + (i - 1) * 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
		ring.Parent = Workspace
		if still then
			ring.Size = Vector3.new(0.06, 4, 4)
			TweenService:Create(ring, TweenInfo.new(1), { Transparency = 1 }):Play()
		else
			local goal = ring.CFrame + Vector3.new(0, if i == 2 then height + 0.6 else 0, 0)
			TweenService:Create(ring, TweenInfo.new(0.7 + 0.2 * i, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = Vector3.new(0.06, 5.5 - i, 5.5 - i), Transparency = 1, CFrame = goal,
			}):Play()
		end
		Debris:AddItem(ring, 1.3)
	end

	local anchor = plainPart("LevelAnchor")
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(feet + Vector3.new(0, height + 0.8, 0))
	anchor.Parent = Workspace
	local bb = Instance.new("BillboardGui")
	bb.Name = "LevelUp"
	bb.Adornee = anchor
	bb.Size = UDim2.fromOffset(180, 56)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 80
	bb.Parent = anchor
	local title = UI.text(bb, "LEVEL UP!", {
		Font = UI.Head, TextSize = 24, Outline = "Strong", TextColor3 = gold,
		TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 0, 32),
	})
	local sub = UI.text(bb, "Lv " .. tostring(level), {
		Font = UI.Bold, TextSize = 16, Outline = "Strong", TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 0, 22),
	})
	if not still then
		TweenService:Create(anchor, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = anchor.CFrame + Vector3.new(0, 1.6, 0),
		}):Play()
	end
	local fadeInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.1)
	TweenService:Create(title, fadeInfo, { TextTransparency = 1 }):Play()
	TweenService:Create(sub, fadeInfo, { TextTransparency = 1 }):Play()
	for _, lbl in { title, sub } do
		local stroke = lbl:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, fadeInfo, { Transparency = 1 }):Play()
		end
	end
	Debris:AddItem(anchor, 1.7)
end

-- ---------------------------------------------------------------------------------------------------------------
-- One-shot bursts (fights, training, level up). A small pool of invisible anchored parts, each holding three
-- emitters that only ever Emit() (no Rate), a few pooled glow balls and pop-text anchors. Everything goes through
-- PetFx.spend, which skips far bursts, shrinks them with Low Effects and holds the whole-client particle budget.

local POOL_BURSTS, POOL_FLASH, POOL_POPS = 6, 4, 8
type Burst = { Part: Part, Spark: ParticleEmitter, Star: ParticleEmitter, Puff: ParticleEmitter }
type Flash = { Part: Part, Tween: Tween? }
type Pop = { Part: Part, Gui: BillboardGui, Label: TextLabel?, Tween: Tween? }

local fxFolder: Folder? = nil
local bursts: { Burst } = {}
local flashes: { Flash } = {}
local pops: { Pop } = {}
local nextBurst, nextFlash, nextPop = 0, 0, 0
local budget = Rules.newBudget()

local function folder(): Folder
	if fxFolder and fxFolder.Parent then
		return fxFolder
	end
	local f = Instance.new("Folder")
	f.Name = "CT_PetFx"
	f.Parent = Workspace
	fxFolder = f
	table.clear(bursts)
	table.clear(flashes)
	table.clear(pops)
	return f
end

local function burstEmitter(parent: BasePart, name: string): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Enabled = false
	e.Rate = 0
	e.LockedToPart = false
	e.SpreadAngle = Vector2.new(180, 180)
	e.Parent = parent
	return e
end

burstAt = function(pos: Vector3): Burst
	local f = folder()
	nextBurst = nextBurst % POOL_BURSTS + 1
	local b = bursts[nextBurst]
	if not b then
		local part = plainPart("PetBurst")
		part.Transparency = 1
		part.Size = Vector3.one * 0.5
		part.Parent = f
		local spark = burstEmitter(part, "Spark")
		spark.LightEmission = 1
		spark.Lifetime = NumberRange.new(0.25, 0.45)
		spark.Drag = 6
		spark.Size = NumberSequence.new(0.3, 0)
		local star = burstEmitter(part, "Star")
		star.LightEmission = 1
		star.Lifetime = NumberRange.new(0.6, 0.95)
		star.Drag = 4
		star.Acceleration = Vector3.new(0, -3, 0)
		star.RotSpeed = NumberRange.new(-200, 200)
		local puff = burstEmitter(part, "Puff")
		puff.LightEmission = 0
		puff.Color = seq(Color3.fromRGB(250, 250, 250), Color3.fromRGB(200, 196, 210))
		puff.Lifetime = NumberRange.new(0.6, 0.9)
		puff.Speed = NumberRange.new(3, 6)
		puff.Drag = 4
		puff.Acceleration = Vector3.new(0, 2, 0)
		puff.Size = NumberSequence.new(1, 2.2)
		puff.Transparency = NumberSequence.new(0.15, 1)
		b = { Part = part, Spark = spark, Star = star, Puff = puff }
		bursts[nextBurst] = b
	end
	b.Part.CFrame = CFrame.new(pos)
	return b
end

-- A neon ball that swells and fades (a hit or level-up flash). Reduce Motion keeps it small.
flash = function(pos: Vector3, size: number, color: Color3)
	local f = folder()
	nextFlash = nextFlash % POOL_FLASH + 1
	local fl = flashes[nextFlash]
	if not fl then
		local part = plainPart("PetFlash")
		part.Shape = Enum.PartType.Ball
		part.Material = Enum.Material.Neon
		part.Transparency = 1
		part.Parent = f
		fl = { Part = part, Tween = nil }
		flashes[nextFlash] = fl
	end
	if fl.Tween then
		fl.Tween:Cancel()
	end
	local grow = if reduced() then size * 0.6 else size
	fl.Part.Color = color
	fl.Part.Size = Vector3.one * grow * 0.3
	fl.Part.Transparency = 0.25
	fl.Part.CFrame = CFrame.new(pos)
	local tw = TweenService:Create(fl.Part, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * grow, Transparency = 1,
	})
	fl.Tween = tw
	tw:Play()
end

-- How many particles a burst of `count` at `pos` may use right now (0 = skip it): distance LOD, Low Effects and the
-- shared budget. Public so other pet effects can share the same budget.
function PetFx.spend(pos: Vector3, count: number): number
	local cam = Workspace.CurrentCamera
	local d = if cam then (cam.CFrame.Position - pos).Magnitude else 0
	return Rules.spend(budget, Rules.scaled(count, Rules.lod(d, lowFx())), os.clock())
end

-- A star spray (FightFx big moments). Shares the pool, LOD and budget.
function PetFx.stars(at: Vector3, count: number, a: Color3, b: Color3, speed: number?, size: number?)
	local n = PetFx.spend(at, count)
	if n > 0 then
		local bu = burstAt(at)
		bu.Star.Color = seq(a, b)
		bu.Star.Size = sparkleSize(size or 0.6)
		local sp = speed or 12
		bu.Star.Speed = NumberRange.new(sp * 0.5, sp)
		bu.Star:Emit(n)
	end
end

-- Slow motion for the burst pool (FightFx KO and special moments): 1 = normal speed.
function PetFx.setTimeScale(k: number)
	for _, b in bursts do
		b.Spark.TimeScale = k
		b.Star.TimeScale = k
		b.Puff.TimeScale = k
	end
end

-- Floating text over a spot ("CRIT!", "KO!", a damage number) that rises and fades. Pooled anchors.
function PetFx.pop(at: Vector3, text: string, color: Color3?, big: boolean?)
	local cam = Workspace.CurrentCamera
	if cam and (cam.CFrame.Position - at).Magnitude > Rules.FAR then
		return
	end
	local f = folder()
	nextPop = nextPop % POOL_POPS + 1
	local p = pops[nextPop]
	if not p then
		local anchor = plainPart("PetPop")
		anchor.Transparency = 1
		anchor.Size = Vector3.one * 0.2
		anchor.Parent = f
		local bb = Instance.new("BillboardGui")
		bb.Name = "Pop"
		bb.Adornee = anchor
		bb.Size = UDim2.fromOffset(160, 48)
		bb.AlwaysOnTop = true
		bb.LightInfluence = 0
		bb.MaxDistance = Rules.FAR
		bb.Parent = anchor
		p = { Part = anchor, Gui = bb, Label = nil, Tween = nil }
		pops[nextPop] = p
	end
	if p.Tween then
		p.Tween:Cancel()
	end
	if p.Label then
		p.Label:Destroy()
	end
	local label = UI.text(p.Gui, text, {
		Font = UI.Head, TextSize = if big then 30 else 22, Outline = "Strong", TextColor3 = color or Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 0, 40),
	})
	p.Label = label
	p.Gui.Size = UDim2.fromOffset(160, 48)
	p.Part.CFrame = CFrame.new(at)
	if not reduced() then
		local tw = TweenService:Create(p.Part, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = CFrame.new(at + Vector3.new(0, 2.2, 0)),
		})
		p.Tween = tw
		tw:Play()
	end
	local fade = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.6)
	TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
	end
end

local function centreOf(target: Model | Vector3): Vector3
	if typeof(target) == "Vector3" then
		return target
	end
	local m = target :: Model
	local h = m:GetAttribute("Height")
	return m:GetPivot().Position + Vector3.new(0, (if type(h) == "number" then h else 2) * 0.5, 0)
end

export type HitOpts = { Element: string?, Crit: boolean?, Damage: number?, Quiet: boolean? } -- Quiet: no word pops (the caller shows them)

-- A fight or training hit landing on `target` (a pet model or a spot): element-coloured sparks and a flash; a crit
-- throws twice the sparks, a star spray and a "CRIT!" pop; Damage shows the number.
function PetFx.hit(target: Model | Vector3, opts: HitOpts?)
	local o: HitOpts = opts or {}
	local at = centreOf(target)
	local h = Rules.hit(o.Element, o.Crit)
	local n = PetFx.spend(at, h.Count)
	if n > 0 then
		local b = burstAt(at)
		b.Spark.Color = seq(Color3.new(1, 1, 1), h.Color)
		b.Spark.Size = NumberSequence.new(h.Size, 0)
		b.Spark.Speed = NumberRange.new(h.Speed * 0.6, h.Speed)
		b.Spark:Emit(n)
		if o.Crit then
			b.Star.Color = seq(Color3.fromRGB(255, 250, 200), Color3.fromRGB(255, 200, 60))
			b.Star.Size = sparkleSize(0.6)
			b.Star.Speed = NumberRange.new(5, 9)
			b.Star:Emit(math.max(1, n // 3))
		end
		flash(at, h.Flash, h.Color)
	end
	if o.Quiet then
		return
	end
	if h.Pop then
		PetFx.pop(at + Vector3.new(0, 1.2, 0), "CRIT!", Color3.fromRGB(255, 214, 90), true)
	elseif o.Damage then
		PetFx.pop(at + Vector3.new(0, 1, 0), tostring(math.floor(o.Damage + 0.5)), Color3.new(1, 1, 1), false)
	end
	if o.Crit and o.Damage then
		PetFx.pop(at + Vector3.new(0.8, 0.4, 0), tostring(math.floor(o.Damage + 0.5)), Color3.fromRGB(255, 240, 200), false)
	end
end

-- A pet knocked out: a soft cloud poof, a ring of dizzy stars and "KO!". The fight code hides or moves the pet.
function PetFx.ko(target: Model | Vector3, noPop: boolean?)
	local at = centreOf(target)
	local n = PetFx.spend(at, Rules.KO_COUNT)
	if n > 0 then
		local b = burstAt(at)
		b.Puff:Emit(math.max(1, n * 2 // 3))
		b.Star.Color = seq(Color3.fromRGB(255, 250, 200), Color3.fromRGB(255, 220, 90))
		b.Star.Size = sparkleSize(0.45)
		b.Star.Speed = NumberRange.new(3, 6)
		b.Star:Emit(math.max(1, n // 3))
		flash(at, 3, Color3.fromRGB(255, 255, 255))
	end
	if not noPop then
		PetFx.pop(at + Vector3.new(0, 1.4, 0), "KO!", Color3.fromRGB(255, 120, 110), true)
	end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Squash and stretch (the happy bounce). Shape only: the hop itself comes from whoever places the pet (PetFollow
-- adds it for followers). Anchored rigid pets (procedural bodies, plain mesh parts) stretch on their own axes around
-- the model pivot; pets with bones (skinned meshes) or welded parts get a gentle uniform ScaleTo pulse instead, so
-- no rig, bone or weld is ever changed. Everything is put back exactly at the end. Reduce Motion: nothing.

type PartState = { Part: BasePart, Size: Vector3, Off: CFrame }
type Squash = { Model: Model, T0: number, Parts: { PartState }?, Scale: number }

local MAX_SQUASH = 6
local squashing: { [Model]: Squash } = {}
local squashConn: RBXScriptConnection? = nil

local function restore(sq: Squash)
	local m = sq.Model
	if sq.Parts then
		local pivot = m:GetPivot()
		for _, st in sq.Parts do
			if st.Part.Parent then
				st.Part.Size = st.Size
				st.Part.CFrame = pivot * st.Off
			end
		end
	else
		pcall(function()
			m:ScaleTo(sq.Scale)
		end)
	end
end

local function squashStep()
	local now = os.clock()
	for m, sq in squashing do
		local k = (now - sq.T0) / Rules.BOUNCE_TIME
		if k >= 1 or not m.Parent then
			restore(sq)
			squashing[m] = nil
			continue
		end
		local _, sx, sy = Rules.squash(k)
		if sq.Parts then
			local pivot = m:GetPivot()
			for _, st in sq.Parts do
				local o = st.Off
				st.Part.Size = Vector3.new(st.Size.X * sx, st.Size.Y * sy, st.Size.Z * sx)
				st.Part.CFrame = pivot * CFrame.new(o.X * sx, o.Y * sy, o.Z * sx) * o.Rotation
			end
		else
			pcall(function()
				m:ScaleTo(sq.Scale * (1 + (sy - 1) * 0.5))
			end)
		end
	end
	if next(squashing) == nil and squashConn then
		squashConn:Disconnect()
		squashConn = nil
	end
end

function PetFx.squash(model: Model)
	if reduced() or squashing[model] then
		if squashing[model] then
			squashing[model].T0 = os.clock() -- bounce again from the start
		end
		return
	end
	local count = 0
	for _ in squashing do
		count += 1
	end
	if count >= MAX_SQUASH then
		return
	end
	local rigid = true
	local parts: { PartState } = {}
	local pivot = model:GetPivot()
	for _, d in model:GetDescendants() do
		if d:IsA("Bone") or d:IsA("Motor6D") or d:IsA("Weld") or d:IsA("WeldConstraint") then
			rigid = false
			break
		elseif d:IsA("BasePart") then
			if not d.Anchored then
				rigid = false
				break
			end
			table.insert(parts, { Part = d, Size = d.Size, Off = pivot:ToObjectSpace(d.CFrame) })
		end
	end
	squashing[model] = { Model = model, T0 = os.clock(), Parts = if rigid then parts else nil, Scale = model:GetScale() }
	if not squashConn then
		squashConn = RunService.RenderStepped:Connect(squashStep)
	end
end

-- A happy pet: squash bounce plus a little star sparkle (petting, a win, a new friend). Followers also hop
-- (PetFollow.bounce calls this).
function PetFx.happy(model: Model)
	PetFx.squash(model)
	local at = centreOf(model)
	local n = PetFx.spend(at, 8)
	if n > 0 then
		local b = burstAt(at + Vector3.new(0, 0.6, 0))
		b.Star.Color = seq(Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 230, 120))
		b.Star.Size = sparkleSize(0.35)
		b.Star.Speed = NumberRange.new(2, 4)
		b.Star:Emit(n)
	end
end

return PetFx
