--!strict
-- Daily gift (7 days, a missed day never punishes) and 3 daily jobs. The server owns the state in
-- profile.daily and pays every reward; the client only says "claim the gift" / "claim job N".
-- Other systems call Daily.bump(player, kind, n) when a flip, heads, mega help or upgrade happens.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local DailyRules = require(ReplicatedStorage.Shared.Util.Daily)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Net = require(script.Parent.Net)
local PlayerData = require(script.Parent.PlayerData)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

type Profile = Types.Profile

local Daily = {}

local limiter = RateLimiter.new(Config.BUY_RATE, Config.BUY_BURST, os.clock)
local dirty: { [Player]: boolean } = {}
local lastDay: { [Player]: number } = {}

local function notify(player: Player, text: string)
	Net.event("Notice"):FireClient(player, { kind = "daily", text = text } :: Types.Notice)
end

-- Count progress toward today's jobs. Cheap; safe to call on every flip.
function Daily.bump(player: Player, kind: string, n: number?)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	local today = DailyRules.day(os.time())
	if DailyRules.bump(profile.daily, player.UserId, today, kind, n) then
		dirty[player] = true
	end
end

local function pay(player: Player, profile: Profile, reward: DailyRules.Reward): (number, number)
	local cash = DailyRules.cash(reward, Economy.cashPerHeads(profile))
	profile.cash += cash
	profile.hatPoints += reward.hats
	PlayerData.changed(player)
	dirty[player] = true
	return cash, reward.hats
end

local function prize(cash: number, hats: number): string
	return if hats > 0 then `+${Format.short(cash)} and +{hats} 🎩` else `+${Format.short(cash)}`
end

local function onClaimGift(player: Player)
	if not limiter:allow(player) then
		return
	end
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	local reward, index = DailyRules.claimGift(profile.daily, DailyRules.day(os.time()))
	if not reward or not index then
		return
	end
	local cash, hats = pay(player, profile, reward)
	notify(player, `Daily gift, day {index}! {prize(cash, hats)}`)
end

local function onClaimJob(player: Player, rawSlot: unknown)
	if not limiter:allow(player) then
		return
	end
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	local reward = DailyRules.claimJob(profile.daily, player.UserId, DailyRules.day(os.time()), rawSlot)
	if not reward then
		return
	end
	local cash, hats = pay(player, profile, reward)
	notify(player, `Daily job done! {prize(cash, hats)}`)
end

local function send(player: Player, profile: Profile)
	local today = DailyRules.day(os.time())
	lastDay[player] = today
	DailyRules.rollover(profile.daily, today)
	Net.event("DailyState")
		:FireClient(player, DailyRules.view(profile.daily, player.UserId, today, Economy.cashPerHeads(profile)))
end

function Daily.init()
	Net.event("ClaimGift").OnServerEvent:Connect(onClaimGift)
	Net.event("ClaimJob").OnServerEvent:Connect(onClaimJob)
	PlayerData.onLoaded(function(player: Player, profile: Profile)
		DailyRules.rollover(profile.daily, DailyRules.day(os.time()))
		dirty[player] = true
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		dirty[player] = nil
		lastDay[player] = nil
		limiter:remove(player)
	end)
end

-- Push the view at most once a second per player, and again when midnight (UTC) passes.
function Daily.start()
	while true do
		task.wait(1)
		local today = DailyRules.day(os.time())
		for _, player in Players:GetPlayers() do
			local profile = PlayerData.get(player)
			if profile and (dirty[player] or (lastDay[player] and lastDay[player] ~= today)) then
				dirty[player] = nil
				send(player, profile)
			end
		end
	end
end

return Daily
