# Master Prompt 4, milestone 1: interaction (client)

Offline only (Lune + preview mock). Nothing here is Studio-tested. Each defect: cause (CONFIRMED = read in
source and reproduced offline; HYPOTHESIS = needs Studio), fix, evidence. Pictures: `docs/m4/interaction/`
(`<scene>-<device>.png`; the grey circle labelled JUMP is the preview's model of Roblox's jump button).

## 1. Action button vs the native jump button (specs 38, 52)

- Owner of the control: `src/client/ui/Hud.luau` (`PrimaryAction`, one `TextButton`, no hidden twin; the only
  other input path is E / RT in `PileView.start`). Insets: the HUD ScreenGui uses `CoreUISafeInsets` and one
  `UIScale` (`UI.fitScale`); `placeAction` converted to screen pixels once, so scale is not applied twice.
- CONFIRMED: placement depended on one guessed table of jump-button numbers (70/120 px, +14 px gap), gated on
  `TouchEnabled`, with no way to see the real rectangle. It was already "above" that model, yet the owner's
  recording shows an overlap, so the model under-estimates the real button on that device.
- HYPOTHESIS (Studio): the real button is larger or higher than the model (new touch-control scaling), or the
  device reports `TouchEnabled = false` at startup.
- Fix: `src/shared/TouchLayout.luau` (pure, tested) reserves the modelled rectangle grown by 10% + 14 px and puts
  the action outside it with a 16 px gap: above it, or, when the screen is too short for that (1108x512, 844x390
  with the roster margin), directly LEFT of it on the bottom row. The bottom dock and queue card shift left of the
  action in that mode. The action is hidden entirely when nothing useful can be done (see 5).
- Checks: `tests/test_m4_interaction.luau` (no overlap on 6 sizes), `tools/preview/check_layout.py` new JUMP rule
  (PrimaryAction, WorldPrompt, GuideEdge, TableQueue, Dock vs the jump ghost), renderer draws the jump ghost.
