-- Results accounting (owner brief V4 section B): started 9 rubble, earned 64, sold 24 then 30.
return function(t)
	local test, shared = t.test, t.shared
	local Ledger = shared("HuntLedger")

	local function assertEq(a, b, msg)
		if a ~= b then
			error((msg or "mismatch") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
		end
	end

	-- A tiny stand-in for the profile: the server owns this, the ledger only counts.
	local function newProfile(rubble, cash)
		return { Rubble = rubble, Cash = cash, Rate = 2, Cap = 30 }
	end
	local function bag(p)
		return { Count = p.Rubble, Capacity = p.Cap, Value = p.Rubble * p.Rate }
	end
	local function earn(l, p, uid, n) -- n ordinary rocks
		for _ = 1, n do
			assert(p.Rubble < p.Cap, "storage reserved: never over capacity")
			p.Rubble += 1
			Ledger.crushed(l, uid, true)
		end
	end
	local function sell(l, p, uid) -- same shape as EconomyService.sellRubble: all at once, once
		local n = p.Rubble
		if n == 0 then
			return
		end
		local cash = n * p.Rate
		p.Rubble = 0
		p.Cash += cash
		Ledger.sold(l, uid, n, cash)
	end

	test("ledger: 9 start + 64 earned, sold 24 then 30 -> bag 19, +$108, results match", function()
		local uid = 1
		-- Replay of the owner's recording: sales take whatever was in the bag at that moment.
		local l, p = Ledger.new(), newProfile(9, 207)
		local function saleOf(n)
			assert(p.Rubble >= n)
			p.Rubble -= n
			p.Cash += n * p.Rate
			Ledger.sold(l, uid, n, n * p.Rate)
		end
		earn(l, p, uid, 15) -- 24 in bag
		saleOf(24)
		earn(l, p, uid, 30) -- 30 in bag
		saleOf(30)
		earn(l, p, uid, 19) -- 64 earned in total
		Ledger.crushed(l, uid, false) -- the geode rock: processed, no rubble
		Ledger.close(l)
		local s = Ledger.snapshot(l, uid, bag(p), 62)
		assertEq(s.Processed, 65)
		assertEq(s.RubbleEarned, 64)
		assertEq(s.RubbleSold, 54)
		assertEq(s.SoldCash, 108)
		assertEq(s.BagCount, 19)
		assertEq(s.BagCapacity, 30)
		assertEq(s.BagValue, 38)
		assertEq(s.SpecimenValue, 62, "specimen value is reported separately")
		assertEq(p.Cash, 207 + 108, "specimen value is never cash")
		assertEq(9 + s.RubbleEarned - s.RubbleSold, s.BagCount, "9 + 64 - 54 = 19")
	end)

	test("ledger: building a snapshot never grants rubble or cash", function()
		local l, p = Ledger.new(), newProfile(19, 315)
		earn(l, p, 1, 0)
		Ledger.close(l)
		for _ = 1, 5 do
			Ledger.snapshot(l, 1, bag(p), 62)
		end
		assertEq(p.Rubble, 19)
		assertEq(p.Cash, 315)
	end)

	test("ledger: a sale after the hunt closed leaves the hunt counters alone but the bag fresh", function()
		local l, p = Ledger.new(), newProfile(0, 0)
		earn(l, p, 1, 10)
		Ledger.close(l)
		local before = Ledger.snapshot(l, 1, bag(p), nil)
		sell(l, p, 1) -- player sells in the results screen
		local after = Ledger.snapshot(l, 1, bag(p), nil)
		assertEq(before.RubbleSold, 0)
		assertEq(after.RubbleSold, 0)
		assertEq(after.RubbleEarned, 10)
		assertEq(after.BagCount, 0)
		assertEq(after.BagValue, 0)
	end)

	test("ledger: repeated sale taps and bad numbers count once", function()
		local l, p = Ledger.new(), newProfile(5, 0)
		sell(l, p, 1)
		sell(l, p, 1)
		sell(l, p, 1)
		Ledger.sold(l, 1, 0 / 0, 99)
		Ledger.sold(l, 1, -4, 99)
		Ledger.sold(l, 1, math.huge, 99)
		local s = Ledger.snapshot(l, 1, bag(p), nil)
		assertEq(s.RubbleSold, 5)
		assertEq(s.SoldCash, 10)
	end)

	test("ledger: players are independent and an untouched player reads zeros", function()
		local l = Ledger.new()
		Ledger.crushed(l, 1, true)
		Ledger.sold(l, 1, 1, 2)
		local s2 = Ledger.snapshot(l, 2, { Count = 3, Capacity = 30, Value = 6 }, nil)
		assertEq(s2.Processed, 0)
		assertEq(s2.RubbleSold, 0)
		assertEq(s2.BagCount, 3)
	end)
end
