--!strict
-- What a pet's stats MEAN, in plain words for young players (pure, tested in tests/test_pet_stat_view.luau).
-- Display only: every number comes from the same rules the server uses (PetStats.roll for the Pet Tower stats,
-- PetRules.boost x Config.Pets.KindScale for the hunt bonus). Nothing here changes how a pet plays.
--
-- carter's pick (2026-10-14): ONE "bigger = better" POWER number per pet (PetStatView.power), on every pet card, the
-- Pet Book detail and the Pet Tower picker, with a green up / red down arrow against the pet that follows you.
-- POWER folds attack, health and attack speed (rarity, Golden / Rainbow and level all raise them) with the weights
-- PvP (PvpRules.petPower) and the tower team pick (TowerService.score) use. Everything else
-- (the hunt bonus, attack, health, speed, type, moves, level, grade, multipliers) is behind MORE (PetStatView.more).
-- New stats (a ride speed, for example) go in as one more `Line` in PetStatView.more.

local Config = require(script.Parent.Config)
local TowerConfig = require(script.Parent.TowerConfig)
local PetStats = require(script.Parent.PetStats)
local PetRules = require(script.Parent.PetRules)

local PetStatView = {}

export type Line = { Icon: string, Head: string, Text: string }

PetStatView.KindIcon = { Coins = "boostCoins", Speed = "boostSpeed", Luck = "boostLuck" } :: { [string]: string }
-- what the bonus does, in a few words (Config.Minerals BoostKind comment)
PetStatView.KindWord = { Coins = "coins", Speed = "run speed", Luck = "luck" } :: { [string]: string }
-- the bonus tile's one-word label
PetStatView.KindShort = { Coins = "coins", Speed = "speed", Luck = "luck" } :: { [string]: string }
PetStatView.KindDoes = {
	Coins = "you get more coins for candy",
	Speed = "you run faster in hunts",
	Luck = "you hatch rarer pets more often",
} :: { [string]: string }

-- The hunt bonus this pet really gives while it follows you: kind and fraction (after KindScale and the cap, the
-- same maths as Profiles.petBoosts for one pet). The old Pet Book line showed it before KindScale.
function PetStatView.bonus(g: { [string]: any }): (string, number)
	local kind = PetRules.kindOf(g)
	local scale = (Config.Pets.KindScale :: any)[kind] or 1
	local cap = (Config.Pets.KindCap :: any)[kind] or 1
	local amt = math.clamp(PetRules.boost(g) * scale, 0, cap)
	return kind, math.floor(amt * 1000 + 0.5) / 1000
end

local function pct(f: number): string
	local p = f * 100
	-- whole percents, except small Speed bonuses (+3.2%) that would all round to the same number
	if p < 10 and math.abs(p - math.floor(p + 0.5)) > 0.05 then
		return string.format("+%.1f%%", p)
	end
	return "+" .. math.floor(p + 0.5) .. "%"
end
PetStatView.pct = pct

-- A pet needs Seed for its tower stats (GeodeGen.public and the tower roster both carry it). Without one only the
-- bonus is known.
local function tower(g: { [string]: any }): PetStats.Stats?
	if type(g.Seed) ~= "number" or type(g.Mineral) ~= "string" or type(g.Rarity) ~= "string" then
		return nil
	end
	return PetStats.roll(g :: any, if type(g.TowerXP) == "number" then g.TowerXP else nil)
end
PetStatView.tower = tower

-- The POWER number from rolled tower stats (PetStats.power: one formula for the whole game).
function PetStatView.powerOf(s: { Power: number, Health: number, Speed: number }): number
	return PetStats.power(s)
end

-- A pet's POWER (nil without a Seed: very old or partial data).
function PetStatView.power(g: { [string]: any }): number?
	local s = tower(g)
	return if s then PetStatView.powerOf(s) else nil
end

-- +1 when `g` is stronger than `other` (the pet that follows you), -1 weaker, 0 same, the same pet, or unknown.
function PetStatView.compare(g: { [string]: any }, other: { [string]: any }?): number
	if other == nil or (other.Id ~= nil and other.Id == g.Id) then
		return 0
	end
	local a, b = PetStatView.power(g), PetStatView.power(other)
	if a == nil or b == nil or a == b then
		return 0
	end
	return if a > b then 1 else -1
end

-- "Lv 7/20": level and its rarity cap (PetStats.cap: Common 10 ... Legendary 50, Void Dragon 100).
-- At the cap it says MAX (Studio 2026-10-16: a maxed pet showed only "Lv 50/50", and with evolve off nothing else
-- told the player the pet was done training).
function PetStatView.levelText(level: number, cap: number): string
	-- "Lv 50 MAX", not "Lv 50/50 MAX": the same width as "Lv 50/50", so pills and rows sized for it still fit
	return if level >= cap then "Lv " .. level .. " MAX" else "Lv " .. level .. "/" .. cap
