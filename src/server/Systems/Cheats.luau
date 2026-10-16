--!strict
-- Studio-only QA buttons, so testing doesn't take an hour of tapping.
-- The remote only exists in Studio, and every call re-checks IsStudio().

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(script.Parent.Net)
local PlayerData = require(script.Parent.PlayerData)
local Tables = require(script.Parent.Tables)
local GameLogic = require(script.Parent.Parent.Util.GameLogic)
local ProfileSchema = require(ReplicatedStorage.Shared.Util.ProfileSchema)

local Cheats = {}

local function onCheat(player: Player, command: unknown)
	if not RunService:IsStudio() then
		return
	end
	local profile = PlayerData.get(player)
	if not profile or typeof(command) ~= "string" then
		return
	end
	if command == "cash" then
		profile.cash += 1000000
	elseif command == "fill" then
		GameLogic.fillTable(profile)
		Tables.refresh(player)
	elseif command == "wipe" then
		local fresh = ProfileSchema.default()
		for key, value in fresh :: any do
			(profile :: any)[key] = value
		end
		Tables.refresh(player)
	else
		return
	end
	PlayerData.changed(player)
end

function Cheats.init()
	if not RunService:IsStudio() then
		return
	end
	Net.event("Cheat").OnServerEvent:Connect(onCheat)
end

return Cheats
