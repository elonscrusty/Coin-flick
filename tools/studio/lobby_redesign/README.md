# Lobby redesign (2026-10-14)

carter asked for the whole lobby to be redesigned from scratch. The design is a compass around the leaderboard tree,
with the Void Dragon on top:

- **South:** the spawn, the shops and the fountain. The spawn looks straight north at the tree, with the castle behind it.
- **West:** FIND, which is the egg pile and the four queue pads.
- **North:** TRAIN, which is the castle court, the door and the TrainPad.
- **East:** FIGHT, which is the stone battle ring with the PvpPad.
- **The sides:** three yards on each side, with their gates facing the curvy lanes.

| File | What it does |
|---|---|
| `layout.py` | The plan: every footprint, path and tree. It runs the overlap check: footprints must stay 2+ studs apart, nothing may sit on a path except at the path's own end, and everything must be inside the walls. Run `python3 layout.py layout.json`; it must print `final overlaps: 0`. It needs `shapely`. |
| `render.py` | Draws the top-down plan picture (`docs/lobby_plan_1014.png`) with headless Chromium. |
| `gen_build.py` | Turns `layout.json` and `runtime.luau` into `build_lobby.luau`, a Studio Edit-mode script. That script moves the existing hooks (plots, pads, boards, shops, hangout seats), moves the old decor into `ServerStorage.LobbyBackups.Removed_1014` without deleting it, and builds the new dressing in `Workspace.LobbyRedesign`: paths, tile plazas, the egg pile, the battle ring, trees, and the cliff ring. |

The full backup from before the redesign is `ServerStorage.LobbyBackups.Lobby_Before_Redesign_1014`.

