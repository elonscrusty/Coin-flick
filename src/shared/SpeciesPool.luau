--!strict
-- Which pet species a zone can hatch, and with what chance (pure; tests/test_species_pool.luau).
--   * Weekly pets (Config.WeeklyPets) are hidden until their week starts.
--   * Chase pets (species Chase = true) are Legendary only: a Legendary hatch in a zone with a released chase pet is
--     always that pet. Every other released species of the zone shares the other rarities equally.
-- GeodeGen.roll picks with SpeciesPool.pick; the shop odds (LuckEvents.eggOdds) and the Pet Book use SpeciesPool.chance,
-- so the printed odds are exactly the rolled ones.

local Config = require(script.Parent.Config)

local SpeciesPool = {}

-- Unix time a weekly species unlocks, nil when it is not weekly. math.huge while Start is unset (hidden).
function SpeciesPool.releaseTime(id: string): number?
	local sp: any = (Config.Minerals :: any)[id]
	if not sp or not sp.Weekly then
		return nil
	end
	local w = Config.WeeklyPets
	local idx = table.find(w.Order, id)
	if not idx or (tonumber(w.Start) or 0) <= 0 then
		return math.huge
	end
	return w.Start + (idx - 1) * w.Days * 86400
end

function SpeciesPool.released(id: string, now: number): boolean
	local t = SpeciesPool.releaseTime(id)
	return t == nil or now >= t
end

-- Released species of a zone, in the zone's list order: (normal ids, chase id or nil).
function SpeciesPool.available(tierId: string, now: number): ({ string }, string?)
	local tier = (Config.Tiers :: any)[tierId]
	local normal, chase = {}, nil
	if not tier then
		return normal, nil
	end
	for _, id in tier.Minerals do
		local sp: any = (Config.Minerals :: any)[id]
		if sp and not sp.TowerOnly and SpeciesPool.released(id, now) then
			if sp.Chase then
				chase = chase or id
			else
				table.insert(normal, id)
			end
		end
	end
	return normal, chase
end

-- Every released species of a zone (normal first, then the chase pet).
function SpeciesPool.list(tierId: string, now: number): { string }
	local normal, chase = SpeciesPool.available(tierId, now)
	local out = table.clone(normal)
	if chase then
		table.insert(out, chase)
	end
	return out
end

-- The species for a pet of `rarity` in this zone.
function SpeciesPool.pick(rng: Random, tierId: string, rarity: string, now: number): string
	local normal, chase = SpeciesPool.available(tierId, now)
	if chase and (rarity == "Legendary" or #normal == 0) then
		return chase
	end
	if #normal == 0 then
		-- nothing released here (bad config): any released pile species, in zone order, never a tower-only one
		for _, tid in Config.TierOrder do
			local other = SpeciesPool.available(tid, now)
			if #other > 0 then
				return other[1]
			end
		end
		local tier = (Config.Tiers :: any)[tierId]
		return tier.Minerals[1]
	end
	return normal[rng:NextInteger(1, #normal)]
end

-- Chance that a pet of this zone is species `id`, given the rarity chances `rarityP` ({ [rarity] = 0..1 }).
function SpeciesPool.chance(tierId: string, id: string, now: number, rarityP: { [string]: number }): number
	local normal, chase = SpeciesPool.available(tierId, now)
	local legendary = rarityP.Legendary or 0
	if chase and id == chase then
		return if #normal == 0 then 1 else legendary
	end
	if not table.find(normal, id) then
		return 0
	end
	local rest = if chase then 1 - legendary else 1
	return rest / #normal
end

-- True when this species can only hatch at this rarity (the chase pet: Legendary).
function SpeciesPool.rarityAllowed(id: string, rarity: string): boolean
	local sp: any = (Config.Minerals :: any)[id]
	return not (sp and sp.Chase) or rarity == "Legendary"
end

return SpeciesPool
