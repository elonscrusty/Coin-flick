--!strict
-- Pure numbers behind the UI juice (client/ui/Juice, UI): count-up values, the coin-fly arc, tab slide direction,
-- reduced-motion gating, scroll canvas height and "new since last look" pet ids. No Instances, no services, so the
-- offline Lune tests can check every rule (tests/test_ui_motion.luau).

local UiMotion = {}

-- Reduce Motion: the game's own setting (UI.Reduced) or Roblox's system setting turns every effect off.
function UiMotion.animate(gameReduced: boolean?, systemReduced: boolean?): boolean
	return gameReduced ~= true and systemReduced ~= true
end

-- Ease out (cubic): fast first, slows into the final value.
function UiMotion.ease(a: number): number
	local x = math.clamp(a, 0, 1)
	return 1 - (1 - x) ^ 3
end

-- The whole number a counter shows `a` (0..1) of the way from `from` to `to` (counts down as well as up).
-- Ends exactly on `to`; never overshoots either end.
function UiMotion.countValue(from: number, to: number, a: number): number
	if a >= 1 then
		return to
	end
	local v = from + (to - from) * UiMotion.ease(a)
	local r = math.floor(v + 0.5)
	if to >= from then
		return math.clamp(r, from, to)
	end
	return math.clamp(r, to, from)
end

-- The values a counter steps through over `frames` frames (frame 1 .. frames), ending on `to`.
function UiMotion.countSteps(from: number, to: number, frames: number): { number }
	local n = math.max(1, math.floor(frames))
	local out = table.create(n)
	for i = 1, n do
		out[i] = UiMotion.countValue(from, to, i / n)
	end
	return out
end

-- Coin-fly arc: a quadratic curve from `p0` to `p1` that bows upward (screen y grows downward) by `lift` plus a
-- quarter of the horizontal distance, so a long flight arcs higher. t in 0..1.
function UiMotion.arcControl(p0: Vector2, p1: Vector2, lift: number): Vector2
	local mid = (p0 + p1) / 2
	return Vector2.new(mid.X, math.min(p0.Y, p1.Y) - lift - math.abs(p1.X - p0.X) * 0.25)
end

function UiMotion.arcPoint(p0: Vector2, p1: Vector2, lift: number, t: number): Vector2
	local u = math.clamp(t, 0, 1)
	local c = UiMotion.arcControl(p0, p1, lift)
	local a = 1 - u
	return p0 * (a * a) + c * (2 * a * u) + p1 * (u * u)
end

-- `n` + 1 points along the arc (t = 0, 1/n, .., 1).
function UiMotion.arcPath(p0: Vector2, p1: Vector2, lift: number, n: number): { Vector2 }
	local k = math.max(1, math.floor(n))
	local out = table.create(k + 1)
	for i = 0, k do
		out[i + 1] = UiMotion.arcPoint(p0, p1, lift, i / k)
	end
	return out
end

-- How many coins fly for a reward of `amount` coins: 3 for small rewards, up to 6 for big ones.
function UiMotion.coinCount(amount: number): number
	local a = math.max(amount, 1)
	return math.clamp(math.floor(math.log10(a)) + 2, 3, 6)
end

-- New tab content slides in from the side of the tab that was tapped: from the right (+dist) when the new tab is
-- right of the old one, from the left (-dist) when it is left of it, not at all for the same tab.
function UiMotion.slideFrom(oldIndex: number?, newIndex: number, dist: number): number
	if oldIndex == nil or oldIndex == newIndex then
		return 0
	end
	return if newIndex > oldIndex then dist else -dist
end

-- Scroll canvas height for a list: content + top and bottom padding + `extra` (one card gap under the last card),
-- never less than 0. Every card is then reachable by scrolling.
function UiMotion.canvasHeight(content: number, padTop: number, padBottom: number, extra: number?): number
	return math.max(0, math.ceil(content + padTop + padBottom + (extra or 0)))
end

-- Pets that arrived since the player last looked: `known` is the set of ids seen so far (nil before the first
-- look: everything is known then, nothing is fresh). Returns the updated known set and the new ids in list order.
function UiMotion.freshIds(known: { [string]: boolean }?, ids: { string }): ({ [string]: boolean }, { string })
	local out: { [string]: boolean } = {}
	local fresh: { string } = {}
	for _, id in ids do
		if known ~= nil and not known[id] then
			table.insert(fresh, id)
		end
		out[id] = true
	end
	return out, fresh
end

-- A GUI object is drawn only when every link from it up to its ScreenGui is on (Visible / Enabled flags, the object
-- first). An empty chain (not under any GUI) is not drawn. Used by Juice.onScreen.
function UiMotion.shownChain(chain: { boolean }): boolean
	if #chain == 0 then
		return false
	end
	for _, on in chain do
		if not on then
			return false
		end
	end
	return true
end

-- A Pet Book tile caption gets two lines when it is several words and too long for one line at the text floor
-- ("Golden Razorclaw", "Skeleton Thunderstrut" showed only their first word); short names stay on one line.
function UiMotion.twoLineName(text: string): boolean
	return string.find(text, " ", 1, true) ~= nil and utf8.len(text) ~= nil and (utf8.len(text) :: number) >= 12
end

-- True when something ending at x = `rightEdge` stays at least `gap` px left of a thing starting at `leftEdge`.
function UiMotion.clearOf(rightEdge: number, leftEdge: number, gap: number): boolean
	return rightEdge + gap <= leftEdge
end

return UiMotion
