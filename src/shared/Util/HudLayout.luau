--!strict
-- Where every always-on HUD piece goes, in pixels, for any screen size.
-- Pure math (no Instances) so tests can prove, for phone, tablet and PC
-- sizes, that nothing overlaps another piece or Roblox's own buttons, text
-- is big enough to read, and buttons are big enough for a thumb.

export type Rect = { x: number, y: number, w: number, h: number }

export type Layout = {
	scale: number,
	-- Always on screen
	top: Rect, -- cash + hat pills
	info: Rect, -- "$x per heads • ..." strip
	boost: Rect, -- mega coin / boost strip
	side: Rect, -- 2x2 grid: SHOP RESET / TOP ZOOM
	sideButtons: { Rect },
	-- Pop in for a moment
	shout: Rect, -- rare coin banner
	toast: Rect, -- little message
	toastLow: Rect, -- little message while a panel is open
	panel: Rect, -- biggest box a shop / reset / top 10 panel may use
	combo: Rect, -- 🔥 x12 COMBO
	cheats: Rect, -- Studio only test buttons
	-- Roblox's own buttons; nothing of ours may sit on them
	reserved: { [string]: Rect },
}

local HudLayout = {}

HudLayout.MIN_TEXT = 14 -- px, smallest readable text
HudLayout.MIN_TOUCH = 44 -- px, smallest thumb-friendly button
HudLayout.GAP = 6
HudLayout.CHEATS = 6 -- Studio test buttons (Hud.buildCheats)

-- Roblox top bar: menu/chat on the left, more buttons on the right.
local TOPBAR_H = 58
local TOPBAR_SIDE_W = 160

local function rect(x: number, y: number, w: number, h: number): Rect
	return { x = math.floor(x + 0.5), y = math.floor(y + 0.5), w = math.floor(w + 0.5), h = math.floor(h + 0.5) }
end

local function clamp(v: number, lo: number, hi: number): number
	return math.max(lo, math.min(hi, v))
end

function HudLayout.overlaps(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

function HudLayout.inside(a: Rect, w: number, h: number): boolean
	return a.x >= 0 and a.y >= 0 and a.x + a.w <= w and a.y + a.h <= h
end

-- Roblox's touch controls (small screens have smaller ones) and top bar.
function HudLayout.reserved(w: number, h: number, touch: boolean): { [string]: Rect }
	local r: { [string]: Rect } = {
		menu = rect(0, 0, TOPBAR_SIDE_W, TOPBAR_H),
		topRight = rect(w - TOPBAR_SIDE_W, 0, TOPBAR_SIDE_W, TOPBAR_H),
	}
	if touch then
		local small = math.min(w, h) <= 500
		if small then
			r.jump = rect(w - 105, h - 100, 90, 90)
			r.thumbstick = rect(0, h - 160, 180, 160)
		else
			r.jump = rect(w - 180, h - 220, 140, 140)
			r.thumbstick = rect(0, h - 260, 280, 260)
		end
	end
	return r
end

-- The part of the screen the table's coins (and their flips and the giant
-- coin) use: the middle half across, from just under the flip peak to just
-- above the near coins. Nothing always-on may sit here (CameraMath.SAFE).
function HudLayout.tableZone(w: number, h: number): Rect
	return rect(w * 0.25, h * 0.19, w * 0.5, h * 0.74)
end

