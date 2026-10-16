--!strict
-- Find The Pet: which pet follows each player, the free starter pet, and the "PetsShown" attribute every client
-- reads to draw followers (client/PetFollow). Pets themselves are specimens in the profile inventory; the server
-- decides everything here, the client only asks to equip or unequip an id it owns.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local GeodeGen = require(Shared.GeodeGen)
local Net = require(Shared.Net)
local PetRules = require(Shared.PetRules)
local Retention = require(Shared.Retention)
local Profiles = require(script.Parent.Profiles)

local PetService = {}

local lastAction: { [Player]: number } = {}
local lastRename: { [Player]: number } = {}
local lastRenameWarn: { [Player]: number } = {}
local renaming: { [Player]: boolean } = {}
local renamedHandler: ((Player) -> ())? = nil

-- Tests only: replaces the Roblox text filter (asked text, user id) -> filtered text; it may error.
local filter = function(text: string, userId: number): string
	local result = TextService:FilterStringAsync(text, userId, Enum.TextFilterContext.PublicChat)
	return result:GetNonChatStringForBroadcastAsync()
end
function PetService.setFilter(fn: (string, number) -> string)
	filter = fn
end

-- Called after a pet's nickname changed or a roaming pet was called to follow (the lobby display re-renders).
function PetService.onRenamed(fn: (Player) -> ())
	renamedHandler = fn
end

local function public(g: any): { [string]: any }
	return { Id = g.Id, Mineral = g.Mineral, Rarity = g.Rarity, Modifier = g.Modifier, Formation = g.Formation, Seed = g.Seed, Mass = g.Mass, Nickname = g.Nickname, Evolve = g.Evolve }
end

-- The public fields a follower needs (no match internals). A player in the pet tower (InTower) or a Pet Battle shows
-- none, so the follower is never mistaken for one of the fighting pets. In a hunt (server attribute MatchKey) only
-- the pet helper follows (owner pick 2026-10-15, Profiles.huntHelper: one pet, never a Robux pet), marked Helper.
local function shown(player: Player, data): string
	local out = {}
	if player:GetAttribute("InTower") == true or player:GetAttribute("InBattle") == true then
		return "[]"
	end
	if player:GetAttribute("MatchKey") ~= nil then
		local g = Profiles.huntHelper(data)
		if g then
			local v = public(g)
			v.Helper = true
			table.insert(out, v)
		end
		return HttpService:JSONEncode(out)
	end
	for _, id in data.EquippedPets do
		local _, g = Profiles.findGeode(data, id)
		if g then
			table.insert(out, public(g))
		end
	end
	return HttpService:JSONEncode(out)
end

-- Drops followers that are no longer owned (sold) and refreshes the attribute when it changed.
function PetService.refresh(player: Player)
	local data = Profiles.get(player)
	if not data then
		return
	end
	local dropped = false
	for i = #data.EquippedPets, 1, -1 do
		if not select(2, Profiles.findGeode(data, data.EquippedPets[i])) then
			table.remove(data.EquippedPets, i)
			dropped = true
		end
	end
	if dropped then
		-- a sold team pet's slot goes to the strongest pet left in the Pet Book (the team of 3 stays full)
		if PetRules.fillTeam(data.EquippedPets, data.InventoryGeodes, Config.Pets.Slots, if type(data.TowerXP) == "table" then data.TowerXP else nil) > 0 then
			Profiles.changed(player) -- sync the refilled team (the next refresh finds nothing dropped, so no loop)
		end
	end
	local json = shown(player, data)
	if player:GetAttribute("PetsShown") ~= json then
		player:SetAttribute("PetsShown", json)
	end
end

-- The free starter pet, once per player (a gift, not a hunt prize: no ledger, no stats, no wins). New players hatch it
-- from the starter egg near the lobby spawn (RetentionService "Starter"); skipping the tutorial hatches it too. Its
-- rarity is always Rare or better and never the zone's 1 in 1000 chase pet (Retention.Starter). Returns the pet when
-- it was hatched just now, nil when it was hatched before or there is no room in the Pet Book yet.
function PetService.ensureStarter(player: Player): { [string]: any }?
	local data = Profiles.get(player)
	if not data or data.StarterPet then
		return nil
	end
	if #data.InventoryGeodes >= Profiles.petCapacity(data) then
		return nil -- no room: the flag stays false, so the egg waits until there is room
	end
	local st = Retention.Starter
	local pet = GeodeGen.roll(Random.new(), st.Tier, HttpService:GenerateGUID(false), "starter", os.time(), true, 0, st.Weights)
	if not Profiles.grantSpecimen(player, "starter:" .. player.UserId, pet, "Gift") then
		return nil
	end
	data.StarterPet = true -- only now that the pet is really in the book
	-- the first pet always follows right away (owner pick 2026-10-14): first in the follow list, even when a pet
	-- already follows (an older save, a dev pet); the last one steps back if the list is full
	local at = table.find(data.EquippedPets, pet.Id)
	if at then
		table.remove(data.EquippedPets, at)
	end
	table.insert(data.EquippedPets, 1, pet.Id)
	while #data.EquippedPets > Config.Pets.Slots do
		table.remove(data.EquippedPets)
	end
	Profiles.changed(player)
	return pet
end

local function toast(player: Player, text: string, kind: string)
	Net.event("Toast"):FireClient(player, text, kind)
end

