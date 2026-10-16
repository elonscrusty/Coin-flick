--!strict
-- Lobby HUD v2 layout (carter's ChatGPT lobby prototype, 2026-10-15): where each piece sits, in LOGICAL px of the
-- HUD layer (origin top left, after UIScale). Pure, so every screen size is tested offline (tests/test_lobby_hud.luau).
--   coin pill top left, FIND THE PET title top centre, MY PETS / PET BOOK stacked on the left, DAILY / SPIN / SHOP
--   stacked on the right, TRAIN / big PLAY / FIGHT in one row at the bottom centre.
-- Keep-outs: Roblox's jump button (SafeZones.jumpZone) on touch screens; nothing overlaps anything else.

local SafeZones = require(script.Parent.SafeZones)
local LobbyHudArt = require(script.Parent.LobbyHudArt)

-- picture width / height of a button (carter's art), so each button box matches its picture
local function aspect(name: string): number
	local a = LobbyHudArt.get(name)
	return if a then a.Aspect else 1
end

local LobbyHudLayout = {}

export type Rect = SafeZones.Rect
export type Layout = { [string]: Rect }

LobbyHudLayout.EDGE = 8
LobbyHudLayout.GAP = 8
LobbyHudLayout.LEFT = { "MyPets", "PetBook" }
LobbyHudLayout.RIGHT = { "Daily", "Spin", "Shop" }
LobbyHudLayout.ROW = { "Train", "Play", "Fight" }
-- the queue line over PLAY ("HUNT IN 12s · 1/4 players")
LobbyHudLayout.STATUS_H = 26

local function status(out: { [string]: Rect }, w: number, aboveY: number?)
	local p = out.Play
	local sw = math.min(w - 2 * LobbyHudLayout.EDGE, math.max(p.w * 1.5, 300))
	out.Status = { x = math.clamp(p.x + p.w / 2 - sw / 2, LobbyHudLayout.EDGE, w - LobbyHudLayout.EDGE - sw), y = (aboveY or p.y) - LobbyHudLayout.STATUS_H - 4, w = sw, h = LobbyHudLayout.STATUS_H }
end

local function rect(x: number, y: number, w: number, h: number): Rect
	return { x = x, y = y, w = w, h = h }
end

-- `w`, `h`: logical screen; `scale`: real px per logical px; `touch`: keep the jump corner clear.
function LobbyHudLayout.layout(w: number, h: number, scale: number?, touch: boolean?): Layout
	local E, G = LobbyHudLayout.EDGE, LobbyHudLayout.GAP
	local out: Layout = {}
	local jump = if touch == false then rect(w, h, 0, 0) else SafeZones.jumpZone(w, h, scale)
	if h > w then
		return LobbyHudLayout.portrait(w, h, jump)
	end

	-- top: coin pill and title
	local coinW, coinH = math.clamp(w * 0.21, 150, 220), math.clamp(h * 0.12, 40, 54)
	out.Coins = rect(E, E - 2, coinW, coinH)
	local titleW = math.clamp(w * 0.24, 170, 260)
	local titleH = titleW * 0.34
	out.Title = rect((w - titleW) / 2, 0, titleW, titleH)

	-- bottom row: PLAY widest, TRAIN / FIGHT a bit over half its width; heights follow the pictures
	local playW = math.clamp(w * 0.29, 200, 320)
	playW = math.min(playW, h * 0.27 * aspect("Play")) -- never taller than about a quarter of a short screen
	local playH = playW / aspect("Play")
	local sideW = math.floor(playW * 0.58)
	local trainH, fightH = sideW / aspect("Train"), sideW / aspect("Fight")
	local rowH = math.max(trainH, fightH)
	local total = playW + 2 * sideW + 2 * G
	local x0 = (w - total) / 2
	local bottom = h - E
	-- slide left of the jump corner when the centred row would touch it
	local maxRight = jump.x - G
	if x0 + total > maxRight and jump.w > 0 then
		x0 = math.max(E + 70, maxRight - total)
	end
	out.Train = rect(x0, bottom - trainH, sideW, trainH)
	out.Play = rect(x0 + sideW + G, bottom - playH, playW, playH)
	out.Fight = rect(x0 + sideW + G + playW + G, bottom - fightH, sideW, fightH)
	local rowTop = bottom - math.max(playH, rowH)

	-- side stacks: square buttons, sized to fit between the top pieces and the row / jump corner
	local s = math.clamp(h * 0.2, 56, 90)
	local rightTop = E
	local rightBottom = math.min(jump.y, h) - G
	local leftTop = out.Coins.y + coinH + G
	local leftBottom = rowTop - G
	-- the row only blocks a stack when it reaches under it
	if out.Train.x > E + s + G then
		leftBottom = h - E
	end
	if out.Fight.x + out.Fight.w < w - E - s - G then
		rightBottom = math.min(rightBottom, h - E)
	else
		rightBottom = math.min(rightBottom, rowTop - G)
	end
	s = math.min(s, (rightBottom - rightTop - 2 * G) / 3, (leftBottom - leftTop - G) / 2)
	local function stack(names: { string }, x: number, top: number, bot: number, centre: number)
		local n = #names
		local height = n * s + (n - 1) * G
		local y = math.clamp(centre - height / 2, top, math.max(top, bot - height))
		for i, name in names do
			out[name] = rect(x, y + (i - 1) * (s + G), s, s)
		end
	end
	stack(LobbyHudLayout.LEFT, E, leftTop, leftBottom, h * 0.47)
	stack(LobbyHudLayout.RIGHT, w - E - s, rightTop, rightBottom, h * 0.42)
	status(out, w)
	return out
end

-- Upright phone: coins and title share the top, the stacks sit at mid height on each side, PLAY spans the bottom
-- left of the jump button with TRAIN and FIGHT side by side above it.
function LobbyHudLayout.portrait(w: number, h: number, jump: Rect): Layout
	local E, G = LobbyHudLayout.EDGE, LobbyHudLayout.GAP
	local out: Layout = {}
	local coinW = math.min(w * 0.46, 200)
	out.Coins = rect(E, E - 2, coinW, 44)
	local titleW = math.min(w - coinW - 3 * E, 220)
	out.Title = rect(w - E - titleW, 0, titleW, math.min(titleW * 0.34, 70))
	local right = (if jump.w > 0 then jump.x else w) - G
	local playW = right - E
	local playH = playW / aspect("Play")
	out.Play = rect(E, h - E - playH, playW, playH)
	local sideW = (playW - G) / 2
	local trainH, fightH = sideW / aspect("Train"), sideW / aspect("Fight")
	local rowH = math.max(trainH, fightH)
	local rowY = out.Play.y - G - rowH
	out.Train = rect(E, rowY + rowH - trainH, sideW, trainH)
	out.Fight = rect(E + sideW + G, rowY + rowH - fightH, sideW, fightH)
	local s = math.clamp(w * 0.19, 56, 84)
	local top = out.Coins.y + out.Coins.h + G + 70
	for i, name in LobbyHudLayout.LEFT do
		out[name] = rect(E, top + (i - 1) * (s + G), s, s)
	end
	for i, name in LobbyHudLayout.RIGHT do
		out[name] = rect(w - E - s, top + (i - 1) * (s + G), s, s)
	end
	status(out, w, rowY)
	return out
end

-- Every piece's name (for tests and the client).
function LobbyHudLayout.names(): { string }
	local list = { "Coins", "Title", "Status" }
	for _, group in { LobbyHudLayout.LEFT, LobbyHudLayout.RIGHT, LobbyHudLayout.ROW } do
		for _, n in group do
			table.insert(list, n)
		end
	end
	return list
end

return LobbyHudLayout
