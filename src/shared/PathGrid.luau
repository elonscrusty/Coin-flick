--!strict
-- Flat-box spatial grid (pure; tests/test_path_grid.luau). Lobby path parts have CanQuery = false (the lobby build turns
-- queries off for its 1500+ decor parts), so raycasts and overlap queries never see them. RainbowPath (is this player
-- standing on a path?) and LobbyBloom (does a flower spot touch a path or a prop?) ask this grid instead: it is filled
-- once from the parts' CFrames and sizes and answers with plain math.
--
-- A box is a part seen from above: centre, half sizes and its two flat axes (R and Z, both on the ground plane). The
-- part's most vertical axis is its height (a path joint disc is a Cylinder turned so its axis points up: its X is the
-- height). An upright cylinder or a ball is a round footprint (Round = radius).

local PathGrid = {}

export type Box = {
	X: number, Y: number, Z: number, -- centre
	HX: number, HY: number, HZ: number, -- half sizes
	RX: number, RZ: number, -- right axis (ground plane, unit)
	ZX: number, ZZ: number, -- back axis (ground plane, unit)
	MinX: number, MaxX: number, MinZ: number, MaxZ: number, -- flat bounds (from the axes)
	Round: number?, -- radius of a round footprint (upright cylinder, ball); nil = rectangle
}
export type Grid = { Cell: number, Cells: { [string]: { Box } }, Count: number }

function PathGrid.new(cell: number?): Grid
	return { Cell = cell or 16, Cells = {}, Count = 0 }
end

local function unit(x: number, z: number): (number, number)
	local m = math.sqrt(x * x + z * z)
	if m < 1e-6 then
		return 1, 0
	end
	return x / m, z / m
end

-- A box from a centre, a size and the part's RightVector / ZVector x and z parts.
function PathGrid.box(x: number, y: number, z: number, sx: number, sy: number, sz: number, rx: number, rz: number, zx: number, zz: number): Box
	local ux, uz = unit(rx, rz)
	local vx, vz = unit(zx, zz)
	local hx, hz = sx / 2, sz / 2
	local ex = math.abs(ux) * hx + math.abs(vx) * hz
	local ez = math.abs(uz) * hx + math.abs(vz) * hz
	return {
		X = x, Y = y, Z = z, HX = hx, HY = sy / 2, HZ = hz,
		RX = ux, RZ = uz, ZX = vx, ZZ = vz,
		MinX = x - ex, MaxX = x + ex, MinZ = z - ez, MaxZ = z + ez,
	}
end

-- A round footprint (upright cylinder disc, ball) of radius r.
function PathGrid.disc(x: number, y: number, z: number, r: number, sy: number): Box
	local b = PathGrid.box(x, y, z, r * 2, sy, r * 2, 1, 0, 0, 1)
	b.Round = r
	return b
end

-- A box from a part's position, size, rotation (the 9 matrix numbers of CFrame:GetComponents, row by row) and shape
-- ("Block", "Cylinder", "Ball"; anything else is a block). Pure, so tests can feed it dumped lobby geometry.
function PathGrid.fromComponents(px: number, py: number, pz: number, sx: number, sy: number, sz: number, m: { number }, shape: string?): Box
	-- columns of the matrix: the part's right (X), up (Y) and back (Z) axes in world space
	local axes = { { m[1], m[4], m[7] }, { m[2], m[5], m[8] }, { m[3], m[6], m[9] } }
	local sizes = { sx, sy, sz }
	local h = 2
	for i = 1, 3 do
		if math.abs(axes[i][2]) > math.abs(axes[h][2]) then
			h = i
		end
	end
	if shape == "Ball" then
		return PathGrid.disc(px, py, pz, sx / 2, sx)
	end
	if shape == "Cylinder" and h == 1 then
		return PathGrid.disc(px, py, pz, math.min(sy, sz) / 2, sx)
	end
	local a = if h == 1 then 2 else 1
	local b = if h == 3 then 2 else 3
	return PathGrid.box(px, py, pz, sizes[a], sizes[h], sizes[b], axes[a][1], axes[a][3], axes[b][1], axes[b][3])
end

-- A box from a Roblox part (its CFrame, Size and shape).
function PathGrid.fromPart(part: BasePart): Box
	local px, py, pz, r00, r01, r02, r10, r11, r12, r20, r21, r22 = part.CFrame:GetComponents()
	local sz = part.Size
	local shape = if part:IsA("Part") then part.Shape.Name else nil
	return PathGrid.fromComponents(px, py, pz, sz.X, sz.Y, sz.Z, { r00, r01, r02, r10, r11, r12, r20, r21, r22 }, shape)
end

