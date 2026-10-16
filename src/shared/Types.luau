--!strict
-- Types that cross the client/server boundary or get saved.

export type UpgradeId = "moreCoins" | "bigCoins" | "luck" | "speed"

export type Upgrades = {
	moreCoins: number,
	bigCoins: number,
	luck: number,
	speed: number,
}

export type Stats = {
	flips: number,
	heads: number,
	skulls: number,
	biggestFlip: number,
	bestCombo: number,
	rares: number,
}

-- Daily gift + jobs, saved in the profile. Days are whole UTC days since 1970.
export type DailyState = {
	day: number, -- the day progress / claimed belong to (0 = never)
	progress: { number }, -- per job slot 1..3
	claimed: { boolean }, -- per job slot 1..3
	giftDay: number, -- last day the gift was claimed (0 = never)
	giftClaims: number, -- total gifts claimed; picks which of the 7 gift days is next
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
	daily: DailyState,
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

-- Server -> one client: today's gift and jobs (DailyState turned into something to draw).
export type DailyView = {
	day: number,
	nextReset: number, -- unix time the jobs and gift turn over (UTC midnight)
	gift: {
		ready: boolean,
		dayIndex: number, -- 1..7, the gift day ready now (or claimed today)
		flips: number, -- reward: heads worth of cash...
		cash: number, -- ...as cash at your current cash per heads
		hats: number,
		cycle: { { flips: number, hats: number } }, -- all 7 days, for the calendar
	},
	jobs: { { text: string, kind: string, goal: number, progress: number, cash: number, hats: number, done: boolean, claimed: boolean } },
	claimable: number, -- done jobs not claimed + 1 if the gift is ready (red dot)
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
