# SNAPSHOT: map of the code (read this instead of the whole repo)

Updated 2026-10-16 after the phase 0 picture-fix batch. Update it when your job ends.

## Shape
- `src/shared` (ReplicatedStorage.Shared): numbers + pure rules. **No Roblox objects**, so Lune tests cover them.
- `src/server` (ServerScriptService.Server): `init.server.luau` loads `Systems/*` in a fixed order (Net, Boosts, World, PlayerData, Tables, Shop, Mega, Hats, Robux, Leaderboards, Cheats), calls `init()` on all, then `start()` on all.
- `src/client` (StarterPlayerScripts.Client): `init.client.luau` loads `Controllers/*` in order (State, Sounds, CameraView, FlipFx, MegaFx, Helpers, CoinTap, Panels, Hud).
- `tests/run.luau` runs Lune against `src/` with a fake Roblox; specs in `tests/specs/*.spec.luau`.

## Shared (pure)
| Module | Owns |
|---|---|
| `Config` | ALL tuning: upgrades, table looks, rarities, helpers, hats, skins, sounds, sky, FLIP_HEIGHT, products (ids 0 = SOON) |
| `Types` | Profile (saved), Snapshot, FlipEvent, Notice, MegaState |
| `Remotes` | the one list of RemoteEvents |
| `Util/Economy` | money math: costs, cash per heads, rarity roll, combo, offline earnings, empty coin slots |
| `Util/ProfileSchema` | save defaults, migrations (now v2), cleaning bad values |
| `Util/TableLayout` | coin positions on the table, plot ring |
| `Util/CameraMath` | ZOOM camera spot that fits all coins on any screen; WALK camera numbers |
| `Util/FlipArc` | coin jump height, spins, shadow numbers |
| `Util/CoinLook` | coin colors/rims/sparkles per rarity, `lift` so spinning coins never sink in the table |
| `Util/HatSizes` | hat widths + `fit` (cowboy shrink) |
| `Util/HudLayout`, `HudText` | HUD rectangles for any screen size (0 overlaps), HUD wording |
| `Util/PanelView` | pure view data for shop/top/reset panels |
| `Util/Format`, `DeepCopy`, `SoundPick` | helpers |
| `Builders/HatBuilder` | hat models from parts (used by server hats and client icons) |

## Server
- `Util/GameLogic`: pure save changes (applyFlip, buyUpgrade, unlock/level/team helper, reset, applyOffline, hats, skins, grantProduct, megaReward, snapshot, shoutNotice).
- `Util/SessionStore` (locked saves, retries), `MemoryStore` (Studio throwaway), `KeyedMutex`, `RateLimiter`, `MegaCoin` (shared counter + Studio debugStep).
- `Systems/PlayerData`: load/autosave/leave/shutdown saves, leaderstats, pushes Snapshot ~5/s. Kicks on load failure so a blank profile never overwrites.
- `Systems/Tables`: each player's table, coins, empty "+" slots, helper guys, every flip (server rolls heads and rarity), rare shout, offline notice.
- `Systems/World`: lighting, cartoon sky (Config.Sky), ground, park (plaza, paths, trees, bushes, rocks, hills), spawn, plot slots. `Builders/Plot`: yard, fence, white arch + name sign.
- `Systems/Shop` (buy/level/team/reset), `Hats` (buy/wear, 3D hat on avatar), `Mega` (shared mega coin + 2x boost), `Boosts` (passes + mega boost), `Robux` (receipts, passes; ids 0), `Leaderboards` (3 top 10s), `Cheats` (Studio only).

## Client
- `State` (latest Snapshot), `ClientNet`, `Sounds` (id swaps to built-in fallback), `CameraView` (ZOOM/WALK), `FlipFx` (jump, spin, trail, shadow, rare look, pop numbers), `MegaFx`, `Helpers` (walk around table), `CoinTap` (taps become TapCoin).
- `Panels` (shop, top 10, reset popup, toasts, rare shout, mega banners) with `Ui/Kit`, `Ui/Icons` (3D viewport icons). `Hud` (top bar, strips, side buttons, combo, Studio cheats) with `UiStyle`.