-- Everything lives in the two free bands beside the table: cash, hats, the
-- heads info, the mega/boost timer and the message slot on the LEFT; combo
-- and the 4 big buttons on the RIGHT. The middle stays clear for coins.
function HudLayout.compute(w: number, h: number, touch: boolean): Layout
	local s = clamp(math.min(w, h) / 390, 0.9, 1.6)
	local gap = HudLayout.GAP * s
	local reserved = HudLayout.reserved(w, h, touch)
	local x0 = 12
	local y0 = TOPBAR_H + 8
	local jumpTop = if reserved.jump then reserved.jump.y else h
	local stickTop = if reserved.thumbstick then reserved.thumbstick.y else h

	-- Left band, top to bottom: pills, heads info, boost / mega timer.
	local colW = clamp(w * 0.25 - 14, 140, 260)
	local pillH = clamp(34 * s, 32, 48)
	local top = rect(x0, y0, colW, pillH)
	local infoH = clamp(40 * s, 38, 64)
	local info = rect(x0, top.y + top.h + gap, colW, infoH)
	local boostH = clamp(26 * s, 26, 38)
	local boost = rect(x0, info.y + info.h + gap, colW, boostH)
	-- Messages (rare coin banner, toasts) use the info + boost spot: those two
	-- hide while a message shows, so nothing ever sits on the table.
	local msg = rect(x0, info.y, colW, boost.y + boost.h - info.y)
	local shout = rect(msg.x, msg.y, msg.w, msg.h)
	local toast = rect(msg.x, msg.y, msg.w, msg.h)

	-- Right band: combo counter, then the 2x2 side buttons, above the jump button.
	local availH = jumpTop - 12 - y0
	local comboH = clamp(44 * s, 40, 64)
	local btn = math.min(64 * s, 84, (availH - comboH - 2 * gap) / 2)
	btn = math.max(btn, HudLayout.MIN_TOUCH)
	local sideW = btn * 2 + gap
	local sideH = btn * 2 + gap
	local sideX = w - 12 - sideW
	local combo = rect(sideX, y0, sideW, comboH)
	local sideY = combo.y + combo.h + gap
	local side = rect(sideX, sideY, sideW, sideH)
	local sideButtons = {
		rect(sideX, sideY, btn, btn),
		rect(sideX + btn + gap, sideY, btn, btn),
		rect(sideX, sideY + btn + gap, btn, btn),
		rect(sideX + btn + gap, sideY + btn + gap, btn, btn),
	}

	-- Studio test buttons: a column under the boost strip if it fits above the
	-- thumbstick, else a row along the bottom between the thumbstick and jump.
	local cheatH = 30
	local n = HudLayout.CHEATS
	local colTop = boost.y + boost.h + gap
	local cheats: Rect
	if colTop + n * cheatH + (n - 1) * gap <= stickTop - 8 then
		cheats = rect(x0, colTop, 72, n * cheatH + (n - 1) * gap)
	else
		local left = if reserved.thumbstick then reserved.thumbstick.w + 8 else 12
		local right = if reserved.jump then reserved.jump.x - 8 else side.x - 12
		local rowW = math.min(n * 64 + (n - 1) * gap, right - left)
		cheats = rect(left + (right - left - rowW) / 2, h - 8 - cheatH, rowW, cheatH)
	end

	-- While a panel is open, toasts go low in the middle (between the
	-- thumbstick and the jump button, above the Studio test row).
	local toastH = clamp(44 * s, 40, 64)
	local lowLeft = if reserved.thumbstick then reserved.thumbstick.w + 8 else 12
	local lowRight = if reserved.jump then reserved.jump.x - 8 else side.x - 12
	local lowBottom = if cheats.y > h / 2 then cheats.y - gap else h - 8
	local lowW = math.min(520 * s, lowRight - lowLeft)
	local toastLow = rect(lowLeft + (lowRight - lowLeft - lowW) / 2, lowBottom - toastH, lowW, toastH)

	-- Room for shop / reset / top 10 panels: right of the pills (which stay
	-- above the dim), left of the side buttons, above the low toast. Touch
	-- controls hide while a panel is open, so it may reach over them.
	local panelLeft = top.x + top.w + 8
	local panelTop = TOPBAR_H + gap
	local panel = rect(panelLeft, panelTop, side.x - 12 - panelLeft, toastLow.y - gap - panelTop)

	return {
		scale = s,
		toastLow = toastLow,
		panel = panel,
		top = top,
		info = info,
		boost = boost,
		side = side,
		sideButtons = sideButtons,
		shout = shout,
		toast = toast,
		combo = combo,
		cheats = cheats,
		reserved = reserved,
	}
end

-- Screen sizes the tests (and the runner) check. Width x height in px,
-- after the device safe area.
HudLayout.SCREENS = {
	{ name = "phone-small", w = 667, h = 375, touch = true },
	{ name = "phone", w = 844, h = 390, touch = true },
	{ name = "phone-wide", w = 926, h = 428, touch = true },
	{ name = "phone-1108", w = 1108, h = 512, touch = true },
	{ name = "tablet", w = 1024, h = 768, touch = true },
	{ name = "pc-small", w = 1280, h = 720, touch = false },
	{ name = "pc", w = 1920, h = 1080, touch = false },
}

return HudLayout
