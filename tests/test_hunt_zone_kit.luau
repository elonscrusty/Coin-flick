-- Per-zone hunt piece sets (shared/HuntZoneKit, used by server/HuntLowPoly): the naming contract the Studio import
-- follows, and the spots every piece lands on stay outside the play area (fence + landmark ring), off the north road
-- and inside the skyline band, so the gameplay inside the fence is unchanged.
return function(t)
	local test, shared = t.test, t.shared
	local Kit = shared("HuntZoneKit")
	local HP = shared("HuntPlacement")
	local ZoneThemes = shared("ZoneThemes")
	local Config = shared("Config")
	local HALF = HP.FenceHalf
	local L = ZoneThemes.Layout

	test("hunt zone kit: every hunt tier maps to a zone, one folder name each", function()
		local seen = {}
		for _, tier in Config.TierOrder do
			local zone = Kit.ZoneOfTier[tier]
			assert(zone, "no zone for tier " .. tostring(tier))
			assert(not seen[zone], "two tiers share " .. zone)
			seen[zone] = true
			assert(Kit.folderName(zone) == "HuntZoneKit_" .. zone)
		end
		assert(Kit.folderName("Volcano") == "HuntZoneKit_Volcano")
	end)

	test("hunt zone kit: names with zone suffix and Blender numbers map to their role", function()
		local cases = {
			{ "Hero", "Hero", "Hero" },
			{ "Hero_Volcano", "Hero", "Hero" },
			{ "Hero_Volcano.001", "Hero", "Hero" },
			{ "Skyline_B_Volcano", "Skyline", "Skyline_B" },
			{ "SkylineFill_3.002", "SkylineFill", "SkylineFill_3" },
			{ "PetStatue_Volcano", "PetStatue", "PetStatue" },
			{ "ZoneGate", "ZoneGate", "ZoneGate" },
			{ "Ground_Volcano", "Ground", "Ground" },
			{ "PathEdge", "PathEdge", "PathEdge" },
			{ "Scatter_ObsidianSpike_Volcano", "Scatter", "Scatter_ObsidianSpike" },
		}
		for _, c in cases do
			local role, key = Kit.roleOf(c[1], "Volcano")
			assert(role == c[2] and key == c[3], c[1] .. " -> " .. tostring(role) .. "/" .. tostring(key))
		end
		-- not kit pieces: another zone's suffix, the meadow set's names, unknown skyline letters
		for _, n in { "Hero_Snow", "Hunt_Ground", "Hunt_Ground_Volcano", "Skyline_D", "SkylineFill_4", "Cliff", "" } do
			assert(Kit.roleOf(n, "Volcano") == nil, n .. " should not be a kit piece")
		end
	end)

	test("hunt zone kit: plan groups keys by role, sorted, first copy wins", function()
		local plan = Kit.plan({ "Skyline_C", "Skyline_A_Volcano", "Skyline_A.001", "Hero", "Scatter_Bones", "Scatter_Lava", "Junk" }, "Volcano")
		assert(#plan.Skyline == 2 and plan.Skyline[1] == "Skyline_A" and plan.Skyline[2] == "Skyline_C")
		assert(#plan.Hero == 1 and #plan.Scatter == 2)
		assert(plan.Ground == nil and plan.Junk == nil)
		-- an empty folder plans nothing: the zone builds exactly as before
		assert(next(Kit.plan({}, "Volcano")) == nil)
	end)

	local function onRoad(s): boolean
		return s.Z < -HALF and math.abs(s.X) < L.RoadHalfWidth
	end

	test("hunt zone kit: skyline, fillers, hero and statue stand outside the fence ring, off the road, inside the band", function()
		local ringR = HALF + L.RingOut
		for _, role in { "Skyline", "SkylineFill", "Hero", "PetStatue" } do
			local slots = Kit.slots(role, HALF)
			assert(#slots > 0, role)
			for _, s in slots do
				local r = math.sqrt(s.X * s.X + s.Z * s.Z)
				-- outside the square fence plus the landmark ring on both axes' far side
				assert(math.max(math.abs(s.X), math.abs(s.Z)) >= ringR, role .. " inside the ring at " .. s.X .. "," .. s.Z)
				assert(r <= Kit.MaxR, role .. " past the skyline band: " .. r)
				-- on the road axis only the hero, and skyline pieces behind it (they close the view past the hero)
				if role ~= "Hero" and not (role == "Skyline" and s.Z < Kit.HeroZ - 5) then
					assert(not onRoad(s), role .. " on the north road at " .. s.X .. "," .. s.Z)
				end
			end
		end
		-- the hero closes the north road's view: on its axis, past the road strip's end (z -115)
		local h = Kit.slots("Hero", HALF)[1]
		assert(h.X == 0 and h.Z < -115 - 10, "hero spot " .. h.Z)
	end)

	test("hunt zone kit: gate on the north fence line, road trim beside the road, ground centred", function()
		local g = Kit.slots("ZoneGate", HALF)[1]
		assert(g.X == 0 and math.abs(g.Z + HALF) <= 2, "gate " .. g.Z)
		local edges = Kit.slots("PathEdge", HALF)
		assert(#edges == 2)
		for _, e in edges do
			assert(math.abs(e.X) > L.RoadHalfWidth and e.Z < -HALF, "edge " .. e.X .. "," .. e.Z)
		end
		assert(edges[1].X == -edges[2].X)
		local gr = Kit.slots("Ground", HALF)[1]
		assert(gr.X == 0 and gr.Z == 0)
	end)

	test("hunt zone kit: ring pieces face the arena centre (front = -Z)", function()
		for _, role in { "Skyline", "SkylineFill", "PetStatue" } do
			for _, s in Kit.slots(role, HALF) do
				-- LookVector of CFrame.Angles(0, yaw, 0) is (-sin yaw, 0, -cos yaw)
				local lx, lz = -math.sin(s.Yaw), -math.cos(s.Yaw)
				local r = math.sqrt(s.X * s.X + s.Z * s.Z)
				local dot = (lx * -s.X + lz * -s.Z) / r
				assert(dot > 0.999, role .. " not facing the centre: " .. dot)
			end
		end
	end)

	test("hunt zone kit: skyline variants are dealt round the spots", function()
		local slots = Kit.slots("Skyline", HALF, { "Skyline_A", "Skyline_C" })
		for i, s in slots do
			assert(s.Variant == (if i % 2 == 1 then "Skyline_A" else "Skyline_C"))
		end
		assert(Kit.slots("Skyline", HALF)[1].Variant == nil)
	end)

	test("hunt zone kit: scatter stands in for nature props only, fitted to their footprint", function()
		local keys = { "Scatter_A", "Scatter_B", "Scatter_C" }
		assert(Kit.scatterFor("PineTree", 1, keys) == "Scatter_A")
		assert(Kit.scatterFor("Rock", 5, keys) == "Scatter_B")
		for _, keep in { "Barrel", "Crate", "HayBale", "CliffTall" } do
			assert(Kit.scatterFor(keep, 1, keys) == nil, keep .. " should stay")
		end
		assert(Kit.scatterFor("PineTree", 1, {}) == nil)
		-- every scatterable prop that really is in the scenery list
		local inList = {}
		for _, row in HP.SCENERY do
			inList[row[1]] = true
		end
		for prop in Kit.Scatterable do
			assert(inList[prop] or prop == "CliffPine" or prop == "Kit_Pine_A" or prop == "PineTree", prop .. " never placed")
		end
		assert(math.abs(Kit.fitScale(10, 5) - 0.5) < 1e-9)
		assert(Kit.fitScale(0, 5) == 1 and Kit.fitScale(4, 0) == 1)
	end)

	-- angular distance between two bearings, degrees
	local function adiff(a: number, b: number): number
		local d = math.abs((a - b) % 360)
		return math.min(d, 360 - d)
	end
	local function bearing(sl): number
		return math.deg(math.atan2(sl.X, -sl.Z)) % 360
	end

	test("hunt zone kit: skyline ring has no gaps for any piece width (runner gap scan, NNE 7-44 deg)", function()
		for _, w in { 20, 45, 80, 120, 200 } do
			local slots = Kit.slots("Skyline", HALF, { "Skyline_A" }, w)
			local half = Kit.spanDeg(w, Kit.SkylineR) / 2
			for b10 = 0, 3595, 5 do
				local b = b10 / 10
				local covered = false
				for _, sl in slots do
					if adiff(bearing(sl), b) <= half then
						covered = true
						break
					end
				end
				assert(covered, "skyline gap at bearing " .. b .. " for width " .. w)
			end
			assert(#slots <= 48, "too many skyline copies " .. #slots)
		end
	end)

	test("hunt zone kit: fillers close every bearing except the north road window", function()
		for _, w in { 15, 40, 60, 100 } do
			local slots = Kit.slots("SkylineFill", HALF, { "SkylineFill_1" }, w)
			local half = Kit.spanDeg(w, Kit.FillR) / 2
			for _, sl in slots do
				assert(adiff(bearing(sl), 0) >= Kit.FillSkipDeg - 1e-6, "filler in the road window at " .. bearing(sl))
			end
			for b = Kit.FillSkipDeg + half, 360 - Kit.FillSkipDeg - half, 0.5 do
				local covered = false
				for _, sl in slots do
					if adiff(bearing(sl), b) <= half + 1e-6 then
						covered = true
						break
					end
				end
				assert(covered, "filler gap at " .. b .. " width " .. w)
			end
		end
	end)

	local RoundRocks = shared("RoundRocks")
	local angles = {}
	for i = 1, Config.Station.Count do
		table.insert(angles, RoundRocks.stationAngle(i))
	end

	test("hunt zone kit: nest clusters clear the fence, the road and the east drop; every nest gets one", function()
		local spots = Kit.clusterSpots(HALF, angles)
		local perNest = {}
		for _, cs in spots do
			local R = cs.Size * Kit.BigScatter / 2
			assert(math.max(math.abs(cs.X), math.abs(cs.Z)) - R >= HALF + Kit.FenceClear - 1e-6, "cluster clips the fence at " .. cs.X .. "," .. cs.Z)
			assert(cs.X + R <= L.DropX + 1e-6, "cluster on the east drop")
			assert(not (cs.Z - R < -HALF and math.abs(cs.X) < L.RoadHalfWidth + R), "cluster on the road")
			assert(not Kit.inLane(cs.X, cs.Z, R, HALF), "cluster in the central path")
			-- nearest nest bearing
			local best, bi = math.huge, 0
			for i, a in angles do
				local d = adiff(math.deg(math.atan2(cs.Z, cs.X)), math.deg(a))
				if d < best then
					best, bi = d, i
				end
			end
			perNest[bi] = (perNest[bi] or 0) + 1
		end
		for i = 1, #angles do
			assert((perNest[i] or 0) >= 3, "nest " .. i .. " has only " .. tostring(perNest[i]) .. " cluster props")
		end
	end)

	test("hunt zone kit: central path is clear of the nests, bays and sell stand edges; markers line the road", function()
		assert(Kit.inLane(0, -30, 0, HALF) and Kit.inLane(0, -100, 1, HALF))
		assert(not Kit.inLane(20, -30, 1, HALF) and not Kit.inLane(0, 30, 1, HALF))
		for i = 1, Config.Station.Count do
			local p = RoundRocks.stationPosition(i)
			assert(not Kit.inLane(p.X, p.Z, 8, HALF), "nest " .. i .. " in the path")
			local b = p.Unit * 32.75
			assert(not Kit.inLane(b.X, b.Z, 7, HALF), "bay " .. i .. " in the path")
		end
		local marks = Kit.laneMarkers(HALF)
		assert(#marks >= 10 and #marks % 2 == 0)
		for _, m in marks do
			assert(math.abs(m.X) > L.RoadHalfWidth + 1, "marker on the road")
			assert(m.Z < -HALF and m.Z >= Kit.RoadEndZ, "marker off the road's length")
			assert(not Kit.inLane(m.X, m.Z, 0.8, HALF))
		end
		-- every zone has a full style
		for _, zone in Kit.Zones do
			local st = Kit.Style[zone]
			assert(st and st.Path and st.Accent and st.Pad and #st.Hill >= 1, zone)
		end
	end)
end
