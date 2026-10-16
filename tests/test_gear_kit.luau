-- Pet gear models: Gear_<Id> first in the shop lookup, machine source decision, no held hammer tool.
return function(t)
	local test, shared = t.test, t.shared
	local G = shared("GearKit")

	test("gear kit: Gear_<Id> is first in the lookup for all 6 ids, old names stay as fallbacks", function()
		assert(#G.Ids == 6)
		for _, id in G.Ids do
			local names = G.kitNames(id)
			assert(names[1] == "Gear_" .. id, id .. " first is " .. tostring(names[1]))
			assert(#names >= 3 and table.find(names, id), id .. " keeps the old names")
		end
	end)

	test("gear kit: machine uses the gear model only when it exists and is Ready", function()
		assert(G.source(true, true) == "Gear")
		assert(G.source(true, false) == "Parts")
		assert(G.source(false, true) == "Parts")
		assert(G.source(false, false) == "Parts")
	end)

	test("gear kit: fit scale keeps the model inside the footprint", function()
		local V = t.Vector3
		assert(math.abs(G.fitScale(V.new(4, 5, 8), V.new(8, 0, 8)) - 1) < 1e-6, "limited by depth")
		assert(math.abs(G.fitScale(V.new(10, 5, 2), V.new(5, 0, 8)) - 0.5) < 1e-6)
		assert(math.abs(G.fitScale(V.new(2, 10, 2), V.new(8, 4, 8)) - 0.4) < 1e-6, "height cap")
	end)

	test("gear kit: pet gear is never a held tool (no Hammer-named tool for any id)", function()
		for _, id in G.Ids do
			assert(G.heldToolName(id) == nil, id)
			local acc = G.accessoryModel(id)
			assert(acc == nil or string.sub(acc, 1, 5) == "Gear_", id)
		end
		assert(G.accessoryModel("Hammer") == "Gear_Hammer" and G.accessoryModel("AutoCracker") == nil)
	end)
	test("gear kit: state light and beacon hide under the gear model, the base stays", function()
		assert(G.hideUnderGear("StateLight", "Light") == true)
		assert(G.hideUnderGear("Beacon", "Beacon") == true)
		assert(G.hideUnderGear("Body", nil) == true)
		assert(G.hideUnderGear("Base", nil) == false)
	end)
	test("gear kit: hip accessory is about 1.8 studs on its longest side", function()
		local k = G.accessoryScale(0.9, 5)
		assert(math.abs(0.9 * k - 1.8) < 1e-6, "0.9 stud model grows to 1.8")
		assert(math.abs(4 * G.accessoryScale(4, 5) - 1.8) < 1e-6, "a big model shrinks to 1.8")
		assert(G.accessoryScale(0.9, 10) > k, "bigger avatar, bigger accessory")
		-- Studio measured 1.4 studs on a short avatar: avatars under 5 studs still get the full 1.8
		assert(math.abs(0.9 * G.accessoryScale(0.9, 3.9) - 1.8) < 1e-6, "short avatar still gets 1.8")
	end)

	test("gear kit: no client UI draws the old hammer icon", function()
		local fs = require("@lune/fs")
		local hits = {}
		for _, dir in { "src/client", "src/client/ui" } do
			for _, name in fs.readDir(dir) do
				local f = dir .. "/" .. name
				if fs.isFile(f) and string.sub(name, -5) == ".luau" and name ~= "UI.luau" then
					local n = 0
					for line in string.gmatch(fs.readFile(f) .. "\n", "(.-)\n") do
						n += 1
						if string.find(line, "icon%([^)]*\"hammer\"") or string.find(line, "icon%([^)]*\"jackhammer\"")
							or string.find(line, "setToolSlotIcon%(.-\"hammer\"") then
							table.insert(hits, f .. ":" .. n)
						end
					end
				end
			end
		end
		assert(#hits == 0, "hammer icon still drawn at " .. table.concat(hits, ", "))
	end)
end
