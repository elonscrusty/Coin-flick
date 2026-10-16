# FIND THE PET! pre-release audit (2026-10-11)

Audit only. No game file was edited, nothing was committed or pushed, nothing was published.

- Repo: `elonscrusty/Crack-the-rocks`, branch `main`, commit `b8cd9fb` ("Forest needs 5 finds, Mythic Legendary 1 in 100, MaxLuck 4").
- Place files read from disk (read-only, copies parsed): `Desktop/FindThePet.rbxlx` (XML, 09:02) and
  `Desktop/FindThePet_WITH_LOBBY.rbxl` (binary, 09:06, newest). Studio itself was not driven; nothing was played.
- `tools/check.sh` run once with Windows builds of the same tool versions (Rojo 7.4.4, luau-lsp 1.52.1, Lune 0.10.4):
  `TYPECHECK: ok`, `COMPILE: ok`, `TESTS: 256 passed, 0 failed`, `BUILD: ok (lobby/single-place + match)`.
  But 60 of 138 `src` files have no `--!strict` line, so they were checked in non-strict mode (list in section 3C).
- Offline UI preview: **BLOCKED** on this PC (no Node, `python3` is the Microsoft Store stub). UI section is a code review.
- `/mnt/project-files` is not reachable from this PC, so `audio/sound-list.md` and `plans/new-pet-models.md` were not read.
- Owners of sound / mesh ids cannot be looked up offline. Every id is "owner unknown, NEEDS STUDIO TEST" unless docs say so.

Updates since the prompt was written, confirmed in code: Forest = 500 coins **and 5 finds** (Config.luau), Mythic egg
Legendary weight 1 (Void Dragon in Space = 1 in 100), `RobuxConfig.MaxLuck = 4`.

---------------------------------------------------------------------------------------------------------------------

## Fix list

### CRITICAL (breaks game, exploit, live failure)

1. **Place file is out of date and has test scripts in it.** `FindThePet_WITH_LOBBY.rbxl` has 38 scripts older than
   `main` plus Studio-only scripts: `ServerScriptService.TEMP_HideOldLodge` (moves the code-built lobby 3000 studs away so
   the hand-placed `Workspace.FTP_Lobby` shows) and `StarterPlayerScripts.PetPreview` ("Delete before release").
   Publishing that file ships old code; publishing a fresh Rojo build loses the hand-placed Meshy lobby (557 MeshParts,
   34 mesh/texture ids not in the repo). Fix: decide which lobby is real, move it into the repo flow (or a Rojo-safe
   place layer), delete both test scripts, re-sync every script from `main`.
2. **Egg wobble hint gives away the pet egg.** `EggConfig.luau:23-26` PatchJitterMax 3 < PatchRadius 3.5, so the pet egg
   is always inside its own patch; Meadow wobbles are pet-only (`EggHints.luau:67-75`), so 2-3 wobbles intersect to one egg.
   Breaks the rule "a wobble never names one egg". Fix: jitter max > radius (e.g. radius 3.5, jitter 2.5-5), always mix decoys.
3. **Any party leader can kick strangers out of the hunt queue.** `PartyService.luau:585-587` `Kick` calls
   `unqueuePlayer(arg)` for any userId before checking the target is in the caller's party. Fix: only unqueue a member.
4. **Teleport/speed check can be beaten.** `RockService.luau:46-73, 268`: position is sampled 0.5 s apart but each action
   uses the live position, so teleport to pile, pick, teleport back is never caught; slack allows about 36 studs/s.
   Fix: check distance from the last trusted sample at action time and cap per-action travel.
5. **Luck Potion is sold without the PolicyService check.** `RobuxService.luau:241-254` sells it to everyone, but it
   raises random-pet odds (`LuckEvents.luau:46-54`, `GeodeGen.luau:70-76`), so it counts as a paid random-item boost.
   Fix: hide/refuse it when `ArePaidRandomItemsRestricted`, same as eggs.

### HIGH

1. Profile load can die outside pcall: `Profiles.luau:325` (`reconcile`) and `onJoin` 842-876. Player gets no profile,
   no kick, lock held up to 300 s. Fix: pcall the whole load, kick with a message on failure.
2. Release save can overwrite newer data from another server after a long DataStore outage (`Profiles.luau:374-378`);
   lost lock is silent (`393-397`). Fix: compare a revision number; kick or toast when the lock is lost.
3. Tower pets almost impossible: boss floors are never replayed (`TowerRules.luau:64-67`, checkpoint after the boss),
   one roll each. Chance to own Astral Kitsune by floor 100 is about 3%. Fix: re-roll on boss re-clears or pity counter.
4. Tower drops are priced as Space pets (`TowerService.luau:274, 287`): about 11.5k coins average, from floor 5.
   One sale beats the Forest+Snow+Volcano unlocks. Fix: price by floor band or make tower pets unsellable.
5. Robux egg pets can be sold for coins (`EconomyService.luau:468-516`): a 10x Mythic pack in Space is about 205k coins.
   That is Robux buying upgrades. Fix: mark bought pets unsellable or sell for a token amount.
6. Pet Master / found count wrong: `PetFlair.luau:40-52` counts tower and unreleased weekly pets, `species()` (28-37)
   does not. Title can fire early; toast can read "36/35". Fix: count only species in `species()`.
7. Chirp hint points at the pet egg: `EggEvents.luau:110-146` only fires within 8 studs of the pet egg, 2-4 studs from
   it. Two chirps triangulate it. Fix: also chirp decoys, or widen the jitter.
8. All 5 zones use the same Meadow arena: `ArenaBuilder.build(slot, c)` (`ArenaBuilder.luau:447`) has no zone input.
   Forest/Snow/Volcano/Space have no own look yet.
9. 60 files not `--!strict` (list in 3C), including Profiles, RockService, MatchService, EconomyService, RobuxService.
10. Tower HUD ignores TouchLayout (`TowerPanel.luau:148-170`): SPECIAL can sit on the thumbstick in portrait; LEAVE 36 px.
11. Touch targets under 44 px on real phones: 44 is logical, UIScale goes to 0.8 (`Theme.luau:74-81`); tabs 34;
    Pet Book rename 26, toolbar 30, footer 28 (`CollectionPanel.luau:189, 276, 348`); tutorial SKIP/OK 36 (`Hud.luau:402,406`).
12. Sounds that may fail live: all 50 species roars share public id 820661880; RaceMusic 1837560399 is an old id;
    CoinPickup, SpeedBoots, TowerHit, TowerSpecial, BossRoar, EggChirp are never played by code; `EggConfig.Chirp.SoundId`
    is a hard-coded 0 that ignores `PetSoundIds.EggChirp`.
13. 182 mesh "Model" assets load with `InsertService:LoadAsset` (`MeshIds`); this breaks if the game moves to a group or
    the assets are not owned by the game owner. NEEDS STUDIO TEST on the live game.
14. StreamingEnabled is not set in `default.project.json` / `match.project.json`. Both place files say false. If the live
    place turns it on, `StationView.luau:104-117`, `MachineView.luau:186-190` and others look up far parts once and break.
    Fix: set `StreamingEnabled = false` in the project files.

### POLISH

- `MatchService.finishRound` (410-507) and the award task (408-444) have no pcall; an error holds the profile 15 s.
- Overtime glow is skipped if the pet egg is being carried at 3:00 (`EggEvents.luau:74-75`); wobbles then stop.
- No hard round time limit; a round can run forever if nobody cracks the egg (planned, not built).
- Pending key with no ledger entry never resolves (`AwardLedger.luau:156-158`); tutorial rounds create such keys.
- BindToClose waits for profiles (25 s) but not leaderboard writes or `Ledger.markApplied`.
- Starter pet flag set before the insert (`PetService.luau:78-82`); tower drops and bonus pets skipped silently when book is full.
- PetMotion keeps un-parented pets and every Bone forever (`PetMotion.luau:118,127,140`); no distance culling for display pets.
- Low Effects misses Rainbow/Silver sparkles and Legendary beams (`PetModel.luau:592,620`) and all of TowerView.
- Late-loading sounds are cut after 3 s (`Audio.luau:215`), can clip the 4 s hatch build-up.
- PromptTriggered handlers (sell hopper, secret egg, gallery) trust range; RenamePet toasts, MatchAction Sync, BuyRevive not rate-limited.
- "Play with a friend" quest counts strangers (`QuestService.luau:91-102`).
- Upgrades to Egg Shop has no way back (`ShopPanel.luau:541-543`); notice X 30 px; Party kick X has no confirm.
- Gallery `likes` table never pruned; LobbyLaunch entries kept in Failed phase (teleport mode off).
- Stale comments/docs: BadgeService header "10 species", TowerService "revive not built", docs `XPPerLevel`.
- Spec wording to fix: speed boots are a 4% roll on cracking an egg, not a pickup; variant sell values are
  Golden 1.5 / Skeleton 2 / Rainbow 3 / Silver 5; levels live in `TowerConfig.Levels`; chase odds are 1 in 1000 only at
  zero luck (max luck about 1 in 320); pets can be sold for coins (main income from Snow up).

---------------------------------------------------------------------------------------------------------------------

## Studio tests for carter (things code alone can't prove)

Open the newest place. Press **Test > Play** unless it says 2 players.

1. **Save test.** Play, get some coins, buy a basket, equip a pet, rename it. Stop. Play again.
   You should see: same coins, basket, pet, name, equipped pet, unlocked zones.
2. **Pet egg secret.** Start a solo Meadow hunt. Watch 3 wobbles. You should see: the wobbling eggs are a group, and
   the pet egg is not always the middle one. (Today it will be inside every group: that is CRITICAL 2.)
3. **Overtime.** Start a hunt and do not crack the pet egg for 3 minutes. You should see: one egg glows gold.
4. **Full Pet Book.** Fill the book to 100, then win a hunt. You should see: the pet is still added and a message
   says the book is full.
5. **2 players.** Test > Clients and Servers > 2 players > Start. Both step on one queue nest. You should see: one
   20 s countdown, both in the same arena, each with own nest, no bumping, one winner, both back in the lobby.
   Then on player 2 leave the queue and rejoin; player 1 should not be removed.
6. **Leave mid-round.** In the 2-player test, close player 2 right after cracking the pet egg. Rejoin.
   You should see: the pet is in player 2's book once (not twice, not missing).
7. **Sounds.** Play a hunt with sound on. You should hear: lobby music, race music, egg tap, egg crack, hatch roar.
   Write down any that are silent; check Output for "Failed to load sound".
8. **Pets move.** In the lobby, equip each of the 10 meshed pets (Raptor, Ostrich, DireWolf, Griffin, FrostWyvern,
   Mammoth, LavaTRex, Phoenix, CosmicDragon, StarPterodactyl). You should see: they walk/bob, no frozen T-pose.
9. **Phone screens.** Test > Device > a small phone (iPhone SE) landscape, then portrait. Open every menu.
   You should see: every button easy to tap, nothing under the jump button or thumbstick, every menu has an X.
10. **Tower.** Climb to floor 6 with 3 pets. You should see: SPECIAL button not on top of the thumbstick, boss on floor 5.
11. **Low Effects.** Settings > Low Effects on, hatch a Rare+ pet. You should see: fewer sparkles.
12. **Robux shop.** Open the egg shop. You should see: odds listed before the buy button. (Do not buy; ids are 0.)
13. **Meshes.** In the live game (not Studio), check Output for "Asset is not trusted" or "failed to load" on meshes.

## Things carter must do

- Create badges (FirstHatch, FirstRare, AllHuntPets, Tower25, Forest, SecretEgg, Pet Master) and paste ids into
  `ProgressConfig.Badges` / `Config.PetIndex`.
- Create dev products (Basic/Rare/Mythic egg x1/x3/x10, Luck Potion, cosmetics in `Config.Products`) and passes
  (DoubleCoins, ExtraPlots, PetStorage) and paste ids into `RobuxConfig` / `Config.Products`. Tower Revive is already 3717828140.
- Pick a weekly-pet start date for `Config.WeeklyPets.Start`.
- Upload the made sounds (EggTap, EggBreak, EggChirp, CoinPickup, SpeedBoots, TowerHit, TowerSpecial) and per-species
  roars as your own account, paste ids.
- Game Settings: Max Players 12. Workspace.StreamingEnabled off (or ask for the client fixes first).
- Decide which lobby is the real one (code-built park or the hand-placed `FTP_Lobby` in the place file).
- Before publishing: delete `TEMP_HideOldLodge` and `PetPreview`, and rebuild the place from `main`.
- Make sure every mesh/sound id is owned by your account (kcdrewcarter 20194281) or your group.

---------------------------------------------------------------------------------------------------------------------

# Detailed tables

## Sections 1 + 2: Game summary and progression


Repo: scratchpad/repo (src/ only read). Nothing run in Studio. "L" = line in the cited file. Names are old on purpose (rock = egg etc.).
Status words: PASS = proven from code. FAIL = code differs from spec or is wrong. NEEDS STUDIO TEST = cannot be proven from code.

## 1. GAME SUMMARY

### 1a. Core loop numbers
| Feature | Status | File + line | Problem | Fix |
|---|---|---|---|---|
| 12 players per server | PASS (config) | shared/Config.luau:431 `LobbyMaxPlayers = 12` | Only a number in code. The real cap is Studio Game Settings Max Players. | Owner: set Max Players 12 in Studio. |
| Queue: 4 racers, 20 s wait, starts at once when full | PASS | shared/QueueConfig.luau:11,13,14 (Size 4, Seconds 20, StartWhenFull) | Spec calls the 20 s a "countdown". The in-hunt countdown is 3 s (Config.luau:408). Both exist, no bug. | Spec wording only. |
| 4 queue pads QueuePad1..4 | PASS | shared/MapNames.luau:21-23, server/MapHooks.luau:138-163 | Hooks only. Pads exist only if map/ParkBuilder has them. | NEEDS STUDIO TEST to see them. |
| 150 eggs per zone, one shared pile | PASS | shared/Config.luau:45,51,57,63,69 (`Rocks = 150` all zones); RoundRocks.luau:157-165 | Pile size does not grow with party size (Config.luau:24 comment). | none |
| Basket starts at 3 | PASS | Config.luau:114 `Capacity = 3`; ProgressConfig.luau:18 | none | none |
| Exactly ONE egg hides the pet, uniform random, never rerolled | PASS | shared/RoundRocks.luau:204-205 (`TargetId = NextInteger(1, count)`) | none | none |
| Whoever cracks it keeps it | PASS | RoundRocks.luau:416-431 `finishRock` sets Winner; server/MatchService.luau:395-459 | none | none |
| Reveal ~2 s Common/Uncommon, ~6 s slow-mo Rare+ | PASS | Config.luau:347-352 (Normal 0.4+0.9+0.7=2.0, Slow 0.6+4.0+1.4=6.0, +Hold 0.2); shared/PetFlair.luau:HatchTiming | Server Reveal phase uses PetFlair.revealSeconds (MatchService.luau:445). Config.Match.RevealSeconds 2.8 (Config.luau:412) is unused default. | none |
| Overtime: pet egg glows gold after 3 min | PASS | shared/EggConfig.luau:37-41 (180 s); server/EggEvents.luau:68-80 | Only if the egg is still in the pile, never in practice. Starts at the first scheduler tick of Searching. | none |
| Patch wobble every few seconds, never one egg id | PASS | EggConfig.luau:7-32 (Meadow pet-only 8-12 s, decoys from Forest 3-5 s, patch radius 3.5, max 8 ids); EggEvents.luau header | Payload is a list of up to 8 ids that CAN contain the pet egg id (a hint). Spec "Meadow every few seconds" is really 8-12 s. | Spec wording. |
| Speed boots | FAIL (wording) | EggConfig.luau:60-68 | Not a "pickup". It is a 4% roll on each ordinary egg a player FINISHES CRACKING, +50% speed for 8 s, rolled on the server (RockService.luau:~199 `EggEvents.cracked`). | Fix spec wording. |
| No stealing/bumping | PASS (code) | server/RacerCollision.luau (whole file); MatchService.luau:~104 `RacerCollision.apply` | Collision off in hunts. Eggs are single-owner state machine (RoundRocks.luau pickup "Gone"). | NEEDS STUDIO TEST for the physics. |
| Solo practice 12 eggs, pet egg is one of eggs 2-6 CRACKED, skip button | PASS | Config.luau:423 (`Rocks=12, TargetFrom=2, TargetWithin=6`); RoundRocks.luau:201 (`TutorialBreak`), HP forced 1 (L129); Hud.luau:390-399 SKIP + confirm; EconomyService.luau:586-602 | Practice pet is a REAL roll with real rarity odds (can be Legendary Sunpetal Drake) and COUNTS AS A FIND (Profiles.luau:749, kind "Tutorial" falls in the SoloFinds branch). | Intended? If not, exclude "Tutorial" at Profiles.luau:749. |
| Server decides everything; pet egg never sent before found | PASS (this file set) | RoundRocks.luau header; EggEvents.luau:68-80 only exception (overtime) | Full leak audit is another section. | n/a |

