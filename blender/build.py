"""Build the Crack the Rocks Blender models: export FBX, write the manifest, render previews.

    /tmp/bpyenv/bin/python blender/build.py                         everything
    /tmp/bpyenv/bin/python blender/build.py --only Station_Table,07  some models / whole sheets
    /tmp/bpyenv/bin/python blender/build.py --no-render              skip preview pictures
    /tmp/bpyenv/bin/python blender/build.py --list                   list registered models

Needs the `bpy` module (bpy 5.x) and Pillow for the stitched preview (optional).
Models live in blender/models/*.py (sheet modules register with ctrkit.register).

Outputs (repo root):
  art/meshes/<Name>.fbx        one FBX per model, one mesh object per piece (preview pieces left out)
  art/meshes/manifest.json     per model: sheet, pieces (slot, material, offset, size, pivot), bounds,
                               attachment points, tris (merged under a lock; legacy CT_Rocks_ glb
                               entries from tools/gen_meshes.py are kept)
  art/previews/<Name>.png      3/4 + front + side views on a cream background
Then: python3 tools/ref_compare.py <Name> to put the render next to the reference-sheet crop.
"""

import argparse
import fcntl
import importlib
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import ctrkit as K  # noqa: E402

MODULES = sorted("models." + f[:-3] for f in os.listdir(os.path.join(HERE, "models"))
                 if f.endswith(".py") and not f.startswith("_"))
OUT_MESH = os.path.join(ROOT, "art", "meshes")
OUT_PREVIEW = os.path.join(ROOT, "art", "previews")
MANIFEST = os.path.join(OUT_MESH, "manifest.json")


def parse():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--no-render", action="store_true")
    ap.add_argument("--samples", type=int, default=24)
    ap.add_argument("--size", type=int, default=440, help="pixel size of each preview view")
    ap.add_argument("--list", action="store_true")
    return ap.parse_args(argv)


# ------------------------------------------------------------------ materials (preview only)

_mats = {}


def srgb_to_linear(c):
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)


def preview_material(slot, material, transparency):
    key = (slot, material, round(transparency, 2))
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new("M_%s_%s" % (slot, material))
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    col = srgb_to_linear(K.rgb(slot))
    bsdf.inputs["Base Color"].default_value = (*col, 1)
    rough = {"Metal": 0.42, "Glass": 0.08, "Neon": 0.5, "Wood": 0.7, "Slate": 0.85, "Concrete": 0.9}.get(material, 0.6)
    bsdf.inputs["Roughness"].default_value = rough
    if material == "Metal":
        bsdf.inputs["Metallic"].default_value = 0.35
    if material == "Neon":
        bsdf.inputs["Emission Color"].default_value = (*col, 1)
        bsdf.inputs["Emission Strength"].default_value = 2.5
    if material == "Glass":
        bsdf.inputs["Transmission Weight"].default_value = 0.85
        bsdf.inputs["Alpha"].default_value = 0.7
    elif transparency > 0:
        bsdf.inputs["Alpha"].default_value = 1 - transparency
    _mats[key] = m
    return m


# ------------------------------------------------------------------ build

def build_model(model, collection):
    objs = []
    for p in model.pieces:
        if len(p.bm.verts) == 0:
            continue
        p.finish()
        me = bpy.data.meshes.new(p.name)
        p.bm.to_mesh(me)
        p.bm.free()
        for poly in me.polygons:
            poly.use_smooth = False  # faceted low-poly look
        me.materials.append(preview_material(p.slot, p.material, p.transparency))
        ob = bpy.data.objects.new(p.name, me)
        ob.location = p.center
        ob["preview"] = p.preview
        ob["render_hide"] = getattr(p, "render_hide", False)
        collection.objects.link(ob)
        objs.append(ob)
    return objs


