--!strict
-- Per-zone arena look (audit: every zone used the one Meadow arena). The arena is built once per slot as the meadow
-- (ArenaBuilder) and re-skinned per round for the hunt's tier (ArenaBuilder.applyZone, called by MatchService
-- when a round starts): ground colours and materials, a tint on the boundary hills and trees, and one procedural
-- landmark set per zone (no asset ids). Pure data plus the placement spots, so tests/test_zone_themes.luau can check it.
--
-- Keys are tier ids (Config.TierOrder, code names): Gravel = Meadow, Quarry = Forest, Cavern = Snow,
-- Volcanic = Volcano, Meteor = Space. Material values are Enum.Material item names (strings, so this module loads
-- outside Roblox); ArenaBuilder turns them into Enum.Material.

local ZoneThemes = {}

-- Arena layout facts the scenery must respect (ArenaBuilder reads these, so there is one source of truth).
-- Arena-local studs, mound centre is the origin, -Z is north.
ZoneThemes.Layout = {
	Apothem = 43, -- inner face of the invisible containment octagon (play area ~86 studs across)
	BenchY = -9, -- top of the lower bench beyond the east drop
	DropX = 44, -- the main floor ends here (east); beyond it the ground is the bench
	RingOut = 7, -- landmark ring: this many studs outside the octagon side (behind the fence and the bounds wall)
	-- the north road beyond the gate: nothing may stand in it
	RoadHalfWidth = 9,
}

-- Directions (deg; x = cos, z = sin) of the landmark ring spots. They avoid the open east drop (|deg| < 25),
-- the north gate and road (255..285) and the kit trees/bushes ArenaBuilder already places outside the fence.
ZoneThemes.RingAngles = { 45, 82, 107, 145, 182, 205, 228, 296, 320 }

-- The hero landmark stands on the lower bench, seen across the east drop from every table (bearing about -17 deg,
-- inside the open east side), clear of the bench hay bales, bushes and trees.
ZoneThemes.HeroSpot = Vector3.new(92, -9, -28)
-- Space only: the planet and its moon hang in the sky east of the arena (well inside the 260-stud slot spacing).
ZoneThemes.PlanetSpot = Vector3.new(140, 62, -40)
ZoneThemes.MoonSpot = Vector3.new(108, 78, 26)

export type Theme = {
	Id: string, -- tier id
	Zone: string, -- player-facing zone name
	Floor: Color3, -- main play floor
	FloorMaterial: string,
	Bench: Color3, -- lower ground beyond the east drop
	BenchMaterial: string,
	Band: Color3, -- perimeter band tone (mixed half and half with Floor)
	BandMaterial: string,
	Path: Color3, -- worn routes and the north road
	PathMaterial: string,
	Hill: Color3, -- boundary hill domes are tinted toward this ...
	HillMix: number, -- ... by this much (0 = the meadow greens)
	HillMaterial: string,
	Leaf: Color3, -- tree crowns, bushes and hedges
	LeafMix: number,
	LeafMaterial: string,
	Trunk: Color3,
	TrunkMix: number,
	Rock: Color3, -- landmark rocks / crystals / trunk of the hero
	RockMaterial: string,
	Accent: Color3, -- landmark accent (flower hearts, leaves, ice glints, lava, crystal glow)
	Light: Color3?, -- arena-local PointLight colour on the hero landmark (nil: none)
	Landmark: string, -- "Flowers" | "BigTree" | "IceRocks" | "LavaRocks" | "Crystals"
	KeepMeadowFlowers: boolean, -- keep the flower beds just inside the fence
	-- Low-poly set (HuntLowPoly): Color tints on the owner's meshes, so the shared Meadow pieces read as this zone.
	Stone: Color3, -- hex stepping stones (Hunt_Pads) and the StonePad under each nest
	Wood: Color3, -- wood deck, stalls and fence (Hunt_Ledge, Hunt_Stalls, Hunt_Fence); white = mesh as built
	Boulder: Color3?, -- grey boulders and flat stone slabs (Rock, Kit_Rock_A); nil = the Meadow tints
	GroundTint: Color3?, -- tint on the low-poly ground mesh (nil = as built)
	LeafTint: Color3?, -- tint on the tree and bush props (nil = as built)
	ExtraTrees: boolean, -- Forest: extra, taller trees in clusters at the edges
	HideWater: boolean, -- Space: no sea (Hunt_Water) behind the arena
	Craters: boolean, -- Space: craters and crystal clusters on the ground outside the play area
}

