--!strict
-- Pure specimen generation. The server rolls once per won match and stores the result;
-- nothing here is re-rolled on reveal, rejoin, inspect or sell.

local Config = require(script.Parent.Config)
local SpeciesPool = require(script.Parent.SpeciesPool)
local RobuxConfig = require(script.Parent.RobuxConfig)
local LaunchPerks = require(script.Parent.LaunchPerks)

local GeodeGen = {}

export type Specimen = {
	Id: string,
	MatchKey: string,
	Tier: string,
	Mineral: string,
	Rarity: string,
	Formation: string,
	Modifier: string,
	Mass: number,
	Seed: number,
	Value: number,
	ConfigVersion: number,
	Found: number,
	Favorite: boolean,
	Solo: boolean,
	Nickname: string?, -- the owner's filtered pet name (PetService rename), nil = the species name
	Evolve: number?, -- evolve stage (PvpService evolve; nil = never evolved)
	Shiny: boolean?, -- 1 in 100 shiny pet (LaunchPerks.Shiny): sparkle shimmer, "Shiny" name, 2x value; nil = not shiny
}

local function pickWeighted(rng: Random, order: { string }, weights: { [string]: number }): string
	local total = 0
	for _, k in order do
		total += weights[k]
	end
	local roll = rng:NextNumber() * total
	for _, k in order do
		roll -= weights[k]
		if roll < 0 then
			return k
		end
	end
	return order[#order]
end
GeodeGen.pickWeighted = pickWeighted

function GeodeGen.rollMass(rng: Random): number
	local roll = rng:NextNumber() * 100
	local band = Config.MassBands[#Config.MassBands]
	for _, b in Config.MassBands do
		roll -= b.Weight
		if roll < 0 then
			band = b
			break
		end
	end
	local raw = band.Min + rng:NextNumber() * (band.Max - band.Min)
	return math.clamp(math.floor(raw * 100 + 0.5) / 100, band.Min, band.Max)
end

function GeodeGen.value(tierId: string, rarity: string, modifier: string, mass: number, shiny: boolean?): number
	local tier = Config.Tiers[tierId]
	local v = tier.GeodeBase * Config.RarityMult[rarity] * Config.ModifierMult[modifier] * (0.75 + 0.25 * mass) * LaunchPerks.shinyMult(shiny)
	return math.floor(v)
end

-- Visual scale from mass: cube root, clamped so big specimens still fit a large stand.
function GeodeGen.visualScale(mass: number): number
	return math.clamp((mass / 2) ^ (1 / 3), 0.7, 2.2)
end

-- Rarity weights for a finder with Luck (every source added up, LuckEvents.total): Rare and better weigh (1 + luck)
-- times more; luck is clamped to [0, RobuxConfig.MaxLuck]. Luck only changes the pet the finder hatches, never which
-- egg hides it or who finds it.
-- baseWeights: another rarity table (a Robux shop Rare / Mythic egg, RobuxConfig.Eggs); nil = the race egg odds.
function GeodeGen.rarityWeights(luck: number?, baseWeights: { [string]: number }?): { [string]: number }
	local l = math.clamp(if luck == luck then luck or 0 else 0, 0, RobuxConfig.MaxLuck)
	local w: { [string]: number } = {}
	local base: { [string]: number } = baseWeights or Config.RarityWeights
	for _, k in Config.Rarities do
		local v = base[k] or 0
		w[k] = if k == "Common" or k == "Uncommon" then v else v * (1 + l)
	end
	return w
end

-- shinyOneIn: this egg's shiny chance (1 in N); nil = LaunchPerks.Shiny.OneIn. Shiny comes from the Seed (one more
-- draw at the very end), so every other roll is exactly what it was before shiny pets existed.
function GeodeGen.roll(rng: Random, tierId: string, id: string, matchKey: string, now: number, solo: boolean, luck: number?, baseWeights: { [string]: number }?, shinyOneIn: number?): Specimen
	local tier = Config.Tiers[tierId]
	assert(tier, "unknown tier " .. tostring(tierId))
	local rarity = pickWeighted(rng, Config.Rarities, GeodeGen.rarityWeights(luck, baseWeights))
	local mineral = SpeciesPool.pick(rng, tierId, rarity, now) -- weekly pets hidden until out; chase pet = Legendary
	local formation = pickWeighted(rng, Config.Formations, Config.FormationWeights)
	local modifier = pickWeighted(rng, Config.Modifiers, Config.ModifierWeights)
	local mass = GeodeGen.rollMass(rng)
	local seed = rng:NextInteger(1, 2 ^ 30)
	local shiny = LaunchPerks.shinyFromSeed(seed, shinyOneIn)
	return {
		Id = id,
		MatchKey = matchKey,
		Tier = tierId,
		Mineral = mineral,
		Rarity = rarity,
		Formation = formation,
		Modifier = modifier,
		Mass = mass,
		Seed = seed,
		Value = GeodeGen.value(tierId, rarity, modifier, mass, shiny),
		ConfigVersion = Config.Version,
		Found = math.floor(now),
		Favorite = false,
		Solo = solo,
		Shiny = if shiny then true else nil,
	}
end

-- Sanitised view for clients / gallery labels: no match internals.
function GeodeGen.public(s: Specimen): { [string]: any }
	return {
		Id = s.Id,
		Tier = s.Tier,
		Mineral = s.Mineral,
		Rarity = s.Rarity,
		Formation = s.Formation,
		Modifier = s.Modifier,
		Mass = s.Mass,
		Seed = s.Seed,
		Value = s.Value,
		Found = s.Found,
		Favorite = s.Favorite,
		Solo = s.Solo,
		Nickname = s.Nickname,
		Evolve = s.Evolve,
		Shiny = s.Shiny,
		TowerXP = (s :: any).TowerXP, -- pet tower experience when present (PetRules.level)
	}
end

-- short = true: a card-sized name (species may set Short, e.g. a long name cut for cards).
function GeodeGen.displayName(s: { Mineral: string, Modifier: string }, short: boolean?): string
	local m: any = (Config.Minerals :: any)[s.Mineral]
	local name = if m then (if short and m.Short then m.Short else m.Name) else s.Mineral
	if s.Modifier ~= "Natural" then
		name = (Config.ModifierNames[s.Modifier] or s.Modifier) .. " " .. name
	end
	if (s :: any).Shiny == true then
		name = "Shiny " .. name
	end
	return name
end

return GeodeGen
