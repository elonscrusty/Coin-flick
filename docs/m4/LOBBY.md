# Master Prompt 4: lobby (sections 03, 05, 06-17, 54, 55)

Offline only (Lune preview renderer + Rojo build). Nothing here is Studio-tested. SurfaceGui text is not drawn by
the preview, so every sign was checked by plate position and size, not by reading the letters.

Pictures (phone-1108, `docs/m4/lobby/`): `spawn.png`, `kiosk_approach.png`, `workshop_front.png`,
`workshop_close.png`, `gallery_front.png`, `records.png`, `records_close.png`, `alcove_owned.png` (8 real
specimens on the display tiers), `alcove_empty.png` (empty-slot pedestal), `overview.png`; `before/` holds the
first-pass views. Scene views: `bash tools/preview/render.sh lobby --device phone-1108 --set view=<name> --set hud=off`
(`approach`, `workshop`, `workshopclose`, `gallery`, `boards`, `boardsclose`, `alc1close`, `alc1side`, `overview`).

## Causes found (confirmed vs hypothesis)

| Symptom | Cause | Status |
|---|---|---|
| RECORDS lettering broken | `Kit.pixelText` spelled it in 5x7 pixel-font blocks (cell 0.4, gaps 0.25) on an 17-stud plate, so round letters (C, O, S, D, R) read as stair-stepped segments from low angles, and two `Court_WallLamp` kit lamps plus two `BoardLamp` parts hung at y 13 directly in front of the R, E and O. Not a render bug. | confirmed from source and the before render |
| Records dominant | four 7.8 x 9.55 boards on two walls of a 19 x 19 nook, bright amber accent bars and edging, 15.6 high header. | confirmed |
| Tall empty shelf walls | `buildAlcove*` made 16 alcoves 13.4 high with 4 shelves x 5 slots each, neon shelf strips and a hood, lined up on three walls. | confirmed |
| Dark supports hide equipment | the Blender `Lobby_Workshop` had four steel posts across the front (x = -10, -3.8, 3.8, 10), 1.55 wide on 2.4-high cream stone feet. The two middle posts stood exactly in front of the displays. | confirmed in `blender/models/lobby.py` |
| Equipment buried | the kit workshop has a 1.0 stud foundation; the stands, price cards, machines and the gallery desk were placed from y = TOP, so they sank 1 stud into the floor (double offset). | confirmed by arithmetic, fixed |
| Several Inspect/Buy prompts | three prompts of range 10 on stands only 6.5 apart (plus locked-machine prompts of range 9 about 6 studs behind them). Studio's default prompt UI shows one prompt per button only when `Exclusivity` is OnePerButton, which the code never set explicitly. Whether Studio showed more than one for another reason (a custom client prompt, duplicate connection) is **not determined**. | spacing/range confirmed; extra display mechanism is a hypothesis |
| Screen filled with wood | not reproduced offline (no physics, no camera collision). Hypotheses: the camera went inside kit roof/beams/trees or the invisible blockers while approaching. Mitigation: all roofs, canopies, foliage, lamps and the kit buildings carry `CameraIgnore=true`; floors, walls and blockers do not. The client helper has to honour the attribute. | hypothesis, mitigated |
| Paving glare, lime foliage, many lamps | plaza and pavers (193,182,162)/(214,204,184) under project Lighting; kit `Leaf`/`LeafDark` slots are lime (94,158,58); 8 standing lamps, 2 kiosk bollards at scale 1.2, shelf neon strips, hanging lanterns. | confirmed |
| Route not open | an entrance arch (12.5 tall) with two fence stubs sat 10 studs in front of the kiosk, a floor beacon and an arrow on the aisle, a 12.7-high shelter and lamps beside the spawn. | confirmed |
| Scale / pivots | Kit models use floor-centre pivots and are placed once through `KitPlace.facing`+`place` (no child scaling). The only double offset found is the foundation height above. Bounding boxes (studs, from `art/meshes/manifest.json`): workshop 25.6 x 13.3 x 18.2, gallery 26.7 x 15.8 x 19.1, kiosk 9.1 x 9.6 x 5.7 (placed at 1.3: 11.8 x 12.4), tree 6.6 x 8.5, bench 5 x 3.1, planter 6 x 2.2, standing lamp 1.6 x 4.6 (a 5-stud avatar). | measured |

