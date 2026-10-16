--!strict
-- Badges: 10 heads in a row, 1,000,000 flips, first reset, every helper. The server checks the saved
-- profile and keeps each badge once in profile.badges. A Roblox badge is awarded only when the badge
-- id in Config.Badges is set (carter makes the badges and gives the ids: all 0 until then, and 0 is
-- never sent to Roblox). Other systems call Badges.check(player) after something worth a badge happens.

local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Rules = require(ReplicatedStorage.Shared.Util.Badges)
local Net = require(script.Parent.Net)
local PlayerData = require(script.Parent.PlayerData)

type Profile = Types.Profile

local Badges = {}

local pending: { [Player]: boolean } = {}

local function awardOnRoblox(player: Player, badgeId: number)
	if badgeId <= 0 then
		return
	end
	local ok, err = pcall(function()
		BadgeService:AwardBadge(player.UserId, badgeId)
	end)
	if not ok then
		warn(`[Badges] award {badgeId} failed: {err}`)
	end
end

local function send(player: Player, profile: Profile)
	Net.event("BadgeState"):FireClient(player, Rules.view(profile))
end

-- Checks every badge now. Safe to call often (it only does a few comparisons).
function Badges.check(player: Player)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	local new = Rules.award(profile)
	if #new == 0 then
		return
	end
	PlayerData.changed(player)
	for _, def in new do
		Net.event("Notice"):FireClient(player, { kind = "badge", text = `Badge: {def.name}!` } :: Types.Notice)
		task.spawn(awardOnRoblox, player, def.badgeId)
	end
	send(player, profile)
end

function Badges.init()
	PlayerData.onLoaded(function(player: Player, profile: Profile)
		pending[player] = true
		send(player, profile)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		pending[player] = nil
	end)
end

-- Flips, streaks, resets and helper unlocks all change the profile, so one cheap pass every few
-- seconds catches every badge without hooking into each of those systems.
function Badges.start()
	while true do
		task.wait(3)
		for _, player in Players:GetPlayers() do
			if pending[player] then
				Badges.check(player)
			end
		end
	end
end

Badges.defs = Config.Badges

return Badges
