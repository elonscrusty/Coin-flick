# Audio and effects (Phase 5)

Pickup, Deposit and MaterialFound were added in the m9 pass (uploaded with the repo tool, ids in `SoundIds`; not listened to in Studio).
All sounds are original, synthesised by `tools/synth_sfx.py` (numpy + ffmpeg, no samples from anywhere).
Files: `art/sfx/*.ogg` (mono, 44.1 kHz, about 360 KB in total). Uploaded asset ids: `art/sfx/uploaded_ids.json`,
generated Luau table: `src/shared/SoundIds.luau` (id 0 = not uploaded, the client then plays nothing).

Status: offline only. Uploaded to Roblox (all 25 returned an asset id) but NOT listened to or moderation-checked in
Studio. Roblox may still moderate a file later; if one is rejected it stays silent and the owner should re-upload.

## Catalog

| Sound | Length | Used by |
|---|---|---|
| HammerHit1-3 | 0.16 s | own strike contact (`PileView`), other players' hits (positioned) |
| StoneCrack1-3 | 0.3-0.4 s | a rock removed |
| GravelSpill1-2 | 0.7-0.95 s | rubble from a cracked rock (half the time), sale hopper |
| JackhammerStart / Loop / Stop | 0.7 / 1.0 loop / 0.5 | held jackhammer (`Audio.machineActive("self:jack", "Jackhammer")`) |
| ConveyorHum | 2 s loop | machine hook: `Audio.machineActive(key, "Conveyor", pos)` |
| PressDescend / PressImpact / PressRetract | 1.1 / 0.9 / 0.9 s | machine hook: `Audio.play("PressDescend", {Pos = p})` etc. |
| CrusherLoop | 2 s loop | machine hook: `Audio.machineActive(key, "Crusher", pos)` |
| GeodeReveal | 2 s | reveal shimmer step (`ResultsPanel`) |
| RarityAccent | 1.6 s | reveal, Uncommon and up, pitch rises with rarity |
| Pickup | 0.28 s | own pickup from the shared pile (`CarryGlimpse` -> `Audio.pickup`) |
| Deposit | 0.4 s | own deposit that moved rocks to the table (`Main.client` RockReply -> `Audio.deposit`) |
| MaterialFound | 1.0 s | first-time material notice (`Main.client` MaterialFound -> `Audio.materialFound`) |
| Sale | 0.6 s | `Fx "Sell"` (`Main.client.luau`) |
| Purchase | 0.7 s | any Toast of kind "ok" (shop buys, unlocks, also "invite sent") |
| Button | 0.07 s | every enabled `UI.button` press |
| CountdownTick | 0.15 s | each second of the hunt countdown, higher on the last |
| MatchWin | 2 s | reveal, versus win only (not solo or practice) |
| LobbyAmbience / QuarryAmbience | 12 s loops | one bed at a time: lobby, or arena while in a match (Master 8 pass: re-synthesised quieter and non-tonal; lobby = soft wind, distant waterfall rush, a few sparse bird calls; quarry = wind, low ground rumble, rare far gravel trickle, a very faint distant machine thrum; new ids 122930016244785 / 119856364587738, not listened to in Studio) |
| MachineHum | 4 s loop | soft motor hum near a working hydraulic press (Ambience bus, positioned, heard within 40 studs, fades 4.5 s after the last stroke; started by `Audio.play` of the press one-shots); id 114419246012514, not listened to in Studio |

Loops are built from whole beats and circular filters, so they repeat without a click.

## Mix

`SoundService.CTR_Audio` holds three SoundGroups, driven by the saved settings:

- SFX = `Settings.Sfx` (default 0.8)
- Music = `Settings.Music` (default 0.6); no music files exist yet
- Ambience = `Settings.Music` x 0.6, crossfaded over 1.2 s when the area changes (State "Match" decides lobby vs arena).
  The press hum also plays on this bus; leaving the arena stops every hum at once (no hum carried into the lobby).

