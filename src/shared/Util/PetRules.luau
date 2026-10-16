--!strict
-- Coin pet rules, pure (numbers and tables in, numbers and tables out).
-- Goals unlock pets, an active pet flips its own coin for cash, and every pet
-- flip is xp toward the next level. No randomness anywhere: pets are earned.

local PetConfig = require(script.Parent.Parent.PetConfig)
local Types = require(script.Parent.Parent.Types)
local Economy = require(script.Parent.Economy)

type Profile = Types.Profile
type PetDef = PetConfig.PetDef

local PetRules = {}

function PetRules.def(id: unknown): PetDef?
	for _, def in PetConfig.Pets do
		if def.id == id then
			return def
		end
	end
	return nil
end

-- Xp to go from `level` to `level + 1`, or nil at max level.
function PetRules.xpToNext(level: number): number?
	if level >= PetConfig.MAX_LEVEL then
		return nil
	end
	return math.floor(PetConfig.XP_BASE * PetConfig.XP_GROWTH ^ (level - 1) + 0.5)
end

function PetRules.interval(def: PetDef, level: number): number
	return def.interval * PetConfig.LEVEL_SPEED ^ (level - 1)
end

function PetRules.cashMult(def: PetDef, level: number): number
	return def.mult * (1 + PetConfig.LEVEL_CASH * (level - 1))
end

-- Cash for one pet flip. `bonus` is the server's mega boost x 2x pass (>= 1).
function PetRules.flipCash(profile: Profile, def: PetDef, level: number, bonus: number?): number
	local value = Economy.cashPerHeads(profile) * PetRules.cashMult(def, level) * math.max(1, bonus or 1)
	return math.max(1, math.floor(value + 0.5))
end

-- (how far you are, how far you need to be) for a pet's goal.
function PetRules.progress(profile: Profile, def: PetDef): (number, number)
	local current = 0
	if def.goal == "free" then
		return 0, 0
	elseif def.goal == "flips" then
		current = profile.stats.flips
	elseif def.goal == "headsInRow" then
		current = profile.stats.bestStreak -- the one streak system (GameLogic.applyStreak)
	elseif def.goal == "megaBeats" then
		current = profile.petProgress.megaBeats
	elseif def.goal == "resets" then
		current = profile.resets
	end
	return math.min(current, def.target), def.target
end

function PetRules.goalMet(profile: Profile, def: PetDef): boolean
	if def.goal == "free" then
		return true
	end
	local current, target = PetRules.progress(profile, def)
	return current >= target
end

-- Give every pet whose goal is met and that you do not own yet. Safe to call
-- any time (idempotent). Returns the ids that were just unlocked, in order.
function PetRules.checkUnlocks(profile: Profile): { string }
	local fresh: { string } = {}
	for _, def in PetConfig.Pets do
		if not profile.pets[def.id] and PetRules.goalMet(profile, def) then
			profile.pets[def.id] = { level = 1, xp = 0 }
			table.insert(fresh, def.id)
		end
	end
	return fresh
end

-- Choose which pet is out ("" = put them all away). Only pets you own.
function PetRules.setActive(profile: Profile, id: unknown): boolean
	if id == "" then
		profile.petActive = ""
		return true
	end
	if typeof(id) ~= "string" or not profile.pets[id] then
		return false
	end
	profile.petActive = id
	return true
end

-- You helped flip the MEGA coin.
function PetRules.recordMegaBeat(profile: Profile)
	profile.petProgress.megaBeats += 1
end

-- Add xp; returns true if the pet gained at least one level.
function PetRules.addXp(profile: Profile, id: string, amount: number): boolean
	local pet = profile.pets[id]
	if not pet or amount <= 0 then
		return false
	end
	local leveled = false
	pet.xp += math.floor(amount)
	while true do
		local need = PetRules.xpToNext(pet.level)
		if not need then
			pet.xp = 0
			break
		end
		if pet.xp < need then
			break
		end
		pet.xp -= need
		pet.level += 1
		leveled = true
	end
	return leveled
end

-- The active pet flips its coin: pays cash, gives xp. nil if no pet is out.
export type PetFlip = { id: string, cash: number, leveled: boolean, level: number }
function PetRules.flip(profile: Profile, bonus: number?): PetFlip?
	local def = PetRules.def(profile.petActive)
	local pet = def and profile.pets[def.id]
	if not def or not pet then
		return nil
	end
	local cash = PetRules.flipCash(profile, def, pet.level, bonus)
	profile.cash += cash
	local leveled = PetRules.addXp(profile, def.id, PetConfig.XP_PER_FLIP)
	return { id = def.id, cash = cash, leveled = leveled, level = pet.level }
end

-- What a pet card needs, owned or not. Sent to the owner's client.
export type PetView = {
	id: string,
	owned: boolean,
	active: boolean,
	level: number,
	xp: number,
	xpNeeded: number, -- 0 at max level
	goalText: string,
	have: number,
	need: number,
	seconds: number, -- between flips now
	cashPerFlip: number,
}
function PetRules.view(profile: Profile): { PetView }
	local list: { PetView } = {}
	for _, def in PetConfig.Pets do
		local pet = profile.pets[def.id]
		local level = if pet then pet.level else 1
		local have, need = PetRules.progress(profile, def)
		table.insert(list, {
			id = def.id,
			owned = pet ~= nil,
			active = profile.petActive == def.id,
			level = level,
			xp = if pet then pet.xp else 0,
			xpNeeded = PetRules.xpToNext(level) or 0,
			goalText = def.goalText,
			have = have,
			need = need,
			seconds = PetRules.interval(def, level),
			cashPerFlip = PetRules.flipCash(profile, def, level, 1),
		})
	end
	return list
end

return PetRules
