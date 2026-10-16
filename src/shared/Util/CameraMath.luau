--!strict
-- Where the ZOOM camera sits so EVERY coin fits on screen, on any screen shape.
-- Pure numbers (no Vector3), so the Lune tests can check it for phone,
-- tablet and wide PC screens.
--
-- Coordinates are in the table's own frame: u = towards the back of the table
-- (away from where the player stands), y = up, s = sideways. The camera looks
-- straight along u, tipped down.

local Config = require(script.Parent.Parent.Config)
local TableLayout = require(script.Parent.TableLayout)

local CameraMath = {}

-- Camera direction: this far back for every 1 up (steep, but you still see the coin faces).
local BACK_PER_UP = 0.62
-- Aim this far past the table centre (studs). Small, so the near coins are not cut.
local AIM_AHEAD = 0.6

-- Room the HUD leaves free, in screen units from -1 (left/bottom) to 1 (right/top).
-- Right side has the big buttons, top has the cash bar.
-- `air` is the top limit for a coin at the top of its flip (it may rise over the table's far edge).
CameraMath.SAFE = table.freeze({ left = -0.62, right = 0.5, bottom = -0.86, top = 0.45, air = 0.62 })

-- Normal (WALK) camera when you leave ZOOM: this far behind and above your avatar.
CameraMath.WALK = table.freeze({ back = 12, up = 5 })

export type View = { back: number, up: number, aim: number }

local function coinRadius(): number
	-- Biggest coin (all Bigger Coins levels) plus a little bounce room.
	local maxBig = Config.Upgrades.bigCoins.maxLevel
	return (Config.COIN_BASE_DIAMETER + Config.COIN_DIAMETER_PER_LEVEL * maxBig) / 2
end

-- Every point that must be on screen: each coin's edges at rest, and the
-- middle of each coin at the top of its flip (marked with a 4th value of 1).
function CameraMath.points(): { { number } }
	local r = coinRadius()
	local list: { { number } } = {}
	for i = 1, Config.MAX_COINS do
		local x, z = TableLayout.coinOffset(i, Config.MAX_COINS)
		-- x runs along the table's "outward" axis, z sideways (same as Tables.restCFrame).
		for _, d in { { r, 0 }, { -r, 0 }, { 0, r }, { 0, -r } } do
			table.insert(list, { x + d[1], 0, z + d[2] })
		end
		table.insert(list, { x, Config.FLIP_HEIGHT, z, 1 })
	end
	return list
end

-- Screen position (-1..1 each way) of point {u, y, s} seen from `view`, or nil if behind the camera.
function CameraMath.project(view: View, point: { number }, aspect: number, fovDeg: number): (number?, number?)
	local eu, ey = -view.back, view.up
	local fu, fy = view.aim - eu, 0 - ey
	local len = math.sqrt(fu * fu + fy * fy)
	fu, fy = fu / len, fy / len
	local vu, vy = -fy, fu -- camera "up", tipped forward because it looks down
	local du, dy, ds = point[1] - eu, point[2] - ey, point[3]
	local depth = du * fu + dy * fy
	if depth <= 0.1 then
		return nil, nil
	end
	local t = math.tan(math.rad(fovDeg) / 2)
	local sx = ds / (depth * t * aspect)
	local sy = (du * vu + dy * vy) / (depth * t)
	return sx, sy
end

local function fits(view: View, aspect: number, fovDeg: number): boolean
	local safe = CameraMath.SAFE
	for _, p in CameraMath.points() do
		local sx, sy = CameraMath.project(view, p, aspect, fovDeg)
		if not sx or not sy then
			return false
		end
		-- Sideways the table is the same both ways, so use the tighter side.
		local half = math.min(-safe.left, safe.right)
		local top = if p[4] == 1 then safe.air else safe.top
		if math.abs(sx) > half or sy > top or sy < safe.bottom then
			return false
		end
	end
	return true
end

local cache: { [string]: View } = {}

-- The closest camera that still fits every coin. `aspect` = screen width / height.
function CameraMath.tableView(aspect: number, fovDeg: number): View
	local a = math.clamp(if aspect == aspect and aspect > 0 then aspect else 1.6, 0.3, 4)
	local key = string.format("%.2f/%d", a, fovDeg)
	local hit = cache[key]
	if hit then
		return hit
	end
	local view: View = { back = 0, up = 0, aim = AIM_AHEAD }
	for up = 8, 80, 0.5 do
		view = { back = up * BACK_PER_UP, up = up, aim = AIM_AHEAD }
		if fits(view, a, fovDeg) then
			break
		end
	end
	cache[key] = view
	return view
end

CameraMath.fits = fits

return CameraMath
