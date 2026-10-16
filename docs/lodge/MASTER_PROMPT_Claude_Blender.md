# Find the Geode — Prospector Lodge Blender master prompt

Paste this entire document into Claude with the reference images in this pack. Build the actual Blender assets and assembled scene. Do not stop at a plan or substitute another concept. The requested deliverables are a complete building model, separate reusable furnishing assets, an assembled lobby scene, exports, and placement documentation. This pack contains references and instructions, not completed 3D models.

## 1. Approved target and reference priority

Recreate the approved warm indoor Prospector Lodge as closely as practical: timber framing, cream plaster, neutral stone floor, red-and-cream Upgrades awning on the left, purple-and-cream Collection awning on the right, three rear hunt bays, and two permanently visible world leaderboard boards. Keep the central gathering area open. This is a compact Roblox public lobby for Find the Geode.

Reference precedence is: (1) this document's functional rules and explicit dimensions; (2) 00_Approved_Lobby.png for the design identity and arrangement; (3) asset sheets for component forms; (4) additional perspectives for spatial understanding. Generated views are illustrative and can contain inconsistent small details. Do not combine all differences into a larger or cluttered scene. In particular, the cutaway intentionally removes the roof and some front wall geometry so placement can be seen. It is NOT an open-air courtyard and is NOT the final shell.

The reverse view correctly swaps the screen positions of Upgrades and Collection because the camera looks in the opposite direction. It must not cause their world positions to swap. Do not duplicate the rear leaderboards onto the entrance wall.

The complete exterior is a supporting design for surfaces not visible in the approved interior. Preserve the interior even if the exterior illustration suggests slightly different proportions. Match the composition, silhouettes, colors, relative scale, and spatial organization, rather than treating generated pixels as engineering measurements.

## 2. One building asset, separate furniture

Deliver Lodge_Building as ONE assembled structural asset with one root pivot and one building export. It includes the floor, foundation, walls, roof, exposed roof beams, timber columns, braces, window frames, window inserts, entrance frame and door leaves, porch, steps, and entrance rails. It must be fully enclosed except for designed door openings. All pieces are already aligned; the user must not assemble individual walls in Roblox.

One asset does not mean one indivisible mesh. Use a clean hierarchy of material-specific meshes inside Lodge_Building. Keep transparent windows separate from opaque surfaces. Separate door leaves with hinge pivots if needed, but deliver them positioned inside the building assembly. Do not join every surface, glass pane, and collision shape into one enormous mesh.

Furnishings remain separate reusable assets: counters, awnings, signs, tool display, specimen displays, hunt bays, leaderboards, furniture, lamps, and decor. Deliver an additional Lodge_Furnished scene/model where they are already placed. The assembled scene and structural building must use the same world origin. Importing the building should not require hand-aligning 30 loose exports.

## 3. Game scope

The lobby is public. Hunts are private solo or party sessions, supporting up to four participants. Each hunt contains one shared pile and exactly one target geode. Players collect neutral rocks, carry them to their own station, deposit them, and process them. This lobby rebuild must not introduce cracking in the public lobby or at the shared pile.

The three hunt bays are visual access points for the existing hunt creation interface. Do not implement automatic countdown matchmaking, change minimum players, or invent different modes. A player may choose solo through the existing flow. The geometry of the bay is not the match logic.

Keep Solo Finds and Competitive Wins separate. Only the winner receives the round's target specimen; ordinary earnings remain individual. No pets, classes, eggs, extra currencies, new maps, prestige, or new upgrade effects. Counters open existing menus. Expanding the tool catalog must not require expanding the building or adding a room for every tool.

## 4. Coordinate system and units

Use Blender X right, Y toward the rear, Z up. Work in a documented design-unit convention: 1 Blender unit = 1 intended Roblox stud. This is a design convention, not a promise about importer scaling. Test the export scale before finishing. Clear interior limits: X from -42 to +42, Y from -34 to +34. Finished interior floor top is Z=0. Root origin is (0,0,0). Front entry is at negative Y; back hunt wall is positive Y.

