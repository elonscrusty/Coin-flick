--!strict
-- Pet Tower tuning (design: project file plans/pet-tower.md). Pure data, no Roblox services.
-- Stats only matter inside the tower; the egg race never reads this file.

local TowerConfig = {}

export type Base = { Element: string, Power: number, Health: number, Speed: number, Basic: string }
export type Special = {
	Id: string,
	Name: string,
	Kind: string, -- "Burn" | "Slow" | "Chain" | "Heal" | "Shield" | "Stomp" | "Dash" | "Crit"
	Value: number, -- meaning depends on Kind (damage multiplier, heal fraction, seconds...)
	MinRarity: number, -- index into Rarities; rarer pets can roll stronger specials
	Element: string?, -- only pets of this type roll it; nil = any type
}
export type Mob = { Id: string, Element: string, Name: string, Pet: string?, Health: number, Power: number, Speed: number, Boss: boolean }

-- Species base stats, keyed by the pet species id (Specimen.Mineral). Speed 100 = one attack per second.
TowerConfig.Species = {
	Raptor = { Element = "Nature", Power = 12, Health = 90, Speed = 115, Basic = "Claw Rush" },
	Ostrich = { Element = "Nature", Power = 10, Health = 110, Speed = 105, Basic = "Peck" },
	DireWolf = { Element = "Storm", Power = 14, Health = 105, Speed = 110, Basic = "Bite" },
	Griffin = { Element = "Storm", Power = 15, Health = 100, Speed = 105, Basic = "Talon Dive" },
	FrostWyvern = { Element = "Ice", Power = 16, Health = 115, Speed = 100, Basic = "Frost Nip" },
	Mammoth = { Element = "Earth", Power = 14, Health = 150, Speed = 85, Basic = "Tusk Bump" },
	LavaTRex = { Element = "Fire", Power = 19, Health = 130, Speed = 90, Basic = "Lava Chomp" },
	Phoenix = { Element = "Fire", Power = 17, Health = 110, Speed = 115, Basic = "Flame Wing" },
	CosmicDragon = { Element = "Cosmic", Power = 20, Health = 140, Speed = 100, Basic = "Star Bite" },
	StarPterodactyl = { Element = "Cosmic", Power = 18, Health = 115, Speed = 120, Basic = "Comet Dive" },
	-- tower-only
	-- Pets added 2026-10-11 (all five zones).
	Puffquill = { Element = "Nature", Power = 10, Health = 105, Speed = 105, Basic = "Fluff Peck" },
	Pebblehorn = { Element = "Earth", Power = 11, Health = 130, Speed = 85, Basic = "Pebble Charge" },
	Mosswhip = { Element = "Nature", Power = 12, Health = 90, Speed = 115, Basic = "Vine Whip" },
	Honeyhoof = { Element = "Earth", Power = 10, Health = 120, Speed = 90, Basic = "Honey Stomp" },
	Bramblebat = { Element = "Nature", Power = 12, Health = 85, Speed = 120, Basic = "Thorn Swoop" },
	Clovercrest = { Element = "Nature", Power = 11, Health = 100, Speed = 110, Basic = "Lucky Talon" },
	SunpetalDrake = { Element = "Nature", Power = 17, Health = 130, Speed = 105, Basic = "Petal Storm" },
	Duskwing = { Element = "Storm", Power = 14, Health = 100, Speed = 115, Basic = "Night Dive" },
	Oakmaw = { Element = "Earth", Power = 15, Health = 150, Speed = 85, Basic = "Log Slam" },
	Thornhoof = { Element = "Nature", Power = 13, Health = 105, Speed = 115, Basic = "Thorn Kick" },
	Vinetail = { Element = "Nature", Power = 14, Health = 100, Speed = 120, Basic = "Vine Lash" },
	Mossback = { Element = "Earth", Power = 15, Health = 140, Speed = 90, Basic = "Moss Crunch" },
	Hollowfang = { Element = "Storm", Power = 15, Health = 100, Speed = 115, Basic = "Hollow Howl" },
	Elderhorn = { Element = "Nature", Power = 19, Health = 150, Speed = 100, Basic = "Spirit Bloom" },
	Frostpaw = { Element = "Ice", Power = 16, Health = 110, Speed = 115, Basic = "Frost Pounce" },
	Yetiboo = { Element = "Ice", Power = 15, Health = 155, Speed = 85, Basic = "Snowball Smash" },
	Shiverclaw = { Element = "Ice", Power = 17, Health = 100, Speed = 120, Basic = "Ice Slash" },
	AuroraHoot = { Element = "Ice", Power = 15, Health = 105, Speed = 110, Basic = "Aurora Beam" },
	Waddlefrost = { Element = "Ice", Power = 14, Health = 125, Speed = 95, Basic = "Belly Slide" },
	Hailwing = { Element = "Storm", Power = 17, Health = 100, Speed = 125, Basic = "Hail Dive" },
	FrostcrownDragon = { Element = "Ice", Power = 20, Health = 140, Speed = 100, Basic = "Crown Blizzard" },
	Cinderpup = { Element = "Fire", Power = 18, Health = 110, Speed = 115, Basic = "Cinder Bite" },
	Magmaw = { Element = "Fire", Power = 19, Health = 135, Speed = 90, Basic = "Magma Chomp" },
	Obsidihorn = { Element = "Earth", Power = 17, Health = 160, Speed = 85, Basic = "Obsidian Ram" },
	Emberclaw = { Element = "Fire", Power = 19, Health = 105, Speed = 120, Basic = "Ember Slash" },
	Ashwing = { Element = "Fire", Power = 18, Health = 105, Speed = 125, Basic = "Ash Cloud" },
	Flarestrut = { Element = "Fire", Power = 17, Health = 115, Speed = 115, Basic = "Flare Kick" },
	InfernalHydra = { Element = "Fire", Power = 22, Health = 150, Speed = 100, Basic = "Triple Blaze" },
	Cometpup = { Element = "Cosmic", Power = 19, Health = 115, Speed = 120, Basic = "Comet Tackle" },
	Moonhoot = { Element = "Cosmic", Power = 18, Health = 110, Speed = 115, Basic = "Moon Beam" },
	Nebuclaw = { Element = "Cosmic", Power = 20, Health = 105, Speed = 125, Basic = "Nebula Slash" },
	LunarTusk = { Element = "Cosmic", Power = 18, Health = 165, Speed = 85, Basic = "Crater Stomp" },
	GalaxyStrut = { Element = "Cosmic", Power = 17, Health = 120, Speed = 115, Basic = "Starlight Kick" },
	Zapstar = { Element = "Storm", Power = 20, Health = 105, Speed = 130, Basic = "Zap Dive" },
	QuasarRex = { Element = "Cosmic", Power = 21, Health = 145, Speed = 90, Basic = "Quasar Chomp" },
	Thornback = { Element = "Nature", Power = 15, Health = 150, Speed = 90, Basic = "Spike Roll" },
	Frostbyte = { Element = "Ice", Power = 17, Health = 120, Speed = 110, Basic = "Snow Pounce" },
	Voltwing = { Element = "Storm", Power = 19, Health = 105, Speed = 125, Basic = "Volt Swoop" },
	Embergeist = { Element = "Fire", Power = 21, Health = 115, Speed = 115, Basic = "Ghost Flame" },
	AstralKitsune = { Element = "Cosmic", Power = 23, Health = 135, Speed = 120, Basic = "Nine-Tail Flash" },
} :: { [string]: Base }
-- Tower-only pets (carter): never in eggs, only dropped by tower bosses. A species drops only from floor
-- `From` up. They join the normal collection once the core game lists them in Config.Minerals (until then
-- no drop is granted). REPLACE: Cube 3D models made on carter's PC.
TowerConfig.TowerPets = {
	{ Id = "Thornback", From = 5, Weight = 40 },
	{ Id = "Frostbyte", From = 10, Weight = 30 },
	{ Id = "Voltwing", From = 15, Weight = 20 },
	{ Id = "Embergeist", From = 20, Weight = 9 },
	{ Id = "AstralKitsune", From = 30, Weight = 1 },
}
TowerConfig.Drop = {
	Chance = 0.08, -- per boss floor clear, plus PerFloor x floor, capped at Max
	PerFloor = 0.002,
	Max = 0.25,
	RarityWeights = { Common = 50, Uncommon = 30, Rare = 14, Epic = 5, Legendary = 1 },
}
-- Pity (audit fix): a boss floor is cleared only once per climb (the run restarts after the last boss), so one plain
-- roll per boss left most tower pets out of reach. Each boss clear without a drop adds PerMiss to the next boss's
-- chance (saved as profile TowerPity), and after GuaranteeAfter misses in a row the next boss always drops. A drop
-- picks a tower pet the player has never had (allowed on that floor) when one is left, each with at least
-- MinNewWeight, so the rare ones are not starved. Aim: a steady climber owns all 5 by about floor 60-80
-- (tests/test_pet_tower.luau simulates it).
TowerConfig.Pity = {
	PerMiss = 0.15,
	GuaranteeAfter = 3,
	MinNewWeight = 10,
}

