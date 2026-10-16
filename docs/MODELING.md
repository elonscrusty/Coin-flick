# Modeling: Blender -> Roblox asset pipeline

Every kit asset from the owner's 14 reference sheets (`docs/refs/assets/*.png`, brief
`docs/BRIEF_V5_ASSET_KIT.txt`) is modelled in Blender by a Python script, previewed, compared with the
sheet, exported as FBX, uploaded as a Roblox Model and loaded at boot by `src/server/MeshService.luau`.
The approach is the one proven in the owner's other project (SWARM): one mesh per piece, colours set in
game from a generated catalog.

Status: built and previewed offline; uploads recorded in `art/meshes/uploaded_ids.json`. NOT verified in
Studio (the owner has to look at `ReplicatedStorage.Assets.Kit` in a play test).

## Tools

| Step | Command |
|---|---|
| list models | `/tmp/bpyenv/bin/python blender/build.py --list` |
| build + preview | `/tmp/bpyenv/bin/python blender/build.py --only Station_Table,Tool_Jackhammer --samples 12` (`--only 07` = a whole sheet, `--no-render` = FBX + manifest only) |
| compare with the sheet | `python3 tools/ref_compare.py Station_Table` or `--sheet 07` / `--all` -> `art/compare/<Name>.png` |
| upload | `ROBLOX_USER_ID=20194281 python3 tools/upload_meshes.py --only Station_Table` (or `--only 07`) |
| regenerate Luau tables | `python3 tools/gen_mesh_catalog.py` (the uploader runs it) |
| verify | `bash tools/check.sh` |

`bpy` (Blender 5.x as a Python module) lives in `/tmp/bpyenv` (`python -m venv /tmp/bpyenv && /tmp/bpyenv/bin/pip
install bpy pillow` on Python 3.11+ if it is missing). A full build of every model takes about 8 minutes on 4 CPUs
(Cycles, 3 views each); use `--only`.

Outputs:
- `art/meshes/<Name>.fbx` one FBX per model, one mesh node per piece (preview-only pieces left out).
- `art/meshes/manifest.json` per model: sheet, pieces (slot, material, centre offset, size, tris, pivot, anim),
  palette, bounds, attach points, reference crop. Legacy `CT_Rocks_*` glb entries (tools/gen_meshes.py) are kept.
- `art/previews/<Name>.png` 3/4 + front + side views on the sheet's cream background.
- `art/compare/<Name>.png` reference crop on top, render below.
- `src/shared/MeshIds.luau` (all ids, 0 = not uploaded) and `src/shared/MeshCatalog.luau` (piece data).

## How to add an asset

1. Pick the sheet module in `blender/models/` (one module per sheet: `station.py` = 07, `rocks.py` = 06,
   `tools.py` = 08) or add `blender/models/<topic>.py`; new modules are picked up automatically.
2. Write a builder and register it with the reference crop (pixel box on the 1536 x 1024 sheet):
   ```python
   @register("Gallery_Pedestal", "04", "Pedestal, origin floor centre.", ref=("04_gallery_kit.png", (x0, y0, x1, y1)))
   def pedestal(m):
       m.slot("Concrete").box((2, 2, 3), loc=(0, 0, 1.5), bevel=K.BEVEL_BIG)
       m.slot("SteelLight").bolt((0.8, -1.0, 2.6), normal=(0, -1, 0))
       m.attach["Specimen"] = (0, 0, 3.0)
   ```
3. Build with `--only Gallery_Pedestal`, run `tools/ref_compare.py Gallery_Pedestal`, open the PNG and iterate
   until the silhouette, proportions, colour blocking and key details match the sheet.
4. Upload, check `bash tools/check.sh`, commit the script, FBX, manifest, previews, compare PNG, ids and the
   generated Luau files. Update the table below.

## Conventions (`blender/ctrkit.py`)

- **Units / axes**: 1 Blender unit = 1 stud. Author with +Z up and the FRONT facing -Y. Export maps Blender
  (x, y, z) to Roblox (-x, z, y): Roblox +Y up, front -Z. Viewer's left on the sheet = Blender -X = Roblox +X.
- **Origin**: floor centre (bottom centre) of the asset. Exceptions are documented in the builder's note and the
  catalog `Origin` field (hand tools: the grip; jackhammer: the handlebar centre).
