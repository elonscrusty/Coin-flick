--!strict
-- Per-hunt rubble accounting (pure, tested in tests/test_hunt_ledger.luau).
--
-- The profile owns the persistent rubble bag and the cash. This ledger only COUNTS what happened during
-- one hunt so the results screen can label each figure honestly:
--   Processed     rocks the player finished crushing (the geode rock counts)
--   RubbleEarned  ordinary rubble granted to the bag by those rocks
--   RubbleSold    rubble sold at the hopper while the hunt was running (may include carried-over material)
--   SoldCash      cash those sales paid
-- Bag count, capacity and bag value come from the profile at snapshot time. Nothing here ever grants
-- rubble or cash: it is read-only bookkeeping, so building a results screen cannot change any balance.

export type Row = { Processed: number, RubbleEarned: number, RubbleSold: number, SoldCash: number }
export type Ledger = { Rows: { [number]: Row }, Closed: boolean }
export type Snapshot = {
	Processed: number,
	RubbleEarned: number,
	RubbleSold: number,
	SoldCash: number,
	BagCount: number,
	BagCapacity: number,
	BagValue: number,
	SpecimenValue: number?,
}

local HuntLedger = {}

function HuntLedger.new(): Ledger
	return { Rows = {}, Closed = false }
end

local function row(l: Ledger, uid: number): Row
	local r = l.Rows[uid]
	if not r then
		r = { Processed = 0, RubbleEarned = 0, RubbleSold = 0, SoldCash = 0 }
		l.Rows[uid] = r
	end
	return r
end

local function whole(n: any): number
	if type(n) ~= "number" or n ~= n or n < 0 or n == math.huge then
		return 0
	end
	return math.floor(n)
end

-- A rock finished. `ordinary` = it paid one rubble into the bag (false for the geode rock).
function HuntLedger.crushed(l: Ledger, uid: number, ordinary: boolean)
	if l.Closed then
		return
	end
	local r = row(l, uid)
	r.Processed += 1
	if ordinary then
		r.RubbleEarned += 1
	end
end

-- A hopper sale the server already applied (count and cash are what it really removed and paid).
function HuntLedger.sold(l: Ledger, uid: number, count: number, cash: number)
	if l.Closed then
		return
	end
	local c = whole(count)
	if c == 0 then
		return
	end
	local r = row(l, uid)
	r.RubbleSold += c
	r.SoldCash += whole(cash)
end

-- Freeze the hunt counters (results are being built). Later sales no longer change them.
function HuntLedger.close(l: Ledger)
	l.Closed = true
end

-- One member's figures. `bag` comes from the profile right now (count, capacity, value of the bag).
function HuntLedger.snapshot(l: Ledger, uid: number, bag: { Count: number, Capacity: number, Value: number }, specimenValue: number?): Snapshot
	local r = row(l, uid)
	return {
		Processed = r.Processed,
		RubbleEarned = r.RubbleEarned,
		RubbleSold = r.RubbleSold,
		SoldCash = r.SoldCash,
		BagCount = whole(bag.Count),
		BagCapacity = whole(bag.Capacity),
		BagValue = whole(bag.Value),
		SpecimenValue = specimenValue,
	}
end

return HuntLedger
