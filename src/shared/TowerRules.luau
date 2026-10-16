--!strict
-- Pet Tower fight rules (pure, deterministic, tested in tests/test_pet_tower.luau).
-- The server steps this; clients only see the events it returns. Pets attack on their own; each player can fire
-- their team's SPECIAL when their meter is full. A fainted pet stays fainted for the rest of the run.

local TowerConfig = require(script.Parent.TowerConfig)
local PetStats = require(script.Parent.PetStats)

local TowerRules = {}

export type Unit = {
	Id: string,
	Owner: number, -- player UserId for pets, 0 for mobs
	Kind: string, -- species id or mob id
	Name: string,
	Max: number,
	Hp: number,
	Power: number,
	Speed: number,
	Cd: number, -- seconds until the next attack
	Shield: number,
	BurnDps: number,
	BurnLeft: number,
	Special: string?,
	Boss: boolean,
	Element: string,
	MoveMult: number, -- second attack (1 for mobs = no second attack)
	MoveSlow: number,
	Swing: number, -- attack counter; pets alternate basic attack and type move
}
export type Event = { Kind: string, From: string?, To: string?, Amount: number?, Owner: number?, Id: string? }
export type Run = {
	Floor: number,
	Wave: number,
	Waves: { { string } },
	Players: number,
	Pets: { Unit },
	Mobs: { Unit },
	Meters: { [number]: number },
	SlowLeft: number,
	FloorTime: number,
	State: string, -- "Fighting" | "Cleared" | "Lost"
	MobSerial: number,
}
export type TeamPet = { Owner: number, Id: string, Name: string?, Xp: number?, Pet: { Mineral: string, Rarity: string, Modifier: string?, Seed: number } }

function TowerRules.isBoss(floor: number): boolean
	return floor % TowerConfig.BossEvery == 0
end