The room is 84 wide by 68 deep. Wall eaves reach Z=26. Roof ridge reaches Z=40 along the Y direction, with the ridge at X=0. Walls are 1.2 thick outside the clear interior boundary. Roof overhang is approximately 2. Floor slab extends down to Z=-1; foundation extends to approximately Z=-3. The front porch may extend to Y=-44. Door opening is 18 wide and 14 high, centered at X=0 on the front wall. Rear-facing windows preserve the quarry view, but rear walk-through exits are not required.

Mapping for placement documentation: Roblox (X,Y,Z) = Blender (X,Z,-Y), a right-handed rotation convention. Actual FBX axis conversion must be checked against this convention rather than applied twice. Include a temporary orientation test object and one 5-stud height marker in validation exports; exclude both from final game exports. Verify one bench and one door opening in Roblox before batch-exporting everything if Roblox is available.

All standing props have an origin at bottom-center. Signs have an origin at back-center. Local front faces toward Blender -Y unless specified. The placement manifest must contain root locations, rotations, bounding-box dimensions, and asset IDs. Rotations in the table below are Blender Z rotation degrees, counterclockwise from local front=-Y.

## 5. Authoritative layout

| Assembly | Root XYZ | Z rotation | Bounding footprint / height |
|---|---|---:|---|
| Lodge_Building | 0,0,0 | 0 | 84×68 interior; roof ridge40 |
| Upgrades_Stall | -37,0,0 | +90 | local width24, depth8, height13 |
| Collection_Stall | +37,0,0 | -90 | local width24, depth8, height13 |
| Hunt_Bays_Assembly | 0,+25,0 | 0 | width36, depth12, height14 |
| Leaderboard_Solo | -27,+27,0 | 0 | width13, depth2.5, height17 |
| Leaderboard_Wins | +27,+27,0 | 0 | width13, depth2.5, height17 |
| Rubble_Sell | +37,+17,0 | -90 | local width7, depth4, height10 |
| Bench_FrontLeft | -23,-24,0 | 0 | width12, depth3, height3 |
| Bench_FrontRight | +23,-24,0 | 0 | width12, depth3, height3 |
| Entry_Rug | 0,-28,0.025 | 0 | width14, depth8, thickness0.04 |
| Chandelier | 0,0,23 | 0 | diameter10; suspension extends to31 |

Within the hunt assembly, pads are centered at local X=-12,0,+12; each is 10×10. Dividers sit at X=-18,-6,+6,+18. Pads have low beveled trim, not a deep step or ramp. Sign spans the group at Z approximately12. Bay dividers stay approximately3 high, leaving sightlines open.

Maintain an open central zone at least X=-22 to+22 and Y=-20 to+14. No piles, machines, fountains, large rugs, specimen statues, pillars, or decorative furniture in this zone. The entry-to-hunt path remains clear. Leave at least8 studs of usable access in front of counters and leaderboards. Objects behind boards cannot obstruct paths into the bays. Do not place a tall plant over leaderboard rows.

The two boards face the central gathering area, not the side walls. They must be visible from the entrance and normal standing positions. Upgrades and Collection signs face inward across the room. A player should understand all three main destinations upon spawning. Camera shots looking backward do not redefine left and right.

## 6. Structural shell modeling

Build a floor slab and a restrained large-scale irregular stone surface. Do not model thousands of individual pebbles. A low-contrast texture or a small number of planar color patches is sufficient. Avoid deep grout that causes stepping or visual noise. Floor collisions should be a flat plane/slab even if the visual mesh has shallow detail.

Use repeating wall segments approximately14 studs wide, but assemble them into the final building. Lower wall panels are pale plaster over a modest stone base. Timber posts are about1.2–1.5 thick; braces are about0.65–0.9. The roof must have visible interior surfaces and normals. Do not depend on a single-sided roof plane that disappears from inside.

Place high windows principally between Z=16 and24. Use clear or lightly tinted panes and simple wood mullions. Avoid heavy blue opaque panes that hide the quarry vista. The front and rear gables can have high window sections. Do not create a full glass skyscraper facade.

