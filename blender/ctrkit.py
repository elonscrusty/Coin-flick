"""CTR modelling kit: chunky bevelled low-poly pieces for Roblox MeshParts (Crack the Rocks style).

Conventions (every asset follows them; docs/MODELING.md has the long version)
  * 1 Blender unit = 1 stud. Author in Blender axes: +Z up, FRONT faces -Y, the model's pivot
    is the FLOOR CENTRE (0, 0, 0) unless the asset documents another origin (tools: the grip).
    Export maps Blender (x, y, z) -> Roblox (-x, z, y): Roblox +Y up, front -Z.
  * A model is a set of PIECES; each piece becomes one MeshPart. Pieces carry no textures and no
    vertex colours: the game colours each one from its colour SLOT (MeshPart.Color) and Roblox
    material, so a piece holds exactly one material. Use model.slot("Wood") to get the shared
    piece for a material and keep piece counts low; give animated or attachable bits their own
    named piece (model.piece("Bit", "SteelLight", anim="Plunge", pivot=(...))).
  * Big confident shapes, bevelled edges (BEVEL), broad flat-shaded facets, few small details.
  * preview=True pieces are only drawn in the preview renders (e.g. rocks sitting in a tray to
    compare against the sheet); they are not exported.
"""

import math
import random

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector
from mathutils.bvhtree import BVHTree

# ------------------------------------------------------------------ style

BEVEL = 0.06        # standard edge bevel (studs); big blocks use BEVEL_BIG
BEVEL_BIG = 0.1
BOLT_R = 0.09       # standard bolt head radius

HEX = {
    "Slate": "#202833",       # deepest dark: rubber, crack lines, deep shadow parts
    "Frame": "#4D5B66",       # dark steel frame (tables, trays, brackets)
    "FrameDark": "#363F48",   # darker steel (feet, inner walls)
    "Steel": "#7D8791",       # plate steel, hammer heads
    "SteelLight": "#B8C0C8",  # bolts, polished faces, bits
    "Concrete": "#C1B6A2",
    "Wood": "#A87548",
    "WoodDark": "#7E5634",
    "Amber": "#F4BE43",       # hazard paint, tool bodies
    "Accent": "#F4BE43",      # per-station accent (stripes, nameplate, beacon); recoloured in game
    "Brass": "#C9A050",
    "Cream": "#F4EFE5",
    "Rubber": "#25292F",
    "Rock": "#8F8D89",
    "RockDark": "#6E6B67",
    "Crack": "#2B2A2A",
    "Glass": "#F4C35A",       # amber shield glass (Glass material, transparency in game)
    "GlassClear": "#CFE3EC", # clear shield pane (pass 2; Glass material, transparency in game)
    "Lamp": "#FFC93A",        # beacon lens (Neon)
    "Red": "#D9382B",         # machine stop / run buttons (sheets 09, 10)
    "Green": "#3FB34F",
    "Cliff": "#8A8279",       # cliff faces (warmer than pile rocks)
    "CliffDark": "#736B62",   # shaded cliff blocks
    "RockLight": "#B2A38B",   # sunlit sandy cliff ledge caps
    "Timber": "#4E4238",      # dark weathered timber (gate, fence posts, shelter frame)
    "Stone": "#8E8C88",       # dressed stone blocks (retaining walls)
    "Moss": "#5F7A2F",        # sparse moss tufts on cliffs
}


def rgb(name_or_hex):
    h = HEX.get(name_or_hex, name_or_hex).lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


# default Roblox material per slot (a piece may override)
SLOT_MATERIAL = {
    "Wood": "Wood", "WoodDark": "Wood", "Frame": "Metal", "FrameDark": "Metal", "Steel": "Metal",
    "SteelLight": "Metal", "Brass": "Metal", "Glass": "Glass", "GlassClear": "Glass", "Lamp": "Neon",
    "Rock": "Slate", "RockDark": "Slate", "Concrete": "Concrete", "Red": "SmoothPlastic", "Green": "SmoothPlastic",
    "Cliff": "Slate", "CliffDark": "Slate", "RockLight": "Slate", "Timber": "Wood", "Stone": "Slate", "Moss": "SmoothPlastic",
}


def mat(loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    r = Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4()
    if not hasattr(scale, "__len__"):
        scale = (scale, scale, scale)
    return Matrix.Translation(Vector(loc)) @ r @ Matrix.Diagonal(Vector((*scale, 1.0)))


def _bevel(bm, amount, segments=1):
    if amount > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges) + list(bm.verts), offset=amount, segments=segments,
                        affect="EDGES", profile=0.5, clamp_overlap=True)


