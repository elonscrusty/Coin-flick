# UI redesign v2: report

Brief: `docs/ui_v2/BRIEF_UI_V2.md`, boards `ui_reference.png` and `additional_screens.png` (the uncorrected draft's
extra worlds were NOT added). Status: **PASS offline** (type check, rule tests, regressions, layout checks, preview
renders). **NOT VERIFIED in Studio**: no real device, real PlayerModule, real mouse lock, multiplayer, purchase or
persistence test was run.

Renders: `docs/ui_v2/renders/` (pc, phone-1108, phone-portrait), `renders/largest/` (Roblox Text size Largest on
phone-1108 and phone-portrait), `renders/before/` (the previous interface, same screens). Shot list:
`tools/preview/ui_v2.list`, rendered with `bash tools/preview/render_list.sh tools/preview/ui_v2.list docs/ui_v2/renders`.
Board numbers map to file names: 01 lobby, 02 collect, 03 station, 04/05 upgrades, 06 collection, 07 display,
08 start hunt, 09 party, 10 results, 11 settings, 12 feedback / 12b confirmation, a1-a9 the additional board.

## 1. Changed scripts and UI systems

| Area | Files | What |
|---|---|---|
| Theme | `src/client/ui/Theme.luau` (new) | every colour, font, text size, outline weight, size, radius and motion value |
| Components + screen manager | `src/client/ui/UI.luau` (rewritten) | outlined fitted text (display font always in capitals), an illustrated outlined icon set, buttons with hover / pressed / selected / disabled / pending states, red close, tabs, catalog rows, specimen cards, counters, cash readout, empty / loading / error states, slider, toggle, modal shell (one primary menu), stacked confirmation dialogs (`UI.confirm`: own layer and block key), coalesced notifications (`UI.notify`: own top layer, at most 3, the same text or tag refreshes the card instead of stacking) |
| Model thumbnails | `src/client/ui/ModelThumb.luau` (new), `ItemView` | still ViewportFrames of the game's own kit models (basket, tray, rubble bin, cabinet, rock) and tools / machines; drawn icon fallback; no asset ids invented |
| Lobby + hunt HUD | `src/client/ui/Hud.luau` (rewritten) | lobby: cash, a rubble line only when there is rubble, Settings / Upgrades / Collection / Party tiles; hunt: objective, real timer + pile count, CARRIED / QUEUE / RUBBLE counters, a processing card from the server plate state, machine chip, HAND / tool slots, the contextual action (PICK UP, BASKET FULL, DEPOSIT ROCKS, HOLD TO CRACK, gray status states), sell card |
| Upgrades | `src/client/ui/ShopPanel.luau` (rewritten) | two-column shell, real catalog states, purchase confirmation, PURCHASING until the server answers; level purchases send the level shown (the server's stale-level guard) |
| Collection | `src/client/ui/CollectionPanel.luau` (rewritten) | Collection / Display / Index / Materials / Records tabs |
| Start Hunt / Party | `src/client/ui/PartyPanel.luau` (rewritten) | Start Hunt, Members, Invite, PARTY INVITE dialog, expiry notice |
| Results | `src/client/ui/ResultsPanel.luau` (rewritten) | compact results |
| Settings | `src/client/ui/SettingsPanel.luau` (rewritten) | Music, Sounds, Camera Sensitivity (mouse only), Reduce Motion, Low Effects, Hints |
| Camera / input | `src/client/CameraMode.luau` | gamepad B closes the top layer (dialog first, then the menu); a dialog holds its own block key, so the cursor stays free and gameplay input suspended until the last layer closes |
| World prompt | `src/client/PromptArbiter.luau` | v2 pill; the rubble seller is drawn as the sell card with the real bag count and SELL, or "No rubble to sell." |
| Reticle | `src/client/Reticle.luau` | outlined dot, dark reason plate |
| Boot wiring | `src/client/Main.client.luau` | leave-hunt confirmation through `UI.confirm`, one notification per server toast, clearer wording, camera sensitivity applied from the profile |
| Loading | `src/first/LoadingScreen.luau` | charcoal title screen with step dots (same real steps) |
| Settings persistence | `src/server/Profiles.luau`, `src/server/EconomyService.luau` | one new validated setting `CameraSensitivity` (0..1, default 0.5; old saves get it through the existing reconcile, no schema change) |
| Preview tools | `tools/preview/render_list.sh`, `tools/preview/ui_v2.list`, Luckiest Guy in the preview fonts, scene options, `tools/run_regressions.sh` | see docs/PREVIEW.md |

Old interface: the old screens were rewritten in place, so each entry point (HUD tile, lobby counter prompt, world
prompt, server event) still reaches exactly one module and no second creator exists. The old cream / slate styles, the
left icon rail, the bottom tool chip, the inline status lines and the old toast column are gone.
Not touched (other helpers): StationView, ToolAnim, Anim, CarryView, HitFx, RevealView, Effects, GeodeView,
GeodeModel and the server world builders. RevealView keeps reading `UI.Colors` / `UI.text`, which still exist.

## 2. Screens against the boards (what is real data)

- Lobby HUD (board 1): cash with the cash icon and compact tiles; no hunt-only pieces (checked by `hud-scope`).
- Hunt collect / station (boards 2, 3): counters are labelled (CARRIED = basket, QUEUE = deposited rocks at the
  station, RUBBLE = storage) and sit top left, away from the joystick. Tool slots are an indicator: the game has no
  manual tool switching (hand while collecting / depositing, the tool while cracking). The processing card shows only
  while the server's plate progress actually changes (or the station's machine runs) and hides when the player leaves
  the table, the round ends or the phase changes; nothing animates it on the client. Basket full: "Basket full.
  Deposit your rocks at the station." (coalesced: repeated refusals refresh one card).
