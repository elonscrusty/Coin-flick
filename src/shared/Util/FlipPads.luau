--!strict
-- Flip pads: round pads on the yard floor beside the table. Walk onto one and a coin flips (server
-- checks where your avatar stands, so the client only walks). Pure numbers in yard-local studs
-- (x = across the yard, z = toward the back; the gate is at z = -half), tested in
-- tests/specs/FlipPads.spec.luau: inside the fence, clear of the table and of the yard's corner
-- pieces, never overlapping each other.

local FlipPads = {}

FlipPads.Radius = 1.8 -- drawn pad
FlipPads.TriggerRadius = 2.3 -- how close your feet must be
FlipPads.Cooldown = 2.0 -- seconds before the same pad flips again
FlipPads.Height = 0.1 -- flat on the floor: nothing to trip on, nothing in the camera's way

export type Pad = { x: number, z: number }

-- Two each side, between the table and the fence, out of the way of the gate walk-in.
FlipPads.pads = table.freeze({
	table.freeze({ x = -13.5, z = -5 }),
	table.freeze({ x = -13.5, z = -0.5 }),
	table.freeze({ x = 13.5, z = -5 }),
	table.freeze({ x = 13.5, z = -0.5 }),
} :: { Pad })

-- Which pad (index) a standing spot (yard-local x, z) is on, or nil.
function FlipPads.padAt(x: number, z: number): number?
	for index, pad in FlipPads.pads do
		local dx, dz = x - pad.x, z - pad.z
		if dx * dx + dz * dz <= FlipPads.TriggerRadius * FlipPads.TriggerRadius then
			return index
		end
	end
	return nil
end

return FlipPads
