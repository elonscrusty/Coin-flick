# Status

FIND THE PET! (2026-10-10, offline only, NOT Studio-tested; docs/FIND_THE_PET.md): the geode hunt is reskinned and
extended into a pet hunt: egg pile (150), 3-egg basket, hatch nests, shells, procedural chunky pets (10 species, 5
variants), hatch reveal, one lobby-only follower with name tag, mixed Coins/Speed/Luck boosts, free starter pet, old
geode saves migrated, Pet Book (Pets / Book / Stats / Display), meadow arena, recoloured lodge, rare-hatch server shout,
RAREST PET board. PASS offline: check.sh (zero diagnostics, 162 tests, build), check_layout 0 problems on results,
collection, hunt, lobby, tutorial (phone, phone-portrait, phone-1108). BLOCKED: everything in Studio.

Prospector Lodge lobby in the game (2026-10-10, offline only, NOT Studio-tested; docs/lodge/INTEGRATION.md, renders
docs/lodge/renders/game/): the courtyard lobby is replaced by the uploaded Lodge kit (building, plaque, 30 furnishings)
placed by `src/server/LodgeBuilder.luau` at the documented positions (pipeline mapping verified with the door and benches
in the preview), invisible box colliders, CameraIgnore decor, Part stand-ins when a mesh is missing. Wired to the existing
systems: UPGRADES counter -> Shop + the UpgradePreview pedestal on the counter, COLLECTION counter -> Collection with three
labelled decorative example geodes, three hunt-bay prompts -> the existing Start Hunt panel (no queue / countdown), RUBBLE
SELL = the Hopper/Body/SellPrompt endpoint, SOLO FINDS and COMPETITIVE WINS kit boards with five live LeaderboardService rows
(avatar heads, medals; Studio saves-off message kept). 16 owner display pockets along the walls (real 3/6/12/20 capacities,
20 = 4x5 now). Spawn inside by the entrance facing the bays; yard, cliffs, pines and the waterfall outside the windows.
PASS offline: check.sh (zero diagnostics, 154 rule tests, build), 45/45 regressions, placement audit, check_lobby zones, signs audit. BLOCKED: everything in
Studio (lighting, collisions, prompts, SurfaceGui text, thumbnails, mesh scale); interior reads dimmer than the target in
the preview.

UI redesign v2 (2026-10-10, offline only, NOT Studio-tested; report docs/ui_v2/REPORT.md, renders docs/ui_v2/renders/):
the owner's two boards implemented in the real client: one theme (`ui/Theme.luau`) and shared components in `ui/UI.luau`
(charcoal panels, outlined capitals titles, gold / gray / red buttons with all states, tabs, rows, cards, counters,
empty / loading / error states, sliders, toggles, stacked confirmations, coalesced notifications); lobby + hunt HUD
(CARRIED / QUEUE / RUBBLE, timer, tool slots, processing from server state), Upgrades with real catalog states and
purchase confirmation, Collection / Display / Index / Materials / Records (honest unavailable state), Start Hunt, Party
(members, invite, invitation dialog, expiry), Results, Settings (+ CameraSensitivity setting, mouse only), loading, sell
card. check.sh clean, 154 rule tests, 44/44 regressions, check_layout 0 problems on 135 renders incl. Text size Largest.

Final acceptance pass (2026-10-09, offline only, NOT Studio-tested): MP4 + MP5 contradiction audit, the three RULES_AUDIT findings
fixed (crush catches machines up first, leaving catches machines up, `counters` Queue/OnPlate split), 98/98 rule tests, 25/25
regressions, 21 acceptance pictures and the owner Studio checklist in `docs/acceptance/ACCEPTANCE.md`.

Last batch: V3 core loop, step 2 (client and presentation, 2026-10-09, branch worktree-agent-a94befb50e96fe6b7): individual-rock
pile, basket on the avatar, tray / plate / fracture visuals, contextual HUD and controls, tutorial, geode opening on the plate,
see docs/V3_LOOP.md section 5. Offline checks only, NOT run in Studio.
Before it: V3 core loop step 1 (2026-10-09): server and shared rules plus the crushing-table world kit and the client protocol.
The owner's V3 revision supersedes every earlier "crack at the pile" rule below (Phase 1 text is kept for history).
Previous batch: Phase 1 repair from the owner's V2 brief, see docs/REPAIR_PHASE1.md.

## First five minutes + comeback hooks (2026-10-14, offline only, NOT Studio-tested)
- Starter egg: a free egg next to the lobby spawn (client/StarterEggView, MapNames.StarterEggSpot) with the route
  arrow and "FREE PET!"; tap hatches a Rare or Epic pet (never Common, never a chase pet: shared/Retention.Starter)
  with the big hatch show (client/HatchShow, port of the Studio demo egg v2). Replaces the free Common Raptor.
  New players skip the park fly-over so the egg comes first.
- First hunt (practice pile): 3 practice bots (server/PracticeBots, rules shared/BotRules) act out the loop at the
  free nests; scenery only, they never take or crack eggs and can never find the pet. Tips in the practice hunt
  are 3 words max ("Grab eggs!", "Go to nest!", "Drop eggs in!", "Tap to crack!").
- Play-time gifts at 1, 3, 5, 10 minutes a day (50/100/150/400 coins) with a FREE GIFT timer under PLAY
  (client/RetentionView); coin burst + confetti; hunter level-up pops (Retention.level from Stats).
- Void Dragon statue with "1 in 1000" in the lobby (server/VoidStatue, MapNames.VoidStatueSpot; procedural pet model,
  REPLACE with a Blender statue).
- Comeback: daily streak now grows past day 7 (+25% gift per week, up to 2x) with a streak shield every 7 days that
  saves one missed day (shared/Quests); away nest (30 min+ away: 1-3 eggs of coins, a Common pet after 8 h, +500
  welcome back after 3 days); friend gift (+50 per Roblox friend in the server, 3 a day); group gift (off until the
  owner sets Retention.Group.Id).
- PASS (offline): tests/test_retention.luau, tests/server/retention.luau, pets/profiles scenes; previews firstfive
  scene. BLOCKED (needs Studio): real bot characters (avatar service), hatch show on a phone, statue placement.
- Studio PASS (17d3750, coordinator re-proof): gift pop/confetti/coins, bots cycling pile<->nest, starter pet follows.
- Hook batch 3 (offline only): statue reads VoidStatueSpot attributes Height / Plinth (false = no code plinth), a
  purple beam up and a big floating "1 in 1000" sign; client/VoidStatueFx breathes the dragon (+-0.4 studs, 4 s),
  orbits sparkles and pulses the sign. Join tour for new players (client/LobbyFlyover: dragon, arena, shrine, starter
  egg, 5.5 s, tap to skip). Gold glowing starter egg that bobs and turns under a bouncing "FREE PET! ▼". NEXT GOAL
  card after the first pet (RetentionView.goalCard: power count-up vs the Void Dragon, a bar, HUNT queues a race,
  TRAIN / BATTLE open Pet Battle's cards (ui/PvpPanel); no TOWER, carter's loop is find -> train -> fight). Tour arena
  stop = Workspace.LobbyMeadow.BattleArena first. Portrait HUD: the menu stays under the objective (My Pets was
  covered) and TOWER / BATTLE stack. Fixed "+50 COINS COINS!". BLOCKED (needs Studio): the tour camera, the beam's look, the egg bob on a phone.

## Master Prompt 7/8 leftovers: UI polish and pickup line of sight (2026-10-10, offline only, NOT Studio-tested; pictures docs/m8/ui/)
- Collection tabs: Index lists every configured mineral; unfound ones are plain silhouettes titled "Not found yet" (no letters, no progress
  implied), a truthful line when nothing is found; Materials sized to its rows ("Materials discovered n/N", real counts); Stats now says
  Competitive wins vs Solo finds and adds Specimens owned and Materials discovered. `UI.tabBar` shares the bar between up to four tabs
  (Stats was off screen at Largest on portrait). Portrait Index uses two columns.
