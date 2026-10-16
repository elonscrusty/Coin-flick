--!strict
-- Session-locked saving. Only ONE server may own a player's save at a time,
-- so rejoining fast can never duplicate or wipe progress.
--
-- Stored record: { data = Profile, lock = { jobId = string, time = number }? }
--
-- Everything Roblox-specific is injected (store, clock, wait), so this whole
-- module is tested outside Roblox with a fake store.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Types)
local ProfileSchema = require(ReplicatedStorage.Shared.Util.ProfileSchema)
local deepCopy = require(ReplicatedStorage.Shared.Util.DeepCopy)

type Profile = Types.Profile

export type Store = {
	-- transform returns (newValue, userIds?) like Roblox's UpdateAsync.
	UpdateAsync: (self: any, key: string, transform: (any, any) -> (any, any)) -> any,
}

export type Deps = {
	store: Store,
	jobId: string,
	now: () -> number, -- os.time()
	wait: (seconds: number) -> (),
	warn: (message: string) -> (),
	attempts: number?, -- tries per DataStore call
	lockAttempts: number?, -- tries while another server still holds the lock
	lockWaitSeconds: number?,
	lockStaleSeconds: number?, -- a lock older than this belongs to a dead server
}

export type LoadError = "locked" | "error"
export type SaveResult = "ok" | "error" | "lost"

export type SessionStore = {
	load: (self: SessionStore, key: string, userId: number) -> (Profile?, LoadError?),
	save: (self: SessionStore, key: string, profile: Profile, release: boolean, userId: number) -> SaveResult,
}

local SessionStore = {}

function SessionStore.new(deps: Deps): SessionStore
	local attempts = deps.attempts or 5
	local lockAttempts = deps.lockAttempts or 6
	local lockWait = deps.lockWaitSeconds or 5
	local stale = deps.lockStaleSeconds or 600

	-- pcall + exponential backoff around one DataStore call.
	local function withRetry(label: string, fn: () -> ()): boolean
		local delay = 1
		for attempt = 1, attempts do
			local results = table.pack(pcall(fn))
			if results[1] then
				return true
			end
			deps.warn(`[Save] {label} try {attempt}/{attempts} failed: {results[2]}`)
			if attempt < attempts then
				deps.wait(delay)
				delay = math.min(delay * 2, 16)
			end
		end
		return false
	end

	local self = {}

	function self.load(_self: SessionStore, key: string, userId: number): (Profile?, LoadError?)
		for _ = 1, lockAttempts do
			local lockedByOther = false
			local loaded: Profile? = nil
			local ok = withRetry(`load {key}`, function()
				deps.store:UpdateAsync(key, function(record: any): (any, any)
					-- This can run more than once; reset results every time.
					lockedByOther = false
					loaded = nil
					if record ~= nil and typeof(record) ~= "table" then
						error("save record is not a table") -- never overwrite it
					end
					local now = deps.now()
					local lock = record and record.lock
					if
						typeof(lock) == "table"
						and lock.jobId ~= deps.jobId
						and now - (tonumber(lock.time) or 0) < stale
					then
						lockedByOther = true
						return nil, nil -- don't write anything
					end
					local profile = ProfileSchema.migrate(record and record.data)
					loaded = profile
					-- Tagging the UserId lets Roblox handle data-erasure requests.
					return { data = profile, lock = { jobId = deps.jobId, time = now } }, { userId }
				end)
			end)
			if not ok then
				return nil, "error"
			end
			if loaded then
				return loaded, nil
			end
			if lockedByOther then
				deps.wait(lockWait)
			end
		end
		return nil, "locked"
	end

	function self.save(_self: SessionStore, key: string, profile: Profile, release: boolean, userId: number): SaveResult
		local lost = false
		local copy = deepCopy(profile)
		local ok = withRetry(`save {key}`, function()
			deps.store:UpdateAsync(key, function(record: any): (any, any)
				lost = false
				if typeof(record) == "table" then
					local lock = record.lock
					if typeof(lock) == "table" and lock.jobId ~= deps.jobId then
						lost = true -- another server owns this save now; don't clobber it
						return nil, nil
					end
					local stored = record.data
					if
						typeof(stored) == "table"
						and typeof(stored.version) == "number"
						and stored.version > copy.version
					then
						lost = true -- a newer game version saved this; never downgrade
						return nil, nil
					end
				end
				local newLock = if release then nil else { jobId = deps.jobId, time = deps.now() }
				return { data = copy, lock = newLock }, { userId }
			end)
		end)
		if not ok then
			return "error"
		end
		local result: SaveResult = if lost then "lost" else "ok"
		return result
	end

	return (self :: any) :: SessionStore
end

return SessionStore
