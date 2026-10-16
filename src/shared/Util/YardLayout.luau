--!strict
-- Where theme pieces stand inside one yard, and how big they may be. Pure numbers (yard-local x, z;
-- -Z is the gate, +Z is the back fence), so tests/specs/Map.spec.luau can prove the camera rules:
--   * the camera stands outside the gate looking at the table, so NOTHING stands in the front half
--     (z < 0) or by the gate corners: it would sit behind the HUD or be huge in ZOOM;
--   * tall pieces (trees, towers, crystals) hug the back fence and the two sides, never near the table;
--   * every piece stays at least FenceGap studs inside the fence, clear of the table and of each other;
--   * every piece's top stays below the top HUD chip in the spawn (WALK) view: the pieces are scaled
--     down where needed (maxTop / tallScale use CameraMath's projection).

local Config = require(script.Parent.Parent.Config)
local CameraMath = require(script.Parent.CameraMath)

local YardLayout = {}

YardLayout.FenceGap = 1.5 -- free studs between a piece and the fence (fence posts are 0.8 wide)
YardLayout.PostHalf = 0.4
YardLayout.TallRadius = 3.4 -- footprint of the biggest tall piece (at its largest scale)
YardLayout.LowRadius = 2.1 -- footprint of the biggest low prop
YardLayout.MaxTallScale = 1.14
YardLayout.MinTallScale = 0.6
YardLayout.TopLimit = 0.7 -- highest screen position (-1 bottom .. 1 top) a piece top may reach: under the top HUD
YardLayout.SpawnFov = 70 -- CameraView.WALK_FOV, the spawn camera's field of view

-- Height of each tall piece at scale 1, measured from its parts in Builders/PlotDecor.
YardLayout.TallHeights = table.freeze({
	oak = 9.6,
	palm = 9.2,
	lolly = 10.4,
	tower = 11.2,
	crystal = 8.2,
})

-- Small props: scale they are built at, and height at scale 1.
YardLayout.LowScale = table.freeze({
	umbrella = 0.7,
	candycane = 0.65,
	torch = 0.7,
	antenna = 0.7,
	orb = 0.8,
	lamp = 0.7,
})
YardLayout.LowDefaultScale = 0.85
YardLayout.LowHeights = table.freeze({
	bench = 3.0,
	boulder = 2.6,
	crate = 2.2,
	bush = 3.2,
	umbrella = 4.8,
	shell = 1.6,
	bucket = 2.4,
	cupcake = 3.7,
	gumdrop = 2.4,
	candycane = 6.2,
	barrel = 2.4,
	torch = 4.8,
	orb = 3.4,
	antenna = 5.7,
})

export type Spot = { x: number, z: number }

-- Centre-to-fence distance a piece of footprint `radius` needs.
function YardLayout.margin(radius: number): number
	return radius + YardLayout.FenceGap + YardLayout.PostHalf
end

-- Big pieces: the two back corners, then the two sides just behind the table's middle line.
function YardLayout.tall(half: number): { Spot }
	local m = half - YardLayout.margin(YardLayout.TallRadius)
	return {
		{ x = -m, z = m },
		{ x = m, z = m },
		{ x = -m, z = 5.2 },
		{ x = m, z = 5.2 },
	}
end

-- Small props: two behind the table's shoulders, one at the back middle.
function YardLayout.low(half: number): { Spot }
	local back = half - YardLayout.margin(YardLayout.LowRadius)
	return {
		{ x = -7, z = 10.5 },
		{ x = 7, z = 10.5 },
		{ x = 0, z = back },
	}
end

-- Yaw (radians, for CFrame.Angles(0, yaw, 0)) that turns a piece's -Z side toward (tx, tz) when it
-- stands at (x, z). Yaw only, so nothing ever tilts.
function YardLayout.yawToward(x: number, z: number, tx: number, tz: number): number
	return math.atan2(-(tx - x), -(tz - z))
end

-- The spawn camera in the table's frame (u = toward the back of the yard, y above the table top):
-- behind your avatar, who stands TABLE_RADIUS + 6 in front of the table, high over the gate.
function YardLayout.spawnView(): CameraMath.View
	local spawn = CameraMath.SPAWN
	return {
		back = Config.TABLE_RADIUS + 6 + spawn.back,
		up = 3 + spawn.up - Config.TABLE_HEIGHT, -- avatar root is 3 above the ground
		aim = 0,
	}
end

-- Screen height (-1 bottom .. 1 top) of a point `height` studs above the ground at yard spot (x, z),
-- seen from the spawn camera. nil when it is behind the camera.
function YardLayout.screenY(x: number, z: number, height: number): number?
	local _, sy =
		CameraMath.project(YardLayout.spawnView(), { z, height - Config.TABLE_HEIGHT, x }, 1.8, YardLayout.SpawnFov)
	return sy
end

-- Highest a piece standing at (x, z) may rise (studs above the ground) and still stay under TopLimit.
function YardLayout.maxTop(x: number, z: number): number
	local lo, hi = 0, 60
	for _ = 1, 40 do
		local mid = (lo + hi) / 2
		local sy = YardLayout.screenY(x, z, mid)
		if sy == nil or sy > YardLayout.TopLimit then
			hi = mid
		else
			lo = mid
		end
	end
	return lo
end

-- Scale for a tall piece `kind` at (x, z): at most `wanted`, small enough that its top stays under the HUD.
function YardLayout.tallScale(kind: string, x: number, z: number, wanted: number): number
	local nominal = YardLayout.TallHeights[kind] or 10
	local cap = YardLayout.maxTop(x, z) / nominal
	return math.clamp(math.min(wanted, YardLayout.MaxTallScale, cap), YardLayout.MinTallScale, YardLayout.MaxTallScale)
end

function YardLayout.lowScale(kind: string): number
	return YardLayout.LowScale[kind] or YardLayout.LowDefaultScale
end

return YardLayout
