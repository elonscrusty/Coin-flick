-- UI juice numbers (shared/UiMotion, used by client/ui/Juice and UI).
return function(t)
	local test, shared = t.test, t.shared
	local M = shared("UiMotion")
	local Vector2 = t.Vector2

	test("ui motion: reduced motion (game or system setting) turns effects off", function()
		assert(M.animate(false, false) == true and M.animate(nil, nil) == true)
		assert(M.animate(true, false) == false, "game setting")
		assert(M.animate(false, true) == false, "system setting")
	end)

	test("ui motion: count-up steps rise, never overshoot and end on the target", function()
		local s = M.countSteps(100, 250, 15)
		assert(#s == 15 and s[15] == 250, "ends on target")
		for i = 2, #s do
			assert(s[i] >= s[i - 1], "monotonic up")
			assert(s[i] >= 100 and s[i] <= 250, "inside the range")
		end
		assert(s[1] > 100, "first frame already moves")
		assert(s[4] - 100 > (250 - 100) * 0.4, "ease out: most of the way early")
	end)

	test("ui motion: counter counts down too, and same value stays", function()
		local s = M.countSteps(500, 120, 10)
		assert(s[10] == 120)
		for i = 2, #s do
			assert(s[i] <= s[i - 1] and s[i] >= 120 and s[i] <= 500)
		end
		assert(M.countValue(7, 7, 0.5) == 7 and M.countValue(0, 10, 2) == 10 and M.countValue(0, 10, -1) == 0)
	end)

	test("ui motion: coin arc starts and ends on the points and bows upward", function()
		local a, b = Vector2.new(100, 300), Vector2.new(700, 40)
		local p = M.arcPath(a, b, 60, 10)
		assert(#p == 11)
		assert((p[1] - a).Magnitude < 1e-6 and (p[11] - b).Magnitude < 1e-6, "ends")
		local mid = M.arcPoint(a, b, 60, 0.5)
		local straight = (a + b) / 2
		assert(mid.Y < straight.Y, "above the straight line (screen y down)")
		for i = 2, #p do
			assert(p[i].X > p[i - 1].X, "moves steadily toward the target")
		end
		local c = M.arcControl(a, b, 60)
		assert(c.Y < math.min(a.Y, b.Y), "control point above both ends")
		assert(M.arcPoint(a, b, 60, 5) == b and M.arcPoint(a, b, 60, -1) == a, "t clamps")
	end)

	test("ui motion: coin count grows with the reward, 3 to 6", function()
		assert(M.coinCount(0) == 3 and M.coinCount(5) == 3 and M.coinCount(50) == 3)
		assert(M.coinCount(500) == 4 and M.coinCount(5000) == 5 and M.coinCount(1e9) == 6)
	end)

	test("ui motion: tab content slides in from the tapped tab's side", function()
		assert(M.slideFrom(1, 3, 24) == 24, "tab to the right: from the right")
		assert(M.slideFrom(3, 1, 24) == -24, "tab to the left: from the left")
		assert(M.slideFrom(2, 2, 24) == 0 and M.slideFrom(nil, 2, 24) == 0)
	end)

	test("ui motion: scroll canvas holds every card plus padding and a gap", function()
		-- three quest cards of 96 with 8 gaps (list content 304), padding 6 / 6, one gap under the last card
		local content = 3 * 96 + 2 * 8
		local h = M.canvasHeight(content, 6, 6, 8)
		assert(h == 324, tostring(h))
		assert(h >= content + 12, "every card reachable")
		assert(M.canvasHeight(10.2, 0, 0) == 11 and M.canvasHeight(-50, 0, 0) == 0)
	end)

	test("ui motion: fresh pets are the ones added since the last look", function()
		local known, fresh = M.freshIds(nil, { "a", "b" })
		assert(#fresh == 0 and known.a and known.b, "first look: nothing is new")
		local k2, f2 = M.freshIds(known, { "a", "b", "c", "d" })
		assert(#f2 == 2 and f2[1] == "c" and f2[2] == "d")
		local _, f3 = M.freshIds(k2, { "b", "d" })
		assert(#f3 == 0, "selling is not new")
	end)
end
