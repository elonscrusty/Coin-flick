--!strict
-- Global leaderboards on OrderedDataStores (shared/Boards.luau defines the four boards):
-- Multiplayer Wins, Biggest Geode (value), Collection Count and Solo Finds (kept apart on purpose).
--
-- Writes: noteChange(player) is called whenever a profile changes; it only records the new
-- numbers. A flush loop writes a value when it grew, at most once per board per player per
-- Config.Leaderboards.WriteMinSeconds, and only while the request budget leaves MinBudget in
-- reserve. UpdateAsync keeps the larger of the stored and the new value, so a rank is never
-- lowered, deleted or reset. Everything is pcall'd; a failed write is retried on the next flush.
--
-- Reads: the top Config.Leaderboards.Top rows of each board are re-read every RefreshSeconds into a
-- cache (status "loading" until the first read, "ok", "error" keeping the last good rows (production
-- retries on the next refresh), "unavailable" in a Studio test whose saves are off or whose DataStores
-- cannot be reached: the boards then show one calm "Records unavailable in this Studio test" note and
-- stop reading for the rest of that Studio session; no rows are invented and nothing is written). Names come from players in this server (display name), else
-- Players:GetNameFromUserIdAsync (cached; a failure shows "Player <id>" and is retried later).
-- Studio uses its own stores ("_Studio" suffix), like Profiles.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Boards = require(Shared.Boards)
local PlaceRole = require(Shared.PlaceRole)
local Profiles = require(script.Parent.Profiles)

local Leaderboards = {}

local L = Config.Leaderboards
local SUFFIX = if RunService:IsStudio() then "_Studio" else ""

export type Row = { Rank: number, UserId: number, Name: string, Value: number, Text: string }
export type State = { Status: string, Rows: { Row }, Updated: number }

local IS_STUDIO = RunService:IsStudio()
local available = true -- false once DataStores proved unreachable in Studio (saves off / no API access)
local stores: { [string]: OrderedDataStore } = {}
local pending: { [number]: { [string]: number } } = {} -- userId -> board -> value to write
local written: { [number]: { [string]: number } } = {} -- userId -> board -> last value written
local lastWrite: { [number]: { [string]: number } } = {} -- userId -> board -> os.clock()
local cache: { [string]: State } = {}
local names: { [number]: string } = {}
local nameFailed: { [number]: number } = {}
local listeners: { (string) -> () } = {}
local reading = false

for _, id in Boards.Order do
	cache[id] = { Status = "loading", Rows = {}, Updated = 0 }
end

local function storeFor(board: string): OrderedDataStore?
	local s = stores[board]
	if s then
		return s
	end
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(L.StorePrefix .. board .. SUFFIX)
	end)
	if ok and result then
		stores[board] = result
		return result
	end
	return nil
end

local function budget(kind: Enum.DataStoreRequestType): number
	local ok, n = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(kind)
	end)
	return if ok and type(n) == "number" then n else 0
end

local function unreachable(err: string): boolean
	return RunService:IsStudio() and (string.find(err, "403") ~= nil or string.find(err, "API") ~= nil or string.find(err, "Studio") ~= nil)
end

-- Writes ---------------------------------------------------------------------------------

-- Records the player's current numbers (cheap; called on every profile change).
function Leaderboards.noteChange(player: Player)
	local data = Profiles.get(player)
	if not data or Profiles.isOffline(player) then
		return -- session-only profiles are never ranked
	end
	local vals = Boards.values(data)
	local uid = player.UserId
	for id, v in vals do
		local w = written[uid]
		if v > 0 and v > ((w and w[id]) or 0) then
			local p = pending[uid]
			if not p then
				p = {}
				pending[uid] = p
			end
			p[id] = v
		end
	end
end

local function writeOne(uid: number, board: string, value: number): boolean
	local store = storeFor(board)
	if not store then
		return false
	end
	local ok, err = pcall(function()
		store:UpdateAsync(tostring(uid), function(old: unknown): any -- nil keeps the stored value (the API type has no nil return)
			if type(old) == "number" and old >= value then
				return nil -- keep the stored (higher or equal) value
			end
			return value
		end)
	end)
	if not ok then
		if unreachable(tostring(err)) then
			available = false
		end
		return false
	end
	return true
end

-- One pass over the pending writes. force = ignore the per-board throttle (player leaving).
local function flush(force: boolean, only: number?)
	if not available then
		return
	end
	-- writes yield and noteChange adds entries meanwhile: walk snapshots, never the live tables
	local uids: { number } = {}
	for uid in pending do
		if not only or uid == only then
			table.insert(uids, uid)
		end
	end
	for _, uid in uids do
		local boardsMap = pending[uid]
		if not boardsMap then
			continue
		end
		for board, value in table.clone(boardsMap) do
			local w = written[uid]
			local lw = lastWrite[uid]
			local due = if force then value > ((w and w[board]) or 0) else Boards.writeDue(w and w[board], value, lw and lw[board], os.clock(), L.WriteMinSeconds)
			if not due then
				if value <= ((w and w[board]) or 0) and boardsMap[board] == value then
					boardsMap[board] = nil
				end
				continue
			end
			if budget(Enum.DataStoreRequestType.UpdateAsync) < L.MinBudget then
				return -- try again on the next flush
			end
			if writeOne(uid, board, value) then
				written[uid] = written[uid] or {}
				written[uid][board] = value
				lastWrite[uid] = lastWrite[uid] or {}
				lastWrite[uid][board] = os.clock()
				if boardsMap[board] == value then
					boardsMap[board] = nil
				end
			elseif not available then
				return
			end
		end
		if next(boardsMap) == nil and pending[uid] == boardsMap then
			pending[uid] = nil
		end
	end
