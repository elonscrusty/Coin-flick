--!strict
-- Where a coin pet walks, as pure numbers (the client moves every pet locally each frame; nothing is sent over
-- the network). The pet trots behind-right of its owner, never closer than a friendly distance, and hops.

local PetFollowMath = {}

PetFollowMath.BEHIND = 4.5 -- studs behind the owner
PetFollowMath.SIDE = 2.6 -- studs to the owner's right
PetFollowMath.FOOT_DROP = 2.8 -- owner root part is about this far above the ground
PetFollowMath.CATCH_UP = 5 -- bigger = the pet closes the gap faster
PetFollowMath.TELEPORT = 60 -- farther than this (owner respawned or teleported): snap to the spot
PetFollowMath.MOVING_ABOVE = 0.5 -- studs from the spot before the pet counts as walking
PetFollowMath.FLIP_HOP_SECONDS = 0.5

-- The spot the pet wants to stand at, from the owner's root position (x, y, z) and look direction (lx, lz;
-- y is ignored, length does not matter). Plain numbers so the rules run offline.
function PetFollowMath.spot(
	rx: number,
	ry: number,
	rz: number,
	lx: number,
	lz: number,
	slot: number?
): (number, number, number)
	local len = math.sqrt(lx * lx + lz * lz)
	local fx, fz = 0, -1
	if len > 1e-3 then
		fx, fz = lx / len, lz / len
	end
	local rightX, rightZ = -fz, fx -- look x up: +X when looking down -Z
	local back = PetFollowMath.BEHIND + (if slot and slot > 1 then (slot - 1) * 2.5 else 0) -- extra pets stand further back
	return rx - fx * back + rightX * PetFollowMath.SIDE,
		ry - PetFollowMath.FOOT_DROP,
		rz - fz * back + rightZ * PetFollowMath.SIDE
end

local function dist(ax: number, ay: number, az: number, bx: number, by: number, bz: number): number
	local dx, dy, dz = bx - ax, by - ay, bz - az
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- One frame of smooth movement from (px, py, pz) toward the spot. Frame-rate independent; never overshoots.
function PetFollowMath.step(
	px: number,
	py: number,
	pz: number,
	sx: number,
	sy: number,
	sz: number,
	dt: number
): (number, number, number)
	if dist(px, py, pz, sx, sy, sz) > PetFollowMath.TELEPORT then
		return sx, sy, sz
	end
	local alpha = 1 - math.exp(-PetFollowMath.CATCH_UP * math.clamp(dt, 0, 0.25))
	return px + (sx - px) * alpha, py + (sy - py) * alpha, pz + (sz - pz) * alpha
end

function PetFollowMath.isMoving(px: number, py: number, pz: number, sx: number, sy: number, sz: number): boolean
	return dist(px, py, pz, sx, sy, sz) > PetFollowMath.MOVING_ABOVE
end

-- Hop height at time `now`: a small bounce while walking, a gentle bob when still, and a big happy jump
-- for FLIP_HOP_SECONDS after the pet flipped its coin (`sinceFlip` seconds ago, nil = never).
function PetFollowMath.hop(now: number, phase: number, moving: boolean, sinceFlip: number?): number
	local h = if moving then math.abs(math.sin(now * 9 + phase)) * 0.6 else (math.sin(now * 2 + phase) + 1) * 0.08
	if sinceFlip and sinceFlip >= 0 and sinceFlip < PetFollowMath.FLIP_HOP_SECONDS then
		h += math.sin(math.pi * sinceFlip / PetFollowMath.FLIP_HOP_SECONDS) * 1.8
	end
	return h
end

return PetFollowMath
