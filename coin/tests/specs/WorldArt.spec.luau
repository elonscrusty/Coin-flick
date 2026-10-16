local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local PlotThemes = require(ReplicatedStorage.Shared.Util.PlotThemes)
local SkyLayout = require(ReplicatedStorage.Shared.Util.SkyLayout)
local YardLayout = require(ReplicatedStorage.Shared.Util.YardLayout)

local HALF = Config.PLOT_SIZE / 2

local function bright(c: Color3): boolean
	return math.max(c.R, c.G, c.B) >= 0.55
end

describe("Sky layout", function()
	it("has clouds, balloons and islands high above the ground", function()
		expect(#SkyLayout.clouds()).toBeAtLeast(20)
		expect(#SkyLayout.balloons()).toBeAtLeast(10)
		expect(#SkyLayout.islands()).toBeAtLeast(4)
		for _, list in { SkyLayout.clouds(), SkyLayout.balloons(), SkyLayout.islands() } do
			for _, item in list do
				expect(item.y).toBeAtLeast(40)
			end
		end
	end)

	it("keeps sky pieces from overlapping each other", function()
		local all = {}
		for _, item in SkyLayout.balloons() do
			table.insert(all, { item = item, r = SkyLayout.BALLOON_FOOTPRINT })
		end
		for _, item in SkyLayout.islands() do
			table.insert(all, { item = item, r = SkyLayout.ISLAND_FOOTPRINT })
		end
		for i = 1, #all do
			for j = i + 1, #all do
				local a, b = all[i], all[j]
				local d = math.sqrt((a.item.x - b.item.x) ^ 2 + (a.item.y - b.item.y) ^ 2 + (a.item.z - b.item.z) ^ 2)
				expect(d).toBeAtLeast(a.r + b.r)
			end
		end
	end)

	it("paints hills in at least five different colours", function()
		local seen: { [string]: boolean } = {}
		for _, hill in SkyLayout.hills() do
			seen[tostring(hill.color)] = true
			expect(bright(hill.cap)).toBe(true)
		end
		local count = 0
		for _ in seen do
			count += 1
		end
		expect(count).toBeAtLeast(5)
	end)

	it("puts the fountains clear of the mega coin, spawn and paths", function()
		local fountains = SkyLayout.fountains(Config.MAX_PLOTS)
		expect(#fountains).toBeAtLeast(2)
		for _, f in fountains do
			expect(math.sqrt(f.x ^ 2 + f.z ^ 2)).toBeAtLeast(SkyLayout.FOUNTAIN_SIZE + 8)
			expect(math.sqrt(f.x ^ 2 + (f.z - 26) ^ 2)).toBeAtLeast(SkyLayout.FOUNTAIN_SIZE + 8)
			expect(math.sqrt(f.x ^ 2 + f.z ^ 2) + SkyLayout.FOUNTAIN_SIZE).toBeAtMost(22) -- paths start at 22
		end
	end)

	it("has flowers beside every path and a different curb colour per neighbour", function()
		expect(#SkyLayout.pathFlowers(22, 100)).toBeAtLeast(4)
		expect(SkyLayout.PATH_EDGES[1] ~= SkyLayout.PATH_EDGES[2]).toBe(true)
	end)
end)

describe("Yard outer pieces", function()
	it("stand outside the back fence and under the top HUD line", function()
		for _, s in YardLayout.outer(HALF) do
			expect(s.z - YardLayout.TallRadius).toBeAtLeast(HALF)
			local scale = YardLayout.tallScale("oak", s.x, s.z, 1)
			expect(scale).toBeAtLeast(0.3)
		end
	end)
end)

describe("Theme skies", function()
	it("every theme has bright sky colours", function()
		for _, theme in PlotThemes.list do
			expect(bright(theme.sky.atmosphere)).toBe(true)
			expect(bright(theme.sky.decay)).toBe(true)
			expect(bright(theme.sky.tint)).toBe(true)
		end
	end)
end)

describe("Sky colours", function()
	it("no sky piece uses brown or tan", function()
		local colors: { Color3 } = {}
		for _, c in SkyLayout.ISLAND do
			table.insert(colors, c)
		end
		for _, c in SkyLayout.BALLOONS do
			table.insert(colors, c)
		end
		for _, c in SkyLayout.PATH_EDGES do
			table.insert(colors, c)
		end
		for _, c in colors do
			expect(SkyLayout.isBrownish(c)).toBe(false)
		end
		expect(SkyLayout.isBrownish(Color3.fromRGB(150, 100, 60))).toBe(true)
		expect(SkyLayout.isBrownish(Color3.fromRGB(190, 150, 110))).toBe(true)
	end)
end)
