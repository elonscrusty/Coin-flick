"""Blender kit 1015j for the lobby (2026-10-15, polish thread): chunky flat-shaded low-poly pieces, colours baked into one
<Name>_tex.png per piece, exported as a flat folder of FBX + PNG for Roblox's 3D importer.

Run on the $200 runner (Blender 3.6+ or 4.x, no add-ons needed):
    blender -b -P tools/blender/lobby_kit_1015j.py -- <out_folder>
<out_folder> defaults to ./lobby_kit_1015j. Deterministic (fixed seeds). Prints one line per piece.

Pieces (names are the contract with tools/studio/lobby_redesign/runtime.luau, which swaps them in by name and keeps
the old scripted / kit pieces when a name is missing). Sizes don't matter: the build fits each piece to its slot.
  Path kit      PathCurb_Stone_v1 (white edge stone), PlazaPaver_Disc_v1 (round cream paver disc)
  Rock wall     RockWall_A_v1 .. RockWall_D_v1 (blue-grey faceted cliffs with grass caps)
  Pines         Pine_Tall_v1, Pine_Mid_v1, Pine_Small_v1, Tree_RoundChunky_v1
  Clouds        Cloud_A_v1 .. Cloud_D_v1
  Far hills     FarHillRing_A_v1 .. FarHillRing_C_v1 (green hill segments with little pines baked in)
Style: bright cartoon, always day, flat shading, chunky. No text, no logos.
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Vector

OUT = os.path.abspath(sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv and len(sys.argv) > sys.argv.index("--") + 1
                      else "lobby_kit_1015j")
os.makedirs(OUT, exist_ok=True)
TEX = 256

GRASS = ["5cae3c", "52a636", "66b845"]
STONE = ["a7b3c9", "97a4be", "b4bfd2", "8e9cb8", "a0adc5"]  # r30k: lighter blue-grey, wider spread for facet contrast (read dark navy in Studio)
PINE = ["2f8a3a", "3a9a3f", "47ab46"]
TRUNK = "6b4a2b"
CLOUD_TOP, CLOUD_UNDER = "ffffff", "dfe8f6"
SAND = ["efe0ad", "e6d59f"]
CURB, CURB_UNDER = "f4f2ea", "d9d6cc"


def hex_rgba(h):
    return (int(h[0:2], 16) / 255) ** 2.2, (int(h[2:4], 16) / 255) ** 2.2, (int(h[4:6], 16) / 255) ** 2.2, 1.0


_mats = {}


def mat(h):
    if h not in _mats:
        m = bpy.data.materials.new("c_" + h)
        m.use_nodes = True
        m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = hex_rgba(h)
        _mats[h] = m
    return _mats[h]


def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for block in (bpy.data.meshes, bpy.data.images):
        for b in list(block):
            if b.users == 0:
                block.remove(b)


class Builder:
    """Collects faces with a colour each into one bmesh."""

    def __init__(self):
        self.bm = bmesh.new()
        self.cols = []

    def add(self, other_bm, colour_of_face):
        """Copy a bmesh in; colour_of_face(face) -> hex."""
        vmap = {}
        for v in other_bm.verts:
            vmap[v] = self.bm.verts.new(v.co)
        for f in other_bm.faces:
            nf = self.bm.faces.new([vmap[v] for v in f.verts])
            self.cols.append(colour_of_face(f))
            nf.material_index = 0
        other_bm.free()

    def finish(self, name):
        me = bpy.data.meshes.new(name)
        self.bm.normal_update()
        self.bm.to_mesh(me)
        self.bm.free()
        ob = bpy.data.objects.new(name, me)
        bpy.context.collection.objects.link(ob)
        order = []
        for c in self.cols:
            if c not in order:
                order.append(c)
        for c in order:
            me.materials.append(mat(c))
        for poly, c in zip(me.polygons, self.cols):
            poly.material_index = order.index(c)
            poly.use_smooth = False
        return ob


def cube_bm(sx, sy, sz, cuts=0, bevel=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * sx, v.co.y * sy, v.co.z * sz + sz / 2))
    if cuts:
        bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=cuts, use_grid_fill=True)
    if bevel:
        bmesh.ops.bevel(bm, geom=bm.edges[:], offset=bevel, segments=1, affect="EDGES")
    bmesh.ops.triangulate(bm, faces=bm.faces[:]) if cuts else None
    bm.normal_update()
    return bm


def cone_bm(r1, r2, h, segs, z0=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r1, radius2=r2, depth=h)
    for v in bm.verts:
        v.co.z += h / 2 + z0
    bm.normal_update()
    return bm


def ico_bm(r, center, rnd, jitter=0.12):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=r)
    for v in bm.verts:
        v.co = v.co * (1 + rnd.uniform(-jitter, jitter)) + Vector(center)
    bm.normal_update()
    return bm


def upward(f, lim=0.55):
    return f.normal.z > lim


# --- pieces -------------------------------------------------------------------------------------------------------

def rock_wall(name, w, h, d, seed):
    rnd = random.Random(seed)
    bm = cube_bm(w, d, h, cuts=2)
    for v in bm.verts:
        if v.co.z > 0.01:  # bottom stays flat on the ground
            v.co.x += rnd.uniform(-0.09, 0.09) * w
            v.co.y += rnd.uniform(-0.12, 0.12) * d
            v.co.z += rnd.uniform(-0.08, 0.1) * h
    bm.normal_update()
    b = Builder()
    b.add(bm, lambda f: rnd.choice(GRASS) if upward(f) else rnd.choice(STONE))
    for k in range(rnd.randint(2, 3)):  # chunky boulders at the foot
        r = rnd.uniform(0.12, 0.2) * h
        b.add(ico_bm(r, (rnd.uniform(-0.4, 0.4) * w, -d * 0.55, r * 0.6), rnd), lambda f: rnd.choice(STONE))
    return b.finish(name)


def pine(name, H, tiers, seed):
    rnd = random.Random(seed)
    b = Builder()
    b.add(cone_bm(0.07 * H, 0.06 * H, 0.28 * H, 6), lambda f: TRUNK)
    z = 0.18 * H
    for t in range(tiers):
        r = (0.34 - 0.07 * t) * H
        hh = (0.42 - 0.05 * t) * H
        col = PINE[t % len(PINE)]
        b.add(cone_bm(r, 0.0, hh, 7, z), lambda f, c=col: c)
        z += hh * 0.55
    return b.finish(name)


def round_tree(name, H, seed):
    rnd = random.Random(seed)
    b = Builder()
    b.add(cone_bm(0.08 * H, 0.06 * H, 0.45 * H, 6), lambda f: TRUNK)
    b.add(ico_bm(0.32 * H, (0, 0, 0.62 * H), rnd), lambda f: rnd.choice(GRASS))
    b.add(ico_bm(0.2 * H, (0.22 * H, 0.05 * H, 0.5 * H), rnd), lambda f: rnd.choice(GRASS))
    return b.finish(name)


def cloud(name, w, seed):
    rnd = random.Random(seed)
    b = Builder()
    n = rnd.randint(4, 6)
    for k in range(n):
        r = w * rnd.uniform(0.14, 0.22) * (1.25 if 0 < k < n - 1 else 1)
        x = (k / (n - 1) - 0.5) * w * 0.75
        b.add(ico_bm(r, (x, rnd.uniform(-0.08, 0.08) * w, rnd.uniform(0, 0.08) * w), rnd, 0.08),
              lambda f: CLOUD_UNDER if f.normal.z < -0.3 else CLOUD_TOP)
    return b.finish(name)


def far_hill(name, seed):
    rnd = random.Random(seed)
    W, D, NX, NY = 140.0, 46.0, 14, 5
    bm = bmesh.new()
    grid = [[None] * (NY + 1) for _ in range(NX + 1)]
    phase = rnd.uniform(0, 6.28)
    for i in range(NX + 1):
        for j in range(NY + 1):
            x = (i / NX - 0.5) * W
            y = (j / NY - 0.5) * D
            ridge = math.sin(math.pi * j / NY)  # 0 at front and back edge, high in the middle
            hgt = ridge * (16 + 12 * math.sin(i * 0.7 + phase) + rnd.uniform(-3, 3))
            if i in (0, NX):
                hgt *= 0.6
            grid[i][j] = bm.verts.new((x, y, max(0.0, hgt)))
    for i in range(NX):
        for j in range(NY):
            bm.faces.new([grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]])
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.normal_update()
    b = Builder()
    b.add(bm, lambda f: rnd.choice(["5a9a48", "63a64f", "6aad55"]))
    for _ in range(10):  # little pines on the slopes
        i, j = rnd.randint(1, NX - 1), rnd.randint(1, NY - 1)
        x = (i / NX - 0.5) * W
        y = (j / NY - 0.5) * D
        ridge = math.sin(math.pi * j / NY)
        z = max(0.0, ridge * 16) - 1
        H = rnd.uniform(9, 14)
        b.add(cone_bm(0.3 * H, 0.0, 0.8 * H, 7, z + 0.15 * H), lambda f: rnd.choice(PINE))
        b.add(cone_bm(0.05 * H, 0.05 * H, 0.2 * H, 5, z), lambda f: TRUNK)
    return b.finish(name)


def curb(name):
    b = Builder()
    b.add(cube_bm(1.5, 0.8, 0.5, bevel=0.08), lambda f: CURB_UNDER if f.normal.z < -0.5 else CURB)
    return b.finish(name)


def plaza_disc(name):
    b = Builder()
    R, ring_w, gap = 10.0, 2.2, 0.12
    r = 1.6
    bm = bmesh.new()
    bmesh.ops.create_circle(bm, cap_ends=True, segments=12, radius=r)
    bmesh.ops.extrude_face_region(bm, geom=bm.faces[:])
    for v in bm.verts[len(bm.verts) // 2:]:
        v.co.z = 0.2
    bm.normal_update()
    b.add(bm, lambda f: SAND[0])
    ring = 0
    while r + ring_w <= R:
        n = max(8, int(2 * math.pi * (r + ring_w / 2) / 2.6))
        for k in range(n):
            a0 = (k + gap) / n * 2 * math.pi + ring * 0.3
            a1 = (k + 1 - gap) / n * 2 * math.pi + ring * 0.3
            r0, r1 = r + gap, r + ring_w - gap
            tb = bmesh.new()
            pts = [(r0, a0), (r1, a0), (r1, a1), (r0, a1)]
            bot = [tb.verts.new((rr * math.cos(a), rr * math.sin(a), 0)) for rr, a in pts]
            top = [tb.verts.new((rr * math.cos(a), rr * math.sin(a), 0.2)) for rr, a in pts]
            tb.faces.new(top)
            tb.faces.new(list(reversed(bot)))
            for q in range(4):
                tb.faces.new([bot[q], bot[(q + 1) % 4], top[(q + 1) % 4], top[q]])
            bmesh.ops.recalc_face_normals(tb, faces=tb.faces[:])
            col = SAND[(k + ring) % 2]
            b.add(tb, lambda f, c=col: c)
        r += ring_w
        ring += 1
    return b.finish(name)


# --- bake + export ------------------------------------------------------------------------------------------------

def bake_and_export(ob):
    name = ob.name
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")
    img = bpy.data.images.new(name + "_tex", TEX, TEX)
    for m in ob.data.materials:
        nodes = m.node_tree.nodes
        node = nodes.new("ShaderNodeTexImage")
        node.image = img
        nodes.active = node
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 1
    scene.render.bake.use_pass_direct = False
    scene.render.bake.use_pass_indirect = False
    scene.render.bake.use_pass_color = True
    scene.render.bake.margin = 4
    bpy.ops.object.bake(type="DIFFUSE")
    img.filepath_raw = os.path.join(OUT, name + "_tex.png")
    img.file_format = "PNG"
    img.save()
    # one textured material in place of the colour materials
    tm = bpy.data.materials.new(name + "_mat")
    tm.use_nodes = True
    tex = tm.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tm.node_tree.links.new(tex.outputs["Color"], tm.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
    ob.data.materials.clear()
    ob.data.materials.append(tm)
    for p in ob.data.polygons:
        p.material_index = 0
    bpy.ops.export_scene.fbx(filepath=os.path.join(OUT, name + ".fbx"), use_selection=True, apply_unit_scale=True,
                             axis_forward="-Z", axis_up="Y", path_mode="RELATIVE", mesh_smooth_type="FACE")
    print(f"[kit1015j] {name}: {len(ob.data.polygons)} faces -> {name}.fbx + {name}_tex.png")


def make(fn, *args):
    clear()
    _mats.clear()
    ob = fn(*args)
    bake_and_export(ob)


make(curb, "PathCurb_Stone_v1")
make(plaza_disc, "PlazaPaver_Disc_v1")
make(rock_wall, "RockWall_A_v1", 24, 30, 12, 1)
make(rock_wall, "RockWall_B_v1", 18, 24, 10, 2)
make(rock_wall, "RockWall_C_v1", 30, 36, 14, 3)
make(rock_wall, "RockWall_D_v1", 14, 18, 9, 4)
make(pine, "Pine_Tall_v1", 30, 4, 11)
make(pine, "Pine_Mid_v1", 22, 3, 12)
make(pine, "Pine_Small_v1", 14, 3, 13)
make(round_tree, "Tree_RoundChunky_v1", 20, 14)
for k, nm in enumerate("ABCD"):
    make(cloud, f"Cloud_{nm}_v1", 60 + 10 * k, 20 + k)
for k, nm in enumerate("ABC"):
    make(far_hill, f"FarHillRing_{nm}_v1", 30 + k)
print("[kit1015j] done ->", OUT)
