--!strict
-- Re-skins a built hunt arena for one zone (theme data: shared/ZoneThemes). ArenaBuilder.applyZone calls it when the
-- arena is built and MatchService (through ArenaBuilder.applyZone) at every round start, so a reused arena always
-- shows the zone being hunted. Three passes:
--   1. ground: floor, bench, perimeter band, worn routes, road and the mound halo take the zone's colours and materials
--      (the pale pile bed itself is never changed: the eggs must read against it, Pass 11);
--   2. boundary: hill domes, tree crowns, bushes and trunks are tinted from their built (meadow) colour, stored once
--      as the ZoneBase attribute so every swap starts from the same base; the flower beds inside the fence are only
--      kept in the Meadow;
--   3. landmarks: one folder (CT_Rocks_ZoneScenery) rebuilt per zone change: a ring of small props just outside the
--      octagon (ZoneThemes.ringSpots) plus a hero landmark on the lower bench across the east drop (Space also gets a
--      planet and moon in the sky). Everything is anchored, collision/query/touch off, CameraIgnore, no shadow on
--      small bits. Every spot lies outside the containment octagon, so the pile, tables, nests and routes stay clear.
-- All procedural parts; no asset ids. REPLACE: real meshes per landmark when uploaded.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local ZoneThemes = require(Shared.ZoneThemes)
local Kit = require(script.Parent.ArenaKit)
local KitPlace = require(script.Parent.KitPlace)

-- Hero landmark size per set (studs); the owner's mesh ServerStorage.MeshyAssets.Zone_<Landmark> replaces the Part hero.
local HERO_SIZE: { [string]: Vector3 } = {
	Flowers = Vector3.new(20, 24, 20),
	BigTree = Vector3.new(30, 34, 30),
	IceRocks = Vector3.new(26, 26, 26),
	LavaRocks = Vector3.new(30, 22, 30),
	Crystals = Vector3.new(20, 28, 20),
}

type Theme = ZoneThemes.Theme

local ZoneScenery = {}

local FOLDER = "CT_Rocks_ZoneScenery"
local BED = Kit.C.Dirt -- the pile bed colour (ArenaBuilder buildGround)
local LEAF_NAMES = { Bush = true, Crown = true, CrownTop = true }

-- The meadow flower beds inside the fence, kept aside (not destroyed) while another zone is shown.
local meadowFlowers: { [Instance]: Instance } = setmetatable({}, { __mode = "k" }) :: any

local function mat(name: string): Enum.Material
	return (Enum.Material :: any)[name] or Enum.Material.SmoothPlastic
end

-- Ground ----------------------------------------------------------------------------------------

local function skinGround(root: Instance, t: Theme)
	local g = root:FindFirstChild("CT_Rocks_Ground")
	if not g then
		return
	end
	-- same mixes ArenaBuilder builds with, so the Meadow theme reproduces the built look exactly
	local band = t.Floor:Lerp(t.Band, 0.5)
	local worn = t.Floor:Lerp(t.Path, 0.55)
	local looks: { [string]: { Color: Color3, Material: Enum.Material } } = {
		CT_Rocks_Floor = { Color = t.Floor, Material = mat(t.FloorMaterial) },
		CT_Rocks_Bench = { Color = t.Bench, Material = mat(t.BenchMaterial) },
		CT_Rocks_GravelBand = { Color = band, Material = mat(t.BandMaterial) },
		CT_Rocks_GravelEdge = { Color = band:Lerp(t.Floor, 0.5), Material = mat(t.BandMaterial) },
		CT_Rocks_Route = { Color = worn, Material = mat(t.PathMaterial) },
		CT_Rocks_RouteEdge = { Color = t.Floor:Lerp(worn, 0.45), Material = mat(t.PathMaterial) },
		CT_Rocks_Road = { Color = t.Path, Material = mat(t.PathMaterial) },
	}
	for _, d in g:GetChildren() do
		local look = looks[d.Name]
		if look and d:IsA("BasePart") then
			d.Color = look.Color
			d.Material = look.Material
		end
	end
	-- mound pad: the bed stays pale; its lobes and the soft halo blend toward the zone floor
	local pad = g:FindFirstChild("CT_Rocks_MoundPad")
	if pad then
		for _, d in pad:GetChildren() do
			if d:IsA("BasePart") then
				if d.Name == "Lobe" then
					local mix = d:GetAttribute("FloorMix")
					d.Color = BED:Lerp(t.Floor, if type(mix) == "number" then mix else 0.25)
				elseif d.Name == "Halo" then
					d.Color = t.Floor:Lerp(BED, 0.35)
				end
			end
		end
	end
