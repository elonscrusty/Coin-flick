--!strict
-- Pure pose maths for the real pet meshes (tests/test_pet_pose.luau). ReplicatedStorage.PetMotion (tools/owner/
-- PetMotion.luau) is the thin Roblox side: it finds the bones, works out where the pet faces and what it looks at,
-- calls PetPose.step every frame and writes the channels to the bones. Everything that decides HOW a pet moves is here.
--
-- Channels (radians unless noted; + pitch = nose / tip DOWN, + yaw = toward +X, wing + = tips up, mirrored L/R):
--   rootY studs up, rootZ studs forward, rootP, rootYaw, rootR, legFL, legFR, legBL, legBR, tailP, tailY,
--   headP, headY, headR, arms, wing.
--
-- Body types (gaits) so pets stop all walking the same:
--   quad   dogs, cats, deer, griffins: diagonal trot.
--   biped  raptors, T-Rex, ostriches: two legs, leans forward, head pumps with each step.
--   heavy  mammoth, bear, panda, turtle, golem: slow wide steps, side-to-side sway, small bob.
--   hopper bunny, frog, owl: moves in hops (legs together), never trots.
--   waddle penguin: tiny steps, big side-to-side rock.
-- Steps follow how fast the pet really moves (no feet sliding over the ground) up to a cap, and the shared clips
-- (PetClips) scale their root moves with the pet's height, so a small pet does not jump three times its size.
-- Owner rules: no mouth or beak opening (there is no jaw channel), no roar.

local PetClips = require(script.Parent.PetClips)

local PetPose = {}

PetPose.CH = { "rootY", "rootZ", "rootP", "rootYaw", "rootR", "legFL", "legFR", "legBL", "legBR",
	"tailP", "tailY", "headP", "headY", "headR", "arms", "wing" }
local CH = PetPose.CH

PetPose.Clips = PetClips
PetPose.CLIP_HEIGHT = 2.4 -- studs: the pet height the clips were made for
PetPose.LEG_MAX = 0.5 -- radians: single-bone legs stretch the hip past this, so every leg channel is clamped to it
PetPose.HOP_TIME = 0.95 -- hatch / celebrate / spin hop length (s)
PetPose.SIT_AFTER = 7 -- seconds standing still before a pet sits
PetPose.SIT_DROP_MAX = 0.3 -- studs a sitting pet lowers at most
PetPose.FADE = 0.2 -- clip cross-fade (s)
PetPose.WING_MIN = -0.3 -- wing angle limits (rad); bigger angles stretch the wing skin
PetPose.WING_MAX = 0.7
PetPose.WING_SPEED = 4.5 -- rad/s: fastest a wing may swing

export type Gait = {
	cycle: number, -- ground covered per full step cycle, in pet heights
	swing: number, -- leg swing (radians)
	bob: number, -- body bob per step, in pet heights
	roll: number, -- side roll per step (radians)
	twist: number, -- body yaw per step (radians)
	lean: number, -- forward lean while moving (radians)
	headPump: number, -- head nod per step (radians)
	minRate: number, -- step clock while moving with no measurable speed (rad/s)
	maxRate: number, -- step clock cap (rad/s): faster than this the pet slides a little instead of buzzing
	hop: boolean?, -- moves in hops (legs together) instead of steps
	hopHeight: number?, -- hop height, in pet heights
}

PetPose.GAITS = {
	quad = { cycle = 0.85, swing = 0.42, bob = 0.03, roll = 0.045, twist = 0.05, lean = 0.07, headPump = 0.05, minRate = 9, maxRate = 17 },
	biped = { cycle = 0.8, swing = 0.45, bob = 0.04, roll = 0.06, twist = 0.07, lean = 0.12, headPump = 0.1, minRate = 9, maxRate = 18 },
	heavy = { cycle = 0.6, swing = 0.3, bob = 0.015, roll = 0.08, twist = 0.04, lean = 0.03, headPump = 0.04, minRate = 6, maxRate = 12 },
	hopper = { cycle = 0.9, swing = 0.4, bob = 0, roll = 0.02, twist = 0.02, lean = 0.05, headPump = 0.06, minRate = 8, maxRate = 14, hop = true, hopHeight = 0.12 },
	waddle = { cycle = 0.35, swing = 0.22, bob = 0.012, roll = 0.24, twist = 0.12, lean = 0.02, headPump = 0.03, minRate = 10, maxRate = 18 },
} :: { [string]: Gait }

