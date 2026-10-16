--!strict
-- Where the world's big cartoon scenery goes: sky clouds, balloons, floating islands, hills, the
-- fountains and rings on the plaza, and the colours of every path. Pure numbers (no Roblox
-- types), so tests/specs/WorldArt.spec.luau can prove nothing overlaps and everything is bright.
-- Builders/WorldArt turns these into parts; client/Controllers/SkyFx makes the sky things bob.
-- Same seed = same world on every server.

local SkyLayout = {}

export type Item = { x: number, y: number, z: number, scale: number, color: number, spin: number, phase: number }
export type Hill = { x: number, z: number, size: number, color: Color3, cap: Color3 }
export type Ring = { diameter: number, color: Color3 }

-- Small deterministic random numbers (no Roblox Random needed).
local function lcg(seed: number): () -> number
	local state = (seed * 2654435761 + 12345) % 4294967296
	return function(): number
		state = (state * 1664525 + 1013904223) % 4294967296
		return state / 4294967296
	end
end

-- Saturated, happy colours.
SkyLayout.BALLOONS = table.freeze({
	Color3.fromRGB(255, 70, 100),
	Color3.fromRGB(255, 200, 40),
	Color3.fromRGB(60, 190, 255),
	Color3.fromRGB(120, 230, 90),
	Color3.fromRGB(190, 110, 255),
	Color3.fromRGB(255, 140, 40),
})

-- Hills: many greens plus a few warm and cool ones, so the horizon is not one flat colour.
SkyLayout.HILL_COLORS = table.freeze({
	{ Color3.fromRGB(95, 205, 85), Color3.fromRGB(140, 230, 100) },
	{ Color3.fromRGB(125, 215, 80), Color3.fromRGB(175, 235, 95) },
	{ Color3.fromRGB(70, 190, 120), Color3.fromRGB(120, 225, 150) },
	{ Color3.fromRGB(60, 185, 175), Color3.fromRGB(110, 225, 215) },
	{ Color3.fromRGB(190, 215, 80), Color3.fromRGB(235, 240, 110) },
	{ Color3.fromRGB(255, 190, 90), Color3.fromRGB(255, 225, 130) },
	{ Color3.fromRGB(255, 150, 190), Color3.fromRGB(255, 195, 220) },
	{ Color3.fromRGB(150, 140, 235), Color3.fromRGB(195, 185, 255) },
})
-- Index weights: mostly greens.
local HILL_PICK = { 1, 2, 3, 1, 2, 4, 5, 1, 3, 2, 6, 7, 1, 8, 2, 4 }

-- The sandy plaza is 46 wide; these coloured discs sit on it (largest first), under the mega pedestal.
SkyLayout.PLAZA_RINGS = table.freeze({
	{ diameter = 44, color = Color3.fromRGB(255, 205, 60) },
	{ diameter = 41, color = Color3.fromRGB(255, 248, 225) },
	{ diameter = 37, color = Color3.fromRGB(70, 175, 255) },
	{ diameter = 33.5, color = Color3.fromRGB(255, 248, 225) },
	{ diameter = 28, color = Color3.fromRGB(255, 130, 190) },
	{ diameter = 24, color = Color3.fromRGB(255, 248, 225) },
} :: { Ring })

-- Each path (one per yard) gets its own happy colour of curb.
SkyLayout.PATH_EDGES = table.freeze({
	Color3.fromRGB(255, 90, 140),
	Color3.fromRGB(70, 175, 255),
	Color3.fromRGB(255, 190, 40),
	Color3.fromRGB(110, 220, 90),
	Color3.fromRGB(190, 120, 255),
	Color3.fromRGB(255, 140, 50),
	Color3.fromRGB(60, 205, 190),
	Color3.fromRGB(255, 110, 100),
})
SkyLayout.PATH_SURFACE = Color3.fromRGB(255, 232, 170)
SkyLayout.PATH_DASH = Color3.fromRGB(255, 255, 255)

