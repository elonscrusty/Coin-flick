--!strict
-- Hand-set sound ids for Find The Pet sounds that are not in the generated SoundIds table (that file is rewritten by
-- tools/upload_audio.py). The client Audio module looks here after SoundIds. 0 = no sound yet: nothing plays.
-- REPLACE: the owner uploads or picks each sound (Creator Dashboard > Audio, or the Toolbox) and pastes its numeric
-- id here. Never put a guessed id here.
--
-- Ids: plain sounds by name (Audio.play(name)).
-- Pets never roar (owner rule 2026-10-13): there is no per-species roar sound.

local PetSoundIds = require(script.Parent.PetSoundIds)

local SoundConfig = {
	Ids = {
		EggCrunch = PetSoundIds.EggTap, -- made sound (0 until uploaded)
		EggPop = PetSoundIds.EggBreak, -- made sound (0 until uploaded)
		HatchChoir = PetSoundIds.HatchBuildUp, -- build-up before a Rare+ pet pops
		-- the owner's uploads (IMPORT_SOUNDS, 2026-10-13)
		ButtonClickSoft = 101452752754957, -- UI button click
		UIWhooshSoft = 131957057864016, -- menu panel open / close
		ShopKaChing = 78809819500095, -- purchase
		ShellPop = 125084463938090, -- shells sold
		HuntWindBed = 130675273376991, -- hunt wind loop (Audio.setArea)
		PetFootstepPat = 77953031296703, -- very quiet pet footstep (not wired yet)
	} :: { [string]: number },
}

return SoundConfig
