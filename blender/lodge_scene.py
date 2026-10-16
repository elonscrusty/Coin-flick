"""Assemble the Prospector Lodge furnishings at the authoritative placement and render the review cameras.

    /tmp/bpyenv/bin/python blender/lodge_scene.py                       all cameras, 24 samples
    /tmp/bpyenv/bin/python blender/lodge_scene.py --cams Player_Eye --samples 16 --size 1280x720
    /tmp/bpyenv/bin/python blender/lodge_scene.py --no-render           placement JSON only

Builds every furnishing model registered in blender/models/lodge_*.py (the same builders build.py exports),
places one instance per entry of PLACEMENT below (MASTER_PROMPT section 5 + Placement_Specification.csv,
plus the decor positions chosen in docs/lodge/FURNISHING_NOTES.md), and renders:
  docs/lodge/renders/furnishings/layout_<camera>.png
Writes art/lodge/furnishing_placement.json (Blender + Roblox positions and yaw per instance).

The structural shell is NOT modelled here: when a model named Lodge_Building is registered (the building
kit) it is placed at the origin, otherwise a plain PREVIEW-ONLY stand-in room (floor, walls with high
windows, roof) gives the furnishings context. Preview text on signs and leaderboard rows is PreviewOnly_*
(Blender text objects): never exported. Blender lights here are preview lighting only.
"""

import argparse
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import build as B  # noqa: E402
import ctrkit as K  # noqa: E402

OUT_DIR = os.path.join(ROOT, "docs", "lodge", "renders", "furnishings")
OUT_JSON = os.path.join(ROOT, "art", "lodge", "furnishing_placement.json")

