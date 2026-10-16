--!strict
-- Pure fit rule for a vertical column of tiles on a short screen (HUD left column). Given the height the column may
-- use, how many tiles it holds, the gap between them and the smallest / largest tile height, it picks the tile size and
-- how many columns are needed. Tall screens get maxSize back unchanged; the size never drops below minSize.

local ColumnFit = {}

export type Fit = { size: number, cols: number }

function ColumnFit.fit(avail: number, count: number, gap: number, minSize: number, maxSize: number): Fit
	if count <= 0 then
		return { size = maxSize, cols = 1 }
	end
	local minS = math.min(minSize, maxSize)
	local cols = 1
	while cols < count do
		local rows = math.ceil(count / cols)
		if rows * minS + gap * (rows - 1) <= avail then
			break
		end
		cols += 1
	end
	local rows = math.ceil(count / cols)
	local size = (avail - gap * (rows - 1)) / rows
	return { size = math.max(minS, math.min(maxSize, size)), cols = cols }
end

return ColumnFit
