--!strict
-- Private hunt arena: a sunny grassy MEADOW around one shared egg pile (was the quarry worksite; the layout notes
-- below keep the old names: cliffs are now hills and hedges, the hoppers are SHELL SELL stands, the crane is gone).
-- Original notes: a functional worksite around one shared
-- mound. Built from the reusable pieces in ArenaKit; WorldBuilder.buildArena delegates here.
--
-- Layout (arena-local, the mound centre is the origin, -Z is north, angles use x = cos, z = sin):
--   mound pad        irregular dirt/stone patch ~18-21 studs across at the centre
--   tables 1-4       StationModels on the Config.Station.Radius circle at 45/135/225/315 deg,
--                    each on a plain concrete pad (table + the stance in front of it)
--   machine bays 1-4 directly behind each table, on the same line (radius 32.75), so table and machine
--                    read as one station; pad top y = 0.3, MachineModels builds on it. Nothing stands
--                    between the pile and a table (the lanes are bare floor).
--   sell hoppers     two identical ones, south (90 deg) serving tables 1 and 2 and north (270 deg) serving
--                    tables 3 and 4 at radius 30: every table is the same walk (about 21 studs) from one
--                    hopper, and nothing but floor lies on that route (V6 Master 4 section 18).
--   entrance gate    north (270 deg), closed, road beyond between cliff shoulders
--   tool shelter     north edge west of the gate (lean-to, tool wall, workbench)
--   cart bay         south edge east of the hopper: track, buffer stop, ore cart, wheel marks to the hopper
--   equipment nook   west (180 deg): shelter with compressor, generator, tool rack, crates
--   drop + railing   east (0 deg): retaining wall down to a lower bench with crane and conveyor
--   containment      invisible octagon (apothem 43, playable ~86 studs across) and a lid
-- Everything outside the octagon is scenery: terraced strata cliffs (Strata_* meshes, Part stepped cliffs as the
-- fallback) in a lower front row and a taller back row, rubble skirts at their feet. Floor: warm hard-packed
-- ground, a soft dust halo round the mound patch, a perimeter gravel band, compacted routes pile -> table and
-- table -> hopper (flat, no collision, CameraIgnore). The centre stays bare.

local Workspace = game:GetService("Workspace")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local RoundRocks = require(Shared.RoundRocks)
local StationModels = require(script.Parent.StationModels)
local ZoneThemes = require(Shared.ZoneThemes)
local Kit = require(script.Parent.ArenaKit)
local ZoneScenery = require(script.Parent.ZoneScenery)
local HuntLowPoly = require(script.Parent.HuntLowPoly)

local C = Kit.C
local P = Config.Palette
local part, deco = Kit.part, Kit.deco

local ArenaBuilder = {}

local APOTHEM = ZoneThemes.Layout.Apothem -- inner face of the containment octagon (43; zone landmarks stand outside it)
local BAY_RADIUS = 32.75 -- machine bay centre: right behind the table pad (table at Config.Station.Radius)
local HOPPER_RADIUS = 30
local BENCH_Y = ZoneThemes.Layout.BenchY -- lower bench beyond the east drop (-9)
local PAD_TOP = 0.3 -- station and bay pad top (the table kit and MachineModels assume it)
-- Restrained owner accents (same order as StationModels.ACCENTS): small inset and nameplate only.
local OWNER_COLORS = StationModels.Accents

local function dirAt(deg: number): Vector3
	local a = math.rad(deg)
	return Vector3.new(math.cos(a), 0, math.sin(a))
end

-- Distance from the centre to the octagon side along `deg` (sides are normal to 0, 45, 90 ... deg).
local function octRadius(deg: number, apothem: number): number
	local d = ((deg % 45) + 45) % 45
	local off = math.min(d, 45 - d)
	return apothem / math.cos(math.rad(off))
end

-- Normal of the octagon side that `deg` falls on.
local function sideNormal(deg: number): Vector3
	return dirAt(math.floor((deg + 22.5) / 45) * 45)
end

-- Ground --------------------------------------------------------------------------------------

