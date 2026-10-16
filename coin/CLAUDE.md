# COIN FLICK: rules for every helper

Roblox tap-to-flip-coins game. Rojo + strict Luau. **The server decides everything** (flip result, cash, buys). Clients send intents only ("I tapped coin N"). Read `SNAPSHOT.md` first (code map), then `MASTER-PLAN.md` in the project files (backlog).

## carter (the owner)
- Not a programmer. Plays on a phone. Windows PC. GitHub: elonscrusty.
- Talk to him: caveman MAX (fewest words), like he is 10, exact taps, choices as short options with a pick marked ⭐. Don't ask small stuff; pick a default and say which.
- Code, commits and docs: normal prose.

## Proof rules
- Never say "fixed" or "done" without proof.
- Every change gets a Lune test in `tests/specs/` that passes.
- Every visual change gets player-view pictures checked by carter's runner (`C:\Users\myson\agent-runner\run.bat`, run by the PC helper). Goal: strict score 8/10 or better, 0 gaps, 0 overlaps. Phone view too.
- Fix the whole structure, not single spots. One batch = one push = one check.

## Hard rules
- Never publish, buy anything, or change security settings. Publish only when carter says "publish". Game stays PRIVATE.
- Robux: never make up product ids or prices (all 0 = SOON until carter gives them). Show odds before any random buy. **No gambling** (no betting, no Lucky Spin, no random eggs/boxes, no double-or-nothing).
- No picking heads or tails. No flags. Nothing scary or gross. Style: chunky low-poly, flat-shaded, bright cartoon, always sunny, animated and flashy.
- Never print API keys. Saves must never be lost (session-locked DataStore).
- Find The Pet (repo `elonscrusty/Crack-the-rocks`) is a port source only: adapt, never copy whole files; new DataStore names; never its Robux ids.
- Max 2 helpers at once, no sub-helpers inside threads. Max Players must be 8 when publishing.
- Only the cloud helpers edit game code. The PC helper only pulls, runs Studio and the runner.

## Build, test, run
```sh
lune run tests/run.luau                       # all tests (must be 0 failed)
stylua --check src tests                      # CI uses stylua 2.6.0 BUILT WITH THE LUAU FEATURE:
                                              #   cargo install stylua --version 2.6.0 --locked --features luau --force
selene src                                    # lint (shadowing and unused vars warn = CI fails)
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --sourcemap=sourcemap.json --definitions=globalTypes.d.luau --no-strict-dm-types src   # strict types, 0 errors
rojo build default.project.json -o CoinFlick.rbxlx
```
- Cloud container: GitHub releases are blocked; tools are in `/tmp/ctr-tools` (lune, rojo, luau-lsp) or `cargo install`. selene needs the roblox std, so test with a temp `selene.toml` using `std = "luau"`.
- Live link on carter's PC: `Start COIN FLICK live.bat` (git pull + `rojo serve`, port 34872) in the "crack butt holes" folder. carter connects: Plugins tab, Rojo, Connect. New code reaches Studio after `git pull` in `C:\Users\myson\coin-flick`.
- Tell carter **not to press Play until you say "ready"**.
- Studio-only 🧪 test buttons: +1M, FILL, RARE, MEGA (charges, then flips), AWAY (fake 3 h away), WIPE.

## Git
- Work on your own branch, PR into the merge-point branch named in your brief. CI must be green (stylua, selene, luau-lsp, Lune, rojo build).
- Commit messages end with the attribution lines your session gives you. No model names in code.
- Don't touch files another helper owns; agree ownership by message first.

## When your job ends
Update all three, short:
1. `SNAPSHOT.md` (repo root): new/changed modules, remotes, data fields.
2. `MASTER-PLAN.md` (project files): move items to ✅ / 🟡 and say what is proven.
3. `HANDOFF.md` (project files): where things stand, next step, open questions for carter.
Then close your thread.
