-- Pet Battle floating islands (shared/IslandRules): one island per fight, far apart, fights fit the floor.
return function(t)
	local test, shared = t.test, t.shared
	local Vector3, CFrame = t.Vector3, t.CFrame
	local R = shared("IslandRules")
	local PvpConfig = shared("PvpConfig")

	test("island: every fight gets its own island, far from the others and from the lobby", function()
		local seen = {}
		for slot = 1, 12 do
			local p = R.spot(slot)
			assert(p.Magnitude > 2000, "far from the lobby (origin)")
			assert(p.Y > 300, "up in the sky")
			for _, q in seen do
				assert((p - q).Magnitude >= PvpConfig.Island.Spacing - 1e-6, "islands never overlap")
			end
			table.insert(seen, p)
		end
		assert((R.spot(1) - PvpConfig.Island.Base).Magnitude < 1e-6, "slot 1 at the base")
	end)

	test("island: the fight sits on the floor top and the stadium layout fits inside it", function()
		local floor = CFrame.new(10, 600, 20)
		local origin, layout = R.origin(floor, Vector3.new(64, 2, 64), PvpConfig.Island.Radius)
		assert(math.abs(origin.Position.Y - 601) < 1e-6, "floor top")
		assert(layout == "LiveBig", "a 64-stud island uses the stadium layout")
		local L = PvpConfig.Layouts[layout]
		for _, z in { L.PetZ, L.FoeZ, L.StandZ } do
			local p = origin * Vector3.new(L.StandX or 0, 0, z)
			assert(R.onIsland(origin, PvpConfig.Island.Radius, p), "every mark is on the island")
		end
		local _, small = R.origin(floor, Vector3.new(20, 1, 20))
		assert(small == "Live", "a small floor uses the small layout")
		assert(not R.onIsland(origin, 30, origin.Position + Vector3.new(0, -60, 0)), "fell off")
		assert(not R.onIsland(origin, 30, origin.Position + Vector3.new(60, 0, 0)), "walked off the edge")
	end)
end