end

-- Reads -----------------------------------------------------------------------------------

local function nameOf(uid: number): string
	local p = Players:GetPlayerByUserId(uid)
	if p then
		names[uid] = p.DisplayName
		return p.DisplayName
	end
	local n = names[uid]
	if n then
		return n
	end
	local failedAt = nameFailed[uid]
	if failedAt and os.clock() - failedAt < L.NameFailRetrySeconds then
		return "Player " .. uid
	end
	local ok, result = pcall(function()
		return Players:GetNameFromUserIdAsync(uid)
	end)
	if ok and type(result) == "string" and result ~= "" then
		names[uid] = result
		nameFailed[uid] = nil
		return result
	end
	nameFailed[uid] = os.clock()
	return "Player " .. uid
end

local function toRows(board: string, ranked: { Boards.Row }): { Row }
	local out: { Row } = {}
	for _, r in ranked do
		table.insert(out, { Rank = r.Rank, UserId = r.UserId, Name = nameOf(r.UserId), Value = r.Value, Text = Boards.format(board, r.Value) })
	end
	return out
end

local function fire(board: string)
	for _, fn in listeners do
		task.spawn(fn, board)
	end
end

-- A Studio test with saves off (any profile in this server is session-only): global records cannot be read
-- or written here, so the boards say so once instead of looking like a failing retry.
local function studioSavesOff(): boolean
	if not IS_STUDIO then
		return false
	end
	for _, p in Players:GetPlayers() do
		if Profiles.isOffline(p) then
			return true
		end
	end
	return false
end

-- Marks the board "unavailable" (Studio only) and tells the listeners once.
local function setUnavailable(c: State, board: string)
	available = false
	local changed = c.Status ~= "unavailable" or #c.Rows > 0
	c.Status = "unavailable"
	c.Rows = {}
	c.Updated = os.clock()
	if changed then
		fire(board)
	end
end

local function refreshBoard(board: string)
	local c = cache[board]
	if not available or studioSavesOff() then
		setUnavailable(c, board)
		return
	end
	local store = storeFor(board)
	if not store then
		if IS_STUDIO then
			setUnavailable(c, board) -- e.g. an unpublished place: DataStores cannot be opened in this test
			return
		end
		c.Status = "error"
		fire(board)
		return
	end
	if budget(Enum.DataStoreRequestType.GetSortedAsync) < 1 then
		return -- keep what we have; the next refresh tries again
	end
	local raw: { any } = {}
	local ok, err = pcall(function()
		local pages = store:GetSortedAsync(false, L.Top)
		for _, entry in pages:GetCurrentPage() do
			table.insert(raw, { key = entry.key, value = entry.value })
		end
	end)
	if ok then
		c.Rows = toRows(board, Boards.rank(raw, L.Top))
		c.Status = "ok"
		c.Updated = os.clock()
	elseif IS_STUDIO then -- any failed read in a Studio test: records are not available here (never retried in a loop)
		setUnavailable(c, board)
		return
	else
		c.Status = "error" -- the last good rows stay
		warn("[Leaderboards] read failed for", board, err)
	end
	fire(board)
end

function Leaderboards.refreshAll()
	if reading then
		return
	end
	reading = true
	for _, id in Boards.Order do
		local ok: boolean, err: any = pcall(refreshBoard, id)
		if not ok then
			warn("[Leaderboards] refresh failed for", id, err)
		end
	end
	reading = false
end

-- Latest cached state of a board (a copy-safe read-only table).
function Leaderboards.get(board: string): State
	return cache[board] or { Status = "error", Rows = {}, Updated = 0 }
end

function Leaderboards.onUpdated(fn: (string) -> ())
	table.insert(listeners, fn)
end

function Leaderboards.start()
	Profiles.onChanged(Leaderboards.noteChange)
	Players.PlayerRemoving:Connect(function(player)
		-- best-effort final write for what the player earned this visit
		Leaderboards.noteChange(player)
		task.spawn(flush, true, player.UserId)
		task.delay(L.FlushSeconds * 4, function()
			-- forget per-player bookkeeping once the last write had its chance
			if Players:GetPlayerByUserId(player.UserId) == nil then
				pending[player.UserId] = nil
				written[player.UserId] = nil
				lastWrite[player.UserId] = nil
			end
		end)
	end)
	-- Server shutdown: write what everyone still here earned; BindToClose (Profiles) waits for it within its budget.
	Profiles.onShutdown(function()
		for _, p in Players:GetPlayers() do
			Leaderboards.noteChange(p)
		end
		flush(true)
	end)
	-- the Match place has no boards: it only records changes and flushes writes
	local isMatch = PlaceRole.resolve(Config.Places.Mode, game.PlaceId, Config.Places.LobbyPlaceId, Config.Places.MatchPlaceId) == "Match"
	if not isMatch then
		task.delay(1, function()
			pcall(Leaderboards.refreshAll)
		end)
	end
	task.spawn(function()
		local sinceRead = 0
		while true do
			task.wait(L.FlushSeconds)
			pcall(flush, false)
			sinceRead += L.FlushSeconds
			if sinceRead >= L.RefreshSeconds and not isMatch then
				sinceRead = 0
				pcall(Leaderboards.refreshAll)
			end
		end
	end)
end

return Leaderboards
