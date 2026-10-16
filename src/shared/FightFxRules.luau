--!strict
-- Fight effect rules, pure: no Roblox services, unit-tested in tests/test_fight_fx.luau. Client FightFx plays what
-- these say (the big fight moments, built from the techniques of the egg hatch show, client HatchShow).
--   * moment(kind, lowEffects, reducedMotion): how big each moment is. Kinds climb hit < advantage (type advantage)
--     < crit < levelup < special < ko. Reduce Motion drops the camera kick, shake and slow motion and softens the
--     flash; Low Effects halves the debris, stars and rings.
--   * screen gate: camera / flash / colour effects never stack faster than SCREEN_GAP, unless the new moment ranks
--     higher than the one still showing (a KO always gets through).
--   * chunkStep: one step of the hand-animated debris (gravity, ground bounce, settle), so slow motion slows it too.

local FightFxRules = {}

export type Moment = {
	Kind: string,
	Rank: number,
	Fov: number, -- degrees added to the view for a moment (the "slam")
	Shake: number, -- camera shake strength 0..1
	Flash: number, -- screen flash opacity 0..1
	Bloom: number, -- bloom spike intensity
	Tint: number, -- colour correction pop 0..1 (towards the moment's colour)
	Slow: number, -- time scale during the slow motion (1 = none)
	SlowTime: number, -- seconds of real time the slow motion lasts
	Rings: number, -- ground shockwave rings
	Chunks: number, -- debris chunks
	Stars: number, -- star burst particles
	Beam: boolean, -- a light beam (special: attacker to target; levelup / ko winner: up into the sky)
	Banner: string?, -- big screen word
	Pop: string?, -- small floating word over the target
}

local BASE: { [string]: Moment } = {
	hit = { Kind = "hit", Rank = 1, Fov = 0, Shake = 0.12, Flash = 0, Bloom = 0, Tint = 0, Slow = 1, SlowTime = 0, Rings = 0, Chunks = 0, Stars = 0, Beam = false },
	advantage = { Kind = "advantage", Rank = 2, Fov = 4, Shake = 0.35, Flash = 0.25, Bloom = 0.4, Tint = 0.35, Slow = 1, SlowTime = 0, Rings = 1, Chunks = 6, Stars = 14, Beam = false, Pop = "SUPER!" },
	crit = { Kind = "crit", Rank = 3, Fov = 7, Shake = 0.6, Flash = 0.45, Bloom = 0.8, Tint = 0.45, Slow = 1, SlowTime = 0, Rings = 2, Chunks = 10, Stars = 24, Beam = false },
	levelup = { Kind = "levelup", Rank = 4, Fov = 5, Shake = 0.3, Flash = 0.35, Bloom = 0.9, Tint = 0.4, Slow = 1, SlowTime = 0, Rings = 2, Chunks = 0, Stars = 40, Beam = true, Banner = "LEVEL UP!" },
	special = { Kind = "special", Rank = 5, Fov = 12, Shake = 0.9, Flash = 0.55, Bloom = 1.2, Tint = 0.6, Slow = 0.35, SlowTime = 0.3, Rings = 3, Chunks = 16, Stars = 50, Beam = true, Banner = "SPECIAL!" },
	ko = { Kind = "ko", Rank = 6, Fov = 16, Shake = 1, Flash = 0.65, Bloom = 1.4, Tint = 0.7, Slow = 0.22, SlowTime = 0.9, Rings = 4, Chunks = 22, Stars = 70, Beam = true, Banner = "K.O.!" },
}
-- Caps on the screen pop (Studio fight test 2026-10-14: the K.O. flash washed the scene near white).
FightFxRules.MAX_FLASH = 0.32
FightFxRules.MAX_BLOOM = 0.8

FightFxRules.KINDS = { "hit", "advantage", "crit", "levelup", "special", "ko" }
FightFxRules.MAX_CHUNKS = 24 -- pooled debris parts (whole client)

function FightFxRules.moment(kind: string, lowEffects: boolean?, reducedMotion: boolean?): Moment
	local m = table.clone(BASE[kind] or BASE.hit)
	if reducedMotion then
		m.Fov, m.Shake, m.Slow, m.SlowTime = 0, 0, 1, 0
		m.Flash *= 0.5
	end
	if lowEffects then
		m.Chunks = m.Chunks // 2
		m.Stars = m.Stars // 2
		m.Rings = if m.Rings > 0 then math.max(1, m.Rings // 2) else 0
		m.Bloom *= 0.5
	end
	m.Chunks = math.min(m.Chunks, FightFxRules.MAX_CHUNKS)
	return m
end

-- Screen effects gate. State is per client.
export type Gate = { Until: number, Rank: number }
FightFxRules.SCREEN_GAP = 0.18 -- s between two screen effects of the same or lower rank

function FightFxRules.newGate(): Gate
	return { Until = 0, Rank = 0 }
end

-- May a moment of `rank` use the screen at `now`? If yes the gate is taken for `hold` seconds.
function FightFxRules.takeScreen(g: Gate, rank: number, now: number, hold: number?): boolean
	if now < g.Until and rank <= g.Rank then
		return false
	end
	g.Until = now + math.max(hold or 0, FightFxRules.SCREEN_GAP)
	g.Rank = rank
	return true
end

-- Debris: gravity, a bounce that loses most of its speed, then rest on the ground. Returns the new position,
-- velocity and whether it has settled.
FightFxRules.GRAVITY = 62
function FightFxRules.chunkStep(pos: Vector3, vel: Vector3, dt: number, groundY: number): (Vector3, Vector3, boolean)
	local v = vel + Vector3.new(0, -FightFxRules.GRAVITY * dt, 0)
	local p = pos + v * dt
	if p.Y < groundY then
		p = Vector3.new(p.X, groundY, p.Z)
		if v.Y < 0 then
			v = Vector3.new(v.X * 0.55, -v.Y * 0.38, v.Z * 0.55)
		end
		if math.abs(v.Y) < 2 then
			return p, Vector3.zero, true
		end
	end
	return p, v, false
end

-- The decaying shake curve of a slam (frame i of n): hard at once, gone at the end.
function FightFxRules.shakeAt(strength: number, k: number): number
	if k <= 0 then
		return strength
	elseif k >= 1 then
		return 0
	end
	return strength * math.exp(-k * 5) * (1 - k)
end

-- Floating fight pops (damage, "Strong!", "Weak", SPECIAL!) in one server batch used to land on the same frame and
-- stack into one blob. popSlot staggers them: pops on the same pet wait POP_GAP after each other and take the next
-- slot (0, 1, 2: the caller stacks each slot one label height higher on screen), and any two pops wait POP_SPREAD.
-- A pet's slots start over only once its last pop has gone (POP_LIFE), so two live pops never share a slot.
-- Never more than POP_MAX_WAIT.
FightFxRules.POP_GAP = 0.3
FightFxRules.POP_SPREAD = 0.1
FightFxRules.POP_MAX_WAIT = 1.2
FightFxRules.POP_LIFE = 0.9 -- TowerView's pop lifetime
FightFxRules.POP_SLOTS = 3

function FightFxRules.popSlot(state: { [string]: number }, key: string, now: number): (number, number)
	local at = math.max(state[key] or now, state["*"] or now, now)
	local wait = math.min(at - now, FightFxRules.POP_MAX_WAIT)
	local landed = state[key .. "@"]
	if landed == nil or now + wait > landed + FightFxRules.POP_LIFE then
		state[key .. "#"] = 0 -- this pet's last pop has gone: back to the first slot
	end
	local n = state[key .. "#"] or 0
	state[key .. "#"] = n + 1
	state[key .. "@"] = now + wait
	state[key] = now + wait + FightFxRules.POP_GAP
	state["*"] = now + wait + FightFxRules.POP_SPREAD
	return wait, n % FightFxRules.POP_SLOTS
end

return FightFxRules
