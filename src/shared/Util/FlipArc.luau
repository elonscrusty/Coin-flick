--!strict
-- The path of a flipping coin: up, spin, down, little bounce. Pure numbers so
-- the Lune tests can check the coin really jumps (pictures showed it barely lifting).

local Config = require(script.Parent.Parent.Config)

local FlipArc = {}

FlipArc.MAIN = 0.8 -- share of the flip spent in the air before the little bounce
FlipArc.BOUNCE = 0.15 -- bounce height, as a share of the jump

-- Studs above the table at `t` (0..1 of the flip) for a jump `peak` studs high.
function FlipArc.height(t: number, peak: number?): number
	local top = peak or Config.FLIP_HEIGHT
	local u = math.clamp(t, 0, 1)
	if u < FlipArc.MAIN then
		local a = u / FlipArc.MAIN
		return top * 4 * a * (1 - a)
	end
	local b = (u - FlipArc.MAIN) / (1 - FlipArc.MAIN)
	return top * FlipArc.BOUNCE * 4 * b * (1 - b)
end

-- The roll (about the coin's own Z axis) that leaves each face up: heads = the "$" (Right) face,
-- anything else = the hat (Left) face. The server rests coins with this and the client lands on it.
function FlipArc.restRoll(face: unknown): number
	return if face == "heads" then math.pi / 2 else -math.pi / 2
end

-- Which cap of the coin points up at a given roll: the Right (+X) face when sin(roll) > 0, else the Left face.
-- The coin art is "$" on Right and the hat on Left (see Tables.coinFace), so this tells what a player sees.
FlipArc.FACE_ART = table.freeze({ Right = "$", Left = "hat" })
function FlipArc.upFace(roll: number): string
	return if math.sin(roll) > 0 then "Right" else "Left"
end
function FlipArc.visibleArt(roll: number): string
	return FlipArc.FACE_ART[FlipArc.upFace(roll)]
end

-- How many full spins a flip of `duration` seconds makes (faster flips still spin a lot).
function FlipArc.spins(duration: number): number
	return 3 + math.floor(math.max(0, duration) * 2)
end

-- Which way to turn a table's coins so they always spin TOWARD the ZOOM camera (like a
-- real coin flip seen from the player), never in a flat "wheel" that looks like a thin
-- sliver. The spin axis is the sideways direction (perpendicular to `outward`, the way the
-- camera looks). Returns a yaw in radians: turn the whole coin by it around the up axis.
function FlipArc.spinYaw(outwardX: number, outwardZ: number): number
	if outwardX == 0 and outwardZ == 0 then
		return 0
	end
	return math.atan2(-outwardZ, outwardX)
end

-- The sideways spin axis (x, z) that goes with a yaw: rotating (0, 0, 1) around up by `yaw`.
function FlipArc.spinAxis(yaw: number): (number, number)
	return math.sin(yaw), math.cos(yaw)
end

-- Shadow under the coin: full size on the table, half size at the top of the jump.
function FlipArc.shadowScale(height: number, peak: number?): number
	local top = peak or Config.FLIP_HEIGHT
	return 1 - 0.5 * math.clamp(height / top, 0, 1)
end

-- Shadow see-through amount: darker when the coin is low.
function FlipArc.shadowFade(height: number, peak: number?): number
	local top = peak or Config.FLIP_HEIGHT
	return 0.45 + 0.4 * math.clamp(height / top, 0, 1)
end

-- The mega coin stands on its edge with its faces along world Z. Turning it by this yaw (about
-- its own up axis) points a face at a viewer standing (dx, dz) away, so it is never seen edge-on.
function FlipArc.megaFacing(dx: number, dz: number): number
	if dx == 0 and dz == 0 then
		return 0
	end
	return math.atan2(-dx, -dz)
end

-- Extra turn of the mega coin `u` (0..1) of the way through its big jump: three fast turns that
-- ease out and end exactly on a full turn, so it lands facing the viewer again.
function FlipArc.megaSpin(u: number): number
	local c = math.clamp(u, 0, 1)
	return math.pi * 6 * (1 - (1 - c) * (1 - c))
end

return FlipArc
