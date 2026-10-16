--!strict
-- Where the hunt arena's scenery props stand (pure, so tests/test_hunt_placement.luau can check it offline).
-- Arena-local studs, origin = pile centre. The fence is a SQUARE (Hunt_Fence, about 85 x 85, lines at +-42.5; the east
-- side is fenced too). A prop whose footprint comes within Clear studs of a fence line steps perpendicular to that
-- line to exactly Clear studs off it (inward if it stood inside, outward if outside); cliffs are the backdrop and stay.
local ZoneThemes = require(script.Parent.ZoneThemes)

local HuntPlacement = {}

HuntPlacement.FenceHalf = 42.5 -- half-extent of the fence square when the mesh is not there to measure
HuntPlacement.Clear = 3 -- studs between a prop's footprint and the fence line
HuntPlacement.TrunkRadius = 1.5 -- trees count by their trunk, not their crown

-- { prop, x, y, z, yaw, scale }
local SCENERY: { { any } } = {
	{ "CliffTall", 67.616, 0.0, 41.425, 4.1816, 0.642 },
	{ "CliffTall", 52.681, 0.0, 57.505, 4.0485, 0.557 },
	{ "CliffTall", 29.861, 0.0, 76.477, 3.4168, 0.636 },
	{ "CliffTall", 5.934, 0.0, 78.078, 3.3459, 0.562 },
	{ "CliffTall", -14.326, 0.0, 78.357, 2.7969, 0.601 },
	{ "CliffTall", -34.069, 0.0, 68.933, 2.6795, 0.585 },
	{ "CliffTall", -52.911, 0.0, 58.875, 2.2681, 0.624 },
	{ "CliffTall", -65.229, 0.0, 41.808, 2.2521, 0.633 },
	{ "CliffTall", -80.121, 0.0, 21.575, 1.7861, 0.565 },
	{ "CliffTall", -77.098, 0.0, 3.619, 1.7711, 0.58 },
	{ "CliffTall", -79.648, 0.0, -19.571, 1.314, 0.577 },
	{ "CliffTall", -65.991, 0.0, -41.265, 0.873, 0.605 },
	{ "CliffTall", -51.622, 0.0, -53.94, 0.6715, 0.687 },
	{ "CliffTall", -30.618, 0.0, -71.14, 0.5143, 0.651 },
	{ "CliffTall", 33.607, 0.0, -74.545, -0.587, 0.606 },
	{ "CliffTall", 49.203, 0.0, -57.541, -0.7365, 0.551 },
	{ "CliffStep", 62.164, 0.0, -44.256, -1.0659, 0.551 },
	{ "Kit_Pine_A", -5.144, 0.0, 50.206, 3.3109, 0.82 },
	{ "CliffPine", 49.881, 0.0, -37.992, 4.2978, 0.79 },
	{ "PineTree", 36.478, 0.0, -40.949, 2.8062, 0.837 },
	{ "Kit_Tree_B", 56.639, 0.0, -26.694, 0.1932, 0.959 },
	{ "RoundTree", 41.749, 0.0, -48.079, 4.7352, 0.722 },
	{ "PineTree", -53.797, 0.0, 12.117, 6.2194, 0.858 },
	{ "RoundTree", -30.329, 0.0, -47.22, 1.191, 0.96 },
	{ "RoundTree", -24.622, 0.0, 45.204, 3.0948, 0.92 },
	{ "Kit_Tree_A", 21.387, 0.0, -49.586, 5.4642, 0.823 },
	{ "Kit_Tree_A", 32.808, 0.0, -41.802, 3.9873, 0.982 },
	{ "Kit_Pine_A", -61.748, 0.0, 15.341, 5.9758, 0.811 },
	{ "PineTree", -47.424, 0.0, 44.227, 4.7525, 0.71 },
	{ "Kit_Pine_A", -36.805, 0.0, 53.56, 1.7471, 0.895 },
	{ "RoundTree", 19.196, 0.0, 57.23, 1.4915, 0.89 },
	{ "RoundTree", -24.397, 0.0, 45.572, 3.0274, 0.84 },
	{ "Kit_Tree_A", 13.589, 0.0, -53.884, 3.0988, 0.995 },
	{ "PineTree", -25.192, 0.0, -54.752, 1.5908, 0.782 },
	{ "RoundTree", 15.081, 0.0, -61.62, 2.4897, 0.716 },
	{ "Kit_Pine_A", -0.812, 0.0, 55.501, 3.0357, 0.761 },
	{ "PineTree", 13.397, 0.0, -61.824, 4.2775, 0.7 },
	{ "Kit_Tree_A", -5.624, 0.0, 54.1, 5.5016, 0.926 },
	{ "CliffPine", -1.808, 0.0, 50.947, 6.1544, 0.809 },
	{ "Kit_Pine_A", -55.62, 0.0, 7.161, 2.8174, 0.814 },
	{ "Kit_Tree_A", -49.91, 0.0, 21.475, 4.1401, 0.803 },
	{ "CliffPine", 37.201, 0.0, 44.392, 6.1269, 0.725 },
	{ "CliffPine", -45.542, 0.0, 28.369, 3.3812, 0.723 },
	{ "RoundTree", -54.12, 0.0, -14.122, 3.066, 0.905 },
	{ "CliffPine", 52.002, 0.0, -28.557, 1.9568, 0.739 },
	{ "Kit_Tree_B", -49.387, 0.0, -22.821, 2.665, 0.921 },
	{ "Kit_Pine_A", 39.752, 0.0, 49.376, 1.974, 0.963 },
	{ "Kit_Pine_A", -10.416, 0.0, 60.151, 5.0496, 0.717 },
	{ "Kit_Tree_A", -27.22, 0.0, -60.348, 3.4476, 0.849 },
	{ "Kit_Pine_A", -57.015, 0.0, -3.112, 3.8196, 0.741 },
	{ "Kit_Tree_A", -52.499, 0.0, -14.933, 3.2344, 0.765 },
	{ "Kit_Tree_A", -61.49, 0.0, -14.88, 3.672, 0.959 },
	{ "Kit_Rock_A", -33.535, 0.0, 23.756, 0.7092, 0.749 },
	{ "Rock", -38.489, 0.0, -1.237, 1.9243, 0.809 },
	{ "FlowerBush", -35.222, 0.0, 21.91, 5.2293, 0.933 },
	{ "FlowerBush", 22.23, 0.0, -33.679, 3.6611, 0.875 },
	{ "Rock", 39.107, 0.0, 4.107, 5.4643, 0.937 },
	{ "Rock", -31.045, 0.0, 25.866, 2.4612, 0.807 },
	{ "FlowerBush", -37.809, 0.0, 18.816, 5.9884, 1.056 },
	{ "Rock", -23.668, 0.0, 31.572, 5.3884, 0.931 },
	{ "Mushroom", -3.647, 0.0, 40.519, 4.278, 0.4 },
	{ "Rock", 39.743, 0.0, 13.513, 3.5652, 0.819 },
	{ "Kit_Rock_A", -17.127, 0.0, 39.111, 2.2687, 0.811 },
	{ "Mushroom", 35.596, 0.0, 22.16, 0.4996, 0.5 },
	{ "FlowerBush", 32.588, 0.0, 23.071, 0.2088, 0.996 },
	{ "Kit_Bush_A", -38.21, 0.0, 0.753, 1.7276, 0.992 },
	{ "Kit_Rock_A", -38.999, 0.0, -18.536, 5.6423, 0.792 },
	{ "Kit_Rock_A", 39.889, 0.0, 7.147, 3.1435, 1.006 },
	{ "FlowerBush", -39.09, 0.0, -14.002, 4.9649, 0.829 },
	{ "Rock", -19.586, 0.0, 37.264, 0.885, 0.741 },
	{ "Kit_Rock_A", 26.398, 0.0, -31.221, 2.1845, 0.827 },
	{ "Kit_Rock_A", 33.552, 0.0, 21.827, 1.1857, 0.845 },
	{ "Kit_Rock_A", -31.314, 0.0, -23.107, 5.5503, 0.97 },
	{ "Kit_Rock_A", -39.027, 0.0, -2.037, 4.0626, 0.996 },
	{ "FlowerBush", -22.56, 0.0, 32.766, 3.7554, 1.058 },
	{ "Kit_Rock_A", 34.612, 0.0, -21.682, 4.8429, 0.978 },
	{ "FlowerBush", 95.913, -9.0, 5.444, 5.9052, 0.876 },
	{ "RoundTree", 89.763, -9.0, 44.946, 1.3087, 0.985 },
	{ "RoundTree", 81.237, -9.0, 7.728, 4.4717, 0.749 },
	{ "RoundTree", 64.155, -9.0, 28.314, 0.7706, 0.749 },
	{ "FlowerBush", 84.831, -9.0, 10.778, 0.0005, 0.769 },
	{ "Kit_Tree_A", 57.638, -9.0, -42.423, 4.2826, 0.715 },
	{ "FlowerBush", 91.139, -9.0, 37.517, 5.5358, 0.856 },
	{ "FlowerBush", 72.577, -9.0, 33.57, 3.6784, 0.823 },
	{ "Kit_Tree_A", 59.197, -9.0, 9.879, 3.1087, 0.869 },
	{ "RoundTree", 77.877, -9.0, 36.712, 3.507, 0.808 },
	-- beside the two SHELL SELL stands (apron 10 x 8 at z +-30), about 2 studs clear of it
	{ "Barrel", 9.8, 0.0, 31.76, 4.4297, 1.0 },
	{ "Crate", -9.8, 0.0, 31.32, 2.7063, 1.0 },
	{ "HayBale", 14.0, 0.0, 36.0, 5.2468, 1.0 },
	{ "Barrel", -9.8, 0.0, -31.76, 2.2708, 1.0 },
	{ "Crate", 9.8, 0.0, -31.32, 0.8822, 1.0 },
	{ "HayBale", -14.0, 0.0, -36.0, 5.2575, 1.0 },
}

