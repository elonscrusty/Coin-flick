--!strict
-- Pet Battle + Pet Training tuning (carter 2026-10-14: "find the pet - train the pet - fight other pets").
-- Pure data, no Roblox services. Fights reuse the tower's pet stats (PetStats) and type chart; rules in PvpRules.

local PvpConfig = {}

PvpConfig.TeamSize = 3 -- pets per side

-- Matchmaking: 1v1, matched by team power (PvpRules.teamPower). Two players match when their power differs by at
-- most Window.Start (share of the bigger one), widening by Window.PerSecond for every second waited. Nobody waits
-- longer than BotAfter seconds: then a bot team of about the same power steps in.
PvpConfig.Window = { Start = 0.15, PerSecond = 0.03 }
PvpConfig.BotAfter = 15
-- Bot team power aims at BotPower x the player's (a small edge for the player), picked from BotTries rolls.
PvpConfig.BotPower = 0.95
PvpConfig.BotTries = 8
PvpConfig.BotSpecialDelay = 1.5 -- seconds a bot waits after its SPECIAL fills
-- Shown with a BOT tag in the game, so nobody thinks a bot is a real player.
PvpConfig.BotNames = { "Pip", "Mo", "Zee", "Bo", "Kit", "Nova", "Sunny", "Tumble" }

