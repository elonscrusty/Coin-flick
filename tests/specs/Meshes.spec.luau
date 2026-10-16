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

describe("Blender models are wired to the game", function()
	local Config = require(ReplicatedStorage.Shared.Config)
	local MeshPaint = require(ReplicatedStorage.Shared.Util.MeshPaint)

	it("every hat and every helper has a model with a catalog entry and an id slot", function()
		for _, hat in Config.Hats do
			local name = MeshPaint.HATS[hat.id]
			expect(name ~= nil).toBe(true)
			expect(MeshCatalog[name] ~= nil).toBe(true)
			expect(type(MeshIds[name])).toBe("number")
		end
		for _, helper in Config.HelperTypes do
			local name = MeshPaint.HELPERS[helper.id]
			expect(name ~= nil).toBe(true)
			-- the game tints these two pieces from HelperDef.body and .cap
			expect(MeshCatalog[name].Body ~= nil).toBe(true)
			expect(MeshCatalog[name].Cap ~= nil).toBe(true)
		end
		expect(MeshCatalog[MeshPaint.COIN].Rim ~= nil and MeshCatalog[MeshPaint.COIN].Face ~= nil).toBe(true)
		expect(MeshCatalog[MeshPaint.COIN].Mark ~= nil).toBe(true)
		for _, slot in { "Top", "Rim", "Legs" } do
			expect(MeshCatalog[MeshPaint.TABLE][slot] ~= nil).toBe(true)
		end
	end)

	it("extra models exist: mega coin and gift box", function()
		expect(MeshCatalog.CF_MegaCoin ~= nil).toBe(true)
		expect(MeshCatalog.CF_GiftBox ~= nil).toBe(true)
	end)

	it("part names give their colour slot", function()
		expect(MeshPaint.slotOf("CF_Coin_Rim")).toBe("Rim")
		expect(MeshPaint.slotOf("CF_HatTop_Felt")).toBe("Felt")
		expect(MeshPaint.slotOf("Rim")).toBe("Rim")
	end)

	it("a tint wins over the catalog colour, other slots keep it, unknown slots give nothing", function()
		local base = MeshPaint.look("CF_Coin", "Face", nil)
		expect(base ~= nil).toBe(true)
		local tint = Color3.fromRGB(1, 2, 3)
		local tinted = MeshPaint.look("CF_Coin", "Face", { Face = tint })
		expect((tinted :: any).R).toBe((tint :: any).R)
		local other = MeshPaint.look("CF_Coin", "Rim", { Face = tint })
		expect((other :: any).R).toBe((MeshPaint.look("CF_Coin", "Rim", nil) :: any).R)
		local none = MeshPaint.look("CF_Coin", "Nope", nil)
		expect(none).toBeNil()
		local noModel = MeshPaint.look("CF_Nope", "Rim", nil)
		expect(noModel).toBeNil()
	end)

	it("coins scale to their diameter and are centred, the rest stand on their floor", function()
		expect(MeshPaint.coinScale(3)).toBe(1)
		expect(MeshPaint.coinScale(4.5)).toBe(1.5)
		expect(MeshPaint.isCentered("CF_Coin")).toBe(true)
		expect(MeshPaint.isCentered("CF_Table")).toBe(false)
		expect(MeshPaint.isCentered("CF_HatTop")).toBe(false)
	end)
end)
