"""Review renders of the assembled Prospector Lodge building (docs/lodge/MASTER_PROMPT_Claude_Blender.md
section 16 cameras) into docs/lodge/renders/building/.

    /tmp/bpyenv/bin/python blender/lodge_render.py                       every camera
    /tmp/bpyenv/bin/python blender/lodge_render.py --cams Player_Eye --samples 32
    /tmp/bpyenv/bin/python blender/lodge_render.py --blockout             also grey/colour blockouts of the
                                                                          furnishings (PREVIEW ONLY, for framing)

Builds Lodge_Building + Lodge_Plaque from blender/models/lodge_building.py (same builders as the export),
mounts the plaque at the building's Plaque attach point and adds a preview-only backdrop (ground, quarry
cliff steps, pines) so the rear windows show a vista. Backdrop, blockouts and lights are never exported.
"""

import argparse
import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import build as B  # noqa: E402
import ctrkit as K  # noqa: E402
from models import lodge_building as LB  # noqa: E402

OUT = os.path.join(ROOT, "docs", "lodge", "renders", "building")

CAMS = {
    # name: (location, target, vertical fov degrees)
    "Approved_Front": ((0, -31, 11), (0, 15, 7), 62),
    "Player_Eye": ((0, -27, 5.2), (0, 23, 6), 66),
    "Entrance_Eye": ((0, -33.2, 5.0), (0, 23, 7.5), 70),
    "Reverse": ((0, 27, 9), (0, -23, 6), 66),
    "Cutaway": ((-65, -70, 65), (0, 0, 7), 34),
    "Exterior": ((-100, -110, 65), (0, 0, 14), 26),
    "Exterior_Front": ((-28, -105, 14), (0, -20, 14), 34),
}

ROOF_PIECES = ("Ceiling", "RoofBase", "RoofTiles", "RidgeCap", "RoofTrim", "RoofFrame", "Trusses", "TrussPegs", "Gable", "Iron")


def parse():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cams", default=",".join(CAMS))
    ap.add_argument("--samples", type=int, default=48)
    ap.add_argument("--width", type=int, default=1280)
    ap.add_argument("--height", type=int, default=720)
    ap.add_argument("--blockout", action="store_true")
    return ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:])


def lin(hexstr):
    return (*B.srgb_to_linear(K.rgb(hexstr)), 1)


