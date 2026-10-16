--!strict
-- Cash shop (upgrades + helper guys) and the table RESET. Hats and Robux live in Hats and Robux.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local Net = require(script.Parent.Net)
local PlayerData = require(script.Parent.PlayerData)
local Tables = require(script.Parent.Tables)
local GameLogic = require(script.Parent.Parent.Util.GameLogic)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local Shop = {}

local buyLimiter = RateLimiter.new(Config.BUY_RATE, Config.BUY_BURST, os.clock)
local REBUILD_ON: { [string]: boolean } = { moreCoins = true, bigCoins = true }

local function notify(player: Player, kind: string, text: string)
	Net.event("Notice"):FireClient(player, { kind = kind, text = text } :: Types.Notice)
end

local function onBuyUpgrade(player: Player, rawId: unknown)
	if not buyLimiter:allow(player) then
		return
	end
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	local ok = GameLogic.buyUpgrade(profile, rawId)
	if not ok then
		return
	end
	local id = rawId :: string -- validated by buyUpgrade
	if REBUILD_ON[id] then
		Tables.refresh(player)
	end
	PlayerData.changed(player)
	notify(player, "bought", `{Config.Upgrades[id].name} level {profile.upgrades[id :: Types.UpgradeId]}!`)
end

local function onBuyHelper(player: Player, rawId: unknown)
	if not buyLimiter:allow(player) then
		return
	end
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	if GameLogic.unlockHelper(profile, rawId) then
		local def = Economy.helperDef(rawId)
		Tables.refresh(player)
		PlayerData.changed(player)
		notify(player, "bought", `{if def then def.name else "A helper"} joined your crew!`)
	end
end

local function onLevelHelper(player: Player, rawId: unknown)
	if not buyLimiter:allow(player) then
		return
	end
	local profile = PlayerData.get(player)
	if profile and GameLogic.levelHelper(profile, rawId) then
		local def = Economy.helperDef(rawId)
		Tables.refresh(player) -- he grows a little
		PlayerData.changed(player)
		if def then
			notify(player, "bought", `{def.name} is now level {profile.crew[def.id]}!`)
		end
	end
end

local function onTeamHelper(player: Player, rawId: unknown, on: unknown)
	if not buyLimiter:allow(player) then
		return
	end
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	local ok, why = GameLogic.setTeam(profile, rawId, on)
	if ok then
		Tables.refresh(player)
		PlayerData.changed(player)
	elseif why == "no free slot" then
		notify(player, "soon", "All helper spots are full. Take one off first!")
	end
end

local function onReset(player: Player)
	if not buyLimiter:allow(player) then
		return
	end
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	if GameLogic.reset(profile) then
		Tables.refresh(player)
		PlayerData.changed(player)
		local look = Config.TableLooks[Economy.tableLook(profile.resets)]
		notify(
			player,
			"reset",
			`RESET! Cash x{Economy.resetMultiplier(profile.resets)} forever. New table: {look.name}`
		)
	end
end

function Shop.init()
	Net.event("BuyUpgrade").OnServerEvent:Connect(onBuyUpgrade)
	Net.event("BuyHelper").OnServerEvent:Connect(onBuyHelper)
	Net.event("LevelHelper").OnServerEvent:Connect(onLevelHelper)
	Net.event("TeamHelper").OnServerEvent:Connect(onTeamHelper)
	Net.event("ResetTable").OnServerEvent:Connect(onReset)
	Players.PlayerRemoving:Connect(function(player: Player)
		buyLimiter:remove(player)
	end)
end

return Shop
