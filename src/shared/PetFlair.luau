--!strict
-- Pet flair rules (Find The Pet owner picks), pure: no Roblox services, unit-tested in tests/test_pet_flair.luau.
--   * rarity size and sparkle look (Config.Pets.RarityScale / Config.Pets.Sparkle)
--   * pet index: first-find coin reward, "all species found" and the Pet Master title (Config.PetIndex)
--   * rare hatch announcements: which rarities, the sanitised payload, a rate limiter (Config.RareHatch)
--   * the lobby name tag lines (best pet tower floor + title)

local Config = require(script.Parent.Config)
local SpeciesPool = require(script.Parent.SpeciesPool)
local TowerConfig = require(script.Parent.TowerConfig)

local PetFlair = {}

-- Size multiplier for a rarity (unknown rarity = 1).
function PetFlair.rarityScale(rarity: any): number
	local v = (Config.Pets.RarityScale :: any)[rarity]
	return if type(v) == "number" and v > 0 then v else 1
end

-- Evolve stage from a spec's Evolve field (0 = never evolved), and how much bigger it draws the pet.
function PetFlair.evolveStage(evolve: any): number
	local e = tonumber(evolve)
	if not e or e ~= e then
		return 0
	end
	return math.clamp(math.floor(e), 0, TowerConfig.Evolve.MaxStage)
end
function PetFlair.evolveScale(evolve: any): number
	return 1 + TowerConfig.Evolve.Scale * PetFlair.evolveStage(evolve)
end

-- Sparkle look for a rarity, or nil when this rarity does not sparkle or the viewer chose Low Effects.
function PetFlair.sparkle(rarity: any, lowEffects: boolean?): { Color: Color3, TimeScale: number }?
	if lowEffects then
		return nil
	end
	return (Config.Pets.Sparkle :: any)[rarity]
end

-- Every species id the game knows (sorted, so the order is stable).
function PetFlair.species(): { string }
	local list: { string } = {}
	for id, m in Config.Minerals :: { [string]: any } do
		if not m.TowerOnly and not m.Retired and SpeciesPool.released(id, os.time()) then -- tower-only, retired and unreleased weekly pets are not in the index
			table.insert(list, id)
		end
	end
	table.sort(list)
	return list
end

-- How many species of the current index (PetFlair.species: released hunt pets) this discovery index (species ->
-- count) has found at least once. Tower-only pets and weekly pets not released yet do not count, so the count can
-- never pass the total ("36/35") or give the title early.
function PetFlair.foundCount(index: any): number
	if type(index) ~= "table" then
		return 0
	end
	local n = 0
	for _, id in PetFlair.species() do
		local v = index[id]
		if type(v) == "number" and v > 0 then
			n += 1
		end
	end
	return n
end

function PetFlair.allFound(index: any): boolean
	local total = #PetFlair.species()
	return total > 0 and PetFlair.foundCount(index) >= total
end

-- The title a profile has earned ("" = none). `earned` is the saved Pet Master flag (profile PetMaster, set by
-- Profiles the first time allFound is true): a weekly pet released later never takes an earned title away.
function PetFlair.title(index: any, earned: boolean?): string
	return if earned == true or PetFlair.allFound(index) then Config.PetIndex.MasterTitle else ""
end

-- Coins for hatching `species`, read BEFORE the hatch is counted: the reward only when this known species is not in
-- the index yet. The caller counts the hatch in the same profile write, so a second call returns 0 (idempotent).
function PetFlair.firstFindReward(index: any, species: any): number
	if type(index) ~= "table" or type(species) ~= "string" or (Config.Minerals :: any)[species] == nil then
		return 0
	end
	local v = index[species]
	if type(v) == "number" and v > 0 then
		return 0
	end
	return Config.PetIndex.FirstFindCoins
end

function PetFlair.shouldAnnounce(rarity: any): boolean
	return (Config.Pets.AnnounceRarities :: any)[rarity] == true
end

export type Payload = { Name: string, Pet: string, Rarity: string }

local function clean(s: any, max: number): string?
	if type(s) ~= "string" then
		return nil
	end
	local t = string.gsub(s, "[%c]", "")
	t = string.match(t, "^%s*(.-)%s*$") or ""
	if t == "" then
		return nil
	end
	if #t > max then
		-- cut on a UTF-8 character boundary
		local cut = max
		while cut > 0 do
			local b = string.byte(t, cut + 1)
			if not b or b < 0x80 or b >= 0xC0 then
				break
			end
			cut -= 1
		end
		t = string.sub(t, 1, cut)
	end
	return t
end

-- The only data a rare hatch message carries: display name, pet display name, rarity. nil when anything is off
-- (also used to check messages arriving from other servers).
function PetFlair.payload(name: any, pet: any, rarity: any): Payload?
	local n = clean(name, Config.RareHatch.NameMax)
	local p = clean(pet, Config.RareHatch.PetMax)
	-- a SHINY pet of any rarity is announced too (its display name starts with "Shiny ", GeodeGen.displayName)
	if not n or not p or type(rarity) ~= "string" or not (PetFlair.shouldAnnounce(rarity) or PetFlair.isShinyName(p)) then
		return nil
	end
	return { Name = n, Pet = p, Rarity = rarity }
end

-- Key that recognises our own message when MessagingService delivers it back to this server.
function PetFlair.echoKey(p: Payload): string
	return p.Name .. "\0" .. p.Pet .. "\0" .. p.Rarity
