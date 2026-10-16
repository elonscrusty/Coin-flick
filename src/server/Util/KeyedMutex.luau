--!strict
-- One-at-a-time lock per key (per player). Saving and loading the same
-- player's data never overlap, so an old save can't land after a newer one.
-- `wait` is injected so tests can run without Roblox.

export type KeyedMutex = {
	run: (self: KeyedMutex, key: any, fn: () -> ()) -> boolean,
	isBusy: (self: KeyedMutex, key: any) -> boolean,
}

local KeyedMutex = {}

function KeyedMutex.new(wait: (seconds: number) -> ()): KeyedMutex
	local busy: { [any]: boolean } = {}
	local mutex = {}

	-- Runs fn while holding the key's lock. Returns false if fn errored.
	function mutex.run(_self: KeyedMutex, key: any, fn: () -> ()): boolean
		while busy[key] do
			wait(0.1)
		end
		busy[key] = true
		local results = table.pack(pcall(fn))
		busy[key] = nil
		if not results[1] then
			warn(`[KeyedMutex] job failed: {results[2]}`)
		end
		return results[1] == true
	end

	function mutex.isBusy(_self: KeyedMutex, key: any): boolean
		return busy[key] == true
	end

	return (mutex :: any) :: KeyedMutex
end

return KeyedMutex
