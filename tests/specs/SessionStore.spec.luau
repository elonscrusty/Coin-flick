local ServerScriptService = game:GetService("ServerScriptService")
local SessionStore = require(ServerScriptService.Server.Util.SessionStore)
local MemoryStore = require(ServerScriptService.Server.Util.MemoryStore)

local function newServer(store, jobId, clock)
	local warnings = {}
	local waited = 0
	local s = SessionStore.new({
		store = store,
		jobId = jobId,
		now = function()
			return clock.t
		end,
		wait = function(seconds)
			waited += seconds
			clock.t += seconds
		end,
		warn = function(msg)
			table.insert(warnings, msg)
		end,
		attempts = 4,
		lockAttempts = 3,
		lockWaitSeconds = 5,
		lockStaleSeconds = 600,
	})
	return s, warnings, function()
		return waited
	end
end

describe("SessionStore", function()
	it("new player loads a fresh profile and the server takes the lock", function()
		local store = MemoryStore.new()
		local clock = { t = 1000 }
		local server = newServer(store, "A", clock)
		local p, err = server:load("u_1")
		expect(err).toBeNil()
		expect(p.cash).toBe(0)
		expect(store.data["u_1"].lock.jobId).toBe("A")
	end)

	it("progress survives leaving and coming back", function()
		local store = MemoryStore.new()
		local clock = { t = 1000 }
		local a = newServer(store, "A", clock)
		local p = a:load("u_1")
		p.cash = 777
		p.upgrades.luck = 3
		expect(a:save("u_1", p, true)).toBe("ok")
		expect(store.data["u_1"].lock).toBeNil()
		local b = newServer(store, "B", clock)
		local again = b:load("u_1")
		expect(again.cash).toBe(777)
		expect(again.upgrades.luck).toBe(3)
	end)

	it("a second server can't load while the first still owns the save", function()
		local store = MemoryStore.new()
		local clock = { t = 1000 }
		local a = newServer(store, "A", clock)
		a:load("u_1")
		local b = newServer(store, "B", clock)
		local p, err = b:load("u_1")
		expect(p).toBeNil()
		expect(err).toBe("locked")
	end)

	it("the second server gets in once the first releases (fast rejoin)", function()
		local store = MemoryStore.new()
		local clock = { t = 1000 }
		local a = newServer(store, "A", clock)
		local p = a:load("u_1")
		p.cash = 50
		-- B starts loading while A still holds it; A releases during B's wait.
		local releasingStore = {
			UpdateAsync = function(_, key, fn)
				local result = store:UpdateAsync(key, fn)
				if store.data[key].lock and store.data[key].lock.jobId == "A" then
					a:save("u_1", p, true)
				end
				return result
			end,
		}
		local b = newServer(releasingStore, "B", clock)
		local got, err = b:load("u_1")
		expect(err).toBeNil()
		expect(got.cash).toBe(50)
	end)

	it("a dead server's old lock goes stale and the player can load", function()
		local store = MemoryStore.new()
		local clock = { t = 1000 }
		local a = newServer(store, "A", clock)
		local p = a:load("u_1")
		p.cash = 10
		a:save("u_1", p, false) -- server A crashes after this, never releasing
		clock.t += 601
		local b = newServer(store, "B", clock)
		local got, err = b:load("u_1")
		expect(err).toBeNil()
		expect(got.cash).toBe(10)
	end)

	it("an old server whose lock was taken can't overwrite the new progress", function()
		local store = MemoryStore.new()
		local clock = { t = 1000 }
		local a = newServer(store, "A", clock)
		local pa = a:load("u_1")
		clock.t += 601
		local b = newServer(store, "B", clock)
		local pb = b:load("u_1")
		pb.cash = 9999
		b:save("u_1", pb, false)
		pa.cash = 1
		expect(a:save("u_1", pa, true)).toBe("lost")
		expect(store.data["u_1"].data.cash).toBe(9999)
	end)

	it("retries when Roblox saving hiccups, then succeeds", function()
		local store = MemoryStore.new()
		local clock = { t = 1000 }
		local a, warnings, waited = newServer(store, "A", clock)
		local p = a:load("u_1")
		p.cash = 42
		store.failNext = 2
		expect(a:save("u_1", p, true)).toBe("ok")
		expect(#warnings).toBe(2)
		expect(waited()).toBe(1 + 2) -- backoff 1s, then 2s
		expect(store.data["u_1"].data.cash).toBe(42)
	end)

	it("load failing every time gives an error (player gets kicked, data untouched)", function()
		local store = MemoryStore.new()
		store.data["u_1"] = { data = { version = 1, cash = 5000 }, lock = nil }
		store.failNext = 100
		local clock = { t = 1000 }
		local a = newServer(store, "A", clock)
		local p, err = a:load("u_1")
		expect(p).toBeNil()
		expect(err).toBe("error")
		expect(store.data["u_1"].data.cash).toBe(5000)
	end)

	it("a corrupted save is never overwritten with a fresh profile", function()
		local store = MemoryStore.new()
		store.data["u_1"] = "this is not a table"
		local clock = { t = 1000 }
		local a = newServer(store, "A", clock)
		local p, err = a:load("u_1")
		expect(p).toBeNil()
		expect(err).toBe("error")
		expect(store.data["u_1"]).toBe("this is not a table")
		store.data["u_2"] = { data = { cash = 5 } } -- missing version
		local p2, err2 = a:load("u_2")
		expect(p2).toBeNil()
		expect(err2).toBe("error")
		expect(store.data["u_2"].data.cash).toBe(5)
	end)

	it("saving copies the profile (later changes don't leak into the store)", function()
		local store = MemoryStore.new()
		local clock = { t = 1000 }
		local a = newServer(store, "A", clock)
		local p = a:load("u_1")
		p.cash = 1
		a:save("u_1", p, false)
		p.cash = 2
		expect(store.data["u_1"].data.cash).toBe(1)
	end)

	it("autosave keeps the lock fresh", function()
		local store = MemoryStore.new()
		local clock = { t = 1000 }
		local a = newServer(store, "A", clock)
		local p = a:load("u_1")
		clock.t = 1500
		a:save("u_1", p, false)
		expect(store.data["u_1"].lock.time).toBe(1500)
		clock.t = 2050 -- 550s after last autosave: still fresh
		local b = newServer(store, "B", clock)
		local got, err = b:load("u_1")
		expect(got).toBeNil()
		expect(err).toBe("locked")
	end)
end)
