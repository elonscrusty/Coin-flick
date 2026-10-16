-- Coin eggs at the lobby EGG SHRINE (shared/RobuxConfig CoinEggs): prices per zone, the Basic / Rare / Mythic ratio,
-- no profit from buying eggs to sell the pets, and the buy check (egg id, count, Pet Book room, coins). The server
-- route (RobuxAction "BuyEggCoins") is tested in tests/server/robux.luau.
return function(t)
	local test, shared = t.test, t.shared
	local Config = shared("Config")
	local RobuxConfig = shared("RobuxConfig")

	local ZONES = { "Gravel", "Quarry", "Cavern", "Volcanic", "Meteor" }

	test("coin eggs: prices match the documented table and scale 1 / 3 / 10", function()
		local want = {
			Gravel = { 370, 1900, 5600 },
			Quarry = { 1100, 5600, 17000 },
			Cavern = { 3200, 16000, 48000 },
			Volcanic = { 8400, 42000, 130000 },
			Meteor = { 21000, 100000, 310000 },
		}
		for _, z in ZONES do
			for i, id in { "BasicEgg", "RareEgg", "MythicEgg" } do
				local one = RobuxConfig.eggCoinPrice(id, z, 1)
				assert(one == want[z][i], z .. " " .. id .. ": " .. tostring(one))
				assert(RobuxConfig.eggCoinPrice(id, z, 3) == 3 * one, "3x = three eggs")
				assert(RobuxConfig.eggCoinPrice(id, z, 10) == 10 * one, "10x = ten eggs")
			end
		end
	end)

	test("coin eggs: Basic is 1-2 rounds, Rare ~5x, Mythic ~15x, and selling the pets never profits", function()
		for _, z in ZONES do
			local round = RobuxConfig.roundCoins(z)
			local basic = RobuxConfig.eggCoinPrice("BasicEgg", z, 1) :: number
			assert(basic >= round and basic <= 2 * round, z .. " basic in 1-2 rounds")
			local rare = RobuxConfig.eggCoinPrice("RareEgg", z, 1) :: number
			local mythic = RobuxConfig.eggCoinPrice("MythicEgg", z, 1) :: number
			assert(rare / basic > 4.5 and rare / basic < 5.5, z .. " rare ~5x")
			assert(mythic / basic > 14 and mythic / basic < 16, z .. " mythic ~15x")
			for _, e in RobuxConfig.Eggs do
				local mean = RobuxConfig.petMeanValue(z, e.Rarity)
				local price = RobuxConfig.eggCoinPrice(e.Id, z, 1) :: number
				-- plus the one-time first-find coins per new species, still well below the price
				assert(price > mean + Config.PetIndex.FirstFindCoins, z .. " " .. e.Id .. " price above the pet's mean value")
			end
		end
	end)

	test("coin eggs: buy check refuses bad ids, counts, a full Pet Book and too few coins", function()
		local p = RobuxConfig.eggCoinPrice("BasicEgg", "Gravel", 3) :: number
		local price, why = RobuxConfig.coinEggCheck("BasicEgg", 3, "Gravel", p, 3)
		assert(price == p and why == nil, "exact coins and exact room is enough")
		price, why = RobuxConfig.coinEggCheck("GoldenEgg", 1, "Gravel", 1e9, 100)
		assert(price == nil and why == nil, "unknown egg: silent")
		price, why = RobuxConfig.coinEggCheck("BasicEgg", 2, "Gravel", 1e9, 100)
		assert(price == nil and why == nil, "count not sold: silent")
		price, why = RobuxConfig.coinEggCheck("BasicEgg", "1", "Gravel", 1e9, 100)
		assert(price == nil and why == nil, "count must be a number")
		price, why = RobuxConfig.coinEggCheck("BasicEgg", 1, "Nowhere", 1e9, 100)
		assert(price == nil and why == nil, "unknown zone")
		price, why = RobuxConfig.coinEggCheck("BasicEgg", 3, "Gravel", 1e9, 2)
		assert(price == nil and why == "Your Pet Book only has room for 2 more pets.", tostring(why))
		price, why = RobuxConfig.coinEggCheck("BasicEgg", 1, "Gravel", 1e9, 0)
		assert(price == nil and why == "Your Pet Book is full.", tostring(why))
		price, why = RobuxConfig.coinEggCheck("BasicEgg", 3, "Gravel", p - 1, 100)
		assert(price == nil and why == "Need 1 more coins.", tostring(why))
		price, why = RobuxConfig.coinEggCheck("BasicEgg", 3, "Gravel", p - 250, 100)
		assert(price == nil and why == "Need 250 more coins.", "the message counts the missing coins: " .. tostring(why))
		price, why = RobuxConfig.coinEggCheck("BasicEgg", 3, "Gravel", 0, 100)
		assert(price == nil and why == "Need " .. p .. " more coins.", "no coins at all: " .. tostring(why))
		price = RobuxConfig.coinEggCheck("BasicEgg", 1, "Gravel", 0 / 0, 100)
		assert(price == nil, "NaN coins never buy")
	end)

	test("coin eggs: the shop button reads NEED N when coins are short", function()
		local fmt = function(n: number): string
			return tostring(n)
		end
		local text, enabled, style = RobuxConfig.coinButton(3, 1500, 1000, 100, false, fmt)
		assert(text == "3x  NEED 500" and style == "gray", text)
		assert(enabled, "stays tappable (it only flashes the coin counter)")
		text, _, style = RobuxConfig.coinButton(1, 500, 500, 100, false, fmt)
		assert(text == "1x  500" and style == "gold", "exact coins buy: " .. text)
		text, enabled = RobuxConfig.coinButton(10, 5000, 1, 3, false, fmt)
		assert(text == "10x  NO ROOM" and not enabled, "no room wins over coins: " .. text)
		text, enabled = RobuxConfig.coinButton(3, 1500, 1000, 100, true, fmt)
		assert(enabled == false and text ~= "3x  NEED 500", "pending shows dots")
	end)
end