local TREES: { [string]: boolean } = { PineTree = true, Kit_Pine_A = true, RoundTree = true, Kit_Tree_A = true, Kit_Tree_B = true }

-- Forest: one extra, taller tree beside every edge tree of the set, a little further out, so the edges read as a
-- dense wood. Same prop meshes; skips the open east drop and the north road.
function HuntPlacement.forestExtras(): { { any } }
	local out = {}
	local roadHalf = ZoneThemes.Layout.RoadHalfWidth
	for i, s in SCENERY do
		local x, z = s[2], s[4]
		local r = math.sqrt(x * x + z * z)
		if TREES[s[1]] and s[3] == 0 and r > 45 then
			for k, step in { { 1.12, 0.09, 1.3 }, { 0.97, -0.1, 1.15 } } do
				local a = math.atan2(z, x) + step[2]
				local nx, nz = math.cos(a) * r * step[1], math.sin(a) * r * step[1]
				local deg = math.deg(math.atan2(nz, nx))
				local onRoad = nz < 0 and math.abs(nx) < roadHalf + 5
				if math.abs(deg) > 30 and not onRoad then
					local pick = if (i + k) % 2 == 0 then "PineTree" else s[1]
					table.insert(out, { pick, nx, 0.0, nz, s[5] + 1.3 * k, s[6] * step[3] })
				end
			end
		end
	end
	return out