-- Species id -> gait, for the pets whose body is not what Config Kind says (Kind is the old procedural stand-in body).
PetPose.SPECIES_GAIT = {
	-- two legs (Studio rig check 2026-10-15): raptors, rexes, birds
	Raptor = "biped", Ostrich = "biped", LavaTRex = "biped", Mosswhip = "biped", Shiverclaw = "biped", Emberclaw = "biped",
	Nebuclaw = "biped", Thornhoof = "biped", Flarestrut = "biped", GalaxyStrut = "biped", Puffquill = "biped",
	Phoenix = "biped", Zapstar = "biped", Hailwing = "biped", Embergeist = "biped", Voltwing = "biped",
	Bramblebat = "biped", Ashwing = "biped", StarPterodactyl = "biped",
	-- big and slow
	Mammoth = "heavy", Pebblehorn = "heavy", Oakmaw = "heavy", Yetiboo = "heavy", Obsidihorn = "heavy", Magmaw = "heavy",
	LunarTusk = "heavy", Panda = "heavy", Mossback = "heavy",
	Turtle = "heavy",
	Bunny = "hopper", Frog = "hopper", Moonhoot = "hopper", AuroraHoot = "hopper",
	Waddlefrost = "waddle",
} :: { [string]: string }
-- Words in a display name or model name that give the body away (checked when the id is not listed above).
local NAME_GAIT = {
	{ "bear", "heavy" }, { "panda", "heavy" }, { "turtle", "heavy" }, { "golem", "heavy" }, { "tusk", "heavy" },
	{ "mammoth", "heavy" }, { "bunny", "hopper" }, { "rabbit", "hopper" }, { "frog", "hopper" }, { "owl", "hopper" },
	{ "hoot", "hopper" }, { "penguin", "waddle" }, { "waddle", "waddle" }, { "raptor", "biped" }, { "rex", "biped" },
	{ "ostrich", "biped" }, { "strut", "biped" },
}
local KIND_GAIT = { raptor = "biped", ostrich = "biped", trex = "biped", mammoth = "heavy" }

-- The gait name for a pet. `id` = species id, `name` = display or model name, `kind` = Config Kind, `backLegs` =
-- whether the rig has LegBL/LegBR (nil = unknown). A model attribute "Gait" (checked by PetMotion first) wins over all.
function PetPose.gaitFor(id: string?, name: string?, kind: string?, backLegs: boolean?): string
	if id and PetPose.SPECIES_GAIT[id] then
		return PetPose.SPECIES_GAIT[id]
	end
	local low = string.lower((name or "") .. " " .. (id or ""))
	for _, pair in NAME_GAIT do
		if string.find(low, pair[1], 1, true) then
			return pair[2]
		end
	end
	if backLegs == false then
		return "biped"
	end
	if kind and KIND_GAIT[kind] and backLegs == nil then
		return KIND_GAIT[kind]
	end
	return "quad"
end