Use approximately five structural truss stations along Y=-28,-14,0,+14,+28. Derive the trusses from the same dimensions rather than visually guessing each one. Keep overhead beams above player movement. The roof has two continuous pitched slopes, a ridge cap, and modest eaves. Use broad slate-brown roof panels, with restrained seam detail. Fully close front/rear gables around intended window openings.

Door leaves approximately8.5×0.5×13.5 use broad planks, a diagonal brace, simple dark hinges and handles. Keep them open approximately100 degrees for the approved entry composition, without sticking into the central route. Hinge pivots lie at the leaf edges. Porch steps are broad and shallow. Include a hidden smooth ramp collision option for mobile traversal. Front railing remains attached to the porch sides and must not block the door opening.

## 7. Upgrades assembly

Counter: local width24, depth5.5, countertop height4, total counter base height3.8. The countertop slightly overhangs. Use large wood panels, simple posts and a restrained bevel. Do not model every grain line. The stall has a shallow back panel and two structural canopy brackets, all within its8-stud depth.

Awning: width25, projection7, supported at rear Z approximately12.5 and front Z10.5. Red and cream alternating broad stripes. Use approximately10–12 stripes across the width, each with a shallow scalloped valance. The sheet's exact stripe count is not binding. Stripes are material assignments or a clean texture, not huge piles of overlapping geometry. Use a modest solidified fabric thickness and simple silhouette.

Wood sign: approximately12×0.35×3, positioned on the front canopy fascia; retain a blank planar front face for text. Approved label is UPGRADES. The text may be generated as a static sign texture or implemented as Roblox SurfaceGui. Do not bake label characters into tens of thousands of polygons.

Tool pegboard approximately8×0.25×5 sits above the counter. Use a texture for peg holes; do not boolean hundreds of tiny holes. Starter hammer is a simple faceted steel head with a warm brown handle, about3.5 long. Place one visual tool on the pegboard/stand. A cashbox and one compact basket occupy the ends. Do not fill the stall with every upgrade or create a workshop bay for each tool.

## 8. Collection assembly

Use matching base proportions to Upgrades, but a different purple-and-cream awning material. Preserve a COLLECTION sign with a blank text face. Include a lower shelf/display cabinet with three clear specimen positions, shallow backing and a clean viewing area. Glass panels are separate objects and use simple transparency; avoid dozens of overlapping panes.

Model three display geodes: violet, blue and amber. Each specimen is a credible hollow gray rock with a thick irregular shell, subtle pale inner mineral rim, recessed crystalline cavity, and clustered faceted crystals. Crystals emerge from the cavity interior rather than floating above it. Rock backs remain neutral gray. Avoid a painted flat purple patch, a sticker plane, or a giant exterior diamond.

A showcase geode may occupy roughly3.2×2.4×3.3. Use 12–24 varied crystals, not hundreds. Crystal prisms should have distinct 5–6-sided bodies and pointed caps. Match size variation deliberately, with the tallest crystal inside the cavity silhouette. Use shared rock geometry with palette variants when suitable. Include a separate crystal cluster and one empty tray as reusable assets. Pedestals are compact and stay below the awning/sign.

These lobby specimens are decorative previews or placeholders for the existing collection system. Do not invent rarity values, rewards, inventory entries, or currencies. Do not place collectible hunt targets in this public lobby.

## 9. Hunt bays and signs

Export the three-bay assembly as a placed reusable group and export one bay separately for reuse. Each pad has a charcoal center and muted gold frame, top elevation no more than0.12 above floor. Avoid strongly emissive yellow borders. Divider rails are wood with simple short posts. Keep all entrances wide and unobstructed.

The START HUNT sign is roughly18 wide and3.5 high. It is centered above the bays with a modest arch support and crossed hammer emblem. Use separate meshes for frame and emblem. Text belongs on a readable plane/SurfaceGui or clean static texture. Do not create distinct map names over individual bays. Do not bake player counts or countdowns onto the assets.

