# CRACK THE ROCKS!

A Roblox party game: up to four friends crack the same pile of rocks. One rock hides a geode.
Whoever finishes cracking that rock wins the geode for their collection. Everyone keeps the
rubble they cracked and sells it for Cash, which buys better tools, bigger storage and tougher
piles with better geodes.

- Design brief: `docs/BRIEF.txt`
- Reference art: `docs/refs/`
- Status and phase plan: `docs/STATUS.md`
- Opening it in Roblox Studio: `docs/OWNER_STEPS.md`

## Build

```bash
bash tools/setup_tools.sh      # rojo, luau-lsp, luau-compile, lune (into /tmp/ctr-tools)
bash tools/check.sh            # type check + compile + rule tests + build
/tmp/ctr-tools/rojo/rojo build default.project.json -o build/CrackTheRocks.rbxlx
```

Open `build/CrackTheRocks.rbxlx` in Roblox Studio and press Play.
