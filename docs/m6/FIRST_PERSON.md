# Master Prompt 6, first person (camera, reticle, one action path, carried load)

> 2026-10-10 update: first person is now the HUNT view only; the lobby is third person, and Alt frees the cursor in a
> hunt on desktop. See `docs/m11/CAMERA_SPAWN_FIX.md`, which replaces the lobby parts below.

Offline only (Lune + preview mock). NOT Studio-tested: nothing here proves the real PlayerModule camera, mouse
unlock, touch look-drag, gamepad or avatar rigs behave this way. Pictures: `docs/m6/fp/` (scene `fp`,
`bash tools/preview/render.sh fp --device phone-1108|pc --set view=lobby|aim|glimpse|table|sell|full|menu|explore`).
Not in this change (another helper): Material Discoveries, hunt timer / pile counts in Hud, Collection Materials,
sell flow, Profiles.

## What changed

| Area | Owner | Notes |
|---|---|---|
| Camera, cursor, modal stack, local visibility | `src/client/CameraMode.luau` (new), pure rules `src/shared/CameraModeRules.luau` | the only module that writes `Player.CameraMode`, zoom limits, `MouseBehavior`, camera type recovery |
| Reticle | `src/client/Reticle.luau` (new) | one dot; neutral / eligible ring / unavailable ring plus one reason line |
| Aim | `src/shared/AimResolve.luau` (new, tested), `PileView` | camera-centre ray over explicitly tagged candidates |
| Carried-load glimpse | `src/client/CarryGlimpse.luau` (new), `CarryView` | local only |
| Old camera guard | `CameraGuard` | does nothing in first person; still the third-person fallback (`Config.Camera.FirstPerson = false`) |
| Tutorial tip | `Main.client` `pickupTip()` | first arena hint of the existing onboarding, worded for mouse / touch / gamepad |

Config: `Config.Camera` (FirstPerson switch, Fov 70, Reach 11, FarReach 30, Slack 0.35, WorkRadius 5.5, PromptCone 0.8,
GraceAfterModal 0.25, Glimpse offset). Nothing else sets CameraType / MouseBehavior / zoom (grep checked); `ShopPanel`,
`HUD`, `CollectionPanel` were not touched.

## Camera and modal lifecycle (sections 3 and 4)
- `Player.CameraMode = LockFirstPerson`, zoom 0.5 / 0.5, FOV left at 70. No head bob, FOV change, roll or shake; no camera loop of ours
  writes `Camera.CFrame` (PlayerModule does the looking).
- Modal stack = `UI.block(key, on)` (already keyed: every modal, the reveal and the results hold a key). `CameraMode` listens to
  `UI.BlockChanged` and applies on the next deferred step, so a menu swapped for another never gives a frame of mouse look, and
  closing one of two layers keeps the cursor free. Free cursor = a 1 px invisible `Modal` GuiButton (the supported unlock under
  LockFirstPerson) plus `MouseBehavior`. Pure rule and tests: `CameraModeRules` (`m6 modal stack`, `m6 camera`).
- Re-applied once on: start, `CharacterAdded` (new humanoid, nothing kept from the old one), `CurrentCamera` replaced,
  match `Init`, `Left` (lobby return) and `Results` (`CameraMode.restore()`). A Scriptable / Fixed camera without a cinematic key
  (`CameraMode.cinematic(key, on)`) or the camera attribute `CT_Cinematic` is put back to Custom on the current humanoid.
  There is no cinematic camera in the game today (reveal / results are GUI), so the hook is unused.
- Input grace: the input that closes a menu cannot act. `CameraMode.mayAct()` is false while blocked and for 0.25 s after the last
  panel closed; `PileView.perform` cancels the press until it is released. A panel opening, window focus loss, `Found` and
  `Left` clear held intent (`PileView.stopAll`). Mouse-click holds are released on all of those.
- Gamepad: ButtonB is bound (High priority, sunk) only while a panel is open and closes it. The action stays R2 (hunt) and Roblox's own
  prompt button for lobby counters; one binding per context.
- Touch: a touch in first person is never a pickup (tap-to-select is off); the look drag is Roblox's; the action button stays where
  `TouchLayout` puts it (tested clear of jump on 5 sizes, `m6 touch`). Desktop: click while the mouse is locked, or E, uses the same
  `PileView.holdBegin` path as the button.