def hull_bm(points):
    """bmesh of the convex hull of points (chunky rock facets)."""
    t = bmesh.new()
    vs = [t.verts.new(p) for p in points]
    res = bmesh.ops.convex_hull(t, input=vs)
    for g in res["geom_interior"] + res["geom_unused"]:
        if isinstance(g, bmesh.types.BMVert) and g.is_valid and not g.link_faces:
            t.verts.remove(g)
    bmesh.ops.recalc_face_normals(t, faces=t.faces)
    return t


class Piece:
    def __init__(self, name, slot, material=None, anim=None, pivot=None, transparency=0.0, preview=False, note=""):
        self.name = name
        self.slot = slot
        self.material = material or SLOT_MATERIAL.get(slot, "SmoothPlastic")
        self.anim = anim
        self.pivot = Vector(pivot) if pivot is not None else None
        self.transparency = transparency
        self.preview = preview
        self.note = note
        self.bm = bmesh.new()

    # every primitive is built in a temporary bmesh, transformed, then merged in
    def _merge(self, tmp, m=None):
        if m is not None:
            tmp.transform(m)
        me = bpy.data.meshes.new("_tmp")
        tmp.to_mesh(me)
        tmp.free()
        self.bm.from_mesh(me)
        bpy.data.meshes.remove(me)
        return self

    def box(self, size, loc=(0, 0, 0), rot=(0, 0, 0), bevel=BEVEL, taper=None):
        """Bevelled box centred at loc. taper=(sx, sy) shrinks the top face."""
        t = bmesh.new()
        bmesh.ops.create_cube(t, size=1.0)
        if taper:
            for v in t.verts:
                if v.co.z > 0:
                    v.co.x *= taper[0]
                    v.co.y *= taper[1]
        t.transform(Matrix.Diagonal(Vector((*size, 1.0))))
        _bevel(t, min(bevel, min(size) * 0.3))
        return self._merge(t, mat(loc, rot))

    def box_between(self, a, b, thick, bevel=BEVEL, up=(0, 0, 1)):
        """Square bar of side `thick` from point a to point b (braces, struts)."""
        a, b = Vector(a), Vector(b)
        d = b - a
        t = bmesh.new()
        bmesh.ops.create_cube(t, size=1.0)
        tx, ty = (thick, thick) if not hasattr(thick, "__len__") else thick
        t.transform(Matrix.Diagonal(Vector((tx, ty, d.length, 1.0))))
        _bevel(t, min(bevel, min(tx, ty) * 0.3))
        q = d.normalized().to_track_quat("Z", "Y" if abs(d.normalized().z) < 0.9 else "X")
        return self._merge(t, Matrix.Translation((a + b) / 2) @ q.to_matrix().to_4x4())

    def cyl(self, r1, r2, h, seg=8, loc=(0, 0, 0), rot=(0, 0, 0), bevel=0.0, scale=(1, 1)):
        """Faceted cylinder / cone along +Z centred at loc."""
        t = bmesh.new()
        bmesh.ops.create_cone(t, cap_ends=True, cap_tris=False, segments=seg,
                              radius1=r1, radius2=max(r2, 0.0001), depth=h)
        t.transform(Matrix.Diagonal(Vector((scale[0], scale[1], 1, 1))))
        _bevel(t, bevel)
        return self._merge(t, mat(loc, rot))

    def bolt(self, loc, normal=(0, 0, 1), r=BOLT_R, h=0.06, seg=6):
        """Hex bolt head sitting on a surface at loc, facing `normal`."""
        n = Vector(normal).normalized()
        t = bmesh.new()
        bmesh.ops.create_cone(t, cap_ends=True, cap_tris=False, segments=seg, radius1=r, radius2=r * 0.8, depth=h)
        t.transform(Matrix.Translation((0, 0, h / 2)))
        q = n.to_track_quat("Z", "Y" if abs(n.z) < 0.9 else "X")
        return self._merge(t, Matrix.Translation(Vector(loc)) @ q.to_matrix().to_4x4())

    def tube(self, points, r, seg=8, closed_ends=True):
        """Bent pipe through points (handles, hose, posts) as joined cylinders + joint balls."""
        pts = [Vector(p) for p in points]
        for i in range(len(pts) - 1):
            a, b = pts[i], pts[i + 1]
            d = b - a
            t = bmesh.new()
            bmesh.ops.create_cone(t, cap_ends=closed_ends, segments=seg, radius1=r, radius2=r, depth=d.length)
            t.transform(Matrix.Translation((0, 0, d.length / 2)))
            q = d.normalized().to_track_quat("Z", "Y" if abs(d.normalized().z) < 0.9 else "X")
            self._merge(t, Matrix.Translation(a) @ q.to_matrix().to_4x4())
            if 0 < i:
                s = bmesh.new()
                bmesh.ops.create_icosphere(s, subdivisions=1, radius=r * 1.02)
                self._merge(s, Matrix.Translation(a))
        return self

    def prism(self, profile, depth, loc=(0, 0, 0), rot=(0, 0, 0), bevel=0.0):
        """Extruded 2D outline (x, z) with thickness `depth` along Y."""
        t = bmesh.new()
        verts = [t.verts.new((x, -depth / 2, z)) for x, z in profile]
        face = t.faces.new(verts)
        ext = bmesh.ops.extrude_face_region(t, geom=[face])
        moved = [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]
        bmesh.ops.translate(t, vec=(0, depth, 0), verts=moved)
        bmesh.ops.recalc_face_normals(t, faces=t.faces)
        _bevel(t, bevel)
        return self._merge(t, mat(loc, rot))

    def hull(self, points, loc=(0, 0, 0), rot=(0, 0, 0), bevel=0.0):
        t = hull_bm(points)
        _bevel(t, bevel)
        return self._merge(t, mat(loc, rot))

    def add_bm(self, t, m=None):
        return self._merge(t, m)

    # ---------------------------------------------------------------- output
    def finish(self):
        bm = self.bm
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
        mins = Vector([min(v.co[i] for v in bm.verts) for i in range(3)])
        maxs = Vector([max(v.co[i] for v in bm.verts) for i in range(3)])
        center = (mins + maxs) / 2
        bmesh.ops.translate(bm, vec=-center, verts=bm.verts)
        self.center, self.size = center, maxs - mins
        self.tris = sum(len(f.verts) - 2 for f in bm.faces)
        return self


