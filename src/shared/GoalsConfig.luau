--!strict
-- Long goals: the streak ladder (coin looks earned by best heads-in-a-row), weekly challenges
-- and the coin book (find every rare coin). All plain counts, no random rewards anywhere.
-- Prizes are "flips" (cash = flips x your cash per heads) and hat points, like the daily gift.

export type LadderRung = {
	id: string,
	name: string,
	icon: string,
	need: number, -- best heads in a row that earns this coin look
	coin: Color3,
	text: Color3,
}

export type ChallengeKind = {
	kind: string, -- what the server counts: flip, heads, mega, buy, rare, streak
	text: string, -- %d = the goal
	goal: number,
	flips: number,
	hats: number,
}

export type BookReward = { flips: number, hats: number }

-- In order. A rung is yours for good once your best streak reaches `need` (the best streak only
-- ever goes up, so a skull never takes a look away). Top rung = the 10-heads streak goal.
local Ladder: { LadderRung } = {
	{
		id = "bronze",
		name = "Bronze Streak",
		icon = "🥉",
		need = 3,
		coin = Color3.fromRGB(205, 140, 80),
		text = Color3.fromRGB(255, 240, 210),
	},
	{
		id = "pearl",
		name = "Pearl Streak",
		icon = "🫧",
		need = 5,
		coin = Color3.fromRGB(240, 235, 255),
		text = Color3.fromRGB(120, 100, 190),
	},
	{
		id = "neon",
		name = "Neon Streak",
		icon = "⚡",
		need = 7,
		coin = Color3.fromRGB(80, 255, 170),
		text = Color3.fromRGB(20, 70, 60),
	},
	{
		id = "crown",
		name = "Crown Coins",
		icon = "👑",
		need = 10,
		coin = Color3.fromRGB(255, 200, 40),
		text = Color3.fromRGB(150, 60, 200),
	},
}

-- Six weekly goals. Each week the whole server gets 3 of them in a row, moving along by one every
-- week, so every kind comes round. Same for everyone, no dice.
local Challenges: { ChallengeKind } = {
	{ kind = "flip", text = "Flip %d coins", goal = 400, flips = 120, hats = 8 },
	{ kind = "heads", text = "Get %d heads", goal = 250, flips = 100, hats = 8 },
	{ kind = "mega", text = "Help flip the MEGA coin %d times", goal = 5, flips = 150, hats = 10 },
	{ kind = "buy", text = "Buy %d upgrades", goal = 15, flips = 100, hats = 6 },
	{ kind = "rare", text = "Flip %d rare coins", goal = 3, flips = 200, hats = 12 },
	{ kind = "streak", text = "Hit the 10 heads streak %d time", goal = 1, flips = 250, hats = 15 },
}

-- One prize per rare coin the first time you flip it, plus a big one for a full book.
local Book = {
	rewards = {
		silver = { flips = 5, hats = 1 },
		gold = { flips = 20, hats = 3 },
		rainbow = { flips = 100, hats = 10 },
		giant = { flips = 500, hats = 50 },
	} :: { [string]: BookReward },
	complete = { flips = 1000, hats = 100 } :: BookReward,
}

return table.freeze({
	Ladder = table.freeze(Ladder),
	Challenges = table.freeze(Challenges),
	CHALLENGES_PER_WEEK = 3,
	CHALLENGE_BONUS = table.freeze({ flips = 300, hats = 25 }) :: BookReward, -- all 3 claimed
	Book = table.freeze(Book),
	CLAIM_RATE = 3, -- claims / ladder swaps per second per player (token bucket)
	CLAIM_BURST = 5,
})