-- Fountains on the plaza, away from the mega pedestal in the middle and the paths.
SkyLayout.FOUNTAIN_RADIUS = 15
SkyLayout.FOUNTAIN_SIZE = 4.6 -- footprint radius (studs)

function SkyLayout.fountains(maxPlots: number): { { x: number, z: number } }
	local out = {}
	for k = 0, 3 do
		-- Between paths: half a plot step off the first path, every quarter turn.
		local a = (k * 0.25 + 0.5 / maxPlots) * math.pi * 2
		table.insert(out, { x = math.cos(a) * SkyLayout.FOUNTAIN_RADIUS, z = math.sin(a) * SkyLayout.FOUNTAIN_RADIUS })
	end
	return out
end

local function spread(
	count: number,
	seed: number,
	rMin: number,
	rMax: number,
	yMin: number,
	yMax: number,
	sMin: number,
	sMax: number,
	footprint: number,
	colors: number
): { Item }
	local rand = lcg(seed)
	local out: { Item } = {}
	local tries = 0
	while #out < count and tries < count * 80 do
		tries += 1
		local a = rand() * math.pi * 2
		local d = rMin + (rMax - rMin) * rand()
		local item: Item = {
			x = math.cos(a) * d,
			z = math.sin(a) * d,
			y = yMin + (yMax - yMin) * rand(),
			scale = sMin + (sMax - sMin) * rand(),
			color = math.floor(rand() * colors) + 1,
			spin = (rand() - 0.5) * 0.3,
			phase = rand() * math.pi * 2,
		}
		local ok = true
		for _, other in out do
			local dx, dz = other.x - item.x, other.z - item.z
			local need = (other.scale + item.scale) * footprint
			if dx * dx + dz * dz < need * need then
				ok = false
				break
			end
		end
		if ok then
			table.insert(out, item)
		end
	end
	return out
end

-- Footprint (studs per unit of scale, radius) of each sky thing, used for spacing.
SkyLayout.CLOUD_FOOTPRINT = 9
SkyLayout.BALLOON_FOOTPRINT = 5
SkyLayout.ISLAND_FOOTPRINT = 14

function SkyLayout.clouds(): { Item }
	return spread(26, 5, 60, 215, 78, 125, 1.0, 2.2, SkyLayout.CLOUD_FOOTPRINT, 1)
end

function SkyLayout.balloons(): { Item }
	return spread(14, 9, 45, 190, 42, 88, 1.0, 1.5, SkyLayout.BALLOON_FOOTPRINT, #SkyLayout.BALLOONS)
end

function SkyLayout.islands(): { Item }
	return spread(6, 21, 115, 195, 58, 98, 1.0, 1.5, SkyLayout.ISLAND_FOOTPRINT, 1)
end

-- Rolling hills all round the edge, in a mix of colours. `cap` is a lighter top patch.
function SkyLayout.hills(): { Hill }
	local rand = lcg(33)
	local count = 30
	local out: { Hill } = {}
	for i = 1, count do
		local pair = SkyLayout.HILL_COLORS[HILL_PICK[(i - 1) % #HILL_PICK + 1]]
		table.insert(out, {
			x = 0,
			z = 0,
			size = 60 + rand() * 42,
			color = pair[1],
			cap = pair[2],
		})
		local a = (i / count) * math.pi * 2 + (rand() - 0.5) * 0.08
		local d = 212 + rand() * 24
		out[i].x = math.cos(a) * d
		out[i].z = math.sin(a) * d
	end
	return out
end

-- Flowers along both edges of a path: distances along the path from the middle, and sideways.
SkyLayout.PATH_FLOWER_SIDE = 5.4
function SkyLayout.pathFlowers(from: number, to: number): { number }
	local out = {}
	local d = from + 3
	while d < to - 2 do
		table.insert(out, d)
		d += 5.5
	end
	return out
end

return SkyLayout