end

-- Boundary tint ---------------------------------------------------------------------------------

local function tint(p: BasePart, toward: Color3, mix: number, material: Enum.Material?)
	local base = p:GetAttribute("ZoneBase")
	if typeof(base) ~= "Color3" then
		base = p.Color
		p:SetAttribute("ZoneBase", base)
	end
	p.Color = (base :: Color3):Lerp(toward, mix)
	if material then
		p.Material = material
	end
end

local function skinBoundary(root: Instance, t: Theme)
	local edge = root:FindFirstChild("CT_Rocks_Boundary")
	if not edge then
		return
	end
	local hillMat, leafMat = mat(t.HillMaterial), mat(t.LeafMaterial)
	for _, d in edge:GetDescendants() do
		if d:IsA("BasePart") then
			if d.Name == "Dome" then
				tint(d, t.Hill, t.HillMix, hillMat)
			elseif LEAF_NAMES[d.Name] then
				tint(d, t.Leaf, t.LeafMix, leafMat)
			elseif d.Name == "Trunk" then
				tint(d, t.Trunk, t.TrunkMix, nil)
			end
		end
	end
	-- the flower beds just inside the fence are meadow only
	local flowers = meadowFlowers[root] or edge:FindFirstChild("Flowers")
	if flowers then
		meadowFlowers[root] = flowers
		flowers.Parent = if t.KeepMeadowFlowers then edge else nil
	end
end

-- procedural boulder clusters (ArenaKit.boulders) take the zone's boulder colour; the Meadow puts the built one back
local function skinBoulders(root: Instance, t: Theme)
	for _, m in root:GetDescendants() do
		if m.Name == "CT_Rocks_Boulders" and not m:FindFirstAncestor(FOLDER) then
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					tint(d, t.Boulder or Color3.new(1, 1, 1), if t.Boulder then 0.6 else 0, nil)
				end
			end
		end
	end
end

-- Landmark helpers --------------------------------------------------------------------------------

local function piece(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	return Kit.part(parent, name, size, cf, color, material, shape)
end

-- vertical cylinder standing on `base` (Roblox cylinders run along X)
local function column(parent: Instance, name: string, base: Vector3, height: number, dia: number, color: Color3, material: Enum.Material): Part
	return piece(parent, name, Vector3.new(height, dia, dia), CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, material, Enum.PartType.Cylinder)
end

local function ballAt(parent: Instance, name: string, pos: Vector3, dia: number, color: Color3, material: Enum.Material, squash: number?): Part
	return piece(parent, name, Vector3.new(dia, dia * (squash or 1), dia), CFrame.new(pos), color, material, Enum.PartType.Ball)
end

-- a chunky rock half sunk into the ground at `p`
local function rock(parent: Instance, name: string, p: Vector3, size: Vector3, color: Color3, material: Enum.Material, rng: Random): Part
	local cf = CFrame.new(p + Vector3.new(0, size.Y * 0.3, 0)) * CFrame.Angles(rng:NextNumber(-0.35, 0.35), rng:NextNumber(0, math.pi), rng:NextNumber(-0.35, 0.35))
	return piece(parent, name, size, cf, color, material)
end

-- a tilted shard / crystal rising from `p`
local function shard(parent: Instance, name: string, p: Vector3, w: number, h: number, color: Color3, material: Enum.Material, rng: Random, lean: number): Part
	local cf = CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0) * CFrame.Angles(rng:NextNumber(-lean, lean), 0, rng:NextNumber(-lean, lean))
	return piece(parent, name, Vector3.new(w, h, w), cf * CFrame.new(0, h * 0.4, 0) * CFrame.Angles(0, math.rad(45), 0), color, material)
