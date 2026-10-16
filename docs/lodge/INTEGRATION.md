# Prospector Lodge: game integration

The public lobby is now the Prospector Lodge from the owner's lobby pack (MASTER_PROMPT_Claude_Blender.md, BUILD_NOTES.md,
FURNISHING_NOTES.md). The uploaded kit (Lodge_Building, Lodge_Plaque and 30 furnishing meshes, ids in
`src/shared/MeshIds.luau`) is placed by Luau code in the real game. The old open-air courtyard (terminal, tool counter,
lectern, sell chute, records frame, paving, courtyard walls, benches, trees) is no longer built.

Status: offline only (Lune preview + Rojo build). **Nothing here is Studio-tested**: real lighting, collisions, prompts,
SurfaceGui text, avatar thumbnails and the mesh import scale/axes in Studio are unverified.

## Code

| What | Where |
|---|---|
| Lodge: building, colliders, plaque, stalls, hunt bays, boards, rubble counter, decor, lights, pocket frames, clear zones | `src/server/LodgeBuilder.luau` (new) |
| Lobby assembly: owner display pockets (cabinet module), yard, quarry vista, waterfall, spawn, return contract | `src/server/LobbyBuilder.luau` (rewritten; the courtyard builders were removed) |
| Live board rows on the kit frames (`createLodgeContent`, mounts with attribute `Bare`) | `src/server/LobbyBoards.luau` |
| Client | unchanged (`UpgradePreview` finds the pedestal by its existing names; no client edit was needed) |

## Frames (verified in the preview)

Placement values are in lodge model space = the repo pipeline mapping, Roblox (X, Y, Z) = Blender (-X, Z, Y)
(BUILD_NOTES / FURNISHING_NOTES). A kit asset goes at `PIVOT * CFrame.new(pos) * CFrame.Angles(0, rad(yaw), 0)`.
`PIVOT = CFrame.new(0, 3, 0) * CFrame.Angles(0, pi, 0)`: the lodge floor is at world y 3, the yard at 0, and the lodge
is turned half a turn so the door faces +Z (the yard) and the hunt wall faces -Z (the waterfall and the quarry vista).
In world terms: world = (Blender X, 3 + Blender Z, -Blender Y). Checked in the renders: the door opening, the open door
leaves and both front benches sit where the master prompt puts them (`renders/game/front-*.png`, `exterior-*.png`),
Upgrades is on the left and Collection on the right seen from the spawn, the boards face the hall.

## Destinations and contracts kept

| Destination | What the player uses | Contract (grepped, unchanged for other code) |
|---|---|---|
| UPGRADES stall | prompt on the counter collider | Part `Counter`, ProximityPrompt `Panel = "Shop"` (opens the existing Shop) |
| Upgrade preview | kit specimen pedestal on the counter | Model `CT_Rocks_UpgradePedestal` (attribute UpgradePedestal), `PreviewAnchor` (PreviewHeight 2.6), `PreviewLabel` sign; `src/client/UpgradePreview.luau` unchanged and working in the preview |
| COLLECTION stall | prompt on the counter collider | Part `Counter`, `Panel = "Collection"` |
| Collection display | three EXAMPLE geodes on the counter pedestals (GeodeModel.onStand: Amethyst, Celestite, Citrine), crystal clusters in the glazed shelf, plaque DISPLAY EXAMPLES | tagged `Decorative`, no Id, in no profile; kit display geodes only as a fallback |
| START HUNT bays | one prompt per bay (3) over the pads | Part `Cabinet` with "Start Hunt", `Panel = "Party"`, range 16: the existing hunt panel. No queue, countdown, minimum players or automatic start |
| RUBBLE SELL | prompt on the counter | Model attribute `Hopper`, part `Body` with ProximityPrompt `SellPrompt` (attribute Sell): the one EconomyService sell endpoint; the HUD "SELL HERE" marker finds it |
| SOLO FINDS / COMPETITIVE WINS | two kit boards, five live rows each | `BoardMounts/Mount_Solo`, `Mount_Wins` (attribute `Bare`) -> LobbyBoards rows from LeaderboardService (Solo = Stats.SoloFinds, Wins = Stats.MultiplayerWins). Studio saves-off shows "Records unavailable in this Studio test" as before. No example names or scores anywhere. Biggest / Collection boards are still kept by LeaderboardService but no longer drawn in the world |
| Owner displays | 16 pockets | `CT_Rocks_Gallery/CT_Rocks_Alcove_<i>` with `Floor`, `SideL`/`SideR`/`ShelfLight`, Alcove fields and `SetCapacity` unchanged; GalleryService untouched; real capacities 3/6/12/20; real specimens only |

Signs (all `KitPlace.signText` + `SignLayout`, audited by the `signs` scene): UPGRADES, COLLECTION, START HUNT,
RUBBLE SELL, SOLO FINDS, COMPETITIVE WINS (Landmark), FIND THE GEODE on the exterior plaque (Landmark), DISPLAY
EXAMPLES and PREVIEW (Plaque).