class Model:
    def __init__(self, name, sheet, note=""):
        self.name, self.sheet, self.note = name, sheet, note
        self.pieces = []
        self._slots = {}
        self.attach = {}   # name -> Blender point; exported as Roblox points from the origin
        self.extra = {}

    def piece(self, name, slot, material=None, anim=None, pivot=None, transparency=0.0, preview=False, note=""):
        p = Piece(name, slot, material, anim, pivot, transparency, preview, note)
        self.pieces.append(p)
        return p

    def slot(self, slot, material=None):
        """The shared piece for one colour slot (named after the slot)."""
        key = (slot, material)
        if key not in self._slots:
            self._slots[key] = self.piece(slot if material is None else f"{slot}_{material}", slot, material)
        return self._slots[key]

    def preview_piece(self, name, slot):
        key = ("preview", name)
        if key not in self._slots:
            self._slots[key] = self.piece(name, slot, preview=True)
        return self._slots[key]


# ------------------------------------------------------------------ shared builders

def rock_points(seed, size=(1, 1, 1), n=22, shape="round", flat_bottom=0.15):
    """Points for a chunky rock hull of roughly `size` (x, y, z), base on z = 0."""
    rng = random.Random(seed)
    sx, sy, sz = size
    pts = []
    golden = math.pi * (3 - math.sqrt(5))
    for i in range(n):
        z = 1 - (i + 0.5) * 2 / n
        r = math.sqrt(1 - z * z)
        a = golden * i + rng.uniform(-0.35, 0.35)
        x, y = math.cos(a) * r, math.sin(a) * r
        k = 1 + rng.uniform(-0.12, 0.1)
        if shape == "cube":   # pull points toward a rounded cube
            m = max(abs(x), abs(y), abs(z)) or 1
            x, y, z = [c / m * 0.62 + c * 0.38 for c in (x, y, z)]
        pts.append(Vector((x * k * sx / 2, y * k * sy / 2, (z * k + 1) * sz / 2)))
    lo = sz * flat_bottom
    pts = [p for p in pts if p.z >= lo]
    for i in range(6):   # a small flat footprint so the rock sits on the ground
        a = i / 6 * math.tau + rng.uniform(-0.3, 0.3)
        pts.append(Vector((math.cos(a) * sx * 0.3 * rng.uniform(0.8, 1.1), math.sin(a) * sy * 0.3 * rng.uniform(0.8, 1.1), 0.0)))
    zmin = min(p.z for p in pts)
    for p in pts:
        p.z -= zmin
    return pts


