local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MeshCatalog = require(ReplicatedStorage.Shared.MeshCatalog)
local MeshIds = require(ReplicatedStorage.Shared.MeshIds) :: { [string]: number }

describe("Blender models", function()
	it("every model has an id entry (0 = not uploaded) and a piece catalog", function()
		local count = 0
		for name, pieces in MeshCatalog do
			count += 1
			expect(type(MeshIds[name])).toBe("number")
			expect(MeshIds[name] >= 0).toBe(true)
			local slots = 0
			for slot, look in pieces do
				slots += 1
				-- MeshService finds the slot in the part name with %w+, so it must be letters/digits only
				expect(string.match(slot, "^%w+$")).toBe(slot)
				expect(type(look.material)).toBe("string")
			end
			expect(slots >= 1).toBe(true)
		end
		expect(count >= 3).toBe(true)
		for name in MeshIds do
			expect(MeshCatalog[name] ~= nil).toBe(true)
		end
	end)
end)

describe("World models", function()
	it("every model the game code asks Meshes.clone for exists in the catalog", function()
		local used = {
			"CF_Tree",
			"CF_TreePalm",
			"CF_TreeCandy",
			"CF_Tower",
			"CF_TreeCrystal",
			"CF_Bench",
			"CF_Rock",
			"CF_Bush",
			"CF_Umbrella",
			"CF_Shell",
			"CF_CandyCane",
			"CF_Mushroom",
			"CF_Flowers",
			"CF_Lamp",
			"CF_FenceSection",
			"CF_FencePost",
			"CF_ArchPillar",
			"CF_Cloud",
			"CF_Balloon",
			"CF_Island",
			"CF_Fountain",
			"CF_PlazaTile",
			"CF_FreeStatue",
		}
		for _, name in used do
			expect(MeshCatalog[name] ~= nil).toBe(true)
		end
	end)

	it("themed slots exist on the models that get tinted", function()
		local tinted = {
			CF_Tree = { "Bark", "Leaf", "LeafLight" },
			CF_TreeCandy = { "Stick", "Candy", "Stripe" },
			CF_Tower = { "Stone", "StoneLight", "Roof", "Trim", "Window" },
			CF_FenceSection = { "Wood" },
			CF_FencePost = { "Wood" },
			CF_ArchPillar = { "Band" },
			CF_Balloon = { "Envelope" },
			CF_Bench = { "Wood", "Leg" },
		}
		for name, slots in tinted do
			for _, slot in slots do
				expect(MeshCatalog[name][slot] ~= nil).toBe(true)
			end
		end
	end)
end)
