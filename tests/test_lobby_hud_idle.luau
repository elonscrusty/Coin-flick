-- Lobby HUD v2 idle personality (shared/LobbyHudIdle): every button has a short move that stays close to rest and
-- ends at rest, one button at a time with quiet gaps, PLAY the liveliest, DAILY only while claimable.
return function(t)
	local test, shared = t.test, t.shared
	local I = shared("LobbyHudIdle")

	test("lobby hud idle: every button has a short move that stays close to rest and ends at rest", function()
		local lim = I.Limit
		for _, name in I.Order do
			local m = I.Moves[name]
			assert(m and #m.Steps >= 2, name .. " has a move")
			local last = m.Steps[#m.Steps]
			assert(not last.x and not last.y and not last.rot and not last.sx and not last.sy, name .. " ends at rest")
			for _, s in m.Steps do
				assert(s.d > 0 and s.d <= 0.5, name .. " step time")
				assert(math.abs(s.x or 0) <= lim.Move and math.abs(s.y or 0) <= lim.Move, name .. " stays near its place")
				assert(math.abs((s.sx or 1) - 1) <= lim.Size and math.abs((s.sy or 1) - 1) <= lim.Size, name .. " size near 1")
				assert(math.abs(s.rot or 0) <= lim.Rot, name .. " tilt small")
				if (s.sx or 1) ~= (s.sy or 1) then
					assert(m.Stretch == true, name .. " squashes only with Stretch on")
				end
			end
			local d = I.duration(name)
			assert(d > 0.2 and d <= lim.Time, name .. " is a short moment: " .. d)
		end
		assert(I.Moves.Play.Fx == "Stars" and I.Moves.Daily.Fx == "Burst" and I.Moves.Train.Fx == "Glow" and I.Moves.Fight.Fx == "Flash", "decorations")
		assert(I.gap(0) >= 3 and I.gap(1) <= 8, "several quiet seconds between moments")
	end)

	-- run the scheduler for ten minutes the way the client does (move, quiet gap, next pick)
	local function simulate(claimable: boolean, seconds: number): ({ [string]: number }, { string })
		local seed = 7
		local function rnd(): number
			seed = (seed * 1103515245 + 12345) % 2147483648
			return seed / 2147483648
		end
		local lastAt: { [string]: number } = {}
		local count: { [string]: number } = {}
		local seq: { string } = {}
		local now, last = I.FirstWait, nil
		while now < seconds do
			local name = I.pick(now, lastAt, last, claimable, rnd())
			if name then
				lastAt[name] = now
				count[name] = (count[name] or 0) + 1
				table.insert(seq, name)
				last = name
				now += I.duration(name) + I.gap(rnd())
			else
				now += 0.5
			end
		end
		return count, seq
	end

	test("lobby hud idle: one at a time, staggered, PLAY liveliest, every button gets a turn", function()
		local count, seq = simulate(false, 600)
		for i = 2, #seq do
			assert(seq[i] ~= seq[i - 1], "never the same button twice in a row")
		end
		for _, name in I.Order do
			if name ~= "Daily" then
				assert((count[name] or 0) >= 3, name .. " moves now and then: " .. tostring(count[name]))
				if name ~= "Play" then
					assert(count.Play > count[name], "PLAY moves most (vs " .. name .. ")")
				end
			end
		end
		assert(#seq <= 600 / I.Gap.Min, "quiet gaps between moments")
	end)

	test("lobby hud idle: DAILY reminds only while a reward is claimable", function()
		local off = simulate(false, 600)
		assert(off.Daily == nil, "no DAILY wiggle with nothing to claim")
		local on = simulate(true, 600)
		assert((on.Daily or 0) >= 5, "DAILY wiggles while claimable: " .. tostring(on.Daily))
		assert(I.pick(100, {}, nil, false, 0.99, { Play = true, MyPets = true }) ~= "Play", "a held button never moves")
		local all = {}
		for _, n in I.Order do
			all[n] = true
		end
		assert(I.pick(100, {}, nil, true, 0.5, all) == nil, "nobody ready = nobody moves")
		assert(I.pick(10, { Play = 5 }, nil, false, 0, { MyPets = true, PetBook = true, Spin = true, Train = true, Fight = true, Shop = true }) == nil, "PLAY rests between its own turns")
	end)
end
