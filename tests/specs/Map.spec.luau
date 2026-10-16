local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local PlotThemes = require(ReplicatedStorage.Shared.Util.PlotThemes)
local YardLayout = require(ReplicatedStorage.Shared.Util.YardLayout)
local DecorLayout = require(ReplicatedStorage.Shared.Util.DecorLayout)

local HALF = Config.PLOT_SIZE / 2
local TABLE_EDGE = Config.TABLE_RADIUS + 0.8 -- rim

describe("Yard layout (camera rules)", function()
	local tall, low = YardLayout.tall(HALF), YardLayout.low(HALF)
	local function dist(a, b)
		return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
	end

	it("nothing stands in the front half or by the gate corners", function()
		for _, list in { tall, low } do
			for _, s in list do
				expect(s.z).toBeAtLeast(0)
			end
		end
	end)

	it("everything stays inside the fence, clear of the table", function()
		for _, s in tall do
			expect(math.abs(s.x) + YardLayout.TallRadius).toBeAtMost(HALF - 0.5)
			expect(s.z + YardLayout.TallRadius).toBeAtMost(HALF - 0.5)
			expect(math.sqrt(s.x ^ 2 + s.z ^ 2) - YardLayout.TallRadius).toBeAtLeast(TABLE_EDGE)
		end
		for _, s in low do
			expect(math.abs(s.x) + YardLayout.LowRadius).toBeAtMost(HALF - 0.5)
			expect(s.z + YardLayout.LowRadius).toBeAtMost(HALF - 0.5)
			expect(math.sqrt(s.x ^ 2 + s.z ^ 2) - YardLayout.LowRadius).toBeAtLeast(TABLE_EDGE)
		end
	end)

	it("pieces do not touch each other", function()
		local all = {}
		for _, s in tall do
			table.insert(all, { s = s, r = YardLayout.TallRadius })
		end
		for _, s in low do
			table.insert(all, { s = s, r = YardLayout.LowRadius })
		end
		for i = 1, #all do
			for j = i + 1, #all do
				expect(dist(all[i].s, all[j].s)).toBeAtLeast(all[i].r + all[j].r - 0.01)
			end
		end
	end)

	it("pieces only turn around Y: the yaw faces the yard centre", function()
		-- standing at the back, facing the middle (toward -Z), yaw is 0
		expect(YardLayout.yawToward(0, 10, 0, 0)).toBeNear(0, 1e-9)
		-- standing at -X facing +X: yaw is a quarter turn
		expect(math.abs(YardLayout.yawToward(-10, 0, 0, 0))).toBeNear(math.pi / 2, 1e-9)
	end)
end)

describe("Themes and tables match", function()
	it("every theme's table is a real table look", function()
		for _, t in PlotThemes.list do
			local i = Economy.tableLookNamed(t.tableLook)
			expect(Config.TableLooks[i].name).toBe(t.tableLook)
		end
	end)

	it("each theme wears a different table", function()
		local seen = {}
		for _, t in PlotThemes.list do
			expect(seen[t.tableLook]).toBeNil()
			seen[t.tableLook] = true
		end
	end)

	it("castle is not lime and beach is not pink", function()
		expect(PlotThemes.get("castle").tableLook ~= "Lime Fizz").toBe(true)
		expect(PlotThemes.get("beach").tableLook ~= "Bubblegum").toBe(true)
		expect(PlotThemes.get("candy").tableLook).toBe("Bubblegum")
	end)
end)

describe("World decoration (view, edge)", function()
	local p = DecorLayout.defaults
	local spots = DecorLayout.spots()

	it("tall pieces keep out of the view corridor in front of every gate", function()
		local count = 0
		for _, s in spots do
			if s.tall then
				count += 1
				local d = math.sqrt(s.x ^ 2 + s.z ^ 2)
				for slot = 1, p.maxPlots do
					local a = (slot - 1) / p.maxPlots * math.pi * 2
					local along = s.x * math.cos(a) + s.z * math.sin(a)
					if along > 0 and along < p.ringRadius + p.plotSize / 2 + DecorLayout.TallExtra then
						local perp = math.abs(-s.x * math.sin(a) + s.z * math.cos(a))
						expect(perp - s.radius).toBeAtLeast(DecorLayout.ViewHalfWidth - 0.001)
					end
				end
				expect(d).toBeAtLeast(p.ringRadius - p.plotSize) -- sanity
			end
		end
		expect(count).toBeAtLeast(20) -- still plenty of trees and boulders
	end)

	it("the forest is thicker than before", function()
		expect(#spots).toBeAtLeast(140)
	end)

	it("an edge wall of tall trees closes the whole circle", function()
		local trees = DecorLayout.edgeTrees()
		expect(#trees).toBeAtLeast(100)
		local beyond = 0
		for _, t in trees do
			local d = math.sqrt(t.x ^ 2 + t.z ^ 2)
			expect(d).toBeAtLeast(DecorLayout.EdgeRadius - 4)
			expect(d + t.radius).toBeAtMost(250) -- stays on the ground tile (256)
			expect(t.scale).toBeAtLeast(2)
			if d > p.extent then
				beyond += 1
			end
		end
		expect(beyond).toBe(#trees)
		-- no gap bigger than a tree: sorted by angle, neighbours are close
		local angles = {}
		for _, t in trees do
			table.insert(angles, math.atan2(t.z, t.x))
		end
		table.sort(angles)
		local widest = (angles[1] + math.pi * 2) - angles[#angles]
		for i = 2, #angles do
			widest = math.max(widest, angles[i] - angles[i - 1])
		end
		expect(widest * DecorLayout.EdgeRadius).toBeAtMost(24)
	end)
end)
