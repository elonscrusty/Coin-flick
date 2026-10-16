--!strict
-- Procedural egg and pet presentation (Find The Pet). The module keeps its old name and public API
-- (build, example, onStand, frontHalves, shellFit, rockLook, rockShell, rubble, grit, gritPatch, RockVariants)
-- so every caller still compiles; what players SEE is now:
--   rockShell   a spotted pastel EGG (pile, basket, tray, plate). Look comes only from the opaque egg id and the
--               round seed (rockLook), never from target info, so the pet egg looks like every other egg.
--   rubble      a little heap of cracked eggshell pieces.
--   grit        a tiny shell crumb (hit bursts, pickup dust); gritPatch is off.
--   build       the pet itself (PetModel); example = a decorative pet; onStand = a pet on a little nest.
--   frontHalves two cracked eggshell halves around the pet that open in the hatch (RevealView, StationView).
-- All procedural Parts. REPLACE: real egg / shell / nest meshes when the owner uploads them.

local Config = require(script.Parent.Config)
local GeodeGen = require(script.Parent.GeodeGen)
local PetModel = require(script.Parent.PetModel)
-- smooth Blender egg / shell / nest meshes (Shared.EggKit + ReplicatedStorage.EggKitMeshes); falls back to Parts
local EggKit: any = nil
do
	local mod = script.Parent:FindFirstChild("EggKit")
	if mod and mod:IsA("ModuleScript") then
		local ok, m = pcall(require, mod)
		if ok then
			EggKit = m
		end
	end
end
-- the owner's textured low-poly pile eggs (Shared.WorldKit + ReplicatedStorage.WorldKit_LowPoly); nil = EggKit / Parts
local WorldKit: any = nil
do
	local mod = script.Parent:FindFirstChild("WorldKit")
	if mod and mod:IsA("ModuleScript") then
		local ok, m = pcall(require, mod)
		if ok then
			WorldKit = m
		end
	end
end
local function eggKit(...: string): boolean
	if EggKit == nil then
		return false
	end
	for _, n in { ... } do
		if not EggKit.has(n) then
			return false
		end
	end
	return true
end

local GeodeModel = {}

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, shape: string?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
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
	p.Parent = parent
	return p
end

-- Pastel egg shells and their spot colours. Every egg in a round draws from the same lists. A shade deeper than the
-- first pastels: those read as washed-out white in bright sun on a phone (owner video).
local EGG_TINTS = {
	Color3.fromRGB(255, 214, 176), Color3.fromRGB(182, 222, 255), Color3.fromRGB(255, 196, 218), Color3.fromRGB(198, 236, 184),
	Color3.fromRGB(222, 200, 255), Color3.fromRGB(255, 234, 158), Color3.fromRGB(176, 236, 220), Color3.fromRGB(255, 206, 178),
}
local SPOT_TINTS = {
	Color3.fromRGB(255, 160, 186), Color3.fromRGB(130, 196, 255), Color3.fromRGB(150, 220, 140), Color3.fromRGB(200, 160, 255),
	Color3.fromRGB(255, 196, 110), Color3.fromRGB(110, 214, 200),
}
local SHELL_INSIDE = Color3.fromRGB(255, 252, 244)

-- EGG_TINTS index -> WorldKit egg mesh (two tints each, by hue: peach/yellow, blue/lilac, pink/rose, green/mint)
local WORLD_EGG = { "HuntEgg_Yellow", "HuntEgg_Blue", "HuntEgg_Pink", "HuntEgg_Green", "HuntEgg_Blue", "HuntEgg_Yellow", "HuntEgg_Green", "HuntEgg_Pink" }

local PATTERNS = 12 -- 4 pattern kinds (spots, band, stripes, dots) x 3 spot colour offsets
GeodeModel.RockVariants = PATTERNS

