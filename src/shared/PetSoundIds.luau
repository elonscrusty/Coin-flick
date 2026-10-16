--!strict
-- Sound ids for Find The Pet (list and sources: /mnt/project-files/audio/sound-list.md).
-- 0 = not picked yet: the client Audio module skips a 0 id. Never put guessed ids here.
-- Sounds already uploaded (SoundIds, generated) are reused by reference; sounds made by
-- tools/synth_pet_sfx.py read their id from SoundIds once tools/upload_audio.py has uploaded them.
local SoundIds = require(script.Parent.SoundIds)

local PetSoundIds: { [string]: number } = {
	-- Music (REPLACE: Roblox licensed tracks from the Creator Store)
	LobbyMusic = 140660383888658, -- "Sun on the Porch" (APM, licensed); picked in Studio (sound-picks.md)
	RaceMusic = 1837560399, -- "High Energy" (APM, licensed); picked in Studio (sound-picks.md)

	-- Eggs
	EggTap = SoundIds.EggTap or 9113959071, -- "Crack Egg Crunchy 6" (Pro Sound Effects, licensed) until the synth tap is uploaded
	EggBreak = SoundIds.EggBreak or 9113959343, -- "Crack Egg Crunchy 11" (Pro Sound Effects, licensed) until the synth break is uploaded
	EggChirp = SoundIds.EggChirp or 9117236949, -- "Parakeet Chirps 7" (Pro Sound Effects, licensed) until the synth chirp is uploaded
	EggPickup = SoundIds.Pickup,

	-- Hatching
	HatchBuildUp = 87681931953984, -- "Vast Horizon - Sting" (APM, licensed); picked in Studio (sound-picks.md)
	HatchWin = SoundIds.MatchWin,
	RareSparkle = SoundIds.RarityAccent,

	-- Lobby, shop, HUD
	CoinPickup = SoundIds.CoinPickup or 1169806635, -- "Coin Collect 2 - SFX" (public, free to use) until the synth coin is uploaded
	SpeedBoots = SoundIds.SpeedBoots or 0, -- made by tools/synth_pet_sfx.py; 0 until uploaded
	UIClick = SoundIds.Button,
	Purchase = SoundIds.Purchase,
	Countdown = SoundIds.CountdownTick,

	-- Tower
	TowerHit = SoundIds.TowerHit or 0, -- made by tools/synth_pet_sfx.py; 0 until uploaded
	TowerSpecial = SoundIds.TowerSpecial or 0, -- made by tools/synth_pet_sfx.py; 0 until uploaded

	-- Find The Pet moments (Item 20): made by tools/synth_pet_sfx.py, 0 until tools/upload_audio.py uploads them.
	-- While a key is 0 the client plays its stand-in from shared/SoundCues.Fallback (or nothing). Moment map: SoundCues.
	-- Pets never roar (owner rule): big hatches use HatchSparkle (swell) and HatchDrum (drum hit).
	HatchSparkle = SoundIds.HatchSparkle or 0,
	HatchDrum = SoundIds.HatchDrum or 0,
	PetFound = SoundIds.PetFound or 0,
	EggGrab = SoundIds.EggGrab or 0,
	EggDrop = SoundIds.EggDrop or 0,
	BattleMatched = SoundIds.BattleMatched or 0,
	PetCrit = SoundIds.PetCrit or 0,
	PetKO = SoundIds.PetKO or 0,
	BattleWin = SoundIds.BattleWin or 0,
	BattleLose = SoundIds.BattleLose or 0,
	TrainTap = SoundIds.TrainTap or 0,
	LevelUp = SoundIds.LevelUp or 0,
	Evolve = SoundIds.Evolve or 0,
	FloorClear = SoundIds.FloorClear or 0,
	DailyClaim = SoundIds.DailyClaim or 0,
	GiftOpen = SoundIds.GiftOpen or 0,
	QuestDone = SoundIds.QuestDone or 0,
	LuckyMeter = SoundIds.LuckyMeter or 0,
	Denied = SoundIds.Denied or 0,
}

return PetSoundIds
