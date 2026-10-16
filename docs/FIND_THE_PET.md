# Find The Pet (2026-10-10)

The geode hunt became a pet hunt. Plan: `/mnt/project-files/plans/find-the-pet.md` (project files). Nothing is Studio-tested.

## Owner picks
Name FIND THE PET!. 12 players per lobby, 4 per round (party size). Rounds about 3 minutes (no hard time limit yet: the
round ends when the pet egg is cracked). ONE pet follows you, in the lobby only (hidden during hunts so the race view
stays clear). Mixed boosts per species: Coins, Speed or Luck. Rarest pet 1 in 1000 (Legendary). Rare and better hatches
are announced to the whole server. First area Meadow. No trading, no egg stealing, pets do not evolve. Robux: see "Robux shop" below (boost eggs,
luck potions, passes, tower revive; 2026-10-11 pick replaced the old hats-and-trails-only rule). Style: chunky toy-like pets like "Steal an Egg".

## Code mapping (names kept, meaning changed)
| Code | Players see |
|---|---|
| rock, pile, RoundRocks, RockService | egg, egg pile |
| crushing table, StationModels / StationView | hatch nest |
| rubble, CashPerRubble | shells, coins |
| geode, Specimen, GeodeGen | pet |
| Specimen.Mineral, Config.Minerals | pet species (Raptor, Ostrich, Dire Wolf, Griffin, Frost Wyvern, Mammoth, Lava T-Rex, Phoenix, Cosmic Dragon, Star Pterodactyl) |
| Specimen.Modifier | variant: Natural, Golden, Skeleton, Rainbow, Silver Cosmic |
| Specimen.Formation | pose: Sitting, Standing, Waving, Sleepy |
| Tiers Gravel/Quarry/Cavern/Volcanic/Meteor | Meadow/Forest/Snow/Volcano/Space |
| Hammer/SteelHammer/Jackhammer | Lucky Collar/Treat Bag/Pet Whistle (AutoCracker/HydraulicPress/IndustrialCrusher = Auto Nest/Warm Incubator/Mega Incubator) |

## New pieces
- `shared/PetModel.luau`: procedural chunky pets (REPLACE with real meshes). `shared/GeodeModel.luau` now draws eggs,
  shells and the pet on a nest with the same API.
- `server/PetService.luau`: free starter pet (once), equip/unequip (`CollectionAction` "EquipPet"/"UnequipPet", lobby
  only), player attribute `PetsShown` (JSON) for followers. A freshly hatched pet follows you at once (`Profiles.grantSpecimen`).
- `client/PetFollow.luau`: draws every player's follower with a small name tag; fades when it blocks the camera.
- `Profiles`: `EquippedPets`, `StarterPet`, `petBoosts` (Coins raise shell prices; Speed raises hunt walk speed, capped
  at 15%; Luck lifts Rare+ odds of the pet you hatch, never which egg hides it). Old geode saves migrate to pets
  (`Config.MineralMigration`, `Config.ModifierMigration`); nothing is deleted.
- Leaderboard "Biggest" is shown as RAREST PET (best pet value).

## Owner picks, batch 2 (2026-10-11)
- Pet storage holds 100 (`Config.Inventory.Max`). `Profiles.petCapacity(data)` adds the save's `ExtraPetSlots` (0; the
  hook a future owner-made game pass helper raises). Saves holding more keep every pet; new pets stop until some are sold.
- Free renaming: Pet Book detail NAME button -> `CollectionAction("RenamePet", id, name)`. `PetService` checks the shape
  (`shared/PetRules.cleanName`, 20 characters, letters/numbers/spaces and `- _ . ! ? '`), filters with
  `TextService:FilterStringAsync` + `GetNonChatStringForBroadcastAsync` in a pcall (failure or any change = refused),
  one rename per 5 s, saves `Nickname` on the pet. Shown on Pet Book cards/detail, the follower tag and the lobby plaque.
- Forest already unlocks with coins: 500 coins + 5 pet finds (`Config.Tiers.Quarry`, `EconomyService` "UnlockTier"). Unchanged.
- Tutorial SKIP button on the tutorial hint card (with a confirm); the server still runs `PetService.ensureStarter`.
- Friend bonus: +10% Luck per Roblox friend in the same server, at most 3 (`QueueConfig.FriendLuck`,
  `server/FriendBonus`: cached `IsFriendsWith` in a pcall, player attribute `FriendLuck`). Applies to the finder of any
  non-practice hunt. Replaces the old party/queue-mate rule.
- Pet type (BoostKind) shown by colour (`Config.Pets.KindColors`) and a procedural icon (REPLACE markers in `UI.icon`
  `boostCoins` / `boostSpeed` / `boostLuck`): glow + icon on Pet Book cards, glow pill + icon on follower tags, a neon disc
  under each follower.
- Pets tab: sort buttons RARITY / LEVEL / TYPE (tap again = newest), EQUIP BEST (server picks the highest boost,
  `PetRules.best`, lobby only). Levels come from pet tower XP (`TowerConfig.Levels` = XpBase 40, XpStep 25, Max 100,
  LevelStat 0.04; `shared/PetStats.level`); the tower (`server/TowerService`) gives the XP. Levels only change tower stats.