local function buildGround(root: Instance, c: Vector3, rng: Random)
	local g = Kit.folder(root, "CT_Rocks_Ground")
	-- main level (top y = 0) ends at the east drop (x = 44); lower bench beyond it
	part(g, "CT_Rocks_Floor", Vector3.new(124, 2, 210), CFrame.new(c + Vector3.new(-18, -1, -25)), C.Floor, Enum.Material.Grass)
	part(g, "CT_Rocks_Bench", Vector3.new(120, 2, 240), CFrame.new(c + Vector3.new(104, BENCH_Y - 1, -20)), C.Bench, Enum.Material.Grass)

	-- No mound pad under the egg pile any more: its overlapping flat sand discs (and their lobes, re-tinted grey in the
	-- colder zones) read as gold and grey plates lying under the eggs (owner video). The pile sits on the grass.

	-- perimeter gravel band along the foot of the boundary (every octagon side), a soft inner edge
	local gravel = C.Floor:Lerp(Color3.fromRGB(150, 214, 104), 0.5)
	local sideLen = 2 * APOTHEM * math.tan(math.rad(22.5))
	for k = 0, 7 do
		local n = dirAt(k * 45)
		local mid = c + n * (APOTHEM - 2.0)
		local cf = CFrame.lookAt(mid, mid + n)
		Kit.floorPatch(g, "CT_Rocks_GravelBand", cf * CFrame.new(0, 0.03, 0), Vector3.new(sideLen + 1.5, 0.06, 4.6), gravel, Enum.Material.Grass)
		for e = -1, 1 do
			local w = sideLen * rng:NextNumber(0.18, 0.28)
			Kit.floorPatch(g, "CT_Rocks_GravelEdge", cf * CFrame.new(e * sideLen * 0.3 + rng:NextNumber(-2, 2), 0.02, -2.6) * CFrame.Angles(0, rng:NextNumber(-0.06, 0.06), 0), Vector3.new(w, 0.04, 2.2), gravel:Lerp(C.Floor, 0.5), Enum.Material.Grass)
		end
	end

	-- compacted routes: mound edge -> each table's stance, and each table -> its sell hopper (south for the
	-- two tables with z > 0, north for the others). Flat, a shade darker than the floor, no collision.
	local worn = C.Floor:Lerp(C.FloorDark, 0.55)
	local function route(a: Vector3, b: Vector3, width: number)
		local mid = (a + b) / 2
		local len = (b - a).Magnitude
		local cf = CFrame.lookAt(mid, b)
		Kit.floorPatch(g, "CT_Rocks_Route", cf * CFrame.new(0, 0.018, 0), Vector3.new(width, 0.03, len), worn, Enum.Material.Ground)
		Kit.floorPatch(g, "CT_Rocks_RouteEdge", cf * CFrame.new(rng:NextNumber(-0.4, 0.4), 0.014, 0) * CFrame.Angles(0, rng:NextNumber(-0.05, 0.05), 0), Vector3.new(width * 1.45, 0.025, len * 0.9), C.Floor:Lerp(worn, 0.45), Enum.Material.Ground)
	end
	for i = 1, Config.Station.Count do
		local dir = RoundRocks.stationPosition(i).Unit
		route(c + dir * 9.5, c + dir * (Config.Station.Radius - 6.5), 3.4)
		local hopper = c + dirAt(if dir.Z > 0 then 90 else 270) * (HOPPER_RADIUS - 4)
		-- from the stance in front of the table (clear of the table body) to the hopper
		route(c + dir * (Config.Station.Radius - 5.5), hopper, 2.4)
	end
	-- the road outside the gate
	part(g, "CT_Rocks_Road", Vector3.new(14, 0.1, 70), CFrame.new(c + Vector3.new(0, 0.05, -80)), C.FloorDark, Enum.Material.SmoothPlastic)
end

-- Stations and bays --------------------------------------------------------------------------

