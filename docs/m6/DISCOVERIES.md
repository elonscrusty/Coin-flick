# Material Discoveries, hunt HUD and sell clarity (Master Prompt 6, sections 7 to 10)

Offline only (Lune + preview mock). NOT Studio-tested. Pictures: `docs/m6/disc/` (phone-1108 and phone-portrait).

## What was built

| Area | Where | Notes |
|---|---|---|
| Categories | `Config.Materials`, `Config.MaterialOrder` | Common Stone 80, Quartz Fragment 15, Metallic Specks 5. Name, description, colours, look. No value, price, capacity or speed fields (a test asserts that). |
| Choice | `shared/Materials.pick(salt, round, rock)` | Pure integer hash. `RoundRocks.new` draws a server-only salt AFTER the target, so the target draw is unchanged. Not affected by tool, player or target. |
| Reveal | `RoundRocks.finishRock` | Material is added to the Cracked result and the Done event only when that rock completes. Rock records, station views, counters and earlier events carry nothing. The geode result has none. |
| Profile | `Profiles` `Materials = { Found, Counts }` | Added by `reconcile` (normalize), no schema bump. Unknown future ids are kept in the save and ignored by the UI. `Profiles.recordMaterial(player, key, id)` is idempotent per `match:round:rock` key. |
| Pipeline | `RockService.apply` | Counts for the crushing player only (hand or machine). One `MaterialFound` message per apply batch, only for first-time categories. No client-reported discoveries. |
| Notice | `Hud.materialNotice` | "Material discovered — Quartz Fragment", quiet toast, bursts merged into one line, at most one per `Config.MaterialNoticeSeconds` (2.2 s). Repeats are silent; the count is in Collection. |
| Output chips | `StationView.styleChip` | Quartz: solid pale marble chips. Metal: grey stone with 4 bright specks. Common unchanged. Looks only. |
| Collection | `ui/CollectionPanel` Materials tab, `ui/MaterialThumb` | "Materials discovered: n/N", silhouettes + "Unknown material", found entries show name, thumbnail, description, count. Specimens, Index, Stats unchanged. |
| HUD | `ui/Hud` | Objective "Find the geode"; sub line "Rocks left in pile: N" (`Counts.Pile`, source only). Old text "N unopened rocks" counted every unresolved rock (pile, baskets, trays, plates), so it was not progress toward the geode. Timer from server `SearchStart`/`SearchEnd` (sent in Init and Phase; no per-frame remote, 0.2 s UI tick), stops at the find. Results shows "Hunt time" (informational, nothing persisted). |
| Sell | `EconomyService.sellRubble`, `Hud` | Preview card on the SELL action: "Sell 9 rubble / for $18" from the profile's server-computed `Rubble` and `RubbleValue`. Receipt toast "Sold 9 rubble for $18" built from the server's returned count and total. Double taps within 0.6 s are dropped silently (no duplicate grant, no false "empty" message). Empty bag: no sell action; a direct attempt says "Your rubble bag is empty. Nothing to sell." |

## Checks (offline)

- `tests/test_materials.luau`: 8 rule tests (weights, determinism, distribution within 1.2 points, core equals pick, tool change cannot reroll, target not special-cased, no leaks before completion, record/normalize defaults).
- Scene `materials` (in `tools/run_regressions.sh`): real server hunt of 30 cracks; counts add up to cracks and rubble, each first-time category announced once, no cash change from cracking, duplicate key ignored, one sale pays once and a double tap pays nothing.
- `bash tools/check.sh` zero diagnostics; `tools/run_regressions.sh` 26/26 (hud-scope and accounting still pass).

## Not done / honest limits

- Not Studio-tested; the preview draws no real chips, sounds or SurfaceGuis. Quartz and speck chips were not rendered close-up.
- Material names are shown only in the notice and Collection; the tray chips are the only in-world cue.
- Sell: the in-world hopper signs were left as they are (they already say SELL RUBBLE); no new bin mesh or stone-to-coin symbol was added. The preview card and receipt are HUD only.
- Carry/queue emphasis uses the existing hierarchy (queue card only at the table, carry card in the hunt); no change was made and it was not re-audited for this brief.
- A save failure follows the existing Profiles policy (the discovery lives in the profile like rubble); no separate recovery path.
- First-person camera, reticle and context actions belong to the other helper; no overlap files (CameraGuard, PromptArbiter, ActionRules, PileView, CarryView, StationModels) were edited.
- Dev tooling: `tools/preview/scenes/disc.luau` (pictures), `lib/ctr.luau` `stopWhen` option.
