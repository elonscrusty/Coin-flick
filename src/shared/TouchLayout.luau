--!strict
-- Where Roblox's own touch controls sit, and where the game's primary action button may go.
--
-- All numbers are SCREEN pixels measured from the bottom-right corner (what Roblox calls
-- AbsoluteSize / Position of the PlayerGui, not our UIScale'd logical pixels).
--
-- Roblox's native jump button (PlayerModule/ControlModule/TouchJump) is, from memory, a circle of
-- 70 px (shorter screen side <= 500) or 120 px, whose left edge is 1.5 * size - 10 from the right edge
-- and whose top edge is size + 20 (small) or 1.75 * size (large) above the bottom edge. The owner's
-- recording shows the previous placement (which already used this model with a 14 px gap) overlapping
-- the real button, so this module does not trust the model alone: it reserves the model's area GROWN by
-- INFLATE towards the screen centre and puts the action outside it, with a visible gap. The real
-- rectangle must still be measured in Studio (docs/m4/INTERACTION.md).
local TouchLayout = {}

export type Rect = { Right: number, Left: number, Bottom: number, Top: number } -- distances from the right / bottom edge

local INFLATE = 1.1 -- allowance for a bigger real button (touch-control scaling, other control schemes) ...
local PAD = 14 -- ... plus a fixed margin in screen px
local GAP = 16 -- clear space between the reserved jump area and the action

-- The native jump button's rectangle by the model (edges as distances from the right/bottom edge).
function TouchLayout.jumpRect(w: number, h: number): Rect
	local small = math.min(w, h) <= 500
	local size = if small then 70 else 120
	local left = size * 1.5 - 10 -- left edge, from the right
	local top = if small then size + 20 else size * 1.75 -- top edge, from the bottom
	return { Right = left - size, Left = left, Bottom = top - size, Top = top }
end

-- The area kept free for the jump button: the model rectangle stretched out to the corner and grown
-- by INFLATE on its inner sides (so it also covers a button placed lower, further right or larger).
function TouchLayout.reserved(w: number, h: number): Rect
	local j = TouchLayout.jumpRect(w, h)
	return { Right = 0, Left = j.Left * INFLATE + PAD, Bottom = 0, Top = j.Top * INFLATE + PAD }
end

-- Position for an action of height `actH` (screen px). Returns the distance of its RIGHT edge from the
-- right edge, of its BOTTOM edge from the bottom edge, and the mode. `topLimit` = the highest its top
-- edge may reach (distance from the bottom edge). Preferred: directly above the reserved jump area; if
-- that is too tall for the screen, left of it on the bottom row. `touch` false (keyboard and mouse):
-- bottom right corner, there is no jump button to avoid.
function TouchLayout.place(w: number, h: number, actH: number, topLimit: number, touch: boolean): (number, number, string)
	if not touch then
		return 20, 90, "corner"
	end
	local r = TouchLayout.reserved(w, h)
	local bottom = r.Top + GAP
	if bottom + actH <= topLimit then
		return 24, bottom, "above"
	end
	return r.Left + GAP, 24, "left"
end

-- True when the action rectangle (right/bottom distances, size actW x actH) overlaps the reserved area.
function TouchLayout.overlapsJump(w: number, h: number, right: number, bottom: number, actW: number, actH: number): boolean
	local r = TouchLayout.reserved(w, h)
	local aLeft, aTop = right + actW, bottom + actH
	return not (right >= r.Left or aLeft <= r.Right or bottom >= r.Top or aTop <= r.Bottom)
end

return TouchLayout