end

local function glow(at: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = at
end

-- Landmark sets (p = arena-world ground point) ------------------------------------------------------

-- Meadow: flower patches outside the fence, a bed of giant flowers on the lower meadow.
local function meadowRing(f: Instance, p: Vector3, _t: Theme, rng: Random)
	for _ = 1, 6 do
		Kit.flower(f, p + Vector3.new(rng:NextNumber(-3.5, 3.5), 0, rng:NextNumber(-3.5, 3.5)), rng)
	end
end
local PETALS = { Color3.fromRGB(255, 142, 170), Color3.fromRGB(255, 255, 255), Color3.fromRGB(176, 150, 255) }
local function meadowHero(f: Instance, p: Vector3, t: Theme, rng: Random)
	local m = Kit.model(f, "GiantFlowers")
	for i = 1, 3 do
		local base = p + Vector3.new((i - 2) * 9 + rng:NextNumber(-1.5, 1.5), 0, rng:NextNumber(-3, 3))
		local h = rng:NextNumber(9, 14)
		column(m, "Stem", base, h, 0.9, Color3.fromRGB(70, 150, 70), Enum.Material.Grass)
		piece(m, "Leaf", Vector3.new(3.2, 0.3, 1.4), CFrame.new(base + Vector3.new(1.4, h * 0.35, 0)) * CFrame.Angles(0, 0, math.rad(25)), Color3.fromRGB(84, 168, 74), Enum.Material.Grass)
		local head = base + Vector3.new(0, h, 0)
		local petal = PETALS[i]
		for k = 1, 5 do
			local a = k / 5 * math.pi * 2
			ballAt(m, "Petal", head + Vector3.new(math.cos(a) * 1.9, 0, math.sin(a) * 1.9), 2.6, petal, Enum.Material.SmoothPlastic, 0.45)
		end
		ballAt(m, "Heart", head + Vector3.new(0, 0.3, 0), 2.2, t.Accent, Enum.Material.SmoothPlastic, 0.6)
	end
	for _ = 1, 14 do
		Kit.flower(f, p + Vector3.new(rng:NextNumber(-14, 14), 0, rng:NextNumber(-8, 8)), rng)
	end
end

-- Forest: small pines outside the fence, one huge old tree on the lower ground.
local function forestRing(f: Instance, p: Vector3, t: Theme, rng: Random)
	local m = Kit.model(f, "Pine")
	local s = rng:NextNumber(0.9, 1.3)
	column(m, "PineTrunk", p, 4 * s, 1.3 * s, t.Rock, Enum.Material.Wood)
	for k = 0, 2 do
		local dia = (7 - k * 2) * s
		ballAt(m, "Needles", p + Vector3.new(0, (4 + k * 2.6) * s, 0), dia, t.Accent:Lerp(Color3.new(0, 0, 0), k * 0.06), Enum.Material.LeafyGrass, 0.7)
	end
end
local function forestHero(f: Instance, p: Vector3, t: Theme, rng: Random)
	local m = Kit.model(f, "BigTree")
	local trunkH = 30
	column(m, "Trunk", p, trunkH, 6, t.Rock, Enum.Material.Wood)
	for k = 1, 5 do -- roots spreading out from the base
		local a = k / 5 * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		piece(m, "Root", Vector3.new(2.2, 1.8, 8), CFrame.lookAt(p + dir * 4.5 + Vector3.new(0, 0.6, 0), p + dir * 9) * CFrame.Angles(math.rad(-10), 0, 0), t.Rock:Lerp(Color3.new(0, 0, 0), 0.1), Enum.Material.Wood)
	end
	for _, side in { -1, 1 } do -- two big limbs
		local from = p + Vector3.new(0, trunkH * 0.7, 0)
		local to = from + Vector3.new(side * 9, 7, rng:NextNumber(-3, 3))
		Kit.bar(m, "Limb", from, to, 2.2, t.Rock, Enum.Material.Wood)
	end
	local crown = p + Vector3.new(0, trunkH + 4, 0)
	ballAt(m, "Canopy", crown, 24, t.Accent, Enum.Material.LeafyGrass, 0.75)
	for k = 1, 6 do
		local a = k / 6 * math.pi * 2
		ballAt(m, "Canopy", crown + Vector3.new(math.cos(a) * 10, rng:NextNumber(-4, 3), math.sin(a) * 10), rng:NextNumber(13, 17), t.Accent:Lerp(t.Leaf, rng:NextNumber(0, 0.5)), Enum.Material.LeafyGrass, 0.8)
	end
	-- a ring of red-cap mushrooms round the foot
	for k = 1, 6 do
		local a = k / 6 * math.pi * 2 + 0.3
		local at = p + Vector3.new(math.cos(a) * 8.5, 0, math.sin(a) * 8.5)
		column(m, "MushStem", at, 1.2, 0.5, Color3.fromRGB(240, 232, 214), Enum.Material.SmoothPlastic)
		ballAt(m, "MushCap", at + Vector3.new(0, 1.3, 0), 1.6, Color3.fromRGB(220, 70, 60), Enum.Material.SmoothPlastic, 0.55)
	end
end

-- Snow: ice rocks with snow caps outside the fence, an ice spire on a snow mound on the lower ground.
local function snowRing(f: Instance, p: Vector3, t: Theme, rng: Random)
	local m = Kit.model(f, "IceRocks")
	for _ = 1, 3 do
		local at = p + Vector3.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3))
		local s = Vector3.new(rng:NextNumber(2.5, 4.5), rng:NextNumber(2, 4), rng:NextNumber(2.5, 4.5))
		local r = rock(m, "IceRock", at, s, t.Rock:Lerp(t.Accent, rng:NextNumber(0, 0.4)), mat(t.RockMaterial), rng)
		piece(m, "SnowCap", Vector3.new(s.X * 0.9, 0.5, s.Z * 0.9), r.CFrame * CFrame.new(0, s.Y / 2, 0), t.Floor, Enum.Material.Snow)
	end
