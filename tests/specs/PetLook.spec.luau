local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MeshCatalog = require(ReplicatedStorage.Shared.MeshCatalog)
local MeshIds = require(ReplicatedStorage.Shared.MeshIds) :: { [string]: number }
local PetConfig = require(ReplicatedStorage.Shared.PetConfig)
local PetFollowMath = require(ReplicatedStorage.Shared.Util.PetFollowMath)
local PetLook = require(ReplicatedStorage.Shared.Util.PetLook)

describe("Pet models", function()
	it("every coin pet has a Blender model with a catalog entry and an id slot", function()
		for _, def in PetConfig.Pets do
			local name = PetLook.modelName(def.id)
			expect(name ~= nil).toBeTruthy()
			expect(MeshCatalog[name] ~= nil).toBeTruthy()
			expect(type(MeshIds[name])).toBe("number")
		end
	end)

	it("pet models share the common slots the game tints", function()
		for _, def in PetConfig.Pets do
			local pieces = MeshCatalog[PetLook.modelName(def.id)]
			for _, slot in { "Body", "Belly", "Foot", "Eye", "EyeShine", "Nose" } do
				expect(pieces[slot] ~= nil).toBeTruthy()
			end
			for slot in PetLook.tints(def) do
				expect(pieces[slot] ~= nil).toBeTruthy() -- a tint for a missing slot would silently do nothing
			end
		end
	end)

	it("unknown pets get no model", function()
		for _, bad in { "ghost", "", 5, false } do
			expect(PetLook.modelName(bad)).toBe(nil)
		end
	end)

	it("a levelled-up pet is bigger, and the level is kept in range", function()
		expect(PetLook.scale(10) > PetLook.scale(1)).toBeTruthy()
		expect(PetLook.scale(99)).toBe(PetLook.scale(PetConfig.MAX_LEVEL))
		expect(PetLook.scale(-4)).toBe(PetLook.scale(1))
	end)
end)

describe("Pet follow", function()
	it("the pet stands behind and to the right of an owner looking down -Z", function()
		local x, y, z = PetFollowMath.spot(0, 10, 0, 0, -1)
		expect(x > 0).toBeTruthy() -- right of a -Z look is +X
		expect(z > 0).toBeTruthy() -- behind
		expect(y < 10).toBeTruthy() -- on the ground, not at head height
	end)

	it("the spot turns with the owner and a zero look direction does not crash", function()
		local x, _, z = PetFollowMath.spot(0, 0, 0, 1, 0) -- looking down +X: behind is -X, right is +Z
		expect(x < 0).toBeTruthy()
		expect(z > 0).toBeTruthy()
		local ax, _, az = PetFollowMath.spot(0, 0, 0, 0, 0)
		expect(ax == ax and az == az).toBeTruthy()
	end)

	it("a second pet of the same owner stands further back", function()
		local _, _, z1 = PetFollowMath.spot(0, 0, 0, 0, -1, 1)
		local _, _, z2 = PetFollowMath.spot(0, 0, 0, 0, -1, 2)
		expect(z2 > z1).toBeTruthy()
	end)

	it("walking closes the gap, never overshoots, same speed at any frame rate", function()
		local x1 = PetFollowMath.step(0, 0, 0, 10, 0, 0, 1 / 30)
		expect(x1 > 0 and x1 < 10).toBeTruthy()
		local fast, slow = 0, 0
		for _ = 1, 60 do
			fast = PetFollowMath.step(fast, 0, 0, 10, 0, 0, 1 / 60)
		end
		for _ = 1, 30 do
			slow = PetFollowMath.step(slow, 0, 0, 10, 0, 0, 1 / 30)
		end
		expect(math.abs(fast - slow) < 0.01).toBeTruthy()
		expect(PetFollowMath.step(0, 0, 0, 10, 0, 0, 100) <= 10).toBeTruthy() -- a huge frame time is capped
	end)

	it("a far-away spot (respawn, teleport) is snapped to", function()
		local x, y, z = PetFollowMath.step(0, 0, 0, 500, 3, -20, 1 / 60)
		expect(x).toBe(500)
		expect(y).toBe(3)
		expect(z).toBe(-20)
	end)

	it("hop: bounces while walking, bobs gently when still, jumps right after a flip", function()
		local still = PetFollowMath.hop(1.3, 0, false, nil)
		expect(still >= 0 and still < 0.4).toBeTruthy()
		local walking = 0
		for i = 1, 200 do
			walking = math.max(walking, PetFollowMath.hop(i / 20, 0, true, nil))
		end
		expect(walking > 0.3).toBeTruthy()
		local jump = PetFollowMath.hop(1, 0, false, PetFollowMath.FLIP_HOP_SECONDS / 2)
		expect(jump > 1.5).toBeTruthy()
		expect(PetFollowMath.hop(1, 0, false, PetFollowMath.FLIP_HOP_SECONDS + 1) < 0.4).toBeTruthy() -- jump is over
		expect(PetFollowMath.hop(1, 0, false, -3) < 0.4).toBeTruthy() -- a flip "in the future" (clock skew) does nothing
	end)
end)
