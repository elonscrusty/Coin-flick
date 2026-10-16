-- Dino-jungle pet park (src/shared/ParkConfig.luau): plot layout and who shows where.
return function(t)
	local test, shared = t.test, t.shared
	local ParkConfig = shared("ParkConfig")

	test("park: an empty plot sign states the real rule and never asks to claim (audit 2 #3)", function()
		local P = t.shared("ParkConfig")
		local up = string.upper(P.EmptyPlot)
		assert(not string.find(up, "CLAIM", 1, true) and not string.find(up, "TAP", 1, true), "no claim action exists: " .. P.EmptyPlot)
		assert(string.find(up, "JOIN", 1, true), "says plots are given on join")
		assert(P.YourPlot == "YOUR PLOT", "own plot tag")
		assert(table.find(P.SignMatch, "FREE PLOT"), "old hand-built signs still found")
	end)

	test("park: 12 square plots around the clearing, spread out, gates toward the clearing", function()
		local P = ParkConfig.Plot
		assert(P.Count == 12)
		local half = P.Size / 2
		for i = 1, P.Count do
			local x, z, dx, dz = ParkConfig.plotCentre(i)
			assert(ParkConfig.inside(x + half, z + half) and ParkConfig.inside(x - half, z - half), "plot inside the park")
			assert(math.max(math.abs(x), math.abs(z)) - half > ParkConfig.Clearing.Half + ParkConfig.Path.Width, "plot outside the clearing and the ring path")
			assert(dx * x + dz * z < 0, "gate faces toward the clearing")
			for j = i + 1, P.Count do
				local x2, z2 = ParkConfig.plotCentre(j)
				local gap = math.max(math.abs(x - x2), math.abs(z - z2)) - P.Size
				assert(gap >= 10, ("plots %d and %d are only %.1f studs apart"):format(i, j, gap))
			end
		end
	end)

	test("park: the plot frame looks at its gate, the nests sit in the clearing", function()
		local cf = ParkConfig.plotFrame(1)
		assert(cf.LookVector.Z < -0.99, "plot 1 (south row) looks north to the ring path")
		local cf5 = ParkConfig.plotFrame(5)
		assert(cf5.LookVector.X > 0.99, "plot 5 (west column) looks east")
		local Q = ParkConfig.QueuePads
		assert(#Q.Spots == 4 and #Q.Colours == 4)
		for _, s in Q.Spots do
			assert(math.abs(s[1]) + Q.Size / 2 + 2 < ParkConfig.Clearing.Half and math.abs(s[2]) + Q.Size / 2 + 2 < ParkConfig.Clearing.Half)
			assert(math.abs(s[1]) - Q.Size / 2 - 2 > 4, "the walk between the nests stays open")
		end
	end)

	test("park: exactly 3 domes, filled in the player's chosen order, the rest stand in the yard", function()
		local S = ParkConfig.Showcase
		assert(#S.Domes == 3, "exactly 3 glass domes per plot")
		local pets = {
			{ Id = "a", Rarity = "Common", Value = 5 },
			{ Id = "b", Rarity = "Epic", Value = 50 },
			{ Id = "c", Rarity = "Legendary", Value = 10 },
			{ Id = "d", Rarity = "Uncommon", Value = 8 },
			{ Id = "e", Rarity = "Rare", Value = 30 },
		}
		local r = ParkConfig.arrange(pets)
		assert(#r.Domes == 3 and r.Domes[1].Id == "a" and r.Domes[2].Id == "b" and r.Domes[3].Id == "c", "player's order, not rarity")
		assert(#r.Yard == 2 and r.Yard[1].Id == "d")
		local none = ParkConfig.arrange({})
		assert(#none.Domes == 0 and #none.Yard == 0)
		local many = {}
		for k = 1, 20 do
			table.insert(many, { Id = "p" .. k, Rarity = "Common", Value = k })
		end
		local m = ParkConfig.arrange(many)
		assert(#m.Domes + #m.Yard == 20, "the largest display capacity all shows")
	end)

	test("park: no pet roams; yard pets stand on fixed spots inside the fence, clear of the big dome", function()
		local Vector2 = t.Vector2
		local S = ParkConfig.Showcase
		local W, B = S.Wander, S.Domes[1]
		local avoid = Vector2.new(B.X, B.Z)
		for _, n in { 1, 5, 17, 27 } do
			local spots = ParkConfig.yardSpots(W, avoid, W.AvoidR, n)
			assert(#spots == n, "one spot per yard pet")
			for i, v in spots do
				assert(v.X > W.MinX and v.X < W.MaxX and v.Y > W.MinZ and v.Y < W.MaxZ, "spot inside the yard box")
				assert((v - avoid).Magnitude >= W.AvoidR, "spot clear of the big dome")
				if n <= 20 then
					for j = i + 1, n do
						assert((v - spots[j]).Magnitude >= 2.4, ("yard pets %d and %d overlap at %d pets"):format(i, j, n))
					end
				end
			end
		end
		assert(#ParkConfig.yardSpots(W, avoid, W.AvoidR, 0) == 0)
		-- a few pets spread over the lawn, front to back and side to side, not in one strip (Studio check 398700f)
		for _, n in { 4, 6, 9 } do
			local sp = ParkConfig.yardSpots(W, avoid, W.AvoidR, n)
			local zl, zh, xl, xh = math.huge, -math.huge, math.huge, -math.huge
			for _, v in sp do
				zl, zh, xl, xh = math.min(zl, v.Y), math.max(zh, v.Y), math.min(xl, v.X), math.max(xh, v.X)
			end
			assert(zh - zl >= (W.MaxZ - W.MinZ) * 0.4, ("%d pets cover only %.1f studs of the lawn depth"):format(n, zh - zl))
			assert(xh - xl >= (W.MaxX - W.MinX) * 0.4, ("%d pets cover only %.1f studs of the lawn width"):format(n, xh - xl))
		end
		-- a big hand-built pen (Studio: 57-wide floor): 6 pets use the full width, front (gate, -Z) rows first
		local big = { MinX = -23, MaxX = 23, MinZ = -23, MaxZ = 23 }
		local far = Vector2.new(0, 30)
		local sp = ParkConfig.yardSpots(big, far, 6, 6)
		local xl, xh, front = math.huge, -math.huge, 0
		for _, v in sp do
			xl, xh = math.min(xl, v.X), math.max(xh, v.X)
			if v.Y < 0 then
				front += 1
			end
		end
		assert(xh - xl >= 46 * 0.5, ("6 pets cover only %.1f of 46 studs width"):format(xh - xl))
		assert(front >= 3, ("only %d of 6 pets in the front half"):format(front))
		local one = ParkConfig.yardSpots(big, far, 6, 1)[1]
		assert(math.abs(one.X) < 0.01 and math.abs(one.Y) < 0.01, "a single yard pet stands in the middle")
		-- same input, same spots (every server and every visit puts each pet in the same place)
		local a1, a2 = ParkConfig.yardSpots(W, avoid, W.AvoidR, 9), ParkConfig.yardSpots(W, avoid, W.AvoidR, 9)
		for i = 1, 9 do
			assert(a1[i] == a2[i], "yard spots are deterministic")
		end
		-- yard pets stand on the ground players see: a lawn laid over the plot floor lifts them, a roof does not
		assert(ParkConfig.yardLift(nil, 3) == 0, "no ground hit: stay on the floor")
		assert(ParkConfig.yardLift(3, 3) == 0 and ParkConfig.yardLift(1, 3) == 0, "floor or lower: stay on the floor")
		assert(math.abs(ParkConfig.yardLift(8.5, 3) - 5.5) < 1e-9, "buried floor: up onto the lawn")
		assert(ParkConfig.yardLift(3 + ParkConfig.YardMaxLift + 1, 3) == 0, "a roof or tree overhead is not ground")
		assert(ParkConfig.yardLift(0 / 0, 3) == 0, "NaN is ignored")
		-- the walker, the wander tag and the ROAM action are gone from the game code
		local fs = require("@lune/fs")
		for _, file in { "src/client/LobbyAmbience.luau", "src/server/GalleryService.luau", "src/server/EconomyService.luau", "src/client/ui/CollectionPanel.luau" } do
			local src = fs.readFile(file)
			assert(not src:find("CT_ParkWanderer", 1, true), file .. " still tags or walks wandering pets")
			assert(not src:find('action == "Roam"', 1, true) and not src:find('act("Roam"', 1, true), file .. " still has the ROAM toggle")
			assert(not src:find("stepWalkers", 1, true), file .. " still moves plot pets")
		end
	end)

	test("park: yard pets cover the whole redesigned lawn (53 x 57 pen), not one strip by the back fence", function()
		-- owner report 2026-10-15 (Studio on c411994): 5 of 6 yard pets lined the back fence, the front lawn empty.
		-- Real plot after the lobby redesign: floor 57 across, 53 gate-to-back (frame), fence runs just inside the
		-- floor edge, posts at the corners, the big dome near the back, plus "fence" pieces INSIDE the pen (a garden
		-- bed rail and a rail in front of the domes) that must not shrink the yard.
		local Vector2 = t.Vector2
		local S = ParkConfig.Showcase
		local hx, hz = 28.5, 26.5
		local fences: { any } = {
			{ X = -27.8, Z = 0, TX = 0.3, TZ = 26 }, { X = 27.8, Z = 0, TX = 0.3, TZ = 26 }, -- side runs
			{ X = 0, Z = 25.8, TX = 28, TZ = 0.3 }, -- back run
			{ X = -16, Z = -25.8, TX = 11, TZ = 0.3 }, { X = 16, Z = -25.8, TX = 11, TZ = 0.3 }, -- front runs, gate between
			{ X = 27.8, Z = 25.8, TX = 0.5, TZ = 0.5 }, -- a corner post (neither run)
			{ X = 0, Z = 12, TX = 14, TZ = 0.4 }, -- rail in front of the domes (inside the pen)
			{ X = -6, Z = -15, TX = 18, TZ = 0.4 }, -- garden bed rail (inside the pen)
		}
		local box = ParkConfig.yardBox(hx, hz, S.FloorMargin, fences, 1.5, S.Wander)
		assert(box.MaxZ - box.MinZ >= (hz - S.FloorMargin) * 2 * 0.9, ("yard depth shrunk to %.1f"):format(box.MaxZ - box.MinZ))
		assert(box.MaxX - box.MinX >= (hx - S.FloorMargin) * 2 * 0.9, ("yard width shrunk to %.1f"):format(box.MaxX - box.MinX))
		-- a fence run inside the floor margin still pulls its side in
		local tight = ParkConfig.yardBox(hx, hz, S.FloorMargin, { { X = 20, Z = 0, TX = 0.3, TZ = 26 } }, 1.5, S.Wander)
		assert(math.abs(tight.MaxX - (20 - 0.3 - 1.5)) < 1e-6, "an outer run inside the floor edge pulls the side in")
		local tiny = ParkConfig.yardBox(6, 4, S.FloorMargin, {}, 1.5, S.Wander)
		assert(tiny.MinX == S.Wander.MinX and tiny.MaxZ == S.Wander.MaxZ, "a small floor keeps the code default box")
		local avoid = Vector2.new(0, 20)
		for n = 1, 20 do
			local sp = ParkConfig.yardSpots(box, avoid, S.Wander.AvoidR, n)
			assert(#sp == n)
			local front, back, left, right = 0, 0, 0, 0
			for i, v in sp do
				assert(v.X > box.MinX and v.X < box.MaxX and v.Y > box.MinZ and v.Y < box.MaxZ, "spot outside the lawn")
				assert((v - avoid).Magnitude >= S.Wander.AvoidR, "spot inside the big dome")
				for j = i + 1, n do
					assert((v - sp[j]).Magnitude >= 2.4, ("pets %d and %d overlap at %d"):format(i, j, n))
				end
				front += if v.Y < -3 then 1 else 0
				back += if v.Y > 3 then 1 else 0
				left += if v.X < -3 then 1 else 0
				right += if v.X > 3 then 1 else 0
			end
			if n >= 4 then
				-- even cover: each half of the lawn holds between a quarter and three quarters of the pets
				for _, c in { front, back, left, right } do
					assert(c >= math.floor(n / 4) and c <= math.ceil(n * 3 / 4), ("%d pets: halves %d/%d front/back, %d/%d left/right"):format(n, front, back, left, right))
				end
			end
		end
	end)

	test("park: the domes fit inside the fence and clear of each other and the yard", function()
		local S = ParkConfig.Showcase
		local half = ParkConfig.Plot.Size / 2
		for k, D in S.Domes do
			local r = D.Plinth / 2
			assert(math.abs(D.X) + r < half - 1 and D.Z + r < half - 1, "dome inside the fence")
			assert(D.Z - r - 1.4 > S.Wander.MaxZ, "plaque clear of the wander yard")
			for k2 = k + 1, #S.Domes do
				local E = S.Domes[k2]
				assert(math.sqrt((D.X - E.X) ^ 2 + (D.Z - E.Z) ^ 2) > r + E.Plinth / 2 + 1, "domes apart")
			end
		end
	end)

	test("park likes: one per visitor per plot, never your own, crown to the most liked", function()
		local s = ParkConfig.newLikes()
		assert(not ParkConfig.like(s, 1, 1), "no liking your own plot")
		assert(ParkConfig.like(s, 2, 1))
		local ok, why = ParkConfig.like(s, 2, 1)
		assert(not ok and why == "already", "one like per visitor per plot")
		assert(ParkConfig.like(s, 3, 1) and ParkConfig.like(s, 1, 2))
		assert(s.Count[1] == 2 and s.Count[2] == 1)
		assert(ParkConfig.likeLeader(s, { 1, 2 }, nil) == 1)
		assert(ParkConfig.likeLeader(s, { 2 }, 1) == 2, "a leaver loses the crown")
		assert(ParkConfig.likeLeader(ParkConfig.newLikes(), { 1, 2 }, nil) == nil, "no likes, no crown")
		assert(ParkConfig.like(s, 3, 2))
		assert(ParkConfig.likeLeader(s, { 1, 2 }, 1) == 1 and ParkConfig.likeLeader(s, { 2, 1 }, 2) == 2, "a tie keeps the crown")
	end)

	test("whats new: 3-5 short lines, pop-up once per version, server stores only the current version", function()
		local W = shared("WhatsNew")
		assert(type(W.Version) == "string" and #W.Version > 0)
		assert(#W.Lines >= 3 and #W.Lines <= 5)
		for _, l in W.Lines do
			assert(#l <= 40, "short line: " .. l)
		end
		assert(W.shouldShow("", true) and W.shouldShow(nil, true))
		assert(not W.shouldShow(W.Version, true) and not W.shouldShow("", false))
		assert(W.accept(W.Version) == W.Version and W.accept("9999") == nil and W.accept(5) == nil)
	end)

	test("map names: a hand-built map is a Model named Lobby or PetPark; numbered hooks", function()
		local MapNames = shared("MapNames")
		assert(MapNames.findRoot({ { Name = "Baseplate" }, { Name = "PetPark" } }).Name == "PetPark")
		assert(MapNames.findRoot({ { Name = "Lobby" } }) ~= nil)
		assert(MapNames.findRoot({ { Name = "CT_Rocks_Lobby" }, { Name = "Terrain" } }) == nil, "the code's own folder is not a hand-built map")
		assert(MapNames.plot(12) == "Plot12" and MapNames.queuePad(4) == "QueuePad4" and MapNames.slotParts(1)[1] == "Dome1Base" and MapNames.slotParts(3)[1] == "Stand2")
		assert(MapNames.findRoot({ { Name = "Lobby" }, { Name = "FTP_Lobby" } }).Name == "FTP_Lobby", "the owner's FTP_Lobby wins")
		assert(MapNames.PlotCount <= ParkConfig.Plot.Count and MapNames.DomeCount == #ParkConfig.Showcase.Domes)
		assert(MapNames.QueuePadCount == #ParkConfig.QueuePads.Spots)
	end)

	test("park: the wander box keeps clear of the middle dome and inside the fence", function()
		local S = ParkConfig.Showcase
		local W = S.Wander
		local B = S.Domes[1]
		local half = ParkConfig.Plot.Size / 2
		assert(W.MinX > -half + 2 and W.MaxX < half - 2 and W.MinZ > -half + 2)
		for _, c in { { W.MinX, W.MaxZ }, { W.MaxX, W.MaxZ }, { 0, W.MaxZ } } do
			local d = math.sqrt((c[1] - B.X) ^ 2 + (c[2] - B.Z) ^ 2)
			assert(d >= W.AvoidR, "wander box corner too close to the middle dome")
		end
	end)

	test("park: with the ExtraPlots pass every display slot past the domes still shows (none dropped at 20)", function()
		local Config, RobuxConfig = shared("Config"), shared("RobuxConfig")
		local slots = RobuxConfig.displaySlots(Config.Display[#Config.Display].Slots, { Passes = { ExtraPlots = true } })
		assert(slots > 20, "ExtraPlots adds slots past the biggest level")
		local pets = {}
		for i = 1, slots do
			table.insert(pets, { Id = "p" .. i, Rarity = "Common", Value = i })
		end
		local arr = ParkConfig.arrange(pets, ParkConfig.wanderCap(slots))
		assert(#arr.Domes + #arr.Yard == slots, ("%d of %d pets placed"):format(#arr.Domes + #arr.Yard, slots))
		assert(ParkConfig.wanderCap(3) == ParkConfig.Showcase.MaxWander, "small displays keep the default cap")
	end)
end