local function buildStations(root: Instance, c: Vector3): ({ Model }, { CFrame })
	local stations = Kit.folder(root, "CT_Rocks_StationPads")
	for i = 1, Config.Station.Count do
		local rel = RoundRocks.stationPosition(i)
		local cf = CFrame.lookAt(c + rel, c)
		local pad = Kit.model(stations, "CT_Rocks_StationPad_" .. i)
		-- One plain concrete slab under the table and the stance in front of it (table frame: -Z toward
		-- the pile, the player stands at z -5): a low outer apron plus the slab, no paint, no glow.
		deco(part(pad, "Apron", Vector3.new(12.2, 0.14, 9.4), cf * CFrame.new(0, 0.07, -1.6), C.PadConcrete:Lerp(C.Dust, 0.3), Enum.Material.WoodPlanks))
		part(pad, "Pad", Vector3.new(11.6, PAD_TOP, 8.8), cf * CFrame.new(0, PAD_TOP / 2, -1.6), C.PadConcrete, Enum.Material.WoodPlanks)
		-- owner mark: one small muted inset with the table number at the front corner of the slab
		local tint = OWNER_COLORS[i] or P.Orange
		-- (no digit on it any more: a single figure on a 1.5 stud disc could only fill a third of it and the table number
		-- is now on the table's own timber sign; the disc stays as the owner's colour mark)
		deco(part(pad, "Number", Vector3.new(0.06, 1.5, 1.5), cf * CFrame.new(-4.6, PAD_TOP + 0.03, -5.0) * CFrame.Angles(0, 0, math.rad(90)), tint, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder))
		-- one work light on the back corner of the slab (beside the machine bay, never in front of the table)
		local light = Kit.kitProp(pad, "Prop_WorkLight", cf * CFrame.new(-5.6, PAD_TOP, 2.3) * CFrame.Angles(0, math.rad(25), 0), 0.8)
		if light and light.PrimaryPart then
			local l = Instance.new("PointLight")
			l.Range = 14
			l.Brightness = 0.5
			l.Color = Color3.fromRGB(255, 226, 170)
			l.Parent = light.PrimaryPart
		end
	end
	local tables = StationModels.buildAll(c, root, PAD_TOP) -- the tables stand ON their pads

	local bays = {}
	for i = 1, Config.Station.Count do
		local dir = RoundRocks.stationPosition(i).Unit
		local pos = c + dir * BAY_RADIUS
		local cf = CFrame.lookAt(pos, Vector3.new(c.X, c.Y, c.Z))
		local bay = Kit.model(root, "CT_Rocks_MachineBay_" .. i)
		-- the machine slot continues the table slab straight back (same concrete, same width class)
		-- snug: just wider than the machine, joined to the table slab at its back edge (the old slab was 11.4 x 10)
		part(bay, "Pad", Vector3.new(9.6, PAD_TOP, 8.9), cf * CFrame.new(0, PAD_TOP / 2, -0.65), C.PadConcrete, Enum.Material.WoodPlanks)
		-- machine clearance: four amber corner brackets, nothing else
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local corner = cf * CFrame.new(sx * 4.3, PAD_TOP + 0.01, sz * 3.5)
				deco(part(bay, "Clearance", Vector3.new(1.4, 0.03, 0.22), corner * CFrame.new(-sx * 0.6, 0, 0), C.Amber, Enum.Material.SmoothPlastic))
				deco(part(bay, "Clearance", Vector3.new(0.22, 0.03, 1.4), corner * CFrame.new(0, 0, -sz * 0.6), C.Amber, Enum.Material.SmoothPlastic))
			end
		end
		table.insert(bays, cf)
	end
	return tables, bays
end

-- Boundary ------------------------------------------------------------------------------------

-- True where the boundary is open (east drop) or used by a feature (north gate).
local function isOpening(deg: number): boolean
	local d = deg % 360
	return d < 21 or d > 339 or math.abs(d - 270) < 13
end

