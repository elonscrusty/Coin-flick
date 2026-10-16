-- Pet Battle camera director shot maths (src/shared/FightCamRules.luau).
return function(t)
	local test, shared = t.test, t.shared
	local Vector3, CFrame = t.Vector3, t.CFrame
	local R = shared("FightCamRules")
	local PvpConfig = shared("PvpConfig")

	local origin = CFrame.lookAt(Vector3.new(0, 2, 0), Vector3.new(-1, 2, 0)) -- the stadium: teams along X
	local layout = PvpConfig.Layouts.LiveBig
	local s = R.stage(origin, layout)
	local mine = (origin * CFrame.new(0, 0, layout.PetZ)).Position
	local foe = (origin * CFrame.new(0, 0, layout.FoeZ)).Position

	-- (no LookVector checks: the offline CFrame.lookAt returns a transposed rotation; positions are exact)
	local function near(a, b, eps)
		return (a - b).Magnitude < (eps or 1e-3)
	end

	test("fight cam: the stage sits between the teams, the base view is high behind the player's team", function()
		assert(near(s.Centre - Vector3.new(0, 1.5, 0), (mine + foe) / 2), "centre between the lines")
		assert(s.Back:Dot((mine - foe).Unit) > 0.99, "back points at the player's own pets")
		for _, tt in { 0, 1.7, 5, 13 } do
			local cf = R.base(s, tt)
			local p = cf.Position
			assert(p.Y > s.Centre.Y + 3, "looks down on the pets")
			assert((p - foe).Magnitude > (p - mine).Magnitude, "on the player's side")
			assert((p - s.Centre).Magnitude > math.abs(layout.PetZ) + 3, "far enough to see both teams")
		end
		assert(not near(R.base(s, 0).Position, R.base(s, 4).Position, 0.5), "it pans")
	end)

	test("fight cam: the intro starts wide on the rival's side and lands on the base view", function()
		local a = R.introAt(s, 0).Position
		assert((a - s.Centre).Magnitude > (R.base(s, 0).Position - s.Centre).Magnitude * 1.5, "wide")
		assert((a - foe).Magnitude < (a - mine).Magnitude, "starts over the rival's side")
		assert(near(R.introAt(s, 1).Position, R.base(s, 0).Position, 0.01), "ends on the base view")
	end)

	test("fight cam: close-ups, K.O. orbit and hero shot frame the pet from the player's side", function()
		local at = foe + Vector3.new(0, 1, 2)
		local c = R.closeUp(s, at, mine, 3, 0.5)
		assert((c.Position - at).Magnitude < 14, "close")
		local o1, o2 = R.orbit(s, at, 3, 0), R.orbit(s, at, 3, 1)
		assert(math.abs((o1.Position - at).Magnitude - (o2.Position - at).Magnitude) < 1e-3, "orbit keeps its distance")
		assert(not near(o1.Position, o2.Position, 1), "orbit moves")
		local h0, h1 = R.hero(s, at, 3, 0), R.hero(s, at, 3, 3)
		assert((h1.Position - at).Magnitude < (h0.Position - at).Magnitude, "hero pushes in")
		assert(h1.Position.Y < R.base(s, 0).Position.Y, "hero is lower than the base view")
		local d = (h1.Position - at)
		assert(d.Y > 0.4 * Vector3.new(d.X, 0, d.Z).Magnitude, "hero looks down on the pet (never a floor-level shot)")
		assert(R.HERO_FOV < R.FIGHT_FOV and R.FIGHT_FOV < 60, "fight lens is narrow, hero narrower")
		local sh = R.shoulder(s, mine)
		assert((sh.Position - foe).Magnitude > (mine - foe).Magnitude, "behind the caster")
	end)

	test("fight cam: the base view is a moving three-quarter side view, never straight behind the player's team", function()
		local lo, hi = math.huge, -math.huge
		for i = 0, 140 do
			local tt = i * 0.1
			local p = R.base(s, tt).Position
			local flat = Vector3.new(p.X - s.Centre.X, 0, p.Z - s.Centre.Z).Unit
			local off = math.acos(math.clamp(flat:Dot(s.Back), -1, 1))
			assert(off > 0.3, "never straight behind the avatar on its mark")
			assert(off < math.rad(85), "stays on the player's side")
			lo, hi = math.min(lo, off), math.max(hi, off)
		end
		assert(hi - lo > math.rad(35), "the orbit sweeps a wide arc (Studio: the old pan moved ~5 studs)")
		-- the player's avatar on its mark never stands between the camera and the fight
		local avatar = (origin * CFrame.new(layout.StandX or 0, 3, layout.StandZ)).Position
		for i = 0, 140 do
			local p = R.base(s, i * 0.1).Position
			local seg = s.Centre - p
			local u = math.clamp((avatar - p):Dot(seg) / seg:Dot(seg), 0, 1)
			local gap = (p + seg * u - avatar).Magnitude
			assert(gap > 6, "avatar clear of the camera's view line: " .. gap)
			local flatCam = (p - s.Centre) * Vector3.new(1, 0, 1)
			local flatAv = (avatar - s.Centre) * Vector3.new(1, 0, 1)
			assert(flatCam:Dot(flatAv) / (flatCam.Magnitude * flatAv.Magnitude) < 0.7, "the camera orbits the other side from the avatar")
		end
		assert(near(R.introAt(s, 1).Position, R.base(s, 0).Position, 0.01), "the intro lands on the base view")
	end)

	test("fight cam: a hit leans the base view towards the pet that was hit and eases back", function()
		local b = R.base(s, 2)
		local at = foe + Vector3.new(3, 1, 0)
		local n = R.nudge(b, s, at, 1)
		assert((n.Position - at).Magnitude < (b.Position - at).Magnitude - 1, "pushes in")
		assert(near(R.nudge(b, s, at, 0).Position, b.Position), "no lean at k = 0")
	end)

	test("fight cam: easing is frame-rate independent and bounded", function()
		local a = R.alpha(4, 1 / 60)
		local twice = 1 - (1 - R.alpha(4, 1 / 120)) ^ 2
		assert(math.abs(a - twice) < 1e-9)
		assert(R.alpha(4, 0) == 0 and R.alpha(4, 100) <= 1)
	end)
	-- Projects every pet (feet and head) into the base view, on its own (not with FightCamRules.project), for the
	-- screens players use and the pet sizes and team sizes a fight can have, and checks they all sit inside the part
	-- of the screen the fight HUD leaves clear. Studio 2026-10-15: a fixed distance tuned for a 2.16 phone cut the
	-- rival off on a 16:9 window and hid the player's pet behind SPECIAL; 2026-10-14: pets were a tenth of the screen.
	test("fight cam: the base view fits both teams clear of the HUD on every screen", function()
		local UP = Vector3.new(0, 1, 0)
		local SAFE = R.SAFE
		local tanV = math.tan(math.rad(R.FIGHT_FOV) / 2)
		local function linePts(z, gap, n)
			local out = {}
			for i = 1, n do
				table.insert(out, (origin * CFrame.new((i - (n + 1) / 2) * gap, 0, z)).Position)
			end
			return out
		end
		local nearest = {}
		for _, aspect in { 4 / 3, 16 / 9, 2.16 } do
			for _, height in { 3, 7 } do
				for _, n in { 1, 3 } do
					local st = R.stage(origin, layout, { Aspect = aspect, Height = height, Pets = n, Foes = n })
					assert(st.R < R.MAX_R, "a fitting distance was found")
					local pts = linePts(layout.PetZ, layout.PetGap, n)
					for _, p in linePts(layout.FoeZ, layout.FoeGap, n) do
						table.insert(pts, p)
					end
					local biggest = 0
					for i = 0, 280 do
						local p = R.base(st, i * 0.05).Position
						local aim = R.focus(st)
						local fwd = (aim - p).Unit
						local right = fwd:Cross(UP).Unit
						local up = right:Cross(fwd)
						for _, foot in pts do
							for _, lift in { 0, height } do
								local d = foot + UP * lift - p
								local dz = d:Dot(fwd)
								assert(dz > 3, "pet in front of the camera")
								local x, y = d:Dot(right) / dz / (tanV * aspect), d:Dot(up) / dz / tanV
								assert(SAFE.X0 < x and x < SAFE.X1 and SAFE.Y0 < y and y < SAFE.Y1,
									string.format("pet clear of the HUD aspect=%.2f h=%d n=%d t=%.1f x=%.2f y=%.2f", aspect, height, n, i * 0.05, x, y))
							end
							biggest = math.max(biggest, height / (2 * (foot - p):Dot(fwd) * tanV))
						end
					end
					nearest[string.format("%.2f/%d/%d", aspect, height, n)] = biggest
				end
			end
		end
		-- and it is no wider than it must be: one pet a side on a phone fills a good part of the screen
		assert(nearest["2.16/3/1"] > 0.15, "1v1 on a phone reads big: " .. nearest["2.16/3/1"])
		assert(nearest["1.78/7/3"] > 0.2, "big pets on 16:9 read big: " .. nearest["1.78/7/3"])
	end)
end
