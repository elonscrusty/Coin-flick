# V3 core loop: pickup, carry, deposit, crush

Owner revision (supersedes every earlier rule about cracking at the pile):
one shared pile of separate rocks -> pick up (basket, 5 max) -> walk to YOUR crushing table ->
deposit -> crush one rock at a time on the plate -> ordinary rocks become rubble, exactly one
hidden target rock holds the geode; whoever finishes crushing it wins. Nothing is hit at the pile.

Status: step 1 (server and shared rules, this document, the world kit) and step 2 (client: pile, basket,
tray and plate visuals, contextual controls, HUD, tutorial, preview scenes) are done offline. Neither is
tested in Studio. Section 5 lists what step 2 built and what only Studio can confirm.

## Section 1: Source map (where things were, where they live now)

| Concern | Before V3 | Now |
|---|---|---|
| Rock records and target | `src/shared/MatchCore.luau` (`Pile` ids, HP table, `TargetId` picked at creation) | `src/shared/RoundRocks.luau` (one record per rock: `State`, `Carrier`, `Station`, `Hp`; `TargetId` chosen once, server only). `MatchCore.luau` and its tests are deleted. |
| Pile layout and exposure | `src/shared/Pile.luau` (hex columns, `isExposed`, `remove`) | Same file, kept. Added `isPickable` / `pickableIds` (exposed AND layer <= `Config.Carry.ReachLevels`, so no climbing), `restore` / `restoreTo` (rocks returned by a leaver), `stacks` / `setStacks` (reconnect sync). Rock id = layout index (opaque, round-scoped; says nothing about the target). |
| Interaction targeting | `src/client/PileView.luau` (`autoTarget`, `validTarget` by `isExposed`, hold-to-crack `strikeTick`) | Same file for now with a temporary stub: targets pickable rocks and sends `RockAction("Pickup")`. The client agent rewrites targeting, prompts and the basket, tray and plate visuals. |
| Strike remote | `Net` event `Strike(roundId, rockId)` -> `MatchService.onStrike` -> `MatchCore:enqueue` (pile damage) | REMOVED from `Net.luau`, `MatchService` and the client. Replaced by `RockAction(action, roundId, rockId?)` handled only by `src/server/RockService.luau`. No remote can damage a pile rock. |
| Reward resolution | `MatchService.step` (profile rubble per `Cracked`, `finishRound` on `Found`) | `RockService` applies each result to the profile (rubble, stats, onboarding) and calls the unchanged `MatchService.finishRound` path (ledger, `Profiles.hold`, reveal, results, idempotent award key `matchKey:round`). Saves, ledger, teleport paths are untouched. |
| Machine processing | `MatchCore.tickMachines` batches that reserved pile rocks near a bay (`Config.MachineRules`) | `RoundRocks.tickMachines`: a machine takes rocks from ITS station queue only, one at a time (`Config.Machines`, seconds per rock = `BatchSeconds / RocksPerBatch`). `Config.MachineRules` removed. Models still built by `src/server/MachineModels.luau` at the bay behind the owner's table. |
| Storage rule | `MatchCore.check` blocked a strike before damage when the bag was full | `RoundRocks.tryStart`: one ordinary-result slot is reserved before ANY rock goes on the plate; no room means nothing starts for any rock. Ordinary consumes the slot, the geode releases it. |
| Party transitions | `MatchService.startRound / leaveMatch / finishRound`, `PartyService`, `MatchPlace` (Teleport) | Same entry points. `startRound` builds a `RoundRocks` through `RockService.newRound`; `leaveMatch` calls `RockService.removeMember` (rocks go back to the pile); `MatchService.rejoin` and `Sync` resend `Init`. |
| World | `WorldBuilder.buildArena` (4 machine bays, spawns, hoppers) | Same, plus `src/server/StationModels.luau`: four crushing tables on a circle (`Config.Station.Radius`), spawns moved inside the ring in front of each table. Machine bays stay behind the tables. |
| UI / tutorial | `Hud.luau` action button (`HOLD TO CRACK`), `Results`, `Config.Tutorial`, `Profiles` tutorial steps | UNCHANGED text in this step except a stub. Client agent: new action states, counters, basket, queue and plate UI, party briefing, tutorial steps (see "Client work left"). |
| Equipment rigs | `src/client/ToolAnim.luau`, `MachineView.luau`, `EconomyService` held tool | Unchanged. Client agent: hammer swings over the table plate, carry basket on the avatar, stow the tool while carrying. |
| Tests | `tests/test_rules.luau` (pile strike rules), `tests/test_machines.luau` (claims) | `tests/test_rules.luau` (pile geometry, reach, restore, geode rolls), `tests/test_v3_loop.luau` (acceptance A to K). |

