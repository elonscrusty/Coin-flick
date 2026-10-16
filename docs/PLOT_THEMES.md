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

## Hooks for build 2 (after phase 0 passes)
1. `Systems/Tables.buildTable`: `local theme = PlotThemes.resolve(profile.resets, profile.plotTheme)`; use
   `theme.pad / border / fence / post / sign / signText` in `Plot.build` instead of the table look; call
   `PlotDecor.yard(...)` in place of the tree and flower loops. The table keeps its own `Config.TableLooks` colours.
2. `Systems/World.decorate`: replace the forest ring and flower patches with `PlotDecor.world(World.makePart, folder)`.
3. Picking (later): save `plotTheme: string` in the profile (`ProfileSchema` clean-up: keep only ids from
   `PlotThemes.ids()`), a `PickPlotTheme` remote that checks `PlotThemes.isUnlocked`, then rebuild the table.

## Proof
Offline tests pass. No Studio pictures yet: the visual check on the runner (phone view) is still to do after the hooks go in.
