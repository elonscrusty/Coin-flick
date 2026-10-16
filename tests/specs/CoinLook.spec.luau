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
		local order =
			{ CoinLook.NORMAL, CoinLook.RARE.silver, CoinLook.RARE.gold, CoinLook.RARE.rainbow, CoinLook.RARE.giant }
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
				local lift = CoinLook.lift(roll, t, d, restT, 3.8)
				-- centre sits restT/2 + lift above the table; lowest point must not go below it
				local half = t / 2 * math.abs(math.sin(roll)) + d / 2 * math.abs(math.cos(roll))
				expect(restT / 2 + lift - half).toBeAtLeast(-1e-9)
			end
		end
		-- lying flat at rest: no lift, so landed coins sit on the table
		expect(CoinLook.lift(math.pi / 2, restT, 3.8, restT, 3.8)).toBeNear(0, 1e-9)
	end)
end)

describe("CoinLook fixes from the runner pictures", function()
	local ServerScriptService = game:GetService("ServerScriptService")
	local GameLogic = require(ServerScriptService.Server.Util.GameLogic)

	it("SILVER is never flat white", function()
		local c = CoinLook.RARE.silver.color
		expect(math.min(c.R, c.G, c.B) * 255).toBeAtMost(190)
		expect(CoinLook.distance(c, Color3.fromRGB(255, 255, 255))).toBeAtLeast(80)
	end)

	it("RAINBOW faces show every color at once, not one solid color", function()
		local stops = CoinLook.rainbowStops(6)
		expect(#stops).toBe(6)
		for i = 1, #stops do
			for j = i + 1, #stops do
				expect(CoinLook.distance(stops[i], stops[j])).toBeAtLeast(60)
			end
			expect(CoinLook.contrast(CoinLook.RARE.rainbow.text, stops[i])).toBeAtLeast(3)
		end
	end)

	it("RAINBOW edge goes through the whole rainbow during one short flip", function()
		local seen = {}
		for i = 0, 6 do
			local c = CoinLook.rainbowColor(i * 0.1) -- 0.6 s of flight
			seen[#seen + 1] = c
		end
		expect(CoinLook.distance(seen[1], seen[4])).toBeAtLeast(100)
	end)

	it("a grown GIANT clears the coins next to it, a normal coin lands flat", function()
		local t, d = Config.COIN_THICKNESS, 3.8
		local grow = 2.5
		local lift = CoinLook.lift(math.pi / 2, t * grow, d * grow, t, d) -- lying flat, full size
		-- bottom of the giant (centre minus half its thickness) is above a neighbour's top
		expect(t / 2 + lift - t * grow / 2).toBeAtLeast(t - 1e-9)
		expect(CoinLook.lift(math.pi / 2, t, d, t, d)).toBeNear(0, 1e-9)
	end)

	it("GIANT and RAINBOW are shouted, small rares are not", function()
		local giant = GameLogic.shoutNotice("Carter", 7, { result = "heads", cash = 500, hats = 0, rarity = "giant" })
		expect(giant ~= nil).toBeTruthy()
		expect(giant.rarity).toBe("giant")
		expect(string.find(giant.text, "GIANT", 1, true) ~= nil).toBeTruthy()
		expect(GameLogic.shoutNotice("C", 7, { result = "heads", cash = 3, hats = 0, rarity = "silver" })).toBeNil()
		expect(GameLogic.shoutNotice("C", 7, { result = "heads", cash = 1, hats = 0, rarity = "normal" })).toBeNil()
	end)
end)

describe("CoinLook round 3: coins stand out on the table, GIANT is a shiny coin", function()
	it("every rare coin has an outline that is clearly darker or lighter than it", function()
		for id, look in CoinLook.RARE do
			if id ~= "silver" then
				expect(look.outline ~= nil).toBeTruthy()
				expect(CoinLook.contrast(look.outline :: Color3, look.color)).toBeAtLeast(2)
			end
		end
	end)

	it("every coin is clearly different from every table top, or is outlined", function()
		for id, look in CoinLook.all() do
			for _, tbl in Config.TableLooks do
				local apart = CoinLook.distance(look.color, tbl.top) >= 60
				local outlined = look.outline ~= nil and CoinLook.contrast(look.outline, tbl.top) >= 1.5
				expect(apart or outlined).toBeTruthy()
			end
		end
	end)

	it("GIANT is deep gold with a white shine, not fire red", function()
		local c = CoinLook.RARE.giant.color
		expect(c.R).toBeAtLeast(c.G)
		expect(c.G).toBeAtLeast(c.B * 1.5) -- gold, not red
		expect(c.G * 255).toBeAtLeast(110)
		expect(CoinLook.RARE.giant.reflectance).toBeAtLeast(CoinLook.RARE.gold.reflectance)
		expect(#CoinLook.RARE.giant.sparkle).toBeAtLeast(4) -- rainbow-ish sparkles
	end)

	it("sparkles never wash the table pale (they keep a little of the color behind them)", function()
		expect(CoinLook.SPARKLE_LIGHT).toBeAtMost(0.5)
	end)

	it("no coin look lights the table (nothing in a look is a light)", function()
		for _, look in CoinLook.all() do
			expect((look :: any).glow).toBeNil()
		end
	end)
end)
