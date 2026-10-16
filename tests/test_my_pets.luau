-- MY PETS screen (shared/MyPetsLayout + the team swap rule): every piece inside the panel, nothing overlaps, the big
-- pet picture stays big, buttons stay tappable, and a full team never swaps a pet without the player's pick.
return function(t)
	local test, shared = t.test, t.shared
	local L = shared("MyPetsLayout")
	local PetRules = shared("PetRules")

	local function inside(a, b, msg)
		assert(a.x >= b.x - 0.01 and a.y >= b.y - 0.01 and a.x + a.w <= b.x + b.w + 0.01 and a.y + a.h <= b.y + b.h + 0.01, msg)
	end
	local function overlaps(a, b): boolean
		return a.x < b.x + b.w - 0.01 and b.x < a.x + a.w - 0.01 and a.y < b.y + b.h - 0.01 and b.y < a.y + a.h - 0.01
	end
	local function apart(names, lay, msg)
		for i = 1, #names do
			for j = i + 1, #names do
				assert(not overlaps(lay[names[i]], lay[names[j]]), msg .. ": " .. names[i] .. " overlaps " .. names[j])
			end
		end
	end

	-- panel sizes in logical px (UI.scaleFor never goes under 0.8, so a landscape phone panel is about 370-410 tall):
	-- PC, big and small landscape phones (844 x 390 reference), upright phones
	local PANELS = { { 900, 500 }, { 900, 380 }, { 900, 350 }, { 834, 400 }, { 760, 372 }, { 370, 700 }, { 350, 620 }, { 370, 500 }, { 340, 500 } }

	test("my pets: every piece inside the panel, no overlaps, big picture, tappable buttons on every size", function()
		for _, sz in PANELS do
			local w, h = sz[1], sz[2]
			local tag = w .. "x" .. h
			local lay = L.layout(w, h)
			local panel = { x = 0, y = 0, w = w, h = h }
			for _, n in L.Top do
				assert(lay[n], tag .. ": " .. n .. " placed")
				inside(lay[n], panel, tag .. ": " .. n .. " inside the panel")
			end
			local tops = table.clone(L.Top)
			if (h > w and h < L.ShortPortrait) or (w > h and h < L.Compact) then
				-- short phones: EQUIP BEST sits inside the team strip, clear of the words and slots
				inside(lay.EquipBest, lay.Team, tag .. ": EQUIP BEST inside the team strip")
				apart({ "EquipBest", "TeamLabel", "Slot1", "Slot2", "Slot3" }, lay, tag)
				table.remove(tops, table.find(tops, "Team"))
			end
			apart(tops, lay, tag)
			for _, n in L.Inner do
				assert(lay[n], tag .. ": " .. n .. " placed")
				inside(lay[n], lay.Detail, tag .. ": " .. n .. " inside the pet panel")
			end
			local inner = table.clone(L.Inner)
			if lay.Roles then
				table.insert(inner, "Roles")
				assert(lay.Roles.w >= 100, tag .. ": room for the ON TEAM chip")
			end
			apart(inner, lay, tag)
			local team = { "TeamLabel", "Slot1", "Slot2", "Slot3" }
			for _, n in team do
				inside(lay[n], lay.Team, tag .. ": " .. n .. " inside the team strip")
			end
			apart(team, lay, tag)
			assert(lay.TeamLabel.w >= 90, tag .. ": room for YOUR TEAM")
			assert(lay.Slot1.w >= 50, tag .. ": team slots big enough to see the pet")
			for _, n in { "Close", "Action", "Display", "Fav", "EquipBest", "Search", "Sort", "Count" } do
				assert(lay[n].h >= 36, tag .. ": " .. n .. " tall enough to tap")
			end
			assert(lay.Fav.w >= 36 and lay.Display.w >= 70 and lay.Action.w >= 90, tag .. ": buttons wide enough")
			assert(lay.Preview.h >= (if w > h and h <= 360 then 80 elseif w > h and h < L.Compact then 84 elseif h > w and h < L.ShortPortrait then 76 else 110) and lay.Preview.w >= 90, tag .. ": the big pet picture stays big " .. lay.Preview.h)
			local cols, cw, ch = L.cards(lay.Grid.w, 8, lay.Grid.h)
			assert(cols >= 2 and cw >= 90 and ch >= 72, tag .. ": cards readable " .. cw .. "x" .. ch)
			if w > h then
				assert(cols == 3, tag .. ": three columns across the whole width")
			end
			local used = cols * cw + (cols - 1) * L.Gap + 8 + 2 * L.GridPad.Side
			assert(lay.Grid.w - used < cols + 2, tag .. ": no blank strip on the right (" .. (lay.Grid.w - used) .. ")")
			local rows = (lay.Grid.h - L.GridPad.Top) / (ch + L.Gap)
			assert(rows >= (if h > w and h < L.ShortPortrait then 1.3 else 1.5), tag .. ": more than one row of cards shows (" .. rows .. ")")
			if w > h then
				assert(rows >= 1.95, tag .. ": two full rows on a big screen (" .. rows .. ")")
			end
			assert(ch <= cw * L.CardAspect + 0.5, tag .. ": cards never taller than the art")
			local eb = lay.EquipBest
			assert(lay.Grid.y + lay.Grid.h <= eb.y - L.Gap + 0.01 or eb.y + eb.h <= lay.Grid.y, tag .. ": the grid never runs under EQUIP BEST")
			local db = L.detailBorder(lay.Detail)
			for _, n in { "Action", "Display", "Fav" } do
				assert(lay[n].y + lay[n].h <= lay.Detail.y + lay.Detail.h - db - 4.99, tag .. ": " .. n .. " clear of the frame's bottom edge")
			end
			if w > h then
				local cut = lay.Detail.x + L.detailBorder(lay.Detail) + 5 + (lay.Detail.w - 2 * (L.detailBorder(lay.Detail) + 5)) * L.CornerClear
				assert(lay.Name.x >= cut - 0.5, tag .. ": the name starts clear of the frame's slanted corner")
				assert(lay.Roles == nil or lay.Roles.x >= cut - 0.5, tag .. ": the chips start clear of the corner")
			end
			assert(lay.Power.h >= 26 and lay.Name.h >= 26, tag .. ": big name and POWER")
		end
	end)

	test("my pets art: every frame picture is listed, measured and cut inside its own pixels", function()
		local A = shared("MyPetsArt")
		assert(#A.Order == 15, "fifteen pictures")
		for _, n in A.Order do
			local p = A.Pieces[n]
			assert(p and p.W > 0 and p.H > 0 and p.W <= 1024 and p.H <= 1024, n .. " size")
			assert(p.Id == 0 or p.Id > 0, n .. " id")
			local x0, y0, x1, y1 = A.slice(p)
			assert(x0 > 0 and y0 > 0 and x1 < p.W and y1 < p.H and x0 < x1 and y0 < y1, n .. " slice inside the picture")
			if p.Inset then
				for _, v in p.Inset do
					assert(v > 0.05 and v < 0.25, n .. " opening measured")
				end
				local k = A.scaleFor(p, 12)
				local l = A.opening(p, k)
				assert(math.abs(l - 12) < 0.6, n .. " border drawn at the asked width")
			end
			if p.Id == 0 then
				assert(A.get(n) == nil, n .. " not uploaded = drawn fallback")
			end
		end
		assert(A.cardKey("Legendary") == "CardLegendary" and A.cardKey("Epic", true) == "CardVoid" and A.cardKey("Weird") == "CardCommon", "card frame per rarity")
	end)

	test("my pets: a full team swaps only the slot the player picked", function()
		assert(PetRules.swapSlot(nil, 3) == nil, "no pick: no swap")
		assert(PetRules.swapSlot(0, 3) == nil and PetRules.swapSlot(4, 3) == nil, "out of range")
		assert(PetRules.swapSlot(1.5, 3) == nil and PetRules.swapSlot("2", 3) == nil and PetRules.swapSlot(0 / 0, 3) == nil, "junk")
		assert(PetRules.swapSlot(2, 3) == 2, "the picked slot")
	end)
end
