--!strict
-- Reusable arena kit (V4 arena, docs/ASSET_MANIFEST.md "Arena kit"): quarry cliff forms, base
-- ledges and boulders, retaining walls, railings, lamps, gate, shelter, utility props, the shared
-- sell hopper and the background crane/conveyor. Everything is built from anchored Parts in the
-- chunky low-poly quarry style; each builder is a REPLACE point for an uploaded mesh of the same
-- name (CT_Rocks_<Name>). Local frames: -Z faces the arena (front), +Y is up, origin on the floor.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local KitPlace = require(script.Parent.KitPlace)
-- soft Blender meadow props (trees, bushes, hills, hedges, flowers); nil-safe: falls back to the ball props
local MeadowKit: any = nil
do
	local mod = script.Parent:FindFirstChild("MeadowKit")
	if mod and mod:IsA("ModuleScript") then
		local ok, m = pcall(require, mod)
		if ok then
			MeadowKit = m
		end
	end
end
local function meadow(name: string): boolean
	return MeadowKit ~= nil and MeadowKit.has(name)
end

local Kit = {}

-- The meadow never uses the quarry meshes: they count as absent here so the procedural meadow props build.
local function noKit(...: string): boolean
	return false
end
local function noPlace(...: any): any
	return nil
end

-- Palette (owner brief V4 section C) plus a few stone and ground tones derived from it.
local C = {
	Charcoal = Color3.fromRGB(104, 78, 98), -- plum brown
	Slate = Color3.fromRGB(150, 138, 186), -- pastel lavender
	Concrete = Color3.fromRGB(244, 228, 198), -- cream
	Wood = Color3.fromRGB(214, 156, 98), -- honey wood
	Amber = Color3.fromRGB(255, 212, 92), -- sunny yellow
	OffWhite = Color3.fromRGB(244, 239, 229), -- #F4EFE5
	Mint = Color3.fromRGB(114, 204, 160), -- #72CCA0
	Floor = Color3.fromRGB(112, 190, 84), -- meadow grass
	FloorDark = Color3.fromRGB(214, 180, 118), -- dirt paths
	Bench = Color3.fromRGB(128, 200, 96), -- lower meadow outside the drop
	Dirt = Color3.fromRGB(232, 200, 128), -- straw patch
	PadConcrete = Color3.fromRGB(236, 206, 156), -- station / bay pads (pale planks)
	Stone = { Color3.fromRGB(104, 180, 84), Color3.fromRGB(92, 168, 80), Color3.fromRGB(122, 194, 92) }, -- hill greens
	Strata = Color3.fromRGB(240, 222, 170),
	Dust = Color3.fromRGB(236, 206, 140),
	Steel = Color3.fromRGB(176, 206, 214),
	Rubber = Color3.fromRGB(86, 70, 74),
}
Kit.C = C

-- Prospector Lodge kit language (blender/models/lodge_building.py and _lodgeparts.py, docs/lodge): warm timber,
-- dark iron fittings, slate-brown roofing, warm stone, plaster, sign wood with cream letters and a muted gold
-- trim. The quarry structures (tables, sell bins, shelters, crane) use the same colours so the hunt reads as
-- the same world as the lobby.
local L = {
	Timber = Color3.fromRGB(206, 138, 84), -- #A9693F WoodMain: posts, beams, bin bodies
	TimberLight = Color3.fromRGB(234, 172, 112), -- #BC7E4E countertops, plank faces
	TimberDark = Color3.fromRGB(150, 96, 64), -- #70452D frames, battens, skids
	SignWood = Color3.fromRGB(172, 112, 72), -- #8A5532 sign faces (cream letters)
	Iron = Color3.fromRGB(124, 98, 90), -- warm brown fittings straps, hinges, bolts, lantern frames
	Stone = Color3.fromRGB(218, 200, 172), -- #A79F90 footings, foundation blocks
	StoneDark = Color3.fromRGB(180, 164, 140), -- #827B71
	Roof = Color3.fromRGB(226, 122, 120), -- coral roof slate-brown roof
	Plaster = Color3.fromRGB(252, 238, 212), -- #E7D6B8
	Gold = Color3.fromRGB(250, 204, 84), -- #C9A042 muted trim (not emissive)
	Cream = Color3.fromRGB(246, 238, 220), -- sign letters
	Charcoal = Color3.fromRGB(110, 82, 104), -- #282B30 board faces
}
Kit.L = L

-- Recolours a placed kit model (MeshParts named after their colour slot) into the lodge language. Slots it does not
-- know (Lamp, Glass, Rubber, Rock, Amber accents on purpose) are left as they are.
local LODGE_SLOT = {
	Wood = L.TimberLight,
	Timber = L.Timber,
	WoodDark = L.TimberDark,
	Frame = L.Iron,
	FrameDark = Color3.fromRGB(42, 44, 47),
	Slate = L.Roof,
	Concrete = L.Stone,
	Steel = Color3.fromRGB(128, 132, 136),
	SteelLight = Color3.fromRGB(150, 148, 142),
	Amber = L.Gold,
}
function Kit.lodgeSkin(m: Instance?)
	if not m then
		return
	end
	for _, d in m:GetDescendants() do
		if d:IsA("MeshPart") then
			local slot = string.match(d.Name, "^([%a]+)") or d.Name
			local col = LODGE_SLOT[slot]
			if col then
				d.Color = col
				if slot == "Wood" or slot == "Timber" or slot == "WoodDark" then
					d.Material = Enum.Material.Wood
				end
			end
		end
	end
end
-- warm charcoal for straps, rims and mast metal (the palette Charcoal reads black in the work view)
local HOP_METAL = Color3.fromRGB(170, 120, 82)

-- Primitives ------------------------------------------------------------------------------

function Kit.part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.Shape = shape or Enum.PartType.Block
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Default WedgePart: the slope faces front (-Z) and up, full height at the back (+Z).
function Kit.wedge(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?): WedgePart
	local p = Instance.new("WedgePart")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.Slate
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Visual only: no collision, queries or touch.
function Kit.deco<T>(p: T): T
	local b = (p :: any) :: BasePart
	b.CanCollide = false
	b.CanQuery = false
	b.CanTouch = false
	return p
end

