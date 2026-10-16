# Performance (offline, mock measurements)

IMPORTANT: every number here comes from the preview mock (Lune on Linux running the real server and
client modules against a fake Roblox API). They are NOT device frame rates and NOT Roblox server
times. Use them to compare one run with another (before / after a change) and to find hot spots.
Real phone FPS, memory and network use are BLOCKED until the owner measures in Studio / on a device
(MicroProfiler, Developer Console, `Stats`).

Run: `bash tools/preview/run_scene.sh perf --device phone --set seconds=20 --set json=1`
(or `bash tools/run_regressions.sh --only perf`). The scene is `tools/preview/scenes/perf.luau`; the
mock profiler is `tools/preview/runtime/mock/profile.luau`. Payload sizes use a serialisation
estimate (numbers 3-9 bytes, strings length + 2, nested tables), not the real wire format.

## Scenario

16 players in one server, each with the biggest gallery (20 slots, 20 specimens on display). Four of
them form a party and hunt a Meteor pile (1600 rocks, HP 10) with a machine each (Crusher, Crusher,
Press, Auto Cracker) and also hand-strike the whole time. The other 12 stay in the lobby.

## Results (this batch, phone device profile)

| Measure | Before | After | Notes |
|---|---|---|---|
| Parts in Workspace, lobby with 16 full galleries | 10,720 | 7,648 | galleries 9,792 -> 6,720 parts |
| Gallery parts per displayed specimen | 30.6 | 21.0 | tiny model beyond slot 8 (`Config.Gallery.FullDetailSlots`) |
| Lobby idle, all Heartbeat callbacks | 0.006 ms/frame | 0.007 ms/frame | nothing runs per frame in the lobby |
| Meteor hunt: parts in Workspace (16 players) | 13,135 | 10,063 | |
| Client-rendered rock parts (Meteor pile) | 1,622 | 1,622 | exposed shells + hidden core blocks only |
| Machine parts (4 machines) | 263 | 263 | |
| Server step (`MatchService` Heartbeat) | 0.32 ms/frame | 0.35-0.39 ms/frame | within noise; 4 machines, 4 hand strikers |
| HUD action button refresh (`autoTarget`, 5x/s) | 2.8 ms/call | 0.9-1.0 ms/call | cached; the rest is the mock's own overhead |
| Client `PileView` + `MachineView` callbacks | about 0.4 ms/frame (machines out of range, not animated) | 1.1 ms/frame with the camera at the arena | the earlier number did not animate machines; see below |
| MatchEvent, one recipient | 0.95 KB/s | 0.95 KB/s | `Rocks` 0.8 KB/s is most of it |
| ProfileState to the 4 party members | 9.0 KB/s total | 9.0 KB/s | about 1.9 KB per message, 4.7 messages/s |
| All remotes together | 12.9 KB/s | 12.9 KB/s | |

The hunt window ends when the geode is found (here 9.3 s, 244 rocks cracked by machines and hands),
so the hunt numbers are an average over a short, very busy stretch, not a whole round.

## Hot spots fixed (no rule changes)

- `PileView.autoTarget` (called by `PileView.actionState` from the HUD 5 times a second, and every
  frame while holding with nothing selected) walked every rock shell and rebuilt each position from
  the pile layout. Now: rock world positions are cached when a shell is placed, the distance test uses
  plain numbers, and the answer is reused for 0.15 s while the rock set (an epoch counter bumped on
  add / remove / reserve / release) is unchanged and the player barely moved or turned.
- `MachineView.animate`: an idle machine no longer rewrites every belt tile / roller / jaw CFrame each
  frame, and the press plate is only moved when its drop changed.
- Gallery model detail: specimens beyond the 8th in an alcove use `GeodeModel.build{Tiny = true}`
  (one shell ring, at most 3 crystals, no stars). The first 8 keep the shelf model. This removed about
  3,100 parts from a 16-player lobby.

## Not fixed / worth watching on a device

- Settle tweens: every rock that drops after a support is cracked gets a `CFrameValue` + tween
  (`PileView.tweenModel`); the mock spends about 2.2 ms/frame on tweens during a busy Meteor hunt. On
  a phone, check the Developer Console; `Reduced motion` already skips them.
- `ProfileState` is sent several times a second to a cracking player (rubble count) and carries the
  whole light profile (about 1.9 KB). Splitting a tiny "cash / rubble" message out would cut it by
  about 90%; not done because it touches the client state contract.
- 16 galleries are still about 6,700 parts in Workspace. If a low-end phone struggles in a full lobby,
  the next step is building a gallery only while a player is within range (needs streaming checks in
  Studio).
- Machines keep animating within 160 studs of the camera; a Meteor arena with 4 machines costs about
  0.7 ms/frame in the mock.

## What was not measured

Real frame time, GPU load, memory, network latency, StreamingEnabled behaviour and anything on iOS /
Android. Server step time is the mock's Lune time, not Roblox's.

## 2026-10-15 budget check (Find The Pet; offline mock, not device numbers)

`tests/server/budget.luau` (run by `bash tools/test.sh` through tests/test_m10_server.luau) counts what the server
builds and fails when a budget is blown:

| What | Parts | Lights | Budget (parts / lights) |
|---|---|---|---|
| Procedural lobby (stand-in for the hand-built map) | 2,211 | 49 | 3,000 / 64 |
| One hunt arena (`CT_Rocks_Arena_<slot>`) | 1,629 | 9 | 2,200 / 16 |
| One fight island (stand-in; the owner's `ArenaIsland` is not in the repo) | 39 | 0 | 120 / - |

No unanchored parts outside characters in any of them. Three hunts in a row reuse one arena with no growth in
parts, connections or waiting threads; the perf-round scene (4 players, 3 Meteor rounds) shows the same.

Fixed: StreamingEnabled is off, so every hunt arena ever built stayed in every player's world (up to
`Config.Match.MaxArenas` = 6, about 9,800 parts) after a busy spell. Arena slots above `ArenaKeepWarm` (1) are now
destroyed once they have stood empty for `ArenaIdleSeconds` (90) and rebuilt on demand (MatchService.endMatch).

Client per-frame code outside the UI was read for allocations and scans: the always-on loops (PetDisplay,
PlayerDust, WorldFx, NameTag, PromptArbiter, LobbyAmbience, PetFollow's obstacle index) are throttled (5-12 Hz)
or distance-culled, and PetFollow's index drops parts on DescendantRemoving. Nothing clear to fix there.

Needs a phone check in Studio (BLOCKED offline): the hand-built lobby's real part and light count (49 PointLights
in the procedural lobby alone is a lot for low-end phones), FPS in a full lobby, the first hunt start after an idle
arena was taken down (build hitch on the server), and particle load during a hatch show + fight on a phone.
