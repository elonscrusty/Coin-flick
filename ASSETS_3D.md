# ASSETS_3D: models FIND THE PET! still needs

Repo: scratchpad/repo. Read-only inventory from code. Tri numbers are MY planning budgets (not measured). Mesh ids were not checked in Studio; nothing here proves ownership of any mesh id.
Old names stay (rock = egg, geode = pet, Quarry = Forest ...).

## 0. Headline facts (proved from code)

1. Only 10 of 50 pets have real meshes: `assets/PetModels.rbxmx` holds 10 `Pet_<species>` Models (Raptor, Ostrich, DireWolf, Griffin, FrostWyvern, Mammoth, LavaTRex, Phoenix, CosmicDragon, StarPterodactyl), each ONE MeshPart plus 7-10 Bones (84 Bone items total; 10 MeshPart, 10 Model, 10 distinct `rbxassetid` mesh ids). `default.project.json:10` maps the file to ReplicatedStorage.PetModels, `PetModel.luau:75-83` loads `Pet_<id>`, else builds a procedural body (`PetModel.build`, 18-30 Parts, 10 `Kind`s). The 10 rigged pets are all LAUNCH pets, so 25 launch pets + 10 weekly + 5 tower pets = 40 pets are procedural re-skins of 10 body Kinds (Config.luau:230-290: e.g. Puffquill, Thornhoof, Flarestrut all reuse `Kind = "ostrich"`).
2. All five zones use the SAME arena. `ArenaBuilder.build(slot, c)` (ArenaBuilder.luau:447) takes no zone/tier argument and `MatchService.luau:633,680` calls `World.buildArena(slot)` with no tier. So Forest / Snow / Volcano / Space have no landmarks, ground, sky or props of their own: the "Meadow" (hay bales, hedges, hills, trees, flowers) is every hunt, only the egg HP/colours change per zone (Config.Tiers has no theme/ground fields). Zone environments are therefore 0 percent built = the biggest 3D gap after pets.
3. Animation is code only. Rigged pets move through `PetMotion` (tools/owner/PetMotion.luau) by NAMED bones: `LegL LegR LegBL LegBR Tail Arms WingL WingR Head Jaw` (optionally prefixed `Raptor_Head`). New rigs MUST use these names or they fall back to a bob.
4. Variant system limits meshes (PetModel.luau:104-135): Golden / Skeleton / SilverCosmic recolor EVERY non-Neon BasePart and clear `TextureID`; Rainbow tints per part. So a new pet needs (a) eyes / teeth / glow as Neon parts or the code must skip "fixed" parts, otherwise eyes turn gold, (b) a readable silhouette when untextured. Natural keeps the texture.
5. Kit meshes exist (182 ids in `MeshIds.luau`, uploaded by `tools/upload_meshes.py` with ROBLOX_USER_ID 20194281) but they are the OLD quarry/lodge theme (rocks, strata cliffs, hoppers, crushers, Lodge stalls). Still used live: `Cliff_A/B/C/E` + `Strata_*` (valley ring and arena boundary), `Lodge_CollectionStall / UpgradesStall / RubbleSell / Leaderboard / Lantern / SpecimenPedestal / RockBasket / TrophyEmblem / RunnerRug` (lobby stalls via LodgeBuilder), `Basket_Empty` (CarryView.luau:71, the ONE basket mesh for all 9 basket levels), `Tool_StarterHammer / SteelHammer / Jackhammer` (WorldBuilder.luau:129, the three tappers), `Wall_Lamp`, `Prop_*` crates. Machines and hatch nests deliberately bypass the kit (`MachineModels.luau:314`, `StationModels.luau:343` return false: "REPLACE: real gadget / nest mesh").
6. `MeshCatalog` is vertex-colour-free: "no UVs or textures" (ASSET_MANIFEST.md header), colours painted per piece in game. That is incompatible with a Meshy textured pipeline unless Meshy assets go in as their own MeshParts with TextureID (pets already work that way: the rbxmx MeshParts keep their texture for Natural).

## 1. Planning rules used below

