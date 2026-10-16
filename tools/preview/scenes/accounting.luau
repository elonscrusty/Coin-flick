-- accounting: the owner's V4 section B recording replayed through the REAL server. A 30-rubble bag that
-- starts with 9 rubble is filled by crushing, emptied at the hopper twice (the real Economy.sellRubble), and
-- the hunt ends on the geode. The one results snapshot must say exactly what happened, the profile must agree,
-- and building results must never change the bag or the cash.
-- Prints "ACCOUNTING PASS" / "ACCOUNTING FAIL: ..." (run by tools/run_regressions.sh).
local C = lib("ctr")
local START_RUBBLE, START_CASH = 9, 207
local s = C.boot({
	profile = function(data)
		data.Cash = START_CASH
		data.TutorialStep = 1
		data.CapacityTier = 1 -- 30 rubble
		data.RubbleByTier = { Gravel = START_RUBBLE }
		data.Onboard.Skipped = true
	end,
})
local Economy = C.server("EconomyService")
local Profiles = s.Profiles
local w = C.watchMatch()
C.startSolo(w)
C.waitPhase(w, "Searching", 6)
local sales = 0
local sold, soldCash = 0, 0
local function bag(): number
	local d = Profiles.get(s.me)
	return d and Profiles.rubbleTotal(d) or 0
end
local found = C.crackUntilFound(w, { s.me }, 900, {
	onStep = function()
		local n = bag()
		local want = if sales == 0 then 15 else 25
		if n >= want then -- Find The Pet: 150 eggs need more than two sales with the free 30-shell bag
			local d = Profiles.get(s.me)
			local cash0 = d.Cash
			Economy.sellRubble(s.me)
			sales += 1
			sold += n
			soldCash += d.Cash - cash0
		end
	end,
})
preview.advance(8) -- reveal, then the Results message
local fails = {}
local function check(name: string, ok: boolean, detail: string?)
	if not ok then
		table.insert(fails, name .. (if detail then " (" .. detail .. ")" else ""))
	end
end
check("geode found", found == true)
check("at least two sales happened", sales >= 2, "sales " .. sales)
local res = w.last.Results
check("results arrived", res ~= nil)
local mine
for _, m in ipairs(res and res.Members or {}) do
	if m.UserId == s.me.UserId then
		mine = m
	end
end
check("own results row", mine ~= nil)
if mine then
	local d = Profiles.get(s.me)
	local rate = s.Config.Tiers.Gravel.CashPerRubble
	preview.log(string.format("snapshot: processed %d earned %d sold %d (+$%d) bag %d/%d value $%d specimen $%s", mine.Processed, mine.RubbleEarned, mine.RubbleSold, mine.SoldCash, mine.BagCount, mine.BagCapacity, mine.BagValue, tostring(mine.SpecimenValue)))
	check("processed = earned + the geode rock", mine.Processed == mine.RubbleEarned + 1, mine.Processed .. " vs " .. mine.RubbleEarned)
	check("sold matches the sales made", mine.RubbleSold == sold, mine.RubbleSold .. " vs " .. sold)
	check("sold cash matches the sales", mine.SoldCash == soldCash, mine.SoldCash .. " vs " .. soldCash)
	check("start + earned - sold = bag", START_RUBBLE + mine.RubbleEarned - mine.RubbleSold == mine.BagCount, (START_RUBBLE + mine.RubbleEarned - mine.RubbleSold) .. " vs " .. mine.BagCount)
	check("bag count is the profile", mine.BagCount == bag(), mine.BagCount .. " vs " .. bag())
	check("capacity", mine.BagCapacity == 30)
	-- the found pet is auto-equipped and may carry a coin boost, so the value can include it
		local boosted = math.floor(mine.BagCount * rate * (1 + Profiles.petCoinBoost(d)))
		check("bag value = count x rate", mine.BagValue == mine.BagCount * rate or mine.BagValue == boosted, mine.BagValue .. " vs " .. boosted)
	check("cash = start + sales", d.Cash == START_CASH + soldCash, d.Cash .. " vs " .. (START_CASH + soldCash))
	check("specimen value reported separately", type(mine.SpecimenValue) == "number" and mine.SpecimenValue > 0)
	check("specimen value is not cash", d.Cash == START_CASH + soldCash)
	-- a sale after the snapshot only refreshes the bag fields
	local before = { Cash = d.Cash, Bag = bag() }
		local lateGain = math.floor(before.Bag * rate * (1 + Profiles.petCoinBoost(d)))
	Economy.sellRubble(s.me)
	preview.advance(1)
	check("late sale: hunt counters frozen", res.Members and mine.RubbleSold == sold)
	check("late sale: cash gained once", d.Cash == before.Cash + lateGain, d.Cash .. " vs " .. (before.Cash + lateGain))
	check("late sale: bag empty", bag() == 0)
end
print(if #fails == 0 then "ACCOUNTING PASS" else ("ACCOUNTING FAIL: " .. table.concat(fails, ", ")))
