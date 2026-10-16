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

function HudLayout.compute(w: number, h: number, touch: boolean): Layout
	local s = clamp(math.min(w, h) / 390, 0.9, 1.6)
	local gap = HudLayout.GAP * s
	local reserved = HudLayout.reserved(w, h, touch)

	-- Side buttons: 2x2 grid on the right, under the Roblox top bar and
	-- above the jump button.
	local jumpTop = if reserved.jump then reserved.jump.y else h
	local roomH = jumpTop - (TOPBAR_H + 8) - 12
	local btn = math.min(64 * s, 84, (roomH - gap) / 2)
	btn = math.max(btn, HudLayout.MIN_TOUCH)
	local sideW = btn * 2 + gap
	local sideH = btn * 2 + gap
	local sideX = w - 12 - sideW
	-- Middle of the free strip, so the thumb finds it without reaching.
	local sideY = clamp((TOPBAR_H + 8 + jumpTop - 12 - sideH) / 2 + 10 * s, TOPBAR_H + 8, jumpTop - 12 - sideH)
	local side = rect(sideX, sideY, sideW, sideH)
	local sideButtons = {
		rect(sideX, sideY, btn, btn),
		rect(sideX + btn + gap, sideY, btn, btn),
		rect(sideX, sideY + btn + gap, btn, btn),
		rect(sideX + btn + gap, sideY + btn + gap, btn, btn),
	}

	-- Top bar sits between Roblox's left and right top bar buttons.
	local topW = math.min(480 * s, w - 2 * (TOPBAR_SIDE_W + 8))
	local topH = clamp(44 * s, 40, 64)
	local top = rect((w - topW) / 2, 8, topW, topH)

	-- Center column under the top bar: must clear the side grid.
	local colW = math.min(520 * s, w - 2 * (sideW + 16))
	local colX = (w - colW) / 2
	local stripH = clamp(28 * s, 26, 40)
	-- Below the top bar and below Roblox's top bar buttons.
	local info = rect(colX, math.max(top.y + top.h, TOPBAR_H) + gap, colW, stripH)
	local boost = rect(colX, info.y + info.h + gap, colW, stripH)
	local shoutH = clamp(58 * s, 52, 88) -- two lines: long names wrap
	local shout = rect(colX, boost.y + boost.h + gap, colW, shoutH)
	local toastH = clamp(44 * s, 40, 64) -- two lines when narrow
	local toast = rect(colX, shout.y + shout.h + gap, colW, toastH)
	-- Low slots that reach down beside the thumbstick or jump button get
	-- narrower (staying centered) so they never sit on them.
	for _, slot in { shout, toast } do
		for _, r in reserved do
			if HudLayout.overlaps(slot, r) then
				local cut = if r.x + r.w / 2 < w / 2 then r.x + r.w + 8 - slot.x else slot.x + slot.w - (r.x - 8)
				slot.x += cut
				slot.w -= 2 * cut
			end
		end
	end

	-- Combo: left side under the Roblox menu, above the thumbstick.
	local stickTop = if reserved.thumbstick then reserved.thumbstick.y else h
	local comboW = 96 * s
	local comboH = clamp(math.min(76 * s, stickTop - 12 - (TOPBAR_H + 8)), 40, 120)
	local combo = rect(12, TOPBAR_H + 8, comboW, comboH)

	-- Studio test buttons: a column on the left under the combo counter;
	-- if that runs into the thumbstick, a row along the bottom middle.
	local cheatH = 30
	local colTop = combo.y + combo.h + gap
	local cheats: Rect
	if colTop + 5 * cheatH + 4 * gap <= stickTop - 8 then
		cheats = rect(12, colTop, 72, 5 * cheatH + 4 * gap)
	else
		local left = if reserved.thumbstick then reserved.thumbstick.w + 8 else 12
		local right = if reserved.jump then reserved.jump.x - 8 else w - 12
		local rowW = math.min(5 * 64 + 4 * gap, right - left)
		cheats = rect(left + (right - left - rowW) / 2, h - 8 - cheatH, rowW, cheatH)
	end

	-- While a panel is open, toasts go low in the middle, between the
	-- thumbstick and the jump button (and above the Studio test row).
	local lowLeft = if reserved.thumbstick then reserved.thumbstick.w + 8 else 12
	local lowRight = if reserved.jump then reserved.jump.x - 8 else side.x - 12
	local lowBottom = if cheats.y > h / 2 then cheats.y - gap else h - 8
	local lowW = math.min(colW, lowRight - lowLeft)
	local toastLow = rect(lowLeft + (lowRight - lowLeft - lowW) / 2, lowBottom - toastH, lowW, toastH)

	-- Room for shop / reset / top 10 panels: under Roblox's top bar, left of
	-- the side buttons (they stay tappable), above the low toast. Touch
	-- controls are hidden while a panel is open, so it may reach over them.
	local panelTop = TOPBAR_H + gap
	local panel = rect(12, panelTop, side.x - 12 - 12, toastLow.y - gap - panelTop)

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