* Meshy export limit 20k tris per piece (owner). Phone-friendly targets (mine): hero pet 3,000 tris (chase pet 5,000), follower LOD 1,200 (Lod/Tiny), egg 250, nest 600, building 2-5k, tree 400-700, landmark 3-8k. Everything GPU-friendly: one texture per group, no per-asset materials.
* Phone scene cap (mine): about 120k visible tris in a hunt, about 200k in the lobby with 12 followers; PERF.md only measured Part counts in the mock (lobby with 16 galleries 7,648 Parts, Meteor hunt 10,063 Parts), no device FPS.
* Texture / palette groups (proposal): **P-MEADOW, P-FOREST, P-SNOW, P-VOLCANO, P-SPACE** (one 1024x1024 pet atlas per zone, 9 species at about 340 px each), **E-MEADOW ... E-SPACE** (one 1024 environment atlas per zone), **S-EGG** (512 atlas: 4 shell patterns, crack halves, 3 Robux egg skins), **S-LOBBY** (1024 jungle park atlas: wood, stone, leaf, lantern), **S-GADGET** (512: nests, baskets, mallets, hatchers), **S-TOWER** (1024: 4 theme palettes + 6 mobs).
* LAUNCH-REQUIRED = needed for the 25 launch zone pets, eggs, nests, hatchers, the 5 zone arenas, lobby. NICE-TO-HAVE = weekly (10), tower-only pets (5), tower mobs, cosmetics.

## 2. Pets (50)

Current state key: RIGGED = real mesh + bones in PetModels.rbxmx; PROC = procedural Parts (PetModel Kind shown), needs a custom mesh. All need rig + PetMotion bone names. Tri budget 3,000 (chase 5,000), group P-<zone>.