- **Pieces = materials**: a piece holds exactly one colour slot + Roblox material (`m.slot("Wood")` returns the
  shared piece for that slot). Anything that animates, is swapped, toggled or attached gets its own named piece
  (`m.piece("Bit", "SteelLight", anim="Plunge", pivot=(x, y, z))`); pivot is a model-space point.
- **Colour**: meshes carry no textures, UVs or vertex colours. `MeshCatalog` gives each piece its slot colour and
  material; MeshService paints the MeshParts after InsertService:LoadAsset. Recolouring (station accents, states)
  = set `MeshPart.Color` on the pieces of slot `Accent` (amber default; red / blue / green sets on sheet 07).
- **Palette** (`ctrkit.HEX`): Slate #202833, Frame #4D5B66, FrameDark #363F48, Steel #7D8791, SteelLight #B8C0C8,
  Concrete #C1B6A2, Wood #A87548, WoodDark #7E5634, Amber / Accent #F4BE43, Brass #C9A050, Cream #F4EFE5,
  Rubber #25292F, Rock #8F8D89, RockDark #6E6B67, Crack #2B2A2A, Glass #F4C35A (Glass, transparency 0.45),
  Lamp #FFC93A (Neon). Add new slots to `HEX` (and `SLOT_MATERIAL` for the default material).
- **Shape language**: chunky blocks with bevelled edges (`BEVEL` 0.06, `BEVEL_BIG` 0.1, never more than 30 % of
  the thinnest side), broad flat-shaded facets, hex bolts (`bolt`, radius 0.09), hazard stripes
  (`hazard_stripes`), rocks as convex hulls (`rock_points` + `roughen`), cracks as thin dark ribbons on the rock
  surface (`crack_strips`), split chunks with `clip_hull`. No noisy greebles; keep pieces under ~3k tris.
- **Attach points**: `m.attach[name] = (x, y, z)`; they become Attachments on the invisible `Root` part.
- **Preview-only** compositions (`Station_Assembled`, `Rock_FractureSequence`, `Rock_Lineup`) mark every piece
  `preview=True`: rendered for comparison, never exported or uploaded.

## In game (`src/server/MeshService.luau`)

`MeshService.start()` loads every id in `MeshIds`. Catalog models become `ReplicatedStorage.Assets.Kit.<Name>`:
a Model with an invisible anchored `Root` part at the origin (PrimaryPart, `WorldPivot` = origin) holding one
Attachment per attach point, plus one anchored, non-colliding MeshPart per piece painted from the catalog.
Animated pieces carry attributes `Anim` and `Pivot`. Use `MeshService.kit(name)`, `:Clone()`, `:PivotTo(cf)`.
If the importer keeps the FBX axis rotation on a MeshPart, the service keeps it and converts the size
(attribute `ImportRotation`). Missing pieces or a failed load = the asset is absent and the Part stand-in stays.
Legacy `CT_Rocks_*` single meshes keep their old path (`ReplicatedStorage.Assets.<Name>`).

Not wired yet: StationModels / WorldBuilder / GeodeModel / EconomyService still build their Part stand-ins; the
next step is to swap them for the kit models where `MeshService.kit(...)` returns a template (keep the stand-in
fallback, keep the named parts / attachments those systems rely on: Plate, InputTray Slot1..10, OutputTray,
Dock, Stand, MachineFeed, Nameplate, Sign, Light).

## Asset table (all 14 sheets)

Status: **done** = modelled, previewed, compared and uploaded (id in `art/meshes/uploaded_ids.json`);
**todo** = not modelled yet (a Part stand-in may exist in game). Claim a row by building it in a new module.

### 06 Rock pickup & fracture (`blender/models/rocks.py`)
| Asset | Model name | Status |
|---|---|---|
| 12 whole rocks (Body + Hairline + Wide crack pieces) | Rock_01_Wedge, Rock_02_Oval, Rock_03_SquatBoulder, Rock_04_Oblong, Rock_05_TallLump, Rock_06_FlatStone, Rock_07_AngularChunk, Rock_08_RoundedCube, Rock_09_RiverStone, Rock_10_SmallBarrel, Rock_11_Triangular, Rock_12_LumpyBoulder | done |
| Split stage (3 chunk pieces) | Rock_Split | done |
| Rubble stage | Rock_Rubble | done |
| Decorative grit | Grit_Patch | done |
| Fracture sequence / lineup (preview only) | Rock_FractureSequence, Rock_Lineup | done (not uploaded) |
| Geode fracture example (coloured crack) | - | not built on purpose (brief: neutral until the reveal; sheet 12 covers geodes) |

