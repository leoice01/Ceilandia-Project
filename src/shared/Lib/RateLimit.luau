--!strict

export type RateLimiter = {
	allow: (self: RateLimiter, key: any) -> boolean,
	forget: (self: RateLimiter, key: any) -> (),
}

type Bucket = {
	tokens: number,
	lastTime: number,
}

local RateLimit = {}

-- Cria um limitador token bucket usando os.clock() como relógio monotônico
function RateLimit.new(rate: number, burst: number): RateLimiter
	assert(
		rate == rate and rate > 0 and rate < math.huge and burst == burst and burst >= 1 and burst < math.huge,
		"RateLimit exige rate > 0 e burst >= 1"
	)

	local buckets: { [any]: Bucket } = {}

	local limiter: RateLimiter = {
		allow = function(_self: RateLimiter, key: any): boolean
			if key == nil then
				return false
			end

			local now = os.clock()
			local bucket = buckets[key]
			if not bucket then
				bucket = {
					tokens = burst,
					lastTime = now,
				}
				buckets[key] = bucket
			else
				local elapsed = math.max(0, now - bucket.lastTime)
				bucket.tokens = math.min(burst, bucket.tokens + elapsed * rate)
				bucket.lastTime = now
			end

			if bucket.tokens < 1 then
				return false
			end

			bucket.tokens -= 1
			return true
		end,

		forget = function(_self: RateLimiter, key: any)
			if key ~= nil then
				buckets[key] = nil
			end
		end,
	}

	return limiter
end

return RateLimit