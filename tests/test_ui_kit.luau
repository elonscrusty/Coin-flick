-- Polygon Adventure UI kit (shared/UiKit): real ids from the owner's uploads, the kit's 9-slice margins, and the
-- fallback (an entry set to id 0 keeps the drawn look).
return function(t)
	local test, shared = t.test, t.shared
	local K = shared("UiKit")
	local Vector2 = t.Vector2

	local function zeroed(): { [string]: any }
		local z = {}
		for name, e in K.Entries do
			local c = table.clone(e)
			c.Id = "rbxassetid://0"
			z[name] = c
		end
		return z
	end

	test("ui kit: 33 pictures, each with a real id, 1x size = half the 2x pixels", function()
		local n = 0
		for name, e in K.Entries do
			n += 1
			assert(K.hasId(e.Id), name .. " has no id")
			assert(string.match(e.Id, "^rbxassetid://%d+$"), name)
			assert(e.Size == e.Pixels / 2, name .. " 1x size")
		end
		assert(n == 33, "33 kit pictures, got " .. n)
		assert(K.Entries.button_green.Id == "rbxassetid://85239779404293" and K.Entries.icon_coin.Id == "rbxassetid://78474630929064")
		assert(K.Entries.panel_large.Pixels == Vector2.new(527, 410) and K.Entries.tab.Pixels == Vector2.new(207, 99))
	end)

	test("ui kit: slice centres follow slices.json (Rect(L, T, W-R, H-B))", function()
		local function check(name: string, l: number, r: number, tt: number, b: number)
			local e = K.Entries[name]
			local c = e.SliceCenter
			assert(c.Min.X == l and c.Min.Y == tt and c.Max.X == e.Pixels.X - r and c.Max.Y == e.Pixels.Y - b, name)
			local s = K.skinFor(name)
			local ml, mt, mr, mb = K.margins(s)
			assert(ml == l and mt == tt and mr == r and mb == b, name .. " margins round trip")
			assert(c.Min.X < c.Max.X and c.Min.Y < c.Max.Y, name .. " centre not empty")
		end
		check("panel_large", 84, 84, 84, 95)
		check("panel_small", 84, 84, 84, 95)
		check("card", 54, 54, 54, 61)
		check("card_selected", 54, 54, 54, 61)
		for _, c in { "blue", "coral", "green", "yellow" } do
			check("button_" .. c, 47, 47, 35, 50)
			check("button_" .. c .. "_pressed", 47, 47, 35, 50)
		end
		check("tab", 40, 40, 40, 14)
		check("tab_active", 40, 40, 40, 14)
		check("coin_pill", 84, 46, 36, 40)
		check("progress_bg", 36, 36, 33, 33)
		check("progress_fill", 36, 36, 33, 33)
		for _, r in { "common", "uncommon", "rare", "epic", "legendary", "void" } do
			check("rarity_" .. r, 49, 49, 49, 56)
		end
		for _, p in { "icon_coin", "icon_star", "badge_dot", "close_x" } do
			assert(K.skinFor(p).ScaleType == "Fit", p .. " is drawn whole")
		end
	end)

	test("ui kit: slice scale draws corners at 1x and shrinks them on small pieces", function()
		local s = K.skinFor("button_green")
		assert(K.sliceScale(s, 200, 60) == 0.5, "a normal button: 1x corners")
		-- a 40 tall button: top + bottom corners (35 + 50) must fit 40 -> 40/85
		assert(math.abs(K.sliceScale(s, 200, 40) - 40 / 85) < 1e-9)
		local f = K.skinFor("progress_fill")
		assert(math.abs(K.sliceScale(f, 20, 12) - 12 / 66) < 1e-9, "a thin bar")
		assert(K.sliceScale(f, 0, 0) == 0.5, "unknown size: 1x")
	end)

	test("ui kit: styles, cards and pressed pictures map onto the kit", function()
		assert(K.buttonKey("gold") == "button_yellow" and K.buttonKey("green") == "button_green")
		assert(K.buttonKey("red") == "button_coral" and K.buttonKey("gray") == nil and K.buttonKey("blue") == "button_blue")
		assert(K.buttonKey(nil) == nil and K.buttonKey("nope") == nil)
		assert(K.cardKey(true, "Epic") == "card_selected" and K.cardKey(false, "Epic") == "rarity_epic")
		assert(K.cardKey(false, nil) == "card" and K.cardKey(false, "Mythic") == "rarity_void")
		local s = K.skinFor("button_coral")
		assert(s.Image == "rbxassetid://108639924673709" and s.Pressed == "rbxassetid://88633559143079" and s.ScaleType == "Slice")
		assert(K.skinFor("panel_large").Pressed == nil)
	end)

	test("ui kit: an entry set to id 0 falls back to the drawn look", function()
		local z = zeroed()
		for name in K.Entries do
			assert(K.skinFor(name, z) == nil, name)
		end
		assert(K.skinFor("no_such_piece") == nil and K.skinFor(nil) == nil)
		-- only the pressed picture missing: the button still skins, without a pressed swap
		local half = table.clone(K.Entries)
		half.button_green_pressed = z.button_green_pressed
		local s = K.skinFor("button_green", half)
		assert(s ~= nil and s.Pressed == nil)
		assert(not K.hasId("rbxassetid://0") and not K.hasId("") and not K.hasId(nil))
	end)

	test("ui kit: secondary (gray) buttons have no kit picture, primaries do", function()
		assert(K.buttonKey("gray") == nil, "gray is drawn flat, never the kit blue")
		for _, st in { "gold", "green", "red", "blue" } do
			assert(K.buttonKey(st) ~= nil, st)
		end
	end)

	test("ui kit: panel lip cropped so the rim is even on all four sides", function()
		local s = K.skinFor("panel_large")
		local size, c = K.crop(s)
		assert(size == Vector2.new(527, 410 - 11), "11 px lip cropped off the bottom")
		local l, tt, r, b = K.drawnMargins(s)
		assert(l == 84 and r == 84 and tt == 84 and b == 84, "even rim " .. l .. "," .. tt .. "," .. r .. "," .. b)
		assert(c.Max.Y == size.Y - 84)
		-- pieces without a lip are drawn whole
		local bs = K.skinFor("button_green")
		local bsize, bc = K.crop(bs)
		assert(bsize == bs.Pixels and bc == bs.SliceCenter)
	end)

	test("ui kit: slice scale clamp per element (corners never overlap or stretch)", function()
		local card = K.skinFor("card")
		-- min(0.5, h / (T + B), w / (L + R)) on the drawn margins
		assert(K.fitScale(card, 200, 200) == 0.5)
		assert(K.fitScale(card, 200, 80) == 0.5, "80 tall holds 1x corners (57.5)")
		assert(math.abs(K.fitScale(card, 200, 50) - 50 / 115) < 1e-9, "a short card shrinks its corners")
		assert(math.abs(K.fitScale(card, 40, 200) - 40 / 108) < 1e-9, "a narrow card")
		for _, sz in { { 30, 30 }, { 50, 120 }, { 400, 40 }, { 90, 64 } } do
			local w, h = sz[1], sz[2]
			local sc = K.fitScale(card, w, h)
			local l, tt, r, b = K.drawnMargins(card)
			assert((l + r) * sc <= w + 1e-9 and (tt + b) * sc <= h + 1e-9, "corners fit " .. w .. "x" .. h)
			assert(sc <= 0.5, "never above 1x corners")
		end
		local p = K.skinFor("panel_large")
		assert(K.fitScale(p, 700, 380, 0.4) == 0.4, "a cap below 0.5")
		assert(math.abs(K.fitScale(p, 700, 60) - 60 / 168) < 1e-9, "panel uses the cropped (even) margins")
		assert(K.panelCap(600) == 0.5 and K.panelCap(450) == 0.5 and K.panelCap(390) == 0.35 and K.panelCap(315) == 0.35)
		assert(math.abs(K.panelCap(420) - 0.425) < 1e-9)
	end)

	test("ui kit: a portrait card does not fit a wide bar (no stretched stripe)", function()
		local card = K.skinFor("card")
		assert(K.fits(card, 90, 100), "a grid tile fits")
		assert(not K.fits(card, 330, 64), "an Upgrades row (wide bar) keeps the drawn look")
		assert(K.fits(card, 0, 0), "unknown size fits")
		assert(K.fits(K.skinFor("button_green"), 400, 40), "buttons stretch sideways by design")
		assert(K.fits(K.skinFor("panel_large"), 900, 200))
	end)

	test("ui kit: panel content rect is inside the rim, equal top and bottom", function()
		local p = K.skinFor("panel_large")
		local l, tt, r, b = K.contentInset(p, 0.5)
		assert(l == math.floor(84 * 0.5 * K.RIM_SHARE) and l == r and tt == b and tt == l, "even insets")
		local l2 = K.contentInset(p, 0.35)
		assert(l2 < l, "smaller corners, smaller inset")
	end)

	test("ui kit: text floor is 14 px and light text gets a 2 px outline", function()
		local Color3 = t.Color3
		local hi, lo = K.textRange(10)
		assert(hi == 14 and lo == 14, "a 10 px design becomes 14")
		hi, lo = K.textRange(20, 10)
		assert(hi == 20 and lo == 14, "shrinks no lower than 14")
		hi, lo = K.textRange(30, 18)
		assert(hi == 30 and lo == 18)
		hi, lo = K.textRange(16, 40)
		assert(hi == 16 and lo == 16, "min never above max")
		assert(K.isLight(Color3.new(1, 1, 1)) and K.isLight(Color3.fromRGB(255, 247, 224)))
		assert(not K.isLight(Color3.fromRGB(22, 52, 112)) and not K.isLight(Color3.fromRGB(70, 44, 20)))
		assert(K.outlineFor(Color3.new(1, 1, 1), 1.4) == 2, "light text: at least 2")
		assert(K.outlineFor(Color3.new(1, 1, 1), nil) == 2, "light text with none designed: 2")
		assert(K.outlineFor(Color3.new(1, 1, 1), 3) == 3, "a heavier design stays")
		assert(K.outlineFor(Color3.fromRGB(22, 52, 112), 0) == 0, "dark text keeps none")
	end)

	test("ui kit: text floor is also 12 REAL px at the current UIScale", function()
		assert(K.floorFor(1) == 14 and K.floorFor(2) == 14, "big scales keep the 14 logical floor")
		assert(K.floorFor(0.6) == 20, "12 / 0.6 = 20 logical px")
		assert(K.floorFor(0.8) == 15)
		assert(K.floorFor(0.05) == K.MaxFloorText, "a tiny scale is capped")
		local hi, lo = K.textRange(14, nil, 0.6)
		assert(lo == 20 and hi == 20, "a 14 design lifts to 20 logical (12 real) at scale 0.6")
		assert(math.ceil(lo * 0.6 - 1e-6) >= 12)
		hi, lo = K.textRange(24, 14, 0.6)
		assert(hi == 24 and lo == 20, "own max kept when it already clears the floor")
		hi, lo = K.textRange(18, 14, 1)
		assert(hi == 18 and lo == 14, "scale 1 changes nothing")
		hi, lo = K.textRange(18, 14)
		assert(hi == 18 and lo == 14, "no scale: the old logical floor")
		for _, sc in { 0.6, 0.7, 0.8, 1, 1.3 } do
			local _, l = K.textRange(10, nil, sc)
			assert(l * sc >= 12 - 1e-6 or l == K.MaxFloorText, "real px floor at " .. sc)
		end
	end)

	test("ui kit: modal headers keep an 8 px margin under the top bar", function()
		assert(K.SafeTopMargin == 8)
		-- 1434 x 658: 36 px inset at scale 0.6 is 60 logical, + overhang 20 + 8
		assert(K.safeTop(36, true, 0.6, 20, K.SafeTopMargin) == 88)
		assert(K.safeTop(36, true, 0.6, 20, K.SafeTopMargin) - K.safeTop(36, true, 0.6, 20, 2) == 6, "6 px more than before")
	end)

	test("ui kit: safe-area top offset for modal headers", function()
		-- layer below the top bar already (IgnoreGuiInset false): only the tab overhang and margin count
		assert(K.safeTop(58, false, 1.3, 28, 0) == 28)
		-- a layer that ignores the inset: the 58 px top bar in logical px comes on top
		assert(K.safeTop(58, true, 1, 28, 2) == 88)
		assert(K.safeTop(58, true, 2, 0, 0) == 29)
		-- a kit panel whose content rect already sits lower than the tab rises: no negative overhang
		assert(K.safeTop(0, false, 1, -10, 4) == 4)
	end)

	test("ui kit: a scroll window ends on a whole row", function()
		-- rows ending at 64, 136, 208, 280; window 250 tall cuts the fourth row: shorten by 42 to end at 208
		assert(K.snapCut({ 64, 136, 208, 280 }, 250) == 42)
		assert(K.snapCut({ 64, 136, 208 }, 250) == 0, "everything fits")
		assert(K.snapCut({ 300 }, 250) == 0, "no row ends inside the window")
		assert(K.snapCut({ 20, 400 }, 250) == 0, "a cut over a third of the window is not worth it")
		assert(K.snapCut({ 208, 64, 280, 136 }, 250) == 42, "any order")
		-- a row more than half in view stays (the quest list: heading at 192, first card 200..262, window 233)
		assert(K.snapCut({ 192, 262 }, 233, nil, { 33, 62 }) == 0, "a card over half in view is kept")
		assert(K.snapCut({ 192, 262 }, 215, nil, { 33, 62 }) == 23, "a card under half in view is cut away")
	end)
	test("ui kit: daily star sits inside its tile and modal scroll bodies keep a scroll bar gap", function()
		local fs = require("@lune/fs")
		local q = fs.readFile("src/client/ui/QuestPanel.luau")
		local x, ys = string.match(q, 'Name = "Star", AnchorPoint = Vector2.new%(1, 0.5%), Position = UDim2.new%(1, (%-?%d+), ([%d.]+), 0%)')
		assert(x and ys, "day 7 star found")
		local yScale = tonumber(ys) :: number
		assert(tonumber(x) <= 0 and yScale > 0.3 and yScale < 0.7, "star inside the tile beside the coin, clear of the corner and the day label")
		local u = fs.readFile("src/client/ui/UI.luau")
		assert(string.find(u, "bodyPad.PaddingRight = UDim.new(0, T.Pad + UI.ScrollBar)", 1, true), "scroll bar gap in UI.modal")
	end)
	test("ui kit: a panel's fill never reaches above the rim (no white strip over a header on the rim)", function()
		local K = shared("UiKit")
		assert(K.backingTop(0, 18) == 18, "header on rim: fill starts under the rim")
		assert(K.backingTop(18, 18) == 0, "padded panel: fill fills the content rect")
	end)
end
