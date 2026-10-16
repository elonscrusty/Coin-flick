# m9 performance: leak check over full rounds (offline mock)

Numbers come from the preview mock (Lune running the real server and client modules). They are NOT device frame
rates. Real memory and FPS are BLOCKED until measured in Studio / on a phone.

Scene: `tools/preview/scenes/perf-round.luau`
`bash tools/preview/run_scene.sh perf-round --device phone --set rounds=5 --set hunt=100 --set json=1`
(about 12 real minutes for 5 rounds; not part of `run_regressions.sh`).

Setup: one Meteor party of 4 (Crusher, Crusher, Press, Auto Cracker), each member also picks up from the shared pile and
deposits (queues stay full) for a 100 s hunt, then the reveal, results and the return to the lobby (`MatchAction Return`).
Five rounds back to back; the scene samples the same point (hunt start) and after clean-up.

| Round | Start: instances alive | Start: parts | Start: connections | Hunt cost (mock ms/frame, all callbacks) | After clean-up: alive / parts / conns |
|---|---|---|---|---|---|
| 1 | 10,841 | 6,103 | 145 | 22.8 | 5,836 / 2,735 / 143 |
| 2 | 10,854 | 6,103 | 146 | 22.1 | 5,836 / 2,735 / 143 |
| 3 | 10,854 | 6,103 | 146 | n/a | 5,836 / 2,735 / 143 |
| 4 | 10,854 | 6,103 | 146 | n/a | 5,836 / 2,735 / 143 |
| 5 | 10,854 | 6,103 | 146 | 22.6 | 5,836 / 2,735 / 143 |

Also flat: active tweens 0, live Sounds 2 at hunt start and 1 after, waiting task threads 4-6.

Result: PASS. No growth in instances, parts, connections, tweens, sounds or per-frame cost across rounds. The only
difference between round 1 and later rounds (+13 instances, +1 connection, a `PropertyChanged:Value` listener) is a one-time
first-use object and does not grow after round 2.
Static review of `MachineView`, `Effects`, `GeodeView` connections found nothing to fix (GeodeView disconnects its
input connections on `Destroying`; MachineView's one RenderStepped is created once).

Not measured: real device frame time, GPU, memory, network, StreamingEnabled. The mock's per-frame figure is dominated by
the 4-machine, 4-player simulation and is only useful for comparing runs. The new reveal crystals add about 14 kit parts
per half only while the reveal is open (destroyed with the viewport on close); the earlier `perf` scene is unchanged.