-- Theme of a floor: jungle 1-10, lava 11-20, ice 21-30, space 31-40, then loops.
function TowerRules.theme(floor: number)
	local n = math.max(math.ceil(floor / TowerConfig.ThemeEvery), 1)
	return TowerConfig.Themes[(n - 1) % #TowerConfig.Themes + 1]
end

-- Seconds the fight waits before it starts on this floor and wave: only the first wave of a new theme (its title
-- pill shows first, then the pets fight); every other wave starts at once.
function TowerRules.introHold(floor: number, wave: number): number
	if wave == 1 and (floor - 1) % TowerConfig.ThemeEvery == 0 then
		return TowerConfig.TitleHold
	end
	return 0
end

-- Bands repeat (endless tower); the returned index keeps counting so boss rewards keep growing.
function TowerRules.band(floor: number)
	local n = math.max(math.ceil(floor / TowerConfig.BossEvery), 1)
	return TowerConfig.Bands[(n - 1) % #TowerConfig.Bands + 1], n
end

-- The checkpoint a player restarts from after reaching `best` (floor 1, 6, 11, ...).
function TowerRules.checkpoint(best: number): number
	local cleared = math.max(math.floor(best), 0)
	return math.floor(cleared / TowerConfig.BossEvery) * TowerConfig.BossEvery + 1
end

-- Mob ids per wave. Deterministic by floor so every run of a floor is the same puzzle.
function TowerRules.waves(floor: number): { { string } }
	local band = TowerRules.band(floor)
	local within = (floor - 1) % TowerConfig.BossEvery + 1 -- 1..5
	local out = {}
	if TowerRules.isBoss(floor) then
		table.insert(out, { band.Mobs[1], band.Mobs[2] })
		table.insert(out, { band.Boss })
		return out
	end
	local waveCount = if within <= 2 then 1 elseif within <= 3 then 2 else 3
	for w = 1, waveCount do
		local wave = {}
		local size = math.min(1 + math.floor((within + w) / 2), 4)
		for m = 1, size do
			table.insert(wave, band.Mobs[(floor + w + m) % #band.Mobs + 1])
		end
		table.insert(out, wave)
	end
	return out
end

function TowerRules.mobStats(mobId: string, floor: number, players: number): (number, number, number)
	local mob = TowerConfig.Mobs[mobId]
	assert(mob, "unknown mob " .. mobId)
	local grow = 1 + TowerConfig.FloorGrowth * (floor - 1)
	local party = 1 + TowerConfig.PartyHealthPerPlayer * (math.clamp(players, 1, TowerConfig.MaxPlayers) - 1)
	return math.floor(mob.Health * grow * party + 0.5), math.floor(mob.Power * grow * 10 + 0.5) / 10, mob.Speed
end

function TowerRules.reward(floor: number): number
	local coins = TowerConfig.Rewards.CoinsPerFloor * floor
	if TowerRules.isBoss(floor) then
		local _, bandIndex = TowerRules.band(floor)
		coins += TowerConfig.Rewards.BossCoins * bandIndex
	end
	return coins
end

-- XP each team pet earns for clearing `floor` (a loss earns LossShare of it).
function TowerRules.xp(floor: number, cleared: boolean): number
	local x = TowerConfig.Xp.PerFloor + TowerConfig.Xp.FloorStep * floor
	return if cleared then x else math.floor(x * TowerConfig.Xp.LossShare)
end

-- Boss drop chance on a boss floor clear (0 elsewhere) and which tower-only pet a 0..1 pick lands on.
-- `misses` = boss clears in a row without a drop (profile TowerPity): each adds Pity.PerMiss, and after
-- Pity.GuaranteeAfter misses the drop is certain.
function TowerRules.dropChance(floor: number, misses: number?): number
	if not TowerRules.isBoss(floor) then
		return 0
	end
	local d = TowerConfig.Drop
	local base = math.min(d.Chance + d.PerFloor * floor, d.Max)
	local m = math.max(math.floor(tonumber(misses) or 0), 0)
	if m >= TowerConfig.Pity.GuaranteeAfter then
		return 1
	end
	return math.min(base + TowerConfig.Pity.PerMiss * m, 1)
end

-- The pity counter after a boss clear: back to 0 on a drop, +1 on a miss.
function TowerRules.pityAfter(misses: number?, dropped: boolean): number
	if dropped then
		return 0
	end
	return math.max(math.floor(tonumber(misses) or 0), 0) + 1
end

-- `owned` (species -> truthy, e.g. the discovery index) favours tower pets the player never had: when any pet
-- allowed on this floor is new, only new ones can drop (each weighs at least Pity.MinNewWeight).
function TowerRules.dropSpecies(floor: number, pick: number, owned: { [string]: any }?): string?
	local function isNew(id: string): boolean
		local v = owned and owned[id]
		return not (v == true or (type(v) == "number" and v > 0))
	end
	local onlyNew = false
	if owned then
		for _, tp in TowerConfig.TowerPets do
			if floor >= tp.From and isNew(tp.Id) then
				onlyNew = true
				break
			end
		end
	end
	local function weight(tp): number
		if floor < tp.From then
			return 0
		end
		if onlyNew then
			return if isNew(tp.Id) then math.max(tp.Weight, TowerConfig.Pity.MinNewWeight) else 0
		end
		return tp.Weight
	end
	local total = 0
	for _, tp in TowerConfig.TowerPets do
		total += weight(tp)
	end
	if total <= 0 then
		return nil
	end
	local roll = math.clamp(pick, 0, 0.999999) * total
	for _, tp in TowerConfig.TowerPets do
		local w = weight(tp)
		if w > 0 then
			roll -= w
			if roll < 0 then
				return tp.Id
			end
		end
	end
	return nil
end

-- The zone a tower drop is priced in: the player's best unlocked zone (`order` = zone ids from first to last,
-- `unlocked` = zone id -> true), so a drop is never worth more than a hunt pet the player can already find.
function TowerRules.dropTier(order: { string }, unlocked: { [string]: any }?): string
	local tier = order[1]
	if type(unlocked) == "table" then
		for _, id in order do
			if unlocked[id] then
				tier = id
			end
		end
	end
	return tier
end

-- Brings a lost floor back: every team pet returns at Revive.Health of max, the timer restarts, mobs keep theirs.
function TowerRules.revive(run: Run): boolean
	if run.State ~= "Lost" or #run.Pets == 0 or #run.Mobs == 0 then
		return false
	end
	for _, p in run.Pets do
		p.Hp = math.max(p.Hp, math.floor(p.Max * TowerConfig.Revive.Health + 0.5))
		p.Shield = 0
	end
	run.FloorTime = 0
	run.State = "Fighting"
	return true
end

local function spawnWave(run: Run)
	run.Mobs = {}
	for _, mobId in run.Waves[run.Wave] do
		local hp, power, speed = TowerRules.mobStats(mobId, run.Floor, run.Players)
		run.MobSerial += 1
		table.insert(run.Mobs, {
			Id = "m" .. run.MobSerial,
			Owner = 0,
			Kind = mobId,
			Name = TowerConfig.Mobs[mobId].Name,
			Max = hp,
			Hp = hp,
			Power = power,
			Speed = speed,
			Cd = 0.6 + 0.15 * #run.Mobs, -- stagger the first hits
			Shield = 0,
			BurnDps = 0,
			BurnLeft = 0,
			Special = nil,
			Boss = TowerConfig.Mobs[mobId].Boss,
			Element = TowerConfig.Mobs[mobId].Element,
			MoveMult = 1,
			MoveSlow = 1,
			Swing = 0,
		})
	end
end

-- Builds a run from the players' chosen pets (at most TeamSize per player, MaxPlayers players).
function TowerRules.newRun(team: { TeamPet }, floor: number): Run
	local pets: { Unit } = {}
	local perOwner: { [number]: number } = {}
	local owners = 0
	for _, tp in team do
		local n = perOwner[tp.Owner]
		if n == nil then
			if owners >= TowerConfig.MaxPlayers then
				continue
			end
			owners += 1
			n = 0
		end
		if n >= TowerConfig.TeamSize then
			continue
		end
		perOwner[tp.Owner] = n + 1
		local s = PetStats.roll(tp.Pet, tp.Xp)
		table.insert(pets, {
			Id = tp.Id,
			Owner = tp.Owner,
			Kind = tp.Pet.Mineral,
			Name = tp.Name or tp.Pet.Mineral,
			Max = s.Health,
			Hp = s.Health,
			Power = s.Power,
			Speed = s.Speed,
			Cd = 0.3 + 0.1 * #pets,
			Shield = 0,
			BurnDps = 0,
			BurnLeft = 0,
			Special = s.Special,
			Boss = false,
			Element = s.Element,
			MoveMult = s.MoveMult,
			MoveSlow = s.MoveSlow,
			Swing = 0,
		})
	end
	local meters = {}
	for owner in perOwner do
		meters[owner] = 0
	end
	local run: Run = {
		Floor = 0,
		Wave = 0,
		Waves = {},
		Players = math.max(owners, 1),
		Pets = pets,
		Mobs = {},
		Meters = meters,
		SlowLeft = 0,
		FloorTime = 0,
		State = "Lost",
		MobSerial = 0,
	}
	if #pets > 0 then
		TowerRules.startFloor(run, floor)
	end
	return run
end

-- Next floor of the same run: fainted pets stay fainted, the rest keep their health.
function TowerRules.startFloor(run: Run, floor: number)
	run.Floor = math.max(math.floor(floor), 1)
	run.Waves = TowerRules.waves(run.Floor)
	run.Wave = 1
	run.FloorTime = 0
	run.SlowLeft = 0
	run.State = "Fighting"
	spawnWave(run)
end

local function alive(list: { Unit }): { Unit }
	local out = {}
	for _, u in list do
		if u.Hp > 0 then
			table.insert(out, u)
		end
	end
	return out
end

local function hurt(target: Unit, amount: number, from: string, events: { Event }, element: string?): number
	local eff = if element then PetStats.effect(element, target.Element) else 1
	local dmg = math.max(math.floor(amount * eff + 0.5), 1)
	local absorbed = math.min(target.Shield, dmg)
	target.Shield -= absorbed
	local real = math.min(dmg - absorbed, target.Hp)
	target.Hp -= real
	-- Id carries the type result so clients can pop "Super hit!" / "Weak..." like Pokemon.
	local note = if eff > 1 then "Strong" elseif eff < 1 then "Weak" else nil
	table.insert(events, { Kind = "Hit", From = from, To = target.Id, Amount = dmg, Id = note })
	if target.Hp <= 0 then
		table.insert(events, { Kind = "Faint", To = target.Id })
	end
	return real
end

local function charge(run: Run, owner: number, dealt: number)
	if run.Meters[owner] ~= nil then
		run.Meters[owner] = math.min(run.Meters[owner] + dealt, TowerConfig.SpecialCharge)
	end
end

local function settle(run: Run, events: { Event })
	if #alive(run.Pets) == 0 then
		run.State = "Lost"
		table.insert(events, { Kind = "Lost" })
	elseif #alive(run.Mobs) == 0 then
		if run.Wave < #run.Waves then
			run.Wave += 1
			spawnWave(run)
			table.insert(events, { Kind = "Wave", Amount = run.Wave })
		else
			run.State = "Cleared"
			table.insert(events, { Kind = "Cleared", Amount = run.Floor })
		end
	end
end

function TowerRules.step(run: Run, dt: number): { Event }
	local events: { Event } = {}
	if run.State ~= "Fighting" then
		return events
	end
	run.FloorTime += dt
	if run.FloorTime >= TowerConfig.FloorTimeLimit then
		run.State = "Lost"
		table.insert(events, { Kind = "Lost", Id = "Time" })
		return events
	end
	run.SlowLeft = math.max(run.SlowLeft - dt, 0)

	for _, m in alive(run.Mobs) do
		if m.BurnLeft > 0 then
			local tick = math.min(dt, m.BurnLeft)
			m.BurnLeft -= tick
			m.Hp = math.max(m.Hp - m.BurnDps * tick, 0)
			if m.Hp <= 0 then
				table.insert(events, { Kind = "Faint", To = m.Id })
			end
		end
	end

	for _, p in alive(run.Pets) do
		p.Cd -= dt
		if p.Cd <= 0 then
			local target = alive(run.Mobs)[1]
			if target == nil then
				break
			end
			p.Swing += 1
			local useMove = p.Swing % 2 == 0
			p.Cd += 100 / p.Speed * (if useMove then p.MoveSlow else 1)
			local amount = p.Power * (if useMove then p.MoveMult else 1)
			charge(run, p.Owner, hurt(target, amount, p.Id, events, p.Element))
		end
	end

	local mobRate = if run.SlowLeft > 0 then 0.5 else 1
	for i, m in alive(run.Mobs) do
		m.Cd -= dt * mobRate
		if m.Cd <= 0 then
			local pets = alive(run.Pets)
			if #pets == 0 then
				break
			end
			m.Cd += 100 / m.Speed
			-- Bosses go for the strongest pet; normal mobs spread out across the team.
			local target = pets[(i - 1) % #pets + 1]
			if m.Boss then
				for _, p in pets do
					if p.Hp > target.Hp then
						target = p
					end
				end
			end
			hurt(target, m.Power, m.Id, events, m.Element)
		end
	end

	settle(run, events)
	return events
end

function TowerRules.meterFull(run: Run, owner: number): boolean
	return (run.Meters[owner] or 0) >= TowerConfig.SpecialCharge
end

-- Fires the owner's SPECIAL with their strongest living pet's special. `pick` (0..1) only matters for Lucky Hit.
function TowerRules.useSpecial(run: Run, owner: number, pick: number?): (boolean, { Event })
	local events: { Event } = {}
	if run.State ~= "Fighting" or not TowerRules.meterFull(run, owner) then
		return false, events
	end
	local caster: Unit? = nil
	for _, p in alive(run.Pets) do
		if p.Owner == owner and (caster == nil or p.Power > caster.Power) then
			caster = p
		end
	end
	if caster == nil or caster.Special == nil then
		return false, events
	end
	local sp = PetStats.special(caster.Special)
	if sp == nil then
		return false, events
	end
	run.Meters[owner] = 0
	table.insert(events, { Kind = "Special", Owner = owner, From = caster.Id, Id = sp.Id })
	local mobs = alive(run.Mobs)
	local power = caster.Power
	if sp.Kind == "Burn" then
		for _, m in mobs do
			m.BurnDps, m.BurnLeft = sp.Value * power, 4
		end
	elseif sp.Kind == "Slow" then
		run.SlowLeft = sp.Value
	elseif sp.Kind == "Chain" then
		for i = 1, math.min(3, #mobs) do
			hurt(mobs[i], sp.Value * power, caster.Id, events, caster.Element)
		end
	elseif sp.Kind == "Heal" then
		for _, p in alive(run.Pets) do
			p.Hp = math.min(p.Max, p.Hp + math.floor(p.Max * sp.Value + 0.5))
		end
	elseif sp.Kind == "Shield" then
		for _, p in alive(run.Pets) do
			p.Shield = math.max(p.Shield, math.floor(p.Max * sp.Value + 0.5))
		end
	elseif sp.Kind == "Stomp" then
		for _, m in mobs do
			hurt(m, sp.Value * power, caster.Id, events, caster.Element)
		end
	elseif sp.Kind == "Dash" then
		if mobs[1] then
			hurt(mobs[1], sp.Value * power, caster.Id, events, caster.Element)
		end
	elseif sp.Kind == "Crit" then
		if #mobs > 0 then
			local i = math.clamp(math.floor((pick or 0) * #mobs) + 1, 1, #mobs)
			hurt(mobs[i], sp.Value * power, caster.Id, events, caster.Element)
		end
	end
	settle(run, events)
	return true, events
end

-- Plays a floor to the end with specials fired as soon as they are ready (tests and balance checks).
function TowerRules.simulate(run: Run, maxSeconds: number?): string
	local t = 0
	local limit = maxSeconds or TowerConfig.FloorTimeLimit + 1
	while run.State == "Fighting" and t < limit do
		TowerRules.step(run, TowerConfig.Tick)
		for owner in run.Meters do
			TowerRules.useSpecial(run, owner, 0.5)
		end
		t += TowerConfig.Tick
	end
	return run.State
end

return TowerRules