## Section 2: Rules (what the server enforces)

All rules live in `src/shared/RoundRocks.luau` (pure, tested) and are applied by `src/server/RockService.luau`.
Tuning: `Config.Carry` (Capacity 5, PickupInterval 0.45, PickupRange 8, ReachLevels 3), `Config.Station`
(Radius 25, QueueCapacity 10, DepositRange 10, CrushRange 9, DepositInterval 0.25), `Config.Handhelds`
(tool damage and rate, unchanged), `Config.Machines` (seconds per rock = `BatchSeconds / RocksPerBatch`),
`Config.Tiers[x].Rocks / HP`, `Config.Tutorial` (12 rocks, geode among crushed rocks 2 to 6).

- One record per rock: `Id` (pile layout index, opaque, round-scoped), `State` (`InPile`, `Carried`, `Queued`,
  `Processing`, `ResolvedOrdinary`, `ResolvedGeode`), `Carrier` (basket owner), `Station` (tray owner), `Hp`.
  The target is drawn once, uniformly, when the round is generated (`TargetRng`), lives only in the server
  core, and is never rerolled. The practice round decides the geode when the N-th rock (N = 2 to 6) is CRUSHED,
  so picking up or depositing can never end it.
- Pickup: round id, phase, membership, cadence 0.45 s (+0.12 s slack), rock state `InPile` (a second picker gets
  `Gone`), basket < 5, rock reachable from the mound edge (`Pile.isPickable`: exposed and layer <= 3), xz range
  from the SERVER-read position. The rock leaves the pile. No rubble, no Unopened change.
- Deposit (own station only, derived from membership, no station id in the request): range to the own table,
  basket not empty, tray not full. Moves the basket in order as far as the tray (10) allows; the overflow stays
  in the basket and the reply says how many moved and how many are left.
- Crush (own station only): range, cadence from the equipped tool (`Handhelds.Rate`, damage `Handhelds.Damage`).
  A station whose machine is installed AND running ignores hits (`Automatic`). The first hit moves the next
  queued rock onto the plate; multi-HP rocks need several hits; the finishing hit resolves it.
- Machines: `tickMachines` runs every Heartbeat for all stations. A machine takes rocks from ITS tray only, one at
  a time, never reads the pile or another station. Several rocks finishing in one tick are resolved in
  completion order (ties by station index). Pausing a machine freezes its rock; the hand tool then works on the
  same plate (never both at once). Practice rounds never run machines.
- Rubble storage: before ANY rock goes on a plate, one slot is reserved (`Reserved`), whatever the rock is. No
  room: `StorageFull`, nothing starts, queue and progress are kept (machine shows `Full`). Ordinary result: the
  reservation becomes the rubble. Geode: the reservation is released, no rubble. The profile is the source of
  truth for free space (`RockService.refreshSpace` before every action and every step), so selling resumes work.
- Geode completion: exactly one `Found` (the phase leaves `Searching` inside the same call, every later action
  gets `NotSearching`), all machine timers are cleared (queued machine work is invalidated), the winner is the
  station owner even if they are away collecting, others keep the ordinary rubble they already earned and get
  nothing else. `MatchService.finishRound` is unchanged: ledger, save hold, reveal, results, idempotent award key.
- Departure (return to lobby, disconnect, `RockService.leave`): plate rock, tray and basket go back to the pile
  near the abandoned table (`Pile.restore`, an edge column with room, so the rock is reachable), `Hp` reset to
  full (progress on the plate rock is DISCARDED, the returned rock is indistinguishable from an untouched one),
  reservation freed. Resolved rubble stays with the player, nothing is reversed or duplicated. The target is
  therefore always recoverable. A character reset drops only the basket (`dropCarried`); the tray stays on the table.