function Kit.model(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

function Kit.folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- A square bar from world point a to world point b.
function Kit.bar(parent: Instance, name: string, a: Vector3, b: Vector3, thick: number, color: Color3, mat: Enum.Material?): Part
	local len = (b - a).Magnitude
	local up = if math.abs((b - a).Unit.Y) > 0.99 then Vector3.new(1, 0, 0) else Vector3.yAxis
	return Kit.part(parent, name, Vector3.new(thick, thick, len), CFrame.lookAt((a + b) / 2, b, up), color, mat or Enum.Material.Metal)
end

-- A cylinder from world point a to world point b (cables, pipes, tanks).
function Kit.pipe(parent: Instance, name: string, a: Vector3, b: Vector3, dia: number, color: Color3, mat: Enum.Material?): Part
	local len = (b - a).Magnitude
	local up = if math.abs((b - a).Unit.Y) > 0.99 then Vector3.new(1, 0, 0) else Vector3.yAxis
	local cf = CFrame.lookAt((a + b) / 2, b, up) * CFrame.Angles(0, math.rad(90), 0)
	return Kit.part(parent, name, Vector3.new(len, dia, dia), cf, color, mat or Enum.Material.Metal, Enum.PartType.Cylinder)
end

-- Fitted text on one face of a part (SignLayout via KitPlace.applyFit: explicit TextSize, never TextScaled), with the
-- sign attributes (SignText / SignPreset / SignW / SignH) the numeric sign audit reads. The face size comes from the
-- part: Front/Back use X x Y, Left/Right Z x Y, Top/Bottom X x Z.
function Kit.label(p: BasePart, face: Enum.NormalId, text: string, color: Color3?, bg: Color3?, preset: string?): TextLabel
	local s = p.Size
	local w, h
	if face == Enum.NormalId.Front or face == Enum.NormalId.Back then
		w, h = s.X, s.Y
	elseif face == Enum.NormalId.Left or face == Enum.NormalId.Right then
		w, h = s.Z, s.Y
	else
		w, h = s.X, s.Z
	end
	local g = Instance.new("SurfaceGui")
	g.Name = "Label"
	g.Face = face
	g.LightInfluence = 0
	g.Parent = p
	local t = Instance.new("TextLabel")
	t.Name = "Text"
	t.BackgroundColor3 = bg or C.Charcoal
	t.BackgroundTransparency = if bg then 0 else 1
	t.TextColor3 = color or C.Amber
	t.Font = Enum.Font.FredokaOne
	t.Parent = g
	local f = KitPlace.applyFit(g, t, text, w, h, preset or "Plaque")
	p:SetAttribute("SignText", f.Text)
	p:SetAttribute("SignPreset", preset or "Plaque")
	p:SetAttribute("SignW", w)
	p:SetAttribute("SignH", h)
	return t
end

local function stone(rng: Random): Color3
	return C.Stone[rng:NextInteger(1, #C.Stone)]
end

-- Cliffs -----------------------------------------------------------------------------------

-- One rock mass: a block with a sloped (wedge) cap toward the arena, a dust top, and an optional
-- lighter strata band on the front face. `cf` is the mass's base-front-centre, -Z out.
local function mass(m: Model, cf0: CFrame, w: number, h: number, d: number, rng: Random, strata: boolean?)
	local col = stone(rng)
	-- a little yaw and back-lean per mass so neighbouring faces never line up like bricks
	local cf = cf0 * CFrame.Angles(math.rad(rng:NextNumber(-7, 0)), math.rad(rng:NextNumber(-8, 8)), math.rad(rng:NextNumber(-3, 3)))
	local capH = math.min(h * 0.3, 7) * rng:NextNumber(0.6, 1)
	local bodyH = h - capH
	local base = -12 -- masses reach below the lower bench so no gap shows from any side
	Kit.part(m, "Mass", Vector3.new(w, bodyH - base, d), cf * CFrame.new(0, (bodyH + base) / 2, d / 2), col, Enum.Material.Slate)
	-- sloped cap: low edge at the front, flat block behind it, same stone colour (one silhouette)
	local capD = d * rng:NextNumber(0.45, 0.7)
	Kit.wedge(m, "Cap", Vector3.new(w, capH, capD), cf * CFrame.new(0, bodyH + capH / 2, capD / 2), col)
	Kit.part(m, "Top", Vector3.new(w, capH, d - capD), cf * CFrame.new(0, bodyH + capH / 2, capD + (d - capD) / 2), col, Enum.Material.Slate)
	Kit.deco(Kit.part(m, "Dust", Vector3.new(w * rng:NextNumber(0.4, 0.7), 0.3, (d - capD) * 0.6), cf * CFrame.new(w * rng:NextNumber(-0.15, 0.15), h + 0.1, capD + (d - capD) * 0.6), C.Dust, Enum.Material.Ground))
	if strata then
		local y = bodyH * rng:NextNumber(0.35, 0.7)
		Kit.deco(Kit.part(m, "Strata", Vector3.new(w + 0.2, rng:NextNumber(0.9, 1.6), 0.5), cf * CFrame.new(0, y, 0.1), C.Strata, Enum.Material.Sandstone))
	end
end

-- Eight broad cliff silhouettes. `cf` is the base-front-centre of the form (-Z faces the arena),
-- w its width, h its nominal height. Each variant is a different arrangement of 2-4 masses.
local CLIFF_VARIANTS: { (m: Model, cf: CFrame, w: number, h: number, rng: Random) -> () } = {
	-- 1 stepped mesa: low front bench, tall block set back
	function(m, cf, w, h, rng)
		mass(m, cf, w, h * 0.45, 8, rng, true)
		mass(m, cf * CFrame.new(w * 0.08, 0, 6), w * 0.75, h, 12, rng, true)
	end,
	-- 2 leaning slab: one broad mass tilted back, low talus wedge in front
	function(m, cf, w, h, rng)
		mass(m, cf * CFrame.new(0, 0, 2) * CFrame.Angles(math.rad(-6), 0, 0), w, h, 13, rng, true)
		Kit.wedge(m, "Talus", Vector3.new(w * 0.7, h * 0.18, 4), cf * CFrame.new(-w * 0.1, h * 0.09, 0.2), stone(rng))
	end,
	-- 3 twin buttress with a notch between
	function(m, cf, w, h, rng)
		mass(m, cf * CFrame.new(-w * 0.27, 0, 0), w * 0.46, h, 12, rng, true)
		mass(m, cf * CFrame.new(w * 0.27, 0, 1), w * 0.46, h * 0.82, 12, rng, true)
		mass(m, cf * CFrame.new(0, 0, 5), w * 0.3, h * 0.6, 8, rng)
	end,
	-- 4 shoulder: tall on one end, falling away to the other
	function(m, cf, w, h, rng)
		mass(m, cf * CFrame.new(-w * 0.22, 0, 0), w * 0.56, h, 13, rng, true)
		mass(m, cf * CFrame.new(w * 0.26, 0, 1), w * 0.5, h * 0.6, 12, rng, true)
		local s = Kit.wedge(m, "Shoulder", Vector3.new(12, h * 0.35, w * 0.3), cf * CFrame.new(w * 0.12, h * 0.6 + h * 0.175, 7) * CFrame.Angles(0, math.rad(-90), 0), stone(rng))
		s.CanCollide = false
	end,
	-- 5 terraced: three benches climbing back
	function(m, cf, w, h, rng)
		mass(m, cf, w, h * 0.32, 6, rng)
		mass(m, cf * CFrame.new(0, 0, 4.5), w * 0.92, h * 0.64, 7, rng, true)
		mass(m, cf * CFrame.new(-w * 0.05, 0, 9), w * 0.8, h, 8, rng)
	end,
	-- 6 broken tooth: tall narrow block beside a squat broad one
	function(m, cf, w, h, rng)
		mass(m, cf * CFrame.new(-w * 0.3, 0, 1), w * 0.36, h * 1.12, 11, rng, true)
		mass(m, cf * CFrame.new(w * 0.18, 0, 0), w * 0.66, h * 0.55, 12, rng, true)
	end,
	-- 7 rounded hump: three overlapping masses, highest in the middle
	function(m, cf, w, h, rng)
		mass(m, cf * CFrame.new(-w * 0.3, 0, 1) * CFrame.Angles(0, math.rad(8), 0), w * 0.42, h * 0.7, 11, rng)
		mass(m, cf * CFrame.new(0, 0, 0), w * 0.42, h, 12, rng, true)
		mass(m, cf * CFrame.new(w * 0.3, 0, 1) * CFrame.Angles(0, math.rad(-8), 0), w * 0.42, h * 0.74, 11, rng)
	end,
	-- 8 overhang ledge: body with a jutting upper shelf
	function(m, cf, w, h, rng)
		mass(m, cf * CFrame.new(0, 0, 2), w, h * 0.78, 12, rng, true)
		local shelf = Kit.part(m, "Shelf", Vector3.new(w * 0.6, 2.2, 6), cf * CFrame.new(w * 0.12, h * 0.78 - 1.1, 1.2), stone(rng), Enum.Material.Slate)
		shelf.CanCollide = false
		mass(m, cf * CFrame.new(w * 0.15, 0, 7), w * 0.55, h, 9, rng)
	end,
}
Kit.CliffVariants = #CLIFF_VARIANTS

function Kit.cliffParts(parent: Instance, cf: CFrame, variant: number, w: number, h: number, rng: Random): Model
	local m = Kit.model(parent, "CT_Rocks_Cliff_" .. variant)
	CLIFF_VARIANTS[((variant - 1) % #CLIFF_VARIANTS) + 1](m, cf, w, h, rng)
	return m
end

-- A low ledge step at a cliff base (walkable top, keeps players off the cliff face visually).
function Kit.ledgeParts(parent: Instance, cf: CFrame, w: number, h: number, d: number, rng: Random): Model
	local m = Kit.model(parent, "CT_Rocks_Ledge")
	local col = stone(rng)
	Kit.part(m, "Step", Vector3.new(w, h, d), cf * CFrame.new(0, h / 2, d / 2), col, Enum.Material.Slate)
	Kit.wedge(m, "Bevel", Vector3.new(w, h * 0.5, 1.4), cf * CFrame.new(0, h * 0.25, -0.7), col:Lerp(C.Dust, 0.2))
	return m
end

-- Boulder cluster: 2-4 faceted chunks with a contact skirt (grounded, no floating cubes).
function Kit.boulders(parent: Instance, cf: CFrame, size: number, rng: Random, count: number?): Model
	local m = Kit.model(parent, "CT_Rocks_Boulders")
	local n = count or rng:NextInteger(2, 4)
	for i = 1, n do
		local s = size * (if i == 1 then 1 else rng:NextNumber(0.4, 0.7))
		local off = if i == 1 then Vector3.zero else Vector3.new(rng:NextNumber(-0.9, 0.9) * size, 0, rng:NextNumber(-0.7, 0.7) * size)
		local col = stone(rng):Lerp(C.Dust, rng:NextNumber(0, 0.2))
		local yaw = rng:NextNumber(0, math.pi * 2)
		local body = Kit.part(m, "Chunk", Vector3.new(s, s * 0.62, s * 0.86), cf * CFrame.new(off + Vector3.new(0, s * 0.26, 0)) * CFrame.Angles(rng:NextNumber(-0.18, 0.18), yaw, rng:NextNumber(-0.18, 0.18)), col, Enum.Material.Slate)
		body.CanCollide = i == 1
		-- faceted shoulder on top
		Kit.deco(Kit.wedge(m, "Facet", Vector3.new(s * 0.8, s * 0.32, s * 0.6), cf * CFrame.new(off + Vector3.new(0, s * 0.72, 0)) * CFrame.Angles(0, yaw + rng:NextNumber(-0.5, 0.5), 0), col:Lerp(C.Dust, 0.15)))
	end
	return m
end

-- Sparse grit at a boundary: a few small dull stones, never near the pile, never collidable.
function Kit.grit(parent: Instance, center: Vector3, spread: number, rng: Random, count: number)
	for _ = 1, count do
		local s = rng:NextNumber(0.4, 1.0)
		local pos = center + Vector3.new(rng:NextNumber(-spread, spread), s * 0.2, rng:NextNumber(-spread * 0.5, spread * 0.5))
		Kit.deco(Kit.part(parent, "CT_Rocks_Grit", Vector3.new(s, s * 0.5, s * 0.8), CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, 6.28), rng:NextNumber(-0.3, 0.3)), C.Dust:Lerp(C.Stone[2], rng:NextNumber(0.2, 0.7)), Enum.Material.Slate))
	end
end

-- Structures ---------------------------------------------------------------------------------

-- Retaining wall: concrete panels between steel H-posts with a cap beam. `cf` is the base-centre
-- of the face; the wall stands from y = bottom to y = 0 (it holds the level behind it, +Z).
function Kit.retainingWallParts(parent: Instance, cf: CFrame, length: number, height: number, bottom: number?): Model
	local m = Kit.model(parent, "CT_Rocks_RetainingWall")
	local b = bottom or 0
	local top = b + height
	Kit.part(m, "Panels", Vector3.new(length, height - 0.04, 1.2), cf * CFrame.new(0, b + (height - 0.04) / 2, 0.6), C.Concrete, Enum.Material.WoodPlanks)
	local n = math.max(2, math.floor(length / 8) + 1)
	for i = 0, n - 1 do
		local x = -length / 2 + i * length / (n - 1)
		Kit.part(m, "Post", Vector3.new(0.9, height + 0.4, 0.7), cf * CFrame.new(x, b + height / 2 + 0.2, -0.3), C.Slate, Enum.Material.Wood)
		Kit.deco(Kit.part(m, "Flange", Vector3.new(1.4, height + 0.4, 0.2), cf * CFrame.new(x, b + height / 2 + 0.2, -0.65), C.Slate, Enum.Material.Wood))
	end
	Kit.part(m, "Cap", Vector3.new(length + 0.4, 0.8, 1.8), cf * CFrame.new(0, top + 0.3, 0.4), C.PadConcrete, Enum.Material.WoodPlanks)
	return m
end

-- Railing at a drop: slate posts, amber top rail, mid rail, toe board.
function Kit.railingParts(parent: Instance, a: Vector3, b: Vector3): Model
	local m = Kit.model(parent, "CT_Rocks_Railing")
	local len = (b - a).Magnitude
	local cf = CFrame.lookAt((a + b) / 2, b)
	local rail = L.TimberLight
	Kit.part(m, "TopRail", Vector3.new(0.3, 0.3, len), cf * CFrame.new(0, 3.0, 0), rail, Enum.Material.Wood)
	Kit.part(m, "MidRail", Vector3.new(0.26, 0.26, len), cf * CFrame.new(0, 1.7, 0), rail, Enum.Material.Wood)
	local n = math.max(2, math.floor(len / 5) + 1)
	for i = 0, n - 1 do
		local p = a:Lerp(b, i / (n - 1))
		Kit.part(m, "Post", Vector3.new(0.5, 3.4, 0.5), CFrame.new(p + Vector3.new(0, 1.7, 0)), L.Timber, Enum.Material.Wood)
		Kit.deco(Kit.part(m, "PostCap", Vector3.new(0.7, 0.25, 0.7), CFrame.new(p + Vector3.new(0, 3.45, 0)), L.Cream, Enum.Material.Wood))
	end
	return m
end

-- Lamp mast with a visible base, brace, arm and housing. `cf` faces the lit area (-Z).
function Kit.lampMast(parent: Instance, cf: CFrame, lit: boolean): Model
	local m = Kit.model(parent, "CT_Rocks_LampMast")
	Kit.part(m, "Footing", Vector3.new(1.8, 0.8, 1.8), cf * CFrame.new(0, 0.4, 0), C.PadConcrete, Enum.Material.Concrete)
	Kit.part(m, "Pole", Vector3.new(0.7, 9.4, 0.7), cf * CFrame.new(0, 5.1, 0), HOP_METAL, Enum.Material.SmoothPlastic)
	Kit.deco(Kit.bar(m, "Brace", cf:PointToWorldSpace(Vector3.new(0, 8.0, 0)), cf:PointToWorldSpace(Vector3.new(0, 9.8, -2.4)), 0.3, HOP_METAL))
	Kit.deco(Kit.part(m, "Arm", Vector3.new(0.4, 0.4, 3.2), cf * CFrame.new(0, 9.8, -1.4), HOP_METAL, Enum.Material.SmoothPlastic))
	local head = Kit.deco(Kit.part(m, "Housing", Vector3.new(1.8, 0.6, 1.2), cf * CFrame.new(0, 9.6, -3) * CFrame.Angles(math.rad(-15), 0, 0), HOP_METAL, Enum.Material.SmoothPlastic))
	local lens = Kit.deco(Kit.part(m, "Lens", Vector3.new(1.5, 0.12, 0.9), head.CFrame * CFrame.new(0, -0.32, 0), Color3.fromRGB(255, 236, 196), Enum.Material.Neon))
	Kit.deco(Kit.part(m, "Junction", Vector3.new(0.8, 1.0, 0.5), cf * CFrame.new(0, 2.2, 0.5), C.Amber, Enum.Material.Metal))
	if lit then
		local l = Instance.new("SpotLight")
		l.Face = Enum.NormalId.Bottom
		l.Range = 30
		l.Angle = 80
		l.Brightness = 1.4
		l.Color = Color3.fromRGB(255, 226, 180)
		l.Parent = lens
	end
	return m
end

-- Entrance gate: concrete pillars, steel header with a sign, closed mesh panels. `cf` is the
-- centre of the gateway on the floor, -Z faces the arena.
function Kit.gateParts(parent: Instance, cf: CFrame, width: number): Model
	local m = Kit.model(parent, "CT_Rocks_EntranceGate")
	for _, s in { -1, 1 } do
		local x = s * (width / 2 + 1.2)
		Kit.part(m, "Pillar", Vector3.new(2.4, 11, 2.4), cf * CFrame.new(x, 5.5, 0), C.Concrete, Enum.Material.Wood)
		Kit.deco(Kit.part(m, "PillarCap", Vector3.new(2.8, 0.6, 2.8), cf * CFrame.new(x, 11.3, 0), C.Slate, Enum.Material.Wood))
		for k = 0, 2 do
			Kit.deco(Kit.part(m, "Hazard", Vector3.new(2.45, 0.5, 2.45), cf * CFrame.new(x, 1 + k * 1.0, 0), if k % 2 == 0 then C.Amber else C.Charcoal, Enum.Material.SmoothPlastic))
		end
	end
	Kit.part(m, "Header", Vector3.new(width + 5, 1.2, 1.2), cf * CFrame.new(0, 12.2, 0), C.Slate, Enum.Material.Wood)
	local sign = Kit.deco(Kit.part(m, "Sign", Vector3.new(width * 0.7, 2.2, 0.3), cf * CFrame.new(0, 13.9, -0.2), C.Charcoal, Enum.Material.SmoothPlastic))
	Kit.label(sign, Enum.NormalId.Front, "PET MEADOW", C.Amber, nil, "Landmark")
	Kit.deco(Kit.part(m, "SignTrim", Vector3.new(width * 0.7 + 0.4, 0.25, 0.4), cf * CFrame.new(0, 15.05, -0.2), C.Amber, Enum.Material.Wood))
	-- two closed sliding panels: frame + vertical bars
	for _, s in { -1, 1 } do
		local pw = width / 2
		local px = s * pw / 2
		local frame = cf * CFrame.new(px, 0, 0.6)
		Kit.part(m, "PanelTop", Vector3.new(pw, 0.35, 0.35), frame * CFrame.new(0, 6.5, 0), C.Slate, Enum.Material.Wood)
		Kit.part(m, "PanelBottom", Vector3.new(pw, 0.35, 0.35), frame * CFrame.new(0, 0.6, 0), C.Slate, Enum.Material.Wood)
		Kit.part(m, "PanelMid", Vector3.new(pw, 0.25, 0.3), frame * CFrame.new(0, 3.6, 0), C.Amber, Enum.Material.Wood)
		local bars = math.floor(pw / 1.1)
		for i = 0, bars do
			Kit.deco(Kit.part(m, "Bar", Vector3.new(0.16, 5.9, 0.16), frame * CFrame.new(-pw / 2 + i * pw / bars, 3.55, 0), C.Slate, Enum.Material.Wood))
		end
		Kit.deco(Kit.part(m, "Wheel", Vector3.new(0.3, 0.6, 0.6), frame * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, 0), C.Charcoal, Enum.Material.Wood, Enum.PartType.Cylinder))
	end
	Kit.deco(Kit.part(m, "Track", Vector3.new(width + 3, 0.1, 0.5), cf * CFrame.new(0, 0.07, 0.6), C.Slate, Enum.Material.Wood))
	return m
end

-- Workshop shelter / equipment nook: slate frame, wood roof, light back wall, amber fascia.
-- `cf` is the front-centre on the floor, -Z faces the arena.
function Kit.shelterParts(parent: Instance, cf: CFrame, w: number, d: number): Model
	local m = Kit.model(parent, "CT_Rocks_EquipmentShelter")
	local h = 8.5
	-- lodge language: stone slab, timber posts and beam, plaster walls, slate-brown roof, dark timber fascia
	Kit.part(m, "Slab", Vector3.new(w + 1, 0.3, d + 1), cf * CFrame.new(0, 0.15, d / 2), L.Stone, Enum.Material.Slate)
	for _, sx in { -1, 1 } do
		for _, sz in { 0.4, d - 0.4 } do
			Kit.part(m, "Post", Vector3.new(0.6, h + (sz / d) * 1.5, 0.6), cf * CFrame.new(sx * (w / 2 - 0.4), (h + (sz / d) * 1.5) / 2, sz), L.Timber, Enum.Material.Wood)
		end
	end
	Kit.part(m, "BackWall", Vector3.new(w, h, 0.5), cf * CFrame.new(0, h / 2 + 0.3, d - 0.3), L.Plaster, Enum.Material.SmoothPlastic)
	Kit.part(m, "SideWall", Vector3.new(0.5, h * 0.6, d - 1), cf * CFrame.new(-w / 2 + 0.4, h * 0.3 + 0.3, d / 2), L.Plaster, Enum.Material.SmoothPlastic)
	-- roof slopes down toward the arena
	Kit.part(m, "Roof", Vector3.new(w + 1.6, 0.45, d + 2), cf * CFrame.new(0, h + 0.75, d / 2 - 0.4) * CFrame.Angles(math.rad(-8), 0, 0), L.Roof, Enum.Material.Slate)
	Kit.deco(Kit.part(m, "Fascia", Vector3.new(w + 1.7, 0.7, 0.25), cf * CFrame.new(0, h + 0.15, -1.3) * CFrame.Angles(math.rad(-8), 0, 0), L.TimberDark, Enum.Material.Wood))
	Kit.deco(Kit.part(m, "Beam", Vector3.new(w, 0.5, 0.5), cf * CFrame.new(0, h - 0.1, 0.4), L.Timber, Enum.Material.Wood))
	local lightBar = Kit.deco(Kit.part(m, "LightBar", Vector3.new(w * 0.5, 0.15, 0.4), cf * CFrame.new(0, h - 0.45, d / 2), Color3.fromRGB(255, 232, 190), Enum.Material.Neon))
	local l = Instance.new("PointLight")
	l.Range = 12
	l.Brightness = 0.8
	l.Color = Color3.fromRGB(255, 220, 170)
	l.Parent = lightBar
	return m
end

-- Utility props ------------------------------------------------------------------------------

-- Air compressor on skids: horizontal tank, motor box, pressure gauge, hose reel.
function Kit.compressorParts(parent: Instance, cf: CFrame): Model
	local m = Kit.model(parent, "CT_Rocks_Compressor")
	Kit.part(m, "Skid", Vector3.new(4.8, 0.4, 2.4), cf * CFrame.new(0, 0.2, 0), C.Charcoal, Enum.Material.Metal)
	Kit.part(m, "Tank", Vector3.new(4.4, 1.9, 1.9), cf * CFrame.new(0, 1.4, 0), C.Amber, Enum.Material.Metal, Enum.PartType.Cylinder)
	Kit.part(m, "Motor", Vector3.new(1.8, 1.3, 1.5), cf * CFrame.new(-0.8, 3.0, 0), C.Slate, Enum.Material.Metal)
	Kit.deco(Kit.part(m, "Pulley", Vector3.new(0.3, 1.0, 1.0), cf * CFrame.new(0.4, 3.0, 0) * CFrame.Angles(0, 0, 0), C.Charcoal, Enum.Material.Metal, Enum.PartType.Cylinder))
	Kit.deco(Kit.part(m, "Gauge", Vector3.new(0.15, 0.6, 0.6), cf * CFrame.new(1.4, 2.6, -0.5) * CFrame.Angles(0, math.rad(90), 0), C.OffWhite, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder))
	Kit.deco(Kit.part(m, "HoseReel", Vector3.new(0.6, 1.3, 1.3), cf * CFrame.new(2.6, 0.9, 0), C.Charcoal, Enum.Material.Rubber, Enum.PartType.Cylinder))
	return m
end

-- Generator housing: louvred box, amber stripe, exhaust stack, control panel.
function Kit.generatorParts(parent: Instance, cf: CFrame): Model
	local m = Kit.model(parent, "CT_Rocks_Generator")
	Kit.part(m, "Skid", Vector3.new(5.6, 0.4, 3), cf * CFrame.new(0, 0.2, 0), C.Charcoal, Enum.Material.Metal)
	Kit.part(m, "Housing", Vector3.new(5.2, 3.2, 2.7), cf * CFrame.new(0, 2.0, 0), C.Slate, Enum.Material.Metal)
	Kit.deco(Kit.part(m, "Stripe", Vector3.new(5.25, 0.35, 2.75), cf * CFrame.new(0, 3.2, 0), C.Amber, Enum.Material.Metal))
	for i = 0, 4 do
		Kit.deco(Kit.part(m, "Louvre", Vector3.new(0.12, 1.4, 0.15), cf * CFrame.new(0.6 + i * 0.35, 1.9, -1.38), C.Charcoal, Enum.Material.Metal))
	end
	Kit.deco(Kit.part(m, "Panel", Vector3.new(1.2, 1.0, 0.12), cf * CFrame.new(-1.4, 2.2, -1.38), C.Charcoal, Enum.Material.SmoothPlastic))
	Kit.deco(Kit.part(m, "Ready", Vector3.new(0.25, 0.25, 0.1), cf * CFrame.new(-1.1, 2.4, -1.45), C.Mint, Enum.Material.Neon))
	Kit.part(m, "Exhaust", Vector3.new(1.6, 0.45, 0.45), cf * CFrame.new(1.8, 4.3, 0.6) * CFrame.Angles(0, 0, math.rad(90)), C.Charcoal, Enum.Material.Metal, Enum.PartType.Cylinder)
	return m
end

-- Cable run along the floor through world points (low, never collidable).
function Kit.cable(parent: Instance, points: { Vector3 }, color: Color3?)
	local m = Kit.model(parent, "CT_Rocks_Cable")
	for i = 1, #points - 1 do
		Kit.deco(Kit.pipe(m, "Cable", points[i] + Vector3.new(0, 0.12, 0), points[i + 1] + Vector3.new(0, 0.12, 0), 0.24, color or C.Charcoal, Enum.Material.Rubber))
	end
	return m
end

-- Crates in three sizes (1 small, 2 medium, 3 large).
local CRATE = { 1.8, 2.6, 3.6 }
function Kit.crateParts(parent: Instance, cf: CFrame, size: number): Model
	local s = CRATE[math.clamp(size, 1, 3)]
	local m = Kit.model(parent, "CT_Rocks_Crate" .. size)
	Kit.part(m, "Box", Vector3.new(s, s * 0.8, s), cf * CFrame.new(0, s * 0.4, 0), C.Wood, Enum.Material.WoodPlanks)
	for _, y in { 0.12, s * 0.68 } do
		Kit.deco(Kit.part(m, "Rim", Vector3.new(s + 0.08, 0.18, s + 0.08), cf * CFrame.new(0, y, 0), C.Wood:Lerp(C.Charcoal, 0.35), Enum.Material.Wood))
	end
	Kit.deco(Kit.part(m, "Strap", Vector3.new(0.2, s * 0.82, s + 0.1), cf * CFrame.new(0, s * 0.4, 0), C.Slate, Enum.Material.Metal))
	return m
end

function Kit.palletParts(parent: Instance, cf: CFrame): Model
	local m = Kit.model(parent, "CT_Rocks_Pallet")
	for _, x in { -1.6, 0, 1.6 } do
		Kit.part(m, "Runner", Vector3.new(0.5, 0.45, 3.8), cf * CFrame.new(x, 0.225, 0), C.Wood:Lerp(C.Charcoal, 0.2), Enum.Material.Wood)
	end
	for i = 0, 4 do
		Kit.part(m, "Slat", Vector3.new(3.8, 0.15, 0.6), cf * CFrame.new(0, 0.52, -1.6 + i * 0.8), C.Wood, Enum.Material.WoodPlanks)
	end
	return m
end

-- Rock bin: open steel skip with fork pockets, holding a few dull spill stones (decor only).
function Kit.rockBinParts(parent: Instance, cf: CFrame, rng: Random): Model
	local m = Kit.model(parent, "CT_Rocks_RockBin")
	Kit.part(m, "Floor", Vector3.new(4.4, 0.3, 3.4), cf * CFrame.new(0, 0.55, 0), C.Slate, Enum.Material.Metal)
	for _, s in { -1, 1 } do
		Kit.part(m, "SideX", Vector3.new(0.3, 2.4, 3.4), cf * CFrame.new(s * 2.2, 1.6, 0) * CFrame.Angles(0, 0, math.rad(8 * s)), C.Slate, Enum.Material.Metal)
		Kit.part(m, "SideZ", Vector3.new(4.6, 2.4, 0.3), cf * CFrame.new(0, 1.6, s * 1.7) * CFrame.Angles(math.rad(-8 * s), 0, 0), C.Slate, Enum.Material.Metal)
		Kit.deco(Kit.part(m, "Pocket", Vector3.new(0.9, 0.4, 3.6), cf * CFrame.new(s * 1.2, 0.2, 0), C.Charcoal, Enum.Material.Metal))
	end
	Kit.deco(Kit.part(m, "Rim", Vector3.new(4.9, 0.2, 0.35), cf * CFrame.new(0, 2.85, -1.85), C.Amber, Enum.Material.Metal))
	for _ = 1, 5 do
		local s = rng:NextNumber(0.7, 1.2)
		Kit.deco(Kit.part(m, "Spill", Vector3.new(s, s * 0.7, s * 0.8), cf * CFrame.new(rng:NextNumber(-1.4, 1.4), 1.6 + rng:NextNumber(0, 0.5), rng:NextNumber(-0.9, 0.9)) * CFrame.Angles(rng:NextNumber(-0.5, 0.5), rng:NextNumber(0, 6), 0), C.Stone[2]:Lerp(C.Dust, 0.3), Enum.Material.Slate))
	end
	return m
end

-- Hand cart: tray, two wheels, push handle.
function Kit.cartParts(parent: Instance, cf: CFrame): Model
	local m = Kit.model(parent, "CT_Rocks_Cart")
	Kit.part(m, "Tray", Vector3.new(2.6, 0.9, 3.6), cf * CFrame.new(0, 1.5, 0), C.Amber, Enum.Material.Metal)
	Kit.deco(Kit.part(m, "Inner", Vector3.new(2.2, 0.1, 3.2), cf * CFrame.new(0, 1.96, 0), C.Charcoal, Enum.Material.Metal))
	for _, s in { -1, 1 } do
		Kit.part(m, "Wheel", Vector3.new(0.35, 1.3, 1.3), cf * CFrame.new(s * 1.5, 0.65, -0.6), C.Rubber, Enum.Material.Rubber, Enum.PartType.Cylinder)
		Kit.deco(Kit.part(m, "Handle", Vector3.new(0.2, 0.2, 2.2), cf * CFrame.new(s * 1.1, 2.1, 2.6) * CFrame.Angles(math.rad(20), 0, 0), C.Slate, Enum.Material.Metal))
		Kit.deco(Kit.part(m, "Leg", Vector3.new(0.2, 1.1, 0.2), cf * CFrame.new(s * 1.0, 0.55, 1.4), C.Slate, Enum.Material.Metal))
	end
	Kit.deco(Kit.part(m, "Grip", Vector3.new(2.4, 0.25, 0.25), cf * CFrame.new(0, 2.5, 3.6), C.Rubber, Enum.Material.Rubber))
	return m
end

-- Spare tool rack against a wall: frame, pegboard, hanging hammers and pry bars.
function Kit.toolRack(parent: Instance, cf: CFrame): Model
	local m = Kit.model(parent, "CT_Rocks_ToolRack")
	Kit.part(m, "Board", Vector3.new(5, 3.6, 0.25), cf * CFrame.new(0, 3.4, 0), C.Wood, Enum.Material.WoodPlanks)
	for _, s in { -1, 1 } do
		Kit.part(m, "Leg", Vector3.new(0.3, 5.4, 0.3), cf * CFrame.new(s * 2.4, 2.7, 0.1), C.Slate, Enum.Material.Metal)
	end
	for i = 0, 3 do
		local x = -1.8 + i * 1.2
		Kit.deco(Kit.part(m, "Handle", Vector3.new(0.22, 2.4, 0.22), cf * CFrame.new(x, 3.0, -0.3), if i % 2 == 0 then C.Amber else C.Wood, Enum.Material.SmoothPlastic))
		if i % 2 == 0 then
			Kit.deco(Kit.part(m, "Head", Vector3.new(1.0, 0.5, 0.5), cf * CFrame.new(x, 4.3, -0.3), C.Steel, Enum.Material.Metal))
		end
	end
	return m
end

-- Warning placard on a short post (sparingly: one at the drop, one at the hopper).
function Kit.placard(parent: Instance, cf: CFrame, text: string): Model
	local m = Kit.model(parent, "CT_Rocks_Placard")
	Kit.part(m, "Post", Vector3.new(0.25, 3.2, 0.25), cf * CFrame.new(0, 1.6, 0.05), C.Slate, Enum.Material.Metal)
	local board = Kit.deco(Kit.part(m, "Board", Vector3.new(2.4, 1.6, 0.12), cf * CFrame.new(0, 3.0, 0), C.Amber, Enum.Material.SmoothPlastic))
	Kit.deco(Kit.part(m, "Border", Vector3.new(2.6, 1.8, 0.08), cf * CFrame.new(0, 3.0, 0.08), C.Charcoal, Enum.Material.SmoothPlastic))
	Kit.label(board, Enum.NormalId.Front, text, C.Charcoal, nil, "Placard")
	return m
end

function Kit.cone(parent: Instance, pos: Vector3): Model
	local m = Kit.model(parent, "CT_Rocks_Cone")
	Kit.deco(Kit.part(m, "Base", Vector3.new(1.1, 0.15, 1.1), CFrame.new(pos + Vector3.new(0, 0.075, 0)), C.Charcoal, Enum.Material.Rubber))
	Kit.deco(Kit.part(m, "Body", Vector3.new(1.2, 0.7, 0.7), CFrame.new(pos + Vector3.new(0, 0.7, 0)) * CFrame.Angles(0, 0, math.rad(90)), C.Amber, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder))
	Kit.deco(Kit.part(m, "Band", Vector3.new(0.25, 0.72, 0.72), CFrame.new(pos + Vector3.new(0, 0.85, 0)) * CFrame.Angles(0, 0, math.rad(90)), C.OffWhite, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder))
	return m
end

-- Shared sell hopper: support frame, funnel lip, chute into a rock bin, receipt light, yellow
-- edge paint on the floor. Keeps the contract the client and EconomyService use: Model attribute
-- Hopper, a "Body" part carrying the ProximityPrompt "SellPrompt" with attribute Sell.
-- `cf` is the floor centre, -Z faces the arena (the side players walk up to).
function Kit.hopperParts(parent: Instance, cf: CFrame, rng: Random): Model
	local m = Kit.model(parent, "CT_Rocks_SellHopper")
	local body = Kit.part(m, "Body", Vector3.new(6, 2.6, 4.6), cf * CFrame.new(0, 3.1, 0.6), C.Slate, Enum.Material.Metal)
	-- legs and braces
	for _, sx in { -2.7, 2.7 } do
		for _, sz in { -1.4, 2.6 } do
			Kit.part(m, "Leg", Vector3.new(0.5, 1.8, 0.5), cf * CFrame.new(sx, 0.9, sz), C.Charcoal, Enum.Material.Metal)
		end
		Kit.deco(Kit.bar(m, "Brace", cf:PointToWorldSpace(Vector3.new(sx, 0.3, -1.4)), cf:PointToWorldSpace(Vector3.new(sx, 1.8, 2.6)), 0.22, C.Charcoal))
	end
	-- funnel lip: four plates flaring outward above the body
	local lipY = 5.0
	for _, s in { -1, 1 } do
		Kit.part(m, "LipX", Vector3.new(0.35, 1.8, 5.4), cf * CFrame.new(s * 3.3, lipY, 0.6) * CFrame.Angles(0, 0, math.rad(-22 * s)), C.Amber, Enum.Material.Metal)
		Kit.part(m, "LipZ", Vector3.new(6.8, 1.8, 0.35), cf * CFrame.new(0, lipY, 0.6 + s * 2.65) * CFrame.Angles(math.rad(22 * s), 0, 0), C.Amber, Enum.Material.Metal)
	end
	Kit.deco(Kit.part(m, "Mouth", Vector3.new(5.6, 0.2, 4.2), cf * CFrame.new(0, 4.45, 0.6), C.Charcoal, Enum.Material.Metal))
	for i = -2, 2 do
		Kit.deco(Kit.part(m, "Grate", Vector3.new(0.16, 0.16, 4.2), cf * CFrame.new(i * 1.1, 4.6, 0.6), C.Steel, Enum.Material.Metal))
	end
	-- chute out the back into a bin
	Kit.deco(Kit.part(m, "Chute", Vector3.new(2.4, 0.3, 4), cf * CFrame.new(0, 2.0, 4.4) * CFrame.Angles(math.rad(28), 0, 0), C.Slate, Enum.Material.Metal))
	for _, s in { -1, 1 } do
		Kit.deco(Kit.part(m, "ChuteSide", Vector3.new(0.2, 0.8, 4), cf * CFrame.new(s * 1.2, 2.3, 4.4) * CFrame.Angles(math.rad(28), 0, 0), C.Slate, Enum.Material.Metal))
	end
	Kit.rockBin(m, cf * CFrame.new(0, 0, 7.6), rng)
	-- receipt light on a post at the front corner (mint = sale accepted)
	Kit.part(m, "LightPost", Vector3.new(0.3, 5.4, 0.3), cf * CFrame.new(3.6, 2.7, -1.6), C.Slate, Enum.Material.Metal)
	local lamp = Kit.deco(Kit.part(m, "ReceiptLight", Vector3.new(0.7, 0.7, 0.7), cf * CFrame.new(3.6, 5.7, -1.6), C.Mint, Enum.Material.Neon, Enum.PartType.Ball))
	lamp.Name = "ReceiptLight"
	-- sign on the front of the body
	local sign = Kit.deco(Kit.part(m, "Sign", Vector3.new(4.4, 1.3, 0.15), cf * CFrame.new(0, 3.1, -1.75), C.Charcoal, Enum.Material.SmoothPlastic))
	Kit.label(sign, Enum.NormalId.Front, "SELL CANDY", C.Amber, nil, "Landmark")
	-- yellow edge paint: a U around the approach side only
	Kit.deco(Kit.part(m, "EdgePaint", Vector3.new(8.4, 0.06, 0.35), cf * CFrame.new(0, 0.03, -2.6), C.Amber, Enum.Material.SmoothPlastic))
	for _, s in { -1, 1 } do
		Kit.deco(Kit.part(m, "EdgePaint", Vector3.new(0.35, 0.06, 5.6), cf * CFrame.new(s * 4.2, 0.03, 0.1), C.Amber, Enum.Material.SmoothPlastic))
	end
	local pp = Instance.new("ProximityPrompt")
	pp.Name = "SellPrompt"
	pp.ActionText = "Sell Candy"
	pp.ObjectText = "Hopper"
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 12
	pp.RequiresLineOfSight = false
	pp.KeyboardKeyCode = Enum.KeyCode.R -- E is the crack key on keyboards
	pp.UIOffset = Vector2.new(0, 30)
	pp:SetAttribute("Panel", "")
	pp:SetAttribute("Sell", true)
	pp.Parent = body
	m:SetAttribute("Hopper", true)
	m.PrimaryPart = body
	return m
end

-- Background ----------------------------------------------------------------------------------

-- Tower crane silhouette on a concrete footing: braced mast, cab, jib, counter-jib with weight,
-- trolley and hook. `cf` is the footing centre; the jib points along -X.
function Kit.craneParts(parent: Instance, cf: CFrame, height: number): Model
	local m = Kit.model(parent, "CT_Rocks_Crane")
	local orange = Config.Palette.Orange
	Kit.part(m, "Footing", Vector3.new(7, 1.5, 7), cf * CFrame.new(0, 0.75, 0), C.PadConcrete, Enum.Material.Concrete)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Kit.deco(Kit.part(m, "Chord", Vector3.new(0.5, height, 0.5), cf * CFrame.new(sx * 1.4, height / 2 + 1.5, sz * 1.4), orange, Enum.Material.Metal))
		end
	end
	local seg = 5
	for i = 0, math.floor(height / seg) - 1 do
		local y0, y1 = 1.5 + i * seg, 1.5 + (i + 1) * seg
		local s = if i % 2 == 0 then 1 else -1
		for _, side in { -1.4, 1.4 } do
			Kit.deco(Kit.bar(m, "Lace", cf:PointToWorldSpace(Vector3.new(-1.4 * s, y0, side)), cf:PointToWorldSpace(Vector3.new(1.4 * s, y1, side)), 0.22, orange))
			Kit.deco(Kit.bar(m, "Lace", cf:PointToWorldSpace(Vector3.new(side, y0, -1.4 * s)), cf:PointToWorldSpace(Vector3.new(side, y1, 1.4 * s)), 0.22, orange))
		end
	end
	local top = height + 1.5
	Kit.deco(Kit.part(m, "Slew", Vector3.new(3.6, 1.0, 3.6), cf * CFrame.new(0, top + 0.5, 0), C.Slate, Enum.Material.Metal))
	Kit.deco(Kit.part(m, "Cab", Vector3.new(2.4, 2.2, 2.4), cf * CFrame.new(-1.6, top + 2, -2.2), C.OffWhite, Enum.Material.Metal))
	Kit.deco(Kit.part(m, "Jib", Vector3.new(34, 1.2, 1.4), cf * CFrame.new(-17, top + 2.2, 0), orange, Enum.Material.Metal))
	Kit.deco(Kit.part(m, "JibTop", Vector3.new(30, 0.4, 0.4), cf * CFrame.new(-15, top + 4.2, 0), orange, Enum.Material.Metal))
	Kit.deco(Kit.part(m, "CounterJib", Vector3.new(12, 1.0, 1.4), cf * CFrame.new(6, top + 2.2, 0), orange, Enum.Material.Metal))
	Kit.deco(Kit.part(m, "Counterweight", Vector3.new(3, 3, 2.2), cf * CFrame.new(10.5, top + 0.8, 0), C.PadConcrete, Enum.Material.Concrete))
	Kit.deco(Kit.part(m, "Apex", Vector3.new(1, 6, 1), cf * CFrame.new(0, top + 4, 0), orange, Enum.Material.Metal))
	Kit.deco(Kit.bar(m, "Tie", cf:PointToWorldSpace(Vector3.new(0, top + 7, 0)), cf:PointToWorldSpace(Vector3.new(-26, top + 2.8, 0)), 0.18, C.Charcoal))
	Kit.deco(Kit.bar(m, "Tie", cf:PointToWorldSpace(Vector3.new(0, top + 7, 0)), cf:PointToWorldSpace(Vector3.new(11, top + 2.8, 0)), 0.18, C.Charcoal))
	Kit.deco(Kit.part(m, "Trolley", Vector3.new(1.6, 0.8, 1.8), cf * CFrame.new(-22, top + 1.2, 0), C.Slate, Enum.Material.Metal))
	Kit.deco(Kit.part(m, "Rope", Vector3.new(0.12, 14, 0.12), cf * CFrame.new(-22, top - 6, 0), C.Charcoal, Enum.Material.Metal))
	Kit.deco(Kit.part(m, "Hook", Vector3.new(1.0, 1.2, 0.6), cf * CFrame.new(-22, top - 13.4, 0), C.Amber, Enum.Material.Metal))
	return m
end

-- Inclined conveyor on A-frame trestles, discharging onto a stockpile cone. `a` is the low
-- (feed) end and `b` the high (discharge) end, both world points on the belt line.
function Kit.conveyor(parent: Instance, a: Vector3, b: Vector3, groundY: number, rng: Random): Model
	local m = Kit.model(parent, "CT_Rocks_Conveyor")
	local len = (b - a).Magnitude
	local cf = CFrame.lookAt((a + b) / 2, b)
	Kit.deco(Kit.part(m, "Belt", Vector3.new(2.4, 0.3, len), cf, C.Charcoal, Enum.Material.Rubber))
	for _, s in { -1, 1 } do
		Kit.deco(Kit.part(m, "Stringer", Vector3.new(0.3, 0.8, len), cf * CFrame.new(s * 1.35, -0.2, 0), C.Slate, Enum.Material.Metal))
	end
	Kit.deco(Kit.part(m, "Head", Vector3.new(3.2, 1.6, 1.6), CFrame.new(b) * (cf - cf.Position), C.Amber, Enum.Material.Metal))
	local n = math.max(2, math.floor(len / 10))
	for i = 1, n do
		local p = a:Lerp(b, i / (n + 0.4))
		local right = cf.RightVector
		for _, s in { -1, 1 } do
			Kit.deco(Kit.bar(m, "Trestle", p + right * s * 1.3, Vector3.new(p.X, groundY, p.Z) + right * s * 2.6, 0.35, C.Slate))
		end
		Kit.deco(Kit.bar(m, "Cross", p + right * -1.6 + Vector3.new(0, -(p.Y - groundY) * 0.5, 0), p + right * 1.6 + Vector3.new(0, -(p.Y - groundY) * 0.5, 0), 0.25, C.Slate))
	end
	-- stockpile under the discharge end
	local pile = Vector3.new(b.X, groundY, b.Z) + cf.LookVector * 3
	for i = 1, 4 do
		local s = 9 - i * 1.6
		Kit.deco(Kit.part(m, "Stockpile", Vector3.new(s * 1.2, s * 0.5, s), CFrame.new(pile + Vector3.new(0, s * 0.25 + (i - 1) * 0.9, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), C.Stone[3]:Lerp(C.Dust, 0.3), Enum.Material.Slate))
	end
	return m
end

-- Blender kit versions (docs/MODELING.md) -------------------------------------------------------
-- Same signatures and frames as the Part builders above (-Z faces the arena, floor-centre origin);
-- each uses the uploaded kit model when it is loaded and the Part builder otherwise. Kit meshes do not
-- collide, so structures the players could touch get invisible blockers.

-- Pass 2 (docs/m4/QUARRY.md): fewer, chunkier stepped cliff blocks in neutral grey, like the owner's quarry
-- placement target. One cliff = three terraced tiers climbing away from the arena (each a broad block with a
-- lighter cap slab and a lower shoulder block in front). `cf` = base-front-centre, -Z out, w width, h height.
function Kit.cliff(parent: Instance, cf: CFrame, variant: number, w: number, h: number, rng: Random): Model
	local m = Kit.model(parent, "CT_Rocks_Cliff_" .. (((variant - 1) % 8) + 1))
	local base = -12 -- below the lower bench so no gap shows from any side
	local depth = 6.5
	for tier = 0, 2 do
		local tw = w * rng:NextNumber(0.82, 1.0) * (1 - 0.07 * tier)
		local th = h * (0.38 + 0.31 * tier) * rng:NextNumber(0.92, 1.08)
		local z = tier * 6.0
		local x = rng:NextNumber(-0.08, 0.08) * w
		local col = stone(rng)
		local tcf = cf * CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(rng:NextNumber(-4, 4)), 0)
		Kit.part(m, "Mass", Vector3.new(tw, th - base, depth), tcf * CFrame.new(0, (th + base) / 2, depth / 2), col, Enum.Material.Slate)
		Kit.deco(Kit.part(m, "Cap", Vector3.new(tw * 0.97, 0.6, depth * 0.96), tcf * CFrame.new(0, th + 0.3, depth / 2), col:Lerp(C.Dust, 0.22), Enum.Material.Slate))
		-- a lower shoulder block in front of the tier (the step), narrower and offset to one side
		local sw = tw * rng:NextNumber(0.34, 0.5)
		local sh = th * rng:NextNumber(0.5, 0.72)
		local sx = (if rng:NextNumber() < 0.5 then -1 else 1) * (tw / 2 - sw / 2 - rng:NextNumber(0, tw * 0.2))
		local scol = stone(rng)
		Kit.part(m, "Step", Vector3.new(sw, sh - base, 4.2), tcf * CFrame.new(sx, (sh + base) / 2, -2.1), scol, Enum.Material.Slate)
		Kit.deco(Kit.part(m, "StepCap", Vector3.new(sw * 0.97, 0.5, 4.0), tcf * CFrame.new(sx, sh + 0.25, -2.1), scol:Lerp(C.Dust, 0.22), Enum.Material.Slate))
	end
	return m
end

function Kit.ledge(parent: Instance, cf: CFrame, w: number, h: number, d: number, rng: Random): Model
	if noKit("Cliff_E") then
		local m = noPlace(parent, "Cliff_E", cf * CFrame.new(0, -0.2, d * 0.5), math.clamp(w / 24.5 * 1.4, 0.3, 0.9), "CT_Rocks_Ledge")
		if m then
			return m
		end
	end
	return Kit.ledgeParts(parent, cf, w, h, d, rng)
end

function Kit.retainingWall(parent: Instance, cf: CFrame, length: number, height: number, bottom: number?): Model
	if noKit("RetainingWall_Low") then
		local b = bottom or 0
		local s = math.max(1, height / 3.26)
		local pitch = 8.0 * s
		local n = math.max(1, math.ceil(length / pitch))
		local m = Kit.model(parent, "CT_Rocks_RetainingWall")
		for i = 0, n - 1 do
			local x = -length / 2 + (i + 0.5) * length / n
			noPlace(m, "RetainingWall_Low", cf * CFrame.new(x, b, 0.85 * s), s * (length / n / pitch) * 1.02, "Segment")
		end
		-- solid face so the level behind it holds
		KitPlace.blocker(m, cf * CFrame.new(0, b + height / 2, 0.8), Vector3.new(length, height, 1.6), "Face")
		return m
	end
	return Kit.retainingWallParts(parent, cf, length, height, bottom)
end

function Kit.railing(parent: Instance, a: Vector3, b: Vector3): Model
	if noKit("Fence_Section") then
		local m = Kit.model(parent, "CT_Rocks_Railing")
		local len = (b - a).Magnitude
		local dir = (b - a).Unit
		local out = Vector3.new(-dir.Z, 0, dir.X) -- the fence front faces sideways to the run
		local n = math.max(1, math.ceil(len / 6.4))
		for i = 0, n - 1 do
			local p = a + dir * ((i + 0.5) * len / n)
			noPlace(m, "Fence_Section", CFrame.lookAt(p, p + out), len / n / 6.4 * 1.02, "Section")
		end
		KitPlace.blocker(m, CFrame.lookAt((a + b) / 2 + Vector3.new(0, 1.7, 0), (a + b) / 2 + Vector3.new(0, 1.7, 0) + out), Vector3.new(len, 3.4, 0.8), "Rail")
		return m
	end
	return Kit.railingParts(parent, a, b)
end

function Kit.gate(parent: Instance, cf: CFrame, width: number): Model
	if noKit("Quarry_Gate") then
		local m = Kit.model(parent, "CT_Rocks_EntranceGate")
		noPlace(m, "Quarry_Gate", cf, width * 1.25 / 17.2, "Gate")
		return m
	end
	return Kit.gateParts(parent, cf, width)
end

function Kit.shelter(parent: Instance, cf: CFrame, w: number, d: number): Model
	if noKit("Storage_Nook") then
		local s = w / 13.5 * 1.1
		local m = noPlace(parent, "Storage_Nook", cf * CFrame.new(0, 0, 4.2 * s), s, "CT_Rocks_EquipmentShelter")
		Kit.lodgeSkin(m)
		if m then
			KitPlace.blocker(m, cf * CFrame.new(0, 3, 8.2 * s), Vector3.new(13.4 * s, 6, 0.8), "BackWall")
			local lamp = m.PrimaryPart
			if lamp then
				local l = Instance.new("PointLight")
				l.Range = 16
				l.Brightness = 0.9
				l.Color = Color3.fromRGB(255, 214, 160)
				l.Parent = lamp
			end
			return m
		end
	end
	return Kit.shelterParts(parent, cf, w, d)
end

function Kit.compressor(parent: Instance, cf: CFrame): Model
	local m = noPlace(parent, "Prop_Compressor", cf, 1.4, "CT_Rocks_Compressor")
	KitPlace.solidify(m)
	return m or Kit.compressorParts(parent, cf)
end

function Kit.generator(parent: Instance, cf: CFrame): Model
	local m = noPlace(parent, "Prop_Generator", cf, 1.4, "CT_Rocks_Generator")
	KitPlace.solidify(m)
	return m or Kit.generatorParts(parent, cf)
end

local CRATE_KIT = { "Prop_CrateSmall", "Prop_CrateMedium", "Prop_CrateLarge" }
local CRATE_SCALE = { 1.05, 1.1, 1.15 }
function Kit.crate(parent: Instance, cf: CFrame, size: number): Model
	local i = math.clamp(size, 1, 3)
	local m = noPlace(parent, CRATE_KIT[i], cf, CRATE_SCALE[i], "CT_Rocks_Crate" .. size)
	KitPlace.solidify(m)
	return m or Kit.crateParts(parent, cf, size)
end

function Kit.pallet(parent: Instance, cf: CFrame): Model
	return noPlace(parent, "Prop_Pallet", cf, 1.0, "CT_Rocks_Pallet") or Kit.palletParts(parent, cf)
end

function Kit.rockBin(parent: Instance, cf: CFrame, rng: Random): Model
	local m = noPlace(parent, "Prop_StoneBin", cf, 1.35, "CT_Rocks_RockBin")
	KitPlace.solidify(m)
	return m or Kit.rockBinParts(parent, cf, rng)
end

function Kit.cart(parent: Instance, cf: CFrame): Model
	local m = noPlace(parent, "Prop_Handcart", cf, 1.2, "CT_Rocks_Cart")
	KitPlace.solidify(m)
	return m or Kit.cartParts(parent, cf)
end

-- Sell hopper (pass 2): a wooden bin on a timber skid with steel straps, a heap of rubble on top, wooden steps
-- and a SELL RUBBLE board on two posts (owner's quarry target). Contract kept: Model "CT_Rocks_SellHopper"
-- with attribute Hopper, a solid "Body" part carrying the ProximityPrompt "SellPrompt" (attribute Sell) and a
-- "ReceiptLight" lamp. `cf` = floor centre, -Z faces the pile (the side players walk up to).
local SHELL_TINTS = { Color3.fromRGB(255, 240, 220), Color3.fromRGB(255, 214, 224), Color3.fromRGB(206, 232, 255), Color3.fromRGB(220, 246, 214), Color3.fromRGB(255, 244, 178) }
local function shellTint(rng: Random): Color3
	return SHELL_TINTS[rng:NextInteger(1, #SHELL_TINTS)]
end

local function woodHopperParts(parent: Instance, cf: CFrame, rng: Random): Model
	-- lodge kit language: timber bin, dark timber skid and seams, iron straps and rim, a framed sign-wood board
	local m = Kit.model(parent, "CT_Rocks_SellHopper")
	Kit.deco(Kit.part(m, "Skid", Vector3.new(7.4, 0.5, 5.6), cf * CFrame.new(0, 0.25, 0.2), L.TimberDark, Enum.Material.WoodPlanks))
	local body = Kit.part(m, "Body", Vector3.new(6.2, 2.9, 4.4), cf * CFrame.new(0, 1.95, 0.2), L.Timber, Enum.Material.WoodPlanks)
	-- plank seams and iron straps on the three visible faces
	for i = -2, 2 do
		Kit.deco(Kit.part(m, "Seam", Vector3.new(0.06, 2.6, 0.06), cf * CFrame.new(i * 1.2, 1.95, -2.02), L.TimberDark, Enum.Material.Wood))
	end
	for _, x in { -2.9, 0, 2.9 } do
		Kit.deco(Kit.part(m, "Strap", Vector3.new(0.3, 3.0, 0.12), cf * CFrame.new(x, 1.95, -2.04), L.Iron, Enum.Material.Wood))
	end
	for _, sx in { -1, 1 } do
		Kit.deco(Kit.part(m, "Strap", Vector3.new(0.12, 3.0, 0.3), cf * CFrame.new(sx * 3.14, 1.95, 0.2), L.Iron, Enum.Material.Wood))
	end
	-- top rim (iron) and the rubble heap showing above it
	Kit.deco(Kit.part(m, "RimF", Vector3.new(6.4, 0.2, 0.3), cf * CFrame.new(0, 3.5, -1.95), L.Iron, Enum.Material.Wood))
	Kit.deco(Kit.part(m, "RimB", Vector3.new(6.4, 0.2, 0.3), cf * CFrame.new(0, 3.5, 2.35), L.Iron, Enum.Material.Wood))
	for _, sx in { -1, 1 } do
		Kit.deco(Kit.part(m, "RimS", Vector3.new(0.3, 0.2, 4.4), cf * CFrame.new(sx * 3.05, 3.5, 0.2), L.Iron, Enum.Material.Wood))
	end
	Kit.deco(Kit.part(m, "Fill", Vector3.new(5.7, 0.3, 3.9), cf * CFrame.new(0, 3.45, 0.2), Color3.fromRGB(255, 244, 214), Enum.Material.Fabric))
	for i = 1, 11 do
		local sz = rng:NextNumber(0.7, 1.3)
		local x, z = rng:NextNumber(-2.3, 2.3), rng:NextNumber(-1.4, 1.8)
		local lift = (1 - (math.abs(x) / 2.8 + math.abs(z - 0.2) / 2.2) * 0.45) * 0.55
		Kit.deco(Kit.part(m, "Shell", Vector3.new(sz, sz * 0.7, sz * 0.9), cf * CFrame.new(x, 3.6 + math.max(lift, 0.1), 0.2 + z) * CFrame.Angles(rng:NextNumber(-0.5, 0.5), rng:NextNumber(0, 6.28), rng:NextNumber(-0.5, 0.5)), shellTint(rng), Enum.Material.SmoothPlastic))
	end
	-- timber steps up the left side
	for k = 1, 3 do
		Kit.part(m, "Step", Vector3.new(1.6, 0.55 * k, 1.2), cf * CFrame.new(-4.6, 0.275 * k, 0.2 + (k - 2) * 1.0), L.TimberDark:Lerp(L.Timber, 0.4), Enum.Material.WoodPlanks)
	end
	-- framed SELL RUBBLE board on two timber posts above the front edge. The board's face is 0.6 in front of the
	-- posts, the posts stop below its top rail and nothing else stands in front of it (text never covered).
	for _, sx in { -2.75, 2.75 } do
		Kit.part(m, "SignPost", Vector3.new(0.45, 5.6, 0.45), cf * CFrame.new(sx, 2.8, -2.25), L.Timber, Enum.Material.Wood)
	end
	KitPlace.signBoard(m, "Sign", cf * CFrame.new(0, 5.25, -2.6) * CFrame.Angles(0, math.pi, 0), 4.8, 1.4, "SELL CANDY", "Landmark", {
		Face = L.SignWood,
		Frame = L.TimberDark,
		Ink = L.Cream,
		Trim = L.Gold,
		Depth = 0.35,
	})
	local lamp = Kit.deco(Kit.part(m, "ReceiptLight", Vector3.new(0.6, 0.6, 0.6), cf * CFrame.new(3.25, 5.0, -2.25), C.Mint, Enum.Material.Neon, Enum.PartType.Ball))
	lamp.Name = "ReceiptLight"
	local pp = Instance.new("ProximityPrompt")
	pp.Name = "SellPrompt"
	pp.ActionText = "Sell Candy"
	pp.ObjectText = "Candy Stand"
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 12
	pp.RequiresLineOfSight = false
	pp.KeyboardKeyCode = Enum.KeyCode.R -- E is the crack key on keyboards
	pp.UIOffset = Vector2.new(0, 30)
	pp:SetAttribute("Panel", "")
	pp:SetAttribute("Sell", true)
	pp.Parent = body
	-- the owner's Meshy stand (ServerStorage.MeshyAssets.MeshySellStand) replaces the timber bin look; Body stays as the
	-- invisible collider that carries the prompt, and the sign and receipt light stay
	local stand = KitPlace.meshy("MeshySellStand", cf * CFrame.new(0, 2.6, 0.4) * CFrame.Angles(0, math.pi, 0), Vector3.new(8, 5.2, 6))
	if stand then
		for _, d in m:GetChildren() do
			if d:IsA("BasePart") and (d.Name == "Skid" or d.Name == "Seam" or d.Name == "Strap" or d.Name:sub(1, 3) == "Rim" or d.Name == "Fill" or d.Name == "Shell" or d.Name == "Step") then
				d:Destroy()
			end
		end
		body.Transparency = 1
		stand.Name = "StandMesh"
		stand.Parent = m
	end
	m:SetAttribute("Hopper", true) -- contract: EconomyService, PileView, Hud and Main.client look for "Hopper"
	m.PrimaryPart = body
	return m
end

function Kit.hopper(parent: Instance, cf: CFrame, rng: Random): Model
	return woodHopperParts(parent, cf, rng)
end

-- Small wooden gantry crane (pass 2): two timber A-frames, a top beam, a small work platform with a rail and a
-- hanging grab. About 14 wide, 13 tall; `cf` = floor centre, the beam runs along X. Replaces the huge steel
-- tower crane. The grab is the Crane_Bucket kit mesh when loaded, else a few dark Parts.
function Kit.crane(parent: Instance, cf: CFrame, height: number): Model
	local m = Kit.model(parent, "CT_Rocks_Crane")
	local h = height
	local half = 6.2
	local timber = L.Timber
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Kit.bar(m, "Leg", cf:PointToWorldSpace(Vector3.new(sx * (half + 1.2), 0, sz * 2.4)), cf:PointToWorldSpace(Vector3.new(sx * half, h, sz * 0.5)), 0.9, timber, Enum.Material.Wood)
		end
		Kit.deco(Kit.part(m, "Footing", Vector3.new(2.6, 0.5, 6.4), cf * CFrame.new(sx * (half + 1.2), 0.25, 0), L.Stone, Enum.Material.Slate))
		Kit.deco(Kit.bar(m, "Brace", cf:PointToWorldSpace(Vector3.new(sx * (half + 0.8), h * 0.25, 1.6)), cf:PointToWorldSpace(Vector3.new(sx * (half + 0.8), h * 0.25, -1.6)), 0.45, timber, Enum.Material.Wood))
		Kit.deco(Kit.part(m, "Plate", Vector3.new(1.4, 1.4, 0.3), cf * CFrame.new(sx * half, h - 0.6, -0.75), L.Iron, Enum.Material.Metal))
	end
	Kit.part(m, "Beam", Vector3.new(half * 2 + 3.4, 1.1, 1.3), cf * CFrame.new(0, h + 0.2, 0), timber, Enum.Material.Wood)
	Kit.deco(Kit.part(m, "BeamStrap", Vector3.new(0.35, 1.3, 1.5), cf * CFrame.new(-half, h + 0.2, 0), L.Iron, Enum.Material.Metal))
	Kit.deco(Kit.part(m, "BeamStrap", Vector3.new(0.35, 1.3, 1.5), cf * CFrame.new(half, h + 0.2, 0), L.Iron, Enum.Material.Metal))
	-- work platform on the left frame, railing toward the arena
	local deckY = h * 0.45
	Kit.part(m, "Deck", Vector3.new(4.2, 0.4, 5.4), cf * CFrame.new(-half - 0.2, deckY, 0), L.TimberLight, Enum.Material.WoodPlanks)
	for _, z in { -2.5, 2.5 } do
		Kit.deco(Kit.part(m, "RailPost", Vector3.new(0.3, 2.4, 0.3), cf * CFrame.new(-half - 0.2, deckY + 1.2, z), timber, Enum.Material.Wood))
	end
	Kit.deco(Kit.part(m, "Rail", Vector3.new(0.25, 0.25, 5.4), cf * CFrame.new(-half + 1.8, deckY + 2.2, 0), timber, Enum.Material.Wood))
	Kit.deco(Kit.part(m, "Rail", Vector3.new(4.2, 0.25, 0.25), cf * CFrame.new(-half - 0.2, deckY + 2.2, -2.6), timber, Enum.Material.Wood))
	-- hanging grab (cable, hook block, two claws) near the middle of the beam
	local hookX = 1.2
	local dropY = h * 0.52
	Kit.deco(Kit.part(m, "Cable", Vector3.new(0.14, h - dropY, 0.14), cf * CFrame.new(hookX, (h + dropY) / 2, 0), L.Iron, Enum.Material.Metal))
	local bucketAt = cf:PointToWorldSpace(Vector3.new(hookX, dropY, 0))
	local placed = false
	if noKit("Crane_Bucket") then
		local bucket = noPlace(m, "Crane_Bucket", CFrame.new(bucketAt) * (cf - cf.Position), 0.8, "Bucket")
		Kit.lodgeSkin(bucket)
		placed = bucket ~= nil
	end
	if not placed then
		Kit.deco(Kit.part(m, "Grab", Vector3.new(1.4, 0.8, 1.4), cf * CFrame.new(hookX, dropY, 0), C.Charcoal, Enum.Material.Metal))
		for _, sx in { -1, 1 } do
			Kit.deco(Kit.part(m, "Claw", Vector3.new(0.3, 2.0, 1.2), cf * CFrame.new(hookX + sx * 0.8, dropY - 1.2, 0) * CFrame.Angles(0, 0, math.rad(-sx * 18)), C.Slate, Enum.Material.Metal))
		end
	end
	return m
end

-- Quarry perimeter pass (Master Prompt 5 section 8) -----------------------------------------------

-- Flat floor treatment (gravel band, worn path, dust): visual only, no shadow, ignored by the camera.
function Kit.floorPatch(parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3, mat: Enum.Material?): Part
	local p = Kit.deco(Kit.part(parent, name, size, cf, color, mat or Enum.Material.Ground))
	p.CastShadow = false
	p:SetAttribute("CameraIgnore", true)
	return p
end

-- Terraced strata cliffs (blender/models/quarry_strata.py). Kit width and the depth of the front foot in
-- front of the model origin, per kind; the model is scaled to `w` and placed so its front foot lies on `cf`.
local STRATA = {
	Low = { w = 28, foot = 4.0, h = 9 },
	Mid = { w = 30, foot = 6.0, h = 14.5 },
	High = { w = 30, foot = 6.0, h = 19 },
	Shoulder = { w = 24, foot = 4.5, h = 12 },
	-- layered bedded walls (Cliff_Strata_A..C): origin on the front foot line
	LayerA = { w = 30, foot = 1.0, h = 14, mesh = "Cliff_Strata_A" },
	LayerB = { w = 28, foot = 1.0, h = 11, mesh = "Cliff_Strata_B" },
	LayerC = { w = 32, foot = 1.0, h = 15, mesh = "Cliff_Strata_C" },
}
Kit.StrataKinds = { "Low", "Mid", "Shoulder", "Mid", "High" }

-- `cf` = base-front-centre of the cliff (-Z faces the arena), `w` the width it should fill. Falls back to the
-- Part stepped cliff when the mesh is not loaded.
function Kit.strata(parent: Instance, cf: CFrame, kind: string, w: number, rng: Random): Model
	local spec = STRATA[kind] or STRATA.Mid
	if noKit(spec.mesh or "Strata_" .. kind) then
		local s = w / spec.w
		local m = noPlace(parent, spec.mesh or "Strata_" .. kind, cf * CFrame.new(0, 0, spec.foot * s), s, "CT_Rocks_Strata_" .. kind)
		if m then
			return m
		end
	end
	if spec.mesh and noKit("Strata_Mid") then
		return Kit.strata(parent, cf, "Mid", w, rng)
	end
	return Kit.cliff(parent, cf, rng:NextInteger(1, 8), w, spec.h * w / spec.w, rng)
end

-- Ground-to-cliff transition cluster (gravel mound + scenery stones). `cf` = floor centre, -Z to the arena.
function Kit.rubbleSkirt(parent: Instance, cf: CFrame, scale: number, rng: Random): Model
	local m = noPlace(parent, "Rubble_Skirt", cf, scale, "CT_Rocks_RubbleSkirt")
	if m then
		return m
	end
	local f = Kit.boulders(parent, cf, 1.6 * scale, rng, 3)
	Kit.grit(f, cf.Position, 3 * scale, rng, 4)
	return f
end

-- Narrow-gauge cart track from a to b on the floor: 8-stud segments, a buffer stop at b, an ore cart parked
-- on the first segment. Decorative and walk-over (no collision).
function Kit.cartTrack(parent: Instance, a: Vector3, b: Vector3): Model
	local m = Kit.model(parent, "CT_Rocks_CartTrack")
	local d = b - a
	local u = d.Unit
	local look = Vector3.new(-u.Z, 0, u.X) -- kit X runs along the track (kit -X = +u, the buffer end)
	local function at(dist: number): CFrame
		local p = a + u * dist
		return CFrame.lookAt(p, p + look)
	end
	local segs = math.max(1, math.floor((d.Magnitude - 3) / 8))
	local kit = noKit("Cart_Track", "Track_Buffer", "Mine_Cart")
	if kit then
		for i = 0, segs - 1 do
			noPlace(m, "Cart_Track", at(4 + i * 8), 1, "Track")
		end
		noPlace(m, "Track_Buffer", at(segs * 8 + 1.5), 1, "Buffer")
		noPlace(m, "Mine_Cart", at(4.2), 1, "Cart")
	else
		local len = segs * 8 + 3
		local mid = at(len / 2)
		Kit.deco(Kit.part(m, "Ballast", Vector3.new(len, 0.24, 3), mid * CFrame.new(0, 0.12, 0), C.Bench, Enum.Material.Pebble))
		for k = 0, math.floor(len / 0.95) - 1 do
			Kit.deco(Kit.part(m, "Sleeper", Vector3.new(0.5, 0.2, 2.4), at(0.5 + k * 0.95) * CFrame.new(0, 0.32, 0), Color3.fromRGB(122, 86, 52), Enum.Material.Wood))
		end
		for _, sz in { -0.75, 0.75 } do
			Kit.deco(Kit.part(m, "Rail", Vector3.new(len, 0.24, 0.16), mid * CFrame.new(0, 0.54, sz), C.Steel, Enum.Material.Metal))
		end
		Kit.deco(Kit.part(m, "Buffer", Vector3.new(0.9, 1.2, 2.6), at(len - 0.45) * CFrame.new(0, 0.84, 0), Color3.fromRGB(122, 86, 52), Enum.Material.Wood))
		Kit.cartParts(m, at(4.2))
	end
	return m
end

-- Lean-to tool shelter (tool wall, workbench, lantern). `cf` = floor centre, -Z = open front. The kit mesh
-- does not collide: an invisible blocker stands in for the back wall.
function Kit.toolShelter(parent: Instance, cf: CFrame): Model
	local m = noPlace(parent, "Quarry_ToolShelter", cf, 1, "CT_Rocks_ToolShelter")
	Kit.lodgeSkin(m)
	if m then
		KitPlace.blocker(m, cf * CFrame.new(0, 2.4, 2.2), Vector3.new(9, 4.8, 0.6), "BackWall")
		local root = m:FindFirstChild("Root")
		local a = root and root:FindFirstChild("Light")
		if a then
			local l = Instance.new("PointLight")
			l.Range = 12
			l.Brightness = 0.6
			l.Color = Color3.fromRGB(255, 214, 160)
			l.Parent = a
		end
		return m
	end
	return Kit.shelterParts(parent, cf * CFrame.new(0, 0, -2.5), 9, 5)
end

-- Small prop from the utility kit at `cf` (nil when absent); used by ArenaBuilder for placed set dressing.
-- Floor props get simple collision (kit meshes never collide); wall-mounted ones (Wall_Lamp) do not.
function Kit.kitProp(parent: Instance, name: string, cf: CFrame, scale: number?): Model?
	local m = KitPlace.place(parent, name, cf, scale or 1.0)
	if m and name ~= "Wall_Lamp" then
		KitPlace.solidify(m)
	end
	return m
end

-- Meadow scenery (replaces the quarry cliffs): soft green hills, hedges, round trees, bushes, flowers, hay bales.
-- All low-poly balls and blocks. REPLACE: real mesh (hill / tree / flower) when uploaded.
local FLOWER_COLORS = {
	Color3.fromRGB(255, 142, 170), Color3.fromRGB(255, 226, 96), Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(176, 150, 255), Color3.fromRGB(255, 170, 96), Color3.fromRGB(130, 200, 255),
}
local function ball(parent: Instance, name: string, pos: Vector3, dia: number, color: Color3, mat: Enum.Material?, squash: number?): Part
	return Kit.part(parent, name, Vector3.new(dia, dia * (squash or 1), dia), CFrame.new(pos), color, mat or Enum.Material.Grass, Enum.PartType.Ball)
end

-- `cf` = base-front-centre (-Z faces the arena), `w` the width, `h` roughly the height of the highest dome.
function Kit.hill(parent: Instance, cf: CFrame, w: number, h: number, rng: Random): Model
	local name = if rng:NextNumber() < 0.5 then "Hill_A" else "Hill_B"
	if meadow(name) then
		-- one soft rolling Blender hill stretched to w x h, a little deeper than wide is tall
		local nat: Vector3 = MeadowKit.size(name)
		local flip = if rng:NextNumber() < 0.5 then math.pi else 0
		local scale = Vector3.new(w * 1.05 / nat.X, h / nat.Y, w * 0.62 / nat.Z)
		return MeadowKit.place(parent, name, "CT_Rocks_Hill", cf * CFrame.new(0, 0, 4) * CFrame.Angles(0, flip, 0), scale)
	end
	local m = Kit.model(parent, "CT_Rocks_Hill")
	local n = 3
	for i = 1, n do
		local t = (i - 0.5) / n - 0.5
		local dia = w * rng:NextNumber(0.5, 0.7)
		local hh = h * rng:NextNumber(0.7, 1.0)
		local col = C.Stone[rng:NextInteger(1, 3)]
		-- dome: ball squashed to its height, centre sunk so only the top shows above the floor
		local pos = cf:PointToWorldSpace(Vector3.new(t * w * 0.9, hh * 0.35 - dia * 0.2, rng:NextNumber(2, 6)))
		local b = ball(m, "Dome", pos, dia, col, Enum.Material.Grass, hh / dia * 1.3)
		b.CanCollide = false
	end
	return m
end

function Kit.hedge(parent: Instance, a: Vector3, b: Vector3, height: number, rng: Random): Model
	local len = (b - a).Magnitude
	local n = math.max(1, math.floor(len / 3.2))
	if meadow("Hedge_A") and len > 0.1 then
		local m = Kit.model(parent, "CT_Rocks_Hedge")
		local nat: Vector3 = MeadowKit.size("Hedge_A")
		local dir = (b - a).Unit
		for i = 0, n - 1 do
			local p = a:Lerp(b, (i + 0.5) / n)
			local cf = CFrame.lookAt(p, p + Vector3.new(-dir.Z, 0, dir.X)) * CFrame.Angles(0, rng:NextNumber(-0.08, 0.08), 0)
			local s = rng:NextNumber(0.95, 1.15)
			local piece = MeadowKit.place(m, "Hedge_A", "Bush", cf,
				Vector3.new(len / n * 1.15 / nat.X, height * s / nat.Y, 3.0 * s / nat.Z))
			if piece then
				for _, d in piece:GetChildren() do
					d.Name = "Bush"
					d.Parent = m
				end
				piece:Destroy()
			end
		end
		return m
	end
	local m = Kit.model(parent, "CT_Rocks_Hedge")
	for i = 0, n - 1 do
		local p = a:Lerp(b, (i + 0.5) / n)
		local col = C.Stone[2]:Lerp(Color3.fromRGB(64, 150, 70), rng:NextNumber(0.2, 0.7))
		ball(m, "Bush", p + Vector3.new(0, height * 0.4, 0), 3.6 * rng:NextNumber(0.9, 1.15), col, Enum.Material.Grass, height / 3.2)
	end
	return m
end

function Kit.tree(parent: Instance, pos: Vector3, scale: number, rng: Random): Model
	local name = if rng:NextNumber() < 0.55 then "Tree_A" else "Tree_B"
	if meadow(name) then
		-- about as tall as the old ball tree (13 studs at scale 1); the trunk collides
		local nat: Vector3 = MeadowKit.size(name)
		local cf = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
		return MeadowKit.place(parent, name, "CT_Rocks_Tree", cf, 13.5 * scale / nat.Y, { Trunk = true })
	end
	local m = Kit.model(parent, "CT_Rocks_Tree")
	local trunkH = 5 * scale
	Kit.part(m, "Trunk", Vector3.new(trunkH, 1.4 * scale, 1.4 * scale), CFrame.new(pos + Vector3.new(0, trunkH / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), L.TimberDark:Lerp(L.Timber, 0.3), Enum.Material.Wood, Enum.PartType.Cylinder)
	local leaf = Color3.fromRGB(74, 170, 78):Lerp(Color3.fromRGB(120, 200, 80), rng:NextNumber(0, 0.6))
	ball(m, "Crown", pos + Vector3.new(0, trunkH + 3.2 * scale, 0), 8 * scale, leaf, Enum.Material.Grass)
	ball(m, "CrownTop", pos + Vector3.new(0.6 * scale, trunkH + 6.2 * scale, 0.4 * scale), 5 * scale, leaf:Lerp(Color3.new(1, 1, 1), 0.12), Enum.Material.Grass)
	return m
end

function Kit.bushCluster(parent: Instance, pos: Vector3, scale: number, rng: Random): Model
	local name = if rng:NextNumber() < 0.5 then "Bush_A" else "Bush_B"
	if meadow(name) then
		local nat: Vector3 = MeadowKit.size(name)
		local cf = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
		local m = MeadowKit.place(parent, name, "CT_Rocks_Bushes", cf, 3.4 * scale / nat.Y)
		-- a fern or a boulder tucked in front now and then
		local extra = if rng:NextNumber() < 0.5 then "Fern_A" else "Boulder_A"
		if m and meadow(extra) and rng:NextNumber() < 0.6 then
			local o = cf * CFrame.new(rng:NextNumber(-1.5, 1.5) * scale, 0, -2.2 * scale)
			local piece = MeadowKit.place(m, extra, extra, o * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), scale * 0.7)
			if piece and extra == "Boulder_A" then
				for _, d in piece:GetDescendants() do
					if d:IsA("BasePart") then
						d.CanCollide = true
					end
				end
			end
		end
		return m
	end
	local m = Kit.model(parent, "CT_Rocks_Bushes")
	for i = 1, 3 do
		local o = Vector3.new(rng:NextNumber(-1.6, 1.6) * scale, 0, rng:NextNumber(-1.2, 1.2) * scale)
		local d = rng:NextNumber(2.4, 3.6) * scale
		ball(m, "Bush", pos + o + Vector3.new(0, d * 0.3, 0), d, C.Stone[rng:NextInteger(1, 3)]:Lerp(Color3.fromRGB(60, 150, 70), 0.3), Enum.Material.Grass, 0.8)
	end
	return m
end

function Kit.flower(parent: Instance, pos: Vector3, rng: Random)
	local name = "Flowers_" .. rng:NextInteger(0, 3)
	if meadow(name) then
		-- a little clump of daisies with leaves (visual only)
		local cf = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
		MeadowKit.place(parent, name, "Flowers", cf, rng:NextNumber(0.75, 1.1))
		return
	end
	local col = FLOWER_COLORS[rng:NextInteger(1, #FLOWER_COLORS)]
	local s = rng:NextNumber(0.8, 1.3)
	Kit.deco(Kit.part(parent, "Stem", Vector3.new(0.9 * s, 0.14, 0.14), CFrame.new(pos + Vector3.new(0, 0.45 * s, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(70, 150, 70), Enum.Material.Grass, Enum.PartType.Cylinder)).CanCollide = false
	local head = ball(parent, "Bloom", pos + Vector3.new(0, 0.95 * s, 0), 0.55 * s, col, Enum.Material.SmoothPlastic)
	head.CanCollide = false
	Kit.deco(head)
	local mid = ball(parent, "Heart", pos + Vector3.new(0, 1.0 * s, 0), 0.25 * s, Color3.fromRGB(255, 204, 70), Enum.Material.SmoothPlastic)
	Kit.deco(mid)
	mid.CanCollide = false
end

function Kit.hayBale(parent: Instance, cf: CFrame): Model
	local m = Kit.model(parent, "CT_Rocks_HayBale")
	local mesh = KitPlace.meshy("MeshyHayBale", cf * CFrame.new(0, 1.2, 0), Vector3.new(2.8, 2.4, 2.8))
	if mesh then
		mesh.Name = "Bale"
		mesh.Parent = m
		return m
	end
	Kit.part(m, "Bale", Vector3.new(2.6, 2.2, 2.2), cf * CFrame.new(0, 1.1, 0), Color3.fromRGB(240, 208, 112), Enum.Material.Fabric, Enum.PartType.Cylinder)
	Kit.deco(Kit.part(m, "Band", Vector3.new(0.3, 2.3, 2.3), cf * CFrame.new(-0.6, 1.1, 0), Color3.fromRGB(190, 120, 90), Enum.Material.Fabric, Enum.PartType.Cylinder))
	Kit.deco(Kit.part(m, "Band", Vector3.new(0.3, 2.3, 2.3), cf * CFrame.new(0.6, 1.1, 0), Color3.fromRGB(190, 120, 90), Enum.Material.Fabric, Enum.PartType.Cylinder))
	return m
end

return Kit
