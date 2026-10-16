--!strict
-- Line of sight for a pickup (Master Prompt 6 section 5): the SERVER checks that nothing solid stands between the
-- character's head and the rock. This module is the pure part (no raycast API), so Lune can test it; RockService
-- supplies the real `cast` function. Rocks themselves are not server instances (the pile is deterministic data), so
-- "the pile's other rocks" can never block here; characters, carried things and decor (CameraIgnore, non-collidable
-- or see-through parts) are skipped, so only solid world geometry such as a wall, a cliff face or the drop between
-- the two quarry levels can refuse a pickup.
local SightRules = {}

SightRules.EYE_LIFT = 1.5 -- studs above the root part when the Head cannot be found
SightRules.STOP_SHORT = 0.9 -- fraction of the rock radius the ray stops before the rock centre
SightRules.MAX_STEPS = 24 -- casts per check; more means a cluster of ignorable parts: the check fails closed
SightRules.EPSILON = 0.02

export type Part = {
	CanCollide: boolean,
	CameraIgnore: boolean,
	Character: boolean, -- part of any player's character (own, partner, or a held tool)
	Transparency: number,
}

export type Hit = { Distance: number, Part: Part }

-- Where the check starts: the head when there is one, otherwise a fixed lift above the root part.
function SightRules.eye(rootPos: Vector3, headPos: Vector3?): Vector3
	if headPos then
		return headPos
	end
	return rootPos + Vector3.new(0, SightRules.EYE_LIFT, 0)
end

-- The point the ray must reach: on the line eye -> rock centre, just before the rock's own shell.
function SightRules.target(eye: Vector3, rockCentre: Vector3, rockSize: number): Vector3
	local d = rockCentre - eye
	local len = d.Magnitude
	if len < 1e-4 then
		return rockCentre
	end
	local back = math.min(len, rockSize * 0.5 * SightRules.STOP_SHORT)
	return eye + d * ((len - back) / len)
end

-- Does this part count as a wall for pickups?
function SightRules.blocks(p: Part): boolean
	if p.Character or p.CameraIgnore or not p.CanCollide or p.Transparency >= 0.95 then
		return false
	end
	return true
end

-- cast(origin, direction) -> Hit? : the first part along the segment, whatever it is (RockService wraps Raycast).
-- Walks past ignorable parts. True when the segment reaches `target` unobstructed.
function SightRules.clear(eye: Vector3, target: Vector3, cast: (Vector3, Vector3) -> Hit?): boolean
	local origin = eye
	for _ = 1, SightRules.MAX_STEPS do
		local d = target - origin
		local len = d.Magnitude
		if len <= SightRules.EPSILON then
			return true
		end
		local hit = cast(origin, d)
		if not hit or hit.Distance >= len - SightRules.EPSILON then
			return true
		end
		if SightRules.blocks(hit.Part) then
			return false
		end
		origin = origin + d.Unit * (hit.Distance + SightRules.EPSILON)
	end
	return false -- ran out of casts before reaching the target: refuse (fails closed)
end

-- The full pickup check. A raycast that starts inside a part never reports that part, so a head pushed into a wall
-- would see straight through it. The segment root -> eye is checked first (the root sits inside the character's
-- collision box, never inside a wall), then eye -> target.
function SightRules.clearFrom(root: Vector3, eye: Vector3, target: Vector3, cast: (Vector3, Vector3) -> Hit?): boolean
	if not SightRules.clear(root, eye, cast) then
		return false
	end
	return SightRules.clear(eye, target, cast)
end

return SightRules
