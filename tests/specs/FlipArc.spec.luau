local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local FlipArc = require(ReplicatedStorage.Shared.Util.FlipArc)
local CameraMath = require(ReplicatedStorage.Shared.Util.CameraMath)

describe("Coin flip jump", function()
	it("starts and ends flat on the table", function()
		expect(FlipArc.height(0)).toBeNear(0)
		expect(FlipArc.height(FlipArc.MAIN)).toBeNear(0)
		expect(FlipArc.height(1)).toBeNear(0)
	end)

	it("really jumps: top of the flip is FLIP_HEIGHT, at least 5 studs (was under 4)", function()
		expect(FlipArc.height(FlipArc.MAIN / 2)).toBeNear(Config.FLIP_HEIGHT)
		expect(Config.FLIP_HEIGHT).toBeAtLeast(5)
	end)

	it("never goes higher than the ZOOM camera can show", function()
		for i = 0, 100 do
			expect(FlipArc.height(i / 100)).toBeAtMost(Config.FLIP_HEIGHT + 1e-9)
		end
	end)

	it("lands with a small bounce", function()
		local bounce = FlipArc.height(FlipArc.MAIN + (1 - FlipArc.MAIN) / 2)
		expect(bounce).toBeAtLeast(0.5)
		expect(bounce).toBeAtMost(Config.FLIP_HEIGHT * 0.2)
	end)

	it("spins at least 3 times, even on the fastest flips", function()
		expect(FlipArc.spins(Config.MIN_FLIP_TIME)).toBeAtLeast(3)
		expect(FlipArc.spins(Config.BASE_FLIP_TIME)).toBeAtLeast(FlipArc.spins(Config.MIN_FLIP_TIME))
	end)

	it("shadow shrinks and fades as the coin goes up", function()
		expect(FlipArc.shadowScale(0)).toBeNear(1)
		expect(FlipArc.shadowScale(Config.FLIP_HEIGHT)).toBeNear(0.5)
		expect(FlipArc.shadowFade(Config.FLIP_HEIGHT)).toBeAtLeast(FlipArc.shadowFade(0))
		expect(FlipArc.shadowFade(Config.FLIP_HEIGHT)).toBeAtMost(0.9)
	end)
end)

describe("WALK camera after ZOOM", function()
	it("sits behind the avatar and looks gently down, not straight down on the head", function()
		local w = CameraMath.WALK
		expect(w.back).toBeAtLeast(8)
		local pitch = math.deg(math.atan2(w.up, w.back))
		expect(pitch).toBeAtMost(30)
		expect(pitch).toBeAtLeast(10)
	end)
end)
