-- HUD left column fit rule (shared/ColumnFit).
return function(t)
	local test, shared = t.test, t.shared
	local CF = shared("ColumnFit")

	test("column fit: tall screens keep the max size in one column", function()
		local f = CF.fit(900, 6, 6, 40, 56)
		assert(f.size == 56 and f.cols == 1, "unchanged")
	end)

	test("column fit: 310 and 390 px phones shrink the tiles to fit, one column", function()
		for _, h in { 290, 370 } do
			local f = CF.fit(h, 6, 6, 40, 56)
			assert(f.cols == 1, "one column at " .. h)
			assert(f.size >= 40 and f.size <= 56, "size in range at " .. h)
			assert(6 * f.size + 5 * 6 <= h + 1e-6, "fits at " .. h)
		end
		assert(CF.fit(290, 6, 6, 40, 56).size < 56, "290 shrinks")
	end)

	test("column fit: too short at the minimum wraps to more columns, never below min", function()
		local w = CF.fit(150, 6, 6, 40, 56)
		assert(w.cols >= 2 and w.size >= 40, "wraps, min kept")
		assert(CF.fit(10, 5, 6, 40, 56).size == 40, "never below min")
		assert(CF.fit(100, 0, 6, 40, 56).cols == 1, "empty column")
	end)
end
