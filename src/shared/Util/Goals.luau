--!strict
-- Streak ladder, weekly challenges and the coin book as pure rules (no Roblox services;
-- tests/specs/Goals.spec.luau drives them). The server (Systems/Goals) owns the state in the profile
-- and pays every prize; the client only sees `Goals.view` and sends claim / wear intents.
-- Nothing here rolls dice: every prize is a fixed amount for a plain goal.

local Config = require(script.Parent.Parent.Config)
local GoalsConfig = require(script.Parent.Parent.GoalsConfig)
local Types = require(script.Parent.Parent.Types)

type Profile = Types.Profile
type ChallengeState = Types.ChallengeState
type BookState = Types.BookState

local Goals = {}

export type Reward = { flips: number, hats: number }

local SLOTS = GoalsConfig.CHALLENGES_PER_WEEK

local function num(value: unknown, default: number): number
	if typeof(value) == "number" and value == value and value > -math.huge and value < math.huge then
		return value
	end
	return default
end

local function count(value: unknown): number
	return math.max(0, math.floor(num(value, 0)))
end

-- Heads-worth prize -> cash at the player's current cash per heads.
function Goals.cash(reward: Reward, cashPerHeads: number): number
	return reward.flips * math.max(1, cashPerHeads)
end

----------------------------------------------------------------------------------------------------
-- Streak ladder
----------------------------------------------------------------------------------------------------

function Goals.rung(id: unknown): GoalsConfig.LadderRung?
	for _, def in GoalsConfig.Ladder do
		if def.id == id then
			return def
		end
	end
	return nil
end

function Goals.ownsRung(profile: Profile, id: unknown): boolean
	local def = Goals.rung(id)
	return def ~= nil and profile.stats.bestStreak >= def.need
end

-- How many rungs the best streak has reached (the server compares this to tell "new look!").
function Goals.rungsOwned(profile: Profile): number
	local n = 0
	for _, def in GoalsConfig.Ladder do
		if profile.stats.bestStreak >= def.need then
			n += 1
		end
	end
	return n
end

-- Wear a ladder look ("" = take it off). Only rungs you reached. Wearing one puts the Robux skin
-- away, so exactly one coin look shows. Returns true when it changed.
function Goals.wearRung(profile: Profile, id: unknown): boolean
	if id == "" then
		profile.ladderSkin = ""
		return true
	end
	if not Goals.ownsRung(profile, id) then
		return false
	end
	profile.ladderSkin = id :: string
	profile.skin = ""
	return true
end

----------------------------------------------------------------------------------------------------
-- Weekly challenges
----------------------------------------------------------------------------------------------------

function Goals.week(unixTime: number): number
	-- Day 0 (1 Jan 1970) was a Thursday, so +3 starts every week on a Monday.
	return math.floor((math.floor(unixTime / 86400) + 3) / 7)
end

-- Seconds left until the next Monday 00:00 UTC.
function Goals.secondsLeft(unixTime: number): number
	local nextWeekStart = ((Goals.week(unixTime) + 1) * 7 - 3) * 86400
	return math.max(0, nextWeekStart - math.floor(unixTime))
end

function Goals.emptyChallenges(): ChallengeState
	local progress, claimed = {}, {}
	for i = 1, SLOTS do
		progress[i] = 0
		claimed[i] = false
	end
	return { week = 0, progress = progress, claimed = claimed, bonusClaimed = false }
end

export type Challenge = { slot: number, kind: string, goal: number, flips: number, hats: number, text: string }

