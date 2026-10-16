--!strict
-- Daily login gift and daily quests (rules: shared/Quests.luau, tuning: shared/ProgressConfig.luau).
-- The server tracks everything: progress comes from what the server itself recorded (profile stats and the shell
-- sale), never from the client. Clients only send claims through ShopAction ("ClaimGift" / "ClaimQuest", index),
-- which EconomyService forwards here after its own rate limit. Coins only, never Robux.
--
-- Progress sources:
--   Crack  - Stats.RocksCracked goes up (RockService counts every egg a player finished)
--   Hunt   - Stats.MatchesPlayed goes up (MatchService counts every finished non-practice hunt)
--   Friend - the same, while a Roblox friend (Player:IsFriendsWith) is in the same hunt (same MatchKey attribute)
--   Hatch  - hatched pets (SoloFinds + MultiplayerWins) go up; the free starter pet does not count
--   Sell   - QuestService.note(player, "Sell") from EconomyService after a real shell sale
--   Display - QuestService.note(player, "Display") from EconomyService when a pet is put on display
--   TowerFloors - the profile counter TowerFloorsToday goes up. The tower calls QuestService.bump(player,
--            "TowerFloors", n) for each floor cleared (or adds to data.TowerFloorsToday itself and calls
--            Profiles.changed); either way each floor counts once. The counter resets every UTC day.
-- Every day has one race, one tower and one pet quest (shared/Quests.forDay).

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local Retention = require(Shared.Retention)
local Quests = require(Shared.Quests)
local EggPerks = require(Shared.EggPerks)
local LaunchPerks = require(Shared.LaunchPerks)
local Profiles = require(script.Parent.Profiles)

local QuestService = {}

type Seen = { Cracked: number, Played: number, Finds: number, Tower: number }
local seen: { [Player]: Seen } = {}

local function today(): number
	return Quests.day(os.time())
end

local function toast(player: Player, text: string, kind: string?)
	Net.event("Toast"):FireClient(player, text, kind or "info")
end

local function towerToday(data): number
	local n = data.TowerFloorsToday
	return if type(n) == "number" and n == n and n >= 0 then math.floor(n) else 0
end

local function snapshot(data): Seen
	return { Cracked = data.Stats.RocksCracked, Played = data.Stats.MatchesPlayed, Finds = Profiles.finds(data), Tower = towerToday(data) }
end

-- Moves the player's quest state to `day`. A new day clears today's progress and the tower floor counter.
-- Returns true when it changed anything.
local function rollDay(player: Player, data, day: number): boolean
	if not Quests.rollover(data.Daily, day) then
		return false
	end
	data.TowerFloorsToday = 0
	local s = seen[player]
	if s then
		s.Tower = 0
	end
	return true
end

-- Counts `n` toward today's quests of `kind` for this player (server-side callers only).
function QuestService.note(player: Player, kind: string, n: number?)
	local data = Profiles.get(player)
	if not data or Profiles.isReleased(player) then
		return
	end
	local rolled = rollDay(player, data, today())
	if Quests.bump(data.Daily, player.UserId, today(), kind, n or 1) or rolled then
		Profiles.changed(player, true)
	end
end

-- Hook for other services (the pet tower): bump(player, "TowerFloors", floorsCleared) adds to TowerFloorsToday,
-- and the change counts toward today's tower quest. Any other kind is the same as note().
function QuestService.bump(player: Player, kind: string, n: number?)
	if kind ~= "TowerFloors" then
		QuestService.note(player, kind, n)
		return
	end
	local data = Profiles.get(player)
	local add = if type(n) == "number" and n == n then math.floor(n) else 1
	if not data or Profiles.isReleased(player) or add <= 0 then
		return
	end
	rollDay(player, data, today())
	data.TowerFloorsToday = towerToday(data) + add
	Profiles.changed(player, true) -- onChanged turns the counter change into quest progress
end

-- Roblox friendship answers (Player:IsFriendsWith yields and can fail), cached per pair while both are in this
-- server; a failed call counts as "not friends" and is asked again next time.
local friendCache: { [string]: boolean } = {}
local function pairKey(a: number, b: number): string
	return math.min(a, b) .. ":" .. math.max(a, b)
end
local function areFriends(a: Player, b: Player): boolean
	local k = pairKey(a.UserId, b.UserId)
	local cached = friendCache[k]
	if cached ~= nil then
		return cached
	end
	local ok, res = pcall(function()
		return a:IsFriendsWith(b.UserId)
	end)
	if ok then
		friendCache[k] = res == true
	end
	return ok and res == true
end

-- Other players in the same hunt right now (the MatchKey attribute is cleared when a player leaves a hunt).
-- Read without yielding, at the moment the hunt is counted.
local function huntMates(player: Player): { Player }
	local out = {}
	local key = player:GetAttribute("MatchKey")
	if key == nil then
		return out
	end
	for _, p in Players:GetPlayers() do
		if p ~= player and p:GetAttribute("MatchKey") == key then
			table.insert(out, p)
		end
	end
	return out
end

