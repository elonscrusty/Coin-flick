--!strict
-- Tuning for the egg events (src/server/EggEvents.luau, src/client/EggFx.luau): the wobble hint and the
-- speed boots power-up. Kept out of Config.luau so it can change on its own.

local PetSoundIds = require(script.Parent.PetSoundIds)

local EggConfig = {}

EggConfig.Wobble = {
	Enabled = true,
	-- Seconds between two wobble picks in one match (a random gap in this range, decided on the server).
	MinGap = 3,
	MaxGap = 5,
	-- Chance that a pick is the pet egg (only while it is still in the pile). Otherwise a uniformly random
	-- other pile egg wobbles. Small on purpose: one wobble says almost nothing about the pet egg.
	TargetChance = 0.25,
	-- Slow tiers wobble at the slower Meadow gap below with a slightly higher pet egg chance (the first zone is the
	-- easiest), but decoy wobbles are mixed in everywhere: pet-only wobbles would let a few patches intersect on
	-- the pet egg. Wobbles also go on after the pet egg left the pile. Code tier ids: Gravel = Meadow.
	SlowTiers = { Gravel = true } :: { [string]: boolean },
	MeadowTargetChance = 0.35,
	MeadowMinGap = 8,
	MeadowMaxGap = 12,
	-- Patch hint (owner pick 2026-10-11): a wobble never names one egg. The server takes the pick above as an
	-- anchor, moves PatchJitterMin..PatchJitterMax studs from it in a random flat direction, and every pile egg
	-- within PatchRadius of that point wobbles together (at most PatchMax, listed by id). The jitter range goes
	-- past the radius, so the anchor is OUTSIDE its own patch most of the time (here 5 times in 8) and
	-- intersecting patches does not single it out.
	PatchRadius = 3.5,
	PatchJitterMin = 2,
	PatchJitterMax = 6,
	PatchMax = 8,
	-- Client animation.
	Seconds = 0.7,
	Degrees = 13,
	Shakes = 3,
}

-- Overtime (owner pick 2026-10-11): when a round has been Searching for RoundSeconds, the pet egg glows gold for
-- everyone so the race finishes and there is always a winner. Only then is the pet egg's id sent, and only while it
-- is in the pile: if it is carried or on a nest at that moment, the glow waits until it is back in the pile (the
-- wobbles keep going meanwhile). Never in the practice round.
EggConfig.Overtime = {
	Enabled = true,
	RoundSeconds = 180,
	GlowColor = Color3.fromRGB(255, 205, 60),
}

EggConfig.Chirp = {
	Enabled = true,
	-- Every MinGap..MaxGap seconds (random, server) each player near the pile may hear ONE chirp (Chance) from an
	-- egg still in the pile within Radius studs of them. The chirping egg is the pet egg with TargetChance when it
	-- is that close, otherwise a random nearby decoy egg, so hearing a chirp does not mean the pet egg is near, and
	-- many chirps do not average out on it. Never in the practice round.
	Radius = 8,
	MinGap = 3,
	MaxGap = 6,
	Chance = 0.6,
	TargetChance = 0.3,
	-- The sound plays at a point Jitter studs (random direction, flat) away from the chirping egg (more than half
	-- the Radius), so it points at an area of the pile, not at one egg. No egg id is ever sent.
	JitterMin = 3,
	JitterMax = 6,
	-- PetSoundIds.EggChirp (uploaded by tools/upload_audio.py). 0 = no sound (only the note sparkle shows).
	SoundId = PetSoundIds.EggChirp,
	Volume = 0.6,
	RollOff = 24, -- studs: the 3D sound fades out past this
}

EggConfig.Boots = {
	Enabled = true,
	-- Chance per ordinary egg a player finishes cracking (rolled on the server).
	Chance = 0.04,
	Seconds = 8,
	Bonus = 0.5, -- +50% walk speed while boosted (owner pick 2026-10-11)
	-- Unused by the boost now: the boots multiply the hunter's current walk speed (pet bonus included) and restore it.
	BaseWalkSpeed = 18,
}

return EggConfig