Round 6 (2026-10-15, from the strict runner's 4.5/10):
- Each zone gets its own ground: a meadow for FIND, red-brown dirt for FIGHT, grey-blue flagstone for TRAIN, and brown soil in the yards.
- Paths are 1.5x wider, with a cobblestone top and a dark border. A spur now leads into every yard gate, and the walks are lined with lamps and flower rows.
- The plazas get props (built stand-ins marked REPLACE): benches, planters, egg crates, hay bales and braziers. Pet bowls and balls sit by the yard gates.
- The zone arches are smaller, each with a round zone icon on top.
- The coin HatchStand moved beside the main walk, well away from the EGG SHOP hut's prompt.
- Bright things floating outside the walls are moved to the bin and named in the report.

Round 7 (2026-10-15, runner 5/10):
- It uses the Blender hero batch when it is in `ServerStorage.LobbyKitV2`: `FIND/FIGHT/TRAIN_Gate_v1`, `FountainBase_v1`, and the zone tree colours `Tree_Round_{Autumn,BlueGreen,Golden}_v1`. It prefers the `_v3` re-exports over `_v2`, and gives `_v2` meshes already in the lobby their `_v3` twin's calm texture. When an asset is missing, it falls back to the scripted versions, which now have a different look per zone.
- Other changes:
  - The main walks are wider. Yard spurs are narrow plank boardwalks, and zone chevrons run down the spokes.
  - Two ponds flank the castle. The shop signs are 3x bigger, and the shop square has a floor inlay and an inner prop ring.
  - The sun is warmer and the far hills sit in a soft haze. The old Lighting values are kept as attributes.

Round 8 (runner 5.5/10):
- Text now shows on both sides of the gate signs and the shop boards. (Round 7's hero gate signs were blank: the plate is named `*_Sign.001`.)
- Zone grass is calmer: a flowered gold meadow for FIND, ember dirt for FIGHT, and a teal lawn round the TRAIN court.
- The cliffs vary between warm and cool stone. Lamps are smaller.
- Gold chevrons run from the spawn, signposts stand at the two junctions, and gate thresholds read from above.
- Sparkles float over the shop square and embers rise from the battle ring.

Round 9 (runner 6/10):
- Shop names are on monument signs beside each door, turned to face the middle of the square, with an icon. All sign text uses pixels-per-stud, so it stays inside its plate, and gate signs have two lines.
- Yards get crop-row ridges on the soil, and the owner sign is 1.5x with its text lined up on the plaque.
- The zone colours blend wider into the lawn, and FIND has fewer, smaller flowers.
- Three colour lines run from the spawn and split down the spokes. Signposts are bigger.
- The dragon spot is lowered so the statue stands on the fountain island.

Round 12:
- The tile square is now r37, just inside the shop fronts, and the spokes run in to meet it. The lawn between the shops and the lanes gets groves and flower beds (the feature grid is denser).
- A bush sits on top of every other cliff, coloured by the side of the island. The tree belt outside the walls is fuller and leans toward each zone's colour.

Round 13 (Blender props batch `blender_lobby_props_1015`, all optional with fallbacks):
- `WallTower_Stone_v1` stands on the four wall corners. `PetStatue_Plaza_v1` goes in the shop square and at the spawn. `PetBowl_v1` sits by the yard gates.
- `CropPlant_Sprout/Carrot_v1` line the two outer crop rows of each yard.
- The 3D zone icons `Icon_Egg/Claws/Star_v1` float over the gates, under a big floating zone name.
- The roads lean toward their zone colour, with a thicker border. The gold claim discs are gone.
- Yards are green grass again (carter, 2026-10-15). Two small wood-edged garden beds along the fence sides hold the crops, and the middle stays open lawn for the pets.

Round 15 (2026-10-15, round 14 runner 6/10, aiming at 9):
- The corner watchtowers now stand inside the cliff line on the ground plate at (+-133, -175) and (+-133, 167), at 1.45x scale (about 35 studs tall). In round 14 they were buried in the cliffs.
- The main road is 24 wide and the side lanes are 14. The zone spokes stay at 18 because the hero gate opening is 21.
- The spawn signpost is now a big direction post: 16 studs tall, with 10-stud arms that end in arrow tips, white outlines and two-sided FIND, FIGHT, TRAIN and SHOPS names.
- A free-egg stand marks StarterEggSpot: a gold neon ring, a pale disc, six lanterns, a warm light and sparkles. The spot itself stays clear.
- The MY PETS monument now stands on the side of its door away from the spawn-to-dragon walk. Every monument picks the side farther from x = 0.
- The TRAIN ground is a cleaner fresh green (5aae78) with light flagstone (c2c8cc).
- Each yard gets a round gold number badge over its owner sign and a watering can (`WateringCan_v1`) at the end of a garden bed. The yards stay green.
- The egg pile has a taller dome (17 studs), bigger eggs and brighter colours, with no pink.

Round 16 (2026-10-15, round 15 runner 6.5/10):
- The Blender hub props (`FruitStall_v1`, `MarketStall_Treats_v1`, `BalloonCart_v1`, from blender_lobby_hub_1015) are wired in:
  - The two stalls stand on the north half of the shop square.
  - The balloon cart stands at the spawn.
  - Scripted stand-ins are used until the props are in `LobbyKitV2`.
- The layout check now measures a shop against a prop with true footprints, because a shop's 45-degree box is far bigger than the hut.
- The corner towers are 1.9x (about 46 tall), set square to the walls at (+-131, -170) and (+-131, 163). They get a stepped orange roof, a gold neon tip with a warm light, and four lanterns.
- Each yard gets:
  - a floating "YARD k" name (200 studs)
  - a wooden gate arch with a YARD k board
  - a red mailbox just inside the gate
  - six softer grass patches on the lawn
- The pale `OuterHills.RollingHill_B.RollingHill_B_Decor_v2` mesh (the "white rock") goes to the backup bin.
- The Terrain clouds are soft and white.
- `src/server/VoidStatue.luau`: the dragon's beam and light are a deeper violet instead of the colour that read as pink.

Round 17 (2026-10-15, round 16 runner 6.5/10):
- Re-runs no longer stack a new yard slab and new beds on the last run's slab. Each run keeps the lowest slab and the lowest copy of each bed piece, and removes the rest.
- Each yard:
  - "YARD k" now floats over its gate arch (on the plaque it read as a bug).
  - Each yard has its own colour, used on the arch board, the mailbox and the pet house roof.
  - It has a pet house in the gate corner: `PetHouse_Wood_v1`, or a stand-in.
- The wall cliffs are 0.8-1.0x (were 1.15-1.5x) and spaced every 16 studs, so the hills show over them.
- `RollingHill_A_Decor_v2` goes to the bin (the seam and rock row over the north-west wall).
- Haze is up a little (Density 0.34, Haze 1.8).
- The spawn post is chunkier.
- `src/client/Main.client.luau`: the onboarding tag says "YOUR YARD" instead of "YOUR GALLERY" (theme rule).

Round 18 (2026-10-15, round 17 runner 6.5/10). Blender kit 1015b (`ServerStorage.LobbyKitV2.Kit1015b`) is wired in, with stand-ins for missing pieces.

New pieces:
- **FIND:** `HatchNest_Big_v1` behind the egg pile and `HuntBoard_v1` (its `_Face` plate says "EGG HUNT / Stand on a pad to play!"). The hunt plaza crates and bales are now `EggCrate_Stack_v1` and `HayBale_Round_v1`.
- **FIGHT:** three `TrainingDummy_Straw_v1` round the battle ring.
- **Yards:** `SteppingStones_v1` in from the gate, `PetBed_Round_v1` by the pet house, two `FlowerBorder_Strip_v1` inside the front fence and two `GardenLantern_v1` at the arch. Kit parts named `*_Glow` turn Neon.
- **Far mountains:** 14 `DistantMountains_Ring_v1_A..E` pieces 330-420 studs out, turned and scaled so the shapes vary. They don't collide or cast shadows.
- **Towers:** `WallIvy_Patch_v1` on the tower faces that look into the park.

Fixes:
- Stacked crop beds: only the lowest set of beds is kept, and crops above it are set back down.
- Every `RollingHill_*_Decor_v2` under OuterHills goes to the bin. There are several with the same name, so the path lookup missed them.
- Pet houses moved 2 studs further from the fence and sit on the grass top. Other yard items also sit on the grass top.

Round 19 (2026-10-15, round 18 runner 6.8/10):
- The flower borders use yaw 0 so they run along z, inside the front fence. With yaw 90 they ran through the fence.
- The ivy slabs are off. They read as flat squares, and half were buried.
- The far mountains are tinted blue / blue-purple with no texture, so they read as distance.
- Each yard gets a thin trim in its own colour just inside the fence.
- Gold sparkles rise off the egg pile.
- Three more market stalls stand on the shop square's outer ring, at (+-43.7, 14.2) and (14.2, -43.7).

Round 20 (2026-10-15). Blender kit 1015c is wired in, with fallbacks for missing pieces:
- Benches and planters across the plazas now use `Bench_Park_v1` and `Planter_Round_v1`.
- `ShopSquare_Tile_v1` rosettes (0.55x) mark where the four walks enter the shop square, replacing the gold diamonds, and a full-size one sits in the spawn plaza.
- Each corner tower face that looks into the park gets two `Buttress_Stone_v1` and one `LeafIvy_Hang_v1`, placed on the real stone face found by a raycast.
- Round 20 patch (after the round 19 check):
  - Flower borders: yaw 0 and yaw 90 both came out along x in Studio. Each strip is now measured after placing, turned if its long side runs along x, and moved back onto its spot inside the fence.
  - The EVENT SHOP "coming soon" monument is 0.65x.
  - The far mountains get paler with each ring further out.
  - Atmosphere Density is 0.38.

Round 21 (2026-10-15): fixes from the first glitch scan and walkthrough (round 20: 544 scan lines, 318 walkthrough flags, runner 6.5).
Glitch fixes:
- **Grass patches:** each patch sits on its own hair-thin layer under the zone discs, which stops the z-fighting.
- **Towers:**
  - Buttresses step out 4.0 and ivy 0.6, because Studio measured them 1.39 and 0.55 into the stone.
  - An ivy ray that lands more than 1.5 studs off the buttress wall line is skipped. This prevents the two buried patches.
- **Rosettes:** sit at G0 + 0.42, just above the inlay.
- **Yards:** pet houses sit 7 in from the gate line and pet beds 12.8 in, so they clear the gate post, the flower border and each other.
- **Spawn signpost:** at (-19, 113) with r = 5 on the plan, so no lamp stands under its arms.
- **Gate icons:** the 3D icons are 1.2x (were 1.6x).

Other changes:
- **Haze:** Atmosphere Density is back to 0.32.
- **FIGHT arena:** sand floor with a red ring, a dark and gold centre, warm stone walls with a red top trim, and fire on the four pillar caps.

`glitch_scan.luau` skips what is sunk, stacked or hovering on purpose:
- folders: paths, grounds, plazas, ponds, egg pile, sparkles, far mountains
- edge cliffs, bushes and trees, yard badges and icons

Its other checks:
- FLOAT needs more than 0.45, because the paving layers can't be hit by rays.
- Yard fences are tested with rays across each yard object. The fence is one mesh whose box covers the whole yard.

Round 22 (2026-10-15): round 21 scan 156 (was 544), walkthrough 19 lines, runner 6.5-7.
- **Ground layers:**
  - Ground layers sit 0.012 apart, measured at their tops: patches +0.012, zone edges +0.024 / +0.036, zone tops +0.048, TRAIN flagstone +0.06 / +0.072 / +0.084, paths from +0.11.
  - Patches no longer overlap each other.
  - The zone blend rings are smaller, so no two zones overlap.
- **Yards:**
  - The yard colour trim is gone, because it ran under the fences.
  - The flower borders are 0.75x (9 long) at z ±16, clear of the pet house.
- **Rosettes:**
  - The shop square rosettes are 0.42x at r 27.5, clear of the stalls and statues.
  - The spawn rosette is 0.6x, and the plan keeps a clear spot for it at (0, 140).
- **Spawn post:** three arms (FIND, FIGHT, TRAIN), all above lamp height.
- **Hidden eggs:** eggs 2 and 3 moved to (+-104, 172), clear of the tower buttresses.
- **Egg pile:** every other egg gets a band, so they read as painted eggs.
- **`glitch_scan.luau`:**
  - It measures ground under the world, not under our own dressing.
  - It also skips the battle ring, the shop signs, ivy, lawn patches and arch ground bands.

## Round 23 (walkthrough glitch fixes)
- Path borders, tops and colour lines each get their own height band, 0.004 apart (0.002 still flickered along Main).
  Plazas moved up 0.1 (G0+0.3), the inlay to G0+0.46 and the rosette tiles to G0+0.54 to make room.
- Zone edge rings grow 3 per step (5 made FIND/FIGHT overlap TRAIN).
- Yard pet house 10 in from the gate, the pet bed in front of it (the roof clipped the flower border).
- Spawn signpost at 0.6 size. Small trees touching a tower buttress are removed.
- GalleryService dome plaques: warm wood, text on both faces (empty domes read as black slabs).
- glitch_scan skips the hand-built YardGates parts; walkthrough FIND_gate_back no longer walks into the egg pile.
- Round 24: path borders share one height; road colours and colour lines get bands 0.02 apart (0.004 per path was too thin).

## Round 25 (one big push, runner round 24 at 6.9)
- Yard gates: the plot's owner sign (PlotSign/Nameplate, if it is a plain board under 9x3.5) moves onto the street side
  of the arch board; the YARD k board keeps its text on the yard side; the floating YARD k title is gone.
- Yards: four flower beds along each side fence, planters in the front corners, a hay bale and an egg crate in the back
  corners (all within 4.5 of a fence).
- Pet bowls and balls by the gates removed from the plan (they read as loose discs).
- Decor trees whose crowns touch a lamp step away from it.
- Path borders are a pale stone curb (Slate, w+3) instead of a dark outline.

## Round 26 (round 25 scan: 121, FENCE and BURIED from the new yard props)
- Side-fence flower beds 4 in from the fence and on the real ground; front-corner planters removed; back-corner hay and
  crate on the real ground.
- Owner sign: the plot's sign set (PlotSignPost/Mesh/Backing, SignPlaque) is hidden (LobbyHidden = true); only the
  PlotSign text carrier moves onto the arch board (8.6 x 2.4, dark wood).
- Pet houses at 0.8 size; 8 lawn patches in three tones, 0.012 apart.
- Client: the YOUR YARD tutorial marker floats 14 above the plot floor (it covered the arch board at 7).
- Walkthrough: gate walks stop before and after each gate instead of under it.
- Brighter look (carter, on a phone: "too bland"): place-wide ColorCorrection (Saturation 0.25, Contrast 0.12,
  Brightness 0.03, tint fffaf2), Ambient 120/120/128, OutdoorAmbient 150/150/158, ExposureCompensation 0.25, sun
  Brightness 3, haze down (Density 0.28, Haze 1.3). Old values kept as RedesignOld_* attributes on Lighting. Lawn
  7cbd4e, yards 88c855, brighter patch, zone and road colours.

## Round 27 (big redo of the three weak areas; runner stuck at 6.9)
- placeIfClear: every fill piece is placed, then removed again if it touches a path or plaza (tested on the plan
  shapes, paving is CanQuery off), a pond, the pile, the ring, the fountain or anything standing.
- YardScenes: per yard, stepping stones in from the gate, 4 small trees, 5 bushes, 3 flower beds, 2 rocks, a bench.
- LawnTufts: grass tufts (3 blades) on a 7-stud jittered grid over open lawn, 30% with a little flower cluster; not in
  yards, on paving or on the TRAIN flagstone. glitch_scan skips the folder.
- Wall: two bushes on every cliff top, leaf ivy on every other cliff's inner face, a bush at the foot of each cliff.
- Plan: lawn features on a 13-stud grid with gap 3 (27 placed, was 17).
- Round 27 fix: yard scenes sit on the soil top and wide flat slabs count as ground (all 102 were rejected); side-fence flower beds off (FENCE); grade Brightness 0 and exposure 0.1 (light paving read near white); glitch_scan leaves tuft blades out of the z-fight test.
- Round 28 (last): exposure 0, grade Brightness -0.02, bloom 0.05 / 2.9 (prints the grade so a stale build shows), paving and plaza tiles ~12% darker; yard stepping stones not doubled at the gate, back bushes off the fence, pet house and bed 3 further from the gate posts, mailbox clear of the plot gate.

## Round 29 (carter 10-15: "the map doesn't look vibrant enough to appeal to kids")
- Section 11 vibe pass: every coloured, untextured lobby part gets `src/shared/VibeGrade.lift` (more saturation, greens
  lean a little toward lime-leaf, greys/whites/stone untouched, nothing pushed toward white). It lifts from the original
  colour kept in the `VibeBase` attribute, so re-runs never stack. Big grass and soil tops become SmoothPlastic (flat
  shaded like the pets; old material in `VibeBaseMaterial`). Pets, characters and textured meshes are skipped.
- Lighting (carter 10-15, screenshot: "I like this old brightness setup we had"): the exact pre-redesign Lighting
  from `VibeGrade.Lighting` (FindThePet_newest.rbxlx, 10-12): brightness 3.13, exposure 0, the two old grades
  (ColorCorrection 0.14 + Grade 0.06 saturation), warm light Atmosphere with haze 0.25, bloom 0.06 / 2.4, Terrain
  clouds off. Any other ColorCorrectionEffect goes to ServerStorage.LobbyBackups. default.project.json and
  match.project.json carry the same set (brightness 3.13, exposure 0); a test keeps them equal.
- `gen_build.py` inlines VibeGrade.luau into build_lobby.luau; tests/test_vibe_grade.luau checks the lift offline.
- Lawn 7cbd4e -> 6ec838, yards 88c855 -> 78d43b, paths c8b286 -> d4b26e.
- Round 29 glitch fixes (scan_r29.txt, 79): plaza tile tones 0.02 apart and the centre disc above both (straight tiles
  on a circle really overlap near the inner edge; `python3 check_plaza_tiles.py` must print 0 pairs, it found 152 on
  the old heights); yard flower strips 1.3 inside the front fence; back-corner hay and crate measured after their turn
  and slid 1.3 off the back and side fences. glitch_scan: ZFIGHT now tests the real footprints (separating axis), and
  CLIP skips the boundary wall interlocking with itself and the outer hills, and loose parts of one hand-built thing
  (pond rim, battle ring, shop square, gate arches).
- Round 29d (runner 6.8 vs carter's old shot, scan_r29c 6): no haze (Atmosphere density 0.12, haze 0, clear-blue
  colour), crisp shadows (ShadowSoftness 0.15), 16 chunky white block clouds high outside the walls (SkyClouds),
  greens less neon (sat cap 0.62, hue 0.31), pale paving capped at value 0.78 (it blew out in the sun), blue-grey
  cliffs and deeper blue far mountains, mostly pines in the outer tree belt. glitch_scan ZFIGHT tests discs as circles
  (the six zone-ground pairs were the square guess; the circles are 1.3 apart).
- Round 29e (runner 6.3 on r29d, scan 0): lower sun (ClockTime 15.4), darker cool shade (OutdoorAmbient .36/.38/.46,
  diffuse 0.25) and every tree and lamp casts a shadow; plaza floor sandstone (b0a088 / c4b49a, grout 988a76), not lifted
  by the vibe pass; greens pulled 60% to one lime-leaf hue (0.3); clouds bigger (60-100) and higher (G0+150-210);
  cliffs bluer and the textured cliff meshes take the flat blue-grey too (texture id kept in VibeTex).
- Round 29f (runner 7 on r29e, scan 0): Lighting.Technology ShadowMap (the place ran Voxel: soft blob shadows; the
  r29e caster step found 0 because trees already cast); half the clouds lower and nearer so a phone sees them; outer
  pines 1.35x; paths and plazas not lifted (sand, not orange-gold), path colour lines thinner and softened toward
  sand; battle braziers' warm light smaller (it tinted the plaza pink); yard lawn patches close to the yard green;
  starter ring plain gold (not neon); neon parts not lifted; deeper blue air for the horizon.
- Round 29g: no Technology in this Studio; the build tries Lighting Style "Realistic" (crisp shadows) and prints a by-hand step if refused; ShadowSoftness 0; shade a bit darker (OutdoorAmbient .32/.34/.43). Technology removed from the project files.
- Round 29h (runner 7): sand paths (cbb88c / c4a990 / c6b894), colour lines 1.1 wide and 60% toward sand, softer lilac inlay, darker plaza sandstone (a89a80 / b8a98c), battle floor sand with a deep red ring (not lifted), calm blue-grey Slate cliffs (not lifted), yard patches without the light tone, 26 clouds, deeper gold for neon tips/lamps/kit glows, path strips CanQuery = true (launch-picks rainbow trail).
- Round 29i (runner 7): one sand path (cfc4a2) with dark edge stones (6e6658), colour lines off; plaza tiles mid sand (9e8c6c / ad9a78); plaza borders and the lilac inlay toned toward brick stone; cliffs lighter blue-grey (Slate read navy); gold trim deeper (d6a73a) and tower tips/lanterns/pile lamps matte; nest disc warm straw; pond and fountain water deeper blue.
- Round 29j (last colour sweep, runner ~7): inlay rings and plaza borders mostly stone, yard boardwalks pale wood, cream eggs and softer pile, starter ring muted, battle ring cap brick, fountain basin stone and solid water (glass read cyan), far hills not lifted, big near-white neutral parts (castle stone) toned to light stone cfc8ba.
- Round 30 path fix (carter: "the pathway looks awful"; his old shot): every walk and yard spur is one plain smooth cream-sand strip (efe0ad, 2 wider, no border, no lines), low white edge stones (0.8 x 0.5 x 1.5, every 3.6, none on junctions or plazas, no collision), plazas plain cream with a ring of low white stones, shop-square inlay off.
- Round 30 kit 1015j wiring (`tools/blender/lobby_kit_1015j.py`, pieces in `ServerStorage.LobbyKitV2`, any depth):
  `PathCurb_Stone_v1` replaces the white edge stones, `PlazaPaver_Disc_v1` lies on every plaza, `RockWall_A..D_v1`
  replace Cliff_Natural_A/B, `Pine_Tall/Mid/Small_v1` and `Tree_RoundChunky_v1` replace the old pines and round
  trees (each fitted to the old piece's height), `Cloud_A..D_v1` replace the block clouds, and 12
  `FarHillRing_A..C_v1` segments ring the park at radius 250. The build prints "kit 1015j used: ..."; any missing
  piece keeps the old one. glitch_scan skips FarHills and SkyClouds and treats RockWall/Pine like the old cliffs/pines.
