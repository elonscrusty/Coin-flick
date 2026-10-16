--!strict
-- Logs where first-time players stop playing (see Shared/Util/Funnel): each milestone once to Roblox
-- Analytics, "still here" minute marks, and a "Left" event with how far they got. Read-only: it never
-- changes a profile and a failed log call is ignored.

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage.Shared.Util.Funnel)
local PlayerData = require(script.Parent.PlayerData)

local Funnel = {}

type Visit = { joined: number, reached: { [number]: boolean }, minute: number }

local visits: { [Player]: Visit } = {}

local function log(fn: () -> ())
	local ok, err = (pcall :: any)(fn)
	if not ok then
		warn(`[Funnel] log failed: {err}`)
	end
end

local function check(player: Player)
	local visit = visits[player]
	local profile = PlayerData.get(player)
	if not visit or not profile then
		return
	end
	for _, index in Rules.newlyReached(profile, visit.reached) do
		visit.reached[index] = true
		log(function()
			AnalyticsService:LogOnboardingFunnelStepEvent(player, index, Rules.steps[index].name)
		end)
	end
	local seconds = os.time() - visit.joined
	local mark = Rules.minuteMark(seconds)
	if mark > visit.minute then
		visit.minute = mark
		log(function()
			AnalyticsService:LogCustomEvent(player, "StillPlaying", mark)
		end)
	end
end

function Funnel.init()
	PlayerData.onLoaded(function(player: Player)
		visits[player] = { joined = os.time(), reached = {}, minute = 0 }
		check(player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		local visit = visits[player]
		if visit then
			local seconds = os.time() - visit.joined
			log(function()
				AnalyticsService:LogCustomEvent(player, "Left", seconds, {
					[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = `step{Rules.furthest(visit.reached)}`,
				})
			end)
		end
		visits[player] = nil
	end)
end

function Funnel.start()
	while true do
		task.wait(3)
		for _, player in Players:GetPlayers() do
			check(player)
		end
	end
end

return Funnel
