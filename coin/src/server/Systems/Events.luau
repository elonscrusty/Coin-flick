--!strict
-- Weekend events (UTC Saturday + Sunday): luck x2 for rare coins and a coin rain every ten minutes.
-- The clock decides, so every server agrees. Sends EventState to everyone when something changes and
-- to each player on join, plus a Notice banner when the weekend or a rain starts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Rules = require(ReplicatedStorage.Shared.Util.WeekendEvents)
local Boosts = require(script.Parent.Boosts)
local Net = require(script.Parent.Net)
local PlayerData = require(script.Parent.PlayerData)

local Events = {}

local current: Types.EventView? = nil

local function banner(text: string)
	for _, player in Players:GetPlayers() do
		Net.event("Notice"):FireClient(player, { kind = "event", text = text } :: Types.Notice)
	end
end

local function update()
	local view = Rules.status(os.time())
	Boosts.setEventLuck(view.luckMult)
	Boosts.setEventMult(view.cashMult)
	local before = current
	if Rules.changed(before, view) then
		current = view
		Net.event("EventState"):FireAllClients(view)
		-- A banner only on the way in (not on server start in the middle of an event).
		if before then
			if view.weekend and not before.weekend then
				banner(`WEEKEND! Rare coins x{Config.Events.LUCK_MULT} luck!`)
			elseif view.rain and not before.rain then
				banner(`COIN RAIN! Heads pay x{Config.Events.RAIN_MULT}!`)
			end
		end
	end
end

function Events.init()
	PlayerData.onLoaded(function(player: Player)
		if current then
			Net.event("EventState"):FireClient(player, current)
		end
	end)
	update()
end

function Events.start()
	while true do
		task.wait(1)
		update()
	end
end

return Events