- Text: `UI.T.Tiny` 12 -> 14, `Small` 14 -> 15, fit floor 11 -> 12; touch rail tiles 62 x 60 px with 14 px captions (floor 11, shrinks only
  for very long words at Largest). Rendered lobby, hunt, party, shop, settings, collection tabs at Text size Largest on phone-1108,
  phone-portrait, pc: `check_layout.py` 0 problems. Results screen was rendered at Largest before the token change only (not re-rendered).
- Hunt HUD: already uses the same compact cards and rail as the lobby (the m7 acceptance picture predates it); no further structural change,
  carry/queue cards keep their bars. Honest note: no new hunt-HUD redesign was done beyond the shared rail and text sizes.
- Pickup line of sight: `shared/SightRules` (pure, 7 Lune tests) + `RockService` raycast from the head to just before the rock shell.
  Characters, CameraIgnore decor, non-collidable and see-through parts are skipped, so only solid geometry (e.g. the level drop) refuses with
  reason `NoSight` ("Something is in the way"). Only runs for a rock still in the pile and in range; the pick stays atomic in the core.
  Rocks are not server instances, so other pile rocks never block. Fails open on a cast error or after 12 skipped parts. The preview mock's
  raycasts hit nothing, so only the pure part is tested; the real raycast is NOT verified in Studio.

## Master Prompt 7, Pass B lobby world (2026-10-10, offline only, NOT Studio-tested; docs/m7/LOBBY.md, pictures docs/m7/lobby/)
- One palette / calm paving / one faceted foliage family / 5 soft lights. Three different silhouettes at the old spots: START HUNT
  waist-high terminal + sign gantry, UPGRADES tool counter + pegboard + one preview pedestal, COLLECTION open cabinet corner + lectern +
  one hero pedestal. New Blender pieces Lobby7_StartTerminal / ToolCounter / InfoLectern / SellChute / ShrubBed (uploaded, ids from the API).
- Display pockets: unclaimed = small plinth + "Open display"; claimed = cabinet sized to the real capacity (3/6/12/20), 16 pockets kept.
  Specimens via GeodeModel.onStand. Seller: compact bin at the west edge, same Hopper/Body/SellPrompt contract. Crates in one corner.
- Records: pale boards in a low frame; Studio saves-off / unreachable stores show one "Records unavailable in this Studio test" state
  (no retry loop, no rows invented, no writes). Production behaviour unchanged.
- Checks: check.sh clean, run_regressions all PASS, check_lobby CLEAR (new SellerFront zone), signs PASS. Open: Studio test, UI text
  "orange SELL hopper", live readiness screen, first-person prompt choice between destinations.

## Master Prompt 7, UI correction (2026-10-10, offline only, NOT Studio-tested; docs/m7/UI.md, pictures docs/m7/ui/)
- Input behind blocking menus now suspended in `CameraMode` (Controls, CameraInput when present, sunk move/look actions), close grace stamped
  synchronously, gamepad focus kept in the modal. Cause inferred from source, not reproduced offline.
- HUD declutter (resource block, icon rail, small lobby tool chip, brief first-hunt cue, Studio-only test chip, HUD hidden under modals),
  Shop item view, Collection empty/populated, Start Hunt per state, public name FIND THE GEODE!. 33/33 regressions, layout check 0 problems.
- Open: Studio verification of input and PlayerModule paths, Index/Materials polish, text-size Largest recheck.

## Master Prompt 6, first-person part (2026-10-09, offline only, NOT Studio-tested; docs/m6/FIRST_PERSON.md, pictures docs/m6/fp/)
- One camera / cursor owner `CameraMode` (LockFirstPerson in lobby and hunt, modal stack from `UI.block`, free cursor while any panel is open,
  restore on spawn / camera replacement / Init / Left / Results, local-only hiding of head, hats, torso, upper arms and the own basket),
  centre `Reticle`, camera-centre-ray resolver (`AimResolve`, `PileView`) feeding the unchanged `ActionRules`, lobby prompts limited to a cone,
  input grace after a menu closes, mouse click / E / R2 action, touch look-drag never picks up, gamepad ButtonB closes panels, `CarryGlimpse`
  (local basket lip + rocks, pickup cue after server accept), first-person controls tip in the onboarding. `CameraGuard` is third-person fallback only.
- Checks: type check clean, 117 rule tests (after merging main), `first-person:*` regression scenes. Open: real camera / mouse unlock / rigs / gamepad in Studio, tool
  poses in first person, server line of sight (not added), Basket-full reason picture. Material Discoveries, timer / pile counts, Collection
  Materials and sell flow are another helper's work and are not part of this entry.

## First-person table view, calmer framing (2026-10-10, offline only, NOT Studio-tested; pictures docs/m8/fp/before and after)
- Causes found: (1) the preview and the work-spot marker stood 3.2 studs from the table centre, so the 2.7-wide plate and the rock filled a third of the
  view; (2) the first-person hammer copy came in from the upper right with its long handle and grip across the top right (the "boom arm" in the old
  picture is that handle, not the arena crane; the thin black diagonal pole is a lamp mast and was left); (3) copy scale 0.85 was too large near the eye.
- Fixes: `StationModels` WORK_SPOT 4.2 (marker only, nothing enforces it; server ranges unchanged); `StationView` first-person tool copy scale 0.7,
  grip low and near on the player's right with the head striking the rock's upper front face, shorter wind-up (head stays in view), jackhammer leans in
  from the lower right. Plate rock size, plate height, FOV, routes, server rules unchanged; no new data to clients. Preview `fp` scene now uses the
  real work-spot distance (`--set dist=`, `--set t=idle`).
- Honest limits: the resting held tool still ghosts large at the lower right near the eye; the `t=idle` picture shows the plate before the rock arrives;
  pile pickup view was checked (fp aim) and left as is; the arena lamp mast still crosses the upper right; real avatar rigs and the real camera
  are not verified.

## Master Prompt 5 lobby, passes 1-3 (2026-10-09, offline only, NOT Studio-tested; pictures docs/m5/lobby/, before/ holds the old views)
- Sign typography (pass 1). Cause confirmed in source: every sign factory (`Kit.label`, `KitPlace.sign/titleBoard`, the alcove and
  RECORDS plates) used `TextScaled` inside a SurfaceGui at a fixed PixelsPerStud, with the text plate sized separately from the visible
  board. TextScaled never goes above 100 px and nothing tied the text to the board, so a text plate smaller than the kit's black sign
  face (or a big board) left small words on a large field. NOT confirmed against the owner's recording itself (only the source and the
  maths). Fix: `shared/SignLayout.luau` (pure) decides TextSize (explicit, <= 100), PixelsPerStud and the width fill from the board size
  and the text, with presets Landmark (55-75 %), Plaque, Nameplate (shrink, then truncate with "..."), Placard; `KitPlace.signBoard`
  builds a framed timber board and its text as ONE object. START HUNT, UPGRADES, COLLECTION, RECORDS, owner nameplates, the SELL RUBBLE
  plate and the screens use it. Still on the old `Kit.label`: only the parts-only fallbacks in KitParts/ArenaKit (not touched here).
- Numeric sign check (the preview cannot draw SurfaceGui text): `bash tools/preview/run_scene.sh signs` measures every sign's text with
  the mock's real Fredoka One metrics and prints board studs, canvas px, TextSize, cap height and fill per sign (27 signs, e.g. START HUNT
  8.8x2.0 studs, 80 px, cap 0.64 studs, 65 %), also a 36-character owner name (truncated, inside its board). Part of run_regressions.
  `tests/test_signs.luau` covers the maths. Assumption: Roblox's own Fredoka One widths match the metrics within the preset margins.
