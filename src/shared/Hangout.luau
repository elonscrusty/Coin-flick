--!strict
-- Lobby hangout (owner picks 2026-10-14: ideas 1, 2, 4, 6, 7, 8, 9, 10; no trading, no pet tricks). All tuning and the
-- pure rules, tested offline (tests/test_hangout.luau). The server owns every outcome (server/LobbyHangout,
-- server/LobbyGames, server/LobbyEvents); clients only draw (client/HangoutView).
--
--   1 show-off plots   likes are saved per UTC day; the plot with the most likes TODAY wears the crown and a glow
--   2 rare-hatch alert a sky beam over the egg shrine when an Epic or Legendary hatches in this server
--   4 mini-games       whack-a-rock stump (the pet race and egg toss were removed 2026-10-14); small coin prizes, one daily cap
--   6 big boards       MOST COINS joins RAREST PET and HIGHEST FLOOR (shared/Boards)
--   7 hourly events    coin rain, golden rock (everyone cracks it together), mystery egg drop
--   8 sit spots        Seats (benches, swing, dock, campfire logs) get a Sit prompt; emote button (Roblox's own emotes)
--   9 secret spots     hidden eggs (coins once each) and the lookout chest up the mountain (coins once a day)
--  10 group bonus      Roblox group members get a free pet once and a little hunt luck (needs the group id)
--
-- Profile state lives in data.Hangout (Hangout.empty), added without a schema bump.

local Retention = require(script.Parent.Retention)

local Hangout = {}

local DAY = 86400

function Hangout.day(now: number): number
	return math.floor(now / DAY)
end

-- Profile state ----------------------------------------------------------------------------------------------------

export type State = {
	Day: number, -- UTC day the daily fields below belong to
	LikesToday: number, -- likes this player's plot got today
	Liked: { string }, -- owner UserIds (strings) this player liked today
	GameCoins: number, -- mini-game coins paid today (Games.DailyCoinCap)
	LookoutDay: number, -- last UTC day the lookout chest was opened
	Secrets: { [string]: boolean }, -- hidden egg names found (once ever)
	GroupGift: boolean, -- free group pet already given
}

function Hangout.empty(): State
	return { Day = 0, LikesToday = 0, Liked = {}, GameCoins = 0, LookoutDay = 0, Secrets = {}, GroupGift = false }
end

local function num(v: any): number
	return if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then v else 0
end

-- Fills or repairs a saved state in place (an old or hand-edited save) and returns it.
function Hangout.sanitize(s: any): State
	if type(s) ~= "table" then
		return Hangout.empty()
	end
	s.Day = math.floor(num(s.Day))
	s.LikesToday = math.max(0, math.floor(num(s.LikesToday)))
	s.GameCoins = math.max(0, math.floor(num(s.GameCoins)))
	s.LookoutDay = math.floor(num(s.LookoutDay))
	if type(s.Liked) ~= "table" then
		s.Liked = {}
	end
	if type(s.Secrets) ~= "table" then
		s.Secrets = {}
	end
	s.GroupGift = s.GroupGift == true
	return s :: State
end

-- Starts a new day: today's likes, liked list and game coins go back to zero.
function Hangout.roll(s: State, day: number)
	if s.Day ~= day then
		s.Day = day
		s.LikesToday = 0
		s.Liked = {}
		s.GameCoins = 0
	end
end

-- 1 Show-off plots --------------------------------------------------------------------------------------------------

Hangout.Likes = {
	LikedMax = 200, -- owners one player can like per day (keeps the save small)
	Glow = Color3.fromRGB(255, 214, 92),
}

-- A like from `visitor` (state, UserId) for `owner` (state, UserId). Returns (ok, reason "own" | "again" | "max").
function Hangout.like(visitor: State, visitorId: number, owner: State, ownerId: number, day: number): (boolean, string?)
	if visitorId == ownerId then
		return false, "own"
	end
	Hangout.roll(visitor, day)
	Hangout.roll(owner, day)
	local key = tostring(ownerId)
	if table.find(visitor.Liked, key) then
		return false, "again"
	end
	if #visitor.Liked >= Hangout.Likes.LikedMax then
		return false, "max"
	end
	table.insert(visitor.Liked, key)
	owner.LikesToday += 1
	return true, nil
end

function Hangout.likesToday(s: State, day: number): number
	return if s.Day == day then s.LikesToday else 0
end

-- 2 Rare-hatch alert -----------------------------------------------------------------------------------------------

Hangout.Beam = {
	Rarities = { Epic = true, Legendary = true },
	Seconds = 8,
	Height = 400,
	Width = { Epic = 5, Legendary = 8 },
	Color = { Epic = Color3.fromRGB(196, 110, 255), Legendary = Color3.fromRGB(255, 206, 64) },
}

function Hangout.beamFor(rarity: any): boolean
	return type(rarity) == "string" and Hangout.Beam.Rarities[rarity] == true
end

-- 4 Mini-games ----------------------------------------------------------------------------------------------------

Hangout.Games = {
	DailyCoinCap = 600, -- all mini-game prizes together, per player per UTC day
	Range = 16, -- studs from a game's prompt part
	Whack = { Seconds = 20, PopSeconds = 0.9, Gap = 0.15, CoinsPerHit = 2, MaxCoins = 40, Cooldown = 5, HoleRadius = 2.6, Holes = 5, LeaveDistance = 30 },
}

-- Coins a mini-game may still pay `want` today (the daily cap), and books them.
function Hangout.payGame(s: State, day: number, want: number): number
	Hangout.roll(s, day)
	local room = math.max(0, Hangout.Games.DailyCoinCap - s.GameCoins)
	local pay = math.clamp(math.floor(num(want)), 0, room)
	s.GameCoins += pay
	return pay
end

function Hangout.whackPrize(hits: number): number
	local w = Hangout.Games.Whack
	return math.clamp(math.floor(num(hits)) * w.CoinsPerHit, 0, w.MaxCoins)
end

-- 7 Hourly events -------------------------------------------------------------------------------------------------

Hangout.Events = {
	Interval = 3600, -- one event at the start of every UTC hour (every server at once)
	WarnSeconds = 60, -- "starts in 1 minute" toast
	Order = { "CoinRain", "GoldenRock", "MysteryEgg" },
	CoinRain = { Seconds = 30, Coins = 80, CoinValue = 5, PlayerCap = 75, Radius = 36, DropHeight = 40, Life = 25 },
	GoldenRock = { Seconds = 120, HitsPerPlayer = 15, MinHits = 25, HitGap = 0.25, Prize = 60, Range = 14 },
	MysteryEgg = { Seconds = 90, Egg = "BasicEgg", FallbackCoins = 120, Range = 12 },
	Names = { CoinRain = "COIN RAIN", GoldenRock = "GOLDEN EGG", MysteryEgg = "MYSTERY EGG" },
}

-- The event that starts at the hour slot holding `now`, and when the next one starts.
function Hangout.eventAt(now: number): string
	local e = Hangout.Events
	local slot = math.floor(now / e.Interval)
	return e.Order[slot % #e.Order + 1]
end

function Hangout.nextEventTime(now: number): number
	local e = Hangout.Events
	return (math.floor(now / e.Interval) + 1) * e.Interval
end

-- Hits the golden rock needs with `players` in the lobby.
function Hangout.rockHits(players: number): number
	local g = Hangout.Events.GoldenRock
	return math.max(g.MinHits, math.floor(num(players)) * g.HitsPerPlayer)
end

-- Coin-rain coins one player may still collect this event.
function Hangout.rainRoom(collected: number): number
	local c = Hangout.Events.CoinRain
	return math.max(0, c.PlayerCap - math.floor(num(collected)))
end

-- 8 Sit spots + emotes --------------------------------------------------------------------------------------------

Hangout.Sit = {
	Names = { "SitSpot", "Bench", "Swing", "DockSeat", "CampfireLog" }, -- a part whose name starts with one of these
	Campfire = "Campfire", -- gets a warm light (static: no flames moving, owner rule)
}

-- Roblox's default emotes, read from the avatar's own Animate script at run time (no asset ids here).
Hangout.Emotes = {
	{ Key = "wave", Name = "Wave" },
	{ Key = "cheer", Name = "Cheer" },
	{ Key = "dance", Name = "Dance" },
	{ Key = "dance2", Name = "Dance 2" },
	{ Key = "laugh", Name = "Laugh" },
	{ Key = "point", Name = "Point" },
}

function Hangout.isSitName(name: string): boolean
	for _, n in Hangout.Sit.Names do
		if string.sub(name, 1, #n) == n then
			return true
		end
	end
	return false
end

-- 9 Secret spots --------------------------------------------------------------------------------------------------

Hangout.Secrets = {
	Prefix = "HiddenEgg", -- HiddenEgg1, HiddenEgg2, ... anywhere in the lobby
	Coins = 75, -- once per hidden egg, ever
	Lookout = "LookoutChest", -- the chest at the mountain lookout
	LookoutCoins = 150, -- once per UTC day
	Range = 12,
}

-- A hidden egg's name -> its number, or nil when the name is not a hidden egg.
function Hangout.secretIndex(name: string): number?
	local n = string.match(name, "^" .. Hangout.Secrets.Prefix .. "(%d+)$")
	return if n then tonumber(n) else nil
end

function Hangout.claimSecret(s: State, name: string): boolean
	if not Hangout.secretIndex(name) or s.Secrets[name] then
		return false
	end
	s.Secrets[name] = true
	return true
end

function Hangout.secretsFound(s: State): number
	local n = 0
	for k, v in s.Secrets do
		if v == true and Hangout.secretIndex(k) then
			n += 1
		end
	end
	return n
end

-- The found hidden eggs as one short player attribute ("HiddenEgg1,HiddenEgg3", sorted): the client hides those
-- eggs and their Take prompts for this player only (audit F25: a taken egg stayed visible and tappable).
Hangout.Secrets.FoundAttr = "HiddenEggsFound"
function Hangout.foundList(s: State): string
	local names = {}
	for k, v in s.Secrets do
		if v == true and Hangout.secretIndex(k) then
			table.insert(names, k)
		end
	end
	table.sort(names, function(a, b)
		return (Hangout.secretIndex(a) or 0) < (Hangout.secretIndex(b) or 0)
	end)
	return table.concat(names, ",")
end

-- The attribute back to a set of hidden egg names (junk and unknown names are dropped).
function Hangout.parseFound(text: any): { [string]: boolean }
	local out = {}
	if type(text) == "string" then
		for name in string.gmatch(text, "[^,]+") do
			if Hangout.secretIndex(name) then
				out[name] = true
			end
		end
	end
	return out
end

function Hangout.claimLookout(s: State, day: number): boolean
	if s.LookoutDay == day then
		return false
	end
	s.LookoutDay = day
	return true
end

-- Animation (owner ask 2026-10-14: "animate what you can on all of them, glowing aura etc"; this lifts the old
-- static-props rule for the hangout pieces). Drawn by client/HangoutAnim, only within Near studs of the camera.
Hangout.Anim = {
	Near = 140, -- studs: farther pieces stop moving and their sparkles switch off
	CullEvery = 0.5, -- seconds between distance checks
	-- part name (exact, or a pattern) -> look
	Kinds = {
		{ Match = "^GoldenRock$", Kind = "GoldenRock" },
		{ Match = "^MysteryEgg$", Kind = "MysteryEgg" },
		{ Match = "^WhackRock$", Kind = "WhackRock" },
		{ Match = "^RainCoin$", Kind = "RainCoin" },
		{ Match = "^HiddenEgg%d+$", Kind = "HiddenEgg" },
		{ Match = "^LookoutChest$", Kind = "Lookout" },
		{ Match = "^CampfireLight$", Kind = "Campfire" },
		{ Match = "^CT_TopPlotGlow$", Kind = "TopPlot" },
		{ Match = "^CT_Park_PlotCrown$", Kind = "Crown" },
		{ Match = "^SkyBeam$", Kind = "Beam" },
		{ Match = "^WhackStump$", Kind = "Stump" },
	},
}

function Hangout.animKind(name: string): string?
	for _, k in Hangout.Anim.Kinds do
		if string.match(name, k.Match) then
			return k.Kind
		end
	end
	return nil
end

-- A smooth 0..1 pulse at `speed` cycles per second (phase-shifted by `seed`).
function Hangout.pulse(t: number, speed: number, seed: number?): number
	return 0.5 + 0.5 * math.sin((t * speed + (seed or 0)) * math.pi * 2)
end

-- Is a piece at distance `d` from the camera animated?
function Hangout.animNear(d: number, lowEffects: boolean): boolean
	return d <= (if lowEffects then Hangout.Anim.Near / 2 else Hangout.Anim.Near)
end

-- 10 Group bonus --------------------------------------------------------------------------------------------------

-- The group id is Retention.Group.Id (one place for it; the daily group coin gift uses it too).
Hangout.Group = {
	Luck = 0.05, -- extra hunt luck for group members
	GiftEgg = "BasicEgg", -- the free pet is hatched from this egg (race egg odds)
	GiftPrompt = "GroupGift", -- optional part in the lobby: "Claim" re-checks after joining the group
}

function Hangout.groupId(): number
	return Retention.Group.Id
end

function Hangout.groupOn(): boolean
	local id = Hangout.groupId()
	return type(id) == "number" and id > 0 and id == math.floor(id)
end

function Hangout.groupLuck(member: boolean): number
	return if member and Hangout.groupOn() then Hangout.Group.Luck else 0
end

-- GroupService:GetGroupsAsync rows -> member of the configured group?
function Hangout.inGroup(rows: any): boolean
	if not Hangout.groupOn() or type(rows) ~= "table" then
		return false
	end
	for _, r in rows do
		if type(r) == "table" and r.Id == Hangout.groupId() then
			return true
		end
	end
	return false
end

return Hangout
