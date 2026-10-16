# M5 rules audit: RoundRocks and HuntLedger

Scope: adversarial offline tests of the pure round rules in `src/shared/RoundRocks.luau` and the results
bookkeeping in `src/shared/HuntLedger.luau`, against brief V6 sections 21, 25, 46, 48 and 56 and brief V7
section 0. No `src/` file was changed. Tests: `tests/test_m5_rules_audit.luau` (18 default cases + 3 known
failures).

How to run:

```
bash tools/setup_tools.sh
bash tools/test.sh                         # default run: 92 passed, 0 failed at the time of writing (18 new + 74 existing)
CTR_AUDIT_FAILING=1 bash tools/test.sh     # also runs the 3 known failures (prefixed KNOWN-FAIL)
```

What this proves and what it does not: the tests drive the real modules in Lune with a fake clock, so they
establish conservation, ownership, idempotence and the arithmetic of the results figures (brief section 48,
"logs or meaningful tests"). They do NOT exercise `RockService`, `EconomyService`, `Profiles`, remotes,
multiple real clients or Studio. Where a finding depends on how the server calls the module, that is said
below and was checked by reading `src/server/RockService.luau`, not by running it.

## Verification matrix

| # | Scenario | Initial state | Action | Expected | Result |
|---|---|---|---|---|---|
| 1a | Every rock resolves once (fuzz) | 4 members (2 machines, jackhammer), Quarry tier, 30 seeds | 900 random ops: pickups, junk ids (0, -1, 1.5, NaN, inf, "3", nil), deposits and hits at own and foreign tables, machine ticks with random gaps, machine swap/unequip, pause/resume, storage set to 0..40, basket resets, up to 2 leavers, stale-round requests; then the last member plays the round out | After every op: each rock in exactly one place matching its state, pile count = InPile, broken = resolved, rubble = ordinary rocks, at most one geode and only the target, winner iff geode, resolved rocks never change state; round always ends with the target found | PASS |
| 1b | Requests after the find | Target found by hand while a machine has a queue | 20 rounds of machine ticks, hits, deposits, pause/resume | Every action `NotSearching`, no rock changes state, no rubble | PASS |
| 2a | Two hand tables, same timestamp | Target on table 1's plate path, ordinary on table 2 | Both finishing hits arrive with the same clock value | One `Found`, winner 1, table 2 gets `NotSearching` and its rock stays unresolved | PASS |
| 2b | Hand win vs machine completion, same instant | Target by hand at table 1, machine at table 2 due at the same time | Both orders (hand first, tick first) | Exactly one `Found`, winner 1 | PASS |
| 2c | Four machines due on one long frame | 4 machines, target in one queue, 15 seeds | One 30 s tick | One `Found`, it is the last result (no work after it), right winner | PASS |
| 2d | Machine rock due before a winning hit | Machine rock finishes at t, winning hand hit at t + 10 ms, no tick in between | `crush` then `tickMachines` | The machine rock that finished first is paid | KNOWN-FAIL F1 (module only; mitigated in RockService) |
| 3a | Target holder leaves while carrying it | 3 members, target in a full basket | `removeMember` | Target back in the pile at full HP; another member wins | PASS |
| 3b | Target holder leaves with it queued | Target queued behind an Industrial Crusher paused on a full bag | `removeMember`, more ticks | Earned rubble kept, nothing extra paid, target back in the pile, winnable | PASS |
| 3c | Everyone but one leaves, each holding rocks | 4 members with trays, plates and baskets, 10 seeds | Members 1-3 leave one by one | Invariants hold after each leave; member 4 wins | PASS |
| 3d | Reset then leave, duplicate notifications | Tray 4, basket 3 | `dropCarried` twice, `removeMember` twice | Exactly 7 rocks return, none twice | PASS |
| 3e | Leaver whose machine already finished the target | Target on the leaver's machine plate, due before the leave, not yet ticked | `removeMember`, then tick | Leaver wins (machine finished first) or a documented rule says otherwise | KNOWN-FAIL F2 (real server path) |
| 4a | Hand tool and running machine on one rock | Machine running, steel hammer, HP 2 | Hit while running; pause; hit; resume | Hit refused (`Automatic`); paused plate finished once by hand; machine never finishes it again; rubble = cracked | PASS |
| 4b | Machine swap / unequip mid-rock | Hydraulic Press working a rock | Swap to Industrial Crusher, tick 1 ms; unequip; hand-crush | No instant completion after a swap; the hand needs the full HP (no hidden machine damage); resolves once | PASS |
| 5 | Sale while a rock is on the plate | 1 free slot, rock started (slot reserved) | Storage refreshed to 10 mid-rock, then finish | Reservation kept through the sale; one rubble; space 9 | PASS |
| 6a | Full bag with the target next in a machine queue | Space 0, target first in queue | 5 ticks, then a sale to space 1 | Nothing starts (`Full`), target stays queued, no winner; after the sale no back-dated instant finish; then `Found`; the geode pays no rubble and releases its slot | PASS |
| 6b | Storage of exactly N | 10 queued, space 4, hand and machine | 30 hits / ticks | Exactly 4 rubble, space 0, 6 still queued | PASS |
| 7a | Rematch after a win | Old round won and ended, machine still owned | New core (round 2); old core keeps ticking; old-round requests on the new core | New members empty (basket, tray, plate, rubble, cracked, reservation), unopened = total, no winner; old core produces nothing; old round id rejected; new round winnable | PASS |
| 7b | Fresh ledger per round | Closed ledger | Late crush and sale after close; new ledger | Closed ledger ignores late events; new ledger all zero | PASS |
| 8a | Results figures | 2 members (machine + hand), member 2 starts at 29/30, random sales during processing, 12 seeds; a sale after the results froze | Profile stand-in wired like RockService/EconomyService (storage refreshed after every grant and sale) | Processed = rocks finished, Earned = ordinary rocks finished, Processed - Earned = 1 only for the winner, SoldCash = RubbleSold x rate, bag = start + earned - sold, cash = start + sold cash, bag never over capacity, snapshot bag figures = profile | PASS |
| 8b | Ledger junk input | - | NaN / negative / inf / fractional counts and bag fields | Ignored or floored, never negative | PASS |
| 25 | Queue counter bound | Tray 10, then one rock moved to the plate | Deposit 1 more, read `counters(uid)` | Queue counter <= QueueCapacity | KNOWN-FAIL F3 (field semantics; HUD unaffected) |

