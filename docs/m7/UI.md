# Master Prompt 7, UI correction (Pass A input, HUD, Shop, Collection, Start Hunt)

Offline only (Lune + preview mock). NOT Studio-tested. Pictures: `docs/m7/ui/` (pc, phone-1108, phone-portrait; `before/`
holds the rejected look). `check_layout.py docs/m7/ui`: 0 problems. `run_regressions.sh`: 33/33 (the `first-person:menu`
check now also asserts input suspension and HUD restore). `check.sh`: zero diagnostics, 117 rule tests.

## Pass A: input behind a blocking menu
- Cause (inferred from source, NOT reproduced: the mock has no PlayerModule): freeing the cursor only unlocked the mouse.
  PlayerModule kept reading look input (mouse delta while it reports LockCenter, right-drag, right stick, touch drag) and move
  input, so the view could still turn and the avatar still walk behind a panel.
- Fix, in the one coordinator (`CameraMode.apply`, same decision that frees the cursor): `Controls:Disable()/Enable()`,
  `CameraInput.setInputEnabled(false/true)` when that PlayerModule child exists (pcall, optional), and a sunk
  `CTR_ModalSink` action for WASD / space / arrows / both sticks. No per-frame camera writes. `CameraMode.suspendedInput()`.
- Close click: `UI.block` now stamps `UI.unblockedAt()` synchronously, so an input arriving in the same frame as the close is
  inside the 0.25 s grace (before, the stamp came from a deferred step). `PromptArbiter` also uses `CameraMode.mayAct()`.
- Gamepad: the modal panel is a selection group that stops at its edges, the backdrop is not selectable, the first control is
  selected when the last input was a gamepad, selection cleared on close. Touch: the backdrop is a full-screen button, so a
  swipe never reaches PileView.
- Unverified in Studio: that `CameraInput.setInputEnabled` exists in the live PlayerModule (the Controls and sink paths do not
  depend on it), real mouse/touch/gamepad behaviour.

## HUD (section 8)
One resource block (cash, then "Bag n / max" with a thin bar); 48 px icon rail (touch-only devices get a one-word caption under
the icon and a 56 px tile; mouse/gamepad get a tooltip); lobby tool chip small, name only; in a blocking panel the whole left
column, top cue and dock hide and return on close; "Start your first hunt" is a 230 px pill for 14 s or until any panel opens,
at the top (never over signs); "Studio test: saves off" is a small bottom-left chip, Studio only (Settings and Results still state
saves-off honestly for players). Hunt HUD unchanged apart from the shared resource block.

## Shop (9), Collection (10), Start Hunt (11)
- Shop: list + one connected item view (framed large preview, name, value-over-label stat tiles, one sentence, one status/action
  area), calm underline tabs (`UI.tabBar`), one selection ring, equipped = check badge in the row and the status line once (no
  disabled EQUIPPED button), "Equipped for your station". Categories, prices and server requests unchanged. Checked with 3 and 30
  mock entries (`--set mock=`).
- Collection: real empty state (illustrative geode marked EXAMPLE, loop line, START A HUNT through `PartyPanel.open`, no toolbar);
  populated grid + hero detail; labelled "Owned n / max" and "Gallery n / slots"; Stats as tiles; `UI.fitModal` sizes the panel
  per view (empty, stats, populated).
- Start Hunt: solo/create-party cards and one rule line, no party row until a party exists; party view unchanged logic (members,
  readiness, leader, invite, tier, start) with the panel capped per state. Joining someone else's invite still shows at the top.
- Branding: no visible "Crack the Rocks" left in client UI; the save-failure kick text now says FIND THE GEODE!.

## Not done / open
Index and Materials tabs only got the tab bar and sizing. Portrait shop splits 44/56 and scrolls. Text in a few captions stays
14 px (stat labels, tab-card captions). Touch rail captions are 12 px. Not tested: real UIScale on devices, text size Largest
after this change (only default), controller focus order.
