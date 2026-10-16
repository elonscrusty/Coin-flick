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
