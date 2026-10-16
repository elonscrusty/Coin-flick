return function(t)
	local test, shared = t.test, t.shared
	local S = shared("SignLayout")

	test("signs: landmark titles fill 60-88 percent of a board in one line at a sane text size", function()
		for _, spec in { { "START HUNT", 8.8, 2.0 }, { "UPGRADES", 8.4, 1.9 }, { "COLLECTION", 9.6, 1.9 }, { "RECORDS", 7.4, 1.6 } } do
			local f = S.fit(spec[1], spec[2], spec[3], "Landmark")
			assert(f.Fill >= 0.6 and f.Fill <= 0.88, spec[1] .. " fill " .. f.Fill)
			assert(f.TextSize <= 100 and f.Lines == 1)
			assert(f.CapStuds > 0.5, spec[1] .. " cap height " .. f.CapStuds)
		end
	end)

	test("signs: size follows the board, not a fixed pixel density", function()
		local small = S.fit("UPGRADES", 4, 1, "Landmark")
		local big = S.fit("UPGRADES", 12, 3, "Landmark")
		assert(math.abs(big.Em / small.Em - 3) < 0.01, "text scales with the board")
		assert(small.TextSize == big.TextSize, "TextSize stays fixed, PixelsPerStud carries the scale")
	end)

	test("signs: lodge lettering is white with a black outline that follows the text size", function()
		assert(S.Outline.Ink.R > 0.99 and S.Outline.Ink.G > 0.99 and S.Outline.Ink.B > 0.99)
		assert(S.Outline.Stroke.R < 0.1 and S.Outline.Stroke.G < 0.1 and S.Outline.Stroke.B < 0.1)
		assert(S.outlinePx(80) == 6 and S.outlinePx(10) == 2 and S.outlinePx(200) == 7)
		-- the board headings fill the board's top band, the long one in one line
		for _, h in { "SOLO FINDS", "COMPETITIVE WINS" } do
			local f = S.fit(h, 10.8, 2.0, "Heading")
			assert(f.Lines == 1 and f.Fill >= 0.55 and f.Fill <= 0.94, h .. " fill " .. f.Fill)
			assert(f.CapStuds > 0.6, h .. " cap " .. f.CapStuds)
		end
	end)

	test("signs: nameplates shrink then truncate long owner names", function()
		local short = S.fit("Ava's gallery", 5.6, 0.7, "Nameplate")
		local long = S.fit("Maximilian_The_Magnificent_Rockhound's gallery", 5.6, 0.7, "Nameplate")
		assert(short.Text == "Ava's gallery")
		assert(#long.Text <= 22 and string.sub(long.Text, -3) == "...")
		assert(long.Fill <= 0.92 and long.Fill >= 0.4, "long name fill " .. long.Fill)
	end)
end
