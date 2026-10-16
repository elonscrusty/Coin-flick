-- Touch keep-out zones (shared/SafeZones).
return function(t)
	local test, shared = t.test, t.shared
	local SZ = shared("SafeZones")
	local screens = { { 668, 383 }, { 678, 310 }, { 844, 390 }, { 390, 844 }, { 1108, 512 }, { 1366, 1024 } }

	test("safe zones: jump zone follows Roblox's small and big jump button", function()
		local z = SZ.jumpZone(668, 383)
		assert(z.w == 105 and z.h == 100 and z.x + z.w == 668 and z.y + z.h == 383, "small screen corner (95x90 + margin)")
		local b = SZ.jumpZone(1366, 1024)
		assert(b.w == 180 and b.h == 220, "tablet corner (170x210 + margin)")
		-- logical px: a 668x383 phone at UI scale 0.835 keeps the same real-px corner
		local w, h = SZ.jumpSize(668 / 0.835, 383 / 0.835, 0.835)
		assert(math.abs(w * 0.835 - 105) < 1e-6 and math.abs(h * 0.835 - 100) < 1e-6, "scaled back to real px")
		-- the real screen decides small vs big, not the logical size
		local w2 = SZ.jumpSize(1200, 700, 0.6) -- real 720x420: small
		assert(math.abs(w2 * 0.6 - 105) < 1e-6, "small by real px")
	end)

	test("safe zones: thumbstick zone is the lower left in landscape, the bottom in portrait", function()
		local z = SZ.thumbZone(1108, 512)
		assert(z.x == 0 and z.w == 1108 * 0.4 and z.y == 512 * 0.4 and z.y + z.h == 512, "landscape: left 40 %, bottom 60 %")
		local pz = SZ.thumbZone(390, 844)
		assert(pz.w == 390 and pz.y == 844 * 0.6, "portrait: full width, bottom 40 %")
		assert(SZ.inThumbZone({ x = 18, y = 300, w = 150, h = 50 }, 1108, 512), "a button low on the left blocks the stick")
		assert(not SZ.inThumbZone({ x = 18, y = 100, w = 600, h = 52 }, 1108, 512), "a row along the top does not")
	end)

	test("safe zones: lobby buttons leave the thumbstick zone on touch screens", function()
		local pc = SZ.lobbyLayout(1920, 1080, false, 172)
		assert(pc.Mode == "column" and pc.Cols == 1 and pc.CellW == 172, "computer: the column")
		local short = SZ.lobbyLayout(844, 390, false, 172)
		assert(short.Mode == "row", "a short mouse window (the Studio phone window) takes the row too")
		assert(SZ.lobbyLayout(1366, 768, false, 172).Mode == "column", "a laptop keeps the column")
		for _, s in { { 844, 390 }, { 1108, 512 }, { 678, 310 } } do
			local L = SZ.lobbyLayout(s[1], s[2], true, 172)
			assert(L.Mode == "row" and L.Cols == 5 and L.CellW >= 44 and L.CellW == L.CellH and (L.PlayW or 0) >= 96, "landscape phone: PLAY pill and four square tiles")
			-- the row (starting 14 px down, under the 40 px coin pill and a 6 px gap) ends above the zone
			local bottom = 14 + 40 + 6 + L.CellH
			assert(bottom < s[2] * 0.4, "row bottom " .. bottom .. " clears " .. s[2] * 0.4)
			-- the row stays inside the left half of the view, so the middle of the screen is clear
			assert(14 + SZ.rowWidth(L, 6) < s[1] * 0.5, "the row stays in the left half: " .. SZ.rowWidth(L, 6))
		end
		local up = SZ.lobbyLayout(390, 844, true, 172)
		assert(up.Mode == "grid" and up.Cols == 2 and up.CellW >= 83 and 2 * up.CellW + 6 <= 390 * 0.7, "upright phone: two columns inside two thirds of the width")
	end)

	test("safe zones: overlap check", function()
		local a = { x = 0, y = 0, w = 10, h = 10 }
		assert(SZ.overlaps(a, { x = 5, y = 5, w = 10, h = 10 }), "overlap")
		assert(not SZ.overlaps(a, { x = 10, y = 0, w = 5, h = 5 }), "touching edges do not overlap")
		assert(SZ.inJumpZone({ x = 600, y = 340, w = 50, h = 30 }, 668, 383), "inside corner")
		assert(not SZ.inJumpZone({ x = 400, y = 340, w = 50, h = 30 }, 668, 383), "left of corner")
	end)

	test("safe zones: touch bottom button clears the jump zone and the prompt band on every phone", function()
		for _, s in screens do
			local r = SZ.bottomButton(s[1], s[2], 62, 48, true)
			assert(not SZ.inJumpZone(r, s[1], s[2]), "jump zone at " .. s[1])
			local r2 = SZ.bottomButton(s[1] / 0.835, s[2] / 0.835, 62, 48, true, 0.835)
			assert(not SZ.inJumpZone(r2, s[1] / 0.835, s[2] / 0.835, 0.835), "scaled jump zone at " .. s[1])
			assert(not SZ.overlaps(r, SZ.promptBand(s[1], s[2])), "prompt band at " .. s[1])
			assert(r.x >= 0 and r.y >= 0 and r.x + r.w <= s[1] and r.y + r.h <= s[2], "on screen at " .. s[1])
		end
	end)

	test("safe zones: PC bottom button keeps its old spot", function()
		local r = SZ.bottomButton(1434, 658, 62, 48, false)
		assert(1434 - (r.x + r.w) == 184 and 658 - (r.y + r.h) == 40, "unchanged")
	end)

	test("safe zones: column limit sits above the jump zone", function()
		for _, s in screens do
			local z = SZ.jumpZone(s[1], s[2])
			assert(SZ.columnLimit(s[1], s[2]) + SZ.GAP == z.y, "limit " .. s[2])
		end
	end)
end
