--!strict
-- Saved data shape: defaults, version migrations, and cleanup of bad values.
-- Rule: a broken save is an ERROR (so it is never overwritten), never "start fresh".

local Types = require(script.Parent.Parent.Types)
local deepCopy = require(script.Parent.DeepCopy)

type Profile = Types.Profile

local ProfileSchema = {}

ProfileSchema.CURRENT_VERSION = 1

local DEFAULT: Profile = {
	version = 1,
	cash = 0,
	hatPoints = 0,
	upgrades = { moreCoins = 0, bigCoins = 0, luck = 0, speed = 0 },
	helpers = 0,
	resets = 0,
	stats = { flips = 0, heads = 0, skulls = 0, biggestFlip = 0 },
	lastSeen = 0,
}

function ProfileSchema.default(): Profile
	return deepCopy(DEFAULT)
end

-- Step N turns a version-N profile into version N+1. Add new steps here.
local MIGRATIONS: { [number]: (any) -> any } = {}

local function cleanNumber(value: unknown, fallback: number): number
	if typeof(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return math.max(0, value)
end

local function cleanInt(value: unknown, fallback: number): number
	return math.floor(cleanNumber(value, fallback))
end

-- Fill any missing or bad field from the defaults (new fields appear this way too).
local function reconcile(data: { [string]: any }): Profile
	local d = DEFAULT
	local up = if typeof(data.upgrades) == "table" then data.upgrades else {}
	local st = if typeof(data.stats) == "table" then data.stats else {}
	return {
		version = ProfileSchema.CURRENT_VERSION,
		cash = cleanNumber(data.cash, d.cash),
		hatPoints = cleanInt(data.hatPoints, d.hatPoints),
		upgrades = {
			moreCoins = cleanInt(up.moreCoins, 0),
			bigCoins = cleanInt(up.bigCoins, 0),
			luck = cleanInt(up.luck, 0),
			speed = cleanInt(up.speed, 0),
		},
		helpers = cleanInt(data.helpers, d.helpers),
		resets = cleanInt(data.resets, d.resets),
		stats = {
			flips = cleanInt(st.flips, 0),
			heads = cleanInt(st.heads, 0),
			skulls = cleanInt(st.skulls, 0),
			biggestFlip = cleanNumber(st.biggestFlip, 0),
		},
		lastSeen = cleanInt(data.lastSeen, d.lastSeen),
	}
end

-- nil -> brand new player. A table -> migrated + cleaned. Anything else -> error.
function ProfileSchema.migrate(data: unknown): Profile
	if data == nil then
		return ProfileSchema.default()
	end
	if typeof(data) ~= "table" then
		error("profile data is not a table")
	end
	local t = data :: { [string]: any }
	local version = t.version
	if typeof(version) ~= "number" or version ~= math.floor(version) or version < 1 then
		error("profile has no valid version")
	end
	if version > ProfileSchema.CURRENT_VERSION then
		-- Saved by a newer server. Refuse instead of downgrading it.
		error(`profile version {version} is newer than {ProfileSchema.CURRENT_VERSION}`)
	end
	while t.version < ProfileSchema.CURRENT_VERSION do
		local step = MIGRATIONS[t.version]
		if not step then
			error(`missing migration from v{t.version}`)
		end
		t = step(t)
		t.version += 1
	end
	return reconcile(t)
end

return ProfileSchema
