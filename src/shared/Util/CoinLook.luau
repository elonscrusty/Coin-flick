--!strict
-- How every coin looks: plain coins and each rare coin.
-- Pure numbers and colors only (no Instances), so the rules are tested in Lune.
-- The server builds coins with NORMAL; the client dresses rare coins in the air.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local TableLayout = require(ReplicatedStorage.Shared.Util.TableLayout)

export type Look = {
	color: Color3,
	material: string, -- Enum.Material name; never Neon (sunlight washes Neon to white)
	reflectance: number,
	text: Color3, -- "$" and hat marks on the faces
	rim: Color3, -- painted ring around each face
	sparkle: { Color3 }, -- sparkle colors, first to last
	sparkleSize: number,
	landBurst: number, -- sparkles thrown when the coin lands on heads
	trail: number, -- sparkles per second while
	outline: Color3?, -- dark outline drawn around the coin in the air (stays on the coin, never lights the table)
	rainbow: boolean, -- color cycles through the rainbow while in the air
	stars: boolean, -- a ring of stars painted on both faces while in the air
}

local CoinLook = {}

-- Sparkles add light on top of what is behind them. Full strength (1) turned the
-- yellow table pale; this keeps them bright but lets the table color through.
CoinLook.SPARKLE_LIGHT = 0.35

-- Warm coin gold. Rare GOLD is a brighter lemon gold so the two never look alike.
CoinLook.NORMAL = table.freeze({
	color = Color3.fromRGB(176, 110, 28), -- warm bronze-gold, clearly darker than lemon GOLD and cooler SILVER
	material = "SmoothPlastic",
	reflectance = 0.15,
	text = Color3.fromRGB(255, 235, 170),
	rim = Color3.fromRGB(110, 60, 8),
	sparkle = { Color3.fromRGB(255, 240, 120), Color3.fromRGB(255, 255, 255) },
	sparkleSize = 0.6,
	landBurst = 14,
	trail = 0,
	rainbow = false,
	stars = false,
} :: Look)

local RARE: { [string]: Look } = {
	silver = table.freeze({
		color = Color3.fromRGB(140, 185, 235), -- light steel blue: never white, never a glow disc
		material = "Metal",
		reflectance = 0.1,
		text = Color3.fromRGB(20, 40, 100),
		rim = Color3.fromRGB(55, 85, 130), -- dark steel ridge
		sparkle = { Color3.fromRGB(190, 225, 255), Color3.fromRGB(120, 175, 235) },
		sparkleSize = 0.7,
		landBurst = 30,
		trail = 10,
		outline = Color3.fromRGB(20, 45, 110), -- thin dark blue outline
		rainbow = false,
		stars = false,
	} :: Look),
	gold = table.freeze({
		color = Color3.fromRGB(255, 200, 30), -- rich yellow-gold
		material = "Foil",
		reflectance = 0.3,
		text = Color3.fromRGB(100, 40, 0),
		rim = Color3.fromRGB(160, 90, 0), -- warm ridge
		sparkle = { Color3.fromRGB(255, 220, 60), Color3.fromRGB(255, 255, 200) },
		sparkleSize = 0.9,
		landBurst = 45,
		trail = 25,
		outline = Color3.fromRGB(120, 70, 0),
		rainbow = false,
		stars = true,
	} :: Look),
	rainbow = table.freeze({
		color = Color3.fromRGB(255, 120, 220), -- starting color; cycles in the air
		material = "SmoothPlastic",
		reflectance = 0.2,
		text = Color3.fromRGB(45, 20, 80),
		rim = Color3.fromRGB(110, 50, 190), -- violet ridge: seen edge-on it is a colored band, never a thin white line
		sparkle = { Color3.fromRGB(255, 120, 220), Color3.fromRGB(120, 220, 255) },
		sparkleSize = 1.0,
		landBurst = 80,
		trail = 45,
		outline = Color3.fromRGB(70, 25, 130),
		rainbow = true,
		stars = false,
	} :: Look),
	giant = table.freeze({
		color = Color3.fromRGB(255, 215, 120), -- pale shiny champagne gold: a huge shiny coin (not a lava ball)
		material = "Foil",
		reflectance = 0.5, -- white shine
		text = Color3.fromRGB(90, 40, 0),
		rim = Color3.fromRGB(200, 130, 20),
		sparkle = {
			Color3.fromRGB(255, 255, 255),
			Color3.fromRGB(255, 225, 80),
			Color3.fromRGB(255, 130, 220),
			Color3.fromRGB(110, 225, 255),
		},
		sparkleSize = 1.2,
		landBurst = 120,
		trail = 60,
		outline = Color3.fromRGB(90, 40, 0),
		rainbow = false,
		stars = false,
	} :: Look),
}
CoinLook.RARE = table.freeze(RARE)