-- Display names (carter, 2026-10-11).
TowerConfig.PetNames = {
	Puffquill = "Puffquill",
	Pebblehorn = "Pebblehorn",
	Mosswhip = "Mosswhip",
	Honeyhoof = "Honeyhoof",
	Bramblebat = "Bramblebat",
	Clovercrest = "Clovercrest",
	SunpetalDrake = "Sunpetal Drake",
	Duskwing = "Duskwing",
	Oakmaw = "Oakmaw",
	Thornhoof = "Thornhoof",
	Vinetail = "Vinetail",
	Mossback = "Mossback",
	Hollowfang = "Hollowfang",
	Elderhorn = "Elderhorn",
	Frostpaw = "Frostpaw",
	Yetiboo = "Yetiboo",
	Shiverclaw = "Shiverclaw",
	AuroraHoot = "Aurora Hoot",
	Waddlefrost = "Waddlefrost",
	Hailwing = "Hailwing",
	FrostcrownDragon = "Frostcrown Dragon",
	Cinderpup = "Cinderpup",
	Magmaw = "Magmaw",
	Obsidihorn = "Obsidihorn",
	Emberclaw = "Emberclaw",
	Ashwing = "Ashwing",
	Flarestrut = "Flarestrut",
	InfernalHydra = "Infernal Hydra",
	Cometpup = "Cometpup",
	Moonhoot = "Moonhoot",
	Nebuclaw = "Nebuclaw",
	LunarTusk = "Lunar Tusk",
	GalaxyStrut = "Galaxy Strut",
	Zapstar = "Zapstar",
	QuasarRex = "Quasar Rex",
	Raptor = "Razorclaw",
	Ostrich = "Thunderstrut",
	DireWolf = "Shadowfang",
	Griffin = "Stormtalon",
	FrostWyvern = "Glacier Wyrm",
	Mammoth = "Titan Tusk",
	LavaTRex = "Inferno Rex",
	Phoenix = "Solar Phoenix",
	CosmicDragon = "Void Dragon",
	StarPterodactyl = "Nova Ptera",
	Thornback = "Thornback",
	Frostbyte = "Frostbyte",
	Voltwing = "Voltwing",
	Embergeist = "Embergeist",
	AstralKitsune = "Astral Kitsune",
} :: { [string]: string }