local function buildBoundary(root: Instance, c: Vector3, rng: Random)
	local edge = Kit.folder(root, "CT_Rocks_Boundary")
	-- front row: low rolling green hills on the octagon sides (the sky stays in view), hedges in front of them
	local deg = 21
	while deg < 339 do
		local w = rng:NextNumber(20, 26)
		local r = octRadius(deg, APOTHEM + 2.5)
		local step = math.deg(w * 0.95 / r)
		local mid = deg + step / 2
		if not isOpening(mid) then
			local n = sideNormal(mid)
			local pos = c + dirAt(mid) * octRadius(mid, APOTHEM + 2.5)
			Kit.hill(edge, CFrame.lookAt(pos, pos - n), w, rng:NextNumber(7, 10), rng)
		end
		deg += step
	end
	-- back row: taller hills behind, offset so gaps never line up
	deg = 30
	while deg < 330 do
		local w = rng:NextNumber(28, 34)
		local r = octRadius(deg, APOTHEM + 16)
		local step = math.deg(w * 0.95 / r)
		local mid = deg + step / 2
		if math.abs(mid - 270) > 9 then
			local n = sideNormal(mid)
			local pos = c + dirAt(mid) * octRadius(mid, APOTHEM + 16)
			Kit.hill(edge, CFrame.lookAt(pos, pos - n), w, rng:NextNumber(13, 19), rng)
		end
		deg += step
	end
	-- north road: hills either side of the path beyond the gate
	for _, s in { -1, 1 } do
		for k = 0, 1 do
			local pos = c + Vector3.new(s * 11, 0, -52 - k * 22)
			Kit.hill(edge, CFrame.lookAt(pos, pos + Vector3.new(-s, 0, 0)), 21, 9 + k * 3, rng)
		end
	end
	-- distant low hills past the lower meadow (east)
	for k = -2, 2 do
		local pos = c + Vector3.new(118 + rng:NextNumber(-4, 4), BENCH_Y, k * 34)
		Kit.hill(edge, CFrame.lookAt(pos, pos + Vector3.new(-1, 0, 0)), 34, 14, rng)
	end

	-- hedges, bushes and round trees between the fence and the hills, at free spots only (not behind the stands,
	-- the nook, the gate, the tool shelter or the lamp post)
	for _, a in { 28, 52, 112, 128, 150, 212, 236, 250, 302, 326 } do
		local pos = c + dirAt(a) * (octRadius(a, APOTHEM) + 1.8)
		Kit.bushCluster(edge, pos, rng:NextNumber(1.0, 1.4), rng)
		local tpos = c + dirAt(a + 7) * (octRadius(a + 7, APOTHEM) + 6)
		Kit.tree(edge, tpos, rng:NextNumber(1.0, 1.5), rng)
	end
	for _, a in { 70, 95, 170, 195, 345 } do
		Kit.tree(edge, c + dirAt(a) * (octRadius(a, APOTHEM) + 9), rng:NextNumber(1.2, 1.7), rng)
	end
	-- flower patches inside the fence line and out on the lower meadow
	local flowers = Kit.folder(edge, "Flowers")
	for _ = 1, 90 do
		local a = rng:NextNumber(0, 360)
		local rr = octRadius(a, APOTHEM) - rng:NextNumber(2.2, 6)
		local fp = c + dirAt(a) * rr
		if not isOpening(a) and (fp - c).Magnitude > 20 then
			Kit.flower(flowers, Vector3.new(fp.X, 0, fp.Z), rng)
		end
	end
	for _ = 1, 24 do
		Kit.flower(flowers, c + Vector3.new(rng:NextNumber(52, 90), BENCH_Y, rng:NextNumber(-40, 40)), rng)
	end

	-- east drop: retaining wall down to the bench, railing along the edge. (No "STEP DOWN / MIND THE EDGE" placard any
	-- more: on a phone it was tiny unreadable text beside the HUD, and the railing plus the invisible boundary already
	-- keep everyone on the meadow.)
	Kit.retainingWall(edge, CFrame.lookAt(c + Vector3.new(44.6, 0, 0), c + Vector3.new(100, 0, 0)), 64, -BENCH_Y, BENCH_Y)
	Kit.railing(edge, c + Vector3.new(42.4, 0, -18), c + Vector3.new(42.4, 0, 18))
	-- (no traffic cones at the rail ends: they touched the rim rails and were clutter, Master 8 section 5)
	-- south: short retaining wall where the cut face sits behind the hopper
	Kit.retainingWall(edge, CFrame.lookAt(c + Vector3.new(0, 0, 44.4), c), 22, 6, 0)

	-- north: entrance gate (closed)
	Kit.gate(edge, CFrame.lookAt(c + Vector3.new(0, 0, -44.5), c), 12)

	-- timber fence rim along the foot of the cliffs (not at the east drop, which has its own railing, and
	-- with a gap at the north gate)
	for k = 1, 7 do
		local side = k * 45
		local a = c + dirAt(side - 22.5) * octRadius(side - 22.5, APOTHEM - 0.9)
		local b = c + dirAt(side + 22.5) * octRadius(side + 22.5, APOTHEM - 0.9)
		if side == 180 then
			-- the equipment nook stands against the west boundary: the rail stops either side of it
			Kit.railing(edge, a:Lerp(b, 0.03), a:Lerp(b, 0.2))
			Kit.railing(edge, a:Lerp(b, 0.8), b:Lerp(a, 0.03))
		elseif side ~= 270 then
			Kit.railing(edge, a:Lerp(b, 0.03), b:Lerp(a, 0.03))
		else
			Kit.railing(edge, a:Lerp(b, 0.03), a:Lerp(b, 0.30))
			Kit.railing(edge, a:Lerp(b, 0.70), b:Lerp(a, 0.03))
		end
	end

	-- background: a few hay bales on the lower meadow
	Kit.hayBale(edge, CFrame.new(c + Vector3.new(68, BENCH_Y, -15)) * CFrame.Angles(0, 0.4, 0))
	Kit.hayBale(edge, CFrame.new(c + Vector3.new(71, BENCH_Y, -12)) * CFrame.Angles(0, -0.2, 0))
	Kit.bushCluster(edge, c + Vector3.new(66, BENCH_Y, 12), 1.4, rng)
	Kit.bushCluster(edge, c + Vector3.new(100, BENCH_Y, 6), 1.6, rng)
	Kit.tree(edge, c + Vector3.new(84, BENCH_Y, -6), 1.6, rng)
	Kit.tree(edge, c + Vector3.new(90, BENCH_Y, 22), 1.4, rng)