-- Spots beside a walkway strip, for props that must stand on the grass next to it: for both flat axes, both sides,
-- every `spacing` studs along the other axis. Each spot is a list of tries (nearest first) at `clear` + each of
-- `steps` studs out from the strip's side, so a stone or a joining strip at the edge pushes the prop further out.
-- A strip's run direction is not assumed (the lobby's strips are short wide slabs: 26 wide, ~3 long), so both axes are
-- tried; tries that land on the path are rejected by the caller's overlap check. Round boxes give none.
function PathGrid.sideSpots(b: Box, clear: number, spacing: number, steps: { number }): { { { number } } }
	local out = {}
	if b.Round then
		return out
	end
	for _, ax in { { b.RX, b.RZ, b.HX, b.ZX, b.ZZ, b.HZ }, { b.ZX, b.ZZ, b.HZ, b.RX, b.RZ, b.HX } } do
		local ux, uz, uh, vx, vz, vh = ax[1], ax[2], ax[3], ax[4], ax[5], ax[6]
		local len = vh * 2
		local n = math.max(1, math.floor(len / spacing))
		for i = 0, n - 1 do
			local t = -vh + (i + 0.5) * len / n
			for _, side in { -1, 1 } do
				local tries = {}
				for _, extra in steps do
					local d = side * (uh + clear + extra)
					table.insert(tries, { b.X + ux * d + vx * t, b.Z + uz * d + vz * t })
				end
				table.insert(out, tries)
			end
		end
	end
	return out
end

