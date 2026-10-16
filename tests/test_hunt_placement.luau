-- Hunt scenery placement (shared/HuntPlacement, used by server/HuntLowPoly): the fence is a SQUARE (lines at +-42.5,
-- the east side fenced too); no prop footprint within 3 studs of it, in any of the five zones; the barrels, crates and
-- hay bales stay clear of the shell sell stands (nearHopper). Mesh sizes are not available offline, so footprints use
-- STANDIN half-widths (studs, before the row's scale); trees use the trunk radius 1.5 exactly as the builder does.
return function(t)
	local test, shared = t.test, t.shared
	local HP = shared("HuntPlacement")
	local ZoneThemes = shared("ZoneThemes")
	local Config = shared("Config")
	local HALF, CLEAR = HP.FenceHalf, HP.Clear
	assert(HALF == 42.5 and CLEAR == 3)

	local STANDIN = { Rock = 3, Kit_Rock_A = 3, Mushroom = 2.5, FlowerBush = 2.5, Kit_Bush_A = 2.5, Barrel = 1.5, Crate = 1.5, HayBale = 2 }
	local function radius(row): number
		return (STANDIN[row[1]] or 2) * row[6]
	end
	local function isCliff(name: string): boolean
		return string.sub(name, 1, 5) == "Cliff" and name ~= "CliffPine"
	end
	local function footprint(row): number
		return if HP.TREES[row[1]] or row[1] == "CliffPine" then HP.TrunkRadius else radius(row)
	end

	test("hunt placement: squareOff moves a prop to exactly the clearance, inward or outward, per line", function()
		local function d(x, z, c)
			local nx, nz = HP.squareOff(x, z, HALF, c)
			return nx, nz
		end
		local x, z = d(40, 4, 6) -- inside, east line
		assert(math.abs(x - 36.5) < 1e-9 and z == 4, "inward " .. x)
		x, z = d(44, 4, 6) -- outside, east line
		assert(math.abs(x - 48.5) < 1e-9 and z == 4, "outward " .. x)
		x, z = d(-4, -41, 5) -- south line
		assert(x == -4 and math.abs(z + 37.5) < 1e-9, "south " .. z)
		x, z = d(30, 90, 6) -- far past the side's end: untouched
		assert(x == 30 and z == 90)
		x, z = d(0, 0, 6)
		assert(x == 0 and z == 0)
		x, z = d(41, 41, 5) -- corner: both lines
		assert(math.abs(x - 37.5) < 1e-9 and math.abs(z - 37.5) < 1e-9)
		assert(math.abs(HP.fenceDistance(36.5, 4, HALF) - 6) < 1e-9)
		assert(math.abs(HP.fenceDistance(48.5, 4, HALF) - 6) < 1e-9)
	end)

	test("hunt placement: the Studio hits (east rocks, south trees) end up 3 studs clear", function()
		local checked = 0
		for _, row in HP.SCENERY do
			local x, z = row[2], row[4]
			local hit = (row[1] == "Rock" or row[1] == "Kit_Rock_A") and math.abs(x - 39.5) < 1.5
				or (row[1] == "Kit_Tree_A" and math.abs(z + 42) < 1.5 and math.abs(x - 33) < 1.5)
			if hit then
				local nx, nz = HP.spot(row[1], x, z, radius(row), HALF)
				assert(HP.fenceDistance(nx, nz, HALF) >= CLEAR + footprint(row) - 1e-6, row[1] .. " " .. x .. "," .. z)
				checked += 1
			end
		end
		assert(checked >= 1, "found a known hit row")
	end)

	for _, id in Config.TierOrder do
		local theme = ZoneThemes.Themes[id]
		test("hunt placement: " .. theme.Zone .. " props stay 3 studs off the square fence", function()
			local rows = table.clone(HP.SCENERY)
			if theme.ExtraTrees then
				local extras = HP.forestExtras()
				assert(#extras > 0)
				table.move(extras, 1, #extras, #rows + 1, rows)
			end
			local n = 0
			for _, row in rows do
				if not isCliff(row[1]) then
					local x, z = HP.spot(row[1], row[2], row[4], radius(row), HALF)
					local need = CLEAR + footprint(row)
					assert(HP.fenceDistance(x, z, HALF) >= need - 1e-6, string.format("%s (%.1f,%.1f) -> (%.1f,%.1f)", row[1], row[2], row[4], x, z))
					n += 1
				end
			end
			assert(n > 20, "checked " .. n)
			if theme.Craters then
				local spots = ZoneThemes.ringSpots()
				assert(#spots > 0)
				for _, r in spots do
					local x, z = HP.pushOut(r.X, r.Z, HALF, 6)
					-- cluster centre 6 out: 1.5 jitter and a crystal half-width of at most 1 still leave 3 clear
					assert(HP.fenceDistance(x, z, HALF) >= 6 - 1e-6 and math.max(math.abs(x), math.abs(z)) >= HALF + 6 - 1e-6, string.format("crystal (%.1f,%.1f)", r.X, r.Z))
				end
			end
		end)
	end

	test("hunt placement: nearHopper keeps barrels, crates and hay bales 2 studs off the sell stands", function()
		assert(HP.nearHopper(0, 30, 1) and HP.nearHopper(0, -30, 1))
		assert(HP.nearHopper(7, 33, 1)) -- inside apron + 2 + radius
		assert(not HP.nearHopper(10, 31.76, 1.5)) -- the Barrel spot
		assert(not HP.nearHopper(20, 30, 1) and not HP.nearHopper(0, 0, 3))
		local n = 0
		for _, row in HP.SCENERY do
			if row[1] == "Barrel" or row[1] == "Crate" or row[1] == "HayBale" then
				local x, z = HP.spot(row[1], row[2], row[4], radius(row), HALF)
				assert(not HP.nearHopper(x, z, radius(row)), row[1] .. " at " .. x .. "," .. z)
				n += 1
			end
		end
		assert(n == 6, "six placed props, got " .. n)
	end)

	test("hunt start: every spawn faces the egg pile, and the camera starts on the pile when no swoop runs", function()
		local Vector3 = t.Vector3
		local CFrame = t.CFrame or require("@lune/roblox").CFrame
		local centre = Vector3.new(100, 5, -40)
		for _, pos in { Vector3.new(130, 6, -40), Vector3.new(100, 6, -10), Vector3.new(70, 6, -70), Vector3.new(100, 6, -75) } do
			-- a pad pointing away from the pile (the bug) still ends up looking at it
			local away = CFrame.lookAt(pos, pos + (pos - centre))
			local cf = HP.faceCentre(away, centre)
			local want = Vector3.new(centre.X - pos.X, 0, centre.Z - pos.Z).Unit
			assert(cf.LookVector:Dot(want) > 0.999, "faces the pile from " .. tostring(pos))
			assert(math.abs(cf.LookVector.Y) < 1e-6, "level gaze")
			assert((cf.Position - pos).Magnitude < 1e-6, "same spot")
		end
		local fs = require("@lune/fs")
		local ms = fs.readFile("src/server/MatchService.luau")
		assert(string.find(ms, "HuntPlacement.faceCentre(cf, m.Arena.Center)", 1, true), "placeAtSpawn turns racers to the pile")
		local ri = fs.readFile("src/client/RoundIntro.luau")
		assert(string.find(ri, "aimAtPile(key, m.Center)", 1, true), "camera on the pile when the round starts without a swoop")
	end)

	test("hatch close-up: the finder's camera looks down at their own nest, from their side, before the reveal card", function()
		local Vector3 = t.Vector3
		local R = shared("CameraModeRules")
		local plate = Vector3.new(20, 3, 10)
		for _, viewer in { Vector3.new(20, 8, 30), Vector3.new(-5, 8, 10), Vector3.new(20.05, 8, 10.05) } do
			local cf = R.nestShot(plate, viewer)
			local look = plate + Vector3.new(0, R.NestLookUp, 0)
			assert((cf.Position + cf.LookVector * (look - cf.Position).Magnitude - look).Magnitude < 1e-3, "aims at the nest")
			assert(cf.LookVector.Y < -0.3, "looks down at it")
			local dist = (cf.Position - look).Magnitude
			assert(dist > 6 and dist < 14, "close: " .. dist)
		end
		local back = R.nestShot(plate, Vector3.new(20, 8, 30))
		assert(back.Position.Z > plate.Z, "on the viewer's side of the nest")
		local fs = require("@lune/fs")
		local main = fs.readFile("src/client/Main.client.luau")
		assert(string.find(main, "HatchFocus.start(StationView.platePosition(Players.LocalPlayer.UserId))", 1, true), "starts on your find")
		assert(string.find(main, "HatchFocus.stop() -- the nest close-up hands over", 1, true), "hands over to the reveal card")
		local rp = fs.readFile("src/client/ui/ResultsPanel.luau")
		assert(string.find(rp, "RevealView.play(res, text, res.Winner == player.UserId)", 1, true), "practice find is a full 'You hatched' reveal")
		-- the label comes from shared/ResultsRules (tutorial -> TRAIN PET, tested in test_results_rules)
		assert(string.find(rp, 'fb(ResultsRules.Label[ResultsRules.primary({ Tutorial = true', 1, true), "practice results push the loop: TRAIN PET")
		assert(not string.find(rp, '"BagRow"', 1, true) and not string.find(rp, '"PileLeft"', 1, true), "no tiny bag / pile-left rows (bug #227)")
	end)
end