## Known failures F1-F3: FIXED in the final acceptance pass

All three are fixed and their tests are in the default run: `RoundRocks.crush` ticks machines to `now` first and returns their results (F1); `removeMember(userId, now)` catches machines up before resetting, and `RockService.leave` passes the clock and applies the results (rule: work already due counts, anything not yet due returns to the pile) (F2); `counters` reports `Queue` (tray only, max 10) and `OnPlate` (0/1) separately (F3). The text below is the original finding.

## Original findings

### F1. `crush` does not catch machines up first (module contract)

Test: `KNOWN-FAIL audit 2: a machine rock due BEFORE a winning hand hit still pays`.

Cause: `RoundRocks.crush` resolves the hit immediately. If another station's machine finished a rock at time
t and the winning hit lands at t + 10 ms before anyone calls `tickMachines`, the winning hit sets the phase to
`RewardPending` and the later tick returns nothing, so the rock that finished first is never paid.

Status: the live server already avoids this. `RockService` (Crush branch, about line 161) calls
`core:tickMachines(t)` before `core:crush(...)` ("Machines first, up to this instant"). So this is a gap in the
module's own contract, not a live bug.

Suggested fix (optional, makes the module safe on its own): at the top of `RoundRocks.crush`, after `gate`,
call `RoundRocks.tickMachines(self, now)` and return its results together with the hit's results; or document
in the module header that callers must tick machines to `now` before `crush`.

