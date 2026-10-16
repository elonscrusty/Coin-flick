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
		expect(math.min(c.R, c.G, c.B) * 255).toBeAtMost(200)
		expect(CoinLook.distance(c, Color3.fromRGB(255, 255, 255))).toBeAtLeast(65)
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

	it("every rare is labelled: GIANT and RAINBOW to everyone, SILVER and GOLD to the flipper only", function()
		local giant = GameLogic.shoutNotice("Carter", 7, { result = "heads", cash = 500, hats = 0, rarity = "giant" })
		expect(giant ~= nil).toBeTruthy()
		expect(giant.rarity).toBe("giant")
		expect(string.find(giant.text, "GIANT", 1, true) ~= nil).toBeTruthy()
		local silver = GameLogic.shoutNotice("C", 7, { result = "heads", cash = 3, hats = 0, rarity = "silver" })
		expect(silver ~= nil and silver.rarity == "silver").toBe(true)
		expect(silver ~= nil and silver.everyone).toBe(false) -- only the flipper sees it
		expect(giant ~= nil and giant.everyone).toBe(true)
		expect(GameLogic.shoutNotice("C", 7, { result = "heads", cash = 1, hats = 0, rarity = "normal" })).toBeNil()
	end)

	it("the welcome-back notice never says $0", function()
		expect(GameLogic.offlineNotice(0)).toBeNil()
		expect(GameLogic.offlineNotice(0.4)).toBeNil()
		local n = GameLogic.offlineNotice(12.6)
		expect(n ~= nil and string.find(n.text, "$12", 1, true) ~= nil).toBe(true)
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

describe("CoinLook round 4: rare coins never overlap a neighbour, edge-on still reads as a coin", function()
	local TableLayout = require(ReplicatedStorage.Shared.Util.TableLayout)

	it("a grown rare coin never touches another slot, at any size upgrade", function()
		for _, restD in { 3.0, 3.4, 3.8 } do
			for index = 1, Config.MAX_COINS do
				local x, z = TableLayout.coinOffset(index, Config.MAX_COINS)
				for _, def in Config.Rarities do
					local grown = restD * CoinLook.growFor(def.grow, index, restD)
					for other = 1, Config.MAX_COINS do
						if other ~= index then
							local ox, oz = TableLayout.coinOffset(other, Config.MAX_COINS)
							local dist = math.sqrt((x - ox) ^ 2 + (z - oz) ^ 2)
							-- grown radius + the ridge (8% wider) + neighbour at rest must fit
							expect(dist - grown * CoinLook.RIDGE_WIDER / 2 - restD / 2).toBeAtLeast(0)
						end
					end
				end
			end
		end
	end)

	it("a grown coin stays over the table (never flies off behind it)", function()
		for index = 1, Config.MAX_COINS do
			local x, z = TableLayout.coinOffset(index, Config.MAX_COINS)
			local grown = 3.8 * CoinLook.growFor(2.5, index, 3.8)
			local reach = math.sqrt(x * x + z * z) + grown * CoinLook.RIDGE_WIDER / 2
			expect(reach).toBeAtMost(Config.TABLE_RADIUS + CoinLook.EDGE_OVERHANG + 1e-9)
		end
	end)

	it("a rare coin never shrinks below its normal size and the cap keeps some puff", function()
		for index = 1, Config.MAX_COINS do
			expect(CoinLook.growFor(1.1, index, 3.0)).toBeAtLeast(1)
			expect(CoinLook.growFor(1.1, index, 3.8)).toBeAtLeast(1)
		end
		-- GIANT is still clearly bigger than the others (capped to 5.6 studs wide)
		expect(CoinLook.growFor(2.5, 1, 3.8)).toBeAtLeast(1.4)
		-- silver (x1.1) puffs fully on every slot at normal size
		for index = 1, Config.MAX_COINS do
			expect(CoinLook.growFor(1.1, index, 3.0)).toBeNear(1.1, 1e-9)
		end
	end)

	it("ring coins at the biggest upgrade still fit on the table", function()
		for index = 1, Config.MAX_COINS do
			local x, z = TableLayout.coinOffset(index, Config.MAX_COINS)
			expect(math.sqrt(x * x + z * z) + 3.8 / 2).toBeAtMost(Config.TABLE_RADIUS)
		end
	end)

	it("the ridge is wider than the coin and thinner, so edge-on has a bump", function()
		local thickness, diameter = CoinLook.ridge(0.5, 3.8)
		expect(thickness).toBeAtMost(0.5)
		expect(diameter).toBeAtLeast(3.8 * 1.05)
		expect((diameter - 3.8) / 2).toBeAtLeast(0.1) -- at least 0.1 stud visible from the side
	end)

	it("coins are chunky enough to read edge-on", function()
		expect(Config.COIN_THICKNESS / 3.8).toBeAtLeast(0.12)
	end)
end)

describe("CoinLook round 5: GOLD stands out, GIANT never sweeps anything, MEGA is a real coin", function()
	local MegaLook = require(ReplicatedStorage.Shared.Util.MegaLook)
	local TableLayout = require(ReplicatedStorage.Shared.Util.TableLayout)

	it("GOLD is deep amber, far from the plain yellow coin, with stars and a dark ridge", function()
		local gold, normal = CoinLook.RARE.gold, CoinLook.NORMAL
		expect(CoinLook.distance(gold.color, normal.color)).toBeAtLeast(60)
		expect(gold.stars).toBeTruthy()
		expect(normal.stars).toBeFalsy()
		-- the ridge is dark enough to show against the coin
		expect(CoinLook.contrast(gold.rim, gold.color)).toBeAtLeast(2.5)
	end)

	it("every rare coin's ridge shows against its coin", function()
		for id, look in CoinLook.RARE do
			if id ~= "silver" and id ~= "rainbow" then
				expect(CoinLook.contrast(look.rim, look.color)).toBeAtLeast(1.5)
			end
		end
	end)

	it("no rare coin is ever wider than 6.4 studs in the air, on any slot or upgrade", function()
		for _, restD in { 3.0, 3.4, 3.8 } do
			for index = 1, Config.MAX_COINS do
				for _, def in Config.Rarities do
					local width = restD * CoinLook.growFor(def.grow, index, restD)
					expect(width).toBeAtMost(math.max(CoinLook.MAX_DIAMETER, restD) + 1e-9)
				end
			end
		end
		-- edge-on, the GIANT's sweep stays short of the coins next to it
		local reach = 3.8 * CoinLook.growFor(2.5, 1, 3.8) * CoinLook.RIDGE_WIDER / 2
		local nextCoin = select(1, TableLayout.coinOffset(2, Config.MAX_COINS))
		expect(reach).toBeAtMost(math.abs(nextCoin) - 3.8 / 2)
	end)

	it("a grown coin hovers higher, a plain coin does not", function()
		expect(CoinLook.hover(1)).toBe(0)
		expect(CoinLook.hover(0.9)).toBe(0)
		expect(CoinLook.hover(1.68)).toBeAtLeast(1.5)
	end)

	it("the star ring is round and inside the face", function()
		local spots = CoinLook.starRing(10, 0.34)
		expect(#spots).toBe(10)
		for _, spot in spots do
			expect(math.sqrt((spot.x - 0.5) ^ 2 + (spot.y - 0.5) ^ 2)).toBeNear(0.34, 1e-9)
			expect(spot.x).toBeAtLeast(0)
			expect(spot.y).toBeAtMost(1)
		end
	end)

	it("MEGA coin: rings nest inside each other, emblem fits inside the star ring", function()
		expect(MegaLook.RING_SCALE).toBeAtMost(MegaLook.RIM_SCALE)
		expect(MegaLook.STAR_RADIUS * 2).toBeAtMost(MegaLook.RING_SCALE)
		expect(MegaLook.EMBLEM_SCALE).toBeAtMost(MegaLook.STAR_RADIUS * 2 - 0.1)
		expect(#MegaLook.starSpots()).toBe(MegaLook.STARS)
	end)

	it("MEGA coin: gold gradient goes light to deep, emblem reads on both ends", function()
		expect(CoinLook.contrast(MegaLook.FACE_TOP, Color3.fromRGB(0, 0, 0))).toBeAtLeast(
			CoinLook.contrast(MegaLook.FACE_BOTTOM, Color3.fromRGB(0, 0, 0))
		)
		expect(CoinLook.contrast(MegaLook.EMBLEM, MegaLook.FACE_TOP)).toBeAtLeast(3)
		expect(CoinLook.contrast(MegaLook.EMBLEM, MegaLook.FACE_BOTTOM)).toBeAtLeast(3)
		expect(CoinLook.contrast(MegaLook.RIM, MegaLook.FACE_BOTTOM)).toBeAtLeast(2)
	end)

	it("MEGA coin: the ridge is wider and thinner than the coin, and it shines", function()
		local thickness, diameter = MegaLook.ridge(1.6, 16)
		expect(thickness).toBeAtMost(1.6)
		expect(diameter).toBeAtLeast(16 * 1.05)
		expect(MegaLook.REFLECTANCE).toBeAtLeast(0.2)
		expect(MegaLook.SHINE_ALPHA).toBeAtMost(0.9)
		expect(MegaLook.SPARKLE_RATE).toBeAtLeast(8)
	end)
end)

describe("CoinLook round 6: thin trail, heads land heads-up, nothing stays dressed", function()
	local FlipArc = require(ReplicatedStorage.Shared.Util.FlipArc)

	it("the flight trail is a thin ribbon, never a slab, for any coin size", function()
		for _, d in { 3.0, 3.8, 4.2, 4.9, 6.1, 6.4, 9.2 } do
			expect(CoinLook.trailHalfWidth(d) * 2).toBeAtMost(1.5 + 1e-9)
		end
		expect(CoinLook.trailHalfWidth(1)).toBeNear(0.5, 1e-9) -- never wider than the coin itself
	end)

	it('heads rests on the "$" face (Right face up), tails on the hat face', function()
		-- Rz(roll) turns local +X (the Right face) toward world up when roll = +90 degrees
		expect(math.sin(FlipArc.restRoll("heads"))).toBe(1)
		expect(math.sin(FlipArc.restRoll("skull"))).toBe(-1)
		expect(FlipArc.restRoll("anything else")).toBe(FlipArc.restRoll("skull"))
	end)

	it("every flip, rare or not, ends on the rest roll of its result (mod full turns)", function()
		for _, from in { "heads", "skull" } do
			for _, to in { "heads", "skull" } do
				for _, duration in { 0.3, 0.8, 1.6 } do
					local fromRoll, toRoll = FlipArc.restRoll(from), FlipArc.restRoll(to)
					local total = (toRoll - fromRoll) + FlipArc.spins(duration) * math.pi * 2
					local landed = fromRoll + total
					expect(math.cos(landed)).toBeNear(math.cos(toRoll), 1e-9)
					expect(math.sin(landed)).toBeNear(math.sin(toRoll), 1e-9)
				end
			end
		end
	end)
end)

describe("CoinLook round 7: right face up for every rarity, rainbow ridge, same jump height", function()
	local FlipArc = require(ReplicatedStorage.Shared.Util.FlipArc)

	it("every rarity and result lands showing the art that matches it", function()
		local rarities = { "normal" }
		for _, def in Config.Rarities do
			table.insert(rarities, def.id)
		end
		for _, rarity in rarities do
			for _, from in { "heads", "skull" } do
				for _, result in { "heads", "skull" } do
					for _, duration in { 0.3, 0.8, 1.6 } do
						-- the exact roll FlipFx ends on, and the server's rest roll
						local fromRoll, toRoll = FlipArc.restRoll(from), FlipArc.restRoll(result)
						local landed = fromRoll + (toRoll - fromRoll) + FlipArc.spins(duration) * math.pi * 2
						local want = if result == "heads" then "$" else "hat"
						expect(FlipArc.visibleArt(landed)).toBe(want)
						expect(FlipArc.visibleArt(toRoll)).toBe(want) -- server rest pose agrees
						expect(rarity ~= "").toBeTruthy()
					end
				end
			end
		end
	end)

	it("RAINBOW ridge and outline are colored, never white", function()
		local r = CoinLook.RARE.rainbow
		expect(math.min(r.rim.R, r.rim.G, r.rim.B) * 255).toBeAtMost(120)
		expect(CoinLook.distance(r.outline :: Color3, Color3.fromRGB(255, 255, 255))).toBeAtLeast(150)
		for i = 0, 10 do
			local ridge = CoinLook.darker(CoinLook.rainbowColor(i * 0.2 + 0.5), 0.55)
			expect(CoinLook.distance(ridge, Color3.fromRGB(255, 255, 255))).toBeAtLeast(100)
		end
	end)

	it("a rare coin's jump peaks exactly as high as any coin's, but never dips into the table", function()
		local peak = Config.FLIP_HEIGHT
		local t, d = Config.COIN_THICKNESS, 3.8
		for _, grow in { 1, 1.3, 1.68 } do
			for i = 0, 40 do
				local roll = i / 40 * math.pi * 2
				local h = peak * 4 * (i / 40) * (1 - i / 40) -- the arc
				local top = CoinLook.flightHeight(h, roll, t * grow, d * grow, t, d)
				expect(top).toBeAtLeast(h)
				-- bottom of the coin stays above the table
				local half = t * grow / 2 * math.abs(math.sin(roll)) + d * grow / 2 * math.abs(math.cos(roll))
				expect(top + t / 2 - half).toBeAtLeast(-1e-9)
				-- at the top of the jump the coin is no higher than the arc
				if i == 20 then
					expect(top).toBeNear(peak, 1e-9)
				end
			end
		end
	end)

	it("the landing drift log is on", function()
		expect(Config.LOG_COIN_DRIFT).toBeTruthy()
	end)
end)

describe("CoinLook round 8: SILVER is cool, plain gold is warm", function()
	it("silver is blue-white and plain gold is warm, far apart", function()
		local silver, plain = CoinLook.RARE.silver, CoinLook.NORMAL
		expect(silver.color.B).toBeAtLeast(silver.color.R) -- cool
		expect(plain.color.R).toBeAtLeast(plain.color.B * 3) -- warm
		expect(CoinLook.distance(silver.color, plain.color)).toBeAtLeast(150)
	end)

	it("silver has a dark steel ridge, a dark blue outline and pale blue sparkles", function()
		local silver = CoinLook.RARE.silver
		expect(CoinLook.contrast(silver.rim, silver.color)).toBeAtLeast(2) -- dark ridge, not white
		expect(silver.rim.B).toBeAtMost(160)
		expect(silver.outline ~= nil).toBeTruthy()
		local outline = silver.outline :: Color3
		expect(outline.B).toBeAtLeast(outline.R * 2) -- blue
		expect(CoinLook.contrast(outline, silver.color)).toBeAtLeast(2)
		expect(silver.material ~= "Foil").toBeTruthy() -- no white shine disc
	end)

	it("every look is far from every other, in the table-top and rare tests too", function()
		local looks = CoinLook.all()
		for idA, a in looks do
			for idB, b in looks do
				if idA < idB then
					expect(CoinLook.distance(a.color, b.color)).toBeAtLeast(60)
				end
			end
		end
	end)

	it("the flight trail stays thin for the biggest rainbow coin too", function()
		local widest = 3.8 * CoinLook.growFor(1.6, 1, 3.8)
		expect(CoinLook.trailHalfWidth(widest) * 2).toBeAtMost(1.5 + 1e-9)
	end)
end)

describe("CoinLook round 10: big coins keep clear of neighbours, no marker under a coin", function()
	local TableLayout = require(ReplicatedStorage.Shared.Util.TableLayout)

	it("a grown coin (with its ridge) keeps at least 0.4 studs from every other slot's coin", function()
		for _, restD in { 3.0, 3.4, 3.8 } do
			for index = 1, Config.MAX_COINS do
				local x, z = TableLayout.coinOffset(index, Config.MAX_COINS)
				local grow = CoinLook.growFor(3, index, restD)
				local grownD = restD * grow * CoinLook.RIDGE_WIDER
				for other = 1, Config.MAX_COINS do
					if other ~= index and grow > 1 then
						local ox, oz = TableLayout.coinOffset(other, Config.MAX_COINS)
						local dist = math.sqrt((x - ox) ^ 2 + (z - oz) ^ 2)
						expect(dist - grownD / 2 - restD / 2).toBeAtLeast(0.4 - 1e-9)
					end
				end
			end
		end
	end)

	it("empty-spot markers exist only for slots with no coin", function()
		for count = 1, Config.MAX_COINS do
			local markers = TableLayout.markerSlots(count, Config.MAX_COINS)
			expect(#markers).toBe(Config.MAX_COINS - count)
			for _, index in markers do
				expect(index).toBeAtLeast(count + 1)
			end
		end
		expect(#TableLayout.markerSlots(Config.MAX_COINS, Config.MAX_COINS)).toBe(0)
	end)
end)

describe("CoinLook round 11: art pass", function()
	it("landing squash starts and ends at exactly normal size, and never gets thin or fat", function()
		local main = 0.8
		for _, t in { 0, 0.5, 0.8, 1 } do
			local thick, wide = CoinLook.squash(t, main)
			expect(thick).toBe(1)
			expect(wide).toBe(1)
		end
		local minThick, maxWide = 1, 1
		for i = 1, 99 do
			local thick, wide = CoinLook.squash(main + (1 - main) * i / 100, main)
			minThick = math.min(minThick, thick)
			maxWide = math.max(maxWide, wide)
			expect(thick).toBeAtLeast(0.7)
			expect(wide).toBeAtMost(1.15)
		end
		expect(minThick).toBeAtMost(0.9) -- a visible squish
		expect(maxWide).toBeAtLeast(1.02)
	end)

	it("hero coins are chunky and landing bursts are big", function()
		expect(Config.COIN_THICKNESS).toBeAtLeast(0.8)
		expect(CoinLook.NORMAL.landBurst).toBeAtLeast(20)
		expect(CoinLook.RARE.giant.landBurst).toBeAtLeast(150)
	end)
end)
