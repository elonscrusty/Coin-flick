# Final acceptance: Master Prompt 4 and 5 (2026-10-09)

Everything here is OFFLINE: Lune + the preview renderer (`docs/PREVIEW.md`). Nothing was run in Studio, on a device, or with
real multiplayer. "PASS (offline)" means the code runs, the rules tests pass and the picture looks right in the preview.
"NOT VERIFIED" means it needs Studio, a phone, or several real players. Pictures: `docs/acceptance/*-phone-1108.png`
(phone-portrait for 08, 09, 17). The preview draws plain colours for some materials and has no real avatar animation.

Checks run: `bash tools/check.sh` (type check 0 diagnostics, compile, 98/98 rule tests, Rojo build for lobby and match);
`bash tools/run_regressions.sh` (25/25).

## 1. Contradiction audit (MP4 section 56)

| Rule | Result | How |
|---|---|---|
| One shared pile, four own stations, nothing cracked at the pile | PASS (offline) | `RoundRocks` pickup/deposit/crush gates; fuzz test (audit 1a) |
| One target, one winner, target never sent to clients | PASS (offline) | audit 1, 2; `RockService` replicates ids only |
| Deposited-only automation (machines touch only their own queue) | PASS (offline) | v3 G tests, audit 4 |
| Separate solo and multiplayer stats | PASS (offline) | profile fields and `HuntLedger`; not re-run with real parties |
| Carry / queue / unresolved / rubble are separate fields | PASS (offline) | `counters()` now has `Queue` (tray) and `OnPlate` apart (was F3); HUD shows Basket, Table n/10, unopened, Rubble Bag |
| No old-rule copy in player flows | PASS (offline) | grep of player strings: only DEPOSIT / TABLE guidance remains |
| No debug markers, no dev scaffolding in player flows | PASS (offline) | grep: only code comments (REPLACE markers for future meshes) |
| No invented asset ids, no durability | PASS (offline) | grep; ids come from `MeshCatalog` / upload tools, no durability anywhere |

## 2. Rules audit (docs/m5/RULES_AUDIT.md): three real findings fixed
- F1 `RoundRocks.crush` now catches every machine up to the hit time first and returns those results (a rock finished earlier is paid before a winning hit).
- F2 `RoundRocks.removeMember(userId, now)` catches machines up before returning rocks; `RockService.leave` passes the clock and applies the results. Rule: work already due counts, anything not yet due goes back to the pile.
- F3 `counters().Queue` is the tray only (max 10) and `OnPlate` is 0/1.
The three tests moved into the default run. NOT VERIFIED: the same paths with real clients and network timing.

## 3. Milestones and passes

| Milestone / pass | Done | Evidence | Status |
|---|---|---|---|
| MP4 M1 interaction (action button, prompts, camera, arrows) | Contextual PICK UP / BASKET FULL / DEPOSIT / HOLD TO CRUSH, arrow to own table | 07, 08, 09 | PASS (offline); touch feel NOT VERIFIED |
| MP4 lobby and quarry (private arena, pile, tables) | Kit-built lobby, one pile, four stations | 01, 06 | PASS (offline) |
| MP4/5 M3 UI system | One panel look across Shop, Collection, Settings, Results | 12, 13, 14, 17 | PASS (offline); small notes below |
| MP4 M4+5 machines, hopper sale, geode, tool animation | Machines run on the deposited queue, hopper sells rubble, geode opens on the plate | 10, 11, 17 | PASS (offline); sound and animation feel NOT VERIFIED |
| MP5 pass 1: sign text, lobby HUD scope, stale messages | Signs fitted; no Table card in the lobby after return | 01, 18 | PASS (offline) |
| MP5 pass 2: compact collection and display cabinets | Owner cabinet and collection zone | 03, 04 | PASS (offline); placement save/rejoin NOT VERIFIED |
| MP5 pass 3: one Upgrades counter, data-driven catalog | Counter with selected preview, catalog in Shop | 02, 12 | PASS (offline) |
| MP5 passes 4-6: quarry art, live station work, Shop, reveal | Station shows rock, tool, tray, machine | 06, 09, 10, 11, 16 | PASS (offline) |
| Records boards | Boards in the lobby | 05 | PASS (offline); the preview shows empty boards, live data NOT VERIFIED |
| Start Hunt countdown, reveal, Results | Countdown card, "found it" banner, results with processed / earned / sold / bag | 15, 16, 17 | PASS (offline) |

