--!strict
-- Per-zone hunt piece sets ("5 worlds, not 5 paint jobs", /mnt/project-files/hunt_zones_v1.md). Pure, so
-- tests/test_hunt_zone_kit.luau checks it offline; server/HuntLowPoly does the cloning.
--
-- Contract for the Studio import: one folder per zone, ServerStorage.HuntZoneKit_<Zone> (Meadow, Forest, Snow,
-- Volcano, Space). Each piece is a MeshPart or a Model, named by its role, optionally with the zone and a Blender
-- number after it ("Hero", "Hero_Volcano", "Hero_Volcano.001" all count as Hero):
--   Ground                 220 x 220 ground tile under the whole arena (replaces the tinted Hunt_Ground; walkable)
--   PathEdge               trim along ONE side of the north road (about 70 long on Z); used on both sides
--   Skyline_A/_B/_C        big skyline silhouettes (about 120 wide), six spots around the arena
--   SkylineFill_1/_2/_3    edge fillers between the skyline spots (five spots), so the gap scan stays at 0
--   Hero                   the zone's hero landmark (30-40 tall) at the end of the north road
--   PetStatue              the zone's best pet as a 12-tall statue beside the hero
--   ZoneGate               the arch over the north gate
--   Scatter_<anything>     up to 6 scatter props; they stand in for the meadow trees, bushes, boulders, mushrooms
--                          (2.5x bigger outside the fence) and form a cluster behind every nest
--   LaneMarker             optional rocket / crystal / torch lining the north path (a glowing pillar without it)
-- Every piece is optional: a missing role keeps the tinted meadow piece it would replace, and a zone with no
-- folder (or an empty one) builds exactly as before. Kit pieces are visual only (no collision) except Ground.
-- Optional attributes on a piece, for tuning in Studio without code changes:
--   Offset (Vector3, studs, in the spot's own frame), Yaw (number, degrees added), Scale (number, size factor;
--   ignored on Scatter pieces, which are fitted to the footprint of the meadow prop they replace).
-- A piece's front (-Z, Roblox LookVector) faces the arena centre; if it imports facing away, set Yaw = 180.
local ZoneThemes = require(script.Parent.ZoneThemes)

local HuntZoneKit = {}

HuntZoneKit.FolderPrefix = "HuntZoneKit_"
HuntZoneKit.Zones = { "Meadow", "Forest", "Snow", "Volcano", "Space" }
-- zone of each hunt tier (Config.TierOrder ids)
HuntZoneKit.ZoneOfTier = { Gravel = "Meadow", Quarry = "Forest", Cavern = "Snow", Volcanic = "Volcano", Meteor = "Space" } :: { [string]: string }

HuntZoneKit.SkylineR = 140 -- skyline ring radius (plan: 60-160)
HuntZoneKit.FillR = 100
HuntZoneKit.HeroZ = -132 -- past the end of the north road (the road strip runs z -45..-115)
HuntZoneKit.StatueAt = Vector2.new(24, -118)
HuntZoneKit.MaxR = 160
HuntZoneKit.SkylineWidth = 120 -- assumed skyline / filler widths when a piece cannot be measured
HuntZoneKit.FillWidth = 60
HuntZoneKit.Overlap = 0.25 -- neighbouring skyline pieces overlap by this share of their width (closes the gap scan)
HuntZoneKit.FillSkipDeg = 18 -- no filler within this bearing of north: the road and the hero stay in view
HuntZoneKit.BigScatter = 2.5 -- scatter outside the fence is this much bigger than the prop it replaces
HuntZoneKit.FenceClear = 3 -- studs between any decoration footprint and the fence line (HuntPlacement.Clear)
HuntZoneKit.ClusterSize = 7 -- footprint (studs) of a nest-cluster prop before BigScatter
HuntZoneKit.LaneHalf = 5 -- the clear central path: half width, from the north gate to the mound
HuntZoneKit.MoundR = 14
HuntZoneKit.RoadEndZ = -115

