--!strict
-- Coin pets on the server: the active pet flips its own coin for extra cash
-- and levels up, and goals (flips, heads in a row, MEGA coin, resets) unlock
-- the other pets. All rules live in Shared/Util/PetRules; this file only
-- runs the timers, talks to the owner and hooks into flips and the mega coin.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PetConfig = require(ReplicatedStorage.Shared.PetConfig)
local Types = require(ReplicatedStorage.Shared.Types)
local PetRules = require(ReplicatedStorage.Shared.Util.PetRules)
local Boosts = require(script.Parent.Boosts)
local Net = require(script.Parent.Net)
local PlayerData = require(script.Parent.PlayerData)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local Pets = {}

local nextFlip: { [Player]: number } = {}
local limiter = RateLimiter.new(PetConfig.EQUIP_RATE, PetConfig.EQUIP_BURST, os.clock)

local function sendState(player: Player, profile: Types.Profile)
	Net.event("PetState"):FireClient(player, PetRules.view(profile), profile.petActive)
end

local function announceUnlocks(player: Player, profile: Types.Profile)
	local fresh = PetRules.checkUnlocks(profile)
	for _, id in fresh do
		local def = PetRules.def(id)
		if def then
			local notice: Types.Notice = { kind = "pet", text = `New pet! {def.icon} {def.name} is yours!` }
			Net.event("Notice"):FireClient(player, notice)
		end
	end
	if #fresh > 0 then
		PlayerData.changed(player)
		sendState(player, profile)
	end
end

-- Hook: this player helped flip the MEGA coin (called by Mega).
function Pets.onMegaBeat(player: Player)
	local profile = PlayerData.get(player)
	if profile then
		PetRules.recordMegaBeat(profile)
		announceUnlocks(player, profile)
	end
end

local function onEquip(player: Player, id: unknown)
	local profile = PlayerData.get(player)
	if not profile or not limiter:allow(player) then
		return
	end
	if PetRules.setActive(profile, id) then
		nextFlip[player] = nil
		PlayerData.changed(player)
		sendState(player, profile)
	end
end

local function tick(player: Player, profile: Types.Profile, now: number)
	local def = PetRules.def(profile.petActive)
	local pet = def and profile.pets[def.id]
	if not def or not pet then
		nextFlip[player] = nil
		return
	end
	local due = nextFlip[player]
	local wait = PetRules.interval(def, pet.level)
	if not due then
		nextFlip[player] = now + wait -- just came out: first flip after one full wait
		return
	end
	if now < due then
		return
	end
	nextFlip[player] = now + wait
	local result = PetRules.flip(profile, Boosts.cashMult(player, now))
	if not result then
		return
	end
	PlayerData.changed(player)
	Net.event("PetFlipped"):FireClient(player, result.id, result.cash, result.level, result.leveled)
	if result.leveled then
		sendState(player, profile)
	end
end

function Pets.init()
	Net.event("PetEquip").OnServerEvent:Connect(onEquip)
	PlayerData.onLoaded(function(player: Player, profile: Types.Profile)
		-- Older saves may already have earned pets (1,000 flips, resets).
		announceUnlocks(player, profile)
		sendState(player, profile)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		nextFlip[player] = nil
		limiter:remove(player)
	end)
end

function Pets.start()
	local slow = 0
	while true do
		task.wait(0.2)
		local now = os.clock()
		slow += 1
		for _, player in Players:GetPlayers() do
			local profile = PlayerData.get(player)
			if profile then
				tick(player, profile, now)
				-- Resets and flip counts change elsewhere; look for new pets once a second.
				if slow % 5 == 0 then
					announceUnlocks(player, profile)
				end
			end
		end
	end
end

return Pets