## 4. Brief V7 section 16 checks
A spawn, B alcoves, C collection, D upgrades, E courtyard, F quarry, H scope: PASS (offline), pictures above. G processing: PASS
(offline) for the picture; five collected, five deposited, five ordinary resolutions are covered by rule tests (audit 1, 8), not a
Studio run. I Shop: PASS (offline). J guidance: PASS (offline) (basket-full text is replaced after deposit, see 09). K devices:
phone-1108 and phone-portrait rendered; real devices NOT VERIFIED. L progress safety: PASS (offline) (save-faults, 5 cases).
M reveal identity: PASS (offline). N performance: perf mock budgets PASS; four real players with machines NOT VERIFIED.

## 5. Notes from the picture review (no change made)
- 09 portrait: the second toast wraps to three lines and is tight but not cut.
- 17 portrait: the engine's Jump circle sits over SKIP TUTORIAL (it is Roblox's own control, drawn by the preview; check on a phone).
- 12 Shop: "Equipped now" sits close under "2 dmg per hit" in the detail card.
- 05 records: boards look empty because the scene has no leaderboard data.
- 18 lobby after return: no Table card; the Party card in that scene is the party state, not a table leftover.
No overlap, clipped text, giant marker or stale HUD needed fixing.

## 6. Owner Studio test checklist (plain words)
1. Join the lobby on your phone. Check the signs read well and nothing is cut off.
2. Walk to Upgrades and Collection. The prompt should appear once and the camera should stay comfortable.
3. Put a geode in your cabinet, leave, rejoin. It should still be there.
4. Start a solo hunt. Pick up 5 rocks. Basket full should show. Walk to your table and tap DEPOSIT.
5. Hold CRUSH by hand. Watch the rock, the tool, the Table counter and the rubble count agree.
6. Equip a machine. Let it run while you fetch more rocks.
7. Find the geode. Check the reveal, the results numbers and that the specimen is in your collection.
8. Return to the lobby. No Table card, no arrow, no old message.
9. Try a party of 2 to 4 friends: one pile, separate tables, one winner. Leave mid-hunt with a rock on a machine and check the others can still win.
10. Open Shop, Collection and Settings on your phone in both directions.

# Master Prompt 7, Pass E (2026-10-10)

Everything is OFFLINE (Lune + preview renderer). Nothing was run in Studio, on a device, or with real players.
Pictures: `docs/m7/acceptance/NN-<step>-phone-1108.png` and `-pc.png`, made by the preview scene `loop`
(`bash tools/preview/render.sh loop --set step=<name> --device phone-1108`; one full simulation per step through the real
server and client: lobby spawn, Start Hunt solo, countdown, aim, glimpse, full, deposit, crack, output, machine, reveal,
results, rematch, lobby, collection, cabinet, hud). Every step prints `LOOP PASS <step>` only if its own checks held
(reticle state, basket lip, context, material notice on screen, no stale HUD / basket model / cinematic camera / free cursor,
specimen really in `DisplayAssignments`). Checks: `bash tools/check.sh` clean (120 rule tests), `bash tools/run_regressions.sh`.

## Fixes made in this pass
- First person: the avatar's own forearms and hands were drawn as a skin-coloured block over the lower right of the table view
  (`CameraMode.fadeTool` only ghosted them by distance, and the hand sat just outside the fade range). They are now never drawn
  locally in first person; the local work tool still swings onto the rock (`StationView`). `src/client/CameraMode.luau`.
- The "grey slab" in the centre of the old table picture is the real rock on the plate seen from 3.2 studs. It is meant to be
  there (it is what you crack); only the arm block was a defect. Rock-on-plate size was NOT changed.
- Lobby HUD: a one-member party left over from a solo hunt showed "Party 1 / 4, Waiting for <you> to ready" in the lobby after
  returning. The objective banner now shows a party only with 2+ members. `src/client/ui/Hud.luau`.

## Section 15 checklist

