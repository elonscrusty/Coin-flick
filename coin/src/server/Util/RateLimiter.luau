--!strict
-- Token bucket per key (per player). Stops tap spam and remote flooding.
-- `clock` is injected so tests can control time.

export type RateLimiter = {
	allow: (self: RateLimiter, key: any) -> boolean,
	remove: (self: RateLimiter, key: any) -> (),
}

type Bucket = { tokens: number, last: number }

local RateLimiter = {}

function RateLimiter.new(ratePerSecond: number, burst: number, clock: () -> number): RateLimiter
	local buckets: { [any]: Bucket } = {}

	local limiter = {}

	function limiter.allow(_self: RateLimiter, key: any): boolean
		local now = clock()
		local b = buckets[key]
		if not b then
			b = { tokens = burst, last = now }
			buckets[key] = b
		end
		local elapsed = math.max(0, now - b.last)
		b.tokens = math.min(burst, b.tokens + elapsed * ratePerSecond)
		b.last = now
		if b.tokens < 1 then
			return false
		end
		b.tokens -= 1
		return true
	end

	function limiter.remove(_self: RateLimiter, key: any)
		buckets[key] = nil
	end

	return (limiter :: any) :: RateLimiter
end

return RateLimiter