-- Every BasePart inside a folder or model named "Paths" (the lobby build's path layer) or with attribute
-- RainbowPath = true, as a grid. Count = 0 when the map has none.
function PathGrid.lobbyPaths(root: Instance): Grid
	local g = PathGrid.new(16)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and (d:GetAttribute("RainbowPath") == true or d:FindFirstAncestor("Paths") ~= nil) then
			PathGrid.add(g, PathGrid.fromPart(d))
		end
	end
	return g
end

local function key(i: number, j: number): string
	return i .. ":" .. j
end

function PathGrid.add(g: Grid, b: Box)
	local c = g.Cell
	for i = math.floor(b.MinX / c), math.floor(b.MaxX / c) do
		for j = math.floor(b.MinZ / c), math.floor(b.MaxZ / c) do
			local k = key(i, j)
			local list = g.Cells[k]
			if not list then
				list = {}
				g.Cells[k] = list
			end
			table.insert(list, b)
		end
	end
	g.Count += 1
end

-- The box under the point (x, z) (within `margin` studs of its edge) whose top is highest between y - `depth` and
-- y + `above`, or nil. `above`: how far the top may be over the point; `depth`: how far below (default: any).
function PathGrid.under(g: Grid, x: number, y: number, z: number, margin: number?, above: number?, depth: number?): Box?
	local list = g.Cells[key(math.floor(x / g.Cell), math.floor(z / g.Cell))]
	if not list then
		return nil
	end
	local m = margin or 0
	local best: Box? = nil
	for _, b in list do
		local dx, dz = x - b.X, z - b.Z
		local lx = dx * b.RX + dz * b.RZ
		local lz = dx * b.ZX + dz * b.ZZ
		local top = b.Y + b.HY
		local r = b.Round
		local inside = if r then dx * dx + dz * dz <= (r + m) * (r + m) else math.abs(lx) <= b.HX + m and math.abs(lz) <= b.HZ + m
		if inside and top <= y + (above or 0) and top >= y - (depth or math.huge) then
			if not best or top > best.Y + best.HY then
				best = b
			end
		end
	end
	return best
end

-- True when the turned box b's footprint, grown by `margin`, overlaps the flat rectangle centred (cx, cz) with half
-- sizes (ax, az): an exact 2D separating-axis test (a turned strip's bounds cover far more grass than the strip).
function PathGrid.overlapsRect(b: Box, cx: number, cz: number, ax: number, az: number, margin: number?): boolean
	local m = margin or 0
	local dx, dz = b.X - cx, b.Z - cz
	local r = b.Round
	if r then
		-- circle against the rectangle: distance from the centre to the rectangle's nearest point
		local nx = math.max(math.abs(dx) - ax, 0)
		local nz = math.max(math.abs(dz) - az, 0)
		return nx * nx + nz * nz <= (r + m) * (r + m)
	end
	local hx, hz = b.HX + m, b.HZ + m
	for _, n in { { 1, 0 }, { 0, 1 }, { b.RX, b.RZ }, { b.ZX, b.ZZ } } do
		local nx, nz = n[1], n[2]
		local ra = ax * math.abs(nx) + az * math.abs(nz)
		local rb = hx * math.abs(b.RX * nx + b.RZ * nz) + hz * math.abs(b.ZX * nx + b.ZZ * nz)
		if math.abs(dx * nx + dz * nz) > ra + rb then
			return false
		end
	end
	return true
end

-- Exact version of touches: the rectangle centred (cx, cz), half sizes (ax, az), between heights minY and maxY,
-- against every box's turned footprint grown by `margin`.
function PathGrid.touchesExact(g: Grid, cx: number, cz: number, ax: number, az: number, minY: number, maxY: number, margin: number?): Box?
	local c = g.Cell
	local m = margin or 0
	for i = math.floor((cx - ax - m) / c), math.floor((cx + ax + m) / c) do
		for j = math.floor((cz - az - m) / c), math.floor((cz + az + m) / c) do
			local list = g.Cells[key(i, j)]
			if list then
				for _, b in list do
					if b.Y - b.HY <= maxY and b.Y + b.HY >= minY and PathGrid.overlapsRect(b, cx, cz, ax, az, m) then
						return b
					end
				end
			end
		end
	end
	return nil
end

-- True when the flat rectangle [minX, maxX] x [minZ, maxZ] between heights minY and maxY touches any box's flat
-- bounds and height range (conservative: a turned box counts by its bounds).
function PathGrid.touches(g: Grid, minX: number, minZ: number, maxX: number, maxZ: number, minY: number, maxY: number): boolean
	local c = g.Cell
	for i = math.floor(minX / c), math.floor(maxX / c) do
		for j = math.floor(minZ / c), math.floor(maxZ / c) do
			local list = g.Cells[key(i, j)]
			if list then
				for _, b in list do
					if b.MinX <= maxX and b.MaxX >= minX and b.MinZ <= maxZ and b.MaxZ >= minZ and b.Y - b.HY <= maxY and b.Y + b.HY >= minY then
						return true
					end
				end
			end
		end
	end
	return false
end

export type SpotOpts = {
	Half: number, -- half size of the prop's square footprint
	Height: number, -- prop height (trim above the ground within this blocks)
	Margin: number, -- clear studs round the prop (walkways)
	Clear: number?, -- first try's distance from a strip side to the prop's centre (default Half + Margin + 0.2)
	Spacing: number, -- studs between spots along a strip side
	Steps: { number }, -- tries out from the strip side, nearest first
	Cell: number, -- no two props in one Cell x Cell square
	Max: number,
	Ground: (x: number, z: number, y: number) -> number?, -- ground height under (x, z) when it is grass, else nil
	Extra: ((x: number, y: number, z: number) -> string?)?, -- any other reason the spot is blocked (props, queries)
}

-- Where props go beside the walkways (pure: the lobby flowers use it; tests run it on dumped lobby geometry). A try is
-- rejected when it is not grass, its footprint (+ Margin) overlaps a walkway (any height), it overlaps trim (edge
-- stones, curbs, tufts: no margin, from just below the ground to Height above), Extra blocks it, or a prop already
-- stands in its Cell square. Walkways are visited in a fixed shuffled order so the props spread over the whole lobby.
-- Returns the spots ({x, y, z}) and counts per reason (the last reason tried per spot).
function PathGrid.spots(walkways: { Box }, paths: Grid, trim: Grid, o: SpotOpts): ({ { number } }, { [string]: number })
	local stats: { [string]: number } = { samples = 0, tries = 0, notGrass = 0, path = 0, trim = 0, solid = 0, query = 0, spaced = 0, placed = 0 }
	local order = table.clone(walkways)
	local seed = 20261015
	for i = #order, 2, -1 do
		seed = (seed * 48271) % 2147483647
		local j = seed % i + 1
		order[i], order[j] = order[j], order[i]
	end
	local taken: { [string]: boolean } = {}
	local out: { { number } } = {}
	local clear = o.Clear or (o.Half + o.Margin + 0.2)
	local function cellKey(x: number, z: number): string
		return math.floor(x / o.Cell) .. ":" .. math.floor(z / o.Cell)
	end
	for _, w in order do
		if #out >= o.Max then
			break
		end
		for _, tries in PathGrid.sideSpots(w, clear, o.Spacing, o.Steps) do
			if #out >= o.Max then
				break
			end
			stats.samples += 1
			local why = "notGrass"
			local spot: { number }? = nil
			for _, at in tries do
				stats.tries += 1
				local x, z = at[1], at[2]
				local y = o.Ground(x, z, w.Y)
				if not y then
					why = "notGrass"
					continue
				end
				if taken[cellKey(x, z)] then
					why = "spaced"
					continue
				end
				if PathGrid.touchesExact(paths, x, z, o.Half, o.Half, -math.huge, math.huge, o.Margin) then
					why = "path"
					continue
				end
				if PathGrid.touchesExact(trim, x, z, o.Half, o.Half, y - 1, y + o.Height, 0) then
					why = "trim"
					continue
				end
				local extra = if o.Extra then o.Extra(x, y, z) else nil
				if extra then
					why = extra
					continue
				end
				spot = { x, y, z }
				break
			end
			if spot then
				taken[cellKey(spot[1], spot[3])] = true
				table.insert(out, spot)
				stats.placed += 1
			else
				stats[why] = (stats[why] or 0) + 1
			end
		end
	end
	return out, stats
end

return PathGrid