def export_fbx(objs, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.context.view_layer.update()
    for o in bpy.context.scene.objects:
        if o.name in bpy.context.view_layer.objects:
            o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    # Same settings as the owner's other project (proven with Roblox's importer): one node per piece.
    bpy.ops.export_scene.fbx(
        filepath=path, use_selection=True, object_types={"MESH"},
        apply_unit_scale=True, apply_scale_options="FBX_SCALE_UNITS", global_scale=1.0,
        axis_forward="Z", axis_up="Y", mesh_smooth_type="OFF", use_mesh_modifiers=True,
        use_triangles=True, add_leaf_bones=False, bake_anim=False, path_mode="AUTO")


def record(model):
    pieces = []
    tris = 0
    for p in model.pieces:
        if p.preview or not hasattr(p, "center"):
            continue
        tris += p.tris
        rec = dict(name=p.name, slot=p.slot, material=p.material,
                   offset=K.to_roblox(p.center), size=K.roblox_size(p.size), tris=p.tris)
        if p.transparency:
            rec["transparency"] = round(p.transparency, 3)
        if p.anim:
            rec["anim"] = p.anim
        if p.pivot is not None:
            rec["pivot"] = K.to_roblox(p.pivot - p.center)  # joint relative to the piece centre
        if p.note:
            rec["note"] = p.note
        pieces.append(rec)
    lo = [min(q["offset"][i] - q["size"][i] / 2 for q in pieces) for i in range(3)]
    hi = [max(q["offset"][i] + q["size"][i] / 2 for q in pieces) for i in range(3)]
    palette = {q["slot"]: K.HEX[q["slot"]] for q in pieces}
    out = dict(name=model.name, sheet=model.sheet, note=model.note, kind="blender", file=model.name + ".fbx",
               tris=tris, pieces=pieces, palette=palette,
               bounds=[[round(x, 3) for x in lo], [round(x, 3) for x in hi]])
    if model.attach:
        out["attach"] = {k: K.to_roblox(Vector(v)) for k, v in model.attach.items()}
    out.update(model.extra)
    return out


# ------------------------------------------------------------------ render

VIEWS = (("3/4", (-0.95, -1.25, 0.8)), ("front", (0, -1, 0.12)), ("side", (-1, 0, 0.12)))


class Renderer:
    def __init__(self, scene, samples, size):
        s = scene
        s.render.engine = "CYCLES"
        s.cycles.device = "CPU"
        s.cycles.samples = samples
        s.cycles.use_denoising = True
        s.render.resolution_x = s.render.resolution_y = size
        s.render.film_transparent = True  # composited onto the sheet cream below
        s.view_settings.view_transform = "Standard"
        world = bpy.data.worlds.new("W")
        world.use_nodes = True
        bg = world.node_tree.nodes["Background"]
        bg.inputs["Color"].default_value = (*srgb_to_linear((0.95, 0.92, 0.86)), 1)
        bg.inputs["Strength"].default_value = 0.45
        s.world = world
        sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
        sun.data.energy = 2.6
        sun.data.angle = math.radians(20)
        sun.rotation_euler = (math.radians(40), math.radians(-8), math.radians(-35))
        s.collection.objects.link(sun)
        fill = bpy.data.objects.new("Fill", bpy.data.lights.new("Fill", "SUN"))
        fill.data.energy = 0.5
        fill.data.angle = math.radians(40)
        fill.rotation_euler = (math.radians(60), math.radians(10), math.radians(150))
        s.collection.objects.link(fill)
        g = bpy.data.meshes.new("Ground")
        g.from_pydata([(-500, -500, -0.005), (500, -500, -0.005), (500, 500, -0.005), (-500, 500, -0.005)], [], [(0, 1, 2, 3)])
        ground = bpy.data.objects.new("Ground", g)
        ground.is_shadow_catcher = True
        s.collection.objects.link(ground)
        cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
        s.collection.objects.link(cam)
        s.camera = cam
        self.scene, self.cam, self.size = s, cam, size
        self.fixed = {sun, fill, ground, cam}

    def view(self, objs, path, direction):
        bpy.context.view_layer.update()  # new objects have no matrix_world until the depsgraph updates
        vis = set(objs)
        for o in self.scene.objects:
            if o not in self.fixed:
                o.hide_render = o not in vis
        corners = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
        lo = Vector([min(c[i] for c in corners) for i in range(3)])
        hi = Vector([max(c[i] for c in corners) for i in range(3)])
        center = (lo + hi) / 2
        d = Vector(direction).normalized()
        rot = (-d).to_track_quat("-Z", "Y")
        inv = rot.to_matrix().inverted()
        ext = max(max(abs((inv @ (c - center)).x), abs((inv @ (c - center)).y)) for c in corners)
        self.cam.rotation_euler = rot.to_euler()
        self.cam.data.type = "ORTHO"
        self.cam.data.ortho_scale = ext * 2 * 1.12
        self.cam.location = center + d * (ext * 4 + 50)
        self.cam.data.clip_end = 1000
        self.scene.render.filepath = path
        bpy.ops.render.render(write_still=True)

    def render(self, objs, path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        # models whose origin is not on the floor (tools: the grip) are lifted onto the ground plane
        bpy.context.view_layer.update()
        zmin = min((o.matrix_world @ Vector(c)).z for o in objs for c in o.bound_box)
        lift = -zmin if zmin < 0 else 0.0
        for o in objs:
            o.location.z += lift
        parts = []
        for i, (_, d) in enumerate(VIEWS):
            p = path[:-4] + "_v%d.png" % i
            self.view(objs, p, d)
            parts.append(p)
        try:
            from PIL import Image, ImageDraw
        except ImportError:
            print("  (Pillow missing: views left as %s_v0..2.png)" % path[:-4])
            for o in objs:
                o.location.z -= lift
            return
        ims = [Image.open(p).convert("RGBA") for p in parts]
        out = Image.new("RGB", (self.size * 3, self.size), (242, 235, 220))
        d = ImageDraw.Draw(out)
        for i, im in enumerate(ims):
            out.paste(im, (i * self.size, 0), im)
            d.text((i * self.size + 8, self.size - 18), VIEWS[i][0].upper(), fill=(60, 60, 60))
        out.save(path)
        for p in parts:
            os.remove(p)
        for o in objs:
            o.location.z -= lift


# ------------------------------------------------------------------ main

def main():
    args = parse()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "NONE"
    for mod in MODULES:
        importlib.import_module(mod)
    if args.list:
        for name, sheet, note, ref, fn in K.REGISTRY:
            print(f"{sheet}  {name:<28} {note}")
        return
    only = {x for x in args.only.split(",") if x}
    todo = [r for r in K.REGISTRY if not only or r[0] in only or r[1] in only]
    if not todo:
        sys.exit("nothing matches --only " + args.only)
    renderer = None if args.no_render else Renderer(scene, args.samples, args.size)
    built = {}
    for name, sheet, note, ref, fn in todo:
        col = bpy.data.collections.new(name)
        scene.collection.children.link(col)
        model = K.Model(name, sheet, note)
        fn(model)
        objs = build_model(model, col)
        export_objs = [o for o in objs if not o["preview"]]
        if export_objs:
            export_fbx(export_objs, os.path.join(OUT_MESH, name + ".fbx"))
            rec = record(model)
        else:  # preview-only composition (e.g. the assembled station): rendered, never exported
            rec = dict(name=name, sheet=sheet, note=note, kind="preview", tris=0, pieces=[])
        if ref:
            rec["ref"] = {"sheet": ref[0], "crop": list(ref[1])}
        built[name] = rec
        print(f"{name:<28} {len(export_objs):>3} pieces {rec['tris']:>6} tris")
        if renderer:
            renderer.render([o for o in objs if not o["render_hide"]] or objs, os.path.join(OUT_PREVIEW, name + ".png"))
        for o in objs:
            me = o.data
            bpy.data.objects.remove(o)
            bpy.data.meshes.remove(me)
        bpy.data.collections.remove(col)

    known = {r[0] for r in K.REGISTRY}
    os.makedirs(OUT_MESH, exist_ok=True)
    with open(MANIFEST + ".lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        manifest = {}
        if os.path.exists(MANIFEST):
            with open(MANIFEST) as f:
                manifest = json.load(f)
        # drop Blender models that were removed from the registry; keep legacy glb entries
        manifest = {k: v for k, v in manifest.items() if v.get("kind") not in ("blender", "preview") or k in known}
        manifest.update(built)
        tmp = MANIFEST + ".tmp"
        with open(tmp, "w") as f:
            json.dump(dict(sorted(manifest.items())), f, indent=1)
        os.replace(tmp, MANIFEST)
        fcntl.flock(lock, fcntl.LOCK_UN)


if __name__ == "__main__":
    main()
