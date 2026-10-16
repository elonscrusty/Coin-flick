-- PathGrid (shared/PathGrid): path detection without raycasts (lobby paths have CanQuery = false).
return function(t)
	local test, shared = t.test, t.shared
	local PathGrid = shared("PathGrid")

	test("path grid: a turned path segment covers its own strip, not the grass beside it", function()
		local g = PathGrid.new(16)
		-- a 40 x 1 x 8 path, turned 45 degrees, top at y = 1
		local c = math.sqrt(0.5)
		PathGrid.add(g, PathGrid.box(100, 0.5, 100, 40, 1, 8, c, -c, c, c))
		assert(PathGrid.under(g, 100, 3, 100, 0, 0) ~= nil, "centre")
		assert(PathGrid.under(g, 100 + 15 * c, 3, 100 - 15 * c, 0, 0) ~= nil, "along the length")
		assert(PathGrid.under(g, 100 + 6 * c, 3, 100 + 6 * c, 0, 0) == nil, "6 studs to the side is grass")
		assert(PathGrid.under(g, 100 + 4.5 * c, 3, 100 + 4.5 * c, 1, 0) ~= nil, "edge margin")
		assert(PathGrid.under(g, 100, 0.6, 100, 0, 0.5) ~= nil and PathGrid.under(g, 100, -2, 100, 0, 0.5) == nil, "height")
		assert(PathGrid.under(g, 100, 4, 100, 0, 0, 5) ~= nil and PathGrid.under(g, 100, 40, 100, 0, 0, 5) == nil, "depth: a path far below a bridge does not count")
		assert(PathGrid.under(g, 300, 3, 300) == nil, "far away")
	end)

	test("path grid: the higher of two stacked layers wins, boxes span grid cells", function()
		local g = PathGrid.new(8)
		local low = PathGrid.box(0, 0.4, 0, 60, 0.2, 9, 1, 0, 0, 1)
		local high = PathGrid.box(0, 0.6, 0, 60, 0.2, 6, 1, 0, 0, 1)
		PathGrid.add(g, low)
		PathGrid.add(g, high)
		assert(PathGrid.under(g, 25, 2, 0) == high, "top layer")
		assert(PathGrid.under(g, 25, 2, 4) == low, "curb only")
		assert(PathGrid.under(g, -29, 2, 0) ~= nil and g.Count == 2, "far end, other cell")
	end)

	test("path grid: touches finds props by bounds and height", function()
		local g = PathGrid.new(16)
		PathGrid.add(g, PathGrid.box(10, 3, 10, 2, 6, 2, 1, 0, 0, 1)) -- a lamp post
		assert(PathGrid.touches(g, 9, 9, 12, 12, 0, 2.4), "flower box at the post")
		assert(not PathGrid.touches(g, 14, 14, 17, 17, 0, 2.4), "clear grass")
		assert(not PathGrid.touches(g, 9, 9, 12, 12, 7, 9), "above the post")
	end)

	test("path grid: exact overlap sees the grass beside a turned strip as free (bounds alone would block it)", function()
		local c = math.sqrt(0.5)
		local g = PathGrid.new(16)
		local strip = PathGrid.box(0, 0.2, 0, 60, 0.4, 6, c, -c, c, c) -- 60 x 6, turned 45 degrees
		PathGrid.add(g, strip)
		-- a 6.4 x 6.4 flower box 8 studs out from the strip's middle, square to the world
		local fx, fz = 8 * c, 8 * c
		assert(PathGrid.touches(g, fx - 3.2, fz - 3.2, fx + 3.2, fz + 3.2, -1, 5), "the bounds test blocks it")
		assert(PathGrid.touchesExact(g, fx, fz, 3.2, 3.2, -1, 5, 0) == nil, "the exact test does not")
		assert(PathGrid.touchesExact(g, 4 * c, 4 * c, 3.2, 3.2, -1, 5, 0) == strip, "a box on the strip edge is blocked")
		assert(PathGrid.touchesExact(g, fx, fz, 3.2, 3.2, -1, 5, 3) == strip, "a big margin reaches the strip")
		assert(PathGrid.touchesExact(g, fx, fz, 3.2, 3.2, 3, 5, 3) == nil, "height range")
	end)
	-- The real lobby (Studio dump near spawn, 2026-10-15, tests/fixtures/bloom/paths_dump.json): strips are short wide
	-- slabs (26 wide along X, ~3 long along Z) joined by 26 wide Cylinder discs whose axis points up; edge stones sit
	-- just outside the edge. Studio placed 0 flowers (path=1091) because spots were offset along the long axis.
	test("path grid: flower spots beside the real lobby paths land on grass, clear of every strip, disc and stone", function()
		local files = t.fixtures("bloom")
		local dump = t.json(assert(files["paths_dump.json"], "fixture missing"))
		local function boxOf(e)
			local c = e.cframe
			return PathGrid.fromComponents(c[1], c[2], c[3], e.size[1], e.size[2], e.size[3], { c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12] }, e.shape)
		end
		local paths, trim = PathGrid.new(16), PathGrid.new(16)
		local walkways = {}
		for _, e in dump.strips do
			local b = boxOf(e)
			PathGrid.add(paths, b)
			if not b.Round and math.max(b.HX, b.HZ) >= 2 then
				table.insert(walkways, b)
			end
			if e.shape == "Cylinder" then
				assert(b.Round == e.size[2] / 2, "a joint disc is round, radius 13")
			else
				assert(math.abs(b.HX - e.size[1] / 2) < 1e-6 and math.abs(b.HY - 0.05) < 1e-6, "a strip keeps its width and thin height")
			end
		end
		for _, e in dump.edgeStones do
			PathGrid.add(trim, boxOf(e))
		end
		assert(#walkways >= 20, "strips")
		local groundTop = 0.6
		local spots, stats = PathGrid.spots(walkways, paths, trim, {
			-- LobbyBloom's numbers (server/LobbyBloom: BOX 6, MARGIN 0.3, CLEAR, STEPS, SPACING, GRID, MAX)
			Half = 3, Height = 4.8, Margin = 0.3, Clear = 3.9, Spacing = 12, Steps = { 0, 0.75, 1.5, 2.5, 3.5, 5, 6.5, 8, 10 }, Cell = 10, Max = 140,
			Ground = function(_x, _z, _y)
				return groundTop
			end,
		})
		assert(#spots >= 25, ("only %d spots (path=%d trim=%d spaced=%d)"):format(#spots, stats.path or 0, stats.trim or 0, stats.spaced or 0))

		-- independent check: points over each flower box (grown by the 0.3 walkway margin) against every strip and disc in its own local
		-- space (straight from the dumped matrix, not through PathGrid), and the box itself against every stone
		local function inside(e, x, z, grow)
			local c = e.cframe
			local dx, dy, dz = x - c[1], groundTop + 0.5 - c[2], z - c[3]
			-- local = transpose(R) * d; R columns are the axes
			local lx = c[4] * dx + c[7] * dy + c[10] * dz
			local lz = c[6] * dx + c[9] * dy + c[12] * dz
			local ly = c[5] * dx + c[8] * dy + c[11] * dz
			if e.shape == "Cylinder" then
				-- axis is local X (vertical here): round in local Y / Z
				return ly * ly + lz * lz <= (e.size[2] / 2 + grow) ^ 2
			end
			return math.abs(lx) <= e.size[1] / 2 + grow and math.abs(lz) <= e.size[3] / 2 + grow
		end
		for _, sp in spots do
			for gx = -3.3, 3.3, 0.33 do
				for gz = -3.3, 3.3, 0.33 do
					local x, z = sp[1] + gx, sp[3] + gz
					for _, e in dump.strips do
						assert(not inside(e, x, z, 0), ("spot %.1f,%.1f touches a path"):format(sp[1], sp[3]))
					end
					if math.abs(gx) <= 3.01 and math.abs(gz) <= 3.01 then
						for _, e in dump.edgeStones do
							assert(not inside(e, x, z, 0), ("spot %.1f,%.1f touches an edge stone"):format(sp[1], sp[3]))
						end
					end
				end
			end
		end
		-- the clumps line the paths: most stand with their edge within 2 studs of the edge stones
		local lining = 0
		for _, sp in spots do
			for _, e in dump.strips do
				if inside(e, sp[1], sp[3], 3 + 0.9 + 2) then
					lining += 1
					break
				end
			end
		end
		assert(lining >= #spots * 0.7, ("only %d of %d clumps line a path"):format(lining, #spots))
		print(("  lobby dump: %d of %d flower spots line a path, from %d strips (path=%d trim=%d spaced=%d)"):format(lining, #spots, #walkways, stats.path or 0, stats.trim or 0, stats.spaced or 0))
	end)
end