### 07 Carry & crush station (`blender/models/station.py`)
| Asset | Model name | Status |
|---|---|---|
| Table (plank top, frame, legs, feet, braces, bolts, nameplate, hooks, dock arm) | Station_Table | done |
| Anvil plate | Station_AnvilPlate | done |
| Input tray (hazard stripes) | Station_InputTray | done |
| Rubble bin (+ Fill piece) | Station_RubbleBin | done |
| Amber shield glass | Station_Shield | done |
| Beacon lamp (Lens piece) | Station_Beacon | done |
| Basket dock | Station_BasketDock | done |
| Station sign | Station_Sign | done |
| Loading chute | Station_LoadingChute | done |
| Floor pad | Station_FloorPad | done |
| Carry basket empty / filled | Basket_Empty, Basket_Filled | done |
| Assembled station (preview only) | Station_Assembled | done (not uploaded) |
| 4 accent sets | (recolour slot Accent in game) | todo (game side) |

### 08 Manual tools (`blender/models/tools.py`)
| Asset | Model name | Status |
|---|---|---|
| Starter hammer | Tool_StarterHammer | done |
| Steel hammer | Tool_SteelHammer | done |
| Jackhammer (handlebar + grips, body, hose stub, Bit piece) | Tool_Jackhammer | done |
| Tool rack, wall hooks, jackhammer stand, spare bits (point/flat/wedge/chisel), portable compressor, coiled air hose, tool case, steel vise | - | todo |

### 01 Lobby building kit (`blender/models/lobby.py`)
Whole buildings, one model each; every slot is split into named pieces (Foundation, Posts, Roof, Walls, Interior ...)
so no MeshPart is huge. Origin = ground centre of the footprint, entrance / open side faces -Y (Roblox -Z).
| Asset | Model name | Status |
|---|---|---|
| Open-front equipment workshop (foundation + steps, stone pedestals, steel posts, timber shed roof, walls, bench, tool board, shelf, compressor, crossed-hammer Sign, 5 lanterns) | Lobby_Workshop | done |
| Specimen gallery (glazed wings, Windows piece, pillars, gabled entrance with Emblem, hip roofs, 5 Display pedestals, rails, planters) | Lobby_Gallery | done |
| Start Hunt kiosk shelter (stone back wall, steel pillars, kiosk body with Screen, timber roof, lantern) | Lobby_KioskShelter | done |
| Leaderboard alcove (stone pillars, Board piece, timber roof, bench, planters) | Lobby_LeaderboardAlcove | done |
| Public courtyard shelter (platform + steps, columns, beams + braces, hip roof, 3 benches, planter, lantern) | Lobby_Shelter | done |
| Equipment storage shed (plank walls, gabled roof, Door + DoorBrace with Swing anim, vent, lamp, crates, barrel) | Lobby_StorageShed | done |

### 02 Courtyard & navigation (`blender/models/courtyard.py`)
| Asset | Model name | Status |
|---|---|---|
| Walkway straight (8 x 4) / L corner (8 x 8) | Court_WalkwayStraight, Court_WalkwayCorner | done |
| Station floor pad, courtyard version (10 x 10, Accent corners) | Court_StationPad | done |
| Stone planter, small tree, wooden bench | Court_Planter, Court_Tree, Court_Bench | done |
| Perimeter wall, fence straight, fence corner | Court_PerimeterWall, Court_FenceStraight, Court_FenceCorner | done |
| Entrance arch (Emblem piece, glowing gem) | Court_EntranceArch | done |
| Wall lamp, standing lamp (Glow pieces) | Court_WallLamp, Court_StandingLamp | done |
| Sign frame (Panel piece), path arrow inset (Arrow piece, points -Y), kiosk bollard (Screen, Glow) | Court_SignFrame, Court_PathArrow, Court_KioskBollard | done |

### 03 Start hunt terminal (`blender/models/terminal.py`)
| Asset | Model name | Status |
|---|---|---|
| Detailed kiosk (plinth, body, emblem, touch Screen, Title / Solo / Party panels, posts, roof, lantern, side lamps) | Terminal_Kiosk | done |
| Screen housing, party ready lights (Light1..Light4 pieces), lamp + bracket | Terminal_ScreenHousing, Terminal_ReadyLights, Terminal_LampBracket | done |
| Geode emblem (wall mount, origin = back face centre), step / paving tile | Terminal_GeodeEmblem, Terminal_StepTile | done |
| Owned station nameplate (Plate piece), party readiness floor beacon (Ring + Face pieces) | Terminal_Nameplate, Terminal_FloorBeacon | done |

