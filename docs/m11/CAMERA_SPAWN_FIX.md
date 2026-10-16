# Camera and spawn fix (owner Studio report, 2026-10-10)

The owner played the build in real Roblox Studio (desktop, mouse) and reported three problems. Everything below is
checked offline only (Lune + the preview mock, which has no PlayerModule and no real spawn placement). **Nothing here
is Studio-tested.**

## 1. "Can't move my mouse to select anything"

Causes:
- **Likely (code confirmed, engine behaviour not reproducible offline):** the free cursor was a `Modal` TextButton placed
  off-screen (`Position -10,-10`, 1x1). Under `LockFirstPerson`, PlayerModule re-locks the mouse every frame; the engine
  only releases it while a Modal GuiButton is Visible in an enabled ScreenGui, and an off-screen button is the most
  probable reason it never did.
- **Confirmed:** in first person there was no way at all to click a HUD button without first opening a menu with a
  world prompt, because the mouse is always locked.
- Checked and NOT a cause: `CameraGuard` (did nothing in first person), `CTR_ModalSink` (sinks only WASD / Space / arrows
  / sticks, never mouse buttons), `CTR_ModalBack` (ButtonB only), `UI.block` (a key set; only toggles touch controls),
  `Controls:Disable()` (movement only).

Fixes (`src/client/CameraMode.luau`, `src/shared/CameraModeRules.luau`):
- The Modal button now sits inside the viewport (top-left pixel, transparent, not selectable) and is Visible exactly
  while the cursor should be free. `UserInputService.MouseIconEnabled` is true whenever the mouse is free (always in the
  lobby) and false only while the first-person view is locked (the reticle is the pointer then).
- First person is now hunt-only (point 2), so the lobby has a normal free mouse for every HUD button and prompt.
- **Hunt, desktop: hold Left Alt (or Right Alt) to free the cursor** (`Config.Camera.FreeCursorKeys`). While it is
  held the reticle hides, movement / look are paused and world actions cannot fire (so a click on a HUD button never
  picks up a rock); releasing it locks the view again with the usual 0.25 s grace. Alt+Tab (focus loss) releases it.
  The desktop tutorial tip says "Hold Alt for the cursor."
- Menus (world prompts, HUD buttons) still free the cursor through `UI.block`; closing the last one restores the view
  once.

## 2. Third-person lobby, first-person hunt (owner decision)

- `CameraModeRules.firstPerson(enabled, inHunt)`: first person only when `Config.Camera.FirstPerson` AND in a hunt
  (`State.Match` from `Init` until `Left`, or the Match place of Teleport mode).
- Lobby: `CameraMode = Classic`, zoom `Config.Camera.Lobby` 8..25, `MouseBehavior = Default` (right-drag turns, as in any
  Roblox game). On leaving a hunt the own body's `LocalTransparencyModifier` is reset once.
- Switching happens once per transition: `CameraMode` listens to `State.Changed("Match")` and applies only when the
  hunt flag changed; the existing `CameraMode.restore()` calls in `Main.client` stay (idempotent).
- Camera clipping: the lodge walls and ceiling are invisible, non-queryable colliders under non-colliding kit meshes,
  so no ray can see them. `CameraGuard` now runs in every third-person view and, while the head is inside the lodge
  room (`Config.Lodge`, shared with `LodgeBuilder.Interior`), adds the distance to the room box face behind the camera
  as one more hit (`CameraSolve.boxExit`). In the preview the spawn camera stops 0.6 studs in front of the front wall.
  Limit: interior stall backs / boards are not in the box, so the camera can still pass through those.
- First-person-only presentation is untouched and keyed on `CameraMode.firstPerson()`, so it is now hunt-only:
  Reticle (also hidden while Alt is held), CarryGlimpse, local hiding, PromptArbiter's aim cone (the lobby uses the
  nearest / facing prompt pill again), PileView click-to-act.

## 3. "I spawn in the roof"

Causes:
- **Confirmed (code):** `Main.server` waits up to 8 s for meshes (`MeshService.start`) BEFORE `World.buildLobby` creates
  the SpawnLocation. A player who joins in that window (Studio Play does) spawns with no SpawnLocation at all, near the
  world origin = the middle of the lodge, and the lodge (with its 86 x 70 `Ceiling` collider at y 29-30) is then built
  around them.
- **Likely (engine behaviour, not reproducible offline):** Roblox's spawn placement lifts a character above anything it
  sees as overlapping the spawn; the old pad was non-colliding inside a huge non-colliding building mesh. Either way the
  only surface up there to stand on is the top of the `Ceiling` collider, inside the roof.
- Checked and clear: `FLOOR_Y` 3 = floor collider top; the 4 x 6 x 4 box on the pad (and on the whole lobby-return
  band, x +-6, z +-3) overlaps no collider (rug, ramp, cabinets at the front wall, benches all clear); only one
  SpawnLocation exists in the lobby; `MatchService` lobby return used `lobby.Spawn` correctly.

Fixes:
- `LobbyBuilder.ensureSpawn()`: a SOLID invisible 8 x 0.2 x 6 SpawnLocation, top 0.02 above the floor, created by
  `Main.server` before the mesh wait; `build()` moves it into the lobby folder.
- `MatchService`: every character that appears outside a hunt is put on the pad by the server (`toLobbySpawn`,
  `PivotTo(lobby.Spawn)`), including characters that already existed when the lobby finished building.

## Checks (offline)

- `bash tools/check.sh`: zero diagnostics, 160 rule tests (new `tests/test_m11_camera.luau`).
- `bash tools/run_regressions.sh`: 51/51 PASS. New: `spawn` and `spawn kit-off` (scene `spawn`: one solid flush pad
  inside the room, clear 4 x 6 x 4 box under the ceiling on the pad and the return band, a character appearing on the
  ceiling is put back on the pad), `first-person:peek` (Alt held: cursor free, Modal button visible on screen, icon on,
  reticle hidden, no action; released: locked again). Updated: `first-person:lobby|menu` (Classic, zoom 8..25, camera
  inside the room, head visible, no reticle), hunt views assert LockFirstPerson, `loop:lobby` asserts third person and
  a visible head after the return. The preview mock gained `preview.key(keyCode, hold, during)`.
- Pictures (`docs/m11/camera/`): `lobby-3p-spawn-pc|phone-1108.png`, `hunt-fp-aim-pc|phone-1108.png`,
  `hunt-fp-peek-pc.png`. The mock has no PlayerModule, so the scene places the camera; CameraGuard is the real code.

## Needs a Studio check

- The Modal button actually frees the mouse in a first-person hunt (Alt held, and with a menu open), and the HUD
  buttons respond; Alt does not trigger anything in the Studio window itself.
- Lobby camera: Classic follow at 8..25, right-drag, no view through the roof or the front wall at the spawn; the
  switch on entering / leaving a hunt happens once and the own avatar is fully visible again in the lobby.
- Spawn: join (fresh and after a reset) lands on the entry rug facing START HUNT, never on the roof.