-- Per-zone accents for the procedural extras (path, lane markers, focal pads and beacons, the backstop hills).
export type Style = { Path: Color3, Accent: Color3, Pad: Color3, Hill: { Color3 } }
HuntZoneKit.Style = {
	Meadow = { Path = Color3.fromRGB(214, 178, 120), Accent = Color3.fromRGB(255, 214, 64), Pad = Color3.fromRGB(255, 240, 200), Hill = { Color3.fromRGB(112, 172, 88), Color3.fromRGB(96, 154, 76) } },
	Forest = { Path = Color3.fromRGB(150, 108, 72), Accent = Color3.fromRGB(255, 226, 110), Pad = Color3.fromRGB(236, 214, 160), Hill = { Color3.fromRGB(52, 108, 50), Color3.fromRGB(70, 128, 58) } },
	Snow = { Path = Color3.fromRGB(150, 200, 236), Accent = Color3.fromRGB(110, 220, 255), Pad = Color3.fromRGB(60, 120, 200), Hill = { Color3.fromRGB(236, 242, 250), Color3.fromRGB(206, 222, 242) } },
	Volcano = { Path = Color3.fromRGB(46, 36, 36), Accent = Color3.fromRGB(255, 110, 30), Pad = Color3.fromRGB(255, 170, 60), Hill = { Color3.fromRGB(70, 54, 52), Color3.fromRGB(96, 72, 64) } },
	Space = { Path = Color3.fromRGB(80, 60, 140), Accent = Color3.fromRGB(90, 255, 230), Pad = Color3.fromRGB(255, 120, 230), Hill = { Color3.fromRGB(150, 124, 204), Color3.fromRGB(120, 96, 180) } },
} :: { [string]: Style }

export type Slot = { X: number, Z: number, Yaw: number, Variant: string? }
export type Plan = { [string]: { string } } -- role -> canonical keys present ("Skyline" -> { "Skyline_A", ... })

function HuntZoneKit.folderName(zone: string): string
	return HuntZoneKit.FolderPrefix .. zone
end