Add named empties for Bay01_Interact, Bay02_Interact and Bay03_Interact. These are integration attachment locations, not physical collision posts or automatic queues. Document that the existing Roblox hunt controller must own their behavior.

## 10. Permanently visible leaderboards

Create two identical reusable board frames, each approximately13 wide,17 high including trophy, and2.5 deep. The dark content panel occupies approximately11.5 wide and11.5 high, with lower edge around Z3.5. Keep the frame modest so it does not reduce the text area excessively.

Each board has a separate blank opaque face called BoardFace. Provide a named UI attachment and dimensions for a Roblox SurfaceGui. The displayed information is dynamic: heading, ranks, avatar thumbnails, names and real scores. Do NOT model or bake Player1/125 or any other example usernames/scores into the final mesh or texture. The two actual headings are SOLO FINDS and COMPETITIVE WINS. They must remain separate records.

Show five prominent rows without opening a menu. The top three have restrained gold/silver/bronze accents. The Blender scene may use replaceable preview text to establish proportions, but preview rows must be excluded from runtime asset exports and clearly named PreviewOnly. If actual Roblox code is outside your environment, document the integration rather than pretending leaderboard data was implemented.

Trophy emblem about1.8×1×2 sits above the frame. Use sturdy simple feet or mount the boards to the rear support structure. Avoid holograms, flickering text, animated scrolling needed for the top rows, bright light washing out lettering, or placement behind shop awnings. Always-visible means continuously displayed world boards, not an unavoidable screen overlay or readable through walls.

## 11. Rubble sale counter

Model a small side counter, approximately7 wide by4 deep, at the right-rear wall. One basket emblem and a wood sign reading RUBBLE SELL identify it. A small lantern can sit at one edge. Keep it secondary in scale and contrast. No giant hopper, oversized crushing apparatus, coin fountain, or item shower. The actual sale amount and behavior remain in the existing Roblox controller.

## 12. Furniture and decor inventory

Deliver these reusable pieces, with bottom-center pivots unless a wall-mounted exception is noted:

| ID | Asset | Suggested dimensions | Initial count |
|---|---|---|---:|
| P01 | Simple wood bench | 12×3×3 | 2 |
| P02 | Closed braced crate | 2.8 cube | 6 |
| P03 | Small cashbox | 2×1.2×1 | 1 |
| P04 | Rock basket | 3×2×1.8 | 2 |
| P05 | Cream planter | 2.2×2.2×2.4 | 6 |
| P06 | Angular leaf plant insert | 3×3×4 | 6 |
| P07 | Portable lantern | 0.9×0.9×1.6 | 8 |
| P08 | Wall lantern plus bracket | 1.2×1.5×2.2 | 6 |
| P09 | Ring chandelier | diameter10, bodyheight3 | 1 |
| P10 | Entry rug | 14×8×0.04 | 1 |
| P11 | Upgrade runner | 16×4×0.04 | 1 |
| P12 | Framed geode poster | 8×0.25×4 | 1 |
| P13 | Framed mineral poster | 8×0.25×4 | 1 |
| P14 | Empty specimen tray | 2.5×1.8×0.25 | 3 |
| P15 | Compact specimen pedestal | 2.7×2.7×1.2 | 3 |
| P16 | Trophy emblem | 1.8×1×2 | 2 |
| P17 | Crossed hammer emblem | 3×0.5×3 | 1 |

Place crate pairs close to the counter ends. Plants belong near stall ends and rear/front corners, never over leaderboard content or bay entrances. Posters sit high on the side walls above the stalls. Keep the open center empty.

Lantern bodies use simple dark metal frames, warm pane inserts and a small diamond-shaped light core. The pane glow is restrained, not a large bloom cloud. The chandelier uses six repeated lanterns attached to one wood ring. Chains should use a simplified low-poly representation rather than dense linked physics geometry. Rugs must be a shallow plane/slab with a texture or broad material border; the asset sheet's apparent thousands of woven squares must NOT be literal geometry.

## 13. Materials and textures