## Remotes (client -> server unless noted)
TapCoin(index), BuyUpgrade(id), BuyHelper(id), LevelHelper(id), TeamHelper(id,on), ResetTable(), TapMega(), BuyHat(id), WearHat(id), ChooseSkin(id), BuyRobux(item). Server -> client: State(Snapshot), Flipped(FlipEvent), Notice(Notice), MegaState, MegaFlipped, Leaderboards. Studio only: Cheat(command: cash, fill, rare, mega, away, wipe).

## Save (Profile v2)
cash, hatPoints, upgrades{moreCoins,bigCoins,luck,speed}, crew{helperId: level}, team{ids}, resets, stats{flips,heads,skulls,biggestFlip,bestCombo,rares}, lastSeen, hats{}, hat, skin, helperSlots, receipts{}. DataStore `CoinFlick_Players_v1` (Studio: throwaway memory store).

## Key numbers
10 coins max, 8 plots, heads 50% +3%/Lucky level (max 80%), rares 1/20 3x, 1/100 10x, 1/1000 50x, 1/10000 500x, combo up to 3x, helpers half speed offline max 2 h, reset +50% cash.

## Added in the "whole game" build (phases 1, 3, 4, 5 + map)
- **Streak (1.3/1.4)**: `stats.bestStreak`/`streakWins`; `Tables` keeps a per-player streak of own taps; 10 heads = prize (`Config` streak goal). Client `Controllers/HudPopups` + `Util/StreakView` (chip, drama at 8+, win pop, welcome-back card).
- **Multi Flip upgrade** (`Config.Upgrades.multiFlip`), `Snapshot.flipsPerTap`.
- **Daily (3.1-3.5)**: `Util/Daily`, `Systems/Daily` (7-day gift, 3 jobs, no punishment), `Util/Friends` + `Systems/Friends` (friend in server = 2x cash), 8 h offline pile. Remotes `DailyState`, `ClaimGift`, `ClaimJob`. Profile `daily`.
- **Play gifts / badges / weekly / events (3.3, 3.6, 5.2, 5.3)**: `Util/PlayGifts`, `Util/Badges` (ids 0, never sent), `Util/WeeklyBoard`, `Util/WeekendEvents`, systems `PlayGifts`, `Badges`, `Events`. Remotes `PlayGiftState`, `ClaimPlayGift`, `BadgeState`, `EventState`; Leaderboards payload gets `weekFlips`. Profile `play`, `badges`, `week`.
- **Pets (4.1)**: `Util/PetRules`, `Systems/Pets`, `Config` PetConfig. Remotes `PetEquip`, `PetState`, `PetFlipped`. Profile `pets`, `petActive`, `petProgress`. Goal-won, never random.
- **Goals (4.2-4.4)**: `Util/Goals` + `Systems/Goals`: streak ladder skins (bronze/pearl/neon/crown), 3 weekly challenges + bonus, coin book. Remotes `GoalsState`, `ClaimChallenge`, `WearLadder`. Profile `ladderSkin`, `challenges`, `book`; `Snapshot.ladderSkin`.
- **Panels**: shop tabs GIFTS (`GiftPets`), PETS, GOALS (`GoalsPanel`, `Ui/PanelWidgets`), THIS WEEK top 10. HUD alert chip (gift ready, rain/luck, friend 2x), banners (`Util/EventText`).
- **Map (2.1/2.2)**: `Builders/PlotDecor`, `PlotThemes` (meadow, beach, candy, castle, space; theme per reset, own table look), `Util/YardLayout` (props only at back/sides, never in front half), `Util/DecorLayout`, edge tree wall, FREE PLOT markers. Docs: `docs/PLOT_THEMES.md`.
- Selene quirk: a local reassigned later from a no-arg default function fails `mismatched_arg_count`; use a table field (`hook.fn`).
