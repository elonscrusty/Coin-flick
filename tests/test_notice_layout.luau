-- Notification column decisions (shared/NoticeLayout, used by client/ui/UI).
return function(t)
	local test, shared = t.test, t.shared
	local N = shared("NoticeLayout")

	test("notice layout: one notice at most while a menu is open", function()
		assert(N.maxCards(true, 3) == 1 and N.maxCards(true, 2) == 1)
		assert(N.maxCards(false, 3) == 3 and N.maxCards(false, 2) == 2)
	end)

	test("notice layout: the column anchors top-right under the header when a menu fills the screen", function()
		assert(N.mode(true, false, 0) == "corner", "menu fills the width")
		assert(N.mode(true, false, N.SideMin - 1) == "corner", "gap too small")
		assert(N.mode(true, false, N.SideMin) == "side", "room beside the menu")
		assert(N.mode(false, false, 500) == "hud" and N.mode(false, true, 0) == "hud", "no menu: the HUD spot")
		assert(N.mode(true, true, 500) == "hud", "a dialog over the menu: kept clear of its bands")
	end)
end