-- Any species not listed (old saves, new pets added later) fights with these.
TowerConfig.DefaultSpecies = { Element = "Earth", Power = 12, Health = 100, Speed = 100, Basic = "Bonk" } :: Base

-- Pokemon-style types. Each beats the next one in the circle (x1.5) and is weak to the one before it (x0.75).
-- Cosmic sits outside the circle: x1.25 against every other type, x1 against Cosmic.
TowerConfig.TypeCircle = { "Fire", "Nature", "Earth", "Storm", "Ice" }
TowerConfig.Strong, TowerConfig.Weak, TowerConfig.CosmicBonus = 1.5, 0.75, 1.25
-- Second attack: every pet rolls one move of its own type on hatch. Mult x Power per hit; Slow = longer wait after it.
TowerConfig.TypeMoves = {
	Fire = { { Name = "Ember", Mult = 1.4, Slow = 1.3 }, { Name = "Flame Burst", Mult = 1.6, Slow = 1.5 }, { Name = "Heat Wave", Mult = 1.8, Slow = 1.7 } },
	Nature = { { Name = "Vine Whip", Mult = 1.4, Slow = 1.3 }, { Name = "Leaf Blade", Mult = 1.6, Slow = 1.5 }, { Name = "Thorn Storm", Mult = 1.8, Slow = 1.7 } },
	Earth = { { Name = "Mud Toss", Mult = 1.4, Slow = 1.3 }, { Name = "Quake", Mult = 1.6, Slow = 1.5 }, { Name = "Mega Stomp", Mult = 1.8, Slow = 1.7 } },
	Storm = { { Name = "Spark", Mult = 1.4, Slow = 1.3 }, { Name = "Gust", Mult = 1.6, Slow = 1.5 }, { Name = "Thunder", Mult = 1.8, Slow = 1.7 } },
	Ice = { { Name = "Ice Shard", Mult = 1.4, Slow = 1.3 }, { Name = "Frost Fang", Mult = 1.6, Slow = 1.5 }, { Name = "Blizzard", Mult = 1.8, Slow = 1.7 } },
	Cosmic = { { Name = "Star Spark", Mult = 1.4, Slow = 1.3 }, { Name = "Moon Beam", Mult = 1.6, Slow = 1.5 }, { Name = "Meteor", Mult = 1.8, Slow = 1.7 } },
} :: { [string]: { { Name: string, Mult: number, Slow: number } } }

