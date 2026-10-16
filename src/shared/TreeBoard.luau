--!strict
-- Leaderboard tree (owner pick 2026-10-14): a giant tree in the lobby centre; the top players by best pet POWER
-- (Boards "Power", the Pet Book's POWER, PetStats.powerOfPet) show that pet as a live model on a branch with a glowing
-- name / power sign. Pure rules here (tested, tests/test_tree_board.luau); the server part is server/TreeBoardService.
--
-- The best pet of each ranked player is saved as a small "card" (public look only) in a plain DataStore, keyed by
-- UserId, so every server can draw the pets of players who are offline. Cards from the store are re-checked here.

local Config = require(script.Parent.Config)
local PetStats = require(script.Parent.PetStats)

local TreeBoard = {}

TreeBoard.Config = {
	Enabled = false, -- carter 2026-10-15: the leaderboard tree is gone (shop square in the middle); top pets by POWER show on the RarestPetBoard
	Branches = 10, -- pets on the tree (rank 1 .. Branches); branch attachments Branch1..N, Branch1 = the top
	Store = "CTR_TreePets", -- DataStore of best-pet cards ("_Studio" suffix in Studio)
	CardWriteSeconds = 120, -- at most one card write per player in this time (and only when it changed)
	CardCacheSeconds = 180, -- cards of other servers' players are re-read after this
	RefreshSeconds = 120, -- the tree redraws at most this often (the board itself refreshes every minute)
	PetHeight = { First = 7, Top3 = 5.5, Rest = 4.2 }, -- studs
	SignColor = { First = Color3.fromRGB(255, 206, 64), Top3 = Color3.fromRGB(150, 220, 255), Rest = Color3.fromRGB(240, 240, 240) },
	Pad = "BattlePad", -- part in the tree model that becomes a BATTLE pad (PvpService: attribute PvpPad)
	Spot = "LeaderboardTreeSpot", -- where a tree from ServerStorage is placed when the map has none
	Model = "LeaderboardTree",
	NameMax = 20,
}

export type Card = {
	Mineral: string,
	Rarity: string,
	Modifier: string,
	Formation: string?,
	Seed: number,
	Mass: number,
	Power: number,
	Nickname: string?,
}

local function num(v: any): number?
	return if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then v else nil
end

-- The player's strongest pet and its POWER (tower XP from data.TowerXP), or nil when they have none.
function TreeBoard.bestPet(data: any): (any?, number)
	if type(data) ~= "table" or type(data.InventoryGeodes) ~= "table" then
		return nil, 0
	end
	local xpBook = if type(data.TowerXP) == "table" then data.TowerXP else {}
	local best, bestPower = nil, 0
	for _, g in data.InventoryGeodes do
		if type(g) == "table" then
			local xp = num(xpBook[g.Id])
			local p = PetStats.powerOfPet(g, xp or 0)
			if p > bestPower then
				best, bestPower = g, p
			end
		end
	end
	return best, bestPower
end

-- A card (look + power only) from a pet, or a stored card checked again. Nil when anything is off.
function TreeBoard.card(pet: any, power: any): Card?
	if type(pet) ~= "table" then
		return nil
	end
	local mineral, rarity = pet.Mineral, pet.Rarity
	local seed, p = num(pet.Seed), num(power)
	if type(mineral) ~= "string" or not (Config.Minerals :: any)[mineral] or type(rarity) ~= "string" or not table.find(Config.Rarities, rarity) then
		return nil
	end
	if not seed or not p or p <= 0 then
		return nil
	end
	local modifier = if type(pet.Modifier) == "string" and table.find(Config.Modifiers, pet.Modifier) then pet.Modifier else "Natural"
	local nick = if type(pet.Nickname) == "string" and #pet.Nickname > 0 then string.sub(pet.Nickname, 1, TreeBoard.Config.NameMax) else nil
	return {
		Mineral = mineral,
		Rarity = rarity,
		Modifier = modifier,
		Formation = if type(pet.Formation) == "string" then pet.Formation else nil,
		Seed = math.floor(seed),
		Mass = math.clamp(num(pet.Mass) or 1, 0.2, 5),
		Power = math.floor(p),
		Nickname = nick,
	}
end

-- A new card is worth saving when there was none, the pet looks different, or the power changed.
function TreeBoard.cardChanged(old: Card?, new: Card?): boolean
	if not new then
		return false
	end
	if not old then
		return true
	end
	return old.Mineral ~= new.Mineral or old.Rarity ~= new.Rarity or old.Modifier ~= new.Modifier or old.Seed ~= new.Seed or old.Power ~= new.Power or old.Nickname ~= new.Nickname
end

-- Rank -> size tier.
function TreeBoard.tier(rank: number): string
	return if rank == 1 then "First" elseif rank <= 3 then "Top3" else "Rest"
end

function TreeBoard.petHeight(rank: number): number
	return (TreeBoard.Config.PetHeight :: any)[TreeBoard.tier(rank)]
end

function TreeBoard.signColor(rank: number): Color3
	return (TreeBoard.Config.SignColor :: any)[TreeBoard.tier(rank)]
end

local function commas(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- "#1 Sam", "POWER 1,234"
function TreeBoard.signLines(rank: number, name: string, power: number): (string, string)
	local n = if #name > TreeBoard.Config.NameMax then string.sub(name, 1, TreeBoard.Config.NameMax - 1) .. "." else name
	return "#" .. rank .. " " .. n, "POWER " .. commas(power)
end

-- Ranked rows (Boards "Power": { Rank, UserId, Name, Value }) -> branch plan: up to Branches entries
-- { Branch = k, Rank, UserId, Name, Power }; rank k goes on branch k; rows without a positive value are skipped.
function TreeBoard.plan(rows: { any }, branches: number?): { any }
	local n = math.min(branches or TreeBoard.Config.Branches, TreeBoard.Config.Branches)
	local out = {}
	for _, r in rows do
		if #out >= n then
			break
		end
		if type(r) == "table" and num(r.UserId) and num(r.Value) and r.Value > 0 then
			table.insert(out, { Branch = #out + 1, Rank = #out + 1, UserId = r.UserId, Name = tostring(r.Name or ("Player " .. r.UserId)), Power = math.floor(r.Value) })
		end
	end
	return out
end

return TreeBoard