| Zone | Pet (species id) | State | Rig + anim | Budget / group | Priority |
|---|---|---|---|---|---|
| Meadow | Razorclaw (Raptor) | RIGGED | done (PetMotion) | in rbxmx; check tris | LAUNCH (done) |
| Meadow | Thunderstrut (Ostrich) | RIGGED | done | in rbxmx | LAUNCH (done) |
| Meadow | Puffquill | PROC `ostrich` | biped: LegL LegR Head Tail | 3k, P-MEADOW | LAUNCH |
| Meadow | Pebblehorn | PROC `mammoth` | quadruped: 4 legs Head Tail | 3k, P-MEADOW | LAUNCH |
| Meadow | Mosswhip | PROC `raptor` | biped | 3k, P-MEADOW | LAUNCH |
| Meadow | Honeyhoof | PROC `mammoth` | quadruped | 3k, P-MEADOW | LAUNCH |
| Meadow | Sunpetal Drake (chase) | PROC `dragon` | wings + 4 legs + Jaw | 5k, P-MEADOW | LAUNCH |
| Meadow | Bramblebat (weekly) | PROC `pterodactyl` | WingL WingR Head | 3k, P-MEADOW | NICE (weekly) |
| Meadow | Clovercrest (weekly) | PROC `griffin` | wings + legs | 3k, P-MEADOW | NICE (weekly) |
| Forest | Shadowfang (DireWolf) | RIGGED | done | in rbxmx | LAUNCH (done) |
| Forest | Stormtalon (Griffin) | RIGGED | done | in rbxmx | LAUNCH (done) |
| Forest | Duskwing | PROC `griffin` | wings + legs | 3k, P-FOREST | LAUNCH |
| Forest | Oakmaw | PROC `mammoth` | quadruped | 3k, P-FOREST | LAUNCH |
| Forest | Thornhoof | PROC `ostrich` | biped | 3k, P-FOREST | LAUNCH |
| Forest | Vinetail | PROC `wolf` | quadruped | 3k, P-FOREST | LAUNCH |
| Forest | Elderhorn (chase) | PROC `mammoth` | quadruped | 5k, P-FOREST | LAUNCH |
| Forest | Mossback (weekly) | PROC `trex` | biped + Arms | 3k, P-FOREST | NICE |
| Forest | Hollowfang (weekly) | PROC `wolf` | quadruped | 3k, P-FOREST | NICE |
| Snow | Glacier Wyrm (FrostWyvern) | RIGGED | done | in rbxmx | LAUNCH (done) |
| Snow | Titan Tusk (Mammoth) | RIGGED | done | in rbxmx | LAUNCH (done) |
| Snow | Frostpaw | PROC `wolf` | quadruped | 3k, P-SNOW | LAUNCH |
| Snow | Yetiboo | PROC `mammoth` | quadruped | 3k, P-SNOW | LAUNCH |
| Snow | Shiverclaw | PROC `raptor` | biped | 3k, P-SNOW | LAUNCH |
| Snow | Aurora Hoot | PROC `griffin` | wings + legs | 3k, P-SNOW | LAUNCH |
| Snow | Frostcrown Dragon (chase) | PROC `dragon` | wings + legs + Jaw | 5k, P-SNOW | LAUNCH |
| Snow | Waddlefrost (weekly) | PROC `ostrich` | biped | 3k, P-SNOW | NICE |
| Snow | Hailwing (weekly) | PROC `pterodactyl` | wings | 3k, P-SNOW | NICE |
| Volcano | Inferno Rex (LavaTRex) | RIGGED | done | in rbxmx | LAUNCH (done) |
| Volcano | Solar Phoenix (Phoenix) | RIGGED | done | in rbxmx | LAUNCH (done) |
| Volcano | Cinderpup | PROC `wolf` | quadruped | 3k, P-VOLCANO | LAUNCH |
| Volcano | Magmaw | PROC `trex` | biped + Arms | 3k, P-VOLCANO | LAUNCH |
| Volcano | Obsidihorn | PROC `mammoth` | quadruped | 3k, P-VOLCANO | LAUNCH |
| Volcano | Emberclaw | PROC `raptor` | biped | 3k, P-VOLCANO | LAUNCH |
| Volcano | Infernal Hydra (chase) | PROC `dragon` | 3 heads = extra Head/Jaw bones, PetMotion does not know them | 5k, P-VOLCANO | LAUNCH (needs PetMotion update or single-head design) |
| Volcano | Ashwing (weekly) | PROC `pterodactyl` | wings | 3k, P-VOLCANO | NICE |
| Volcano | Flarestrut (weekly) | PROC `ostrich` | biped | 3k, P-VOLCANO | NICE |
| Space | Nova Ptera (StarPterodactyl) | RIGGED | done | in rbxmx | LAUNCH (done) |
| Space | Void Dragon (CosmicDragon, chase) | RIGGED | done | in rbxmx | LAUNCH (done) |
| Space | Cometpup | PROC `wolf` | quadruped | 3k, P-SPACE | LAUNCH |
| Space | Moonhoot | PROC `griffin` | wings + legs | 3k, P-SPACE | LAUNCH |
| Space | Nebuclaw | PROC `raptor` | biped | 3k, P-SPACE | LAUNCH |
| Space | Lunar Tusk | PROC `mammoth` | quadruped | 3k, P-SPACE | LAUNCH |
| Space | Galaxy Strut | PROC `ostrich` | biped | 3k, P-SPACE | LAUNCH |
| Space | Zapstar (weekly) | PROC `pterodactyl` | wings | 3k, P-SPACE | NICE |
| Space | Quasar Rex (weekly) | PROC `trex` | biped + Arms | 3k, P-SPACE | NICE |
| Tower | Thornback (floor 5) | PROC `trex` | biped + Arms | 3k, P-FOREST or P-TOWER | NICE (can trail) |
| Tower | Frostbyte (floor 10) | PROC `wolf` | quadruped | 3k | NICE |
| Tower | Voltwing (floor 15) | PROC `griffin` | wings | 3k | NICE |
| Tower | Embergeist (floor 20) | PROC `phoenix` | wings | 3k | NICE |
| Tower | Astral Kitsune (floor 30) | PROC `wolf` | quadruped, 9 tail bones would be nice | 3k | NICE |

Counts: 10 rigged (all launch), 25 launch pets still PROC, 10 weekly PROC, 5 tower PROC. New meshes needed for launch: 25 x 3k-5k = about 80k tris authored (one Meshy piece each, under the 20k cap). Followers use `Lod`/`Tiny` options of PetModel (procedural fewer parts): a mesh pet needs a decimated LOD mesh (about 1,200 tris) or the lobby with 12 followers pays full price (12 x 3k = 36k).
Existing 10 meshes: tri counts and mesh-id ownership NOT verified here (rbxmx only carries ids); check in Studio that all 10 `rbxassetid` ids are owned by kcdrewcarter (20194281) or the group.
Boss mobs: `TowerConfig.Mobs` Boss* (6) reuse the rigged pet models scaled up and tinted red (`TowerView.bossBody`), so bosses cost no new asset. Mob species with rigged meshes: Raptor, DireWolf, Mammoth, Griffin, FrostWyvern, LavaTRex.

