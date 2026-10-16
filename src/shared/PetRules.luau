--!strict
-- Pure pet rules shared by the server and the client (tested offline in tests/test_pet_rules.luau):
--   capacity     how many pets the Pet Book holds (Config.Inventory.Max plus extra slots a future game pass may add)
--   cleanName    the shape check of a pet nickname before the server runs Roblox text filtering on it
--   label        the name players see for a pet (its nickname, else its species name)
--   friendLuck   the friend bonus: extra Luck per Roblox friend in the same server, capped
--   kindOf       a pet's boost kind (Coins / Speed / Luck), which picks its glow colour and icon
--   level / sort / best   Pet Book sorting (rarity, level, type) and Equip Best
--   autoFollow   whether a newly gained pet joins the team (empty slot, or stronger than the weakest member)

local Config = require(script.Parent.Config)
local GeodeGen = require(script.Parent.GeodeGen)
local PetStats = require(script.Parent.PetStats)

local PetRules = {}

-- Pet Book size: the base storage plus `extra` slots (Profiles.petCapacity reads the save's ExtraPetSlots; anything
-- that is not a whole non-negative number counts as 0).
function PetRules.capacity(base: number, extra: any): number
	local n = if type(extra) == "number" and extra == extra and extra > 0 then math.floor(extra) else 0
	return base + math.min(n, 100000)
end

-- Trims and tidies a requested nickname. Returns (name, nil) when it may go to the text filter, ("", nil) to clear the
-- nickname, or (nil, reason) when it is refused before filtering. Letters, digits, spaces and a few marks only
-- (no line breaks, rich text or invisible characters), at most `max` characters.
function PetRules.cleanName(raw: any, max: number): (string?, string?)
	if type(raw) ~= "string" then
		return nil, "That name can't be used."
	end
	if #raw > max * 4 + 16 then
		return nil, "Names can be up to " .. max .. " letters."
	end
	if utf8.len(raw) == nil then
		return nil, "That name can't be used."
	end
	local s = string.gsub(raw, "%s+", " ")
	s = string.match(s, "^%s*(.-)%s*$") or ""
	if s == "" then
		return "", nil
	end
	if string.find(s, "[^%w %-_%.!%?']") then
		return nil, "Use letters, numbers and spaces only."
	end
	if #s > max then
		return nil, "Names can be up to " .. max .. " letters."
	end
	return s, nil
end

-- The filtered text must come back exactly as asked; anything the filter changed (hashed out) is refused rather than
-- saved with hash marks.
function PetRules.filterAccepted(asked: string, filtered: any): boolean
	return type(filtered) == "string" and filtered == asked and not string.find(filtered, "#", 1, true)
end

function PetRules.label(g: { [string]: any }, short: boolean?): string
	local nick = g.Nickname
	if type(nick) == "string" and nick ~= "" then
		return nick
	end
	return GeodeGen.displayName(g :: any, short)
end

-- Friend bonus: `per` extra Luck for each friend, counting at most `maxFriends` of them.
function PetRules.friendLuck(friends: number, per: number, maxFriends: number): number
	local n = math.clamp(math.floor(friends), 0, maxFriends)
	return math.floor(n * per * 1000 + 0.5) / 1000
end

function PetRules.kindOf(g: { [string]: any }): string
	local sp: any = (Config.Minerals :: any)[g.Mineral]
	local kind = sp and sp.BoostKind
	return if type(kind) == "string" and (Config.Pets.KindColors :: any)[kind] then kind else "Coins"
end

function PetRules.kindColor(kind: string): Color3
	local colors: any = Config.Pets.KindColors
	return colors[kind] or colors.Coins
end

-- The boost a pet shows in the Pet Book (species Boost + rarity bonus, before KindScale and caps).
function PetRules.boost(g: { [string]: any }): number
	local sp: any = (Config.Minerals :: any)[g.Mineral]
	return ((Config.Pets.RarityBoost :: any)[g.Rarity] or 0) + ((sp and sp.Boost) or 0)
end

-- A pet's level: from its TowerXP (the pet tower's curve, PetStats.level; Profiles copies it into the public view), else 1.
function PetRules.level(g: { [string]: any }): number
	local xp = g.TowerXP
	if type(xp) ~= "number" or xp ~= xp or xp <= 0 then
		return 1
	end
	return (PetStats.level(xp, PetStats.cap(g :: any))) -- the same level the pet tower shows (capped by rarity)
end

local RANK = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 }
local KIND_ORDER = { Coins = 1, Speed = 2, Luck = 3 }

-- Pet Book sort: "Rarity" (rarest first), "Level" (highest first), "Type" (Coins, Speed, Luck; strongest first) or
-- anything else = newest first. Ties: newest, then id, so the order never jumps.
function PetRules.sort(list: { any }, by: string)
	table.sort(list, function(a, b)
		if by == "Rarity" then
			local ra, rb = RANK[a.Rarity] or 0, RANK[b.Rarity] or 0
			if ra ~= rb then
				return ra > rb
			end
		elseif by == "Level" then
			local la, lb = PetRules.level(a), PetRules.level(b)
			if la ~= lb then
				return la > lb
			end
			local ra, rb = RANK[a.Rarity] or 0, RANK[b.Rarity] or 0
			if ra ~= rb then
				return ra > rb
			end
		elseif by == "Type" then
			local ka, kb = KIND_ORDER[PetRules.kindOf(a)] or 9, KIND_ORDER[PetRules.kindOf(b)] or 9
			if ka ~= kb then
				return ka < kb
			end
			local ba, bb = PetRules.boost(a), PetRules.boost(b)
			if ba ~= bb then
				return ba > bb
			end
		end
		local fa, fb = tonumber(a.Found) or 0, tonumber(b.Found) or 0
		if fa ~= fb then
			return fa > fb
		end
		return tostring(a.Id) < tostring(b.Id)
	end)
