--!strict
-- Where Pet Battle islands float and how a fight sits on one (pure; tested in tests/test_island.luau).
-- server/SkyIsland places a copy of the island per fight at spot(slot) and reads its fight floor (the part marked
-- ArenaCenter) through origin().

local PvpConfig = require(script.Parent.PvpConfig)

local IslandRules = {}

-- The island for fight slot `slot` (1, 2, ...): a row far from everything else, Spacing studs apart.
function IslandRules.spot(slot: number): Vector3
	local c = PvpConfig.Island
	return c.Base + Vector3.new(0, 0, (math.max(slot, 1) - 1) * c.Spacing)
end

-- The fight origin on a floor part (its CFrame and Size) and the layout that fits a floor of `radius` studs. The two
-- teams face each other along the part's X axis; TowerView draws side 1's pets along the origin's -Z.
function IslandRules.origin(floor: CFrame, size: Vector3, radius: number?): (CFrame, string)
	local pos = floor.Position + Vector3.new(0, size.Y / 2, 0)
	local look = floor.RightVector
	look = Vector3.new(look.X, 0, look.Z)
	look = if look.Magnitude > 0.1 then look.Unit else Vector3.xAxis
	local r = radius or math.min(size.X, size.Z) / 2
	local layout = if r >= PvpConfig.BigArena then "LiveBig" else "Live"
	return CFrame.lookAt(pos, pos - look), layout
end

-- True when a point is still on the island (for the fall catcher): within the floor radius plus a margin, and not
-- far below the floor.
function IslandRules.onIsland(origin: CFrame, radius: number, at: Vector3): boolean
	local d = at - origin.Position
	return Vector3.new(d.X, 0, d.Z).Magnitude <= radius + 8 and d.Y > -25
end

return IslandRules
