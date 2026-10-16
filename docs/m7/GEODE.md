# Pass C: geode specimens (Master Prompt 7, section 7)

Offline only (Rojo + preview renderer). NOT verified in Studio. Pictures: `docs/m7/geode/` (`before/`, `after-*.png`).

## Cause of the sticker look (found in code, not from the video)
Not a 2D image substitution and not camera-facing parts: every specimen is real geometry. The flatness came from several things together:
1. **Rim too wide and too bright.** `Geode_Rim` spanned 0.74-0.99 of the opening radius (a quarter of it), coloured near-white (236,230,218 lerped up to white) in SmoothPlastic: a thick white ring.
2. **Cavity read as one flat coloured disk.** Crystals were `Glass` (transparency 0.06) over a lining only 22% darkened at gallery detail (`Lod`, which `GeodeModel.example` forced on), with 2 clusters at that detail; Glass washes to a pastel and there was no shadow band between rim and crystals.
3. **Neon white glint cubes** on tips read as stickers/dots.
4. One shell silhouette, one hue swap: all specimens had the same outline and the same cluster.
5. The shell floated 0.12 studs above the stand planks, and `Tilt` was silently ignored by the kit path (early return).
6. Collection thumbnails looked straight at the cavity (-20 degrees yaw) under strong ambient light, so depth never showed.
The Part fallback (used when the kit is not loaded) had the same wide rim, Glass crystals and light flat "Bed" panels.

## What changed
- `blender/models/geodes.py`: three shell shapes (A rounded, B wide, C tall; `Geode_Shell[_B|_C]`, `Geode_Rim[_B|_C]`), deeper shell with real side/back volume, flat underside that rests on the planks, narrow rim (12% of radius) with wandering width and height, dark `Shade` band inside the rim, `Lining` one dark tone, `Druse` (mineral-coloured wall points instead of dark flecks), fewer and larger crystals with clear planes, new cluster `Geode_Cluster_F` (bloom), stand rebuilt a little wider with the specimen resting on the planks (attach `Geode`). Uploaded (ids from the API in `art/meshes/uploaded_ids.json`, `MeshIds`/`MeshCatalog` regenerated).
- `src/shared/GeodeModel.luau`: shell chosen from the seed; clusters arranged by formation (Cluster = main + 2 flankers, Spire = one tall hero + low beds, TwinCore = two spires, HollowBloom = ring around an empty heart), shrunk and clamped to the shell opening; per-crystal-piece brightness steps; crystals SmoothPlastic (Neon only on one step of three for Glowing/Cosmic); no white glints except on glowing specimens; warm-chalk rim; faint fill light (an Attachment on the shell so bounding boxes stay exact); `Tilt` now applies to kit specimens; Part fallback gets the narrow rim, dark lining, SmoothPlastic crystals; `example` varies formation by seed.
- **One source:** `GeodeModel.build` (reveal, results, Collection and inspect thumbnails via `GeodeView`, plate) and the new `GeodeModel.onStand(spec, opts)` (world: kit `Geode_Stand` or a Part stand, specimen rests on the planks, cavity faces -Z). `build` / `example` signatures unchanged. `frontHalves` is fitted to the kit shell the specimen really has (`GeodeModel.shellFit`); `StationView` hinge/glow height uses the model's `CentreY`.
- `GeodeView`: 3/4 turn (-32 degrees), 16 degrees pitch, lower ambient and a side key light so depth reads.
- Uncracked rocks are untouched (`rockShell`); nothing here sees the target before the reveal.
- Preview: `tools/preview/scenes/_geode.luau` (`--set view=front|side|close n= i= yaw=`).

## Not done / limits
- Cabinets (`GalleryService`, `LobbyBuilder`) still call `build`/`example`; moving them to `onStand` is the lobby helper's job. The Studio test of placing, removing and restoring a real earned specimen after rejoin is NOT done (no Studio).
- Preview lighting is an approximation; the fill light and colours need a Studio look. The reveal half-shells' cut-face crystals are still simple blocks.
- Crystal "planes" are flat-shaded hex prisms; no baked ambient occlusion.