def roughen(points, seed, count=14, amount=0.06, keep_base=True):
    """More, uneven facets: add points sampled on the hull's faces pushed out by up to `amount`
    (times the rock size). Re-hulling the result gives the chunky hand-cut look of the sheets."""
    rng = random.Random(seed)
    t = hull_bm(points)
    faces = list(t.faces)
    areas = [f.calc_area() for f in faces]
    total = sum(areas) or 1
    size = max((max(p[i] for p in points) - min(p[i] for p in points)) for i in range(3))
    zmin = min(p.z for p in points)
    out = [Vector(p) for p in points]
    for _ in range(count):
        r = rng.uniform(0, total)
        for f, a in zip(faces, areas):
            r -= a
            if r <= 0:
                break
        if keep_base and f.normal.z < -0.8:
            continue
        vs = [v.co for v in f.verts]
        w = [rng.random() + 0.05 for _ in vs]
        sw = sum(w)
        p = sum((v * (wi / sw) for v, wi in zip(vs, w)), Vector())
        p = p + f.normal * rng.uniform(0.2, 1.0) * amount * size
        p.z = max(p.z, zmin)
        out.append(p)
    t.free()
    return out


def scatter_rocks(piece, count, area, size_range, seed, z=0.0, flat=0.85, origin=(0, 0, 0)):
    """Small hull rocks scattered over area=(x0, y0, x1, y1) at height z (rubble, grit, tray fill)."""
    rng = random.Random(seed)
    placed = []
    tries = 0
    while len(placed) < count and tries < count * 40:
        tries += 1
        s = rng.uniform(*size_range)
        x, y = rng.uniform(area[0] + s / 2, area[2] - s / 2), rng.uniform(area[1] + s / 2, area[3] - s / 2)
        if any((Vector((x, y)) - q).length < (s + qs) * 0.42 for q, qs in placed):
            continue
        placed.append((Vector((x, y)), s))
        pts = rock_points(rng.randrange(1 << 30), (s, s * rng.uniform(0.8, 1.1), s * flat * rng.uniform(0.8, 1.1)), n=12)
        piece.hull(pts, loc=Vector(origin) + Vector((x, y, z)), rot=(0, 0, rng.uniform(0, 360)))
    return placed


def hazard_stripes(piece_stripe, width, height, loc, rot=(0, 0, 0), count=4, slant=0.6, depth=0.03, margin=0.06):
    """Diagonal hazard stripes: parallelograms clipped to a width x height rectangle in the local
    XZ plane, `depth` thick along local Y, centred at loc and turned by rot (degrees).
    Front face: rot (0, 0, 0); right face (+X): (0, 0, 90); top face: (90, 0, 0)."""
    w, h = width - 2 * margin, height - 2 * margin
    pitch = (w + h * slant) / (count * 2)
    for i in range(count + 1):
        x0 = -w / 2 - h * slant + i * 2 * pitch + pitch * 0.5
        quad = [(x0, -h / 2), (x0 + pitch, -h / 2), (x0 + pitch + h * slant, h / 2), (x0 + h * slant, h / 2)]
        poly = _clip_rect(quad, -w / 2, w / 2, -h / 2, h / 2)
        if len(poly) < 3:
            continue
        piece_stripe.prism(poly, depth, loc=loc, rot=rot)


def _clip_rect(poly, x0, x1, y0, y1):
    def clip(pts, inside, inter):
        out = []
        for i in range(len(pts)):
            a, b = pts[i - 1], pts[i]
            if inside(b):
                if not inside(a):
                    out.append(inter(a, b))
                out.append(b)
            elif inside(a):
                out.append(inter(a, b))
        return out

    def ix(xv):
        return lambda a, b: (xv, a[1] + (b[1] - a[1]) * (xv - a[0]) / ((b[0] - a[0]) or 1e-9))

    def iy(yv):
        return lambda a, b: (a[0] + (b[0] - a[0]) * (yv - a[1]) / ((b[1] - a[1]) or 1e-9), yv)

    p = poly
    p = clip(p, lambda q: q[0] >= x0, ix(x0)) if p else p
    p = clip(p, lambda q: q[0] <= x1, ix(x1)) if p else p
    p = clip(p, lambda q: q[1] >= y0, iy(y0)) if p else p
    p = clip(p, lambda q: q[1] <= y1, iy(y1)) if p else p
    return p


