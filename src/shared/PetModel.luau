--!strict
-- Procedural low-poly pets (Find The Pet). One chunky, toy-like body per species Kind (Config.Minerals[id].Kind):
-- big head, big glossy eyes, SmoothPlastic, and the few parts that make each animal readable at a glance
-- (raptor tail and little arms, ostrich neck and legs, wolf ears and bushy tail, griffin beak and wings, wyvern
-- horns and ice spikes, mammoth trunk and tusks, T-Rex lava cracks, phoenix flame tail, dragon stars, pterodactyl
-- crest and wide wings). Everything derives from the stored specimen record (Mineral = species, Formation = pose,
-- Modifier = variant, Rarity, Mass, Seed), so the same pet looks the same in the hatch reveal, results, book,
-- gallery and following its owner.
--
-- Frame: the pivot is the centre of the feet on the ground (y = 0); the pet faces -Z (Roblox LookVector), so
-- CFrame.lookAt(pos, pos + dir) makes it face `dir`. Every part is anchored, never collides, not queryable.
-- About 18-30 parts per pet. REPLACE: real mesh per species when the owner uploads them (docs/BRIEF.txt).

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Config = require(script.Parent.Config)
local GeodeGen = require(script.Parent.GeodeGen)
local PetFlair = require(script.Parent.PetFlair)
local PetSkins = require(script.Parent.PetSkins)

local PetModel = {}

export type Opts = {
	Scale: number?, -- overrides the mass scale (1 = about 2.4 studs tall)
	Lod: boolean?, -- fewer small pieces (gallery shelves, followers)
	Tiny: boolean?, -- fewest pieces (implies Lod)
	NoLight: boolean?, -- no PointLight (many pets in one view)
	NoFx: boolean?, -- no sparkles, aura ring or beams
}

local GOLD = Color3.fromRGB(255, 196, 64)
local INK = Color3.fromRGB(30, 28, 38)
local WHITE = Color3.new(1, 1, 1)
local BLUSH = Color3.fromRGB(255, 150, 172)
local ORANGE = Color3.fromRGB(255, 160, 50)
local BEAK = Color3.fromRGB(255, 205, 70)
local BONE = Color3.fromRGB(238, 232, 212)
local SOCKET = Color3.fromRGB(52, 46, 54)
local SILVER = Color3.fromRGB(206, 212, 226)
local COSMIC = { Color3.fromRGB(170, 90, 255), Color3.fromRGB(80, 150, 255), Color3.fromRGB(230, 120, 255) }

local SPECIES = { "Raptor", "Ostrich", "DireWolf", "Griffin", "FrostWyvern", "Mammoth", "LavaTRex", "Phoenix", "CosmicDragon", "StarPterodactyl" }
local KINDS = {
	raptor = true, ostrich = true, wolf = true, griffin = true, wyvern = true,
	mammoth = true, trex = true, phoenix = true, dragon = true, pterodactyl = true,
}

-- The species entry for a specimen; an unknown id (old saves, decorative examples) maps to a fixed species.
local function species(id: any): { [string]: any }
	local m = (Config.Minerals :: any)[id]
	if m then
		return m
	end
	local h = 0
	for i = 1, #tostring(id) do
		h = (h * 31 + string.byte(tostring(id), i)) % 1000003
	end
	return (Config.Minerals :: any)[SPECIES[h % #SPECIES + 1]] or { Kind = "raptor", Crystal = Color3.fromRGB(110, 190, 90), Rim = Color3.fromRGB(250, 210, 90) }
end
PetModel.species = species

-- body/accent are recoloured by variants; glow = neon pieces (keep their colour except Golden/Rainbow);
-- fixed = eyes, shines, cheeks, beaks, sockets (never recoloured)
type Role = "body" | "accent" | "glow" | "fixed"

-- Real meshes (owner's Studio models): a Model named "Pet_<species id>" inside a folder "PetModels" in ReplicatedStorage
-- (preferred) or Workspace. When one exists it is used instead of the procedural body; otherwise the stand-in below.
local TEMPLATE_HEIGHT = 2.4 -- studs: procedural pets at Scale 1 are about this tall
local VARIANT_TINT: { [string]: Color3 } = {
	Golden = Color3.fromRGB(255, 196, 64),
	Skeleton = Color3.fromRGB(238, 232, 212),
	SilverCosmic = Color3.fromRGB(206, 212, 226),
}

local function template(id: any): Model?
	for _, root in { game:GetService("ReplicatedStorage"), game:GetService("Workspace") } do
		local folder = root:FindFirstChild("PetModels")
		local m = folder and folder:FindFirstChild("Pet_" .. tostring(id))
		if m and m:IsA("Model") then
			return m
		end
	end
	return nil
end

-- Rare and better pets sparkle (Config.Pets.Sparkle). Tagged "PetSparkle" so the client (PetSparkle) can turn every
-- one off locally when the viewer picks Low Effects. Never on Tiny pets or with NoFx.
local function addRaritySparkle(part: BasePart?, rarity: any, o: Opts)
	if not part or o.NoFx == true or o.Tiny == true then
		return
	end
	local look = PetFlair.sparkle(rarity)
	if not look then
		return
	end
	local sp = Instance.new("Sparkles")
	sp.Name = "RaritySparkle"
	sp.SparkleColor = look.Color
	sp.TimeScale = look.TimeScale
	sp.Parent = part
	CollectionService:AddTag(sp, "PetSparkle")
end

-- Shiny pets (LaunchPerks.Shiny, 1 in 100): a white-pink star shimmer and a soft twinkle light. Same Low Effects tag.
local function addShinyFx(part: BasePart?, spec: { [string]: any }, o: Opts)
	if not part or spec.Shiny ~= true or o.NoFx == true or o.Tiny == true then
		return
	end
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "ShinyShimmer"
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 150, 230))
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.45), NumberSequenceKeypoint.new(1, 0) })
	pe.Lifetime = NumberRange.new(0.6, 1.1)
	pe.Rate = 9
	pe.Speed = NumberRange.new(0.3, 0.9)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Rotation = NumberRange.new(0, 360)
	pe.RotSpeed = NumberRange.new(-90, 90)
	pe.Parent = part
	CollectionService:AddTag(pe, "PetSparkle")
	local pl = Instance.new("PointLight")
	pl.Name = "ShinyGlow"
	pl.Color = Color3.fromRGB(255, 200, 245)
	pl.Brightness = 0.8
	pl.Range = 6
	pl.Shadows = false
	pl.Parent = part
	CollectionService:AddTag(pl, "PetSparkle")
