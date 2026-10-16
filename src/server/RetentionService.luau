--!strict
-- First five minutes and comeback hooks (rules and tuning: shared/Retention, streak extras: shared/Quests).
-- The server decides every reward; clients send intents only on RetentionAction:
--   "Ready"    the client UI is up: any waiting notice (away nest, friend gift) is sent now
--   "Starter"  hatch the free starter egg (lobby only, once per player; PetService.ensureStarter rolls Rare or better)
--   "Gift"     open the next play-time gift once its time is reached
-- Notices go back on the "Retention" event as (kind, payload):
--   ("Starter", { Pet })                    the starter pet that just hatched (public specimen) for the hatch show
--   ("Gift", { Coins, Index })              a play-time gift was opened
--   ("GiftReady", { Index })                a play-time gift is ready to open
--   ("Away", { Seconds, Eggs, Coins, Pet?, WelcomeBack })   eggs hatched while the player was away
--   ("Friend", { Name, Coins })             a Roblox friend is in this server: friend gift paid
--   ("Group", { Coins })                    the daily group gift was paid

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local GeodeGen = require(Shared.GeodeGen)
local Net = require(Shared.Net)
local Retention = require(Shared.Retention)
local LaunchPerks = require(Shared.LaunchPerks)
local RobuxConfig = require(Shared.RobuxConfig)
local EggPerks = require(Shared.EggPerks)
local Profiles = require(script.Parent.Profiles)
local PetService = require(script.Parent.PetService)

local RetentionService = {}

local TICK = 5 -- seconds between play-time ticks
local greeted: { [Player]: boolean } = {} -- away check done for this join (play time and LastSeen count after it)
type Notice = { Kind: string, Payload: { [string]: any } }
local pending: { [Player]: { Notice } } = {} -- notices waiting for the client's "Ready"
local ready: { [Player]: boolean } = {}
local lastAction: { [Player]: number } = {}
local lobbyServer = true

local friendCheck = function(a: Player, b: Player): boolean
	return a:IsFriendsWith(b.UserId)
end
-- Tests only: replace the Roblox friend check (it yields and can fail; failures pay nothing). The group check moved
-- to LobbyHangout (one group reward: LobbyHangout.checkGroup asks Roblox once and calls groupDaily); `_group` is kept
-- so old callers still work.
function RetentionService.setChecks(friend: ((Player, Player) -> boolean)?, _group: ((Player, number) -> boolean)?)
	if friend then
		friendCheck = friend
	end
end

local function today(): number
	return Retention.day(os.time())
end

local function notify(player: Player, kind: string, payload: { [string]: any })
	if ready[player] then
		Net.event("Retention"):FireClient(player, kind, payload)
	else
		local list = pending[player] or {}
		pending[player] = list
		table.insert(list, { Kind = kind, Payload = payload })
	end
end

local function pay(player: Player, data: { [string]: any }, coins: number)
	if coins <= 0 then
		return
	end
	data.Cash += coins
	data.Stats.CashEarned += coins
	Profiles.changed(player, true)
end

local function usable(player: Player): { [string]: any }?
	if not Profiles.isLoaded(player) or Profiles.isReleased(player) then
		return nil
	end
	return Profiles.get(player)
end

-- The best zone this player has unlocked (an away-nest pet comes from there).
local function bestTier(data: { [string]: any }): string
	local best = Config.TierOrder[1]
	for _, tid in Config.TierOrder do
		if type(data.UnlockedTiers) == "table" and data.UnlockedTiers[tid] == true then
			best = tid
		end
	end
	return best
end

-- Starter egg -----------------------------------------------------------------------------------

-- Hatches the starter pet and tells the client to play the show. Returns true when it hatched just now.
function RetentionService.hatchStarter(player: Player): boolean
	local pet = PetService.ensureStarter(player)
	if not pet then
		return false
	end
	notify(player, "Starter", { Pet = GeodeGen.public(pet :: any) })
	return true
end

-- Away nest --------------------------------------------------------------------------------------

local function greet(player: Player, data: { [string]: any })
	local st = data.Retention
	local now = os.time()
	local reward = if lobbyServer then Retention.away(st.LastSeen, now) else nil
	st.LastSeen = now
	greeted[player] = true
	if not reward then
		return
	end
	pay(player, data, reward.Coins)
	local petView = nil
	-- first pet rule: no free pet before the starter egg hatched (the coins still come)
	if reward.Pet and Retention.freePetReady(data) and #data.InventoryGeodes < Profiles.petCapacity(data) then
		local tier = bestTier(data)
		-- a Common pet of the best zone (never a chase pet: the chase pet is Legendary only)
		local pet = GeodeGen.roll(Random.new(), tier, HttpService:GenerateGUID(false), "away", now, true, 0, { Common = 1 })
		if Profiles.grantSpecimen(player, "away:" .. player.UserId .. ":" .. now, pet, "Gift") then
			petView = GeodeGen.public(pet)
		end
	end
	notify(player, "Away", {
		Seconds = reward.Seconds,
		Eggs = reward.Eggs,
		Coins = reward.Coins,
		Pet = petView,
		WelcomeBack = reward.WelcomeBack,
	})
end

RetentionService.greet = greet -- (tests) the away check a fresh join runs

-- Friend + group gifts ----------------------------------------------------------------------------

local function friendGifts(player: Player)
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local ok, yes = pcall(friendCheck, player, other)
			if ok and yes == true then
				local day = today()
				for _, pair in { { player, other }, { other, player } } do
					local who, friend = pair[1], pair[2]
					local data = usable(who)
					if data then
						local coins = Retention.friendGift(data.Retention, day, friend.UserId)
						if coins > 0 then
							pay(who, data, coins)
							notify(who, "Friend", { Name = friend.DisplayName, Coins = coins })
						end
					end
				end
			end
		end
	end