| Item | Result | Evidence |
|---|---|---|
| Spawn view has a clear Start Hunt focal point; seller and perimeter secondary | PASS (offline) | 01-spawn |
| Three destinations with different silhouettes, no large buildings | PASS (offline) | 01-spawn, docs/m7/lobby |
| Materials and foliage one kit; lamps do not compete with signs | PASS (offline) | 01-spawn; real lighting NOT VERIFIED |
| No long dark alcove wall; real slot capacities supported | PASS (offline) | 15-cabinet, docs/m7/lobby |
| World geodes show volume, cavity, shell thickness | PASS (offline) | 15-cabinet, docs/m7/geode |
| Shop has a large preview and connected facts | PASS (offline) | docs/m7/ui (not redone here) |
| Zero-specimen Collection intentional; populated grid and selection flow; labelled capacity | PASS (offline) | 14-collection (populated, "Owned 1 / 500, Gallery 0 / 20 slots"); empty state in docs/m7/ui |
| Start Hunt shows only real solo/party actions and members | PASS (offline) | 13-lobby (no leftover party banner after the fix), 12-rematch |
| First-person cursor/menu ownership on desktop, touch, controller; close input does not trigger the world | NOT VERIFIED | rules tested (`m6 input`, `m7 modal stack`); `fp` scene menu open/close PASS; real mouse unlock, touch, gamepad need Studio/device |
| Tutorial guidance does not cover signs or stay at full emphasis | PASS (offline) | 01-spawn, 13-lobby; long browsing behaviour NOT VERIFIED |
| Records unavailable in Studio handled honestly; live read tested separately | PASS (offline) for the Studio state; live read NOT VERIFIED | docs/m7/lobby records pictures; needs a published server |
| Saved progress intact; Studio 0/30 defaults not treated as data loss | PASS (offline) | save-faults regressions; real saved profile NOT VERIFIED |
| One pile, one hidden target, owned queues, one winner/specimen | PASS (offline) | 03-aim, 11-results ("Solo find", one specimen); rule tests incl. conservation fuzz |
| Pickup / deposit / tool contact / output / reveal / placement demonstrated | PASS (offline) | 03 aim, 04 glimpse, 05 full, 06 deposit, 07 crack (hammer head on the rock), 08 output (Material discovered), 09 machine (Table 2/10, Machine running), 10 reveal, 15 cabinet |
| Rejoin / rematch / respawn clear listeners, viewmodels, prompts, effects, HUD | PASS (offline) for return and rematch; rejoin and respawn NOT VERIFIED | 12-rematch (new round, no results card, no basket model, first-person camera), 13-lobby / 16-hud (no hunt cards, no free cursor, no Scriptable camera); `loop` scene checks |
| Every claimed asset exists in the running scene; every claimed path was checked | PASS (offline) | the `loop` scene runs the real code; the preview draws plain colours for some materials, no avatar animation |

