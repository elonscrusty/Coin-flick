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

-- How many full spins a flip of `duration` seconds makes (faster flips still spin a lot).
function FlipArc.spins(duration: number): number
	return 3 + math.floor(math.max(0, duration) * 2)
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

return FlipArc
