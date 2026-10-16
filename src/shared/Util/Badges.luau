--!strict
-- Badges as pure rules (tests/specs/Badges.spec.luau). A badge is earned once and kept in
-- profile.badges. badgeId (Roblox) stays 0 until carter makes the badges and gives the ids:
-- with id 0 the badge still shows in the game but nothing is awarded on Roblox.

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)

type Profile = Types.Profile

local Badges = {}

export type Def = { id: string, name: string, text: string, badgeId: number }

function Badges.isBadgeId(id: unknown): boolean
	for _, def in Config.Badges do
		if def.id == id then
			return true
		end
	end
	return false
end

-- Known badge ids only, true only.
function Badges.sanitize(raw: unknown): { [string]: boolean }
	local out: { [string]: boolean } = {}
	if typeof(raw) == "table" then
		for id, owned in raw :: { [any]: any } do
			if owned == true and Badges.isBadgeId(id) then
				out[id] = true
			end
		end
	end
	return out
end

-- Does the profile meet the badge's goal right now?
function Badges.met(id: string, profile: Profile): boolean
	if id == "streak10" then
		return profile.stats.bestStreak >= Config.BADGE_STREAK
	elseif id == "flips1m" then
		return profile.stats.flips >= Config.BADGE_FLIPS
	elseif id == "firstReset" then
		return profile.resets >= 1
	elseif id == "allHelpers" then
		for _, helper in Config.HelperTypes do
			if not profile.crew[helper.id] then
				return false
			end
		end
		return true
	end
	return false
end

-- Marks every newly met badge as earned and returns them (once each, never taken back).
function Badges.award(profile: Profile): { Def }
	local new: { Def } = {}
	for _, def in Config.Badges do
		if not profile.badges[def.id] and Badges.met(def.id, profile) then
			profile.badges[def.id] = true
			table.insert(new, def)
		end
	end
	return new
end

function Badges.view(profile: Profile): Types.BadgeView
	local list = {}
	local earned = 0
	for _, def in Config.Badges do
		local has = profile.badges[def.id] == true
		if has then
			earned += 1
		end
		table.insert(list, { id = def.id, name = def.name, text = def.text, earned = has })
	end
	return { badges = list, earned = earned }
end

return Badges
