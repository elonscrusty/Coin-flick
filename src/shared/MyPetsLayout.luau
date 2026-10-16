--!strict
-- MY PETS screen layout (carter's low-poly reference, 2026-10-15): where each piece sits inside the menu panel, in
-- LOGICAL px of the panel (origin top left). Pure, so every screen size is tested offline (tests/test_my_pets.luau).
--   landscape: title + red X on top (short phones: YOUR TEAM on the title row, the title over the pet panel); YOUR TEAM (3 slots) over the toolbar (count, search, sort) and the scrolling
--   pet grid, EQUIP BEST under it; the selected pet's big panel on the right.
--   upright phone: the same pieces stacked; the selected pet's panel sits between the team and the grid (picture
--   left, numbers and buttons right).

local MyPetsLayout = {}

export type Rect = { x: number, y: number, w: number, h: number }
export type Layout = { [string]: Rect }

MyPetsLayout.Pad = 16 -- inside the main frame's border (MyPetsLayout.Border)
MyPetsLayout.Gap = 6
MyPetsLayout.CardAspect = 0.9 -- tallest card height / width (the art cards are near square)
MyPetsLayout.CardFlat = 0.6 -- flattest card height / width (the frames are nine-sliced, so they stay crisp)
MyPetsLayout.Compact = 430
MyPetsLayout.CornerClear = 0.14 -- share of the pet panel width the frame's slanted top-left corner covers
MyPetsLayout.ShortPortrait = 600 -- upright panels shorter than this put EQUIP BEST in the team strip -- landscape panels shorter than this put the team strip on the title row

-- the pieces the panel builds (the test checks them all)
MyPetsLayout.Top = { "Title", "Close", "Team", "Count", "Search", "Sort", "Grid", "EquipBest", "Detail" }
MyPetsLayout.Inner = { "Name", "Badge", "Preview", "PowerLabel", "Power", "Level", "Bar", "Action", "Display", "Fav" }

local function r(x: number, y: number, w: number, h: number): Rect
	return { x = x, y = y, w = math.max(w, 0), h = math.max(h, 0) }
end

local function clamp(v: number, lo: number, hi: number): number
	return math.max(lo, math.min(v, hi))
end

-- border widths (logical px) the frame pictures are drawn at: the main frame, the pet panel frame, a card frame
function MyPetsLayout.Border(w: number, h: number): number
	return clamp(math.min(w, h) * 0.03, 9, 14)
end

function MyPetsLayout.detailBorder(d: Rect): number
	return clamp(d.w * 0.04, 9, 15)
end

function MyPetsLayout.cardBorder(cw: number): number
	return clamp(cw * 0.075, 7, 14)
end