# id, model, Blender location (x, y, z), Blender Z rotation (deg, CCW from local front -Y), [parent id, parent attach]
# Top-level rows follow Placement_Specification.csv / MASTER section 5 exactly.
PLACEMENT = [
    ("Upgrades_Stall", "Lodge_UpgradesStall", (-37, 0, 0), 90),
    ("Collection_Stall", "Lodge_CollectionStall", (37, 0, 0), -90),
    ("Hunt_Bays_Assembly", "Lodge_HuntBays", (0, 25, 0), 0),
    ("Leaderboard_Solo", "Lodge_Leaderboard", (-27, 27, 0), 0),
    ("Leaderboard_Wins", "Lodge_Leaderboard", (27, 27, 0), 0),
    ("Rubble_Sell", "Lodge_RubbleSell", (37, 17, 0), -90),
    ("Bench_FrontLeft", "Lodge_Bench", (-23, -24, 0), 0),
    ("Bench_FrontRight", "Lodge_Bench", (23, -24, 0), 0),
    ("Entry_Rug", "Lodge_EntryRug", (0, -28, 0.025), 0),
    ("Chandelier", "Lodge_Chandelier", (0, 0, 23), 0),
    # decor on attach points of the assemblies (offset = local position from the attach point)
    ("Upgrades_Cashbox", "Lodge_Cashbox", (0, 0, 0), 0, "Upgrades_Stall", "Cashbox"),
    ("Upgrades_Basket", "Lodge_RockBasket", (0, 0, 0), 0, "Upgrades_Stall", "Basket"),
    ("Upgrades_Lantern", "Lodge_Lantern", (0, 0, 0), 0, "Upgrades_Stall", "Lantern"),
    ("Upgrade_Runner", "Lodge_RunnerRug", (0, 0, 0.025), 0, "Upgrades_Stall", "Runner"),
    ("Collection_Pedestal1", "Lodge_SpecimenPedestal", (0, 0, 0), 0, "Collection_Stall", "Specimen1"),
    ("Collection_Pedestal2", "Lodge_SpecimenPedestal", (0, 0, 0), 0, "Collection_Stall", "Specimen2"),
    ("Collection_Pedestal3", "Lodge_SpecimenPedestal", (0, 0, 0), 0, "Collection_Stall", "Specimen3"),
    ("Collection_GeodeViolet", "Lodge_DisplayGeode_Violet", (0, 0, 0), 0, "Collection_Pedestal1", "Specimen"),
    ("Collection_GeodeBlue", "Lodge_DisplayGeode_Blue", (0, 0, 0), 0, "Collection_Pedestal2", "Specimen"),
    ("Collection_GeodeAmber", "Lodge_DisplayGeode_Amber", (0, 0, 0), 0, "Collection_Pedestal3", "Specimen"),
    ("Collection_Tray1", "Lodge_SpecimenTray", (0, 0, 0), 0, "Collection_Stall", "Shelf1"),
    ("Collection_Tray2", "Lodge_SpecimenTray", (0, 0, 0), 0, "Collection_Stall", "Shelf2"),
    ("Collection_Tray3", "Lodge_SpecimenTray", (0, 0, 0), 0, "Collection_Stall", "Shelf3"),
    ("Collection_ClusterViolet", "Lodge_CrystalCluster_Violet", (0, 0, 0), 0, "Collection_Tray1", "Specimen"),
    ("Collection_ClusterBlue", "Lodge_CrystalCluster_Blue", (0, 0, 0), 0, "Collection_Tray2", "Specimen"),
    ("Collection_ClusterAmber", "Lodge_CrystalCluster_Amber", (0, 0, 0), 0, "Collection_Tray3", "Specimen"),
    ("Collection_Lantern", "Lodge_Lantern", (0, 0, 0), 0, "Collection_Stall", "Lantern"),
    ("HuntSign_Emblem", "Lodge_HammerEmblem", (0, 0, 0), 0, "Hunt_Bays_Assembly", "Emblem"),
    ("HuntBay_WallLantern1", "Lodge_WallLantern", (0, 0, 0), 0, "Hunt_Bays_Assembly", "Lantern1"),
    ("HuntBay_WallLantern2", "Lodge_WallLantern", (0, 0, 0), 0, "Hunt_Bays_Assembly", "Lantern2"),
    ("HuntBay_WallLantern3", "Lodge_WallLantern", (0, 0, 0), 0, "Hunt_Bays_Assembly", "Lantern3"),
    ("HuntBay_WallLantern4", "Lodge_WallLantern", (0, 0, 0), 0, "Hunt_Bays_Assembly", "Lantern4"),
    ("HuntBay_PostLantern1", "Lodge_Lantern", (0, 0, 0), 0, "Hunt_Bays_Assembly", "PostLamp1"),
    ("HuntBay_PostLantern2", "Lodge_Lantern", (0, 0, 0), 0, "Hunt_Bays_Assembly", "PostLamp2"),
    ("HuntBay_PostLantern3", "Lodge_Lantern", (0, 0, 0), 0, "Hunt_Bays_Assembly", "PostLamp3"),
    ("HuntBay_PostLantern4", "Lodge_Lantern", (0, 0, 0), 0, "Hunt_Bays_Assembly", "PostLamp4"),
    ("Solo_Trophy", "Lodge_TrophyEmblem", (0, 0, 0), 0, "Leaderboard_Solo", "Trophy"),
    ("Wins_Trophy", "Lodge_TrophyEmblem", (0, 0, 0), 0, "Leaderboard_Wins", "Trophy"),
    ("Rubble_Basket", "Lodge_RockBasket", (0, 0, 0), 0, "Rubble_Sell", "Basket"),
    ("Rubble_Lantern", "Lodge_Lantern", (0, 0, 0), 0, "Rubble_Sell", "Lantern"),
    # free-standing decor (world positions, see FURNISHING_NOTES.md)
    ("Crate_UpgradesFront1", "Lodge_Crate", (-39.4, -14.4, 0), 8, None, None),
    ("Crate_UpgradesFront2", "Lodge_Crate", (-36.3, -14.9, 0), -6, None, None),
    ("Crate_UpgradesRear", "Lodge_Crate", (-39.4, 14.4, 0), 4, None, None),
    ("Crate_CollectionFront1", "Lodge_Crate", (39.4, -14.4, 0), -8, None, None),
    ("Crate_CollectionFront2", "Lodge_Crate", (36.3, -14.9, 0), 5, None, None),
    ("Crate_RubbleSide", "Lodge_Crate", (39.4, 22.6, 0), 0, None, None),
    ("Crate_Lantern", "Lodge_Lantern", (0, 0, 0), 0, "Crate_RubbleSide", "Top"),
    ("Planter_UpgradesFront", "Lodge_Planter", (-39.6, -18.4, 0), 0, None, None),
    ("Planter_CollectionFront", "Lodge_Planter", (39.6, -18.4, 0), 0, None, None),
    ("Planter_RearLeft", "Lodge_Planter", (-40.0, 31.8, 0), 0, None, None),
    ("Planter_RearRight", "Lodge_Planter", (40.0, 31.8, 0), 0, None, None),
    ("Planter_FrontLeft", "Lodge_Planter", (-40.0, -31.8, 0), 0, None, None),
    ("Planter_FrontRight", "Lodge_Planter", (40.0, -31.8, 0), 0, None, None),
    ("Wall_LanternLeft", "Lodge_WallLantern", (-42.0, -17.0, 9.0), 90, None, None),
    ("Wall_LanternRight", "Lodge_WallLantern", (42.0, -17.0, 9.0), -90, None, None),
    ("Poster_Geode", "Lodge_PosterGeode", (-42.0, -7.0, 15.75), 90, None, None),
    ("Poster_Mineral", "Lodge_PosterMineral", (42.0, -7.0, 15.75), -90, None, None),
]
# one angular plant in every planter (turned a little differently each)
PLANTS = [("Plant" + p[0][7:], "Lodge_Plant", (0, 0, 0), 37 * k, p[0], "Plant")
          for k, p in enumerate(x for x in PLACEMENT if x[0].startswith("Planter_"))]
