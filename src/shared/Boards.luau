--!strict
-- Lobby leaderboard definitions and the pure rules around them (tested offline): which profile
-- number feeds which board, how a value is shown, when a write is due and how raw store rows
-- become a ranked list. The server owns the DataStores (LeaderboardService); the lobby boards
-- (LobbyBoards) only draw what it hands over.
--
-- Solo Finds are a separate board on purpose: only multiplayer hunts count as Wins.

local TreeBoard = require(script.Parent.TreeBoard)

local Boards = {}

export type Info = {
	Id: string,
	Title: string, -- big board title
	Sub: string, -- one line under it
	Unit: string, -- shown after the value
	Accent: Color3,
	Money: boolean?,
}

-- Owner: the lobby shows only two boards, RAREST PET (the crowned board) and HIGHEST FLOOR. The other boards keep
-- their definitions and values (nothing is wiped) but are no longer read or drawn.
-- Owner 2026-10-14 (lobby hangout): MOST COINS joins them (coins earned ever, so spending never drops a rank).
-- 2026-10-14 leaderboard tree: STRONGEST PET (best pet POWER) feeds the tree (server/TreeBoardService).
Boards.Order = { "Biggest", "Tower", "Coins", "Power" }

Boards.Info = {
	Wins = { Id = "Wins", Title = "MULTIPLAYER WINS", Sub = "Pet hunts won against friends", Unit = "wins", Accent = Color3.fromRGB(244, 198, 68) },
		-- Owner: "rarest pet" board. The score is the best pet's value (rarity x trait x size), so a rarer pet ranks higher.
	Biggest = { Id = "Biggest", Title = "RAREST PET", Sub = "Best pet ever hatched (rarity, trait, size)", Unit = "pts", Accent = Color3.fromRGB(166, 106, 255) },
	Collection = { Id = "Collection", Title = "PETS HATCHED", Sub = "Pets hatched (released ones count)", Unit = "pets", Accent = Color3.fromRGB(105, 218, 232) },
	Solo = { Id = "Solo", Title = "SOLO FINDS", Sub = "Pets found in solo hunts", Unit = "finds", Accent = Color3.fromRGB(88, 196, 108) },
	Power = { Id = "Power", Title = "STRONGEST PET", Sub = "Best pet POWER (the leaderboard tree)", Unit = "power", Accent = Color3.fromRGB(255, 120, 80) },
	Coins = { Id = "Coins", Title = "MOST COINS", Sub = "Coins earned ever", Unit = "coins", Accent = Color3.fromRGB(255, 196, 64) },
	Tower = { Id = "Tower", Title = "HIGHEST FLOOR", Sub = "Highest pet tower floor cleared", Unit = "floor", Accent = Color3.fromRGB(150, 96, 230) },
} :: { [string]: Info }

local function nonNegInt(n: any): number
	if type(n) ~= "number" or n ~= n or n == math.huge or n < 0 then
		return 0
	end
	return math.floor(n)
end

-- Profile data -> value per board. Collection counts every geode ever collected (the discovery
-- index keeps counting after a sale), so selling never lowers a rank.
function Boards.values(data: any): { [string]: number }
	local stats = if type(data) == "table" and type(data.Stats) == "table" then data.Stats else {}
	local collected = 0
	if type(data) == "table" and type(data.DiscoveryIndex) == "table" then
		for _, n in data.DiscoveryIndex do
			collected += nonNegInt(n)
		end
	end
	return {
		Wins = nonNegInt(stats.MultiplayerWins),
		Biggest = nonNegInt(stats.BestGeodeValue),
		Collection = collected,
		Solo = nonNegInt(stats.SoloFinds),
		Tower = if type(data) == "table" then nonNegInt(data.TowerBest) else 0,
		Coins = nonNegInt(stats.CashEarned),
		Power = nonNegInt((select(2, TreeBoard.bestPet(data)))),
	}
end

local function commas(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return out
end
Boards.commas = commas

function Boards.format(id: string, value: number): string
	local info = Boards.Info[id]
	if info and info.Money then
		return "$" .. commas(value)
	end
	return commas(value)
end

-- A write is due when the value grew (boards only ever go up), is above zero, and the last
-- write for that board was long enough ago.
function Boards.writeDue(lastWritten: number?, newValue: number, lastWriteTime: number?, now: number, minSeconds: number): boolean
	if newValue <= 0 or newValue <= (lastWritten or 0) then
		return false
	end
	if lastWriteTime and now - lastWriteTime < minSeconds then
		return false
	end
	return true
end

-- Raw sorted rows ({ key = "u"-less user id string, value = number }) -> ranked rows. Skips
-- malformed keys and non-positive values, orders by value then lower UserId, keeps `top`.
export type Row = { Rank: number, UserId: number, Value: number }

function Boards.rank(raw: { any }, top: number): { Row }
	local rows: { Row } = {}
	local seen: { [number]: boolean } = {}
	for _, r in raw do
		local uid = if type(r) == "table" then tonumber(r.key) else nil
		local v = if type(r) == "table" and type(r.value) == "number" then r.value else 0
		if uid and uid > 0 and uid == math.floor(uid) and v > 0 and not seen[uid] then
			seen[uid] = true
			table.insert(rows, { Rank = 0, UserId = uid, Value = math.floor(v) })
		end
	end
	table.sort(rows, function(a, b)
		if a.Value ~= b.Value then
			return a.Value > b.Value
		end
		return a.UserId < b.UserId
	end)
	while #rows > top do
		table.remove(rows)
	end
	for i, r in rows do
		r.Rank = i
	end
	return rows
end

return Boards