-- "Play N hunts with a friend": counts only when a Roblox friend of the player was in the same hunt (strangers from
-- the public queue do not count). The friendship check may yield, so it runs on its own after the hunt was counted.
local function bumpIfFriend(player: Player, mates: { Player }, day: number, n: number)
	if #mates == 0 then
		return
	end
	task.spawn(function()
		for _, mate in mates do
			if areFriends(player, mate) then
				local data = Profiles.get(player)
				if data and not Profiles.isReleased(player) and Quests.bump(data.Daily, player.UserId, day, "Friend", n) then
					Profiles.changed(player, true)
				end
				return
			end
		end
	end)
end

local function onChanged(player: Player)
	local data = Profiles.get(player)
	if not data or not seen[player] then
		return
	end
	local day = today()
	local changed = rollDay(player, data, day)
	local last = seen[player]
	local now = snapshot(data)
	seen[player] = now
	if now.Cracked > last.Cracked then
		changed = Quests.bump(data.Daily, player.UserId, day, "Crack", now.Cracked - last.Cracked) or changed
	end
	if now.Played > last.Played then
		local n = now.Played - last.Played
		changed = Quests.bump(data.Daily, player.UserId, day, "Hunt", n) or changed
		bumpIfFriend(player, huntMates(player), day, n)
	end
	if now.Finds > last.Finds then
		changed = Quests.bump(data.Daily, player.UserId, day, "Hatch", now.Finds - last.Finds) or changed
	end
	if now.Tower > last.Tower then
		changed = Quests.bump(data.Daily, player.UserId, day, "TowerFloors", now.Tower - last.Tower) or changed
	end
	if changed and not Profiles.isReleased(player) then
		Profiles.changed(player, true)
	end
end

local function pay(player: Player, data: { [string]: any }, coins: number)
	data.Cash += coins
	data.Stats.CashEarned += coins
	Profiles.changed(player, true)
end

-- ShopAction claims (forwarded by EconomyService). Returns true when the action was a quest action.
function QuestService.handle(player: Player, action: string, id: any): boolean
	if action ~= "ClaimGift" and action ~= "ClaimQuest" then
		return false
	end
	local data = Profiles.get(player)
	if not data then
		return true
	end
	local day = today()
	rollDay(player, data, day)
	if action == "ClaimGift" then
		local coins, streakDay, why, shieldUsed = Quests.claimGift(data.Daily, day)
		if coins then
			pay(player, data, coins)
			local streak = data.Daily.Streak
			toast(player, streak .. " day streak! Daily gift: +" .. coins .. " coins!", "cash")
			-- day 7 of the streak also banks a free egg (LaunchPerks.StreakEgg; RobuxService hatches it for free)
			local egg = LaunchPerks.streakEgg(streakDay or 0)
			if egg then
				local perks = EggPerks.sanitize(data.EggPerks)
				data.EggPerks = perks
				if EggPerks.bankAdd(perks, egg) then
					toast(player, "DAY 7! You earned a FREE " .. EggPerks.eggName(egg) .. "!", "rare")
					Profiles.changed(player, true)
				end
			end
			if shieldUsed then
				toast(player, "Your streak shield saved your streak!", "rare")
			elseif streak % Retention.Streak.ShieldEvery == 0 and (data.Daily.Shields or 0) > 0 then
				toast(player, "You earned a streak shield! It saves your streak if you miss a day.", "rare")
			end
		elseif why == "Claimed" then
			toast(player, "You already opened today's gift. Come back tomorrow!", "info")
		end
	else
		local coins, why = Quests.claim(data.Daily, player.UserId, day, id)
		if coins then
			pay(player, data, coins)
			toast(player, "Quest done: +" .. coins .. " coins!", "cash")
			-- all of today's quests claimed: a free egg once a day (banked; RobuxService hatches it)
			local allClaimed = true
			for _, q in Quests.view(data.Daily, player.UserId, day).Quests do
				allClaimed = allClaimed and q.Claimed
			end
			if allClaimed then
				local perks = EggPerks.sanitize(data.EggPerks)
				data.EggPerks = perks
				local egg = EggPerks.questsDone(perks, day)
				if egg then
					toast(player, "Every quest done! You earned a FREE " .. EggPerks.eggName(egg) .. "!", "rare")
					Profiles.changed(player, true)
				end
			end
		elseif why == "NotDone" then
			toast(player, "That quest is not finished yet.", "info")
		elseif why == "Claimed" then
			Profiles.changed(player, true) -- the screen was stale: send the real state
		end
	end
	return true
end

function QuestService.start()
	Profiles.onLoaded(function(player, data)
		seen[player] = snapshot(data)
		if rollDay(player, data, today()) then
			Profiles.changed(player, true)
		end
	end)
	Profiles.onChanged(onChanged)
	Players.PlayerRemoving:Connect(function(p)
		seen[p] = nil
		local prefix, suffix = p.UserId .. ":", ":" .. p.UserId
		for k in friendCache do
			if string.sub(k, 1, #prefix) == prefix or string.sub(k, -#suffix) == suffix then
				friendCache[k] = nil
			end
		end
	end)
	-- UTC midnight: move everyone to the new day so the quest screen and the HUD dot refresh on their own.
	task.spawn(function()
		local lastDay = today()
		while true do
			task.wait(30)
			local d = today()
			if d ~= lastDay then
				lastDay = d
				for _, p in Players:GetPlayers() do
					local data = Profiles.get(p)
					if data and not Profiles.isReleased(p) and rollDay(p, data, d) then
						Profiles.changed(p, true)
					end
				end
			end
		end
	end)
end

return QuestService
