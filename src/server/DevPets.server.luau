--!strict
-- Dev pet spawner (owner tool). Only works in Studio or for the place owner (game.CreatorId); everyone else is
-- refused on the server, and the client button (DevPetsClient) only shows when the server marks the player IsDev.
-- Request: DevSpawnPet:InvokeServer(speciesId, rarity) -> (ok, message). The pet is granted like a bought pet
-- (follows you, not counted as a hunt find or for the boards).
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local GeodeGen = require(Shared.GeodeGen)
local Retention = require(Shared.Retention)
local Profiles = require(script.Parent.Profiles)

local COOLDOWN = 0.3
local last: { [Player]: number } = {}

local function isDev(player: Player): boolean
	return RunService:IsStudio() or (game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId)
end

-- Pet minting is Studio-only; live servers never create the remote. IsDev (owner fly mode, DevFly) still works live.
local function canMint(player: Player): boolean
	return RunService:IsStudio() and isDev(player)
end

local function tierOf(id: string): string?
	for tierId, tier in Config.Tiers :: any do
		if table.find(tier.Minerals, id) then
			return tierId
		end
	end
	return nil
end

local remote = Instance.new("RemoteFunction")
remote.Name = "DevSpawnPet"
if RunService:IsStudio() then
	remote.Parent = ReplicatedStorage
end

remote.OnServerInvoke = function(player: Player, species: any, rarity: any): (boolean, string)
	if not canMint(player) then
		return false, "not allowed"
	end
	local now = os.clock()
	if now - (last[player] or 0) < COOLDOWN then
		return false, "slow down"
	end
	last[player] = now
	if type(species) ~= "string" or (Config.Minerals :: any)[species] == nil then
		return false, "unknown pet"
	end
	-- owner rule: only pets with a real (Meshy) model can be spawned from the DEV menu
	local folder = ReplicatedStorage:FindFirstChild("PetModels")
	local model = folder and folder:FindFirstChild("Pet_" .. species)
	if not (model and model:GetAttribute("Mesh") == true) then
		return false, "no model yet"
	end
	if type(rarity) ~= "string" or not table.find(Config.Rarities, rarity) then
		return false, "unknown rarity"
	end
	if not Profiles.isLoaded(player) then
		return false, "profile not loaded"
	end
	local tierId = tierOf(species) or next(Config.Tiers :: any)
	local id = HttpService:GenerateGUID(false)
	local pet = GeodeGen.roll(Random.new(), tierId, id, "dev:" .. id, os.time(), true)
	pet.Mineral = species
	pet.Rarity = rarity
	pet.Value = GeodeGen.value(tierId, rarity, pet.Modifier, pet.Mass)
	if not Profiles.grantSpecimen(player, "dev:" .. id, pet, "Bought") then
		return false, "grant failed (pet storage full?)"
	end
	return true, rarity .. " " .. GeodeGen.displayName(pet)
end

-- Studio playtests only: ReplicatedStorage attribute DevAutoPet = a species id (e.g. "Ostrich") gives that pet
-- (Legendary, following) once per test session, so a new model can be looked at without opening the menu.
local function autoPet(player: Player)
	local species = ReplicatedStorage:GetAttribute("DevAutoPet")
	if not RunService:IsStudio() or type(species) ~= "string" or (Config.Minerals :: any)[species] == nil then
		return
	end
	local t0 = os.clock()
	while player.Parent and not Profiles.isLoaded(player) and os.clock() - t0 < 30 do
		task.wait(0.5)
	end
	if not player.Parent or not Profiles.isLoaded(player) then
		return
	end
	-- a fresh save hatches its starter egg first: the dev pet never steals "YOUR FIRST PET!" (walkthrough 10-14)
	while player.Parent and not Retention.freePetReady(Profiles.get(player)) do
		task.wait(1)
	end
	if not player.Parent then
		return
	end
	local tierId = tierOf(species) or next(Config.Tiers :: any)
	local id = HttpService:GenerateGUID(false)
	local pet = GeodeGen.roll(Random.new(), tierId, id, "devauto:" .. id, os.time(), true)
	pet.Mineral = species
	pet.Rarity = "Legendary"
	pet.Value = GeodeGen.value(tierId, "Legendary", pet.Modifier, pet.Mass)
	Profiles.grantSpecimen(player, "devauto:" .. id, pet, "Bought")
end

local function mark(player: Player)
	if isDev(player) then
		player:SetAttribute("IsDev", true) -- fly mode (live too)
		if RunService:IsStudio() then
			player:SetAttribute("DevPets", true) -- shows the client DEV tile
		end
		task.spawn(autoPet, player)
	end
end
Players.PlayerAdded:Connect(mark)
for _, p in Players:GetPlayers() do
	mark(p)
end
Players.PlayerRemoving:Connect(function(p)
	last[p] = nil
end)