local function smooth01(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end
PetPose.smooth01 = smooth01

-- Channel values of clip c at time t (loops wrap, one-shots clamp), eased between keys.
function PetPose.sampleClip(c: any, t: number, out: { [string]: number })
	local keys = c.keys
	t = if c.loop then t % c.dur else math.clamp(t, 0, c.dur)
	local a, b, k = keys[#keys], keys[#keys], 0
	for i = 1, #keys - 1 do
		if t >= keys[i].t and t <= keys[i + 1].t then
			a, b = keys[i], keys[i + 1]
			k = smooth01((t - a.t) / math.max(b.t - a.t, 1e-6))
			break
		end
	end
	for _, ch in CH do
		local va, vb = a[ch] or 0, b[ch] or 0
		out[ch] = va + (vb - va) * k
	end
end

-- One hop: height (in clip studs), squash (+ = crouched), pitch (+ = nose down).
function PetPose.hopCurve(p: number): (number, number, number)
	if p < 0.18 then -- anticipation crouch
		local k = smooth01(p / 0.18)
		return -0.12 * k, k, 0.12 * k
	elseif p < 0.62 then -- airborne: fast up, hang, fall
		local k = (p - 0.18) / 0.44
		return 0.9 * math.sin(k * math.pi) - 0.12 * (1 - k) * (1 - k), 0, -0.22 * math.cos(k * math.pi)
	elseif p < 0.74 then -- landing squash
		local k = math.sin((p - 0.62) / 0.12 * math.pi)
		return -0.1 * k, 0.8 * k, 0.1 * k
	else -- settle with a small overshoot
		local k = math.min(1, (p - 0.74) / 0.21)
		return 0.03 * math.sin(k * math.pi) * (1 - k), 0, -0.03 * math.sin(k * math.pi * 2) * (1 - k)
	end
end

-- Step clock speed (rad/s) for a pet moving at `speed` studs/s. One full cycle (2 pi) covers gait.cycle * height
-- studs, so the feet keep up with the ground; with no measured speed (pets walking on the spot in a viewport) it is
-- the gait's minRate times walkRate. Capped at maxRate.
function PetPose.stepRate(g: Gait, speed: number, height: number, walkRate: number?): number
	local base = g.minRate * math.clamp(walkRate or 1, 0.5, 2)
	if speed <= 0.5 then
		return base
	end
	local r = 2 * math.pi * speed / math.max(g.cycle * height, 0.2)
	return math.clamp(r, g.minRate * 0.6, g.maxRate)
end

export type Input = {
	moving: boolean, -- the owner is walking (model attribute Moving)
	speed: number, -- measured ground speed, studs/s (0 = unknown / on the spot)
	height: number, -- pet height, studs
	gait: string,
	rigged: boolean, -- has bones (else a gentle whole-body bob)
	anim: string?, -- looping clip name (model attribute Anim), nil = procedural idle / walk
	walkRate: number?,
	sleepy: boolean?,
	aimYaw: number?, -- head turn toward a LookAt point (nil = nothing to look at)
	aimPitch: number?,
	yaw: number, -- current facing yaw (radians), for the tail follow-through on turns
}

export type State = { [string]: any }

function PetPose.new(seed: number?): State
	local r = seed or 0
	return {
		t = (r * 7.31) % 10, walk = 0, ph = 0, still = 0, sit = 0, sleep = 0,
		lookW = 0, lookYaw = 0, lookPitch = 0, yawRate = 0, tailYaw = 0, tailVel = 0, lastYaw = nil,
		happyWait = 3 + (r * 3.7) % 4, happyT = nil, pop = nil, popKind = nil,
		animName = nil, animT = 0, fromK = 1, fromV = {}, V = {}, L = {}, SV = {}, shot = nil, shotT = 0,
	}
end

-- Pops: "hatch" (crouch, hop, squash), "celebrate" (two hops with a spin), "spin" (one hop with a turn), "hop" (a
-- small hop; never cuts another pop short).
function PetPose.pop(s: State, kind: string)
	if kind == "hop" and s.pop then
		return
	end
	s.pop = 0
	s.popKind = kind
	s.shot = nil
end

-- One-shot clip (attack / hit / win) over whatever the pet is doing. Returns false for an unknown clip.
function PetPose.play(s: State, name: string): boolean
	if not PetClips[name] then
		return false
	end
	s.shot = name
	s.shotT = 0
	s.pop = nil
	return true
end

-- Advances the state by dt and returns the channel table (reused between calls; copy it to keep it).
function PetPose.step(s: State, i: Input, dt: number): { [string]: number }
	dt = math.clamp(dt, 0, 1 / 15)
	s.t += dt
	local t = s.t
	local g: Gait = PetPose.GAITS[i.gait] or PetPose.GAITS.quad
	local h = math.max(i.height, 0.3)
	local hs = h / PetPose.CLIP_HEIGHT -- root moves in clips and hops scale with the pet

	local target = if i.moving then 1 else 0
	s.walk += (target - s.walk) * math.min(1, dt * 6)
	local w = s.walk
	local idle = 1 - w
	-- the step clock keeps turning (slowly) into idle instead of freezing mid-stride
	local rate = PetPose.stepRate(g, i.speed, h, i.walkRate)
	s.ph += dt * (4 * idle + rate * w)
	local ph = s.ph

	-- sit after standing still a while; any move or hop stands it straight back up
	if not i.moving and not s.pop and not s.shot then
		s.still += dt
	else
		s.still = 0
	end
	local sitTarget = if s.still >= PetPose.SIT_AFTER and i.anim == nil then 1 else 0
	s.sit += (sitTarget - s.sit) * math.min(1, dt * (if sitTarget > s.sit then 3 else 10))
	local sit = s.sit

	-- happy idle: every 5-9 s of standing (not sitting), a 1.2 s burst of fast tail wag and quick wing beats
	s.happyWait -= dt * idle * (1 - sit)
	if s.happyWait <= 0 and not s.pop then
		s.happyT = 0
		s.happyWait = 5 + ((t * 13.7) % 4)
	end
	local happyFx = 0
	if s.happyT then
		s.happyT += dt
		if s.happyT >= 1.2 or w > 0.3 then
			s.happyT = nil
		else
			happyFx = math.sin(math.pi * s.happyT / 1.2) * idle
		end
	end

	-- turning: the tail swings out the other way on a spring, then settles (follow-through)
	if s.lastYaw then
		local d = (i.yaw - s.lastYaw + math.pi) % (2 * math.pi) - math.pi
		s.yawRate += (d / math.max(dt, 1e-3) - s.yawRate) * math.min(1, dt * 10)
	end
	s.lastYaw = i.yaw
	local tailTarget = math.clamp(-s.yawRate * 0.12, -0.5, 0.5)
	s.tailVel += ((tailTarget - s.tailYaw) * 60 - s.tailVel * 9) * dt
	s.tailYaw += s.tailVel * dt

	-- hatch / celebrate / spin / hop
	local hopY, squash, hopPitch, spin = 0, 0, 0, 0
	if s.pop then
		s.pop += dt
		local p = s.pop
		local dur = if s.popKind == "celebrate" then PetPose.HOP_TIME * 2 else PetPose.HOP_TIME
		if p >= dur then
			s.pop = nil
		else
			local q = p % PetPose.HOP_TIME
			hopY, squash, hopPitch = PetPose.hopCurve(q)
			if s.popKind == "hop" then
				hopY *= 0.6
				squash *= 0.6
				hopPitch *= 0.6
			end
			if (s.popKind == "celebrate" or s.popKind == "spin") and q > 0.18 and q < 0.62 then
				spin = smooth01((q - 0.18) / 0.44) * math.pi * 2
			end
		end
	end
	local air = if s.pop and hopY > 0 then math.min(1, hopY / 0.5) else 0

	-- sleepy (owner idle a long while): the head droops and the breathing slows
	s.sleep += ((if i.sleepy then 1 else 0) - s.sleep) * math.min(1, dt * 2)
	local sleep = s.sleep

	-- look at a point (the owner, a passer-by): small angles, eased in and out
	local aimYaw = if sleep < 0.5 then i.aimYaw else nil
	local k = math.min(1, dt * 4)
	s.lookW += ((if aimYaw then 1 else 0) - s.lookW) * k
	if aimYaw then
		s.lookYaw += (math.clamp(aimYaw, -0.6, 0.6) - s.lookYaw) * k
		s.lookPitch += (math.clamp(i.aimPitch or 0, -0.3, 0.2) - s.lookPitch) * k
	end
	local lw = s.lookW

	local L = s.L
	local sn = math.sin(ph)
	-- legs and body by gait
	local tuck = -0.35 * air + 0.25 * squash - 0.3 * sit
	local stepLift = 0 -- extra height from gait hops (studs)
	local stepPitch = 0
	if g.hop then
		-- hoppers: the cycle is one hop. Ground half (sin < 0): crouch, push; air half: legs tucked, nose up then down.
		local up = math.max(0, sn)
		local crouch = math.max(0, -sn)
		stepLift = up * (g.hopHeight or 0.12) * h * w
		stepPitch = (-0.12 * math.cos(ph) * up) * w
		L.legFL = (-0.3 * up + 0.2 * crouch) * w + tuck
		L.legFR = L.legFL
		L.legBL = (0.35 * crouch - 0.25 * up) * w + tuck - 0.25 * sit
		L.legBR = L.legBL
	else
		local swing = sn * g.swing * w
		L.legFL = -swing + tuck
		L.legFR = swing + tuck
		L.legBL = swing + tuck - 0.25 * sit
		L.legBR = -swing + tuck - 0.25 * sit
	end
	for _, leg in { "legFL", "legFR", "legBL", "legBR" } do
		L[leg] = math.clamp(L[leg], -PetPose.LEG_MAX, PetPose.LEG_MAX)
	end

	-- bob is lowest when the feet are spread, highest as they pass under; sway over the planted foot
	local bob = (1 - math.abs(sn)) * g.bob * h * w
	local breathe = math.sin(t * (2.4 - 1.2 * sleep)) * (0.015 + 0.01 * sleep) * hs * idle
	local roll = sn * g.roll * w
	local twist = sn * g.twist * w
	local lean = g.lean * w + hopPitch + stepPitch - 0.1 * sit

	-- tail: drags behind the body sway (phase-lagged), droops on landing, lifts in the air, wags when happy
	L.tailY = math.sin(ph - 1.1) * 0.22 * w + math.sin(t * 1.3) * 0.16 * idle + s.tailYaw - twist
		+ math.sin(t * 14) * 0.38 * happyFx
	L.tailP = math.sin(t * 0.9) * 0.04 * idle + math.sin(ph * 2 - 1.2) * 0.05 * w
		- 0.18 * squash + 0.15 * air - lean * 0.6 - 0.12 * sit

	-- little arms: bounce a beat after each step, flail up in the air
	L.arms = math.sin(t * 2.2) * 0.07 * idle + math.sin(ph * 2 - 0.9) * 0.14 * w - 0.5 * air + 0.2 * squash
	-- wings: slow breathing lift when idle, folded down while walking, about one slow full beat per second in the
	-- air and in the happy burst (fast beats looked like a buzz and sheared the wing skin; owner 2026-10-15)
	L.wing = math.sin(t * 1.8) * 0.22 * idle * (1 - sleep) - 0.18 * w + sn * 0.03 * w
		+ (0.35 + math.sin(t * 6) * 0.35) * air + (0.22 + math.sin(t * 6) * 0.3) * happyFx

	-- head: stays level while the body bobs (counter-rotates), pumps with the step, looks around when idle
	local glance = (math.sin(t * 0.55) + 0.5 * math.sin(t * 1.37)) * 0.3 * idle * (1 - sleep) * (1 - lw)
		+ s.lookYaw * lw
	L.headY = glance - twist * 0.8
	L.headR = math.sin(t * 1.1) * 0.07 * idle * (1 - lw) + 0.12 * sleep
	L.headP = math.sin(t * 1.7) * 0.04 * idle * (1 - sleep) + math.sin(ph * 2 - 0.5) * g.headPump * w - lean * 0.7
		+ 0.35 * sleep + math.sin(t * 1.2) * 0.04 * sleep + s.lookPitch * lw

	local bobAmt = if i.rigged then 0 else 0.05 * h
	L.rootY = math.sin(t * 2) * bobAmt * idle + bob + breathe + hopY * hs + stepLift
		- sit * math.min(h * 0.1, PetPose.SIT_DROP_MAX)
	L.rootZ, L.rootP, L.rootYaw, L.rootR = 0, lean, spin + twist, roll

	-- clips: a looping Anim (cross-faded in, out and between clips), then a one-shot on top
	local clip = if i.anim then PetClips[i.anim] else nil
	if i.anim ~= s.animName then
		-- snapshot what is showing now so the switch fades instead of popping
		for _, ch in CH do
			s.fromV[ch] = s.V[ch] or L[ch] or 0
		end
		s.fromK, s.animName, s.animT = 0, i.anim, 0
	end
	-- walk / run clips play faster or slower with the real speed, like the procedural steps
	local clipRate = 1
	if clip and (i.anim == "walk" or i.anim == "run") and i.speed > 0.5 then
		local natural = 2 * math.pi / clip.dur -- rad/s the clip was made at
		clipRate = math.clamp(PetPose.stepRate(g, i.speed, h, nil) / natural, 0.7, 1.8)
	end
	s.animT += dt * clipRate
	s.fromK = math.min(1, s.fromK + dt / PetPose.FADE)
	local V = s.V
	if clip then
		PetPose.sampleClip(clip, s.animT, V)
		V.rootY *= hs
		V.rootZ *= hs
		V.arms = L.arms -- clips have no arm channel: keep the procedural bounce
	else
		for _, ch in CH do
			V[ch] = L[ch] or 0
		end
	end
	if s.fromK < 1 then
		local kk = smooth01(s.fromK)
		for _, ch in CH do
			V[ch] = s.fromV[ch] + (V[ch] - s.fromV[ch]) * kk
		end
	end
	if s.shot then
		local c = PetClips[s.shot]
		s.shotT += dt
		if not c or s.shotT >= c.dur then
			s.shot = nil
		else
			local SV = s.SV
			PetPose.sampleClip(c, s.shotT, SV)
			SV.rootY *= hs
			SV.rootZ *= hs
			local kk = smooth01(s.shotT / 0.08) -- quick ease in; every one-shot ends on the rest pose
			for _, ch in CH do
				if ch ~= "arms" then
					V[ch] = V[ch] + (SV[ch] - V[ch]) * kk
				end
			end
			if s.shot == "win" then
				V.rootYaw = SV.rootYaw -- full spin: never blend the angle
			end
		end
	end
	for _, leg in { "legFL", "legFR", "legBL", "legBR" } do
		V[leg] = math.clamp(V[leg], -PetPose.LEG_MAX, PetPose.LEG_MAX)
	end
	-- wings follow on a soft spring with a speed cap, so clip snaps and beats ease in and out instead of jerking
	local wt = math.clamp(V.wing, PetPose.WING_MIN, PetPose.WING_MAX)
	local wv = s.wingV or wt
	wv += math.clamp((wt - wv) * math.min(1, dt * 12), -PetPose.WING_SPEED * dt, PetPose.WING_SPEED * dt)
	s.wingV = wv
	V.wing = wv
	return V
end

return PetPose
