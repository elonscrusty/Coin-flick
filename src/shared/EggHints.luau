--!strict
-- Pure rule for the egg wobble and chirp hints (no Roblox services; tests/test_egg_hints.luau drives it).
-- Every few seconds the server picks ONE anchor egg that is still in the pile and wobbles a small patch of eggs
-- near a jittered point around it (EggHints.patch); the anchor's id is never sent on its own and the anchor is
-- usually outside its own patch. With a small chance the pick is the pet egg (when it is still in the pile),
-- otherwise a uniformly random other pile egg. Every zone mixes in decoys; the Meadow (EggConfig.Wobble.SlowTiers)
-- only wobbles less often, with a slightly higher pet egg chance.

local EggConfig = require(script.Parent.EggConfig)

local EggHints = {}

-- Ids of the eggs still in the pile (state InPile), sorted so the pick depends on the rng only.
-- `rocks` is RoundRocks' Core.Rocks: { [id]: { State: string } }.
function EggHints.pileIds(rocks: { [number]: any }): { number }
	local out = {}
	for id, r in rocks do
		if r.State == "InPile" then
			table.insert(out, id)
		end
	end
	table.sort(out)
	return out
end

-- One pick. `pile` lists the candidate ids, `target` is the pet egg id (nil when unknown, e.g. the
-- practice pile), `chance` the probability of picking the pet egg while it is among the candidates.
-- Returns nil only when the pile is empty. Never returns an id that is not in `pile`.
function EggHints.pick(rng: Random, pile: { number }, target: number?, chance: number): number?
	local n = #pile
	if n == 0 then
		return nil
	end
	local targetIn = target ~= nil and table.find(pile, target) ~= nil
	local others = if targetIn then n - 1 else n
	if targetIn and (others == 0 or rng:NextNumber() < chance) then
		return target
	end
	-- uniform among the non-target pile eggs
	local k = rng:NextInteger(1, others)
	for _, id in pile do
		if not targetIn or id ~= target then
			k -= 1
			if k == 0 then
				return id
			end
		end
	end
	return nil
end

-- True when `tier` (code tier id, e.g. "Gravel" = Meadow) wobbles at the slower Meadow pace.
function EggHints.slowTier(tier: string?): boolean
	return tier ~= nil and EggConfig.Wobble.SlowTiers[tier] == true
end

-- Gap range (seconds) between two wobble picks in `tier`.
function EggHints.gapRange(tier: string?): (number, number)
	local w = EggConfig.Wobble
	if EggHints.slowTier(tier) then
		return w.MeadowMinGap, w.MeadowMaxGap
	end
	return w.MinGap, w.MaxGap
end

-- Chance that a wobble pick in `tier` is the pet egg (while it is in the pile).
function EggHints.targetChance(tier: string?): number
	local w = EggConfig.Wobble
	return if EggHints.slowTier(tier) then w.MeadowTargetChance else w.TargetChance
end

-- The wobble pick for a tier: EggHints.pick with the tier's target chance. Every tier mixes in decoys, and a
-- pile without the pet egg (taken, or the practice pile) still wobbles decoys, so wobbles never stop early.
function EggHints.pickForTier(rng: Random, pile: { number }, target: number?, tier: string?): number?
	return EggHints.pick(rng, pile, target, EggHints.targetChance(tier))
end

-- Patch hint: the eggs that wobble together for one pick. `anchor` = the picked egg's position, `eggs` = the
-- pile eggs as { Id, Pos } (any order). Returns the ids within `radius` of a point `jMin..jMax` studs from the
-- anchor (random flat direction), sorted by id and capped at `max` (the closest to the point are kept). The
-- anchor is not special: it is listed only if it happens to lie in the patch. Empty when nothing is near.
function EggHints.patch(rng: Random, anchor: Vector3, eggs: { { Id: number, Pos: Vector3 } }, radius: number, jMin: number, jMax: number, max: number): { number }
	local a = rng:NextNumber(0, math.pi * 2)
	local d = rng:NextNumber(jMin, jMax)
	local center = anchor + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
	local near = {}
	for _, e in eggs do
		local flat = Vector3.new(e.Pos.X - center.X, 0, e.Pos.Z - center.Z).Magnitude
		if flat <= radius then
			table.insert(near, { Id = e.Id, D = flat })
		end
	end
	table.sort(near, function(x, y)
		return x.D < y.D
	end)
	local out = {}
	for i = 1, math.min(#near, max) do
		table.insert(out, near[i].Id)
	end
	table.sort(out)
	return out
end

-- Chirp source for one listener: among the pile eggs within `radius` (flat) of `playerPos` (`eggs` as { Id, Pos }),
-- the pet egg with `chance` when it is one of them, else a uniformly random other nearby egg. Returns the chosen
-- egg's position, or nil when no pile egg is that close. The caller decides whether a chirp happens at all.
function EggHints.chirpSource(rng: Random, eggs: { { Id: number, Pos: Vector3 } }, playerPos: Vector3, radius: number, target: number?, chance: number): Vector3?
	local ids: { number } = {}
	local posOf: { [number]: Vector3 } = {}
	for _, e in eggs do
		if Vector3.new(e.Pos.X - playerPos.X, 0, e.Pos.Z - playerPos.Z).Magnitude <= radius then
			table.insert(ids, e.Id)
			posOf[e.Id] = e.Pos
		end
	end
	table.sort(ids)
	local id = EggHints.pick(rng, ids, target, chance)
	return if id then posOf[id] else nil
end

-- Chirp point: `eggPos` = the chirping egg's world position (nil when there is none), `playerPos` = the
-- listener's root position. Returns the point to play the chirp at, or nil when the player is farther than
-- `radius`. The point is `jMin..jMax` studs from the egg in a random flat direction (never the egg).
function EggHints.chirpPoint(rng: Random, eggPos: Vector3?, playerPos: Vector3, radius: number, jMin: number, jMax: number): Vector3?
	if eggPos == nil or (playerPos - eggPos).Magnitude > radius then
		return nil
	end
	local a = rng:NextNumber(0, math.pi * 2)
	local d = rng:NextNumber(jMin, jMax)
	return eggPos + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
end

return EggHints
