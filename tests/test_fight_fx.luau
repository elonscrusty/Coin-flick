-- Fight effect rules: moments escalate, Reduce Motion and Low Effects, the screen gate, debris physics.
return function(t)
	local test, shared, V3 = t.test, t.shared, t.Vector3
	local R = shared("FightFxRules")

	test("fight fx: moments escalate hit -> ko", function()
		local prev = nil
		for _, k in R.KINDS do
			local m = R.moment(k)
			assert(m.Kind == k, "kind " .. k)
			if prev then
				assert(m.Rank > prev.Rank, "rank climbs at " .. k)
				for _, f in { "Fov", "Shake", "Flash", "Tint" } do
					assert(m[f] >= prev[f] or k == "levelup", f .. " shrinks at " .. k)
				end
			end
			prev = m
		end
		local ko, crit, hit = R.moment("ko"), R.moment("crit"), R.moment("hit")
		assert(ko.Slow < 1 and ko.SlowTime > 0, "ko is slow motion")
		assert(crit.Slow == 1 and hit.Slow == 1, "crits and hits never slow the game")
		assert(ko.Banner and R.moment("special").Banner, "big moments have a banner")
		assert(R.moment("nope").Kind == "hit", "unknown kind is a plain hit")
	end)

	test("fight fx: reduce motion and low effects", function()
		local r = R.moment("ko", false, true)
		assert(r.Fov == 0 and r.Shake == 0 and r.Slow == 1 and r.SlowTime == 0, "no motion")
		assert(r.Flash < R.moment("ko").Flash, "softer flash")
		local l = R.moment("ko", true)
		assert(l.Chunks < R.moment("ko").Chunks and l.Rings >= 1 and l.Stars < R.moment("ko").Stars, "low effects lighter")
		for _, k in R.KINDS do
			assert(R.moment(k).Chunks <= R.MAX_CHUNKS, "chunks capped")
		end
	end)

	test("fight fx: screen gate", function()
		local g = R.newGate()
		assert(R.takeScreen(g, 3, 0, 0.5), "first crit")
		assert(not R.takeScreen(g, 1, 0.1), "hit waits")
		assert(not R.takeScreen(g, 3, 0.2), "same rank waits")
		assert(R.takeScreen(g, 6, 0.2, 1), "ko breaks through")
		assert(not R.takeScreen(g, 5, 0.5), "special waits for the ko")
		assert(R.takeScreen(g, 1, 1.3), "free again")
	end)

	test("fight fx: debris bounces and settles on the ground", function()
		local p, v = V3.new(0, 3, 0), V3.new(10, 25, 0)
		local settled, lowest = false, math.huge
		for _ = 1, 600 do
			local s
			p, v, s = R.chunkStep(p, v, 1 / 60, 0)
			lowest = math.min(lowest, p.Y)
			if s then
				settled = true
				break
			end
		end
		assert(settled, "settles")
		assert(lowest >= 0, "never under the ground")
		assert(R.shakeAt(1, 0) == 1 and R.shakeAt(1, 1) == 0 and R.shakeAt(1, 0.5) < 0.1, "shake decays")
	end)
	test("fight fx: the K.O. flash and bloom stay capped (Studio: the K.O. flash was blinding)", function()
		assert(R.MAX_FLASH <= 0.32 and R.MAX_BLOOM <= 0.8)
		for _, k in R.KINDS do
			assert(math.min(R.moment(k).Flash, R.MAX_FLASH) <= 0.32, k)
		end
	end)

	test("fight fx: pops in one batch are staggered in time and stepped up on the same pet", function()
		local st = {}
		local w1, s1 = R.popSlot(st, "a", 10)
		local w2, s2 = R.popSlot(st, "a", 10)
		local w3, s3 = R.popSlot(st, "b", 10)
		local w4, s4 = R.popSlot(st, "a", 10)
		assert(w1 == 0 and s1 == 0, "first pop lands at once")
		assert(w2 >= R.POP_GAP - 1e-9 and s2 == 1, "second pop on the same pet waits and steps up")
		assert(w3 > 0 and w3 < w2 + R.POP_GAP and s3 == 0, "another pet's pop waits a little, first slot")
		assert(w4 > w2 and s4 == 2, "third pop on the pet")
		for _ = 1, 30 do
			local w = R.popSlot(st, "a", 10)
			assert(w <= R.POP_MAX_WAIT, "never waits too long")
		end
		local w5, s5 = R.popSlot(st, "a", 100)
		assert(w5 == 0 and s5 == 0, "after a quiet spell the pet starts over")
	end)
end
