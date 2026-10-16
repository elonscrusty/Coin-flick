-- Results card rules (shared/ResultsRules): PLAY AGAIN leads, never a sell button, a few short lines.
return function(t)
	local test, shared = t.test, t.shared
	local R = shared("ResultsRules")
	local function ctx(o)
		return { Tutorial = o.Tutorial == true, Leader = o.Leader ~= false, Ready = o.Ready == true, Racers = o.Racers or 1 }
	end

	test("results: the primary button is PLAY AGAIN (READY! once tapped, TRAIN PET in the tutorial), never selling", function()
		assert(R.primary(ctx({})) == "PlayAgain", "solo")
		assert(R.primary(ctx({ Leader = false })) == "PlayAgain", "a member who has not tapped yet")
		assert(R.primary(ctx({ Leader = false, Ready = true })) == "Ready")
		assert(R.primary(ctx({ Tutorial = true })) == "TrainPet", "practice: the loop goes on to TRAIN")
		for _, label in R.Label do
			assert(not string.find(string.upper(label), "SELL", 1, true), label)
		end
	end)

	test("results: at most three short detail rows; no bag strip or pile-left line", function()
		for _, c in { ctx({}), ctx({ Racers = 4 }), ctx({ Tutorial = true, Racers = 4 }) } do
			local lines = R.lines(c)
			assert(#lines <= R.MaxLines and lines[1] == "Reward", "reward first")
			for _, l in lines do
				assert(l ~= "Bag" and l ~= "PileLeft", l)
			end
		end
		assert(#R.lines(ctx({ Racers = 3 })) == 3 and R.lines(ctx({ Racers = 3 }))[3] == "Racers")
	end)

	test("results: the card's buttons never offer selling (GO SELL SHELLS led it, walkthrough 10-14 #12)", function()
		local src = require("@lune/fs").readFile("src/client/ui/ResultsPanel.luau")
		for btn in string.gmatch(src, 'fb%("([^"]*)"') do
			assert(not string.find(string.upper(btn), "SELL", 1, true), "results button: " .. btn)
		end
	end)
end
