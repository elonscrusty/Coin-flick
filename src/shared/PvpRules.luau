--!strict
-- Pet Battle rules (pure, deterministic given the `rand` function; tested in tests/test_pvp.luau).
-- Two sides of up to 3 pets fight in real time like the tower: every pet attacks on its own, alternating its basic
-- attack and its type move; each side fires SPECIAL when its meter is full. Types work as in the tower (PetStats.effect).
-- The server steps a fight and sends the events; clients only draw them.

local PvpConfig = require(script.Parent.PvpConfig)
local TowerConfig = require(script.Parent.TowerConfig)
local PetStats = require(script.Parent.PetStats)

local PvpRules = {}

export type Pet = { Mineral: string, Rarity: string, Modifier: string?, Seed: number }
export type TeamPet = { Id: string, Name: string?, Xp: number?, Pet: Pet }
export type Unit = {
	Id: string,
	Side: number, -- 1 or 2
	Kind: string, -- species id
	Rarity: string,
	Name: string,
	Max: number,
	Hp: number,
	Power: number,
	Speed: number,
	Cd: number,
	Shield: number,
	BurnDps: number,
	BurnLeft: number,
	Special: string?,
	Element: string,
	MoveMult: number,
	MoveSlow: number,
	Swing: number,
	Warned: boolean, -- a ring is up for this pet's next type move (Warn sent)
	Guarded: boolean, -- the other side blocked that move in time
}
export type Event = {
	Kind: string, From: string?, To: string?, Amount: number?, Side: number?, Id: string?, Crit: boolean?, Combo: number?,
}
export type Fight = {
	Units: { Unit },
	Meters: { number }, -- [side]
	Slow: { number }, -- [side] seconds that side still attacks at half speed
	Time: number,
	State: string, -- "Fighting" | "Done"
	Winner: number, -- 0 = draw (or not done), else the winning side
	Pool: { number }, -- [side] total max health of the OTHER side (the SPECIAL meter fills by share of it)
	Turn: number, -- steps so far: on a tie the side that strikes first alternates (no side edge)
	Combo: { number }, -- [side] tap combo (PvpConfig.Tap)
	LastTap: { number }, -- [side] fight time of the last tap
	BlockLock: { number }, -- [side] fight time until which BLOCK is locked after a miss
}

-- THE power number of one pet (matchmaking, team cards, training level-ups). One place to change it.
function PvpRules.petPower(s: { Power: number, Health: number, Speed: number }): number
	return PetStats.power(s) -- the Pet Book's POWER (PetStats.power): one formula for the whole game
end

function PvpRules.power(pet: Pet, xp: number?): number
	return PvpRules.petPower(PetStats.roll(pet, xp))
end

function PvpRules.teamPower(team: { TeamPet }): number
	local sum = 0
	for i, tp in team do
		if i > PvpConfig.TeamSize then
			break
		end
		sum += PvpRules.power(tp.Pet, tp.Xp)
	end
	return sum
end

-- How far apart (share of the bigger power) two teams may be after waiting `waited` seconds.
function PvpRules.window(waited: number): number
	return PvpConfig.Window.Start + PvpConfig.Window.PerSecond * math.max(waited, 0)
end

-- Two waiting players always beat a bot: once either has waited BotAfter seconds (when the bot would step in), any
-- power gap is fine (Studio 2026-10-14: two testers, one with a maxed team, both got bots seconds apart).
function PvpRules.canMatch(powerA: number, waitedA: number, powerB: number, waitedB: number): boolean
	if math.max(waitedA, waitedB) >= PvpConfig.BotAfter then
		return true
	end
	local big = math.max(powerA, powerB, 1)
	local gap = math.abs(powerA - powerB) / big
	return gap <= math.max(PvpRules.window(waitedA), PvpRules.window(waitedB))
end

-- Species a bot may field: every egg pet with stats (tower-only drops are left out).
local botSpecies: { string } = {}
do
	local towerOnly = {}
	for _, tp in TowerConfig.TowerPets do
		towerOnly[tp.Id] = true
	end
	for id in TowerConfig.Species do
		if not towerOnly[id] then
			table.insert(botSpecies, id)
		end
	end
	table.sort(botSpecies)
end

