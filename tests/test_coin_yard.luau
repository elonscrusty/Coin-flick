-- Coin yard rules (src/shared/CoinYard.luau).
return function(t)
	local test, shared = t.test, t.shared
	local CY = shared("CoinYard")

	test("coin yard: coin odds add up to 1 and the sign prints every one", function()
		local sum = 0
		for _, c in CY.Coins do
			sum += c.Chance
		end
		assert(math.abs(sum - 1) < 1e-9, "odds sum " .. sum)
		local text = table.concat(CY.oddsLines(), "\n")
		for _, c in CY.Coins do
			assert(string.find(text, c.Name, 1, true), c.Name .. " missing from the odds sign")
		end
		assert(string.find(text, "Heads 55%", 1, true), "heads chance printed")
	end)

	test("coin yard: heads pays more than tails, rare coins pay more, tails still pays", function()
		local h = CY.flip(100, 0.1, 0.1, 1)
		local tails = CY.flip(100, 0.9, 0.1, 1)
		local gold = CY.flip(100, 0.1, 0.95, 1)
		assert(h.heads and h.cash == 100 and h.coin == "Copper")
		assert(not tails.heads and tails.cash == 20)
		assert(gold.coin == "Gold" and gold.cash == 1000, "gold " .. gold.cash)
		assert(CY.flip(100, 0.1, 0.999, 1).coin == "Diamond")
		assert(CY.flip(1, 0.9, 0.1, 1).cash >= 1, "a flip never pays 0")
	end)

	test("coin yard: chain adds 10% per flip up to +100%, pet boost stacks, window resets", function()
		assert(CY.flip(100, 0.1, 0.1, 3).cash == 120)
		assert(CY.flip(100, 0.1, 0.1, 50).cash == 200, "chain capped")
		assert(CY.flip(100, 0.1, 0.1, 1, 0.5).cash == 150)
		assert(CY.nextChain(0, 0, 10) == 1)
		assert(CY.nextChain(4, 10, 11) == 5)
		assert(CY.nextChain(4, 10, 13) == 1, "outside the window restarts")
	end)

	test("coin yard: a basic egg costs about FlipsPerBasicEgg average base flips", function()
		local roundCoins = 5000
		local base = CY.baseFor(roundCoins)
		local eggPrice = roundCoins * CY.EggRounds
		local flips = eggPrice / (base * CY.meanMult())
		assert(flips > 10 and flips < CY.FlipsPerBasicEgg, "flips to afford an egg: " .. flips)
	end)

	test("coin yard: pads fit inside the yard and do not overlap", function()
		local P = CY.Pads
		local half = P.Size / 2
		for c = 1, P.Cols do
			for r = 1, P.Rows do
				local x, z = CY.padCentre(c, r)
				assert(math.abs(x - CY.Centre.X) + half <= CY.Size.X / 2, "pad inside x")
				assert(math.abs(z - CY.Centre.Z) + half <= CY.Size.Z / 2, "pad inside z")
				if c < P.Cols then
					local x2 = CY.padCentre(c + 1, r)
					assert(x2 - x >= P.Size + 1, "pads apart")
				end
			end
		end
		local lastX = CY.padCentre(P.Cols, 1)
		assert(lastX + half < CY.Stand.X - 4, "pads clear of the egg stand")
		local firstX = CY.padCentre(1, 1)
		assert(firstX - half > CY.YardArch.X + 4, "pads clear of the return arch")
	end)

	test("coin yard: yard sits outside the park and the battle ring in the clearing", function()
		local P = shared("ParkConfig")
		assert(CY.Centre.X - CY.Size.X / 2 > P.Bounds.MaxX + 40, "yard well past the park cliffs")
		assert(CY.ParkArch.X < P.Bounds.MaxX and CY.ParkArrive.X < CY.ParkArch.X)
		local half = P.Clearing.Half
		local r = CY.Ring.Diameter / 2
		assert(math.abs(CY.Ring.X) + r <= half and math.abs(CY.Ring.Z) + r <= half, "ring in the clearing")
		for _, s in P.QueuePads.Spots do
			local d = math.sqrt((s[1] - CY.Ring.X) ^ 2 + (s[2] - CY.Ring.Z) ^ 2)
			assert(d > r + P.QueuePads.Size / 2 + 2, "ring clear of the queue nests")
		end
	end)
end