def crack_strips(piece, hull_points, seed, cracks=1, width=0.05, wander=0.12, front_only=True, loc=(0, 0, 0), rot=(0, 0, 0)):
    """Thin dark crack ribbons lying on a rock hull's surface (hairline / wider crack stages).
    Each crack follows a plane cut through the rock, zig-zagged and snapped back onto the surface."""
    rng = random.Random(seed)
    src = hull_bm(hull_points)
    bvh = BVHTree.FromBMesh(src)
    zs = [p.z for p in hull_points]
    centre = Vector((sum(p.x for p in hull_points) / len(hull_points), sum(p.y for p in hull_points) / len(hull_points),
                     (min(zs) + max(zs)) / 2))
    out = bmesh.new()
    for c in range(cracks):
        ang = rng.uniform(-0.9, 0.9) + c * 1.3
        n = Vector((math.cos(ang), 0.35 * rng.uniform(-1, 1), math.sin(ang) * 0.6)).normalized()
        u = n.cross(Vector((0, 1, 0))).normalized()   # in-plane direction around the front
        v = n.cross(u).normalized()
        path = []
        steps = 26
        for i in range(steps + 1):
            a = -math.pi * 0.95 + i / steps * math.pi * 1.9
            d = (u * math.cos(a) + v * math.sin(a)).normalized()
            d += n * rng.uniform(-wander, wander)
            hit = bvh.ray_cast(centre + d * 10, -d)
            if hit[0] is None:
                continue
            p, nrm = hit[0], hit[1]
            if front_only and nrm.y > 0.25:
                if len(path) > 1:
                    _strip(out, path, width)
                path = []
                continue
            path.append((p + nrm * 0.012, nrm))
        if len(path) > 1:
            _strip(out, path, width)
    src.free()
    piece.add_bm(out, mat(loc, rot))


def _strip(bm, path, width):
    prev = None
    for i, (p, nrm) in enumerate(path):
        nxt = path[min(i + 1, len(path) - 1)][0]
        bef = path[max(i - 1, 0)][0]
        tan = (nxt - bef).normalized()
        side = nrm.cross(tan).normalized() * width * (0.6 + 0.4 * math.sin(i * 1.7) ** 2)
        a, b = bm.verts.new(p - side), bm.verts.new(p + side)
        if prev:
            try:
                f = bm.faces.new((prev[0], prev[1], b, a))
                if f.normal.dot(nrm) < 0:
                    f.normal_flip()
            except ValueError:
                pass
        prev = (a, b)


def clip_hull(points, planes):
    """Convex hull of `points` clipped by planes [(point, normal)] keeping the side the normal points away from."""
    t = hull_bm(points)
    verts = [v.co.copy() for v in t.verts]
    edges = [(e.verts[0].co.copy(), e.verts[1].co.copy()) for e in t.edges]
    t.free()
    for (pp, nn) in planes:
        pp, nn = Vector(pp), Vector(nn)
        keep = [v for v in verts if (v - pp).dot(nn) <= 0]
        for a, b in edges:
            da, db = (a - pp).dot(nn), (b - pp).dot(nn)
            if (da < 0) != (db < 0):
                keep.append(a + (b - a) * (da / (da - db)))
        verts = keep
        if len(verts) < 4:
            return []
        t = hull_bm(verts)
        verts = [v.co.copy() for v in t.verts]
        edges = [(e.verts[0].co.copy(), e.verts[1].co.copy()) for e in t.edges]
        t.free()
    return verts


# ------------------------------------------------------------------ coordinates + registry

def to_roblox(v):
    """Blender (x, y, z) -> Roblox (x, y, z) for FBX Forward=Z, Up=Y."""
    return [round(-v[0], 4) + 0.0, round(v[2], 4) + 0.0, round(v[1], 4) + 0.0]


def roblox_size(s):
    return [round(s[0], 4), round(s[2], 4), round(s[1], 4)]


REGISTRY = []


def register(name, sheet, note="", ref=None):
    """Register a model builder. ref = (sheet_png, (x0, y0, x1, y1)) crop of the reference sheet
    that tools/ref_compare.py shows next to the render."""
    def deco(fn):
        REGISTRY.append((name, sheet, note, ref, fn))
        return fn
    return deco
