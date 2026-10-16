local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlotThemes = require(ReplicatedStorage.Shared.Util.PlotThemes)
local DecorLayout = require(ReplicatedStorage.Shared.Util.DecorLayout)

describe("Plot themes", function()
	it("has the five looks in unlock order, the first free", function()
		expect(#PlotThemes.list).toBe(5)
		expect(PlotThemes.ids()[1]).toBe("meadow")
		expect(PlotThemes.ids()[2]).toBe("beach")
		expect(PlotThemes.ids()[3]).toBe("candy")
		expect(PlotThemes.ids()[4]).toBe("castle")
		expect(PlotThemes.ids()[5]).toBe("space")
		local last = -1
		for i, t in PlotThemes.list do
			expect(t.resets).toBe(i - 1)
			expect(t.resets).toBeAtLeast(last + 1)
			last = t.resets
			expect(#t.accent).toBeAtLeast(4)
			expect(#t.foliage).toBeAtLeast(2)
			expect(#t.stone).toBeAtLeast(1)
			expect(#t.props).toBeAtLeast(3)
		end
	end)

	it("every look names real pieces", function()
		local trees = { oak = true, palm = true, lolly = true, tower = true, crystal = true }
		local props = {
			bench = true,
			boulder = true,
			crate = true,
			bush = true,
			umbrella = true,
			shell = true,
			bucket = true,
			cupcake = true,
			gumdrop = true,
			candycane = true,
			barrel = true,
			torch = true,
			orb = true,
			antenna = true,
		}
		for _, t in PlotThemes.list do
			expect(trees[t.tree]).toBe(true)
			for _, p in t.props do
				expect(props[p]).toBe(true)
			end
		end
	end)

	it("each reset gives the next look, then loops", function()
		expect(PlotThemes.cycle(0).id).toBe("meadow")
		expect(PlotThemes.cycle(1).id).toBe("beach")
		expect(PlotThemes.cycle(2).id).toBe("candy")
		expect(PlotThemes.cycle(3).id).toBe("castle")
		expect(PlotThemes.cycle(4).id).toBe("space")
		expect(PlotThemes.cycle(5).id).toBe("meadow")
		expect(PlotThemes.cycle(-3).id).toBe("meadow")
	end)

	it("looks unlock by resets", function()
		expect(#PlotThemes.unlocked(0)).toBe(1)
		expect(#PlotThemes.unlocked(2)).toBe(3)
		expect(#PlotThemes.unlocked(4)).toBe(5)
		expect(#PlotThemes.unlocked(99)).toBe(5)
		expect(PlotThemes.isUnlocked("space", 3)).toBe(false)
		expect(PlotThemes.isUnlocked("space", 4)).toBe(true)
		expect(PlotThemes.isUnlocked("lava", 99)).toBe(false)
	end)

	it("picking only starts after all five looks were seen", function()
		expect(PlotThemes.canPick(3)).toBe(false)
		expect(PlotThemes.canPick(4)).toBe(true)
		expect(PlotThemes.resolve(2, "space").id).toBe("candy") -- not unlocked, newest shows
		expect(PlotThemes.resolve(3, "meadow").id).toBe("castle") -- cannot pick yet
		expect(PlotThemes.resolve(4, "beach").id).toBe("beach")
		expect(PlotThemes.resolve(7, "castle").id).toBe("castle")
	end)

	it("a bad saved pick never crashes or unlocks anything", function()
		for _, bad in { "lava", "", 5, true, {}, false } do
			expect(PlotThemes.resolve(1, bad).id).toBe("beach")
			expect(PlotThemes.resolve(6, bad).id).toBe(PlotThemes.cycle(6).id)
		end
		expect(PlotThemes.resolve(6, nil).id).toBe(PlotThemes.cycle(6).id)
	end)
end)

describe("World decoration layout", function()
	local p = DecorLayout.defaults
	local spots = DecorLayout.spots()

	it("fills the world and is the same every time", function()
		expect(#spots).toBeAtLeast(90)
		local again = DecorLayout.spots()
		expect(#again).toBe(#spots)
		for i = 1, #spots do
			expect(again[i].x).toBe(spots[i].x)
			expect(again[i].kind).toBe(spots[i].kind)
		end
		local other = DecorLayout.spots({
			ringRadius = p.ringRadius,
			plotSize = p.plotSize,
			maxPlots = p.maxPlots,
			plazaRadius = p.plazaRadius,
			spawnZ = p.spawnZ,
			pathWidth = p.pathWidth,
			extent = p.extent,
			seed = 99,
			outerCount = p.outerCount,
			innerCount = p.innerCount,
		})
		expect(other[1].x == spots[1].x and other[2].x == spots[2].x).toBe(false)
	end)

	it("nothing lands inside a yard, on a path, the plaza or the spawn", function()
		for _, s in spots do
			expect(DecorLayout.isFree(p, s.x, s.z, s.radius)).toBe(true)
			expect(DecorLayout.yardGap(p, s.x, s.z, s.radius)).toBeAtLeast(DecorLayout.Clear - 0.001)
			local d = math.sqrt(s.x * s.x + s.z * s.z)
			expect(d - s.radius).toBeAtLeast(p.plazaRadius)
			expect(d + s.radius).toBeAtMost(p.extent)
			expect(math.sqrt(s.x * s.x + (s.z - p.spawnZ) ^ 2) - s.radius).toBeAtLeast(7)
		end
	end)

	it("no two props overlap", function()
		for i = 1, #spots do
			for j = i + 1, #spots do
				local a, b = spots[i], spots[j]
				local dist = math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
				expect(dist).toBeAtLeast(a.radius + b.radius)
			end
		end
	end)

	it("uses both zones and a good mix of pieces", function()
		local zones, kinds = { inner = 0, outer = 0 }, {}
		for _, s in spots do
			zones[s.zone] += 1
			kinds[s.kind] = true
		end
		expect(zones.inner).toBeAtLeast(6)
		expect(zones.outer).toBeAtLeast(80)
		local n = 0
		for _ in kinds do
			n += 1
		end
		expect(n).toBeAtLeast(6)
	end)

	it("keeps trees and boulders clear of the path from the middle to each yard", function()
		for _, s in spots do
			expect(DecorLayout.pathDistance(p, s.x, s.z) - s.radius).toBeAtLeast(p.pathWidth / 2)
		end
	end)
end)
