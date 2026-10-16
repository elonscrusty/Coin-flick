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
