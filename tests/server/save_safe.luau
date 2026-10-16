-- Save safety (run by tests/test_save_safe.luau): pets and coins are never lost on leave / rejoin, a failed or
-- throttled DataStore, session lock contention, schema changes or a server shutdown. Drives the REAL Profiles (and
-- PetService / AwardLedger through the boot) on the offline mock, whose in-memory DataStore can fail writes, run
-- out of request budget and run game:BindToClose callbacks (preview.failNextWrites / setRequestBudget / closeServer).
local C = lib("ctr")

local function case(name: string, fn)
	local ok, err = pcall(fn)
	if ok then
		print("CASE " .. name .. " PASS")
	else
		print("[FAIL] CASE " .. name .. ": " .. tostring(err))
	end
	preview.failDataStores(false, false)
	preview.setRequestBudget(100)
end
local function eq(a, b, msg)
	if a ~= b then
		error((msg or "mismatch") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

local Config = C.shared("Config")
local DataStoreService = game:GetService("DataStoreService")
local store = DataStoreService:GetDataStore(Config.Save.StoreName)
local function stored(uid: number): any
	return store:GetAsync("u_" .. uid)
end
-- A save a "second server" holds right now (or held long ago when `age` is past the lock time).
local function seed(uid: number, data: any, lock: any?, rev: number?)
	store:SetAsync("u_" .. uid, { Data = data, Lock = lock, Rev = rev or 1 })
end
seed(70, { Cash = 777 }, { Job = "other-server", Session = "S-OTHER", Time = os.time() }, 3)
seed(71, { Cash = 555 }, { Job = "crashed-server", Session = "S-OLD", Time = os.time() - Config.Save.LockSeconds - 60 }, 4)
seed(72, { Cash = 10, Schema = Config.Save.SchemaVersion + 4, FutureThing = { Kept = true } }, nil, 2)

local s = C.boot({
	others = { { "Ava", 2 }, { "Ben", 3 }, { "Cal", 4 } },
	profile = function(data)
		data.TutorialStep = 1
		data.Onboard.Skipped = true
	end,
})
local me, Profiles = s.me, s.Profiles
local function step(dt: number?)
	preview.advance(dt or 0.25)
end
local function until_(fn, limit: number?): boolean
	local t = 0
	while not fn() and t < (limit or 60) do
		step(0.25)
		t += 0.25
	end
	return fn() and true or false
end
local serial = 0
local function pet(tag: string): any
	serial += 1
	local g = C.fakeSpecimens(1)[1]
	g.Id = tag .. "-" .. serial
	return g
end
local function join(name: string, uid: number): Player
	local p = preview.addPlayer(name, uid)
	C.makeCharacter(p, CFrame.new(0, 0, 8 + uid))
	preview.playerJoined(p)
	return p
end
local function hasPet(data: any, id: string): boolean
	for _, g in (data and data.InventoryGeodes) or {} do
		if g.Id == id then
			return true
		end
	end
	return false
end
for _, p in s.others do
	assert(until_(function()
		return Profiles.isLoaded(p)
	end, 20), "loaded " .. p.Name)
end
local ava, ben, cal = s.others[1], s.others[2], s.others[3]

case("leave right after hatching a pet: the pet and its coins are in the save, the lock is released", function()
	local g = pet("hatch")
	local d = Profiles.get(ava)
	d.Cash += 40
	assert(Profiles.grantSpecimen(ava, "gift:" .. g.Id, g, "Gift"), "granted")
	local cash = d.Cash
	preview.removePlayer(ava)
	step(1)
	local rec = stored(ava.UserId)
	assert(rec and hasPet(rec.Data, g.Id), "pet saved")
	eq(rec.Data.Cash, cash, "coins saved")
	eq(rec.Lock, nil, "lock released")
	-- rejoin on this server: the same pet and coins come back
	local back = join("Ava", ava.UserId)
	assert(until_(function()
		return Profiles.isLoaded(back)
	end, 20), "rejoined")
	assert(hasPet(Profiles.get(back), g.Id), "pet after rejoin")
	eq(Profiles.get(back).Cash, cash)
	ava = back
end)

case("a transient write failure is retried: saveNow lands on a later attempt", function()
	local d = Profiles.get(me)
	d.Cash += 11
	local before = preview.dataStoreWrites()
	preview.failNextWrites(2)
	local ok: boolean? = nil
	task.spawn(function()
		ok = Profiles.saveNow(me)
	end)
	assert(until_(function()
		return ok ~= nil
	end, 30), "save returned")
	eq(ok, true, "saved")
	eq(preview.dataStoreWrites() - before, 3, "two failed tries, then one that landed")
	eq(stored(me.UserId).Data.Cash, d.Cash)
end)

case("a throttled DataStore (no request budget) waits, then still saves", function()
	local d = Profiles.get(me)
	d.Cash += 5
	preview.setRequestBudget(0)
	local ok: boolean? = nil
	task.spawn(function()
		ok = Profiles.saveNow(me)
	end)
	step(1)
	eq(ok, nil, "still waiting for budget")
	assert(until_(function()
		return ok ~= nil
	end, 20), "save returned")
	eq(ok, true)
	eq(stored(me.UserId).Data.Cash, d.Cash)
end)

case("leave while saves fail: the pet is kept and the release save retried until it lands", function()
	local g = pet("outage")
	assert(Profiles.grantSpecimen(ben, "gift:" .. g.Id, g, "Gift"), "granted")
	Profiles.get(ben).Cash += 300
	local cash = Profiles.get(ben).Cash
	preview.failDataStores(false, true)
	preview.removePlayer(ben)
	step(20) -- the leave save's own tries all fail
	local rec = stored(ben.UserId)
	assert(not hasPet(rec.Data, g.Id), "nothing written during the outage")
	assert(rec.Lock ~= nil, "our lock still guards the stored copy (no other server loads an older one)")
	preview.failDataStores(false, false)
	assert(until_(function()
		local r = stored(ben.UserId)
		return r.Lock == nil and hasPet(r.Data, g.Id)
	end, 45), "the retried release save carried the pet")
	eq(stored(ben.UserId).Data.Cash, cash, "coins too")
end)

case("rejoin the same server during an outage: the newest copy (with the new pet) comes back", function()
	local g = pet("rejoin")
	assert(Profiles.grantSpecimen(cal, "gift:" .. g.Id, g, "Gift"), "granted")
	preview.failDataStores(false, true)
	preview.removePlayer(cal)
	step(20)
	local back = join("Cal", cal.UserId)
	assert(until_(function()
		return Profiles.isLoaded(back)
	end, 40), "rejoined without a fresh load")
	eq(preview.kickedWith(back), nil, "not kicked")
	assert(hasPet(Profiles.get(back), g.Id), "pet from the parked copy")
	preview.failDataStores(false, false)
	assert(Profiles.saveNow(back), "saves again once the DataStore is back")
	assert(hasPet(stored(back.UserId).Data, g.Id), "saved")
	cal = back
end)

case("a grant during a slow leave save is refused (kept pending), never silently dropped", function()
	local dee = join("Dee", 9)
	assert(until_(function()
		return Profiles.isLoaded(dee)
	end, 20), "loaded")
	preview.failNextWrites(1)
	preview.removePlayer(dee) -- first release try fails, the retry waits
	local g = pet("late")
	eq(Profiles.grantSpecimen(dee, "gift:" .. g.Id, g, "Gift"), false, "refused: the release save is already under way")
	step(6)
	local rec = stored(9)
	eq(rec.Lock, nil, "released")
	assert(not hasPet(rec.Data, g.Id), "no phantom pet")
end)

case("second server holds the lock: the join is refused with a kind message, the stored save untouched", function()
	Profiles.setLoadAttempts(2)
	local p = join("Held", 70)
	assert(until_(function()
		return preview.kickedWith(p) ~= nil
	end, 30), "kicked")
	assert(string.find(preview.kickedWith(p) :: string, "another server", 1, true), "explains: " .. tostring(preview.kickedWith(p)))
	eq(Profiles.isLoaded(p), false)
	local rec = stored(70)
	eq(rec.Lock.Session, "S-OTHER", "the other server's lock kept")
	eq(rec.Data.Cash, 777)
	preview.removePlayer(p)
	Profiles.setLoadAttempts(Config.Save.LoadAttempts)
end)

case("an abandoned lock (crashed server) is taken over with the data kept", function()
	local p = join("Crash", 71)
	assert(until_(function()
		return Profiles.isLoaded(p)
	end, 20), "loaded")
	eq(Profiles.get(p).Cash, 555)
	local rec = stored(71)
	assert(rec.Lock and rec.Lock.Session ~= "S-OLD", "our lock now")
	eq(rec.Rev, 5, "revision moved on")
	preview.removePlayer(p)
	step(1)
end)

case("lock taken by another server mid-session: this server stops saving and never writes over it", function()
	local p = join("Moved", 73)
	assert(until_(function()
		return Profiles.isLoaded(p)
	end, 20), "loaded")
	local rec = stored(73)
	seed(73, { Cash = 999 }, { Job = "other-server", Session = "S-NEW", Time = os.time() }, rec.Rev + 1)
	Profiles.get(p).Cash = 1
	eq(Profiles.saveNow(p), false, "refused")
	eq(Profiles.lockLost(p), true)
	eq(stored(73).Data.Cash, 999, "the newer copy is untouched")
	preview.removePlayer(p)
	step(1)
	eq(stored(73).Data.Cash, 999, "the leave save does not write either")
end)

case("a save from a newer build keeps its schema and unknown fields through a load and save here", function()
	local p = join("Future", 72)
	assert(until_(function()
		return Profiles.isLoaded(p)
	end, 20), "loaded")
	assert(Profiles.saveNow(p), "saved")
	local rec = stored(72)
	eq(rec.Data.Schema, Config.Save.SchemaVersion + 4, "schema marker never lowered")
	eq(type(rec.Data.FutureThing), "table", "unknown field kept")
	eq(rec.Data.Cash, 10)
	preview.removePlayer(p)
	step(1)
end)

case("shutdown with several players: every profile and a parked leaver are saved and released", function()
	local p1 = join("Gus", 81)
	local p2 = join("Hal", 82)
	assert(until_(function()
		return Profiles.isLoaded(p1) and Profiles.isLoaded(p2)
	end, 20), "loaded")
	local pets = {}
	for _, p in { me, ava, cal, p1, p2 } do
		local g = pet("bye")
		assert(Profiles.grantSpecimen(p, "gift:" .. g.Id, g, "Gift"), "granted " .. p.Name)
		Profiles.get(p).Cash += 7
		pets[p.UserId] = { Id = g.Id, Cash = Profiles.get(p).Cash }
	end
	-- one more who left during an outage: parked, retried only every 30 s
	local p3 = join("Ivy", 83)
	assert(until_(function()
		return Profiles.isLoaded(p3)
	end, 20), "loaded")
	local g3 = pet("parked")
	assert(Profiles.grantSpecimen(p3, "gift:" .. g3.Id, g3, "Gift"))
	preview.failDataStores(false, true)
	preview.removePlayer(p3)
	step(16)
	preview.failDataStores(false, false)
	local done = preview.closeServer()
	assert(until_(done, 28), "BindToClose finished inside the shutdown budget")
	for uid, want in pets do
		local rec = stored(uid)
		assert(hasPet(rec.Data, want.Id), "pet saved for " .. uid)
		eq(rec.Data.Cash, want.Cash, "coins saved for " .. uid)
		eq(rec.Lock, nil, "released " .. uid)
	end
	local r3 = stored(83)
	assert(hasPet(r3.Data, g3.Id) and r3.Lock == nil, "the parked leaver was saved by the shutdown pass")
end)

print("SAVE_SAFE DONE")
