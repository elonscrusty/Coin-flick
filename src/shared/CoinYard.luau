--!strict
-- The coin yard: a fenced area east of the pet park. Walk onto a floor pad to flip its coin; heads pay cash, and the
-- cash buys eggs at the yard's egg stand (the normal Pet Shop, odds shown there). Pure numbers and rules; the server
-- (server/CoinYardService) does the building and the paying. Tested offline in tests/test_coin_yard.luau.

local CoinYard = {}

CoinYard.FolderName = "CT_CoinYard"
CoinYard.StandName = "EggStand"
CoinYard.ArchName = "CoinYardArch"

-- Yard floor: centre and size (world studs). It sits beyond the park's cliffs, reached by the two portal arches.
CoinYard.Centre = { X = 230, Z = 0 }
CoinYard.Size = { X = 100, Z = 80 }
CoinYard.Arrive = { X = 187, Z = 0 } -- where the park arch drops you (inside the yard, facing +X)
-- Arch at the east end of the park's cross path; stepping on it enters the yard. The yard's own arch leads back.
CoinYard.ParkArch = { X = 93, Z = 0 }
CoinYard.ParkArrive = { X = 80, Z = 0 }
CoinYard.YardArch = { X = 183, Z = 0 }
CoinYard.Stand = { X = 262, Z = 0 }

-- Battle ring in the middle clearing (west side, off the main walk): a part with attribute PvpPad opens the battle card.
CoinYard.Ring = { X = -26, Z = 0, Diameter = 14 }

-- Pad grid: Cols x Rows pads of Size studs, Gap apart, centred on the yard.
CoinYard.Pads = { Cols = 6, Rows = 4, Size = 7, Gap = 4 }
CoinYard.PadCooldown = 1.2 -- seconds before the same pad flips again for the same player
CoinYard.ChainWindow = 1.8 -- a flip within this many seconds of the last one keeps the chain going

-- Odds printed on the yard sign. Each row is the chance of that coin and what heads pays (x the base).
CoinYard.HeadsChance = 0.55
CoinYard.Coins = {
	{ Name = "Copper", Chance = 0.80, Mult = 1 },
	{ Name = "Silver", Chance = 0.14, Mult = 3 },
	{ Name = "Gold", Chance = 0.055, Mult = 10 },
	{ Name = "Diamond", Chance = 0.005, Mult = 50 },
}
CoinYard.TailsPays = 0.2 -- tails pays this fraction of the base (nothing is ever lost)
CoinYard.ChainStep = 0.1 -- +10% per chained flip
CoinYard.ChainMax = 1.0 -- up to +100%
-- A basic egg should take about this many flips of base coins to afford.
CoinYard.FlipsPerBasicEgg = 90
CoinYard.EggRounds = 1.5 -- = RobuxConfig.CoinEggs.Rounds.BasicEgg

export type Flip = { heads: boolean, coin: string, cash: number, chain: number }

function CoinYard.pickCoin(rarityRoll: number): { Name: string, Chance: number, Mult: number }
	local acc = 0
	for _, c in CoinYard.Coins do
		acc += c.Chance
		if rarityRoll < acc then
			return c
		end
	end
	return CoinYard.Coins[1]
end

-- Cash for one flip at base `base` (coins). `roll` / `rarityRoll` in [0, 1). `chain` = flips chained so far (1 = first).
-- `boost` is a fraction from pets (0.1 = +10%).
function CoinYard.flip(base: number, roll: number, rarityRoll: number, chain: number, boost: number?): Flip
	local coin = CoinYard.pickCoin(rarityRoll)
	local heads = roll < CoinYard.HeadsChance
	local chainBonus = math.min(CoinYard.ChainMax, math.max(0, chain - 1) * CoinYard.ChainStep)
	local mult = (1 + chainBonus) * (1 + math.max(0, boost or 0))
	local pay = if heads then base * coin.Mult else base * CoinYard.TailsPays
	return { heads = heads, coin = coin.Name, cash = math.max(1, math.floor(pay * mult + 0.5)), chain = chain }
end

-- Next chain count: within the window it goes up, else back to 1.
function CoinYard.nextChain(chain: number, lastAt: number, now: number): number
	if chain > 0 and now - lastAt <= CoinYard.ChainWindow then
		return chain + 1
	end
	return 1
end

-- Base coins per flip for a zone whose average round pays `roundCoins`.
function CoinYard.baseFor(roundCoins: number): number
	return math.max(5, math.floor(roundCoins * CoinYard.EggRounds / CoinYard.FlipsPerBasicEgg + 0.5))
end

-- Average cash one flip pays at base 1 (no chain, no boost).
function CoinYard.meanMult(): number
	local mean = 0
	for _, c in CoinYard.Coins do
		mean += c.Chance * c.Mult
	end
	return CoinYard.HeadsChance * mean + (1 - CoinYard.HeadsChance) * CoinYard.TailsPays
end

-- Centre of pad (col, row), 1-based, world studs.
function CoinYard.padCentre(col: number, row: number): (number, number)
	local P = CoinYard.Pads
	local pitch = P.Size + P.Gap
	local x = CoinYard.Centre.X - 6 + (col - (P.Cols + 1) / 2) * pitch
	local z = CoinYard.Centre.Z + (row - (P.Rows + 1) / 2) * pitch
	return x, z
end

-- The sign text: the odds, so nobody guesses (rule: odds are always shown).
function CoinYard.oddsLines(): { string }
	local out = { ("Heads %d%%  /  Tails %d%% (pays a little)"):format(CoinYard.HeadsChance * 100 + 0.5, (1 - CoinYard.HeadsChance) * 100 + 0.5) }
	for _, c in CoinYard.Coins do
		table.insert(out, ("%s coin %s%%: heads pays x%d"):format(c.Name, tostring(math.floor(c.Chance * 1000 + 0.5) / 10), c.Mult))
	end
	return out
end

return CoinYard