## Pet flair (2026-10-11, owner picks; offline-verified only)
- Rare hatch: `server/RareHatch` (fireworks + gold banner in this server, banner in every other server through
  MessagingService topic "RareHatch", payload = display name + pet name + rarity, rate limited), `client/ui/RareBanner`.
- Hatch timing by rarity (`Config.Hatch`, `PetFlair.hatchTiming`): about 2 s for Common/Uncommon, about 6 s slow
  motion with a rarity glow for Rare+; the server's Reveal phase follows it. Choir build-up, then a sting by rarity (Epic+ sparkle swell, Legendary/Void drum hit). Pets never roar.
- Rarer pets are bigger (`Config.Pets.RarityScale`) and sparkle (`Config.Pets.Sparkle`, tagged "PetSparkle", off with
  Low Effects via `client/PetSparkle`).
- Pet index: `Config.PetIndex.FirstFindCoins` the first time a species is hatched (paid in `Profiles.grantSpecimen`
  with the discovery row, so never twice). Every released hunt species (35 at launch, 45 once the weekly pets are out;
  tower-only pets do not count, `PetFlair.species`) = title "Pet Master" (kept for good once earned: profile `PetMaster`)
  + badge `AllHuntPets` (id 0, REPLACE).
- Lobby name tag (`client/NameTag`): name, title, best pet tower floor (`TowerBest`), from server attributes (`server/PetIndex`).
- Sounds: `shared/SoundConfig` (EggCrunch, EggPop, HatchChoir) and `shared/PetSoundIds` + `shared/SoundCues` (moment map, docs/AUDIO.md). No roars (owner rule).
- Real meshes: `client/PetMotionBridge` (optional ReplicatedStorage.PetMotion: hatch on the nest and in the reveal),
  `client/PetDisplay` starts PetMotion on server-built mesh pets (tag "PetDisplay").
- Pure rules in `shared/PetFlair` (tests/test_pet_flair.luau); preview scene `petflair`.
## Robux shop (2026-10-11, owner)
EGG SHOP hut (prompt Panel "RobuxShop") or UPGRADES > Robux: Basic / Rare / Mythic eggs (1x, 3x, 10x; pets of the
buyer's best zone; full odds on the card; hidden when PolicyService restricts paid random items), Luck Potion (+1 luck,
15 min, saved as server time), passes 2x Coins / Pet Storage+ (+250) / Extra Plots (stub). Free events: 2x luck every
UTC weekend, random 15-minute luck storms per server. Luck sources add up, clamped at `RobuxConfig.MaxLuck` (x4 Rare+).
Bought eggs hatch at the public hatch stand (part attribute HatchStand, attachment HatchPoint) for everyone, queued.
Bought pets are not finds or wins and do not count for the RAREST PET board. All ids 0 (docs/OWNER_STEPS.md).
Bought pets sell for 10% of their value (`Profiles.priceValue`; marked by MatchKey `robux:<PurchaseId>:<n>` or
`Source = "Robux"`), so Robux never turns into coins for upgrades. The Pet Book shows that sell price.

## Pet tower drops (audit fixes 2026-10-11)
- Boss floors drop a tower-only pet with `TowerConfig.Drop` odds plus pity (`TowerConfig.Pity`): each boss clear
  without a drop adds PerMiss to the next boss chance (profile `TowerPity`), after GuaranteeAfter misses the next boss
  always drops, and a tower pet the player never had is picked first. Offline simulation (tests/test_pet_tower.luau):
  a steady climber owns all 5 by floor ~70 (median), 90% by floor 80.
- A drop is priced like a hunt pet of the player's best unlocked zone (`TowerRules.dropTier`), not as a Space pet.
- Pet Book full: no drop, the pity counter is kept, and a toast says why.

## Forest pets (names 2026-10-11, models made on the owner's PC; not in code yet)
Duskwing (owl), Oakmaw (bear), Thornhoof (deer), Vinetail (fox), Elderhorn (spirit stag, rarest Forest pet).

## Not done yet
Hard 3-minute round limit, daily gift + quests, basket upgrades, real meshes, pet hats/trails shop, Studio test.

## Hunt fun (2026-10-15, owner picks 1, 2 and 6)
Rules in `shared/HuntFun.luau` (tests/test_hunt_fun.luau; server case in tests/server/rocks.luau). Not Studio-tested.
- Surprise eggs: every ordinary egg a player finishes (hand or auto nest) also pays one prize: coins (1-2 x zone
  CashPerRubble, 55%), pet XP (3 per following pet, 39%), a Lucky Meter tick (5%; a full meter pays coins instead) or a
  jackpot (40 x CashPerRubble, 1%). Not in the practice round. MatchEvent "Surprise" to that player only; `client/SurprisePop`.
- Pet helper: replaces "followers are lobby only". In a hunt the strongest equipped pet that did not come from a Robux egg
  follows (PetsShown carries just it, marked Helper) and helps: crack speed +5..25% and +1..3 basket slots by POWER
  (`HuntFun.Helper.Steps`). Robux pets never help, so Robux never changes who finds the pet.
- Prizes for everyone: the finder is Gold (the pet is the prize); the others by eggs finished get Silver / Bronze / Star,
  coins and pet XP (`HuntFun.Prizes`), paid at the find. No egg finished, no prize. Shown on the results reward line.
