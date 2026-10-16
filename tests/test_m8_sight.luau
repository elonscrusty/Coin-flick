-- Pickup line of sight (pure part, src/shared/SightRules.luau). RockService supplies the real raycast.
return function(t)
	local test, shared, V3 = t.test, t.shared, t.Vector3
	local Sight = shared("SightRules")

	local function part(o)
		o = o or {}
		return { CanCollide = o.CanCollide ~= false, CameraIgnore = o.CameraIgnore == true, Character = o.Character == true, Transparency = o.Transparency or 0 }
	end
	-- A fake world along one ray: parts sit at fixed distances from the eye (straight-line test).
	local function world(list)
		return function(origin, dir)
			local base = origin
			local best
			for _, w in list do
				local d = w.At - (w.From or 0)
				-- distance from the current origin: parts are described by absolute distance from the eye
				local rel = w.At - (origin - V3.new(0, 5, 0)).Magnitude
				if rel > 0 and rel <= dir.Magnitude + 1e-6 and (not best or rel < best.Distance) then
					best = { Distance = rel, Part = w.Part }
				end
			end
			return best
		end
	end
	local eye = V3.new(0, 5, 0)
	local rock = V3.new(0, 5, -6)

	test("m8 sight: open ground is clear", function()
		assert(Sight.clear(eye, Sight.target(eye, rock, 2.2), world({})))
	end)

	test("m8 sight: a solid wall between head and rock blocks", function()
		assert(not Sight.clear(eye, Sight.target(eye, rock, 2.2), world({ { At = 3, Part = part() } })))
	end)

	test("m8 sight: characters, decor, non-collidable and see-through parts are walked through", function()
		local w = world({
			{ At = 1, Part = part({ Character = true }) },
			{ At = 2, Part = part({ CameraIgnore = true }) },
			{ At = 3, Part = part({ CanCollide = false }) },
			{ At = 4, Part = part({ Transparency = 1 }) },
		})
		assert(Sight.clear(eye, Sight.target(eye, rock, 2.2), w))
	end)

	test("m8 sight: a wall hidden behind decor still blocks", function()
		local w = world({ { At = 1.5, Part = part({ CameraIgnore = true }) }, { At = 3, Part = part() } })
		assert(not Sight.clear(eye, Sight.target(eye, rock, 2.2), w))
	end)

	test("m8 sight: a part at the rock itself does not block (the ray stops short of the shell)", function()
		local tgt = Sight.target(eye, rock, 2.2)
		assert((tgt - rock).Magnitude > 0.9 and (tgt - rock).Magnitude < 1.2, "stops about one stud before the centre")
		assert(Sight.clear(eye, tgt, world({ { At = 5.5, Part = part() } })))
	end)

	test("m8 sight: eye is the head, or the root plus a lift", function()
		assert(math.abs(Sight.eye(V3.new(1, 3, 1), V3.new(1, 4.5, 1)).Y - 4.5) < 1e-4)
		assert(math.abs(Sight.eye(V3.new(1, 3, 1), nil).Y - (3 + Sight.EYE_LIFT)) < 1e-4)
	end)

	test("m8 sight: a cluster of ignorable parts fails closed instead of looping", function()
		local list = {}
		for i = 1, 40 do
			table.insert(list, { At = 0.1 + i * 0.1, Part = part({ CameraIgnore = true }) })
		end
		assert(not Sight.clear(eye, Sight.target(eye, rock, 2.2), world(list)))
	end)

	-- A solid slab across z in [-1.5, -0.5] (full height). Like Roblox, a cast that starts inside the slab misses it.
	local function slab(origin, dir)
		local z0, z1 = -0.5, -1.5
		if origin.Z <= z0 and origin.Z >= z1 then
			return nil
		end
		if origin.Z > z0 and dir.Z < 0 then
			local dist = (origin.Z - z0) / -dir.Z * dir.Magnitude
			if dist <= dir.Magnitude then
				return { Distance = dist, Part = part() }
			end
		end
		return nil
	end

	test("m8 sight: a head pushed into a wall cannot see through it", function()
		local root = V3.new(0, 3.5, 0)
		local head = V3.new(0, 5, -1) -- inside the slab
		local tgt = Sight.target(head, rock, 2.2)
		assert(Sight.clear(head, tgt, slab), "the plain eye cast misses the wall it starts in")
		assert(not Sight.clearFrom(root, head, tgt, slab), "the root -> head segment catches it")
	end)

	test("m8 sight: clearFrom passes with nothing in the way", function()
		local root = V3.new(0, 3.5, 0)
		assert(Sight.clearFrom(root, eye, Sight.target(eye, rock, 2.2), world({})))
	end)
end
