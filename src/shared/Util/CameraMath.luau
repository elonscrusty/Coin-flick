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

-- Camera tilt choices: this far back for every 1 up. Steep (0.62 = 58 degrees down) shows the
-- coin faces; flatter ones let a WIDE screen get closer (the table is wider than it is deep).
-- The closest camera that fits wins; the flattest allowed is 1.0 (45 degrees).
local BACK_PER_UP_CHOICES = { 0.62, 0.8, 1.0 }
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
	-- The table's rim, and the helper guys who walk around it (feet on the ground, heads up).
	local rimY = -1.2
	local helperR = Config.TABLE_RADIUS + 2
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2
		table.insert(
			list,
			{ math.cos(a) * (Config.TABLE_RADIUS + 0.6), rimY, math.sin(a) * (Config.TABLE_RADIUS + 0.6) }
		)
		table.insert(list, { math.cos(a) * helperR, -Config.TABLE_HEIGHT + 0.2, math.sin(a) * helperR })
		table.insert(list, { math.cos(a) * helperR, -Config.TABLE_HEIGHT + 3.4, math.sin(a) * helperR })
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
	local best: View? = nil
	local bestDist = math.huge
	for _, ratio in BACK_PER_UP_CHOICES do
		for up = 8, 90, 0.5 do
			local candidate: View = { back = up * ratio, up = up, aim = AIM_AHEAD }
			if fits(candidate, a, fovDeg) then
				local dist = math.sqrt(candidate.back ^ 2 + candidate.up ^ 2)
				if dist < bestDist then
					best, bestDist = candidate, dist
				end
				break
			end
		end
	end
	local view: View = best or { back = 90 * BACK_PER_UP_CHOICES[1], up = 90, aim = AIM_AHEAD }
	cache[key] = view
	return view
end

CameraMath.fits = fits

return CameraMath