- Upgrades (boards 4, 5, additional 1-3): Tools, Machines, Storage, Tiers, Gallery (and Store only with a real product
  id). Storage shows the three capacities apart: carry basket and station queue are fixed in Config (no upgrade
  exists, and the screen says so), rubble storage shows current and next size with the real price. Tiers show the
  real pile size, pay, hits and unlock requirements (no "Use existing tier progression" text). Gallery uses
  Config.Display (3 / 6 / 12 / 20 slots, no 9-slot). Machines read "Processes deposited rocks automatically." and
  "It never collects rocks." Action states: BUY $x / UPGRADE $x / UNLOCK $x / EQUIP / INSTALL; EQUIPPED / INSTALLED /
  CURRENT / OWNED / UNLOCKED / FIXED SIZE / MAX SIZE as status (not buttons); LOCKED with the real reason; NOT ENOUGH
  CASH; PURCHASING.
- Purchase confirmation (board 12): item, picture, consequence and price; nothing is sent before CONFIRM.
- Collection / Display (boards 6, 7): "Display slots n/N" apart from "Owned n/500"; place, replace and remove go
  through the existing `Display` / `DisplayAt` actions; a full display asks which slot to replace. Sell and
  favourite are kept.
- Records (additional 4, 8): Solo finds, Competitive wins, Matches played from the server profile, other stats below.
  Without stats: "Records unavailable" with RETRY (asks the server to resend the profile, rate limited there) and
  CLOSE, never zeros.
- Empty collection (additional 5): "No geodes yet." / "Find one in a hunt." / START HUNT (the real Start Hunt panel).
- Start Hunt (board 8): "One pile. One geode.", SOLO HUNT START / PARTY HUNT CREATE PARTY, "Starting hunt..." while the
  request is out (no double start; a refusal ends it).
- Party (board 9, additional 6, 7): PartyService has a real ready system, so it is shown (Ready / Not ready / a
  blocker); leader crown, kick, hunt tier, START HUNT for the leader only (enabled when the server says it can
  start), LEAVE. Invite tab (leader): players in this server, not in the party, not in a hunt; "The party is full."
  instead of invites. PARTY INVITE dialog with ACCEPT / DECLINE; an invite that expires closes it with "Party
  invitation expired.".
