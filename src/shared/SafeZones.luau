--!strict
-- Pure screen geometry for touch HUD keep-out zones, in LOGICAL px (the HUD layer after UIScale), origin top left.
--   * jump zone: the bottom-right corner kept clear for Roblox's own jump button on touch devices, sized by Roblox's
--     default TouchGui rule (real px: min(W, H) <= 500 is a 70x70 button at (1,-95,1,-90), else 120x120 at
--     (1,-170,1,-210)) plus a small margin. `scale` = real px per logical px (UI.Scale); 1 when omitted.
--   * prompt band: the bottom-centre strip where a ProximityPrompt card (egg "E FREE PET / Hatch!") appears.
-- Everything that sits near the bottom edge (EMOTE, right column tiles) asks this module instead of using its own numbers.
local SafeZones = {}

export type Rect = { x: number, y: number, w: number, h: number }

SafeZones.JUMP_SMALL = { w = 95, h = 90 } -- real px from the bottom-right corner, small screens
SafeZones.JUMP_BIG = { w = 170, h = 210 } -- real px, tablets and big phones
SafeZones.JUMP_MARGIN = 10 -- real px around the button
SafeZones.SMALL_SCREEN = 500 -- Roblox: min(W, H) at or under this is a small screen
SafeZones.PROMPT_W = 230 -- widest prompt card (action + object line), centred
SafeZones.PROMPT_H = 74 -- from the bottom edge up, with its own margin
SafeZones.GAP = 8
SafeZones.STACK_H = 160 -- tutorial hint / notice cards stacked at the bottom of a narrow (portrait) screen

-- Logical size of the jump keep-out corner for a logical screen at `scale` real px per logical px.
function SafeZones.jumpSize(screenW: number, screenH: number, scale: number?): (number, number)
	local k = math.max(scale or 1, 0.05)
	local small = math.min(screenW, screenH) * k <= SafeZones.SMALL_SCREEN
	local j = if small then SafeZones.JUMP_SMALL else SafeZones.JUMP_BIG
	return (j.w + SafeZones.JUMP_MARGIN) / k, (j.h + SafeZones.JUMP_MARGIN) / k
end

function SafeZones.jumpZone(screenW: number, screenH: number, scale: number?): Rect
	local w, h = SafeZones.jumpSize(screenW, screenH, scale)
	return { x = screenW - w, y = screenH - h, w = w, h = h }
end

function SafeZones.promptBand(screenW: number, screenH: number): Rect
	return { x = (screenW - SafeZones.PROMPT_W) / 2, y = screenH - SafeZones.PROMPT_H, w = SafeZones.PROMPT_W, h = SafeZones.PROMPT_H }
end

function SafeZones.overlaps(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

function SafeZones.inJumpZone(r: Rect, screenW: number, screenH: number, scale: number?): boolean
	return SafeZones.overlaps(r, SafeZones.jumpZone(screenW, screenH, scale))
end

-- Where a w x h bottom button (EMOTE) goes: on the bottom row just left of the jump zone, or, when that would touch the
-- prompt band (narrow screens), on the row above the bottom card stack (hint cards, prompt). Never inside the jump zone. `touch` false: the PC spot
-- (same offsets as before: right edge 184 from the right, 40 above the bottom).
function SafeZones.bottomButton(screenW: number, screenH: number, w: number, h: number, touch: boolean, scale: number?): Rect
	if not touch then
		return { x = screenW - 184 - w, y = screenH - 40 - h, w = w, h = h }
	end
	local band = SafeZones.promptBand(screenW, screenH)
	local jump = SafeZones.jumpZone(screenW, screenH, scale)
	local r: Rect = { x = jump.x - SafeZones.GAP - w, y = screenH - SafeZones.GAP - h, w = w, h = h }
	if SafeZones.overlaps(r, band) then
		r.y = screenH - SafeZones.STACK_H - SafeZones.GAP - h
	end
	return r
end

-- Roblox's dynamic thumbstick listens for touches that start anywhere in the lower left of a landscape screen
-- (the left 40 % of the width, the bottom 60 % of the height) or the bottom 40 % of an upright one. A button there
-- takes the touch first, so the player cannot start walking: no HUD button may sit in this zone on touch devices.
function SafeZones.thumbZone(screenW: number, screenH: number): Rect
	if screenH > screenW then
		return { x = 0, y = screenH * 0.6, w = screenW, h = screenH * 0.4 }
	end
	return { x = 0, y = screenH * 0.4, w = screenW * 0.4, h = screenH * 0.6 }
end

function SafeZones.inThumbZone(r: Rect, screenW: number, screenH: number): boolean
	return SafeZones.overlaps(r, SafeZones.thumbZone(screenW, screenH))
end

-- How the lobby buttons (PLAY, GIFT, TOWER, BATTLE, DAILY) are laid out. A computer keeps the column down the left.
-- Touch screens keep them out of the thumbstick zone: a landscape phone puts them in one short row along the top
-- (PLAY as a pill `PlayW` wide, the other four as `CellW` squares, so the row covers little of the view: owner's
-- phone shot 2026-10-15 "the ui is blocking my view"), an upright one in two columns. Sizes in logical px.
export type LobbyLayout = { Mode: string, Cols: number, CellW: number, CellH: number, PlayW: number? }
SafeZones.ROW_TILE = 60 -- square tiles of the landscape row (a thumb target: 44 px or more; 60 fits a 16 px word)
SafeZones.ROW_PLAY = 112 -- PLAY pill width in that row
function SafeZones.lobbyLayout(screenW: number, screenH: number, touch: boolean, columnW: number): LobbyLayout
	-- a short landscape window without touch (the Studio phone window, a small laptop) takes the row too: the
	-- column of five buttons filled 40% of a 390 px tall screen
	if not touch and not (screenW > screenH and screenH < 420) then
		return { Mode = "column", Cols = 1, CellW = columnW, CellH = 52 }
	end
	if screenH > screenW then
		-- two columns under the coins, as wide as two thirds of the screen allows (the right column keeps its side)
		local cell = math.clamp(math.floor((screenW * 0.66 - 6) / 2), math.floor((columnW - 6) / 2), 130)
		return { Mode = "grid", Cols = 2, CellW = cell, CellH = 52 }
	end
	-- the tiles shrink (never under 44) so the row stays inside the left half of a narrow phone
	local tile = math.clamp(math.floor((screenW * 0.48 - 14 - SafeZones.ROW_PLAY - 4 * 6) / 4), 44, SafeZones.ROW_TILE)
	return { Mode = "row", Cols = 5, CellW = tile, CellH = tile, PlayW = SafeZones.ROW_PLAY }
end

-- Width of the landscape row: PLAY, four tiles and the gaps between them.
-- true when the lobby buttons leave the column (a phone, or a short landscape window): the objective pill and
-- the rare-hatch banner follow the same verdict
function SafeZones.compactLobby(screenW: number, screenH: number, touch: boolean): boolean
	return SafeZones.lobbyLayout(screenW, screenH, touch, 172).Mode ~= "column"
end

function SafeZones.rowWidth(L: LobbyLayout, gap: number): number
	return (L.PlayW or L.CellW) + (L.Cols - 1) * L.CellW + (L.Cols - 1) * gap
end

-- Largest bottom (logical y) a right-column tile may reach on touch: just above the jump zone.
function SafeZones.columnLimit(screenW: number, screenH: number, scale: number?): number
	local _, h = SafeZones.jumpSize(screenW, screenH, scale)
	return screenH - h - SafeZones.GAP
end

return SafeZones