def flat_mat(name, hexstr, rough=0.8, emit=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = lin(hexstr)
    b.inputs["Roughness"].default_value = rough
    if emit:
        b.inputs["Emission Color"].default_value = lin(hexstr)
        b.inputs["Emission Strength"].default_value = emit
    return m


def glass_mat():
    """Thin clear pane: mostly transparent so daylight and the vista pass (no refraction / caustics)."""
    m = bpy.data.materials.new("PreviewGlass")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = lin("#D9ECF2")
    b.inputs["Roughness"].default_value = 0.05
    b.inputs["Alpha"].default_value = 0.12
    return m


def mesh_obj(name, verts, faces, mat, col):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    col.objects.link(ob)
    return ob


def build_lodge(col):
    objs = []
    for fn, name, offset in ((LB.lodge_building, "Lodge_Building", None), (LB.lodge_plaque, "Lodge_Plaque", "Plaque")):
        m = K.Model(name, LB.SHEET)
        fn(m)
        os_ = B.build_model(m, col)
        if name == "Lodge_Building":
            plaque_at = Vector(m.attach["Plaque"])
        else:
            for o in os_:
                o.location += plaque_at
        objs += os_
    g = glass_mat()
    for o in objs:
        if o.name.startswith(("Glass", "GableGlass")):
            o.data.materials[0] = g
            o.visible_shadow = False
    return objs


def backdrop(col):
    """Preview-only surroundings: ground, stepped grey quarry cliffs with grass tops, pines."""
    ground = flat_mat("Ground", "#C9B48F", 0.95)
    mesh_obj("Ground", [(-400, -400, -3.0), (400, -400, -3.0), (400, 400, -3.0), (-400, 400, -3.0)], [(0, 1, 2, 3)], ground, col)
    rock = [flat_mat("Cliff1", "#8E8A8C", 0.9), flat_mat("Cliff2", "#7C7880", 0.9), flat_mat("Cliff3", "#9C9796", 0.9)]
    grass = flat_mat("Grass", "#6FA33A", 0.9)
    leaf = flat_mat("Pine", "#3F8A3A", 0.9)
    trunk = flat_mat("Trunk", "#7A4A2A", 0.9)
    rng = random.Random(3)

    def box(name, c, s, mat):
        x, y, z = c
        sx, sy, sz = (v / 2 for v in s)
        v = [(x - sx, y - sy, z - sz), (x + sx, y - sy, z - sz), (x + sx, y + sy, z - sz), (x - sx, y + sy, z - sz),
             (x - sx, y - sy, z + sz), (x + sx, y - sy, z + sz), (x + sx, y + sy, z + sz), (x - sx, y + sy, z + sz)]
        f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        return mesh_obj(name, v, f, mat, col)

    def pine(x, y, z, h):
        box("Trunk", (x, y, z + h * 0.12), (0.8, 0.8, h * 0.24), trunk)
        for k in range(3):
            r = h * (0.3 - k * 0.07)
            zc = z + h * (0.25 + k * 0.22)
            n = 7
            v = [(x + math.cos(a * math.tau / n) * r, y + math.sin(a * math.tau / n) * r, zc) for a in range(n)] + [(x, y, zc + h * 0.38)]
            f = [(i, (i + 1) % n, n) for i in range(n)] + [tuple(range(n))[::-1]]
            mesh_obj("Pine", v, f, leaf, col)

    # three tiers of cliff blocks behind the rear wall and around the sides
    for tier, (y0, h) in enumerate(((75, 16), (100, 32), (130, 50))):
        x = -170
        while x < 170:
            w = rng.uniform(12, 22)
            hh = h + rng.uniform(-4, 5)
            box("Cliff", (x + w / 2, y0 + rng.uniform(-3, 3), -3 + hh / 2), (w, 22, hh), rock[rng.randrange(3)])
            box("CliffTop", (x + w / 2, y0 - 2, -3 + hh + 0.4), (w - 1, 16, 0.8), grass)
            if rng.random() < 0.6:
                pine(x + w / 2 + rng.uniform(-3, 3), y0 - 4, -3 + hh + 0.8, rng.uniform(10, 16))
            x += w
    for sx in (-1, 1):   # side cliffs and pines
        for i in range(7):
            y = -60 + i * 22
            hh = rng.uniform(16, 30)
            box("CliffS", (sx * rng.uniform(95, 110), y, -3 + hh / 2), (24, 22, hh), rock[rng.randrange(3)])
            pine(sx * rng.uniform(70, 85), y + rng.uniform(-6, 6), -3, rng.uniform(12, 18))
    # simple lookout tower silhouette behind the rear (reference vista)
    tw = flat_mat("Tower", "#8A4E2E", 0.85)
    for sx in (-1, 1):
        for sy in (-1, 1):
            box("Tower", (18 + sx * 4, 95 + sy * 4, 22), (0.9, 0.9, 50), tw)
    for z in (12, 24, 36, 46):
        box("TowerBand", (18, 95, z), (9, 9, 0.9), tw)


def blockouts(col):
    """PREVIEW ONLY: rough coloured boxes at the master prompt section 5 positions, just to judge the
    building's framing against 00_Approved_Lobby.png. Not furnishing models."""
    wood = flat_mat("BO_Wood", "#A9693F", 0.8)
    red = flat_mat("BO_Red", "#D94D52", 0.8)
    purple = flat_mat("BO_Purple", "#9555BF", 0.8)
    char = flat_mat("BO_Board", "#282B30", 0.8)
    gold = flat_mat("BO_Gold", "#E1B443", 0.8)
    rug = flat_mat("BO_Rug", "#B8452F", 0.9)
    lamp = flat_mat("BO_Lamp", "#FFC24A", 0.5, emit=6.0)

    def box(c, s, mat):
        x, y, z = c
        sx, sy, sz = (v / 2 for v in s)
        v = [(x - sx, y - sy, z - sz), (x + sx, y - sy, z - sz), (x + sx, y + sy, z - sz), (x - sx, y + sy, z - sz),
             (x - sx, y - sy, z + sz), (x + sx, y - sy, z + sz), (x + sx, y + sy, z + sz), (x - sx, y + sy, z + sz)]
        f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        mesh_obj("Blockout", v, f, mat, col)

    for sx, aw in ((-1, red), (1, purple)):
        box((sx * 39.5, 0, 2), (5.5, 24, 4), wood)
        box((sx * 41.5, 0, 6.5), (0.6, 24, 13), wood)
        box((sx * 37.8, 0, 11.5), (7, 25, 0.5), aw)
        box((sx * 34.4, 0, 11.5), (0.4, 12, 3), wood)
        box((sx * 27, 27, 3.5 + 5.75), (13, 2.5, 13.5), wood)
        box((sx * 27, 25.7, 3.5 + 5.75), (11.5, 0.2, 11.5), char)
        box((sx * 27, 27, 16.4), (1.8, 1, 2), gold)
        box((sx * 23, -24, 1.5), (12, 3, 3), wood)
    for x in (-12, 0, 12):
        box((x, 25, 0.06), (10, 10, 0.12), gold)
        box((x, 25, 0.08), (8.6, 8.6, 0.12), char)
    for x in (-18, -6, 6, 18):
        box((x, 25, 1.5), (0.6, 10, 3), wood)
    box((0, 25.5, 12), (18, 0.6, 3.5), wood)
    for x in (-18, 18):
        box((x, 25.5, 7), (1, 1, 14), wood)
    box((37, 17, 2), (4, 7, 4), wood)
    box((0, -28, 0.03), (14, 8, 0.04), rug)
    box((0, 0, 23), (10, 10, 0.8), wood)
    for i in range(6):
        a = i / 6 * math.tau
        box((math.cos(a) * 4.6, math.sin(a) * 4.6, 22.2), (0.9, 0.9, 1.4), lamp)


def lights(scene, col):
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 4.2
    sun.data.angle = math.radians(3)
    sun.data.color = (1.0, 0.95, 0.86)
    # from high rear-left, so beams fall through the rear and side high windows toward the entrance (as in the reference)
    d = Vector((0.42, -0.55, -0.72)).normalized()
    sun.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    col.objects.link(sun)
    # soft warm fill under the roof (stands in for the lantern / chandelier light that furnishings add)
    for x, y, e in ((0, 0, 9000), (-26, 0, 3500), (26, 0, 3500), (0, 22, 3000), (0, -24, 2500)):
        L = bpy.data.objects.new("Fill", bpy.data.lights.new("Fill", "POINT"))
        L.data.energy = e
        L.data.shadow_soft_size = 6
        L.data.color = (1.0, 0.82, 0.6)
        L.location = (x, y, 20)
        col.objects.link(L)
    world = bpy.data.worlds.new("Sky")
    world.use_nodes = True
    nt = world.node_tree
    bg = nt.nodes["Background"]
    grad = nt.nodes.new("ShaderNodeTexGradient")
    coord = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    nt.links.new(coord.outputs["Generated"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], ramp.inputs["Fac"])
    ramp.color_ramp.elements[0].position = 0.5
    ramp.color_ramp.elements[0].color = lin("#D8ECF7")
    ramp.color_ramp.elements[1].position = 0.8
    ramp.color_ramp.elements[1].color = lin("#5FA8E0")
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 1.1
    del grad
    scene.world = world


def main():
    args = parse()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "NONE"
    col = bpy.data.collections.new("10_Building")
    scene.collection.children.link(col)
    prev = bpy.data.collections.new("99_PreviewOnly")
    scene.collection.children.link(prev)
    objs = build_lodge(col)
    backdrop(prev)
    if args.blockout:
        blockouts(prev)
    lights(scene, prev)
    s = scene
    s.render.engine = "CYCLES"
    s.cycles.device = "CPU"
    s.cycles.samples = args.samples
    s.cycles.use_denoising = True
    s.cycles.max_bounces = 6
    s.cycles.diffuse_bounces = 3
    s.render.resolution_x, s.render.resolution_y = args.width, args.height
    s.view_settings.view_transform = "AgX"
    s.view_settings.exposure = 0.3
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    prev.objects.link(cam)
    s.camera = cam
    os.makedirs(OUT, exist_ok=True)
    roof_objs = [o for o in objs if o.name.startswith(ROOF_PIECES)]
    for name in [c for c in args.cams.split(",") if c]:
        loc, tgt, fov = CAMS[name]
        cam.location = loc
        d = Vector(tgt) - Vector(loc)
        cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        cam.data.sensor_fit = "VERTICAL"
        cam.data.angle_y = math.radians(fov)
        cam.data.clip_end = 2000
        for o in roof_objs:   # the cutaway hides the roof by visibility only; the asset keeps it
            o.hide_render = name == "Cutaway"
        suffix = "_blockout" if args.blockout else ""
        s.render.filepath = os.path.join(OUT, name + suffix + ".png")
        bpy.ops.render.render(write_still=True)
        print("rendered", s.render.filepath)


if __name__ == "__main__":
    main()
