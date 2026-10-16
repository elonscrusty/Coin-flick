--!strict
-- Types that cross the client/server boundary or get saved.

export type UpgradeId = "moreCoins" | "bigCoins" | "luck" | "speed" | "multiFlip"

export type Upgrades = {
	moreCoins: number,
	bigCoins: number,
	luck: number,
	speed: number,
	multiFlip: number,
}

export type Stats = {
	flips: number,
	heads: number,
	skulls: number,
	biggestFlip: number,
	bestCombo: number,
	rares: number,
	bestStreak: number, -- most heads in a row
	streakWins: number, -- times you hit the streak goal
}

-- Saved player data. Plain JSON-friendly values only.
export type Profile = {
	version: number,
	cash: number,
	hatPoints: number,
	upgrades: Upgrades,
	crew: { [string]: number }, -- helper id -> level, for every helper you own
	team: { string }, -- helper ids working at your table (up to your slots)
	resets: number,
	stats: Stats,
	lastSeen: number, -- os.time() of the last save, for the offline bonus
	hats: { [string]: boolean }, -- owned hat ids
	hat: string, -- worn hat id, "" = none
	skin: string, -- chosen coin skin id, "" = classic gold
	helperSlots: number, -- extra helper slots bought with Robux
	receipts: { string }, -- recent Robux purchase ids, so one is never granted twice
}

export type FlipResult = "heads" | "skull"

export type Rarity = "normal" | "silver" | "gold" | "rainbow" | "giant"

-- Server -> all clients when any coin flips.
export type FlipEvent = {
	ownerId: number,
	coin: number,
	result: FlipResult,
	cash: number,
	hats: number,
	duration: number,
	byHelper: boolean,
	helper: string?, -- which helper flipped it
	rarity: Rarity,
	combo: number, -- 0 for helper/auto flips
	streak: number, -- heads in a row after this flip (0 for helper flips and skulls)
	streakWin: boolean, -- true when this flip hit the streak goal
	streakCash: number, -- prize paid on a streak win
	streakHats: number,
}

-- Server -> one client: everything the HUD needs.
export type Snapshot = {
	cash: number,
	hatPoints: number,
	upgrades: Upgrades,
	crew: { [string]: number },
	team: { string },
	resets: number,
	flips: number,
	biggestFlip: number,
	coinCount: number,
	tableFull: boolean,
	cashPerHeads: number,
	headsChance: number,
	resetBonus: number,
	bestCombo: number,
	bestStreak: number,
	streakGoal: number,
	flipsPerTap: number,
	hats: { string }, -- owned hat ids
	hat: string,
	skin: string,
	maxHelpers: number,
	helperSlots: number, -- extra slots bought with Robux
	passes: { [string]: boolean }, -- "doubleCash", "autoFlip", and skin ids
}

-- Server -> all clients: the shared mega coin.
export type MegaState = {
	taps: number,
	goal: number,
	boostLeft: number, -- seconds of server-wide 2x cash left
}

export type LeaderRow = { name: string, value: number }
export type Leaderboards = { [string]: { LeaderRow } }

-- Server -> one client: a short message ("bought", "reset", "offline").
export type Notice = {
	kind: string,
	text: string,
	rarity: Rarity?, -- set on "shout"
	ownerId: number?, -- who flipped it, on "shout"
}

return {}
