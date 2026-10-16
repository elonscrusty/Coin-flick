--!strict
-- Which sound plays at which Find The Pet moment (pure rules; the client Audio module and SoundCueView play them).
-- Every key named here resolves through Audio's id lookup: SoundIds (uploaded), SoundConfig.Ids (hand-set),
-- PetSoundIds (Find The Pet). An id of 0 plays nothing; a key in Fallback plays its stand-in instead, so a moment that
-- already had a sound never goes quiet while its new made sound waits for upload.
-- Pets never roar (owner rule): no key here or in the id tables may be a roar.
-- Tests: tests/test_sound_cues.luau. Docs: docs/AUDIO.md "Find The Pet moments".

local SoundCues = {}

export type Cue = { Key: string, Delay: number, Pitch: number, Volume: number, Tag: string? }

-- new made sound -> the uploaded sound it replaces (played while the new one's id is still 0)
SoundCues.Fallback = {
	EggGrab = "Pickup",
	EggDrop = "Deposit",
	BattleWin = "MatchWin",
	LevelUp = "RarityAccent",
	Evolve = "RarityAccent",
} :: { [string]: string }

-- The audit list (Item 20): every key moment and the key it plays. Order = the owner's list.
SoundCues.Moments = {
	{ Moment = "Hatch reveal (every rarity)", Key = "GeodeReveal" },
	{ Moment = "Hatch reveal rarity sting (Uncommon+)", Key = "RarityAccent" },
	{ Moment = "Hatch reveal Epic+ sparkle swell", Key = "HatchSparkle" },
	{ Moment = "Hatch reveal Legendary / Void drum hit", Key = "HatchDrum" },
	{ Moment = "Hatch build-up (Rare+ slow motion)", Key = "HatchChoir" },
	{ Moment = "Pet found (everyone in the round)", Key = "PetFound" },
	{ Moment = "Pet found, you won (versus)", Key = "MatchWin" },
	{ Moment = "Egg grab from the pile", Key = "EggGrab" },
	{ Moment = "Egg drop at the nest", Key = "EggDrop" },
	{ Moment = "Egg tap", Key = "EggCrunch" },
	{ Moment = "Egg breaks (no pet)", Key = "EggPop" },
	{ Moment = "Pet egg hint chirp", Key = "EggChirp" },
	{ Moment = "Pet Battle queue matched", Key = "BattleMatched" },
	{ Moment = "Pet Battle hit", Key = "TowerHit" },
	{ Moment = "Pet Battle crit", Key = "PetCrit" },
	{ Moment = "Pet Battle SPECIAL", Key = "TowerSpecial" },
	{ Moment = "Pet Battle SPECIAL ready", Key = "RarityAccent" },
	{ Moment = "Pet Battle K.O. (a pet faints)", Key = "PetKO" },
	{ Moment = "Pet Battle win", Key = "BattleWin" },
	{ Moment = "Pet Battle lose", Key = "BattleLose" },
	{ Moment = "Training tap", Key = "TrainTap" },
	{ Moment = "Level up", Key = "LevelUp" },
	{ Moment = "Evolve", Key = "Evolve" },
	{ Moment = "Tower floor clear", Key = "FloorClear" },
	{ Moment = "Tower run lost", Key = "BattleLose" },
	{ Moment = "Daily claim", Key = "DailyClaim" },
	{ Moment = "Gift open", Key = "GiftOpen" },
	{ Moment = "Coin gain", Key = "CoinPickup" },
	{ Moment = "Buttons and tabs", Key = "ButtonClickSoft" },
	{ Moment = "Panel open / close", Key = "UIWhooshSoft" },
	{ Moment = "Purchase / unlock", Key = "ShopKaChing" },
	{ Moment = "Quest done", Key = "QuestDone" },
	{ Moment = "Lucky Meter full", Key = "LuckyMeter" },
	{ Moment = "Error / denied", Key = "Denied" },
	{ Moment = "Round countdown", Key = "CountdownTick" },
	{ Moment = "Speed boots", Key = "SpeedBoots" },
} :: { { Moment: string, Key: string } }

-- Hatch reveal: rarity sets the pitch and loudness of the sting; Epic and up add the sparkle swell, Legendary and
-- Void (the Void Dragon, or a Mythic / Secret / Void rarity) add the drum hit on top. No roars.
local STING: { [string]: { Pitch: number, Volume: number, Reveal: number, Echo: number?, Sparkle: boolean?, Drum: number? } } = {
	Common = { Pitch = 0.8, Volume = 0.55, Reveal = 0.95 },
	Uncommon = { Pitch = 0.9, Volume = 0.7, Reveal = 1.0 },
	Rare = { Pitch = 1.0, Volume = 0.85, Reveal = 1.0 },
	Epic = { Pitch = 1.12, Volume = 1.0, Reveal = 1.04, Echo = 1.5, Sparkle = true },
	Legendary = { Pitch = 1.25, Volume = 1.2, Reveal = 1.08, Echo = 2.0, Sparkle = true, Drum = 1.0 },
	Void = { Pitch = 1.1, Volume = 1.25, Reveal = 0.92, Echo = 2.0, Sparkle = true, Drum = 0.85 },
}
local VOID_RARITY = { Mythic = true, Secret = true, Void = true }

function SoundCues.reveal(rarity: string?, isVoid: boolean?): { Cue }
	local name = if isVoid or (rarity and VOID_RARITY[rarity]) then "Void" else rarity
	local st = name and STING[name]
	local out: { Cue } = { { Key = "GeodeReveal", Delay = 0, Pitch = if st then st.Reveal else 1, Volume = 1 } }
	if not st then
		return out
	end
	table.insert(out, { Key = "RarityAccent", Delay = 0.25, Pitch = st.Pitch, Volume = st.Volume })
	if st.Echo then
		table.insert(out, { Key = "RarityAccent", Delay = 0.6, Pitch = st.Pitch * st.Echo, Volume = st.Volume * 0.6, Tag = "RarityEcho" })
	end
	if st.Drum then
		table.insert(out, { Key = "HatchDrum", Delay = 0.05, Pitch = st.Drum, Volume = 1 })
	end
	if st.Sparkle then
		table.insert(out, { Key = "HatchSparkle", Delay = 0.15, Pitch = 1, Volume = if st.Drum then 1 else 0.85 })
	end
	return out
end

local function has(text: string, word: string): boolean
	return string.find(string.lower(text), word, 1, true) ~= nil
end

-- A server Toast (text, kind) -> the key to play, or nil. Kinds: ok (purchase / unlock), cash (daily gift, quest
-- reward), rare (Lucky Meter, free eggs, streak shield), warn (refused / not allowed), info (no sound).
function SoundCues.toast(text: string?, kind: string?): string?
	local t = if type(text) == "string" then text else ""
	if kind == "ok" then
		return "ShopKaChing"
	elseif kind == "warn" then
		return "Denied"
	elseif kind == "cash" then
		if has(t, "quest") then
			return "QuestDone"
		elseif has(t, "daily gift") or has(t, "streak") then
			return "DailyClaim"
		end
		return "CoinPickup"
	elseif kind == "rare" then
		if has(t, "lucky meter") then
			return "LuckyMeter"
		elseif has(t, "quest") then
			return "QuestDone"
		elseif has(t, "streak") then
			return "DailyClaim"
		end
		return "LuckyMeter"
	end
	return nil
end

-- A PvpNet.PvpEvent message -> the key to play here, or nil. The Pet Battle panel (ui/PvpPanel) plays the win,
-- level-up and evolve keys itself; TowerView plays hit, crit, SPECIAL and K.O. per fight event.
function SoundCues.pvp(msg: any): string?
	if type(msg) ~= "table" then
		return nil
	end
	if msg.Kind == "Start" then
		return "BattleMatched"
	elseif msg.Kind == "Result" and msg.Result == "Loss" then
		return "BattleLose"
	elseif msg.Kind == "Trained" and not msg.LevelUp and (tonumber(msg.Gain) or 0) > 0 then
		return "TrainTap"
	end
	return nil
end

-- A TowerNet.TowerEvent message -> key, or nil.
function SoundCues.tower(msg: any): string?
	if type(msg) ~= "table" then
		return nil
	end
	if msg.Kind == "FloorEnd" then
		return if msg.Result == "Cleared" then "FloorClear" elseif msg.Result == "Lost" then "BattleLose" else nil
	end
	return nil
end

-- A Retention remote kind -> key, or nil (gifts that pay coins open with the gift sound).
function SoundCues.retention(kind: string?): string?
	if kind == "Gift" or kind == "Friend" or kind == "Group" then
		return "GiftOpen"
	end
	return nil
end

return SoundCues
