--!strict
-- Pet effects rules, pure: no Roblox services, unit-tested in tests/test_pet_fx.luau. Client PetFx draws what these
-- say; nothing here touches the world or the server.
--   * look(rarity, species, modifier): the aura tier and how much of each piece a pet gets. The tiers climb
--     Common 0, Uncommon 1, Rare 2, Epic 3, Legendary 4, chase pet 5 (Config.Minerals Chase = true), Void Dragon 6.
--     Golden and Rainbow pets keep their tier and swap the colour (gold, or a hue that cycles).
--   * lod(distance, lowEffects): how much of a one-shot burst to show (1 full, 0.5 half, 0 skip).
--   * budget: a token bucket that caps particles emitted per second for the whole client (phones).
--   * squash(k): the happy bounce, two hops with stretch on take-off and squash on landing, volume kept.
--   * hit(element, crit): the fight hit spark burst (count, size, colour) and whether a CRIT! pop shows.

local Config = require(script.Parent.Config)

local PetFxRules = {}

PetFxRules.VOID_SPECIES = "CosmicDragon" -- the Void Dragon, the rarest pet (1 in 1000)
PetFxRules.TOP_TIER = 6

local TIER_OF: { [string]: number } = { Common = 0, Uncommon = 1, Rare = 2, Epic = 3, Legendary = 4 }

-- What each tier gets. Ring = ground ring diameter per pet scale (0 = none); Alpha = ring transparency;
-- Motes = rising sparkle rate; Orbs = little lights circling the pet; Light = glow brightness;
-- Pillar = soft light column (chase pets and up); Trail = sparkles per second while the pet walks.
export type Look = {
	Tier: number,
	Ring: number,
	Alpha: number,
	Motes: number,
	Orbs: number,
	Light: number,
	Pillar: boolean,
	Trail: number,
	Color: Color3,
	Accent: Color3,
	Rainbow: boolean,
	Void: boolean,
}

local TIERS = {
	[0] = { Ring = 0, Alpha = 1, Motes = 0, Orbs = 0, Light = 0, Pillar = false, Trail = 0 },
	[1] = { Ring = 2.6, Alpha = 0.65, Motes = 0, Orbs = 0, Light = 0, Pillar = false, Trail = 2 },
	[2] = { Ring = 2.9, Alpha = 0.62, Motes = 2, Orbs = 0, Light = 0, Pillar = false, Trail = 4 },
	[3] = { Ring = 3.2, Alpha = 0.58, Motes = 3, Orbs = 2, Light = 0.4, Pillar = false, Trail = 6 },
	[4] = { Ring = 3.5, Alpha = 0.54, Motes = 5, Orbs = 3, Light = 0.7, Pillar = false, Trail = 8 },
	[5] = { Ring = 3.8, Alpha = 0.5, Motes = 6, Orbs = 4, Light = 0.9, Pillar = true, Trail = 10 },
	[6] = { Ring = 4.2, Alpha = 0.46, Motes = 8, Orbs = 5, Light = 1.1, Pillar = true, Trail = 12 },
}

local GOLD = Color3.fromRGB(255, 205, 70)
local GOLD_LIGHT = Color3.fromRGB(255, 244, 190)
local VOID = Color3.fromRGB(150, 70, 255)
local VOID_RIM = Color3.fromRGB(240, 140, 255)

function PetFxRules.tier(rarity: any, species: any, _modifier: any): number
	if species == PetFxRules.VOID_SPECIES then
		return 6
	end
	local sp: any = if type(species) == "string" then (Config.Minerals :: any)[species] else nil
	if sp and sp.Chase == true then
		return 5
	end
	return TIER_OF[tostring(rarity)] or 0
end

function PetFxRules.look(rarity: any, species: any, modifier: any): Look
	local tier = PetFxRules.tier(rarity, species, modifier)
	local base = TIERS[tier]
	local rc: Color3? = (Config.RarityColors :: any)[tostring(rarity)]
	local color = rc or (Config.RarityColors :: any).Common
	local sp: any = if type(species) == "string" then (Config.Minerals :: any)[species] else nil
	local accent: Color3 = if sp and type(sp.Rim) == "userdata" then sp.Rim else color
	if tier == 5 then
		color = accent -- a chase pet glows in its own rim colour
	elseif tier == 6 then
		color, accent = VOID, VOID_RIM
	end
	if modifier == "Golden" then
		color, accent = GOLD, GOLD_LIGHT
	end
	local fancy = modifier == "Golden" or modifier == "Rainbow"
	return {
		Tier = tier,
		-- a Golden / Rainbow Common still gets a small ring so the variant shows
		Ring = if base.Ring == 0 and fancy then TIERS[1].Ring else base.Ring,
		Alpha = if base.Ring == 0 and fancy then TIERS[1].Alpha else base.Alpha,
		Motes = base.Motes,
		Orbs = base.Orbs,
		Light = base.Light,
		Pillar = base.Pillar,
		Trail = if fancy then math.max(base.Trail, 4) else base.Trail,
		Color = color,
		Accent = accent,
		Rainbow = modifier == "Rainbow",
		Void = tier == 6,
	}
