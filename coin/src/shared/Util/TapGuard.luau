--!strict
-- Is a press on a shop button a real, deliberate tap? A press only counts when
-- the list did not move under the finger and is not still coasting from a
-- scroll (otherwise a tap lands on whatever row slid under it, and buys the
-- wrong item). Pure so it is tested offline.

local TapGuard = {}

TapGuard.MAX_MOVE = 6 -- pixels the list may move between press and release
TapGuard.SETTLE = 0.2 -- seconds the list must have been still

function TapGuard.ok(canvasAtPress: number, canvasNow: number, secondsSinceScroll: number): boolean
	return math.abs(canvasNow - canvasAtPress) <= TapGuard.MAX_MOVE and secondsSinceScroll >= TapGuard.SETTLE
end

return TapGuard
