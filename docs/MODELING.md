# Modeling: Blender -> Roblox models

Real 3D models (not Roblox blocks): built in Blender by Python, exported as FBX, uploaded once by the owner's PC,
loaded at boot by `src/server/Systems/Meshes.luau`. Style: chunky low-poly, flat shaded, bright cartoon, always sunny.
Until a model has an id (0) every caller keeps its Part stand-in, so nothing breaks.

## Tools
- Setup (cloud): `python3 -m venv /tmp/bpyenv && /tmp/bpyenv/bin/pip install bpy pillow numpy`
  (download the bpy wheel with `pip download bpy --no-deps`; the install can fail through the proxy otherwise).
- Build + preview: `/tmp/bpyenv/bin/python blender/build.py --only CF_Coin,CF_Tree` (`--no-render` = FBX + manifest only).
  Outputs `art/meshes/<Name>.fbx`, `art/meshes/manifest.json`, `art/previews/<Name>.png`, `art/previews/CF_Scene.png`.
- Then `python3 tools/gen_mesh_catalog.py` (writes `src/shared/MeshIds.luau` + `MeshCatalog.luau`).
- Upload (owner's PC only, key from the environment, never printed):
  `ROBLOX_API_KEY=... ROBLOX_USER_ID=... python3 tools/upload_meshes.py` then commit the regenerated ids.

## Add a model
1. `blender/cfkit.py` has `Model`, `slot(name, "#hex", material)` and pieces `box cyl ball cone star`. Units = studs,
   +Z up in Blender (exported +Y up), origin = floor centre. One slot = one colour = one MeshPart.
   Slot names are letters/digits only (`Leaf`, `Bark`).
2. Add a builder to `blender/models*.py` (or a new `models_<topic>.py` imported in `build.py`) and register it in `MODELS`.
3. Build, LOOK at `art/previews/<Name>.png`, iterate. Keep each model under about 1500 faces.
4. In game code: `Meshes.clone("CF_Tree", cframe, { Leaf = color })` returns a Model, or nil when the model is not
   uploaded yet: keep the old Part code as the fallback. Never invent ids.

## World models (blender/models_world.py)
25 pieces: trees (oak `CF_Tree`, palm, pine, candy, crystal), castle tower, bush, rock, flowers, mushroom, lamp, bench,
umbrella, shell, candy cane, crystals, fence post + section, gate pillar, fountain, FREE PLOT trophy, sky island,
cloud, balloon, plaza floor. Build one: `blender/build.py --only CF_Bench`.
- Front: models face Blender +Y (Roblox -Z, toward the gate); bench back is on the Blender -Y side. UNVERIFIED in Studio.
- Wired with the Part code kept as fallback: `PlotDecor` (`withModels`: trees and props, tinted from the theme),
  `Plot` (fence: models + one invisible wall; gate pillar: model + invisible solid), `WorldArt` (cloud, balloon, island,
  fountain, plaza), `World` (FREE PLOT trophy). `Meshes.clone(name, cf, tints, scale)` scales about the model origin.
- Sky pieces (island, cloud, balloon) are tagged `SkyBob` and bob via client SkyFx; no brown anywhere in the sky.
- Not wired yet (built only): `CF_TreePine`, `CF_Crystals`.
## Models in the game (coin side)
- `CF_Coin` (3 wide, top = heads), `CF_Table`, `CF_MegaCoin`, `CF_GiftBox` (not wired yet), helpers `CF_Buddy CF_Zippy CF_Chompy CF_Twinkle CF_King`
  (front = -Y in Blender, pieces `Body` and `Cap` take the helper colours), hats `CF_HatParty CF_HatCone CF_HatCowboy CF_HatChef
  CF_HatPropeller CF_HatDuck CF_HatTop CF_HatCrown` (origin = head top). Game id -> model name lives in `shared/Util/MeshPaint`.
- Wiring (all fall back to the Part code while the id is 0): `Tables.makeCoin` puts the coin model on the invisible coin part as child `Visual`
  (the part still does the rest pose, flips and attributes; FlipFx repaints and scales `Visual` for rare coins); `buildTable` swaps Top/Rim/Legs
  for `TableMesh`; `makeHelper` returns the helper model (pivot one stud above its feet, the client hops it by pivot); `Hats.dress` uses the hat model.
- Not yet checked in Studio (ids are 0 until the PC uploads): the FBX front direction (helpers/hats should face -Z in Roblox; if they face
  backwards rotate the model in `Meshes.clone`), and that `Model:ScaleTo` on the welded coin copy behaves.