-- This week's challenges: the same for every player and every server.
function Goals.challengesFor(week: number): { Challenge }
	local pool = GoalsConfig.Challenges
	local list: { Challenge } = {}
	for slot = 1, SLOTS do
		local def = pool[(week + slot - 1) % #pool + 1]
		table.insert(list, {
			slot = slot,
			kind = def.kind,
			goal = def.goal,
			flips = def.flips,
			hats = def.hats,
			text = string.format(def.text, def.goal),
		})
	end
	return list
end

-- A clean ChallengeState from anything saved. Never invents progress or claims.
function Goals.sanitizeChallenges(raw: unknown): ChallengeState
	local c = Goals.emptyChallenges()
	if typeof(raw) ~= "table" then
		return c
	end
	local t = raw :: { [string]: any }
	c.week = count(t.week)
	local progress = if typeof(t.progress) == "table" then t.progress else {}
	local claimed = if typeof(t.claimed) == "table" then t.claimed else {}
	for i = 1, SLOTS do
		c.progress[i] = count(progress[i])
		c.claimed[i] = claimed[i] == true
	end
	c.bonusClaimed = t.bonusClaimed == true
	return c
end

-- Moves the state to `week` (fresh progress on a new week). True when it changed.
function Goals.rolloverChallenges(c: ChallengeState, week: number): boolean
	if c.week == week then
		return false
	end
	c.week = week
	for i = 1, SLOTS do
		c.progress[i] = 0
		c.claimed[i] = false
	end
	c.bonusClaimed = false
	return true
end

-- Counts `n` toward every unfinished challenge of `kind` this week. True when anything changed.
function Goals.bumpChallenge(c: ChallengeState, week: number, kind: string, n: number?): boolean
	local add = if n == nil then 1 else math.floor(num(n, 0))
	if add <= 0 then
		return false
	end
	local changed = Goals.rolloverChallenges(c, week)
	for i, ch in Goals.challengesFor(week) do
		if ch.kind == kind and not c.claimed[i] and c.progress[i] < ch.goal then
			c.progress[i] = math.min(ch.goal, c.progress[i] + add)
			changed = true
		end
	end
	return changed
end

-- Claims challenge `slot`. Returns (reward, nil) or (nil, reason). Each one pays once a week.
function Goals.claimChallenge(c: ChallengeState, week: number, slot: unknown): (Reward?, string?)
	Goals.rolloverChallenges(c, week)
	if typeof(slot) ~= "number" or slot ~= slot or slot % 1 ~= 0 then
		return nil, "BadSlot"
	end
	local ch = Goals.challengesFor(week)[slot]
	if not ch then
		return nil, "BadSlot"
	end
	if c.claimed[slot] then
		return nil, "Claimed"
	end
	if c.progress[slot] < ch.goal then
		return nil, "NotDone"
	end
	c.claimed[slot] = true
	return { flips = ch.flips, hats = ch.hats }, nil
end

-- The extra prize once all three are claimed. Once a week.
function Goals.claimChallengeBonus(c: ChallengeState, week: number): (Reward?, string?)
	Goals.rolloverChallenges(c, week)
	if c.bonusClaimed then
		return nil, "Claimed"
	end
	for i = 1, SLOTS do
		if not c.claimed[i] then
			return nil, "NotDone"
		end
	end
	c.bonusClaimed = true
	local bonus = GoalsConfig.CHALLENGE_BONUS
	return { flips = bonus.flips, hats = bonus.hats }, nil
end

----------------------------------------------------------------------------------------------------
-- Coin book
----------------------------------------------------------------------------------------------------

function Goals.emptyBook(): BookState
	return { found = {}, paid = {} }
end

local function isRarityId(id: unknown): boolean
	for _, def in Config.Rarities do
		if def.id == id then
			return true
		end
	end
	return false
end

-- A clean BookState: known rare coins only, counts >= 1, prizes paid only where it was found.
function Goals.sanitizeBook(raw: unknown): BookState
	local b = Goals.emptyBook()
	if typeof(raw) ~= "table" then
		return b
	end
	local t = raw :: { [string]: any }
	if typeof(t.found) == "table" then
		for id, n in t.found :: { [any]: any } do
			if isRarityId(id) and count(n) >= 1 then
				b.found[id] = count(n)
			end
		end
	end
	if typeof(t.paid) == "table" then
		for id, paid in t.paid :: { [any]: any } do
			if paid == true and b.found[id] then
				b.paid[id] = true
			end
		end
	end
	if typeof(t.paid) == "table" and (t.paid :: any).all == true and Goals.bookComplete(b) then
		b.paid.all = true
	end
	return b
end

function Goals.bookFound(b: BookState): number
	local n = 0
	for _, def in Config.Rarities do
		if b.found[def.id] then
			n += 1
		end
	end
	return n
end

function Goals.bookComplete(b: BookState): boolean
	return Goals.bookFound(b) == #Config.Rarities
end

-- A coin of `rarity` was flipped (heads or skull, any of your flips). Counts it and returns the
-- prizes that just became due: (first-find prize or nil, full-book prize or nil). Each pays once.
function Goals.recordRare(b: BookState, rarity: unknown): (Reward?, Reward?)
	if not isRarityId(rarity) then
		return nil, nil -- "normal" coins are not in the book
	end
	local id = rarity :: string
	b.found[id] = (b.found[id] or 0) + 1
	local page: Reward? = nil
	if not b.paid[id] then
		b.paid[id] = true
		local r = GoalsConfig.Book.rewards[id]
		if r then
			page = { flips = r.flips, hats = r.hats }
		end
	end
	local all: Reward? = nil
	if not b.paid.all and Goals.bookComplete(b) then
		b.paid.all = true
		local r = GoalsConfig.Book.complete
		all = { flips = r.flips, hats = r.hats }
	end
	return page, all
end

----------------------------------------------------------------------------------------------------
-- What the client draws
----------------------------------------------------------------------------------------------------

export type RungView = { id: string, name: string, icon: string, need: number, owned: boolean, worn: boolean }
export type ChallengeView = {
	slot: number,
	text: string,
	kind: string,
	goal: number,
	progress: number,
	done: boolean,
	claimed: boolean,
	cash: number,
	hats: number,
}
export type PageView = {
	id: string,
	name: string,
	found: boolean,
	count: number,
	cash: number, -- first-find prize
	hats: number,
	paid: boolean,
}
export type GoalsView = {
	ladder: { rungs: { RungView }, best: number, nextNeed: number, worn: string }, -- nextNeed 0 = top rung reached
	challenges: {
		items: { ChallengeView },
		claimable: number,
		secondsLeft: number,
		bonus: { cash: number, hats: number, ready: boolean, claimed: boolean },
	},
	book: {
		pages: { PageView },
		found: number,
		total: number,
		complete: boolean,
		bonusCash: number,
		bonusHats: number,
		bonusPaid: boolean,
	},
}

function Goals.view(profile: Profile, unixTime: number, cashPerHeads: number): GoalsView
	local week = Goals.week(unixTime)

	local rungs: { RungView } = {}
	local nextNeed = 0
	for _, def in GoalsConfig.Ladder do
		local owned = profile.stats.bestStreak >= def.need
		if not owned and nextNeed == 0 then
			nextNeed = def.need
		end
		table.insert(rungs, {
			id = def.id,
			name = def.name,
			icon = def.icon,
			need = def.need,
			owned = owned,
			worn = owned and profile.ladderSkin == def.id,
		})
	end

	local state = profile.challenges
	local fresh = state.week ~= week
	local items: { ChallengeView } = {}
	local claimable, claimedAll = 0, true
	for i, ch in Goals.challengesFor(week) do
		local progress = if fresh then 0 else math.min(ch.goal, state.progress[i] or 0)
		local claimed = not fresh and state.claimed[i] == true
		local done = progress >= ch.goal
		if done and not claimed then
			claimable += 1
		end
		if not claimed then
			claimedAll = false
		end
		table.insert(items, {
			slot = i,
			text = ch.text,
			kind = ch.kind,
			goal = ch.goal,
			progress = progress,
			done = done,
			claimed = claimed,
			cash = Goals.cash(ch, cashPerHeads),
			hats = ch.hats,
		})
	end
	local bonus = GoalsConfig.CHALLENGE_BONUS
	local bonusClaimed = not fresh and state.bonusClaimed

	local pages: { PageView } = {}
	local book = profile.book
	-- Config lists the rarest first; the book reads easiest first.
	for i = #Config.Rarities, 1, -1 do
		local def = Config.Rarities[i]
		local r = GoalsConfig.Book.rewards[def.id] or { flips = 0, hats = 0 }
		table.insert(pages, {
			id = def.id,
			name = def.name,
			found = book.found[def.id] ~= nil,
			count = book.found[def.id] or 0,
			cash = Goals.cash(r, cashPerHeads),
			hats = r.hats,
			paid = book.paid[def.id] == true,
		})
	end
	local all = GoalsConfig.Book.complete

	return {
		ladder = { rungs = rungs, best = profile.stats.bestStreak, nextNeed = nextNeed, worn = profile.ladderSkin },
		challenges = {
			items = items,
			claimable = claimable,
			secondsLeft = Goals.secondsLeft(unixTime),
			bonus = {
				cash = Goals.cash(bonus, cashPerHeads),
				hats = bonus.hats,
				ready = claimedAll and not bonusClaimed,
				claimed = bonusClaimed,
			},
		},
		book = {
			pages = pages,
			found = Goals.bookFound(book),
			total = #Config.Rarities,
			complete = Goals.bookComplete(book),
			bonusCash = Goals.cash(all, cashPerHeads),
			bonusHats = all.hats,
			bonusPaid = book.paid.all == true,
		},
	}
end

return Goals