- Still to measure in Studio: the real jump rectangle on phone-1108 (Device Emulator "Touch" and the owner's phone).

## 2. Prompt arbitration (specs 27, 51)

- CONFIRMED cause: each tool stand, pedestal, hopper and the kiosk carry their own `ProximityPrompt`; Roblox draws every
  enabled one in range with its default large billboard, nothing coordinates them, and the billboards sit on the
  tool chip. (Not duplicate connections: the server `PromptTriggered` handlers connect once.)
- Fix: `src/client/PromptArbiter.luau`. Prompts are switched to `Style = Custom` locally, one winner is chosen every
  0.1 s (`src/shared/PromptPick.luau`: nearest, camera-facing bonus, 2.5 stud hysteresis, a prompt behind a big solid is
  penalised not removed), only it stays Enabled locally, and it is drawn as ONE compact pill above the tool chip.
  Tap triggers the same prompt (`InputHoldBegin/End`); keyboard / gamepad stay with Roblox. Nothing shows while a
  modal or reveal owns the screen, while a button is held, or outside `Searching` in a hunt; in a hunt the hopper
  prompt is hidden (the action button sells) and only the player's own machine panel is offered.
- No server file changed. `PromptArbiter.stats()` reports tracked / enabled / winner for dev counts (entries are
  dropped on `DescendantRemoving`, one connection set, so returning from a hunt cannot accumulate).
- Evidence: `workshop-*.png` (one Inspect / Buy pill, matches the tool opened).

## 3. Camera occlusion (specs 28, 51)

- CONFIRMED in source: Roblox's default camera only pulls in for `CanCollide = true` parts. `KitModels.clone` keeps kit
  MeshParts anchored and non-colliding and `Kit.deco` parts are non-colliding AND non-queryable, so the camera passes
  through roofs and beams (the wood-filled screen). Making them collide would trap avatars, so collisions are not touched.
- Fix: render-step guard `src/client/CameraGuard.luau`: five thin rays from the head
  to the camera the default script chose; the nearest real occluder pulls the camera in at once (never inside it) and it
  eases out at 9 studs/s (`src/shared/CameraSolve.luau`, tested). Zoom limits 5 to 60 studs.
- Marking rule for world builders (honoured by the guard): a part is NOT an occluder when
  `part:SetAttribute("CameraIgnore", true)` on the part or ANY ancestor Model / Folder, or it has the CollectionService
  tag `CameraIgnore`, or `CanQuery = false`, or it is smaller than 3 studs on every side, or `Transparency >= 0.5`.
  Use it on decorative-only trim, canopy fringe, signs, foliage, lamps. Floors, walls and boundaries stay occluders.
  (The lobby and quarry helpers already set it on roofs, canopies, foliage and lamps.)
- Cannot be shown offline: the preview has no raycasts and no default camera. Unavoidable close angles (wall right behind
  the head: camera stops at 2.2 studs) are documented, not hidden. Needs a Studio camera tour (spawn, kiosk sides, workshop
  aisle, gallery, hopper, pile rim, each table).

## 4. Navigation (specs 04, 29)

- CONFIRMED: the giant "ROCK PILE" sign was not a world model: it is the client `GuideArrow` BillboardGui
  (`PileView.updateGuide` -> `GuideArrow.set(center, "ROCK PILE")`, 7 studs up, AlwaysOnTop, 150x52 yellow) plus a
  1.5x scaled yellow floor arrow, shown for every non-pickup context. Nothing to delete in `ArenaBuilder` / `ArenaKit`.
- Fix: `GuideArrow.luau` rewritten. No billboard, no big arrow. A small ground chevron (V, 35% transparent) a few studs
  ahead of the avatar, only for 6 s after the destination changes and never within 14 studs of it; plus a small dark chip
  ("TABLE" / "PILE") on the screen edge while the target is off screen, kept inside a rectangle the HUD supplies (clear
  of the left column, objective, action, jump and the bottom row). Direction comes from the real target position and
  camera. Table hint: whenever rocks wait to be deposited. Pile hint: only while the profile is still in onboarding.
  `PileView.updateGuide` clears it outside `Searching`, behind modals and when the context has no arrow.

## 5. Pickup, carry, deposit, action state machine, HUD (specs 23 to 26, 39)

- Action state machine: `src/shared/ActionRules.luau` (pure, tested) decides the whole context from one inputs table;
  `PileView.context` only gathers inputs. Label, enabled state and the request all come from that one result, and the
  outlined rock is `ctx.Target`, the id sent. Priority: sell (with rubble) > own table (deposit beats crush; a running
  machine only deposits) > pile > nothing. `closer` only appears just outside range of a relevant place (no more
  "MOVE CLOSER" next to scenery); `none` / `wait` / `securing` draw no button. BASKET FULL is a neutral status, not a
  yellow pickup. 0.35 s jitter guard keeps the last answer while crossing a boundary, never past a round change; the
  at-table range has a small hysteresis.
- Hold: a press whose meaning changes (basket fills, leaves range, reaches the table) is cancelled until released; the
  pressed-button connection is single (second finger ignored) and dropped when the button hides; a modal, focus loss,
  respawn, `Init` and `Left` clear press state. A refused pickup (`Gone`, `Unreachable`, `BadRock`) drops the target
  quietly (`PileView.onReply`).
- HUD (`Hud.luau`): queue card + tool/machine chips only AT the own table (and always in the lobby, tool chip more
  modest); while exploring, one small queue summary in the left column only when rocks are queued or a machine runs.
  The "No machine" chip is gone (Shop is the way to buy one). Rubble Bag and Carry Basket stay separate cards;
  rubble capacity is `profile.Capacity` (from `Config.Capacity` tier), shown 0/30 at tier 1 and 1/300 in the rocks-views
  profile (tier 3). Basket 5 means "5 / 5", capacity from `Config.Carry`.
- Carried rocks (24): `CarryView` already draws 1 to 5 neutral miniatures from the public `Basket` ids and clears on
  `Left`; unchanged. Deposit/queue display (25): `StationView` tray slots + the HUD card from the server snapshot;
  unchanged apart from where the card shows.

## 6. Loop verified offline

`rocks-views` A to D: pick 1..5 (basket 5/5, BASKET FULL, TABLE chip), walk to the table, DEPOSIT (queue 4/10), HOLD TO
CRUSH, rubble 1/300; `tests/test_v3_loop.luau` covers the server rules; all unchanged. Not run: a real multi-client contest.
