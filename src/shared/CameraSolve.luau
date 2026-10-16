--!strict
-- Pure helpers for the client camera guard (src/client/CameraGuard.luau, Master Prompt 4 section 28).
-- The guard casts from the head towards the camera the default camera script chose; this module turns the
-- distances of what was hit into a safe camera distance and eases it back out smoothly.
local CameraSolve = {}

CameraSolve.Margin = 0.6 -- studs kept between the camera and the surface it stops at
CameraSolve.MinDistance = 2.2 -- never pull the camera closer to the head than this
CameraSolve.Recover = 9 -- studs per second the camera is allowed to move back out

-- `wanted`: distance the default camera chose. `hits`: distance to the first blocking surface of each probe
-- ray (nil = that ray hit nothing). Returns the distance to use now (<= wanted).
function CameraSolve.allowed(wanted: number, hits: { number? }): number
	local nearest = wanted
	for _, h in hits do
		if h then
			nearest = math.min(nearest, h - CameraSolve.Margin)
		end
	end
	return math.clamp(nearest, math.min(CameraSolve.MinDistance, wanted), wanted)
end

-- Snap in at once (never show the inside of a wall), ease out at Recover studs per second.
function CameraSolve.smooth(current: number?, target: number, dt: number): number
	if current == nil or target <= current then
		return target
	end
	return math.min(target, current + CameraSolve.Recover * dt)
end

local function exitAxis(o: number, d: number, lo: number, hi: number): number
	if d > 1e-6 then
		return (hi - o) / d
	elseif d < -1e-6 then
		return (lo - o) / d
	end
	return math.huge
end

-- Room box for the third-person lobby camera: when `origin` (the head) is inside the axis-aligned box, the distance
-- along the unit `dir` to the first face it would leave through, else nil. The lodge's walls and ceiling are
-- invisible, non-queryable colliders under non-colliding kit meshes, so no ray can find them; this keeps the camera
-- in the room by geometry instead (CameraGuard adds it as one more hit).
function CameraSolve.boxExit(origin: Vector3, dir: Vector3, min: Vector3, max: Vector3): number?
	if origin.X <= min.X or origin.X >= max.X or origin.Y <= min.Y or origin.Y >= max.Y or origin.Z <= min.Z or origin.Z >= max.Z then
		return nil
	end
	local best = math.min(exitAxis(origin.X, dir.X, min.X, max.X), exitAxis(origin.Y, dir.Y, min.Y, max.Y), exitAxis(origin.Z, dir.Z, min.Z, max.Z))
	return if best == math.huge then nil else best
end

return CameraSolve