end

-- The daily group coins (part of the one group reward; LobbyHangout.checkGroup decides membership and calls this).
-- Returns the coins paid (0 when off, not a member, or already paid today).
function RetentionService.groupDaily(player: Player, member: boolean): number
	if Retention.Group.Id == 0 then
		return 0
	end
	local data = usable(player)
	if not data then
		return 0
	end
	local coins = Retention.groupGift(data.Retention, today(), member)
	if coins > 0 then
		pay(player, data, coins)
		notify(player, "Group", { Coins = coins })
	end
	return coins
end

-- Play-time gifts -----------------------------------------------------------------------------------

-- One play-time tick for every greeted player (exposed for tests).
function RetentionService.tick(dt: number)
	local day = today()
	local now = os.time()
	for _, player in Players:GetPlayers() do
		local data = if greeted[player] then usable(player) else nil
		if data then
			local st = data.Retention
			st.LastSeen = now
			if Retention.tickPlay(st, day, dt) then
				Profiles.changed(player, true) -- the timer turns into OPEN
				notify(player, "GiftReady", { Index = st.Play.Claimed + Retention.readyGifts(st, day) })
			end
		end
	end
end

-- Spin wheel (LaunchPerks.Spin, idea 3): one free spin every 4 hours. The server rolls the slice and pays it; the
-- client only animates the wheel onto the slice it is told ("Spin", { Slice, Text }).
local spinRng = Random.new()
-- Every tap gets an answer: "Spin" { Slice, Text } or "SpinNo" { In = seconds left | Text }. force = Studio dev spin
-- (the 4-hour clock is ignored; DevCommands "/spin").
local function spinNow(player: Player, data: { [string]: any }, force: boolean?): (string?, string?)
	local perks = LaunchPerks.sanitize(data.Perks)
	data.Perks = perks
	local now = os.time()
	if force then
		perks.SpinAt = 0
	end
	local slice, why = LaunchPerks.spin(perks, now, spinRng:NextNumber())
	if not slice then
		if why == "NotYet" then
			Profiles.changed(player, true) -- the screen was early: send the real timer
			notify(player, "SpinNo", { In = LaunchPerks.spinLeft(perks, now) })
		end
		return nil, why
	end
	local tierId = RobuxConfig.eggTier(data.UnlockedTiers)
	local text = LaunchPerks.sliceText(slice, tierId)
	if slice.Kind == "Coins" then
		pay(player, data, LaunchPerks.sliceCoins(slice, tierId))
	elseif slice.Kind == "Potion" then
		RobuxConfig.addPotion(data.Robux, now, (slice.Minutes or 0) * 60)
		data.Robux.PotionsBought = math.max(0, (data.Robux.PotionsBought or 1) - 1) -- a free potion is not a purchase
	else
		local eggPerks = EggPerks.sanitize(data.EggPerks)
		data.EggPerks = eggPerks
		if not (slice.Egg and EggPerks.bankAdd(eggPerks, slice.Egg)) then
			-- the free egg bank is full: the same spin pays the big coin slice instead
			local big = LaunchPerks.slice("CoinsL") :: LaunchPerks.Slice
			pay(player, data, LaunchPerks.sliceCoins(big, tierId))
			text = LaunchPerks.sliceText(big, tierId)
		end
	end
	Profiles.changed(player, true)
	notify(player, "Spin", { Slice = slice.Id, Text = text })
	return slice.Id, text
end

function RetentionService.spin(player: Player, data: { [string]: any }, force: boolean?): (string?, string?)
	local ok, id, text = pcall(spinNow, player, data, force)
	if not ok then
		warn("[RetentionService] spin failed:", id)
		notify(player, "SpinNo", { Text = "Spin failed. Try again!" })
		return nil, "Error"
	end
	return id, text
end

local function onAction(player: Player, action: any)
	local t = os.clock()
	if lastAction[player] and t - lastAction[player] < 0.3 then
		return
	end
	lastAction[player] = t
	if action == "Ready" then
		ready[player] = true
		local list: { Notice } = pending[player] or {}
		pending[player] = nil
		for _, n in list do
			Net.event("Retention"):FireClient(player, n.Kind, n.Payload)
		end
		return
	end
	local data = usable(player)
	if not data then
		return
	end
	if action == "Starter" then
		if not lobbyServer then
			return
		end
		if not RetentionService.hatchStarter(player) and data.StarterPet ~= true then
			Net.event("Toast"):FireClient(player, "Your Pet Book is full. Sell a pet to hatch your starter egg!", "warn")
		end
	elseif action == "Spin" then
		RetentionService.spin(player, data)
	elseif action == "Gift" then
		local coins, index, why = Retention.claimGift(data.Retention, today())
		if coins then
			pay(player, data, coins)
			notify(player, "Gift", { Coins = coins, Index = index })
		elseif why == "NotYet" then
			Profiles.changed(player, true) -- the screen was early: send the real timer
		end
	end
end

function RetentionService.start(isMatch: boolean)
	lobbyServer = not isMatch
	Net.event("RetentionAction").OnServerEvent:Connect(onAction)
	Profiles.onLoaded(function(player, data)
		data = data or Profiles.get(player)
		if not data then
			return
		end
		greet(player, data)
		task.spawn(friendGifts, player) -- the group gift: LobbyHangout.checkGroup (one group reward)
	end)
	Players.PlayerRemoving:Connect(function(player)
		greeted[player] = nil
		pending[player] = nil
		ready[player] = nil
		lastAction[player] = nil
	end)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(TICK)
			local t = os.clock()
			RetentionService.tick(t - last)
			last = t
		end
	end)
end

return RetentionService
