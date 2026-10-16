--!strict
-- Luck events and luck stacking (pure; tested in tests/test_robux.luau). The server (RobuxService) runs the storm
-- clock and publishes the live state as ReplicatedStorage attributes; the hunt reward (MatchService) and paid eggs
-- (RobuxService) add the sources up with LuckEvents.total, and the shop / HUD show the same numbers.
--
-- "Luck" is the GeodeGen number: Rare and better pets weigh (1 + luck) times more. Luck never changes which egg hides
-- the pet or who finds it.
--
-- ReplicatedStorage attributes (set by the server only):
--   LuckStormUntil  number  os.time() when the current luck storm ends (0 / past = no storm)
--   LuckWeekend     boolean the UTC weekend 2x luck is on

local Config = require(script.Parent.Config)
local RobuxConfig = require(script.Parent.RobuxConfig)
local GeodeGen = require(script.Parent.GeodeGen)
local SpeciesPool = require(script.Parent.SpeciesPool)
local LaunchPerks = require(script.Parent.LaunchPerks)

local LuckEvents = {}

-- Saturday or Sunday in UTC (os.date "!*t": wday 1 = Sunday, 7 = Saturday).
function LuckEvents.isWeekend(t: number): boolean
	local d = os.date("!*t", math.floor(t)) :: any
	return d.wday == 1 or d.wday == 7
end

export type Sources = {
	Pet: number?, -- equipped pets' Luck boost (already capped by Config.Pets.KindCap.Luck)
	Friends: number?, -- friends / party luck (already capped by QueueConfig.FriendLuck.Max)
	Potion: number?,
	Weekend: number?,
	Storm: number?,
	Hour: number?, -- lucky hour (LaunchPerks.luckyHourUntil)
	Vip: number?, -- VIP pass (RobuxConfig.vipLuck)
}

-- The timed sources active at `now` for a player whose potion runs until `potionUntil`, on a server whose storm runs
-- until `stormUntil`.
function LuckEvents.timed(now: number, potionUntil: number?, stormUntil: number?): { Potion: number, Weekend: number, Storm: number, Hour: number }
	local ev = RobuxConfig.Events
	return {
		Potion = if (potionUntil or 0) > now then RobuxConfig.Potion.Luck else 0,
		Weekend = if LuckEvents.isWeekend(now) then ev.WeekendLuck else 0,
		Storm = if (stormUntil or 0) > now then ev.StormLuck else 0,
		Hour = if LaunchPerks.luckyHourUntil(now) > 0 then ev.LuckyHourLuck else 0,
	}
end

-- Sum of every source, clamped to [0, RobuxConfig.MaxLuck]. Bad numbers (nil, NaN, negative) count as 0.
function LuckEvents.total(s: Sources): number
	local sum = 0
	for _, v in { s.Pet, s.Friends, s.Potion, s.Weekend, s.Storm, s.Hour, s.Vip } do
		if type(v) == "number" and v == v and v > 0 then
			sum += v
		end
	end
	return math.clamp(sum, 0, RobuxConfig.MaxLuck)
end

-- "x2" style multiplier the UI shows for a luck total (Rare and better odds factor).
function LuckEvents.factor(luck: number): number
	return 1 + math.clamp(luck, 0, RobuxConfig.MaxLuck)
end

-- Seconds until the next storm (random within the configured gap). first = a fresh server.
function LuckEvents.nextGap(rng: Random, first: boolean?): number
	local ev = RobuxConfig.Events
	if first then
		return ev.FirstStormMin + rng:NextNumber() * (ev.StormGapMax - ev.StormGapMin) * 0.5
	end
	return ev.StormGapMin + rng:NextNumber() * (ev.StormGapMax - ev.StormGapMin)
end

-- "12:05" / "1:02:03" for a countdown in seconds.
function LuckEvents.clock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local h, m = math.floor(s / 3600), math.floor(s % 3600 / 60)
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s % 60)
	end
	return string.format("%d:%02d", m, s % 60)
end

export type Odds = {
	Rarity: { { Name: string, P: number } },
	Variant: { { Name: string, P: number } },
	Species: { string },
	SpeciesP: { { Id: string, Name: string, P: number, Chase: boolean } }, -- per species chance (chase = Legendary only)
}

-- The exact odds GeodeGen.roll uses for a pet of this zone with this luck (the paid egg card prints these).
-- Rarity and variant are independent; the species follows SpeciesPool (chase pet = the Legendary roll).
function LuckEvents.eggOdds(tierId: string, luck: number?, baseWeights: { [string]: number }?): Odds
	local w = GeodeGen.rarityWeights(luck, baseWeights)
	local total = 0
	for _, r in Config.Rarities do
		total += w[r] or 0
	end
	local out: Odds = { Rarity = {}, Variant = {}, Species = {}, SpeciesP = {} }
	for _, r in Config.Rarities do
		table.insert(out.Rarity, { Name = r, P = if total > 0 then (w[r] or 0) / total else 0 })
	end
	local vt = 0
	for _, m in Config.Modifiers do
		vt += (Config.ModifierWeights :: any)[m] or 0
	end
	for _, m in Config.Modifiers do
		local name = (Config.ModifierNames :: any)[m]
		table.insert(out.Variant, { Name = if name == nil or name == "" then "Normal" else name, P = if vt > 0 then ((Config.ModifierWeights :: any)[m] or 0) / vt else 0 })
	end
	local rp = {}
	for _, r in out.Rarity do
		rp[r.Name] = r.P
	end
	local now = os.time()
	for _, id in SpeciesPool.list(tierId, now) do
		local m: any = (Config.Minerals :: any)[id]
		table.insert(out.Species, if m then m.Name else id)
		table.insert(out.SpeciesP, { Id = id, Name = if m then m.Name else id, P = SpeciesPool.chance(tierId, id, now, rp), Chase = m ~= nil and m.Chase == true })
	end
	return out
end

-- "60%", "3.9%", "0.1% (1 in 1000)": a chance a young player can read.
function LuckEvents.chanceText(p: number): string
	local pct = p * 100
	local s
	if pct >= 10 or math.abs(pct - math.floor(pct + 0.5)) < 0.05 then
		s = tostring(math.floor(pct + 0.5)) .. "%"
	elseif pct >= 0.0995 then
		s = string.format("%.1f%%", pct)
	else
		s = string.format("%.2f%%", pct)
	end
	if p > 0 and p < 0.01 then
		s ..= " (1 in " .. math.floor(1 / p + 0.5) .. ")"
	end
	return s
end

-- The hatch reveal's odds line: the "1 in N" for one pet, or nil when no line should show. N is always a whole
-- number ("1 in 1.5?" read as a typo, bug #226) and common results show no line at all: a Common pet, or anything
-- better than 1 in OddsLineMin. `p` = the chance of this exact pet (rarity chance times species share).
LuckEvents.OddsLineMin = 10
function LuckEvents.oneIn(p: number, rarity: string?): number?
	if type(p) ~= "number" or p ~= p or p <= 0 or rarity == "Common" then
		return nil
	end
	local n = math.floor(1 / p + 0.5)
	if n < LuckEvents.OddsLineMin then
		return nil
	end
	return n
end

return LuckEvents