end

-- The banner line ("Ava hatched a LEGENDARY Golden Void Dragon!"). A Legendary (the 1 in 1000 chase pets, the Void
-- Dragon among them) opens with "WOW!" so the whole server notices.
function PetFlair.bannerLine(p: Payload): string
	local r = string.upper(p.Rarity)
	local article = if string.match(r, "^[AEIOU]") then "an" else "a"
	local line = p.Name .. " hatched " .. article .. " " .. r .. " " .. p.Pet .. "!"
	return if p.Rarity == "Legendary" then "WOW! " .. line else line
end

function PetFlair.isShinyName(pet: any): boolean
	return type(pet) == "string" and string.sub(pet, 1, 6) == "Shiny "
end

-- Rate limiter: at most one pass per `gap` seconds overall and per `keyGap` seconds per key.
export type Limiter = { Gap: number, KeyGap: number, Last: number, Keys: { [string]: number } }

function PetFlair.newLimiter(gap: number, keyGap: number?): Limiter
	return { Gap = gap, KeyGap = keyGap or 0, Last = -math.huge, Keys = {} }
end

function PetFlair.allow(l: Limiter, key: string, now: number): boolean
	if now - l.Last < l.Gap then
		return false
	end
	if l.KeyGap > 0 then
		local k = l.Keys[key]
		if k and now - k < l.KeyGap then
			return false
		end
		for other, t in l.Keys do
			if now - t >= l.KeyGap then
				l.Keys[other] = nil -- forget old keys so the table never grows
			end
		end
		l.Keys[key] = now
	end
	l.Last = now
	return true
end

-- Hatch reveal timing (Config.Hatch). The reveal animation runs on its own clock from 0 to HatchAnim.End; the
-- window SlowFrom..SlowTo (wobble, cracks, pop) is stretched or squeezed to the rarity's Slow seconds.
PetFlair.HatchAnim = { SlowFrom = 0.4, SlowTo = 1.55, End = 2.6, Pop = 1.0 }

export type HatchTiming = { Pre: number, Slow: number, Post: number, Glow: boolean, Total: number, SlowMo: boolean }

function PetFlair.hatchTiming(rarity: any): HatchTiming
	local slow = (Config.Hatch.SlowRarities :: any)[rarity] == true
	local h = if slow then Config.Hatch.Slow else Config.Hatch.Normal
	return { Pre = h.Pre, Slow = h.Slow, Post = h.Post, Glow = h.Glow, Total = h.Pre + h.Slow + h.Post, SlowMo = slow }
end

-- Seconds the server keeps a round in its Reveal phase for this rarity.
function PetFlair.revealSeconds(rarity: any): number
	return PetFlair.hatchTiming(rarity).Total + Config.Hatch.Hold
end

-- The longest reveal any rarity has (notices that must wait until after any reveal).
function PetFlair.longestReveal(): number
	local best = 0
	for _, r in Config.Rarities do
		best = math.max(best, PetFlair.revealSeconds(r))
	end
	return best
end

-- Real seconds since the reveal started -> animation time (continuous, never past HatchAnim.End).
function PetFlair.hatchWarp(h: HatchTiming, t: number): number
	local A = PetFlair.HatchAnim
	if t <= 0 then
		return 0
	elseif t < h.Pre then
		return t / h.Pre * A.SlowFrom
	elseif t < h.Pre + h.Slow then
		return A.SlowFrom + (t - h.Pre) / h.Slow * (A.SlowTo - A.SlowFrom)
	elseif t < h.Total then
		return A.SlowTo + (t - h.Pre - h.Slow) / h.Post * (A.End - A.SlowTo)
	end
	return A.End
end

-- Real seconds at which the pet pops out, for this timing.
function PetFlair.hatchPopAt(h: HatchTiming): number
	local A = PetFlair.HatchAnim
	return h.Pre + (A.Pop - A.SlowFrom) / (A.SlowTo - A.SlowFrom) * h.Slow
end

-- Lines under the player's name on the lobby name tag: the title first, then the best tower floor (0 = none).
-- Pet Battle line under a lobby name (carter 2026-10-14: others should see how strong you are and want that):
-- team power, trophies, and a crown with the win streak from 3 wins in a row. nil when there is nothing to show.
function PetFlair.battleLine(power: any, trophies: any, streak: any): string?
	local parts = {}
	local p, t, s = tonumber(power), tonumber(trophies), tonumber(streak)
	if p and p > 0 and p == p then
		table.insert(parts, "\u{26A1}" .. math.floor(p))
	end
	if t and t > 0 and t == t then
		table.insert(parts, "\u{1F3C6}" .. math.floor(t))
	end
	if s and s >= 3 and s == s then
		table.insert(parts, "\u{1F451}" .. math.floor(s) .. " streak")
	end
	return if #parts > 0 then table.concat(parts, "  ") else nil
end

function PetFlair.tagLines(towerBest: any, title: any, battle: string?): { string }
	local lines = {}
	if type(title) == "string" and title ~= "" then
		table.insert(lines, title)
	end
	local f = tonumber(towerBest)
	if f and f >= 1 and f == f then
		-- "Best": it is the record, not the floor the player is on now (owner video: read as the current floor)
		table.insert(lines, "Best floor " .. math.floor(f))
	end
	if battle then
		table.insert(lines, battle)
	end
	return lines
end

return PetFlair