end

-- A pet's level and cap (level from TowerXP, as PetRules.level).
function PetStatView.levelOf(g: { [string]: any }): (number, number)
	return PetRules.level(g), PetStats.cap(g :: any)
end

-- Short hunt bonus text for the facts line ("+3.2% speed").
function PetStatView.bonusText(g: { [string]: any }): string
	local kind, amt = PetStatView.bonus(g)
	return pct(amt) .. " " .. (PetStatView.KindShort[kind] or "coins")
end

local function times(x: number): string
	if x == math.floor(x) then
		return "x" .. tostring(x)
	end
	local t = string.gsub(string.format("%.2f", x), "0$", "")
	return "x" .. t
end
PetStatView.times = times

local GRADE_WORD = { S = "super lucky", A = "great", B = "good", C = "okay" }

-- Every stat in one plain sentence each (the MORE page). Order: what it does for you first, battle stats next,
-- then where the numbers come from.
function PetStatView.more(g: { [string]: any }): { Line }
	local lines: { Line } = {}
	local kind, amt = PetStatView.bonus(g)
	local cap = (Config.Pets.KindCap :: any)[kind] or 1
	table.insert(lines, {
		Icon = PetStatView.KindIcon[kind] or "boostCoins",
		Head = pct(amt) .. " " .. (PetStatView.KindWord[kind] or "coins"),
		Text = "When it follows you, " .. (PetStatView.KindDoes[kind] or "") .. ". Max " .. pct(cap) .. " from all pets.",
	})
	local s = tower(g)
	if s then
		table.insert(lines, 1, { Icon = "statPower", Head = "POWER " .. PetStatView.powerOf(s), Text = "Bigger = better. Attack, health and speed together." })
		table.insert(lines, { Icon = "statAttack", Head = "Attack " .. s.Power, Text = "How hard it hits in the Pet Tower." })
		table.insert(lines, { Icon = "statHealth", Head = "Health " .. s.Health, Text = "How many hits it can take." })
		table.insert(lines, { Icon = "statSpeed", Head = "Attack speed " .. s.Speed, Text = "Higher attacks more often." })
		local circle = TowerConfig.TypeCircle
		local i = table.find(circle, s.Element)
		local typeText = if s.Element == "Cosmic"
			then "Strong against every other type."
			elseif i then "Strong vs " .. circle[i % #circle + 1] .. ", weak vs " .. circle[(i - 2) % #circle + 1] .. "."
			else ""
		table.insert(lines, { Icon = "sparkle", Head = s.Element .. " type", Text = typeText })
		local sp = PetStats.special(s.Special)
		table.insert(lines, { Icon = "hammer", Head = "Moves", Text = s.Basic .. ", " .. s.Move .. ", and special " .. (if sp then sp.Name else s.Special) .. "." })
		local top = PetStats.cap(g :: any)
		table.insert(lines, {
			Icon = "trophy",
			Head = "Level " .. s.Level .. " of " .. top .. (if s.Level >= top then " (MAX)" else ""),
			Text = "Fights level it up (+" .. math.floor(TowerConfig.Levels.LevelStat * 100 + 0.5) .. "% Attack and Health each). Rarer pets can grow higher.",
		})
		table.insert(lines, { Icon = "star", Head = "Grade " .. s.Grade, Text = "Its hatch roll was " .. (GRADE_WORD[s.Grade] or "okay") .. ". S is best, C is lowest." })
	end
	local rarityX = (TowerConfig.RarityStat :: any)[g.Rarity] or 1
	table.insert(lines, {
		Icon = "gem",
		Head = tostring(g.Rarity),
		Text = (if rarityX > 1 then times(rarityX) .. " Attack and Health, " else "") .. "rarer pets give a bigger bonus.",
	})
	local mod = g.Modifier
	if type(mod) == "string" and mod ~= "Natural" then
		local vx = (TowerConfig.VariantStat :: any)[mod] or 1
		table.insert(lines, {
			Icon = "sparkle",
			Head = (Config.ModifierNames :: any)[mod] or mod,
			Text = times(vx) .. " Attack and Health, sells for " .. times((Config.ModifierMult :: any)[mod] or 1) .. " coins.",
		})
	end
	return lines
end

-- Short variant tag for the header ("Golden x1.5"), nil for a plain pet.
function PetStatView.variantTag(g: { [string]: any }): string?
	local mod = g.Modifier
	if type(mod) ~= "string" or mod == "Natural" then
		return nil
	end
	return ((Config.ModifierNames :: any)[mod] or mod) .. " " .. times((TowerConfig.VariantStat :: any)[mod] or 1)
end

return PetStatView