## What changed

* `blender/models/lobby.py` + `Lobby_Workshop` re-uploaded (new asset id in `MeshIds.luau`): only the two outer front
  posts remain, 1.15 wide on 1.3-high stone feet (was four posts, 1.55 wide, 2.4-high feet). Roof beams unchanged.
* `LobbyBuilder`:
  * Open route: arch, fences, path arrows, floor beacon, shelter, storage shed and 6 of 8 standing lamps removed. Kiosk moved to z = 16
    (18 studs from the spawn at z = 34). Aisle 12 wide, lighter tone, tile seams every 6 studs, cross band in front of the
    buildings, darker aprons; scattered inset rectangles removed.
  * Calmer palette: plaza (176,161,136), aisle (190,175,148), apron (150,138,118); kit foliage recoloured through
    `KitPlace.tone` to (96,128,78)/(70,100,62); edge-tree leaves toned; kiosk bollards 0.8; lamp lights 0.4-0.7.
  * Workshop: tool stands lifted onto the floor and spaced 9 apart (x = -9/0/9) with prompt range 6; locked machines in a back row, range 5;
    duplicate compressor removed; one WORKSHOP board on the fascia.
  * Gallery: one GALLERY board over the door, desk lifted onto the floor, prompt range 8.
  * Alcoves: 8.6 wide, about 8.9 tall including the nameplate, four stepped tiers of five slots (1.1 rise, 1.55 run), one
    nameplate, no hood or shelves, no neon. Same slot count (20), same `Alcove` return contract (`Index`, `Root`, `Plate`, `Slots`),
    parts `SideL`, `SideR`, `ShelfLight` kept so `Cosmetics.applyAlcoveTheme` still works. Layout: 6 north (3 each side of the
    records), 1 west-north, 4 west-south, 1 east-north, 4 east-south = 16.
  * Records moved to the north-centre, behind the kiosk: four 5.6 x 6.9 boards on one low back wall, ONE title plate, planters at the ends.
  * `LobbyBuilder.ClearZones` + `tools/preview/check_lobby.py`: clear-zone audit (spawn aisle, north aisle, both building fronts): all CLEAR.
* `LobbyBoards`: header is a wood plate with one fitted `TextLabel` (FredokaOne, no pixel blocks); board accent bars thinner. Data path unchanged.
* `GalleryService`: inspect plaque moved onto the tier riser, Inspect range 6, Place-geode range 7, explicit `OnePerButton`.
* `KitPlace`: `cameraIgnore`, `tone`, `titleBoard` helpers.
* `tools/preview/scenes/lobby.luau`: player-height views (avatar + follow camera) and free close-ups.

## Prompt contracts kept (grepped before changing)

`Panel` attribute (`Shop`, `Collection`, `Party`), `Sell`/`Hopper` (`KitPlace.hopper`, untouched), `InspectOwner`/`InspectId`,
`PlacePrompt`, `Stands` positions returned to `EconomyService`, alcove `Plate`/`Slots`, spawn `CFrame`.

## Not done / open

* Parts-only fallbacks (used only when kit meshes are missing) still build the old workshop and gallery; the new layout targets the kit path.
* The gallery building itself is the kit's closed house with a door; the personal collection is the 16 alcoves, not the interior.
* Records boards show data through SurfaceGui, which the preview does not draw: the text, empty state and row grid were not seen.
* No Studio camera test: whether the CameraIgnore attribute removes the wood-filled-screen case depends on the client helper and a play test.