end

HuntPlacement.SCENERY = SCENERY
HuntPlacement.TREES = TREES

local function axis(c: number, other: number, half: number, clear: number): number
	-- the fence line on this axis only reaches as far as the square's side (plus the clearance round its end)
	if math.abs(other) > half + clear then
		return c
	end
	local a = math.abs(c)
	if math.abs(a - half) >= clear then
		return c
	end
	local want = if a < half then half - clear else half + clear
	return if c < 0 then -want else want
end

-- (x, z) stepped off the square fence of half-extent `half` until it is `clear` studs from the line (clear includes the
-- prop radius); unchanged when it already is.
function HuntPlacement.squareOff(x: number, z: number, half: number, clear: number): (number, number)
	return axis(x, z, half, clear), axis(z, x, half, clear)
end

-- Distance from (x, z) to the fence outline (inside or outside).
function HuntPlacement.fenceDistance(x: number, z: number, half: number): number
	local qx, qz = math.abs(x) - half, math.abs(z) - half
	local ox, oz = math.max(qx, 0), math.max(qz, 0)
	local outside = math.sqrt(ox * ox + oz * oz)
	if outside > 0 then
		return outside
	end
	return -math.max(qx, qz)
end

-- (x, z) pushed out past the square until it is `clear` studs outside the line (Space crystal clusters).
function HuntPlacement.pushOut(x: number, z: number, half: number, clear: number): (number, number)
	local want = half + clear
	if math.max(math.abs(x), math.abs(z)) >= want then
		return x, z
	end
	if math.abs(x) >= math.abs(z) then
		return (if x < 0 then -want else want), z
	end
	return x, (if z < 0 then -want else want)
end

-- Where a scenery row of prop `name` and footprint radius `radius` stands.
function HuntPlacement.spot(name: string, x: number, z: number, radius: number, half: number): (number, number)
	if string.sub(name, 1, 5) == "Cliff" and name ~= "CliffPine" then
		return x, z
	end
	local r = if TREES[name] or name == "CliffPine" then HuntPlacement.TrunkRadius else radius
	return HuntPlacement.squareOff(x, z, half, HuntPlacement.Clear + r)
end

-- True when a prop of `radius` at (x, z) would touch a SHELL SELL stand (apron 10 x 8 centred at z = +-30) or come
-- within 2 studs of it.
function HuntPlacement.nearHopper(x: number, z: number, radius: number): boolean
	return math.abs(x) < 5 + 2 + radius and math.abs(math.abs(z) - 30) < 4 + 2 + radius
end

-- A hunt spawn turned to face the egg pile (same spot, level gaze): every racer starts the round looking at the
-- action, whatever way a zone kit's spawn pad points (walkthrough 10-14: the hunt opened on an empty lawn).
function HuntPlacement.faceCentre(cf: CFrame, centre: Vector3): CFrame
	local pos = cf.Position
	local flat = Vector3.new(centre.X - pos.X, 0, centre.Z - pos.Z)
	if flat.Magnitude < 0.1 then
		return cf
	end
	local look = flat.Unit
	return CFrame.fromMatrix(pos, look:Cross(Vector3.yAxis), Vector3.yAxis) -- level gaze (same as CFrame.lookAt)
end

return HuntPlacement