end
local function snowHero(f: Instance, p: Vector3, t: Theme, rng: Random)
	local m = Kit.model(f, "IceSpire")
	local mound = ballAt(m, "SnowMound", p + Vector3.new(0, -1, 0), 22, t.Floor, Enum.Material.Snow, 0.35)
	for k = 1, 7 do
		local a = k / 7 * math.pi * 2
		local r = if k == 1 then 0 else rng:NextNumber(3, 6)
		local h = if k == 1 then 26 else rng:NextNumber(9, 17)
		shard(m, "IceShard", p + Vector3.new(math.cos(a) * r, 1.5, math.sin(a) * r), if k == 1 then 4.5 else rng:NextNumber(2.2, 3.4), h, t.Rock:Lerp(t.Accent, rng:NextNumber(0, 0.5)), Enum.Material.Ice, rng, if k == 1 then 0.05 else 0.35)
	end
	for _ = 1, 4 do
		rock(m, "IceRock", p + Vector3.new(rng:NextNumber(-12, 12), 0, rng:NextNumber(-10, 10)), Vector3.new(rng:NextNumber(3, 5), rng:NextNumber(2, 4), rng:NextNumber(3, 5)), t.Rock, mat(t.RockMaterial), rng)
	end
	if t.Light then
		glow(mound, t.Light, 22, 0.8)
	end
end

-- Volcano: basalt rocks split by glowing lava cracks outside the fence, a small smoking cone on the lower ground.
local function lavaRing(f: Instance, p: Vector3, t: Theme, rng: Random)
	local m = Kit.model(f, "LavaRocks")
	for _ = 1, 3 do
		local at = p + Vector3.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3))
		local s = Vector3.new(rng:NextNumber(2.5, 4.5), rng:NextNumber(2, 3.6), rng:NextNumber(2.5, 4.5))
		local r = rock(m, "LavaRock", at, s, t.Rock, mat(t.RockMaterial), rng)
		-- two crossing cracks on the top face, a hair proud of it
		piece(m, "LavaCrack", Vector3.new(s.X * 0.8, 0.12, 0.28), r.CFrame * CFrame.new(0, s.Y / 2 + 0.03, 0) * CFrame.Angles(0, rng:NextNumber(-0.5, 0.5), 0), t.Accent, Enum.Material.Neon)
		piece(m, "LavaCrack", Vector3.new(0.24, 0.12, s.Z * 0.6), r.CFrame * CFrame.new(rng:NextNumber(-0.5, 0.5), s.Y / 2 + 0.03, 0), t.Accent, Enum.Material.Neon)
	end
	-- a crack across the ground beside the rocks
	piece(m, "LavaCrack", Vector3.new(0.35, 0.08, rng:NextNumber(4, 7)), CFrame.new(p + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0), t.Accent, Enum.Material.Neon)
