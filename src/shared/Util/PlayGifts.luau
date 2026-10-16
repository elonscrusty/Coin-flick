--!strict
-- Play-time gifts as pure rules (tests/specs/PlayGifts.spec.luau). Stay in the game and gifts become
-- ready at 5, 15, 30 and 60 minutes. The server owns the state in profile.play and pays the rewards;
-- the client only sees PlayGifts.view and sends "claim gift N".
--
-- Nothing is ever taken away: seconds restart every UTC day, but a gift that was reached and not
-- claimed becomes `owed` and waits until it is claimed.

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)
local Daily = require(script.Parent.Daily)

type PlayState = Types.PlayState
type PlayGiftView = Types.PlayGiftView

local PlayGifts = {}

local GIFTS = Config.PlayGifts.Gifts
local COUNT = #GIFTS

function PlayGifts.empty(): PlayState
	local claimed, owed = {}, {}
	for i = 1, COUNT do
		claimed[i] = false
		owed[i] = false
	end
	return { day = 0, seconds = 0, claimed = claimed, owed = owed }
end

local function num(value: unknown): number
	if typeof(value) == "number" and value == value and value > -math.huge and value < math.huge then
		return value
	end
	return 0
end

-- A clean PlayState from anything saved. Never invents time or gifts.
function PlayGifts.sanitize(raw: unknown): PlayState
	local s = PlayGifts.empty()
	if typeof(raw) ~= "table" then
		return s
	end
	local t = raw :: { [string]: any }
	s.day = math.max(0, math.floor(num(t.day)))
	-- never more than a full day of play
	s.seconds = math.clamp(math.floor(num(t.seconds)), 0, 86400)
	local claimed = if typeof(t.claimed) == "table" then t.claimed else {}
	local owed = if typeof(t.owed) == "table" then t.owed else {}
	for i = 1, COUNT do
		s.claimed[i] = claimed[i] == true
		s.owed[i] = owed[i] == true and not s.claimed[i]
	end
	return s
end

local function reached(s: PlayState, slot: number): boolean
	return s.seconds >= GIFTS[slot].minutes * 60
end

-- Moves to `today`. Gifts reached but not claimed yesterday stay owed. True when it changed.
function PlayGifts.rollover(s: PlayState, today: number): boolean
	if s.day == today then
		return false
	end
	if s.day < today then
		for i = 1, COUNT do
			if not s.claimed[i] and reached(s, i) then
				s.owed[i] = true
			end
		end
		s.seconds = 0
		for i = 1, COUNT do
			s.claimed[i] = false
		end
	end
	-- s.day > today: the saving server's clock ran ahead. Keep everything, just wait.
	s.day = today
	return true
end

-- Adds played seconds (clamped to Config.PlayGifts.MAX_STEP per call). True when anything changed.
function PlayGifts.add(s: PlayState, today: number, seconds: number): boolean
	local changed = PlayGifts.rollover(s, today)
	local add = math.clamp(math.floor(num(seconds)), 0, Config.PlayGifts.MAX_STEP)
	if add > 0 and s.seconds < 86400 then
		s.seconds = math.min(86400, s.seconds + add)
		changed = true
	end
	return changed
end

-- Claims gift `slot`. Returns (reward, nil) or (nil, reason). Owed gifts are paid first.
function PlayGifts.claim(s: PlayState, today: number, slot: unknown): (Daily.Reward?, string?)
	PlayGifts.rollover(s, today)
	if typeof(slot) ~= "number" or slot ~= slot or slot % 1 ~= 0 or slot < 1 or slot > COUNT then
		return nil, "BadGift"
	end
	local def = GIFTS[slot]
	if s.owed[slot] then
		s.owed[slot] = false
		return { flips = def.flips, hats = def.hats }, nil
	end
	if s.claimed[slot] then
		return nil, "Claimed"
	end
	if not reached(s, slot) then
		return nil, "NotYet"
	end
	s.claimed[slot] = true
	return { flips = def.flips, hats = def.hats }, nil
end

function PlayGifts.claimable(s: PlayState): number
	local n = 0
	for i = 1, COUNT do
		if s.owed[i] or (not s.claimed[i] and reached(s, i)) then
			n += 1
		end
	end
	return n
end

-- What the client draws. cashPerHeads turns "flips" into cash.
function PlayGifts.view(s: PlayState, today: number, cashPerHeads: number): PlayGiftView
	local fresh = s.day ~= today
	local gifts = {}
	local claimable = 0
	for i, def in GIFTS do
		local seconds = if fresh then 0 else s.seconds
		local owed = s.owed[i] == true
		local claimed = not fresh and s.claimed[i] == true
		local state = "waiting"
		-- Owed, or reached yesterday and not claimed (becomes owed on the next tick).
		if owed or (fresh and not s.claimed[i] and reached(s, i)) then
			state = "ready"
		elseif claimed then
			state = "claimed"
		elseif seconds >= def.minutes * 60 then
			state = "ready"
		end
		if state == "ready" then
			claimable += 1
		end
		table.insert(gifts, {
			slot = i,
			minutes = def.minutes,
			cash = Daily.cash(def, cashPerHeads),
			hats = def.hats,
			state = state,
			left = if state == "waiting" then def.minutes * 60 - seconds else 0,
		})
	end
	return { seconds = if fresh then 0 else s.seconds, gifts = gifts, claimable = claimable }
end

return PlayGifts
