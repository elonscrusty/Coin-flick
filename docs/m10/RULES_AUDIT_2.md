# Pass 6: server rules and safety audit (offline only, NOT Studio-tested)

Scope: brief V10 sections 2, 21, 22 and matrix rows C, D, E, G, H, I, N, on the real server modules
(`PartyService`, `MatchService`, `RockService`, `EconomyService`, `Profiles`) and the pure rules
(`RoundRocks`, `HuntLedger`, `Materials`). Builds on `docs/m5/RULES_AUDIT.md` (round rules; F1-F3 fixed there).
Every remote name and payload is unchanged.

## How the server is tested offline

`tests/test_m10_server.luau` (run by `tests/run.luau`, so by `tools/test.sh` and `tools/check.sh`) runs each scene in
`tests/server/*.luau` in its own Lune process on the offline Roblox mock (`tools/preview/runtime`). A scene boots the real
server (`Main.server`: remotes, Profiles on an in-memory DataStore, PartyService, MatchService, Economy, Gallery), adds
mock players, and drives everything through the real remotes (`PartyAction`, `MatchAction`, `RockAction`, `ShopAction`,
`CollectionAction`). No client GUI is built (`headless=on`). Each `CASE ... PASS` / `[FAIL] CASE ...` line becomes one
test. The whole run adds about 4 s.

Limits of this harness: one server, remotes delivered instantly and in order, "same frame" means two handler calls
with no simulated time between them; no real network reordering, no real DataStore latency or throttling, no Studio.

## Matrix

| Area (row) | Case | Result |
|---|---|---|
| E/N contention | two players pick the same rock in the same frame: one holder, repeat pickup refused | PASS |
| E/N duplicates | three Deposit requests (two in one frame): each rock moved once, basket empty, queue + n | PASS |
| G | manual Crush refused while the machine runs; resolved records = broken = rubble | PASS |
| I/N | target finished at one table while the other table finishes an ordinary rock in the same frame: one winner; the rock that finished first still pays; duplicate/late `Found` reports for the round change nothing; one specimen, one win, one "hunt played" per member | PASS (was FAIL, bug 1) |
| N | late Crush / Deposit / Pickup after the find leave every record unchanged | PASS |
| C rematch | non-leader StartRematch ignored; leader blocked until everyone taps REMATCH; double tap starts one round; fresh core | PASS |
| C/N leaver | member leaves with the target queued: target and other rocks back in the pile, reachable; the remaining player finds it; one specimen | PASS |
| C party | 4-player limit holds with 4 invites outstanding (the 4th accept after the party filled is refused) | PASS |
| C party | members cannot kick, change tier or start | PASS |
| C party | leader leaves: earliest remaining member leads and can kick | PASS |
| C/N | double Start in one frame: one hunt for the whole party, roster locked | PASS |
| C | locked roster: no invites, kicks or joins mid-hunt | PASS |
| C | member returns to the lobby mid-hunt: out of the round, others keep hunting; cannot start a Solo while the party hunts; may leave the party; arena released and party unlocked when the last one leaves | PASS |
| C/N | double Solo in one frame: one hunt; Solo while hunting refused | PASS |
| C rematch | party leader returns to the lobby on the results screen: the member still there can start the rematch | PASS |
| H/N purchase | tool bought twice in one frame: charged once | PASS |
| H/N purchase | storage and gallery level double tap: one level each, charged once | PASS (was FAIL, bug 2) |
| H | level request for a level other than the next one refused | PASS (new, optional `id`) |
| H/N | purchase without enough cash: cash, ownership and equipped tool unchanged | PASS |
| H/N sale | rubble sold twice: paid once; rubble of an unknown (newer) tier stays in the bag | PASS (was FAIL, bug 3) |
| H/N sale | specimen sold twice: paid once; a specimen with a broken value is refused | PASS (bug 4) |
| saves | old save without Materials / Onboard / DiscoveryRarity, partial Settings and Stats, plus a newer build's tool, machine, tier, mineral, rarity, formation, modifier and levels: loads through the real load path; cash, specimens, displays, ownership and unlocks kept; unknown tool not held, unknown machine not installed | PASS |
| saves | storage / gallery level above this build's tables: biggest known size (stored level kept) | PASS (was FAIL, bug 5) |
| saves | wrong-typed fields (Settings a string, numeric strings, NaN, negative rubble, junk list entries, an owned-but-unknown or known-but-unowned tool, a specimen without Mass) are repaired without losing money or specimens; public view and party view build | PASS (bug 6) |

