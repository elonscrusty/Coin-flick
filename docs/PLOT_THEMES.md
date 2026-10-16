# Plot themes + world decoration (Phase 2)

Built on a side branch off `picture-fixes`. Nothing here touches World, Plot, Tables or CameraView yet.

## What is in
- `src/shared/Util/PlotThemes.luau` (tested): Meadow, Beach, Candy, Castle, Space. Each reset gives the next look
  (reset 0 Meadow, 1 Beach, 2 Candy, 3 Castle, 4 Space, then it loops). From reset 4 on the player may pick any
  unlocked look (`PlotThemes.resolve(resets, picked)`, `PlotThemes.canPick`). Space unlocks at reset 4, because the
  Phase 4 cat pet is tied to that.
- `src/shared/Util/DecorLayout.luau` (tested): deterministic spots for the empty world. Nothing inside a yard, on a
  path, the plaza or the spawn, and no two props overlap.
- `src/server/Builders/PlotDecor.luau`: parts only, no asset ids. Tree, boulder, bench, crate and lamp shapes are
  ported from Find The Pet's `KitParts` (pieces only) and recoloured bright. Beach, candy, castle and star pieces are new.
  `PlotDecor.yard(make, parent, plotCFrame, theme, resets)` and `PlotDecor.world(make, parent)`.

## Wired in (2026-10-16, carter: "build the map now")
- `Plot.build` takes a theme: pad, border, fence, posts, name sign colours, then `PlotDecor.yard` (floor tiles, corner pieces, side props; grows each reset).
- `Tables.buildTable`: `PlotThemes.resolve(profile.resets, nil)`; sets model attribute `PlotTheme`. Table colours still follow `Config.TableLooks`.
- `World.decorate`: old forest ring and flower patches replaced by `PlotDecor.world`. Plaza, paths and gap trees stay.

## Still open
- Picking a look after reset 4: needs a saved `plotTheme` in the profile, a remote that checks `PlotThemes.isUnlocked`, a rebuild, and a UI button. `resolve(resets, picked)` already handles it. Not built.

## Proof
Lune 109 pass, luau-lsp 0 diagnostics, stylua clean, rojo build ok. No Studio pictures yet: runner pictures (desktop + phone) are the next step.