PLACEMENT += PLANTS

CAMERAS = {
    "Player_Eye": ((0, -27, 5.2), (0, 23, 6), 17),
    "Approved_Front": ((0, -31, 11), (0, 15, 7), 15),
    "Cutaway": ((-65, -70, 65), (0, 0, 7), 30),
    "Plan": ((0, 0, 120), (0, 0, 0), None),
    "Upgrades_Close": ((-19, -9, 7.5), (-37, 1, 6.5), 24),
    "Collection_Close": ((19, -9, 7.5), (37, 1, 6.5), 24),
    "Hunt_Close": ((0, 4, 7), (0, 26, 7.5), 22),   # orthographic top view (compare with 05_Dimensioned_Placement_Plan.png)
}

# preview-only labels (never exported): (parent id, attach, text, size)
LABELS = [
    ("Upgrades_Stall", "SignFace", "UPGRADES", 1.6),
    ("Collection_Stall", "SignFace", "COLLECTION", 1.45),
    ("Hunt_Bays_Assembly", "SignFace", "START HUNT", 2.1),
    ("Rubble_Sell", "SignFace", "RUBBLE\nSELL", 0.95),
    ("Leaderboard_Solo", "Title", "SOLO FINDS", 1.25),
    ("Leaderboard_Wins", "Title", "COMPETITIVE WINS", 0.95),
]


def parse():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("--cams", default=",".join(CAMERAS))
    ap.add_argument("--samples", type=int, default=24)
    ap.add_argument("--size", default="1600x900")
    ap.add_argument("--no-render", action="store_true")
    ap.add_argument("--contact", action="store_true", help="only stitch art/previews/Lodge_*.png into contact sheets")
    return ap.parse_args(argv)


