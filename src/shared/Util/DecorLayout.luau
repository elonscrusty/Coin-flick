--!strict
-- Where the world decorations go around the yards. Pure numbers (x, z, yaw, size), so tests
-- can prove nothing lands inside a yard, on a path, on the plaza or on the spawn, and that
-- no two props overlap. Same seed = same spots on every server.
--
-- Two zones:
--   inner  small props (lamps, benches, bushes) in the gaps between the paths, near the plaza
--   outer  trees, boulders, bushes, logs, mushrooms and flower beds past the yards

export type Spot = {
	x: number,
	z: number,
	yaw: number, -- radians
	scale: number,
	kind: string,
	zone: string,
	radius: number, -- footprint, studs (already scaled)
}

export type Params = {
	ringRadius: number, -- distance of every yard centre from the middle
	plotSize: number, -- side of a square yard
	maxPlots: number,
	plazaRadius: number, -- sandy plaza in the middle
	spawnZ: number, -- spawn pad sits at (0, spawnZ)
	pathWidth: number,
	extent: number, -- nothing past this distance from the middle
	seed: number,
	outerCount: number,
	innerCount: number,
}

local DecorLayout = {}

DecorLayout.Clear = 3 -- studs of free space around every yard and path

-- footprint radius (at scale 1) and share of the outer zone
local OUTER: { { kind: string, radius: number, weight: number, min: number, max: number } } = {
	{ kind = "tree", radius = 3.2, weight = 5, min = 1.2, max = 2.0 },
	{ kind = "boulder", radius = 3.0, weight = 3, min = 1.0, max = 2.2 },
	{ kind = "bush", radius = 1.8, weight = 3, min = 1.0, max = 1.6 },
	{ kind = "log", radius = 2.4, weight = 1, min = 1.0, max = 1.5 },
	{ kind = "mushroom", radius = 1.4, weight = 1, min = 1.0, max = 1.8 },
	{ kind = "flowerbed", radius = 2.6, weight = 2, min = 1.0, max = 1.4 },
}
local INNER: { { kind: string, radius: number, weight: number, min: number, max: number } } = {
	{ kind = "lamp", radius = 1.0, weight = 3, min = 1.0, max = 1.0 },
	{ kind = "bench", radius = 2.4, weight = 2, min = 1.0, max = 1.0 },
	{ kind = "bush", radius = 1.6, weight = 2, min = 1.0, max = 1.3 },
}

DecorLayout.OuterKinds = OUTER
DecorLayout.InnerKinds = INNER

DecorLayout.defaults = table.freeze({
	ringRadius = 72,
	plotSize = 36,
	maxPlots = 8,
	plazaRadius = 23,
	spawnZ = 26,
	pathWidth = 6,
	extent = 200,
	seed = 11,
	outerCount = 110,
	innerCount = 16,
} :: Params)

-- Small deterministic random numbers (no Roblox Random needed).
local function lcg(seed: number): () -> number
	local state = (seed * 2654435761 + 12345) % 4294967296
	return function(): number
		state = (state * 1664525 + 1013904223) % 4294967296
		return state / 4294967296
	end
end

local function pick(list: { { kind: string, radius: number, weight: number, min: number, max: number } }, r: number)
	local total = 0
	for _, e in list do
		total += e.weight
	end
	local t = r * total
	for _, e in list do
		t -= e.weight
		if t <= 0 then
			return e
		end
	end
	return list[#list]
end

-- Distance from point (x, z) to the straight path from the middle to yard `slot`'s entrance.
function DecorLayout.pathDistance(p: Params, x: number, z: number): number
	local best = math.huge
	for slot = 1, p.maxPlots do
		local a = (slot - 1) / p.maxPlots * math.pi * 2
		local dx, dz = math.cos(a), math.sin(a)
		local along = x * dx + z * dz
		if along > 0 then
			local perp = math.abs(-x * dz + z * dx)
			best = math.min(best, perp)
		end
	end
	return best
end

-- Smallest gap between a circle (x, z, radius) and every yard (treated as its circumscribed circle).
function DecorLayout.yardGap(p: Params, x: number, z: number, radius: number): number
	local yardR = p.plotSize / 2 * math.sqrt(2)
	local best = math.huge
	for slot = 1, p.maxPlots do
		local a = (slot - 1) / p.maxPlots * math.pi * 2
		local cx, cz = math.cos(a) * p.ringRadius, math.sin(a) * p.ringRadius
		best = math.min(best, math.sqrt((x - cx) ^ 2 + (z - cz) ^ 2) - yardR - radius)
	end
	return best
end

-- Is a circle (x, z, radius) free of the yards, paths, plaza, spawn and the world edge?
function DecorLayout.isFree(p: Params, x: number, z: number, radius: number): boolean
	local d = math.sqrt(x * x + z * z)
	if d + radius > p.extent then
		return false
	end
	if d - radius < p.plazaRadius + DecorLayout.Clear then
		return false
	end
	if math.sqrt(x * x + (z - p.spawnZ) ^ 2) - radius < 7 + DecorLayout.Clear then
		return false
	end
	if DecorLayout.yardGap(p, x, z, radius) < DecorLayout.Clear then
		return false
	end
	if DecorLayout.pathDistance(p, x, z) - radius < p.pathWidth / 2 + DecorLayout.Clear then
		return false
	end
	return true
end

function DecorLayout.spots(params: Params?): { Spot }
	local p = params or DecorLayout.defaults
	local rand = lcg(p.seed)
	local out: { Spot } = {}

	local function room(x: number, z: number, radius: number): boolean
		for _, s in out do
			local dx, dz = s.x - x, s.z - z
			if dx * dx + dz * dz < (s.radius + radius + 0.5) ^ 2 then
				return false
			end
		end
		return true
	end

	local function fill(zone: string, count: number, kinds: typeof(OUTER), rMin: number, rMax: number)
		local added, tries = 0, 0
		while added < count and tries < count * 60 do
			tries += 1
			local def = pick(kinds, rand())
			local scale = def.min + (def.max - def.min) * rand()
			local radius = def.radius * scale
			-- area-fair radius so the outskirts are not bare
			local d = math.sqrt(rMin * rMin + (rMax * rMax - rMin * rMin) * rand())
			local a = rand() * math.pi * 2
			local x, z = math.cos(a) * d, math.sin(a) * d
			if DecorLayout.isFree(p, x, z, radius) and room(x, z, radius) then
				table.insert(out, {
					x = x,
					z = z,
					yaw = rand() * math.pi * 2,
					scale = scale,
					kind = def.kind,
					zone = zone,
					radius = radius,
				})
				added += 1
			end
		end
	end

	fill("inner", p.innerCount, INNER, p.plazaRadius, p.ringRadius)
	fill("outer", p.outerCount, OUTER, p.ringRadius, p.extent)
	return out
end

return DecorLayout
