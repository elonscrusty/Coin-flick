--!strict
-- Every gameplay number lives here so balancing touches one file.
-- NOTE: this is replicated to clients, so nothing secret goes here, and the
-- server never trusts a value a client sends back from it.

export type UpgradeDef = {
	name: string,
	icon: string,
	desc: string,
	baseCost: number,
	growth: number,
	maxLevel: number,
}

export type TableLook = {
	name: string,
	top: Color3,
	rim: Color3,
	legs: Color3,
}

local Upgrades: { [string]: UpgradeDef } = {
	moreCoins = {
		name = "More Coins",
		icon = "🪙",
		desc = "Put one more coin on your table",
		baseCost = 10,
		growth = 1.8,
		maxLevel = 9,
	},
	bigCoins = {
		name = "Bigger Coins",
		icon = "🔍",
		desc = "+50% cash every heads",
		baseCost = 30,
		growth = 1.8,
		maxLevel = 10,
	},
	luck = {
		name = "Lucky Heads",
		icon = "🍀",
		desc = "+3% chance to land heads",
		baseCost = 50,
		growth = 1.9,
		maxLevel = 10,
	},
	speed = {
		name = "Faster Flips",
		icon = "⚡",
		desc = "Coins land faster",
		baseCost = 40,
		growth = 1.75,
		maxLevel = 10,
	},
}

local TableLooks: { TableLook } = {
	{
		name = "Picnic Wood",
		top = Color3.fromRGB(214, 150, 86),
		rim = Color3.fromRGB(150, 96, 52),
		legs = Color3.fromRGB(120, 76, 42),
	},
	{
		name = "Bubblegum",
		top = Color3.fromRGB(255, 140, 200),
		rim = Color3.fromRGB(210, 80, 160),
		legs = Color3.fromRGB(255, 255, 255),
	},
	{
		name = "Ocean Splash",
		top = Color3.fromRGB(70, 190, 255),
		rim = Color3.fromRGB(30, 110, 210),
		legs = Color3.fromRGB(255, 230, 90),
	},
	{
		name = "Lime Fizz",
		top = Color3.fromRGB(150, 230, 70),
		rim = Color3.fromRGB(70, 160, 40),
		legs = Color3.fromRGB(255, 120, 60),
	},
	{
		name = "Royal Purple",
		top = Color3.fromRGB(160, 100, 240),
		rim = Color3.fromRGB(100, 50, 180),
		legs = Color3.fromRGB(255, 210, 60),
	},
}

return table.freeze({
	-- World
	MAX_PLOTS = 8,
	PLOT_RING_RADIUS = 72,
	PLOT_SIZE = 36, -- each player's square yard
	TABLE_RADIUS = 9,
	TABLE_HEIGHT = 3.6,

	-- Coins
	START_COINS = 1,
	MAX_COINS = 10, -- table is "full" here and can be RESET
	BASE_CASH = 1,
	COIN_BASE_DIAMETER = 2.4,
	COIN_DIAMETER_PER_LEVEL = 0.12,
	COIN_THICKNESS = 0.35,
	HITBOX_EXTRA = 1.4, -- big invisible tap target around each coin (phone first)
	BASE_HEADS_CHANCE = 0.5,
	HEADS_CHANCE_PER_LEVEL = 0.03,
	MAX_HEADS_CHANCE = 0.8,
	BASE_FLIP_TIME = 1.2,
	FLIP_TIME_PER_LEVEL = 0.075,
	MIN_FLIP_TIME = 0.45,
	CASH_PER_BIG_LEVEL = 0.5,

	-- Helpers
	MAX_HELPERS = 1, -- first build: one helper slot
	HELPER_COST = 150,
	HELPER_FLIP_INTERVAL = 2.5,
	OFFLINE_RATE = 0.5, -- helpers earn half speed while you're away
	OFFLINE_CAP_SECONDS = 2 * 60 * 60, -- and at most 2 hours of it

	-- Reset (prestige)
	RESET_CASH_BONUS = 0.5, -- each reset = +50% cash forever

	-- Anti-spam (per player, token bucket)
	TAP_RATE = 10,
	TAP_BURST = 15,
	BUY_RATE = 5,
	BUY_BURST = 8,

	-- Saving
	AUTOSAVE_INTERVAL = 60,
	DATASTORE_NAME = "CoinFlick_Players_v1",
	STUDIO_DATASTORE_NAME = "CoinFlick_STUDIO_TEST",
	-- false = Studio play uses a throwaway in-memory store (never touches real saves).
	-- true  = Studio uses the separate STUDIO_DATASTORE_NAME store (needs API access on).
	STUDIO_USE_REAL_TEST_STORE = false,

	Upgrades = table.freeze(Upgrades),
	UPGRADE_ORDER = table.freeze({ "moreCoins", "bigCoins", "luck", "speed" }),
	TableLooks = table.freeze(TableLooks),

	-- Built-in Roblox sounds (ship with every client). Swap for nicer ones any time.
	Sounds = table.freeze({
		Tap = "rbxasset://sounds/clickfast.wav",
		Flip = "rbxasset://sounds/swoosh.wav",
		Land = "rbxasset://sounds/action_jump_land.mp3",
		Heads = "rbxasset://sounds/electronicpingshort.wav",
		Skull = "rbxasset://sounds/uuhhh.mp3",
		Buy = "rbxasset://sounds/button.wav",
		Reset = "rbxasset://sounds/snap.wav",
	} :: { [string]: string }),

	-- Robux shop (built in step 2). Ids come from carter; 0 means "not set yet".
	-- Prices are set on the Roblox website, never in code.
	Products = table.freeze({
		DoubleCashPassId = 0,
		AutoFlipPassId = 0,
		ExtraHelperSlotProductId = 0,
	}),
})
