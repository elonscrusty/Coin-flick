--!strict
-- All tuning lives here. Numbers are the brief's starting defaults (docs/BRIEF.txt),
-- not measured truths: tune after playtests.

local Config = {}

Config.Version = 1 -- config version stamped on every specimen

Config.Palette = {
	Slate = Color3.fromRGB(38, 50, 60), -- #26323C
	SlateLight = Color3.fromRGB(58, 72, 84),
	Orange = Color3.fromRGB(242, 138, 38), -- #F28A26
	Yellow = Color3.fromRGB(244, 198, 68), -- #F4C644
	Cream = Color3.fromRGB(243, 233, 216), -- #F3E9D8
	Rock = Color3.fromRGB(120, 129, 138), -- #78818A
	Violet = Color3.fromRGB(166, 106, 255), -- #A66AFF
	Cyan = Color3.fromRGB(105, 218, 232), -- #69DAE8
	Green = Color3.fromRGB(88, 196, 108),
	Red = Color3.fromRGB(226, 76, 64),
	Dirt = Color3.fromRGB(196, 168, 128),
}

-- Delivery tiers. Rocks is the logical pile size (it does not grow with party size).
-- Radius/RockSize shape the mound: Gravel ~17 studs across and ~5-6 tall, Meteor ~30 across.
export type Tier = {
	Id: string,
	Name: string,
	Order: number,
	Rocks: number,
	HP: number,
	CashPerRubble: number,
	GeodeBase: number,
	UnlockCash: number,
	UnlockFinds: number,
	Radius: number,
	RockSize: number,
	Minerals: { string },
	Recommended: string,
}

Config.TierOrder = { "Gravel", "Quarry", "Cavern", "Volcanic", "Meteor" }

Config.Tiers = {
	Gravel = {
		Id = "Gravel", Name = "Meadow", Order = 1, Rocks = 150, HP = 1, CashPerRubble = 2,
		GeodeBase = 40, UnlockCash = 0, UnlockFinds = 0, Radius = 10, RockSize = 2.2,
		Minerals = { "Raptor", "Ostrich", "Puffquill", "Pebblehorn", "Mosswhip", "Honeyhoof", "Bramblebat", "Clovercrest", "SunpetalDrake", "Bunny", "Frog" },
		Recommended = "Lucky Collar",
	},
	Quarry = {
		Id = "Quarry", Name = "Forest", Order = 2, Rocks = 150, HP = 2, CashPerRubble = 5,
		GeodeBase = 150, UnlockCash = 500, UnlockFinds = 5, Radius = 12, RockSize = 2.2, -- Forest: 500 coins + 5 pets found (owner pick 2026-10-11)
		Minerals = { "DireWolf", "Griffin", "Duskwing", "Oakmaw", "Thornhoof", "Vinetail", "Mossback", "Hollowfang", "Elderhorn", "Panda", "Turtle" },
		Recommended = "Treat Bag",
	},
	Cavern = {
		Id = "Cavern", Name = "Snow", Order = 3, Rocks = 150, HP = 4, CashPerRubble = 12,
		GeodeBase = 500, UnlockCash = 3000, UnlockFinds = 15, Radius = 14, RockSize = 2.1,
		Minerals = { "FrostWyvern", "Mammoth", "Frostpaw", "Yetiboo", "Shiverclaw", "AuroraHoot", "Waddlefrost", "Hailwing", "FrostcrownDragon", "Shark" },
		Recommended = "Pet Whistle",
	},
	Volcanic = {
		Id = "Volcanic", Name = "Volcano", Order = 4, Rocks = 150, HP = 7, CashPerRubble = 25,
		GeodeBase = 1500, UnlockCash = 25000, UnlockFinds = 35, Radius = 15, RockSize = 2.0,
		Minerals = { "LavaTRex", "Phoenix", "Cinderpup", "Magmaw", "Obsidihorn", "Emberclaw", "Ashwing", "Flarestrut", "InfernalHydra" },
		Recommended = "Pet Whistle + Auto Nest",
	},
	Meteor = {
		Id = "Meteor", Name = "Space", Order = 5, Rocks = 150, HP = 10, CashPerRubble = 50,
		GeodeBase = 4000, UnlockCash = 100000, UnlockFinds = 75, Radius = 16, RockSize = 1.9,
		Minerals = { "CosmicDragon", "Cometpup", "Moonhoot", "Nebuclaw", "LunarTusk", "GalaxyStrut", "Zapstar", "QuasarRex" },
		Recommended = "Best incubator",
	},
} :: { [string]: Tier }

-- Hand tools. Rate is strikes (or pulses) per second; Hold means held input repeats.
export type Handheld = {
	Id: string,
	Name: string,
	Order: number,
	Price: number,
	Damage: number,
	Rate: number,
	Hold: boolean,
	Requires: string?,
}

Config.HandheldOrder = { "Hammer", "SteelHammer", "Jackhammer" }
Config.Handhelds = {
	Hammer = { Id = "Hammer", Name = "Lucky Collar", Order = 1, Price = 0, Damage = 1, Rate = 0.9, Hold = false },
	SteelHammer = { Id = "SteelHammer", Name = "Treat Bag", Order = 2, Price = 150, Damage = 2, Rate = 1.2, Hold = false },
	Jackhammer = { Id = "Jackhammer", Name = "Pet Whistle", Order = 3, Price = 1200, Damage = 1, Rate = 5, Hold = true },
} :: { [string]: Handheld }

