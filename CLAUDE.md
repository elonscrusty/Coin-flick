# CRACK THE ROCKS!: notes for Claude

**Now FIND THE PET! (2026-10-10, owner decision).** Same loop, new skin: eggs instead of rocks, hatch nests instead of
crushing tables, shells instead of rubble, one pet per round instead of the geode. Code names (rock, geode, rubble,
Specimen, Mineral = pet species) are kept on purpose; see `docs/FIND_THE_PET.md` for the mapping and the owner's picks.
Where this file or the brief says geode/rock, read pet/egg.

Roblox party geode hunt (Rojo + Luau), chunky low-poly industrial quarry style. 1-4 friends take rocks
from ONE shared pile to their own crushing tables (nothing is cracked at the pile); exactly one rock hides a
geode; whoever finishes crushing that rock wins it.
Full design brief: `docs/BRIEF.txt` (the owner's master prompt, it wins over everything else).
Reference pictures: `docs/refs/01..06_*.png`. They show the look, not real meshes.
The owner (kcdrewcarter, Roblox user 20194281) plays on a phone, isn't a programmer, and has no
Studio access during sessions, so nothing is verified in Studio unless they say so.

## How to work here
- Chat replies in caveman style (`/caveman full`); code, commits and docs in normal prose.
- Save straight to `main` and push (`git push origin main`). No PRs unless asked.
- Commit messages end with the attribution lines the session provides. Never put model names in code or commits.
- Save tokens: delegate routine work to cheaper subagents, keep prompts short, review only big batches.
- Rebuild and commit `build/CrackTheRocks.rbxlx` once at the end of a batch, then send it to the owner.

## Commands
- `bash tools/setup_tools.sh` installs rojo, luau-lsp, luau-compile, lune into /tmp/ctr-tools
  (a SessionStart hook in `.claude/settings.json` runs it automatically in cloud sessions).
- `bash tools/check.sh` type check (zero diagnostics), compile, rule tests, Rojo build; `--quick` skips the build.
- `bash tools/test.sh` offline rule tests only (tests/test_*.luau, run by tests/run.luau in Lune).
- Offline preview (screens/world without Studio): `bash tools/preview/setup.sh` once, then
  `bash tools/preview/render.sh hunt --device phone-1108` and `python3 tools/preview/check_layout.py <dir>`
  (docs/PREVIEW.md). Look at the PNGs; check every UI change on phone-1108, phone, phone-portrait.
- Build: `/tmp/ctr-tools/rojo/rojo build default.project.json -o build/CrackTheRocks.rbxlx`.

## Layout
- `src/shared`: Config (all tuning), Pile (deterministic mound + exposure + pickable/restore), RoundRocks (pure V3
  round rules: pickup, basket, tray, plate, machines, storage reservation; tested), GeodeGen (specimen rolls),
  GeodeModel (procedural geode/rock parts), Net (remotes). V3 loop: `docs/V3_LOOP.md` (source map, rules, protocol).
- `src/server`: Profiles (session-locked saves), AwardLedger (durable win records), PartyService,
  MatchService (arenas + hunt lifecycle), RockService (the one authority for RockAction: pickup, deposit, crush),
  StationModels (four crushing tables), EconomyService (shop, selling, settings, held tool),
  GalleryService (lobby alcoves), WorldBuilder (procedural lobby/arena kit).
- Teleport mode (Phase 2, off by default): `PlaceRole`, `MatchTicket`, `ArrivalGate` (shared, tested),
  `LobbyLaunch`, `MatchPlace`, `Tickets` (server), `ui/LaunchPanel` (client); `match.project.json`.
- `src/shared/Vendor`: third-party modules, unmodified. `spr` (spring motion for UI/parts, MIT,
  github.com/Fraktality/spr; license in `docs/third_party/`). Not wired into any UI yet.
- Egg gravity on the hunt pile: `shared/EggFall` (pure fall + bounce + hop arc; tested), sampled by PileView.
- `src/client`: PileView (pile render, targeting, contextual action), StationView (tray / plate / fracture / geode opening),
  CarryView (basket, pickup arc, tool stowing), GuideArrow, Anim, ToolAnim, MachineView, ui/* panels (docs/V3_LOOP.md section 5).
- UI juice and kit: `ui/UiJuice` (sweep, claim pulse, badge wiggle, tab slide, number count; wired in UI.luau),
  `ui/Juice` (coin flight via `Juice.coinSource` + `Juice.payout`), pure numbers in `shared/UiMotion`. Kit pictures
  (ids + 9-slice) in `shared/UiKit`, drawn by `UI.kitSkin` from the shared helpers; id 0 = drawn fallback;
  HudArt.skin (owner HUD pictures) wins. Preview scene `_juice` captures mid-animation frames.
- Hunt zone piece sets: `shared/HuntZoneKit` (naming contract, spots; tested) + `server/HuntLowPoly` swaps in
  ServerStorage.HuntZoneKit_<Zone> pieces role by role; a missing role keeps the tinted meadow piece.
- Pet Battle + training (find -> train -> fight, 2026-10-14): `shared/PvpConfig` (tuning), `shared/PvpRules` (fight,
  bot team, rewards, ranks, THE power number `petPower`; tested), `server/PvpService` (queue, bot after 15 s, fights in
  TowerBuilder arenas, trophies, tap/idle training on the tower XP book), `client/ui/PvpPanel` (BATTLE/TRAIN cards,
  fight HUD; 3D via TowerView). Tap to fight (2026-10-16): TAP = extra hit + combo, gold ring = BLOCK in time for
  PERFECT (PvpRules.tap / block, PvpConfig.Tap / Block, client `ui/TapFight`; balance in tests/test_pvp_tap.luau). Lobby pads: parts with attribute `PvpPad` / `TrainPad`. Preview: scene `battle`.
  Fight camera director: `client/FightCam` + `shared/FightCamRules` (intro sweep, wide orbit fitted to the screen, crit
  and SPECIAL cut-ins, K.O. orbit, hero shot; tested). It holds a `CameraMode.cinematic` key for the whole fight.
  Camera log: Workspace attribute `FightCamLog` = true prints `FCLOG {json}` lines on the client; logs saved in
  `tests/fixtures/fightcam/` are checked by tests/test_fight_cam_log.luau (preview: `battle --set log=1`). Every fight on its own floating island: `server/SkyIsland` clones ServerStorage `ArenaIsland`
  (part with `ArenaCenter` + `FightRadius` = fight floor) or builds a stand-in; `shared/IslandRules`. No spectating.
  `server/FightBoard`: lobby sign (live fight, biggest win) at a part marked `FightBoard`.
  Also hunt XP (RockService.onCracked), the Training Tower (the pet tower re-pitched as training; TOWER on the train
  card) and evolve (3 copies, `Evolve` stage on the pet: cap/stat/size bonus in TowerConfig.Evolve). No gym gear.
- Robux shop: `shared/RobuxConfig` (all tuning, ids 0 + REPLACE), `shared/LuckEvents` (luck stacking, weekend, odds),
  `server/RobuxService` (receipt route, passes, luck storms, hatch-stand queue), `client/ui/RobuxShopPanel`,
  `client/HatchStandView`. Owner steps: `docs/OWNER_STEPS.md` "Robux shop".
- Reasons to want eggs (2026-10-15): `shared/EggPerks` (tested): Lucky Meter (full = next shop egg Epic+, Legendary
  odds unchanged), Pet Book pages (full zone page = +10% shell coins and pet XP), free eggs (every 3rd battle win, all
  daily quests) banked in profile `EggPerks` and hatched by `RobuxService.openFreeEggs`. Egg-card UI: Fable thread.
- Hunt fun (owner picks 2026-10-15): `shared/HuntFun` (tested): surprise eggs (every ordinary egg pops coins, pet XP,
  a Lucky Meter tick or a rare jackpot; RockService, client `SurprisePop`), pet helper (strongest equipped non-Robux pet
  follows in the hunt: faster cracking + basket room by POWER; `Profiles.huntHelper`, PetService/PetFollow), prizes for
  everyone (medal + coins + pet XP by eggs finished, MatchService `payPrizes`, ResultsPanel line).
- First five minutes + comeback hooks: `shared/Retention` (starter odds, play gifts, away nest, friend/group gifts,
  levels), `shared/BotRules`, `server/RetentionService`, `server/PracticeBots`, `server/VoidStatue`,
  `client/StarterEggView`, `client/HatchShow` (demo egg v2 port), `client/RetentionView`. Streak shield: `shared/Quests`.

## Rules that must hold
- Robux (owner decision 2026-10-11, replaces the old cosmetics-only rule): the shop may sell pet eggs with boosts (Basic =
  race egg odds, Rare / Mythic = better tables, never worse than race odds; full odds shown before buying; respect PolicyService paid-random-item limits), 15-minute luck
  potions, game passes (2x coins, plot slots, pet slots) and a tower revive. Coins buy upgrades only. Robux never
  buys hints about which egg hides the pet, never changes who finds it, and product ids/prices come from the owner.
- Don't publish, deploy, buy assets, create products, invent or change prices, or make purchases.
- Don't enable Studio API access, HTTP or other security settings; give the owner steps.
- Don't wipe saves or reset rankings. Studio uses separate `_Studio` DataStores.
- Server decides everything (target, damage, claims, cash, items, winner). Clients send intents only.
- The target rock is never sent to clients before it is found; it looks identical to other rocks. One exception
  (owner pick 2026-10-11): after 3 minutes of searching the pet egg glows gold for everyone (EggConfig.Overtime).
- One geode, one winner per round; no reward for the leftover pile; no trading.
- Never present a mock or unconnected feature as working. Report verified vs assumed (PASS/FAIL/BLOCKED).
- Never invent asset ids. Procedural stand-ins have REPLACE markers where real meshes go.

## Where things stand
See `docs/STATUS.md` (phase plan, what is done, PASS/BLOCKED per area), `docs/REPAIR_PHASE1.md`
(V2 repair: causes and fixes) and `docs/OWNER_STEPS.md`. UI text uses `UI.text` / `UI.button`
(fitted text, tokens in `UI.T`); never size text with raw TextSize in fixed boxes.
