# Master Prompt 4/5, milestone 3: one UI system across the panels (client)

Offline only (Lune + preview mock). Nothing here is Studio-tested. Pictures: `docs/m4/ui/` (phone-1108, phone,
phone-portrait; the shop also on pc) and variants in subfolders (`shop-*`, `collection-*`, `party-*`).
The style sheet `docs/refs/assets/13_mobile_ui_kit.png` is style only; its names, values and bars are not config.

## Design system (src/client/ui/UI.luau, additive)
Tokens (`UI.Colors`, `UI.T`, fonts) and components were already shared; this pass added:
`UI.Notice` (server/gameplay notices, fired next to the HUD toast in Main), `UI.statusLine` (one inline line, kept
across re-renders for 6 s), `UI.headerStatus` (notices in the modal subtitle, returns a setter for the normal
subtitle), `UI.pending` (button waits for the server, 4 s timeout so a lost reply never leaves it dead),
`UI.statRow`, `UI.emptyState`. All text goes through `UI.text` (fitted, never raw TextSize in fixed boxes).

## Screens
- Start Hunt (`PartyPanel`): two entry cards with room for two-line descriptions (portrait overlap fixed), one
  accurate rule line (shared pile, own table, first table to crush the geode rock wins; no shared-reward promise),
  party slots from real state only. A solo player shows "Solo", never "Not ready". Party state: READY / START HUNT /
  LEAVE in a pinned footer, server reason for START, invite and start buttons pending, errors inline.
- Shop (`ShopPanel`): one catalog renderer. Each tab builds `Spec`s from Config and the profile; the screen is a
  scrolling list (search box from 9 entries) plus one selected-item pane (picture, real stats with units, comparison
  with the equipped item, state, reason when disabled, one action). Selecting never buys. Landscape phones put the
  picture beside the facts so the action is always on screen; portrait stacks list over pane; desktop gets a larger
  modal. Subtitles describe what the tab does (stronger tools break rocks faster; machines crush rocks you deposit,
  they do not collect; tiers = bigger piles, tougher rocks, richer pay). Entry point `ShopPanel.open(tab?)`.
  Lobby: selecting a tool or machine calls `UpgradePreview.select(id)`; closing resets it.
  Dev mock catalog: `preview ... shop --set mock=12|30` (ReplicatedStorage attribute `DevShopMock`, never set in game).
- Collection (`CollectionPanel`): detail pane with actions pinned (place / favourite / sell), portrait detail is a
  stacked page, short landscape uses smaller cards, empty vs filtered-empty states, remove-from-gallery lives on the
  slot chooser, pending notices while the server confirms.
- Results (`ResultsPanel`): HuntLedger numbers unchanged (processed, earned, sold with cash, bag with value). The
  "Added to your collection" line is drawn only when the specimen id is in the profile inventory; otherwise
  "Securing..." for 8 s, then "not in your collection yet, added the next time you join" (AwardLedger reconcile).
  Saves-off note. Return / rematch buttons wait for the server.
- Settings: subtitle states "Saves are off here" when the profile says so; inline notices.

## HUD scope (brief V7 section 10)
Hud already hid the Table card, mini summary and carry card outside a hunt; new scene `hud-scope` proves it (second
hunt rebinds, second return clean). Added: arena guidance toasts (basket full, bag full, move closer, tray full,
collect more) are tagged; basket guidance clears when carry drops below capacity, bag guidance when the bag is not
full, all arena toasts on lobby return. Arena arrow chips were not visible after return (checked).

## Checks (offline)
tools/check.sh clean (95 tests), tools/run_regressions.sh 25/25 including `hud-scope`, check_layout on every picture
in docs/m4/ui and its subfolders: 0 problems (info-only clipped labels remain in two phone pictures).
NOT verified: Studio, real touch input, real UIScale/AbsoluteSize (the portrait grid uses relative cell sizes for this
reason), controller focus, the basket-toast clear against a real deposit (code path only, tested via lobby return).