## 3. Eggs, nests, baskets, tappers, hatchers (the shared kit; used in every zone)

| Asset | Current state | Rig / anim | Budget, group | Priority |
|---|---|---|---|---|
| Pile egg (150 per hunt, 4 shell patterns x tints) | PROC: `GeodeModel.rockShell` (GeodeModel.luau:252, "REPLACE: real egg mesh"), up to about 10 Parts per egg (ball + spot/zigzag/stripe/dot decals), `Low` mode fewer. PileView.luau:133 | wobble/crack by code (EggFx, CFrame shakes) | 1 egg mesh, 250 tris, S-EGG with 4 spot textures (one MeshPart per egg instead of 10 Parts = about 1,000 fewer Parts) | LAUNCH |
| Egg shell halves (crack/hatch reveal) | PROC (`GeodeModel.frontHalves`) | tween halves | 2 meshes 150 tris each, S-EGG | LAUNCH |
| Hatch nest on the plate, 4 levels Straw/Wood/Stone/Gold (ProgressConfig.luau:31-36) | PROC straw ring + cushion (`StationModels.luau:228`, 542; `GeodeModel.luau:111`) | none (egg sits, cracks) | 4 skins of one mesh, 600 tris, S-GADGET (colour per level already data driven: Color/Dark/Material) | LAUNCH |
| Basket, 9 levels Starter..Golden Basket (ProgressConfig.luau:17-27) | ONE old kit mesh `Basket_Empty`/`Basket_Filled` (CarryView.luau:71) for all levels, scaled | carry pose via ToolAnim code | Wagon, Wheelbarrow, Egg Cart, Giant Crate are different objects by name: 5 distinct meshes (basket, wagon, barrow, cart, crate) about 500 tris each, S-GADGET | LAUNCH (5), rest tint |
| Tappers (Wooden Mallet / Golden Mallet / Rainbow Tapper) | old kit hammer meshes `Tool_StarterHammer/SteelHammer/Jackhammer` (WorldBuilder.luau:129); names changed but art is the old hammer / jackhammer | swing/hold = ToolAnim code | 3 meshes 300-800 tris, grip at origin, S-GADGET | LAUNCH |
| Tool skins (Copper Heads, Night Steel) | colour only (Config.Products ToolSkin, ProductId 0 = hidden) | none | recolour, no mesh | NICE |
| Gallery themes (Amber Glow, Glacier Trim) | colour only | none | recolour | NICE |
| Hatchers Auto Hatcher / Egg Press / Mega Hatcher | PROC pastel gadgets (MachineModels.luau:9, 314 "REPLACE: real gadget mesh"); old kit `Auto_Cracker / Hydraulic_Press / Industrial_Crusher` exist but are disabled | MachineView animates named pieces (KitJaw, KitPress, KitRoller attributes) | 3 meshes 2-3k each, 2-4 moving pieces, S-GADGET | LAUNCH |
| Shell sell stand (2 per arena) | PROC wood hopper (`ArenaKit.luau:847 woodHopperParts`) | none | 1 mesh 1.5k, S-GADGET | LAUNCH |
| Robux eggs Basic / Rare / Mythic (hatch stand, Egg Shop) | reuse the same `rockShell` | hatch show | 3 egg skins, S-EGG | LAUNCH (but ProductIds are 0) |
| Coin / shell pickup, hit sparks | particles + Parts (EggFx, HitFx) | code | none | n/a |
| Pet type icons Coins/Speed/Luck | procedural UI icons (UI.luau:628 "REPLACE with the owner's icon art") | none | 3 images 128 px | NICE |
| Boot icon on egg (speed boots) | drawn stand-in (EggFx.luau:133) | code | 1 small mesh/image | NICE |

## 4. Environments

### 4a. Lobby park (ParkBuilder.luau + LobbyBuilder + LodgeBuilder + ParkConfig)

All Parts ("Everything is procedural Parts (REPLACE: real jungle / dino / nest meshes)", ParkBuilder.luau:10). Only the cliffs use the old kit meshes (Cliff_*, with Part fallback). No rig needed anywhere (static props); lanterns/water none.