Existing coverage kept: `tests/test_v3_loop.luau` and `tests/test_m5_rules_audit.luau` (pure round rules: conservation fuzz,
same-instant machine/hand finishes, machine vs hand, storage reservation, leavers, rematch, results figures),
`tests/test_hunt_ledger.luau`, `tests/test_materials.luau`.

## Bugs found and fixed

1. **A duplicate `Found` report awarded a second specimen** (`RockService.apply`, `MatchService.finishRound`). Nothing
   guarded against a second Found result for the same round reaching the server: with the guards removed, the test's
   late Found naming the other player gave that player a specimen too, and stats were counted twice. The pure core only
   ever produces one Found, so this needed a second report (a late callback or a future code path), but the award path
   must hold on its own. Fix: `RockService.apply` applies one Found per round (`m.FoundRound`), and `finishRound` runs once
   per round (`m.FinishedRound`).
2. **Double tap bought two storage or gallery levels** (`EconomyService`). `BuyCapacity` / `BuyDisplay` carry no item id,
   so a repeated request bought the next level again. Fix: a repeat of the same level purchase within 1 s is dropped, and
   a client may send the level it expects (the existing `id` argument, a number); any other level is refused. The current
   client sends no id and is unaffected apart from the double-tap guard.
3. **Selling rubble destroyed unknown-tier rubble for $0** (`EconomyService.sellRubble`). The sale cleared the whole bag
   while only known tiers were priced. Fix: `Profiles.sellableRubble` (known tiers only) prices and removes the sale;
   rubble of a tier this build does not know stays in the bag (it still takes space, as before).
4. **A specimen with a non-number value could crash or pay NaN** on sale. Fix: such a specimen is refused with a message.
5. **Storage or gallery levels above this build's tables fell back to level 1** (`Profiles.capacity` / `displaySlots`),
   shrinking a bag or gallery bought in a newer build. Fix: lookups clamp to the highest known level; the stored level is
   never lowered.
6. **`reconcile` trusted field types.** A table field saved as another type stayed broken (a later `data.Stats.X` crashed),
   numbers saved as strings or NaN stayed, rubble counts could be negative or text, junk entries could sit in the
   specimen and display lists, an unknown tool id could be the held tool, and a specimen without `Mass` crashed the gallery
   render. Fix: tables replaced only when the saved value is not a table; numbers recovered with `tonumber` where possible,
   else defaulted; settings clamped; rubble counts whole and non-negative (unknown tier ids kept); non-table specimens and
   non-string display ids dropped (they cannot be shown or sold); held tool must be known and owned, else the hammer
   (ownership records kept); missing `Mass` filled with 2. `Profiles.reconcile` is now exported for tests.
7. Minor: leaving the server cleared other players' invite cooldowns whose ids contained this player's id as a substring
   (`PartyService`). Fix: exact `from:to` match.

Also added: `MatchService.matchFor(uid)` (server-only lookup used by the offline tests; no remote).

## Not verified / limits

- Studio and live servers: NOT tested. Real network timing (two clients' packets interleaving across frames), DataStore
  throttling and save retries under load, teleport mode.
- The harness runs one server with mock players that have no client; client-side pending states are not exercised here.
- Award durability across a crash between `Ledger.record` and the profile save is covered by the existing `save-faults`
  regression scene, not by this pass.