-- Machines install at the owner's crushing table and crush that station's queue ONE rock at a time
-- (docs/V3_LOOP.md). Throughput = RocksPerBatch / BatchSeconds rocks per second, so one rock takes
-- BatchSeconds / RocksPerBatch seconds (RoundRocks.machineSeconds): Auto Cracker 2 rocks/s,
-- Hydraulic Press 4/s, Industrial Crusher 12/s. The two fields stay as the shop shows them.
Config.MachinesEnabled = true
Config.MachineOrder = { "AutoCracker", "HydraulicPress", "IndustrialCrusher" }
Config.Machines = {
	AutoCracker = { Id = "AutoCracker", Name = "Auto Nest", Price = 6000, RocksPerBatch = 1, BatchSeconds = 0.5 },
	HydraulicPress = { Id = "HydraulicPress", Name = "Warm Incubator", Price = 45000, RocksPerBatch = 8, BatchSeconds = 2 },
	IndustrialCrusher = { Id = "IndustrialCrusher", Name = "Mega Incubator", Price = 180000, RocksPerBatch = 12, BatchSeconds = 1 },
}

-- V3 loop (docs/V3_LOOP.md): rocks are picked up from the shared pile into a basket, deposited at
-- the player's own crushing table and crushed there. Nothing is cracked at the pile.
-- Carry: Capacity = uncrushed rocks per basket (independent of rubble storage); PickupInterval =
-- seconds between pickups (held input repeats at this rate); PickupRange = xz studs from the
-- player to the rock; ReachLevels = highest pile layer that can be picked without climbing.
-- SightCheck: the server refuses pickups through walls (RockService hasSight). Set false if real play shows false refusals.
-- PickupHeight: most studs the rock may sit above or below the avatar's root (stops picks from far above the pile).
Config.Carry = { Capacity = 3, PickupInterval = 0.45, PickupTolerance = 0.12, PickupRange = 8, PickupHeight = 12, ReachLevels = 3, SightCheck = true }
-- Motion sanity check on rock actions (RockService). The server keeps a trusted point per hunter and judges every
-- scheduler step AND the live position at every Pickup / Deposit / Crush against it: a horizontal move farther
-- than WalkSpeed * SpeedFactor * elapsed + Slack studs is a teleport; that action is refused and the player's rock
-- actions are ignored for Lock seconds. The trusted point moves at most every Anchor seconds (Slack is forgiven
-- once per Anchor) and never to an impossible spot. Server moves (spawns) give Grace seconds to settle.
-- Slack forgives about a second of bunched-up network updates on a laggy phone. Enabled = false turns it off.
Config.Motion = { Enabled = true, Anchor = 2, Grace = 1, SpeedFactor = 1.25, Slack = 6, Lock = 1.5 }
-- First person (docs/m6/FIRST_PERSON.md), in hunts only. FirstPerson = false makes hunts third person too
-- (CameraGuard guards every third-person camera). Reach = studs along the camera-centre ray a target may be aimed
-- from (the server still checks the avatar's own distance); Slack = studs of forgiveness around a target
-- (a rock is small, the reticle is a dot); WorkRadius = within this many studs of the own table the table
-- wins over a pile rock the reticle happens to cover; PromptCone = cos of the half angle in which a lobby
-- prompt may be offered (0.8 is about 37 degrees); LocalHide* = what the local view hides.
Config.Camera = {
	FirstPerson = true,
	Fov = 70,
	Reach = 11,
	FarReach = 30,
	Slack = 0.35,
	WorkRadius = 5.5,
	PromptCone = 0.8,
	GraceAfterModal = 0.25, -- seconds after the last menu closes in which the same input cannot act
	Glimpse = { Offset = Vector3.new(1.5, -1.9, -3.2), Max = 5 }, -- lower right, clear of the hotbar (phone video: it peeked out behind it)
	-- First person is the HUNT view only (owner decision 2026-10-10, docs/m11/CAMERA_SPAWN_FIX.md). The lobby uses the
	-- normal Roblox Classic camera: free mouse, right-drag to turn, zoom between these distances; CameraGuard keeps it
	-- inside the lodge room (Config.Lodge) and out of solid geometry.
	Lobby = { MinZoom = 8, MaxZoom = 25 },
	-- Desktop, first-person hunt: holding one of these keys frees the mouse so HUD buttons can be clicked (the view
	-- and the avatar hold still while it is held; releasing it locks the view again).
	FreeCursorKeys = { "LeftAlt", "RightAlt" },
}

-- The lobby park box in world studs (the outdoor dino-jungle pet park, ParkConfig.Bounds): the ground top, a sky
-- ceiling well above the longest lobby zoom (outdoors: no roof) and the invisible boundary walls. Used by the lobby
-- builders (Interior), the lobby spawn check and the lobby camera box (CameraGuard).
Config.Lodge = { FloorY = 0, CeilingY = 60, MinX = -100, MaxX = 100, MinZ = -164, MaxZ = 160 } -- = ParkConfig.Bounds

-- Station (crushing table): four tables evenly around the pile at Radius studs, one per member.
-- QueueCapacity = input tray size; DepositRange / CrushRange = xz studs from the table centre.
Config.Station = {
	Count = 4,
	Radius = 25,
	QueueCapacity = 10,
	DepositRange = 10,
	CrushRange = 9,
	DepositInterval = 0.25,
	DepositTolerance = 0.1,
	MaxMachineSteps = 24, -- rocks one scheduler step may finish for one station (catch-up bound)
}

-- Rubble storage. Level 1 is free.
Config.Capacity = {
	{ Size = 30, Price = 0 },
	{ Size = 100, Price = 200 },
	{ Size = 300, Price = 1000 },
	{ Size = 1000, Price = 5000 },
	{ Size = 3000, Price = 50000 },
}

-- Pet Book storage (owner: 100 pets). Profiles.petCapacity adds a save's ExtraPetSlots (0 unless a future, owner-made
-- game pass raises it). A save already holding more keeps every pet; it only stops new pets until some are sold.
Config.Inventory = { Max = 100 }