local function eggTint(i: number): Color3
	return EGG_TINTS[((i - 1) % #EGG_TINTS) + 1]
end

local function spotTint(i: number): Color3
	return SPOT_TINTS[((i - 1) % #SPOT_TINTS) + 1]
end

-- Point and outward normal on an egg ellipsoid (half width a, half height b) at polar angle th from the top, azimuth ph.
local function eggPoint(a: number, b: number, th: number, ph: number): (Vector3, Vector3)
	local d = Vector3.new(math.sin(th) * math.cos(ph), math.cos(th), math.sin(th) * math.sin(ph))
	local p = Vector3.new(d.X * a, d.Y * b, d.Z * a)
	local nrm = Vector3.new(d.X / a, d.Y / b, d.Z / a).Unit
	return p, nrm
end

local function tangentCF(p: Vector3, nrm: Vector3): CFrame
	local up = if math.abs(nrm.Y) > 0.98 then Vector3.zAxis else Vector3.yAxis
	return CFrame.lookAt(p, p + nrm, up)
end

-- Pet presentation -------------------------------------------------------------------------------

export type BuildOpts = {
	Scale: number?, -- overrides the mass scale
	Lod: boolean?, -- fewer pieces (gallery shelves)
	Tiny: boolean?, -- fewest pieces (implies Lod)
	NoLight: boolean?, -- no light (many pets in one view)
	Tilt: number?, -- ignored for pets (kept for callers)
}

-- The pet for a specimen (spec: Mineral, Formation, Modifier, Rarity, Mass, Seed). Pivot = feet on the ground, faces -Z.
function GeodeModel.build(spec: { [string]: any }, opts: BuildOpts?): Model
	local o: BuildOpts = opts or {}
	local m = PetModel.build(spec, { Scale = o.Scale, Lod = o.Lod, Tiny = o.Tiny, NoLight = o.NoLight })
	m.Name = "CT_Rocks_Specimen"
	return m
end

-- A public DECORATIVE example pet (lobby signs, pedestals): a made-up specimen with no Id, tagged "Decorative".
function GeodeModel.example(mineral: string, seed: number, opts: BuildOpts?): Model
	local o: BuildOpts = table.clone(opts or {})
	if o.Lod == nil then
		o.Lod = true
	end
	local forms = { "Cluster", "Spire", "TwinCore", "HollowBloom" }
	local model = GeodeModel.build({ Mineral = mineral, Formation = forms[seed % #forms + 1], Modifier = "Natural", Rarity = "Common", Mass = 1.2, Seed = seed }, o)
	model.Name = "CT_Rocks_DecorGeode"
	model:SetAttribute("Decorative", true)
	return model
end

-- A pet sitting in a little straw nest on a short pastel pedestal (gallery, Collection corner). Pivot = floor centre.
-- REPLACE: real nest mesh.
function GeodeModel.onStand(spec: { [string]: any }, opts: BuildOpts?): Model
	local o: BuildOpts = table.clone(opts or {})
	local s = o.Scale or GeodeGen.visualScale(spec.Mass or 1)
	o.Scale = s
	local pet = GeodeModel.build(spec, o)
	local out = Instance.new("Model")
	out.Name = "CT_Rocks_SpecimenStand"
	local W = 2.3 * s
	local H = 0.32 * s
	local straw = Color3.fromRGB(214, 172, 108)
	if eggKit("Pedestal", "Nest_Ring") then
		-- soft rounded pedestal + woven straw ring
		local pn: Vector3 = EggKit.size("Pedestal")
		EggKit.place(out, "Pedestal", "StandBase", CFrame.new(), Vector3.new(W / pn.X, H / pn.Y, W / pn.Z), Color3.fromRGB(255, 226, 236))
		part(out, "Nest", Vector3.new(0.12 * s, W * 0.8, W * 0.8), CFrame.new(0, H + 0.05 * s, 0) * CFrame.Angles(0, 0, math.rad(90)), straw:Lerp(Color3.new(0, 0, 0), 0.15), Enum.Material.Fabric, "cyl")
		local nn: Vector3 = EggKit.size("Nest_Ring")
		local k = W * 0.92 / nn.X
		EggKit.place(out, "Nest_Ring", "Nest", CFrame.new(0, H - 0.04 * s, 0), Vector3.new(k, k * 0.8, k), straw, Enum.Material.Fabric)
	else
		part(out, "StandBase", Vector3.new(H, W, W), CFrame.new(0, H / 2, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 226, 236), Enum.Material.SmoothPlastic, "cyl")
		part(out, "Nest", Vector3.new(0.18 * s, W * 0.82, W * 0.82), CFrame.new(0, H + 0.06 * s, 0) * CFrame.Angles(0, 0, math.rad(90)), straw:Lerp(Color3.new(0, 0, 0), 0.15), Enum.Material.Fabric, "cyl")
		local ring = if o.Tiny then 5 elseif o.Lod then 6 else 8
		for i = 1, ring do
			local a = i / ring * math.pi * 2
			local r = W * 0.38
			part(out, "Nest", Vector3.new(0.7, 0.34, 0.5) * s, CFrame.new(math.cos(a) * r, H + 0.16 * s, math.sin(a) * r) * CFrame.Angles(0, -a, 0.15), straw, Enum.Material.Fabric, "ball")
		end
	end
	local rest = H + 0.1 * s
	for _, d in pet:GetChildren() do
		if d:IsA("BasePart") then
			d.CFrame = CFrame.new(0, rest, 0) * d.CFrame
			d.Parent = out
		end
	end
	local centreY = pet:GetAttribute("CentreY")
	out:SetAttribute("CentreY", rest + (if type(centreY) == "number" then centreY else 1.1 * s))
	out:SetAttribute("Radius", pet:GetAttribute("Radius"))
	out:SetAttribute("OnStand", true)
	pet:Destroy()
	out.WorldPivot = CFrame.new()
	return out
end

-- Eggshell halves around a pet (hatch) ---------------------------------------------------------------

-- Egg around a pet at scale s: half width A, half height B, centre height Y (pivot = ground under the egg).
local function eggDims(s: number): (number, number, number)
	local A = 1.25 * s
	local B = 1.55 * s
	return A, B, B + 0.02 * s
end

function GeodeModel.shellFit(spec: { [string]: any }, scale: number?): { Width: number, Height: number, CentreY: number }?
	local s = scale or GeodeGen.visualScale(spec.Mass or 1)
	local A, B, Y = eggDims(s)
	return { Width = 2 * A, Height = 2 * B, CentreY = Y }
end

-- Two cracked eggshell halves (left x < 0, right x > 0) that together close a whole egg around the pet. Each half's
-- pivot is its outer hinge (x = -A or +A at the egg centre height). Neon "Crack" zigzags along the seam start
-- invisible (Transparency 1). Colour comes from spec.Seed only (the reveal never needs the pile egg's look).
-- Returns { left, right }.
function GeodeModel.frontHalves(spec: { [string]: any }, scale: number?): { Model }
	local s = scale or GeodeGen.visualScale(spec.Mass or 1)
	local A, B, Y = eggDims(s)
	local seed = spec.Seed or 1
	local shell = eggTint(seed % #EGG_TINTS + 1)
	local spot = spotTint(seed % #SPOT_TINTS + 1)
	local rng = Random.new(seed + 7)
	local thick = 0.09 * s
	local centre = Vector3.new(0, Y, 0)
	local out = {}
	local meshShell = eggKit("Shell_Out", "Shell_In", "Shell_Spots")
	for side = -1, 1, 2 do
		local m = Instance.new("Model")
		m.Name = if side < 0 then "ShellLeft" else "ShellRight"
		m:SetAttribute("Side", side)
		if meshShell then
			-- smooth jagged half-shell meshes (built as the LEFT half; the right half is it turned half a turn)
			local k = Vector3.new(A / 1.25, B / 1.55, A / 1.25) -- meshes are the s = 1 egg (A 1.25, B 1.55)
			local frame = CFrame.new(centre) * (if side < 0 then CFrame.new() else CFrame.Angles(0, math.pi, 0))
			EggKit.place(m, "Shell_Out", "Shell", frame, k, shell)
			EggKit.place(m, "Shell_Spots", "Shell", frame, k, spot)
			EggKit.place(m, "Shell_In", "Inside", frame, k, SHELL_INSIDE)
		end
		-- rings of tangent slabs from the top pole to the bottom pole over this half's azimuths
		local rings: { { number } } = if meshShell then {} else { { 14, 1 }, { 38, 2 }, { 64, 3 }, { 90, 3 }, { 116, 3 }, { 142, 2 }, { 166, 1 } }
		for _, ring in rings do
			local th = math.rad(ring[1])
			local cnt = ring[2]
			for i = 1, cnt do
				local u = (i - 0.5) / cnt
				local ph = if side < 0 then math.pi / 2 + u * math.pi else -math.pi / 2 + u * math.pi
				local p, nrm = eggPoint(A, B, th, ph)
				local w = math.max(math.pi * A * math.sin(th) / cnt * 1.3, A * 0.42)
				local h = B * math.rad(26) * 1.45
				local col = shell
				if rng:NextNumber() < 0.3 then
					col = spot
				end
				part(m, "Shell", Vector3.new(w, h, thick), CFrame.new(centre) * tangentCF(p, nrm) * CFrame.new(0, 0, -thick / 2), col, Enum.Material.SmoothPlastic)
			end
		end
		-- pale inside lining so an opened half reads as a shell
		if not meshShell then
			part(m, "Inside", Vector3.new(0.05 * s, B * 1.5, A * 1.5), CFrame.new(centre + Vector3.new(side * 0.12 * s, 0, 0)), SHELL_INSIDE, Enum.Material.SmoothPlastic, "ball")
		end
		-- zigzag crack along the seam (x = 0 plane), shared by both halves
		local seamRng = Random.new(seed + 19)
		local prev: Vector3? = nil
		for t = -70, 250, 20 do
			local tr = math.rad(t)
			local zig = (if (t // 20) % 2 == 0 then 0.07 else -0.07) * s + seamRng:NextNumber(-0.02, 0.02) * s
			local pnt = Vector3.new(zig, math.sin(tr) * B * 1.03, -math.cos(tr) * A * 1.03)
			if prev then
				local mid = (prev + pnt) / 2
				local len = (pnt - prev).Magnitude
				local c = part(m, "Crack", Vector3.new(0.06 * s, 0.05 * s, len + 0.04 * s), CFrame.new(centre) * CFrame.lookAt(mid, pnt), Color3.fromRGB(255, 248, 210), Enum.Material.Neon)
				c.Transparency = 1
			end
			prev = pnt
		end
		m.WorldPivot = CFrame.new(centre + Vector3.new(side * A * 0.97, 0, 0))
		table.insert(out, m)
	end
	return out
end

-- Pile eggs ---------------------------------------------------------------------------------------

-- Pattern, tint index and yaw for an opaque egg id in a round (stable on every client; nothing about the target).
function GeodeModel.rockLook(id: number, seed: number): (number, number, number)
	local r = Random.new((seed % 100000) * 7919 + id * 104729)
	return r:NextInteger(1, PATTERNS), r:NextInteger(1, #EGG_TINTS), r:NextNumber(0, 360)
end

export type RockOpts = {
	Tint: number?, -- EGG_TINTS index
	Low: boolean?, -- body only (eggs buried inside the mound)
	Mini: boolean?, -- miniature for the basket, tray and plate (no shadows)
	Interactive: boolean?, -- Bounds part can be hit by tap rays (pile eggs)
	Cracks: boolean?, -- unused for eggs (HitFx draws the crack lines)
	Color: Color3?, -- body colour instead of the tint (shop eggs); needs NoTexture to show on the owner's textured eggs
	NoTexture: boolean?, -- never the owner's textured pile eggs (the smooth kit egg or Parts, which take a colour)
}

local function bounds(m: Model, size: Vector3, interactive: boolean): BasePart
	local b = Instance.new("Part")
	b.Name = "Bounds"
	b.Anchored = true
	b.CanCollide = false
	b.CanTouch = false
	b.CanQuery = interactive
	b.CastShadow = false
	b.Transparency = 1
	b.Size = size
	b.Parent = m
	return b
end

-- One egg Model. `variant` 1..RockVariants = pattern, `size` = egg height in studs, `name` = the egg id. PrimaryPart
-- is "Bounds" (invisible interaction box, 1.25 x the egg height so callers resting at 0.4 x Bounds height sit it on
-- the surface). Visible pieces are named "Rock" (the plate's crack drift moves them). Pivot = egg centre.
-- REPLACE: real egg mesh.
function GeodeModel.rockShell(variant: number, size: number, name: string, opts: RockOpts?): Model
	local o: RockOpts = opts or {}
	local v = ((variant - 1) % PATTERNS) + 1
	local D = size
	local A, B = 0.39 * D, 0.5 * D
	local tint = o.Color or eggTint(o.Tint or 1)
	local spot = spotTint((o.Tint or 1) + (v - 1) // 4)
	local mini = o.Mini == true
	local m = Instance.new("Model")
	m.Name = name
	bounds(m, Vector3.new(2 * A * 1.1, 2 * B * 1.25, 2 * A * 1.1), o.Interactive == true)
	-- the owner's textured egg meshes, picked by the tint only (rockLook: egg id + round seed, never the target), so
	-- the pet egg looks like every other egg of its colour. All four must be there, else no egg uses them.
	local worldEgg = WORLD_EGG[((o.Tint or 1) - 1) % #WORLD_EGG + 1]
	local wsize: Vector3? = if WorldKit and not o.NoTexture and WorldKit.has(table.unpack(WorldKit.Eggs)) then WorldKit.size(worldEgg) else nil
	if wsize then
		local body: BasePart? = WorldKit.clone(worldEgg, "Rock")
		if body then
			-- one mesh, uniform scale to fit inside the old egg body (2A x 2B x 2A), bottom on the old egg's bottom
			local k = math.min(2 * A / wsize.X, 2 * B / wsize.Y, 2 * A / wsize.Z)
			body.Size = wsize * k
			body.CFrame = CFrame.new(0, -B + body.Size.Y / 2, 0) * CFrame.Angles(0, (v * 1.7) % (math.pi * 2), 0)
			body.CastShadow = not mini
			body.Parent = m
			m.PrimaryPart = m:FindFirstChild("Bounds") :: BasePart
			m:PivotTo(CFrame.new())
			return m
		end
	end
	local pat = "Egg_Pat" .. ((v - 1) % 4 + 1)
	if eggKit("Egg_Body", pat) then
		-- one smooth egg mesh + one pattern mesh (2 parts instead of up to 7)
		local nat: Vector3 = EggKit.size("Egg_Body")
		local k = Vector3.new(2 * A / nat.X, 2 * B / nat.Y, 2 * A / nat.Z)
		local yaw = CFrame.Angles(0, (v * 1.7) % (math.pi * 2), 0)
		local body = EggKit.place(m, "Egg_Body", "Rock", yaw, k, tint)
		if body then
			body.CastShadow = not mini
		end
		if not o.Low then
			local rngC = Random.new(v * 131 + (o.Tint or 1))
			local col = if (v - 1) % 4 == 3 then spot:Lerp(Color3.new(1, 1, 1), 0.15) else spot
			EggKit.place(m, pat, "Rock", yaw * CFrame.Angles(0, rngC:NextNumber(0, math.pi * 2), 0), k, col)
		end
		m.PrimaryPart = m:FindFirstChild("Bounds") :: BasePart
		m:PivotTo(CFrame.new())
		return m
	end
	local body = part(m, "Rock", Vector3.new(2 * A, 2 * B, 2 * A), CFrame.new(), tint, Enum.Material.SmoothPlastic, "ball")
	body.CastShadow = not mini
	if not o.Low then
		local kindIdx = (v - 1) % 4
		local rng = Random.new(v * 131 + (o.Tint or 1))
		local function decal(th: number, ph: number, w: number, h: number, col: Color3)
			local p, nrm = eggPoint(A, B, th, ph)
			part(m, "Rock", Vector3.new(w, h, 0.05 * D), tangentCF(p, nrm) * CFrame.new(0, 0, -0.012 * D), col, Enum.Material.SmoothPlastic, "ball")
		end
		if kindIdx == 0 then -- big spots
			for i = 1, 4 do
				local s = rng:NextNumber(0.2, 0.3) * D
				decal(rng:NextNumber(0.5, 2.3), i * 1.57 + rng:NextNumber(-0.4, 0.4), s, s, spot)
			end
		elseif kindIdx == 1 then -- zigzag band round the middle
			for i = 1, 6 do
				local ph = i / 6 * math.pi * 2
				local p, nrm = eggPoint(A, B, math.pi / 2, ph)
				part(m, "Rock", Vector3.new(0.4 * D, 0.1 * D, 0.04 * D), tangentCF(p, nrm) * CFrame.Angles(0, 0, if i % 2 == 0 then 0.5 else -0.5), spot, Enum.Material.SmoothPlastic)
			end
		elseif kindIdx == 2 then -- two stripes (rings of flat ovals)
			for _, th in { 1.15, 2.0 } do
				for i = 1, 3 do
					decal(th, i / 3 * math.pi * 2 + th, 0.42 * D, 0.1 * D, spot)
				end
			end
		else -- many small dots
			for i = 1, 6 do
				local s = rng:NextNumber(0.1, 0.14) * D
				decal(rng:NextNumber(0.4, 2.5), i * 1.05 + rng:NextNumber(-0.3, 0.3), s, s, spot:Lerp(Color3.new(1, 1, 1), 0.15))
			end
		end
	end
	m.PrimaryPart = m:FindFirstChild("Bounds") :: BasePart
	m:PivotTo(CFrame.new())
	return m
end

-- A small heap of cracked eggshell pieces about `size` studs across. Pivot = heap centre. Never nil now.
function GeodeModel.rubble(size: number, tint: number, name: string): Model?
	local rng = Random.new(#name * 97 + tint * 13)
	local col = eggTint(tint)
	local m = Instance.new("Model")
	m.Name = name
	bounds(m, Vector3.new(size * 0.8, size * 0.5, size * 0.8), false)
	for i = 1, 3 do
		local a = i / 3 * math.pi * 2 + rng:NextNumber(-0.4, 0.4)
		local r = size * 0.22
		local sz = size * rng:NextNumber(0.42, 0.58)
		local cf = CFrame.new(math.cos(a) * r, -size * 0.12 + i * 0.02 * size, math.sin(a) * r) * CFrame.Angles(rng:NextNumber(-0.6, 0.6), rng:NextNumber(0, 6.28), rng:NextNumber(-0.6, 0.6))
		if eggKit("Shard") then
			-- curved jagged bit of shell, about the old flat oval's footprint
			local nat: Vector3 = EggKit.size("Shard")
			local k = sz / math.max(nat.Y, nat.Z)
			local frame = cf * CFrame.Angles(math.rad(90), 0, 0)
			local sh = EggKit.place(m, "Shard", "Rock", CFrame.new(), Vector3.one * k, if i == 2 then SHELL_INSIDE else col)
			if sh then
				sh.CFrame = frame -- centred on the piece's spot (the mesh offset is irrelevant here)
			end
		else
			part(m, "Rock", Vector3.new(sz, sz * 0.22, sz * 0.8), cf, if i == 2 then SHELL_INSIDE else col, Enum.Material.SmoothPlastic, "ball")
		end
	end
	m.PrimaryPart = m:FindFirstChild("Bounds") :: BasePart
	m:PivotTo(CFrame.new())
	return m
end

-- Flat decorative patches are off (they read as pickable objects).
function GeodeModel.gritPatch(_width: number, _rng: Random): BasePart?
	return nil
end

-- Decorative bit (no id, never queryable): a tiny eggshell crumb for hit bursts and pickup dust. The grass clumps
-- this once also made for the pile base read as dark green discs and are gone.
function GeodeModel.grit(rng: Random, maxSize: number): BasePart
	local p = Instance.new("Part")
	p.Name = "Grit"
	local s = maxSize * rng:NextNumber(0.5, 1)
	p.Size = Vector3.new(s, s * 0.25, s * rng:NextNumber(0.6, 1))
	p.Color = if rng:NextNumber() < 0.5 then SHELL_INSIDE else EGG_TINTS[rng:NextInteger(1, #EGG_TINTS)]
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

local _ = Config -- (palette lives in Config; kept required for callers that rely on load order)

return GeodeModel
