-- Server audit (run by tests/test_m10_server.luau): old profiles missing new fields and profiles written by a
-- newer build (unknown ids) load safely. The in-memory DataStore is seeded with such a record BEFORE the
-- server starts, so the real Profiles load path (UpdateAsync + reconcile) runs on it; Profiles.reconcile is
-- also fed a few broken shapes directly.
local C = lib("ctr")

local function case(name: string, fn)
	local ok, err = pcall(fn)
	if ok then
		print("CASE " .. name .. " PASS")
	else
		print("[FAIL] CASE " .. name .. ": " .. tostring(err))
	end
end
local function eq(a, b, msg)
	if a ~= b then
		error((msg or "mismatch") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

local Config = C.shared("Config")
local me = game:GetService("Players").LocalPlayer
-- An early V2 save: no Materials, no Onboard, no DiscoveryRarity, partial Settings and Stats, plus ids
-- from a newer build: a tool, a machine, a tier, a storage and gallery level beyond this build's tables.
local OLD = {
	Schema = 1,
	Cash = 1234,
	RubbleByTier = { Gravel = 7, Volcano = 3 },
	EquipmentOwned = { Hammer = true, SteelHammer = true, PlasmaDrill = true },
	EquippedHandheld = "PlasmaDrill",
	InstalledMachine = "QuantumCrusher",
	CapacityTier = 99,
	UnlockedTiers = { Gravel = true, Volcano = true },
	InventoryGeodes = {
		{ Id = "g1", Mineral = "Amethyst", Rarity = "Rare", Formation = "Cluster", Modifier = "None", Mass = 2.1, Seed = 11, Value = 120, Tier = "Gravel", Found = 1700000000 },
		-- written by a newer build: mineral, rarity, formation, modifier and tier this build does not know
		{ Id = "g2", Mineral = "Starstone", Rarity = "Mythic", Formation = "Spiral", Modifier = "Prismatic", Mass = 3.4, Seed = 22, Value = 999, Tier = "Volcano", Found = 1800000000 },
	},
	DisplayAssignments = { "g2" },
	DisplayCapacity = 42,
	DiscoveryIndex = { Amethyst = 1 },
	TutorialStep = 1,
	Settings = { Music = 0.3 },
	Stats = { SoloFinds = 2, CashEarned = 50 },
	RecentAwardIds = { "k1", "k2" },
	PendingAwards = {},
	Cosmetics = { Owned = { NeonTrail = true }, Equipped = { Trail = "NeonTrail" } },
}

local DataStoreService = game:GetService("DataStoreService")
local store = DataStoreService:GetDataStore(Config.Save.StoreName)
store:SetAsync("u_" .. me.UserId, { Data = OLD })

C.makeCharacter(me, CFrame.new(0, 0, 0))
C.try("start server", preview.startServer)
local Profiles = C.server("Profiles")
for _ = 1, 80 do
	if Profiles.isLoaded(me) then
		break
	end
	preview.advance(0.1)
end

case("an old save with a newer build's ids loads", function()
	assert(Profiles.isLoaded(me), "profile loaded")
	local d = Profiles.get(me)
	eq(d.Cash, 1234, "cash kept")
	eq(#d.InventoryGeodes, 2, "specimens kept, the unknown mineral too (the starter pet now waits in the starter egg)")
	eq(d.StarterPet, false, "the starter egg is waiting near the spawn")
	eq(d.DisplayAssignments[1], "g2", "display kept")
	eq(d.EquipmentOwned.PlasmaDrill, true, "future ownership kept")
	eq(d.EquippedHandheld, "Hammer", "unknown tool not held")
	eq(d.InstalledMachine, nil, "unknown machine not installed")
	eq(d.UnlockedTiers.Volcano, true, "future tier unlock kept")
	eq(d.CapacityTier, 99, "stored level never lowered")
	eq(d.DisplayCapacity, 42)
end)

case("missing new fields are filled (Materials, Onboard, Settings, Stats)", function()
	local d = Profiles.get(me)
	assert(type(d.Materials) == "table" and type(d.Materials.Found) == "table", "Materials")
	eq(d.Settings.Music, 0.3, "existing setting kept")
	eq(d.Settings.Sfx, 0.8, "missing setting defaulted")
	eq(d.Settings.Hints, true)
	eq(d.Stats.SoloFinds, 2)
	eq(d.Stats.MultiplayerWins, 0)
	eq(type(d.Onboard), "table")
	eq(d.Onboard.Sold, true, "inferred: cash was earned before")
	assert(type(d.DiscoveryRarity.Ostrich) == "table", "rarity index rebuilt from owned specimens (geode Amethyst -> pet Ostrich)")
	eq(d.DiscoveryRarity.Amethyst, nil, "old mineral rows move to pets")
	for _, g in d.InventoryGeodes do
		assert(Config.Minerals[g.Mineral], "every old geode became a known pet: " .. tostring(g.Mineral))
	end
	eq(#d.EquippedPets, 0, "no follower until the starter egg is hatched")
	eq(type(d.EquippedPets), "table")
end)

case("levels beyond this build use the biggest known size, not level 1", function()
	local d = Profiles.get(me)
	eq(Profiles.capacity(d), Config.Capacity[#Config.Capacity].Size)
	eq(Profiles.displaySlots(d), Config.Display[#Config.Display].Slots)
end)

case("unknown-tier rubble takes space but is not priced", function()
	local d = Profiles.get(me)
	eq(Profiles.rubbleTotal(d), 10)
	eq(Profiles.rubbleValue(d), 7 * Config.Tiers.Gravel.CashPerRubble)
end)

case("public view and party view build for this profile", function()
	local view = Profiles.publicView(me)
	assert(view and view.Capacity > 0, "public view")
	local PartyService = C.server("PartyService")
	preview.fireServerAs(me, "PartyAction", "Create")
	preview.advance(0.3)
	local party = PartyService.of(me.UserId)
	assert(party, "party")
	local v = PartyService.view(party)
	eq(#v.Members, 1)
end)

case("broken shapes are repaired without losing money or specimens", function()
	local bad = {
		Cash = "250",
		Settings = "loud",
		Stats = { CashEarned = "x", SoloFinds = 0 / 0 },
		TutorialStep = "done",
		RubbleByTier = { Gravel = -3, Quarry = "many", Cavern = 2.7 },
		InventoryGeodes = { { Id = "a", Value = 5 }, 17, "junk" },
		DisplayAssignments = { "a", 4 },
		Materials = { Found = { NotAThing = true }, Counts = "?" },
		EquipmentOwned = { Hammer = true },
		EquippedHandheld = "SteelHammer", -- known but not owned
		UnlockedTiers = {},
		Onboard = 5,
	}
	local d = Profiles.reconcile(bad)
	eq(d.Cash, 250, "numeric string cash kept as a number")
	eq(type(d.Settings), "table")
	eq(d.Settings.Music, 0.6)
	eq(d.Stats.CashEarned, 0)
	eq(d.Stats.SoloFinds, 0)
	eq(d.TutorialStep, 0)
	eq(d.RubbleByTier.Gravel, nil, "negative count dropped")
	eq(d.RubbleByTier.Quarry, nil, "non-number dropped")
	eq(d.RubbleByTier.Cavern, 2, "whole counts")
	eq(#d.InventoryGeodes, 1, "only real specimens")
	eq(type(d.InventoryGeodes[1].Mass), "number", "a specimen without a mass gets one (the gallery sizes from it)")
	eq(#d.DisplayAssignments, 1)
	eq(d.EquippedHandheld, "Hammer", "only an owned tool is held")
	eq(d.UnlockedTiers.Gravel, true)
	eq(type(d.Onboard), "table")
	assert(Profiles.capacity(d) > 0 and Profiles.displaySlots(d) > 0)
end)

case("a released profile (teleport hand-off) refuses a pet grant; it lands again once re-acquired", function()
	local pet = { Id = "rel1", Mineral = "Amethyst", Rarity = "Common", Formation = "Cluster", Modifier = "None", Mass = 1, Seed = 1, Value = 10, Tier = "Gravel", Found = 1700000000 }
	local ok = Profiles.releaseForTeleport(me)
	eq(ok, true, "released")
	eq(Profiles.grantSpecimen(me, "rel:1", pet, "Solo"), false, "no write to a released profile")
	eq(Profiles.findGeode(Profiles.get(me), "rel1"), nil, "nothing added in memory")
	eq(Profiles.reacquire(me), true, "lock taken back")
	eq(Profiles.grantSpecimen(me, "rel:1", pet, "Solo"), true, "granted once the profile is ours again")
end)

case("hatching a stronger pet onto a full team swaps out the weakest; a weaker hatch stays off (193 off / 156 on bug)", function()
	local PetStats = C.shared("PetStats")
	local d = Profiles.get(me)
	d.EquippedPets = {}
	local function mk(id: string, rarity: string, seed: number)
		return { Id = id, Mineral = "Raptor", Rarity = rarity, Formation = "Cluster", Modifier = "None", Mass = 1, Seed = seed, Value = 10, Tier = "Gravel", Found = 1700000000 + seed }
	end
	for i, r in { "Common", "Common", "Uncommon" } do
		assert(Profiles.grantSpecimen(me, "team:" .. i, mk("t" .. i, r, 100 + i), "Solo"), "granted")
	end
	eq(#d.EquippedPets, Config.Pets.Slots, "first pets fill the team")
	local strong = mk("tbig", "Legendary", 200)
	assert(Profiles.grantSpecimen(me, "team:big", strong, "Solo"))
	assert(table.find(d.EquippedPets, "tbig"), "the stronger pet joined the team")
	eq(#d.EquippedPets, Config.Pets.Slots)
	local function p(id)
		local _, g = Profiles.findGeode(d, id)
		return PetStats.powerOfPet(g)
	end
	local minTeam = math.huge
	for _, id in d.EquippedPets do
		minTeam = math.min(minTeam, p(id))
	end
	for _, g in d.InventoryGeodes do
		if string.sub(g.Id, 1, 1) == "t" and not table.find(d.EquippedPets, g.Id) then
			assert(PetStats.powerOfPet(g) <= minTeam, "no pet off the team is stronger than one on it: " .. g.Id)
		end
	end
	local before = table.concat(d.EquippedPets, ",")
	assert(Profiles.grantSpecimen(me, "team:bonus", mk("tbonus", "Legendary", 300), "Bonus"))
	eq(table.concat(d.EquippedPets, ","), before, "a Bonus pet never auto-joins")
end)

print("PROFILES DONE")
