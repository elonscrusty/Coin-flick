--!strict
-- A fake DataStore that lives in memory. Used in Studio (so playtests never
-- touch real saves) and in automated tests. `failNext` makes the next N calls
-- error, to test retries.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local deepCopy = require(ReplicatedStorage.Shared.Util.DeepCopy)

export type MemoryStore = {
	data: { [string]: any },
	failNext: number,
	calls: number,
	UpdateAsync: (self: MemoryStore, key: string, transform: (any, any) -> (any, any)) -> any,
}

local MemoryStore = {}

function MemoryStore.new(): MemoryStore
	local store = {
		data = {},
		failNext = 0,
		calls = 0,
	}

	function store.UpdateAsync(self: MemoryStore, key: string, transform: (any, any) -> (any, any)): any
		self.calls += 1
		if self.failNext > 0 then
			self.failNext -= 1
			error("simulated DataStore failure")
		end
		local newValue = transform(deepCopy(self.data[key]), nil)
		if newValue ~= nil then
			self.data[key] = deepCopy(newValue)
		end
		return newValue
	end

	return (store :: any) :: MemoryStore
end

return MemoryStore