- Compact lobby (pass 2): courtyard 74 x 78 (was 100 x 94; the 16 cabinets at the edges need the perimeter). From the spawn: START HUNT
  open pavilion ahead (canvas gable, counter with the unchanged prompt, one title, one screen "SOLO OR PARTY / UP TO 4", one emblem),
  UPGRADES open-air counter left, COLLECTION counter and display bank right (hollow `GeodeModel.example` geodes, labelled DISPLAY
  EXAMPLES, never inventory), RECORDS wall behind (secondary), hopper beside Upgrades. Removed: workshop and gallery buildings, the
  stair-like shelf wall, per-tool stands (`Stands` is now `{}`; nothing else read it), arch, shelter. Zoned paving (route, forecourt with joints, edging, counter pads, perimeter
  band at separate heights), seating pockets, tree beds, low walls, warm lanterns (pale glass, a handful of lights). Nothing built with new Blender meshes: all
  Parts plus existing kit props (REPLACE markers kept in spirit); `blender/build.py` was not needed or run, no asset ids invented.
- Cabinets: `GalleryService` contract kept (Alcove Index / Root / Plate / Slots, SideL, SideR, ShelfLight, InspectPrompt, PlacePrompt,
  Panel "Collection"). 4 rows x 5 niches = 20 slots, filled centre-out; unowned niches keep a closed slate shutter, owned empty niches
  show a stand, specimens get a slim plaque on the shelf edge. Capacity 3/6/12/20 comes from `Profiles.displaySlots` (unchanged);
  scene `lobby --set display=N` shows a filled cabinet. Empty / partly filled / full pictures with DisplayCapacity 1..4 were NOT all taken (only display=4).
- Upgrades (pass 3): the counter prompt opens the existing Shop (Panel "Shop"). `client/UpgradePreview.luau` (started from Main.client) puts the
  equipped (or `UpgradePreview.select(id)`) item on the pedestal client-locally, from `Assets.Previews` and Config order only,
  normalised to a 3.2-stud height and 3.4-stud footprint, slow spin (off for ReducedMotion). ShopPanel was NOT touched, so the pedestal does not yet follow shop browsing; the
  helper recomposing ShopPanel can call `UpgradePreview.select(id)`. No 3/12/30-item test of the Shop panel here (not my scope).
- Checks: `check_lobby.py` zones (spawn aisle, aisle behind the pavilion, both counter approaches) CLEAR. Held back / open: records board
  text, screens and plaques are invisible in the preview (SurfaceGui), collision of the new counters and the camera behaviour near the
  canopies are unverified in Studio; the lobby ground is still large flat colour fields (textures not drawn offline); the far cliffs were pulled in but not re-composed.

## Milestones 4+5: machines, hopper sale, geode, tool animation (offline only, NOT Studio-tested; pictures docs/m4/machines/)
- Machines rebuilt in Blender (`blender/models/machines.py`, re-uploaded: new ids in MeshIds): warm timber + steel, Press 7.2 -> 4.95
  studs tall (timber header, fixed cylinder sleeve, rod and platen move together, 1.25 stroke), Crusher 5.7 -> 4.4 (low hopper),
  Auto Cracker keeps its size with a timber housing and a clear hood (GlassClear, 0.72). Piece names, attach points and
  attributes are unchanged, so `MachineModels` needed no edit. The Part stand-in press in `MachineModels` is still the old 7-stud one (fallback only).
- `MachineView`: every Start event (PileView.Claimed, Duration = Config seconds per rock) is ONE visible cycle of exactly that
  length: press platen down to contact at 50%, cracker jaws close at 50%, crusher rollers run while cycles arrive; idle, paused,
  full bag or round over settles open and silent. Cosmetic stones take their stages from the cycle and are throttled for very fast
  machines (crusher 12 rocks/s shows a stone every 0.2 s at most; a 0.083 s cycle cannot be shown as separate strokes: honest limit).
- One mechanism per station: confirmed in `RoundRocks` (running machine refuses hand hits "Automatic"; paused machine hands the plate to the
  hand tool). New test "v3 G: one mechanism per station ..." interleaves hits, pauses, swaps and ticks over 5 seeds with the conservation checks. No rule bug found.
- Sale (34): `sellRubble` is synchronous (read, clear, credit in one server step), so repeated taps sell once; selling while a machine
  runs only changes `Space`, refreshed every scheduler step; existing test "v3 J: a machine pauses on a full bag ... resumes after a sale".
- Geode (35): the plate geode and the results card use the hollow shell / pale rim / crystal cavity model. BUG FOUND AND FIXED: the
  client waited `fxRemaining + 1.8 s` before starting the hero reveal while the server's Results event came 2.8 s after Reveal, so
  Results closed the reveal mid-crack (the opening was never seen). `Main.client` now holds the results card until `RevealView`
  reaches its final frame (`RevealView.isPlaying`) plus 1.5 s (a tap closes sooner), bounded at 8 s. Pre-resolution the plate geode
  uses a fixed neutral placeholder spec (Quartz) until the Reveal brings the real one; nothing before Found differs between rocks.
- Collection (Master 5 section 5): `GeodeModel.build` takes `Tilt` (degrees the cavity leans up), new `GeodeModel.example(mineral, seed, opts)`
  makes DECORATIVE example geodes (tagged `Decorative`, no id, never in an inventory). Picture: collection-display-geodes.png (scene `_specimens --set display=1`).
- Tool animation (36): ToolAnim already restores joints and ends loops on stop; hammer contact and jackhammer loop pictures taken
  (stand-in avatar, not a real rig).
- Preview: scene view `M` in rocks-views (`--set machine= --set t= --set cam=side|front|wide|table --set flip=1 --set loads=0..`),
  view `H` takes `--set cam=front|close`.
- NOT fixed / open: from the normal behind-the-avatar camera the avatar's body still covers the plate and live rock (docs/m4/machines/hammer-plate-contact.png);
  fixing it needs an offset operating stance or a camera/transparency rule (stance and camera are outside this scope; Master 5 section 9).
  The press descent at 0.25 s per rock is very fast to the eye. Everything here is Mock-rendered: real mesh load, hood transparency and sounds are unverified in Studio.

## Blender kit models wired into the game (offline only, NOT Studio-tested)

Uses the uploaded kit meshes (`ReplicatedStorage.Assets.Kit`, built by MeshService) everywhere, each with its
Part stand-in kept as the fallback (`shared/KitModels.luau` returns nil when a template is missing):
- Stations (`StationModels`): Station_Table + AnvilPlate, InputTray, RubbleBin, Shield, Beacon, Sign, FloorPad;
  invisible helper parts keep the old contract (Surface = PrimaryPart, Plate, InputTray Slot1..10, OutputTray,
  DockPad, Stand, Feed, Nameplate, Sign, Light, Tarp). Accent pieces take the station colour.
- Rocks (`GeodeModel.rockShell`): Rock_01..12 with seeded tint and size; plate rock shows Hairline, then Wide, then
  Rock_Split chunks (neutral dark, no colour clue); rubble = Rock_Rubble, pile floor = Grit_Patch.
- Basket (`CarryView`): Basket_Empty with up to 5 mini rocks. Hand tools (`WorldBuilder.toolModel`): Tool_* meshes welded
  to the origin grip; `World.toolDims` keeps the head / bit reach of the Part tools.
- Machines (`MachineModels`, `MachineView`): Auto_Cracker (jaws slide), Hydraulic_Press (piston + platen drop 1.5),
  Industrial_Crusher (rollers spin about X), driven by the existing timings; paths come from the kit attachments.
- `MeshService.waitReady` makes arena builds wait (6 s, never errors) for the kit; Station_RubbleBin.Fill is absent from
  its FBX, so it is an optional piece.
- Preview: the mock now loads `art/meshes/*.fbx` through MeshIds + MeshCatalog, so previews SHOW the real meshes
  (rocks-views A/B/C/H, hunt wide, view G with `--set cam=machine`). Legacy CT_Rocks_* glb assets still fall back to Parts.
- Regressions 22/22, check.sh clean. UNVERIFIED until Studio: whether InsertService:LoadAsset returns these meshes with
  the piece names and axes the catalog expects, collision and look of the kit table, tool grips on real avatars.
- Not done: arenas are not rebuilt when assets arrive late (the 6 s wait covers normal loads); ArenaBuilder's own pad is
  still under the kit FloorPad.
