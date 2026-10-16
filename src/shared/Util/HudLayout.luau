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
	mega: Rect, -- mega coin count chip (stays after the flip)
	boost: Rect, -- 2x boost timer chip
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
HudLayout.CARD_GAP = 12 -- air between the combo card and the buttons
HudLayout.COMBO_POP_MAX = 1.1 -- biggest the combo card ever grows (UIScale)
HudLayout.RESET_BAR_MIN = 20 -- px, the RESET progress bar is never thinner
HudLayout.MSG_MARGIN = 10 -- px of air around the message spot

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

	-- Left band, top to bottom: cash + hat pills, heads info, then the message
	-- spot (rare banner, toasts) which has the band's leftover room to itself,
	-- so a message never lands on a pill or card.
	local colW = clamp(w * 0.25 - 14, 140, 260)
	local pillH = clamp(34 * s, 32, 48)
	local top = rect(x0, y0, colW, pillH)
	-- Tall as the room allows (a short phone gives some to the message spot).
	local infoH = clamp(48 * s, 40, 70)
	if touch then
		infoH = clamp(math.min(infoH, stickTop - 10 - 56 - (top.y + top.h + gap) - 10), 40, 70)
	end
	local info = rect(x0, top.y + top.h + gap, colW, infoH)
	local margin = HudLayout.MSG_MARGIN
	local msgTop = info.y + info.h + margin
	local msgBottom = if touch then stickTop - margin else math.min(h - 12, msgTop + 140 * s)
	local msgH = clamp(msgBottom - msgTop, 56, 120 * s)
	local msg = rect(x0, msgTop, colW, msgH)
	local shout = rect(msg.x, msg.y, msg.w, msg.h)
	local toast = rect(msg.x, msg.y, msg.w, msg.h)

	-- Right band, top to bottom: mega count chip, 2x boost timer chip, combo
	-- card, then the 2x2 side buttons above the jump button.
	local yr = TOPBAR_H + 4 -- the right band starts just under Roblox's top buttons
	local availH = jumpTop - 12 - yr
	local chipH = 26
	local comboH = clamp(44 * s, 48, 50)
	local rgap = math.max(4, gap * 0.6) -- tighter gaps in the packed right band
	local btn = math.min(64 * s, 84, (availH - 2 * chipH - comboH - 3 * rgap - HudLayout.CARD_GAP) / 2)
	btn = math.max(btn, HudLayout.MIN_TOUCH)
	local sideW = btn * 2 + rgap
	local sideH = btn * 2 + rgap
	local sideX = w - 12 - sideW
	local chipW = math.max(sideW, 112)
	local chipX = w - 12 - chipW
	local mega = rect(chipX, yr, chipW, chipH)
	local boost = rect(chipX, mega.y + mega.h + rgap, chipW, chipH)
	local combo = rect(sideX, boost.y + boost.h + rgap, sideW, comboH)
	local sideY = combo.y + combo.h + HudLayout.CARD_GAP
	local side = rect(sideX, sideY, sideW, sideH)
	local sideButtons = {
		rect(sideX, sideY, btn, btn),
		rect(sideX + btn + rgap, sideY, btn, btn),
		rect(sideX, sideY + btn + rgap, btn, btn),
		rect(sideX + btn + rgap, sideY + btn + rgap, btn, btn),
	}

	-- Studio test buttons: a column under the boost strip if it fits above the
	-- thumbstick, else a row along the bottom between the thumbstick and jump.
	local cheatH = 30
	local n = HudLayout.CHEATS
	local colTop = msg.y + msg.h + margin
	local cheats: Rect
	if colTop + n * cheatH + (n - 1) * gap <= stickTop - 8 then
		cheats = rect(x0, colTop, 72, n * cheatH + (n - 1) * gap)
	else
		local left = if reserved.thumbstick then reserved.thumbstick.w + 8 else 12
		local right = if reserved.jump then reserved.jump.x - 8 else side.x - 12
		local rowW = math.min(n * 64 + (n - 1) * gap, right - left)
		cheats = rect(left + (right - left - rowW) / 2, h - 8 - cheatH, rowW, cheatH)
	end

	-- While a panel is open the left band under the pills is free (the panel
	-- starts to its right), so toasts use the same message spot.
	local toastLow = rect(msg.x, msg.y, msg.w, msg.h)

	-- Panels are modal (the screen is dimmed), so they take nearly all the
	-- room between the two side bands: right of the pills and cards, left of
	-- the side buttons and combo, from just under Roblox's top bar to 4% above
	-- the bottom. Touch controls hide while one is open. A 2% side inset
	-- leaves room for the pop-in.
	local panelLeft = x0 + colW + 10
	local panelTop = TOPBAR_H + gap + h * 0.02
	local rawW = math.min(side.x, mega.x) - 10 - panelLeft
	local panel = rect(panelLeft + rawW * 0.02, panelTop, rawW * 0.96, h * 0.96 - panelTop)

	return {
		scale = s,
		toastLow = toastLow,
		panel = panel,
		top = top,
		info = info,
		mega = mega,
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

-- Inside the RESET button (pixels from its top-left corner, before the
-- button's own padding): the word on top, the progress bar along the bottom.
function HudLayout.resetParts(w: number, h: number): { word: Rect, bar: Rect }
	local barH = math.max(HudLayout.RESET_BAR_MIN, h * 0.44)
	local barY = h - barH - math.max(3, h * 0.06)
	local bar = rect(w * 0.06, barY, w * 0.88, barH)
	local word = rect(0, 2, w, math.max(12, barY - 4))
	return { word = word, bar = bar }
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
