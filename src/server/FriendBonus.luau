--!strict
-- Friend bonus (QueueConfig.FriendLuck): a finder gets extra Luck for each Roblox friend of theirs in the same server,
-- up to MaxFriends. Player:IsFriendsWith yields and can fail, so answers are asked once per pair when a player joins
-- (in the background), cached for as long as both stay, and a failed call is simply not counted (and asked again
-- next time). The server sets the player attribute "FriendLuck" (fraction) so the client can show it; the client
-- never decides it.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local QueueConfig = require(Shared.QueueConfig)
local PetRules = require(Shared.PetRules)

local FriendBonus = {}

local cache: { [string]: boolean } = {}
local check = function(a: Player, b: Player): boolean
	return a:IsFriendsWith(b.UserId)
end

local function key(a: number, b: number): string
	return math.min(a, b) .. ":" .. math.max(a, b)
end

-- Tests only: replace the friendship check (and forget cached answers).
function FriendBonus.setCheck(fn: (Player, Player) -> boolean)
	check = fn
	table.clear(cache)
end

local function ask(a: Player, b: Player): boolean
	local k = key(a.UserId, b.UserId)
	local cached = cache[k]
	if cached ~= nil then
		return cached
	end
	local ok, res = pcall(check, a, b)
	if ok then
		cache[k] = res == true
		return res == true
	end
	return false
end

-- Friends of `player` in this server right now. With `cachedOnly` nothing yields (unknown pairs count as not friends).
function FriendBonus.count(player: Player, cachedOnly: boolean?): number
	local n = 0
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local yes = if cachedOnly then cache[key(player.UserId, other.UserId)] == true else ask(player, other)
			if yes then
				n += 1
			end
		end
	end
	return n
end

function FriendBonus.luck(player: Player, cachedOnly: boolean?): number
	local fc = QueueConfig.FriendLuck
	return PetRules.friendLuck(FriendBonus.count(player, cachedOnly), fc.PerFriend, fc.MaxFriends)
end

local function publish(player: Player)
	if player.Parent then
		local v = FriendBonus.luck(player, true)
		if player:GetAttribute("FriendLuck") ~= v then
			player:SetAttribute("FriendLuck", v)
		end
	end
end

local function onJoin(player: Player)
	for _, other in Players:GetPlayers() do
		if other ~= player then
			ask(player, other)
			publish(other)
		end
	end
	publish(player)
end

function FriendBonus.start()
	Players.PlayerAdded:Connect(function(p)
		task.spawn(onJoin, p)
	end)
	for _, p in Players:GetPlayers() do
		task.spawn(onJoin, p)
	end
	Players.PlayerRemoving:Connect(function(leaver)
		local id = leaver.UserId
		for _, other in Players:GetPlayers() do
			if other ~= leaver then
				cache[key(id, other.UserId)] = nil
			end
		end
		task.defer(function()
			for _, other in Players:GetPlayers() do
				publish(other)
			end
		end)
	end)
end

return FriendBonus