-- the selected pet's panel: name, rarity badge, big picture, POWER, level, XP bar, buttons. `wide` = picture on
-- the left, numbers on the right (upright phones, where the panel is short and wide). Everything sits inside the
-- frame's border, buttons a clear step up from its bottom edge.
local function detail(out: Layout, d: Rect, wide: boolean)
	local p, g = MyPetsLayout.detailBorder(d) + 5, MyPetsLayout.Gap
	local btnH = clamp(d.h * 0.12, 42, 52)
	if wide then
		-- buttons along the whole bottom; picture left, numbers right above them
		local by = d.y + d.h - p - btnH
		local bw = d.w - 2 * p
		out.Action = r(d.x + p, by, bw * 0.45 - g, btnH)
		out.Display = r(d.x + p + bw * 0.45, by, bw * 0.55 - btnH - g, btnH)
		out.Fav = r(d.x + d.w - p - btnH, by, btnH, btnH)
		local pw = math.floor(d.w * 0.42)
		out.Preview = r(d.x + p, d.y + p, pw - p, by - g - d.y - p)
		local x = d.x + pw + g
		local w = d.x + d.w - p - x
		if d.h < 200 then
			-- short upright panel: badge beside the name, POWER beside its number, the level beside the XP bar
			local nameH = 28
			local bwd = math.min(w * 0.44, 96)
			out.Name = r(x, d.y + p, w - bwd - 4, nameH)
			out.Badge = r(x + w - bwd, d.y + p + 4, bwd, 20)
			local lvY = by - 4 - 20
			out.Level = r(x, lvY, w * 0.5, 20)
			out.Bar = r(x + w * 0.5 + 4, lvY + 4, w * 0.5 - 4, 12)
			local py = d.y + p + nameH + 2
			local ph = math.min(lvY - 2 - py, 44)
			out.PowerLabel = r(x, py, w * 0.36, ph)
			out.Power = r(x + w * 0.36 + 2, py, w * 0.64 - 2, ph)
			return
		end
		local nameH = clamp(d.h * 0.13, 28, 38)
		out.Name = r(x, d.y + p, w, nameH)
		local y = d.y + p + nameH + 2
		out.Badge = r(x + w * 0.2, y, w * 0.6, 20)
		y += 20 + 2
		local barY = by - g - 12
		out.Bar = r(x + 4, barY, w - 8, 12)
		local lvY = barY - 2 - 20
		out.Level = r(x, lvY, w, 20)
		out.PowerLabel = r(x, y, w, 16)
		y += 16
		out.Power = r(x + w * 0.06, y, w * 0.88, math.min(lvY - 2 - y, 50))
		return
	end
	local x, w = d.x + p, d.w - 2 * p
	local by = d.y + d.h - p - btnH
	out.Action = r(x, by, w * 0.48 - g, btnH)
	out.Display = r(x + w * 0.48, by, w * 0.52 - btnH - g, btnH)
	out.Fav = r(x + w - btnH, by, btnH, btnH)
	if d.h < 380 then
		-- short panel: the full name on its own row (clear of the frame's corners), the ON TEAM / ON DISPLAY chips and
		-- the rarity badge on the row under it; POWER (label over the number) and the level over its XP bar share one
		-- row, so the picture keeps its room
		local nameH = clamp(d.h * 0.1, 26, 34)
		local nc = w * MyPetsLayout.CornerClear -- clear of the frame's slanted top-left corner, centred
		out.Name = r(x + nc, d.y + p, w - 2 * nc, nameH)
		local bw = math.min(w * 0.36, 110)
		local cy = d.y + p + nameH + 2
		out.Badge = r(x + w - bw, cy, bw, 22)
		-- the chips start a step in: the pet panel frame's slanted top-left corner reaches into its opening
		local cx = w * MyPetsLayout.CornerClear
		out.Roles = r(x + cx, cy, w - bw - g - cx, 22)
		local rowH = clamp(d.h * 0.15, 40, 54)
		local ry = by - g - rowH
		local pw = math.floor(w * 0.56)
		out.PowerLabel = r(x, ry, pw, 14)
		out.Power = r(x, ry + 14, pw, rowH - 14)
		out.Level = r(x + pw + g, ry + 2, w - pw - g, 20)
		out.Bar = r(x + pw + g, ry + rowH - 16, w - pw - g, 14)
		local y = cy + 22 + 2
		out.Preview = r(x, y, w, ry - 2 - y)
		return
	end
	local nameH = clamp(d.h * 0.1, 30, 44)
	local nc = w * MyPetsLayout.CornerClear
	out.Name = r(x + nc, d.y + p, w - 2 * nc, nameH)
	local y = d.y + p + nameH + 2
	out.Badge = r(x + w * 0.28, y, w * 0.44, 24)
	y += 24 + 4
	local barY = by - g - 12
	local lvY = barY - 3 - 20
	local powH = clamp(d.h * 0.11, 36, 52)
	local powY = lvY - 2 - powH
	local plY = powY - 18
	out.PowerLabel = r(x, plY, w, 18)
	out.Power = r(x + w * 0.1, powY, w * 0.8, powH)
	out.Level = r(x, lvY, w, 20)
	out.Bar = r(x + 6, barY, w - 12, 12)
	out.Preview = r(x, y, w, plY - 4 - y)
end

-- the team strip: the YOUR TEAM words on the left, three square slots on the right
local function team(out: Layout, t: Rect, minLabel: number)
	local g = MyPetsLayout.Gap
	local s = t.h - 8
	local slotsW = 3 * s + 2 * g
	local labelW = t.w - slotsW - 12
	if labelW < minLabel then -- narrow: smaller slots so the words keep room
		s = math.floor((t.w - 12 - minLabel - 2 * g) / 3)
		slotsW = 3 * s + 2 * g
		labelW = t.w - slotsW - 12
	end
	out.TeamLabel = r(t.x + 6, t.y + 4, labelW, t.h - 8)
	for i = 1, 3 do
		out["Slot" .. i] = r(t.x + t.w - 6 - slotsW + (i - 1) * (s + g), t.y + (t.h - s) / 2, s, s)
	end
end

-- count / search / sort in one row
local function toolbar(out: Layout, b: Rect)
	local g = MyPetsLayout.Gap
	local cw = math.max(b.w * 0.24, 92)
	local sw = math.max(b.w * 0.25, 96)
	out.Count = r(b.x, b.y, cw, b.h)
	out.Sort = r(b.x + b.w - sw, b.y, sw, b.h)
	out.Search = r(b.x + cw + g, b.y, b.w - cw - sw - 2 * g, b.h)
end

-- Grid columns and card size for a grid `w` x `h` (logical), leaving room for the scroll bar: three even columns
-- across the whole width (two on a very narrow grid); cards as tall as fits two full rows, never flatter than
-- CardFlat, and flatter still only when that is what it takes to show a row and a half (so the grid reads as a
-- scrolling list on short phones).
MyPetsLayout.GridPad = { Top = 6, Bottom = 10, Side = 4 }
function MyPetsLayout.cards(w: number, bar: number?, h: number?): (number, number, number)
	local g = MyPetsLayout.Gap
	local inner = w - (bar or 8) - 2 * MyPetsLayout.GridPad.Side
	local cols = if inner >= 330 then 3 else 2
	local cw = math.floor((inner - (cols - 1) * g) / cols)
	local tall = cw * MyPetsLayout.CardAspect
	if not h then
		return cols, cw, math.floor(tall)
	end
	local room = h - MyPetsLayout.GridPad.Top
	local two = room / 2 - g
	local ch = math.min(tall, math.max(two, cw * MyPetsLayout.CardFlat))
	if room / (ch + g) < 1.5 then
		ch = math.max(room / 1.5 - g, 72)
	end
	return cols, cw, math.floor(math.min(ch, tall))
end

function MyPetsLayout.layout(w: number, h: number): Layout
	local out: Layout = {}
	local p, g = MyPetsLayout.Pad, MyPetsLayout.Gap
	local portrait = h > w * 1.05
	local bottom = h - p
	if portrait then
		local headH = clamp(h * 0.08, 44, 60)
		out.Title = r(p, 4, math.min(w * 0.62, 320), headH - 4)
		local cs = math.max(headH - 6, 40)
		out.Close = r(w - p - cs, 4, cs, cs)
		local top = headH + 4
		local cw = w - 2 * p
		-- a short upright phone: EQUIP BEST moves into the team strip, under the YOUR TEAM words, and the pet panel
		-- tightens, so the grid keeps room for its cards
		local short = h < MyPetsLayout.ShortPortrait
		local teamH = if short then 84 else clamp(h * 0.11, 64, 92)
		out.Team = r(p, top, cw, teamH)
		local y = top + teamH + g
		local detH = if short then clamp(h * 0.33, 162, 220) else clamp(h * 0.34, 220, 270)
		out.Detail = r(p, y, cw, detH)
		y += detH + g
		local tbH = 40
		local tb = r(p, y, cw, tbH)
		if short then
			local t = out.Team
			local s = math.min(t.h - 8, math.floor((t.w - 12 - 130 - 2 * g) / 3))
			local slotsW = 3 * s + 2 * g
			local lw = t.w - slotsW - 12 - g
			out.TeamLabel = r(t.x + 6, t.y + 4, lw, 22)
			out.EquipBest = r(t.x + 6, t.y + 28, lw, t.h - 34)
			for i = 1, 3 do
				out["Slot" .. i] = r(t.x + t.w - 6 - slotsW + (i - 1) * (s + g), t.y + (t.h - s) / 2, s, s)
			end
			out.Grid = r(p, y + tbH + g, cw, bottom - (y + tbH + g))
		else
			local ebH = 48
			out.EquipBest = r(p, bottom - ebH, cw, ebH)
			out.Grid = r(p, y + tbH + g, cw, bottom - ebH - g - (y + tbH + g))
			team(out, out.Team, 120)
		end
		toolbar(out, tb)
		detail(out, out.Detail, true)
		return out
	end
	local lw = math.floor((w - 3 * p) * 0.6)
	local rx = p * 2 + lw
	local rw = w - rx - p
	local tbH = clamp(h * 0.09, 36, 42)
	local ebH = clamp(h * 0.1, 40, 56)
	local gy
	if h < MyPetsLayout.Compact then
		-- short phone: YOUR TEAM on the title row (left), the title and the X over the pet panel (right)
		local rowH = clamp(h * 0.17, 56, 72)
		local y0 = 8
		out.Team = r(p, y0, lw, rowH)
		local cs = clamp(rowH - 14, 38, 50)
		out.Close = r(w - p - cs, y0 + (rowH - cs) / 2, cs, cs)
		out.Title = r(rx, y0 + 2, rw - cs - g, rowH - 4)
		local top = y0 + rowH + g
		out.Detail = r(rx, top, rw, bottom - top)
		local tb = r(p, top, lw, tbH)
		toolbar(out, tb)
		gy = top + tbH + g
		team(out, out.Team, 96)
		-- EQUIP BEST joins the team row (between the words and the slots), so the grid runs to the bottom and two
		-- full rows of cards fit on a phone
		local tl = out.TeamLabel
		local lw2 = clamp(tl.w * 0.42, 100, 150)
		out.EquipBest = r(tl.x + lw2 + g, out.Team.y + 6, tl.w - lw2 - g, out.Team.h - 12)
		tl.w = lw2
		out.Grid = r(p, gy, lw, bottom - gy)
		detail(out, out.Detail, false)
		return out
	else
		local headH = clamp(h * 0.11, 46, 60)
		out.Title = r(p, 4, math.min(w * 0.5, 340), headH - 4)
		local cs = math.max(headH - 6, 40)
		out.Close = r(w - p - cs, 4, cs, cs)
		local top = headH + 4
		out.Detail = r(rx, top, rw, bottom - top)
		local teamH = clamp((bottom - top) * 0.21, 70, 108)
		out.Team = r(p, top, lw, teamH)
		local tb = r(p, top + teamH + g, lw, tbH)
		toolbar(out, tb)
		gy = tb.y + tbH + g
		team(out, out.Team, 120)
	end
	out.EquipBest = r(p, bottom - ebH, lw, ebH)
	out.Grid = r(p, gy, lw, bottom - ebH - g - gy)
	detail(out, out.Detail, false)
	return out
end

return MyPetsLayout
