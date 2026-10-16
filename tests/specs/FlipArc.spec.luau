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

describe("Coins spin toward the ZOOM camera on every plot", function()
	it("the spin axis is sideways to the camera view on all 8 plots (not a flat wheel)", function()
		local Config = require(ReplicatedStorage.Shared.Config)
		local TableLayout = require(ReplicatedStorage.Shared.Util.TableLayout)
		for slot = 1, Config.MAX_PLOTS do
			local x, z = TableLayout.plotPosition(slot, Config.MAX_PLOTS, Config.PLOT_RING_RADIUS)
			local len = math.sqrt(x * x + z * z)
			local ox, oz = x / len, z / len -- the way the ZOOM camera looks
			local ax, az = FlipArc.spinAxis(FlipArc.spinYaw(ox, oz))
			-- axis is unit length and at right angles to the view direction
			expect(math.sqrt(ax * ax + az * az)).toBeNear(1, 1e-9)
			expect(ax * ox + az * oz).toBeNear(0, 1e-9)
		end
	end)

	it("a table with no direction keeps the old spin", function()
		expect(FlipArc.spinYaw(0, 0)).toBe(0)
	end)
end)

describe("Mega coin always shows a face", function()
	it("turns a face toward the viewer from every side", function()
		for k = 0, 11 do
			local a = k / 12 * math.pi * 2
			local dx, dz = math.cos(a), math.sin(a)
			local yaw = FlipArc.megaFacing(dx, dz)
			-- the coin's face axis (world) after the extra turn: (-sin, -cos)
			local ax, az = -math.sin(yaw), -math.cos(yaw)
			expect(math.abs(ax * dx + az * dz)).toBeNear(1, 1e-9)
		end
	end)

	it("the big jump spin ends on a whole turn", function()
		expect(FlipArc.megaSpin(0)).toBe(0)
		local last = FlipArc.megaSpin(1)
		expect(last / (math.pi * 2)).toBeNear(3, 1e-9)
		expect(FlipArc.megaSpin(0.5)).toBeAtLeast(FlipArc.megaSpin(0.2))
	end)
end)
