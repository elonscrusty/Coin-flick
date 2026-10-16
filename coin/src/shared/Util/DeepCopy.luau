--!strict
-- Plain-table deep copy (no metatables, no cycles). Used for default profiles
-- and for the in-memory test store so nobody shares a live table by accident.

local function deepCopy<T>(value: T): T
	if typeof(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value :: any do
		out[deepCopy(k)] = deepCopy(v)
	end
	return (out :: any) :: T
end

return deepCopy
