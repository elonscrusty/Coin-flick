-- Server audit (run by tests/test_m10_server.luau): Find The Pet owner picks through the real remotes.
-- Pet renaming (filter, length, cooldown, filter failure, follower tag), the tutorial SKIP still granting the free
-- starter pet, and the Pet Book capacity hook (Config.Inventory.Max + ExtraPetSlots).
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

local s = C.boot({
	profile = function(data)
		data.TutorialStep = 0
		data.Onboard.Skipped = false
	end,
})
local me, Profiles, Config = s.me, s.Profiles, s.Config
local PetService = C.server("PetService")
local data = Profiles.get(me)
local function step(dt: number?)
	preview.advance(dt or 0.2)
end
local function rename(id: string, name: any)
	preview.fireServerAs(me, "CollectionAction", "RenamePet", id, name)
	step()
end

case("a new player's starter egg waits; tapping it hatches a Rare or better pet that follows", function()
	eq(data.StarterPet, false, "the egg waits near the spawn")
	eq(#data.InventoryGeodes, 0)
	eq(Profiles.publicView(me, false).StarterEgg, true, "the client is told to show the egg")
	preview.fireServerAs(me, "RetentionAction", "Starter")
	step()
	eq(data.StarterPet, true)
	eq(#data.InventoryGeodes, 1)
	local pet = data.InventoryGeodes[1]
	assert(pet.Rarity == "Rare" or pet.Rarity == "Epic", "Rare or better, never the Legendary chase pet: " .. tostring(pet.Rarity))
	eq(data.EquippedPets[1], pet.Id, "follows right away")
	eq(data.Stats.SoloFinds, 0, "a gift is not a find (zones unlock on real finds)")
	eq(data.Onboard.Geode, false, "the practice find is still to come")
	step(0.5)
	preview.fireServerAs(me, "RetentionAction", "Starter")
	step()
	eq(#data.InventoryGeodes, 1, "never a second starter")
end)

case("rename: a clean name is filtered, saved as Nickname and shown on the follower tag", function()
	local pet = data.InventoryGeodes[1]
	rename(pet.Id, "  Sir   Chomps ")
	eq(pet.Nickname, "Sir Chomps", "trimmed and saved")
	local shown = me:GetAttribute("PetsShown")
	assert(type(shown) == "string" and string.find(shown, "Sir Chomps", 1, true), "follower attribute carries the nickname")
end)

case("rename: rate limited to one per cooldown", function()
	local pet = data.InventoryGeodes[1]
	rename(pet.Id, "Speedy")
	eq(pet.Nickname, "Sir Chomps", "second rename inside the cooldown is refused")
	step(Config.Pets.RenameCooldown + 0.1)
	rename(pet.Id, "Speedy")
	eq(pet.Nickname, "Speedy")
end)

case("rename: too long, odd characters and filtered words are refused; empty clears", function()
	local pet = data.InventoryGeodes[1]
	step(Config.Pets.RenameCooldown + 0.1)
	rename(pet.Id, string.rep("a", Config.Pets.NameMax + 1))
	eq(pet.Nickname, "Speedy", "over the length limit")
	step(Config.Pets.RenameCooldown + 0.1)
	rename(pet.Id, "<b>Rex</b>")
	eq(pet.Nickname, "Speedy", "rich text refused")
	step(Config.Pets.RenameCooldown + 0.1)
	rename(pet.Id, "Badword Rex") -- the mock filter hashes "badword"
	eq(pet.Nickname, "Speedy", "a name the filter changed is refused")
	step(Config.Pets.RenameCooldown + 0.1)
	rename(pet.Id, { "not", "text" })
	eq(pet.Nickname, "Speedy", "not a string")
	step(Config.Pets.RenameCooldown + 0.1)
	rename(pet.Id, "   ")
	eq(pet.Nickname, nil, "an empty name clears the nickname")
end)

case("rename: a filter failure refuses the name; a pet you do not own is ignored", function()
	local pet = data.InventoryGeodes[1]
	PetService.setFilter(function()
		error("text filter unavailable (test)")
	end)
	step(Config.Pets.RenameCooldown + 0.1)
	rename(pet.Id, "Rex")
	eq(pet.Nickname, nil, "filter error: not saved")
	PetService.setFilter(function(text)
		return text
	end)
	step(Config.Pets.RenameCooldown + 0.1)
	rename("not-my-pet", "Rex")
	step(Config.Pets.RenameCooldown + 0.1)
	rename(pet.Id, "Rex")
	eq(pet.Nickname, "Rex")
	local view = Profiles.publicView(me, true)
	eq(view.Inventory[1].Nickname, "Rex", "the Pet Book view carries the nickname")
end)

case("tutorial SKIP ends the tutorial and still grants the starter pet", function()
	data.StarterPet = false
	local old = C.fakeSpecimens(1)[1]
	data.InventoryGeodes = { old }
	data.EquippedPets = { old.Id } -- a pet already follows (older save, dev pet)
	data.RecentAwardIds = {} -- the starter award key from the first case would block the grant (it is idempotent)
	data.TutorialStep = 0
	data.Onboard.Skipped = false
	step(1.2)
	preview.fireServerAs(me, "TutorialAction", "Skip")
	step()
	eq(data.Onboard.Skipped, true)
	eq(data.TutorialStep, 1)
	eq(data.StarterPet, true)
	eq(#data.InventoryGeodes, 2, "starter granted")
	local starter = data.InventoryGeodes[2]
	assert(starter.Rarity ~= "Common", "the starter is Rare or better")
	eq(data.EquippedPets[1], starter.Id, "the first hatched pet always follows, even over a pet already following")
	assert(#data.EquippedPets <= Config.Pets.Slots, "follow list never over the slots")
	step(1.2)
	preview.fireServerAs(me, "TutorialAction", "Skip")
	step()
	eq(#data.InventoryGeodes, 2, "never a second starter")
end)

case("Pet Book holds 100 pets; ExtraPetSlots raises it; bad values count as 0", function()
	eq(Config.Inventory.Max, 100)
	eq(Profiles.petCapacity(data), 100)
	data.ExtraPetSlots = 50
	eq(Profiles.petCapacity(data), 150)
	eq(Profiles.publicView(me, false).InventoryMax, 150)
	data.ExtraPetSlots = -3
	eq(Profiles.petCapacity(data), 100)
	local r = Profiles.reconcile({ ExtraPetSlots = "lots" })
	eq(r.ExtraPetSlots, 0, "reconcile repairs a broken field")
	local r2 = Profiles.reconcile({})
	eq(r2.ExtraPetSlots, 0, "old saves get the field")
	data.ExtraPetSlots = 0
end)

case("Equip Best: the server equips the owned pet with the highest POWER, lobby only", function()
	local specs = C.fakeSpecimens(6)
	for _, g in specs do
		table.insert(data.InventoryGeodes, g)
	end
	local PetRules = C.shared("PetRules")
	local PetStats = C.shared("PetStats")
	local want = PetRules.best(data.InventoryGeodes, Config.Pets.Slots, data.TowerXP)[1]
	local top = 0
	for _, g in data.InventoryGeodes do
		top = math.max(top, PetStats.powerOfPet(g, data.TowerXP and data.TowerXP[g.Id]))
	end
	local _, wg = Profiles.findGeode(data, want)
	eq(PetStats.powerOfPet(wg, data.TowerXP and data.TowerXP[want]), top, "best has the top POWER")
	data.EquippedPets = { data.InventoryGeodes[1].Id }
	local before = data.EquippedPets[1]
	me:SetAttribute("MatchKey", "test-hunt")
	step(0.5)
	preview.fireServerAs(me, "CollectionAction", "EquipBest")
	step()
	eq(data.EquippedPets[1], before, "refused during a hunt")
	assert(before ~= want, "the starter is not the best pet here")
	me:SetAttribute("MatchKey", nil)
	step(0.5)
	preview.fireServerAs(me, "CollectionAction", "EquipBest")
	step()
	eq(data.EquippedPets[1], want)
	eq(#data.EquippedPets, Config.Pets.Slots)
end)

case("a full team never swaps silently: EquipPet needs the slot the player picked", function()
	local spare
	for _, g in data.InventoryGeodes do
		if not table.find(data.EquippedPets, g.Id) then
			spare = g
		end
	end
	assert(spare, "a pet off the team")
	local before = table.clone(data.EquippedPets)
	eq(#before, Config.Pets.Slots, "team is full")
	step(0.5)
	preview.fireServerAs(me, "CollectionAction", "EquipPet", spare.Id)
	step()
	for i, id in before do
		eq(data.EquippedPets[i], id, "no slot picked: team unchanged")
	end
	step(0.5)
	preview.fireServerAs(me, "CollectionAction", "EquipPet", spare.Id, 9)
	step()
	eq(data.EquippedPets[1], before[1], "a bad slot is refused")
	step(0.5)
	preview.fireServerAs(me, "CollectionAction", "EquipPet", spare.Id, 2)
	step()
	eq(data.EquippedPets[2], spare.Id, "the picked slot swaps")
	eq(data.EquippedPets[1], before[1], "the others stay")
	eq(data.EquippedPets[3], before[3], "the others stay")
	step(0.5)
	preview.fireServerAs(me, "CollectionAction", "UnequipPet", spare.Id)
	step()
	eq(#data.EquippedPets, Config.Pets.Slots - 1, "unequip frees a slot")
	step(0.5)
	preview.fireServerAs(me, "CollectionAction", "EquipPet", before[2])
	step()
	eq(data.EquippedPets[#data.EquippedPets], before[2], "a free slot needs no pick")
end)

print("PETS DONE")
