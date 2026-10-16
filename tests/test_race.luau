-- Race bar standings (src/shared/RaceRules.luau): most eggs cracked first, ties keep station order, no target info.
return function(t)
	local test, shared = t.test, t.shared
	local RaceRules = shared("RaceRules")

	test("race: most eggs first, ties keep station order, shares of the leader", function()
		local stations = {
			{ UserId = 10, Index = 1, Cracked = 3 },
			{ UserId = 20, Index = 2, Cracked = 6 },
			{ UserId = 30, Index = 3, Cracked = 3 },
		}
		local members = {
			{ UserId = 10, Name = "A", Present = true },
			{ UserId = 20, Name = "B", Present = true },
			{ UserId = 30, Name = "C", Present = true },
			{ UserId = 40, Name = "D", Present = false, Cracked = 1 },
		}
		local rows = RaceRules.standings(stations, members)
		assert(#rows == 4)
		assert(rows[1].UserId == 20 and rows[1].Leader and rows[1].Share == 1)
		assert(rows[2].UserId == 10 and rows[3].UserId == 30, "tie keeps station order")
		assert(rows[2].Share == 0.5 and not rows[2].Leader)
		assert(rows[4].UserId == 40 and rows[4].Cracked == 1 and not rows[4].Present)
	end)

	test("race: nobody cracked yet -> no leader, empty bars; junk counts are zero; ties have no leader", function()
		local rows = RaceRules.standings({ { UserId = 1, Index = 1, Cracked = 0 }, { UserId = 2, Index = 2, Cracked = -5 } }, {
			{ UserId = 1, Name = "A" },
			{ UserId = 2, Name = "B" },
		})
		for _, r in rows do
			assert(r.Cracked == 0 and r.Share == 0 and not r.Leader)
		end
		assert(#RaceRules.standings(nil, nil) == 0)
		local tie = RaceRules.standings({ { UserId = 1, Index = 1, Cracked = 2 }, { UserId = 2, Index = 2, Cracked = 2 } }, {
			{ UserId = 1, Name = "A" },
			{ UserId = 2, Name = "B" },
		})
		assert(not tie[1].Leader and tie[1].Share == 1 and tie[2].Share == 1)
	end)

	test("race: station views carry each member's crack count", function()
		local RoundRocks = shared("RoundRocks")
		local core = RoundRocks.new({
			MatchKey = "k",
			RoundId = 1,
			Tier = "Gravel",
			Seed = 5,
			TargetRng = t.Random.new(3),
			Members = { { UserId = 1, Tool = "Hammer", Station = 1 }, { UserId = 2, Tool = "Hammer", Station = 2 } },
		})
		for _, v in core:stationViews(0) do
			assert(v.Cracked == 0, "starts at zero")
		end
	end)
end