def contact_sheets(per=8):
    """Stitch the per-asset previews (blender/build.py, 3/4 + front + side) into labelled contact sheets:
    docs/lodge/renders/furnishings/assets_<n>.png."""
    from PIL import Image, ImageDraw, ImageFont
    prev = os.path.join(ROOT, "art", "previews")
    names = sorted(f[:-4] for f in os.listdir(prev) if f.startswith("Lodge_") and f.endswith(".png") and "_v" not in f[-7:])
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 22)
    except OSError:
        font = ImageFont.load_default()
    cw, ch, head = 990, 330, 34
    os.makedirs(OUT_DIR, exist_ok=True)
    for k in range(0, len(names), per):
        group = names[k:k + per]
        rows = (len(group) + 1) // 2
        out = Image.new("RGB", (cw * 2, rows * (ch + head)), (34, 38, 46))
        d = ImageDraw.Draw(out)
        for i, n in enumerate(group):
            x, y = (i % 2) * cw, (i // 2) * (ch + head)
            im = Image.open(os.path.join(prev, n + ".png")).convert("RGB").resize((cw, ch), Image.LANCZOS)
            out.paste(im, (x, y + head))
            d.text((x + 10, y + 6), n, fill=(244, 239, 229), font=font)
        path = os.path.join(OUT_DIR, "assets_%d.png" % (k // per + 1))
        out.save(path)
        print("wrote", path)


# ------------------------------------------------------------------ helpers

def rotz(deg):
    return Matrix.Rotation(math.radians(deg), 4, "Z")


def to_roblox_world(p):
    """The repo pipeline's mapping (ctrkit.to_roblox, same as Lodge_Building): Roblox (X, Y, Z) = Blender (-X, Z, Y).
    Entrance at Roblox -Z, hunt wall at +Z. (The master prompt's (X, Z, -Y) is the same layout turned 180 degrees;
    it is NOT used, so building and furnishings share one frame.)"""
    return K.to_roblox(p)


def roblox_yaw(rot_deg):
    """Blender Z rotation r -> Roblox yaw r about +Y (the kit meshes go through the same mapping)."""
    y = rot_deg % 360
    return y - 360 if y > 180 else y


def material(name, hexcol, emit=0.0, alpha=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    col = B.srgb_to_linear(K.rgb(hexcol))
    b.inputs["Base Color"].default_value = (*col, 1)
    b.inputs["Roughness"].default_value = 0.8
    if emit:
        b.inputs["Emission Color"].default_value = (*col, 1)
        b.inputs["Emission Strength"].default_value = emit
    if alpha < 1:
        b.inputs["Alpha"].default_value = alpha
    return m


def box_obj(name, size, loc, mat, col, rot=0.0):
    me = bpy.data.meshes.new(name)
    sx, sy, sz = (s / 2 for s in size)
    v = [(-sx, -sy, -sz), (sx, -sy, -sz), (sx, sy, -sz), (-sx, sy, -sz), (-sx, -sy, sz), (sx, -sy, sz), (sx, sy, sz), (-sx, sy, sz)]
    f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    me.from_pydata(v, [], f)
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    ob.location = loc
    ob.rotation_euler = (0, 0, math.radians(rot))
    col.objects.link(ob)
    return ob


# ------------------------------------------------------------------ stand-in room (preview only)

def standin_room(col):
    floor = material("SI_Floor", "#B8A486")
    floor2 = material("SI_Floor2", "#AC977A")
    plaster = material("SI_Plaster", "#E7D6B8")
    stone = material("SI_Stone", "#8F877B")
    timber = material("SI_Timber", "#8E5A35")
    roof = material("SI_Roof", "#5A4436")
    sky = material("SI_Sky", "#BFE0F2", emit=1.2)
    objs = []
    objs.append(box_obj("StandIn_Floor", (86.4, 70.4, 1.0), (0, 0, -0.5), floor, col))
    for i, (x, y, w, d) in enumerate(((-20, 8, 22, 16), (18, -12, 26, 14), (6, 22, 18, 10), (-26, -18, 14, 12))):
        objs.append(box_obj("StandIn_FloorPatch%d" % i, (w, d, 0.01), (x, y, 0.004), floor2, col))
    t = 1.2
    # side walls (x = +-42) with a high window band z 16..24 between posts; rear wall (y = +34) with windows
    for sx in (-1, 1):
        x = sx * (42 + t / 2)
        objs.append(box_obj("StandIn_WallBase", (t, 68, 3), (x, 0, 1.5), stone, col))
        objs.append(box_obj("StandIn_WallLow", (t, 68, 13), (x, 0, 9.5), plaster, col))
        objs.append(box_obj("StandIn_WallHigh", (t, 68, 2), (x, 0, 25), plaster, col))
        for yy in (-21, -7, 7, 21):
            objs.append(box_obj("StandIn_WinS", (0.2, 10, 8), (x + sx * 0.4, yy, 20), sky, col))
            objs.append(box_obj("StandIn_WallPier", (t, 4, 8), (x, yy + 7, 20), plaster, col))
        objs.append(box_obj("StandIn_WallPier", (t, 4, 8), (x, -32, 20), plaster, col))
    y = 34 + t / 2
    objs.append(box_obj("StandIn_RearBase", (86.4, t, 3), (0, y, 1.5), stone, col))
    objs.append(box_obj("StandIn_RearLow", (86.4, t, 3), (0, y, 4.5), plaster, col))
    objs.append(box_obj("StandIn_RearWin", (60, 0.2, 18), (0, y + 0.5, 15), sky, col))
    for xx in (-36, 36):
        objs.append(box_obj("StandIn_RearPier", (14.4, t, 18), (xx, y, 15), plaster, col))
    objs.append(box_obj("StandIn_RearTop", (86.4, t, 2), (0, y, 25), plaster, col))
    for xx in (-30, -15, 0, 15, 30):
        objs.append(box_obj("StandIn_RearMullion", (1.2, 1.4, 18), (xx, y - 0.2, 15), timber, col))
    objs.append(box_obj("StandIn_RearSill", (86.4, 1.6, 1.0), (0, y - 0.2, 6.2), timber, col))
    objs.append(box_obj("StandIn_RearHead", (86.4, 1.6, 1.0), (0, y - 0.2, 24.0), timber, col))
    # front wall with the 18 x 14 door
    y = -34 - t / 2
    for xx in (-25.5, 25.5):
        objs.append(box_obj("StandIn_Front", (33, t, 26), (xx, y, 13), plaster, col))
    objs.append(box_obj("StandIn_FrontTop", (18, t, 12), (0, y, 20), plaster, col))
    # posts on the walls + a few trusses
    for yy in (-28, -14, 0, 14, 28):
        for sx in (-1, 1):
            objs.append(box_obj("StandIn_Post", (1.4, 1.4, 26), (sx * 41.3, yy, 13), timber, col))
        roof_beam = box_obj("StandIn_TieBeam", (84, 1.2, 1.2), (0, yy, 26.6), timber, col)
        objs.append(roof_beam)
    for sx in (-1, 1):
        objs.append(box_obj("StandIn_Eave", (1.4, 70, 1.2), (sx * 41.3, 0, 25.8), timber, col))
    roof_objs = []
    for sx in (-1, 1):
        ang = math.atan2(14, 43)
        ln = math.hypot(43, 14) + 2
        ob = box_obj("StandIn_Roof", (ln, 72, 0.6), (sx * 21.5, 0, 33.2), roof, col)
        ob.rotation_euler = (0, -sx * ang, 0)
        roof_objs.append(ob)
    for sx in (-1, 1):   # gables
        me = bpy.data.meshes.new("StandIn_Gable")
        yy = sx * (34 + t / 2)
        me.from_pydata([(-43, yy, 26), (43, yy, 26), (0, yy, 40)], [], [(0, 1, 2)])
        me.materials.append(plaster)
        ob = bpy.data.objects.new("StandIn_Gable", me)
        col.objects.link(ob)
        roof_objs.append(ob)
    return objs, roof_objs


# ------------------------------------------------------------------ main

def build_protos(names):
    reg = {r[0]: r for r in K.REGISTRY}
    protos = {}
    holder = bpy.data.collections.new("_protos")
    for n in names:
        name, sheet, note, ref, fn = reg[n]
        model = K.Model(name, sheet, note)
        fn(model)
        objs = B.build_model(model, holder)
        protos[n] = (objs, dict(model.attach), model)
    return protos


def place_all(protos, col):
    world = {}      # id -> (matrix, model name)
    rows = []
    for row in PLACEMENT:
        pid, model, loc, rot = row[:4]
        parent, att = (row[4], row[5]) if len(row) > 4 else (None, None)
        if parent:
            pm, pmodel = world[parent]
            a = protos[pmodel][1][att]
            M = pm @ Matrix.Translation(Vector(a)) @ Matrix.Translation(Vector(loc)) @ rotz(rot)
        else:
            M = Matrix.Translation(Vector(loc)) @ rotz(rot)
        world[pid] = (M, model)
        for o in protos[model][0]:
            if o["preview"]:
                continue
            c = o.copy()
            c.name = pid + "_" + o.name
            c.matrix_world = M @ o.matrix_basis
            c.hide_render = bool(o["render_hide"])
            col.objects.link(c)
        p = M.to_translation()
        yaw = math.degrees(M.to_euler().z)
        rows.append(dict(id=pid, model=model, parent=parent, attach=att,
                         blender=dict(pos=[round(v, 3) + 0.0 for v in p], rot_z=round(yaw, 2) + 0.0),
                         roblox=dict(pos=to_roblox_world(p), yaw=round(roblox_yaw(yaw), 2) + 0.0)))
    return world, rows


def world_attach(world, protos, pid, att):
    M, model = world[pid]
    return M @ Vector(protos[model][1][att]), M


def labels(world, protos, col):
    txt = material("PreviewOnly_Text", "#FFF4DC")
    ink = material("PreviewOnly_Ink", "#2A1A10")
    for pid, att, text, size in LABELS:
        p, M = world_attach(world, protos, pid, att)
        cu = bpy.data.curves.new("PreviewOnly_" + pid, "FONT")
        cu.body = text
        cu.size = size
        cu.align_x = "CENTER"
        cu.align_y = "CENTER"
        cu.extrude = 0.03
        cu.offset = 0.04
        cu.space_line = 0.85
        cu.materials.append(txt)
        ob = bpy.data.objects.new("PreviewOnly_" + pid + "_" + att, cu)
        R = M.to_3x3().to_4x4()
        ob.matrix_world = Matrix.Translation(p - M.to_3x3() @ Vector((0, 0.05, 0))) @ R @ Matrix.Rotation(math.radians(90), 4, "X")
        col.objects.link(ob)
    # leaderboard rows: rank tiles, avatar squares and name / score bars (proportions only)
    tiles = [material("PreviewOnly_Gold", "#E1B443"), material("PreviewOnly_Silver", "#C3C8CE"),
             material("PreviewOnly_Bronze", "#C47A3A"), material("PreviewOnly_Grey", "#4A4F57"),
             material("PreviewOnly_Grey2", "#4A4F57")]
    bar = material("PreviewOnly_Bar", "#3A3F47")
    face = material("PreviewOnly_Face", "#E8B07A")
    for pid in ("Leaderboard_Solo", "Leaderboard_Wins"):
        p, M = world_attach(world, protos, pid, "BoardFace")
        R = M.to_3x3()
        for i in range(5):
            z = 2.9 - i * 1.65 - 0.9
            for (dx, w, h, m) in ((-4.6, 1.2, 1.2, tiles[i]), (-3.2, 1.0, 1.0, face), (0.4, 5.6, 1.15, bar), (4.4, 1.6, 1.15, bar)):
                ob = box_obj("PreviewOnly_Row", (w, 0.04, h), (0, 0, 0), m, col)
                ob.matrix_world = Matrix.Translation(p + R @ Vector((dx, -0.03, z))) @ R.to_4x4()
        _ = ink


def lights(world, protos, col):
    """Preview lights only: warm points in lanterns, sun through the high windows, sky fill."""
    for pid, (M, model) in world.items():
        for a, v in protos[model][1].items():
            if a.startswith("Light"):
                L = bpy.data.lights.new("PL", "POINT")
                L.energy = 260 if model == "Lodge_Chandelier" else 140
                L.color = (1.0, 0.78, 0.48)
                L.shadow_soft_size = 0.3
                ob = bpy.data.objects.new("PreviewLight_" + pid + a, L)
                ob.location = M @ Vector(v)
                col.objects.link(ob)


def setup_render(scene, samples, size):
    w, h = (int(x) for x in size.split("x"))
    s = scene
    s.render.engine = "CYCLES"
    s.cycles.device = "CPU"
    s.cycles.samples = samples
    s.cycles.use_denoising = True
    s.cycles.max_bounces = 6
    s.render.resolution_x, s.render.resolution_y = w, h
    s.view_settings.view_transform = "AgX"
    s.view_settings.look = "AgX - Base Contrast" if "AgX - Base Contrast" in [x.identifier for x in
                                                                             s.view_settings.bl_rna.properties["look"].enum_items] else "None"
    s.view_settings.exposure = 0.35
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (*B.srgb_to_linear((0.72, 0.84, 0.95)), 1)
    bg.inputs["Strength"].default_value = 1.4
    s.world = world
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 4.5
    sun.data.angle = math.radians(3)
    sun.data.color = (1.0, 0.92, 0.8)
    sun.rotation_euler = (math.radians(52), math.radians(-28), math.radians(-30))
    s.collection.objects.link(sun)
    for x in (-20, 20):   # warm interior fill under the roof (preview only)
        a = bpy.data.objects.new("Fill", bpy.data.lights.new("Fill", "AREA"))
        a.data.energy = 9000
        a.data.size = 30
        a.data.color = (1.0, 0.86, 0.68)
        a.location = (x, 0, 24)
        s.collection.objects.link(a)
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    s.collection.objects.link(cam)
    s.camera = cam
    return cam


def aim(cam, loc, target, lens):
    cam.location = loc
    d = Vector(target) - Vector(loc)
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    if lens is None:
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = 92
        cam.rotation_euler = (0, 0, 0)
    else:
        cam.data.type = "PERSP"
        cam.data.lens = lens
        cam.data.sensor_width = 36
    cam.data.clip_end = 1000


def main():
    args = parse()
    if args.contact:
        contact_sheets()
        return
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    import importlib
    for mod in B.MODULES:
        importlib.import_module(mod)
    names = sorted({r[1] for r in PLACEMENT})
    has_building = any(r[0] == "Lodge_Building" for r in K.REGISTRY)
    protos = build_protos(names + (["Lodge_Building"] if has_building else []))
    col = bpy.data.collections.new("Lodge_Furnished")
    scene.collection.children.link(col)
    world, rows = place_all(protos, col)
    os.makedirs(os.path.dirname(OUT_JSON), exist_ok=True)
    with open(OUT_JSON, "w") as f:
        json.dump(dict(note="Generated by blender/lodge_scene.py. Blender = room design axes (front -Y, rot CCW about +Z). "
                            "Roblox pos = (-X, Z, Y) from the Lodge root (repo pipeline mapping, same as Lodge_Building); CFrame = CFrame.new(pos) * CFrame.Angles(0, math.rad(yaw), 0) "
                            "applied to the kit Model's Root (MeshService), relative to the Lodge_Building pivot CFrame.",
                       instances=rows), f, indent=1)
    print("wrote", OUT_JSON, len(rows), "instances")
    if args.no_render:
        return
    shell = bpy.data.collections.new("StandIn")
    scene.collection.children.link(shell)
    if has_building:
        roof_names = ("Ceiling", "RoofBase", "RoofTiles", "RidgeCap", "RoofTrim", "RoofFrame", "Trusses", "TrussPegs", "Gable", "Iron")
        roof = []
        for o in protos["Lodge_Building"][0]:
            c = o.copy()
            c.hide_render = bool(o["render_hide"])
            shell.objects.link(c)
            if o.name.startswith(roof_names):
                roof.append(c)
    else:
        objs, roof = standin_room(shell)
        roof += [o for o in objs if "TieBeam" in o.name]
    pv = bpy.data.collections.new("PreviewOnly")
    scene.collection.children.link(pv)
    labels(world, protos, pv)
    lights(world, protos, pv)
    cam = setup_render(scene, args.samples, args.size)
    os.makedirs(OUT_DIR, exist_ok=True)
    for name in args.cams.split(","):
        loc, target, lens = CAMERAS[name]
        aim(cam, loc, target, lens)
        hide_roof = name in ("Cutaway", "Plan")
        w, h = (int(x) for x in args.size.split("x"))
        scene.render.resolution_x, scene.render.resolution_y = (h, h) if name == "Plan" else (w, h)
        for o in roof:
            o.hide_render = hide_roof
        scene.render.filepath = os.path.join(OUT_DIR, "layout_%s.png" % name.lower())
        bpy.ops.render.render(write_still=True)
        print("rendered", scene.render.filepath)


if __name__ == "__main__":
    main()