### 1b. Zones table (Config.Tiers)
| Zone (id) | Spec | Code | Status | File + line |
|---|---|---|---|---|
| Meadow (Gravel) | 0 / 0, 2 per shell, HP1 | UnlockCash 0, UnlockFinds 0, CashPerRubble 2, HP 1 | PASS | Config.luau:44-49 |
| Forest (Quarry) | 500 / 5, 5, HP2 | 500, 5, 5, 2 | PASS (updated spec confirmed) | Config.luau:50-55 (L52) |
| Snow (Cavern) | 4000 / 15, 12, HP4 | 4000, 15, 12, 4 | PASS | Config.luau:56-61 |
| Volcano (Volcanic) | 25000 / 35, 25, HP7 | 25000, 35, 25, 7 | PASS | Config.luau:62-67 |
| Space (Meteor) | 100000 / 75, 50, HP10 | 100000, 75, 50, 10 | PASS | Config.luau:68-73 |
| Unlock rule | coins AND finds, previous zone first | EconomyService.luau:375-396: finds check, previous tier check, then `spend`. No negative coins (L48-55). | PASS | EconomyService.luau:375-396 |
| Public queue zone | not in spec | Public/mixed queue hunts in the HIGHEST zone EVERYONE in the queue has unlocked (HuntQueue.luau:203-218, PartyService.luau:399). A Space player queued with a Meadow player plays Meadow. | NOTE (design) | PartyService.luau:368-415 |

