--!strict
-- Studio dev shortcuts for screenshots (owner tool). Nothing here runs in a live game: the script returns at once
-- unless RunService:IsStudio(), and the server functions it calls refuse outside Studio too.
-- Chat commands (or ReplicatedStorage.DevCommand:FireServer("<same text>")):
--   /endround   end your current hunt round as if you found the pet egg (goes to results)
--   /findpet    same as /endround, named for the hatch check: your camera glides to your nest, then the big
--               "You hatched ...!" card with confetti, then the results
--   /boss [N]   jump your tower run to boss floor N (rounded up to a boss floor; no N = next boss floor)
--   /zone NAME  show hunt zone NAME (meadow, forest, snow, volcano, space) on your hunt arena, or on a free arena you
--               are moved to when not in a hunt
--   /coins N    set your coins to N (0 - 10,000,000), e.g. to test the egg shrine buys
--   /event NAME start a lobby event now: rain (coin rain), rock (golden rock) or egg (mystery egg)
--   /xp N       give every pet following you N XP (tower XP book, same as training)
--   /maxpet     put every pet following you at its level cap (to test EVOLVE)
--   /spin       spin the free wheel now (ignores the 4-hour clock; same pay as a real spin)
-- Chat works through TextChatService commands (TextChatCommand per command, made below) and legacy Player.Chatted.
-- Without chat: ServerStorage.DevRun:Invoke(player, "/coins 5000") from the Studio command bar returns (ok, message).
-- See docs/OWNER_STEPS.md "Studio dev shortcuts".
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

if not RunService:IsStudio() then
	return
end

local MatchService = require(script.Parent.MatchService)
local TowerService = require(script.Parent.TowerService)
local PartyService = require(script.Parent.PartyService)
local Profiles = require(script.Parent.Profiles)

local last: { [Player]: number } = {}

local function run(player: Player, text: any): (boolean?, string?)
	if not RunService:IsStudio() or type(text) ~= "string" or #text > 40 then
		return
	end
	local cmd, arg = string.match(string.lower(text), "^%s*/(%a+)%s*(%w*)")
	if cmd == "findpet" then
		cmd = "endround"
	end
	if cmd ~= "endround" and cmd ~= "boss" and cmd ~= "zone" and cmd ~= "coins" and cmd ~= "event" and cmd ~= "xp" and cmd ~= "maxpet" and cmd ~= "spin" then
		return
	end
	local t = os.clock()
	if t - (last[player] or 0) < 0.5 then
		return
	end
	last[player] = t
	local ok, msg
	if cmd == "endround" then
		ok, msg = MatchService.devEndRound(player)
	elseif cmd == "coins" then
		local data = Profiles.get(player)
		local n = tonumber(arg)
		if not data then
			ok, msg = false, "Profile not loaded yet."
		elseif not n then
			ok, msg = false, "Use /coins N"
		else
			data.Cash = math.clamp(math.floor(n), 0, 10_000_000)
			Profiles.changed(player)
			ok, msg = true, "Coins set to " .. data.Cash .. "."
		end
	elseif cmd == "spin" then
		local data = Profiles.get(player)
		if not data then
			ok, msg = false, "Profile not loaded yet."
		else
			local id, what = require(script.Parent.RetentionService).spin(player, data, true)
			ok, msg = id ~= nil, if id then "Spin: " .. tostring(what) .. " (" .. id .. ")" else "Spin refused: " .. tostring(what)
		end
	elseif cmd == "xp" or cmd == "maxpet" then
		local data = Profiles.get(player)
		local n = tonumber(arg)
		if not data or type(data.EquippedPets) ~= "table" or #data.EquippedPets == 0 then
			ok, msg = false, "Equip (follow) a pet first."
		elseif cmd == "xp" and not n then
			ok, msg = false, "Use /xp N"
		else
			local PetStats = require(game:GetService("ReplicatedStorage").Shared.PetStats)
			for _, id in data.EquippedPets do
				local g = TowerService.petById(player, id)
				if g then
					local cur = TowerService.xpOf(player, id)
					local want = if cmd == "xp" then math.clamp(math.floor(n :: number), 0, 1_000_000) else math.max(PetStats.xpForLevel(PetStats.cap(g)) - cur, 0)
					TowerService.addXp(player, id, want, true)
				end
			end
			Profiles.changed(player)
			ok, msg = true, if cmd == "xp" then "Gave " .. tostring(n) .. " XP to your following pets." else "Following pets are at max level."
		end
	elseif cmd == "event" then
		local kind = ({ rain = "CoinRain", rock = "GoldenRock", egg = "MysteryEgg" } :: any)[arg or ""]
		if not kind then
			ok, msg = false, "Use /event rain, /event rock or /event egg"
		elseif require(script.Parent.LobbyEvents).run(kind) then
			ok, msg = true, "Started " .. kind .. "."
		else
			ok, msg = false, "An event is already running."
		end
	elseif cmd == "zone" then
		ok, msg = MatchService.devZone(player, arg or "")
	else
		ok, msg = TowerService.devJump(player, tonumber(arg))
	end
	PartyService.toast(player, "[DEV] " .. msg, if ok then "info" else "warn")
	return ok, msg
end

local remote = Instance.new("RemoteEvent")
remote.Name = "DevCommand"
remote.Parent = ReplicatedStorage
remote.OnServerEvent:Connect(run)

local function hook(player: Player)
	player.Chatted:Connect(function(text)
		run(player, text)
	end)
end
Players.PlayerAdded:Connect(hook)
for _, p in Players:GetPlayers() do
	hook(p)
end
Players.PlayerRemoving:Connect(function(p)
	last[p] = nil
end)

-- TextChatService chat: Player.Chatted does not fire for it, so every command gets a TextChatCommand whose Triggered
-- runs on the server (the text is checked by run() like any other).
local TextChatService = game:GetService("TextChatService")
local folder = Instance.new("Folder")
folder.Name = "DevCommands"
for _, name in { "endround", "findpet", "boss", "zone", "coins", "event", "xp", "maxpet", "spin" } do
	local c = Instance.new("TextChatCommand")
	c.Name = "Dev_" .. name
	c.PrimaryAlias = "/" .. name
	c.Triggered:Connect(function(source: TextSource, text: string)
		local player = Players:GetPlayerByUserId(source.UserId)
		if player then
			run(player, text) -- the same text may also arrive through Player.Chatted: run()'s 0.5 s guard drops the twin
		end
	end)
	c.Parent = folder
end
pcall(function()
	folder.Parent = TextChatService
end)

-- Command bar (no chat): ServerStorage.DevRun:Invoke(game.Players.<you>, "/spin") returns (ok, message).
local bind = Instance.new("BindableFunction")
bind.Name = "DevRun"
bind.OnInvoke = function(player: any, text: any)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "Pass a Player"
	end
	last[player] = 0
	return run(player, text)
end
bind.Parent = game:GetService("ServerStorage")
