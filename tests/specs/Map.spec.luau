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

local CameraMath = require(ReplicatedStorage.Shared.Util.CameraMath)

describe("Pieces stay under the top HUD in the spawn view", function()
	local function topOk(x, z, height)
		local sy = YardLayout.screenY(x, z, height)
		expect(sy ~= nil).toBe(true)
		expect(sy).toBeAtMost(YardLayout.TopLimit + 1e-6)
	end

	it("every theme's tall piece, at every tall spot, even when the yard is full", function()
		for _, theme in PlotThemes.list do
			for i, spot in YardLayout.tall(HALF) do
				local scale = YardLayout.tallScale(theme.tree, spot.x, spot.z, 1 + (i % 3) * 0.07)
				expect(scale).toBeAtLeast(YardLayout.MinTallScale)
				expect(scale).toBeAtMost(YardLayout.MaxTallScale)
				topOk(spot.x, spot.z, YardLayout.TallHeights[theme.tree] * scale)
			end
		end
	end)

	it("pieces are only shrunk as much as needed", function()
		for _, theme in PlotThemes.list do
			for _, spot in YardLayout.tall(HALF) do
				local scale = YardLayout.tallScale(theme.tree, spot.x, spot.z, 1)
				if scale < 1 - 1e-6 then
					-- it is exactly at the limit, not far below it
					local sy = YardLayout.screenY(spot.x, spot.z, YardLayout.TallHeights[theme.tree] * scale)
					expect(sy).toBeAtLeast(YardLayout.TopLimit - 0.02)
				end
			end
		end
	end)

	it("every small prop, at every low spot", function()
		for _, theme in PlotThemes.list do
			for _, kind in theme.props do
				expect(YardLayout.LowHeights[kind] ~= nil).toBe(true)
				for _, spot in YardLayout.low(HALF) do
					topOk(spot.x, spot.z, YardLayout.LowHeights[kind] * YardLayout.lowScale(kind))
				end
			end
		end
	end)

	it("a piece higher than the cap really would poke over the HUD", function()
		local spot = YardLayout.tall(HALF)[2]
		local sy = YardLayout.screenY(spot.x, spot.z, YardLayout.maxTop(spot.x, spot.z) + 3)
		expect(sy).toBeAtLeast(YardLayout.TopLimit)
	end)
end)

describe("Fence gap, floor tiles, ground ring", function()
	it("every piece is at least 1.5 studs inside the fence", function()
		local inner = HALF - YardLayout.PostHalf
		for _, s in YardLayout.tall(HALF) do
			expect(inner - (math.abs(s.x) + YardLayout.TallRadius)).toBeAtLeast(YardLayout.FenceGap - 1e-6)
			expect(inner - (s.z + YardLayout.TallRadius)).toBeAtLeast(YardLayout.FenceGap - 1e-6)
		end
		for _, s in YardLayout.low(HALF) do
			expect(inner - (math.abs(s.x) + YardLayout.LowRadius)).toBeAtLeast(YardLayout.FenceGap - 1e-6)
			expect(inner - (s.z + YardLayout.LowRadius)).toBeAtLeast(YardLayout.FenceGap - 1e-6)
		end
	end)

	it("floor tiles are never white, and clearly differ from the white fence", function()
		for _, t in PlotThemes.list do
			local white = (t.tile.R + t.tile.G + t.tile.B) / 3
			expect(white).toBeAtMost(0.82)
			local dFence = math.abs(t.tile.R - t.fence.R)
				+ math.abs(t.tile.G - t.fence.G)
				+ math.abs(t.tile.B - t.fence.B)
			expect(dFence).toBeAtLeast(0.45)
			local dPad = math.abs(t.tile.R - t.pad.R) + math.abs(t.tile.G - t.pad.G) + math.abs(t.tile.B - t.pad.B)
			expect(dPad).toBeAtLeast(0.1) -- still visible on its own floor
		end
	end)

	it("every theme has its own ground ring colour", function()
		local seen = {}
		for _, t in PlotThemes.list do
			local key = string.format("%.2f/%.2f/%.2f", t.ground.R, t.ground.G, t.ground.B)
			expect(seen[key]).toBeNil()
			seen[key] = true
			expect((t.ground.R + t.ground.G + t.ground.B) / 3).toBeAtMost(0.93)
		end
	end)
end)

describe("Gate in the walk view", function()
	local Plot = require(game:GetService("ServerScriptService").Server.Builders.Plot)
	-- The Roblox camera behind the avatar just after walking out of the spawn view (CameraView.behindAvatar):
	-- 12 back, 5 up, looking at the avatar. The avatar stands TABLE_RADIUS + 6 in front of the table.
	local avatarU = -(Config.TABLE_RADIUS + 6)
	local view = {
		back = -avatarU + CameraMath.WALK.back,
		up = 3 + 1.5 + CameraMath.WALK.up - Config.TABLE_HEIGHT,
		aim = avatarU,
	}
	local gateU = -HALF

	it("the gate is wide: the pillars stay well outside the table in the walk view", function()
		for _, aspect in { 1.78, 2.17 } do
			local pillar = CameraMath.project(view, { gateU, 0, Plot.GATE_HALF - Plot.PILLAR_W / 2 }, aspect, 70)
			local tableEdge = CameraMath.project(view, { -Config.TABLE_RADIUS, 0, Config.TABLE_RADIUS }, aspect, 70)
			expect(pillar).toBeAtLeast(0.6)
			expect(pillar).toBeAtLeast(tableEdge + 0.15)
		end
	end)

	it("pillars are thin: each fills at most 4% of the screen width", function()
		for _, aspect in { 1.78, 2.17 } do
			local a = CameraMath.project(view, { gateU, 0, Plot.GATE_HALF - Plot.PILLAR_W / 2 }, aspect, 70)
			local b = CameraMath.project(view, { gateU, 0, Plot.GATE_HALF + Plot.PILLAR_W / 2 }, aspect, 70)
			expect((b - a) / 2).toBeAtMost(0.04)
		end
	end)

	it("the name sign hangs above the picture, so the table gets the whole screen", function()
		local bottom = Plot.ARCH_TOP - 1.6 - 1.3 - Config.TABLE_HEIGHT
		local _, sy = CameraMath.project(view, { gateU, bottom, 0 }, 2, 70)
		expect(sy).toBeAtLeast(1)
		expect(Plot.CAP_SIZE).toBeAtMost(1.5)
	end)
end)