### 1c. Pets
| Feature | Status | File + line | Problem | Fix |
|---|---|---|---|---|
| Rarity weights 60/25/11/3.9/0.1 | PASS | Config.luau:190 (sum 100) | none | none |
| Per-zone ONE chase pet, Legendary only | PASS | Config.luau:243,252,260,268,276 (`Chase = true`: CosmicDragon, SunpetalDrake, Elderhorn, FrostcrownDragon, InfernalHydra); SpeciesPool.luau:(n-165) `pick`/`chance`/`rarityAllowed` | none | none |
| Chase odds "true 1 in 1000" | FAIL (nuance) | GeodeGen.luau:74-83 (`v*(1+l)` for Rare+ incl. Legendary); SpeciesPool.chance L76-87 | 1/1000 holds only at zero luck. Luck raises Legendary share: luck 1 = ~1/575, luck 4 (max) = ~1/320. Robux Rare egg 0.5% (1/200) and Mythic 1% (1/100) (RobuxConfig.luau:25,28-29 rel.). Luck does NOT change which egg hides the pet (RoundRocks.luau:204, PASS). | Spec: say "1/1000 base, up to ~1/320 with max luck". |
| Others split rest equally | PASS | SpeciesPool.luau `chance`: `rest/#normal` | none | none |
| 35 launch hunt species (7 per zone) + 10 weekly | PASS | Config.luau:234-284. Per zone launch: Meadow 7 (Raptor, Ostrich, Puffquill, Pebblehorn, Mosswhip, Honeyhoof + chase SunpetalDrake); Forest 7; Snow 7; Volcano 7; Space 7 (StarPtera, Cometpup, Moonhoot, Nebuclaw, LunarTusk, GalaxyStrut + CosmicDragon). Weekly 10 (2 per zone) flagged `Weekly = true`. | Names/zone lists match spec exactly. | none |
| 5 tower-only pets | PASS | Config.luau:285-291 (`TowerOnly`), TowerConfig.luau:75-81 (floors 5/10/15/20/30) | Drop reachability FAILS, see section 2. | see 2 |
| Weekly hidden while `Start = 0` | PASS | Config.luau:299-303; SpeciesPool.luau:14-23 (`math.huge`); SpeciesPool `available` skips unreleased; PetFlair.species L28-37; CollectionPanel.luau:581 | Client Book uses the CLIENT os.time() (CollectionPanel.luau:572,581) while the server uses server os.time(): a wrong client clock shows/hides weekly pets wrongly. Cosmetic. | Use a server-synced time or server-sent species list. |
| Variants Natural/Golden/Skeleton/Rainbow/Silver Cosmic | FAIL (numbers) | Config.luau:215-218: weights 90/7/2/0.8/0.2; sell-value mult 1/1.5/**2/3/5** | Spec says Golden 1.5x, Rainbow 2x. That matches TowerConfig.VariantStat (TowerConfig.luau:163: 1/1.5/1.75/2/2.5) = tower STATS. The SELL VALUE mult is Rainbow 3x, Skeleton 2x, Silver 5x. Both exist; spec mixes them. | Spec: list both tables. |
| Poses Sitting/Standing/Waving/Sleepy | PASS | Config.luau:209-212 (weights 45/25/20/10) | none | none |
| Boost kinds Coins/Speed(cap 15%)/Luck | PASS | Config.luau:314-341 (KindScale Speed 0.4, KindCap Coins .5 / Speed .15 / Luck .5, Slots = 1); Profiles.luau:632-645 `petBoosts` | none | none |
| Tower drop 8% + 0.2%/floor, max 25% | PASS | TowerConfig.luau:82-87; TowerRules.luau:115-121 (boss floors only) | none | none |
| Free starter pet once (Common Raptor) | PASS | PetService.luau:73-109, Config.luau:321 | Starter registers in DiscoveryIndex (L101), so it counts as "Raptor found" for AllHuntPets / Pet Master. No +50 coins for Raptor. | Owner decision, see badges. |
| Robux eggs: buyer's best zone, not finds/wins, not on RAREST board | PASS | RobuxConfig.luau:410-418 `eggTier`; Profiles.luau:749-755 (Bought not a find, no BestGeodeValue); RobuxService.luau:141-148 | BUT bought/tower pets can be SOLD for coins (EconomyService.luau:468-516) = Robux to coins conversion. See section 2 Q-economy. | see 2 |
| Totals "45 hunt (35+10) + 5 tower = 50" | PASS | Config.luau:234-291 | none | none |

### 1d. Currencies, luck, XP
| Feature | Status | File + line | Problem | Fix |
|---|---|---|---|---|
| Coins only currency, buys upgrades | FAIL (partial) | Profiles `Cash`; pets can ALSO be sold for coins | Coins are also earned by SELLING PETS (EconomyService.luau:468-516, `Config.Sell.SpecimenFraction = 1`, Config.luau:404). This is not in the spec and is the biggest coin source from Snow upward (section 2). | Add to spec or cap it. |
| Luck sources: pets, friends +10% x max 3, potion, weekend 2x, storm; clamp MaxLuck | PASS | QueueConfig.luau:35-38 (0.10, max 3); RobuxConfig.luau:50-53 (potion Luck 1, 15 min), 69-76 (weekend 1, storm 1/15 min), 84 (`MaxLuck = 4`); LuckEvents.luau:55-62 `total`; MatchService.luau:~383-392 | Friend luck only for the finder of a non-practice hunt. Potion +1, weekend +1, storm +1 = 3, pet and friends sit on top to the 4 clamp. | none |
| Pet XP/levels from tower `Config.Pets.XPPerLevel` | FAIL (stale spec) | `Config.Pets.XPPerLevel` does NOT exist (Config.luau:314-341). Levels are `TowerConfig.Levels = {XpBase 40, XpStep 25, Max 100, LevelStat 0.04}` (TowerConfig.luau:223), PetStats.luau:26-39. docs/FIND_THE_PET.md also stale. Levels only affect tower stats, not hunt boosts (Profiles.luau:632-645). | Spec/docs stale. | Fix spec. |
| Finds = SoloFinds + MultiplayerWins | PASS | Profiles.luau:661 (`finds`), 747-751 | Tutorial pet counts (Solo). Bought, Bonus, Tower do not. | none |

### 1e. Coin sinks
| Item | Spec | Code | Status | File + line |
|---|---|---|---|---|
| Baskets 3/4/5/6/8/10/12/15/20 for 0/400/3000/15000/40000/90000/180000/350000/700000 | as spec | identical | PASS | ProgressConfig.luau:17-27 |
| Nests Straw 0, Wood 800, Stone 6000, Gold 25000 | as spec | identical (queue 10/12/14/16) | PASS | ProgressConfig.luau:31-36 |
| Tappers Wooden 0, Golden 150, Rainbow 1800 | as spec | identical | PASS | Config.luau:89-93 |
| Hatchers Auto 10000, Egg Press 45000, Mega 180000 | as spec | identical (2 /s, 4 /s, 12 /s) | PASS | Config.luau:101-105 |
| Storage 30/100/300/1000/3000 for 0/200/1500/10000/50000 | as spec | identical | PASS | Config.luau:164-170 |
| Display slots 3/6/12/20 for 0/500/4000/20000 | as spec | identical (+10 Extra Plots pass) | PASS | Config.luau:176-182, RobuxConfig.luau:~63,70 |
| Pet book max 100 (+ExtraPetSlots, +250 pass) | as spec | identical | PASS | Config.luau:174, RobuxConfig.luau:(n-282) `ExtraPetSlots = 250`, Profiles.luau:668-672 |
| First find of species +50 | as spec | Applies to tower-only pets too (5 x 50) | PASS | Config.luau:357, Profiles.luau:726-729, PetFlair.luau:66-75 |
| Daily gift 25,35,45,60,75,100,300 | as spec | identical, once per UTC day, streak resets | PASS | ProgressConfig.luau:68, Quests.luau:195-206 |
| Daily quests: one Race, one Tower, one Pet per UTC day | as spec | identical | PASS | ProgressConfig.luau:74-85, Quests.luau:87-106 |
| Quest "Play N hunts WITH A FRIEND" | not a friend check | `withFriend` = ANY other player with the same MatchKey, strangers from the public queue count | FAIL (minor) | QuestService.luau:91-102 | Text lies. | Check `IsFriendsWith` (FriendBonus has a cache) or rename "with another player". |

### 1f. Badges
| Badge | Status | File + line | Problem | Fix |
|---|---|---|---|---|
| All 6 Ids = 0 (OFF) | PASS | ProgressConfig.luau:89-96 | none | Owner pastes ids. |
| Stored once in `Badges` map + UserHasBadgeAsync fallback; not remembered while id 0 so it fires later | PASS | BadgeService.luau:(369-415 in concat) award: AwardBadge pcall, then UserHasBadgeAsync pcall, only then `data.Badges[key] = true`; check skips Id 0 and does not store | 60 s retry per badge | none |
| Never for starter pet | PASS for FirstHatch | ProgressConfig.luau:156 `finds >= 1` (starter not a find) | BUT tutorial pet is a find, so FirstHatch fires after practice. And starter Raptor counts toward AllHuntPets / Pet Master. | Owner decision. |
| FirstRare = any Rare+ owned or ever hatched | PASS | ProgressConfig.luau:118-135 | none | none |
| AllHuntPets = all CURRENT hunt species | PASS | ProgressConfig.luau:103-111, 136-152 | Uses `SpeciesPool.list(tier, os.time())`, so it needs 35 now, 45 when weekly start set. Once the badge is awarded it is remembered (Badges map); an unawarded player is pushed back when a weekly species appears. | none |
| Pet Master title (Config.PetIndex) | FAIL | shared/PetFlair.luau:40-60 | `foundCount` loops ALL `Config.Minerals` (L45, no TowerOnly/unreleased filter), but `allFound` compares to `#PetFlair.species()` (hunt-only, 35). Owning the 5 tower pets counts as 5 of 35. A player with 30 hunt species + 5 tower pets gets "Pet Master" early. Toast count can read 36/35 (PetIndex.luau:310). | In foundCount skip `m.TowerOnly` and unreleased ids, or count over `PetFlair.species()`. |
| Tower25 | PASS (logic), reachability NEEDS STUDIO TEST | ProgressConfig.luau:99,159; TowerService.luau:309 | See section 2. | n/a |
| Forest | PASS | ProgressConfig.luau:100,154 `UnlockedTiers.Quarry` | none | none |
| SecretEgg | PASS | ParkBuilder.luau:553-572 (part+prompt "Take" built), MapHooks.luau:266-280, BadgeService.luau:(417-444) | none | none |
| Doc comment "found all 10 hunt pet species" | FAIL (stale) | BadgeService.luau:4 header | It is 35 now. | Fix comment. |

### 1g. UI screens
Hud, PlayButton, PartyPanel, LaunchPanel, ShopPanel, RobuxShopPanel, CollectionPanel, InspectPanel, ItemView, GeodeView, ResultsPanel, QuestPanel, SettingsPanel, TowerPanel, NewsPopup, RareBanner: all PASS as files in src/client/ui/. RevealView, HatchStandView, NameTag, PetFollow in src/client/. Tutorial hint card + SKIP confirm: Hud.luau:390-399 PASS. LobbyBoards, queue nest signs are server side (LobbyBoards.luau, SignLayout.luau, MapHooks:138). Collection tabs Pets/Book/Records/Stats/Display (CollectionPanel.luau:~716 `TABS`) include Records and Display that the spec omits; sort buttons L283, EQUIP BEST L366, NAME L187 PASS. Whether each renders: NEEDS STUDIO TEST (section 5 owner).

### 1h. REMOTES
| Remote | Dir | Status | File + line |
|---|---|---|---|
| RockAction, PartyAction, MatchAction, ShopAction, CollectionAction, SettingsAction, ClientReady, TutorialAction, LaunchAction, StoreAction, RobuxAction | C to S | PASS all 11 exist and are used | shared/Net.luau:10-20 |
| ProfileState, PartyState, Inspect, MatchEvent, Toast, LaunchEvent, Fx, RareHatch, EggEvent, HatchShow | S to C | PASS all 10 | Net.luau:22-31 |
| NOT in spec: ReplicatedStorage.TowerNet folder with **TowerAction** (C to S, `{Op=...}`: Open, SetTeam, EquipBest, Start, Special, Next, Revive, BuyRevive, Leave) and **TowerEvent** (S to C) | | extra, both RemoteEvents, created at TowerService.start | server/TowerService.luau:611-620; handler L536-602; client ui/TowerPanel.luau:276 |
| Any other remote? | | None. `grep Instance.new("Remote...")` finds only Net.luau:64 and TowerService:614,617. No RemoteFunction, no BindableFunction crossing the boundary. | whole src |
| Race risk: TowerNet created in TowerService.start, `Tower.server.luau` | | Client does `WaitForChild("TowerNet")` with no timeout (TowerPanel.luau:276). If TowerService errors at start the panel waits forever (infinite-yield warning). | TowerPanel.luau:276 | Add timeout. | NEEDS STUDIO TEST |
| Stale comment: TowerService "Robux revive is not built" | FAIL (comment) | TowerService.luau:~573 vs Revive.ProductId set | Revive IS built (BuyRevive, processReceipt). | Fix comment. |

### 1i. DATA
| Item | Status | File + line | Notes |
|---|---|---|---|
| DataStores CTR_Profiles_v1, CTR_Ledger_v1, CTR_Pending_v1 (+ "_Studio" in Studio) | PASS | Config.luau:448-452; Profiles.luau:26,31; AwardLedger.luau:20,24-25 | none |
| OrderedDataStores CTR_LB_Biggest / CTR_LB_Tower (+_Studio) | PASS | Config.luau:493-494; LeaderboardService.luau:31,58; MapNames.luau (Boards ids Biggest, Tower) | none |
| Keys by UserId `u_<id>`; pending `p_<id>` | PASS | Profiles.luau:272-274; AwardLedger.luau:96,148 | Ledger key = awardKey `matchKey:round`. |
| SchemaVersion 1, LockSeconds 300, Autosave 90, BindToClose | PASS | Config.luau:453-455; Profiles.luau:278-283, 904-930 (autosave check every 5 s) | BindToClose waits up to 25 s. |
| MessagingService topic "RareHatch" | PASS | Config.luau:365; RareHatch.luau:65,106 | none |
| UpdateAsync not SetAsync | PASS | Profiles.luau:309,367 | (full DS audit is section 3) |

Profile fields (Profiles.defaults, Profiles.luau:48-101): Schema, Cash, RubbleByTier, EquipmentOwned, EquippedHandheld, InstalledMachine (nil), CapacityTier, UnlockedTiers, InventoryGeodes (the pets), DisplayAssignments, DisplayCapacity, DiscoveryIndex, DiscoveryRarity, Cosmetics, Materials, TutorialStep, Onboard (Started, PickedUp, Deposited, Cracked, Geode, Sold, Displayed, Goal, Skipped), Settings (Music, Sfx, CameraSensitivity, ReducedMotion, LowEffects, Hints), Stats (SoloFinds, MultiplayerWins, MatchesPlayed, RocksCracked, CashEarned, BestGeodeValue), RecentAwardIds (kept 50), PendingAwards, EquippedPets, StarterPet, TowerBest, TowerXP, TowerReviveCredits, TowerReceipts, ExtraPetSlots, LastSeenNews, BasketLevel, NestLevel, Daily (Day, Progress, Claimed, GiftDay, Streak), SecretEggFound, TowerFloorsToday, Badges, Robux (Receipts, ReceiptOrder, LuckUntil, Passes, EggsBought, PotionsBought). All reconciled on load (Profiles.luau:105-269). Note `PendingAwards` is defined but unused in the files read (grep before deleting).

### 1j. ROBUX ids
| Item | Value | File + line |
|---|---|---|
| Tower Revive ProductId | **3717828140** (the only real id) | TowerConfig.luau:229 |
| Basic/Rare/Mythic x 1/3/10 (9 products) | all 0 | RobuxConfig.luau:23,26,31 (rel. 307,311,316) |
| Luck Potion ProductId | 0 | RobuxConfig.luau:~51 |
| Passes DoubleCoins/ExtraPlots/PetStorage | all 0 | RobuxConfig.luau:~61-63 |
| Cosmetic products (4) | all 0 | Config.luau:468-486 |
| Badges (6) | all 0 | ProgressConfig.luau:90-95 |
Status: PASS, matches spec. Odd: RobuxConfig.luau:5 comment says "ids 0 + REPLACE except tower revive" which is right. Egg odds: Basic = race odds, Rare 30/35/25/9.5/0.5, Mythic 11/25/40/23/1 (sum 100 each; Mythic Legendary 1/100 CONFIRMED). RobuxConfig MaxLuck = 4 CONFIRMED (L84).

### 1k. PLANNED NOT BUILT
| Item | Verdict | Evidence |
|---|---|---|
| Trading | not built (confirmed) | No trade code. docs say "No trading". |
| Pet hats/trails shop | not built | Config.Products are tool skins + gallery themes only (Config.luau:466-487), all id 0. |
| Group +5% luck | not built | No group code; LuckEvents sources have no group. |
| Hard round time limit | not built, but OVERTIME exists | EggConfig.luau:37-41 makes pet egg glow at 180 s. No forced end. Overtime is more than the spec says. |
| Teleport mode live | OFF but built | Config.luau:428 `Mode = "SinglePlace"`; LobbyLaunch/MatchPlace/Tickets exist. |
| Real meshes for 35 new pets + 5 tower + eggs + props | confirmed missing (stand-in bodies) | Config.luau:245,253,261,269,277,285 REPLACE comments; PetModel Kind stand-ins. |
| Badge/product/pass ids, weekly start, uploaded sounds | confirmed 0 | see above; Config.luau:300 `Start = 0` |
| Codes, emotes, hunger | none found | no such code |
| Half-done to add | (a) Pet Book "tower pets" have no tracker: Book only loops the 5 zones (CollectionPanel.luau:569-598) so tower pets never appear in any index. (b) `PendingAwards` field unused. (c) practice-round `SKIP` leaves `TutorialStep=1` with no find (EconomyService.luau:588-598). (d) `Config.Match.RevealSeconds`, `WaitForMembersSeconds` apply to Teleport mode only. |

## 2. PROGRESSION (real numbers)

### Assumptions (stated, not measured)
- A hunt: 150 eggs, ONE hides the pet. Eggs are cracked in effectively random order, so the pet egg is on average the 75.5th egg cracked: **74.5 shells + 1 pet** per round in total, across all racers.
- 4-racer public hunt, equal skill: each racer cracks 74.5/4 = **18.6 shells**, finds 25% of rounds. Solo: **74.5 shells**, find **100%** (solo party of 1; `m.Solo`, MatchService.luau:400). (Bag is 30 shells at level 1 (Config.luau:165), so a solo hunt needs a mid-hunt sell at the arena hopper (ArenaBuilder.luau:470 `Hopper`, RoundRocks.tryStart "StorageFull").)
- Time per egg tEgg = crack time + haul. Crack = HP / damage per hit / rate (Wooden 1 dmg 0.9/s, Golden 2 dmg 1.2/s, Rainbow 1 dmg 5/s hold, Config.luau:90-92, RoundRocks.luau:crush). Haul = 0.45 s pickup interval (Config.luau:114) + ~2.25 s round trip / basket size. Machines crack in parallel, so with a machine tEgg is the haul only.
- Overhead per hunt: ~30 s multi (queue fill ~10 s, countdown 3, reveal 2-6, results ~10), ~40 s solo (QueueConfig.Seconds 20 wait + same).
- Gear: whatever fits the phase (Meadow wooden + basket 3; Forest golden + basket 4; Snow rainbow + basket 5; Volcano auto hatcher + basket 8; Space egg press + basket 10).
- Expected pet SALE value per find (rarity mult 1.551 x variant mult 1.079 x mass factor 1.489, all independent, GeodeGen.luau:59-63, 91-92): Meadow **100**, Forest **374**, Snow **1,246**, Volcano **3,738**, Space **9,967**. Only SHELLS get the 2x pass (Profiles.luau:604, `coinMult`); pet sales are not doubled (EconomyService.luau:498).
- Pet coin boost ignored (+1-6%, a Common Coins pet is +3%).

### Step table (4-racer public queue, 25% win rate)
Cumulative finds needed to unlock: Forest 5, Snow 15, Volcano 35, Space 75 (Config.luau:52,58,64,70). The tutorial pet is find #1.

| Step | Finds still needed | Coins/hunt shells only (1x / 2x pass) | + sell the found pet (avg per hunt) | Hunts needed (finds / 0.25) | Hunt length | Time |
|---|---|---|---|---|---|---|
| 0 First join: starter Raptor + tutorial (12 eggs) | 1 (tutorial) | ~2 per shell, tiny | none | 1 (3 min, skippable) | ~3 min | 0.05 h |
| 1 Meadow to Forest (500 c + 5 finds) | 4 | 37 / 74 | 62 / 99 | 16 | 74 s (tEgg 2.31) | 0.33 h |
| 2 Forest to Snow (4,000 c + 15 finds) | 10 | 93 / 186 | 186 / 279 | 40 | 65 s (tEgg 1.84) | 0.72 h |
| 3 Snow to Volcano (25,000 c + 35 finds) | 20 | 223 / 446 | 534 / 757 | 80 | 62 s (tEgg 1.7) | 1.38 h |
| 4 Volcano to Space (100,000 c + 75 finds) | 40 | 465 / 930 | 1,400 / 1,865 | 160 | 44 s (tEgg 0.73, machine) | 1.95 h |
| **Subtotal to unlock Space** | **75** | | | **~297** | | **~4.4 h** |
| 5 Collect 30 non-chase species (6 per zone, each 16.65% per find; coupon collector 6 x H6 = 14.7 finds per zone) | ~74 finds | 930/hunt in Space | | ~295 hunts | ~45 s | ~3.7 h (spread over zones, but weekly species dilute it) |
| 6 Collect the 5 chase pets (each Legendary 1/1000 per find in ITS zone; sequential, expected 5 x 1000) | **~5,000 finds** | | | solo: 5,000 hunts; 4-racer: 20,000 hunts | solo 85-215 s by zone | **solo ~120-210 h; 4-racer ~280 h** at zero luck. With average luck 0.5 (Legendary x1.5 weight, about 1/660) ~ 3,300 finds ~ 80-140 h. |
| 7 Tower floor 25 (TowerBest >= 25) | | 7,125 coins total for clearing floors 1-25 (TowerRules.luau:99-106) | | | | NEEDS SIM, see below |
| 8 All 5 tower pets | | | | | | **practically unreachable**, see Q below |
| 9 All badges | | | | | | gated by steps 6 and 8 (AllHuntPets needs the chase pets; Tower25 via step 7) |

Solo path (every hunt = find, bag sell mid-hunt), same unlock chain: hunts needed 4 / 10 / 20 / 40 = 74 total. Hunt length: Meadow 214 s, Forest 179, Snow 168, Volcano 95, Space 91 (40 s overhead + min(75.5 x tEgg, ~190 s overtime cap)). **Time to unlock Space solo ~2.7 h vs ~4.4 h in 4-racer queue. Coins per find: Meadow 249+100, Forest 372+374, Snow 894+1,246, Volcano 1,862+3,738.** Solo is strictly faster per find than the public queue unless the player wins more than 25% (equal-skill case). The "race" is the slower way to progress.

Coin bind check (what limits each step): hunts are the limit when pets are sold. If the player never sells pets: Snow phase earns 17.8k of the 25k needed (+gear), Volcano phase 74k of the 100k (+ gear). They would need 112 and 269 hunts instead of 80 and 160, i.e. coin-bound.

Income not in the table: daily gift avg 91 coins/day (25..300), 3 quests ~150-200 coins/day, first-find +50 per new species (total ~50 x 35 = 1,750), tower floor coins (15 x floor, +150 x boss band, TowerConfig.luau:234-237). The tower is open from minute one (no unlock gate, TowerService.luau startRun requires only 1 pet).

### Explicit answers
| Question | Answer | Evidence |
|---|---|---|
| Never-win player still progresses (solo finds count)? | **YES.** SoloFinds count as finds. A solo hunt is a guaranteed find (m.Solo, kind "Solo"). Public-queue "never wins" can switch to solo and unlock everything. | Profiles.luau:661, 747-751; MatchService.luau:400; ProgressConfig.luau:118 |
| Soft-lock? | **No hard soft-lock found.** (1) Pet Book full (100) blocks queueing and party start (PartyService.luau:71,301; MatchService.luau:797) but pets can be sold (Sell). Favourites and displayed pets cannot be sold (EconomyService.luau:490-497), so a player with 100 favourites + displays must unfavourite first: UI-clear toast exists. There is no "release/delete" action, only Sell. (2) Shell bag full (30) blocks cracking until sold (RoundRocks.luau:tryStart `StorageFull`); hopper exists in arena and lobby. (3) Tower with 0 pets: "Hatch a pet first" notice, but starter pet prevents. | PartyService.luau:71,301; EconomyService.luau:468-516 |
| Coins negative / buy fails after taking coins? | **No.** `spend` checks `Cash < price` before subtracting, same tick, no yields between. Level buys have a 1 s double-tap guard and expected-level check. Tier unlock checks finds and previous tier before `spend`. | EconomyService.luau:48-55, 239-256, 333-396 |
| Pet Book "found X / Y" real count? | **YES for the Book tab:** X = species with DiscoveryIndex>0 or any rarity row, Y = SpeciesPool.list per zone (35 now, 45 after weekly). Matches ProgressConfig.huntSpecies. Tower pets are not listed in the Book (separate, no tracker). | CollectionPanel.luau:569-601; ProgressConfig.luau:103-111; PetFlair.luau:28-37 |
| Matches AllHuntPets / Pet Master? | **AllHuntPets: yes. Pet Master: NO**, `foundCount` counts tower pets (PetFlair.luau:45) against a hunt-only total. | see 1f |
| Releasing a weekly pet un-completes a badge/title? | **No release action exists; Sell leaves DiscoveryIndex/DiscoveryRarity untouched,** so nothing un-completes. But when a weekly species is first RELEASED, the Book total rises 35 to 36, AllHuntPets (not yet awarded) goes false, and the Pet Master title is dropped until the new species is found. An awarded badge stays (Badges map). | EconomyService.luau:468-516; BadgeService; PetFlair.luau:54-60 |
| Chase pets Legendary only, true 1/1000, luck never changes which egg hides it? | Legendary only: **YES** (SpeciesPool.pick returns chase only when rarity is Legendary, and chase can only be Legendary). Which egg: **YES** luck never touches TargetId (RoundRocks.luau:204). 1/1000 exact: **only at luck 0**; luck scales Legendary weight (GeodeGen.luau:77-80). | GeodeGen.luau:74-83 |
| Storage full (100) when finding the round pet: never lost silently? | **YES, never lost.** `grantSpecimen` has no capacity check, the pet is added over the cap; the book just blocks the next hunt. Same for ledger/pending replay. NOT the same for: tower drops (`rollDrop` returns nil silently when full, TowerService.luau:263-265, no toast) and Bonus pets (skipped, MatchService.luau:368). Robux eggs refused BEFORE the prompt (RobuxService.luau:230-237). | Profiles.luau:696-733 |
| Badges once (Badges map + UserHasBadgeAsync), never for starter, fire later when id set? | Once: YES. Starter: YES for FirstHatch, but starter Raptor DOES count for AllHuntPets/Pet Master. Later when id set: YES (id 0 not stored). | BadgeService.luau (award/check), ProgressConfig.luau:156 |
| First-find coins once per species? | **YES.** Read before count, paid in the same write as the DiscoveryIndex increment. Starter Raptor never pays (index already set by ensureStarter). Tower pets pay 50 too. | Profiles.luau:726-729, PetFlair.luau:66-75 |
| Daily gift once per UTC day, streak reset? | **YES.** GiftDay=today blocks; streak +1 only if GiftDay == today-1, else 1; day 7 wraps to 1; clock-ahead save blocked ("Clock", silent). | Quests.luau:185-206, QuestService.luau:152-159 |
| Rejoin: everything saved and restored? | Saved fields all in `defaults` and mutated then `Profiles.changed`. Rejoin cycle needs Studio. Equipped pets re-validated, levels clamped. | Profiles.luau:105-269 -> NEEDS STUDIO TEST |

### Progression findings (problems)
| Feature | Status | File + line | Problem | Fix |
|---|---|---|---|---|
| Tower pets Embergeist / Astral Kitsune / Voltwing reachability | **FAIL** | TowerConfig.luau:75-87; TowerRules.luau:64-67, 115-142; TowerService.luau:258-290, 390 | A boss floor (every 5th) rolls ONE drop when it is first cleared. The run always starts at `checkpoint(best)` = floor after the last boss (best 25 starts at 26), so each boss floor pays one roll, never again. Drop chance 8%+0.2%/floor (cap 25%) x species weight. Probability of owning each by max floor reached: floor 25: Thornback 26%, Frostbyte 15%, Voltwing 7%, Embergeist 2%, Kitsune 0%. Floor 50: 47/33/21/9/0.8%. Floor 100: 80/67/51/26/3%. Floor 200: 98/93/82/53/8%. Mob HP grows +16%/floor (TowerConfig.luau:216), floor 100 mobs have 16.8x HP. "All 5 tower pets" cannot be achieved in play. | Allow replaying boss floors (or a boss-floor retry), or guarantee a pity drop, or raise chance/weights (Kitsune 1/100 per drop is the killer). |
| Tower drops sell at Space prices | **FAIL (economy)** | TowerService.luau:274,287 (`tier` = last zone "Meteor", Value from GeodeBase 4000); EconomyService.luau:468-516 | A tower drop is worth GeodeBase 4000 x rarity x variant x mass: expected **11,503 coins**, a plain Common Natural Thornback 5,000. The first drop appears at the FIRST boss (floor 5, 9% chance). One drop sold = more than the whole Meadow-to-Volcano coin cost and ~10 hunts of Space. Floor 5 is reachable on minute 1. | Set Value from the species's home zone or a fixed small value, or block selling tower pets. |
| Robux eggs convert to coins | **FAIL (design)** | RobuxService.luau:141-148, EconomyService.luau:468-516, Config.luau:404 | Bought pets are not finds but can be sold. A Mythic Egg in Space averages ~20,467 coins sale value (x10 = ~205k). Spec/docs say coins are earned, pets "never sold for Robux" (Config.luau:312). Pay to get 2x worth of upgrades. | Block selling `MatchKey` Bought pets, or sell them for a fixed low value. |
| Pet sales dominate income from Snow up | NOTE | Section 2 table | Snow: pet 311 vs shells 223 per hunt; Volcano: 934 vs 465; Space: 2,492 vs 930. | Intentional? If not, rebalance shell price or pet Value. |
| Chase pets = ~5,000 finds | **FAIL (pacing)** | Config.luau:190, SpeciesPool `chance` | "All hunt species" (Pet Master, AllHuntPets) needs the 5 x 1/1000 pets: ~5,000 finds = ~100-280 h at base luck. 10 weekly species add more finds on top. | Pity timer, per-zone Legendary boost, or make chase pets 1/200-300. |
| Solo beats racing | NOTE | MatchService.luau:400 | Solo = guaranteed find with the same pet odds; multiplayer 25% finds per hunt. 2.7 h solo vs 4.4 h racing to Space. The competitive mode is the slower way. | Owner decision; maybe lower solo pet quality or slow solo shell income. |
| Pet Master title bug | **FAIL** | PetFlair.luau:40-60 | See 1f. | Fix `foundCount`. |
| "Play with a friend" quest | **FAIL (minor)** | QuestService.luau:91-102 | Any stranger counts. | Check friendship. |
| Tower floor 25 reachability | NEEDS STUDIO TEST | TowerRules.luau, TowerConfig.luau | Hand estimate with the shipped numbers: Common starter-level teams (Raptor base 90 HP / 12 power) get beaten around the floor 15 boss (Mammoth boss HP 520 x 3.24 = 1,685, 32 power). Floor 25 boss (Frost Wyvern, 450 x 4.84 = 2,178 HP, 63 power, 90 speed) kills a 130-HP Lv12 Common in about 2 hits. Needs Rare+/Legendary pets with levels (about 1,800 XP per pet for floors 1-25 = Lv 11-12, TowerConfig.luau:223-224). Run `TowerRules.simulate` (tests/test_pet_tower.luau) with real teams. | Simulate, then tune. |
| Practice pet is a real roll | NOTE | MatchService.luau:395-459 | Tutorial grants a normal Meadow pet of any rarity including 1/1000 Legendary, and a find. | Cap at Common or exclude from finds. |
| Public queue drags players down a zone | NOTE | HuntQueue.luau:203-218 | Mixed queues use the lowest common unlocked zone; high players farm Meadow to stay with friends. | Maybe give a zone vote. |
| Stale docs/comments | FAIL (docs) | BadgeService.luau:4 ("10 species"), docs/FIND_THE_PET.md "XPPerLevel", "all 10 species = Pet Master", TowerService.luau:~573 ("Robux revive not built") | Wrong info. | Update. |
| Daily "Display" quest farmable | NOTE | EconomyService.luau:421-423, 452,462 `QuestService.note("Display")` fires on every placement | Place/remove repeats to finish the 2-pet quest (50 coins/day cap). Trivial. | Count unique pets. |

## Section 3A: Code checks, security

Read-only static audit. Nothing run in Studio. Paths are relative to `repo/`. PASS only where the code proves it.

Remote inventory: 21 RemoteEvents in `src/shared/Net.luau:10-34` (11 client->server, 10 server->client) plus `ReplicatedStorage.TowerNet` {TowerAction (c->s), TowerEvent (s->c)} created at `src/server/TowerService.luau:611-622`. No RemoteFunctions. No cheat/admin/debug remote anywhere in `src/`. The list in AUDIT_PROMPT matches the code.
Strict mode: `RockService`, `MatchService`, `EconomyService`, `PartyService`, `StoreService`, `RobuxService`, `QuestService`, `AwardLedger`, `Profiles` have no `--!strict` (RoundRocks, Pile, EggEvents, PetService, TowerService, HuntLedger, Net, RacerCollision do). These are the security-critical files.

## 1. Client to server remotes, one row each

| Feature | Verdict | File + line | Problem | Fix |
|---|---|---|---|---|
| RockAction: arg types | PASS | RockService.luau:237-239 (action string in whitelist, roundId number); RoundRocks.luau:219-221 (rockId finite integer 1..Total), 228-230 (pos not NaN or huge) | none. Float/NaN/string/table rockId is rejected (`core.Rocks[1.5]` is nil, then `validId`) | - |
| RockAction: rate limit | PASS | RockService.luau:24, 241-245 (30 ms floor), 25 and 254-255 (toggle 0.4 s), 123-131 (reply 0.15 s); tables cleared by RockService.forget (411-416) from MatchService.luau:885 | none | - |
| RockAction: wrong state (lobby / tower / hunt phase) | PASS | MatchService.luau:730-736 (no match = ignored, so lobby and tower players are ignored); RockService.luau:247 (round id, phase == Searching, Present); RoundRocks.luau:233-245 | none | - |
| RockAction: fake roundId | PASS | RockService.luau:247, RoundRocks.luau:234 | stale or forged round id silently dropped | - |
| RockAction: fake rockId | PASS | RoundRocks.luau:320, 328-343 (must be InPile, exposed, layer <= ReachLevels, in range) | a client can name any reachable pile egg, but nothing about it reveals the pet egg | - |
| Pickup: range, height, sight, one egg per interval | PASS | Range RoundRocks.luau:338 (PickupRange 8 + RockSize/2, Config.luau:114); height 341 (PickupHeight 12); sight RockService.luau:146-184 and 277-284 (fails closed); interval RoundRocks.luau:324 and 344 (NextPick += 0.45, tolerance 0.12; debt accumulates so average is 0.45 s); exactly one rock moves per accepted Pickup (345-349) | positions are the avatar root (client-owned physics), see Motion row | - |
| Deposit / Crush: nest range, own station, cadence | PASS | Station comes from membership, never from the client: RoundRocks.luau:369 (DepositRange 10), 485 (CrushRange 9), 375 (DepositTolerance), 490 (Match.CadenceTolerance 0.3, Config.luau:415), 503 (NextHit += 1/Rate on success only) | none | - |
| Config.Motion teleport check | FAIL **HIGH** | RockService.luau:46-73, 268; Config.luau:119 | (a) Samples position at least 0.5 s apart (60-70) but each action is judged on the instantaneous position (271). A cheater who teleports to the pile, fires Pickup, and is back at the nest before the next sample never trips it. (b) Sustained speed allowance = max(WalkSpeed,16) x 1.25 x dt + 8 slack per 0.5 s, about 36 studs/s (2.25x normal), about 50 studs/s with boots or speed pets, undetected. (c) Vertical is never checked. | Remember last accepted action position and time per player in RockService.action and reject any Pickup/Deposit/Crush whose horizontal distance from the previous action exceeds WalkSpeed x SpeedFactor x dt + small slack. Drop Slack to 3-4. |
| ToggleMachine | PASS | RockService.luau:251-261; MatchService.luau:866-881 (owner attr check, 0.4 s) | none | - |
| MatchAction (Return / Rematch / StartRematch / Sync) | PASS (types) / POLISH (rate) | MatchService.luau:856-863 (0.25 s), 759-811 (only Present members; StartRematch needs Results phase, leader, all ticked, Pet Book room) | `Sync` re-sends the full Init (Stacks, Removed, Stations) up to 4 times a second per client (805). | Limit Sync to 1 per 2 s. POLISH |
| PartyAction: types, rate | PASS | PartyService.luau:545-547 (action string), 617 (Invite id number), 641 (Accept id string), 666 and 680 (Kick/Tier types; Tier must exist in Config.Tiers), 710-723 (8 per second) | none | - |
| PartyAction Kick removes arbitrary players from the public queue | FAIL **HIGH** (griefing) | PartyService.luau:585-587 | `kind == "Kick"` calls `unqueuePlayer(arg)` for any number BEFORE checking `arg` is in the caller's party (the real kick at 666 does check). Any player: Create (leader of a one-person party), then Kick(victimUserId) repeatedly. The victim is dropped from the hunt queue every time. | Move the unqueue into the validated branch (`table.find(party.Members, arg)`). |
| PartyAction Accept / Leave / forged id | PASS | PartyService.luau:579-584 (only a real invite can pull a queued group out), 640-664 | none | - |
| PartyAction Invite spam | POLISH | PartyService.luau:630-639 | 10 s cooldown is per (from,to) pair only; many leaders can toast one victim. | Cap invites received per minute per target. |
| ShopAction: types, rate, prices | PASS | EconomyService.luau:258-262, 273/292/303/321/376 (id must be a string key of a Config table), 48-55 (price from Config, spend then grant in one synchronous block, cash cannot go negative), 241-256 (level buys need the shown next level and 1 s gap), 562-583 (6 per second, released profile refused) | no negative-coin or "coins taken then buy fails" path found | - |
| ShopAction hopper sell via prompt | NEEDS STUDIO TEST | EconomyService.luau:604-609 vs 263-270 and 209-234 | The HUD button path measures 12 studs on the server. The prompt path trusts `PromptTriggered` as proof of range (comment at 603). Roblox may not distance-check a Triggered event from an exploit client. Same trust at BadgeService.luau:117-121 (secret egg) and GalleryService.luau:358-364. Impact is low. | Re-check player to prompt distance on the server in each PromptTriggered handler. POLISH |
| CollectionAction (Favorite / Display / DisplayAt / Sell / Equip / Unequip / EquipBest) | PASS | EconomyService.luau:399-516 (ids strings, slot finite 1..64 and <= slots, Sell list bounded by inventory, de-duplicated, expected total must equal server total, no favourites or displayed pets); PetService.luau:173-238 (0.3 s, refused during a hunt, ids must be owned) | Sell id strings have no length cap (470-478). | Reject ids longer than 64 chars. POLISH |
| CollectionAction RenamePet: filter | PASS | PetService.luau:119-171; PetRules.luau:26-54 | Shape check (type, <= 84 bytes, valid UTF-8, `[%w -_.!?']` only, <= 20 chars); FilterStringAsync + GetNonChatStringForBroadcastAsync inside pcall (141); pcall failure refuses with a toast (143-146); result must equal the asked text and have no '#' (147); profile, player and pet re-checked after the yield (154-164); 5 s cooldown and one in flight (124-130). Name stored only after the filter. | - |
| RenamePet toast spam | POLISH | PetService.luau:128-131, 175-177 | RenamePet skips the 0.3 s `lastAction` gap, so "Wait a moment" toasts fire as fast as the client sends. | Put the lastAction gap before the RenamePet branch. |
| SettingsAction | PASS | EconomyService.luau:518-539; WhatsNew.luau:24-29 | table type checked, numbers NaN-checked and clamped 0..1, booleans typed, news version must equal current | - |
| ClientReady | PASS | Main.server.luau:101-112 (5 s per player) | none | - |
| TutorialAction (Skip / Goal) | PASS | EconomyService.luau:586-602; PetService.luau:73-78 | idempotent (TutorialStep only 0 to 1, starter pet once via StarterPet flag) | - |
| LaunchAction | PASS (dormant) | LobbyLaunch.luau:421-504, 566; MatchPlace.luau:372-404, 492-499 (0.4 s); Config.luau:428 (Mode "SinglePlace"); PlaceRole.luau:11-13 | In SinglePlace neither `start()` runs, so the remote has no listener. In Teleport mode inputs are string compares and state-gated. | - |
| StoreAction (Buy / Equip / Unequip) | PASS | StoreService.luau:80-140 | catalogue id validated, visible (ProductId > 0) required, 0.4 s gap, server opens the prompt, prompt grants nothing | - |
| RobuxAction (Buy) | PASS (shape) | RobuxService.luau:381-392, 219-268 | id string, count must be in EggCounts, 0.4 s gap, ids > 0, eggs need policy allowance and Pet Book room | - |
| TowerAction (Open / SetTeam / EquipBest / Start / Special / Next / Revive / BuyRevive / Leave) | PASS (types, rate, state) / POLISH | TowerService.luau:475-555 | msg must be a table with string Op (476), 0.15 s gap (480), SetTeam refused during a run and bounded (489), ids must be owned strings (497), Start refuses when in a hunt (373), Special needs a full meter (TowerRules.luau:378-382), Next only after Cleared (532), Revive only when Lost (Revive.Free = 0, TowerConfig.luau:229). BuyRevive can re-open the Roblox prompt every 0.15 s (544-551). | Add a 3 s gap for BuyRevive. POLISH |
| TowerEvent payload leak | PASS | TowerService.luau:128-145, 187-205 | only the player's own pets and server-spawned mobs | - |

## 2. Pet-egg leak hunt (server to client and shared data)

| Feature | Verdict | File + line | Problem | Fix |
|---|---|---|---|---|
| Target id absent from every hunt payload before the crack | PASS | TargetId is read only in RoundRocks.luau:206, 434-437 and EggEvents.luau:70, 86, 120-124. Init (MatchService.luau:242-264), Rocks flush (RockService.luau:349-357), stationViews (RoundRocks.luau:722-744), removedIds (747) carry ids and states only. No FireClient / SetAttribute / Name / Color / Size in RockService, MatchService, StationModels, WorldBuilder, MachineModels, Pile, RacerCollision touches the target. Eggs are client-drawn from Stacks. | none | - |
| All eggs identical: HP, cadence, storage, material | PASS | RoundRocks.luau:144 (same Hp), 402-421 (storage reserved for every egg, a full bag cannot single out the target), 449-451 (material from server-only MatSalt, told only in Done), 436-444 (geode emits Found only at the crack) | none | - |
| Public Seed vs target | PASS (POLISH) | MatchService.luau:302-307 | Seed and TargetRng are sibling outputs of one `serverRng`. Not derivable in practice. | Seed TargetRng from fresh `Random.new()`. POLISH |
| Overtime glow only after 3 min | PASS (timing) / FAIL **POLISH** (can be skipped) | EggConfig.luau:37-41 (180 s); EggEvents.luau:68-77 | Gate is server-side `t - Start >= 180`, never in the tutorial, id only sent while the egg is InPile. But if the egg is carried, queued or on a plate at that instant, `st.Overtime = true` is set without sending anything (74-75) and wobbles stop forever (78). If that player then dies or leaves and the egg returns to the pile (RoundRocks.luau:627-638) the glow never fires and the round can run unbounded. Late joiners and Sync never get the glow (event only). | Set the flag only after sending; re-test every step; resend on Init/Sync. POLISH |
| Wobble patch never identifies one egg | FAIL **HIGH** | EggEvents.luau:78-103; EggHints.luau:28-49, 67-75, 81-101; EggConfig.luau:7-32 | (1) PatchJitterMax 3 < PatchRadius 3.5, so the anchor (the pet egg when the pick is the pet) is ALWAYS inside its own patch (EggConfig.luau:23-26). The "anchor may fall outside" comment is false except when the PatchMax 8 cap trims it. (2) Meadow is pet-only (EggConfig.luau:17, EggHints.luau:68-72): every wobble patch contains the pet egg. Intersecting two or three patches (ids are in the payload, positions are public from Stacks) or simply watching "which egg wobbles every time" names it, within about 30-40 s, in the first zone every new player plays. (3) Forest and later: the pet egg is picked 25% of the time versus about 0.5/N for a decoy (EggHints.luau:35); counting appearances over 10 wobbles singles it out. (4) In Meadow, wobbles stop entirely once the egg is picked up (EggHints.luau:68-73), telling everyone it left the pile. | Owner decision. Either accept it as a solvable hint (and move overtime earlier) or make it non-intersecting: jitter must exceed the radius, exclude the anchor from the patch a fixed share of the time, keep wobbling decoys in Meadow and after the target is carried, randomise patch size. |
| Chirp never identifies one egg | FAIL **HIGH** | EggEvents.luau:110-146; EggHints.luau:106-113; EggConfig.luau:43-58 | A Chirp reaches only a player within 8 studs of the pet egg (the event itself says "pet egg within 8 studs of you") at a point 2-4 studs from it in a random direction. Two chirps give two annuli whose overlap is a few studs; the mean of N chirps converges on the egg. It also stops when the egg leaves the pile. | Add decoy chirps from non-pet eggs, widen jitter above Radius/2, cap chirps per player per minute. |
| Boots roll independent of egg identity | PASS | EggEvents.luau:172-204; RockService.luau:213 (ordinary Cracked only) | none | - |
| Client event handling for Wobble / Overtime / Chirp / Boots | PASS | EggFx.luau:221-267 | typed and Round-checked before use | - |
| RareHatch / HatchShow / Toast payloads | PASS | RareHatch.luau:41-93; RobuxService.luau:100-116 | display name, species name, rarity only; no user id, round or egg id; incoming MessagingService data re-validated (78) and rate limited (89) | - |
| PetsShown / MatchKey attributes | PASS | PetService.luau:41-53 | followers hidden during a hunt; MatchKey is a random GUID | - |

## 3. Services and other checks

| Feature | Verdict | File + line | Problem | Fix |
|---|---|---|---|---|
| RoundRocks: one owner per egg, atomic transitions | PASS | RoundRocks.luau:22-28, 327-349, 387-392, 412-420, 445-451 | Pickup / Deposit / Crush are the only mutators | - |
| Pile | PASS | Pile.luau:183-230; RoundRocks.luau:632-637 | exposure and reach consistent; a returned egg is indistinguishable from an untouched one | - |
| HuntLedger | PASS | HuntLedger.luau:1-11, 41-46, 49-77 | read-only counters, NaN and negatives clamped, Closed flag | - |
| EggEvents speed boots | PASS | EggEvents.luau:157-204 | server sets WalkSpeed, token stops a stale restore | - |
| MatchService: one finish per round, award key | PASS | MatchService.luau:389-398; RockService.luau:220 | double guard (FinishedRound, FoundRound), key = MatchKey:Round | - |
| MatchService.finishRound has no error guard | FAIL **POLISH** | MatchService.luau:410-507 | an error inside the task (roll, ledger, reveal) leaves the phase at RewardPending and a Profiles.hold (408, 444) that expires only after 15 s (Config.luau:411). Players can still press Return. | Wrap in pcall; always unhold and advance phase. |
| Double prize: same round twice | PASS | MatchService.luau:391; Profiles.luau:713-720; AwardLedger.luau:49-57 | canonical ledger entry, RecentAwardIds, specimen id check | - |
| Double prize: award + leave + rejoin | PASS (POLISH edge) | MatchService.luau:407-445; AwardLedger.luau:90-121, 141-187; Profiles.luau:886-905 | Offline winner gets a pending key applied once on next load (applied entries skipped, 162-163). Edge: RecentAwardIds keeps 50 (Config.luau:456). If markApplied (74-88) failed and 50+ newer awards followed, a sold prize could be granted again. | Keep applied keys in pending until the ledger confirms. POLISH |
| Double prize: party leaves mid-round | PASS | MatchService.luau:572-596; RockService.luau:368-374; RoundRocks.luau:643-703 | leaver forfeits; held, queued and plate eggs (even the pet egg) go back to the pile at full HP; leaving during RewardPending does not cancel the award (hold + ensurePending) | - |
| Bonus (helper) pet | PASS | MatchService.luau:358-387 | own award key per uid, idempotent grant, book room checked | - |
| Pet Book full when prize arrives | PASS | Profiles.luau:708-763 (no capacity refusal); PartyService.luau:71, 301; MatchService.luau:797 | prize never silently dropped (book may pass the cap); start and rematch blocked when full | - |
| Free starter pet once | PASS | PetService.luau:73-78 | none | - |
| QuestService claims | PASS | QuestService.luau:142-172; Quests.luau:165-182, 195-206 | claim index must be a finite integer; claimed flag set in the same block as payout; gift once per UTC day | - |
| PartyService roster | PASS | PartyService.luau:179-205, 640-664 | locked parties cannot be joined; leader reassignment; invites expire | - |
| StoreService ProcessReceipt | PASS (code) / NEEDS STUDIO TEST | StoreService.luau:40-78, 141-148 | PurchaseGranted only after `Profiles.saveNow` is true (71-73); PurchaseId recorded in the same mutation (64-69); missing or released profile and any error give NotProcessedYet. Never run with a real product (ids 0, Config.luau:468-483). | Test with a dev product (rejoin mid-purchase, forced save failure). |
| RobuxService ProcessReceipt (eggs, potion) | PASS (code) / NEEDS STUDIO TEST | RobuxService.luau:122-183; RobuxConfig.luau:170-186 | grant and receipt id in one mutation (156), saveNow before PurchaseGranted (160), idempotent per PurchaseId (300 kept), egg awards keyed `robux:<purchase>:<i>`. The product ids are public (shared module), so an exploit client can call MarketplaceService:PromptProductPurchase directly and skip the Pet Book room and policy checks at prompt time. | Re-check policy in processReceipt (still grant, but log). Test live. |
| Paid random items: PolicyService (eggs) | PASS | RobuxService.luau:55-68, 227-230; RobuxShopPanel.luau:109, 437 | `ArePaidRandomItemsRestricted` read in pcall, default is blocked on error or unknown, server refuses at 227, client hides until the attribute is false | - |
| Paid random items: Luck Potion | FAIL **HIGH** (compliance) | RobuxService.luau:241-254; LuckEvents.luau:46-54; GeodeGen.luau:70-76 | The potion is sold to everyone with no policy check, but it raises rarity odds of the random pet reward (Rare and better x(1+luck), up to MaxLuck 4). It is a paid random-outcome modifier. | Gate with `Robux.eggsAllowed(player)` or get explicit policy sign-off; print the resulting odds on the card. |
| Odds shown for Robux eggs | NEEDS STUDIO TEST | RobuxShopPanel.luau:194-224; RobuxConfig.luau:23-40 | The card prints odds from LuckEvents.eggOdds; not proven equal to what GeodeGen.roll does (RobuxService.luau:147). Rare Egg Legendary 0.5% (RobuxConfig.luau:28) with one chase pet per zone is about 1 in 200 for that chase pet, against the stated 1/1000. | Add a sampling test; confirm intended. |
| Game passes | PASS | RobuxService.luau:187-215, 393-400 | granted only from the server event, re-checked on join with retries | - |
| Tower revive receipt | PASS (code) / NEEDS STUDIO TEST | TowerService.luau:586-609; Tower.server.luau:8-13 | one credit per PurchaseId (last 50 kept), saved before PurchaseGranted, used only on a Lost floor, MaxPaid 3 per climb (569); product 3717828140 live (TowerConfig.luau:229) | - |
| TowerService economy | PASS | TowerService.luau:299-325, 258-297 | coins, xp, best from server rules; drops respect Pet Book room; pets sold mid-run earn nothing (118) | TowerXP rows for sold pets are never pruned. POLISH |
| Tower vs hunt state | PASS | TowerService.luau:373, 663-667; PartyService.luau:224-232 | hunt start pulls a climber out; InTower counts as busy | - |
| RacerCollision (no bumping or stealing) | PASS | RacerCollision.luau:43-58; RoundRocks.luau:369, 485 | collision group only; theft is impossible because baskets are server state and deposit/crush use the caller's own station | - |
| Per-player tables cleaned on leave | PASS | MatchService.luau:882-887; EconomyService.luau:558-566; PartyService.luau:724-740; PetService.luau:256-260; StoreService.luau:130-132; RobuxService.luau:364-367; TowerService.luau:684-690 | none | - |
| Code-injection patterns in src/ | PASS | grep over `src/**/*.luau` | no loadstring, getfenv, setfenv, require(<number>); InsertService only in MeshService.luau:54 (owner mesh ids) | Check ids are owned (Section 4). |

## Section 3B/3C: Code checks, saves, awards, leaks, strict mode

Read-only. All paths under `repo/src/`. Nothing run in Studio. PASS = proven from code. Teleport mode is OFF (`Config.Places.Mode = "SinglePlace"`, shared/Config.luau:428) so LobbyLaunch, MatchPlace and Tickets never run today.

## 1. DataStore safety
| Feature | Result | File + line | Problem | Fix |
|---|---|---|---|---|
| pcall around every DataStore call | PASS | server/Profiles.luau:30,308,366,533; AwardLedger.luau:23,28-38 (retry wrapper); LeaderboardService.luau:57,106,251 | All UpdateAsync/GetAsync/GetSortedAsync are inside pcall. | - |
| Profile load can throw outside pcall (silent no-profile) | FAIL HIGH | server/Profiles.luau:325 (`reconcile` runs outside the pcall); onJoin 842-876 has no pcall | If `reconcile` errors on an odd save, the onJoin thread dies: `loading[player]` stays true, the player stays in game with no profile and no kick, and the session lock written at 309-320 stays held up to 300 s. | Wrap `reconcile` (and the onJoin body) in pcall; on error release the lock and kick with a message. |
| Retries + backoff | PASS | Profiles.luau:303-345 (7 tries, 2^n capped 12 s), 358-405 (4 tries, 2^n), AwardLedger.luau:28-38 (4 tries, 1/2/4/8 s) | - | - |
| Request budget respected | PASS (POLISH gap) | Profiles.luau:285-290 (waits max 10 s then proceeds); LeaderboardService.luau:142,247 (MinBudget) | Ledger/Pending calls (AwardLedger.luau:49,80,96,148,157,175) never check budget. Fine at 12 players, but retries blind in an outage. | Add budgetWait to Ledger.retry. POLISH |
| UpdateAsync, not SetAsync | PASS | Only SetAsync in repo is MemoryStore Tickets.luau:32 (teleport only). All DataStore writes use UpdateAsync; leaderboards keep the max (LeaderboardService.luau:107-112). | - | - |
| Session lock (LockSeconds 300) | PASS | Profiles.luau:278-283,311-314,374-378; Config.luau:453 | Lock per session GUID; autosave refreshes Lock.Time every 90 s (Profiles.luau:918) so it never looks abandoned. | - |
| Rejoin after a server crash | FAIL POLISH | Profiles.luau:303-346 | Load retries total about 50 s but a crashed server's lock lives 300 s, so the player is kicked (866) for up to 5 min. Safe but annoying. | Clearer kick text, or LockSeconds 120 with 60 s autosave. |
| Release save can overwrite newer data from another server | FAIL HIGH (rare: needs >300 s save outage) | Profiles.luau:374-378 | On release the check only rejects if `old.Lock` is a table that is not ours. If another server took the abandoned lock, saved and released it (Lock = nil), our stale release passes and overwrites their newer Data. No Rev compare. | In the release branch also require `(old.Rev or 0) == (rec.Rev or 0)`; otherwise set LockLost and do not write. |
| Lock lost mid-session is silent | FAIL POLISH | Profiles.luau:393-397 | After `LockLost` all later progress is discarded; only a `warn` is printed, the player is never told or kicked. | Kick or toast "saves paused, rejoin" when `rec.LockLost`. |
| Autosave | PASS | Profiles.luau:913-924 (every 90 s, clean profiles too) | - | - |
| BindToClose waits for saves | PASS (POLISH) | Profiles.luau:925-939 (waits up to 25 s until `loaded` is empty) | Release save uses 4 attempts with waits 2/4/8/16 s (404), so in an outage a player may not finish inside Roblox's 30 s cap. Leaderboard final writes (LeaderboardService.luau:296-299) and `Ledger.markApplied` (AwardLedger.luau:79) are not awaited. | Fewer attempts at shutdown; add a BindToClose flush to Leaderboards. POLISH |
| No wipe / overwrite path | PASS | Profiles.luau:315-318 (unreadable Data returns nil, never overwritten), 292-299 (never returns defaults on read failure in production), defaults only when key is absent (319); Studio offline profile never written (354) | - | - |
| Schema migration | PASS (POLISH) | Profiles.luau:105-269, 258 | `reconcile` only fills missing fields, repairs types, migrates old mineral ids, never deletes. `Schema` is overwritten with 1; no versioned steps exist. | Add `if data.Schema < 2` block before the next breaking change. POLISH |
| Studio uses `_Studio` stores | PASS | Profiles.luau:26,31; AwardLedger.luau:20; LeaderboardService.luau:31,58 | MemoryStore `CTR_Tickets_v1` (Tickets.luau:16) has no suffix but is Teleport-only. | Add suffix if Teleport mode is enabled. POLISH |
| Dead field | POLISH | Profiles.luau:77 `PendingAwards` | Default exists, never used. | Remove. |

## 2. Awards, ledger, replay
| Feature | Result | File + line | Problem | Fix |
|---|---|---|---|---|
| Round pet awarded exactly once (award + leave + rejoin) | PASS | MatchService.luau:405-445; AwardLedger.luau:41-72,126-138,141-187; Profiles.luau:708-718 | Decision written to ledger first (UpdateAsync keeps the first entry); grant keyed by awardKey in `RecentAwardIds` and by specimen Id; winner profile held open (`hold` MatchService.luau:408, wait up to 15 s Profiles.luau:894); absent winner gets a pending key replayed on next load; `applied` entries never re-granted (AwardLedger.luau:162-163). | - |
| Ledger / pending replay double award | PASS | AwardLedger.luau:162-170; Profiles.luau:713-720 | Idempotent twice over (ledger State + RecentAwardIds/Id). RecentAwardIds trims at 50 (731) but State still blocks a stale key. | - |
| Pending key without a ledger entry never resolves | FAIL POLISH | AwardLedger.luau:108-121,156-158; MatchService.luau:405-441 | If the ledger write fails for the full 10 min retry (AwardLedger.luau:61-69) but the pending write lands, `reconcile` finds entry nil, never grants and never clears the key. Tutorial rounds also call `Ledger.apply` (MatchService.luau:432), so a failed tutorial save leaves a pending key with no ledger entry ever. | Drop keys with nil entry after N days; skip `ensurePending` when `m.Tutorial`. POLISH |
| Error inside award task leaks the hold | FAIL POLISH | MatchService.luau:408-444 | No pcall; if anything throws before line 444 `Profiles.unhold` never runs, so every later leave waits the full 15 s (Profiles.luau:894). | pcall the body, always unhold. |
| Storage full when finding the round pet: never lost | PASS | Profiles.luau:708-763 (no capacity check, appends past cap); queue blockers PartyService.luau:71,301; rematch MatchService.luau:797; bonus pet gated MatchService.luau:368 | Round pet always saved even into a full book (book may exceed 100). Players with a full book cannot queue (PartyService.luau:301) until they sell (EconomyService.luau:468), not a soft-lock. | NEEDS STUDIO TEST: confirm the blocker message points to SELL. |
| Starter pet skipped silently if book full | FAIL POLISH | PetService.luau:78-82 | Sets `StarterPet = true` then returns with no pet if full (not reachable on fresh saves). | Set the flag only after inserting. |
| Starter pet is no find/win | PASS | PetService.luau:72-109 | No Stats, no ledger. It does set `DiscoveryIndex[species]` (101-104): starter species counts for Pet Master/AllHuntPets and its later real first find pays no +50 (Profiles.luau:736). | Owner decision. |
| First-find coins once per species | PASS | Profiles.luau:736-740,757-761; shared/PetFlair.luau:66-75 | Index read before increment, same write; second call returns 0. Also paid on Bonus/Bought/Tower kinds. | - |
| Bought pets are not finds | PASS | Profiles.luau:747-753 | - | - |
| Tutorial pet counts as a Solo Find | NOTE | Profiles.luau:749-750 (kind "Tutorial" falls into SoloFinds++) | Practice find counts toward Forest unlock (5 finds), FirstHatch badge and Hatch quest. Comment at 744 says intended. | Owner decision. |
| Receipts only after save | PASS | RobuxService.luau:120-175 (`remember` in same mutation, `saveNow` before PurchaseGranted) | Detail covered by other auditor. | - |
| Tower drops and TowerBest persisted | PASS | TowerService.luau:306-323 (`Profiles.changed`), key `tower:<id>` at 293 | Saved by autosave only (up to 90 s loss on crash). | - |

## 3. Badges, quests, daily gift
| Feature | Result | File + line | Problem | Fix |
|---|---|---|---|---|
| Badges awarded once | PASS | BadgeService.luau:39-70 (busy guard; `Badges[key]` set only after Roblox confirms; AwardBadge false falls back to UserHasBadgeAsync); 73-82 skips remembered | - | - |
| Never for starter | PASS | shared/ProgressConfig.luau:118,156 (FirstHatch = SoloFinds + MultiplayerWins >= 1) | FirstRare (120-135) also fires from a Rare bought with a Robux egg or a tower drop (not a find). | Owner decision. POLISH |
| Still fire after id set later | PASS | BadgeService.luau:73-82 requires id > 0; id 0 is never remembered; check runs on load (116-124) and every profile change | A failed award is retried only on the next `Profiles.changed`, not on a timer, so the header "retried at most once a minute" is not real. | Add a 60 s retry loop. POLISH |
| Pet Master / found count wrong | FAIL HIGH | shared/PetFlair.luau:40-52 (`foundCount` loops ALL `Config.Minerals`, incl. TowerOnly and unreleased weekly) vs `species()` 28-37 (excludes them); ProgressConfig.luau:103-111 | `allFound` = foundCount >= #species(). Tower-only pets enter DiscoveryIndex through grantSpecimen (Profiles.luau:740), so a player can get the Pet Master title (and toast "36/35", PetIndex.luau:47) with hunt pets still missing. | Count only ids in `PetFlair.species()`; add a test in tests/test_pet_flair.luau. |
| AllHuntPets uses current released pool | PASS | ProgressConfig.luau:103-111,136-152 (`SpeciesPool.list(..., os.time())`, weekly counted once out) | Badge is remembered (BadgeService.luau:67) so a later weekly pet never takes it away. Pet Master title is derived live (PetFlair.luau:60-62): it disappears when a weekly pet is released until that pet is found. Selling a pet does not lower DiscoveryIndex. | Owner decision (store title as a saved flag). |
| SecretEgg badge | PASS (code) | BadgeService.luau:102-114,117-118 | Once per profile. | NEEDS STUDIO TEST that the park builds the part with the attribute. |
| Daily gift once per UTC day + streak reset | PASS | shared/Quests.luau:24-26,195-205; QuestService.luau:142-172 | Streak +1 only if GiftDay == yesterday else 1; future-dated save is refused ("Clock", no toast). Claim is not blocked when profile is `Released` (QuestService.luau:146). | Add isReleased guard + toast. POLISH |
| Daily quests roll at UTC midnight | PASS | QuestService.luau:49-59,104-133,186-201 | - | - |

## 4. Profile fields saved + restored on rejoin
All fields live in one `rec.Data` table written whole by UpdateAsync (Profiles.luau:382-386) and passed through `reconcile` on load (105-269). Every `data.<Field>` used in server code is in `Profiles.defaults()` (grep-checked). Actual rejoin needs a Studio test.
| Feature | Result | File + line | Problem | Fix |
|---|---|---|---|---|
| Coins | PASS (code) | Profiles.luau:51,123-126 | NEEDS STUDIO TEST rejoin | - |
| Pets + nicknames | PASS (code) | InventoryGeodes :58; Nickname repaired :149-151; saved at PetService.luau:165 | - | - |
| Equipped pets | PASS | :80, filtered to owned :235-243, PetService.refresh | - | - |
| Upgrades (basket, nest, tools, capacity) | PASS | :92-93,53-54,56; levels clamped :247-250 | - | - |
| Zones | PASS | UnlockedTiers :57, Gravel forced :264 | - | - |
| Badges | PASS | :97, sanitized :252-256 | - | - |
| Tower best, XP, revive credits | PASS | :82-85 | TowerXP/TowerReceipts only checked "is table" in reconcile. | POLISH |
| Quests, gift, tower floors today | PASS | Daily :94 (Quests.sanitize :251), TowerFloorsToday :96 | - | - |
| Potion time + passes | PASS | Robux :100, `RobuxConfig.sanitize` :257 | - | - |
| Display plots | PASS (data) / NEEDS STUDIO TEST (render) | Profiles.luau:59-60,154-158; GalleryService.luau:369-371 | Only 12 plots (`assign` GalleryService.luau:288-303): a 13th player would get no plot and `render` returns silently. | Confirm max players = 12. |
| XP, settings, onboarding, news | PASS | :83,74,73,89 | - | - |
| Leaderboard writes | PASS | LeaderboardService.luau:81-121,124-161 (max-only, throttled, budget-gated); per-player tables cleared after leave :300-306 | Final write on leave not awaited at shutdown. | See BindToClose row |
| RareHatch / MessagingService | PASS | RareHatch.luau:23-29,63-70,104-111 (all pcall, no user id in payload) | - | - |
| FriendBonus | PASS | FriendBonus.luau:30-37 (pcall + cache), 90-100 clears pairs on leave | Tiny race: in-flight `ask` can re-add a pair for a player who just left. | POLISH |

## 5. Memory leaks / cleanup
| Feature | Result | File + line | Problem | Fix |
|---|---|---|---|---|
| Per-player server tables cleared on PlayerRemoving | PASS | Profiles.luau:900-904; BadgeService.luau:128-131; QuestService.luau:182-184; PetService.luau:256-260; GalleryService.luau:365-367; Main.server.luau:98-100; EconomyService.luau:558-566; EggEvents.luau:207-209; PartyService.luau:526-541,724+; MatchService.luau:882-887; RockService.luau:412-415; TowerService.luau:684-689; RobuxService.luau:364-367; StoreService.luau:130-132 | Every `{ [Player]/[number] ... }` module table found by grep has a cleanup. | - |
| Gallery likes never pruned | FAIL POLISH | GalleryService.luau:43 | `likes` grows per distinct user for the server's life (small). | Clear when server empties. |
| LobbyLaunch entries when members leave in Failed phase | FAIL POLISH (teleport OFF) | LobbyLaunch.luau:520-540,570-579 | Leavers in Failed phase keep `launchOf[uid]`; launch lives forever if everyone leaves (the timer only frees Away launches). | Dissolve when no member remains. |
| Gallery display instances | PASS | GalleryService.luau:47-53,142 (Display folder destroyed on each render and release) | - | - |
| Tower arenas / mobs | PASS (server) | TowerService.luau:229-249 `closeRun` -> TowerBuilder.free (TowerBuilder.luau:151 Destroy); mobs are rule data only server-side | Client models destroyed TowerView.luau:177,226,242. | NEEDS STUDIO TEST leaving mid-floor. |
| Client followers, eggs, stations, wobble, sparkles | PASS (code) | PetFollow.luau:67,177-195,313-314; EggFx.luau:36-100,195-215; StationView.luau:715-727,830-860; PileView.luau:123,211-214,901,978-994 | Only module-level single connections remain (PileView.luau:1028-1105, CarryView.luau:261). | NEEDS STUDIO TEST: 10-round soak watching instance count. |
| Single prompt/event connections | PASS | GalleryService.luau:358-364; BadgeService.luau:117-121 | - | - |

## 6. StreamingEnabled
| Feature | Result | File + line | Problem | Fix |
|---|---|---|---|---|
| Real setting | NEEDS STUDIO TEST | default.project.json and match.project.json: Workspace `$properties` has only `Gravity`. No code or doc sets it (docs/PERF.md:69 says "not measured"). | Rojo leaves the property alone, so the value comes from the published place file; new Roblox places often default ON. Unknown here. | Read Workspace.StreamingEnabled in Studio. If ON, set `"StreamingEnabled": false` in both project files or fix items below. |
| Client lookups of far parts | FAIL HIGH only if ON | client/StationView.luau:104-117,145; client/MachineView.luau:186-190; client/Main.client.luau:266-267; client/UpgradePreview.luau:201-217; client/LobbyAmbience.luau:405-420; client/CameraGuard.luau:96,168 | Arenas are far from the lobby. `findTable` / machines scan `Workspace:GetChildren()` for `CT_Rocks_Arena_*` stations once and return nil if not streamed (no retry per frame). Plot marker and lobby lookups fail soft or give up after a poll. Eggs/pets are built client-side (safe). | Persistent model streaming mode on arenas/lobby, or streaming off. NEEDS STUDIO TEST. |

## 7. Files without `--!strict` (60 of 138 under src/; tests/ 0 of 32; tools/ 1 of 56)
Money/save code is among them: server/Profiles, AwardLedger, QuestService, BadgeService, LeaderboardService, GalleryService, LobbyLaunch, MatchPlace, Tickets, Main.server, MatchService, EconomyService, RobuxService, StoreService, RockService. Strict ones: PetService, RareHatch, FriendBonus, PetIndex, shared/*. Severity POLISH.
Full list (no `--!strict`):
- client: Anim, CameraGuard, CameraMode, CarryGlimpse, CarryView, GuideArrow, HatchStandView, MachineView, Main.client, PileView, PromptArbiter, Reticle, State, StationView, Tower.client
- client/ui: CollectionPanel, GeodeView, Hud, InspectPanel, ItemView, LaunchPanel, ModelThumb, NewsPopup, PartyPanel, PlayButton, QuestPanel, ResultsPanel, RobuxShopPanel, SettingsPanel, ShopPanel, UI
- first: Boot.client
- server: ArenaBuilder, ArenaKit, AwardLedger, BadgeService, EconomyService, GalleryService, KitParts, LeaderboardService, LobbyBoards, LobbyBuilder, LobbyLaunch, LodgeBuilder, MachineModels, Main.server, MapHooks, MatchPlace, MatchService, ParkBuilder, PartyService, Profiles, QuestService, RobuxService, RockService, StationModels, StoreService, Tickets, Tower.server, WorldBuilder

Fix: add `--!strict` one file at a time, starting with Profiles, AwardLedger, QuestService, BadgeService, then run tools/check.sh.

## Section 4: Animation, FX, audio, place files


Repo: `scratchpad/repo` (HEAD b8cd9fb). Nothing was edited. Owner status below is only what code or docs state; owners cannot be looked up from here, so "owner unknown - NEEDS STUDIO TEST" means: open the asset in Studio / Creator Hub (or play-test and watch the Output for 403 / "failed to load") and confirm it is owned by kcdrewcarter (20194281) or a group the place belongs to.

Place-file tooling note: `FindThePet_WITH_LOBBY.rbxl` is Zstd-compressed and uses the newer `Tags` property type, so `@lune/roblox` 0.10.4 `deserializePlace` throws ("AssetService.Tags should be SharedString"). To read it anyway: `unzstd_rbxl.ps1` (uses the libzstd.dll that ships with Git for Windows, P/Invoke, nothing installed) wrote an uncompressed COPY of the chunk stream into this findings folder (`lobby_plain.bin`); `rbxl_binary_dump.luau` is a small own parser run with Lune on that copy. Output: `dump_lobby.txt`. The XML place was read with `place_dump.luau` (@lune/roblox) -> `dump_xml.txt`. Nothing was written next to the place files.

## 1. Feature checks (Section 4)

| Feature | Result | File + line | Problem | Fix |
|---|---|---|---|---|
| AnimationIds in repo | PASS (none) | whole `src/`, `tools/owner`, `assets/PetModels.rbxmx` (grep AnimationId, LoadAnimation, `Instance.new("Animation")`, AnimationTrack: 0 hits outside offline-preview mocks) | No Animation instance and no AnimationId anywhere, so no ownership risk. Both place files also contain 0 `Animation` instances. | none |
| Animator vs Humanoid:LoadAnimation | PASS (not used) | `src/client/ToolAnim.luau:4-11` | Nothing loads tracks, so no track leak or stacking. Strokes are written onto shoulder `Motor6D.Transform` from `RunService.Stepped` (lines 401, 449, 492). | none |
| ToolAnim layering over the default Animate script ("after the Animator") | NEEDS STUDIO TEST | `src/client/ToolAnim.luau:401-416, 449-478, 492-509` | The comment says the layer is applied after the Animator, but it runs on `Stepped` (before physics). Whether the default Animate script has already written Transform for that frame on a real R15 avatar is unproven; if not, the stroke/carry pose can be overwritten or flicker. State tables (`swings`, `jacks`, `carrying`, `scoops`) drop a character when `character.Parent == nil`, so respawn does not stack; `layers`/`restGrip` are strong `Motor6D` maps cleaned via `unlayer` / `Destroying` (line 120). | Playtest R15 + R6: swing, carry, jackhammer, respawn mid-stroke. If arms snap back, move the layering to `RunService.PreSimulation`/`RenderStepped` with a `BindToRenderStep` priority after `Enum.RenderPriority.Character`. |
| PetMotion runs per client | PASS | `tools/owner/PetMotion.luau:111-141, 166`; mapped by `default.project.json:13-15` as `ReplicatedStorage.PetMotion` | Client-only module (comment line 2); each client runs its own Heartbeat loop; Bone.Transform does not replicate so server never animates. | none |
| PetMotion stops when pet removed | FAIL (partial) | `tools/owner/PetMotion.luau:140` | Cleanup relies only on `model.Destroying:Once(...)`. A model that is merely un-parented (PetFollow sets `p.Model.Parent = nil` in `CharacterRemoving` and in `step` when no character, `PetFollow.luau:183, 248`) stays in `active` and is `PivotTo`'d every frame until it is finally destroyed. Server-built `PetDisplay` pets removed by the server may not fire `Destroying` on the client copy. `active` is a strong table, so a missed removal is a permanent per-pet leak. | In the Heartbeat loop: `if not model:IsDescendantOf(game) then active[model] = nil; continue end`. Make `active` and `restRot` weak-keyed (`setmetatable({}, {__mode="k"})`). |
| PetMotion per-pet leak | FAIL (small) | `tools/owner/PetMotion.luau:118, 127` | `restRot[bone]` is written for every Bone of every started pet and never cleared. Each equip change in PetFollow (`rebuild` -> destroy + build) adds ~8 bones per follower per player; Destroyed Bones stay referenced forever. | Clear `restRot[d]` for the model's bones in the `Destroying`/removal path, or weak-key the table. |
| PetMotion cost with many display pets | NEEDS STUDIO TEST | `PetMotion.luau:166-224`, `src/client/PetDisplay.luau:90-104` | Every tagged `PetDisplay` pet (plots, domes, hatch stands, gallery: up to 12 plots x 20 slots) plus up to 36 followers animate every frame with no distance or visibility culling. | Profile the full 12-player lobby with MicroProfiler. If heavy: skip models farther than ~80 studs from the camera (track `CurrentCamera.CFrame.Position`) and only update bones for those inside. |
| Clean fallback when PetModels missing | PASS | `src/shared/PetModel.luau:75-84, 171-174`; `src/client/PetMotionBridge.luau:37-47` | `template()` returns nil -> procedural pet is built, never gets attribute `Mesh`, so `Bridge.start/hatch` return false without touching PetMotion. | none |
| Clean fallback when PetMotion missing / errors | PASS | `src/client/PetMotionBridge.luau:14-29, 37-60`; `src/client/PetFollow.luau:27-38, 92-94, 287-296` | Every call is `pcall`-wrapped and returns false; PetFollow falls back to its own hop (`PivotTo`). | none |
| PetMotion module cached as "missing" forever | NEEDS STUDIO TEST (low) | `PetMotionBridge.luau:14-19` (`tried = true` after first `FindFirstChild`), `PetFollow.luau:31` (one-shot `FindFirstChild` at require time) | If `ReplicatedStorage.PetMotion` has not replicated when the client first calls it, mesh pets stay still for the whole session (no retry). LoadingScreen waits for `game:IsLoaded()` (`src/first/LoadingScreen.luau:246`) so this is probably fine, but it is not proven. | `ReplicatedStorage:WaitForChild("PetMotion", 5)` in both places, and only set `tried` after the wait. |
| PetMotion vs RevealView / StationView both moving the same model | NEEDS STUDIO TEST | `RevealView.luau:288, 347` (RenderStepped pivots), `StationView.luau:587`, `PetMotion.luau:139, 222` (Heartbeat `PivotTo(base*offset)`, base frozen at start) | Two writers on one model. In the reveal, RenderStepped sets the pose before render so the pet shows RevealView's position while bones still animate; in StationView nothing re-pivots after `hatch`, so the frozen base is fine. Visual only. | Look at a Rare+ hatch in Studio; if the pet jitters call `PetMotion.setBase(model, cf)` from RevealView each frame instead of `PivotTo`. |
| Pet follow hidden during hunts | PASS | `src/server/PetService.luau:40-44` (returns "[]" when attribute `MatchKey` is set), `:243-249` (re-run on every `MatchKey` change), `src/client/PetFollow.luau:76, 177` | Server blanks `PetsShown`, client `rebuild` destroys followers; set by `MatchService.luau:615, 721`, cleared `:555, 560`. | Confirm in Studio that practice/tutorial also sets `MatchKey` (it uses the same match path). |
| PetFollow cleanup on leave / respawn | PASS | `PetFollow.luau:171-199, 313-314` | Conns disconnected, models destroyed on `PlayerRemoving`; respawn only un-parents and snaps (`Height = -1`). | none |
| Hatch reveal fires once | PASS (static) | `src/client/RevealView.luau:280-312` (`once("sound")`, `once("burst")`, `once("shimmer")`, `once("win")`), `:322` (choir once, only SlowMo) | Each side effect is guarded by `once(...)`; `RevealView.play` starts with `close()`. | Studio: trigger a Reveal then a duplicate `Results`; confirm no second roar/confetti. |
| Egg crack sound/FX once | PASS (static) | `StationView.luau:467` (`splitOrdinary`) and `:548` (`openGeode`) | One `Audio.rockCracked` per crack event (two different code paths, never both for one egg). | none |
| Coin fly / sale FX once | PASS (static) | `src/client/Main.client.luau:445-466` | One `Fx "Sell"` event = one Sale sound + one cashFly + gravel bits. Pooled and capped at 40 pieces (`Effects.luau:23, 68-77`). | none |
| Rare banner + fireworks once | PASS | `src/client/ui/RareBanner.luau:127-168`; `src/server/RareHatch.luau:35-55, 78-99` | Queue with `QueueMax`; local banner fires once; own MessagingService echo suppressed by `sent[echoKey]`; receive rate limit. | none |
| Egg wobble hint fires once per egg | PASS | `src/client/EggFx.luau:33-37, 225-237` (`wobbling[model]` guard); Overtime glow guarded by `FindFirstChild("OvertimeGlow")` (`:243`) | A second Wobble for a model already wobbling is ignored; the heartbeat connection is disconnected on every exit path. | none |
| Speed boots fire once, no stacking | PASS | `src/server/EggEvents.luau:174-205` (`boosts[uid]` blocks a second roll, token guards `endBoost`), `src/client/EggFx.luau:87-90` (old sparkle destroyed first), `:150-170` (one ticker) | One event per grant to the match; sparkles replaced not stacked. | none |
| Low Effects really reduces particles | PASS with gaps | `Effects.luau:38, 149, 181, 233, 271, 334` (halved); `HitFx.luau:44`; `RareBanner.luau:80-82` (2x8 instead of 5x14); `PetSparkle.luau:12-49` (all tagged Sparkles off); `EggFx.luau:79`; `Main.client.luau:451` (gravel bits skipped); `PileView.luau:234`, `StationView.luau:214` | Gaps: (a) procedural-pet Rainbow/SilverCosmic Sparkles and Legendary Beams are NOT tagged "PetSparkle" (`src/shared/PetModel.luau:592-598, 620-633`); (b) PointLights on hatch/gallery pets stay on (`PetModel.luau:143-152`); (c) `TowerView.luau`, `Tower.client.luau`, `TowerPanel.luau` have no LowEffects/ReducedMotion check at all (0 hits). | (a) `CollectionService:AddTag(sparkles, "PetSparkle")` at 592 and give the Beams the same treatment in `PetSparkle.apply`. (b) disable PointLights too in `PetSparkle`. (c) read `State.Profile.Settings.LowEffects/ReducedMotion` in TowerView hit/death effects. |
| Sound id 0 skipped quietly | PASS | `src/client/Audio.luau:97-110` (resolves to 0), `:162` (`if id == 0 or not started then return false`), `:266-269` (loops), `:438-441` (ambience), `EggFx.luau:186` (`cfg.SoundId ~= 0`) | No warn, no Instance created. | none |
| Sound that loads late is cut off | NEEDS STUDIO TEST | `src/client/Audio.luau:215` | Safety `task.delay(math.max(s.TimeLength, 1.5) + 1.5, finish)` runs right after `Play()`; `TimeLength` is 0 until the asset loads, so the timer is 3 s. A longer clip (HatchChoir / HatchBuildUp "Vast Horizon - Sting", the 4 s slow-mo build-up) can be destroyed early. | Use `s.Loaded:Wait()` (with timeout) or set the delay from `TimeLength` in a `GetPropertyChangedSignal("TimeLength")`; at minimum raise the floor to 8 s for `HatchChoir`. |
| Sounds never wired / dead ids | FAIL (cosmetic) | `src/shared/PetSoundIds.luau:14-16, 26-27, 33-34, 35`; `EggConfig.luau:55` | `CoinPickup`, `SpeedBoots`, `TowerHit`, `TowerSpecial`, `BossRoar`, `EggChirp` are never played by any code (grep of `Audio.play(` shows none of them; Tower client has no Audio calls). `EggConfig.Chirp.SoundId` is a separate hard-coded 0 and does not read `PetSoundIds.EggChirp`, so uploading an EggChirp sound would not enable the chirp. | Hook `Audio.play("CoinPickup")` in the Sell Fx, `SpeedBoots` in the Boots handler, Tower hit/special/boss in TowerView; make `EggConfig.Chirp.SoundId` read `PetSoundIds.EggChirp`. Until then they are inert (harmless). |
| Licensed / public audio may fail | NEEDS STUDIO TEST | `src/shared/PetSoundIds.luau:11-12, 21-22, 35` | `RaceMusic 1837560399` (very old id), `HatchRoar 820661880` and `BossRoar 257001341` are "public upload" ids by other creators: audio not owned by the place owner can be private/deleted and silently fail in the live game even if it played in Studio. APM-licensed `LobbyMusic` / `HatchBuildUp` are Creator-Store licensed tracks (usable, but confirm they show as available in the live server). | Play a live (non-Studio) server and listen for each; re-upload the two public roars as own audio if they are silent. |
| Respawn stacking | PASS (no tracks) | `ToolAnim.luau` (see above); `EggFx.luau:87-90` | No AnimationTrack exists to stack; the only per-character effect (boots sparkles) is replaced. | none |

## 2. Sound ids

Rule from code: `0` = skipped silently. `Owner` column = what repo/docs state. All SoundIds entries were uploaded with `tools/upload_audio.py` using Open Cloud with `creationContext.creator.userId = 20194281` (`tools/upload_audio.py:50`, `docs/AUDIO.md` regenerate block uses `ROBLOX_USER_ID=20194281`) -> "docs say uploaded as user 20194281; not confirmed in Studio; docs/AUDIO.md:7-9 say never listened to or moderation-checked".

| Source | Name(s) | Id | Purpose | Owner status |
|---|---|---|---|---|
| shared/SoundIds (29 generated) | Button | 137600997709297 | UI press | uploaded as 20194281 per tool - NEEDS STUDIO TEST (moderation) |
| | ConveyorHum | 116407567137133 | machine loop | same |
| | CountdownTick | 79652696354111 | hunt countdown | same |
| | CrusherLoop | 138428497803897 | machine loop | same |
| | Deposit | 126483540112150 | nest deposit | same |
| | GeodeReveal | 72391498318833 | reveal | same |
| | GravelSpill1 / 2 | 78940181344173 / 82891299772928 | rubble | same |
| | HammerHit1 / 2 / 3 | 72227078896273 / 86601388019916 / 102759260321003 | strike | same |
| | JackhammerLoop / Start / Stop | 131504600976872 / 78634490499816 / 83018819731984 | tool | same |
| | LobbyAmbience | 122930016244785 | defined, NOT used (area bed uses PetSoundIds LobbyMusic) | same |
| | QuarryAmbience | 119856364587738 | defined, NOT used | same |
| | MachineHum | 114419246012514 | press hum | same |
| | MatchWin | 109965175431278 | win fanfare (also HatchWin alias) | same |
| | MaterialFound | 83895168221710 | first-find | same |
| | Pickup | 112800468947570 | egg pickup (EggPickup alias) | same |
| | PressDescend / PressImpact / PressRetract | 114004518104171 / 112924982562568 / 91989972714719 | press | same |
| | Purchase | 120358225055021 | ok toast | same |
| | RarityAccent | 109340819460170 | reveal + banner (RareSparkle alias) | same |
| | Sale | 110909694539094 | sell | same |
| | StoneCrack1 / 2 / 3 | 112535091051990 / 130830642781604 / 111531578619182 | crack | same |
| shared/PetSoundIds direct | LobbyMusic | 140660383888658 | lobby bed ("Sun on the Porch", APM) | Roblox-licensed per comment - NEEDS STUDIO TEST on live server |
| | RaceMusic | 1837560399 | hunt bed ("High Energy", APM) | Roblox-licensed per comment; old id - NEEDS STUDIO TEST |
| | HatchBuildUp (= SoundConfig HatchChoir) | 87681931953984 | Rare+ build-up ("Vast Horizon - Sting", APM) | Roblox-licensed per comment - NEEDS STUDIO TEST (also TimeLength cut-off risk above) |
| | HatchRoar | 820661880 | shared roar for ALL 50 species | public upload by someone else (per comment) - owner unknown - NEEDS STUDIO TEST |
| | BossRoar | 257001341 | tower boss roar, NOT played by any code | public upload (per comment) - owner unknown |
| PetSoundIds = 0 | EggTap, EggBreak, EggChirp, CoinPickup, SpeedBoots, TowerHit, TowerSpecial | 0 | not uploaded (`SoundIds.X or 0`; SoundIds has no such keys) | skipped quietly |
| shared/SoundConfig | Roar[species] x50 | all = HatchRoar 820661880 | per-species roars not made | same as HatchRoar |
| shared/EggConfig:55 | Chirp.SoundId | 0 | egg chirp | skipped quietly |

## 3. Mesh / texture / animation ids

Animations: 0 in repo, 0 in both place files.

| Source | Count | Purpose | Owner status |
|---|---|---|---|
| `src/shared/MeshIds.luau` | 182 ids (0 of them zero; all distinct), by prefix: Lodge_ ~32, Prop_ 20, Court_ 15, Gallery_ 12, Station_ 10, Terminal_ 8, Cliff_ 10, Lobby_ 6, Lobby7_ 5, Geode_* 15, Strata_ 4, CT_Rocks_* 11, Tool_ 3, others ~12 | Model assets (glb/fbx) loaded at boot by `MeshService` with `InsertService:LoadAsset` into `ReplicatedStorage.Assets` (`MeshService.luau:205-240`, 182 parallel loads) | docs/ASSET_MANIFEST.md:7-9 and `tools/upload_meshes.py:3-5, 57, 94`: uploaded as user 20194281 via Open Cloud. Not verified in Studio. NOTE: `LoadAsset` only works if the place creator owns the asset (or it is free/public), so moving the game to a group breaks every kit mesh unless re-uploaded under the group. |
| `src/shared/MeshCatalog.luau` | 0 asset ids (placement/colour data only) | per-piece offsets for the MeshIds models | n/a |
| `assets/PetModels.rbxmx` | 10 MeshParts, 20 ids, 84 Bones | the 10 launch pets (skinned) | not in `art/meshes/uploaded_ids.json`; docs/FIND_THE_PET.md says "models made on the owner's PC" -> owner unknown - NEEDS STUDIO TEST |
| `src/assets` | (does not exist; assets live in `assets/`) | | |

PetModels ids (identical in the repo rbxmx, in `FindThePet.rbxlx` ReplicatedStorage.PetModels and in `FindThePet_WITH_LOBBY.rbxl` ReplicatedStorage.PetModels and Workspace.PetLineup):

| Pet | MeshId | TextureID |
|---|---|---|
| CosmicDragon | 121406743115065 | 107725290581100 |
| DireWolf | 109295933346307 | 79759316194032 |
| FrostWyvern | 97743485036125 | 129762737381318 |
| Griffin | 140451292432333 | 94634027618827 |
| LavaTRex | 140259176520050 | 133828932950890 |
| Mammoth | 93921687577281 | 74332095640965 |
| Ostrich | 121709500522998 | 77714439301377 |
| Phoenix | 105262078177798 | 75807391096725 |
| Raptor | 123509309553233 | 114418249744757 |
| StarPterodactyl | 105889078042928 | 103678914968630 |

Other pet code paths: 40 of the 50 species (35 hunt species not in the table above plus the 5 tower pets) have no mesh and use the procedural stand-in (PetModel.build), as the brief expects.

Lobby ids found only in `FindThePet_WITH_LOBBY.rbxl` (not in repo; 34 ids, 557 MeshParts, every one with a TextureID). Owner unknown - NEEDS STUDIO TEST (all of these are not in `MeshIds.luau`, so they are the owner's hand-placed Meshy/Studio uploads):

| Template (ServerStorage.LobbyTemplates / *Template) | MeshId | TextureID | Placed copies in Workspace.FTP_Lobby |
|---|---|---|---|
| Fence | 114453178116313 | 126455240885549 | 132 (Plots) |
| Cliff | 112233479344584 | 70978430930797 | 22 (Decor) |
| BushTemplate.body | 120940493530675 | 81249300929030 | 19 (Jungle) |
| TreeTemplate.body (Tree1..60) | 128188204990854 | 88450927735808 | 13 (Jungle) |
| RoundTree | 85452168565452 | 136920107250161 | 12 (Jungle) |
| Pedestal | 132116174097662 | 139939768168463 | 12 Plots + 4 DisplayEggs |
| StoneBase | 138741480375372 | 101544915820620 | 6 |
| Hut | 70662834831434 | 101619312750268 | 6 |
| CatStatue | 135977052261032 | 111887085367253 | 2 (Buildings) |
| Buildings (3 more MeshParts) | 104818596848023, 121428725258874, 78926918437770 | 83740230036305, 90338598849732, 90364514287661 | 1 each |
| SecretEgg | 78289001670112 | 93790667150275 | 1 |
| Lantern / Lantern2 / Nest / Shop2 (templates only, not placed) | 96237893664471 / 81723848176910 / 101647689594138 / 87462883195818 | 128217357996398 / 101496514634877 / 87616744599919 / 91845985388239 | 0 |
| Waterfall `Texture` | (Texture.Texture) rbxassetid://5434484211 | | 1 (+1 backup): ancient id, public Roblox-era asset, may not be usable - NEEDS STUDIO TEST |
| Waterfall ParticleEmitter, Sky | `rbxasset://` built-ins only | | safe |

## 4. Place files (read-only)

| Item | `FindThePet.rbxlx` (XML, 09:02) | `FindThePet_WITH_LOBBY.rbxl` (binary, 09:06, newest) |
|---|---|---|
| Instances | 263 | 2786 (557 MeshPart, 480 Part, 1149 Model, 168 Bone) |
| Scripts | 138 (2 Script, 3 LocalScript, 133 ModuleScript) | 96 (4 Script, 3 LocalScript, 89 ModuleScript) |
| Scripts same as current repo | 111 | 54 |
| Scripts older/changed vs current repo (same name) | 27 | 38 (e.g. Client.Main 21743B vs 22924B, Audio 14359B vs 15533B, Config, PetFollow, MatchService, Profiles) -> this place was built BEFORE the latest commits; it is stale, not tampered |
| Scripts NOT from repo | 0 | 4, listed below |
| `require(<number>)`, getfenv, setfenv, loadstring, string.char chains, hex/decimal escape strings, long base64 literals | none | none |
| HttpService / InsertService / MarketplaceService / TeleportService | all expected: HttpService only for JSON (PetFollow, PetService, PartyService, MatchService, Profiles, LobbyLaunch, RobuxService); InsertService only `MeshService`; MarketplaceService in Robux/Store/Tower/ShopPanel; TeleportService only in `MatchPlace` and `LobbyLaunch` (mode off) | same set (older versions) |
| Obfuscation | none found | none found |
| ReplicatedStorage.PetModels | 10 Models, each 1 MeshPart + Bones (104 descendants) | 10 Models (same ids as repo) |
| ReplicatedStorage.PetMotion | ModuleScript, identical to `tools/owner/PetMotion.luau` (4320 B) | identical (4320 B) |
| Workspace content | empty (0 children): this is a bare Rojo build, so the lobby is built by code at runtime | Terrain, Camera, `PetLineup` (10 pets), `FTP_Lobby` hand-built (Ground 22, QueuePads 4, Leaderboards 2, Plots 6, Buildings 4, Jungle 44, SecretEgg, Decor 4, DisplayEggs 4) |
| ServerStorage | none | LobbyTemplates (Fence, Cliff, Hut, Nest, Pedestal, StoneBase, Lantern, Lantern2, RoundTree, Shop2, CatStatue), TreeTemplate, BushTemplate, LobbyBackups (FTP_Lobby_backup_0235 with 60 trees + a Lighting backup) |
| Meshy tree + sign models | no such models | Trees: 25 `TreeN` / `RoundTreeN` Models in Workspace.FTP_Lobby.Jungle, `ServerStorage.TreeTemplate`, `LobbyTemplates.RoundTree`, ~60 backup trees: 0 scripts in all. Signs: PlotSign + SignPost x6 per plot set, HatchStand.Sign, TowerEntrance.Sign, EggShop.Sign (plain Parts): 0 scripts. The only scripts inside any Workspace/ServerStorage model are the two `WaterfallFlow` copies. |
| Sound / Animation instances | 0 / 0 | 0 / 0 (a `SoundService` object only) |
| Workspace.StreamingEnabled | false | false (StreamingMinRadius 64, TargetRadius 1024, unused) |
| Players.MaxPlayers | 12 | 12 (`MaxPlayersInternal`) |
| Players.CharacterAutoLoads / RespawnTime | true / 5 | true / 5 |

Scripts in the binary place that are NOT in the repo (all four read in full; none obfuscated, none remote-requiring):

| Script | Class | Content | Verdict |
|---|---|---|---|
| Workspace.FTP_Lobby.Decor.Waterfall.WaterfallFlow (+ identical copy in ServerStorage.LobbyBackups...) | Script (server) | one-line loop scrolling a `Texture.OffsetStudsV` every 0.03 s forever | Benign, but a server-side 33 Hz property write that replicates to every client; move to client `LobbyAmbience` (already has a waterfall) or use a Tween loop. |
| StarterPlayer.StarterPlayerScripts.PetPreview | LocalScript | "Studio preview only ... Delete before release"; requires PetMotion, animates `Workspace.PetLineup`, toggles `Moving` every 5/3 s | FAIL if published: ships a debug script plus a 10-pet lineup in Workspace. Delete the script and `Workspace.PetLineup` before release. |
| ServerScriptService.TEMP_HideOldLodge | Script | moves the runtime `CT_Rocks_Lobby` 3000 studs away and disables its spawn | FAIL if published: "TEMP, remove when the repo fix lands". It loops `DescendantAdded` forever and hides the code-built lobby; with the current repo (ParkBuilder lobby) it may hide the real lobby or do nothing. Remove once the repo builds only one lobby. |

Other place findings:

| Feature | Result | File + line | Problem | Fix |
|---|---|---|---|---|
| Lobby comes from two sources | NEEDS STUDIO TEST | `src/shared/MapNames.luau:1-4` ("The owner builds the lobby by hand in Studio (Workspace.FTP_Lobby)") vs `docs`/audit spec ("code-built park: ParkBuilder") and the binary place (hand-built FTP_Lobby + TEMP_HideOldLodge) | The repo can build the lobby (ParkBuilder/LobbyBuilder) and the place also carries a hand-built one; which one a live server shows depends on MapHooks and the temp script. | Decide one lobby; confirm in a Studio play test that exactly one SpawnLocation and one set of QueuePads exists. |
| Place files are not the live game | NEEDS STUDIO TEST | both place files on Desktop | Both are older than the repo HEAD (27 / 38 scripts differ). They are not proof of what is published. | Re-sync with Rojo before judging the published place; audit the published version's Output for asset failures. |
| StreamingEnabled | PASS (value) / NEEDS STUDIO TEST (published) | both place files; repo `default.project.json` does not set it | Disabled in both files, matches the "no streaming" assumption of `PetDisplay` (`try` requires `IsDescendantOf(Workspace)` at add time). Published place setting not visible here. | Check the live place's Game Settings > Workspace. |
| MaxPlayers 12 | PASS | both place files | matches "12 players/server" | none |
| Foreign / obfuscated scripts in places | PASS | `dump_xml.txt`, `dump_lobby.txt` | No `require(number)`, no getfenv/setfenv/loadstring, no encoded strings in either file; only the three non-repo scripts above. | Remove PetPreview + TEMP_HideOldLodge before release. |
| Meshy tree/sign models have zero scripts | PASS | `dump_lobby.txt` section "tree/sign/meshy" | 0 scripts under every Tree*, RoundTree*, Sign*, PlotSign*, SignPost* Model/Part (live and backup). | none |
| Place mesh/texture ownership | NEEDS STUDIO TEST | table in section 3 | 34 lobby ids + 20 pet ids cannot be owner-checked offline; no AnimationId/Sound ids in either place. | Open each id in Creator Hub (or insert in Studio) while logged in as kcdrewcarter / the group. |

## 5. Counts

- Animations: repo 0, XML place 0, binary place 0.
- Sounds: 29 generated + 5 direct (music/hatch/boss) + 7 zero placeholders + 50 species roars (all = HatchRoar) + 1 zero chirp.
- MeshIds (Model uploads): 182; PetModels: 10 meshes + 10 textures; binary-only lobby: 34 distinct mesh/texture ids over 557 MeshParts (Meshy-style Fence 132 copies, Cliff 22, Bush 19, Tree 13, RoundTree 12, Pedestal 16, Hut/StoneBase 6 each).

## Section 5: UI


Repo: scratchpad/repo. Read-only. Nothing here was run in Studio. "PASS" = proven from code. Line numbers are in the repo files as read.
Names are old on purpose (rock = egg, geode = pet, Quarry = Forest ...) and are NOT reported as bugs.

## 0. Offline preview status: BLOCKED (tried once, stopped)

| Step | Result |
|---|---|
| Lune | `ctr-tools/lune/lune.exe --version` -> `lune 0.10.4` (works on Windows) |
| Node | `node: command not found` (no Node anywhere: not in PATH, not in Program Files, no nvm/volta). Renderer step 2 (`node tools/preview/renderer/render.mjs`, three.js + headless Chromium) cannot run. |
| Python | `python3` / `python` are the Microsoft Store stub: "Python was not found; run without arguments to install from the Microsoft Store". `tools/preview/fonts/fetch_fonts.py` and `check_layout.py` need Python 3. |
| Lune step 1 alone | `lune run tools/preview/runtime/main.luau -- --scene collection --device phone-1108 ...` -> `[preview] fonts are missing: run bash tools/preview/setup.sh` (fonts come from the Python fetcher). |
| Scripts | `render.sh` / `setup.sh` are Linux-only (download the linux-x86_64 Lune zip, `/opt/pw-browsers`). |
| Chrome / Edge | Present (`C:/Program Files/Google/Chrome/Application/chrome.exe`, `C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe`), so CTR_CHROMIUM would work, but Node and Python are the blockers. |

Nothing was rendered, `findings/renders` was not created, `check_layout.py` was not run. No packages were installed.
Unblock: install Node 20+ and Python 3.11+ (winget), then
`CTR_TOOLS=<abs>/ctr-tools CTR_CHROMIUM="C:/Program Files/Google/Chrome/Application/chrome.exe" bash tools/preview/render.sh lobby,hunt,results,shop,collection,settings --devices phone-1108,phone-portrait,pc --outdir ../findings/renders`
then `python tools/preview/check_layout.py ../findings/renders`.
Scenes that exist: lobby, party, hunt, results, shop, collection, settings, inspect, news, quests, eggshop, petflair, tutorial, launch, boards, signs. There is NO tower scene, so the Tower HUD and picker have no offline render at all.

## 1. How the UI kit works (so the tables make sense)

* `UI.text` / `UI.button` set `TextScaled = true` plus a `UITextSizeConstraint` (`UI.fit`, UI.luau:277-289): the `TextSize` prop is only the MAX size, min is `T.MinText` 12. So the 196 `TextSize =` hits in grep are almost all fine (they go through UI.text/UI.button). Raw (not fitted) text: `UI.notify` label (UI.luau:1907-1913, deliberately TextScaled=false, auto-height), the confirm TextBox (UI.luau:1659), billboards (NameTag, PetFollow, HatchStand use UI.text inside a BillboardGui at 1:1 px).
* Scale: `UI.scaleFor` (UI.luau:121-129): landscape = min(W/800, H/400) floored at 0.8, portrait = W/390 clamped 0.8..1.3. Every layer is a ScreenGui with `ScreenInsets = CoreUISafeInsets` and a UIScale (UI.luau:152-173).
* Modal shell `UI.modal` (UI.luau:1434): red X close 40 px with a 46 px hit area (UI.luau:852-875), tap-outside closes (unless `Dismissable=false`), gamepad B closes the top layer (CameraMode.luau:244-252), panel = screen minus 24 x 12, capped by a UISizeConstraint, so it always fits the safe area. Dialogs (`UI.confirm`) stack above and have X + CANCEL.
* ScreenGuis NOT using the shared layer/scale: TowerPanel (`gui()` TowerPanel.luau:49-56: no UIScale), LoadingScreen, CameraMode (1x1 invisible).

## 2. Global findings

| Feature | Verdict | File + line | Problem | Fix |
|---|---|---|---|---|
| Touch target floor (44) | FAIL | Theme.luau:74-81 (`Touch/Button = 44` logical px, `Tab = 34`); UI.luau:121-129 | 44 is LOGICAL px. On any landscape phone below 800x400 the UIScale is 0.8-0.97 (844x390 -> 0.975 = 43 px; 667x375 -> 0.834 = 37 px; 568x320 -> 0.8 = 35 px). So even "44" buttons are under 44 physical px on those phones. Only phone-1108x512 (scale 1.28) and PC are safe. | Make `UI.button` / slider / toggle min height `ceil(44 / scale)` (keep the scale in UI), or raise `Theme.Size.Touch` to 48 and `Tab` to 44. |
| Tabs bar | FAIL | Theme.luau:81, UI.luau:932 | Every tab bar (Shop, Collection, Party, Tower) is 34 logical high = 27-33 px physical on phones. | `Tab = 44` (tabs are one line). |
| Close button | PASS | UI.luau:852-875 | Red X 40 px + invisible 46 px hit child (child sinks the click, fires the handler once). Present in every `UI.modal` (nobody passes `NoClose`). | none |
| Confirm dialog buttons | PASS | UI.luau:1675-1690 | 46 px row, X + CANCEL + tap outside. Rename TextBox 40 high (UI.luau:1665), acceptable for a typing box. | optional 44 |
| Notice X | FAIL | UI.luau:1915-1917 | Notice close X is 30x30 -> 36 px hit area. | 44 hit area, or no X (notices auto-dismiss in 2.8 s). |
| Minimum readable text | FAIL (minor) | Hud.luau:101-103 (menu tile caption min 9), Hud.luau:120-122 (tool slot caption min 9), Hud.luau:331 (`fit(ml, Tiny+1, 10)`), UI.luau:950-974 (tab labels min 9) | `MinText` is 12 but these spots shrink to 9-10 logical = 7-9 px physical on small phones. | Keep min >= 11 and shorten captions ("Upgrades" is the longest). |
| Portrait support | NEEDS STUDIO TEST | UI.luau:191-199; Hud.luau:441-507 (`placeTop`: objective/hint stack, columns start under it, notices re-placed); ShopPanel.luau:579-584, 634-636; CollectionPanel.luau:274-381; ResultsPanel.luau:106, 316; QuestPanel.luau:132 | Portrait branches exist in every screen checked; no render proves nothing clips. | Run the matrix once Node/Python exist. |

## 3. Per-screen table

Jump button model (shared/TouchLayout): large (120 px) when the shorter side > 500, so phone-1108x512 uses the 120 px model; reserved area = model x1.1 + 14 px from the bottom-right corner. Only Hud's PrimaryAction uses TouchLayout (Hud.luau:556); nothing else in src does.

| Feature | Verdict | File + line | Problem | Fix |
|---|---|---|---|---|
| Hud: cash, counters, timer, objective | NEEDS STUDIO TEST | Hud.luau:268-410 | Left column (132 wide) and right column (64 wide) are fixed-logical-px auto-sized lists; objective centred with a 360 cap. No measurement. Hunt left column is about 340 logical tall (Timer 52 + 3 counters 52 + Processing 40 + Machine 44 + roster), reaching toward the default thumbstick on 390-high phones. These cards are not Active so they do not eat touches. | render hunt on phone, phone-1108, phone-portrait |
| Hud: menu tiles | PASS (size) | Hud.luau:81-110 | Tiles 56 px (Settings 44). 44 logical only 35 px at scale 0.8. | Settings tile 48+ |
| Hud: right menu column vs jump button | FAIL (by model) / NEEDS STUDIO TEST | Hud.luau:343-372, 905-922 | Lobby column = Settings 44 + Shop/Collection/Party 56 + gaps 6 = about 230 logical, + 12 edge = 242. On phone-1108x512 (scale 1.28) that ends 310 px from the top; the large-model jump button top is 512-210 = 302 px and it spans 50-170 px from the right edge; the column spans 15-97 px. Party tile overlaps the jump rect by about 8 px and the inflated reserved area (top at 264 px) by about 46 px. The tiles are not placed with TouchLayout. | Check column bottom against `TouchLayout.reserved`; fall back to a 2-column / 44 px tile row on screens <= 520 high. |
| Hud: PrimaryAction (hunt button) | PASS (code) | Hud.luau:539-583 | `TouchLayout.place`: "above" the jump area, falls back to "left" on the bottom row, stays right of the tool dock; 124x64 (CRACK 150x94). The real jump rect still needs Studio measuring (TouchLayout.luau header says the model is "from memory"). | Studio measure |
| Hud: tutorial hint card + SKIP/OK | FAIL | Hud.luau:402 (`SKIP` 54x36), 406 (`OK` 46x36) | Both 36 high, 6 px apart. SKIP does confirm first (good). | 56x44 and 52x44, widen the card |
| Hud: DAILY button | FAIL (minor) | Hud.luau:292 (112x42) | 42 high. | 44 |
| Hud: LOBBY tile in hunt | PASS | Hud.luau:368-370 | 56 px tile with `ConfirmReturn` dialog. | none |
| PlayButton (PLAY + queue card) | FAIL (minor) | PlayButton.luau:93 (`LEAVE` height 40) | PLAY 172x52 ok; LEAVE 40 high. Frame is 172 wide in a 132 wide list (overflows right, harmless). | LEAVE 44 |
| TowerPanel entry button | NEEDS STUDIO TEST | TowerPanel.luau:136-139 | `TOWER` 110x44 at x 12, y = 62% of screen height, left half. On phone-1108x512 that is y about 317 px (+/- 28); the default thumbstick (bottom-left about 120 px) reaches about y 337: likely overlap. Own ScreenGui with no UIScale. | Put it in the HUD left column (under PLAY); use UI layers. |
| TowerPanel HUD (floor, LEAVE, SPECIAL) | FAIL | TowerPanel.luau:148-170 | (a) LEAVE 100x36. (b) SPECIAL 180x70 bottom-centre ignores TouchLayout; on portrait 390x844 its left edge is 105 px from the left (inside the thumbstick zone) and its right edge is 105 px from the right (about 13 px into the jump reserved margin). (c) ScreenGui has no UIScale, so it ignores the 0.8-1.3 scale. | Use `UI.screen()` layers; place SPECIAL with `TouchLayout.place`; LEAVE 56x44. |
| TowerPanel picker | PASS (structure) / FAIL (detail) | TowerPanel.luau:104-135 | Modal with X, subtitle, 70 px rows, EQUIP BEST / CLIMB footer (64). But tapping a pet row calls `close()` after every pick (line 122-124): 3 picks = 3 close/open cycles. | keep open, refresh rows in place |
| TowerPanel floor-end cards | PASS | TowerPanel.luau:215-265 | `UI.confirm` with explicit choices, Robux revive spelled out. `UI.notify(..., "success")` at line 211 uses a kind the notice kit does not list (ok/warn/info/cash/geode/material): falls back to no icon. | use "ok" |
| NewsPopup | PASS | NewsPopup.luau:18-34 | Modal with X + GOT IT (46). Fixed body for 5 lines x 34 fits a 400-high canvas (about 342). More than about 6 lines would clip (body does not scroll). | scroller or size from `UI.Logical.Y` |
| SettingsPanel | PASS (mostly) | SettingsPanel.luau:47-129 | Scrolling body, 46 px rows, 44 px slider/toggle hit boxes, X close. SKIP tutorial button 90x36 (line 121). | SKIP 44 high |
| QuestPanel (DAILY) | FAIL (minor) | QuestPanel.luau:63-65 (OPEN gift 40 high), 113-122 (Claim buttons 40 high) | 40 px buttons. Scroller body, X, cash readout fine. | 44 |
| PartyPanel | FAIL (minor) | PartyPanel.luau:132, 135 (ACCEPT/DECLINE 100x38), 220 (Kick = 30x30 X, hit 36, no confirm), 293 (Invite 112x38) | Several 38 px buttons. A mis-tap on the kick X removes a friend. Members/Invite tabs, X present. | 44 px; confirm on kick |
| LaunchPanel | PASS (dead path) | LaunchPanel.luau:1-232 | Teleport mode only (`Config.Places.Mode = "SinglePlace"`), never shown. Buttons 44 high. Legacy colour names still exist in UI.Colors, button styles "yellow"/"dark" are aliased (UI.luau:659-662). | none |
| ShopPanel (UPGRADES) | FAIL (minor) / NEEDS STUDIO TEST | ShopPanel.luau:433-503, 589 (rows 50/58), 620 (EGG SHOP button height 40), 579-584 (portrait stack), 541-543 | Detail card is Fixed with `footH 46`, `textH 40/48`. Tabs 34 (global). The Robux tab/EGG SHOP button calls `RobuxShopPanel.open()` which closes this menu (primary slot replaced) and the egg shop has no BACK to Upgrades, only X. | 44; BACK on RobuxShop |
| RobuxShopPanel (EGG SHOP) | PASS (odds) / NEEDS STUDIO TEST (fit) | RobuxShopPanel.luau:109 (hidden unless `PaidRandomRestricted == false`), 187-224 (full odds above the buy button), 364-374 | Compliance good: eggs hidden until PolicyService result known, odds listed before buying. Fit on 400-high landscape not proven. | render |
| CollectionPanel (PET BOOK) | FAIL | CollectionPanel.luau:189 (Rename 52x26), 276 (toolbar height 30: SORT/FAVS/SELL), 348-378 (footer 28 high: EQUIP BEST, pager `<` `>` 34x28), 226-236 (FAV/SELL row 34), 205 (Equip 40) | Densest sub-44 cluster: toolbar 30, footer 28, rename 26, FAV/SELL 34, tabs 34. A big pet book on a phone is mis-tap heavy. Portrait branch exists (45% grid / 55% detail). | 44 high toolbar/footer; Rename 56x44 |
| InspectPanel | PASS | InspectPanel.luau:23-42 | Modal + X + CLOSE footer 58 high. Fixed 330 canvas fits 400. | none |
| ItemView / GeodeView | PASS | ItemView.luau, GeodeView.luau | Non-interactive ViewportFrames. | none |
| ResultsPanel | NEEDS STUDIO TEST | ResultsPanel.luau:196-232 (footer buttons 46), 316 (`Dismissable=false`, `Footer=62`, `Fixed=true`, 580x360), 106 | Buttons OK. Facts column is a fixed, non-scrolling 244 logical px (360-54-62); tutorial stage line + payout + others + rematch note can exceed it on short phones. X exists and a "Results" HUD tile reopens it, so no soft-lock. | verify on phone-1108 and 844x390 |
| RevealView | PASS | RevealView.luau:329-347 | Full-screen tap-to-skip; reduced-motion skips to end. | none |
| RareBanner | PASS | RareBanner.luau:85-130 | Non-interactive; landscape width min(440, 0.5 W) at x 0.56 W, y 58 sits between the left and right columns on an 800 logical canvas. | none |
| NameTag (lobby) | NEEDS STUDIO TEST | NameTag.luau:56-83 | Billboard 18 px / 15 px at 1:1 px, MaxDistance 60, not scaled to the screen. | check in Studio |
| PetFollow tags | NEEDS STUDIO TEST | PetFollow.luau:128-147 | 14 px text per follower, up to 12 in a lobby. | same |
| HatchStandView tag | PASS | HatchStandView.luau:34-47 | 260x56 billboard, 18 px, MaxDistance 90. | none |
| LobbyBoards (SurfaceGui) | PASS (code) | LobbyBoards.luau:30-110 | TextScaled + UITextSizeConstraint min 8 on the board face; `tools/preview/check_signs.py` exists. Not run (needs Python). | run check_signs |
| Queue nest signs | NEEDS STUDIO TEST | ParkBuilder.luau:445-466; QueueConfig.luau (Board texts) | `QueueGui` SurfaceGui 40 px/stud, TextScaled, "STEP ON TO PLAY" / "HUNT IN %ds  (%d/%d)". Readable from the spawn not verified. | Studio look |
| Gamepad / keyboard | PASS | UI.luau:1352-1395; CameraMode.luau:244-252 | Selection group, first control selected, B closes dialog then menu. | none |
| Every menu has close + back | PASS (close) / FAIL (back) | UI.luau:1405-1427 | All modal panels have X. "Back" only where there is a drill-down (Collection picker Cancel, Party tabs). Menu-to-menu jumps do not return: Upgrades -> Egg Shop (ShopPanel.luau:541-543). | BACK button on menus opened from another menu |
| Raw TextSize in fixed boxes | PASS | grep `TextSize` in src/client | All 196 hits are UI.text/UI.button props (max size, shrink to fit). Genuine raw text: notice label (UI.luau:1907-1913, auto height, cannot clip) and dialog TextBox. `Instance.new("TextLabel")` outside UI.luau: TowerView.luau:138/260 (TextScaled), LoadingScreen.luau:51 (TextScaled+constraint). | none |

## 4. Top fixes by value

1. Make every interactive element a real 44 physical px (scale-aware min height; tabs 44; the nine 36-42 px buttons above).
2. Tower HUD: build with `UI.screen()` layers, `TouchLayout.place` for SPECIAL, LEAVE 44 px; move the TOWER entry button out of the thumbstick zone.
3. Lobby right column vs jump button on large phones (phone-1108x512).
4. BACK from Egg Shop to Upgrades.
5. CollectionPanel toolbar/footer heights.
6. Install Node + Python on this machine so the render matrix, `check_layout.py` and `check_signs.py` can run.