function CoinLook.forRarity(id: string?): Look
	return if id then RARE[id] or CoinLook.NORMAL else CoinLook.NORMAL
end

-- 0..255 RGB from hue (0..1), saturation and value. Color3.fromHSV without Roblox.
function CoinLook.hsv(h: number, s: number, v: number): Color3
	h = (h % 1) * 6
	local i = math.floor(h)
	local f = h - i
	local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
	local r, g, b
	if i == 0 then
		r, g, b = v, t, p
	elseif i == 1 then
		r, g, b = q, v, p
	elseif i == 2 then
		r, g, b = p, v, t
	elseif i == 3 then
		r, g, b = p, q, v
	elseif i == 4 then
		r, g, b = t, p, v
	else
		r, g, b = v, p, q
	end
	return Color3.fromRGB(math.round(r * 255), math.round(g * 255), math.round(b * 255))
end

-- Soft rainbow: bright enough that the dark marks stay readable at every hue.
CoinLook.RAINBOW_SATURATION = 0.6
function CoinLook.rainbowColor(seconds: number): Color3
	return CoinLook.hsv(seconds * 1.5, CoinLook.RAINBOW_SATURATION, 1)
end

-- Colors painted across a rainbow coin's faces (so even a still picture shows
-- every color, not one solid color).
function CoinLook.rainbowStops(count: number): { Color3 }
	local out = {}
	for i = 0, count - 1 do
		table.insert(out, CoinLook.hsv(i / count, CoinLook.RAINBOW_SATURATION, 1))
	end
	return out
end

-- A darker shade (the rim for a skin color).
function CoinLook.darker(c: Color3, k: number): Color3
	return Color3.fromRGB(math.round(c.R * 255 * k), math.round(c.G * 255 * k), math.round(c.B * 255 * k))
end

