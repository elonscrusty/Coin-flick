local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local CoinLook = require(ReplicatedStorage.Shared.Util.CoinLook)

describe("CoinLook", function()
	it("every rare coin has its own look", function()
		for _, def in Config.Rarities do
			expect(CoinLook.RARE[def.id] ~= nil).toBeTruthy()
			expect(CoinLook.forRarity(def.id) ~= CoinLook.NORMAL).toBeTruthy()
		end
		expect(CoinLook.forRarity(nil)).toBe(CoinLook.NORMAL)
		expect(CoinLook.forRarity("nope")).toBe(CoinLook.NORMAL)
	end)

	it("never uses Neon (sunlight washes it to white)", function()
		for _, look in CoinLook.all() do
			expect(look.material ~= "Neon").toBeTruthy()
		end
	end)

	it("rare coin colors are clearly different from a plain coin and each other", function()
		local looks = CoinLook.all()
		for idA, a in looks do
			for idB, b in looks do
				if idA < idB then
					expect(CoinLook.distance(a.color, b.color)).toBeAtLeast(60)
				end
			end
		end
	end)

	it("the $ and hat marks are readable on every coin", function()
		for _, look in CoinLook.all() do
			expect(CoinLook.contrast(look.text, look.color)).toBeAtLeast(3)
		end
	end)

	it("rainbow marks stay readable at every color of the cycle", function()
		local text = CoinLook.RARE.rainbow.text
		for i = 0, 35 do
			local c = CoinLook.hsv(i / 36, CoinLook.RAINBOW_SATURATION, 1)
			expect(CoinLook.contrast(text, c)).toBeAtLeast(3)
		end
	end)

	it("popups use the coin's own color", function()
		for _, def in Config.Rarities do
			local look = CoinLook.forRarity(def.id)
			if not look.rainbow then
				expect(CoinLook.distance(def.color, look.color)).toBeAtMost(1)
			end
		end
	end)

	it("rarer coins sparkle more", function()
		local order = { CoinLook.NORMAL, CoinLook.RARE.silver, CoinLook.RARE.gold, CoinLook.RARE.rainbow, CoinLook.RARE.giant }
		for i = 2, #order do
			expect(order[i].landBurst).toBeAtLeast(order[i - 1].landBurst + 1)
			expect(order[i].sparkleSize).toBeAtLeast(order[i - 1].sparkleSize)
			expect(order[i].trail).toBeAtLeast(order[i - 1].trail)
		end
	end)

	it("hsv makes the right corner colors", function()
		local red = CoinLook.hsv(0, 1, 1)
		expect(red.R).toBe(1)
		expect(red.G).toBe(0)
		local blue = CoinLook.hsv(2 / 3, 1, 1)
		expect(blue.B).toBe(1)
		expect(blue.R).toBe(0)
	end)

	it("a GIANT coin grows evenly (never squished)", function()
		local mt = {}
		mt.__mul = function(v, k)
			return setmetatable({ X = v.X * k, Y = v.Y * k, Z = v.Z * k }, mt)
		end
		local rest = setmetatable({ X = 0.35, Y = 3.8, Z = 3.8 }, mt)
		local grow = Config.Rarities[1].grow
		local big = CoinLook.size(rest, CoinLook.scale(grow, 0.5, 0.8))
		expect(big.Y).toBeNear(3.8 * grow, 1e-6)
		expect(big.X / big.Y).toBeNear(rest.X / rest.Y, 1e-6) -- same shape, just bigger
		expect(big.Z).toBeNear(big.Y, 1e-6) -- still round
	end)

	it("grows fast, stays big in the air, is back to normal after the bounce", function()
		expect(CoinLook.scale(2.5, 0, 0.8)).toBe(1)
		expect(CoinLook.scale(2.5, 0.15, 0.8)).toBeNear(2.5, 1e-9)
		expect(CoinLook.scale(2.5, 0.6, 0.8)).toBeNear(2.5, 1e-9)
		expect(CoinLook.scale(2.5, 1, 0.8)).toBeNear(1, 1e-9)
	end)

	it("a spinning coin of any size never cuts into the table", function()
		local restT = Config.COIN_THICKNESS
		for _, grow in { 1, 1.1, 1.3, 1.6, 2.5 } do
			local t, d = restT * grow, 3.8 * grow
			for i = 0, 72 do
				local roll = i / 72 * math.pi * 2
				local lift = CoinLook.lift(roll, t, d, restT)
				-- centre sits restT/2 + lift above the table; lowest point must not go below it
				local half = t / 2 * math.abs(math.sin(roll)) + d / 2 * math.abs(math.cos(roll))
				expect(restT / 2 + lift - half).toBeAtLeast(-1e-9)
			end
		end
		-- lying flat at rest: no lift, so landed coins sit on the table
		expect(CoinLook.lift(math.pi / 2, restT, 3.8, restT)).toBeNear(0, 1e-9)
	end)
end)
