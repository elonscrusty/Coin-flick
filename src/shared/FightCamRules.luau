--!strict
-- Shot maths for the Pet Battle camera director (client FightCam). Pure (Vector3 / CFrame only), tested in
-- tests/test_fight_cam.luau. A Stage is the fight seen from the local player's side: the middle of the fight, the
-- direction back towards the player's own team, and how far / high the base camera sits for that arena layout.

local FightCamRules = {}

export type Stage = {
	Centre: Vector3, -- the middle between the two pet lines, a little above the floor
	Back: Vector3, -- flat unit vector from the centre towards the player's own pets
	Right: Vector3, -- flat unit vector, right of Back
	R: number, -- base camera distance from the centre
	H: number, -- base camera height above the centre (at R)
	Aim: number?, -- how high over the floor the base view looks (about half the pets' height; default 1)
	Fit: { number }?, -- the fitted base distance at FIT_SAMPLES angles across the orbit (FightCamRules.radiusAt)
}

FightCamRules.FIGHT_FOV = 45 -- the lens for the whole fight (FightCam gives the player's own back at the end)
FightCamRules.CUT_GAP = 6 -- s between two crit close-ups: the wide view (both teams) is the fight's main shot

local UP = Vector3.yAxis

local function flat(v: Vector3, fallback: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else fallback
end

local function turn(v: Vector3, a: number): Vector3
	return CFrame.Angles(0, a, 0):VectorToWorldSpace(v)
end

local function ease(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

-- The part of the screen the fight HUD leaves clear, in screen units (-1..1, y up): under the top banner, inside the
-- JUMP / SPECIAL buttons on the right and LEAVE on the left, above the bottom buttons.
FightCamRules.SAFE = { X0 = -0.72, X1 = 0.72, Y0 = -0.55, Y1 = 0.45 }

-- What the client knows about the fight it frames: the screen's width / height, how tall the drawn pets are, and how
-- many stand in each line. Unknown fields fall back to a 16:9 screen, 5-stud pets, three a side.
export type View = { Aspect: number?, Height: number?, Pets: number?, Foes: number? }

-- Where the pets of one line stand (TowerView.floor draws them the same way).
local function line(origin: CFrame, z: number, gap: number, n: number): { Vector3 }
	local out = {}
	for i = 1, n do
		table.insert(out, (origin * CFrame.new((i - (n + 1) / 2) * gap, 0, z)).Position)
	end
	return out
end

-- Screen position (-1..1) of `pt` seen from `pos` looking at `aim` through a lens FIGHT_FOV tall; nil = behind or
-- too close to the camera.
function FightCamRules.project(pos: Vector3, aim: Vector3, pt: Vector3, aspect: number): (number?, number?)
	local fwd = (aim - pos).Unit
	local right = fwd:Cross(UP).Unit
	local up = right:Cross(fwd)
	local d = pt - pos
	local depth = d:Dot(fwd)
	if depth < 3 then
		return nil, nil
	end
	local tanV = math.tan(math.rad(FightCamRules.FIGHT_FOV) / 2)
	return d:Dot(right) / depth / (tanV * aspect), d:Dot(up) / depth / tanV
end

-- Every pet's feet and head stay inside SAFE seen from `pos` looking at `aim`.
local function framed(pos: Vector3, aim: Vector3, pets: { Vector3 }, height: number, aspect: number): boolean
	local safe = FightCamRules.SAFE
	for _, foot in pets do
		for _, lift in { 0, height } do
			local x, y = FightCamRules.project(pos, aim, foot + UP * lift, aspect)
			if not x or not y or x < safe.X0 or x > safe.X1 or y < safe.Y0 or y > safe.Y1 then
				return false
			end
		end
	end
	return true
end

-- The orbit point at angle `a` (radians off Back towards Right), distance `r` (height follows: low and side-on).
local function orbitAt(s: Stage, a: number, r: number): Vector3
	return s.Centre + turn(s.Back, a) * r + UP * r * FightCamRules.LOW
end
FightCamRules.LOW = 0.2 -- base camera height over distance
FightCamRules.FIT_SAMPLES = 13 -- angles across the orbit fitted one by one

-- `origin`: the player's view origin (TowerView draws the player's pets at origin * (x, 0, PetZ), the rival's at
-- FoeZ); `layout`: a PvpConfig.Layouts entry; `view`: the screen and pets being framed. The base camera sits low and
-- side-on through the narrow FIGHT_FOV lens. For each angle of its orbit it comes as close as it can while every pet
-- stays inside SAFE on this screen (Studio 2026-10-15: one distance for the whole orbit left the pets in the middle
-- third of the screen at most angles).
function FightCamRules.stage(origin: CFrame, layout: { PetZ: number, FoeZ: number, PetGap: number?, FoeGap: number? }, view: View?): Stage
	local v: View = view or {}
	local mineMid = (origin * CFrame.new(0, 0, layout.PetZ)).Position
	local foeMid = (origin * CFrame.new(0, 0, layout.FoeZ)).Position
	local back = flat(mineMid - foeMid, flat(-origin.LookVector, Vector3.zAxis))
	local aspect = math.clamp(v.Aspect or 16 / 9, 1, 3)
	local height = math.clamp(v.Height or 5, 2, 12)
	local pets = line(origin, layout.PetZ, layout.PetGap or 6, math.clamp(v.Pets or 3, 1, 6))
	for _, p in line(origin, layout.FoeZ, layout.FoeGap or 6, math.clamp(v.Foes or 3, 1, 6)) do
		table.insert(pets, p)
	end
	local s: Stage = { Centre = (mineMid + foeMid) / 2 + UP * 1.5, Back = back, Right = back:Cross(UP).Unit, R = 12, H = 2.4, Fit = {}, Aim = height * 0.42 }
	local focus = FightCamRules.focus(s)
	local lo, hi = FightCamRules.BASE_ANGLE - FightCamRules.BASE_SWING, FightCamRules.BASE_ANGLE + FightCamRules.BASE_SWING
	local far = 0
	for i = 1, FightCamRules.FIT_SAMPLES do
		local a = lo + (hi - lo) * (i - 1) / (FightCamRules.FIT_SAMPLES - 1)
		local r = 10
		while r < FightCamRules.MAX_R and not framed(orbitAt(s, a, r), focus, pets, height, aspect) do
			r += 0.5
		end
		r *= 1.03 -- a little room between the fitted angles
		table.insert(s.Fit :: { number }, r)
		far = math.max(far, r)
	end
	s.R, s.H = far, far * FightCamRules.LOW
	return s
end

-- The fitted base distance at orbit angle `a`.
function FightCamRules.radiusAt(s: Stage, a: number): number
	local fit = s.Fit
	if not fit or #fit < 2 then
		return s.R
	end
	local lo, hi = FightCamRules.BASE_ANGLE - FightCamRules.BASE_SWING, FightCamRules.BASE_ANGLE + FightCamRules.BASE_SWING
	local u = math.clamp((a - lo) / (hi - lo), 0, 1) * (#fit - 1) + 1
	local i = math.min(math.floor(u), #fit - 1)
	return fit[i] + (fit[i + 1] - fit[i]) * (u - i)
end
FightCamRules.MAX_R = 80

-- The base view at fight time t: a three-quarter side view (the player's team on one side of the screen, the rival's
-- on the other, like a fighting game) that orbits slowly round the fight (between about 43 and 83 degrees off the
-- player's back, a sweep every ~14 s) and dollies in and out, so the shot is always moving. Never behind the player's
-- avatar (Studio test 2026-10-14: a tiny pan low behind the avatar read as a still camera).
FightCamRules.BASE_ANGLE = 1.1 -- radians off Back towards Right (mostly side-on: both teams across the frame)
FightCamRules.BASE_SWING = 0.35 -- +- radians of orbit

-- What the base view looks at: the middle of the fight at about half the pets' height (so tall pets are centred
-- too), a little towards the player's own team (it is nearer the camera, so this centres the two teams on screen).
function FightCamRules.focus(s: Stage): Vector3
	return s.Centre + UP * ((s.Aim or 1) - 1.5) + s.Back * 2
end

function FightCamRules.baseAngle(t: number): number
	return FightCamRules.BASE_ANGLE + math.sin(t * 0.45) * FightCamRules.BASE_SWING
end

-- The dolly: breathes out from the fitted distance and back (never closer, so no pet leaves the frame).
local function dolly(t: number): number
	return 1 + 0.08 * (0.5 + 0.5 * math.sin(t * 0.6 + 1))
end

function FightCamRules.basePos(s: Stage, t: number): Vector3
	local a = FightCamRules.baseAngle(t)
	return orbitAt(s, a, FightCamRules.radiusAt(s, a) * dolly(t))
end

function FightCamRules.base(s: Stage, t: number): CFrame
	return CFrame.lookAt(FightCamRules.basePos(s, t), FightCamRules.focus(s))
end

-- Reduce Motion: one still view (the middle of the orbit).
function FightCamRules.still(s: Stage): CFrame
	local a = FightCamRules.BASE_ANGLE
	return CFrame.lookAt(orbitAt(s, a, FightCamRules.radiusAt(s, a)), FightCamRules.focus(s))
end

FightCamRules.NUDGE_AIM, FightCamRules.NUDGE_MOVE = 0.2, 0.07

-- A hit lands on a pet at `at`: the base view leans towards it and pushes in a little (k = 0..1 strength).
function FightCamRules.nudge(base: CFrame, s: Stage, at: Vector3, k: number): CFrame
	k = math.clamp(k, 0, 1)
	local aim = FightCamRules.focus(s):Lerp(at, FightCamRules.NUDGE_AIM * k)
	local pos = base.Position:Lerp(at, FightCamRules.NUDGE_MOVE * k)
	return CFrame.lookAt(pos, aim)
end

-- The opening sweep, u = 0..1: starts wide and high over the rival's side of the arena and swings round and in to
-- the base view (u = 1 lands exactly on base(0)).
function FightCamRules.introAt(s: Stage, u: number): CFrame
	local e = ease(u)
	local a0 = FightCamRules.baseAngle(0)
	local r0 = FightCamRules.radiusAt(s, a0) * dolly(0) -- base(0)'s distance
	return CFrame.lookAt(orbitAt(s, a0 + (1 - e) * 2.4, r0 * (1.7 - 0.7 * e)), FightCamRules.focus(s))
end

function FightCamRules.intro(s: Stage, u: number, _base: CFrame?): CFrame
	return FightCamRules.introAt(s, u)
end

-- Side-on close-up of a pet that was hit (`from` = the attacker, when known), easing in a little over the shot.
-- The camera stays on the player's side of the fight.
function FightCamRules.closeUp(s: Stage, at: Vector3, from: Vector3?, size: number, t: number): CFrame
	local axis = if from then flat(at - from, s.Back) else s.Back
	local side = axis:Cross(UP)
	side = if side.Magnitude > 1e-3 then side.Unit else s.Right
	if side:Dot(s.Back) < 0 then
		side = -side
	end
	local dist = (size * 1.4 + 5) * (1 - 0.1 * math.clamp(t, 0, 1))
	local pos = at + (side * 0.85 + s.Back * 0.35).Unit * dist + UP * (size * 0.35 + 1.6)
	return CFrame.lookAt(pos, at)
end

-- Over the shoulder of the player's SPECIAL caster, looking at the rival team.
function FightCamRules.shoulder(s: Stage, caster: Vector3, _from: Vector3?): CFrame
	local pos = caster + s.Back * 5.5 + s.Right * 2.2 + UP * 3
	return CFrame.lookAt(pos, caster - s.Back * 14)
end

-- K.O. orbit round the pet that fainted (about 65 degrees a second).
function FightCamRules.orbit(s: Stage, at: Vector3, size: number, t: number): CFrame
	local dist = size * 1.2 + 6
	local pos = at + turn(s.Back, 0.6 + t * 1.15) * dist + UP * (2.5 + size * 0.3)
	return CFrame.lookAt(pos, at)
end

-- Three-quarter hero shot looking down on the pet (about 28 degrees) so it stands out against the floor, pushing in
-- over 2.5 s and holding. FightCam narrows the lens to HERO_FOV for it, so even a small pet fills the middle.
FightCamRules.HERO_FOV = 42
function FightCamRules.hero(s: Stage, at: Vector3, size: number, t: number): CFrame
	local dist = (size * 0.8 + 4) * (1.15 - 0.15 * math.clamp(t / 2.5, 0, 1))
	local pos = at + turn(s.Back, 0.55) * dist + UP * (dist * 0.53)
	return CFrame.lookAt(pos, at + UP * size * 0.4) -- a little above the pet: its power card stays in frame
end

-- Frame-rate independent easing factor towards the target camera.
function FightCamRules.alpha(k: number, dt: number): number
	return 1 - math.exp(-k * math.max(dt, 0))
end

return FightCamRules
