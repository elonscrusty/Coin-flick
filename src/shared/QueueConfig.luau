--!strict
-- Tuning for the public hunt queue (lobby portal / PLAY button) and the round extras that come with it
-- (bonus common pets for helpers, friends luck). Kept apart from Config so the queue can be tuned alone.

local QueueConfig = {}

-- Public queue: up to Size players per hunt; the hunt starts Seconds after the first player joins with whoever
-- is there (1..Size). A full queue starts at once when StartWhenFull is on. A joiner who does not fit starts the
-- next queue. When a start fails (all quarries busy, someone still spawning) the queue waits RetrySeconds and tries
-- again.
QueueConfig.Size = 4
QueueConfig.Seconds = 20
QueueConfig.StartWhenFull = true
QueueConfig.RetrySeconds = 5
-- Touching a portal pad more often than this does nothing (one join per touch burst).
QueueConfig.TouchDebounce = 1.5
-- After LEAVE, a player standing on a portal pad is not queued again until they are this many studs off every pad.
QueueConfig.PadClear = 4

-- Lobby queue board and pads (built by the lobby builder; all optional).
QueueConfig.Board = {
	Idle = "STEP ON TO PLAY",
	Counting = "HUNT IN %ds  (%d/%d)", -- seconds left, queued, size
	PadLit = Color3.fromRGB(110, 230, 120),
}

-- Non-finders who cracked at least MinCracked eggs in a round get a Chance (0..1) of a Common pet of that zone.
-- Not a win, not a find; never auto-follows. Practice rounds never roll it.
QueueConfig.Bonus = {
	MinCracked = 5,
	Chance = 0.05,
}

-- Friend bonus (owner pick): the finder gets PerFriend extra Luck for every Roblox friend of theirs in the same server
-- (lobby or hunt), counting at most MaxFriends (so +30% at most). Luck only lifts the odds of a Rare or better pet
-- (GeodeGen); it never changes which egg hides the pet or who finds it. Practice rounds get none.
QueueConfig.FriendLuck = {
	PerFriend = 0.10,
	MaxFriends = 3,
}

return QueueConfig