### F2. Leaving discards a machine result that was already due (real server path)

Test: `KNOWN-FAIL audit 21: a leaver whose machine already finished the target (not yet ticked) is not robbed of the win`.

Cause: `RockService.leave` calls `core:removeMember(uid)` directly, and `removeMember` -> `resetMember` returns
the plate rock to the pile with its progress discarded. If the member's machine finished the rock (its
`Complete` time is before the leave) but the Heartbeat step has not run since, the finished rock goes back to
the pile unresolved. For an ordinary rock the member loses one earned rubble; for the target the member loses
a win the machine had already completed, and someone else can win it later. The window is at most one
scheduler step (about 16 ms), so it is rare, but brief section 46 asks for "a documented server rule based on
confirmed state" when departure intersects processing.

Suggested fix (server, `src/server/RockService.luau`, `RockService.leave`): before `removeMember`, run
`RockService.apply(m, m.Core:tickMachines(os.clock()))` (the same catch-up the Crush branch does), and only then
remove the member; if that tick found the geode, the normal reward path handles it. Alternatively give
`RoundRocks.removeMember(self, userId, now)` a `now` and tick machines inside it. Either way, document the rule:
"work already due at the moment of leaving counts; anything not yet due is returned to the pile".

### F3. `counters(uid).Queue` can read 11 / 10

Test: `KNOWN-FAIL audit 25: the station queue counter never exceeds its capacity`.

Cause: `RoundRocks.counters` reports `Queue = #tray + (1 if a rock is on the plate)` next to
`QueueCapacity = Config.Station.QueueCapacity` (10), while `deposit` only limits the tray
(`free = QueueCapacity - #m.Queue`). With 10 queued and one moved to the plate, a deposit legally adds one more,
and the counter pair reads 11 / 10.

Impact: no rule is broken (the tray holds 10, the plate holds 1, matching `StationModels` Slot1..10 + Plate).
The live HUD draws `#st.Queue / cap` from the station view (tray only), and `RockService` calls `counters()`
without a user id (Queue 0), so players do not see 11 / 10 today. It is a trap for any future UI that shows
the per-member counter pair.

Suggested fix: in `RoundRocks.counters`, report the tray and the plate separately
(`Queue = #m.Queue`, new `OnPlate = 1/0`), or rename the combined value (`Pending`) and pair it with
`QueueCapacity + 1`. Update `docs/V3_LOOP.md` (Counts fields) with the choice.

## Observations (no failing test)

- Same-instant machine ties are broken by station index (`tickMachines`, strict `<` over `Order`). When the
  target finishes first in that order, another station's ordinary rock due at the very same timestamp is not
  paid (case 2c ends with `Found` as the last result). One winner holds; the tie rule is arbitrary but
  deterministic. Worth one line in `docs/V3_LOOP.md` so nobody "fixes" it into a double award.
- `HuntLedger.snapshot` creates an empty row for an unknown user id, even on a closed ledger. Harmless
  (all zeros), noted only because the ledger otherwise promises to be read-only after `close`.
- `RubbleSold` can be larger than `RubbleEarned` (sales include material carried over from before the hunt).
  That is by design (HuntLedger header) and case 8a checks the bag equation that makes it honest; the results
  screen should keep labelling the two figures separately.

## Not covered here (next verification steps)

- Server wiring: `RockService` storage refresh timing, `EconomyService.sellRubble` during processing, award
  save path (`AwardLedger`), and that results read the same ledger the round wrote. Needs a server-side test
  harness or a Studio play test.
- Multi-client concurrency (two real clients hitting at once, contested pickup over the network, disconnect
  mid-request). Module-level ordering is covered above; the network path is UNVERIFIED (BLOCKED: no Studio /
  multi-client run in this environment).