- Round-scoped ids: every action carries the round id; a request from an old round gets `StaleRound` (silent).
  A rematch builds a fresh `RoundRocks` (new layout seed, new target, empty baskets and trays).
- Counters: `Unopened` (all unresolved rocks, only drops when a rock is crushed), `Pile` (rocks lying in the pile),
  `Carrying` x of 5 per member, queue count per station. Rubble y/capacity is the profile (`Profiles.rubbleTotal / capacity`) and is
  never mixed with the others.
- Security: the old `Strike` remote is gone from `Net`, `MatchService` and the client. `RockAction` is the only
  gameplay remote; actions are whitelisted, any request faster than 33 per second is dropped, replies are
  rate limited, the player must be alive with a root part, membership comes from `MatchService`'s own tables,
  tool and machine are re-checked against `EquipmentOwned` on every action.

## Section 3: Protocol (for the client)

All gameplay messages ride the existing `MatchEvent` RemoteEvent (server to client) and the new `RockAction`
RemoteEvent (client to server). Round ids are plain numbers (`Init.Round`); every message carries `Round` and the
client must drop messages whose `Round` is not the current one.

### Client to server: `RockAction(action, roundId, rockId?)`

| action | arguments | server answer on failure (`RockReply.Reason`) |
|---|---|---|
| `"Pickup"` | roundId, rockId (a pile rock the client targets) | `Gone` (someone else got it), `BasketFull`, `Unreachable` (too high, climb not allowed), `TooFar`, `BadRock`, `NotSearching`, `NotMember` |
| `"Deposit"` | roundId | `TooFar` (not at your own table), `BasketEmpty`, `QueueFull`, `NotSearching` |
| `"Crush"` | roundId | `TooFar`, `Automatic` (machine running), `QueueEmpty`, `StorageFull`, `NotSearching` |
| `"ToggleMachine"` | roundId | none (silently ignored without a machine) |

`TooFast` and `StaleRound` are never answered. Send `Crush` repeatedly while the button is held, at the tool's rate
(`1 / Config.Handhelds[tool].Rate`, hold-repeat tools like the jackhammer have `Hold = true`) and `Pickup` at most every
`Config.Carry.PickupInterval` (0.45 s). The client sends NO position, station, damage, target flag or timestamp.

### Server to client (all via `MatchEvent(kind, payload)`)

- `"Init"` (also on reconnect and after `MatchAction("Sync")`): pre-V3 fields `Key, Round, Tier, Seed, Tutorial,
  Center, Phase, EndsAt, SearchStart, Members, Machines` plus
  - `Rocks` (total rock count), `MaxHp`
  - `Stacks`: array by column index of rock-id arrays (bottom first): the exact pile now. Build `Pile.new(Rocks, tier.RockSize,
    tier.Radius, Seed)` then `pile:setStacks(Stacks)`.
  - `Removed`: ids not in the pile (carried, queued, on a plate or resolved), kept for old code.
  - `Stations`: array of station views (below). `Tables`: array of `{ Index, Position, Owner }` (`Owner` = user id, 0 = inactive
    table). `Counts`: `{ Unopened, Pile, Carrying, CarryCapacity, Queue, QueueCapacity }` (global ones; per member in `Stations`).
  - `Members[i].Station` = that member's table index. `Machines[i].Bay` = the same index.
- `"Rocks"` (batched, at most 10 per second, only when something changed): `{ Round, Ev, Stations, Counts }` plus the
  legacy empty `Hits` / `Res` and `Removed` (= pickups). `Ev` is an ordered list; apply in order:

