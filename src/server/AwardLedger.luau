--!strict
-- Durable record of match wins. One entry per award key (MatchKey:RoundId):
--   { Winner, Specimen, State = "pending" | "applied", Time }
-- The winner decision and specimen are written here before the reveal. The grant to the
-- winner's profile is a separate write (two stores cannot be updated atomically), so:
--   * the profile records the award key with the item (idempotent grant), and
--   * if the winner is not on this server any more, the key goes into their pending list and
--     is applied on their next load.
-- If the ledger cannot be reached (Studio without API access), the in-memory grant and the
-- normal profile save still happen; only the cross-session recovery is missing.

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Profiles = require(script.Parent.Profiles)

local Ledger = {}

-- A pending key whose ledger entry is still missing after this long is dropped (Ledger.record retries for 10 minutes).
local MISSING_EXPIRY_SECONDS = 3 * 24 * 3600

local SUFFIX = if RunService:IsStudio() then "_Studio" else ""
local ledger: DataStore? = nil
local pending: DataStore? = nil
pcall(function()
	ledger = DataStoreService:GetDataStore(Config.Save.LedgerName .. SUFFIX)
	pending = DataStoreService:GetDataStore(Config.Save.PendingName .. SUFFIX)
end)

local function retry(fn: () -> ()): boolean
	for attempt = 1, 4 do
		local ok: boolean, err: any = pcall(fn)
		if ok then
			return true
		end
		warn("[Ledger]", err)
		task.wait(2 ^ attempt * 0.5)
	end
	return false
end

-- Writes the decision if no entry exists yet. Returns the stored (canonical) entry.
function Ledger.record(awardKey: string, winner: number, specimen): any
	local stored = { Winner = winner, Specimen = specimen, State = "pending", Time = os.time() }
	if not ledger then
		return stored
	end
	local ds = ledger :: DataStore
	local result = stored
	local function write()
		ds:UpdateAsync(awardKey, function(old)
			if old then
				result = old
				return nil
			end
			result = stored
			return stored
		end)
	end
	if not retry(write) then
		-- outage: keep trying in the background (every 30 s for 10 minutes) so the decision still
		-- becomes durable and a pending key written later can find its entry
		task.spawn(function()
			for _ = 1, 20 do
				task.wait(30)
				if pcall(write) then
					return
				end
			end
			warn("[Ledger] could not store the decision for", awardKey)
		end)
	end
	return result
end

-- Grants applied in memory whose own save failed, per player, until a later committed save carries them.
local unsaved: { [Player]: { { Key: string, At: number } } } = {}

-- markApplied writes still running; BindToClose waits for them (Profiles.onShutdown).
local inFlight = 0

function Ledger.markApplied(awardKey: string)
	if not ledger then
		return
	end
	local ds = ledger :: DataStore
	inFlight += 1
	task.spawn(function()
		pcall(retry, function()
			ds:UpdateAsync(awardKey, function(old)
				if not old then
					return nil
				end
				old.State = "applied"
				return old
			end)
		end)
		inFlight -= 1
	end)
end

Profiles.onShutdown(function()
	while inFlight > 0 do
		task.wait(0.2) -- Profiles bounds the whole shutdown wait
	end
end)

function Ledger.addPending(userId: number, awardKey: string): boolean
	if not pending then
		return false
	end
	local ds = pending :: DataStore
	return retry(function()
		ds:UpdateAsync("p_" .. userId, function(old)
			old = old or {}
			if not table.find(old, awardKey) then
				table.insert(old, awardKey)
			end
			return old
		end)
	end)
end

-- addPending with a slow background retry (every 30 s for 10 minutes) so a DataStore outage
-- right after a winner leaves does not silently drop the prize.
function Ledger.ensurePending(userId: number, awardKey: string)
	if Ledger.addPending(userId, awardKey) then
		return
	end
	task.spawn(function()
		for _ = 1, 20 do
			task.wait(30)
			if Ledger.addPending(userId, awardKey) then
				return
			end
		end
		warn("[Ledger] could not record pending award", awardKey, "for", userId, "- the ledger entry stays pending")
	end)
end