| Asset | Current state | Budget, group | Priority |
|---|---|---|---|
| Jungle edge: palms + trees (`palm`, `tree`, ParkBuilder.luau:124-166) | few-part low-poly | 3 tree meshes + 2 palms, 400-700 tris, instanced about 40 x = about 24k, S-LOBBY | LAUNCH |
| Giant dino skulls (2) (:175) | Parts | 1 mesh 3k | NICE |
| Mossy cliff ring / valley (`buildValley`) | old kit `Cliff_A..E` + Part stepped fallback | 5 cliff pieces 1.5-3k, S-LOBBY (re-skin to jungle) | LAUNCH |
| 12 fenced plots with glass display domes (`buildPlot`, :243) | fence Parts + dome | fence 300 tris x12, dome mesh 300, plot sign 100, S-LOBBY | LAUNCH |
| 4 queue nests with colour glow + sign (`nest`, :380-466) | twig rolls Part ring | 1 nest mesh 1k + glow disc, 4 tints, S-GADGET | LAUNCH |
| Leaderboard crown / RAREST PET board + trophy | `ParkBuilder.crown` (:211), Lodge boards | 1 crown 1.5k, boards flat | NICE |
| Stone paths, lantern posts, bushes | Parts | lantern 250, bush 300, paths = flat meshes/textures | LAUNCH (lantern), rest NICE |
| Spawn plaza stalls (Collection / Upgrades / Sell) | old kit `Lodge_*Stall` meshes (live) else Part stall (`LodgeBuilder.luau:136`) | re-theme to jungle stalls 3 x 3k | NICE |
| EGG SHOP hut + egg shelf | timber Parts + procedural eggs (`LodgeBuilder.luau:316-358`, 326) | hut 4k, uses S-EGG | LAUNCH |
| Hatch stand (public) (`buildHatchStand`, :655) | Parts + sign | pedestal/podium 2k | LAUNCH |
| PET TOWER doorway / `TowerPortal` (`buildTower`, :619) | Parts + sign | gate/arch 5k, purple S-TOWER | LAUNCH |
| Signs (ParkSign, WhatsNew, TowerSign, HatchSign, QueueSign) | `KitPlace.signBoard` Parts + SurfaceGui | keep (text boards) | n/a |

Lobby total estimate with budgets: environment about 110k + 12 followers x 3k (36k, or 14k with LOD) + 12 avatars about 60k = about 205k (about 180k with follower LOD) vs cap 200k.

### 4b. Hunt zones (5 zones; today ONE shared Meadow arena)

Shared arena content today (ArenaBuilder / ArenaKit, Parts): ground + dirt/halo patches, pile pad, 4 stations (tables + nests), 4 machine bays, 2 sell stands, west picnic shelter + hay bales + crates + pallet, east lamp mast, tool shelter, hedges, hills, trees, bushes, flowers, boundary (invisible octagon apothem 43, playable about 86 studs), kit `Strata_*` cliffs ring + `Rubble_Skirt`. Part-based balls and blocks (`ArenaKit.luau:1080 "REPLACE: real mesh (hill / tree / flower)"`).

| Zone | What exists | What is missing (new assets) | Budget / group | Priority |
|---|---|---|---|---|
| Meadow | the shared arena (green, hay, hedges) | meshes for hills (3), hedge, tree (3), flower patch, hay bale, shelter, lamp mast, pile mound, fence | arena scenery 25-35k, E-MEADOW | LAUNCH |
| Forest | NOTHING (same Meadow arena) | forest ground, big trees (4), mossy rocks (3), log, mushroom, ferns, vines wall, dappled sky/lighting; recolour station props | scenery 30-40k, E-FOREST | LAUNCH |
| Snow | NOTHING | snow ground, ice cliffs (3), pine (3), snowmen/igloo, ice boulders, frozen pond, snow lighting | 30-40k, E-SNOW | LAUNCH |
| Volcano | NOTHING | black rock ground, lava river/pool (animated texture), volcano cone backdrop, obsidian spikes (3), embers, red lighting | 30-40k, E-VOLCANO | LAUNCH |
| Space | NOTHING | asteroid platform, crater, floating rocks (4), planet/nebula backdrop (Skybox, not tris), neon crystals | 25-35k, E-SPACE | LAUNCH |

