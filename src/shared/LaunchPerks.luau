--!strict
-- Launch picks (owner list 2026-10-15: ideas 2, 3, 9, 41-46), pure rules: no Roblox services, tested in
-- tests/test_launch_perks.luau. The server (RetentionService, QuestService, RobuxService) owns the state and pays every
-- reward; clients only see LaunchPerks.view and send intents.
--
--   Day 7 egg     the daily login gift's 7th streak day also banks a free Rare Egg (EggPerks bank, hatched for free).
--   Spin wheel    one free spin every 4 hours: coins (sized to the player's best zone), free luck potion minutes or a
--                 free egg. Free only; Robux never buys a spin.
--   Shiny         1 in 100 pets hatch SHINY (any egg, race or shop): a sparkle shimmer, "Shiny" in the name and 2x sell
--                 value. Decided from the pet's own Seed, so it never changes any other roll.
--   Lucky hour    2x luck for everyone at fixed UTC hours every day (RobuxConfig.Events.LuckyHours).
-- Nothing here changes which hunt egg hides the pet or who finds it.

local RobuxConfig = require(script.Parent.RobuxConfig)

local LaunchPerks = {}

LaunchPerks.StreakEgg = { Day = 7, Egg = "RareEgg" }

LaunchPerks.Shiny = {
	OneIn = 100,
	ValueMult = 2,
	Salt = 7919, -- mixes the pet's Seed so shiny is independent of its look rolls
}

-- Spin wheel slices (the wheel draws them in this order). Coins = Rounds x an average solo round in the player's best
-- zone (RobuxConfig.roundCoins), so a spin stays worth it from Meadow to Space. Weights sum to 100.
export type Slice = { Id: string, Kind: string, Weight: number, Rounds: number?, Minutes: number?, Egg: string? }
LaunchPerks.Spin = {
	Cooldown = 4 * 3600,
	Slices = {
		{ Id = "CoinsS", Kind = "Coins", Rounds = 0.25, Weight = 30 },
		{ Id = "Potion5", Kind = "Potion", Minutes = 5, Weight = 16 },
		{ Id = "CoinsM", Kind = "Coins", Rounds = 0.5, Weight = 20 },
		{ Id = "Basic", Kind = "Egg", Egg = "BasicEgg", Weight = 14 },
		{ Id = "CoinsL", Kind = "Coins", Rounds = 1, Weight = 10 },
		{ Id = "Potion15", Kind = "Potion", Minutes = 15, Weight = 6 },
		{ Id = "Rare", Kind = "Egg", Egg = "RareEgg", Weight = 3.5 },
		{ Id = "Mythic", Kind = "Egg", Egg = "MythicEgg", Weight = 0.5 },
	} :: { Slice },
}

export type State = { SpinAt: number, Spins: number, AutoEgg: string? }

function LaunchPerks.empty(): State
	return { SpinAt = 0, Spins = 0 }
end

local function whole(v: any, lo: number): number
	local n = tonumber(v)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return lo
	end
	return math.max(lo, math.floor(n))
end

function LaunchPerks.sanitize(s: any): State
	if type(s) ~= "table" then
		return LaunchPerks.empty()
	end
	s.SpinAt = whole(s.SpinAt, 0)
	s.Spins = whole(s.Spins, 0)
	if s.AutoEgg ~= nil and type(s.AutoEgg) ~= "string" then
		s.AutoEgg = nil
	end
	return s :: State
end

-- Day 7 egg ------------------------------------------------------------------------------------------------------------

-- The free egg a daily gift on streak day `streakDay` (1..7) banks, or nil.
function LaunchPerks.streakEgg(streakDay: number): string?
	return if streakDay == LaunchPerks.StreakEgg.Day then LaunchPerks.StreakEgg.Egg else nil
end

-- Shiny ----------------------------------------------------------------------------------------------------------------

-- Shiny from a pet's Seed (1 in oneIn; default Shiny.OneIn). Same seed, same answer, on every server.
function LaunchPerks.shinyFromSeed(seed: any, oneIn: number?): boolean
	local n = math.max(1, math.floor(oneIn or LaunchPerks.Shiny.OneIn))
	local s = tonumber(seed)
	if not s or s ~= s then
		return false
	end
	-- one Park-Miller step (exact in doubles: seed < 2^31) so neighbouring seeds don't line up
	local h = ((math.floor(math.abs(s)) % 2147483647) * 48271 + LaunchPerks.Shiny.Salt) % 2147483647
	return h % n == 0
end

function LaunchPerks.shinyMult(shiny: any): number
	return if shiny == true then LaunchPerks.Shiny.ValueMult else 1
end

-- Spin wheel -----------------------------------------------------------------------------------------------------------

-- The prize line once the wheel lands ("YOU WON +500 COINS!"), or nil when there is no prize to show yet: the panel
-- hides the prize pill then (Studio 2026-10-15: an empty green bar sat there before the first spin).
function LaunchPerks.spinWon(text: string?): string?
	if type(text) ~= "string" or string.match(text, "%S") == nil then
		return nil
	end
	return "YOU WON " .. string.upper(text) .. "!"
end

function LaunchPerks.spinLeft(s: State, now: number): number
	return math.max(0, s.SpinAt + LaunchPerks.Spin.Cooldown - now)
end

function LaunchPerks.slice(id: any): Slice?
	for _, sl in LaunchPerks.Spin.Slices do
		if sl.Id == id then
			return sl
		end
	end
	return nil
end

-- x rounded to two significant digits.
local function nice(x: number): number
	if x <= 0 then
		return 0
	end
	local step = 10 ^ math.max(0, math.floor(math.log10(x)) - 1)
	return math.floor(x / step + 0.5) * step
end

function LaunchPerks.sliceCoins(sl: Slice, tierId: string): number
	if sl.Kind ~= "Coins" then
		return 0
	end
	return math.max(10, nice((sl.Rounds or 0) * RobuxConfig.roundCoins(tierId)))
end

-- Short text for a slice ("+500 coins", "5 min 2x luck", "Rare Egg").
function LaunchPerks.sliceText(sl: Slice, tierId: string): string
	if sl.Kind == "Coins" then
		return "+" .. LaunchPerks.sliceCoins(sl, tierId) .. " coins"
	elseif sl.Kind == "Potion" then
		return (sl.Minutes or 0) .. " min 2x luck"
	end
	local e = RobuxConfig.egg(sl.Egg)
	return if e then e.Name else "Egg"
end

-- Spins the wheel if the cooldown is over: (slice, nil) and the clock restarts, or (nil, "NotYet").
-- `r` is a number in [0, 1) from the server's random (the client never picks).
function LaunchPerks.spin(s: State, now: number, r: number): (Slice?, string?)
	if LaunchPerks.spinLeft(s, now) > 0 then
		return nil, "NotYet"
	end
	local total = 0
	for _, sl in LaunchPerks.Spin.Slices do
		total += sl.Weight
	end
	local roll = math.clamp(r, 0, 0.999999) * total
	local pick = LaunchPerks.Spin.Slices[#LaunchPerks.Spin.Slices]
	for _, sl in LaunchPerks.Spin.Slices do
		roll -= sl.Weight
		if roll < 0 then
			pick = sl
			break
		end
	end
	s.SpinAt = now
	s.Spins += 1
	return pick, nil
end

-- Lucky hour -----------------------------------------------------------------------------------------------------------

-- Unix time the lucky hour running at `now` ends, or 0 when none is on.
function LaunchPerks.luckyHourUntil(now: number): number
	local ev = RobuxConfig.Events
	local dayStart = now - now % 86400
	for _, h in ev.LuckyHours do
		local from = dayStart + h * 3600
		local to = from + ev.LuckyHourMinutes * 60
		if now >= from and now < to then
			return to
		end
	end
	return 0
end

-- Seconds until the next lucky hour starts (0 = one is on now).
function LaunchPerks.nextLuckyHour(now: number): number
	if LaunchPerks.luckyHourUntil(now) > 0 then
		return 0
	end
	local dayStart = now - now % 86400
	local best = math.huge
	for _, h in RobuxConfig.Events.LuckyHours do
		for d = 0, 1 do
			local from = dayStart + d * 86400 + h * 3600
			if from > now then
				best = math.min(best, from - now)
			end
		end
	end
	return if best == math.huge then 0 else best
end

-- Limited eggs ---------------------------------------------------------------------------------------------------------

-- The limited egg on sale at `now` (the first one), with its seconds left; nil when none is on sale.
function LaunchPerks.limitedEgg(now: number): (RobuxConfig.Egg?, number)
	for _, e in RobuxConfig.LimitedEggs do
		if RobuxConfig.eggOnSale(e, now) then
			return e, (e.EndsAt :: number) - now
		end
	end
	return nil, 0
end

-- Client view ----------------------------------------------------------------------------------------------------------

function LaunchPerks.view(s: State, robux: any, now: number): { [string]: any }
	local egg, left = LaunchPerks.limitedEgg(now)
	return {
		SpinIn = LaunchPerks.spinLeft(s, now),
		Spins = s.Spins,
		AutoEgg = s.AutoEgg,
		StarterPack = type(robux) == "table" and robux.StarterPack == true,
		Limited = if egg then { Id = egg.Id, Name = egg.Name, EndsIn = left, ShinyOneIn = egg.ShinyOneIn } else nil,
		LuckyHourIn = LaunchPerks.nextLuckyHour(now),
	}
end

return LaunchPerks
