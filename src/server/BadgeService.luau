--!strict
-- Roblox badges for launch milestones (ids in shared/ProgressConfig.Badges; 0 = off until the owner creates the badge
-- and pastes its id there, see the REPLACE note). Awarded by the server from the saved profile only:
--   FirstHatch  - hatched your first pet (the free starter pet does not count)
--   FirstRare   - own (or once owned) a Rare, Epic or Legendary pet
--   AllHuntPets - found every released hunt pet species (35 at launch, 45 once the weekly pets are out; tower-only
--                 pets do not count)
--   Tower25     - reached floor 25 of the pet tower (profile TowerBest)
--   Forest      - unlocked the Forest zone
--   SecretEgg   - found the hidden egg in the lobby park: a part with attribute SecretEgg = true holding a
--                 ProximityPrompt (built by the park). Triggered marks SecretEggFound once, with a toast. If the
--                 part is missing nothing happens (the handler only reacts to prompts it finds on such a part).
-- A badge is remembered in the profile (`Badges`) once Roblox confirms it, so it is not asked for again. A badge
-- that is still off (id 0) is not remembered, so players who already qualify get it once the id is set.
-- Every Roblox call is wrapped in pcall; a failure is retried on a later profile change (at most once a minute per
-- badge and player).

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RobloxBadges = game:GetService("BadgeService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local ProgressConfig = require(Shared.ProgressConfig)
local Profiles = require(script.Parent.Profiles)
local Net = require(Shared.Net)

local BadgeService = {}

local RETRY = 60
local busy: { [Player]: { [string]: boolean } } = {}
local lastTry: { [Player]: { [string]: number } } = {}

-- Which milestones this profile has reached (pure reads of the saved data, ProgressConfig.badgeProgress).
function BadgeService.earned(data): { [string]: boolean }
	local out = {}
	for key, p in ProgressConfig.badgeProgress(data) do
		out[key] = p.Done
	end
	return out
end

local function award(player: Player, key: string, id: number)
	local mine = busy[player]
	local tries = lastTry[player]
	if not mine or not tries or mine[key] or os.clock() - (tries[key] or -math.huge) < RETRY then
		return
	end
	mine[key] = true
	tries[key] = os.clock()
	task.spawn(function()
		local ok, res = pcall(function()
			return RobloxBadges:AwardBadge(player.UserId, id)
		end)
		local done = ok and res == true
		if not done then
			-- already owned (awarded before the profile remembered it) also counts as done
			local hasOk, has = pcall(function()
				return RobloxBadges:UserHasBadgeAsync(player.UserId, id)
			end)
			done = hasOk and has == true
			if not done then
				warn("[BadgeService] badge " .. key .. " not awarded yet:", res)
			end
		end
		if busy[player] then
			busy[player][key] = nil
		end
		local data = Profiles.get(player)
		if done and data and player.Parent and not Profiles.isReleased(player) then
			data.Badges[key] = true
			Profiles.changed(player, true)
		end
	end)
end

function BadgeService.check(player: Player)
	local data = Profiles.get(player)
	if not data or type(data.Badges) ~= "table" then
		return
	end
	local earned = BadgeService.earned(data)
	for _, key in ProgressConfig.BadgeOrder do
		local b = ProgressConfig.Badges[key]
		if earned[key] and not data.Badges[key] and b and type(b.Id) == "number" and b.Id > 0 then
			award(player, key, b.Id)
		end
	end
end

-- The prompt's part (or a model above it) carries SecretEgg = true. Triggered alone is not proof of range; start() re-checks the distance.
local function isSecretEgg(prompt: ProximityPrompt): boolean
	local node: Instance? = prompt.Parent
	for _ = 1, 3 do
		if not node then
			return false
		end
		if node:GetAttribute("SecretEgg") == true then
			return true
		end
		node = node.Parent
	end
	return false
end

function BadgeService.secretEgg(player: Player)
	local data = Profiles.get(player)
	if not data or Profiles.isReleased(player) then
		return
	end
	if data.SecretEggFound == true then
		Net.event("Toast"):FireClient(player, "You already found the secret egg!", "info")
		return
	end
	data.SecretEggFound = true
	Profiles.changed(player, true) -- onChanged runs check(): the badge is awarded once its id is set
	-- a big moment: the client shows it as a big banner with confetti (Main.client, Fx "SecretEgg"), not a small toast
	Net.event("Fx"):FireClient(player, "SecretEgg", {})
end

function BadgeService.start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		if prompt and isSecretEgg(prompt) then
			-- Triggered is not proof of range (an exploit client can fire it): re-check the avatar distance.
			local parent = prompt.Parent
			local at = if parent and parent:IsA("BasePart") then parent.Position else nil
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if not at or not root or not root:IsA("BasePart") or (root.Position - at).Magnitude > prompt.MaxActivationDistance + 6 then
				return
			end
			BadgeService.secretEgg(player)
		end
	end)
	Profiles.onLoaded(function(player)
		busy[player] = {}
		lastTry[player] = {}
		BadgeService.check(player)
	end)
	Profiles.onChanged(BadgeService.check)
	Players.PlayerRemoving:Connect(function(p)
		busy[p] = nil
		lastTry[p] = nil
	end)
end

return BadgeService
