--!strict
-- First five minutes and comeback hooks as pure rules (no Roblox services; tests/test_retention.luau drives them).
-- The server (src/server/RetentionService.luau) owns the state in the profile (`Retention`) and decides every reward;
-- clients only see Retention.view and send intents ("Starter", "Gift").
--
-- Every reward here is in-game COINS or a pet rolled by the server, never Robux, and nothing here changes which egg
-- hides the hunt pet or who finds it.
--
--   Starter egg   one free egg near the lobby spawn; its pet is always Rare or better (never the 1 in 1000 chase pet).
--   Play gifts    free gifts after 1, 3, 5 and 10 minutes of play each UTC day (a timer shows the next one).
--   Away nest     coming back after a while: eggs "hatched while you were away" pay coins (and a Common pet after a
--                 long break); a big welcome-back gift after several days away.
--   Friend gift   a Roblox friend in the same server: coins once per friend per day (a few friends a day).
--   Group gift    members of the owner's Roblox group get a daily coin gift (off until the owner sets GroupId).

local PopupRules = require(script.Parent.PopupRules)

local Retention = {}

Retention.Starter = {
	Tier = "Gravel", -- the first zone (Meadow)
	-- Rare or better, never Legendary (the zone's Legendary is its 1 in 1000 chase pet; it must stay the dream)
	Weights = { Rare = 85, Epic = 15 } :: { [string]: number },
}

Retention.PlayGifts = {
	Marks = { 60, 180, 300, 600 }, -- seconds played today
	Coins = { 50, 100, 150, 400 },
	TickMax = 15, -- a single play-time tick never adds more than this (a stalled server cannot jump the clock)
}

Retention.Away = {
	MinSeconds = 30 * 60, -- shorter breaks are not "away"
	HoursCap = 12, -- coins stop growing after this many hours
	EggEverySeconds = 4 * 3600, -- one nest egg hatches per 4 hours away (at least one once away counts)
	MaxEggs = 3,
	CoinsPerEgg = 60,
	PetAfterSeconds = 8 * 3600, -- a long break (8 h+) also hatches one Common pet
	WelcomeBackSeconds = 3 * 86400, -- 3 days or more away
	WelcomeBackCoins = 500,
}

Retention.Friend = { Coins = 50, MaxPerDay = 3 }

-- REPLACE: the owner's Roblox group id (Creator Dashboard / roblox.com/groups/<id>). 0 = the group gift is off.
Retention.Group = { Id = 0, Coins = 100 }

-- Daily streak extras on top of ProgressConfig.DailyGift (shared/Quests applies them):
--   every full week of streak adds WeekBonus to the gift multiplier (up to MaxMult), and every ShieldEvery streak
--   days earn one streak shield (up to MaxShields). A shield is used up to save the streak after one missed day.
Retention.Streak = { WeekBonus = 0.25, MaxMult = 2, ShieldEvery = 7, MaxShields = 1 }

export type PlayState = { Day: number, Seconds: number, Claimed: number }
export type FriendState = { Day: number, Ids: { number } }
export type State = {
	LastSeen: number, -- os.time the player was last seen in a server (saved with the profile)
	Play: PlayState,
	Friend: FriendState,
	GroupDay: number, -- last UTC day the group gift was paid
}

local function num(v: any, default: number): number
	local n = tonumber(v)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return default
	end
	return n
end

function Retention.day(unixTime: number): number
	return math.floor(unixTime / 86400)
end

function Retention.empty(): State
	return {
		LastSeen = 0,
		Play = { Day = 0, Seconds = 0, Claimed = 0 },
		Friend = { Day = 0, Ids = {} },
		GroupDay = 0,
	}
end

-- Repairs a stored State (old save, hand edit) in place and returns it. Never invents progress.
function Retention.sanitize(s: any): State
	if type(s) ~= "table" then
		return Retention.empty()
	end
	s.LastSeen = math.max(0, math.floor(num(s.LastSeen, 0)))
	if type(s.Play) ~= "table" then
		s.Play = { Day = 0, Seconds = 0, Claimed = 0 }
	end
	s.Play.Day = math.floor(num(s.Play.Day, 0))
	s.Play.Seconds = math.max(0, num(s.Play.Seconds, 0))
	s.Play.Claimed = math.clamp(math.floor(num(s.Play.Claimed, 0)), 0, #Retention.PlayGifts.Marks)
	if type(s.Friend) ~= "table" then
		s.Friend = { Day = 0, Ids = {} }
	end
	s.Friend.Day = math.floor(num(s.Friend.Day, 0))
	if type(s.Friend.Ids) ~= "table" then
		s.Friend.Ids = {}
	end
	local ids = {}
	for _, id in s.Friend.Ids do
		if type(id) == "number" and #ids < Retention.Friend.MaxPerDay then
			table.insert(ids, id)
		end
	end
	s.Friend.Ids = ids
	s.GroupDay = math.floor(num(s.GroupDay, 0))
	return s :: State
end

-- Play gifts ------------------------------------------------------------------------------------

local function rollPlay(p: PlayState, today: number)
	if p.Day ~= today then
		p.Day = today
		p.Seconds = 0
		p.Claimed = 0
	end
end

-- Adds `dt` seconds of play on `today` (clamped per tick). Returns true when a gift just became ready.
function Retention.tickPlay(s: State, today: number, dt: number): boolean
	local p = s.Play
	rollPlay(p, today)
	local before = Retention.readyGifts(s, today)
	p.Seconds += math.clamp(num(dt, 0), 0, Retention.PlayGifts.TickMax)
	return Retention.readyGifts(s, today) > before
end

-- How many play gifts are earned and not claimed yet.
function Retention.readyGifts(s: State, today: number): number
	local p = s.Play
	if p.Day ~= today then
		return 0
	end
	local earned = 0
	for _, mark in Retention.PlayGifts.Marks do
		if p.Seconds >= mark then
			earned += 1
		end
	end
	return math.max(0, earned - p.Claimed)
end

-- The next gift: (index, seconds until it is ready; 0 = ready now) or nil when every gift today is claimed.
function Retention.nextGift(s: State, today: number): (number?, number)
	local p = s.Play
	local claimed = if p.Day == today then p.Claimed else 0
	local secs = if p.Day == today then p.Seconds else 0
	local i = claimed + 1
	local mark = Retention.PlayGifts.Marks[i]
	if not mark then
		return nil, 0
	end
	return i, math.max(0, math.ceil(mark - secs))
end

-- Claims the oldest ready gift. Returns (coins, index, nil) or (nil, nil, reason).
function Retention.claimGift(s: State, today: number): (number?, number?, string?)
	rollPlay(s.Play, today)
	local i, left = Retention.nextGift(s, today)
	if not i then
		return nil, nil, "AllClaimed"
	end
	if left > 0 then
		return nil, nil, "NotYet"
	end
	s.Play.Claimed = i
	return Retention.PlayGifts.Coins[i], i, nil
end

-- Away nest -------------------------------------------------------------------------------------

export type AwayReward = { Seconds: number, Eggs: number, Coins: number, Pet: boolean, WelcomeBack: boolean }

-- What a player gets for coming back at `now` after last being seen at `lastSeen` (0 = brand new: nothing).
-- nil when the break is too short (or the clock went backwards).
function Retention.away(lastSeen: number, now: number): AwayReward?
	local a = Retention.Away
	if lastSeen <= 0 then
		return nil
	end
	local gone = now - lastSeen
	if gone < a.MinSeconds then
		return nil
	end
	local capped = math.min(gone, a.HoursCap * 3600)
	local eggs = math.clamp(math.floor(capped / a.EggEverySeconds), 1, a.MaxEggs)
	local welcome = gone >= a.WelcomeBackSeconds
	return {
		Seconds = gone,
		Eggs = eggs,
		Coins = eggs * a.CoinsPerEgg + (if welcome then a.WelcomeBackCoins else 0),
		Pet = gone >= a.PetAfterSeconds,
		WelcomeBack = welcome,
	}
end

-- Friend + group gifts --------------------------------------------------------------------------

-- Pays the friend gift for `friendId` on `today` if this friend was not paid today and the daily cap is not reached.
-- Returns the coins (0 = nothing).
function Retention.friendGift(s: State, today: number, friendId: number): number
	local f = s.Friend
	if f.Day ~= today then
		f.Day = today
		f.Ids = {}
	end
	if table.find(f.Ids, friendId) or #f.Ids >= Retention.Friend.MaxPerDay then
		return 0
	end
	table.insert(f.Ids, friendId)
	return Retention.Friend.Coins
end

-- Pays the group gift once per day when the group gift is on and the player is a member. Returns the coins.
function Retention.groupGift(s: State, today: number, member: boolean): number
	if Retention.Group.Id == 0 or not member or s.GroupDay >= today then
		return 0
	end
	s.GroupDay = today
	return Retention.Group.Coins
end

-- Streak extras (used by shared/Quests) ---------------------------------------------------------

-- Gift multiplier for a streak of `streak` days (week 1 = 1x, week 2 = 1.25x, ... up to MaxMult).
function Retention.streakMult(streak: number): number
	local st = Retention.Streak
	local weeks = math.max(0, math.floor((math.max(streak, 1) - 1) / 7))
	return math.min(st.MaxMult, 1 + weeks * st.WeekBonus)
end

-- Hunter level (a level-up pop for the first minutes; shown only, nothing is bought with it) -----------------
-- XP comes from what the player already did (profile Stats): eggs cracked, hunts played, pets found.
Retention.Level = { PerCrack = 1, PerHunt = 10, PerFind = 20, Step = 25 }

function Retention.xp(stats: any): number
	local l = Retention.Level
	if type(stats) ~= "table" then
		return 0
	end
	local finds = num(stats.SoloFinds, 0) + num(stats.MultiplayerWins, 0)
	return math.max(0, math.floor(num(stats.RocksCracked, 0) * l.PerCrack + num(stats.MatchesPlayed, 0) * l.PerHunt + finds * l.PerFind))
end

-- XP needed to reach `level` (level 1 = 0; each level asks Step more than the one before: 25, 75, 150, ...).
function Retention.levelXp(level: number): number
	local n = math.max(0, level - 1)
	return Retention.Level.Step * n * (n + 1) / 2
end

-- (level, xp into this level, xp this level needs) for `xp`.
function Retention.level(xp: number): (number, number, number)
	local lv = 1
	while Retention.levelXp(lv + 1) <= xp and lv < 999 do
		lv += 1
	end
	local from = Retention.levelXp(lv)
	return lv, xp - from, Retention.levelXp(lv + 1) - from
end

-- The dream (the "next goal" card after the first hatch) ------------------------------------------------------
-- The strongest a Void Dragon can get: Legendary, the best variant, the best roll, the top level (TowerConfig), so
-- the card's "Void Dragon: power N" is a real number from the same rules the tower fights with.
Retention.DreamSpecies = "CosmicDragon" -- "Void Dragon", the 1 in 1000 chase pet
-- Where the dream pet comes from, shown on the lobby statue (audit F22: the sign said "1 in 1000" but not where to
-- get it). The Space zone's Legendary hatch is always its chase pet; Legendary is 0.1% before luck boosts.
Retention.DreamZone = "Meteor" -- Config.Tiers id (shown as "Space")
Retention.DreamSource = "Hatch it from SPACE zone eggs!"
Retention.DreamHint = "The rarest pet. Base odds: 1 in 1000 Space zone eggs. Luck boosts raise it!"

function Retention.dreamPower(): number
	local TowerConfig = require(script.Parent.TowerConfig)
	local base = TowerConfig.Species[Retention.DreamSpecies] or TowerConfig.DefaultSpecies
	local bestVariant = 1
	for _, v in TowerConfig.VariantStat do
		bestVariant = math.max(bestVariant, v)
	end
	local grow = 1 + TowerConfig.Levels.LevelStat * (TowerConfig.Levels.Max - 1)
	return math.floor(base.Power * TowerConfig.RollMax * (TowerConfig.RarityStat.Legendary or 1) * bestVariant * grow + 0.5)
end

-- How far `power` is toward the dream, 0..1 (square root, so a first pet shows a sliver, not an empty bar).
function Retention.dreamProgress(power: number): number
	local dream = Retention.dreamPower()
	if dream <= 0 then
		return 1
	end
	return math.clamp(math.sqrt(math.max(0, power) / dream), 0, 1)
end

-- Client view -----------------------------------------------------------------------------------

export type View = { NextGift: number?, NextIn: number, Ready: number, GiftCoins: number?, Marks: { number }, Coins: { number } }

function Retention.view(s: State, today: number): View
	local i, left = Retention.nextGift(s, today)
	return {
		NextGift = i,
		NextIn = left,
		Ready = Retention.readyGifts(s, today),
		GiftCoins = if i then Retention.PlayGifts.Coins[i] else nil,
		Marks = table.clone(Retention.PlayGifts.Marks),
		Coins = table.clone(Retention.PlayGifts.Coins),
	}
end

-- Big welcome cards (NEXT GOAL, away nest) wait for a calm moment: never over a hunt, a tower climb or a Pet Battle
-- (Studio 2026-10-14: the NEXT GOAL card covered a fight). `busy` = the player's MatchKey / InTower / InBattle
-- attributes and whether a hunt round is open on the client.
-- One rule with every other popup: PopupRules (Card).
function Retention.calm(busy: { MatchKey: any?, InTower: any?, InBattle: any?, Match: any?, Held: boolean?, Shown: boolean? }): boolean
	return PopupRules.free("Card", busy)
end

-- FIRST PET RULE: a player's first pet only ever comes from their first hatch (the starter egg). Any pet that is given
-- for free (the away nest's Common pet, the Studio dev auto pet, DevPets.server attribute DevAutoPet) waits until
-- the save has hatched its starter egg, so a fresh save always sees "YOUR FIRST PET!" on its own hatch and never a
-- "New in your Pet Book" toast on join (walkthrough 2026-10-14 #1).
function Retention.freePetReady(data: any): boolean
	return type(data) == "table" and data.StarterPet == true
end

return Retention
