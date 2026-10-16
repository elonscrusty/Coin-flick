--!strict
-- Hunt fun (owner picks 2026-10-15, "do 1 2 and 6"): pure rules, tested in tests/test_hunt_fun.luau.
--   1. Surprise eggs: every ordinary egg a player finishes pops a small server-rolled prize on top of its shells:
--      coins, pet XP or (rarely) a coin jackpot, and every 10th egg adds a Lucky Meter point. Never a pet.
--   2. Pet helper: the strongest equipped pet the player found (never one from a Robux egg, so Robux never changes who
--      finds the pet) joins the hunt and helps: faster cracking and extra basket room, bigger with more POWER.
--   6. Prizes for everyone: the racers who did not find the pet get a medal by eggs finished (2nd, 3rd, 4th), coins
--      and pet XP. A racer who finished no egg gets nothing (no reward for standing still or for the leftover pile).
-- Applied by src/server/RockService.luau (1, 2) and src/server/MatchService.luau (6); shown by the client
-- (Main "Surprise" event, PetFollow helper, ResultsPanel prize line).

local Config = require(script.Parent.Config)
local PetStats = require(script.Parent.PetStats)

local HuntFun = {}

HuntFun.Surprise = {
	Enabled = true,
	-- what an ordinary egg pops (relative weights; every egg pops one)
	Weights = { Coins = 58, Xp = 41, Jackpot = 1 } :: { [string]: number },
	Order = { "Coins", "Xp", "Jackpot" }, -- fixed roll order (weights tables have no order)
	-- Lucky Meter: every EggsPerMeter-th ordinary egg adds one point, for sure (a 5% random tick left the meter at 0
	-- for a whole Studio hunt, 2026-10-15). A shop Basic egg is 1 point too; 30 points fill the meter.
	EggsPerMeter = 10,
	CoinsMin = 1, -- coins = CoinsMin..CoinsMax x the zone's CashPerRubble
	CoinsMax = 2,
	Jackpot = 40, -- jackpot coins = Jackpot x the zone's CashPerRubble
	Xp = 3, -- pet XP for each following pet (the Pet Book page bonus applies on top)
}

HuntFun.Helper = {
	Enabled = true,
	-- POWER steps (PetStats.power): Rate = crack speed bonus (share), Carry = extra basket slots. A fresh Common is
	-- about 110 POWER, a maxed Common about 230, a maxed Legendary about 1600.
	Steps = {
		{ Power = 0, Rate = 0.05, Carry = 1 },
		{ Power = 250, Rate = 0.10, Carry = 1 },
		{ Power = 500, Rate = 0.15, Carry = 2 },
		{ Power = 900, Rate = 0.20, Carry = 2 },
		{ Power = 1400, Rate = 0.25, Carry = 3 },
	},
}