end

-- Equipment nook, lamps, utility props --------------------------------------------------------

local function buildWorksite(root: Instance, c: Vector3, rng: Random)
	local site = Kit.folder(root, "CT_Rocks_Worksite")
	-- west equipment nook
	local front = c + Vector3.new(-34.5, 0, 0)
	local ncf = CFrame.lookAt(front, c) -- -Z faces the arena, +Z goes back toward the wall
	Kit.shelter(site, ncf, 15, 8)
	-- picnic corner: hay bales and crates under the shelter (the old generator / compressor / tool rack are gone)
	Kit.hayBale(site, ncf * CFrame.new(-4.5, 0.3, 4.6) * CFrame.Angles(0, 0.2, 0))
	Kit.hayBale(site, ncf * CFrame.new(-1.4, 0.3, 5.0) * CFrame.Angles(0, -0.15, 0))
	Kit.hayBale(site, ncf * CFrame.new(-3.0, 2.5, 4.8) * CFrame.Angles(0, 0.4, 0))
	Kit.pallet(site, ncf * CFrame.new(5.2, 0.3, 1.8))
	Kit.crate(site, ncf * CFrame.new(5.0, 0.82, 1.6), 2)
	Kit.crate(site, ncf * CFrame.new(9.2, 0, -0.5) * CFrame.Angles(0, 0.4, 0), 1)
	Kit.crate(site, ncf * CFrame.new(4.0, 0.3, 5.4) * CFrame.Angles(0, 0.3, 0), 3)

	-- One lamp mast on the east edge, 9.4 studs tall. The old four masts stood 22 degrees off the table axes and
	-- crossed the first-person table view; this one is 70 degrees off every table's line of sight (the nook has
	-- its own lanterns and work light, the cut face wall lamps, the gate its own light).
	do
		local pos = c + Vector3.new(40.6, 0, 0)
		Kit.lampMast(site, CFrame.lookAt(pos, Vector3.new(c.X, pos.Y, c.Z)), true)
	end

	-- Two identical SHELL SELL stands on the free edges: south (tables 1 and 2) and north (tables 3 and 4), so
	-- the sale walk is the same short route for every table (about 21 studs) and no table sits behind
	-- the crane, a cliff or the pile. Each stands on a small concrete apron with one sign and one barrow.
	for _, deg in { 90, 270 } do
		local hpos = c + dirAt(deg) * HOPPER_RADIUS
		local hcf = CFrame.lookAt(hpos, c) -- -Z faces the pile (the side players walk up to)
		deco(part(site, "HopperApron", Vector3.new(10, 0.14, 8), hcf * CFrame.new(0, 0.07, 0), C.PadConcrete:Lerp(C.Dust, 0.2), Enum.Material.WoodPlanks))
		Kit.hopper(site, hcf, rng)
	end
	-- south cut face: kit wall lamps over the retaining wall either side of the south hopper
	for _, sx in { -9, 9 } do
		-- back plate flush on the wall's front face (the kit wall segments stand 0.45 behind the wall line at 44.4)
		local lamp = Kit.kitProp(site, "Wall_Lamp", CFrame.lookAt(c + Vector3.new(sx, 4.6, 44.85), c + Vector3.new(sx, 4.6, 0)), 1.4)
		if lamp and lamp.PrimaryPart then
			local l = Instance.new("PointLight")
			l.Range = 16
			l.Brightness = 0.7
			l.Color = Color3.fromRGB(255, 214, 150)
			l.Parent = lamp.PrimaryPart
		end
	end

	-- utility groups on the free edges (pass four): a lean-to tool shelter west of the gate (open side to the
	-- arena) and a cart bay east of the south hopper (track along the boundary, buffer stop, parked ore cart;
	-- wheel marks lead to the hopper). Both stand outside the pile/table/hopper routes.
	local shelterAt = c + Vector3.new(-12.5, 0, -38.6)
	Kit.toolShelter(site, CFrame.lookAt(shelterAt, shelterAt + Vector3.new(0, 0, 1)))
	Kit.hayBale(site, CFrame.new(c + Vector3.new(10, 0, 40)) * CFrame.Angles(0, 0.3, 0))
	Kit.hayBale(site, CFrame.new(c + Vector3.new(13, 0, 40.5)) * CFrame.Angles(0, -0.2, 0))
	Kit.hayBale(site, CFrame.new(c + Vector3.new(16, 0, -39)) * CFrame.Angles(0, 0.2, 0))