Shared helpers for these three kits live in `blender/models/_lobbyparts.py` (lanterns, wall lights, planters, rosette
shrubs, stone courses, steps, crystal cluster, gem). It adds slots ConcreteDark #A39883, Leaf #5E9E3A, LeafDark #3F7A2C
(Grass), Soil #5A4130 (Ground), Window #CFE2E8 (Glass, transparency 0.6), Red #C4402F, Plaster #E2CDA2. Signs, screens and
boards are Slate pieces with an attach point on their front face for a SurfaceGui (no baked text). Not wired into
LobbyBuilder yet; NOT checked in Studio.

### 04 Geode gallery (`blender/models/gallery.py`)
Floor pieces: origin floor centre. Wall pieces (niche, nameplate, index board, lamp): y 0 = wall plane, origin noted
per model. Specimen places = attach `Slot1..N` (bottom of a scaled specimen) + `Label1..N` (label plate face),
numbered left to right, top row first. Glass is one `Glass` piece (slot GlassClear, transparent SmoothPlastic), hidden
in the preview renders only. Specimens in the previews are preview-only (built from the sheet-12 kit).
| Asset | Model name | Status |
|---|---|---|
| Glass specimen cabinet (9 places, 3 downlights, glowing shelf edges, attach Light) | Gallery_Cabinet | done |
| Wall display niche (1 place, downlight) | Gallery_WallNiche | done |
| Individual pedestal (1 place on a labelled plinth) | Gallery_Pedestal | done |
| Empty-slot pedestal (recessed top, `SlotGlow` Neon ring piece to toggle) | Gallery_PedestalEmpty | done |
| Countertop showcase (3 places) | Gallery_Showcase | done |
| Three-tier specimen shelf (9 places) | Gallery_Shelf | done |
| Specimen label plaque (attach Text, face tilt in catalog extra) | Gallery_LabelPlaque | done |
| Specimen stand (attach Specimen, lean-back tilt 15 deg in extra) | Gallery_SpecimenStand | done |
| Owner nameplate (attach Text) | Gallery_OwnerNameplate | done |
| Mineral index board (6 cards, gem pieces Gem1..6 slot Crystal, attach Card1..6) | Gallery_IndexBoard | done |
| Bench (attach Seat1, Seat2) | Gallery_Bench | done |
| Gallery wall lamp (lantern `Glow` Neon piece, attach Light) | Gallery_WallLamp | done |

### 05 Quarry environment (`blender/models/quarry.py`)
| Asset | Model name | Status |
|---|---|---|
| Cliff modules A-F (layered faceted columns, sandy ledge caps, moss, front boulders; box colliders in manifest `colliders`) | Cliff_A, Cliff_B, Cliff_C, Cliff_D, Cliff_E, Cliff_F | done |
| Ledged cliff corner (L-shaped, inner corner faces -Y / +X) | Cliff_Corner | done |
| Low retaining wall (8 studs, tiles via attach `Next`) + corner | RetainingWall_Low, RetainingWall_Corner | done |
| Wooden fence section (6 studs, attach `Next`) | Fence_Section | done |
| Quarry entrance gate (timber posts, lanterns, attach `Sign`) | Quarry_Gate | done |
| Storage nook / shelter (crates, barrels, lanterns) | Storage_Nook | done |
| Large gantry crane (attach `Bucket`) + clamshell bucket (ShellL / ShellR anim Open) | Crane_Large, Crane_Bucket | done |
| Wall lamp (origin = wall plate back, attach `Light`) | Wall_Lamp | done |

### 09 Auto cracker (`blender/models/machines.py`)
| Asset | Model name | Status |
|---|---|---|
| Base, feed roller conveyor, chamber, JawL / JawR (separate, slide along X), Hood glass, motor, control panel, output bin + Fill | Auto_Cracker | done (footprint ~7.5 x 4.7, 4.25 tall; pivots in MeshCatalog attach `JawL_Open/Closed`, `JawR_Open/Closed`) |