TowerConfig.Rarities = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }
TowerConfig.RarityStat = { Common = 1, Uncommon = 1.2, Rare = 1.45, Epic = 1.75, Legendary = 2.2 } :: { [string]: number }
-- carter: Golden 1.5x, Rainbow 2x. Skeleton and Silver Cosmic are rarer, so they sit just above their neighbours.
TowerConfig.VariantStat = { Natural = 1, Golden = 1.5, Skeleton = 1.75, Rainbow = 2, SilverCosmic = 2.5 } :: { [string]: number }
TowerConfig.RollMin = 0.8
TowerConfig.RollMax = 1.2
-- Grade from the average of the three rolls, mapped to 0..1. Below B is C.
TowerConfig.Grades = { { Grade = "S", Min = 0.85 }, { Grade = "A", Min = 0.6 }, { Grade = "B", Min = 0.3 } }

-- Specials match the pet's type (Fire Puff only on Fire pets, and so on); ones with no Element suit any type.
-- Every circle type has a MinRarity 1 special; a Common Cosmic pet gets the lowest any-type one (PetStats.roll).
TowerConfig.Specials = {
	{ Id = "FirePuff", Name = "Fire Puff", Kind = "Burn", Value = 0.6, MinRarity = 1, Element = "Fire" }, -- burn: Value x Power per second, 4 s
	{ Id = "IceBreath", Name = "Ice Breath", Kind = "Slow", Value = 4, MinRarity = 1, Element = "Ice" }, -- all mobs attack at half speed for Value s
	{ Id = "Zap", Name = "Zap", Kind = "Chain", Value = 2, MinRarity = 1, Element = "Storm" }, -- Value x Power to up to 3 mobs
	{ Id = "HealSong", Name = "Heal Song", Kind = "Heal", Value = 0.35, MinRarity = 1, Element = "Nature" }, -- heals every team pet by Value x max health
	{ Id = "Shield", Name = "Bubble Shield", Kind = "Shield", Value = 0.4, MinRarity = 2 }, -- each pet gets Value x max health shield
	{ Id = "BigStomp", Name = "Big Stomp", Kind = "Stomp", Value = 2.5, MinRarity = 1, Element = "Earth" }, -- Value x Power to every mob
	{ Id = "DashStrike", Name = "Dash Strike", Kind = "Dash", Value = 6, MinRarity = 3 }, -- Value x Power to the front mob
	{ Id = "LuckyHit", Name = "Lucky Hit", Kind = "Crit", Value = 8, MinRarity = 4 }, -- Value x Power, one mob, at random
} :: { Special }