-- A bot team for `team`: same rarities, variants and levels, other species and seeds. Of BotTries rolls, the one
-- whose power is closest to BotPower x the player's is kept.
function PvpRules.botTeam(team: { TeamPet }, rand: () -> number): { TeamPet }
	local target = PvpRules.teamPower(team) * PvpConfig.BotPower
	local best: { TeamPet }? = nil
	local bestGap = math.huge
	for _ = 1, PvpConfig.BotTries do
		local out: { TeamPet } = {}
		for i, tp in team do
			if i > PvpConfig.TeamSize then
				break
			end
			local species = botSpecies[math.clamp(math.floor(rand() * #botSpecies) + 1, 1, #botSpecies)]
			table.insert(out, {
				Id = "bot" .. i,
				Name = TowerConfig.PetNames[species] or species,
				Xp = tp.Xp,
				Pet = { Mineral = species, Rarity = tp.Pet.Rarity, Modifier = tp.Pet.Modifier, Seed = math.floor(rand() * 2 ^ 30) + 1 },
			})
		end
		local gap = math.abs(PvpRules.teamPower(out) - target)
		if gap < bestGap then
			best, bestGap = out, gap
		end
	end
	return best or {}
end

-- How much faster than its plain level-1 self a pet attacks (level, rarity, variant and evolve all add speed). Battle
-- health grows by the same factor, so a trained rare team's fight lasts about as long as a fresh common one's
-- (balance sim: maxed legendary fights were over in 6 s); who is stronger is unchanged.
local function speedGrowth(pet: Pet, s: PetStats.Stats): number
	local plain = PetStats.roll({ Mineral = pet.Mineral, Rarity = "Common", Modifier = "Natural", Seed = pet.Seed }, 0)
	return math.max(s.Speed / math.max(plain.Speed, 1), 1)
end

local function unit(tp: TeamPet, side: number, slot: number): Unit
	local s = PetStats.roll(tp.Pet, tp.Xp)
	local hp = s.Health * PvpConfig.HealthMult * speedGrowth(tp.Pet, s)
	return {
		Id = tp.Id,
		Side = side,
		Kind = tp.Pet.Mineral,
		Rarity = tp.Pet.Rarity,
		Name = tp.Name or (TowerConfig.PetNames[tp.Pet.Mineral] or tp.Pet.Mineral),
		Max = hp,
		Hp = hp,
		Power = s.Power,
		Speed = s.Speed,
		Cd = 0.3 + 0.12 * slot, -- both sides alike: ties are broken fairly in step (Turn)
		Shield = 0,
		BurnDps = 0,
		BurnLeft = 0,
		Special = s.Special,
		Element = s.Element,
		MoveMult = s.MoveMult,
		MoveSlow = s.MoveSlow,
		Swing = 0,
		Warned = false,
		Guarded = false,
	}
end

function PvpRules.newFight(a: { TeamPet }, b: { TeamPet }): Fight
	local units: { Unit } = {}
	for side, team in { a, b } do
		for i, tp in team do
			if i > PvpConfig.TeamSize then
				break
			end
			table.insert(units, unit(tp, side, i))
		end
	end
	local max = { 0, 0 }
	for _, u in units do
		max[u.Side] += u.Max
	end
	return {
		Units = units, Meters = { 0, 0 }, Slow = { 0, 0 }, Time = 0, State = "Fighting", Winner = 0,
		Pool = { math.max(max[2], 1), math.max(max[1], 1) }, Turn = 0,
		Combo = { 0, 0 }, LastTap = { -math.huge, -math.huge }, BlockLock = { -math.huge, -math.huge },
	}
end

function PvpRules.alive(f: Fight, side: number): { Unit }
	local out = {}
	for _, u in f.Units do
		if u.Side == side and u.Hp > 0 then
			table.insert(out, u)
		end
	end
	return out
end

-- Share of max health a side has left (0..1).
function PvpRules.healthShare(f: Fight, side: number): number
	local hp, max = 0, 0
	for _, u in f.Units do
		if u.Side == side then
			hp += u.Hp
			max += u.Max
		end
	end
	return if max > 0 then hp / max else 0
end

local function hurt(target: Unit, amount: number, from: string, events: { Event }, element: string, crit: boolean?): number
	local eff = PetStats.effect(element, target.Element)
	local dmg = math.max(math.floor(amount * eff + 0.5), 1)
	local absorbed = math.min(target.Shield, dmg)
	target.Shield -= absorbed
	local real = math.min(dmg - absorbed, target.Hp)
	target.Hp -= real
	local note = if eff > 1 then "Strong" elseif eff < 1 then "Weak" else nil
	table.insert(events, { Kind = "Hit", From = from, To = target.Id, Amount = dmg, Id = note, Crit = if crit then true else nil })
	if target.Hp <= 0 then
		table.insert(events, { Kind = "Faint", To = target.Id })
	end
	return real
end

-- The meter fills after dealing PvpConfig.SpecialShare of the other team's total max health (meter units stay
-- 0..SpecialCharge). A flat damage number filled at once for trained, rare teams, so their fights were all SPECIALs
-- and over in seconds (balance sim, tests/test_pvp_balance.luau).
local function charge(f: Fight, side: number, dealt: number)
	local gain = dealt / f.Pool[side] / PvpConfig.SpecialShare * PvpConfig.SpecialCharge
	f.Meters[side] = math.min(f.Meters[side] + gain, PvpConfig.SpecialCharge)
end

-- A pet hits the first standing foe it is strong against, else the first standing foe.
local function pickTarget(foes: { Unit }, element: string): Unit?
	for _, u in foes do
		if PetStats.effect(element, u.Element) > 1 then
			return u
		end
	end
	return foes[1]
end

local function finish(f: Fight, winner: number, events: { Event })
	f.State = "Done"
	f.Winner = winner
	table.insert(events, { Kind = "KO", Side = winner })
end

local function settle(f: Fight, events: { Event })
	if f.State ~= "Fighting" then
		return
	end
	local a, b = #PvpRules.alive(f, 1), #PvpRules.alive(f, 2)
	if a == 0 and b == 0 then
		finish(f, 0, events)
	elseif a == 0 then
		finish(f, 2, events)
	elseif b == 0 then
		finish(f, 1, events)
	end
end

-- One fight step. `rand` returns 0..1 (crits); the server passes math.random, tests a seeded stream.
function PvpRules.step(f: Fight, dt: number, rand: () -> number): { Event }
	local events: { Event } = {}
	if f.State ~= "Fighting" then
		return events
	end
	f.Time += dt
	if f.Time >= PvpConfig.FightTime then
		local a, b = PvpRules.healthShare(f, 1), PvpRules.healthShare(f, 2)
		table.insert(events, { Kind = "TimeUp" })
		finish(f, if a > b then 1 elseif b > a then 2 else 0, events)
		return events
	end
	for side = 1, 2 do
		f.Slow[side] = math.max(f.Slow[side] - dt, 0)
	end
	for _, u in f.Units do
		if u.Hp > 0 and u.BurnLeft > 0 then
			local tick = math.min(dt, u.BurnLeft)
			u.BurnLeft -= tick
			u.Hp = math.max(u.Hp - u.BurnDps * tick, 0)
			if u.Hp <= 0 then
				table.insert(events, { Kind = "Faint", To = u.Id })
			end
		end
	end
	-- who is due this step strikes in the order they came due (most overdue first); on a tie the first side
	-- alternates step by step, so neither side always lands the first blow (mirror fights split evenly)
	f.Turn += 1
	local due: { Unit } = {}
	for _, u in f.Units do
		if u.Hp > 0 then
			u.Cd -= dt * (if f.Slow[u.Side] > 0 then 0.5 else 1)
			if u.Cd <= 0 then
				table.insert(due, u)
			elseif not u.Warned and (u.Swing + 1) % 2 == 0 and u.Cd <= PvpConfig.Block.WarnTime then
				-- the next swing is the big type move: ring up on the other side so its player can BLOCK it
				local target = pickTarget(PvpRules.alive(f, 3 - u.Side), u.Element)
				if target then
					u.Warned = true
					table.insert(events, { Kind = "Warn", From = u.Id, To = target.Id, Side = 3 - u.Side })
				end
			end
		end
	end
	local first = f.Turn % 2 + 1
	table.sort(due, function(x: Unit, y: Unit): boolean
		if math.abs(x.Cd - y.Cd) > 1e-6 then
			return x.Cd < y.Cd
		end
		if x.Side ~= y.Side then
			return x.Side == first
		end
		return x.Id < y.Id
	end)
	for _, u in due do
		if u.Hp > 0 then
			local foes = PvpRules.alive(f, 3 - u.Side)
			local target = pickTarget(foes, u.Element)
			if target == nil then
				break
			end
			u.Swing += 1
			local useMove = u.Swing % 2 == 0
			u.Cd += 100 / u.Speed * (if useMove then u.MoveSlow else 1)
			local crit = rand() < PvpConfig.CritChance
			local amount = u.Power * (if useMove then u.MoveMult else 1) * (if crit then PvpConfig.CritMult else 1)
			if useMove then
				if u.Guarded then
					amount *= 1 - PvpConfig.Block.Cut
					local side = 3 - u.Side
					f.Meters[side] = math.min(f.Meters[side] + PvpConfig.Block.PerfectCharge, PvpConfig.SpecialCharge)
					table.insert(events, { Kind = "Perfect", From = u.Id, To = target.Id, Side = side })
				end
				u.Warned, u.Guarded = false, false
			end
			charge(f, u.Side, hurt(target, amount, u.Id, events, u.Element, crit))
		end
	end
	settle(f, events)
	return events
end

function PvpRules.meterFull(f: Fight, side: number): boolean
	return (f.Meters[side] or 0) >= PvpConfig.SpecialCharge
end

local function rarityIndex(r: string): number
	return table.find(TowerConfig.Rarities, r) or 1
end

-- Only Epic+ pets bring a SPECIAL to a battle (TowerConfig.SpecialMinRarity). The caster is the strongest standing one.
local function caster(f: Fight, side: number): Unit?
	local best: Unit? = nil
	for _, u in PvpRules.alive(f, side) do
		if u.Special ~= nil and rarityIndex(u.Rarity) >= TowerConfig.SpecialMinRarity and (best == nil or u.Power > best.Power) then
			best = u
		end
	end
	return best
end

-- True while `side` has a standing pet that can fire SPECIAL.
function PvpRules.hasSpecial(f: Fight, side: number): boolean
	return caster(f, side) ~= nil
end

-- Fires `side`'s SPECIAL with its strongest standing Epic+ pet's special (TowerConfig.Specials, aimed at the other side).
function PvpRules.useSpecial(f: Fight, side: number, pick: number?): (boolean, { Event })
	local events: { Event } = {}
	if f.State ~= "Fighting" or (side ~= 1 and side ~= 2) or not PvpRules.meterFull(f, side) then
		return false, events
	end
	local c = caster(f, side)
	if c == nil or c.Special == nil then
		return false, events
	end
	local sp = PetStats.special(c.Special)
	if sp == nil then
		return false, events
	end
	f.Meters[side] = 0
	table.insert(events, { Kind = "Special", Side = side, From = c.Id, Id = sp.Id })
	local foes = PvpRules.alive(f, 3 - side)
	local power = c.Power
	if sp.Kind == "Burn" then
		for _, m in foes do
			m.BurnDps, m.BurnLeft = sp.Value * power, 4
		end
	elseif sp.Kind == "Slow" then
		f.Slow[3 - side] = sp.Value
	elseif sp.Kind == "Chain" then
		for i = 1, math.min(3, #foes) do
			hurt(foes[i], sp.Value * power, c.Id, events, c.Element)
		end
	elseif sp.Kind == "Heal" then
		for _, p in PvpRules.alive(f, side) do
			p.Hp = math.min(p.Max, p.Hp + math.floor(p.Max * sp.Value + 0.5))
		end
	elseif sp.Kind == "Shield" then
		for _, p in PvpRules.alive(f, side) do
			p.Shield = math.max(p.Shield, math.floor(p.Max * sp.Value + 0.5))
		end
	elseif sp.Kind == "Stomp" then
		for _, m in foes do
			hurt(m, sp.Value * power, c.Id, events, c.Element)
		end
	elseif sp.Kind == "Dash" then
		if foes[1] then
			hurt(foes[1], sp.Value * power, c.Id, events, c.Element)
		end
	elseif sp.Kind == "Crit" then
		if #foes > 0 then
			local i = math.clamp(math.floor((pick or 0) * #foes) + 1, 1, #foes)
			hurt(foes[i], sp.Value * power, c.Id, events, c.Element, true)
		end
	end
	settle(f, events)
	return true, events
end

-- Damage per second of a side's standing pets (basic and type move averaged; taps scale with it).
local function teamDps(f: Fight, side: number): number
	local dps = 0
	for _, u in PvpRules.alive(f, side) do
		dps += u.Power * (1 + u.MoveMult) / 2 * u.Speed / 100 / ((1 + u.MoveSlow) / 2)
	end
	return dps
end

-- One TAP from `side` (rate limited by the server): a quick hit on the foe its strongest standing pet aims at,
-- growing with the tap combo. Fills the SPECIAL meter like any hit. Returns false when the fight is not on.
function PvpRules.tap(f: Fight, side: number): (boolean, { Event })
	local events: { Event } = {}
	if f.State ~= "Fighting" or (side ~= 1 and side ~= 2) then
		return false, events
	end
	local lead: Unit? = nil
	for _, u in PvpRules.alive(f, side) do
		if lead == nil or u.Power > lead.Power then
			lead = u
		end
	end
	local target = lead and pickTarget(PvpRules.alive(f, 3 - side), lead.Element)
	if lead == nil or target == nil then
		return false, events
	end
	local cfg = PvpConfig.Tap
	f.Combo[side] = if f.Time - f.LastTap[side] <= cfg.ComboGap then f.Combo[side] + 1 else 1
	f.LastTap[side] = f.Time
	local combo = f.Combo[side]
	local amount = teamDps(f, side) * cfg.Share * (1 + cfg.ComboStep * math.min(combo - 1, cfg.ComboMax))
	local before = #events
	charge(f, side, hurt(target, amount, lead.Id, events, lead.Element))
	-- the hit goes out as a Tap (its own small pop on the client, not a pet lunge)
	local e = events[before + 1]
	e.Kind, e.Side, e.Combo = "Tap", side, combo
	settle(f, events)
	return true, events
end

-- BLOCK from `side`: guards against the soonest rival type move that has its ring up. With no ring up it misses and
-- BLOCK stays locked for PvpConfig.Block.MissLock seconds. Returns true on a guard ("Blocked"; the PERFECT lands with
-- the move), false on a miss or a locked BLOCK.
function PvpRules.block(f: Fight, side: number): (boolean, { Event })
	local events: { Event } = {}
	if f.State ~= "Fighting" or (side ~= 1 and side ~= 2) or f.Time < f.BlockLock[side] then
		return false, events
	end
	local soonest: Unit? = nil
	for _, u in PvpRules.alive(f, 3 - side) do
		if u.Warned and not u.Guarded and (soonest == nil or u.Cd < soonest.Cd) then
			soonest = u
		end
	end
	if soonest == nil then
		f.BlockLock[side] = f.Time + PvpConfig.Block.MissLock
		table.insert(events, { Kind = "BlockMiss", Side = side, Amount = PvpConfig.Block.MissLock })
		return false, events
	end
	soonest.Guarded = true
	table.insert(events, { Kind = "Blocked", From = soonest.Id, Side = side })
	return true, events
end

-- Plays a fight to the end, both sides firing SPECIAL as soon as it is ready (tests and balance checks).
function PvpRules.simulate(f: Fight, rand: () -> number): number
	local t = 0
	while f.State == "Fighting" and t < PvpConfig.FightTime + 1 do
		PvpRules.step(f, TowerConfig.Tick, rand)
		for side = 1, 2 do
			PvpRules.useSpecial(f, side, rand())
		end
		t += TowerConfig.Tick
	end
	return f.Winner
end

export type Outcome = { Coins: number, Trophies: number, Xp: number, Streak: number }

-- What one side gets: `result` = "Win" | "Loss" | "Draw"; `trophies` and `streak` are the player's before the fight.
-- Trophies never go below 0.
function PvpRules.outcome(result: string, trophies: number, streak: number, vsBot: boolean): Outcome
	local R = PvpConfig.Rewards
	trophies = math.max(math.floor(trophies), 0)
	streak = math.max(math.floor(streak), 0)
	if result == "Win" then
		local s = streak + 1
		return {
			Coins = R.WinCoins + R.StreakCoins * math.min(s - 1, R.StreakCap),
			Trophies = if vsBot then R.BotWinTrophies else R.WinTrophies,
			Xp = R.WinXp,
			Streak = s,
		}
	elseif result == "Loss" then
		local lose = if vsBot then R.BotLossTrophies else R.LossTrophies
		return { Coins = R.LossCoins, Trophies = -math.min(lose, trophies), Xp = R.LossXp, Streak = 0 }
	end
	return { Coins = R.DrawCoins, Trophies = 0, Xp = R.LossXp, Streak = streak }
end

-- What the side that stayed gets when the rival leaves mid-fight: a real "Win" only once the fight has run
-- PvpConfig.ForfeitWinAfter seconds; a quit in the count-in or the first seconds pays a "Draw" (no trophies, no streak,
-- no free-egg progress), so a second account cannot feed wins by leaving at once.
function PvpRules.forfeitResult(phase: string, fightTime: number): string
	if phase == "Fighting" and type(fightTime) == "number" and fightTime >= PvpConfig.ForfeitWinAfter then
		return "Win"
	end
	return "Draw"
end

-- Rank for a trophy count: (rank, next rank or nil).
function PvpRules.rank(trophies: number)
	local cur, nxt = PvpConfig.Ranks[1], nil
	for i, r in PvpConfig.Ranks do
		if trophies >= r.Min then
			cur = r
			nxt = PvpConfig.Ranks[i + 1]
		end
	end
	return cur, nxt
end

-- Training: (level before, level after, new xp) for adding `gain` XP to `xp`; `cap` = PetStats.cap(pet).
function PvpRules.train(xp: number, gain: number, cap: number?): (number, number, number)
	local before = PetStats.level(xp, cap)
	local now = math.max(xp, 0) + math.max(gain, 0)
	return before, (PetStats.level(now, cap)), now
end

-- True when the pet cannot train any higher (its rarity's level cap).
function PvpRules.maxed(pet: Pet, xp: number?): boolean
	return (PetStats.level(xp, PetStats.cap(pet))) >= PetStats.cap(pet)
end

-- ARENA BOARD --------------------------------------------------------------------------------------------------

export type Win = { Winner: string, Loser: string, WinnerPower: number, LoserPower: number, Day: number }

-- How big a win is: the loser's team power over the winner's (above 1 = an upset).
function PvpRules.winScore(w: Win): number
	return w.LoserPower / math.max(w.WinnerPower, 1)
end

-- The day's biggest win after `cand` (a new day starts over); ties keep the older one.
function PvpRules.biggerWin(best: Win?, cand: Win): Win
	if best == nil or best.Day ~= cand.Day or PvpRules.winScore(cand) > PvpRules.winScore(best) then
		return cand
	end
	return best
end

-- EVOLVE -------------------------------------------------------------------------------------------------------

export type EvolvePet = { Id: string, Mineral: string, Rarity: string, Evolve: number?, Favorite: boolean? }

-- Can `pet` evolve? It must sit at its level cap, below the last stage, and the player must own Copies - 1 other
-- copies of the same species and rarity at the same stage that are free to use up: not `locked` (following, on the
-- plot, in the battle team), not favourites. Returns (ok, reason, the copies to use: lowest XP first).
-- reason: "Stage" (fully evolved), "Level" (not at the cap yet), "Copies" (not enough free copies).
function PvpRules.evolveCheck(pet: EvolvePet, xpOf: (string) -> number, inventory: { EvolvePet }, locked: { [string]: boolean }): (boolean, string?, { string }, number)
	local stage = PetStats.stage(pet)
	local free: { EvolvePet } = {}
	for _, g in inventory do
		if g.Id ~= pet.Id and g.Mineral == pet.Mineral and g.Rarity == pet.Rarity and PetStats.stage(g) == stage
			and not locked[g.Id] and g.Favorite ~= true then
			table.insert(free, g)
		end
	end
	table.sort(free, function(a, b)
		local xa, xb = xpOf(a.Id), xpOf(b.Id)
		if xa ~= xb then
			return xa < xb
		end
		return a.Id < b.Id
	end)
	local need = TowerConfig.Evolve.Copies - 1
	local use = {}
	for i = 1, math.min(need, #free) do
		table.insert(use, free[i].Id)
	end
	if stage >= TowerConfig.Evolve.MaxStage then
		return false, "Stage", use, #free
	end
	if not PvpRules.maxed(pet :: any, xpOf(pet.Id)) then
		return false, "Level", use, #free
	end
	if #use < need then
		return false, "Copies", use, #free
	end
	return true, nil, use, #free
end

-- Why a battle search ended without a fight -> the one line the player sees (audit F24: every exit has one clear
-- reason). nil = say nothing (the player is gone, or a fight is starting).
local UNQUEUE_TEXT: { [string]: string } = {
	Cancel = "Battle search cancelled.",
	Hunt = "Battle search stopped: you joined a hunt.",
	Busy = "Battle search stopped: finish what you are doing first.",
	NoTeam = "Battle search stopped: hatch a pet first! Pets fight in battles.",
}
function PvpRules.unqueueText(why: string?): string?
	return if why then UNQUEUE_TEXT[why] else nil
end

return PvpRules
