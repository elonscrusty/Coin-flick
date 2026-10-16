--!strict
-- Egg gravity for the hunt pile (carter 2026-10-16: "the eggs during the hunt should have gravity"). Pure maths, tested
-- in tests/test_egg_fall.luau; the client (PileView) samples it, the server never moves eggs.
--
-- An egg that moves on the pile (it settles when the egg under it is taken, a returned egg drops back on, the gold
-- overtime egg hops to the edge) flies a real gravity path: it speeds up as it falls (never eases in to land softly,
-- which read as floating), lands, then makes one small bounce. A move that goes up or sideways first hops over the
-- mound in a parabola. No physics engine: the pile stays deterministic and costs nothing per frame when still.

local EggFall = {}

export type Plan = {
	From: Vector3,
	To: Vector3,
	G: number, -- gravity, studs/s^2
	Vy0: number, -- launch speed up (0 for a plain drop)
	Flight: number, -- seconds from start to first touch-down
	Hop: number, -- bounce speed up at touch-down
	Dur: number, -- whole motion incl. the bounce
}

EggFall.Restitution = 0.3 -- bounce speed / landing speed
EggFall.MinFlight = 0.05

-- `maxHop`: highest bounce in studs. A move that rises, or slides sideways more than `sideways` studs, gets an arc
-- whose top clears the higher end by a third of the sideways distance (at most `maxLift`).
function EggFall.plan(from: Vector3, to: Vector3, g: number, maxHop: number, sideways: number?, maxLift: number?): Plan
	g = math.max(g, 1)
	local horiz = Vector3.new(to.X - from.X, 0, to.Z - from.Z).Magnitude
	local apex = math.max(from.Y, to.Y)
	if to.Y > from.Y - 0.01 or horiz > (sideways or math.huge) then
		apex += math.max(0.3, math.min(horiz / 3, maxLift or 4))
	end
	local up = math.max(0, apex - from.Y)
	local down = math.max(0, apex - to.Y)
	local tUp = math.sqrt(2 * up / g)
	local tDown = math.sqrt(2 * down / g)
	local flight = math.max(EggFall.MinFlight, tUp + tDown)
	local landSpeed = g * tDown
	local hopHeight = math.min(maxHop, (landSpeed * EggFall.Restitution) ^ 2 / (2 * g))
	local hop = math.sqrt(2 * g * math.max(0, hopHeight))
	return {
		From = from,
		To = to,
		G = g,
		Vy0 = g * tUp,
		Flight = flight,
		Hop = hop,
		Dur = flight + 2 * hop / g,
	}
end

-- Position at `t` seconds (clamped to the plan). Height follows gravity; across the ground it moves evenly during the
-- flight and stays put during the bounce.
function EggFall.at(p: Plan, t: number): Vector3
	t = math.clamp(t, 0, p.Dur)
	if t >= p.Flight then
		local s = t - p.Flight
		local y = math.max(0, p.Hop * s - 0.5 * p.G * s * s)
		return p.To + Vector3.new(0, y, 0)
	end
	local k = t / p.Flight
	local flat = p.From:Lerp(p.To, k)
	local y = p.From.Y + p.Vy0 * t - 0.5 * p.G * t * t
	-- tUp + tDown was rounded up to MinFlight for tiny moves: blend to the goal height so it always touches down exactly
	local yLine = p.From.Y + (p.To.Y - p.From.Y) * k
	if p.Flight <= EggFall.MinFlight + 1e-6 then
		y = yLine
	end
	return Vector3.new(flat.X, math.max(y, math.min(p.To.Y, yLine)), flat.Z)
end

-- Share of the flight done at `t` (0..1), for turning the egg from its old facing to its new one.
function EggFall.turn(p: Plan, t: number): number
	return math.clamp(t / p.Flight, 0, 1)
end

return EggFall
