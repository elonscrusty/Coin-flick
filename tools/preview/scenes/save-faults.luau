-- save-faults: DataStore failure paths of the real server (Profiles, AwardLedger, MatchService),
-- driven with preview.failDataStores(reads, writes, opening). Prints PASS/FAIL lines; the scene
-- ends with "SAVE-FAULTS PASS" or "SAVE-FAULTS FAIL: ...". One case per run (a run boots one server):
--   --set case=load      a failing DataStore at join: kick with a message, nothing written
--   --set case=save      saves fail then recover: retries, data kept in memory, autosave catches up
--   --set case=award     a multiplayer winner leaves during RewardPending while the stores are down:
--                        the award is applied once, never twice on later joins
--   --set case=pending   ledger entry + pending list, winner offline: applied on the next join, once
--   --set case=release   teleport hand-off: release waits for an award hold, no late save re-takes
--                        the lock, a failed release is refused, re-acquire refuses a moved profile
--   --set case=all       (default) is not possible in one run: tools/run_regressions.sh runs each case
-- Mock DataStores (UpdateAsync fails with "Writes", GetAsync with "Reads"); nothing here is Roblox.
local C = lib("ctr")
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local R = preview.Mock.R
local CASE = preview.args.case or "load"
local fails = {}
local function check(name: string, ok: boolean, detail: string?)
	print(string.format("[%s] %s%s", if ok then "PASS" else "FAIL", name, if detail then (": " .. detail) else ""))
	if not ok then
		table.insert(fails, name)
	end