-- Fight
PvpConfig.FightTime = 60 -- seconds; on time-out the side with more health left (share of max) wins
PvpConfig.ForfeitWinAfter = 8 -- seconds: a rival who leaves sooner gives the stayer a draw reward, not a win (anti win-feeding)
PvpConfig.CritChance = 0.1 -- basic and type-move hits
PvpConfig.CritMult = 1.6
PvpConfig.HealthMult = 4 -- pets have this much more health in battle than in the tower, so a fight lasts ~20-30 s
PvpConfig.SpecialCharge = 150 -- meter units when SPECIAL is full (clients get the meter as a 0..1 share of it)
-- SPECIAL fills after dealing this share of the other team's total max health, at every level and rarity (a flat
-- damage number filled at once for trained teams: their fights were all SPECIALs, 6 s long; balance sim).
PvpConfig.SpecialShare = 0.15
-- The rival's pets stand on this line (arena z; ours are at z -14), nearer than the tower's mob line (z 3) so both
-- teams read clearly from behind the player. PvpService mirrors side 2's view about the middle of the two lines.
PvpConfig.FoeZ = -4
-- Fight layouts (studs along the arena's look axis from the origin): our pet line, the rival's, where the players
-- stand, gaps between pets. Private = a TowerBuilder arena; Live = the open arena in the middle of the lobby (carter
-- 2026-10-14: everyone can watch). Its origin is the arena floor's centre, so the two pet lines sit either side of it.
PvpConfig.Layouts = {
	Private = { PetZ = -14, FoeZ = -4, StandZ = -22, PetGap = 8, FoeGap = 8 },
	Live = { PetZ = -4, FoeZ = 4, StandZ = -12, PetGap = 6, FoeGap = 6 },
	-- the lobby stadium (fight floor ~64 studs, ArenaCenter FightRadius 30): pet lines at +-10 facing each other across
	-- the middle, pets 9 apart in a line, players at +-21 behind their own team (Studio test 2026-10-14: at +-6 the
	-- two teams' real-size pets overlapped). StandX puts the player off to their left (the view's +X), away from the
	-- fight camera's orbit (it swings round their right side): their avatar never fills the foreground.
	LiveBig = { PetZ = -10, FoeZ = 10, StandZ = -21, StandX = 13, PetGap = 9, FoeGap = 9 },
}
-- An ArenaCenter with FightRadius (or a floor half-size) of at least BigArena studs uses Layouts.LiveBig.
PvpConfig.BigArena = 20
-- Fights happen on small floating islands (carter 2026-10-14: "make a floating island ... teleport to the small
-- island"), one copy per fight, nobody watches. The island is ServerStorage[Island.Model] (the owner's Blender model,
-- with a part marked ArenaCenter = true and FightRadius on its fight floor); without it a procedural stand-in is built.
-- Copies float at Base, Spacing studs apart, far from the lobby, hunts and the tower.
PvpConfig.Island = { Model = "ArenaIsland", Base = Vector3.new(-4000, 600, 0), Spacing = 400, Radius = 30 }
PvpConfig.CountIn = 3 -- seconds of "3, 2, 1, FIGHT!" before pets start
PvpConfig.ResultHold = 4 -- seconds the winners cheer before the result card

-- Rewards. Bots pay full coins and XP but fewer trophies, so the trophy count mostly means real wins.
PvpConfig.Rewards = {
	WinCoins = 75,
	LossCoins = 15,
	DrawCoins = 25,
	StreakCoins = 10, -- per win in the current streak after the first, up to StreakCap
	StreakCap = 5,
	WinXp = 60, -- to each of the side's pets (training XP, PetStats.level)
	LossXp = 25,
	WinTrophies = 20,
	LossTrophies = 10,
	BotWinTrophies = 8,
	BotLossTrophies = 4,
}

-- Trophy ranks, lowest first.
PvpConfig.Ranks = {
	{ Name = "Bronze", Min = 0, Color = Color3.fromRGB(205, 140, 90) },
	{ Name = "Silver", Min = 150, Color = Color3.fromRGB(200, 210, 225) },
	{ Name = "Gold", Min = 400, Color = Color3.fromRGB(255, 205, 70) },
	{ Name = "Diamond", Min = 800, Color = Color3.fromRGB(120, 220, 255) },
	{ Name = "Champion", Min = 1500, Color = Color3.fromRGB(255, 120, 200) },
}

-- Training (TRAIN): pets level up with the tower's XP book (profile TowerXP, PetStats.level, +4% power per level).
-- Tap TRAIN: each accepted tap gives TapXp to the picked pet; at most TapsPerSecond taps count (more are dropped).
-- Idle: every IdleEvery seconds online, each pet following the player gets IdleXp.
PvpConfig.Train = { TapXp = 2, TapsPerSecond = 5, IdleEvery = 60, IdleXp = 5 }
-- Hunt XP (carter 2026-10-14): every egg a player cracks in a hunt gives each pet following them CrackXp; the
-- egg with the pet inside gives FoundXp.
PvpConfig.Hunt = { CrackXp = 3, FoundXp = 25 }

-- Tap to fight (carter 2026-10-16: "Fight part is thin"). The player's hands count too:
-- TAP anywhere on the fight: a quick extra hit from the team (Share of the team's damage per second, so taps add
-- about Share x PerSecond on top: 6 taps a second ~ +18%). Taps within ComboGap seconds grow a combo; each combo step
-- adds ComboStep, up to ComboMax steps. The server counts at most PerSecond taps.
-- BLOCK: a rival pet about to use its big type move WarnTime seconds ahead raises a gold ring on our side; a BLOCK
-- before it lands is PERFECT (the move does Cut less damage and our SPECIAL meter gains PerfectCharge). A BLOCK with
-- no ring up misses and locks BLOCK for MissLock seconds, so spamming it does not work.
-- Bots tap BotTaps a second and block BotBlock of the rings, so a player who plays along has the edge (balance in
-- tests/test_pvp_tap.luau: vs bots a kid who taps and blocks wins ~87%, one who only watches ~36%).
PvpConfig.Tap = { Share = 0.03, PerSecond = 6, ComboGap = 0.7, ComboStep = 0.05, ComboMax = 10, BotTaps = 2 }
PvpConfig.Block = { WarnTime = 1.1, Cut = 0.5, PerfectCharge = 25, MissLock = 1.5, BotBlock = 0.35 }

-- Rate limits (server): one queue / leave intent per QueueGap, one SPECIAL per ActionGap.
PvpConfig.QueueGap = 1
PvpConfig.ActionGap = 0.15

return PvpConfig