### 10 Advanced processors (`blender/models/machines.py`)
| Asset | Model name | Status |
|---|---|---|
| Hydraulic press: frame + hazard header, cylinder, Piston + Platen (separate, press along Roblox Y, 1.5 studs), bed, feed conveyor, controller, hose, tray + Fill | Hydraulic_Press | done (~7.8 x 3.9, 7.2 tall; attach `Platen_Open`, `Platen_Down`) |
| Industrial crusher: hopper + HopperFill, RollerL / RollerR (separate, spin about Roblox X), mesh guards, discharge conveyor, motor, controller pedestal, bin + Fill | Industrial_Crusher | done (~7.8 x 5.1, 5.7 tall; attach `RollerL`, `RollerR` = axis points) |

### 11 Utility & workshop props (`blender/models/props.py`)
| Asset | Model name | Status |
|---|---|---|
| Rubble selling hopper (Beacon, ReceiptLight, Receipt pieces; attach Deposit / Prompt / Output) | Prop_RubbleHopper | done |
| Generator (Indicator piece), air compressor (attach Hose) | Prop_Generator, Prop_Compressor | done |
| Wheelbarrow, handcart (attach Load) | Prop_Wheelbarrow, Prop_Handcart | done |
| Wooden crates small / medium / large (attach Top) | Prop_CrateSmall, Prop_CrateMedium, Prop_CrateLarge | done |
| Steel storage chest (Lid anim Open), pallet (attach Top) | Prop_SteelChest, Prop_Pallet | done |
| Stacked stone bin (Fill piece), bucket | Prop_StoneBin, Prop_Bucket | done |
| Spare parts tray, bolt container | Prop_PartsTray, Prop_BoltContainer | done |
| Rolled cable, bent pipe module, hose reel (Drum anim Spin) | Prop_RolledCable, Prop_BentPipe, Prop_HoseReel | done |
| Warning placard, work light (Lens piece, attach Light), spare processing plate | Prop_WarningPlacard, Prop_WorkLight, Prop_SparePlate | done |

Colliders: sheet 05 / 11 models record simple boxes in the manifest (`collider` = one box, `colliders` = a list for
cliffs, gate, nook, crane). MeshService does not read them yet (game side: make the MeshParts non-colliding and add
invisible box Parts from these entries). New palette slots for these kits: Cliff, CliffDark, RockLight, Stone, Moss,
Timber (ctrkit.HEX).

### 12 Geode specimens (`blender/models/geodes.py`)
Built like the sheet's construction reference. `Geode_Shell` and `Geode_Rim` share one origin (bottom centre of the
shell; open side faces -Y / Roblox -Z): put both at the same CFrame. A cluster's origin is its base centre: put it at
the shell's attach `Cluster`. The assembled specimen sits on `Geode_Stand` attach `Geode` (or on a gallery Slot).
Colour per mineral: crystal pieces use slot `Crystal`, the cavity wall uses slot `Lining` (a darker shade); each
cluster is split into `Crystal1..3` so a multicolour specimen can paint the groups differently. New palette slots:
GeodeShell #46444A (Slate), Rim #E9DBD0, Crystal #9B5DE5, Lining #6236B0, GlassClear #D6E4EA (transparency 0.72).
| Asset | Model name | Status |
|---|---|---|
| Rough hollow shell (pieces Shell + Lining with druzy points) | Geode_Shell | done |
| Thick pale mineral rim | Geode_Rim | done |
| Crystal clusters: A cathedral, B fan, C low bed, D twin spire, E spray | Geode_Cluster_A .. Geode_Cluster_E | done |
| Wooden display stand (brass caps, dark cradle posts) | Geode_Stand | done |
| Construction reference / one specimen / 5-mineral lineup (preview only) | Geode_Assembled, Geode_Specimen, Geode_Lineup | done (not uploaded) |
| Game side: build the reveal / inventory / gallery specimen from these meshes with Config mineral colours | - | todo (game side; legacy CT_Rocks_GeodeShell / Crystal_1..3 still used) |

### Prospector Lodge building (`blender/models/lodge_building.py`, docs/lodge/)
| Asset | Model name | Status |
|---|---|---|
| Structural shell 84 x 68 (floor, foundation, timber frame, plaster, glass, trusses, roof, door leaves, porch, steps, rails; colliders + ramp in the manifest) | Lodge_Building | done (placement table + review renders: docs/lodge/BUILD_NOTES.md) |
| Blank exterior title plaque (SurfaceGui face) | Lodge_Plaque | done |

### 13 Mobile UI / 14 Animation
UI and animation references, not meshes (no Blender work; see the brief).