-- Grants a decided award to a player who is on this server. Holds the profile open while
-- saving so a leaving winner still gets it.
-- Returns (granted or saved, saved): only a saved grant may leave the pending list.
function Ledger.apply(player: Player, awardKey: string, specimen, kind: string): (boolean, boolean)
	Profiles.hold(player)
	local granted = Profiles.grantSpecimen(player, awardKey, specimen, kind)
	local saved = Profiles.saveNow(player)
	Profiles.unhold(player)
	if kind == "Tutorial" then
		-- practice rounds write no ledger entry, so a pending key could never resolve; an unsaved practice pet
		-- stays in memory and goes out with the next autosave or the leave save
		return granted or saved, saved
	end
	if saved then
		Ledger.markApplied(awardKey)
	else
		-- the grant lives only in memory: make sure the next join can still find the award
		Ledger.ensurePending(player.UserId, awardKey)
		if granted then
			-- the next committed save (autosave or leave) carries it: mark the entry applied then (Profiles.onSaved)
			local list = unsaved[player] or {}
			unsaved[player] = list
			table.insert(list, { Key = awardKey, At = os.clock() })
		end
	end
	return granted or saved, saved
end

-- A later save that started after an unsaved grant committed it: the ledger entry is applied now, so a rejoin never
-- has to resolve it again (and a sold pet whose key left RecentAwardIds is never granted twice).
Profiles.onSaved(function(player: Player, startedAt: number)
	local list = unsaved[player]
	if not list then
		return
	end
	local keep = {}
	for _, u in list do
		if startedAt >= u.At then
			Ledger.markApplied(u.Key)
		else
			table.insert(keep, u)
		end
	end
	if #keep > 0 then
		unsaved[player] = keep
	else
		unsaved[player] = nil
	end
end)
game:GetService("Players").PlayerRemoving:Connect(function(player: Player)
	-- the leave save runs first (the profile stays loaded until it lands), so drop the list once it is gone
	task.spawn(function()
		local t0 = os.clock()
		while Profiles.isLoaded(player) and os.clock() - t0 < 300 do
			task.wait(1)
		end
		unsaved[player] = nil
	end)
end)

-- On profile load: apply any awards decided while the player was away.
function Ledger.reconcile(player: Player)
	if not pending or not ledger or Profiles.isOffline(player) then
		return
	end
	local pds, lds = pending :: DataStore, ledger :: DataStore
	local keys: { any } = {}
	local okRead = retry(function()
		keys = pds:GetAsync("p_" .. player.UserId) or {}
	end)
	if not okRead or #keys == 0 then
		return
	end
	local done = {}
	local missing: { string } = {}
	for _, awardKey in keys do
		local entry
		local readOk = type(awardKey) == "string" and retry(function()
			entry = lds:GetAsync(awardKey)
		end)
		if type(awardKey) ~= "string" then
			table.insert(done, awardKey) -- junk in the list can never resolve
		elseif not readOk then
			continue -- read failed: try again on the next join
		elseif entry == nil then
			table.insert(missing, awardKey) -- no decision stored (yet): expires below
		elseif type(entry) ~= "table" or entry.Winner ~= player.UserId or not entry.Specimen then
			table.insert(done, awardKey) -- not this player's prize: it can never be granted here
		else
			if not player.Parent then
				return
			end
			if entry.State == "applied" then
				table.insert(done, awardKey) -- already in a committed save: never grant it twice
			else
				local kind = if entry.Specimen.Solo then "Solo" else "Multiplayer"
				local _, saved = Ledger.apply(player, awardKey, entry.Specimen, kind)
				if saved then
					table.insert(done, awardKey) -- a failed save keeps the key pending for the next join
				end
			end
		end
	end
	-- A pending key whose ledger entry never appeared (the decision write failed for its whole 10 minute retry,
	-- or an old practice round) would stay forever. Remember when each was first seen missing; after
	-- MISSING_EXPIRY_SECONDS it is dropped. Keys that resolved are forgotten here too.
	local missKey = "m_" .. player.UserId
	local now = os.time()
	retry(function()
		pds:UpdateAsync(missKey, function(old)
			local seen = if type(old) == "table" then old else {}
			local out = {}
			for _, k in missing do
				local first = tonumber(seen[k]) or now
				out[k] = first
				if now - first >= MISSING_EXPIRY_SECONDS then
					table.insert(done, k)
					out[k] = nil
				end
			end
			if next(out) == nil and next(seen) == nil then
				return nil -- nothing to remember, nothing stored: no write
			end
			return out
		end)
	end)
	if #done > 0 then
		retry(function()
			pds:UpdateAsync("p_" .. player.UserId, function(old)
				old = old or {}
				local keep = {}
				for _, k in old do
					if not table.find(done, k) then
						table.insert(keep, k)
					end
				end
				return keep
			end)
		end)
	end
end

return Ledger