- Results (board 10): the real winner (avatar headshot via rbxthumb, crown), the specimen, Rubble earned and Rocks
  cracked from the hunt ledger. The game has no single "cash earned" figure for a hunt (rubble is cash only when
  sold), so that tile is Rubble earned, with the sold amount and storage value on one line below. "Geode added to
  collection!" only for the recipient once the profile holds it; others read "<name> keeps the geode. You keep your
  rubble." PLAY AGAIN follows the existing rematch rules (the leader starts, members mark ready).
- Settings (board 11): percentages next to the sliders; Reduce Motion applies at once.
- Loading (additional 8): FIND THE GEODE! title, the real step text and three step dots.
- Rubble sale (additional 9): the seller prompt as a card with "Rubble: n/cap" and SELL, or "No rubble to sell." with
  SELL disabled; the sale and its receipt stay the server's.

## 3. Verification (offline only)

| Check | Result |
|---|---|
| `bash tools/check.sh` (luau-lsp strict, compile, Lune rule tests, Rojo build) | PASS: zero diagnostics, 154 rule tests |
| `bash tools/run_regressions.sh` | PASS: 44 / 44 (offline; includes `hud-scope`, the `first-person:*` scenes such as `menu` that assert input suspension and HUD restore, the `loop:*` rematch / lobby return, and four new UI checks below) |
| `ui:notices coalesce` (`hunt --set toast=feedback`) | PASS: three identical "Basket full" refusals stay one card, two cards in all |
| `ui:records unavailable` (`collection --set tab=Records --set records=fail`) | PASS: RETRY + CLOSE shown, no record rows |
| `ui:purchase confirm` (`shop --set tab=Storage --set confirm=1`) | PASS: confirmation shown with CONFIRM / CANCEL, nothing sent |
| `ui:invite expiry` (`party --set view=expired`) | PASS: dialog shown, closed when the server expired the invite, "Party invitation expired." shown |
| `python3 tools/preview/check_layout.py docs/ui_v2/renders docs/ui_v2/renders/largest` (JSON next to each PNG at render time) | PASS: 135 scenes, 0 problems (4 informational clipped rows inside scroll lists) |
| Renders | 27 shots x pc / phone-1108 / phone-portrait, plus 27 x phone-1108 / phone-portrait at Text size Largest; compared side by side with both boards and iterated (title capitals, single-line tabs, portrait HUD stack, notice placement, dialog width, sell card) |

Not run: Studio, a real phone, gamepad, multiplayer with real clients, real purchases, DataStore persistence.

## 4. Limitations and what needs Studio

- Nothing here ran in Studio or on a phone: the real PlayerModule (mouse unlock, look / move suspension, gamepad B),
  real touch controls, real UIScale, text size on devices, avatar headshots (`rbxthumb://`), purchases, persistence of
  the new setting and multiplayer party flows are NOT verified.
- Camera Sensitivity uses `UserInputService.MouseDeltaSensitivity`, so it only affects mouse look and its row is shown
  only when a mouse is present; touch and gamepad look speed stay Roblox's own setting.
- Icons are drawn from UI frames (one outline weight) or are still ViewportFrames of the game's real models. The repo
  has no icon upload pipeline (no upload_icons / ImageIds), so no image ids were created or invented.
- (Fixed in section 5) Notifications could cover a menu title on short phones; "Starting hunt..." could not be
  captured offline; PC menus stopped growing past UIScale 1.3.
- The station still (`fp view=table`) shows the plate while cracking; the processing card depends on live server
  progress and is not in the still frame.
- An empty basket at the own table keeps the existing ActionRules wording (COLLECT ROCKS, a gray status).

## 5. Leftovers fixed (UI v2 follow-up)