-- Canonical role and key of an instance name in zone `zone`'s kit, or nil when it is not a kit piece.
function HuntZoneKit.roleOf(name: string, zone: string): (string?, string?)
	local n = string.gsub(name, "%.%d+$", "")
	local suffix = "_" .. zone
	if #n > #suffix and string.sub(n, -#suffix) == suffix then
		n = string.sub(n, 1, #n - #suffix)
	end
	if n == "Ground" or n == "PathEdge" or n == "Hero" or n == "PetStatue" or n == "ZoneGate" or n == "LaneMarker" then
		return n, n
	end
	if string.match(n, "^Skyline_[ABC]$") then
		return "Skyline", n
	end
	if string.match(n, "^SkylineFill_[123]$") then
		return "SkylineFill", n
	end
	if string.match(n, "^Scatter_[%w_]+$") then
		return "Scatter", n
	end
	return nil, nil
end

-- Which roles a folder holding `names` provides (keys sorted, first copy of a key wins).
function HuntZoneKit.plan(names: { string }, zone: string): Plan
	local out: Plan = {}
	local seen: { [string]: boolean } = {}
	for _, name in names do
		local role, key = HuntZoneKit.roleOf(name, zone)
		if role and key and not seen[key] then
			seen[key] = true
			out[role] = out[role] or {}
			table.insert(out[role], key)
		end
	end
	for _, keys in out do
		table.sort(keys)
	end
	return out
end

-- yaw (radians) that turns a piece's front (-Z) toward the arena centre from (x, z)
local function facing(x: number, z: number): number
	return math.atan2(x, z)
end

local function ring(r: number, degs: { number }): { Slot }
	local out: { Slot } = {}
	for _, d in degs do
		-- bearing from north (-Z), clockwise toward east (+X)
		local a = math.rad(d)
		local x, z = math.sin(a) * r, -math.cos(a) * r
		table.insert(out, { X = x, Z = z, Yaw = facing(x, z) })
	end
	return out
end

-- Degrees of bearing a piece `width` wide covers seen from the centre at radius r.
function HuntZoneKit.spanDeg(width: number, r: number): number
	return math.deg(2 * math.atan((width / 2) / r))
end

-- Evenly spaced bearings that cover the whole circle (minus a window of `skip` degrees either side of north) with
-- pieces `width` wide at radius r, neighbours overlapping by Overlap: the gap scan closes by construction for any
-- piece width, instead of relying on six hand-picked spots.
function HuntZoneKit.coverRing(r: number, width: number, skip: number?): { number }
	local span = HuntZoneKit.spanDeg(math.max(width, 1), r) * (1 - HuntZoneKit.Overlap)
	local lo = skip or 0
	local arc = 360 - 2 * lo
	local n = math.clamp(math.ceil(arc / span), 3, 48)
	local out = {}
	if lo == 0 then
		for k = 0, n - 1 do
			table.insert(out, k * 360 / n)
		end
	else
		-- the first and last piece sit half a span inside the window's edges, so the arc between is covered
		local half = math.min(span / 2, arc / 2)
		local from, to = lo + half, 360 - lo - half
		local step = if n > 1 then (to - from) / (n - 1) else 0
		for k = 0, n - 1 do
			table.insert(out, from + k * step)
		end
	end
	return out
end

-- Arena-local spots (origin = pile centre on the floor, -Z north) for every copy of role `role`.
-- `variants` (sorted keys present, e.g. Skyline_A, Skyline_C) are dealt round the spots in turn; `width` is the
-- narrowest measured piece of a ring role (Skyline, SkylineFill), so the ring has no gaps.
function HuntZoneKit.slots(role: string, fenceHalf: number, variants: { string }?, width: number?): { Slot }
	local out: { Slot }
	if role == "Ground" then
		out = { { X = 0, Z = 0, Yaw = 0 } }
	elseif role == "ZoneGate" then
		out = { { X = 0, Z = -(fenceHalf + 1.5), Yaw = 0 } }
	elseif role == "PathEdge" then
		-- along the road strip's two sides, beyond the road's keep-clear half width; the east copy turned round
		local x = ZoneThemes.Layout.RoadHalfWidth + 1
		out = { { X = -x, Z = -80, Yaw = 0 }, { X = x, Z = -80, Yaw = math.pi } }
	elseif role == "Hero" then
		out = { { X = 0, Z = HuntZoneKit.HeroZ, Yaw = 0 } }
	elseif role == "PetStatue" then
		local p = HuntZoneKit.StatueAt
		out = { { X = p.X, Z = p.Y, Yaw = facing(p.X, p.Y) } }
	elseif role == "Skyline" then
		out = ring(HuntZoneKit.SkylineR, HuntZoneKit.coverRing(HuntZoneKit.SkylineR, width or HuntZoneKit.SkylineWidth))
	elseif role == "SkylineFill" then
		-- not near north: the road and the hero stay in view
		out = ring(HuntZoneKit.FillR, HuntZoneKit.coverRing(HuntZoneKit.FillR, width or HuntZoneKit.FillWidth, HuntZoneKit.FillSkipDeg))
	elseif role == "LaneMarker" then
		out = HuntZoneKit.laneMarkers(fenceHalf)
	else
		out = {}
	end
	if variants and #variants > 0 then
		for i, s in out do
			s.Variant = variants[(i - 1) % #variants + 1]
		end
	end
	return out
end

-- Lane markers: pairs along the north road from just past the gate to the road's end, plus one pair either side
-- of the gate, all facing the road.
function HuntZoneKit.laneMarkers(fenceHalf: number): { Slot }
	local out: { Slot } = {}
	local x = ZoneThemes.Layout.RoadHalfWidth + 4 -- outside the road and its PathEdge trim
	local z = -(fenceHalf + 6)
	while z >= HuntZoneKit.RoadEndZ do
		table.insert(out, { X = -x, Z = z, Yaw = -math.pi / 2 })
		table.insert(out, { X = x, Z = z, Yaw = math.pi / 2 })
		z -= 12
	end
	return out
end

-- The clear central path (arena-local box): from the hero's pad down the road, through the north gate, to the
-- mound's edge. Nothing decorative stands in it.
function HuntZoneKit.lane(fenceHalf: number): (number, number, number)
	return HuntZoneKit.LaneHalf, HuntZoneKit.HeroZ + 14, -HuntZoneKit.MoundR
end

-- True when a footprint of radius r at (x, z) reaches into the clear central path.
function HuntZoneKit.inLane(x: number, z: number, r: number, fenceHalf: number): boolean
	local half, zFar, zNear = HuntZoneKit.lane(fenceHalf)
	return math.abs(x) < half + r and z < zNear + r and z > zFar - r
end

-- Scatter clusters behind every nest: a fan of props just outside the fence on the nest's bearing (`angles` are
-- the nests' math angles, x = cos, z = sin), so each nest is framed by the zone. Skips the road and the east drop.
export type ClusterSpot = { X: number, Z: number, Yaw: number, Size: number }
function HuntZoneKit.clusterSpots(fenceHalf: number, angles: { number }): { ClusterSpot }
	local out: { ClusterSpot } = {}
	-- { bearing offset (rad), extra studs out, size factor }
	local fan = { { 0, 2, 1.3 }, { -0.16, 0, 1.0 }, { 0.16, 0, 1.0 }, { -0.3, 6, 0.9 }, { 0.3, 6, 0.9 }, { -0.08, 13, 1.15 }, { 0.08, 13, 1.15 } }
	for i, a in angles do
		-- nests on the east side swing their fan toward the north / south fence, away from the open east drop
		local swing = if math.sin(a) >= 0 then 1 else -1
		for k, f in fan do
			local size = HuntZoneKit.ClusterSize * f[3]
			local R = size * HuntZoneKit.BigScatter / 2
			for shift = 0, 8 do
				local b = a + f[1] + swing * shift * 0.1
				local dx, dz = math.cos(b), math.sin(b)
				-- far enough out on that bearing that the whole footprint clears the fence square by FenceClear
				local r = (fenceHalf + HuntZoneKit.FenceClear + R + f[2]) / math.max(math.abs(dx), math.abs(dz))
				local x, z = dx * r, dz * r
				local onRoad = z - R < -fenceHalf and math.abs(x) < ZoneThemes.Layout.RoadHalfWidth + 4 + R
				if x + R <= ZoneThemes.Layout.DropX and math.sqrt(x * x + z * z) + R < HuntZoneKit.SkylineR - 20 then
					if not onRoad then
						table.insert(out, { X = x, Z = z, Yaw = (i * 7 + k * 3) % 13 * 0.48, Size = size })
					end
					break
				end
			end
		end
	end
	return out
end

-- True when (x, z) is past the fence square (scatter there may grow BigScatter times).
function HuntZoneKit.outside(x: number, z: number, r: number, fenceHalf: number): boolean
	return math.max(math.abs(x), math.abs(z)) - r > fenceHalf
end

-- Meadow scenery props the Scatter pieces stand in for (trees, bushes, boulders, mushrooms; the barrels, crates
-- and hay bales by the sell stands and the cliffs stay as they are).
HuntZoneKit.Scatterable = {
	PineTree = true, Kit_Pine_A = true, RoundTree = true, Kit_Tree_A = true, Kit_Tree_B = true, CliffPine = true,
	FlowerBush = true, Kit_Bush_A = true, Rock = true, Kit_Rock_A = true, Mushroom = true,
} :: { [string]: boolean }

-- Which scatter key stands in for scenery row `index` (prop `prop`): deterministic, mixes the props per spot.
function HuntZoneKit.scatterFor(prop: string, index: number, keys: { string }): string?
	if not HuntZoneKit.Scatterable[prop] or #keys == 0 then
		return nil
	end
	return keys[(index - 1) % #keys + 1]
end

-- Uniform factor that fits a scatter piece of footprint `have` (max X/Z, studs) into the footprint `want` of the
-- meadow prop it replaces, so the placement checks (fence clearance, keep-outs, sell stands) still hold.
function HuntZoneKit.fitScale(have: number, want: number): number
	if have <= 0 or want <= 0 then
		return 1
	end
	return want / have
end

return HuntZoneKit