TowerConfig.Mobs = {
	Slime = { Id = "Slime", Element = "Nature", Name = "Slime", Health = 45, Power = 4, Speed = 80, Boss = false },
	Beetle = { Id = "Beetle", Element = "Earth", Name = "Grumpy Beetle", Health = 60, Power = 5, Speed = 90, Boss = false },
	Mushroom = { Id = "Mushroom", Element = "Nature", Name = "Mushroom Hopper", Health = 50, Power = 6, Speed = 100, Boss = false },
	Snail = { Id = "Snail", Element = "Earth", Name = "Thorn Snail", Health = 90, Power = 5, Speed = 60, Boss = false },
	Crab = { Id = "Crab", Element = "Ice", Name = "Snappy Crab", Health = 80, Power = 7, Speed = 85, Boss = false },
	Ghost = { Id = "Ghost", Element = "Storm", Name = "Ghost Puff", Health = 55, Power = 8, Speed = 110, Boss = false },
	-- Bosses (carter): giant, angry versions of the pets. Pet = species model to scale up, tint red, glowing eyes.
	BossRaptor = { Id = "BossRaptor", Element = "Nature", Name = "Angry Razorclaw", Pet = "Raptor", Health = 380, Power = 9, Speed = 80, Boss = true },
	BossDireWolf = { Id = "BossDireWolf", Element = "Storm", Name = "Angry Shadowfang", Pet = "DireWolf", Health = 420, Power = 10, Speed = 80, Boss = true },
	BossMammoth = { Id = "BossMammoth", Element = "Earth", Name = "Angry Titan Tusk", Pet = "Mammoth", Health = 520, Power = 10, Speed = 60, Boss = true },
	BossGriffin = { Id = "BossGriffin", Element = "Storm", Name = "Angry Stormtalon", Pet = "Griffin", Health = 400, Power = 12, Speed = 95, Boss = true },
	BossFrostWyvern = { Id = "BossFrostWyvern", Element = "Ice", Name = "Angry Glacier Wyrm", Pet = "FrostWyvern", Health = 450, Power = 13, Speed = 90, Boss = true },
	BossLavaTRex = { Id = "BossLavaTRex", Element = "Fire", Name = "Angry Inferno Rex", Pet = "LavaTRex", Health = 600, Power = 14, Speed = 85, Boss = true },
} :: { [string]: Mob }
-- Which normal mobs appear on floors 1-5, 6-10, ... and the boss at the end of each band.
TowerConfig.Bands = {
	{ Mobs = { "Slime", "Beetle" }, Boss = "BossRaptor" },
	{ Mobs = { "Beetle", "Mushroom", "Snail" }, Boss = "BossDireWolf" },
	{ Mobs = { "Snail", "Crab", "Mushroom" }, Boss = "BossMammoth" },
	{ Mobs = { "Crab", "Ghost", "Mushroom" }, Boss = "BossGriffin" },
	{ Mobs = { "Ghost", "Crab", "Snail" }, Boss = "BossFrostWyvern" },
	{ Mobs = { "Ghost", "Crab", "Beetle" }, Boss = "BossLavaTRex" },
}

-- Endless (carter): floors never run out, mobs keep getting tougher; the board ranks the highest floor.
-- Bands repeat after the last one, stats keep growing.
-- Floor look (carter): changes every ThemeEvery floors, jungle -> lava -> ice -> space, then loops.
TowerConfig.ThemeEvery = 10
-- The first wave of a new theme (floors 1, 11, 21, ...) waits this long before the pets fight, so the theme title pill
-- ("JUNGLE · FLOORS 1-10", TowerFx.titleCard: 1.6 s + fade) is gone before the first hit (Studio 2026-10-14: it sat
-- over the pets while they fought). The client also takes it down at the first hit.
TowerConfig.TitleHold = 2.2
TowerConfig.Themes = {
	{ Id = "Jungle", Name = "Jungle", Floor = Color3.fromRGB(120, 180, 90), Ring = Color3.fromRGB(150, 110, 70), Pillar = Color3.fromRGB(176, 170, 150), Cap = Color3.fromRGB(96, 172, 84), Glow = Color3.fromRGB(170, 240, 120) },
	{ Id = "Lava", Name = "Lava", Floor = Color3.fromRGB(140, 94, 70), Ring = Color3.fromRGB(255, 110, 40), Pillar = Color3.fromRGB(150, 70, 44), Cap = Color3.fromRGB(255, 140, 50), Glow = Color3.fromRGB(255, 90, 30) },
	{ Id = "Ice", Name = "Ice", Floor = Color3.fromRGB(215, 240, 255), Ring = Color3.fromRGB(140, 200, 255), Pillar = Color3.fromRGB(170, 215, 245), Cap = Color3.fromRGB(240, 250, 255), Glow = Color3.fromRGB(150, 230, 255) },
	{ Id = "Space", Name = "Space", Floor = Color3.fromRGB(58, 48, 110), Ring = Color3.fromRGB(190, 120, 255), Pillar = Color3.fromRGB(84, 66, 150), Cap = Color3.fromRGB(255, 230, 120), Glow = Color3.fromRGB(200, 160, 255) },
}
TowerConfig.BossEvery = 5 -- floors 5, 10, ... are boss floors; they are also checkpoints
TowerConfig.FloorGrowth = 0.16 -- mob health and power grow by this much per floor
TowerConfig.PartyHealthPerPlayer = 0.6 -- extra mob health per extra player (rules support parties; tower is solo)
TowerConfig.TeamSize = 3 -- pets per player
TowerConfig.MaxPlayers = 1 -- solo (carter)

