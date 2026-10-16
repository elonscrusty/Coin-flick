local ServerScriptService = game:GetService("ServerScriptService")
local RateLimiter = require(ServerScriptService.Server.Util.RateLimiter)

describe("RateLimiter", function()
	it("allows a burst, then blocks spam, then refills over time", function()
		local now = 0
		local limiter = RateLimiter.new(10, 15, function()
			return now
		end)
		local allowed = 0
		for _ = 1, 1000 do
			if limiter:allow("p1") then
				allowed += 1
			end
		end
		expect(allowed).toBe(15)
		now = 1 -- one second later: 10 more
		allowed = 0
		for _ = 1, 1000 do
			if limiter:allow("p1") then
				allowed += 1
			end
		end
		expect(allowed).toBe(10)
	end)
	it("players don't share a bucket", function()
		local limiter = RateLimiter.new(1, 1, function()
			return 0
		end)
		expect(limiter:allow("a")).toBeTruthy()
		expect(limiter:allow("a")).toBeFalsy()
		expect(limiter:allow("b")).toBeTruthy()
	end)
	it("a clock jumping backwards can't create free taps", function()
		local now = 100
		local limiter = RateLimiter.new(10, 2, function()
			return now
		end)
		limiter:allow("a")
		limiter:allow("a")
		now = 0
		expect(limiter:allow("a")).toBeFalsy()
	end)
end)
