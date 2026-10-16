--!strict
-- VIBE GRADE (carter 2026-10-15: "the map doesn't look vibrant enough to appeal to kids"). One pure colour lift for the
-- lobby dressing: coloured parts get more saturation (greens also lean a little toward a fresh yellow-green), greys,
-- whites and stone stay as they are, and nothing is pushed into a blown-out near-white (it read white on a phone).
-- Numbers only (r, g, b in 0..1), so tests/test_vibe_grade.luau runs it offline and the Studio lobby build
-- (tools/studio/lobby_redesign/gen_build.py inlines this file) applies the very same function.
-- Always lift from the part's ORIGINAL colour (the build keeps it in a VibeBase attribute), so a re-run never stacks.

local VibeGrade = {}

VibeGrade.NeutralSat = 0.17 -- below this a colour is grey / white / stone and is left alone
VibeGrade.GreenHue = { Lo = 0.17, Hi = 0.47, Target = 0.3, Pull = 0.6 } -- greens pull 60% to ONE lime-leaf green
-- (r29d runner: yellow-lime in front, teal-neon in places; one even lime grass reads cleaner)
-- (r29 runner: 0.29 / 0.72 read neon yellow-green in full sun)
VibeGrade.SatMul, VibeGrade.SatAdd, VibeGrade.SatMax = 1.3, 0.05, 0.9
VibeGrade.GreenSatMul, VibeGrade.GreenSatMax = 1.35, 0.62 -- grass stays natural, not neon
VibeGrade.ValMul, VibeGrade.ValMax = 1.06, 0.93
-- pale warm surfaces (sand paths, peach tiles) blew out in the 3.13 sun (r29 runner): no brighter than this
VibeGrade.PaleSat, VibeGrade.PaleValMax = 0.5, 0.78

-- Lighting: carter's favourite "old brightness" look (2026-10-15, screenshot of the pre-redesign lobby: deep blue sky,
-- crisp shadows, saturated grass, no grey haze). These are the exact Lighting values of that place (FindThePet_newest
-- .rbxlx, 2026-10-12 Studio save; default.project.json carries the same set). The build applies all of them and keeps
-- the round 26-28 values only as RedesignOld_* attributes. Two grades stack, as in the old place.
VibeGrade.Lighting = {
	Brightness = 3.13,
	ExposureCompensation = 0,
	ClockTime = 15.4, -- r29d runner: a lower sun for longer, clearer shadows (old 14.6)
	GeographicLatitude = 38,
	Ambient = { 0.4, 0.4, 0.42 },
	OutdoorAmbient = { 0.32, 0.34, 0.43 }, -- r29d runner: darker, cool shade so shadows read (old 0.46 grey)
	ColorShiftTop = { 1, 0.94, 0.84 },
	-- r29g: this Studio has no Technology property (carter could not find it); the newer Lighting Style "Realistic"
	-- gives crisp sun shadows ("Soft" is the blurry one). Scripts may not set it, then it is set by hand.
	LightingStyle = "Realistic",
	ShadowSoftness = 0, -- r29g: fully crisp edges (0.15 still read soft) -- r29 runner: crisp dark shadows like the old shot (was 0.55)
	EnvironmentDiffuseScale = 0.25, -- less sky fill in the shade (old 0.45)
	EnvironmentSpecularScale = 0.15,
	ColorCorrection = { Saturation = 0.14, Contrast = 0.04, Brightness = 0, Tint = { 1, 1, 1 } },
	Grade = { Saturation = 0.06, Contrast = 0.08, Brightness = 0.01, Tint = { 1, 0.985, 0.955 } },
	-- r29 runner: the warm haze washed the far yards and mountains and paled the sky at the horizon; a thin clear-blue
	-- air keeps the depth, no haze
	-- r29e runner: "slight horizon brightening": a deeper blue air so the horizon stays sky blue
	Atmosphere = { Density = 0.12, Offset = 0.3, Color = { 0.62, 0.78, 0.98 }, Decay = { 0.45, 0.62, 0.9 }, Glare = 0, Haze = 0 },
	Bloom = { Intensity = 0.06, Size = 12, Threshold = 2.4 },
	TerrainClouds = false, -- the old sky had only the blocky low-poly clouds (the build adds them), no soft Terrain layer
}

local function toHsv(r: number, g: number, b: number): (number, number, number)
	local mx, mn = math.max(r, g, b), math.min(r, g, b)
	local d = mx - mn
	local h = 0
	if d > 0 then
		if mx == r then
			h = ((g - b) / d) % 6
		elseif mx == g then
			h = (b - r) / d + 2
		else
			h = (r - g) / d + 4
		end
		h /= 6
	end
	local s = if mx > 0 then d / mx else 0
	return h, s, mx
end

local function fromHsv(h: number, s: number, v: number): (number, number, number)
	local i = math.floor(h * 6) % 6
	local f = h * 6 - math.floor(h * 6)
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	if i == 0 then
		return v, t, p
	elseif i == 1 then
		return q, v, p
	elseif i == 2 then
		return p, v, t
	elseif i == 3 then
		return p, q, v
	elseif i == 4 then
		return t, p, v
	end
	return v, p, q
end
VibeGrade.toHsv, VibeGrade.fromHsv = toHsv, fromHsv

function VibeGrade.isGreen(h: number): boolean
	return h >= VibeGrade.GreenHue.Lo and h <= VibeGrade.GreenHue.Hi
end

-- The lifted colour of (r, g, b).
function VibeGrade.lift(r: number, g: number, b: number): (number, number, number)
	local h, s, v = toHsv(r, g, b)
	if s < VibeGrade.NeutralSat then
		return r, g, b
	end
	local s2, v2
	if VibeGrade.isGreen(h) then
		local gh = VibeGrade.GreenHue
		h += (gh.Target - h) * gh.Pull
		s2 = math.min(VibeGrade.GreenSatMax, math.max(s, s * VibeGrade.GreenSatMul + VibeGrade.SatAdd))
	else
		s2 = math.min(VibeGrade.SatMax, math.max(s, s * VibeGrade.SatMul + VibeGrade.SatAdd))
	end
	-- light, pale colours (paving, sand) get colour, not more light: they already read near white on a phone
	v2 = if v >= VibeGrade.ValMax then v else math.min(VibeGrade.ValMax, v * VibeGrade.ValMul)
	if not VibeGrade.isGreen(h) and s < VibeGrade.PaleSat and v2 > VibeGrade.PaleValMax then
		v2 = math.max(VibeGrade.PaleValMax, math.min(v2, v) - 0.04) -- pale paving: colour up, light a touch down
	end
	return fromHsv(h, s2, v2)
end

-- Hex in, hex out (lowercase, no #), for the build script and the tests.
function VibeGrade.liftHex(hex: string): string
	local r = tonumber(string.sub(hex, 1, 2), 16) or 0
	local g = tonumber(string.sub(hex, 3, 4), 16) or 0
	local b = tonumber(string.sub(hex, 5, 6), 16) or 0
	local r2, g2, b2 = VibeGrade.lift(r / 255, g / 255, b / 255)
	local function byte(x: number): number
		return math.clamp(math.floor(x * 255 + 0.5), 0, 255)
	end
	return string.format("%02x%02x%02x", byte(r2), byte(g2), byte(b2))
end

-- Textured part materials that flatten colour; the flat-shaded low-poly look wants a clean surface. Big grass and soil
-- tops become SmoothPlastic so the green reads as green on a phone. Other materials stay.
VibeGrade.FlatMaterials = { Grass = true, Ground = true }

return VibeGrade