Renders: `docs/ui_v2/renders2/` (pc, phone-1108, phone-portrait), `renders2/largest/` (Text size Largest on phone-1108
and phone-portrait), PC-only notice shots from `tools/preview/ui_v2_pc.list`. Rendered with `--set uiscale=real`.

**Preview finding.** The offline renderer ignores a `UIScale` parented to a `ScreenGui` (it lays every layer out at
scale 1), and every UI layer carries one (`UI.luau` "Scale"). So `docs/ui_v2/renders/` showed the menus at scale 1:
too small on PC and phone-1108, and on portrait the game's layout maths (logical 487 wide) did not match the 390 px
the picture used. `--set uiscale=real` (`scenes/lib/ctr.luau`, preview only) moves each layer's contents into a
full-screen Frame that carries the same scale, which the renderer does draw, so `renders2/` shows real device sizes.
The renderer itself was not changed.

| Leftover | Fix | Check |
|---|---|---|
| PC menus too small | `UI.scaleFor`: landscape phones keep 0.8-1.3 (same formula); past 1.3 the scale keeps growing with the height, holding the logical canvas at ~600 tall: 1366x768 laptop 1.30, 1080p 1.70 (Upgrades 1226 x 750 px), 1440p 2.30, 4K ~3.5. Logical size is rounded so the `Logical.Y >= 600` layouts hold on big screens. Portrait phones scale by width (390 -> 1.0, 430 -> 1.1) instead of sitting on the 0.8 floor (labels were a fifth smaller than designed). | `SCALE` lines in `ui_notices` (asserted) |
| Notice over a menu title | `fitNotices` (UI.luau): with a menu open the notification column goes beside the menu when there is room (>= 230 logical, PC and tablets), else it takes the first top whose whole stack misses the menu header (title, cash, X) and any confirmation dialog: the top edge, then just under the header, then under the dialog. Refits on menu / dialog open and close, `UI.fitModal`, new or removed cards and resizes. The HUD's own spot is unchanged when no menu is open. On a short phone with a full-height menu the cards sit under the header over the top of the menu body (they keep their X and leave on their own). | `ui:notices clear of headers` (`ui_notices`, phone-small, Text size Largest, real scale: 4 menus + Upgrades under a purchase dialog; also passes on phone, phone-1108, phone-portrait, pc). With the placement switched off the same check fails (overlaps on phone-small and pc). |
| "Starting hunt..." | PartyPanel: the pending state stays on the start view when the server's solo party arrives before the hunt, shows as a compact card (additional board 8), ends when the hunt arrives or a warning (refusal) comes, and gives up after 8 s with "The hunt did not start. Try again."; one request per tap (the button is gone while pending, reopening keeps the state). A party leader's START HUNT reads STARTING... with "Starting hunt..." in gold under the tiers. Preview seam `PartyPanel.Hold` holds requests back so it can be seen offline. | `ui:starting hunt` (`party --set view=startcheck`): two taps + a reopen send one request, card shown, timeout notice, a real start clears it. Shot `08c-starting`. |
| Drift against the boards | Tab bars use one text size for every tab (the long words "Machines" / "Materials" used to shrink alone; measured after layout, held to the smallest). Dark text on gold never takes the dark outline (the "SELL HERE" marker and any other display-font label in DarkText were a blot; buttons already did this). Start Hunt pending is a compact card like additional board 8. Sizes now match the boards' proportions on PC and portrait (above). | renders2 side by side with both boards |

Checks: `bash tools/check.sh` zero diagnostics; `bash tools/run_regressions.sh` (48 / 48 PASS, two new checks above);
`python3 tools/preview/check_layout.py` on the scene JSONs of `renders2` (86) and `renders2/largest` (56): 0 problems (the checker also reads the new `*.surfaces.json` files and reports them unreadable; those were left out).
Not run: Studio, a real phone or monitor. Real `UIScale` on a `ScreenGui`, real viewport sizes and the start
round trip through a real server are NOT verified.
