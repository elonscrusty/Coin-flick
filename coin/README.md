# COIN FLICK

A Roblox game with one action: **TAP**. Tap your coins, watch them flip,
earn cash on heads and hat points on skulls, buy more coins, get a helper
guy, fill your table and RESET it for a permanent bonus.

Built with [Rojo](https://rojo.space) and strict Luau. The server decides
everything; the client only ever says "I tapped coin N".

## What's in the first build

- Your own table (up to 8 tables per server, so set Max Players to 8)
- Tap a coin: it jumps, spins, bounces, sparkles and pops a number
- Heads = cash, skull = hat points (hats come in step 2)
- Shop: More Coins (up to 10), Bigger Coins, Lucky Heads, Faster Flips
- 1 Helper Guy who walks around your table flipping coins, and also
  earns while you're away (half speed, at most 2 hours)
- RESET when the table is full: lose cash + upgrades, keep helpers and hats,
  get +50% cash forever and a new table look
- Saves: session-locked, retried, saved on leave, on autosave and on shutdown.
  In Studio it uses a throwaway test store, so real saves are never touched.
- Studio-only test buttons (🧪 +1M / FILL / WIPE) to test fast

## Try it in Roblox Studio (needs a computer)

1. Download `CoinFlick.rbxlx` (from the latest **Actions** run, under *Artifacts*).
2. Open it in Roblox Studio.
3. Press **Play**.

## For developers

```sh
rokit install                     # tools: rojo, lune, selene, stylua, luau-lsp
rojo serve                        # live-sync into Studio with the Rojo plugin
lune run tests/run.luau           # automated tests (game rules + saving)
stylua src tests && selene src    # format + lint
rojo build -o CoinFlick.rbxlx     # build a place file
```

Layout:

- `src/shared` → `ReplicatedStorage.Shared`: config, types, pure game math
- `src/server` → `ServerScriptService.Server`: systems (saving, tables, shop)
- `src/client` → `StarterPlayerScripts.Client`: tapping, effects, HUD
- `tests/` → Lune test runner + specs for all pure logic

Robux products are placeholders in `src/shared/Config.luau` (`Products`).
Real ids are filled in only from the game owner.
