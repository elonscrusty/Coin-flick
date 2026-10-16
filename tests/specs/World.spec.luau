local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local HatSizes = require(ReplicatedStorage.Shared.Util.HatSizes)

local function brightness(c): number
	return 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
end

describe("Hats fit the head", function()
	it("every hat has a size", function()
		for _, def in Config.Hats do
			expect(HatSizes.WIDTH[def.id]).toBeTruthy()
		end
	end)

	it("no hat is wider than the limit once fitted (cowboy hat was huge)", function()
		for _, def in Config.Hats do
			expect(HatSizes.WIDTH[def.id] * HatSizes.fit(def.id)).toBeAtMost(HatSizes.MAX_WIDTH + 1e-9)
		end
		expect(HatSizes.fit("cowboy")).toBeAtMost(0.6)
		expect(HatSizes.fit("party")).toBe(1)
		expect(HatSizes.fit("nope")).toBe(1)
	end)
end)

describe("Cartoon sky", function()
	it("is a thick bright-blue haze (hides the realistic default clouds)", function()
		local sky = Config.Sky
		expect(sky.haze).toBeAtLeast(1.5)
		expect(sky.density).toBeAtLeast(0.3)
		expect(sky.density).toBeAtMost(0.5) -- yards still clear
		expect(sky.color.B).toBeAtLeast(sky.color.R)
		expect(brightness(sky.color)).toBeAtLeast(0.6)
	end)
end)

describe("Yard arch", function()
	it("pillars are bright, so avatars (brown, dark, any color) stand out", function()
		local Plot = require(game:GetService("ServerScriptService").Server.Builders.Plot)
		expect(brightness(Plot.PILLAR)).toBeAtLeast(0.9)
	end)
end)