HuntFun.Prizes = {
	Enabled = true,
	Medals = { "Gold", "Silver", "Bronze", "Star" }, -- by place; the finder is always Gold
	Coins = { 0, 15, 10, 6 }, -- base coins by place (x the zone's CashPerRubble / 2); the finder gets the pet instead
	CoinsPerEgg = 1, -- + this per egg finished (same zone factor)
	MaxEggs = 60, -- eggs counted for the per-egg part
	Xp = { 0, 20, 14, 10 }, -- pet XP by place, for each following pet
	MinEggs = 1, -- at least this many eggs finished to get a prize
}

local function zoneFactor(tierId: string): number
	local tier = Config.Tiers[tierId]
	return if tier then math.max(tier.CashPerRubble, 1) else 1
end

export type Surprise = { Kind: string, Amount: number }

-- One ordinary egg's surprise, rolled by the server.
function HuntFun.surprise(rng: Random, tierId: string): Surprise
	local cfg = HuntFun.Surprise
	local total = 0
	for _, k in cfg.Order do
		total += cfg.Weights[k] or 0
	end
	local r = rng:NextNumber() * total
	local kind = cfg.Order[1]
	for _, k in cfg.Order do
		local w = cfg.Weights[k] or 0
		if r < w then
			kind = k
			break
		end
		r -= w
	end
	local f = zoneFactor(tierId)
	if kind == "Coins" then
		return { Kind = kind, Amount = rng:NextInteger(cfg.CoinsMin, cfg.CoinsMax) * f }
	elseif kind == "Jackpot" then
		return { Kind = kind, Amount = cfg.Jackpot * f }
	elseif kind == "Xp" then
		return { Kind = kind, Amount = cfg.Xp }
	end
	return { Kind = "Xp", Amount = cfg.Xp }
end

-- Counts one more ordinary hunt egg toward the Lucky Meter: the new count and whether this egg adds a point.
function HuntFun.meterTick(count: any): (number, boolean)
	local n = (if type(count) == "number" and count == count then math.max(math.floor(count), 0) else 0) + 1
	local per = math.max(HuntFun.Surprise.EggsPerMeter, 1)
	if n >= per then
		return 0, true
	end
	return n, false
end

export type HelperStep = { Power: number, Rate: number, Carry: number }

-- The helper step for a pet POWER (nil power = no helper).
function HuntFun.helperStep(power: number?): HelperStep?
	if not HuntFun.Helper.Enabled or type(power) ~= "number" or power ~= power then
		return nil
	end
	local best: HelperStep? = nil
	for _, s in HuntFun.Helper.Steps do
		if power >= s.Power then
			best = s
		end
	end
	return best
end

export type Candidate = { Pet: { [string]: any }, Xp: number?, Bought: boolean }

-- The helper among the equipped pets: the highest POWER pet that did not come from a Robux egg (ties: list order).
-- Returns the pet and its POWER, or nil when every equipped pet was bought (or none is equipped).
function HuntFun.pickHelper(list: { Candidate }): ({ [string]: any }?, number)
	local best, bestPower = nil, -1
	for _, c in list do
		if not c.Bought and type(c.Pet) == "table" then
			local p = PetStats.powerOfPet(c.Pet, c.Xp or 0)
			if p > bestPower then
				best, bestPower = c.Pet, p
			end
		end
	end
	return best, math.max(bestPower, 0)
end

export type Racer = { UserId: number, Eggs: number }
export type Prize = { Place: number, Medal: string, Coins: number, Xp: number }

-- Places for one finished round: the finder is 1st; the others by eggs finished (most first), equal counts share a
-- place. Racers below MinEggs get no row. `winner` may be nil (a round that ended without a finder gives no prizes).
function HuntFun.prizes(racers: { Racer }, winner: number?, tierId: string): { [number]: Prize }
	local cfg = HuntFun.Prizes
	local out: { [number]: Prize } = {}
	if not cfg.Enabled or winner == nil then
		return out
	end
	out[winner] = { Place = 1, Medal = cfg.Medals[1], Coins = 0, Xp = 0 }
	local rest: { Racer } = {}
	for _, r in racers do
		if r.UserId ~= winner and (tonumber(r.Eggs) or 0) >= cfg.MinEggs then
			table.insert(rest, r)
		end
	end
	table.sort(rest, function(a, b)
		if a.Eggs ~= b.Eggs then
			return a.Eggs > b.Eggs
		end
		return a.UserId < b.UserId
	end)
	local f = zoneFactor(tierId) / 2
	local place = 1
	for i, r in rest do
		if i == 1 or r.Eggs ~= rest[i - 1].Eggs then
			place = i + 1
		end
		local at = math.min(place, #cfg.Medals)
		local eggs = math.min(math.floor(r.Eggs), cfg.MaxEggs)
		out[r.UserId] = {
			Place = place,
			Medal = cfg.Medals[at],
			Coins = math.max(1, math.floor((cfg.Coins[at] + cfg.CoinsPerEgg * eggs) * f + 0.5)),
			Xp = cfg.Xp[at],
		}
	end
	return out
end

-- Surprise pop placement (client SurprisePop), in screen shares (0..1). Studio 2026-10-15: pops over the nest were
-- behind the first-person camera, and pops in front of the camera in the world drifted over the top-left clock card.
-- They are screen pops now, right of centre, clear of the clock card (top left), the action button (bottom right) and
-- the crosshair; up to three in the air at once, in different rows.
HuntFun.PopSpots = { Vector2.new(0.68, 0.42), Vector2.new(0.68, 0.32), Vector2.new(0.68, 0.64) }

function HuntFun.popScreen(n: number): Vector2
	local spots = HuntFun.PopSpots
	return spots[(math.max(math.floor(n), 0) % #spots) + 1]
end

export type TargetCand = { Id: number, Pos: Vector3 }

-- Which pickable egg in reach the action takes (client PileView auto target, third person): the nearest, the one the
-- avatar and camera face preferred. `priority` = the gold overtime egg: when it is in reach it always wins (Studio
-- 2026-10-15: the glowing egg lay alone at the pile edge 3 studs away, but eggs the player faced won every time, so
-- the round sat at 0:00). The glow is public by then (EggConfig.Overtime), so this gives nothing away.
function HuntFun.pickTarget(cands: { TargetCand }, rp: Vector3, look: Vector3, camLook: Vector3, limit: number, priority: number?): number?
	local best, bestScore = nil, math.huge
	for _, c in cands do
		local pos = c.Pos
		local dx, dz = pos.X - rp.X, pos.Z - rp.Z
		local d = math.sqrt(dx * dx + dz * dz)
		if d <= limit then
			if c.Id == priority then
				return c.Id
			end
			local facing = if d > 0.01 then (look.X * dx + look.Z * dz) / d else 1
			local aim = if d > 0.01 then (camLook.X * dx + camLook.Z * dz) / d else 1
			local score = d - facing * 3 - aim * 1.5 + pos.Y * -0.05
			if score < bestScore then
				best, bestScore = c.Id, score
			end
		end
	end
	return best
end

return HuntFun