## UI redesign and results accounting (sheet 13, brief V4 B and H; offline only, NOT Studio-tested)
- Results accounting (Task A): `src/shared/HuntLedger.luau` (pure, `tests/test_hunt_ledger.luau`) counts, per hunt and player,
  rocks processed, rubble earned and rubble sold (+ cash). `RockService.apply` records crushes, `Economy.setSaleListener` (set by
  `MatchService`) records hopper sales. `MatchService.finishRound` freezes the ledger and sends ONE snapshot per member in
  `Results.Members`: `Processed, RubbleEarned, RubbleSold, SoldCash, BagCount, BagCapacity, BagValue` and, for the winner,
  `SpecimenValue` (never cash). Bag figures come from the profile at that moment. A sale after the snapshot only sends
  `ResultsBag` (bag fields) so the screen is not stale; hunt counters stay frozen. Results never grant rubble or cash.
  The old `Cracked / Rubble / RubbleValue` fields (which mislabelled earnings as "Rubble you keep") are gone.
  Checks: owner's replay 9 + 64 - 24 - 30 = 19 bag, +$108 (`test_hunt_ledger`), and the real server path in scene `accounting`
  (two hopper sales mid-hunt, late sale after results) in `tools/run_regressions.sh`.
- Design system (Task B): `ui/UI.luau` rebuilt (docs: comments at the top of the file). Cream panels with honey frame, slate HUD
  cards and insets, amber only for the primary action, neutral slate for the rest, red only for destructive confirm; 1 px borders,
  radii 10 / 16, spacing 4/8/12/16/24, Fredoka (display) + Builder Sans (body), one redrawn icon family (`UI.icon`), `UI.card`,
  `UI.bar`, `UI.tile`; text picks ink or light automatically from the surface behind it. Rebuilt on it: HUD (wallet, Rubble Bag,
  Carry Basket cards, icon rail, compact objective + timer chip, calm "Rubble bag full" notice, bounded toasts, machine chip
  secondary, tutorial hint low in the lobby so it never covers the START HUNT kiosk), Start Hunt modal, Shop (3D previews via
  `ui/ItemView` + server `PreviewKit`; Kit model preferred when present), Collection (grid, detail, gallery slot chooser with
  server `DisplayAt`), Results, Settings (real sliders/switches). Inspect / Launch / confirm dialogs pick the style up automatically.
- Not verified: Studio, real touch bounds of the jump button (placement uses the same size rule as before), Kit-model previews
  (no Kit tool / machine names exist yet; `ItemView` looks for `Tool_<Id>` / `Machine_<Id>` marked Ready), `DisplayAt` on a real
  alcove, slider drag on a real touchscreen. Preview font mapping for Builder Sans is Inter (renderer substitute).
- Preview additions: scenes `accounting`, `_icons`, `hunt --set bag=full --set toast=1`, `collection --set place=1`.

