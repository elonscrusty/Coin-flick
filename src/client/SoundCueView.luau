--!strict
-- Find The Pet moment sounds heard from server messages (client only, cosmetic): Pet Battle matched / lost, training
-- taps, tower floor cleared / lost, gifts opened, coins gained. Which key plays where: shared/SoundCues. Each listener is
-- an extra connection next to the panels' own, so no panel code changes. Every id 0 plays nothing (Audio).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local SoundCues = require(Shared.SoundCues)
local Audio = require(script.Parent.Audio)
local State = require(script.Parent.State)

local SoundCueView = {}

local started = false
local lastCash: number? = nil
local sellAt = -math.huge -- a sale plays its own coin sound when the coins land (Main.client Fx "Sell")

local function listen(folderName: string, eventName: string, pick: (any) -> string?)
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild(folderName, 60)
		local ev = folder and folder:WaitForChild(eventName, 30)
		if ev and ev:IsA("RemoteEvent") then
			ev.OnClientEvent:Connect(function(msg)
				local key = pick(msg)
				if key then
					Audio.play(key)
				end
			end)
		end
	end)
end

function SoundCueView.start()
	if started then
		return
	end
	started = true
	listen("PvpNet", "PvpEvent", SoundCues.pvp)
	listen("TowerNet", "TowerEvent", SoundCues.tower)
	Net.event("Retention").OnClientEvent:Connect(function(kind)
		local key = SoundCues.retention(kind)
		if key then
			Audio.play(key)
		end
	end)
	Net.event("Fx").OnClientEvent:Connect(function(kind)
		if kind == "Sell" then
			sellAt = os.clock()
		end
	end)
	-- coin gain: any rise of the saved coins (not the first load, not a sale, which rings when its coins land)
	State.Changed.Event:Connect(function(what)
		if what ~= "Profile" or not State.Profile then
			return
		end
		local cash = tonumber(State.Profile.Cash)
		if not cash then
			return
		end
		local before = lastCash
		lastCash = cash
		if before and cash > before and os.clock() - sellAt > 2 then
			Audio.play("CoinPickup", { Volume = 0.8, Key = "coin:gain" })
		end
	end)
end

return SoundCueView