end
local function lavaHero(f: Instance, p: Vector3, t: Theme, rng: Random)
	local m = Kit.model(f, "Volcano")
	local tiers = { 30, 25, 20, 15, 11 }
	local y = 0
	for k, dia in tiers do
		local h = 3.6
		column(m, "Cone", p + Vector3.new(0, y, 0), h, dia, t.Rock:Lerp(t.Hill, (k - 1) * 0.08), mat(t.RockMaterial))
		y += h
	end
	local pool = column(m, "LavaPool", p + Vector3.new(0, y - 0.3, 0), 0.4, 8, t.Accent, Enum.Material.Neon)
	-- three lava streams down the steps
	for k = 1, 3 do
		local a = k / 3 * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local top = p + dir * 4.5 + Vector3.new(0, y, 0)
		local foot = p + dir * 15.5 + Vector3.new(0, 0.2, 0)
		Kit.bar(m, "LavaFlow", top, foot, 0.9, t.Accent, Enum.Material.Neon)
	end
	-- glowing cracks across the ground round the cone
	for k = 1, 8 do
		local a = k / 8 * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local r = rng:NextNumber(17, 22)
		local at = p + Vector3.new(math.cos(a) * r, 0.05, math.sin(a) * r)
		piece(m, "LavaCrack", Vector3.new(0.4, 0.08, rng:NextNumber(4, 8)), CFrame.new(at) * CFrame.Angles(0, -a + rng:NextNumber(-0.6, 0.6), 0), t.Accent, Enum.Material.Neon)
	end
	if t.Light then
		glow(pool, t.Light, 30, 2)
	end
end

-- Space: crystal clusters outside the fence, a giant crystal cluster on the lower ground, a ringed planet and a moon.
local function crystalRing(f: Instance, p: Vector3, t: Theme, rng: Random)
	local m = Kit.model(f, "Crystals")
	rock(m, "CrystalBase", p, Vector3.new(3.6, 1.4, 3.6), t.Hill, mat(t.HillMaterial), rng)
	for k = 1, 3 do
		local neon = k == 1
		shard(m, "Crystal", p + Vector3.new(rng:NextNumber(-1.5, 1.5), 0.4, rng:NextNumber(-1.5, 1.5)), rng:NextNumber(1.0, 1.6), rng:NextNumber(4, 8), if neon then t.Accent else t.Rock, if neon then Enum.Material.Neon else mat(t.RockMaterial), rng, 0.4)
	end
end
local function crystalHero(f: Instance, p: Vector3, t: Theme, rng: Random)
	local m = Kit.model(f, "CrystalCluster")
	local base = rock(m, "CrystalBase", p, Vector3.new(14, 3, 12), t.Hill, mat(t.HillMaterial), rng)
	for k = 1, 8 do
		local a = k / 8 * math.pi * 2
		local r = if k == 1 then 0 else rng:NextNumber(2.5, 5)
		local h = if k == 1 then 24 else rng:NextNumber(8, 16)
		local neon = k % 3 == 0
		shard(m, "Crystal", p + Vector3.new(math.cos(a) * r, 1, math.sin(a) * r), if k == 1 then 4 else rng:NextNumber(1.8, 3), h, if neon then t.Accent else t.Rock, if neon then Enum.Material.Neon else mat(t.RockMaterial), rng, if k == 1 then 0.05 else 0.4)
	end
	if t.Light then
		glow(base, t.Light, 26, 1.2)
	end
