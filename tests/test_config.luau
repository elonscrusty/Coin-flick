return function(t)
	local test, shared = t.test, t.shared
	local Config = shared("Config")

	test("config: every tier mineral exists and orders are consistent", function()
		for i, id in Config.TierOrder do
			local tier = Config.Tiers[id]
			assert(tier and tier.Order == i, id .. " order")
			for _, m in tier.Minerals do
				assert(Config.Minerals[m], id .. " unknown mineral " .. m)
			end
		end
		for _, id in Config.HandheldOrder do
			assert(Config.Handhelds[id], id)
		end
	end)

	test("config: storage and display upgrades only go up", function()
		for i = 2, #Config.Capacity do
			assert(Config.Capacity[i].Size > Config.Capacity[i - 1].Size and Config.Capacity[i].Price > Config.Capacity[i - 1].Price)
		end
		for i = 2, #Config.Display do
			assert(Config.Display[i].Slots > Config.Display[i - 1].Slots)
		end
		assert(Config.Display[#Config.Display].Slots <= 20, "alcove has 20 slots")
	end)

	test("config: weights sum to 100", function()
		local function sum(w)
			local n = 0
			for _, v in w do
				n += v
			end
			return n
		end
		assert(math.abs(sum(Config.RarityWeights) - 100) < 1e-9)
		assert(math.abs(sum(Config.FormationWeights) - 100) < 1e-9)
		assert(math.abs(sum(Config.ModifierWeights) - 100) < 1e-9)
		local m = 0
		for _, b in Config.MassBands do
			m += b.Weight
		end
		assert(m == 100)
	end)
end
