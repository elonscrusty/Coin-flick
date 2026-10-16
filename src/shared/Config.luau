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

-- A rare coin multiplies whatever the flip gives (cash on heads, hats on skull).
export type RarityDef = {
	id: string,
	name: string,
	chance: number, -- odds per flip, e.g. 1/100
	mult: number,
	color: Color3, -- popup/shout text; the coin itself is dressed by Util/CoinLook
	grow: number, -- how much bigger the coin gets in the air
	shout: boolean, -- tell the whole server
}

-- A helper guy you collect with cash and level up. Each one walks around
-- your table and flips coins for you (and earns while you're away).
export type HelperDef = {
	id: string,
	name: string,
	icon: string,
	cost: number, -- cash to unlock
	resets: number, -- resets needed before you can unlock it
	interval: number, -- seconds between flips at level 1
	mult: number, -- cash multiplier on its heads at level 1
	body: Color3,
	cap: Color3,
}

-- A silly hat bought with hat points (🎩). Built from chunky parts on your head.
export type HatDef = {
	id: string,
	name: string,
	icon: string,
	cost: number,
}

-- A Robux coin skin (a game pass). passId 0 = carter hasn't made it yet.
export type SkinDef = {
	id: string,
	name: string,
	icon: string,
	passId: number,
	coin: Color3,
	text: Color3,
}

-- id 0 = no uploaded sound yet, so the fallback always plays.
export type SoundDef = {
	id: number,
	fallback: string,
}

local Upgrades: { [string]: UpgradeDef } = {
	moreCoins = {
		name = "More Coins",
		icon = "💰",
		desc = "Put one more coin on your table",
		baseCost = 7,
		growth = 1.8,
		maxLevel = 9,
	},
	bigCoins = {
		name = "Bigger Coins",
		icon = "🔍",
		desc = "+50% cash every heads",
		baseCost = 20,
		growth = 1.8,
		maxLevel = 10,
	},
	luck = {
		name = "Lucky Heads",
		icon = "🍀",
		desc = "+4.5% chance to land heads",
		baseCost = 33,
		growth = 1.9,
		maxLevel = 10,
	},
	speed = {
		name = "Faster Flips",
		icon = "⚡",
		desc = "Coins land faster",
		baseCost = 26,
		growth = 1.75,
		maxLevel = 10,
	},
	multiFlip = {
		name = "Multi Flip",
		icon = "🌀",
		desc = "One tap flips +1 more coin",
		baseCost = 150,
		growth = 2.4,
		maxLevel = 4,
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

-- Rarest first. Anything that isn't one of these is a normal coin.
local Rarities: { RarityDef } = {
	{
		id = "giant",
		name = "GIANT",
		chance = 1 / 10000,
		mult = 500,
		color = Color3.fromRGB(255, 215, 120),
		grow = 2.5,
		shout = true,
	},
	{
		id = "rainbow",
		name = "RAINBOW",
		chance = 1 / 1000,
		mult = 50,
		color = Color3.fromRGB(255, 80, 200),
		grow = 1.6,
		shout = true,
	},
	{
		id = "gold",
		name = "GOLD",
		chance = 1 / 100,
		mult = 10,
		color = Color3.fromRGB(255, 200, 30),
		grow = 1.3,
		shout = false,
	},
	{
		id = "silver",
		name = "SILVER",
		chance = 1 / 20,
		mult = 3,
		color = Color3.fromRGB(140, 185, 235),
		grow = 1.1,
		shout = false,
	},
}

-- In unlock order. All cute, nothing scary.
local HelperTypes: { HelperDef } = {
	{
		id = "buddy",
		name = "Buddy",
		icon = "🙂",
		cost = 150,
		resets = 0,
		interval = 2.5,
		mult = 1,
		body = Color3.fromRGB(90, 200, 255),
		cap = Color3.fromRGB(255, 90, 90),
	},
	{
		id = "zippy",
		name = "Zippy",
		icon = "⚡",
		cost = 2000,
		resets = 1,
		interval = 1.5,
		mult = 1,
		body = Color3.fromRGB(110, 220, 90),
		cap = Color3.fromRGB(255, 220, 60),
	},
	{
		id = "chompy",
		name = "Chompy",
		icon = "🍩",
		cost = 15000,
		resets = 2,
		interval = 2.5,
		mult = 2,
		body = Color3.fromRGB(255, 150, 60),
		cap = Color3.fromRGB(255, 120, 190),
	},
	{
		id = "twinkle",
		name = "Twinkle",
		icon = "✨",
		cost = 100000,
		resets = 3,
		interval = 1.6,
		mult = 1.6,
		body = Color3.fromRGB(255, 130, 200),
		cap = Color3.fromRGB(150, 225, 255),
	},
	{
		id = "king",
		name = "King Flip",
		icon = "👑",
		cost = 1000000,
		resets = 5,
		interval = 1.2,
		mult = 3,
		body = Color3.fromRGB(160, 100, 240),
		cap = Color3.fromRGB(255, 200, 40),
	},
}

-- Cheapest first. Everything is goofy, nothing scary.
local Hats: { HatDef } = {
	{ id = "party", name = "Party Hat", icon = "🥳", cost = 5 },
	{ id = "cone", name = "Traffic Cone", icon = "🚧", cost = 15 },
	{ id = "cowboy", name = "Cowboy Hat", icon = "🤠", cost = 30 },
	{ id = "chef", name = "Chef Hat", icon = "👨‍🍳", cost = 60 },
	{ id = "propeller", name = "Propeller Cap", icon = "🚁", cost = 100 },
	{ id = "duck", name = "Rubber Duck", icon = "🦆", cost = 200 },
	{ id = "tophat", name = "Fancy Top Hat", icon = "🎩", cost = 400 },
	{ id = "crown", name = "Golden Crown", icon = "👑", cost = 800 },
}

local Skins: { SkinDef } = {
	{
		id = "candy",
		name = "Candy Coins",
		icon = "🍬",
		passId = 0,
		coin = Color3.fromRGB(255, 120, 190),
		text = Color3.fromRGB(255, 255, 255),
	},
	{
		id = "ice",
		name = "Ice Coins",
		icon = "🧊",
		passId = 0,
		coin = Color3.fromRGB(150, 225, 255),
		text = Color3.fromRGB(40, 90, 160),
	},
	{
		id = "lava",
		name = "Lava Coins",
		icon = "🌋",
		passId = 0,
		coin = Color3.fromRGB(255, 90, 40),
		text = Color3.fromRGB(255, 240, 120),
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
	COIN_BASE_DIAMETER = 3.0,
	COIN_DIAMETER_PER_LEVEL = 0.08, -- max 3.8, still fits 10 coins on the ring
	COIN_THICKNESS = 0.5, -- chunky, so a coin seen edge-on is clearly a coin
	HITBOX_EXTRA = 1.4, -- big invisible tap target around each coin (phone first)
	-- Streak game: heads is hard at first, so 10 in a row feels special.
	BASE_HEADS_CHANCE = 0.35,
	HEADS_CHANCE_PER_LEVEL = 0.045, -- 10 levels = 80%
	MAX_HEADS_CHANCE = 0.8,
	STREAK_GOAL = 10, -- heads in a row (your own taps; helpers don't count)
	STREAK_PRIZE_FLIPS = 200, -- prize cash = this many heads worth
	STREAK_PRIZE_HATS = 50, -- and this many hat points
	BASE_FLIP_TIME = 1.2,
	FLIP_TIME_PER_LEVEL = 0.075,
	MIN_FLIP_TIME = 0.45,
	LOG_COIN_DRIFT = true, -- warn when a landed coin was more than 0.3 studs off its slot (it is snapped back either way)
	FLIP_HEIGHT = 6, -- studs a coin jumps at the top of its flip (ZOOM camera fits this)
	CASH_PER_BIG_LEVEL = 0.5,

	-- Helpers
	MAX_HELPERS = 1, -- helper slots everyone starts with
	HELPER_SLOT_RESETS = table.freeze({ 1, 3 }), -- each of these resets opens one more slot
	HELPER_MAX_LEVEL = 10,
	HELPER_LEVEL_COST = 1.0, -- level 2 costs the unlock price (an upgrade never looks cheaper than the hire)...
	HELPER_LEVEL_GROWTH = 1.9, -- ...and each level after costs 1.9x more
	HELPER_LEVEL_SPEED = 0.93, -- each level flips 7% faster
	HELPER_LEVEL_CASH = 0.2, -- and +20% cash
	OFFLINE_RATE = 0.5, -- helpers earn half speed while you're away
	OFFLINE_CAP_SECONDS = 8 * 60 * 60, -- and at most 8 hours of it

	-- Chain flips: tap again within the window to grow the combo.
	COMBO_WINDOW = 1.5,
	COMBO_BONUS_PER_STEP = 0.1, -- +10% cash per combo step
	COMBO_MAX_MULT = 3, -- reached at a 21 combo

	-- Shared mega coin in the middle of the server
	MEGA_BASE_TAPS = 60,
	MEGA_TAPS_PER_PLAYER = 30,
	MEGA_REWARD_FLIPS = 1000, -- everyone who tapped gets 1000 heads worth of cash (more than the best rare coin pays)
	MEGA_REWARD_HATS = 5,
	MEGA_BOOST_MULT = 2, -- then the whole server gets 2x cash...
	MEGA_BOOST_SECONDS = 60, -- ...for this long
	MEGA_TAP_RATE = 6,
	MEGA_TAP_BURST = 10,
	MEGA_DIAMETER = 16,
	MEGA_JUMP = 3, -- studs the mega coin hops in its big flip (small, so it stays on screen from your yard)
	MEGA_HEIGHT = 12, -- coin centre above the ground (sits just above the 3.2 tall pedestal)

	-- Leaderboards (global, OrderedDataStore)
	LEADERBOARD_SIZE = 10,
	LEADERBOARD_REFRESH = 120,
	LEADERBOARD_WRITE_INTERVAL = 120,

	-- Robux extras
	PASS_CASH_MULT = 2,
	AUTO_FLIP_INTERVAL = 0.6, -- auto-flip pass flips one coin this often
	MAX_EXTRA_HELPER_SLOTS = 3,
	MAX_SAVED_RECEIPTS = 50,

	-- Friend in the same server: both get this cash multiplier
	FRIEND_CASH_MULT = 2,

	-- Daily gift + daily jobs. Rewards are "flips" = that many heads worth of cash at
	-- the player's current cash per heads (so a gift is never tiny or huge), plus hat points.
	Daily = table.freeze({
		JOBS_PER_DAY = 3,
		-- 7-day gift. Missing a day does NOT reset it: the next claim just pays the next day.
		Gift = table.freeze({
			table.freeze({ flips = 20, hats = 0 }),
			table.freeze({ flips = 30, hats = 0 }),
			table.freeze({ flips = 40, hats = 2 }),
			table.freeze({ flips = 60, hats = 0 }),
			table.freeze({ flips = 80, hats = 4 }),
			table.freeze({ flips = 100, hats = 0 }),
			table.freeze({ flips = 250, hats = 10 }), -- day 7 chest
		}),
		-- Job kinds. Three of these four are picked per player per day; goals[i] pays rewards[i].
		JobKinds = table.freeze({
			table.freeze({
				kind = "flip",
				text = "Flip %d coins",
				goals = table.freeze({ 50, 100, 200 }),
				flips = table.freeze({ 10, 20, 40 }),
				hats = table.freeze({ 0, 1, 2 }),
			}),
			table.freeze({
				kind = "heads",
				text = "Get %d heads",
				goals = table.freeze({ 25, 50, 100 }),
				flips = table.freeze({ 10, 20, 40 }),
				hats = table.freeze({ 0, 1, 2 }),
			}),
			table.freeze({
				kind = "mega",
				text = "Help flip the mega coin %d time(s)",
				goals = table.freeze({ 1, 2, 3 }),
				flips = table.freeze({ 15, 30, 50 }),
				hats = table.freeze({ 1, 2, 3 }),
			}),
			table.freeze({
				kind = "buy",
				text = "Buy %d upgrades",
				goals = table.freeze({ 3, 6, 10 }),
				flips = table.freeze({ 10, 20, 40 }),
				hats = table.freeze({ 0, 1, 2 }),
			}),
		}),
	}),

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
	UPGRADE_ORDER = table.freeze({ "moreCoins", "bigCoins", "luck", "speed", "multiFlip" }),
	TableLooks = table.freeze(TableLooks),
	Rarities = table.freeze(Rarities),
	HelperTypes = table.freeze(HelperTypes),
	Hats = table.freeze(Hats),
	Skins = table.freeze(Skins),
	LEADERBOARDS = table.freeze({ "flips", "biggestFlip", "resets" }),

	-- Built-in Roblox sounds (ship with every client). Swap for nicer ones any time.
	Sounds = table.freeze({
		-- id = carter's own uploaded sound (from Find The Pet), only after carter
		-- says yes to it; he found them annoying all at once, so they are tried
		-- one at a time. fallback = built-in Roblox sound, used when id is 0 or
		-- the id will not load.
		Tap = { id = 0, fallback = "rbxasset://sounds/clickfast.wav" },
		Flip = { id = 0, fallback = "rbxasset://sounds/action_jump.mp3" },
		Land = { id = 0, fallback = "rbxasset://sounds/action_jump_land.mp3" },
		Heads = { id = 0, fallback = "rbxasset://sounds/electronicpingshort.wav" }, -- to try: CoinPickup
		Skull = { id = 0, fallback = "rbxasset://sounds/button.wav" }, -- to try: Pickup
		Buy = { id = 0, fallback = "rbxasset://sounds/button.wav" }, -- to try: Purchase
		Reset = { id = 0, fallback = "rbxasset://sounds/snap.wav" }, -- to try: LevelUp
		Rare = { id = 109340819460170, fallback = "rbxasset://sounds/victory.wav" }, -- RarityAccent, trying now
		Combo = { id = 0, fallback = "rbxasset://sounds/electronicpingshort.wav" }, -- to try: LuckyMeter
		Mega = { id = 0, fallback = "rbxasset://sounds/victory.wav" }, -- to try: MatchWin
		Daily = { id = 0, fallback = "rbxasset://sounds/victory.wav" }, -- to try: DailyClaim
		Gift = { id = 0, fallback = "rbxasset://sounds/victory.wav" }, -- to try: GiftOpen
		JobDone = { id = 0, fallback = "rbxasset://sounds/electronicpingshort.wav" }, -- to try: QuestDone
		Denied = { id = 0, fallback = "rbxasset://sounds/button.wav" }, -- to try: Denied
	} :: { [string]: SoundDef }),

	-- Cartoon sky (World): a thick, bright-blue haze over the default skybox.
	Sky = table.freeze({
		density = 0.36,
		offset = 0.1,
		haze = 2.4,
		color = Color3.fromRGB(150, 210, 255),
		decay = Color3.fromRGB(95, 175, 255),
	}),

	-- Robux shop. Ids come from carter; 0 means "not set yet" (shows SOON).
	-- Prices are set on the Roblox website and read live, never written in code.
	-- Coin skin pass ids live in Skins above.
	Products = table.freeze({
		DoubleCashPassId = 0,
		AutoFlipPassId = 0,
		ExtraHelperSlotProductId = 0,
	}),
})
