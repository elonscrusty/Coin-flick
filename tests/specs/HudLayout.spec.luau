local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HudLayout = require(ReplicatedStorage.Shared.Util.HudLayout)

-- FredokaOne letters are about 0.55 of the text size wide (emoji ~1.2).
local function fittedTextSize(r, text, padding, lines)
	lines = lines or 1
	local chars = 0
	for _, c in utf8.codes(text) do
		chars += if c > 0x2600 then 1.2 else 0.55
	end
	local innerW = r.w * (1 - 2 * (padding or 0.05)) * lines
	local innerH = r.h * 0.8 / lines
	return math.min(innerH, innerW / chars)
end

-- Text with line breaks: the longest line decides the width.
local function fittedLines(r, text, padding)
	local lines = string.split(text, "\n")
	local best = math.huge
	for _, line in lines do
		best = math.min(best, fittedTextSize(r, line, padding, 1))
	end
	return math.min(best, r.h * 0.8 / #lines)
end

local function pieces(l)
	return {
		top = l.top,
		info = l.info,
		boost = l.boost,
		side = l.side,
		shout = l.shout,
		toast = l.toast,
		combo = l.combo,
		cheats = l.cheats,
	}
end

describe("HUD layout", function()
	it("every piece stays on screen", function()
		for _, sc in HudLayout.SCREENS do
			local l = HudLayout.compute(sc.w, sc.h, sc.touch)
			for name, r in pieces(l) do
				if not HudLayout.inside(r, sc.w, sc.h) then
					error(`{sc.name}: {name} off screen`)
				end
			end
		end
	end)

	it("no two HUD pieces overlap (0 overlaps)", function()
		for _, sc in HudLayout.SCREENS do
			local l = HudLayout.compute(sc.w, sc.h, sc.touch)
			local list = {}
			for name, r in pieces(l) do
				-- The rare banner and toasts share one message spot (a new one
				-- replaces the old), but never sit on anything else.
				table.insert(list, { name, r })
			end
			for i = 1, #list do
				for j = i + 1, #list do
					local a, b = list[i][1], list[j][1]
					local sharedSpot = (a == "shout" or a == "toast") and (b == "shout" or b == "toast")
					if not sharedSpot and HudLayout.overlaps(list[i][2], list[j][2]) then
						error(`{sc.name}: {list[i][1]} covers {list[j][1]}`)
					end
				end
			end
		end
	end)

	it("the table's coins, flips and giant coin have the middle to themselves", function()
		for _, sc in HudLayout.SCREENS do
			local l = HudLayout.compute(sc.w, sc.h, sc.touch)
			local zone = HudLayout.tableZone(sc.w, sc.h)
			-- cheats are Studio-only test buttons (and may sit in a bottom row)
			for name, r in pieces(l) do
				if name ~= "cheats" and HudLayout.overlaps(r, zone) then
					error(`{sc.name}: {name} sits on the table ({r.x},{r.y} {r.w}x{r.h})`)
				end
			end
		end
	end)

	it("the cash and hat pills sit left, never over the top-middle yard sign", function()
		for _, sc in HudLayout.SCREENS do
			local l = HudLayout.compute(sc.w, sc.h, sc.touch)
			expect(l.top.x + l.top.w).toBeAtMost(sc.w * 0.3)
		end
	end)

	it("a panel (even at its 1.1x pop-in peak) stays between the side bands", function()
		for _, sc in HudLayout.SCREENS do
			local l = HudLayout.compute(sc.w, sc.h, sc.touch)
			local p = l.panel
			-- UIScale 1.1 at the peak of the bounce
			local pop = { x = p.x - p.w * 0.05, y = p.y - p.h * 0.05, w = p.w * 1.1, h = p.h * 1.1 }
			for _, other in { "top", "info", "boost", "combo", "side" } do
				if HudLayout.overlaps(pop, l[other]) then
					error(`{sc.name}: panel pop-in touches {other}`)
				end
			end
			for _, button in l.sideButtons do
				expect(HudLayout.overlaps(pop, button)).toBeFalsy()
			end
			expect(pop.y).toBeAtLeast(l.reserved.menu.y + l.reserved.menu.h)
		end
	end)

	it("messages have their own spot: never on a pill, card, chip or button", function()
		for _, sc in HudLayout.SCREENS do
			local l = HudLayout.compute(sc.w, sc.h, sc.touch)
			for _, msg in { l.shout, l.toast } do
				expect(msg.h).toBeAtLeast(56)
				for _, other in { "top", "info", "boost", "combo", "side" } do
					if HudLayout.overlaps(msg, l[other]) then
						error(`{sc.name}: message spot sits on {other}`)
					end
				end
			end
		end
	end)

	it("pills have a gap, and the combo card is big enough to read", function()
		for _, sc in HudLayout.SCREENS do
			local l = HudLayout.compute(sc.w, sc.h, sc.touch)
			-- Hud.init: two pills (48% + 44% of the row) with an 8 px gap between
			expect(l.top.w * (1 - 0.48 - 0.44)).toBeAtLeast(8)
			expect(l.combo.h).toBeAtLeast(48)
			expect(l.combo.w).toBeAtLeast(90)
			local size = fittedLines(l.combo, "🔥 x99\nCOMBO", 0.05)
			expect(size).toBeAtLeast(HudLayout.MIN_TEXT)
		end
	end)

	it("nothing covers Roblox's menu, jump button or thumbstick", function()
		for _, sc in HudLayout.SCREENS do
			local l = HudLayout.compute(sc.w, sc.h, sc.touch)
			for name, r in pieces(l) do
				for rname, rr in l.reserved do
					if HudLayout.overlaps(r, rr) then
						error(`{sc.name}: {name} covers Roblox {rname}`)
					end
				end
			end
		end
	end)

	it("panels and the low toast fit between the controls", function()
		for _, sc in HudLayout.SCREENS do
			local l = HudLayout.compute(sc.w, sc.h, sc.touch)
			for _, key in { "panel", "toastLow" } do
				local r = l[key]
				if not HudLayout.inside(r, sc.w, sc.h) then
					error(`{sc.name}: {key} off screen`)
				end
				for name, other in l.reserved do
					-- Touch controls hide while a panel is open (Hud), so a
					-- panel may reach over the thumbstick; never the top bar.
					local hidden = key == "panel" and (name == "thumbstick" or name == "jump")
					if not hidden and HudLayout.overlaps(r, other) then
						error(`{sc.name}: {key} covers Roblox {name}`)
					end
				end
				for _, name in { "side", "cheats", "combo" } do
					if key == "toastLow" and HudLayout.overlaps(r, l[name]) then
						error(`{sc.name}: toastLow covers {name}`)
					end
				end
			end
			expect(HudLayout.overlaps(l.panel, l.side)).toBeFalsy()
			expect(HudLayout.overlaps(l.panel, l.toastLow)).toBeFalsy()
			expect(l.panel.h).toBeAtLeast(190)
			expect(l.panel.w).toBeAtLeast(270)
			expect(fittedTextSize(l.toastLow, "Reset 3 times to meet King Flip!", nil, 2)).toBeAtLeast(
				HudLayout.MIN_TEXT
			)
		end
	end)

	it("side buttons are thumb sized and don't touch each other", function()
		for _, sc in HudLayout.SCREENS do
			local l = HudLayout.compute(sc.w, sc.h, sc.touch)
			expect(#l.sideButtons).toBe(4)
			for i, b in l.sideButtons do
				expect(b.w).toBeAtLeast(HudLayout.MIN_TOUCH)
				expect(b.h).toBeAtLeast(HudLayout.MIN_TOUCH)
				for j = i + 1, 4 do
					expect(HudLayout.overlaps(b, l.sideButtons[j])).toBeFalsy()
				end
			end
		end
	end)

	it("longest HUD text still fits big enough to read", function()
		local longest = {
			info = "Heads = $999K\nLuck 100%",
			boost = "⚡ 2x  9:59",
			mega = "🌟 999/999",
			shout = "⭐ SomeLongName20Char flipped a GIANT coin! +$999K ⭐",
			toast = "Fill your table first! (24/25 coins)",
		}
		for _, sc in HudLayout.SCREENS do
			local l = HudLayout.compute(sc.w, sc.h, sc.touch)
			for key, text in longest do
				local rect = if key == "mega" then l.boost else l[key]
				local size = if key == "info"
					then fittedLines(rect, text)
					else fittedTextSize(rect, text, nil, if key == "shout" or key == "toast" then 3 else 1)
				if size < HudLayout.MIN_TEXT then
					error(`{sc.name}: {key} text only {size}px`)
				end
			end
			-- Cash pill is 48% of the pill row, hat pill 44% (Hud.init)
			local cash = { w = l.top.w * 0.48, h = l.top.h }
			expect(fittedTextSize(cash, "$999.9K", 0.07)).toBeAtLeast(16)
			local hat = { w = l.top.w * 0.44, h = l.top.h }
			expect(fittedTextSize(hat, "🎩 999K", 0.07)).toBeAtLeast(HudLayout.MIN_TEXT)
		end
	end)

	it("handles odd screen sizes without breaking", function()
		for _, size in { { 568, 320 }, { 2560, 1440 }, { 800, 600 } } do
			local l = HudLayout.compute(size[1], size[2], true)
			expect(l.top.w).toBeAtLeast(100)
			expect(l.sideButtons[1].w).toBeAtLeast(HudLayout.MIN_TOUCH)
		end
	end)
end)
