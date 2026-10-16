--!strict
-- Where each coin sits on a table, as an (x, z) offset from the table centre.
-- Coin 1 is in the middle, coins 2..10 make a ring around it.

local TableLayout = {}

local RING_RADIUS = 5.6

function TableLayout.coinOffset(index: number, maxCoins: number): (number, number)
	if index <= 1 then
		return 0, 0
	end
	local ringCount = math.max(1, maxCoins - 1)
	local angle = (index - 2) / ringCount * math.pi * 2
	return math.cos(angle) * RING_RADIUS, math.sin(angle) * RING_RADIUS
end

-- Plot slot -> position on the big ring around the middle of the map.
function TableLayout.plotPosition(slot: number, maxPlots: number, ringRadius: number): (number, number)
	local angle = (slot - 1) / maxPlots * math.pi * 2
	return math.cos(angle) * ringRadius, math.sin(angle) * ringRadius
end

return TableLayout
