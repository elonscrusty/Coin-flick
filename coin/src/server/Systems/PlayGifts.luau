--!strict
-- Play-time gifts: stay in the game and gifts become ready (5, 15, 30, 60 minutes). The server owns the
-- state in profile.play and pays every reward; the client only says "claim gift N". Nothing is ever
-- taken away (see Shared/Util/PlayGifts). Time only counts while the player is in the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local DailyRules = require(ReplicatedStorage.Shared.Util.Daily)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Rules = require(ReplicatedStorage.Shared.Util.PlayGifts)
local Net = require(script.Parent.Net)
local PlayerData = require(script.Parent.PlayerData)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

type Profile = Types.Profile

local PlayGifts = {}

local TICK = 5 -- seconds between time updates
local limiter = RateLimiter.new(Config.BUY_RATE, Config.BUY_BURST, os.clock)
local lastSent: { [Player]: number } = {}

local function send(player: Player, profile: Profile)
	local today = DailyRules.day(os.time())
	Rules.rollover(profile.play, today)
	lastSent[player] = os.time()
	Net.event("PlayGiftState"):FireClient(player, Rules.view(profile.play, today, Economy.cashPerHeads(profile)))
end

local function onClaim(player: Player, rawSlot: unknown)
	if not limiter:allow(player) then
		return
	end
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	local reward = Rules.claim(profile.play, DailyRules.day(os.time()), rawSlot)
	if not reward then
		return
	end
	local cash = DailyRules.cash(reward, Economy.cashPerHeads(profile))
	profile.cash += cash
	profile.hatPoints += reward.hats
	PlayerData.changed(player)
	local text = if reward.hats > 0 then `+${Format.short(cash)} and +{reward.hats} 🎩` else `+${Format.short(cash)}`
	Net.event("Notice"):FireClient(player, { kind = "playGift", text = `Play gift! {text}` } :: Types.Notice)
	send(player, profile)
end

function PlayGifts.init()
	Net.event("ClaimPlayGift").OnServerEvent:Connect(onClaim)
	PlayerData.onLoaded(function(player: Player, profile: Profile)
		Rules.rollover(profile.play, DailyRules.day(os.time()))
		send(player, profile)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastSent[player] = nil
		limiter:remove(player)
	end)
end

-- Every few seconds: add the time, push the view only when something a player sees changed
-- (a gift became ready) or once a minute so the countdowns stay right.
function PlayGifts.start()
	while true do
		task.wait(TICK)
		local today = DailyRules.day(os.time())
		for _, player in Players:GetPlayers() do
			local profile = PlayerData.get(player)
			if profile then
				local before = Rules.claimable(profile.play)
				Rules.add(profile.play, today, TICK)
				local late = os.time() - (lastSent[player] or 0) >= 60
				if Rules.claimable(profile.play) ~= before or late then
					send(player, profile)
				end
			end
		end
	end
end

return PlayGifts
