-- m11 camera + spawn fix (docs/m11/CAMERA_SPAWN_FIX.md): third-person lobby, first-person hunt, the desktop
-- free-cursor key, the lobby camera room box and the lodge room numbers the spawn check relies on.
return function(t)
	local test, shared, V3 = t.test, t.shared, t.Vector3
	local CameraModeRules = shared("CameraModeRules")
	local CameraSolve = shared("CameraSolve")
	local Config = shared("Config")

	test("m11 camera: first person only in a hunt, the lobby is third person", function()
		assert(CameraModeRules.firstPerson(true, true) == true, "hunt")
		assert(CameraModeRules.firstPerson(true, false) == false, "lobby is third person")
		assert(CameraModeRules.firstPerson(false, true) == false, "switch off: hunts third person too")
		local lobby = CameraModeRules.decide({ FirstPerson = CameraModeRules.firstPerson(true, false), Blocked = false, Cinematic = false })
		assert(lobby.Mode == "Classic" and not lobby.Reticle and lobby.Actions and not lobby.CursorFree, "lobby: classic, no reticle")
		local hunt = CameraModeRules.decide({ FirstPerson = CameraModeRules.firstPerson(true, true), Blocked = false, Cinematic = false })
		assert(hunt.Mode == "LockFirstPerson" and hunt.Reticle and not hunt.CursorFree, "hunt: locked first person")
	end)

	test("m11 camera: the free-cursor key frees the mouse in a hunt and does nothing in the lobby", function()
		local peek = CameraModeRules.decide({ FirstPerson = true, Blocked = false, Cinematic = false, Peek = true })
		assert(peek.CursorFree and not peek.Reticle and not peek.Actions, "held: free cursor, no reticle, no world action")
		local lobby = CameraModeRules.decide({ FirstPerson = false, Blocked = false, Cinematic = false, Peek = true })
		assert(not lobby.CursorFree and lobby.Actions, "lobby: the mouse is free anyway, nothing changes")
		local released = CameraModeRules.decide({ FirstPerson = true, Blocked = false, Cinematic = false, Peek = false })
		assert(not released.CursorFree and released.Reticle, "released: locked again")
		assert(#Config.Camera.FreeCursorKeys >= 1, "at least one key")
	end)

	test("m11 camera: lobby zoom limits are sane", function()
		local L = Config.Camera.Lobby
		assert(L.MinZoom >= 0.5 and L.MinZoom < L.MaxZoom, "min below max")
		assert(L.MaxZoom <= Config.Lodge.CeilingY - Config.Lodge.FloorY, "the longest zoom fits under the ceiling")
	end)

	test("m11 camera: the park box stops the camera at the boundary and the sky ceiling", function()
		local L = Config.Lodge
		local lo, hi = V3.new(L.MinX, L.FloorY, L.MinZ), V3.new(L.MaxX, L.CeilingY, L.MaxZ)
		local head = V3.new(0, L.FloorY + 5, L.MaxZ - 20)
		local up = CameraSolve.boxExit(head, V3.new(0, 1, 0), lo, hi)
		assert(up and math.abs(up - (L.CeilingY - head.Y)) < 1e-6, "straight up: the sky ceiling")
		assert(up > Config.Camera.Lobby.MaxZoom, "outdoors: the ceiling never shortens a normal zoom")
		local back = CameraSolve.boxExit(head, V3.new(0, 0, 1), lo, hi)
		assert(back and math.abs(back - 20) < 1e-6, "behind: the south boundary")
		assert(CameraSolve.boxExit(V3.new(0, 1, 1200), V3.new(0, 1, 0), lo, hi) == nil, "outside the park (arenas): no box")
		assert(CameraSolve.allowed(25, { back }) <= back - CameraSolve.Margin + 1e-6)
	end)

	test("m11 lobby: the park box matches the park bounds and the spawn is inside it", function()
		local L = Config.Lodge
		local ParkConfig = shared("ParkConfig")
		local B = ParkConfig.Bounds
		assert(L.FloorY == 0)
		assert(L.MinX == B.MinX and L.MaxX == B.MaxX and L.MinZ == B.MinZ and L.MaxZ == B.MaxZ, "Config.Lodge mirrors ParkConfig.Bounds")
		assert(ParkConfig.inside(ParkConfig.Spawn.X, ParkConfig.Spawn.Z), "spawn inside")
		assert(Config.Camera.Lobby.MaxZoom <= L.CeilingY - L.FloorY)
	end)
end
