"""Build COIN FLICK models: FBX into art/meshes, preview PNG into art/previews.

    /tmp/bpyenv/bin/python blender/build.py [--only CF_Coin,CF_Tree] [--no-render]
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

import cfkit  # noqa: E402
from models import MODELS  # noqa: E402
from models_world import MODELS as WORLD_MODELS  # noqa: E402
from models_coin import MODELS as COIN_MODELS  # noqa: E402

MODELS.update(COIN_MODELS)
MODELS.update(WORLD_MODELS)  # the world tree replaces the sample CF_Tree

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--no-render", action="store_true")
    args = ap.parse_args()
    names = [n for n in args.only.split(",") if n] or list(MODELS)
    os.makedirs(os.path.join(ROOT, "art/meshes"), exist_ok=True)
    os.makedirs(os.path.join(ROOT, "art/previews"), exist_ok=True)
    manifest_path = os.path.join(ROOT, "art/meshes/manifest.json")
    manifest = json.load(open(manifest_path)) if os.path.exists(manifest_path) else {}
    for name in names:
        cfkit.reset_scene()
        model = MODELS[name]()
        objs = model.objects()
        cfkit.export_fbx(objs, os.path.join(ROOT, f"art/meshes/{name}.fbx"))
        tris = sum(len(o.data.polygons) for o in objs)
        print(f"{name}: {len(objs)} pieces, {tris} faces")
        manifest[name] = model.manifest(tris)
        if not args.no_render:
            big = name == "CF_Table"
            cfkit.render(objs, os.path.join(ROOT, f"art/previews/{name}.png"), cam_dir=(1.0, -1.25, 0.9 if big else 0.8))
    write_manifest(manifest)


def write_manifest(manifest):
    path = os.path.join(ROOT, "art/meshes/manifest.json")
    json.dump(dict(sorted(manifest.items())), open(path, "w"), indent=1)


def scene_preview():
    """One picture: the table with coins on it and trees, to judge the look together (not exported)."""
    import math

    from mathutils import Matrix

    cfkit.reset_scene()
    objs = []
    placed = [("CF_Table", (0, 0, 0), 0, 1.0)]
    for i in range(7):
        a = i / 6 * math.tau if i else 0
        placed.append(("CF_Coin", (0 if i == 0 else math.cos(a) * 4.8, 0 if i == 0 else math.sin(a) * 4.8, 3.6 + 0.4), a, 1.0))
    placed += [("CF_Tree", (-15, 6, 0), 0.3, 1.0), ("CF_Tree", (14, 9, 0), 1.1, 0.85), ("CF_Tree", (-10, 16, 0), 2.0, 1.1)]
    for name, loc, rot, sc in placed:
        for o in MODELS[name]().objects():
            o.matrix_world = Matrix.Translation(loc) @ Matrix.Rotation(rot, 4, "Z") @ Matrix.Diagonal((sc, sc, sc, 1))
            objs.append(o)
    cfkit.render(objs, os.path.join(ROOT, "art/previews/CF_Scene.png"), size=(960, 640), cam_dir=(0.6, -1.0, 0.75), samples=16, dist=48)


main()
if not any(a.startswith("--no-render") for a in sys.argv):
    scene_preview()
