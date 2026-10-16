# Master Prompt 4: private quarry (sections 04, 05, 18-22, 30-34, 54/55)

Offline only (Lune preview renderer). Nothing here is Studio-tested. Pictures: `docs/m4/quarry/*.png`
(phone-1108). Scene options added to `tools/preview/scenes/hunt.luau`: `--set qcam=x,y,z --set qlook=x,y,z`
(camera relative to the mound) and `--set tcam=own|idle --set toff=x,y,z --set tlook=x,y,z` (camera in the
frame of the player's table or the first inactive table; -Z is toward the pile).

## Causes found (confirmed, not guessed)

| Symptom | Cause | Where |
|---|---|---|
| Flat white/pale fragments around the mound base | `GeodeModel.gritPatch` places the `Grit_Patch` kit mesh (one fused sheet of 26 flat scraps, 0.12-0.42 studs thick) 5-12 times, 3.5-5 studs wide, around the pile (called by the client `PileView.scatterGrit`). They are decoration, not rocks, but a pale slab that size reads as a loose rock. A second source: 14 flat `RimStone` slabs built by `ArenaBuilder.buildGround` on the mound pad rim. | `src/shared/GeodeModel.luau`, `ArenaBuilder` |
| Neon cyan/green/violet pad borders, many hazard bands | `Station_FloorPad` kit mesh = dark steel plate with a hazard-stripe border in the `Accent` slot (tinted with the owner colour), plus `ArenaBuilder` painted an owner-colour edge bar and the table's own `COLORS` were the saturated palette cyan/green/violet. | `StationModels.buildKit`, `ArenaBuilder.buildStations` |
| Big red NOT IN USE, dark slab over idle tables | `Tarp` part 7.6 x 4.6 studs over the table top with a red SurfaceGui, shown by `StationModels.setOwner` for every table without an owner; nameplate also set to red `NOT IN USE`. | `StationModels` |
| Machine not "on the table" | Machine bays were a separate 12 x 10 slab at radius 36, 11 studs behind the table pad with a gap, plus an owner plate on the pad edge that faced the table's back (unreadable). | `ArenaBuilder`, `MachineModels` |
| Unequal sale routes | One hopper at the south: tables 1 and 2 were about 21 studs away, tables 3 and 4 about 52. | `ArenaBuilder.buildWorksite` |
| Giant ROCK PILE sign | Client `GuideArrow.set(center, "ROCK PILE", ...)` from `PileView` (not a world part). Client side; see handoff below. | `src/client/PileView.luau:449` |
| Pile shards | Variants 5 (TallLump, 1.2 x 2.7 x 1.2) and 7 (AngularChunk, 1.1 x 2.2 x 1.2) are twice as tall as wide and stuck out of the mound as spikes. The other ten variants are chunky. | `GeodeModel.kitRock` |
| Lime moss everywhere on cliffs | `Moss` slot of the Cliff_A..F meshes is a saturated lime on every ledge. | `ArenaBuilder.buildBoundary` |

## What changed

* **Layout (18)**: tables stay on the radius 25 circle (45/135/225/315 deg, one central mound, `Config.Station` and
  all ranges untouched). Each table has one plain concrete slab 12 x 9.4 (apron 12.8 x 10.2) covering table plus
  stance; the machine bay continues straight behind it (centre radius 32.75, slab 11.4 x 10) so table and machine
  read as one station and the machine fits the station footprint. Nothing stands in the pile-to-table lanes.
  Two identical sell hoppers (south for tables 1-2, north for 3-4, radius 30, on small aprons): every table has
  the same 21.5 stud walk and no obstacle on it. `EconomyService.nearestHopperBody` already picks the nearest.
* **Boundary (19)**: pallet/crate group removed from the west lane; wheel marks removed; moss pulled toward olive
  grey; crane stays on the lower bench, fence and placard stay on the east drop.
* **Floor and pads (20)**: concrete slabs only; no paint on tables' pads; owner identity is the plaque text, a
  muted accent (orange / steel blue / sage / plum, `StationModels.Accents`), a small numbered inset, no glow.
  Bay slab keeps four amber corner brackets only. Neon junction light removed.
* **Inactive tables (20)**: no tarp, no red text; plaque `TABLE n` in dim grey, sign `TABLE n` in grey, lamp off.
* **Pile (22)**: flat grit sheets removed (`GRIT_PATCHES = false`), rim slabs removed, tall variants widened and
  shortened (`kitRock` squash, applied to the body, crack ribbons and bounds). 12 silhouettes kept. Pickability,
  ids and layout are unchanged (`Pile.luau` untouched): every pickable rock is still reachable (tests:
  "every rock is reachable", "pickable rocks ...").
* **Tables (30)**: kit table unchanged; the hazard-striped floor pad is no longer used; sign scaled 1.5 to 1.2;
  all prompt attributes, `Surface`/`Plate`/`InputTray`/`Slot1..10`/`OutputTray`/`DockPad`/`Stand`/`Feed` and the
  `Light`/`Nameplate`/`Sign` carriers are as before. Operating side (-Z) is bare slab for 5 studs.
* **Machines (31-33)**: the same models; they now sit directly behind the table on the extended slab and the
  owner plate moved to the slab's outer side where it can be read.
* **Camera**: `CameraIgnore = true` on decorative parts (cliffs, lamps, props, fence, crane, signs, table
  shield and machine hoods). Floors, pads, the table surface and the invisible bounds are not tagged. The client
  has to honour the attribute (other helper).

## Rule check (21)

Read `RoundRocks` and `RockService`: records have one state and one location, counters are separate
(`Unopened`, `Pile`, `Carrying`, `Queue` count different things; earned rubble is the member's `Rubble` and the
profile bag). No bug found. Added `v3 conservation: random ...` in `tests/test_v3_loop.luau`: 6 seeded random
runs with three players (one hand, AutoCracker, HydraulicPress) over pickups, deposits, crushes, machine ticks,
basket drops, one leaver and bad requests; after every step each record is in exactly one place, state matches
location, pile = total - carried - queued - on plates - resolved, resolved = Broken = sum of members' Cracked,
sum of rubble = resolved ordinary records, a slot is reserved exactly while a rock is on a plate.

## Client handoff (not edited here)

* Remove or shrink the `GuideArrow.set(center, "ROCK PILE", ...)` sign over the mound (PileView.luau:449) in
  favour of the small hint.
* Honour `CameraIgnore` in the camera occlusion code.
* `StationView.nameplate` still recolours own-table Accent pieces yellow; that is fine with the new muted accents.

## Open

* Studio: collision of the 0.3 stud slab step, real camera clipping, hopper prompt range at the new spots,
  sale walk times with real avatars.
* The kit meshes themselves were not changed (no Blender work): the table frame is dark steel, the hopper is
  large; a lighter hopper mesh and a plain concrete pad mesh would be nicer than Part slabs.
* Machine moving parts were only checked as static frames here (Auto Cracker running at 6 s).

## Pass 2 (owner target `docs/refs/assets/16_quarry_placement_target.jpg`; pictures `docs/m4/quarry2/`)

* Rocks: `blender/models/rocks.py` `chunk()` hulls (rounded-cube, 11-26 points, height <= ~1.1 x width), wedge and
  tall-lump silhouettes removed; `GeodeModel.kitRock` scale 1.08 -> 1.22; `GeodeModel.grit` returns small faceted kit
  stones (maxSize >= 0.4) instead of dark flat chips (pickup dust keeps the tiny chip).
* Table: `blender/models/station.py` `table`, `tray_box` (wood bins with steel posts), `plate` (hazard border), shield
  uses the new `GlassClear` slot. `StationModels`: `SIGN_AT` (4.7, 0, 0.2), `TableBody` solid helper, nameplate 1.5 x 0.42.
* Arena: `ArenaKit.cliff` (stepped blocks, replaces the kit Cliff_A..F placement), `woodHopperParts`, `Kit.crane`
  (wooden gantry); `ArenaBuilder` fence rim, hopper placards removed, ledges removed, gantry at (76, bench, -4) (a
  first spot at (66, -30) sat inside the back cliff row), pads 11.6 x 8.8 and 9.6 x 8.9.
* Client: no edits needed (the ROCK PILE billboard and CameraIgnore were handled on main).