end

-- One-shot bursts: full near the camera, half further out, skipped far away. Low Effects shows a third.
PetFxRules.NEAR = 45
PetFxRules.FAR = 90
function PetFxRules.lod(distance: number, lowEffects: boolean?): number
	local k = if distance < PetFxRules.NEAR then 1 elseif distance < PetFxRules.FAR then 0.5 else 0
	return if lowEffects then k / 3 else k
end

-- Count after the level of detail: never more than asked, at least 1 when anything shows.
function PetFxRules.scaled(count: number, k: number): number
	if k <= 0 or count <= 0 then
		return 0
	end
	return math.max(1, math.floor(count * k + 0.5))
end

-- Whole-client particle budget for bursts (a phone stays smooth even in a 4-pet brawl).
export type Budget = { Rate: number, Cap: number, Tokens: number, At: number }
PetFxRules.BUDGET_RATE = 160 -- particles per second refilled
PetFxRules.BUDGET_CAP = 120 -- most particles one moment can spend

function PetFxRules.newBudget(rate: number?, cap: number?): Budget
	local c = cap or PetFxRules.BUDGET_CAP
	return { Rate = rate or PetFxRules.BUDGET_RATE, Cap = c, Tokens = c, At = 0 }
end

-- Asks for `want` particles at time `now`; returns how many may be emitted (0..want) and spends them.
function PetFxRules.spend(b: Budget, want: number, now: number): number
	if now > b.At then
		b.Tokens = math.min(b.Cap, b.Tokens + (now - b.At) * b.Rate)
		b.At = now
	end
	local give = math.clamp(math.floor(math.min(want, b.Tokens)), 0, math.max(0, want))
	b.Tokens -= give
	return give
end

-- Happy bounce: two hops over BOUNCE_TIME. Returns (height in studs per pet scale, sideways scale, up scale).
-- Stretch while rising, squash on each landing, and sideways = 1 / sqrt(up) so the pet keeps its volume.
PetFxRules.BOUNCE_TIME = 0.7
local HOPS = 2
function PetFxRules.squash(k: number): (number, number, number)
	if k <= 0 or k >= 1 then
		return 0, 1, 1
	end
	local h = k * HOPS
	local i = math.floor(h)
	local f = h - i
	local amp = if i == 0 then 1 else 0.6 -- the second hop is smaller
	local height = math.sin(f * math.pi) * 0.9 * amp
	local up: number
	if f < 0.15 then
		up = 1 - 0.18 * amp * (1 - f / 0.15) -- crouch before the jump / landing squash
	elseif f < 0.5 then
		up = 1 + 0.12 * amp * math.sin((f - 0.15) / 0.35 * math.pi) -- stretch on the way up
	elseif f > 0.85 then
		up = 1 - 0.18 * amp * ((f - 0.85) / 0.15) -- squash as the feet land
	else
		up = 1
	end
	return height, 1 / math.sqrt(up), up
end

-- Fight hit sparks. Element colours match the pet element traits in client PetFx.
PetFxRules.ELEMENT_COLORS = {
	Fire = Color3.fromRGB(255, 140, 40),
	Ice = Color3.fromRGB(150, 220, 255),
	Nature = Color3.fromRGB(130, 230, 90),
	Storm = Color3.fromRGB(255, 240, 110),
	Earth = Color3.fromRGB(205, 165, 110),
	Cosmic = Color3.fromRGB(210, 150, 255),
}
local WHITE = Color3.new(1, 1, 1)
export type Hit = { Count: number, Size: number, Speed: number, Color: Color3, Pop: boolean, Flash: number }
function PetFxRules.hit(element: any, crit: boolean?): Hit
	local c = (PetFxRules.ELEMENT_COLORS :: any)[tostring(element)] or WHITE
	if crit then
		return { Count = 18, Size = 0.5, Speed = 16, Color = c, Pop = true, Flash = 2.4 }
	end
	return { Count = 8, Size = 0.32, Speed = 10, Color = c, Pop = false, Flash = 1.2 }
end

-- KO poof and level-up blast sizes (particles before LOD and budget).
PetFxRules.KO_COUNT = 16
PetFxRules.LEVEL_COUNT = 24

return PetFxRules