Zone hunt tri estimate (mine, new-asset design): 150 eggs x 250 = 37.5k, 4 nests 2.4k, 4 hatchers (owned ones) about 10k, 2 sell stands 3k, scenery 25-40k, 4 baskets/tools about 4k, 4 racer avatars about 20k = **about 100-120k per zone** vs the 120k phone cap. The egg is the single biggest cost: 150 x 10 Parts today versus 150 meshes at 250 tris.
Needs animation: lava (texture scroll), embers/snow (ParticleEmitters), none rigged. Lighting/sky per zone is code (Lighting) not assets; no tier lighting code exists.

### 4c. Pet Tower (TowerBuilder.luau, TowerConfig.luau)

| Asset | Current state | Budget, group | Priority |
|---|---|---|---|
| Fighting floor (disc, ring, pillars, caps; pet half blue / mob half red) | PROC Parts, recoloured per theme by `TowerBuilder` (line 87+) | 4 theme kits (Jungle, Lava, Ice, Space): floor disc + 6 pillars + ring about 3-6k each, S-TOWER (palette swap 4 colours exist in `TowerConfig.Themes`) | NICE (works today as recolour) |
| 6 normal mobs: Slime, Grumpy Beetle, Mushroom Hopper, Thorn Snail, Rock Crab, Ghost Puff | one generic "round critter" Part body recoloured by element (`TowerView.luau:68`, "REPLACE with real mob meshes") | 6 meshes 800-1,500 tris, bob/lunge by code, S-TOWER | NICE |
| 6 bosses (Raptor, DireWolf, Mammoth, Griffin, FrostWyvern, LavaTRex) | reuse the 10 rigged pet meshes scaled, tinted red, glowing eyes | none new | done |
| 5 tower pets | see section 2 | 3k each | NICE |
| Tower entry (lobby) | see 4a | | LAUNCH |

Tower tri estimate: floor kit 6k + 3 team pets 9k + up to 4 mobs 6k + boss 5k + avatar 5k = about 30-45k, far under cap.

## 5. Shared / UI-adjacent

| Asset | State | Priority |
|---|---|---|
| Pet follow aura / sparkles / rarity light | PointLight + Sparkles per rare pet (PetModel.luau:88) | keep; Low Effects hides |
| Hatch show props (stand, confetti) | Parts + particles (HatchStandView) | NICE |
| Hatch reveal egg + pet | `RevealView` uses `GeodeView` + procedural egg halves | uses S-EGG assets above |
| Sounds for pets | all roar ids = shared `HatchRoar` (SoundConfig.luau:20-50 REPLACE); not 3D art | separate audio task |
| Meshy tree/sign scripts | owner rule: zero scripts inside Meshy models (audit item 3) | enforce on import |

## 6. Totals and priorities

| Group | Count to author | Tris (est) | Priority |
|---|---|---|---|
| Launch pets without mesh | 25 (5 are chase, 5k) | about 85k authored | LAUNCH |
| Weekly pets | 10 | 30k | NICE (needed when `Config.WeeklyPets.Start` is set; 1 per week so one every 7 days) |
| Tower pets | 5 | 15k | NICE |
| Egg + shells + nests (4) + baskets (5) + mallets (3) + hatchers (3) + sell stand | about 20 small meshes | about 20k | LAUNCH |
| Lobby park props + buildings | about 25 meshes | about 60k | LAUNCH (trees, cliffs, plots, nests, egg shop, hatch stand, tower gate) |
| Zone scenery Forest / Snow / Volcano / Space | 4 zones x about 12 meshes | 4 x 35k | LAUNCH |
| Meadow scenery (re-mesh the Part balls) | about 12 | 30k | LAUNCH |
| Tower mobs (6) + floors (4 themes) | 10 | 30k | NICE |

| Zone | Est. visible tris in hunt | Phone cap (mine) | Note |
|---|---|---|---|
| Lobby | about 180-205k | 200k | tightest; needs follower LOD and tree instancing |
| Meadow / Forest / Snow / Volcano / Space | about 100-120k each | 120k | eggs 37.5k are the main cost; scenery 25-40k |
| Pet Tower | about 30-45k | 120k | fine |

Pipeline risks to settle before mass-producing: (1) variant recolour clears `TextureID` and tints all non-Neon parts, so eyes/teeth need Neon or a skip tag; (2) PetMotion only knows the 10 named bones (no 3-head Hydra, no 9-tail Kitsune); (3) meshes must be uploaded to the owner's account/group or they may fail to load for others; (4) Meshy outputs have their own materials: use the zone atlas, not per-asset materials, to stay within Roblox's texture memory on phones.