-- Free renaming (Pet Book detail): the client names a pet it owns and the wanted name; the server checks the shape
-- (PetRules.cleanName), runs Roblox text filtering for text other players see (FilterStringAsync +
-- GetNonChatStringForBroadcastAsync, in a pcall: a filter failure refuses the name) and saves it as the pet's
-- Nickname. An empty name clears it. One rename at a time and one per Config.Pets.RenameCooldown seconds per player.
local function rename(player: Player, id: any, raw: any)
	local data = Profiles.get(player)
	if not data or type(id) ~= "string" or not select(2, Profiles.findGeode(data, id)) then
		return
	end
	if renaming[player] then
		return
	end
	local t = os.clock()
	if t - (lastRename[player] or -math.huge) < Config.Pets.RenameCooldown then
		if t - (lastRenameWarn[player] or -math.huge) >= 1 then -- one toast a second, so spam can't flood toasts
			lastRenameWarn[player] = t
			toast(player, "Wait a moment before renaming again.", "warn")
		end
		return
	end
	local name, why = PetRules.cleanName(raw, Config.Pets.NameMax)
	if not name then
		toast(player, why or "That name can't be used.", "warn")
		return
	end
	lastRename[player] = t
	local final: string? = nil
	if name ~= "" then
		renaming[player] = true
		local ok, res = pcall(filter, name, player.UserId)
		renaming[player] = nil
		if not ok then
			toast(player, "Names can't be checked right now. Try again soon.", "warn")
			return
		end
		if not PetRules.filterAccepted(name, res) then
			toast(player, "Oops! That name can't be used. Try a different one!", "warn")
			return
		end
		final = res :: string
	end
	-- the filter yields: the player may have left, sold the pet or handed the profile over meanwhile
	if not player.Parent or not Profiles.isLoaded(player) or Profiles.isReleased(player) then
		return
	end
	local d2 = Profiles.get(player)
	if not d2 then
		return
	end
	local _, g = Profiles.findGeode(d2, id)
	if not g then
		return
	end
	g.Nickname = final
	Profiles.changed(player)
	toast(player, if final then "Your pet is now called " .. final .. "!" else "Name cleared.", "ok")
	if renamedHandler then
		renamedHandler(player)
	end
end

-- Pets called to follow leave the pen (they would show twice); they stay on display in a dome. The plot re-renders
-- through the same hook a rename uses (Gallery.render).
local function unroam(player: Player, data: any, ids: { string })
	if type(data.RoamPets) ~= "table" then
		return
	end
	local hit = false
	for _, id in ids do
		local r = table.find(data.RoamPets, id)
		if r then
			table.remove(data.RoamPets, r)
			hit = true
		end
	end
	if hit and renamedHandler then
		task.defer(renamedHandler, player)
	end
end

local function onAction(player: Player, action: any, id: any, extra: any)
	if action == "RenamePet" then
		if Profiles.isLoaded(player) and not Profiles.isReleased(player) then
			task.spawn(rename, player, id, extra)
		end
		return
	end
	if action ~= "EquipPet" and action ~= "UnequipPet" and action ~= "EquipBest" then
		return -- other collection actions belong to EconomyService
	end
	local t = os.clock()
	if t - (lastAction[player] or 0) < 0.3 then
		return
	end
	lastAction[player] = t
	if not Profiles.isLoaded(player) or Profiles.isReleased(player) then
		return -- teleport hand-off: this server no longer owns the profile
	end
	if player:GetAttribute("MatchKey") ~= nil then
		Net.event("Toast"):FireClient(player, "Change pets in the lobby.", "warn")
		return -- the hunt keeps the pet it started with (speed and luck are read from it)
	end
	local data = Profiles.get(player)
	if action == "EquipBest" then
		-- the server picks: the owned pets with the highest POWER fill the follower slots (PetRules.best)
		if not data then
			return
		end
		local best = PetRules.best(data.InventoryGeodes, Config.Pets.Slots, if type(data.TowerXP) == "table" then data.TowerXP else nil)
		if #best == 0 then
			return
		end
		local same = #best == #data.EquippedPets
		for i, bid in best do
			if data.EquippedPets[i] ~= bid then
				same = false
			end
		end
		if same then
			Net.event("Toast"):FireClient(player, "Your best pet is already following you.", "info")
			return
		end
		data.EquippedPets = best
		unroam(player, data, best)
		Profiles.changed(player)
		return
	end
	if not data or type(id) ~= "string" or not select(2, Profiles.findGeode(data, id)) then
		return
	end
	local list = data.EquippedPets
	local at = table.find(list, id)
	if action == "EquipPet" then
		if at then
			return
		end
		if #list >= Config.Pets.Slots then
			-- team full: the player picks the slot to swap (MY PETS asks); never a silent replace (carter 2026-10-15)
			local slot = PetRules.swapSlot(extra, #list)
			if not slot then
				Net.event("Toast"):FireClient(player, "Your team is full! Pick a team slot to swap.", "warn")
				return
			end
			list[slot] = id
		else
			table.insert(list, id)
		end
		unroam(player, data, { id })
	elseif at then
		table.remove(list, at)
	else
		return
	end
	Profiles.changed(player)
end

function PetService.start()
	Net.event("CollectionAction").OnServerEvent:Connect(onAction)
	Profiles.onLoaded(function(player)
		PetService.refresh(player) -- the starter pet now hatches from the starter egg (RetentionService)
	end)
	Profiles.onChanged(PetService.refresh)
	local function watch(player: Player)
		player:GetAttributeChangedSignal("MatchKey"):Connect(function()
			PetService.refresh(player)
		end)
		player:GetAttributeChangedSignal("InTower"):Connect(function()
			PetService.refresh(player)
		end)
		player:GetAttributeChangedSignal("InBattle"):Connect(function()
			PetService.refresh(player)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
		lastRename[player] = nil
		lastRenameWarn[player] = nil
		renaming[player] = nil
	end)
end

return PetService