-- Every material name a theme may use (all real Enum.Material items; the test checks themes stay inside this list).
ZoneThemes.Materials = {
	Grass = true, LeafyGrass = true, Ground = true, Sand = true, Snow = true, Glacier = true, Ice = true,
	Basalt = true, CrackedLava = true, Rock = true, Slate = true, Pebble = true, Neon = true, Glass = true,
	SmoothPlastic = true, Wood = true, Mud = true, Asphalt = true,
}

local rgb = Color3.fromRGB

ZoneThemes.Themes = {
	-- Meadow: exactly the colours the arena is built with (ArenaKit C.Floor / C.Bench / C.FloorDark, hill greens).
	Gravel = {
		Id = "Gravel", Zone = "Meadow",
		Floor = rgb(112, 190, 84), FloorMaterial = "Grass",
		Bench = rgb(128, 200, 96), BenchMaterial = "Grass",
		Band = rgb(150, 214, 104), BandMaterial = "Grass",
		Path = rgb(214, 180, 118), PathMaterial = "SmoothPlastic",
		Hill = rgb(104, 180, 84), HillMix = 0, HillMaterial = "Grass",
		Leaf = rgb(74, 170, 78), LeafMix = 0, LeafMaterial = "Grass",
		Trunk = rgb(150, 96, 64), TrunkMix = 0,
		Rock = rgb(70, 150, 70), RockMaterial = "Grass",
		Accent = rgb(255, 204, 70),
		Light = nil,
		Landmark = "Flowers",
		KeepMeadowFlowers = true,
		Stone = rgb(255, 205, 140), Wood = rgb(255, 255, 255), Boulder = nil,
		GroundTint = nil, LeafTint = nil,
		ExtraTrees = false, HideWater = false, Craters = false,
	},
	Quarry = {
		Id = "Quarry", Zone = "Forest",
		Floor = rgb(62, 124, 56), FloorMaterial = "LeafyGrass",
		Bench = rgb(56, 114, 52), BenchMaterial = "LeafyGrass",
		Band = rgb(120, 98, 70), BandMaterial = "Ground",
		Path = rgb(150, 112, 78), PathMaterial = "SmoothPlastic",
		Hill = rgb(36, 96, 48), HillMix = 0.75, HillMaterial = "LeafyGrass",
		Leaf = rgb(26, 86, 40), LeafMix = 0.75, LeafMaterial = "Grass",
		Trunk = rgb(104, 70, 48), TrunkMix = 0.5,
		Rock = rgb(112, 76, 52), RockMaterial = "Wood",
		Accent = rgb(40, 104, 50),
		Light = nil,
		Landmark = "BigTree",
		KeepMeadowFlowers = false,
		Stone = rgb(98, 120, 86), Wood = rgb(150, 112, 86), Boulder = rgb(86, 108, 76),
		GroundTint = nil, LeafTint = rgb(140, 180, 130),
		ExtraTrees = true, HideWater = false, Craters = false,
	},
	Cavern = {
		Id = "Cavern", Zone = "Snow",
		Floor = rgb(236, 244, 252), FloorMaterial = "Snow",
		Bench = rgb(226, 238, 250), BenchMaterial = "Snow",
		Band = rgb(196, 220, 240), BandMaterial = "Snow",
		Path = rgb(198, 210, 226), PathMaterial = "SmoothPlastic",
		Hill = rgb(244, 250, 255), HillMix = 0.85, HillMaterial = "Snow",
		Leaf = rgb(232, 244, 250), LeafMix = 0.6, LeafMaterial = "Snow",
		Trunk = rgb(110, 92, 84), TrunkMix = 0.4,
		Rock = rgb(150, 210, 240), RockMaterial = "Glacier",
		Accent = rgb(214, 244, 255),
		Light = rgb(170, 220, 255),
		Landmark = "IceRocks",
		KeepMeadowFlowers = false,
		Stone = rgb(150, 182, 214), Wood = rgb(222, 236, 255), Boulder = rgb(160, 188, 216),
		GroundTint = nil, LeafTint = nil,
		ExtraTrees = false, HideWater = false, Craters = false,
	},
	Volcanic = {
		Id = "Volcanic", Zone = "Volcano",
		Floor = rgb(92, 76, 72), FloorMaterial = "Basalt",
		Bench = rgb(70, 58, 56), BenchMaterial = "CrackedLava",
		Band = rgb(60, 50, 50), BandMaterial = "Basalt",
		Path = rgb(126, 96, 80), PathMaterial = "SmoothPlastic",
		Hill = rgb(66, 54, 54), HillMix = 0.85, HillMaterial = "Basalt",
		Leaf = rgb(84, 64, 56), LeafMix = 0.75, LeafMaterial = "Ground",
		Trunk = rgb(48, 38, 36), TrunkMix = 0.7,
		Rock = rgb(52, 44, 44), RockMaterial = "Basalt",
		Accent = rgb(255, 110, 30),
		Light = rgb(255, 120, 50),
		Landmark = "LavaRocks",
		KeepMeadowFlowers = false,
		Stone = rgb(92, 78, 78), Wood = rgb(226, 158, 108), Boulder = rgb(76, 64, 64),
		GroundTint = nil, LeafTint = nil,
		ExtraTrees = false, HideWater = true, Craters = false,
	},
	Meteor = {
		Id = "Meteor", Zone = "Space",
		Floor = rgb(150, 142, 172), FloorMaterial = "Slate",
		Bench = rgb(122, 114, 150), BenchMaterial = "Slate",
		Band = rgb(104, 96, 136), BandMaterial = "Pebble",
		Path = rgb(182, 176, 200), PathMaterial = "SmoothPlastic",
		Hill = rgb(112, 102, 150), HillMix = 0.8, HillMaterial = "Rock",
		Leaf = rgb(160, 110, 230), LeafMix = 0.7, LeafMaterial = "SmoothPlastic",
		Trunk = rgb(90, 80, 120), TrunkMix = 0.6,
		Rock = rgb(150, 120, 255), RockMaterial = "Glass",
		Accent = rgb(110, 230, 255),
		Light = rgb(170, 140, 255),
		Landmark = "Crystals",
		KeepMeadowFlowers = false,
		Stone = rgb(96, 78, 150), Wood = rgb(200, 178, 240), Boulder = rgb(110, 86, 170),
		GroundTint = rgb(214, 190, 255), LeafTint = nil,
		ExtraTrees = false, HideWater = true, Craters = true,
	},
} :: { [string]: Theme }

ZoneThemes.Default = "Gravel"

-- The theme for a tier id; an unknown or missing id falls back to the Meadow look (never errors mid-round).
function ZoneThemes.get(tierId: string?): Theme
	local t = if tierId then ZoneThemes.Themes[tierId] else nil
	return t or ZoneThemes.Themes[ZoneThemes.Default]
end

-- Distance from the centre to the octagon side along `deg` (sides are normal to 0, 45, 90 ... deg).
function ZoneThemes.octRadius(deg: number, apothem: number): number
	local d = ((deg % 45) + 45) % 45
	local off = math.min(d, 45 - d)
	return apothem / math.cos(math.rad(off))
end

-- Arena-local ground points of the landmark ring (y = floor height there: main floor 0, bench beyond the drop).
function ZoneThemes.ringSpots(): { Vector3 }
	local L = ZoneThemes.Layout
	local out = {}
	for _, deg in ZoneThemes.RingAngles do
		local r = ZoneThemes.octRadius(deg, L.Apothem) + L.RingOut
		local a = math.rad(deg)
		local x, z = math.cos(a) * r, math.sin(a) * r
		table.insert(out, Vector3.new(x, if x > L.DropX then L.BenchY else 0, z))
	end
	return out
end

return ZoneThemes