-- Lobby gallery display slots per player alcove. Level 1 is free.
Config.Display = {
	{ Slots = 3, Price = 0 },
	{ Slots = 6, Price = 500 },
	{ Slots = 12, Price = 2000 },
	{ Slots = 20, Price = 12000 },
}
-- FullDetailSlots: the first N specimens of an alcove use the shelf model; the rest use the tiny one
-- (fewest parts) so 16 full galleries stay light (docs/PERF.md).
Config.Gallery = { Alcoves = 16, FullDetailSlots = 8 }

-- Geode generation.
Config.Rarities = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }
-- Owner: the rarest pet is 1 in 1000 (Legendary 0.1 of 100).
Config.RarityWeights = { Common = 60, Uncommon = 25, Rare = 11, Epic = 3.9, Legendary = 0.1 }
Config.RarityMult = { Common = 1, Uncommon = 1.5, Rare = 3, Epic = 6, Legendary = 12 }
Config.RarityColors = {
	Common = Color3.fromRGB(138, 148, 158),
	Uncommon = Color3.fromRGB(64, 170, 110),
	Rare = Color3.fromRGB(52, 120, 230),
	Epic = Color3.fromRGB(150, 80, 220),
	Legendary = Color3.fromRGB(240, 160, 30),
}
-- Rarity colours for TEXT on the dark panels and plaques: lighter tints of the colours above (Epic purple was hard to
-- read on charcoal). The rarity word is always written next to the colour, never colour alone.
Config.RarityTextColors = {
	Common = Color3.fromRGB(206, 212, 218),
	Uncommon = Color3.fromRGB(110, 222, 150),
	Rare = Color3.fromRGB(126, 178, 255),
	Epic = Color3.fromRGB(204, 156, 255),
	Legendary = Color3.fromRGB(255, 198, 84),
}

Config.Formations = { "Cluster", "Spire", "TwinCore", "HollowBloom" }
Config.FormationWeights = { Cluster = 45, Spire = 25, TwinCore = 20, HollowBloom = 10 }
-- Formation is the pet's pose on stands and in the book (ids kept from the geode saves).
Config.FormationNames = { Cluster = "Sitting", Spire = "Standing", TwinCore = "Waving", HollowBloom = "Sleepy" }