## Lobby rebuild (V4 C and D, owner sheets 01-04), offline only, NOT checked in Studio
- New `src/server/LobbyBuilder.luau` + `KitParts.luau`; `WorldBuilder.buildLobby` delegates (same return fields). START HUNT kiosk
  12-20 studs ahead of the spawn behind a 12-stud entrance arch, workshop left, gallery right, 16 alcoves along the walls,
  records nook in the NE corner, hopper with chute beside the workshop, stone perimeter wall, cliffs and trees. Details and
  per-piece notes: docs/ASSET_MANIFEST.md "Lobby kit". Pictures: docs/lobby_preview/*.png.
- Also touched: `LobbyBoards.build` (reads BoardMounts, empty text), `GalleryService` visuals (ghost pedestal, "Place geode"
  prompt, two-line tags, smaller specimen scale), `Cosmetics` default alcove side colour, `default.project.json` lighting.
- PASS (offline): type check, build, 22/22 regressions. Preview scene `lobby` has `--set view=spawn|kiosk|workshop|gallery|boards|alcoves|alcoves2|hopper|overview|wide` and `--set hud=off`; it now places the player at the spawn.
- NOT verified: SurfaceGui text (renderer skips it; size math only), real lighting and bloom, walking the paths, prompt reach, Studio.
- Known issue outside this scope: in the spawn view the HUD banner ("Crack the Rocks! / Tap PARTY") and the tutorial hint sit over
  the kiosk sign on a phone; the HUD owner should move or hide them while the lobby is idle.
- The "Place geode" prompt on an empty owned alcove is visible to every visitor (a server prompt cannot hide per client); it only opens the visitor's own Collection panel.
## V4 arena rebuild (branch v4-arena, offline only, NOT Studio-tested)
- `src/server/ArenaBuilder.luau` builds the private arena; `WorldBuilder.buildArena` delegates to it and returns the
  same fields (Root, Center, Spawns, Bays, Tables, PileFolder, MachineFolder, plus Hopper). Kit pieces in
  `src/server/ArenaKit.luau` (docs/ASSET_MANIFEST.md "Arena kit").
- Layout: containment octagon (apothem 43, ~86 studs across); irregular mound pad; the four `StationModels` tables
  unchanged on the Config.Station circle with concrete pads; machine bays at radius 36 with amber clearance brackets;
  ONE shared sell hopper south between tables 1 and 2 (was four); entrance gate north; equipment shelter west;
  east drop with retaining wall + railing down to a lower bench with a crane and conveyor; layered cliffs (8 variants)
  replace the flat wall slabs; the yellow hazard ring and full bay outlines are gone.
- PASS (offline): tools/check.sh, tools/run_regressions.sh (22 checks), preview renders `hunt --set view=wide|corner|top|
  gate|hopper|nook|drop|station|low` on phone-1108 (screens in docs/screens/v4-arena/).
- Known gaps: station radius stays at Config.Station.Radius 25 (shared rule, not changed), so tables sit ~9-15 studs
  from the mound edge depending on tier, not the brief's 14-20. Bigger tiers' piles (radius up to 16) spill past the
  ~18-stud mound pad. Hopper route distance differs per station (tables 1-2 near, 3-4 walk around the mound).
  Lighting is not set by the arena (renderer default in previews). ~1,375 parts per arena, not profiled on a phone.
- BLOCKED: anything that needs Studio (real lighting/materials, collision feel at ledges, prompts, phone performance).
## V4 geode specimen, reveal and tool rigs (branch `v4-geode-tools`, offline only, NOT Studio-tested)

Scope: BRIEF_V4_UI_WORLD.txt section I (geode presentation, tool models and grips) and the geode part of C.
Screenshots (offline preview, phone-1108): `docs/shots/v4_geode_tools/` (reveal at 0.3/0.8/1.3/1.8/2.6 s,
results, collection detail, specimens at full/Lod/Tiny, tool strokes on R15 and R6 stand-ins).

- Specimen (`GeodeModel.build`): rough dark rind, thick pale chalcedony rim on the cut face with a thin
  agate band in the mineral's rim colour, cavity lined in a dark tone of the mineral, a dense druse
  (about 60 crystals at full detail, golden-angle spread, varied heights, formation-specific heroes)
  in the mineral's colour, and five glints. Cavity faces -Z; deterministic from the stored seed, the
  same model in reveal, results, collection and gallery (gallery Lod/Tiny take the largest crystals
  of the same list). Uses CT_Rocks_GeodeShell v2 and Crystal meshes when loaded, Parts otherwise.
  PASS offline (renders); gallery 30.4 parts per specimen (budget 40, was 21).
- Reveal (`src/client/RevealView.luau`, ResultsPanel only calls it): 0-0.4 isolate, 0.4-1.0 glowing
  fractures + small tremor, 1.0-1.7 front halves swing open beside the specimen (never in front of
  the cavity) while the cavity light comes up, 1.7-2.6 camera ease, glints, name/rarity. Tap after
  0.5 s jumps to the final frame, tap again closes; reduced motion shows the final frame at once.
  The server saves the reward before the Reveal event, so skipping cannot affect it.
  `Config.Match.RevealSeconds` 2.5 -> 2.8 so results do not cut the sequence. PASS offline (frames).
- Tools: `WorldBuilder.toolModel(id, scale)` with a new Part jackhammer (two grips, hose, chuck,
  silver chisel bit) and the v2 jackhammer mesh to match; `EconomyService.attachTool` fits tools to
  the avatar height (hammer ~0.45, jackhammer ~0.43 of it; R15, R6 and other rigs) and holds them
  in a neutral carry pose (hammer head up, jackhammer stowed bit-back). `ToolAnim` rewritten:
  shoulder poses written in torso space and converted per joint (R15, R6, named fallbacks, grip-only
  fallback), layered without accumulating, restored exactly on end/stop. Hammer: wind-up, contact on
  the work in front, recoil. Jackhammer: both hands on the grips, upright with the bit leaning at
  most 32 degrees toward the stone, height from a ray to the work (table Plate attachment fallback),
  0.05 stud local vibration, start/stop easing, ends when moving 3 studs away or unequipped.
  PASS offline on the R15 and R6 stand-ins (`_tools` scene). NOTE: nothing calls `ToolAnim.strike`
  on main yet (V3 removed pile striking; the client carry-loop work must call it on Crush pulses),
  so the `hunt --set swing=T` scene only shows the carry pose.
- BLOCKED (needs Studio): real avatars and animations under the layered shoulders, mesh pivots of
  the two new uploads, ViewportFrame look of Glass crystals, reveal timing on device.

## V3 core loop (pickup, carry, deposit, crush), step 1
- Shared rules: `src/shared/RoundRocks.luau` (pure, replaces `MatchCore`): rock records and states, basket (5), tray (10),
  one plate and one mechanism per station, storage reserved before any rock starts, one geode / one winner, leaver recovery.
  `Pile.luau` gained `isPickable`, `restore`, `stacks`. `Config.Carry` and `Config.Station` hold the tuning.
- Server: `src/server/RockService.luau` is the single authority (`RockAction` remote: Pickup, Deposit, Crush, ToggleMachine),
  used by `MatchService` for single-place arenas and the Teleport Match place. The old `Strike` remote is removed.
  `src/server/StationModels.luau` builds four crushing tables per arena (tray slots, plate, dock attachments).
- Client: only a temporary stub (`PileView` picks up the targeted rock, HUD text says PICK UP ROCK, tutorial hint wording).
- Tests: 60 offline rule tests (`tests/test_v3_loop.luau` covers acceptance A to K; `test_rules.luau` pile, reach, restore, geode rolls).
  Scenes `hunt`, `results`, `machine-fx`, `perf`, `save-faults` drive rounds through the V3 loop (`C.crackUntilFound`).
| Area (V3 step 1) | Result | How checked |
|---|---|---|
| Type check, compile, 60 rule tests, both Rojo builds | PASS | `tools/check.sh` |
| Pickup / deposit / crush / machine / storage / geode / leaver / rematch rules (A to K) | PASS (logic) | `tests/test_v3_loop.luau` |
| Server wiring end to end (real MatchService + RockService on the mock runtime) | PASS (mock) | `hunt`, `results` (solo and party), `machine-fx` scenes |
| Four tables rendered, evenly spaced, inactive ones tarped | PASS (offline picture only) | `hunt --set view=wide` render |
| Real multi-client races, disconnect in Studio, Teleport Match place | BLOCKED | needs Studio / live servers |
| Rock look, basket on the avatar, tray / plate visuals, contextual buttons, tutorial (acceptance L) | PASS (offline pictures) | step 2: `rocks-views` scene on phone-1108 and phone-portrait, `check_layout.py` 0 problems |
| `tools/run_regressions.sh` (22 checks), `tools/check.sh` incl. both Rojo builds, `check_layout.py` on phone-1108 (38 scenes), phone-portrait (27) and phone (13 rocks views): 0 problems | PASS offline | step 2 final run; not Studio |
| Avatar rigs (acceptance M): basket follow, scoop, swing at the plate on real R15 / R6 / other rigs | BLOCKED | needs Studio (preview avatar is a blocky R15 stand-in) |
| Party, shop, collection, gallery unchanged paths (acceptance N) | NOT RE-TESTED in Studio | untouched code, offline smoke only |

## Phase plan (from docs/BRIEF.txt section 16)
1. **Phase 1, this batch**: shared-pile party rules in private test arenas: hammer tools, cash,
   one geode / one winner, specimen generation, simple gallery, saving. DONE (offline only).
2. **Phase 2, built (offline only)**: separate Lobby and Match places, reserved servers, match tickets,
   teleport hand-off, partial-arrival and failed-teleport handling, reconnects. Off by default
   (`Config.Places.Mode = "SinglePlace"`); see "Phase 2" below. Live teleports BLOCKED (owner steps).
3. Phase 3: machines (Auto Cracker, Hydraulic Press, Industrial Crusher) with claim reservations,
   collision-safe animation.
4. Phase 4: detailed modular art (Blender meshes), full UI polish, gallery and collection extras,
   leaderboards (Wins, biggest geode, collection count, Solo Finds separate).
5. Phase 5: sound and VFX assets, performance measurements, save fault testing.

## What Phase 1 contains
- One server holds the lobby plus up to 6 private walled quarry arenas ("SinglePlace" mode,
  `Config.Places.Mode`). Only party members are moved into an arena; no paths lead there.
- Parties: invite-only, 1-4, leader picks tier and starts once all are ready; blockers shown
  (locked tier, full collection, loading). SOLO HUNT starts right away.
- First solo hunt is a 12-rock practice pile; the geode is in one of the first six rocks cracked.
  Not counted as a win.
- (SUPERSEDED by V3) Hunt: 3 s frozen countdown with a rock drop, then everyone cracks the same pile. Pile size by
  tier (80 to 1600 rocks), fixed for the round, not scaled by party size. Rocks are only hittable
  when exposed (top of a stack or side open), within 14 studs. Rocks above a cracked one settle.
- Server queue orders strikes by when each tool was ready, then arrival order. Finishing hit owns
  the rock: 1 rubble per ordinary rock, the target rock gives the geode and ends the round at once.
  Leftover pile pays nothing.
- Storage cap blocks strikes before any damage, identically for every rock (no target hint).
- Specimen: rarity 60/25/10/4/1, formation, modifier, mass bands, value formula from the brief;
  rolled once, written to a durable ledger, granted to the winner's save idempotently, saved
  before the reveal is shown. If the winner left, it is applied on their next join.
- Reveal (2.5 s, skippable after 0.5 s, reduced-motion version) and results (winner, specimen,
  everyone's cracked count and rubble), REMATCH / START REMATCH / LOBBY. Spawn spots rotate.
- Shop: Starter Hammer (free), Steel Hammer $150, Jackhammer $1800, storage 30-3000, tier unlocks
  (cash + finds), gallery slots 3-20. Machines are listed as "later update", not sold.
- Collection: search, sort, favourites, viewport thumbnails, detail with drag-to-turn, favourite,
  show in gallery, sell with exact confirmation; sell mode with "Select commons" (skips favourites,
  displayed, Epic, Legendary). Discovery index and stats.
- Gallery: 16 lobby alcoves, one per player for the session, specimens rebuilt from the save.
- Settings: music/SFX volume (wired to the audio buses in Phase 5), reduced motion, low effects, hints.
- Saves: session lock in the same key, UpdateAsync, retries, autosave 90 s, release on leave,
  BindToClose. Never writes defaults over unreadable data (kicks with a message instead).
  Studio without API access runs a session-only profile and shows SAVES OFF.

## Phase 2: Lobby and Match places (Teleport mode)
Default stays `SinglePlace` (unchanged behaviour, Studio-testable). `Mode = "Teleport"` plus both place
ids in `Config.Places` switches on the split; `PlaceRole.resolve` falls back to single-place when ids are
0 or the place is neither (Studio). Two Rojo projects: `default.project.json` (lobby / single place) and
`match.project.json` (Match place); same code, the server picks its role from `game.PlaceId`.
- Lobby (`LobbyLaunch`): START creates a ticket (`MatchTicket`, stored in MemoryStore by the reserved
  server's PrivateServerId via `Tickets`), `ReserveServer`, saves + releases every profile
  (`Profiles.releaseForTeleport`, bounded retries, a failed release stops the launch), then
  `TeleportAsync` with `ReservedServerAccessCode`. Teleport data is a hint only. Failure paths
  (`TeleportInitFailed`, a throw, a watchdog for members still here): the profile lock is taken back
  (`Profiles.reacquire`, refused if another server wrote the save), the party and ticket stay, the
  loading card offers RETRY (once per member) and CANCEL. Members who left keep their party seat for
  15 min (the party stays locked until they are back).
- Match (`MatchPlace`): every arrival is checked against the ticket before its save is touched (join
  gate in `Profiles`); strangers, expired, consumed and duplicate entries are sent back. Arrivals wait
  on the arena pads (one arena at the origin), up to 30 s (`ArrivalGate`); everyone here -> normal
  `MatchService` rounds; members missing -> leader picks START WITH ARRIVED or RETURN ALL. Late
  arrivals after the start are turned away; roster members may reconnect (3 times) and watch until the
  next round (no new target, no extra reward). Leader leaves -> earliest member. Empty server ->
  ticket consumed. LOBBY returns one player, ALL TO LOBBY (leader, results screen) the whole party, both
  via `TeleportAsync` to the lobby, pinned to the lobby server the party left (retry without the pin).
- UI: `LaunchPanel` (party rows with arrival checkmarks, 30 s countdown, timeout buttons).
- Tests: `tests/test_ticket.luau` (11) covers unknown user, expired, consumed, duplicate, reconnect once,
  partial arrival and timeout rules, leader leaving, place role.

## PASS / FAIL / BLOCKED
| Area | Result | How checked |
|---|---|---|
| Type check (luau-lsp, Roblox types) | PASS | `tools/check.sh`, zero diagnostics |
| Compile (luau-compile -O0) | PASS | `tools/check.sh` |
| Rojo build | PASS | `tools/check.sh` |
| Pile layout, reachability, exposure | PASS | 5 tests in `tests/test_rules.luau`, all tiers |
| Round rules (one winner, cadence, queue cap, race order, storage, range, tutorial) | PASS | 10 tests |
| Geode roll weights and value formula | PASS | 2 tests (50k rolls) |
| Config sanity | PASS | 3 tests |
| Ticket validation, arrival/timeout state machine, place role (tests/test_ticket.luau) | PASS | 11 offline tests |
| Both Rojo projects build (lobby/single + match) | PASS | `tools/check.sh` |
| Teleport lobby -> Match -> lobby (reserved server, TeleportAsync, TeleportInitFailed) | BLOCKED | teleports do not run in Studio; needs two published places and a live test (docs/OWNER_STEPS.md) |
| MemoryStore tickets, profile release/re-acquire across places | BLOCKED | needs live servers with API access |
| Loading / waiting card layout (LaunchPanel) | BLOCKED | not rendered in the offline preview yet; needs a phone check |
| Playing it in Studio (movement, UI on phone, tool look, arenas) | BLOCKED | needs the owner in Studio |
| Saving with real DataStores | BLOCKED | needs Studio API access (owner choice) |
| 2-4 player party flow | BLOCKED | needs a Studio multi-client test |
| Performance (Meteor 1600 rocks, 16-player lobby) | Mock numbers PASS (docs/PERF.md); device FPS BLOCKED | `perf` scene; needs device measurement |
| UI layout, 7 screens x 6 devices (offline preview) | PASS | tools/preview + check_layout.py, 0 problems |
| Final layout sweep: 45 scene variants (launch, inspect, tutorial, machines, confirm-sell, party) on phone-1108, portrait, phone, small, iphone, tablet, pc (tools/preview/sweep.list) | PASS offline | check_layout 0 problems after fixes; sweep ran before the V3 loop rebuild, hunt/HUD action states need a re-run; Studio BLOCKED |
| Hammer visible and swinging onto the rock (offline preview) | PASS | hunt scene near/swing renders; Studio still needed |

## Review fixes (same day, code review of the whole batch)
Per-load save session id (safe same-server rejoin), BindToClose waits for every save, light
profile updates (inventory only sent when it changes), strike tolerance 0.3 s with at most 2
queued, results screen can't be tapped away + HUD RESULTS button, idle results return everyone to
the lobby after 120 s, party panel scrolls on short phones, pending-award background retry,
timer survives a re-sync, objective box fits portrait phones, invite cooldown (10 s per player).

## Known limits (honest list)
- Line of sight is approximated by the exposure rule (you can only hit rocks with an open face)
  plus range; there is no ray test against other rocks.
- Tool swings move the tool joint only (no humanoid animation assets exist yet).
- Sound and effects (Phase 5) are synthesised and uploaded but never heard in Studio; see the section below.
- Rocks, geodes, tools and buildings are plain Roblox parts. REPLACE markers in
  `src/shared/GeodeModel.luau` show where uploaded meshes go.
- Single-place mode: a party that finishes keeps its arena until everyone taps LOBBY.
- Rubble is saved by autosave (90 s) and on leave; a server crash can lose up to that much rubble.

## Phase 5: audio + VFX (offline only, NOT heard or seen in Studio)
- 25 original sounds synthesised (`tools/synth_sfx.py` -> `art/sfx/*.ogg`), all uploaded with
  `tools/upload_audio.py`; ids in `art/sfx/uploaded_ids.json` and `src/shared/SoundIds.luau` (0 = silent).
  Roblox moderation of audio can still reject a file after upload: check in Studio.
- `src/client/Audio.luau`: SFX / Ambience / Music buses on the Sfx / Music settings, one ambience per area,
  distance roll-off, live-sound caps, cooldowns, machine loops. Hooks: strike, rock removal, other players'
  hits, sale, "ok" toasts, buttons, countdown, reveal chime + rarity accent, versus win.
- `src/client/Effects.luau`: cash fly-up, reveal shimmer, 2 s winner confetti, machine glint (hook only,
  nothing calls it yet). Respect Reduced motion / Low effects.
- Machines: `MachineView` now calls `Audio.machineActive` (conveyor hum, crusher loop), `Audio.play`
  (press descend / impact / retract, per owner key) and `Effects.glint` (at the machine's recovery chute when
  a machine-cracked rock is the geode). Caps, cooldowns, Sfx volume and Reduced motion are handled by Audio /
  Effects. Checked offline by `machine-fx` (sounds created, loop cap, wind-down, glint, reduced motion);
  NOT heard or seen in Studio.
- Check: type check, compile, 21 rule tests, build PASS. Loudness, mix and feel: BLOCKED (needs ears in Studio).
## Phase 4 gameplay-facing batch (offline only, NOT Studio-tested)
- Leaderboards: `src/server/LeaderboardService.luau` (OrderedDataStores `CTR_LB_<Board>`, `_Studio` suffix in
  Studio; boards Wins, Biggest Geode value, Collection Count, Solo Finds kept separate; throttled, budget-checked,
  pcall'd, never lowered or reset; names via display name / GetNameFromUserIdAsync cached) and
  `src/server/LobbyBoards.luau` (4 SurfaceGui stands south of the collection hall with loading / empty / error /
  offline states). Rules in `src/shared/Boards.luau` (tested). Collection Count counts every geode ever collected.
- Collection: Discovery index silhouettes per mineral x rarity (profile `DiscoveryRarity`; old saves are rebuilt
  from geodes still owned), read-only inspect card for displayed specimens (`GalleryService` prompts, `Inspect`
  remote, `ui/InspectPanel.luau`; server re-checks owner and display).
- Cosmetic store: `Config.Products` / `Cosmetics.luau` (2 tool skins, 2 gallery themes, all ProductId 0 = hidden,
  no prices), `StoreService.luau` (idempotent ProcessReceipt keyed by PurchaseId stored in the profile, answered
  granted only after a save). Store tab hidden unless an id is real and the tutorial is done.
- UI pass: shop cards fit short phones; layout check 0 problems over 35 scenes; `boards` preview scene (board
  faces are drawn on a ScreenGui because the preview skips SurfaceGuis); `shop --set store=on` uses fake ids.
- Not verified: DataStore boards live, real purchases, prompts in Studio, 3D placement of the boards.
## Phase 3: machines (offline only, NOT Studio-tested)
Auto Cracker (10k, 2 rocks/s), Hydraulic Press (45k, 8 per 2 s), Industrial Crusher (180k, 12 per s);
`Config.MachinesEnabled = true`, `Config.MachineRules` (claim 3 s max, claims never above half the rocks left).
- Rules (`MatchCore`, pure): `tickMachines`, `setMachine` (a swap waits for the batch in flight, cadence kept),
  `setMachineRunning`, `machineState` (Running / Paused / Full). A batch reserves only exposed, unreserved rocks nearest
  the owner's bay, never the target by choice. Reserved rocks reject hand hits ("Reserved", owner included). In-flight
  claims count against storage for every rock alike. Completion finishes the rocks in order through `finishRock` (same
  code as hand hits); target -> Found, owner wins, all other jobs stop and pay nothing. Pause, leave, late tick (>3 s),
  full bag or round end release claims unpaid. One scheduler step for all machines; no per-rock loops. Practice piles never run machines.
- Server: `MatchService` gives each member the bay matching their spawn index, builds models (`MachineModels`), replicates
  claims as rock ids only (`Rocks.Res`, `Machines` event, `Init.Reserved`). `EconomyService`: BuyMachine (installs on buy),
  InstallMachine, ToggleMachine (also the bay panel prompt, owner only). Profile `InstalledMachine` validated against owned.
- Client: `MachineView` (belts, rollers, jaws, press cycle per brief section 10, feed stones, state light, beacon, dust),
  reserved-rock pulsing outline in `PileView` (SelectionBox), HUD machine cell (Running / Paused / Storage Full, tap to
  start-stop), shop Machines tab (owned / installed / buy, rocks per second vs the equipped hand tool), press/crusher icons.
| Area | Result | How checked |
|---|---|---|
| Type check, compile, 34 rule tests (13 new in tests/test_machines.luau: limits, expiry, race, overflow, no pay, one winner, cadence) | PASS | `tools/check.sh` |
| Machines run in the offline preview (3 machines, HUD state, rubble grows, rocks removed) | PASS | `hunt --set machine=... --set view=bay` |
| Studio feel, animation smoothness, real phone layout, multi-client claims, sound | BLOCKED | needs Studio |
Known limits: exposure is checked at claim time only; the Auto Cracker/Crusher outlet leads to a bin, rubble still goes straight to storage; machine paint skins and sounds not built.

## Phase 5 remainder: performance, save faults, regression runner (offline only, NOT Studio-tested)
- Performance: scene `perf` + `docs/PERF.md` (mock measurements, not device FPS). Fixed: cached
  `PileView.autoTarget` (HUD refresh 2.8 -> about 1 mock ms), idle machine animation skipped, tiny gallery
  specimens beyond slot 8 (16-player lobby 10.7k -> 7.6k parts). Device FPS / memory: BLOCKED.
- Save faults: scene `save-faults` (cases load, save, pending, award, release; mock `failDataStores`). All
  PASS after fixes: a save after `Released` can no longer re-take the lock (`saveRecord` returns false and the
  transaction skips), `releaseForTeleport` waits (bounded by `Config.Match.RewardSaveTimeout`) for award holds,
  `AwardLedger.apply` queues a pending key when the save fails, `AwardLedger.record` keeps retrying in the
  background during an outage. Not covered: real DataStore throttling and budget limits, DEV paths (none in
  this project), Studio API access.
- Review fixes from the coordinator: leaver removed from the match core in Countdown and Searching (machine stops
  claiming); Store receipts and actions refused for released profiles; ClientReady limited to once per 5 s;
  leaderboard `reading` flag always reset, Match place skips board reads, cleanup by `GetPlayerByUserId`; party
  lock only when the party is still registered (no dead Party panel in the Match place).
- Runner: `bash tools/run_regressions.sh [--quick] [--only text]` (22 checks: type check + rules, save-faults x5,
  machine-fx x4, perf, smoke scenes). All 22 PASS offline.

## Lobby, gallery and quarry built from the kit models (offline only, NOT Studio-tested)

Branch `worktree-agent-a8ab983528a54f474`. Renders in `docs/kit_world/` (preview mock loads `art/meshes/*.fbx`;
SurfaceGui text is not drawn offline, so sign text was checked by size only).
- `src/server/KitPlace.luau` (new): place kit models, invisible blockers (MeshService strips collision), fitted
  SurfaceGui sign plates, the shared prop-kit sell hopper (keeps model attr `Hopper`, part `Body`, prompt `SellPrompt`
  with attr `Sell`). Every builder falls back to its old Part version when a kit model is missing.
- Lobby (`LobbyBuilder`): Terminal_Kiosk (START HUNT / SOLO / PARTY panels, ready lights, step tiles, floor beacon,
  bollards; prompt `Cabinet` with Panel=Party), entrance arch + fences + path arrow, Lobby_Workshop (tool stands,
  price cards, locked machines kept; Prompt Panel=Shop), Lobby_Gallery (collection desk Panel=Collection, quarry
  samples plaques), sell hopper from the prop kit, storage shed, shelter, walkway tiles and dark station pads,
  planters, trees, benches, lamps, perimeter wall, cliff modules A-F + corner in two rows, crane + bucket, kit wall
  lamps and planters at the records nook.
- Not done: Lobby_LeaderboardAlcove is not used (the four boards are portrait; LobbyBoards mounts stay in the
  Part nook). Kiosk SOLO/PARTY panels are labels only, the prompt opens the Party panel.
- Alcoves: 20-slot grid, `Floor`/`SideL`/`SideR`/`ShelfLight`/`Nameplate` kept; kit owner nameplate and wall lamps;
  first 8 specimens stand on `Gallery_SpecimenStand`; empty slot shows `Gallery_PedestalEmpty` (prompt kept).
- Specimens (`GeodeModel.build`): Geode_Shell + Geode_Rim + 1-3 clusters painted per mineral, seeded from the stored
  seed; old Part build still used when the kit is absent.
- Arena (`ArenaKit` wrappers + `ArenaBuilder`): cliffs A-F, retaining walls, fence sections, quarry gate, storage
  nook (generator, compressor, hose reel, work light beside it), crane + bucket, prop-kit hopper with wheelbarrow,
  bucket, placard and wall lamps, work light + parts tray per station. Stations, pile, spawns untouched.
- Preview additions: lobby `--set display=N` and views `alc1`, `alc1close`; `_specimens --set cam=front`.
- check.sh PASS, run_regressions 22/22 PASS offline. Unverified: collision of the blockers, real mesh pivots, text
  fit, light levels, performance on device.

## Master Prompt 4 / quarry (private arena, pile, tables)

Offline only (Lune preview renderer, phone-1108 pictures in `docs/m4/quarry/`), NOT Studio-tested. Notes and causes:
`docs/m4/QUARRY.md`.

- PASS (offline): one central mound, four tables on the existing radius-25 circle each on one plain concrete slab
  with the machine slot straight behind it; two identical sell hoppers (south for tables 1-2, north for 3-4) so every
  table has the same short sale walk; inactive tables calm (no tarp, no red text, no dark slab); restrained owner
  accents (no neon cyan/green/violet, hazard-striped kit floor pad no longer used); flat pale fragments around the mound
  removed (cause: `Grit_Patch` kit sheets placed by the client grit scatter, plus 14 flat rim slabs in `ArenaBuilder`);
  tall shard rocks widened; cliff moss toned down; `CameraIgnore` set on decorative parts.
- PASS: rule check (21): no bug found; new randomized conservation test in `tests/test_v3_loop.luau`
  (66 tests, type check zero diagnostics, Rojo build ok).
- BLOCKED / client side: the big ROCK PILE sign is a client `GuideArrow` (`PileView.luau:449`); the client has to
  replace it and honour `CameraIgnore`. Studio: slab step collision, hopper prompt range, real camera clipping,
  moving machine parts were only seen as static frames.
### Quarry pass 2 (offline only, NOT Studio-tested; pictures `docs/m4/quarry2/`, details `docs/m4/QUARRY.md` "Pass 2")

- PASS (offline): pile = rounded mound of chunky faceted grey boulders (12 rock meshes rebuilt, none taller than ~1.1 x
  wide, drawn 13% larger) plus small loose stones at the base (`GeodeModel.grit`); Pile.luau untouched (layout, ids,
  reachability tests pass). Table = low solid wooden unit with dark steel posts and straps, two wooden bins, crush plate
  with yellow/black hazard border, clear shield, basket crate at the player's right end, owner colour tag; top is now 2.5
  (was 3.0), contract (Surface/Plate/InputTray/Slot1..10/OutputTray/DockPad/Stand/Feed, attributes) unchanged; the four
  legs became one solid `TableBody` helper, `Surface` is no longer solid. Pads snug (11.6 x 8.8, bay slab 9.6 x 8.9
  joined to it). Cliffs = 3-tier stepped grey blocks (fewer, chunkier), timber fence rim, wooden sell hoppers with a
  SELL RUBBLE board (same Hopper/Body/SellPrompt contract), small wooden gantry on the east bench (steel tower crane and
  conveyor removed), crate stacks beside the shelter, orange-brown floor. Meshes uploaded (ids from the API):
  Rock_01..12, Rock_Split, Rock_Rubble, Station_Table/AnvilPlate/InputTray/RubbleBin/Shield.
- check.sh zero diagnostics, 73 tests, run_regressions 23/23 (offline).
- NOT done / open: machines are the unchanged kit meshes (they fit the table footprint behind the table; the Hydraulic
  Press stays about 7 studs tall); moving parts only seen as static frames; Station_Beacon/Sign meshes not rebuilt; the
  boundary cliffs are Parts (no Blender cliff rebuild, old Cliff_A..F meshes are no longer used by the arena);
  collision, camera clipping and performance in Studio unverified.

## Master Prompt 4 / lobby (offline only, NOT Studio-tested)

Details, causes and pictures: `docs/m4/LOBBY.md`, `docs/m4/lobby/*.png` (phone-1108). Owner: shared lobby only.
- PASS (offline): open paved route spawn to the Start Hunt kiosk (18 studs, aisle 12 wide); workshop left with only two
  front posts (Blender `Lobby_Workshop` re-uploaded) and equipment on the real floor; gallery right; records moved
  behind the kiosk (north wall) as four compact boards with ONE fitted-text title (the old pixel-block lettering plus lamps
  over it was the broken look); 16 compact stepped alcoves (20 slots each, real specimens only) instead of 13-high
  shelf walls; calmer paving, foliage and lamps; display prompts 9 apart with range 5-6 (`OnePerButton`);
  `CameraIgnore=true` on roofs, canopies, foliage and lamps; clear-zone audit `tools/preview/check_lobby.py` all CLEAR.
- BLOCKED / not verified: any Studio play (camera against roofs, prompt display, SurfaceGui text which the preview
  does not draw: WORKSHOP, GALLERY, RECORDS titles and board rows); the client helper must honour `CameraIgnore`.
- Open: parts-only fallback buildings still use the old layout; the gallery house is closed (door), owned slots are the alcoves.
- Lobby pass 2 (offline only, NOT Studio-tested, pictures `docs/m4/lobby2/`): Blender `Terminal_Kiosk` rebuilt as a modest
  timber canopy (stone plinth, four posts, gabled plank roof, hanging title board, stone pickaxe emblem, wooden counter, stone
  planters, two lanterns; re-uploaded, new id in `MeshIds`); tall dark kiosk, ready-light head and bollards no longer placed.
  Kit steel/navy pieces repainted warm brown at runtime (`TIMBER_TONE`), warmer paving, sandstone cliff tones, cliff rows low
  and sparse, crane pushed far back and smaller, one standing-lamp pair only, timber WORKSHOP/GALLERY title boards, glass
  display fronts on all 16 alcoves (rails + clear pane, no collision/query), tool rack with hung tools inside the workshop.
  `check_lobby.py` CLEAR on all four zones; check.sh and 23/23 regressions pass.
- NOT done / honest gaps: workshop and gallery buildings are unchanged Blender meshes (only recoloured), not rebuilt; locked machine
  previews, hopper and records boards stay dark; no glass cases added in the gallery house (alcoves are the cases) and alcove rows
  are not rarity tiers (specimens fill in collection order); tool rack and SurfaceGui texts not seen in preview.
  The `SELL HERE` marker is a client billboard: `src/client/Main.client.luau:283` (`setMarker(nearestHopper(), "SELL HERE")`), not edited.

## Master Prompt 4 / M1 interaction (client; offline only, NOT Studio-tested)

Notes with causes and fixes: `docs/m4/INTERACTION.md`. Pictures: `docs/m4/interaction/` (phone-1108, phone, phone-portrait).
Checks: `tools/check.sh` zero diagnostics, 73 rule tests, `tools/run_regressions.sh` 23/23, `check_layout.py` 0 problems
(new JUMP rule) on the evidence set.

| Area | Result |
|---|---|
| Action button clear of jump (TouchLayout, above or left of the reserved area) | PASS offline against the MODELLED jump button; BLOCKED: real jump rectangle must be measured in Studio / on the owner's phone |
| One world prompt at a time (PromptArbiter, custom pill) | PASS offline (workshop picture); BLOCKED: Roblox Custom-style keyboard / gamepad activation and tap trigger need Studio |
| Camera occlusion (CameraGuard, CameraIgnore attribute / tag) | BLOCKED: logic unit-tested (CameraSolve) but the preview has no raycasts or default camera; needs a Studio camera tour |
| Giant ROCK PILE sign / floor arrows replaced by a small contextual hint | PASS offline (client GuideArrow; no server sign existed) |
| Action state machine, hold cancellation, target priority (ActionRules) | PASS offline (tests + pictures); contested multi-client pickup not run |
| HUD hierarchy: queue/chips only at the table, left-column summary, real rubble capacity | PASS offline |
| Pickup -> basket 5 -> deposit -> processing -> rubble | PASS offline (rocks-views A to D, v3 loop tests); NOT Studio |

## Master 4/5 milestone 3: UI system pass (offline only, NOT Studio-tested)
Start Hunt, party slots, Shop (catalog list + selected pane, scales to 30+ entries, truthful copy), Collection, Results
(collection line only when the specimen is really in the inventory), Settings and inline truthful states; HUD arena
toasts scoped to the hunt. Details, pictures and limits: `docs/m4/UI.md`, `docs/m4/ui/`.
- PASS (offline): tools/check.sh, tools/run_regressions.sh (25/25 incl. new `hud-scope`), check_layout 0 problems.
- BLOCKED: Studio, real touch/controller input, real device scale, a real deposit clearing the basket toast.

## Master Prompt 6: Material Discoveries, hunt HUD, sell clarity (offline only, NOT Studio-tested)
Categories (Common 80 / Quartz 15 / Metal 5, presentation only), server-decided per rock+round, revealed on the owner's completion, profile Materials (no schema bump), Collection Materials tab, quiet batched notice, "Rocks left in pile" + server hunt timer, sell preview and exact receipt. Details, checks, limits: `docs/m6/DISCOVERIES.md`, pictures `docs/m6/disc/`. check.sh clean, regressions 26/26. BLOCKED: Studio.

## Pass C geode rebuild (Master 7, offline only, NOT Studio-tested)
See docs/m7/GEODE.md. Rebuilt Blender kit (shells A/B/C, narrow rim, shade band, druse, cluster F, stand), GeodeModel formations + onStand + fitted reveal halves, GeodeView 3/4. Check + 33 regressions PASS offline. BLOCKED: cabinet switch to onStand (lobby helper), Studio placement/rejoin test.
