-- Vibe grade (shared/VibeGrade): the lobby colour lift for carter's "not vibrant enough". Coloured parts gain
-- saturation, greens stay natural greens, greys/whites/stone are untouched, nothing new turns near-white, and the lift
-- is a pure function of the original colour (the build lifts from VibeBase, so re-runs never stack).
return function(t)
	local test, shared = t.test, t.shared
	local V = shared("VibeGrade")

	local function hsv(hex)
		local r = tonumber(hex:sub(1, 2), 16) / 255
		local g = tonumber(hex:sub(3, 4), 16) / 255
		local b = tonumber(hex:sub(5, 6), 16) / 255
		return V.toHsv(r, g, b)
	end

	test("vibe grade: HSV round trip", function()
		for _, hex in { "7cbd4e", "c8b286", "e0443a", "2fa7d6", "8a4fd8", "ffffff", "000000", "f2c230" } do
			local r = tonumber(hex:sub(1, 2), 16) / 255
			local g = tonumber(hex:sub(3, 4), 16) / 255
			local b = tonumber(hex:sub(5, 6), 16) / 255
			local r2, g2, b2 = V.fromHsv(V.toHsv(r, g, b))
			assert(math.abs(r - r2) + math.abs(g - g2) + math.abs(b - b2) < 1e-6, hex)
		end
	end)

	test("vibe grade: lobby colours get more saturated, greens stay green and not neon", function()
		-- lawn, yards, patch greens, foliage, paving, plaza tiles, accents
		for _, hex in { "7cbd4e", "88c855", "4f8a35", "5e9a3e", "6b8f3a", "c8b286", "d1925e", "e0443a", "2fa7d6", "f0a020" } do
			local h0, s0, v0 = hsv(hex)
			local out = V.liftHex(hex)
			local h1, s1, v1 = hsv(out)
			assert(s1 > math.min(s0 + 0.03, if V.isGreen(h0) then V.GreenSatMax - 0.01 else 1), hex .. " saturation " .. s0 .. " -> " .. s1)
			assert(v1 >= v0 - 0.005 or (s0 < V.PaleSat and v1 >= V.PaleValMax - 0.005), hex .. " got darker")
			if not V.isGreen(h0) and s0 < V.PaleSat then
				assert(v1 <= math.max(V.PaleValMax, v0 - 0.04) + 0.005, hex .. " pale colour too light " .. v1)
			end
			if V.isGreen(h0) then
				assert(V.isGreen(h1), hex .. " left the green range: " .. h1)
				assert(s1 <= V.GreenSatMax + 0.006, hex .. " neon green " .. s1)
			else
				assert(math.abs(h1 - h0) < 1e-3, hex .. " hue moved")
			end
		end
	end)

	test("vibe grade: greys, whites and stone stay, nothing new is near-white", function()
		for _, hex in { "8d877f", "9a958e", "a39a8a", "8d8478", "a39a8c", "ffffff", "cfc6b8", "5a554f", "b9b0a2", "000000" } do
			assert(V.liftHex(hex) == hex, hex .. " changed to " .. V.liftHex(hex))
		end
		-- sweep the whole colour cube: a lifted colour never gets brighter than ValMax unless it already was
		for r = 0, 255, 17 do
			for g = 0, 255, 17 do
				for b = 0, 255, 17 do
					local _, _, v0 = V.toHsv(r / 255, g / 255, b / 255)
					local _, s1, v1 = V.toHsv(V.lift(r / 255, g / 255, b / 255))
					assert(v1 <= math.max(v0, V.ValMax) + 1e-9, "too bright")
					assert(s1 <= 1 + 1e-9, "saturation over 1")
				end
			end
		end
	end)

	test("vibe grade: lifting the original twice gives the same colour (re-runs never stack)", function()
		for _, hex in { "7cbd4e", "c8b286", "e0443a" } do
			assert(V.liftHex(hex) == V.liftHex(hex))
		end
		print("    lawn 7cbd4e -> " .. V.liftHex("7cbd4e") .. ", yard 88c855 -> " .. V.liftHex("88c855")
			.. ", path c8b286 -> " .. V.liftHex("c8b286"))
	end)

	test("vibe grade: lobby light is carter's old look, the same set as the project file", function()
		local fs = require("@lune/fs")
		local serde = require("@lune/serde")
		local L = serde.decode("json", fs.readFile("default.project.json")).tree.Lighting
		local VL = V.Lighting
		local function near(a, b, what)
			assert(math.abs(a - b) < 1e-6, what .. ": " .. tostring(a) .. " ~= " .. tostring(b))
		end
		local function near3(a, b, what)
			for k = 1, 3 do
				near(a[k], b[k], what)
			end
		end
		local P = L["$properties"]
		near(VL.Brightness, P.Brightness, "Brightness")
		near(VL.ExposureCompensation, P.ExposureCompensation, "Exposure")
		near(VL.ClockTime, P.ClockTime, "ClockTime")
		near3(VL.Ambient, P.Ambient, "Ambient")
		near3(VL.OutdoorAmbient, P.OutdoorAmbient, "OutdoorAmbient")
		near3(VL.ColorShiftTop, P.ColorShift_Top, "ColorShift_Top")
		local A = L.Atmosphere["$properties"]
		near(VL.Atmosphere.Haze, A.Haze, "Haze")
		near(VL.Atmosphere.Density, A.Density, "Density")
		near3(VL.Atmosphere.Color, A.Color, "Atmosphere Color")
		near(VL.ColorCorrection.Saturation, L.ColorCorrection["$properties"].Saturation, "CC saturation")
		near(VL.Grade.Saturation, L.Grade["$properties"].Saturation, "Grade saturation")
		near(VL.Bloom.Threshold, L.Bloom["$properties"].Threshold, "Bloom")
		assert(VL.Atmosphere.Haze == 0, "no haze (r29 runner)")
		near(VL.ShadowSoftness, P.ShadowSoftness, "ShadowSoftness")
		assert(VL.LightingStyle == "Realistic", "crisp Realistic lighting style")
		near3(VL.Atmosphere.Decay, A.Decay, "Atmosphere Decay")
		assert(VL.TerrainClouds == false, "old sky: no soft Terrain cloud layer")
	end)
end
