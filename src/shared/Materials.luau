--!strict
-- Material Discoveries, pure rules (docs/m6/DISCOVERIES.md). No Roblox services: unit-tested in tests/.
--
--   pick(salt, roundId, rockId)   the category of one rock in one round. A pure function of a server-only
--                                 salt, so retries / tool changes / who cracks it cannot reroll it, and it does
--                                 not depend on which rock is the geode target. Weights: Config.Materials.
--   record(store, id)             a finished ordinary crush for the owner: counts it and says whether the
--                                 category is new. Unknown ids (a future build wrote them) are ignored.
--   normalize(store)              safe defaults for old or damaged profile data; keeps unknown future ids.
--   progress(store)               numerator / denominator for the Collection line, configured categories only.

local Config = require(script.Parent.Config)

local Materials = {}

export type Store = { Found: { [string]: boolean }, Counts: { [string]: number } }

-- Exact 32-bit multiply (a double cannot hold a 64-bit product, so split into 16-bit halves).
local function mul32(a: number, b: number): number
	local hi = bit32.band(bit32.rshift(a, 16) * b, 0xFFFF)
	return bit32.band(hi * 65536 + bit32.band(a, 0xFFFF) * b, 0xFFFFFFFF)
end

-- 32-bit integer mix (xorshift-multiply), all values stay in uint32 range.
local function mix(h: number): number
	h = bit32.band(h, 0xFFFFFFFF)
	h = mul32(bit32.bxor(h, bit32.rshift(h, 16)), 0x45D9F3B)
	h = mul32(bit32.bxor(h, bit32.rshift(h, 16)), 0x45D9F3B)
	return bit32.bxor(h, bit32.rshift(h, 16))
end

function Materials.order(): { string }
	return Config.MaterialOrder
end

function Materials.get(id: any): any?
	if type(id) ~= "string" then
		return nil
	end
	return Config.Materials[id]
end

function Materials.totalWeight(): number
	local total = 0
	for _, id in Config.MaterialOrder do
		total += Config.Materials[id].Weight
	end
	return total
end

-- The unit-interval draw for one rock: deterministic in (salt, roundId, rockId).
function Materials.roll(salt: number, roundId: number, rockId: number): number
	local h = mix(bit32.band(salt, 0xFFFFFFFF) + 0x9E3779B1)
	h = mix(bit32.bxor(h, mul32(bit32.band(roundId, 0xFFFFFFFF), 0x85EBCA6B)))
	h = mix(bit32.bxor(h, mul32(bit32.band(rockId, 0xFFFFFFFF), 0xC2B2AE35)))
	return h / 4294967296
end

function Materials.pick(salt: number, roundId: number, rockId: number): string
	local x = Materials.roll(salt, roundId, rockId) * Materials.totalWeight()
	local acc = 0
	for _, id in Config.MaterialOrder do
		acc += Config.Materials[id].Weight
		if x < acc then
			return id
		end
	end
	return Config.MaterialOrder[1]
end

function Materials.empty(): Store
	return { Found = {}, Counts = {} }
end

-- Repairs a profile's Materials table in place (never removes ids it does not know: a newer build may have them).
function Materials.normalize(store: any): Store
	if type(store) ~= "table" then
		return Materials.empty()
	end
	if type(store.Found) ~= "table" then
		store.Found = {}
	end
	if type(store.Counts) ~= "table" then
		store.Counts = {}
	end
	for k, v in store.Counts do
		if type(k) ~= "string" or type(v) ~= "number" or v ~= v or v < 0 or v == math.huge then
			store.Counts[k] = nil
		else
			store.Counts[k] = math.floor(v)
		end
	end
	for k, v in store.Found do
		if type(k) ~= "string" or v ~= true then
			store.Found[k] = nil
		end
	end
	-- a counted category was necessarily discovered
	for k, v in store.Counts do
		if v > 0 then
			store.Found[k] = true
		end
	end
	return store
end

-- Returns (counted, isNew). Only configured categories count.
function Materials.record(store: Store, id: any): (boolean, boolean)
	if type(id) ~= "string" or not Config.Materials[id] then
		return false, false
	end
	local isNew = store.Found[id] ~= true
	store.Found[id] = true
	store.Counts[id] = (store.Counts[id] or 0) + 1
	return true, isNew
end

function Materials.progress(store: any): (number, number)
	local n = 0
	local found = if type(store) == "table" and type(store.Found) == "table" then store.Found else {}
	for _, id in Config.MaterialOrder do
		if found[id] == true then
			n += 1
		end
	end
	return n, #Config.MaterialOrder
end

-- The compact copy sent to the owning client (configured ids only).
function Materials.publicView(store: Store): Store
	local out = Materials.empty()
	for _, id in Config.MaterialOrder do
		if store.Found[id] then
			out.Found[id] = true
			out.Counts[id] = store.Counts[id] or 0
		end
	end
	return out
end

return Materials
