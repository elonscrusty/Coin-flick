--!strict
-- Tower stats for one pet copy (pure, tested in tests/test_pet_tower.luau).
-- Stats come from the pet's secret server-rolled Seed, so every pet already has them and nothing new is saved.
-- Same pet in, same stats out, on every server.

local TowerConfig = require(script.Parent.TowerConfig)

local PetStats = {}

export type Stats = {
	Power: number,
	Health: number,
	Speed: number,
	Grade: string,
	Level: number,
	Quality: number, -- 0..1, how good the three rolls were
	Element: string, -- Pokemon-style type
	Basic: string,
	Move: string, -- second attack, of the pet's own type
	MoveMult: number,
	MoveSlow: number,
	Special: string, -- TowerConfig.Specials Id
}

-- Evolve stage of a pet copy (0 = never evolved), always a whole number in 0..TowerConfig.Evolve.MaxStage.
function PetStats.stage(pet: any): number
	local e = if type(pet) == "table" then tonumber(pet.Evolve) else nil
	if not e or e ~= e then
		return 0
	end
	return math.clamp(math.floor(e), 0, TowerConfig.Evolve.MaxStage)
end

-- Highest level a pet can train to: its rarity's cap (TowerConfig.LevelCaps), or its species' own (Void Dragon),
-- plus TowerConfig.Evolve.CapBonus per evolve stage.
function PetStats.cap(pet: { Mineral: string?, Rarity: string? }?): number
	local L = TowerConfig.Levels
	if pet == nil then
		return L.Max
	end
	local c = (pet.Mineral and TowerConfig.CapSpecies[pet.Mineral]) or (pet.Rarity and TowerConfig.LevelCaps[pet.Rarity]) or L.Max
	return math.clamp(c + PetStats.stage(pet) * TowerConfig.Evolve.CapBonus, 1, L.Max)
end

-- Level from saved tower XP: (level, xp into this level, xp needed for the next). `cap` (PetStats.cap) stops the
-- climb: at the cap the last two are 0 (XP past it is kept but does nothing).
function PetStats.level(xp: number?, cap: number?): (number, number, number)
	local L = TowerConfig.Levels
	local top = math.clamp(cap or L.Max, 1, L.Max)
	local left = math.max(math.floor(tonumber(xp) or 0), 0)
	local level = 1
	while level < top do
		local need = L.XpBase + L.XpStep * (level - 1)
		if left < need then
			return level, left, need
		end
		left -= need
		level += 1
	end
	return top, 0, 0
end

-- Total XP from level 1 to reach `level` (dev /maxpet, tests).
function PetStats.xpForLevel(level: number): number
	local L = TowerConfig.Levels
	local total = 0
	for l = 1, math.clamp(math.floor(level), 1, L.Max) - 1 do
		total += L.XpBase + L.XpStep * (l - 1)
	end
	return total
end

-- Damage multiplier for an attack of type `att` hitting type `def`.
function PetStats.effect(att: string, def: string): number
	if att == "Cosmic" then
		return if def == "Cosmic" then 1 else TowerConfig.CosmicBonus
	end
	local circle = TowerConfig.TypeCircle
	local n = #circle
	for i, e in circle do
		if e == att then
			if circle[i % n + 1] == def then
				return TowerConfig.Strong
			elseif circle[(i - 2) % n + 1] == def then
				return TowerConfig.Weak
			end
		end
	end
	return 1
end

-- Small integer hash stream (deterministic and identical everywhere, unlike Random across platforms).
local function stream(seed: number)
	local s = (math.floor(seed) % 2147483646) + 1
	return function(): number
		s = (s * 48271) % 2147483647
		return s / 2147483647
	end
end

local function rarityIndex(rarity: string): number
	for i, r in TowerConfig.Rarities do
		if r == rarity then
			return i
		end
	end
	return 1
end

function PetStats.grade(quality: number): string
	for _, g in TowerConfig.Grades do
		if quality >= g.Min then
			return g.Grade
		end
	end
	return "C"
end