local function lum(c: Color3): number
	local function ch(x: number): number
		return if x <= 0.03928 then x / 12.92 else ((x + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * ch(c.R) + 0.7152 * ch(c.G) + 0.0722 * ch(c.B)
end

-- Readability of one color on another (1 = same, 21 = black on white).
function CoinLook.contrast(a: Color3, b: Color3): number
	local la, lb = lum(a), lum(b)
	return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05)
end

-- How far apart two colors look, in 0..255 RGB steps.
function CoinLook.distance(a: Color3, b: Color3): number
	return math.sqrt(((a.R - b.R) * 255) ^ 2 + ((a.G - b.G) * 255) ^ 2 + ((a.B - b.B) * 255) ^ 2)
end

-- How big a rare coin is during its flip (t = 0..1 of the flip, main = share
-- spent in the air). Grows fast, stays big, shrinks back during the bounce.
function CoinLook.scale(grow: number, t: number, main: number): number
	local puff = if t < 0.15 then t / 0.15 elseif t < main then 1 else math.max(0, 1 - (t - main) / (1 - main))
	return 1 + (grow - 1) * puff
end

-- Coins grow evenly in every direction, so a GIANT coin stays a chunky coin
-- (never a thin squished pancake).
function CoinLook.size(rest: Vector3, scale: number): Vector3
	return rest * scale
end

-- Extra height so a spinning coin never cuts into the table. The coin's round
-- faces start pointing up; roll turns it on its edge. restThickness is how
-- high the coin's centre already sits above the table top. A grown coin is
-- wide enough to reach the coins next to it, so it also clears their height.
function CoinLook.lift(
	roll: number,
	thickness: number,
	diameter: number,
	restThickness: number,
	restDiameter: number
): number
	local half = thickness / 2 * math.abs(math.sin(roll)) + diameter / 2 * math.abs(math.cos(roll))
	local grownBy = diameter / restDiameter - 1
	local clearance = restThickness * math.clamp(grownBy * 4, 0, 1)
	return math.max(0, half - restThickness / 2 + clearance)
end

-- How far a coin may grow before it touches a neighbour or hangs off the table.
-- Every slot on the table counts as a neighbour (empty slots show a disc).
-- Returns a scale >= 1 to clamp a rare coin's `grow` with. `restDiameter` is the
-- diameter of the coins sitting on the other slots.
CoinLook.GAP = 0.1 -- air left between a grown coin (with its ridge) and its neighbours
CoinLook.RIDGE_WIDER = 1.12 -- the ridge ring is this much wider than the coin
CoinLook.EDGE_OVERHANG = 0.5 -- a grown coin may hang this far past the table edge

function CoinLook.maxScale(index: number, restDiameter: number): number
	local maxCoins = Config.MAX_COINS
	local x, z = TableLayout.coinOffset(index, maxCoins)
	local room = (Config.TABLE_RADIUS + CoinLook.EDGE_OVERHANG) - math.sqrt(x * x + z * z) -- radius left to the table edge
	for other = 1, maxCoins do
		if other ~= index then
			local ox, oz = TableLayout.coinOffset(other, maxCoins)
			local dist = math.sqrt((x - ox) ^ 2 + (z - oz) ^ 2)
			room = math.min(room, dist - restDiameter / 2 - CoinLook.GAP)
		end
	end
	return math.max(1, room * 2 / (restDiameter * CoinLook.RIDGE_WIDER))
end

-- The grown scale a rare coin really uses on this slot.
CoinLook.MAX_DIAMETER = 5.6 -- no rare coin is ever wider than this in the air (edge-on it swept helpers and back coins)

function CoinLook.growFor(grow: number, index: number, restDiameter: number): number
	return math.max(1, math.min(grow, CoinLook.maxScale(index, restDiameter), CoinLook.MAX_DIAMETER / restDiameter))
end

-- Height of the coin's centre above its rest spot: the flight arc `h`, but never so low that the coin
-- (turning, or grown) cuts into the table or brushes the helpers. A max, not a sum, so the top of a
-- rare coin's jump is the same height as any other coin's.
function CoinLook.flightHeight(
	h: number,
	roll: number,
	thickness: number,
	diameter: number,
	restThickness: number,
	restDiameter: number
): number
	local need = CoinLook.lift(roll, thickness, diameter, restThickness, restDiameter)
		+ CoinLook.hover(diameter / restDiameter)
	return math.max(h, need)
end

-- A grown coin also hovers a bit higher, so it flies over the helpers and the coins behind it.
function CoinLook.hover(scale: number): number
	return math.max(0, scale - 1) * 3.2
end

-- The flight trail is a thin ribbon: its two ends sit at most this far from the coin's spin axis,
-- so a wide (grown) coin never drags a slab-sized yellow block behind it.
CoinLook.TRAIL_MAX_HALF = 0.75
function CoinLook.trailHalfWidth(diameter: number): number
	return math.min(diameter / 2, CoinLook.TRAIL_MAX_HALF)
end

-- Where a ring of `count` stars sits on a coin face: (x, y) as 0..1 of the face, radius is a share of the face.
function CoinLook.starRing(count: number, radius: number): { { x: number, y: number } }
	local out = {}
	for i = 0, count - 1 do
		local a = i / count * math.pi * 2
		table.insert(out, { x = 0.5 + math.cos(a) * radius, y = 0.5 + math.sin(a) * radius })
	end
	return out
end

-- A thin, slightly wider ring around the middle of the coin's edge, so a coin
-- seen edge-on still has a ridge and reads as a coin, not a flat plank.
function CoinLook.ridge(thickness: number, diameter: number): (number, number)
	return thickness * 0.8, diameter * CoinLook.RIDGE_WIDER
end

-- Every look the coins can wear, for tests and the preview.
function CoinLook.all(): { [string]: Look }
	local out: { [string]: Look } = { normal = CoinLook.NORMAL }
	for _, def in Config.Rarities do
		out[def.id] = CoinLook.forRarity(def.id)
	end
	return out
end

return CoinLook
