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
}

-- Saved player data. Plain JSON-friendly values only.
export type Profile = {
	version: number,
	cash: number,
	hatPoints: number,
	upgrades: Upgrades,
	helpers: number,
	resets: number,
	stats: Stats,
	lastSeen: number, -- os.time() of the last save, for the offline bonus
}

export type FlipResult = "heads" | "skull"

-- Server -> all clients when any coin flips.
export type FlipEvent = {
	ownerId: number,
	coin: number,
	result: FlipResult,
	cash: number,
	hats: number,
	duration: number,
	byHelper: boolean,
}

-- Server -> one client: everything the HUD needs.
export type Snapshot = {
	cash: number,
	hatPoints: number,
	upgrades: Upgrades,
	helpers: number,
	resets: number,
	flips: number,
	biggestFlip: number,
	coinCount: number,
	tableFull: boolean,
	cashPerHeads: number,
	headsChance: number,
	resetBonus: number,
}

-- Server -> one client: a short message ("bought", "reset", "offline").
export type Notice = {
	kind: string,
	text: string,
}

return {}
