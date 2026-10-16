--!strict
-- Friend bonus: while a friend of yours is in the same server, you both get 2x cash (Boosts reads it).
-- Roblox answers "are these two friends" (it can yield or fail), the rules live in shared Friends.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local FriendRules = require(ReplicatedStorage.Shared.Util.Friends)
local Boosts = require(script.Parent.Boosts)
local Net = require(script.Parent.Net)

local Friends = {}

-- Pairs already asked about ("small:big" -> answer). Cleared per player when they leave.
local known: { [string]: boolean } = {}

local function pairKey(a: number, b: number): string
	return if a < b then `{a}:{b}` else `{b}:{a}`
end

local function areFriends(players: { [number]: Player }, a: number, b: number): boolean
	local key = pairKey(a, b)
	local cached = known[key]
	if cached ~= nil then
		return cached
	end
	local ok, result = pcall(function()
		return players[a]:IsFriendsWith(b)
	end)
	if not ok then
		return false -- try again next time (not cached)
	end
	known[key] = result == true
	return result == true
end

local function refresh()
	local players: { [number]: Player } = {}
	local ids: { number } = {}
	for _, player in Players:GetPlayers() do
		players[player.UserId] = player
		table.insert(ids, player.UserId)
	end
	local flags = FriendRules.flags(ids, function(a: number, b: number): boolean
		return areFriends(players, a, b)
	end)
	for _, player in Players:GetPlayers() do
		local had = Boosts.hasFriendBonus(player)
		local has = flags[player.UserId] == true
		Boosts.setFriendBonus(player, has)
		if has and not had then
			Net.event("Notice"):FireClient(
				player,
				{ kind = "friend", text = `Friend bonus! {Config.FRIEND_CASH_MULT}x cash while your friend is here!` } :: Types.Notice
			)
		elseif had and not has then
			Net.event("Notice"):FireClient(player, { kind = "friendOff", text = "Your friend left." } :: Types.Notice)
		end
	end
end

function Friends.init()
	Players.PlayerAdded:Connect(function()
		task.spawn(refresh)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		for key in known do
			local a, b = string.match(key, "^(%d+):(%d+)$")
			if a == tostring(player.UserId) or b == tostring(player.UserId) then
				known[key] = nil
			end
		end
		task.defer(refresh)
	end)
end

-- Also re-check once a minute, so a friend lookup that failed earlier gets another try.
function Friends.start()
	while true do
		refresh()
		task.wait(60)
	end
end

return Friends
