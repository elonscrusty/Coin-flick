--!strict
-- Global top 10s: most flips, biggest flip, most resets. Each player's best is
-- written to an OrderedDataStore now and then, and the top lists are read back
-- and sent to everyone. In Studio (no real saves) it shows the players here.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local WeeklyBoard = require(ReplicatedStorage.Shared.Util.WeeklyBoard)
local Net = require(script.Parent.Net)
local PlayerData = require(script.Parent.PlayerData)

type Profile = Types.Profile

local Leaderboards = {}

local stores: { [string]: OrderedDataStore } = {}
local storePrefix = ""
local useStores = false
local latest: Types.Leaderboards = {}
local names: { [number]: string } = {}

local function isWeekly(key: string): boolean
	return table.find(Config.WEEKLY_LEADERBOARDS, key) ~= nil
end

-- Every board's key, weekly ones last.
local function allKeys(): { string }
	local keys = table.clone(Config.LEADERBOARDS) :: { string }
	for _, key in Config.WEEKLY_LEADERBOARDS do
		table.insert(keys, key)
	end
	return keys
end

-- Weekly boards are a new ordered store every Monday (UTC), so they start empty on their own.
local function storeFor(key: string): OrderedDataStore
	if isWeekly(key) then
		return DataStoreService:GetOrderedDataStore(
			WeeklyBoard.storeName(storePrefix, key, WeeklyBoard.week(os.time()))
		)
	end
	return stores[key]
end

local function valueOf(profile: Profile, key: string): number
	if key == "weekFlips" then
		local week = WeeklyBoard.week(os.time())
		WeeklyBoard.sync(profile.week, week, profile.stats.flips)
		return WeeklyBoard.score(profile.week, week, profile.stats.flips)
	elseif key == "flips" then
		return profile.stats.flips
	elseif key == "biggestFlip" then
		return profile.stats.biggestFlip
	end
	return profile.resets
end

local function nameOf(userId: number): string
	local cached = names[userId]
	if cached then
		return cached
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		names[userId] = player.DisplayName
		return player.DisplayName
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = if ok and typeof(name) == "string" then name else "Player"
	names[userId] = result
	return result
end

local function writeAll()
	for _, player in Players:GetPlayers() do
		local profile = PlayerData.get(player)
		if profile then
			for _, key in allKeys() do
				local value = Economy.leaderboardValue(valueOf(profile, key))
				if value > 0 then
					local ok, err = pcall(function()
						storeFor(key):SetAsync(tostring(player.UserId), value)
					end)
					if not ok then
						warn(`[Leaderboards] write {key} failed: {err}`)
					end
				end
			end
			task.wait(0.5) -- spread the writes out
		end
	end
end

local function readStore(key: string): { Types.LeaderRow }?
	local ok, result = pcall(function()
		return storeFor(key):GetSortedAsync(false, Config.LEADERBOARD_SIZE):GetCurrentPage()
	end)
	if not ok then
		warn(`[Leaderboards] read {key} failed: {result}`)
		return nil
	end
	local rows: { Types.LeaderRow } = {}
	for _, entry in result :: { { key: string, value: number } } do
		local userId = tonumber(entry.key)
		if userId then
			table.insert(rows, { name = nameOf(userId), value = entry.value })
		end
	end
	return rows
end

-- Studio: just rank the players in this server.
local function readLocal(key: string): { Types.LeaderRow }
	local rows: { Types.LeaderRow } = {}
	for _, player in Players:GetPlayers() do
		local profile = PlayerData.get(player)
		if profile then
			table.insert(rows, { name = player.DisplayName, value = math.floor(valueOf(profile, key)) })
		end
	end
	table.sort(rows, function(a, b)
		return a.value > b.value
	end)
	while #rows > Config.LEADERBOARD_SIZE do
		table.remove(rows)
	end
	return rows
end

local function refresh()
	for _, key in allKeys() do
		local rows = if useStores then readStore(key) else readLocal(key)
		if rows then
			latest[key] = rows
		end
	end
	Net.event("Leaderboards"):FireAllClients(latest)
end

function Leaderboards.init()
	useStores = not RunService:IsStudio() or Config.STUDIO_USE_REAL_TEST_STORE
	if useStores then
		storePrefix = if RunService:IsStudio() then "CoinFlick_STUDIO_Top_" else "CoinFlick_Top_"
		for _, key in Config.LEADERBOARDS do
			stores[key] = DataStoreService:GetOrderedDataStore(`{storePrefix}{key}_v1`)
		end
	end
	PlayerData.onLoaded(function(player: Player, profile: Profile)
		valueOf(profile, "weekFlips") -- starts this week's baseline
		Net.event("Leaderboards"):FireClient(player, latest)
	end)
end

function Leaderboards.start()
	-- Start a new week for everyone online the moment Monday (UTC) comes.
	task.spawn(function()
		while true do
			task.wait(10)
			for _, player in Players:GetPlayers() do
				local profile = PlayerData.get(player)
				if profile then
					valueOf(profile, "weekFlips")
				end
			end
		end
	end)
	task.wait(10) -- let the first players load
	if useStores then
		task.spawn(function()
			while true do
				writeAll()
				task.wait(Config.LEADERBOARD_WRITE_INTERVAL)
			end
		end)
	end
	while true do
		refresh()
		task.wait(if useStores then Config.LEADERBOARD_REFRESH else 15)
	end
end

return Leaderboards