| `Kind` | fields | meaning, what to draw |
|---|---|---|
| `Pick` | `UserId, Id` | rock `Id` left the pile (`pile:remove(Id)`) and flies into that player's basket (carry prop shows count) |
| `Return` | `UserId, Id, Col` | a leaver's rock is back in the pile: `pile:restoreTo(Id, Col)`, rebuild that column and its neighbours; pop it back with a short arc |
| `Deposit` | `UserId, Ids` | those rocks left the basket and now sit in that player's input tray, in order (slot 1 is next); animate basket to tray |
| `Start` | `UserId, Id, Duration?` | rock `Id` moved from the tray to the plate (`Duration` = seconds a machine needs, nil for hand tools); draw it centred on the plate. Sent before that rock's first `Hit` / `Done` |
| `Hit` | `UserId, Id, Progress` | a hand hit landed, `Progress` 0..1: show hairline cracks, wider cracks and chips, then the break (animation never resolves a rock) |
| `Done` | `UserId, Id` | ordinary rock finished: subdued split, rubble drops into the output tray, queue advances, tiny counter bump |
| `Found` | `UserId, Id` | the geode rock finished (the `"Found"` message and the reveal follow in the same second) |

  A hand rock gets a `Start` without `Duration` at its first hit; a machine rock gets one with `Duration`.
  `Stations` is a full, self-healing snapshot taken at the same moment: for each active member
  `{ UserId, Index, Basket = {ids}, Queue = {ids}, Current = id?, Progress = 0..1, Machine = id?, Tool, State }`
  with machine `State` = `"None" | "Running" | "Paused" | "Full"`. The client derives every rock's state from
  it: in `Stacks` = InPile, in a `Basket` = Carried by that member, in a `Queue` = Queued, `Current` = Processing,
  none of these = resolved. Render other players' baskets and trays too (they are public); the target never appears
  in any field before the end.
- `"RockReply"` (only to the acting player, at most ~6 per second, skipped for `TooFast` and `StaleRound`):
  `{ Round, Action, Ok, Reason?, Moved?, Left?, Queue? }`. Deposit success carries `Moved, Left, Queue` so the toast can say
  "Deposited 3, 2 still in your basket"; `QueueFull` becomes "Tray full: crush some rocks first".
- `"Machines"` (unchanged shape): `{ Round, List = { { UserId, Bay, Id, State } } }`. `"Phase"`, `"Members"`, `"Found"`, `"Reveal"`,
  `"Results"`, `"Left"` are unchanged. `Toast` carries "Rubble bag full! Sell rubble at a hopper." (at most every 4 s).

### Button states (one contextual main button; the nearest relevant task wins)

Inputs the client knows: phase, `Stations` (own basket and queue, `Machine`, `State`), own table position
(`Tables[Members[me].Station].Position`), pile rocks near the avatar, profile `Rubble` / `Capacity`. Use the same ranges as the server
(`Config.Carry.PickupRange`, `Config.Station.DepositRange` / `CrushRange`, xz distance); the server has the final say.

| Situation | Label | Action sent | Notes |
|---|---|---|---|
| Phase is not `Searching` | none / waiting | none | countdown, reveal and results disable it |
| Near the pile, a pickable rock in range, basket < 5 | PICK UP ROCK | `Pickup(rockId)`; holding repeats every 0.45 s | exactly one restrained yellow outline on the rock the server will validate (nearest pickable, facing preferred) |
| Near the pile, basket full (5/5) | TAKE TO TABLE | none | toast "Basket full: take rocks to your table", arrow to own table |
| At own table, basket not empty, tray has room | DEPOSIT ROCKS | `Deposit` | partial: show the `RockReply` counts |
| At own table, basket not empty, tray full | HOLD TO CRUSH (rocks are queued) | `Crush` | never discard; the basket keeps the overflow |
| At own table, manual tool, tray or plate not empty | HOLD TO CRUSH | `Crush` at the tool rate while held | hammer swings onto the plate; jackhammer vibrates over it |
| At own table, manual tool, bag full and nothing on the plate | RUBBLE BAG FULL: SELL AT HOPPER | none | the server would answer `StorageFull`; rocks and progress are preserved |
| At own table, machine running | MACHINE RUNNING (DEPOSIT ROCKS if the basket is not empty) | `Deposit` only | `Crush` is ignored by the server; `State == "Full"` shows the bag-full message instead |
| At own table, nothing carried, tray and plate empty | COLLECT ROCKS | none | arrow to the pile |
| At the sell hopper | SELL RUBBLE | existing prompt | only when the profile has rubble |
| Too far from the task that matters (carrying: the table; empty: the pile) | MOVE CLOSER | none | arrow to that place |

Another player's table shows progress but never accepts your actions (the server derives the station from you, so
tapping near it does nothing). Hide or stow the cracking tool while carrying; show it again at your table.

### What the client must render (step 2)

1. Pile: individual readable rocks (at least 10 silhouettes), one Model per rock with an opaque id, interaction bounds part,
   no fused facade; layout from `Pile` + `Stacks`; reveal rocks as the mound shrinks; no invisible blockers.