end

-- Equip Best: the ids of the `slots` owned pets with the highest POWER (PetStats.powerOfPet; `xpBook` = the save's
-- TowerXP by pet id, for server rows that do not carry it). Ties: higher boost, level, value, then id.
function PetRules.best(pets: { any }, slots: number, xpBook: { [string]: number }?): { string }
	local list = {}
	local power: { [any]: number } = {}
	for _, g in pets do
		if type(g) == "table" and type(g.Id) == "string" then
			table.insert(list, g)
			local xp = if xpBook then xpBook[g.Id] else nil
			power[g] = PetStats.powerOfPet(g, if type(xp) == "number" then xp else nil)
		end
	end
	table.sort(list, function(a, b)
		-- carter's pick (2026-10-14): the biggest POWER wins (bigger = better); the hunt bonus breaks ties
		if power[a] ~= power[b] then
			return power[a] > power[b]
		end
		local ba, bb = PetRules.boost(a), PetRules.boost(b)
		if ba ~= bb then
			return ba > bb
		end
		local la, lb = PetRules.level(a), PetRules.level(b)
		if la ~= lb then
			return la > lb
		end
		local va, vb = tonumber(a.Value) or 0, tonumber(b.Value) or 0
		if va ~= vb then
			return va > vb
		end
		return a.Id < b.Id
	end)
	local out = {}
	for i = 1, math.min(slots, #list) do
		out[i] = list[i].Id
	end
	return out
end

-- The team slot a full team swaps when a new pet joins: the slot the player picked (1..size), else nil (no silent
-- replace: the server refuses and MY PETS asks which slot).
function PetRules.swapSlot(pick: any, size: number): number?
	if type(pick) ~= "number" or pick ~= pick or pick % 1 ~= 0 or pick < 1 or pick > size then
		return nil
	end
	return pick
end

-- A newly hatched / found pet joins the team when a slot is empty, or, on a full team, when `powerOf` (POWER by pet id)
-- says it is stronger than the weakest team member, which it replaces. A fresh Common never pushes out a stronger pet,
-- and a stronger new pet is never left off (bug: 193 off the team, 156 on). Edits `equipped` in place; true = joined.
function PetRules.autoFollow(equipped: { string }, id: string, slots: number, powerOf: ((string) -> number)?): boolean
	if table.find(equipped, id) then
		return false
	end
	if #equipped < slots then
		table.insert(equipped, id)
		return true
	end
	if not powerOf or slots <= 0 then
		return false
	end
	local weakest, weakPower = nil, math.huge
	for i = 1, math.min(#equipped, slots) do
		local p = powerOf(equipped[i])
		if p < weakPower then
			weakest, weakPower = i, p
		end
	end
	if weakest and powerOf(id) > weakPower then
		equipped[weakest] = id
		return true
	end
	return false
end

-- MAX level is not a dead end (evolve is off, carter 2026-10-16): XP a team pet can no longer use (it is at its rarity
-- cap) goes to the other team pets that still have room, split evenly, so hunting and fighting with a maxed pet still
-- trains the rest of the team. `room(id)` = XP the pet can still take before its cap (0 = maxed). Pets off the team keep
-- the old rule (only `target` grows). Returns { [id] = gain }; XP no team pet can use is dropped.
function PetRules.spillXp(target: string, amount: number, team: { string }, room: (string) -> number): { [string]: number }
	local out: { [string]: number } = {}
	amount = math.max(math.floor(tonumber(amount) or 0), 0)
	if amount <= 0 then
		return out
	end
	if not table.find(team, target) then
		out[target] = amount
		return out
	end
	local left: { [string]: number } = {}
	local first = math.min(amount, math.max(room(target), 0))
	if first > 0 then
		out[target] = first
	end
	local over = amount - first
	local open: { string } = {}
	for _, id in team do
		if id ~= target and not left[id] then
			local r = math.max(math.floor(room(id)), 0)
			if r > 0 then
				left[id] = r
				table.insert(open, id)
			end
		end
	end
	while over > 0 and #open > 0 do
		local share, extra = over // #open, over % #open
		local still: { string } = {}
		for i, id in open do
			local give = math.min(share + (if i <= extra then 1 else 0), left[id])
			if give > 0 then
				out[id] = (out[id] or 0) + give
				left[id] -= give
				over -= give
			end
			if left[id] > 0 then
				table.insert(still, id)
			end
		end
		open = still -- every pass hands out at least 1 XP, so this ends
	end
	return out
end

-- After a team pet is sold, the empty team slots fill with the strongest owned pets not on the team (PetRules.best
-- order), so the team never sits at 2 while a strong pet waits in the Pet Book. Edits `equipped`; returns how many joined.
function PetRules.fillTeam(equipped: { string }, pets: { any }, slots: number, xpBook: { [string]: number }?): number
	local added = 0
	for _, id in PetRules.best(pets, #pets, xpBook) do
		if #equipped >= slots then
			break
		end
		if not table.find(equipped, id) then
			table.insert(equipped, id)
			added += 1
		end
	end
	return added
end

return PetRules