Tests added: `tests/test_m7_lifecycle.luau` (any modal close order restores play exactly once; a duplicate close is harmless; the
reveal's cinematic and modal keys leave a normal first-person state in either order). Record conservation:
`tests/test_v3_loop.luau` (random pickups, deposits, crushes, machines, resets and a leaver) still passes. Regression scenes
`loop:output|machine|reveal|rematch|lobby|cabinet` were added to `tools/run_regressions.sh`.

Known limits: the first-person stroke is a local copy of the tool (the avatar arm stays at rest), so how it looks with a real
R15 rig and animations is NOT VERIFIED. 12-rematch shows a bright plate because the preview lights an empty plate.
The preview cannot show the geode reveal's full-screen overlay, only the plate opening.

## Owner Studio checklist for this build (plain words)
1. Join. Look around with the mouse or your thumb: no body, arm or big brown block should cover the screen.
2. Walk to START, UPGRADES and COLLECTION. Open and close each menu. Closing must not swing or pick anything up.
3. Start a solo hunt. Aim the dot at a rock, pick up 5. The basket edge shows at the bottom of the view.
4. Walk to your table, deposit. Hold to crush: the hammer comes down on the rock and it breaks. You get a "Material discovered" note.
5. Equip a machine, deposit rocks, walk away: the table counter drops while you fetch more.
6. Find the geode: watch the opening, then Results. Tap REMATCH (or leave): no old results card, empty basket, camera back in your eyes.
7. Return to the lobby: no table card, no arrows, no "Party 1 / 4" banner. Open COLLECTION, place the new geode, walk to your cabinet: it stands there.
8. Leave and rejoin: the geode is still on the cabinet and your rubble and cash are unchanged (a Studio test shows 0 and SAVES OFF; that is not data loss).
9. Try on a phone and a PC; with a friend, check one pile, separate tables, one winner.

# Master Prompt 8 acceptance (2026-10-10)

OFFLINE only (Lune + preview renderer). Nothing was run in Studio, on a device or with real players. Pictures:
`docs/m10/acceptance/NN-<step>-pc.png` and `-phone-1108.png` (scene `loop`, 16 steps, every one printed `LOOP PASS`, 0 game errors).
Checks: `bash tools/check.sh` (0 diagnostics, 154 rule tests, builds), `bash tools/run_regressions.sh` (45/45).

## Fixes in this pass
- Lodge interior too dark: the project Lighting is shared by the lobby and every hunt, so it was left alone. New client module
  `src/client/LodgeLight.luau` blends Ambient / OutdoorAmbient / ExposureCompensation toward a warm fill only while the camera is
  inside the lodge box and restores the exact original values outside (the hunt pictures are unchanged). Server lodge lights are
  stronger (wall lanterns, bay lanterns, two hall fills, plus two side-aisle fills: 16 point lights, no shadows), and a thin
  translucent sand wash lies just over the kit floor (`FloorWarmWash`, below the rugs) so the paving reads warm stone. No bloom or
  colour-effect change. Real Roblox brightness is NOT VERIFIED (the preview lights approximately).
- Lobby first person showed the resting hammer at the lower right: the corner tool copy (`CarryGlimpse.placeRest`) now shows only
  inside a hunt (`State.Match ~= nil`); the lobby shows nothing.

## Matrix A to O
| Row | Result | Evidence |
|---|---|---|
| A Fresh join, first-person camera, no accessory in view, Start Hunt clear, menu cursor | PASS (offline) | 01-spawn (no hammer, no arm block), 16-hud; real mouse/touch NOT VERIFIED |
| B Destinations, signs, coherent materials, quiet lights | PASS (offline) | 01-spawn, signs scene; lighting feel NOT VERIFIED |
| C Solo and party, four-member limit, private arena | PASS (offline) | 02-countdown, smoke:party; real multiplayer NOT VERIFIED |
| D One pile, neutral rocks, no identity leak | PASS (offline) | 03-aim, rule tests |
| E Five-rock transfer, deposit, queue | PASS (offline) | 04-glimpse, 05-full, 06-deposit, conservation fuzz |
| F Manual processing, one resolution, interruptions | PASS (offline) | 07-crack, 08-output; real timing/feel NOT VERIFIED |
| G Supported machines | PASS (offline) | 09-machine; no manual duplicate by rule tests |
| H Ordinary discovery and sale | PASS (offline) | 08-output; sale in rule tests |
| I Target, reveal, one winner, stats | PASS (offline) | 10-reveal, 11-results; cancellation grant by rule tests |
| J Collection, preview, cabinet placement | PASS (offline); rejoin NOT VERIFIED | 14-collection, 15-cabinet |
| K UI states, no blank panels | PASS (offline) | 11, 14, ui_v2 renders, layout check in regressions |
| L Input and devices | NOT VERIFIED | pc and phone-1108 rendered; controller, touch and real mouse need Studio or a device |
| M Rematch, return, respawn cleanup | PASS (offline) for rematch and return; respawn NOT VERIFIED | 12-rematch, 13-lobby |
| N Concurrency and recovery | PASS (offline) | rule tests, save-faults; real network timing NOT VERIFIED |
| O Performance, four players | PASS (offline, mock budgets); real four-player and phone frame rate NOT VERIFIED | perf and perf-round regressions |

## Owner Studio checklist for this build (plain words)
1. Join. The lodge should look warm and bright, the floor like sandstone, and no hammer in the lower right.
2. Walk the hall: signs, boards and counters readable, no glare or washed-out white lamps.
3. Step outside, then start a hunt: the quarry should look as before (not brighter, not hazier).
4. In the hunt: pick up 5 rocks, deposit, crack by hand, check the small tool at the corner appears only in the hunt.
5. Find the geode: reveal, results, rematch, return to the lobby with no old cards.
6. Place the geode in your cabinet, leave and rejoin: it is still there.
7. Try phone and PC, and with a friend: one pile, separate tables, one winner.