-- `pet` needs Mineral (species), Rarity, Modifier (variant) and Seed, i.e. a GeodeGen Specimen.
function PetStats.roll(pet: { Mineral: string, Rarity: string, Modifier: string?, Seed: number }, xp: number?): Stats
	local base = TowerConfig.Species[pet.Mineral] or TowerConfig.DefaultSpecies
	local nextNum = stream(pet.Seed)
	for _ = 1, 4 do -- decorrelate nearby seeds
		nextNum()
	end
	local span = TowerConfig.RollMax - TowerConfig.RollMin
	local rolls = {}
	local sum = 0
	for i = 1, 3 do
		rolls[i] = TowerConfig.RollMin + nextNum() * span
		sum += rolls[i]
	end
	local quality = math.clamp((sum / 3 - TowerConfig.RollMin) / span, 0, 1)
	local level = PetStats.level(xp, PetStats.cap(pet))
	local grow = 1 + TowerConfig.Levels.LevelStat * (level - 1)
	local mult = (TowerConfig.RarityStat[pet.Rarity] or 1) * (TowerConfig.VariantStat[pet.Modifier or "Natural"] or 1)
		* (1 + TowerConfig.Evolve.StatBonus * PetStats.stage(pet))

	local tier = rarityIndex(pet.Rarity)
	local pool = {}
	-- Only specials of the pet's own type (or of no type). If none is open at this rarity (Common Cosmic), the
	-- lowest-rarity matching one is used.
	local fallback: TowerConfig.Special? = nil
	for _, sp in TowerConfig.Specials do
		if sp.Element == nil or sp.Element == base.Element then
			if sp.MinRarity <= tier then
				table.insert(pool, sp.Id)
			end
			if fallback == nil or sp.MinRarity < fallback.MinRarity then
				fallback = sp
			end
		end
	end
	if #pool == 0 then
		table.insert(pool, if fallback then fallback.Id else TowerConfig.Specials[1].Id)
	end
	local special = pool[math.clamp(math.floor(nextNum() * #pool) + 1, 1, #pool)]
	-- Rarer pets can roll stronger type moves: Common gets the first, Uncommon up to the second, Rare+ any.
	local moves = TowerConfig.TypeMoves[base.Element] or TowerConfig.TypeMoves.Earth
	local reach = math.min(#moves, tier)
	local move = moves[math.clamp(math.floor(nextNum() * reach) + 1, 1, reach)]

	return {
		Power = math.floor(base.Power * rolls[1] * mult * grow + 0.5),
		Health = math.floor(base.Health * rolls[2] * mult * grow + 0.5),
		-- speed grows gently so fights stay readable
		Speed = math.floor(base.Speed * rolls[3] * mult ^ 0.25 * (1 + (grow - 1) / 4) + 0.5),
		Grade = PetStats.grade(quality),
		Level = level,
		Quality = quality,
		Element = base.Element,
		Basic = base.Basic,
		Move = move.Name,
		MoveMult = move.Mult,
		MoveSlow = move.Slow,
		Special = special,
	}
end

-- THE one "bigger = better" POWER number players see (Pet Book, Pet Tower, hatch reveal, Equip Best; PvP should use it
-- too): attack counts most. Rarity, Golden / Rainbow and level are already inside the rolled stats.
function PetStats.power(s: { Power: number, Health: number, Speed: number }): number
	return math.floor(s.Power * 3 + s.Health * 0.5 + s.Speed * 0.2 + 0.5)
end

-- A pet's POWER (0 without a Seed). `xp` defaults to the pet's own TowerXP (the public view carries it).
function PetStats.powerOfPet(pet: { [string]: any }, xp: number?): number
	if type(pet.Seed) ~= "number" or type(pet.Mineral) ~= "string" or type(pet.Rarity) ~= "string" then
		return 0
	end
	local x = xp or (if type(pet.TowerXP) == "number" then pet.TowerXP else nil)
	return PetStats.power(PetStats.roll(pet :: any, x))
end

function PetStats.special(id: string): TowerConfig.Special?
	for _, sp in TowerConfig.Specials do
		if sp.Id == id then
			return sp
		end
	end
	return nil
end

return PetStats
