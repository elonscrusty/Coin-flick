-- Leaderboard tree rules (shared/TreeBoard): best pet by POWER, card checks, branch plan, signs, the Power board.
return function(t)
	local test, shared = t.test, t.shared
	local TB = shared("TreeBoard")
	local Boards = shared("Boards")
	local PetStats = shared("PetStats")
	local Config = shared("Config")

	local species = {}
	for k in Config.Minerals do
		table.insert(species, k)
	end
	table.sort(species)
	local function pet(id, seed, rarity)
		return { Id = id, Mineral = species[1], Rarity = rarity or "Common", Modifier = "Natural", Seed = seed, Mass = 1 }
	end

	test("tree: best pet is the highest POWER, tower XP counted", function()
		local a, b = pet("a", 11), pet("b", 12, "Legendary")
		local data = { InventoryGeodes = { a, b }, TowerXP = { a = 0, b = 0 } }
		local best, power = TB.bestPet(data)
		local pa, pb = PetStats.powerOfPet(a, 0), PetStats.powerOfPet(b, 0)
		assert(best == (if pb >= pa then b else a) and power == math.max(pa, pb))
		data.TowerXP.a = 1e7 -- lots of training lifts a
		local best2, power2 = TB.bestPet(data)
		assert(power2 >= power and power2 == math.max(PetStats.powerOfPet(a, 1e7), pb))
		assert(best2 ~= nil)
		local none, zero = TB.bestPet({ InventoryGeodes = {} })
		assert(none == nil and zero == 0)
		assert(select(2, TB.bestPet(nil)) == 0)
	end)

	test("tree: cards keep only a valid look and power", function()
		local c = TB.card(pet("x", 5), 321.7)
		assert(c and c.Power == 321 and c.Mineral == species[1] and c.Seed == 5 and c.Modifier == "Natural")
		assert(TB.card({ Mineral = "NotAPet", Rarity = "Common", Seed = 1 }, 10) == nil, "unknown species")
		assert(TB.card(pet("x", 5), 0) == nil, "no power")
		assert(TB.card(pet("x", 5), 0 / 0) == nil, "NaN power")
		local odd = pet("y", 2)
		odd.Modifier = "Hacked"
		odd.Nickname = string.rep("z", 60)
		local c2 = TB.card(odd, 5)
		assert(c2 and c2.Modifier == "Natural" and #(c2.Nickname :: string) == TB.Config.NameMax)
		assert(TB.cardChanged(nil, c) and not TB.cardChanged(c, c) and not TB.cardChanged(c, nil))
		assert(TB.cardChanged(c, TB.card(pet("x", 5), 400)), "power change is saved")
	end)

	test("tree: plan puts rank k on branch k, skips empty rows, caps at the branch count", function()
		local rows = {}
		for i = 1, 14 do
			table.insert(rows, { Rank = i, UserId = 100 + i, Name = "P" .. i, Value = 1000 - i })
		end
		table.insert(rows, 2, { Rank = 2, UserId = 9, Name = "Zero", Value = 0 })
		local plan = TB.plan(rows)
		assert(#plan == TB.Config.Branches)
		assert(plan[1].Branch == 1 and plan[1].UserId == 101 and plan[2].UserId == 102, "zero row skipped")
		assert(#TB.plan(rows, 3) == 3, "fewer branches in the model")
		assert(#TB.plan({}) == 0)
	end)

	test("tree: signs and sizes by rank", function()
		local a, b = TB.signLines(1, "Sam", 12345)
		assert(a == "#1 Sam" and b == "POWER 12,345")
		local long = TB.signLines(2, string.rep("n", 40), 5)
		assert(#long <= #"#2 " + TB.Config.NameMax)
		assert(TB.petHeight(1) > TB.petHeight(2) and TB.petHeight(3) > TB.petHeight(4))
		assert(TB.signColor(1) ~= TB.signColor(5))
	end)

	test("tree: the STRONGEST PET board reads the best pet POWER", function()
		local data = { InventoryGeodes = { pet("a", 3) }, TowerXP = {} }
		assert(Boards.values(data).Power == select(2, TB.bestPet(data)))
		assert(Boards.values({}).Power == 0)
		assert(Boards.Info.Power and table.find(Boards.Order, "Power"))
	end)

	test("tree: off by design (shop square in the middle), so the service stays quiet", function()
		assert(TB.Config.Enabled == false)
	end)
end
