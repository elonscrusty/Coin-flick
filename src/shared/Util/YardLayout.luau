--!strict
-- Where theme pieces stand inside one yard. Pure numbers (yard-local x, z; -Z is the gate, +Z is the
-- back fence), so tests/specs/Map.spec.luau can prove the camera rules:
--   * the camera stands outside the gate looking at the table, so NOTHING stands in the front half
--     (z < 0) or by the gate corners: it would sit behind the HUD or be huge in ZOOM;
--   * tall pieces (trees, towers, crystals) hug the back fence and the two sides, never near the table;
--   * everything stays well inside the fence and clear of the table and of each other.

local YardLayout = {}

YardLayout.FenceMargin = 4.5 -- studs between a piece centre and the fence line
YardLayout.TallRadius = 3.6 -- footprint of the biggest tall piece (at its largest scale)
YardLayout.LowRadius = 2.4 -- footprint of the biggest low prop
YardLayout.MaxTallScale = 1.2
YardLayout.MaxLowScale = 0.85

export type Spot = { x: number, z: number }

-- Big pieces: the two back corners, then the two sides just behind the table's middle line.
function YardLayout.tall(half: number): { Spot }
	local m = half - YardLayout.FenceMargin
	return {
		{ x = -m, z = m },
		{ x = m, z = m },
		{ x = -m, z = 3 },
		{ x = m, z = 3 },
	}
end

-- Small props: two behind the table's shoulders, one at the back middle.
function YardLayout.low(half: number): { Spot }
	local m = half - YardLayout.FenceMargin
	return {
		{ x = -8.5, z = 10 },
		{ x = 8.5, z = 10 },
		{ x = 0, z = m },
	}
end

-- Yaw (radians, for CFrame.Angles(0, yaw, 0)) that turns a piece's -Z side toward (tx, tz) when it
-- stands at (x, z). Yaw only, so nothing ever tilts.
function YardLayout.yawToward(x: number, z: number, tx: number, tz: number): number
	return math.atan2(-(tx - x), -(tz - z))
end

return YardLayout