-- Pet variants (Find The Pet; owner's roster). Old geode saves used Glowing / Cosmic; Profiles migrates them.
Config.Modifiers = { "Natural", "Golden", "Skeleton", "Rainbow", "SilverCosmic" }
Config.ModifierWeights = { Natural = 90, Golden = 7, Skeleton = 2, Rainbow = 0.8, SilverCosmic = 0.2 }
Config.ModifierMult = { Natural = 1, Golden = 1.5, Skeleton = 2, Rainbow = 3, SilverCosmic = 5 }
Config.ModifierNames = { Natural = "", Golden = "Golden", Skeleton = "Skeleton", Rainbow = "Rainbow", SilverCosmic = "Silver Cosmic" }
Config.ModifierMigration = { Glowing = "Golden", Cosmic = "SilverCosmic" }

-- Mass bands (kg): weight, min, max.
Config.MassBands = {
	{ Weight = 90, Min = 0.5, Max = 4 },
	{ Weight = 9, Min = 4.01, Max = 12 },
	{ Weight = 1, Min = 12.01, Max = 30 },
}

-- Find The Pet: the round's prize is a pet. For save and code compatibility the species table keeps the old name
-- Config.Minerals (a specimen's Mineral field holds the species id). Crystal = main body colour, Rim = accent colour,
-- Kind = which procedural body PetModel builds (REPLACE with real meshes when the owner uploads them).
-- BoostKind: what the pet helps with while it follows you (Coins = shell sell price, Speed = walk speed in hunts,
-- Luck = better rarity odds on the pet YOU hatch; luck never changes which egg hides the pet or who finds it).
-- Boost: extra fraction this species adds on top of the rarity bonus (Config.Pets.RarityBoost).
Config.Minerals = {
	Raptor = { Name = "Razorclaw", Kind = "raptor", Crystal = Color3.fromRGB(110, 190, 90), Rim = Color3.fromRGB(250, 210, 90), BoostKind = "Speed", Boost = 0 },
	Ostrich = { Name = "Thunderstrut", Kind = "ostrich", Crystal = Color3.fromRGB(70, 60, 60), Rim = Color3.fromRGB(250, 190, 170), BoostKind = "Coins", Boost = 0 },
	DireWolf = { Name = "Shadowfang", Kind = "wolf", Crystal = Color3.fromRGB(120, 124, 140), Rim = Color3.fromRGB(235, 235, 245), BoostKind = "Speed", Boost = 0.02 },
	Griffin = { Name = "Stormtalon", Kind = "griffin", Crystal = Color3.fromRGB(210, 160, 80), Rim = Color3.fromRGB(250, 250, 240), BoostKind = "Luck", Boost = 0.02 },
	FrostWyvern = { Name = "Glacier Wyrm", Kind = "wyvern", Crystal = Color3.fromRGB(130, 200, 250), Rim = Color3.fromRGB(235, 250, 255), BoostKind = "Luck", Boost = 0.04 },
	Mammoth = { Name = "Titan Tusk", Kind = "mammoth", Crystal = Color3.fromRGB(150, 100, 70), Rim = Color3.fromRGB(250, 245, 230), BoostKind = "Coins", Boost = 0.04 },
	LavaTRex = { Name = "Inferno Rex", Kind = "trex", Crystal = Color3.fromRGB(60, 44, 44), Rim = Color3.fromRGB(255, 110, 30), BoostKind = "Speed", Boost = 0.06 },
	Phoenix = { Name = "Solar Phoenix", Kind = "phoenix", Crystal = Color3.fromRGB(240, 80, 40), Rim = Color3.fromRGB(255, 210, 60), BoostKind = "Luck", Boost = 0.06 },
	CosmicDragon = { Name = "Void Dragon", Kind = "dragon", Crystal = Color3.fromRGB(70, 60, 170), Rim = Color3.fromRGB(240, 140, 255), BoostKind = "Luck", Boost = 0.1, Chase = true },
	StarPterodactyl = { Name = "Nova Ptera", Kind = "pterodactyl", Crystal = Color3.fromRGB(60, 90, 200), Rim = Color3.fromRGB(255, 230, 120), BoostKind = "Coins", Boost = 0.08, Retired = true }, -- retired from eggs 2026-10-15 (owner); owned ones keep working
	-- Meadow pets added 2026-10-11 (Kind = a stand-in body until the owner's mesh exists; REPLACE: Pet_<id> under PetModels).
	Puffquill = { Name = "Puffquill", Kind = "ostrich", Crystal = Color3.fromRGB(250, 200, 220), Rim = Color3.fromRGB(255, 250, 250), BoostKind = "Coins", Boost = 0.01 },
	Pebblehorn = { Name = "Pebblehorn", Kind = "mammoth", Crystal = Color3.fromRGB(150, 140, 120), Rim = Color3.fromRGB(230, 220, 190), BoostKind = "Coins", Boost = 0.01 },
	Mosswhip = { Name = "Mosswhip", Kind = "raptor", Crystal = Color3.fromRGB(90, 160, 80), Rim = Color3.fromRGB(200, 240, 140), BoostKind = "Speed", Boost = 0.01 },
	Honeyhoof = { Name = "Unicorn", Kind = "mammoth", Crystal = Color3.fromRGB(240, 180, 60), Rim = Color3.fromRGB(255, 240, 180), BoostKind = "Luck", Boost = 0.01 },
	Bramblebat = { Name = "Bramblebat", Kind = "pterodactyl", Crystal = Color3.fromRGB(110, 80, 120), Rim = Color3.fromRGB(170, 220, 110), BoostKind = "Speed", Boost = 0.01, Weekly = true },
	Clovercrest = { Name = "Clovercrest", Kind = "griffin", Crystal = Color3.fromRGB(90, 190, 110), Rim = Color3.fromRGB(255, 255, 200), BoostKind = "Luck", Boost = 0.01, Weekly = true },
	SunpetalDrake = { Name = "Sunpetal Drake", Kind = "dragon", Crystal = Color3.fromRGB(250, 210, 70), Rim = Color3.fromRGB(255, 130, 170), BoostKind = "Luck", Boost = 0.03, Chase = true },
	-- Forest pets added 2026-10-11 (Kind = a stand-in body until the owner's mesh exists; REPLACE: Pet_<id> under PetModels).
	Duskwing = { Name = "Duskwing", Kind = "griffin", Crystal = Color3.fromRGB(90, 70, 120), Rim = Color3.fromRGB(250, 210, 120), BoostKind = "Luck", Boost = 0.02 },
	Oakmaw = { Name = "Oakmaw", Kind = "mammoth", Crystal = Color3.fromRGB(120, 80, 50), Rim = Color3.fromRGB(150, 200, 90), BoostKind = "Coins", Boost = 0.02 },
	Thornhoof = { Name = "Thornhoof", Kind = "ostrich", Crystal = Color3.fromRGB(170, 120, 80), Rim = Color3.fromRGB(130, 200, 90), BoostKind = "Speed", Boost = 0.02 },
	Vinetail = { Name = "Vinetail", Kind = "wolf", Crystal = Color3.fromRGB(230, 110, 50), Rim = Color3.fromRGB(140, 210, 90), BoostKind = "Speed", Boost = 0.02 },
	Mossback = { Name = "Mossback", Kind = "trex", Crystal = Color3.fromRGB(80, 120, 70), Rim = Color3.fromRGB(180, 220, 120), BoostKind = "Coins", Boost = 0.02, Weekly = true },
	Hollowfang = { Name = "Tiger", Kind = "wolf", Crystal = Color3.fromRGB(70, 70, 80), Rim = Color3.fromRGB(160, 240, 200), BoostKind = "Speed", Boost = 0.02, Weekly = true },
	Elderhorn = { Name = "Crystal Deer", Kind = "mammoth", Crystal = Color3.fromRGB(200, 240, 230), Rim = Color3.fromRGB(120, 255, 200), BoostKind = "Luck", Boost = 0.04, Chase = true },
	-- Snow pets added 2026-10-11 (Kind = a stand-in body until the owner's mesh exists; REPLACE: Pet_<id> under PetModels).
	Frostpaw = { Name = "Ice Lion", Kind = "wolf", Crystal = Color3.fromRGB(200, 230, 250), Rim = Color3.fromRGB(120, 180, 240), BoostKind = "Speed", Boost = 0.04 },
	Yetiboo = { Name = "Grizzly Bear", Kind = "mammoth", Crystal = Color3.fromRGB(240, 245, 255), Rim = Color3.fromRGB(150, 200, 240), BoostKind = "Coins", Boost = 0.04 },
	Shiverclaw = { Name = "Shiverclaw", Kind = "raptor", Crystal = Color3.fromRGB(120, 190, 230), Rim = Color3.fromRGB(240, 250, 255), BoostKind = "Speed", Boost = 0.04 },
	AuroraHoot = { Name = "Aurora Hoot", Kind = "griffin", Crystal = Color3.fromRGB(110, 220, 200), Rim = Color3.fromRGB(220, 150, 255), BoostKind = "Luck", Boost = 0.04 },
	Waddlefrost = { Name = "Waddlefrost", Kind = "ostrich", Crystal = Color3.fromRGB(40, 50, 70), Rim = Color3.fromRGB(250, 250, 255), BoostKind = "Coins", Boost = 0.04, Weekly = true },
	Hailwing = { Name = "Hailwing", Kind = "pterodactyl", Crystal = Color3.fromRGB(170, 200, 230), Rim = Color3.fromRGB(255, 255, 255), BoostKind = "Speed", Boost = 0.04, Weekly = true },
	FrostcrownDragon = { Name = "Frostcrown Dragon", Kind = "dragon", Crystal = Color3.fromRGB(150, 220, 255), Rim = Color3.fromRGB(255, 255, 255), BoostKind = "Luck", Boost = 0.06, Chase = true },
	-- Volcano pets added 2026-10-11 (Kind = a stand-in body until the owner's mesh exists; REPLACE: Pet_<id> under PetModels).
	Cinderpup = { Name = "Cinderpup", Kind = "wolf", Crystal = Color3.fromRGB(90, 60, 50), Rim = Color3.fromRGB(255, 140, 40), BoostKind = "Speed", Boost = 0.06 },
	Magmaw = { Name = "Lava Golem", Kind = "trex", Crystal = Color3.fromRGB(120, 40, 30), Rim = Color3.fromRGB(255, 170, 40), BoostKind = "Coins", Boost = 0.06 },
	Obsidihorn = { Name = "Obsidihorn", Kind = "mammoth", Crystal = Color3.fromRGB(40, 35, 45), Rim = Color3.fromRGB(255, 90, 40), BoostKind = "Coins", Boost = 0.06 },
	Emberclaw = { Name = "Emberclaw", Kind = "raptor", Crystal = Color3.fromRGB(200, 70, 30), Rim = Color3.fromRGB(255, 220, 90), BoostKind = "Luck", Boost = 0.06 },
	Ashwing = { Name = "Ashwing", Kind = "pterodactyl", Crystal = Color3.fromRGB(110, 110, 110), Rim = Color3.fromRGB(255, 120, 50), BoostKind = "Speed", Boost = 0.06, Weekly = true },
	Flarestrut = { Name = "Flarestrut", Kind = "ostrich", Crystal = Color3.fromRGB(240, 100, 40), Rim = Color3.fromRGB(255, 220, 120), BoostKind = "Speed", Boost = 0.06, Weekly = true },
	InfernalHydra = { Name = "Infernal Hydra", Kind = "dragon", Crystal = Color3.fromRGB(170, 30, 30), Rim = Color3.fromRGB(255, 190, 50), BoostKind = "Luck", Boost = 0.08, Chase = true },
	-- Space pets added 2026-10-11 (Kind = a stand-in body until the owner's mesh exists; REPLACE: Pet_<id> under PetModels).
	Cometpup = { Name = "Cometpup", Kind = "wolf", Crystal = Color3.fromRGB(60, 70, 140), Rim = Color3.fromRGB(170, 230, 255), BoostKind = "Speed", Boost = 0.08 },
	Moonhoot = { Name = "Moon Owl", Kind = "griffin", Crystal = Color3.fromRGB(200, 200, 230), Rim = Color3.fromRGB(140, 120, 255), BoostKind = "Luck", Boost = 0.08 },
	Nebuclaw = { Name = "Nebuclaw", Kind = "raptor", Crystal = Color3.fromRGB(130, 60, 180), Rim = Color3.fromRGB(255, 150, 230), BoostKind = "Speed", Boost = 0.08 },
	LunarTusk = { Name = "Lunar Tusk", Kind = "mammoth", Crystal = Color3.fromRGB(180, 185, 200), Rim = Color3.fromRGB(120, 200, 255), BoostKind = "Coins", Boost = 0.08 },
	GalaxyStrut = { Name = "Galaxy Strut", Kind = "ostrich", Crystal = Color3.fromRGB(40, 30, 90), Rim = Color3.fromRGB(255, 120, 220), BoostKind = "Coins", Boost = 0.08 },
	Zapstar = { Name = "Zapstar", Kind = "pterodactyl", Crystal = Color3.fromRGB(250, 230, 80), Rim = Color3.fromRGB(120, 140, 255), BoostKind = "Speed", Boost = 0.08, Weekly = true },
	QuasarRex = { Name = "Quasar Rex", Kind = "trex", Crystal = Color3.fromRGB(30, 30, 60), Rim = Color3.fromRGB(120, 255, 240), BoostKind = "Coins", Boost = 0.08, Weekly = true },
	-- Tower-only pets (owner pick 2026-10-11): won in the pet tower, never in a hunt pile (no zone lists them).
	-- Kind reuses a hunt body as a stand-in until real meshes exist (REPLACE: Pet_<id> under PetModels).
	Thornback = { Name = "Thornback", Kind = "trex", Crystal = Color3.fromRGB(70, 150, 60), Rim = Color3.fromRGB(200, 240, 120), BoostKind = "Coins", Boost = 0.03, TowerOnly = true, Element = "Nature" },
	Frostbyte = { Name = "Frostbyte", Kind = "wolf", Crystal = Color3.fromRGB(150, 220, 255), Rim = Color3.fromRGB(240, 250, 255), BoostKind = "Speed", Boost = 0.04, TowerOnly = true, Element = "Ice" },
	Voltwing = { Name = "Storm Eagle", Kind = "griffin", Crystal = Color3.fromRGB(250, 220, 60), Rim = Color3.fromRGB(120, 200, 255), BoostKind = "Speed", Boost = 0.05, TowerOnly = true, Element = "Storm" },
	Embergeist = { Name = "Embergeist", Kind = "phoenix", Crystal = Color3.fromRGB(255, 120, 40), Rim = Color3.fromRGB(255, 230, 120), BoostKind = "Coins", Boost = 0.06, TowerOnly = true, Element = "Fire" },
	AstralKitsune = { Name = "Astral Kitsune", Kind = "wolf", Crystal = Color3.fromRGB(150, 90, 230), Rim = Color3.fromRGB(255, 220, 255), BoostKind = "Luck", Boost = 0.1, TowerOnly = true, Element = "Cosmic" },
	-- owner's new low-poly pets with no older species to take over (2026-10-13)
	Bunny = { Name = "Bunny", Kind = "wolf", Crystal = Color3.fromRGB(245, 240, 235), Rim = Color3.fromRGB(255, 190, 210), BoostKind = "Speed", Boost = 0.01 },
	Frog = { Name = "Frog", Kind = "raptor", Crystal = Color3.fromRGB(110, 190, 70), Rim = Color3.fromRGB(230, 250, 140), BoostKind = "Coins", Boost = 0.01 },
	Panda = { Name = "Panda", Kind = "mammoth", Crystal = Color3.fromRGB(245, 245, 245), Rim = Color3.fromRGB(60, 60, 70), BoostKind = "Luck", Boost = 0.02 },
	Turtle = { Name = "Turtle", Kind = "mammoth", Crystal = Color3.fromRGB(110, 140, 70), Rim = Color3.fromRGB(205, 190, 140), BoostKind = "Luck", Boost = 0.01 }, -- owner 2026-10-15: "bring the turtle back" (Pet_Turtle mesh)
	Shark = { Name = "Ice Shark", Kind = "raptor", Crystal = Color3.fromRGB(90, 140, 190), Rim = Color3.fromRGB(220, 240, 255), BoostKind = "Speed", Boost = 0.04 },
}
-- Chase pets (Chase = true): a zone's one Legendary-only species. A Legendary hatch in that zone is always its chase
-- pet and the chase pet is never anything but Legendary, so each one is exactly the 1 in 1000 roll (Void Dragon in
-- Space, owner pick). Every other species of the zone shares the remaining odds equally (SpeciesPool).
-- New pet every week (owner pick): species marked Weekly = true unlock one per week in the Order below, the first at
-- Start (UTC unix seconds), the next 7 days later, and so on. Start = 0 keeps every weekly pet hidden (not in piles,
-- odds, Pet Book or badges) until the owner sets the launch date (docs/OWNER_STEPS.md "Weekly pets").
Config.WeeklyPets = {
	Start = 0,
	Days = 7,
	Order = { "Clovercrest", "Hollowfang", "Waddlefrost", "Flarestrut", "Zapstar", "Bramblebat", "Mossback", "Hailwing", "Ashwing", "QuasarRex" },
}

-- Old geode saves name minerals; Profiles moves each to a pet of the same zone (docs/PET_MIGRATION in Profiles).
Config.MineralMigration = {
	Quartz = "Raptor", Amethyst = "Ostrich", Citrine = "Ostrich", RoseQuartz = "Raptor", Calcite = "Raptor",
	Fluorite = "Griffin", Celestite = "FrostWyvern", EmberQuartz = "Phoenix", Starstone = "Cometpup", VoidCrystal = "CosmicDragon",
}

-- Pets you own and show off. Slots = the ONE team: pets that follow you and fight (carter 2026-10-15: one team of 3). Pets are only found in hunts, never
-- sold for Robux, so their boosts are earned (never pay-to-win). Boost = (species Boost + RarityBoost[rarity]) *
-- KindScale[kind], summed over followers, capped at KindCap[kind]. Speed is kept small so new players can still win.
-- Lobby-only walk speed (MatchService; Roblox default is 16). Hunts use Config.Pets.BaseWalkSpeed.
Config.Lobby = { WalkSpeed = 18 }

-- The sleepy pet "Zzz" bubble (client/PetMoodFx). 2026-10-14 runner rounds: it pulled the eye, so it is half the old
-- 52 x 30 size and never fully opaque (Faint = the lowest text transparency).
Config.PetZzz = { Width = 26, Height = 16, TextSize = 12, Faint = 0.45 }

Config.Pets = {
	Slots = 3,
	RarityBoost = { Common = 0.03, Uncommon = 0.06, Rare = 0.1, Epic = 0.15, Legendary = 0.25 },
	KindScale = { Coins = 1, Speed = 0.4, Luck = 1 },
	KindCap = { Coins = 0.5, Speed = 0.15, Luck = 0.5 },
	AnnounceRarities = { Rare = true, Epic = true, Legendary = true }, -- whole-server message after the hatch
	BaseWalkSpeed = 18, -- hunt walk speed before the Speed boost (MatchService)
	Starter = "Raptor", -- every new player gets one Common Raptor so a pet follows them from minute one
	-- Free renaming (Pet Book detail): at most NameMax characters, filtered by Roblox (PetService), one rename per
	-- RenameCooldown seconds per player.
	NameMax = 20,
	RenameCooldown = 5,
	-- Pet type colours: the glow and icon on Pet Book cards and follower tags (BoostKind of the species).
	KindColors = {
		Coins = Color3.fromRGB(255, 196, 40),
		Speed = Color3.fromRGB(80, 200, 255),
		Luck = Color3.fromRGB(96, 220, 110),
	},
	-- Rarer pets are drawn a little bigger (PetModel multiplies its size by this; looks only, no gameplay effect).
	RarityScale = { Common = 1, Uncommon = 1.05, Rare = 1.12, Epic = 1.2, Legendary = 1.3 },
	-- Rarer pets sparkle (PetModel adds a Sparkles tagged "PetSparkle"; PetSparkle on the client turns them off
	-- with Settings.LowEffects). TimeScale < 1 = slower, calmer sparkles.
	Sparkle = {
		Rare = { Color = Color3.fromRGB(90, 170, 255), TimeScale = 0.6 },
		Epic = { Color = Color3.fromRGB(200, 110, 255), TimeScale = 0.8 },
		Legendary = { Color = Color3.fromRGB(255, 205, 60), TimeScale = 1 },
	},
}

-- Hatch reveal timing by rarity (owner pick: commons about 2 s, Rare and better about 6 s in slow motion with a
-- rarity glow, under a choir build-up; SoundConfig HatchChoir; pets never roar). RevealView plays
-- its animation in three parts: the egg drops in (Pre), wobbles, cracks and the pet pops (Slow), then rays and name
-- settle (Post); each value is real seconds. The server's Reveal phase lasts the total plus Hold (PetFlair).
Config.Hatch = {
	Normal = { Pre = 0.4, Slow = 0.9, Post = 0.7, Glow = false },
	Slow = { Pre = 0.6, Slow = 4.0, Post = 1.4, Glow = true },
	SlowRarities = { Rare = true, Epic = true, Legendary = true },
	Hold = 0.2,
}

-- Pet index rewards (PetIndex): coins the first time a species is hatched (once per species, paid inside the same
-- profile write that records the discovery, so it can never pay twice), and a title once every species is found.
-- FirstFindCoins is an in-game coin amount (never Robux), sized like the daily gift.
Config.PetIndex = { FirstFindCoins = 50, MasterTitle = "Pet Master" }

-- Rare hatch announcements (RareHatch). Same server: fireworks and a gold banner for everyone. Every other server:
-- the same banner (no fireworks) through MessagingService topic `Topic`. Payload = display name + pet name + rarity.
-- PublishGap: seconds between two publishes from this server; PlayerGap: per player. ReceiveGap: at most one
-- banner from other servers per this many seconds (extra ones are dropped). EchoSeconds: our own message coming
-- back from MessagingService within this time is ignored (the local banner already played).
Config.RareHatch = {
	Topic = "RareHatch",
	PublishGap = 6,
	PlayerGap = 30,
	ReceiveGap = 4,
	EchoSeconds = 30,
	NameMax = 32,
	PetMax = 48,
	BannerSeconds = 4.5,
	QueueMax = 3,
}

-- Material Discoveries (docs/m6/DISCOVERIES.md). Presentation only: which kind of ordinary stone a
-- player's own finished crush turns out to be. NO value, capacity, speed or currency changes: every ordinary
-- result is the same rubble unit as before. The category of a rock is fixed on the server per round + rock
-- (Materials.pick) and is only told to the player who completed that rock. Weights are relative.
-- Quartz chips are solid pieces (never a hollow geode); metallic specks are inclusions (never a gold nugget).
-- Thumbnails are drawn from Color / Accent / Look by ui/MaterialThumb (no asset ids).
Config.MaterialOrder = { "CommonStone", "QuartzFragment", "MetallicSpecks" }
Config.Materials = {
	CommonStone = {
		Id = "CommonStone", Name = "Plain Candy", Weight = 80, Look = "stone",
		Desc = "Sweet candy. Every egg you hatch leaves some.",
		Color = Color3.fromRGB(150, 148, 142), Accent = Color3.fromRGB(190, 188, 180),
	},
	QuartzFragment = {
		Id = "QuartzFragment", Name = "Sprinkle Candy", Weight = 15, Look = "chip",
		Desc = "Candy with sprinkles from a lucky egg.",
		Color = Color3.fromRGB(226, 214, 204), Accent = Color3.fromRGB(255, 250, 240),
	},
	MetallicSpecks = {
		Id = "MetallicSpecks", Name = "Golden Candy", Weight = 5, Look = "specks",
		Desc = "Shiny candy with golden flecks.",
		Color = Color3.fromRGB(128, 126, 122), Accent = Color3.fromRGB(226, 178, 84),
	},
}
-- Discovery notices from fast machines are merged into one card per this many seconds on the client.
Config.MaterialNoticeSeconds = 2.2

-- Specimens worth less than this fraction of their value cannot be "sold" twice etc. Sell price = value.
Config.Sell = { SpecimenFraction = 1 }

-- Match flow.
Config.Match = {
	CountdownSeconds = 3,
	WaitForMembersSeconds = 30,
	ManualRange = 14, -- client reach cue only; the server checks Config.Carry / Config.Station ranges
	RewardSaveTimeout = 15,
	RevealSeconds = 2.8, -- default reveal length; the hunt's Reveal phase uses PetFlair.revealSeconds(rarity) (Config.Hatch)
	ResultsReturnSeconds = 120, -- results screen; players may leave or rematch at any time
	MaxArenas = 6, -- single-place mode: concurrent private arenas in one server
	-- Phone speed: StreamingEnabled is off, so every built hunt arena (~1,600 parts) sits in every player's world. Arena
	-- slots above ArenaKeepWarm are torn down once they have stood empty for ArenaIdleSeconds (rebuilt on the next busy
	-- spell); the first ArenaKeepWarm slots stay built so a hunt starts without a build hitch. (tests/server/budget.luau)
	ArenaKeepWarm = 1,
	ArenaIdleSeconds = 90,
	CadenceTolerance = 0.3, -- network slack on strike cadence; eligible times still keep the true rate
	SettleSeconds = 0.4, -- client: rocks above a removed one settle over this long
	EggGravity = 90, -- client: studs/s^2 eggs fall with on the pile (shared/EggFall; real Roblox is 196, this is cartoon)
}

Config.Party = { MaxSize = 4, InviteSeconds = 60 }

-- First-time solo practice: a small pile on purpose (24 eggs; was 12, which read as a thin scatter on the meadow
-- mound, bug 245); the pet is still one of eggs 2-6 cracked, so the round stays short and the player always
-- cracks at least one ordinary egg (and sees shells) first.
Config.Tutorial = { Rocks = 24, TargetFrom = 2, TargetWithin = 6, Tier = "Gravel" }

-- Place topology. "SinglePlace" runs lobby and private arenas in one server (Phase 1, works in
-- Studio and live). "Teleport" (Phase 2) sends parties to a reserved Match place.
Config.Places = {
	Mode = "SinglePlace",
	LobbyPlaceId = 0,
	MatchPlaceId = 0,
	LobbyMaxPlayers = 12, -- owner: 12 per server (also set Max Players in Studio Game Settings)
	MatchMaxPlayers = 4,
}

-- Teleport mode only (Config.Places.Mode = "Teleport"). Seconds unless noted.
Config.Teleport = {
	ArriveSeconds = 180, -- first arrivals must reach the Match place within this of the ticket being made
	TicketSeconds = 3600, -- the whole ticket (reconnects included) dies after this
	MaxReconnects = 3, -- re-entries per member once they left a live Match server
	MaxRetries = 1, -- manual RETRY presses after a failed or partial teleport
	ReleaseAttempts = 4, -- save-and-release tries per profile before a teleport
	SentWatchdog = 25, -- a member still in the lobby this long after TeleportAsync counts as not sent
	AwayHoldSeconds = 900, -- lobby keeps a teleported party member's seat this long
	ReturnWatchdog = 25,
	LoadAttempts = 10, -- profile load tries on the Match server (lock waits after a teleport)
}

Config.Save = {
	StoreName = "CTR_Profiles_v1",
	LedgerName = "CTR_Ledger_v1",
	PendingName = "CTR_Pending_v1",
	AutosaveSeconds = 90,
	LockSeconds = 300, -- a lock older than this is treated as abandoned
	LoadAttempts = 7, -- profile load tries (lock held elsewhere / DataStore errors)
	SchemaVersion = 1,
	RecentAwardsKept = 50,
}

-- Cosmetic Robux products (launch rule: cosmetics only: no tool power, Cash, luck, hints or
-- speed). Every ProductId is 0 until the owner creates the Developer Product; with 0 the item
-- is hidden, and the whole Store tab is hidden when every id is 0. Prices are NOT set here:
-- once an id is real the client shows the price Roblox reports for the product, and until then
-- PriceText says "set by owner". Kinds: ToolSkin (recolours the held hammer / jackhammer) and
-- GalleryTheme (recolours the owner's own lobby alcove). See src/shared/Cosmetics.luau.
Config.CosmeticOrder = { "SkinCopper", "SkinNightSteel", "ThemeAmber", "ThemeGlacier" }
Config.Products = {
	SkinCopper = {
		Id = "SkinCopper", Kind = "ToolSkin", Name = "Copper Shine", ProductId = 0, PriceText = "set by owner",
		Desc = "Warm copper shine for your gear. Looks only: same power.",
		Head = Color3.fromRGB(184, 115, 51), Accent = Color3.fromRGB(232, 168, 110),
	},
	SkinNightSteel = {
		Id = "SkinNightSteel", Kind = "ToolSkin", Name = "Night Shine", ProductId = 0, PriceText = "set by owner",
		Desc = "Dark blue shine with bright edges. Looks only: same power.",
		Head = Color3.fromRGB(40, 48, 78), Accent = Color3.fromRGB(120, 160, 255),
	},
	ThemeAmber = {
		Id = "ThemeAmber", Kind = "GalleryTheme", Name = "Amber Glow", ProductId = 0, PriceText = "set by owner",
		Desc = "Warm amber frame and shelf lights for your gallery alcove.",
		Accent = Color3.fromRGB(255, 176, 64), Light = Color3.fromRGB(255, 196, 110),
	},
	ThemeGlacier = {
		Id = "ThemeGlacier", Kind = "GalleryTheme", Name = "Glacier Trim", ProductId = 0, PriceText = "set by owner",
		Desc = "Cool ice-blue frame and shelf lights for your gallery alcove.",
		Accent = Color3.fromRGB(96, 190, 230), Light = Color3.fromRGB(170, 230, 255),
	},
}
Config.CosmeticKinds = { ToolSkin = "Gear skin", GalleryTheme = "Gallery theme" }

-- Lobby leaderboards (OrderedDataStores; Studio adds "_Studio" to every store name). Writes
-- are throttled per board and only run while the request budget leaves MinBudget spare; a
-- stored value is never lowered or deleted. Rankings are never reset.
Config.Leaderboards = {
	StorePrefix = "CTR_LB_",
	Top = 10,
	RefreshSeconds = 60, -- how often the top lists are re-read
	WriteMinSeconds = 60, -- at most one write per player per board in this time
	FlushSeconds = 15,
	MinBudget = 8,
	NameFailRetrySeconds = 120,
}

return Config