Create a shared palette and name materials consistently. Suggested starting sRGB colors: WoodMain #A9693F; WoodDark #70452D; Plaster #E7D6B8; StoneMain #A79F90; StoneDark #827B71; MetalDark #343639; Steel #8E9AA6; AwningCream #FFF0D0; AwningRed #D94D52; AwningPurple #9555BF; Gold #E1B443; BoardCharcoal #282B30; PlantGreen #659B35; CrystalViolet #9B5DE5; CrystalBlue #55B7E8; CrystalAmber #E8B54B. Match the approved image perceptually and avoid excessive orange saturation.

Use moderate roughness: wood/plaster/stone0.7–0.9, metal0.35–0.55, crystal0.25–0.4. These Blender values guide renders and may require mapping in Roblox. Do not rely on procedural Blender shaders, displacement, compositor glow or node effects that will not export. Bake necessary appearance to ordinary texture maps or document Roblox material assignments.

Aim for a small shared opaque atlas for furniture and a separate architecture atlas if textures are needed. Use1024 or2048 texture sizes as a starting budget, not4K textures for every prop. Keep transparency separate. Make signs crisp at normal viewing distance. Large texture noise should not dominate the floor or wood. No imagegen watermarks or sheet captions in exported materials.

## 14. Geometry and export quality

Use broad forms first, then limited bevels and structural details. A low-poly result still needs believable thickness and deliberate silhouettes. Avoid plain boxes for every object, but also avoid sculpted millions-of-polygon models.

Suggested planning budgets, not platform maximum claims: complete structural shell20k–45k triangles; counter assembly2k–5k; leaderboard frame/emblem1k–2.5k; geode1k–3k; bench300–700; crate150–400; lantern200–500; planter with plant400–900. Target assembled visible lobby around100k–150k triangles or less, using repeated shared assets. Report actual counts. Do not silently exceed these targets; simplify details that contribute little to the view.

Apply scale and rotation appropriately, resolve negative-scale instances, clean normals, remove loose vertices and accidental internal faces, avoid z-fighting, and verify UVs. Keep transparent meshes and UI faces separate. Use bevels roughly0.03–0.08 on small props,0.08–0.15 on larger counters, adjusted for the intended visual scale. Use weighted/custom normals only where supported and validated; never assume a Blender modifier exports automatically.

Provide simple collision proxies separately from render geometry. Shell collision must preserve the hollow interior and openings: do not use one convex hull that seals the entire building. Floors use flat collision. Walls use boxes arranged around openings. Counters and boards can use simple boxes. Small decoration and chandelier should normally be non-collidable in Roblox. Keep collision meshes clearly named COL_ and explain whether they need conversion to invisible Roblox Parts rather than assuming automatic collider recognition.

## 15. Scene hierarchy and repeatable build

Organize collections:00_References;10_Building;20_Upgrades;30_Collection;40_HuntBays;50_Leaderboards;60_Seller;70_Decor;80_Collision;90_CamerasLights;99_PreviewOnly.

Use root empties for all assemblies, descriptive stable names and reusable mesh datablocks. Keep the fully assembled scene at the authoritative coordinates. Make no gameplay scripts, unexplained online downloads, random asset IDs, or destructive changes to unrelated project files.

If generating the model through Blender Python, deliver the actual script. Centralize dimensions, palette and layout in configuration. Use a fixed seed for any rock variation. The script should create/update only its own named collections and be safely rerunnable. Save the .blend after generation, render the review cameras, export meshes, and write an asset manifest. A script alone is not proof that it ran: report whether Blender execution and exports were actually verified.

## 16. Lighting and cameras

Use daylight through windows and modest warm interior lanterns. Preserve cream walls rather than turning the entire lodge orange. No oversized bloom, blown-out panes, atmospheric fog inside, or extreme glossy reflections. Blender lights are preview lighting; Roblox runtime lighting requires separate configuration. Do not claim preview lights automatically export as usable Roblox lights.