2. Basket on the avatar with 1 to 5 neutral miniatures (supported rigs only, fallback for non-R15), pickup scoop and arc,
   no hammer out while collecting.
3. Station (built by `StationModels`, named parts in its header comment): tray rocks at `InputTray` attachments `Slot1..Slot10`
   (slot 1 = next), plate rock at attachment `Plate`, rubble in `OutputTray`, basket docked at `Dock`, `Stand` = where to frame the
   camera, `MachineFeed` = where a machine takes rocks. Crack stages from `Hit.Progress`. Tables of unused slots carry a NOT IN USE tarp.
4. HUD: Unopened (`Counts.Unopened`), optional Pile (`Counts.Pile`), Carrying x/5 (own `Basket`), Rubble y/cap (profile, separate icon),
   own station queue and current-rock progress. Party briefing: "Collect rocks from one shared pile. Carry them to your station and
   crack them. First station to reveal the geode wins." Say that a machine's owner wins even while away collecting.
5. Geode reveal and results: unchanged paths; hidden cavity and crystals are step 2 polish.
6. Machines: `MachineView` is fed by the `Start` / `Done` events (the temporary `PileView` stub forwards them as `Claimed` / `Cracked`
   signals); step 2 should feed it from `Stations` directly and animate at the owner's table.

### Protocol additions in step 2

- `ShopAction("SellAtHopper")` (client to server): the HUD's SELL RUBBLE button. The server finds the nearest hopper to the
  character itself (12 studs, xz) and runs the same sale as the hopper prompt; without a hopper in range it only toasts.
- `Profiles.Onboard` gained `PickedUp` and `Deposited` (additive keys, set by `RockService` on the first accepted pickup / deposit).
  Migration: a save with `Cracked` or `Geode` set (old meaning: cracked at the pile, or practice finished) gets both set so the
  new first two steps never repeat. `Cracked` now means "first ordinary rock crushed at a table". `onboardDone` is unchanged.
- No other remote or payload changed.

## Section 4: Verification (offline only, NOT Studio)

See `docs/STATUS.md` for the live PASS / BLOCKED table. Acceptance A to K are covered by `tests/test_v3_loop.luau`:
A pickup grants no rubble; B 5/5 cap; C partial deposit; D crush only at the own table, nothing at the pile, ordinary rocks resolve once;
E two pickers one owner, no foreign deposits or hits; F four stations equal distance; G machine only crushes its own queue and never the pile;
H target picked or queued early stays hidden and wins only when crushed; I leaver's rocks return, target stays winnable; J rubble-full pause is the same for every rock
and keeps records and progress; K geode ends the round, machine work is invalidated, rematch is fresh and old ids are rejected.
L (tutorial without stale lobby hints) is covered offline by the `rocks-views` L views and the hint gating in `Main.client.luau` (section 5); M (avatar rigs) and N (party, shop, collection, gallery) need Studio.

## Section 5: Step 2 client (offline only, NOT Studio)

Files: `src/client/PileView.luau` (pile render, targeting, outline, contextual action `PileView.context()`, hold loop),
`StationView.luau` (tray, plate, fracture, rubble, hand tool at the plate, geode opening, nameplate highlight),
`CarryView.luau` (basket on the avatar, pickup arc, scoop, tool stowing), `GuideArrow.luau` (floor arrow, table / pile label,
edge chip when the target is off screen), `Anim.luau` (one shared animation scheduler, `Anim.scale`), `ToolAnim.luau`
(`scoop`, `face`), `ui/Hud.luau` (counters, queue pill, action states), `Main.client.luau` (hints, markers, RockReply toasts),
`src/shared/GeodeModel.luau` (`rockShell`, `rockLook`, `grit`).

- Pile: one Model per rock, 12 silhouettes in the order of the owner's sheet `docs/refs/assets/06_rock_fracture_kit.png`
  (wedge, oval, squat boulder, oblong, tall lump, flat stone, angular chunk, rounded cube, asymmetric river stone, small barrel,
  triangular stone, lumpy boulder), each 1 to 3 Parts (blocks, squashed spheres, one cylinder; no WedgeParts, they render
  badly in the preview). Silhouette, tint (mid greys), yaw and a small offset come from `GeodeModel.rockLook(id, seed)`, never from
  server knowledge of the target. Rocks inside the mound are 1-part fillers, surface rocks full models with an invisible `Bounds`
  PrimaryPart (queryable only when pickable). Decorative grit is separate, smaller, duller, not queryable. Every part is anchored
  and `CanCollide = false` (so the mound cannot trap or launch anyone; avatars walk through it: a visual compromise, a collision
  group would need server registration). The uploaded `CT_Rocks_RockShell_A..D` meshes are not used.
