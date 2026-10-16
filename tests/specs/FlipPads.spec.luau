local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local FlipPads = require(ReplicatedStorage.Shared.Util.FlipPads)
local YardLayout = require(ReplicatedStorage.Shared.Util.YardLayout)

local HALF = Config.PLOT_SIZE / 2
local R = FlipPads.Radius

describe("Flip pads", function()
	it("has four pads, flat on the floor", function()
		expect(#FlipPads.pads).toBe(4)
		expect(FlipPads.Height <= 0.15).toBe(true)
	end)

	it("every pad is inside the fence and clear of the table", function()
		for _, p in FlipPads.pads do
			expect(math.abs(p.x) + R).toBeAtMost(HALF - 1)
			expect(math.abs(p.z) + R).toBeAtMost(HALF - 1)
			expect(math.sqrt(p.x ^ 2 + p.z ^ 2) - R).toBeAtLeast(Config.TABLE_RADIUS + 0.8)
		end
	end)

	it("pads stay out of the gate walk-in and off each other", function()
		for i, p in FlipPads.pads do
			-- the gate is 22 wide (x = -11..11) in the front wall: keep pads out of its straight walk-in
			expect(math.abs(p.x) - R).toBeAtLeast(11)
			for j = i + 1, #FlipPads.pads do
				local q = FlipPads.pads[j]
				expect(math.sqrt((p.x - q.x) ^ 2 + (p.z - q.z) ^ 2)).toBeAtLeast(2 * R + 0.5)
			end
		end
	end)

	it("pads do not touch the yard's corner trees or props", function()
		local groups = {
			{ spots = YardLayout.tall(HALF), radius = YardLayout.TallRadius },
			{ spots = YardLayout.low(HALF), radius = YardLayout.LowRadius },
		}
		for _, group in groups do
			for _, s in group.spots do
				for _, p in FlipPads.pads do
					expect(math.sqrt((p.x - s.x) ^ 2 + (p.z - s.z) ^ 2)).toBeAtLeast(R + group.radius)
				end
			end
		end
	end)

	it("padAt finds the pad you stand on and nothing else", function()
		local p = FlipPads.pads[2]
		expect(FlipPads.padAt(p.x, p.z)).toBe(2)
		expect(FlipPads.padAt(p.x + 1, p.z)).toBe(2)
		expect(FlipPads.padAt(0, -15)).toBeNil() -- where the avatar starts
		expect(FlipPads.padAt(p.x + 6, p.z)).toBeNil()
	end)
end)