end

-- Evolved pets (PvpService evolve) glow: a soft force-field shell around the body in the stage colour, plus sparkles.
local EVOLVE_GLOW = { Color3.fromRGB(120, 230, 255), Color3.fromRGB(255, 200, 70) }
local function addEvolveGlow(model: Model, spec: { [string]: any }, o: Opts)
	local stage = PetFlair.evolveStage(spec.Evolve)
	if stage <= 0 then
		return
	end
	model:SetAttribute("Evolve", stage)
	if o.Tiny == true then
		return
	end
	local cf, size = model:GetBoundingBox()
	local col = EVOLVE_GLOW[math.clamp(stage, 1, #EVOLVE_GLOW)]
	local aura = Instance.new("Part")
	aura.Name = "EvolveAura"
	aura.Shape = Enum.PartType.Ball
	local d = math.max(size.X, size.Y, size.Z) * 1.1
	aura.Size = Vector3.new(d, d, d)
	aura.CFrame = cf
	aura.Color = col
	aura.Material = Enum.Material.ForceField
	aura.Transparency = 0.2
	aura.Anchored = true
	aura.CanCollide = false
	aura.CanQuery = false
	aura.CanTouch = false
	aura.CastShadow = false
	aura.Parent = model
	if o.NoFx ~= true then
		local sp = Instance.new("Sparkles")
		sp.Name = "EvolveSparkle"
		sp.SparkleColor = col
		sp.Parent = aura
		CollectionService:AddTag(sp, "PetSparkle")
	end
end

-- Whether a mesh pet faces +Z of `frame` (back to front): its Head bone sits behind its Tail bone (or Body bone when
-- there is no tail). nil-safe: no bones = false.
function PetModel.faceFlip(model: Model, frame: CFrame): boolean
	local head: Vector3?, back: Vector3?, body: Vector3? = nil, nil, nil
	for _, d in model:GetDescendants() do
		if d:IsA("Bone") then
			local key = d.Name:match("_(%a+)$") or d.Name
			if key == "Head" then
				head = frame:PointToObjectSpace(d.WorldPosition)
			elseif key == "Tail" then
				back = frame:PointToObjectSpace(d.WorldPosition)
			elseif key == "Body" then
				body = frame:PointToObjectSpace(d.WorldPosition)
			end
		end
	end
	local b = back or body
	return head ~= nil and b ~= nil and head.Z > b.Z + 0.05
end

local function fromTemplate(tmpl: Model, spec: { [string]: any }, s: number, o: Opts): Model
	local model = tmpl:Clone()
	model.Name = "CT_Pet_" .. tostring(spec.Mineral)
	for _, d in model:GetDescendants() do
		if d:IsA("BaseScript") then
			d:Destroy() -- motion scripts belong to the owner's preview, never to copies
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	local _, size = model:GetBoundingBox()
	local h = math.max(size.Y, 0.1)
	pcall(function()
		model:ScaleTo(math.max(0.05, model:GetScale() * TEMPLATE_HEIGHT * s * ((tmpl:GetAttribute("SizeBoost") :: number?) or 1) / h))
	end)
	local tint: Color3? = VARIANT_TINT[spec.Modifier]
	-- painted variant skins (shared/PetSkins): same mesh, other texture, eyes stay dark; used instead of the flat
	-- tint for any variant the species has one for (a flat tint has to drop the texture, eyes and all)
	local skins = PetSkins[tostring(spec.Mineral)]
	local skin: string? = if skins and spec.Modifier then skins[tostring(spec.Modifier)] else nil
	if type(skin) == "string" and skin ~= "" then
		for _, d in model:GetDescendants() do
			if d:IsA("MeshPart") then
				d.TextureID = skin
				if spec.Modifier == "Golden" or spec.Modifier == "SilverCosmic" then
					d.Reflectance = 0.1
				end
			end
		end
		tint = nil
	end
	local i = 0
	for _, d in model:GetDescendants() do
		if type(skin) == "string" and skin ~= "" then
			break
		end
		if d:IsA("BasePart") and d.Material ~= Enum.Material.Neon then
			i += 1
			if spec.Modifier == "Rainbow" then
				d.Color = Color3.fromHSV(((spec.Seed or 1) * 0.07 + i * 0.13) % 1, 0.85, 1) -- vivid, not pastel (a one-mesh pet at 0.55 read as a pale ghost)
			elseif tint then
				d.Color = tint
				if spec.Modifier ~= "Skeleton" then
					d.Reflectance = 0.2
				end
			end
			if d:IsA("MeshPart") and (tint or spec.Modifier == "Rainbow") then
				d.TextureID = "" -- a texture would hide the variant colour
			end
		end
	end
	local cf, box = model:GetBoundingBox()
	local floor = cf.Position.Y - box.Y / 2
	local feet = CFrame.new(cf.Position.X, floor, cf.Position.Z) * (cf - cf.Position)
	-- the pet must face -Z (followers, reveal, fights all use CFrame.lookAt): a mesh imported back to front (Studio
	-- check 2026-10-15: Bramblebat, Ashwing) is turned round here, judged by its head bone in front of its tail bone
	local flip = PetModel.faceFlip(model, feet)
	if flip then
		feet *= CFrame.Angles(0, math.pi, 0)
		model:SetAttribute("FaceFlipped", true)
	end
	if model.PrimaryPart then
		-- with a PrimaryPart the pivot comes from PivotOffset (WorldPivot is ignored), so put it at the feet too
		model.PrimaryPart.PivotOffset = model.PrimaryPart.CFrame:ToObjectSpace(feet)
	else
		model.WorldPivot = feet
	end
	model:PivotTo(CFrame.new())
	local rc: Color3? = (Config.RarityColors :: any)[spec.Rarity]
	local body = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if rc and spec.Rarity ~= "Common" and o.NoLight ~= true and o.NoFx ~= true and body then
		local pl = Instance.new("PointLight")
		pl.Color = rc
		pl.Brightness = if spec.Rarity == "Legendary" then 1.4 else 0.7
		pl.Range = 5 * s + 2
		pl.Shadows = false
		CollectionService:AddTag(pl, "PetSparkle") -- Low Effects turns it off (client PetSparkle)
		pl.Parent = body
	end
	model:SetAttribute("Radius", math.max(box.X, box.Z) / 2)
	model:SetAttribute("CentreY", box.Y / 2)
	model:SetAttribute("Height", box.Y)
	model:SetAttribute("Kind", species(spec.Mineral).Kind)
	-- followers get renamed (Pet_<uid>_n), so PetMotion reads the species from here to pick the body type (gait)
	model:SetAttribute("Species", tostring(spec.Mineral))
	model:SetAttribute("Mesh", true)
	addRaritySparkle(body, spec.Rarity, o)
	addShinyFx(body, spec, o)
	if RunService:IsServer() then
		-- bone motion does not replicate: each client starts PetMotion on tagged server pets (client PetDisplay)
		CollectionService:AddTag(model, "PetDisplay")
	end
	return model
end

function PetModel.build(spec: { [string]: any }, opts: Opts?): Model
	local o: Opts = opts or {}
	-- rarer pets are a bit bigger everywhere they are drawn (Config.Pets.RarityScale)
	-- evolved pets are bigger again (PetFlair.evolveScale)
	local s = (o.Scale or GeodeGen.visualScale(spec.Mass or 1)) * PetFlair.rarityScale(spec.Rarity) * PetFlair.evolveScale(spec.Evolve)
	local tmpl = template(spec.Mineral)
	if tmpl then
		local m = fromTemplate(tmpl, spec, s, o)
		addEvolveGlow(m, spec, o)
		return m
	end
	local tiny = o.Tiny == true
	local lod = o.Lod == true or tiny
	local sp = species(spec.Mineral)
	local kind: string = if KINDS[sp.Kind] then sp.Kind else "raptor"
	local base: Color3 = sp.Crystal
	local rim: Color3 = sp.Rim
	local trait = spec.Modifier
	local form = spec.Formation
	local rarity = spec.Rarity
	local rng = Random.new((spec.Seed or 1) * 3 + 11)
	local hue0 = rng:NextNumber(0, 1)

	local model = Instance.new("Model")
	model.Name = "CT_Pet_" .. tostring(spec.Mineral)
	local n = 0

	-- paint: variants recolour body/accent pieces; glow keeps its colour; eyes, cheeks, beaks are fixed
	local function paint(c: Color3, role: Role): Color3
		if role == "fixed" then
			return c
		end
		if trait == "Rainbow" then
			return Color3.fromHSV((hue0 + n * 0.13) % 1, if role == "glow" then 0.7 else 0.55, 1)
		elseif trait == "Golden" then
			return c:Lerp(GOLD, if role == "body" then 0.82 elseif role == "accent" then 0.6 else 0.4)
		elseif role == "glow" then
			return c
		elseif trait == "Skeleton" then
			return if role == "body" then BONE else BONE:Lerp(INK, 0.1)
		elseif trait == "SilverCosmic" then
			return if role == "body" then SILVER else SILVER:Lerp(COSMIC[1], 0.35)
		end
		return c
	end

	-- add: one piece in unit space (scaled by s). shape: ball (ellipsoid), block, cyl.
	local function add(name: string, shape: string, size: Vector3, cf: CFrame, color: Color3, role: Role, neon: boolean?): BasePart
		n += 1
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size * s
		p.CFrame = CFrame.new(cf.Position * s) * cf.Rotation
		p.Color = paint(color, role)
		p.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
		if role == "body" or role == "accent" then
			if trait == "Golden" then
				p.Reflectance = 0.2
			elseif trait == "SilverCosmic" then
				p.Reflectance = 0.25
			end
		end
		if shape == "ball" then
			local m = Instance.new("SpecialMesh")
			m.MeshType = Enum.MeshType.Sphere
			m.Parent = p
		elseif shape == "cyl" then
			p.Shape = Enum.PartType.Cylinder
		end
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end
	local V = Vector3.new
	local A = CFrame.Angles
	local R45 = math.rad(45)

	-- pose (Formation): Cluster = Sitting, Spire = Standing (taller), TwinCore = Waving, HollowBloom = Sleepy
	local up = if form == "Spire" then 0.15 else 0
	local sleepy = form == "HollowBloom"
	local waving = form == "TwinCore"
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(x, y + up, z) -- body-space: lifted by the standing pose
	end
	local function gr(x: number, y: number, z: number): CFrame
		return CFrame.new(x, y, z) -- ground-space: feet and legs
	end

	local dark = base:Lerp(INK, 0.25)

	-- body: the main torso (ribs and specks are placed on it)
	local bodyPart: BasePart? = nil
	local bodyCF = CFrame.new()
	local bodySize = V(1, 1, 1)
	local function torso(size: Vector3, cf: CFrame, col: Color3?): BasePart
		local p = add("Body", "ball", size, cf, col or base, "body")
		bodyPart = p
		bodyCF = cf
		bodySize = size
		return p
	end

	-- head: everything on it is placed in head space so the sleepy tilt carries the face
	local H = CFrame.new()
	local headSize = V(1.5, 1.3, 1.35)
	local function head(size: Vector3, x: number, y: number, z: number, col: Color3?, role: Role?): BasePart
		H = CFrame.new(x, y + up, z) * A(if sleepy then 0.12 else 0, 0, if sleepy then 0.2 else 0)
		headSize = size
		return add("Head", "ball", size, H, col or base, role or "body")
	end
	local function hp(x: number, y: number, z: number, rx: number?, ry: number?, rz: number?): CFrame
		return H * CFrame.new(x, y, z) * A(rx or 0, ry or 0, rz or 0)
	end
	-- z of the head's front surface at (x, y) in head space
	local function front(x: number, y: number): number
		local u = (x / (headSize.X / 2)) ^ 2 + (y / (headSize.Y / 2)) ^ 2
		return -(headSize.Z / 2) * math.sqrt(math.max(0.05, 1 - u))
	end

	-- face: big glossy eyes with shines (closed lines when sleepy), blush cheeks; Skeleton adds dark sockets
	local function face(eyeY: number, eyeScale: number?, spread: number?)
		local k = math.min(headSize.X, headSize.Y) / 1.45 * (eyeScale or 1)
		local ex = headSize.X * (spread or 0.21)
		local ez = front(ex, eyeY)
		for side = -1, 1, 2 do
			local x = side * ex
			if trait == "Skeleton" and not tiny then
				add("Socket", "ball", V(0.5 * k, 0.58 * k, 0.1), hp(x, eyeY, ez + 0.02), SOCKET, "fixed")
			end
			if sleepy then
				add("Eye", "block", V(0.3 * k, 0.06, 0.06), hp(x, eyeY - 0.02, ez - 0.03, 0, 0, side * -0.15), INK, "fixed")
			else
				add("Eye", "ball", V(0.36 * k, 0.44 * k, 0.12), hp(x, eyeY, ez - 0.02), INK, "fixed")
				add("Shine", "ball", V(0.13 * k, 0.13 * k, 0.05), hp(x + 0.07 * k, eyeY + 0.1 * k, ez - 0.08), WHITE, "fixed", true)
			end
			if not lod then
				local cx, cy = side * headSize.X * 0.33, eyeY - headSize.Y * 0.2
				add("Cheek", "ball", V(0.24 * k, 0.13 * k, 0.06), hp(cx, cy, front(cx, cy) + 0.01), BLUSH, "fixed")
			end
		end
	end

	-- shared limb helpers
	local function biped(thigh: Vector3, x: number, footCol: Color3)
		for side = -1, 1, 2 do
			add("Thigh", "ball", thigh, gr(side * x, thigh.Y / 2 + 0.05 + up * 0.5, 0.05), base, "body")
			add("Foot", "ball", V(thigh.X * 0.85, 0.18, thigh.Z * 0.95), gr(side * x, 0.09, -0.15), footCol, "body")
		end
	end
	local function quad(leg: Vector3, x: number, zf: number, zb: number, col: Color3)
		for _, z in { zf, zb } do
			for side = -1, 1, 2 do
				add("Leg", "ball", V(leg.X, leg.Y + up, leg.Z), gr(side * x, (leg.Y + up) / 2 + 0.02, z), col, "body")
			end
		end
	end
	-- arms: little forward paws; the waving pose raises the right one
	local function arms(size: Vector3, x: number, y: number, z: number, col: Color3)
		for side = -1, 1, 2 do
			local cf = if waving and side == 1
				then at(x + 0.18, y + 0.42, z + 0.1) * A(0, 0, math.rad(-150))
				else at(side * x, y, z) * A(-0.8, 0, side * 0.2)
			add("Arm", "ball", size, cf, col, "body")
		end
	end
	-- wings: a flat membrane rooted at the shoulders, raised and swept back; waving lifts the right one higher
	local function wings(size: Vector3, x: number, y: number, z: number, col: Color3, shape: string, tilt: number?)
		for side = -1, 1, 2 do
			local lift = if waving and side == 1 then 0.5 else 0
			local t = (tilt or 0.55) + lift
			add("Wing", shape, size, at(side * x, y + lift * 0.25, z) * A(0.3, side * 0.45, side * -t), col, "accent")
		end
	end
	local function spike(name: string, sz: number, cf: CFrame, col: Color3, role: Role, neon: boolean?): BasePart
		return add(name, "block", V(0.1, sz, sz), cf * A(R45, 0, 0), col, role, neon)
	end
	local function star(cf: CFrame, sz: number, col: Color3)
		add("Star", "block", V(sz, sz, 0.05), cf * A(0, 0, R45), col, "glow", true)
	end

	local radius = 0.95 -- footprint (aura ring, viewport framing)

	if kind == "raptor" then
		biped(V(0.42, 0.6, 0.5), 0.32, dark)
		torso(V(1.15, 1.2, 1.15), at(0, 1.0, 0.05) * A(-0.15, 0, 0))
		add("Belly", "ball", V(0.72, 0.8, 0.3), at(0, 0.95, -0.46), rim:Lerp(WHITE, 0.4), "accent")
		arms(V(0.18, 0.38, 0.18), 0.42, 1.15, -0.45, base)
		add("Tail", "ball", V(0.42, 0.42, 1.25), at(0, 0.75, 0.85) * A(0.45, 0, 0), base, "body")
		if not lod then
			add("TailTip", "ball", V(0.26, 0.26, 0.5), at(0, 0.45, 1.42) * A(0.6, 0, 0), base, "body")
		end
		head(V(1.45, 1.25, 1.4), 0, 2.0, -0.2)
		add("Snout", "ball", V(0.85, 0.52, 0.7), hp(0, -0.27, -0.52), base:Lerp(WHITE, 0.15), "body")
		face(0.1)
		spike("Spike", 0.34, hp(0, 0.6, 0.15), rim, "accent")
		if not tiny then
			spike("Spike", 0.3, at(0, 1.6, 0.45), rim, "accent")
			spike("Spike", 0.26, at(0, 1.25, 0.66), rim, "accent")
		end
	elseif kind == "trex" then
		biped(V(0.55, 0.7, 0.65), 0.4, dark)
		torso(V(1.4, 1.3, 1.35), at(0, 1.05, 0.1) * A(-0.12, 0, 0))
		add("Belly", "ball", V(0.66, 0.85, 0.3), at(0, 1.0, -0.52), base:Lerp(rim, 0.6), "accent")
		arms(V(0.14, 0.26, 0.14), 0.45, 1.25, -0.55, base)
		add("Tail", "ball", V(0.55, 0.55, 1.4), at(0, 0.75, 0.95) * A(0.4, 0, 0), base, "body")
		head(V(1.75, 1.4, 1.75), 0, 2.1, -0.3)
		add("Jaw", "ball", V(1.25, 0.55, 0.9), hp(0, -0.38, -0.62), base:Lerp(WHITE, 0.08), "body")
		if not lod then
			for side = -1, 1, 2 do
				add("Fang", "block", V(0.12, 0.12, 0.06), hp(side * 0.28, -0.6, -0.98, 0, 0, R45), WHITE, "fixed")
			end
		end
		face(0.18)
		-- lava cracks
		add("Crack", "block", V(0.13, 0.55, 0.12), at(0.38, 1.25, -0.47) * A(0, 0, 0.5), rim, "glow", true)
		add("Crack", "block", V(0.12, 0.12, 0.6), hp(0, 0.66, 0.05, 0, 0.3, 0), rim, "glow", true)
		add("Crack", "block", V(0.13, 0.5, 0.12), hp(0.5, 0.35, front(0.5, 0.35) + 0.02, 0, 0, -0.6), rim, "glow", true)
		if not lod then
			add("Crack", "block", V(0.13, 0.5, 0.12), at(-0.4, 0.88, -0.45) * A(0, 0, -0.4), rim, "glow", true)
			add("Crack", "block", V(0.08, 0.08, 0.6), at(0, 1.02, 0.9) * A(0.4, 0.3, 0), rim, "glow", true)
		end
		radius = 1.05
	elseif kind == "ostrich" then
		for side = -1, 1, 2 do
			add("Leg", "ball", V(0.2, 0.95 + up, 0.2), gr(side * 0.28, (0.95 + up) / 2 + 0.03, 0.05), rim, "accent")
			add("Foot", "ball", V(0.3, 0.14, 0.42), gr(side * 0.28, 0.07, -0.1), rim:Lerp(INK, 0.2), "accent")
		end
		torso(V(1.5, 1.1, 1.55), at(0, 1.25, 0.1))
		wings(V(0.4, 0.75, 0.95), 0.62, 1.3, 0.15, base:Lerp(WHITE, 0.08), "ball", 0.2)
		add("Plume", "ball", V(0.85, 0.65, 0.55), at(0, 1.55, 0.85), WHITE:Lerp(base, 0.08), "accent")
		if not lod then
			add("Plume", "ball", V(0.5, 0.45, 0.4), at(0, 1.82, 0.98), WHITE:Lerp(base, 0.08), "accent")
		end
		add("Ruff", "ball", V(0.72, 0.38, 0.72), at(0, 1.72, -0.42), base, "body")
		add("Neck", "ball", V(0.32, 1.05, 0.32), at(0, 2.08, -0.45), rim, "accent")
		head(V(1.1, 1.0, 1.05), 0, 2.72, -0.5, rim:Lerp(WHITE, 0.25), "accent")
		add("Beak", "ball", V(0.52, 0.18, 0.5), hp(0, -0.17, -0.5), ORANGE:Lerp(WHITE, 0.4), "fixed")
		face(0.06, 1.3, 0.23)
		if not tiny then
			add("Tuft", "ball", V(0.18, 0.32, 0.18), hp(0.04, 0.52, 0.02, 0, 0, -0.3), base, "body")
		end
	elseif kind == "wolf" then
		quad(V(0.32, 0.7, 0.32), 0.32, -0.45, 0.72, base)
		torso(V(1.15, 1.0, 1.7), at(0, 0.95, 0.15))
		add("Chest", "ball", V(0.8, 0.75, 0.45), at(0, 1.05, -0.6), rim, "accent")
		add("Tail", "ball", V(0.5, 0.5, 1.1), at(0, 1.3, 1.05) * A(-0.7, 0, 0), base, "body")
		add("TailTip", "ball", V(0.4, 0.4, 0.45), at(0, 1.62, 1.42) * A(-0.7, 0, 0), rim, "accent")
		head(V(1.4, 1.2, 1.25), 0, 1.85, -0.65)
		add("Snout", "ball", V(0.6, 0.42, 0.62), hp(0, -0.26, -0.56), rim, "accent")
		add("Nose", "ball", V(0.18, 0.13, 0.12), hp(0, -0.13, -0.86), INK, "fixed")
		face(0.1)
		for side = -1, 1, 2 do
			add("Ear", "block", V(0.48, 0.48, 0.16), hp(side * 0.42, 0.56, 0.05, 0, 0, R45), base, "body")
			if not tiny then
				add("EarInner", "block", V(0.26, 0.26, 0.06), hp(side * 0.42, 0.58, -0.04, 0, 0, R45), INK, "fixed")
			end
		end
		radius = 1.1
	elseif kind == "griffin" then
		quad(V(0.32, 0.7, 0.32), 0.33, -0.4, 0.75, base)
		torso(V(1.2, 1.0, 1.65), at(0, 0.95, 0.2))
		add("Chest", "ball", V(0.95, 0.85, 0.5), at(0, 1.15, -0.5), rim, "accent")
		local feather = base:Lerp(WHITE, 0.35)
		wings(V(0.12, 0.95, 1.2), 0.62, 1.72, 0.35, feather, "block", 0.5)
		if not lod then
			for side = -1, 1, 2 do
				add("Feathers", "block", V(0.1, 0.6, 1.0), at(side * 0.95, 2.08, 0.5) * A(0.3, side * 0.45, side * -0.75), dark, "accent")
			end
		end
		add("Tail", "ball", V(0.15, 0.15, 0.85), at(0, 1.05, 1.1) * A(-0.5, 0, 0), base, "body")
		add("TailTuft", "ball", V(0.32, 0.32, 0.32), at(0, 1.3, 1.45), dark, "body")
		head(V(1.3, 1.2, 1.2), 0, 1.92, -0.62, rim, "accent")
		add("Beak", "ball", V(0.42, 0.34, 0.52), hp(0, -0.2, -0.6), BEAK, "fixed")
		add("BeakTip", "ball", V(0.2, 0.24, 0.2), hp(0, -0.34, -0.8), BEAK:Lerp(ORANGE, 0.5), "fixed")
		face(0.12)
		radius = 1.15
	elseif kind == "wyvern" then
		biped(V(0.5, 0.55, 0.6), 0.38, dark)
		torso(V(1.25, 1.25, 1.2), at(0, 0.95, 0.05))
		add("Belly", "ball", V(0.8, 0.85, 0.3), at(0, 0.9, -0.5), rim, "accent")
		wings(V(0.1, 1.0, 1.1), 0.72, 1.6, 0.45, rim:Lerp(base, 0.35), "block")
		add("Tail", "ball", V(0.38, 0.38, 1.1), at(0, 0.5, 0.85) * A(0.4, 0, 0), base, "body")
		head(V(1.5, 1.3, 1.35), 0, 2.0, -0.12)
		add("Snout", "ball", V(0.75, 0.5, 0.6), hp(0, -0.26, -0.52), base:Lerp(WHITE, 0.15), "body")
		face(0.1)
		for side = -1, 1, 2 do
			add("Horn", "block", V(0.14, 0.5, 0.14), hp(side * 0.38, 0.68, 0.18, 0.5, 0, side * -0.3), rim, "accent")
		end
		-- icy spikes along the spine
		spike("Ice", 0.3, hp(0, 0.6, 0.38), rim:Lerp(WHITE, 0.3), "accent").Transparency = 0.15
		spike("Ice", 0.34, at(0, 1.55, 0.55), rim:Lerp(WHITE, 0.3), "accent").Transparency = 0.15
		if not lod then
			spike("Ice", 0.28, at(0, 1.12, 0.68), rim:Lerp(WHITE, 0.3), "accent").Transparency = 0.15
			spike("Ice", 0.22, at(0, 0.3, 1.38), rim:Lerp(WHITE, 0.3), "accent").Transparency = 0.15
		end
		radius = 1.1
	elseif kind == "mammoth" then
		quad(V(0.45, 0.75, 0.45), 0.42, -0.4, 0.7, dark)
		torso(V(1.6, 1.35, 1.75), at(0, 1.15, 0.15))
		add("Shag", "ball", V(1.72, 0.55, 1.86), at(0, 0.78, 0.15), dark, "body")
		if not tiny then
			add("Hump", "ball", V(0.95, 0.6, 0.95), at(0, 1.78, -0.05), dark, "body")
		end
		head(V(1.45, 1.35, 1.25), 0, 1.92, -0.7)
		for side = -1, 1, 2 do
			add("Ear", "ball", V(0.7, 0.8, 0.15), hp(side * 0.75, 0.05, 0.12, 0, side * 0.4, 0), dark, "body")
			add("Tusk", "ball", V(0.16, 0.16, 0.8), hp(side * 0.32, -0.48, -0.78, 0.6, side * -0.3, 0), rim, "accent")
		end
		add("Trunk", "ball", V(0.42, 0.62, 0.42), hp(0, -0.28, -0.6), base, "body")
		add("Trunk", "ball", V(0.34, 0.55, 0.34), hp(0, -0.72, -0.72), base, "body")
		if not lod then
			add("TrunkTip", "ball", V(0.28, 0.28, 0.32), hp(0, -1.0, -0.84), base, "body")
		end
		if not tiny then
			add("Tuft", "ball", V(0.6, 0.42, 0.6), hp(0, 0.62, 0.05), dark, "body")
		end
		face(0.14, 0.95, 0.23)
		radius = 1.2
	elseif kind == "phoenix" then
		for side = -1, 1, 2 do
			add("Leg", "ball", V(0.12, 0.42 + up, 0.12), gr(side * 0.25, (0.42 + up) / 2 + 0.04, 0), BEAK, "fixed")
			add("Foot", "ball", V(0.3, 0.08, 0.35), gr(side * 0.25, 0.04, -0.08), BEAK, "fixed")
		end
		torso(V(1.25, 1.25, 1.25), at(0, 1.0, 0.05))
		add("Belly", "ball", V(0.8, 0.8, 0.3), at(0, 0.95, -0.5), rim, "accent")
		wings(V(0.22, 0.85, 0.65), 0.7, 1.12, 0.1, base:Lerp(rim, 0.3), "ball", 0.35)
		local flames = { rim, ORANGE, Color3.fromRGB(255, 90, 40) }
		for i = 1, 3 do
			local x = (i - 2) * 0.32
			add("Flame", "ball", V(0.24, 0.24, 1.25), at(x, 1.05 + (if i == 2 then 0.12 else 0), 0.95) * A(-0.6, x * 1.1, 0), flames[i], "glow", true)
		end
		head(V(1.35, 1.25, 1.25), 0, 2.0, -0.1)
		add("Beak", "ball", V(0.32, 0.22, 0.38), hp(0, -0.16, -0.66), BEAK, "fixed")
		face(0.1)
		for i = 1, (if lod then 2 else 3) do
			local x = (i - 2) * 0.2
			add("Crest", "ball", V(0.18, 0.55, 0.18), hp(x, 0.75 - math.abs(x) * 0.4, 0.12, -0.3, 0, -x * 1.2), flames[i], "glow", true)
		end
	elseif kind == "dragon" then
		biped(V(0.5, 0.5, 0.6), 0.38, dark)
		torso(V(1.3, 1.25, 1.2), at(0, 0.95, 0.05))
		add("Belly", "ball", V(0.8, 0.85, 0.3), at(0, 0.9, -0.5), rim, "accent")
		arms(V(0.25, 0.4, 0.25), 0.6, 1.0, -0.35, base)
		wings(V(0.1, 0.95, 1.15), 0.72, 1.62, 0.5, rim:Lerp(base, 0.4), "block")
		add("Tail", "ball", V(0.36, 0.36, 1.1), at(0, 0.45, 0.85) * A(0.35, 0, 0), base, "body")
		if not lod then
			add("TailTip", "block", V(0.08, 0.3, 0.3), at(0, 0.25, 1.38) * A(R45, 0, 0), rim, "accent")
		end
		head(V(1.55, 1.35, 1.4), 0, 2.0, -0.12)
		add("Snout", "ball", V(0.8, 0.5, 0.6), hp(0, -0.26, -0.55), base:Lerp(WHITE, 0.2), "body")
		face(0.12)
		for side = -1, 1, 2 do
			add("Horn", "block", V(0.15, 0.48, 0.15), hp(side * 0.4, 0.7, 0.15, 0.45, 0, side * -0.35), rim, "accent")
		end
		-- starry speckles
		local gold = Color3.fromRGB(255, 240, 150)
		star(at(0.32, 1.22, -0.68), 0.16, WHITE)
		star(hp(-0.48, 0.38, front(-0.48, 0.38) - 0.02), 0.14, gold)
		if not lod then
			star(at(-0.62, 1.15, -0.4), 0.12, gold)
		end
	elseif kind == "pterodactyl" then
		biped(V(0.26, 0.42, 0.28), 0.25, dark)
		torso(V(1.0, 1.1, 1.0), at(0, 0.92, 0.05))
		add("Belly", "ball", V(0.62, 0.72, 0.28), at(0, 0.88, -0.4), base:Lerp(WHITE, 0.35), "accent")
		for side = -1, 1, 2 do
			local lift = if waving and side == 1 then 0.35 else 0
			local wcf = at(side * 1.15, 1.42 + lift * 0.6, 0.18) * A(0, side * -0.25, side * (0.32 + lift))
			add("Wing", "ball", V(1.75, 0.8, 0.1), wcf * CFrame.new(0, -0.12, 0), dark, "accent")
			if not lod then
				add("WingEdge", "ball", V(1.75, 0.13, 0.15), wcf * CFrame.new(0, 0.25, 0), rim, "accent")
			end
			star(wcf * CFrame.new(side * 0.35, -0.1, -0.08), 0.15, rim)
		end
		add("Tail", "ball", V(0.14, 0.14, 0.6), at(0, 0.62, 0.62) * A(0.4, 0, 0), base, "body")
		head(V(1.3, 1.15, 1.2), 0, 1.92, -0.1)
		add("Beak", "ball", V(0.36, 0.3, 1.05), hp(0, -0.22, -0.82, 0.12, 0, 0), rim, "accent")
		add("Crest", "ball", V(0.14, 0.45, 0.95), hp(0, 0.42, 0.55, -0.5, 0, 0), rim, "accent")
		face(0.12)
		radius = 1.4
	end

	-- Skeleton: dark rib stripes around the torso (rings follow the ellipsoid so they sit on its surface)
	if trait == "Skeleton" and not tiny and bodyPart then
		local long = bodySize.Z > bodySize.Y * 1.2
		for i = 1, 3 do
			local t = (i - 2) * 0.24 + (if long then -0.1 else 0.05)
			local f = math.sqrt(math.max(0.05, 1 - (t * 2) ^ 2)) * 1.04
			if long then
				add("Rib", "ball", V(bodySize.X * f, bodySize.Y * f, 0.09), bodyCF * CFrame.new(0, 0, t * bodySize.Z), SOCKET, "fixed")
			else
				add("Rib", "ball", V(bodySize.X * f, 0.09, bodySize.Z * f), bodyCF * CFrame.new(0, t * bodySize.Y, 0), SOCKET, "fixed")
			end
		end
	end

	-- SilverCosmic: purple / blue neon specks on the torso and head
	if trait == "SilverCosmic" and not tiny then
		for i = 1, (if lod then 2 else 4) do
			local onHead = i % 2 == 0
			local cf0 = if onHead then H else bodyCF
			local size = if onHead then headSize else bodySize
			local d = V(rng:NextNumber(-0.8, 0.8), rng:NextNumber(-0.3, 0.8), -1 - rng:NextNumber(0, 0.6)).Unit
			local r = 1 / math.sqrt((d.X / (size.X / 2)) ^ 2 + (d.Y / (size.Y / 2)) ^ 2 + (d.Z / (size.Z / 2)) ^ 2)
			if onHead then
				d = V(if math.abs(d.X) < 0.45 then d.X + 0.6 else d.X, d.Y, d.Z).Unit -- keep specks off the eyes
				r = 1 / math.sqrt((d.X / (size.X / 2)) ^ 2 + (d.Y / (size.Y / 2)) ^ 2 + (d.Z / (size.Z / 2)) ^ 2)
			end
			add("Speck", "ball", V(0.12, 0.12, 0.12), cf0 * CFrame.new(d * r), COSMIC[i % #COSMIC + 1], "fixed", true)
		end
	end

	-- glints (show in viewports) and sparkles for the special variants
	local special = trait == "Golden" or trait == "Rainbow" or trait == "SilverCosmic"
	if special and not tiny then
		local hy = H.Position.Y
		for i = 1, 2 do
			local g = add("Glint", "block", V(0.12, 0.12, 0.04), CFrame.new((i * 2 - 3) * (headSize.X * 0.5 + 0.12), hy + 0.55 - i * 0.2, H.Position.Z - 0.3) * A(0, 0, R45), WHITE, "fixed", true)
			g.Transparency = 0.1
		end
	end
	if (trait == "Rainbow" or trait == "SilverCosmic") and o.NoFx ~= true and not lod and bodyPart then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = if trait == "Rainbow" then Color3.fromHSV(hue0, 0.4, 1) else COSMIC[1]
		CollectionService:AddTag(sparkles, "PetSparkle") -- Low Effects turns it off (client PetSparkle)
		sparkles.Parent = bodyPart
	end

	-- rarity: Uncommon+ soft aura ring and light in the rarity colour; Legendary adds gold beams
	local rc: Color3? = (Config.RarityColors :: any)[rarity]
	if rc and rarity ~= "Common" and o.NoFx ~= true and not tiny then
		local ring = add("Aura", "cyl", V(0.05, 2.2 * radius, 2.2 * radius), CFrame.new(0, 0.03, 0) * A(0, 0, math.rad(90)), rc, "fixed", true)
		ring.Transparency = 0.55
		if o.NoLight ~= true and bodyPart then
			local pl = Instance.new("PointLight")
			pl.Color = rc
			pl.Brightness = if rarity == "Legendary" then 1.4 else 0.7
			pl.Range = 5 * s + 2
			pl.Shadows = false
			CollectionService:AddTag(pl, "PetSparkle")
			pl.Parent = bodyPart
		end
		if rarity == "Legendary" and not lod then
			-- beams don't render in ViewportFrames (RevealView draws its own rays) and add nothing to the bounding box
			for i = 1, 3 do
				local a = i / 3 * math.pi * 2
				local a0 = Instance.new("Attachment")
				a0.Position = Vector3.new(0, math.cos(a) * 0.8, math.sin(a) * 0.8) * s
				a0.Parent = ring
				local a1 = Instance.new("Attachment")
				a1.Position = Vector3.new(5, math.cos(a) * 0.9, math.sin(a) * 0.9) * s -- ring local X is world up
				a1.Parent = ring
				local b = Instance.new("Beam")
				b.Attachment0 = a0
				b.Attachment1 = a1
				b.Color = ColorSequence.new(GOLD)
				b.Transparency = NumberSequence.new(0.35, 1)
				b.LightEmission = 1
				b.FaceCamera = true
				b.Width0 = 0.35 * s
				b.Width1 = 0.1 * s
				b.Segments = 1
				CollectionService:AddTag(b, "PetSparkle")
				b.Parent = ring
			end
		end
	end

	model:SetAttribute("Radius", radius * s)
	model:SetAttribute("CentreY", bodyCF.Position.Y * s)
	model:SetAttribute("Height", (H.Position.Y + headSize.Y / 2) * s)
	model:SetAttribute("Kind", kind)
	model.WorldPivot = CFrame.new()
	addRaritySparkle(bodyPart, rarity, o)
	addShinyFx(bodyPart, spec, o)
	addEvolveGlow(model, spec, o)
	return model
end

-- Scales a built pet so its bounding box is `height` studs tall and its footprint is at most `maxWidth` across
-- (wide-winged pets like the Griffin would otherwise dwarf their owner), and refreshes the Radius / CentreY / Height
-- attributes to the new size. Returns the scale factor applied.
function PetModel.fitHeight(model: Model, height: number, maxWidth: number?): number
	local _, size = model:GetBoundingBox()
	if size.Y < 0.05 then
		return 1
	end
	local k = height / size.Y
	local wide = math.max(size.X, size.Z) * k
	if maxWidth and wide > maxWidth then
		k *= maxWidth / wide
	end
	local ok = pcall(function()
		model:ScaleTo(model:GetScale() * k)
	end)
	if not ok then
		return 1
	end
	for _, name in { "Radius", "CentreY", "Height" } do
		local v = model:GetAttribute(name)
		if type(v) == "number" then
			model:SetAttribute(name, v * k)
		end
	end
	return k
end

-- Display name of a species ("Frost Wyvern"), falling back to the id.
function PetModel.name(mineral: any): string
	local m = (Config.Minerals :: any)[mineral]
	return if m then m.Name else tostring(mineral)
end

return PetModel