Per-sound base volumes are in `BASE_VOLUME` in `src/client/Audio.luau`.

## Attenuation and caps (all in Audio.luau)

- Positioned sounds (other players' hits, rock removal, sale gravel, machines) use `LinearSquare` roll-off:
  full volume inside 14 studs, silent at 95 studs; farther than 95 studs they are never created.
- Your own strike and UI sounds are flat (not positioned).
- At most 8 live positioned sounds and 6 live flat sounds; extra requests are dropped.
- Per-sound cooldown (`COOLDOWN`), e.g. hammer 0.06 s, jackhammer start 1 s, press 0.8 s, button 0.05 s.
- At most 4 machine loops at once (nearest win; three machines plus your own jackhammer). A loop stops itself 0.35 s after the last
  `Audio.machineActive` call and plays its stop sound once, so machine and jackhammer sounds cannot pile up.

## Effects (`src/client/Effects.luau`, client only, pooled, each piece <= 1 s, no camera shake)

- `Effects.cashFly(worldPos, amount)`: 2-6 small coins from the hopper to the HUD cash row (set by `Hud.build`).
- `Effects.shimmer(topLeft, size)`: sparkles around the geode in the reveal.
- `Effects.confetti()`: gentle confetti spawned over 2 s for the winner (Tutorial excluded).
- `Effects.glint(worldPos)`: machine-recovery glint (4 pooled emitters). Hook point only: nothing calls it yet,
  the machine code should call it when a machine recovers.
- Reduced motion: no moving effects at all. Low effects: half the pieces. `Effects.clear()` runs when the reveal closes.

## Hooks for the machine code

```lua
local Audio = require(script.Parent.Audio)  -- from src/client
Audio.machineActive(machineId, "Conveyor", position) -- call every ~0.2 s while it runs
Audio.play("PressImpact", { Pos = position })
Effects.glint(position)                              -- on recovery
```

## Regenerate and upload

```
python3 tools/synth_sfx.py [--only HammerHit1,Sale] [--wav]       # writes art/sfx
ROBLOX_USER_ID=20194281 python3 tools/upload_audio.py [--only A,B] [--force]
```

The upload script uses the Open Cloud Assets API (assetType Audio). The cloud environment adds the `x-api-key`
header for `apis.roblox.com`; locally set `ROBLOX_API_KEY`. Already uploaded files are skipped unless `--force`.
It rewrites `art/sfx/uploaded_ids.json` and `src/shared/SoundIds.luau`; failed files keep id 0.

## Find The Pet moments (Item 20, 2026-10-15)

Which sound plays at which moment: `src/shared/SoundCues.luau` (`SoundCues.Moments`, reveal cues per rarity, toast /
Pet Battle / tower / gift rules), played by `client/Audio`, `client/SoundCueView` (server messages), `Main.client`
(toasts, pet found), `TowerView` (hit, crit, SPECIAL, K.O.), `RevealView` / `HatchShow` (hatch), `PetLevelFx` (level up)
and three lines in `ui/PvpPanel` (battle win, training level up, evolve) plus one in `ui/UI` (tap on a greyed-out
button). Checked by `tests/test_sound_cues.luau`.

Pets never roar (owner rule): no roar keys exist. Big hatches use `HatchSparkle` (Epic+, sparkle swell) and
`HatchDrum` (Legendary and the Void Dragon, drum hit).

New made sounds (`tools/synth_pet_sfx.py`, all peak-normalized to -3 dBFS, 0.14-1.9 s): HatchSparkle, HatchDrum,
PetFound, EggGrab, EggDrop, BattleMatched, PetCrit, PetKO, BattleWin, BattleLose, TrainTap, LevelUp, Evolve, FloorClear,
DailyClaim, GiftOpen, QuestDone, LuckyMeter, Denied. Ids are 0 until uploaded (owner steps: "Game sounds"); until then
EggGrab, EggDrop, BattleWin, LevelUp and Evolve play their old stand-in (`SoundCues.Fallback`), the rest are silent.
Not listened to in Studio.
