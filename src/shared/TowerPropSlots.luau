--!strict
-- Where the tower rooms' theme props stand (pure, tested in tests/test_tower_prop_slots.luau): one prop in each wall span
-- between the side doors, on the east and west walls. Side doors sit at 0 and +-TILE along the wall and are about 6.2
-- studs half-wide, so a prop centred at +-TILE/2 may be at most (TILE/2 - DoorHalf) * 2 wide before it blocks a door.
local TowerPropSlots = {}

TowerPropSlots.Room = 48 -- half width of the kit room: 3 x 3 floor tiles
TowerPropSlots.Tile = 32
TowerPropSlots.DoorHalf = 6.2 -- half width of a side door opening
TowerPropSlots.MaxWidth = 7 -- studs: no theme prop wider than this (big pines clipped the walls)
TowerPropSlots.TreeWidth = 14 -- trees keep their height (a squashed pine reads as a blob); 14 still clears both doors
TowerPropSlots.Alongs = { -0.5, 0.5 } -- slot centres along each wall, in tiles
TowerPropSlots.DoorAlongs = { -1, 0, 1 } -- door centres along each wall, in tiles

-- Uniform scale for a mesh of `size` that should be `height` tall, capped so its wider side stays within the width cap.
function TowerPropSlots.scale(sizeX: number, sizeY: number, sizeZ: number, height: number, tree: boolean): number
	local cap = if tree then TowerPropSlots.TreeWidth else TowerPropSlots.MaxWidth
	return math.min(height / sizeY, cap / math.max(sizeX, sizeZ))
end

-- Half the footprint of a scaled prop (its wider side), as the builder insets it.
function TowerPropSlots.half(sizeX: number, sizeZ: number): number
	return 0.5 * math.max(sizeX, sizeZ)
end

-- Local (x, z) of slot `along` (-0.5 / 0.5) on wall side `sx` (-1 west, 1 east) for a prop of half-footprint `half`.
function TowerPropSlots.position(sx: number, along: number, half: number): (number, number)
	return sx * (TowerPropSlots.Room - 2 - half), along * TowerPropSlots.Tile
end

-- Gap between the prop's footprint edge along the wall and the nearest door opening.
function TowerPropSlots.doorGap(along: number, half: number): number
	local best = math.huge
	for _, d in TowerPropSlots.DoorAlongs do
		best = math.min(best, math.abs(along - d) * TowerPropSlots.Tile - half - TowerPropSlots.DoorHalf)
	end
	return best
end

return TowerPropSlots