- Outline: one `Highlight`, only while the button reads PICK UP ROCK, on the rock `ctx.Target` (nearest pickable in reach,
  facing preferred, or the tapped rock) which is exactly the id sent to the server.
- Context (`PileView.context`): sell hopper (with rubble) > own table (DEPOSIT / HOLD TO CRUSH / MACHINE RUNNING / COLLECT ROCKS /
  BAG FULL) > pile (PICK UP ROCK / TAKE TO TABLE) > MOVE CLOSER; GET READY and SECURING outside Searching. Ranges are the
  server's minus a margin. The press latches its action (deposit never turns into a crush while still held). Pickup repeats every
  0.45 s + 0.03, crush at the tool rate. E and gamepad R2 use the same path.
- Basket: wooden crate with metal straps and arch handle, follows UpperTorso (R15), Torso (R6) or HumanoidRootPart (other rigs)
  every frame, 1 to 5 grey miniatures of the exact rocks held (from `Stations[i].Basket`, public). The hand tool is hidden
  locally (Transparency) unless the owner is near their table with an empty basket. The picked rock flies in an arc, shrinking,
  into the crate; pickups play a short right-arm scoop.
- Station: queued rocks on the tray slots, current rock on the plate, fracture from the server's `Progress` (hairline seams,
  wider seams plus drifting pieces and chips, split into rubble in the output tray, a one-hit rock still shows its crack for 0.26 s),
  own nameplate and strip highlighted yellow, other tables show the same progress. The local avatar turns to the plate and swings
  when a Crush is sent (`ToolAnim`); remote avatars swing on their `Hit`. The crack lands ~0.3 s after the swing starts.
  Jackhammer: arm vibration (ToolAnim) plus the plate rock shaking. Machine rocks ride from the tray to `MachineFeed` and
  `MachineView` animates the machine from the same `Start` events. Rubble ring: 12 chunks per table. Chips capped at 24.
  Geode: on `Found` the plate rock is replaced by a hollow geode (`GeodeModel.build` + `frontHalves`) whose halves part over
  1.8 s with light inside (generic specimen until the Reveal arrives, then rebuilt from the real one); no coloured crystal is
  ever shown before the win. The reveal screen waits for the opening (`StationView.fxRemaining() + 1.8 s`).
- HUD: separate cards for Rubble Bag (y / cap) and Carry Basket (x / 5) with their own icons and bars (top left), "Unopened rocks"
  with a rock icon in the objective, own-table queue pill with current-rock progress above the dock, contextual action button with
  a key hint (E / RT, none on touch), guide arrow and edge chip. Party briefing, practice text, shop machine text and results
  text no longer mention cracking at the pile.
- Tutorial hints follow the activity: pick up, walk to the highlighted table, deposit, crush, keep going. Arena hints show only
  during Countdown / Searching / RewardPending, the sell / gallery / shop hints only in the lobby (or results); the gallery hint no longer
  appears during a hunt. The sell step is optional when the player never had rubble (geode first).

Verified offline (preview mock, not Studio): `tools/preview/scenes/rocks-views.luau` renders views A (pickup arc), B (5/5 +
TAKE TO TABLE + arrow), C (deposit, queue, hammer at the plate), D (COLLECT ROCKS), G (machine running while at the pile),
H (geode opening on the plate), L (tutorial hints in order), W (four stations), pile on phone-1108 and phone-portrait;
`check_layout.py` 0 problems on the sweep; regressions in `docs/STATUS.md`.
Needs Studio: real R15/R6/other rigs (basket follow, scoop, hammer swing at the plate, avatar turn), Motor6D and ToolAnim feel,
collision (avatars walk through the mound), real lighting and Highlight look, touch hold feel, performance with four tables and
80 rocks, sounds, and the real multi-client races.
