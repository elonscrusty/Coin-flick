--!strict
-- Pet index rewards and the lobby name tag data (owner picks). Full zone pages pay a lasting bonus (shared/EggPerks).
--   * First find: Profiles.grantSpecimen pays Config.PetIndex.FirstFindCoins the first time a species is hatched
--     (idempotent: the discovery row is written in the same save). This module only tells the player, after the
--     hatch reveal so the notice is not swept away by it.
--   * Pet Master: every species found (PetFlair.allFound). The title is derived from the saved discovery index, so
--     it can never be lost or double-granted; the badge is BadgeService "AllHuntPets" (id in ProgressConfig.Badges).
--   * Name tag: the server copies the title and the best pet tower floor (profile TowerBest) to Player attributes
--     "Title" and "TowerBest"; client NameTag draws them over the head in the lobby.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local PetFlair = require(Shared.PetFlair)
local PetModel = require(Shared.PetModel)
local EggPerks = require(Shared.EggPerks)
local Profiles = require(script.Parent.Profiles)

local PetIndex = {}

local NOTICE_DELAY = PetFlair.longestReveal() + 1.5 -- after even a slow-motion Rare+ reveal

function PetIndex.refresh(player: Player)
	local data = Profiles.get(player)
	if not data or not player.Parent then
		return
	end
	local title = PetFlair.title(data.DiscoveryIndex, data.PetMaster == true)
	if player:GetAttribute("Title") ~= title then
		player:SetAttribute("Title", title)
	end
	local best = tonumber(data.TowerBest) or 0
	best = if best == best then math.max(0, math.floor(best)) else 0
	if player:GetAttribute("TowerBest") ~= best then
		player:SetAttribute("TowerBest", best)
	end
end

local function onSpeciesFound(player: Player, species: string, coins: number)
	local data = Profiles.get(player)
	local master = data ~= nil and PetFlair.allFound(data.DiscoveryIndex)
	local found = if data then PetFlair.foundCount(data.DiscoveryIndex) else 0
	local page = if data then EggPerks.pageJustDone(data.DiscoveryIndex, species) else nil
	task.delay(NOTICE_DELAY, function()
		if not player.Parent then
			return
		end
		local toast = Net.event("Toast")
		toast:FireClient(player, "New in your Pet Book: " .. PetModel.name(species) .. "! +" .. coins .. " coins (" .. found .. "/" .. #PetFlair.species() .. ")", "ok")
		if page then
			local pct = math.floor(EggPerks.Pages.CoinsPerPage * 100 + 0.5)
			toast:FireClient(player, page.Name:upper() .. " PAGE COMPLETE! +" .. pct .. "% coins and +" .. pct .. "% pet XP forever!", "rare")
		end
		if master then
			toast:FireClient(player, "Every pet found! New title: " .. Config.PetIndex.MasterTitle, "ok")
		end
	end)
end

local started = false
function PetIndex.start()
	if started then
		return
	end
	started = true
	Profiles.onSpeciesFound(onSpeciesFound)
	Profiles.onLoaded(function(player)
		PetIndex.refresh(player)
	end)
	Profiles.onChanged(PetIndex.refresh)
end

return PetIndex
