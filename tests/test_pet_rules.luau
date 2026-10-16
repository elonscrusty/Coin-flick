-- Owner picks (pet storage, renaming, friend bonus, pet type): the pure rules in shared/PetRules.
return function(t)
	local test, shared = t.test, t.shared
	local Config = shared("Config")
	local PetRules = shared("PetRules")

	test("pets: storage holds 100, extra slots add on, bad extras count as 0", function()
		assert(Config.Inventory.Max == 100)
		assert(PetRules.capacity(100, nil) == 100)
		assert(PetRules.capacity(100, 0) == 100)
		assert(PetRules.capacity(100, 25) == 125)
		assert(PetRules.capacity(100, 2.9) == 102)
		assert(PetRules.capacity(100, -5) == 100)
		assert(PetRules.capacity(100, "50") == 100)
		assert(PetRules.capacity(100, 0 / 0) == 100)
	end)

	test("pets: nickname shape check before the filter", function()
		local max = Config.Pets.NameMax
		assert(max == 20)
		assert(PetRules.cleanName("  Sir   Chomps ", max) == "Sir Chomps")
		assert(PetRules.cleanName("   ", max) == "", "blank clears")
		assert(PetRules.cleanName(string.rep("x", 20), max) == string.rep("x", 20))
		assert(PetRules.cleanName(string.rep("x", 21), max) == nil)
		assert(PetRules.cleanName("<b>Rex</b>", max) == nil, "no rich text")
		assert(PetRules.cleanName("Rex\nRex", max) == "Rex Rex", "line breaks fold to a space")
		assert(PetRules.cleanName(42, max) == nil)
		assert(PetRules.cleanName("Mr. Fluff-Paws!", max) == "Mr. Fluff-Paws!")
		assert(PetRules.cleanName("\255\254", max) == nil, "invalid UTF-8")
		assert(PetRules.filterAccepted("Rex", "Rex"))
		assert(not PetRules.filterAccepted("Rex Bad", "Rex ###"))
		assert(not PetRules.filterAccepted("Rex", nil))
	end)

	test("pets: label prefers the nickname", function()
		local g = { Mineral = "Raptor", Modifier = "Natural" }
		assert(PetRules.label(g) == Config.Minerals.Raptor.Name)
		g.Nickname = "Chompy"
		assert(PetRules.label(g) == "Chompy")
		g.Nickname = ""
		assert(PetRules.label(g) == Config.Minerals.Raptor.Name)
	end)

	test("pets: friend bonus +10% per friend, at most 3", function()
		assert(PetRules.friendLuck(0, 0.1, 3) == 0)
		assert(PetRules.friendLuck(1, 0.1, 3) == 0.1)
		assert(PetRules.friendLuck(2, 0.1, 3) == 0.2)
		assert(PetRules.friendLuck(3, 0.1, 3) == 0.3)
		assert(PetRules.friendLuck(11, 0.1, 3) == 0.3)
		assert(PetRules.friendLuck(-2, 0.1, 3) == 0)
	end)

	test("pets: every species has a type with a colour", function()
		for id, sp in Config.Minerals do
			assert(Config.Pets.KindColors[sp.BoostKind], id .. " has a known BoostKind")
			assert(PetRules.kindOf({ Mineral = id }) == sp.BoostKind)
		end
		assert(PetRules.kindOf({ Mineral = "FutureThing" }) == "Coins")
	end)

	test("pets: level, sort by rarity / level / type, equip best", function()
		assert(PetRules.level({}) == 1)
		assert(PetRules.level({ TowerXP = 40 + 65 }) == 3, "tower curve: 40 then 65 xp")
		assert(PetRules.level({ TowerXP = 40 + 64 }) == 2)
		assert(PetRules.level({ TowerXP = -4 }) == 1)
		local a = { Id = "a", Mineral = "Raptor", Rarity = "Common", Found = 3, Value = 10 } -- Speed
		local b = { Id = "b", Mineral = "Ostrich", Rarity = "Epic", Found = 2, Value = 50 } -- Coins
		local c = { Id = "c", Mineral = "Griffin", Rarity = "Rare", Found = 1, Value = 30, TowerXP = 500 } -- Luck
		local list = { a, b, c }
		PetRules.sort(list, "Rarity")
		assert(list[1] == b and list[2] == c and list[3] == a)
		PetRules.sort(list, "Level")
		assert(list[1] == c)
		PetRules.sort(list, "Type")
		assert(list[1] == b and list[2] == a and list[3] == c, "Coins, Speed, Luck")
		PetRules.sort(list, "Newest")
		assert(list[1] == a)
		local best = PetRules.best({ a, b, c }, 1)
		assert(#best == 1 and best[1] == "b", "Epic Ostrich has the highest boost")
		assert(#PetRules.best({}, 1) == 0)
		assert(#PetRules.best({ a, b, c }, 2) == 2)
	end)

	test("Equip Best picks the biggest POWER (carter: bigger = better), xp from the save's TowerXP book", function()
		local PetStats = shared("PetStats")
		-- a Common with a big coin bonus loses to a stronger Legendary; a trained Rare beats an untrained one
		local weak = { Id = "w", Mineral = "Ostrich", Rarity = "Common", Seed = 11 }
		local strong = { Id = "s", Mineral = "Raptor", Rarity = "Legendary", Seed = 12, Modifier = "Golden" }
		assert(PetStats.powerOfPet(strong) > PetStats.powerOfPet(weak))
		assert(PetRules.best({ weak, strong }, 1)[1] == "s")
		local r1 = { Id = "r1", Mineral = "Raptor", Rarity = "Rare", Seed = 5 }
		local r2 = { Id = "r2", Mineral = "Raptor", Rarity = "Rare", Seed = 5 }
		assert(PetRules.best({ r1, r2 }, 1, { r2 = 2000 })[1] == "r2", "the trained copy (xp book) is stronger")
		assert(PetRules.best({ r1, { Id = "r3", Mineral = "Raptor", Rarity = "Rare", Seed = 5, TowerXP = 2000 } }, 1)[1] == "r3", "own TowerXP counts")
		local view = shared("PetStatView")
		assert(view.power(strong) == PetStats.powerOfPet(strong), "Pet Book shows the number Equip Best uses")
	end)

	test("pets: a new pet auto-follows only into an empty slot, never replacing a follower", function()
		local eq = { "legend" }
		assert(PetRules.autoFollow(eq, "common", 1) == false, "slot full: keep the Legendary")
		assert(#eq == 1 and eq[1] == "legend")
		local empty = {}
		assert(PetRules.autoFollow(empty, "new", 1) == true and empty[1] == "new")
		assert(PetRules.autoFollow(empty, "new", 2) == false, "no duplicate")
		local two = { "a" }
		assert(PetRules.autoFollow(two, "b", 2) == true and #two == 2)
	end)

	test("team: a stronger hatch replaces the weakest team pet, a weaker one never does", function()
		local PetStats = shared("PetStats")
		local pets = {
			a = { Id = "a", Mineral = "Raptor", Rarity = "Common", Seed = 1 },
			b = { Id = "b", Mineral = "Raptor", Rarity = "Common", Seed = 2 },
			c = { Id = "c", Mineral = "Raptor", Rarity = "Uncommon", Seed = 3 },
			big = { Id = "big", Mineral = "Raptor", Rarity = "Legendary", Seed = 4 },
			tiny = { Id = "tiny", Mineral = "Raptor", Rarity = "Common", Seed = 5 },
		}
		local function power(id: string): number
			return PetStats.powerOfPet(pets[id])
		end
		local team = {}
		for _, id in { "a", "b", "c" } do
			assert(PetRules.autoFollow(team, id, 3, power))
		end
		local weakest, wp = nil, math.huge
		for i, id in team do
			if power(id) < wp then
				weakest, wp = i, power(id)
			end
		end
		assert(power("big") > wp)
		assert(PetRules.autoFollow(team, "big", 3, power) == true, "the stronger pet joins")
		assert(team[weakest] == "big" and #team == 3, "it takes the weakest slot")
		-- the team is now the best 3 of the 4 owned (the 193-off / 156-on bug)
		local best = PetRules.best({ pets.a, pets.b, pets.c, pets.big }, 3)
		table.sort(best)
		local now = table.clone(team)
		table.sort(now)
		assert(table.concat(best, ",") == table.concat(now, ","), "auto team = Equip Best")
		local before = table.concat(team, ",")
		if power("tiny") <= math.min(power(team[1]), power(team[2]), power(team[3])) then
			assert(PetRules.autoFollow(team, "tiny", 3, power) == false and table.concat(team, ",") == before, "a weaker hatch stays off")
		end
		assert(PetRules.autoFollow(team, "big", 3, power) == false, "no duplicate")
	end)

	test("team: a sold team pet's slot goes to the strongest pet left", function()
		local pets = {
			{ Id = "w", Mineral = "Raptor", Rarity = "Common", Seed = 1 },
			{ Id = "s", Mineral = "Raptor", Rarity = "Legendary", Seed = 2 },
			{ Id = "m", Mineral = "Raptor", Rarity = "Rare", Seed = 3 },
		}
		local team = { "m" }
		assert(PetRules.fillTeam(team, pets, 2) == 1 and team[2] == "s", "the strongest bench pet joins")
		assert(PetRules.fillTeam(team, pets, 2) == 0, "a full team is left alone")
		local src = require("@lune/fs").readFile("src/server/PetService.luau")
		assert(string.find(src, "PetRules.fillTeam(data.EquippedPets", 1, true), "PetService refills after a sale")
	end)
	test("pets: a maxed team pet's XP spills to teammates with room (MAX is not a dead end)", function()
		local rooms = { a = 0, b = 10, c = 3 }
		local function room(id)
			return rooms[id] or 0
		end
		local out = PetRules.spillXp("a", 9, { "a", "b", "c" }, room)
		assert(out.a == nil and (out.b or 0) + (out.c or 0) == 9, "all 9 passed on")
		assert(out.c <= 3 and out.b <= 10)
		out = PetRules.spillXp("a", 20, { "a", "b", "c" }, room)
		assert(out.b == 10 and out.c == 3, "fills both, rest dropped")
		out = PetRules.spillXp("b", 4, { "a", "b", "c" }, room)
		assert(out.b == 4 and out.c == nil, "room left: target keeps it all")
		out = PetRules.spillXp("b", 12, { "a", "b", "c" }, room)
		assert(out.b == 10 and out.c == 2, "overflow past the cap spills")
		out = PetRules.spillXp("z", 5, { "a", "b" }, room)
		assert(out.z == 5, "off the team: unchanged rule")
		out = PetRules.spillXp("a", 5, { "a" }, room)
		assert(next(out) == nil, "solo maxed pet: nothing to give")
		assert(next(PetRules.spillXp("a", 0, { "a", "b" }, room)) == nil)
		assert(next(PetRules.spillXp("a", -3, { "a", "b" }, room)) == nil)
		out = PetRules.spillXp("a", 7, { "a", "b", "b", "c" }, room)
		assert((out.b or 0) + (out.c or 0) == 7, "duplicate ids counted once")
	end)
end