end

-- Containment ---------------------------------------------------------------------------------

local function buildBounds(root: Instance, c: Vector3)
	local b = Kit.folder(root, "CT_Rocks_Bounds")
	local side = 2 * APOTHEM * math.tan(math.rad(22.5)) + 4 -- overlap the corners
	for k = 0, 7 do
		local n = dirAt(k * 45)
		local w = part(b, "CT_Rocks_Bounds", Vector3.new(side, 90, 2), CFrame.lookAt(c + n * (APOTHEM + 1) + Vector3.new(0, 40, 0), c + Vector3.new(0, 40, 0)), Color3.new(), Enum.Material.SmoothPlastic)
		w.Transparency = 1
		w.CanQuery = false
		w.CanTouch = false
	end
	local lid = part(b, "CT_Rocks_BoundsTop", Vector3.new(2 * APOTHEM + 4, 2, 2 * APOTHEM + 4), CFrame.new(c + Vector3.new(0, 85, 0)), Color3.new())
	lid.Transparency = 1
	lid.CanQuery = false
	lid.CanTouch = false
end

-- Master Prompt 7 palette (section 3): warm wood, slate stone, charcoal metal, subdued green and ONE amber
-- accent; fewer bright lamps and yellow strips. One pass over the built arena (tables keep their own state
-- light, machines are built later by MachineModels): scenery neon lamp faces become warm matte glass, scenery
-- amber trims are muted, the bay clearance strips go charcoal, and the lights are fewer and softer.
local WARM_GLASS = Color3.fromRGB(255, 226, 150)
local MUTED_AMBER = Color3.fromRGB(246, 200, 96)
local KEEP_NEON = { Light = true, StateLight = true, Beacon = true, PanelOn = true, PanelOff = true, ReceiptLight = true }
local AMBER_NAMES = { Amber = true, Amber_Metal = true, Accent = true, Accent_Metal = true, Hazard = true, Stripe = true }
local function calmPalette(root: Instance)
	for _, d in root:GetDescendants() do
		local inStation = d:FindFirstAncestorWhichIsA("Model")
		while inStation and inStation:GetAttribute("StationIndex") == nil do
			inStation = inStation.Parent and inStation.Parent:FindFirstAncestorWhichIsA("Model") or nil
		end
		if inStation then
			continue -- the tables have their own restrained accents and the state light
		end
		if d:IsA("BasePart") then
			if d.Material == Enum.Material.Neon and not KEEP_NEON[d.Name] then
				d.Material = Enum.Material.SmoothPlastic
				d.Color = WARM_GLASS
			elseif d.Name == "Clearance" then
				d.Color = C.Slate:Lerp(C.PadConcrete, 0.3)
			elseif AMBER_NAMES[d.Name] then
				d.Color = MUTED_AMBER
			end
		elseif d:IsA("PointLight") or d:IsA("SpotLight") then
			local light = d :: PointLight -- SpotLight shares Enabled / Brightness / Range / Shadows
			local pad = d:FindFirstAncestor("CT_Rocks_StationPads")
			if pad then
				light.Enabled = false -- the pad work lights stay as unlit fixtures: one lit lamp per corner is enough
			else
				light.Brightness *= 0.6
				light.Range = math.min(light.Range, 14)
				light.Shadows = false
			end
		end
	end