end
local function spaceSky(f: Instance, c: Vector3, t: Theme)
	local m = Kit.model(f, "Planet")
	local at = c + ZoneThemes.PlanetSpot
	ballAt(m, "Planet", at, 28, Color3.fromRGB(120, 92, 200), Enum.Material.SmoothPlastic)
	ballAt(m, "PlanetBand", at, 28.4, Color3.fromRGB(170, 140, 240), Enum.Material.SmoothPlastic, 0.18)
	local ring = piece(m, "PlanetRing", Vector3.new(0.5, 50, 50), CFrame.new(at) * CFrame.Angles(math.rad(18), 0, math.rad(90 + 14)), t.Accent:Lerp(Color3.new(1, 1, 1), 0.4), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	ring.Transparency = 0.35
	local moon = c + ZoneThemes.MoonSpot
	ballAt(m, "Moon", moon, 9, Color3.fromRGB(214, 214, 226), Enum.Material.Slate)
	ballAt(m, "Crater", moon + Vector3.new(-3.6, 1.2, 1.8), 2.4, Color3.fromRGB(176, 176, 190), Enum.Material.Slate, 0.5)
	ballAt(m, "Crater", moon + Vector3.new(-3.2, -1.8, -2.2), 1.8, Color3.fromRGB(176, 176, 190), Enum.Material.Slate, 0.5)
end

type Builder = (Instance, Vector3, Theme, Random) -> ()
local SETS: { [string]: { Ring: Builder, Hero: Builder } } = {
	Flowers = { Ring = meadowRing, Hero = meadowHero },
	BigTree = { Ring = forestRing, Hero = forestHero },
	IceRocks = { Ring = snowRing, Hero = snowHero },
	LavaRocks = { Ring = lavaRing, Hero = lavaHero },
	Crystals = { Ring = crystalRing, Hero = crystalHero },
}

local function seedOf(id: string): number
	local n = 0
	for i = 1, #id do
		n = (n * 31 + string.byte(id, i)) % 100000
	end
	return 4000 + n
end

local function buildLandmarks(root: Instance, c: Vector3, t: Theme)
	local old = root:FindFirstChild(FOLDER)
	if old then
		old:Destroy()
	end
	local set = SETS[t.Landmark]
	if not set then
		return
	end
	local f = Kit.folder(root, FOLDER)
	local rng = Random.new(seedOf(t.Id))
	for _, spot in ZoneThemes.ringSpots() do
		set.Ring(f, c + spot, t, rng)
	end
	local heroAt = c + ZoneThemes.HeroSpot
	local size = HERO_SIZE[t.Landmark] or Vector3.new(24, 24, 24)
	local hero = KitPlace.meshy("Zone_" .. t.Landmark, CFrame.new(heroAt + Vector3.new(0, size.Y / 2, 0)) * CFrame.Angles(0, math.rad(-90), 0), size)
	if hero then
		hero.Name = "HeroMesh"
		local box, ext = hero:GetBoundingBox()
		hero:PivotTo(hero:GetPivot() + Vector3.new(0, heroAt.Y + ext.Y / 2 - box.Position.Y - 0.5, 0)) -- sit just into the ground
		hero.Parent = f
	else
		set.Hero(f, heroAt, t, rng)
	end
	if t.Landmark == "Crystals" then
		spaceSky(f, c, t)
	end
	-- decor only: no collision, queries or touch, ignored by the camera; only the big pieces cast shadows
	-- (and never the sky props, which would shade the arena)
	for _, d in f:GetDescendants() do
		if d:IsA("BasePart") then
			Kit.deco(d)
			d:SetAttribute("CameraIgnore", true)
			d.CastShadow = d.Size.Magnitude > 12 and d.Position.Y < c.Y + 50
		end
	end
end

-- Applies zone `t` to the arena under `root` (centre `c`). Cheap when the zone is already shown.
function ZoneScenery.apply(root: Instance, c: Vector3, t: Theme)
	if root:GetAttribute("Zone") == t.Id and root:FindFirstChild(FOLDER) then
		return
	end
	skinGround(root, t)
	skinBoundary(root, t)
	skinBoulders(root, t)
	buildLandmarks(root, c, t)
	root:SetAttribute("Zone", t.Id)
end

return ZoneScenery