-- Pet levels from tower XP (carter). Level L -> L+1 costs XpBase + XpStep * (L - 1). Each level adds LevelStat
-- to Power and Health (Speed a quarter of that). XP is saved per pet; leaving keeps what was earned.
-- LevelStat 0.14 (carter 2026-10-14): a maxed Common (Lv 10, x2.26) slightly beats a fresh Legendary (x2.2); a maxed
-- Legendary (Lv 50) still wins by far.
TowerConfig.Levels = { XpBase = 40, XpStep = 25, Max = 100, LevelStat = 0.14 }
-- Rarity sets how high a pet can grow (carter 2026-10-14): training stops at the cap. Species in CapSpecies override
-- (Void Dragon, the 1/1000 pet, can reach 100). Uncommon sits between Common and Rare.
TowerConfig.LevelCaps = { Common = 10, Uncommon = 15, Rare = 20, Epic = 30, Legendary = 50 } :: { [string]: number }
TowerConfig.CapSpecies = { CosmicDragon = 100 } :: { [string]: number }
-- Only pets of this rarity or rarer (index into Rarities) bring a SPECIAL to a Pet Battle (carter 2026-10-14).
TowerConfig.SpecialMinRarity = 4 -- Epic
-- EVOLVE (carter 2026-10-14): a pet at its level cap merges with Copies - 1 other copies of the same species and rarity
-- (at the same stage) into its next stage, up to MaxStage. Each stage raises the cap by CapBonus levels, multiplies
-- every stat by (1 + StatBonus * stage) and draws the pet Scale bigger per stage with a glow (PetModel).
-- Enabled: carter 2026-10-16 "remove evolution 4 now": EVOLVE is off (no button, server refuses). Pets that already
-- evolved keep their stars and bonuses.
TowerConfig.Evolve = { Enabled = false, MaxStage = 2, Copies = 3, CapBonus = 10, StatBonus = 0.2, Scale = 0.15 }
TowerConfig.Xp = { PerFloor = 20, FloorStep = 4, LossShare = 0.5 } -- floor f clear: PerFloor + FloorStep * f to each team pet

-- Revive after a loss (carter picked Robux revive, 2026-10-11): pets come back at Health of max, mobs keep theirs.
-- ProductId = the Developer Product carter made on the Creator Dashboard (0 would turn revive off).
-- At most MaxPaid revives per climb so the floor board can't be bought outright.
TowerConfig.Revive = { Health = 0.5, Free = 0, MaxPaid = 3, ProductId = 3717828140 } -- carter's "Tower Revive" product (2026-10-11)
TowerConfig.SpecialCharge = 100 -- damage a player's pets must deal to fill the SPECIAL button
TowerConfig.FloorTimeLimit = 90 -- seconds; running out ends the run (rewards so far are kept)
TowerConfig.Tick = 0.1 -- server fight step in seconds

TowerConfig.Rewards = {
	CoinsPerFloor = 15, -- x floor number
	BossCoins = 150, -- x boss band number, on top
}

return TowerConfig