end
local function finish()
	print(if #fails == 0 then ("SAVE-FAULTS PASS (" .. CASE .. ")") else ("SAVE-FAULTS FAIL (" .. CASE .. "): " .. table.concat(fails, ", ")))
end
local function warnCount(sub: string): number
	local n = 0
	for _, w in ipairs(R.log.warnings) do
		if string.find(w.message, sub, 1, true) then
			n += w.count or 1
		end
	end
	return n
end
local function stored(userId: number)
	local ds = DataStoreService:GetDataStore("CTR_Profiles_v1")
	return ds:GetAsync("u_" .. userId)
end
local function storedAwards(userId: number): number
	local rec = stored(userId)
	local n = 0
	for _, g in ipairs(rec and rec.Data.InventoryGeodes or {}) do
		if g.MatchKey ~= "starter" then -- the free starter pet is not an award
			n += 1
		end
	end
	return n
end
-- Awarded pets in a profile (the free starter pet every player gets once is not an award).
local function awards(d): number
	local n = 0
	for _, g in ipairs(d and d.InventoryGeodes or {}) do
		if g.MatchKey ~= "starter" then
			n += 1
		end
	end
	return n
end
local ME = Players.LocalPlayer.UserId

----------------------------------------------------------------------------------------------
if CASE == "load" then
	-- (a) writes fail: the load transaction cannot take the lock
	local Profiles = C.server("Profiles")
	Profiles.setLoadAttempts(3)
	preview.failDataStores(false, true)
	local s = C.boot({})
	preview.advance(60)
	local kicks = warnCount("Player:Kick(")
	check("load failure: player kicked", kicks >= 1, kicks .. " kick(s)")
	check("load failure: kick message explains", warnCount("could not load your save safely") >= 1)
	check("load failure: no profile in memory", Profiles.get(s.me) == nil)
	preview.failDataStores(false, false)
	check("load failure: no default save written", stored(ME) == nil)
	check("load failure: warned in the log", warnCount("[Profiles] could not load") >= 1)
	finish()
	return
end

----------------------------------------------------------------------------------------------
local s = C.boot({
	others = { { "Ava", 2 } },
	profile = function(data)
		data.Cash = 100
		data.TutorialStep = 1
	end,
})
local Profiles = s.Profiles
local Ledger = C.server("AwardLedger")
local ava = s.others[1]

if CASE == "save" then
	check("loaded and saved once", stored(ME) ~= nil and stored(ME).Lock ~= nil, "lock held by this server")
	local oldCash = stored(ME).Data.Cash
	local data = Profiles.get(s.me)
	data.Cash = 777
	Profiles.changed(s.me)
	preview.failDataStores(false, true)
	local before = warnCount("[Profiles] save failed")
	local result = nil
	task.spawn(function()
		result = Profiles.saveNow(s.me)
	end)
	preview.advance(40) -- four attempts with 2, 4, 8, 16 s back-off
	check("save failure: retried", warnCount("[Profiles] save failed") - before >= 4, (warnCount("[Profiles] save failed") - before) .. " failed attempts")
	check("save failure: saveNow reports false", result == false)
	check("save failure: data kept in memory", Profiles.get(s.me) == data and data.Cash == 777)
	check("save failure: old value still in the store", stored(ME).Data.Cash == oldCash)
	check("save failure: lock not lost", stored(ME).Lock ~= nil and stored(ME).Lock.Session ~= nil)
	preview.failDataStores(false, false)
	-- the dirty profile is written by the next autosave without any new change
	preview.advance(120)
	check("recovery: autosave writes the kept data", stored(ME).Data.Cash == 777)
	-- a leave while the stores are down: release save retries, then lock stays but data is not wiped
	data.Cash = 888
	Profiles.changed(s.me)
	preview.failDataStores(false, true)
	local gone = false
	task.spawn(function()
		preview.removePlayer(ava)
		gone = true
	end)
	preview.advance(5)
	preview.failDataStores(false, false)
	check("other player leaving during an outage does not touch my profile", stored(ME).Data.Cash == 777 or stored(ME).Data.Cash == 888)
	finish()
	return
end

----------------------------------------------------------------------------------------------
if CASE == "pending" then
	local GeodeGen = C.shared("GeodeGen")
	local specimen = C.fakeSpecimens(1)[1]
	specimen.Id = "pending-geode-1"
	local awardKey = "match-x:1"
	-- the winner (Ava) is away: the ledger holds the decision, the pending list holds the key
	preview.removePlayer(ava)
	preview.advance(2)
	local entry = Ledger.record(awardKey, 2, specimen)
	check("ledger entry stored", entry.State == "pending" and entry.Winner == 2)
	check("pending key stored", Ledger.addPending(2, awardKey))
	local function join()
		local p = preview.addPlayer("Ava", 2)
		preview.playerJoined(p)
		preview.advance(15)
		return p
	end
	local p1 = join()
	local d = Profiles.get(p1)
	check("next join: profile loaded", d ~= nil)
	check("next join: award applied once", d ~= nil and awards(d) == 1 and Profiles.findGeode(d, "pending-geode-1") ~= nil, d and (awards(d) .. " awarded") or "no profile")
	check("next join: stats counted once", d ~= nil and d.Stats.SoloFinds + d.Stats.MultiplayerWins == 1)
	local ledgerStore = DataStoreService:GetDataStore("CTR_Ledger_v1")
	check("ledger marked applied", ledgerStore:GetAsync(awardKey).State == "applied")
	check("pending list cleared", #(DataStoreService:GetDataStore("CTR_Pending_v1"):GetAsync("p_2") or {}) == 0)
	-- leave and join again: nothing is granted a second time
	preview.removePlayer(p1)
	preview.advance(5)
	check("saved before leaving", storedAwards(2) == 1)
	-- even if the pending key were still there (cleanup failed), the profile's award ids stop a repeat
	Ledger.addPending(2, awardKey)
	local p2 = join()
	local d2 = Profiles.get(p2)
	check("second join: no duplicate", d2 ~= nil and awards(d2) == 1 and d2.Stats.SoloFinds + d2.Stats.MultiplayerWins == 1, d2 and (awards(d2) .. " awarded") or "no profile")
	finish()
	return
end

----------------------------------------------------------------------------------------------
if CASE == "award" then
	local w = C.watchMatch()
	for _, p in ipairs({ s.me, ava }) do
		local d = Profiles.get(p)
		d.TutorialStep = 1
		d.CapacityTier = 3
		Profiles.changed(p)
	end
	-- a two-person party hunt; Ava does all the cracking, so she finds the geode
	C.fireServer("PartyAction", "Create")
	preview.advance(0.3)
	local party = s.PartyService.of(ME)
	C.fireServer("PartyAction", "Invite", 2)
	preview.advance(0.3)
	preview.fireServerAs(ava, "PartyAction", "Accept", party and party.Id)
	preview.advance(0.3)
	preview.fireServerAs(ava, "PartyAction", "Ready", true)
	C.fireServer("PartyAction", "Ready", true)
	preview.advance(0.3)
	C.fireServer("PartyAction", "Start")
	for _ = 1, 30 do
		if w.last.Init then
			break
		end
		preview.advance(0.1)
	end
	C.waitPhase(w, "Searching", 8)
	preview.failDataStores(false, true) -- the stores go down before the geode is found
	C.crackUntilFound(w, { ava }, 400) -- 150 eggs, 3-egg basket
	check("geode found", w.last.Found ~= nil and w.last.Found.Winner == 2, w.last.Found and ("winner " .. tostring(w.last.Found.Winner)) or "no Found")
	preview.advance(0.5)
	check("RewardPending: save still pending", awards(stored(2).Data) == 0)
	-- the winner leaves right now, during RewardPending
	task.spawn(preview.removePlayer, ava)
	preview.advance(2)
	preview.failDataStores(false, false) -- the stores come back inside the hold window
	preview.advance(90)
	local rec = stored(2)
	check("winner left: award applied once", rec ~= nil and awards(rec.Data) == 1, rec and (awards(rec.Data) .. " awarded") or "no profile")
	check("winner left: lock released", rec ~= nil and rec.Lock == nil)
	check("winner left: win counted once", rec ~= nil and rec.Data.Stats.MultiplayerWins == 1)
	local awardKey = rec and rec.Data.RecentAwardIds[1]
	local entry = awardKey and DataStoreService:GetDataStore("CTR_Ledger_v1"):GetAsync(awardKey)
	check("ledger entry applied", entry ~= nil and entry.State == "applied", entry and entry.State or "no entry")
	for n = 1, 2 do
		local p = preview.addPlayer("Ava", 2)
		preview.playerJoined(p)
		preview.advance(15)
		local d = Profiles.get(p)
		check("join " .. n .. ": still exactly one specimen", d ~= nil and awards(d) == 1 and d.Stats.MultiplayerWins == 1, d and (awards(d) .. " awarded") or "no profile")
		preview.removePlayer(p)
		preview.advance(5)
	end
	check("no repeat grant after rejoins", storedAwards(2) == 1)
	finish()
	return
end

----------------------------------------------------------------------------------------------
if CASE == "release" then
	local data = Profiles.get(ava)
	data.Cash = 50
	Profiles.changed(ava)
	preview.advance(1)
	-- (1) an award hold delays the hand-off (bounded), and the award saved before the lock is released
	Profiles.hold(ava)
	data.Cash = 60
	local order = {}
	local released = nil
	task.spawn(function()
		released = Profiles.releaseForTeleport(ava)
		table.insert(order, "released")
	end)
	preview.advance(2)
	check("release waits while an award is held", released == nil)
	table.insert(order, "award saved")
	Profiles.saveNow(ava)
	Profiles.unhold(ava)
	preview.advance(2)
	check("release then succeeds", released == true and Profiles.isReleased(ava), table.concat(order, " -> "))
	check("hand-off wrote the held award", stored(2).Data.Cash == 60 and stored(2).Lock == nil)
	-- (2) a late save must not take the lock back
	data.Cash = 70
	Profiles.changed(ava)
	check("saveNow after release returns false", Profiles.saveNow(ava) == false)
	preview.advance(150) -- an autosave interval
	check("no late save re-took the lock", stored(2).Lock == nil and stored(2).Data.Cash == 60)
	-- (3) the destination server wrote a newer copy: re-acquire is refused
	local ds = DataStoreService:GetDataStore("CTR_Profiles_v1")
	ds:UpdateAsync("u_2", function(old)
		old.Rev = (old.Rev or 0) + 1
		old.Lock = { Job = "other", Session = "other", Time = os.time() }
		return old
	end)
	check("re-acquire refused when another server holds it", Profiles.reacquire(ava) == false)
	-- (4) a failed release is refused and the profile stays usable (caller must not teleport)
	local bob = preview.addPlayer("Bob", 3)
	preview.playerJoined(bob)
	preview.advance(10)
	check("second player loaded", Profiles.get(bob) ~= nil)
	preview.failDataStores(false, true)
	local ok, msg = nil, nil
	task.spawn(function()
		ok, msg = Profiles.releaseForTeleport(bob)
	end)
	preview.advance(60)
	check("failed release is refused", ok == false, tostring(msg))
	check("failed release leaves the profile live", Profiles.isReleased(bob) == false and Profiles.get(bob) ~= nil)
	preview.failDataStores(false, false)
	local ok2 = Profiles.releaseForTeleport(bob)
	check("release succeeds once the store is back", ok2 == true and stored(3).Lock == nil)
	-- (5) re-acquire after a clean release (teleport failed): lock back, writes allowed again
	check("re-acquire after clean release", Profiles.reacquire(bob) == true and not Profiles.isReleased(bob))
	check("lock held again", stored(3).Lock ~= nil)
	check("saves work again", Profiles.saveNow(bob) == true)
	finish()
	return
end

print("unknown case " .. CASE)
table.insert(fails, "unknown case")
finish()