Provide these review cameras in Blender coordinates: Approved_Front at(0,-31,11) looking toward(0,15,7); Player_Eye at(0,-27,5.2) looking toward(0,23,6); Reverse at(0,27,9) looking toward(0,-23,6); Cutaway at(-65,-70,65) looking toward(0,0,7); Exterior at(-100,-110,65) looking toward(0,0,14). Use appropriate focal lengths to capture the room without fisheye distortion. Render cutaway through temporary visibility controls, not by deleting the roof from the final asset. Final exterior render must show a complete roof and enclosed walls.

## 17. Deliverables

Deliver: FindTheGeode_Lodge.blend; Lodge_Building.fbx with all structure preassembled; Lodge_Furnished.fbx if the import pipeline supports a suitable grouped scene; separate furnishing exports in assets/; textures/; asset_manifest.json; placement_manifest.csv; collision_notes.md; build_lodge.py if procedural generation was used; and preview renders for the five cameras plus contact sheets of finished assets.

The manifest must document model dimensions, triangle counts, materials, texture paths, pivot location, attachment empties, collisions and export settings. Preserve blank dynamic text faces. Include at least one benchmark export with verified intended scale. If FBX is not supported by the actual environment, use the currently supported Roblox-compatible format and document the substitution rather than generating an invalid file.

Avoid using FBX files alone as a claim that a ready-to-run Roblox Model exists. State which Roblox import and gameplay integration steps remain. Never invent a .rbxm or .rbxl file unless you actually created and validated it.

## 18. Required build sequence and verification

First create the complete shell and block out assemblies at the exact coordinates. Render the approved camera and check proportions. Then refine the architecture; refine counters and awnings; add the boards and bays; model specimens and small decor; implement materials; validate exports. Do not spend time detailing a crate before the room composition matches.

Before claiming completion, confirm: full roof present in normal/exterior views; door opening traversable; inward-facing counters; both boards visible from entry with unobstructed faces; three accessible hunt bays; no objects in the main center path; no shell collision sealing the interior; player-height scale; consistent pivots; no image-only fake details replacing important forms; no sample usernames baked into runtime meshes; no excessive rug/peg-hole geometry; textures resolve; exports reopen correctly; all claimed files actually exist.

Compare the final front view directly with00_Approved_Lobby.png. Report any meaningful visual differences and correct them before presenting the finished model. Do not replace this lobby with another art direction or call an untextured blockout finished.

## 19. Roblox integration boundary

Modeling is the requested work. Preserve the game's existing menu controllers, economy, collection persistence and hunt logic. Blank sign surfaces can receive SurfaceGuis; permanent leaderboards need server-fed real data; lamps need carefully budgeted Roblox lights; bays need existing interaction handlers; specimen positions need attachment markers. Document those hookups accurately. If the current environment provides the Roblox project and authorization to integrate, wire into existing systems instead of building duplicates. Otherwise deliver clear integration instructions and mark gameplay testing as unperformed.

Start working on the assets and scene now. Keep all geometry coherent with the approved reference and this placement specification. Deliver an assembled building that I can import as one model, reusable furnishings already placed in the furnished scene, and evidence of the real output.

## 20. Exterior finish sheet clarification

Sheet06 adds exterior finishing references, not another building kit. The porch, doors, ridge/eaves and foundation are already included in Lodge_Building. Make one separate blank exterior title plaque approximately14 wide,0.5 deep and5 high, mounted above the front door without covering its opening. Its actual label is FIND THE GEODE. The oversized multicolor gem logo in the exterior concept is optional styling, not a required new identity. Use restrained lettering on the plaque to preserve readability.

Pine trees, cliff modules and short fence sections are optional background assets used to frame the window vista and entrance approach. They must not create a new gameplay area or delay finishing the interior. Suggested sizes: pine12–18 high; cliff module20 wide by10 deep by15 high; fence6 wide by0.7 deep by3 high. Keep scenery in a separate collection/export. The exterior illustration suggests a small secondary gable: the authoritative build uses the simple continuous pitched roof specified above. Do not add extra roof wings or change the approved room footprint to match that incidental image detail.
