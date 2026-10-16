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
				table.insert(list, { name, r })
			end
			for i = 1, #list do
				for j = i + 1, #list do
					if HudLayout.overlaps(list[i][2], list[j][2]) then
						error(`{sc.name}: {list[i][1]} covers {list[j][1]}`)
					end
				end
			end
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
			expect(l.panel.h).toBeAtLeast(210)
			expect(l.panel.w).toBeAtLeast(300)
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
			info = "Heads = $999K  •  🍀 80% luck  •  🪙 25/25",
			boost = "🌟 Mega coin 999/999  •  tap it together!",
			shout = "⭐ SomeLongName20Char flipped a GIANT coin! +$999K ⭐",
			toast = "Fill your table first! (24/25 coins)",
		}
		for _, sc in HudLayout.SCREENS do
			local l = HudLayout.compute(sc.w, sc.h, sc.touch)
			for key, text in longest do
				local size = fittedTextSize(l[key], text, nil, if key == "shout" or key == "toast" then 2 else 1)
				if size < HudLayout.MIN_TEXT then
					error(`{sc.name}: {key} text only {size}px`)
				end
			end
			-- Cash pill is 58% of the top bar, holds "$999.9K" at 40px max
			local cash = { w = l.top.w * 0.58, h = l.top.h }
			expect(fittedTextSize(cash, "$999.9K", 0.08)).toBeAtLeast(18)
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
