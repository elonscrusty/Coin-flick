--!strict
-- Long goals on the server: the streak ladder (coin looks earned by best streak), weekly
-- challenges and the coin book. The server owns the state in the profile and pays every prize;
-- the client only says "claim challenge N" / "wear ladder look X". Rules: Shared/Util/Goals.
-- Other systems call Goals.bump (flip, heads, mega, buy, streak) and Goals.onFlip (rare coins).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GoalsConfig = require(ReplicatedStorage.Shared.GoalsConfig)
local Types = require(ReplicatedStorage.Shared.Types)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local GoalRules = require(ReplicatedStorage.Shared.Util.Goals)
local Net = require(script.Parent.Net)
local PlayerData = require(script.Parent.PlayerData)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

type Profile = Types.Profile

local Goals = {}

local limiter = RateLimiter.new(GoalsConfig.CLAIM_RATE, GoalsConfig.CLAIM_BURST, os.clock)
local dirty: { [Player]: boolean } = {}
local lastWeek: { [Player]: number } = {}
local rungsSeen: { [Player]: number } = {}

local function notify(player: Player, text: string)
	Net.event("Notice"):FireClient(player, { kind = "goals", text = text } :: Types.Notice)
end

local function pay(player: Player, profile: Profile, reward: GoalRules.Reward): string
	local cash = GoalRules.cash(reward, Economy.cashPerHeads(profile))
	profile.cash += cash
	profile.hatPoints += reward.hats
	PlayerData.changed(player)
	dirty[player] = true
	return if reward.hats > 0 then `+${Format.short(cash)} and +{reward.hats} 🎩` else `+${Format.short(cash)}`
end

-- Count progress toward this week's challenges. Cheap; safe to call on every flip.
function Goals.bump(player: Player, kind: string, n: number?)
	local profile = PlayerData.get(player)
	if profile and GoalRules.bumpChallenge(profile.challenges, GoalRules.week(os.time()), kind, n) then
		dirty[player] = true
	end
end

-- Call after every flip of the player's coins (taps, helpers, auto flip). Rare coins fill the book.
function Goals.onFlip(player: Player, rarity: Types.Rarity)
	if rarity == "normal" then
		return
	end
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	Goals.bump(player, "rare", 1)
	local page, all = GoalRules.recordRare(profile.book, rarity)
	dirty[player] = true
	if page then
		notify(player, `New in your coin book: {string.upper(rarity)}! {pay(player, profile, page)}`)
	end
	if all then
		notify(player, `COIN BOOK FULL! Every rare coin found! {pay(player, profile, all)}`)
	end
end

local function onClaimChallenge(player: Player, rawSlot: unknown)
	if not limiter:allow(player) then
		return
	end
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	local week = GoalRules.week(os.time())
	if rawSlot == 0 then
		local bonus = GoalRules.claimChallengeBonus(profile.challenges, week)
		if bonus then
			notify(player, `All weekly challenges done! {pay(player, profile, bonus)}`)
		end
		return
	end
	local reward = GoalRules.claimChallenge(profile.challenges, week, rawSlot)
	if reward then
		notify(player, `Weekly challenge done! {pay(player, profile, reward)}`)
	end
end

local lookChanged: (Player) -> () = function() end

-- Tables.init gives us its rebuild, so a new coin look shows at once (Tables needs Goals, not the reverse).
function Goals.setLookChanged(fn: (Player) -> ())
	lookChanged = fn
end

local function onWearLadder(player: Player, rawId: unknown)
	if not limiter:allow(player) then
		return
	end
	local profile = PlayerData.get(player)
	if profile and GoalRules.wearRung(profile, rawId) then
		lookChanged(player)
		PlayerData.changed(player)
		dirty[player] = true
	end
end

-- New best streak -> new coin look: tell the player the moment a rung is reached.
local function checkLadder(player: Player, profile: Profile)
	local owned = GoalRules.rungsOwned(profile)
	local seen = rungsSeen[player]
	rungsSeen[player] = owned
	if seen and owned > seen then
		local rung = GoalsConfig.Ladder[owned]
		notify(player, `New coin look: {rung.icon} {rung.name}! Wear it in your goals.`)
		dirty[player] = true
	end
end

local function send(player: Player, profile: Profile)
	local now = os.time()
	lastWeek[player] = GoalRules.week(now)
	GoalRules.rolloverChallenges(profile.challenges, lastWeek[player])
	Net.event("GoalsState"):FireClient(player, GoalRules.view(profile, now, Economy.cashPerHeads(profile)))
end

function Goals.init()
	Net.event("ClaimChallenge").OnServerEvent:Connect(onClaimChallenge)
	Net.event("WearLadder").OnServerEvent:Connect(onWearLadder)
	PlayerData.onLoaded(function(player: Player, profile: Profile)
		GoalRules.rolloverChallenges(profile.challenges, GoalRules.week(os.time()))
		rungsSeen[player] = GoalRules.rungsOwned(profile) -- looks from before this visit are not "new"
		dirty[player] = true
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		dirty[player] = nil
		lastWeek[player] = nil
		rungsSeen[player] = nil
		limiter:remove(player)
	end)
end

-- Push the view at most once a second per player, and again when the week turns over.
function Goals.start()
	while true do
		task.wait(1)
		local week = GoalRules.week(os.time())
		for _, player in Players:GetPlayers() do
			local profile = PlayerData.get(player)
			if profile then
				checkLadder(player, profile)
				if dirty[player] or (lastWeek[player] and lastWeek[player] ~= week) then
					dirty[player] = nil
					send(player, profile)
				end
			end
		end
	end
end

return Goals