## Owner display cabinets

16 pockets, never in the open centre (Blender X -22..22, Y -20..14) or in an 8-stud access strip:
2 + 2 on the side walls between the entrance and the stalls, 2 on the Upgrades side wall behind the stall, 1 on the
Collection side wall beside the rubble counter, 1 in the rear Upgrades corner beside SOLO FINDS, 8 along the front wall
either side of the door (behind the spawn, facing the hall). To fit, the cabinet module is narrower: a 20-slot display is
now 4 x 5 (6.8 wide, about 10 tall with the nameplate) instead of 5 x 4; 3 / 6 / 12 keep 3x1 / 3x2 / 4x3. The fifth row
is filled last but one (eye-level rows first). Pocket indices 1..16 and GalleryService ids/records are unchanged.

## Decor changes against art/lodge/furnishing_placement.json

The eleven assemblies and every child on an attach point follow the JSON. To make room for the cabinets: the stall
front-end crates and planters, the front-corner and rear-left planters, the rubble-side crate and its lantern are left
out; one planter + plant stands at each stall's front end on the room side (z -15), two crates at the Upgrades rear end,
the two side wall lanterns moved to z -13.4. Everything else (benches, rug, runner, chandelier, posters, rear-right
planter, trophies, emblem, bay lanterns) is where the furnishing pass put it.

## Collision, camera, fallbacks

- Kit meshes never collide (MeshService). Invisible anchored boxes from the manifest: the shell (floor, walls around the
  door opening, gables, ceiling, porch, steps, rails, hidden smooth ramp over the steps), counters and stall backs, the
  bay dividers and back frame, both boards, the rubble counter and back, benches, crates, planters. Pads, rugs, lamps,
  chandelier, posters, plants and trays have none.
- Every decorative kit model carries CameraIgnore; `KitPlace.decorPolicy` covers the rest.
- Every kit asset has a Part stand-in (`StandIn` attribute = REPLACE marker) built when its mesh did not load: a hand
  built shell for the building, simple counters/awnings/boards/bays, a bounds box for small decor. Check:
  `bash tools/preview/render.sh lobby --set kit=off` (regression `smoke:lobby kit-off`).

## Lighting

Global Lighting is unchanged (the hunts are outdoors and share it). Inside: 14 PointLights, shadows off, no visible
fixture brighter than the kit's small Neon diamond cores: chandelier 3 (of its 6 lanterns), two high warm fills under the
tie beams, the Upgrades / Collection / rubble counter lanterns, the two inner bay wall lanterns, the two side wall
lanterns, one soft wash per board. Plus each claimed cabinet's existing SurfaceLight. The roof shades the hall, so in
the preview the interior reads darker than the painted target; real Roblox brightness was not checked.

## Outside

Ground, a stone path to the porch, four planting beds by the porch (the client's butterflies use them), pines, kit cliff
rows (taller toward the north so the rear windows frame a quarry wall), the crane silhouette far north, and the existing
waterfall moved to (-14, 0, -74), north of the hunt wall (still animated by `LobbyAmbience`, unchanged). An invisible
boundary keeps players in the yard.

## Checks (offline)

- `bash tools/check.sh`: zero diagnostics, 154 rule tests, build.
- `bash tools/run_regressions.sh`: 45/45 PASS (incl. the new `smoke:lobby kit-off`).
- `placement` scene: lobby audit against the lodge floor (y 3) and `LodgeBuilder.ClearZones` (open centre, entry walk,
  bay entrances, counter / seller / board access strips): PASS. Items set on an assembly share a `MountGroup` so a
  lantern on a counter is not a clip; the hunt bays are a `WalkIn` structure.
- `check_lobby.py` on a phone-1108 render: all eight zones CLEAR.
- `signs` scene: every lodge title present once, all fills in range.
- Renders: `docs/lodge/renders/game/<view>-<device>.png` (pc, phone-1108): spawn, upgrades, collection, bays, boards,
  boardswins, seller, owned (a claimed owner cabinet with 4 specimens), pocket (unclaimed), front, exterior;
  `board-face-solo-pc.png` (the live row layout drawn on a ScreenGui, seeded preview rows) and `fallback-spawn-pc.png`.

## Differences from the target (00_Approved_Lobby.png) and open items

- The painting's camera stands further back and higher; the first-person spawn view shows the same arrangement (boards
  either side of START HUNT, red UPGRADES left, purple COLLECTION right, rubble counter by Collection, chandelier),
  closer. Board faces and sign text are SurfaceGuis, which the preview does not draw (blank/black there).
- Interior lighting is dimmer than the painting in the preview; tune in Studio (fill brightness in `buildDecor`).
- Not verified in Studio: import scale/axes of the large building mesh, collisions (door, steps, ramp), prompt choice
  between the three bay prompts, avatar thumbnails (`rbxthumb://` content), lighting, performance on phones.