## Local avatar visibility (section 3)
`LocalTransparencyModifier = 1` on the Head, accessory handles, UpperTorso / LowerTorso / Torso and both upper arms (render step
just after the camera, list kept current by DescendantAdded / Removing, no per-frame search), and on the own carry basket and its minis
(`CameraMode.hideLocally`, parts added later covered). Other players see the full avatar. Forearms, hands and the held tool stay,
but ghost out (up to 90 %) when a stroke brings them within 2.8 studs of the eye. Not tested on real rigs (R6, layered clothing, big
accessories); R6 has one arm part per side and is not hidden.

## One context from the reticle (section 5)
- `PileView.context()` still gathers inputs for the pure `ActionRules.decide` (unchanged, reused). In first person the inputs come
  from the camera-centre ray: `HasTarget` = the ray (centre + `Slack`) is on a pickable rock inside the server's own reach, with line
  of sight over real geometry (`CameraGuard.ignorable` parts, avatars and the pile do not block); `NearHopper` needs the ray on the hopper
  (or standing within 3.5 studs); a pile rock under the reticle beats the table when further than `WorkRadius` from it; `closer` ("Move
  closer") appears only while the ray is on the own table (when the table is wanted) or on a rock out of reach, never for scenery.
- Tagged targets: source rocks (`kind == 2` pile models), own table (its model), sell hopper bodies (`Hopper` attribute), lobby
  counters / kiosk (`ProximityPrompt`s). `PromptArbiter` now offers a lobby prompt in first person only inside a `PromptCone` (about
  37 degrees) around the ray (closer than 3 studs is exempt); the pill is the single label, tapping triggers the same prompt. In a hunt
  the hopper prompt stays hidden (the action button sells) and no ProximityPrompt label duplicates the action button.
- Reticle states from `AimResolve.reticle(ctxId, aimed)`: eligible (pickup, deposit, crush, sell), unavailable with ONE reason
  (basket full on a rock, rubble bag full, move closer on a far target), neutral otherwise; hidden while any panel / reveal / results
  holds the screen or during the countdown. It does not repeat the action label (button / pill does).
- Server: `RockService` already takes the avatar position from the server (never the client), `RoundRocks.pickup` checks session,
  rock state (atomic: `Gone` for a second taker), basket space, reachable layer and flat distance <= PickupRange + half a rock, and a
  rate limit; deposit / crush check the table range. Not tightened: there is no server line-of-sight check (the server has no pile
  parts; the client's ray is a convenience) and no vertical limit beyond the layer rule. Neither was changed. The target rock is not sent
  anywhere new: nothing in this change reads or sends hidden state.

## Carried load and table work (section 6)
- `CarryGlimpse`: one local model (lip, two end boards, up to 5 real rock minis from `CarryView.shown(uid)`, i.e. the server-accepted
  basket) at the lower right edge of the view, moved with the camera in one render step, rebuilt only when the list changes, removed with
  the round. Shown only in a hunt, first person, no panel. Pickup cue only after the server accepted (count up): a short dip of
  the lip and a quiet gravel sound (skipped with Reduced Motion for the dip). There is no predicted feedback, so a refused pickup needs no undo.
  The rock flying into the basket now lands at the glimpse (`CarryView.basketPoint`). The HUD "Carry n / 5" card still shows the count.
- Table at eye level: standing at the work spot (3.2 studs from the table) the camera is about 1.5 studs above the plate and looks
  down roughly 25 degrees: tray, plate and rock are visible without climbing or pitching straight down (`fp-table`). `StationModels`
  heights and routes were NOT changed. The hammer / jackhammer comes in from the side and ghosts near the eye; honest limit: the third-person
  `ToolAnim` poses were not redone for first person, so contact point and arm pose still need a Studio look.

## Checks
`bash tools/check.sh` zero diagnostics, 117 rule tests (after merging main) (11 new in `tests/test_m6_first_person.luau`), `run_regressions.sh` (33 checks, all pass) includes
`first-person:<view>` scenes (lobby, menu, aim, glimpse, table, sell, explore) that assert ctx / reticle / glimpse state.

## Not done / needs Studio
- Real LockFirstPerson camera, the Modal button unlocking the mouse, gamepad ButtonB, touch look vs the action button, rig variants.
- Multi-client rock contention (server rule is unchanged and tested in `test_v3_loop`).
- Table pose / tool contact in first person; plate view with real kit meshes; hazard-stripe plate reads large in the preview.
- The "full" view (reason line "Basket full") is not captured: the scene's sweep stops at `none`; the state is covered by `AimResolve` tests.
- Material Discoveries, timer / pile counts, Collection Materials and sell presentation belong to the other helper.