end

-- Decorative pieces the camera must not be pushed in by (cliffs, lamps, props, fences, crane, signs,
-- shield glass, machine hoods): the client camera honours the attribute CameraIgnore. Floors, pads and
-- the boundary invisible walls are left out.
-- (the station pads folder is tagged too: only its walkable Pad / Apron slabs are left out, by name)
local CAMERA_SKIP = { CT_Rocks_Ground = true, CT_Rocks_Bounds = true, Pile = true }
local function tagCameraIgnore(root: Instance)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and (d.Name ~= "Pad" and d.Name ~= "Apron" and d.Name ~= "Surface") then
			local top = d
			local skip = false
			while top.Parent and top.Parent ~= root do
				top = top.Parent :: any
			end
			skip = CAMERA_SKIP[top.Name] == true
			if not skip then
				d:SetAttribute("CameraIgnore", true)
			end
		end
	end
end

-- Entry point ---------------------------------------------------------------------------------

-- Builds the arena at centre `c` under Workspace.CT_Rocks_Arena_<slot>. Returns the same fields
-- WorldBuilder.buildArena always returned: Root, Center, Spawns, Bays, Tables, PileFolder,
-- MachineFolder (plus Hopper).
function ArenaBuilder.build(slot: number, c: Vector3): { [string]: any }
	local rng = Random.new(500 + slot)
	local root = Kit.folder(Workspace, "CT_Rocks_Arena_" .. slot)
	buildGround(root, c, rng)
	local tables, bays = buildStations(root, c)
	buildBoundary(root, c, rng)
	buildWorksite(root, c, rng)
	buildBounds(root, c)
	calmPalette(root)
	tagCameraIgnore(root)

	-- Spawn spots: in front of each crushing table, equal distance from the pile and the table,
	-- facing the pile. Which member gets which one rotates between rounds (MatchService).
	local spawns = {}
	for i = 1, Config.Station.Count do
		local dir = RoundRocks.stationPosition(i).Unit
		local pos = c + dir * (Config.Station.Radius - 4.5) + Vector3.new(0, 3, 0)
		table.insert(spawns, CFrame.lookAt(pos, Vector3.new(c.X, 3, c.Z)))
	end

	local hopper = root:FindFirstChild("CT_Rocks_SellHopper", true)
	local pileFolder = Kit.folder(root, "Pile")
	local machineFolder = Kit.folder(root, "CT_Rocks_Machines")
	local arena = { Root = root, Center = c, Spawns = spawns, Bays = bays, Tables = tables, PileFolder = pileFolder, MachineFolder = machineFolder, Hopper = hopper }
	-- built as the meadow; the round start re-skins it for the hunted zone (MatchService -> applyZone)
	ArenaBuilder.applyZone(arena, ZoneThemes.Default)
	return arena
end

-- Shows zone `tierId` (Config.TierOrder id; unknown ids fall back to the Meadow) on a built arena: ground colours,
-- boundary tint and the zone's landmark set (ZoneScenery, theme data in shared/ZoneThemes). The previous zone's
-- landmarks are destroyed first; a no-op when that zone is already shown, so reused arenas swap cleanly per round.
function ArenaBuilder.applyZone(arena: { [string]: any }, tierId: string?)
	local root = arena.Root
	local c = arena.Center
	if typeof(root) ~= "Instance" or typeof(c) ~= "Vector3" then
		return
	end
	ZoneScenery.apply(root, c, ZoneThemes.get(tierId))
	-- the owner's low-poly set for the zone (when its meshes are in the place) covers the procedural one
	HuntLowPoly.apply(root, c, tierId)
end

return ArenaBuilder
