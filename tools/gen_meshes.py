"""Generate the original CT_Rocks_ low-poly meshes as binary glTF (.glb).

    python3 tools/gen_meshes.py [--sheet art/meshes/contact_sheet.png]

Conventions: studs, front -Z, up +Y. Flat normals, vertex colours (COLOR_0, linear-ish values
used as a tint over MeshPart.Color). Deterministic: fixed seeds, no external assets.
Output: art/meshes/<Name>.glb plus art/meshes/manifest.json (tri counts, bounds).
"""

import argparse
import json
import math
import os
import struct

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "art", "meshes")


class Mesh:
    def __init__(self):
        self.tris = []  # (3,3) arrays
        self.cols = []  # (3,) per triangle

    def tri(self, a, b, c, col):
        self.tris.append(np.array([a, b, c], dtype=np.float64))
        self.cols.append(np.array(col, dtype=np.float64))

    def quad(self, a, b, c, d, col):
        self.tri(a, b, c, col)
        self.tri(a, c, d, col)

    def fan(self, ring, col, flip=False):
        c = np.mean(ring, axis=0)
        n = len(ring)
        for i in range(n):
            a, b = ring[i], ring[(i + 1) % n]
            if flip:
                self.tri(c, b, a, col)
            else:
                self.tri(c, a, b, col)

    def orient_outward(self, centre=None):
        """Flip triangles whose normal points toward `centre` (for closed convex-ish solids)."""
        for i, t in enumerate(self.tris):
            n = np.cross(t[1] - t[0], t[2] - t[0])
            mid = t.mean(axis=0)
            ref = mid - (np.zeros(3) if centre is None else centre)
            if np.dot(n, ref) < 0:
                self.tris[i] = t[[0, 2, 1]]

    def merge(self, other):
        self.tris += other.tris
        self.cols += other.cols

    def arrays(self):
        pos = np.array(self.tris, dtype=np.float32).reshape(-1, 3)
        nrm = np.zeros_like(pos)
        col = np.zeros((len(pos), 4), dtype=np.float32)
        for i, t in enumerate(self.tris):
            n = np.cross(t[1] - t[0], t[2] - t[0])
            ln = np.linalg.norm(n)
            n = n / ln if ln > 1e-12 else np.array([0, 1, 0])
            nrm[i * 3:i * 3 + 3] = n
            col[i * 3:i * 3 + 3] = list(self.cols[i]) + [1.0]
        return pos, nrm, col


def shade(base, k):
    return tuple(min(1.0, max(0.0, c * k)) for c in base)


# ---------------------------------------------------------------- primitives

def icosphere(sub):
    t = (1 + 5 ** 0.5) / 2
    v = [(-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t), (0, -1, -t), (0, 1, -t),
         (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1)]
    v = [np.array(x, dtype=float) / np.linalg.norm(x) for x in v]
    f = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6),
         (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10),
         (8, 6, 7), (9, 8, 1)]
    for _ in range(sub):
        cache = {}

        def mid(a, b):
            k = (min(a, b), max(a, b))
            if k not in cache:
                m = v[a] + v[b]
                v.append(m / np.linalg.norm(m))
                cache[k] = len(v) - 1
            return cache[k]

        nf = []
        for a, b, c in f:
            ab, bc, ca = mid(a, b), mid(b, c), mid(c, a)
            nf += [(a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)]
        f = nf
    return np.array(v), f


def prism(profile, y0, y1, col_side, col_cap, tip=None, bevel=0.0, axis="y", sides_shade=True):
    """Extrude a convex 2D profile (list of (a,b)) between y0 and y1 along an axis.
    tip: (height, scale) puts a pointed/tapered cap above y1 (scale 0 = point).
    bevel: inset ring (fraction) at both ends for a chamfered look."""
    m = Mesh()
    P = np.array(profile, dtype=float)
    n = len(P)

    def pt(p, y):
        if axis == "y":
            return np.array([p[0], y, p[1]])
        if axis == "x":
            return np.array([y, p[0], p[1]])
        return np.array([p[0], p[1], y])

    rings = []  # (scale, y)
    if bevel > 0:
        b = min(bevel, (y1 - y0) * 0.45)
        rings = [(1 - bevel * 0.9, y0), (1.0, y0 + b), (1.0, y1 - b), (1 - bevel * 0.9, y1)]
    else:
        rings = [(1.0, y0), (1.0, y1)]
    if tip is not None:
        h, sc = tip
        rings.append((sc, y1 + h))
    pts = [[pt(P[i] * s, y) for i in range(n)] for s, y in rings]
    for r in range(len(rings) - 1):
        for i in range(n):
            j = (i + 1) % n
            k = 0.82 + 0.18 * (i % 3) / 2 if sides_shade else 1.0
            c = shade(col_side, k * (0.92 if r == 0 and bevel > 0 else 1.0))
            m.quad(pts[r][i], pts[r][j], pts[r + 1][j], pts[r + 1][i], c)
    m.fan(pts[0], shade(col_cap, 0.8), flip=True)
    m.fan(pts[-1], col_cap)
    allp = np.array(m.tris).reshape(-1, 3)
    m.orient_outward(allp.mean(axis=0))
    return m


def ngon(n, rx, rz=None, rot=0.0):
    rz = rx if rz is None else rz
    return [(math.cos(rot + i / n * 2 * math.pi) * rx, math.sin(rot + i / n * 2 * math.pi) * rz) for i in range(n)]


def chamfer_rect(w, d, c):
    """Rectangle w x d (half sizes) with corners cut by c."""
    return [(w - c, -d), (w, -d + c), (w, d - c), (w - c, d), (-w + c, d), (-w, d - c), (-w, -d + c), (-w + c, -d)]


def orient(m, centre):
    m.orient_outward(np.array(centre, dtype=float))
    return m


def translate(m, off):
    off = np.array(off, dtype=float)
    out = Mesh()
    out.tris = [t + off for t in m.tris]
    out.cols = list(m.cols)
    return out


# ---------------------------------------------------------------- assets

ROCK = (0.62, 0.64, 0.67)
ROCK_LIGHT = (0.78, 0.8, 0.82)


def rock_shell(seed, dims, sub=2):
    rng = np.random.default_rng(seed)
    v, f = icosphere(sub)
    ph = rng.uniform(0, 6.28, 3)
    low = 1 + 0.13 * np.sin(v[:, 0] * 2.3 + ph[0]) * np.cos(v[:, 2] * 2.1 + ph[1]) + 0.08 * np.sin(v[:, 1] * 3.1 + ph[2])
    noise = low * rng.uniform(0.95, 1.04, len(v))
    pts = v * noise[:, None] * np.array(dims)[None, :]
    # chamfer the bottom: flat base so rocks sit on the pile
    floor = -dims[1] * 0.62
    pts[:, 1] = np.maximum(pts[:, 1], floor)
    pts[:, 1] -= floor  # base at y = 0
    m = Mesh()
    for a, b, c in f:
        n = np.cross(pts[b] - pts[a], pts[c] - pts[a])
        up = n[1] / (np.linalg.norm(n) + 1e-9)
        k = 0.78 + 0.22 * max(0.0, up) + rng.uniform(-0.05, 0.05)
        m.tri(pts[a], pts[b], pts[c], shade(ROCK, k))
    m.orient_outward(np.array([0, dims[1] * 0.62, 0]))
    # centre the bounding box on the origin (matches the Part stand-in, which is centred)
    allp = np.array(m.tris).reshape(-1, 3)
    return translate(m, -(allp.max(0) + allp.min(0)) / 2)


RIND = (0.38, 0.35, 0.32)  # rough dark outer stone
LINING = (0.30, 0.29, 0.30)
CHALK = (0.93, 0.91, 0.86)  # pale chalcedony cut face


def geode_shell(seed=11, R=1.25, segs=16, rings=5, inner_scale=0.7):
    """Back half of an opened geode: a thick hollow bowl of rough dark stone with a pale flat cut
    face, opening toward -Z, centred on the egg centre. Matches GeodeModel's layout (egg squash
    0.95 x 1.12 x 1, inner wall at 0.7 R, cut face on z = 0), where Parts add the mineral-tinted
    rim band, lining and crystals in front of it."""
    rng = np.random.default_rng(seed)
    wob = rng.uniform(0.95, 1.06, (rings + 1, segs))
    wob[rings, :] = rng.uniform(0.99, 1.02, segs)  # the cut face stays round and flat
    squash = np.array([0.95, 1.12, 1.0])

    def surf(r_scale, k, i):
        th = (math.pi / 2) * k / rings
        ph = i / segs * 2 * math.pi
        r = R * r_scale * (wob[k, i] if r_scale == 1.0 else 1.0)
        p = np.array([math.sin(th) * math.cos(ph), math.sin(th) * math.sin(ph), math.cos(th)])
        q = p * r * squash
        if k == rings:
            q[2] = rng.uniform(-0.015, 0.015) * R  # flat cut face
        return q

    pts_o = [[surf(1.0, k, i) for i in range(segs)] for k in range(rings + 1)]
    pts_i = [[surf(inner_scale, k, i) for i in range(segs)] for k in range(rings + 1)]
    for i in range(segs):  # the inner lip meets the cut face at the same depth as the outer lip
        pts_i[rings][i][2] = pts_o[rings][i][2]
    outer, inner, rim = Mesh(), Mesh(), Mesh()
    for k in range(rings):
        for i in range(segs):
            j = (i + 1) % segs
            col = shade(RIND, 0.85 + rng.uniform(-0.12, 0.12))
            a, b, c, d = pts_o[k][i], pts_o[k][j], pts_o[k + 1][j], pts_o[k + 1][i]
            if k == 0:
                outer.tri(a, c, d, col)
            else:
                outer.quad(a, b, c, d, col)
            ai, bi, ci, di = pts_i[k][i], pts_i[k][j], pts_i[k + 1][j], pts_i[k + 1][i]
            icol = shade(LINING, 0.85 + 0.15 * k / rings)
            if k == 0:
                inner.tri(ai, di, ci, icol)
            else:
                inner.quad(ai, di, ci, bi, icol)
    for i in range(segs):
        j = (i + 1) % segs
        rim.quad(pts_o[rings][i], pts_i[rings][i], pts_i[rings][j], pts_o[rings][j], shade(CHALK, 0.96 + rng.uniform(-0.04, 0.04)))
    outer.orient_outward(np.zeros(3))
    for i, t in enumerate(inner.tris):  # inner surface faces the centre
        if np.dot(np.cross(t[1] - t[0], t[2] - t[0]), t.mean(axis=0)) > 0:
            inner.tris[i] = t[[0, 2, 1]]
    for i, t in enumerate(rim.tris):  # cut face faces the opening (-Z)
        if np.cross(t[1] - t[0], t[2] - t[0])[2] > 0:
            rim.tris[i] = t[[0, 2, 1]]
    m = Mesh()
    for part_ in (outer, inner, rim):
        m.merge(part_)
    return m


def crystal(seed, height, width, sides=6, taper=0.82, tilt=0.0):
    """Hex prism with pointed tip. Base at origin, growing along +Y."""
    rng = np.random.default_rng(seed)
    w = width / 2
    prof = ngon(sides, w, w * (0.9 + 0.1 * rng.random()), rot=rng.uniform(0, 1))
    body = height * 0.68
    col = (0.93, 0.93, 0.96)
    P = np.array(prof)
    base_ring = [np.array([p[0], 0.0, p[1]]) for p in P]
    mid_ring = [np.array([p[0] * taper, body, p[1] * taper]) for p in P]
    tip = np.array([P[:, 0].mean() * 0.3, height, P[:, 1].mean() * 0.3])
    m = Mesh()
    for i in range(sides):
        j = (i + 1) % sides
        k = 0.78 + 0.22 * (i % 3) / 2
        m.quad(base_ring[i], base_ring[j], mid_ring[j], mid_ring[i], shade(col, k))
        m.tri(mid_ring[i], mid_ring[j], tip, shade(col, min(1.0, k + 0.1)))
    m.fan(base_ring, shade(col, 0.7), flip=True)
    m.orient_outward(np.array([0, height * 0.4, 0]))
    return m


DARK = (0.16, 0.17, 0.19)
ORANGE = (0.96, 0.52, 0.12)
STEEL = (0.62, 0.65, 0.7)
DSTEEL = (0.26, 0.28, 0.32)
FACE = (0.84, 0.86, 0.9)


def hammer(steel):
    m = Mesh()
    # grip (origin) + handle along +Y
    m.merge(prism(ngon(8, 0.24), -0.55, 0.55, DARK, DARK, bevel=0.15))
    m.merge(prism(ngon(8, 0.19), 0.45, 3.05, ORANGE, ORANGE, bevel=0.0))
    m.merge(prism(ngon(8, 0.3), 2.5, 2.8, DARK, DARK, bevel=0.2))  # collar
    hy = 3.35
    if steel:
        hx, hh, hd = 1.25, 0.65, 0.65
        head = DSTEEL
    else:
        hx, hh, hd = 1.1, 0.575, 0.575
        head = STEEL
    m.merge(translate(prism(chamfer_rect(hh, hd, hh * 0.35), -hx + 0.12, hx - 0.12, head, head, axis="x", bevel=0.0), (0, hy, 0)))
    for s in (-1, 1):  # striking faces: slightly larger pale plates
        x0, x1 = (s * (hx - 0.12), s * (hx + 0.02))
        lo, hi = min(x0, x1), max(x0, x1)
        m.merge(translate(prism(chamfer_rect(hh * 1.08, hd * 1.08, hh * 0.4), lo, hi, FACE, FACE, axis="x"), (0, hy, 0)))
    if steel:  # reinforcing band
        m.merge(translate(prism(chamfer_rect(hh * 1.1, hd * 1.1, hh * 0.4), -0.2, 0.2, STEEL, STEEL, axis="x"), (0, hy, 0)))
    return m


def along(m, a, b):
    """Map a mesh built along +Y from y=0 to y=1 onto the segment a -> b (length-scaled)."""
    a, b = np.array(a, dtype=float), np.array(b, dtype=float)
    d = b - a
    L = np.linalg.norm(d)
    y = d / L
    x = np.cross(y, [0, 0, 1.0]) if abs(y[2]) < 0.9 else np.cross(y, [1.0, 0, 0])
    x /= np.linalg.norm(x)
    z = np.cross(x, y)
    Rm = np.stack([x, y * L, z], axis=1)  # columns: local x, y (scaled), z
    out = Mesh()
    out.tris = [(Rm @ t.T).T + a for t in m.tris]
    out.cols = list(m.cols)
    return out


def box(cx, cy, cz, sx, sy, sz, col, c=0.0):
    prof = chamfer_rect(sx / 2, sz / 2, c) if c > 0 else [(sx / 2, -sz / 2), (sx / 2, sz / 2), (-sx / 2, sz / 2), (-sx / 2, -sz / 2)]
    return translate(prism(prof, -sy / 2, sy / 2, col, col), (cx, cy, cz))


RUBBER = (0.11, 0.12, 0.13)
SILVER = (0.77, 0.79, 0.82)


def jackhammer():
    """Matches WorldBuilder.toolModel's Part jackhammer: handlebar along X at the origin with two
    rubber grips (x = +-0.7), neck, orange body, air inlet and a hanging hose at the back (+Z),
    dark chuck, silver bit with a flat chisel blade whose edge (the contact point) is at y -2.92."""
    m = Mesh()
    m.merge(prism(ngon(10, 0.08), -0.85, 0.85, DARK, DARK, axis="x"))  # handlebar
    for s in (-1, 1):
        lo, hi = sorted((s * 0.53, s * 0.87))
        m.merge(prism(ngon(10, 0.13), lo, hi, RUBBER, RUBBER, axis="x", bevel=0.2))
        lo, hi = sorted((s * 0.85, s * 0.91))
        m.merge(prism(ngon(10, 0.15), lo, hi, DARK, DARK, axis="x"))
    m.merge(box(0, -0.2, 0, 0.34, 0.36, 0.3, DARK))  # neck
    m.merge(box(0, -0.88, 0, 0.72, 1.05, 0.72, ORANGE, c=0.1))  # body
    m.merge(box(0, -0.38, 0, 0.78, 0.12, 0.78, DARK, c=0.1))  # cap
    m.merge(box(0, -0.75, 0, 0.76, 0.1, 0.76, DARK, c=0.1))  # stripe
    m.merge(box(-0.41, -1.0, 0, 0.14, 0.32, 0.26, DARK))  # exhaust
    m.merge(box(0, -0.62, 0.43, 0.18, 0.18, 0.2, DARK))  # air inlet
    pts = [(0, -0.62, 0.52), (0, -0.78, 0.76), (0.04, -1.12, 0.92), (0.1, -1.55, 0.95), (0.16, -1.95, 0.8), (0.2, -2.25, 0.55)]
    tube = prism(ngon(8, 0.065), 0.0, 1.0, RUBBER, RUBBER)
    for a, b in zip(pts, pts[1:]):
        m.merge(along(tube, a, b))
    m.merge(prism(ngon(10, 0.19), -1.62, -1.38, DSTEEL, DSTEEL, bevel=0.15))  # chuck
    m.merge(prism(ngon(6, 0.065), -2.645, -1.595, SILVER, SILVER))  # bit shaft
    m.merge(box(0, -2.77, 0, 0.17, 0.3, 0.06, shade(SILVER, 1.08)))  # chisel blade
    return m


def build_all():
    assets = {}
    dims = {"A": (1.15, 0.9, 1.0), "B": (1.0, 0.75, 1.1), "C": (0.95, 1.15, 0.95), "D": (1.2, 0.7, 1.05)}
    for i, (k, d) in enumerate(dims.items()):
        assets[f"CT_Rocks_RockShell_{k}"] = rock_shell(100 + i * 17, d, sub=2 if k != "C" else 2)
    assets["CT_Rocks_GeodeShell"] = geode_shell()
    assets["CT_Rocks_Crystal_1"] = crystal(1, 1.6, 0.5, 6, 0.85)
    assets["CT_Rocks_Crystal_2"] = crystal(2, 1.1, 0.36, 6, 0.8)
    assets["CT_Rocks_Crystal_3"] = crystal(3, 0.7, 0.3, 6, 0.75)
    assets["CT_Rocks_Hammer"] = hammer(False)
    assets["CT_Rocks_SteelHammer"] = hammer(True)
    assets["CT_Rocks_Jackhammer"] = jackhammer()
    return assets


# ---------------------------------------------------------------- GLB writer / reader

def write_glb(path, mesh, name):
    pos, nrm, col = mesh.arrays()
    n = len(pos)
    idx = np.arange(n, dtype=np.uint32)
    pb, nb, cb, ib = pos.tobytes(), nrm.tobytes(), col.astype(np.float32).tobytes(), idx.tobytes()
    blob = pb + nb + cb + ib
    views = [
        {"buffer": 0, "byteOffset": 0, "byteLength": len(pb), "target": 34962},
        {"buffer": 0, "byteOffset": len(pb), "byteLength": len(nb), "target": 34962},
        {"buffer": 0, "byteOffset": len(pb) + len(nb), "byteLength": len(cb), "target": 34962},
        {"buffer": 0, "byteOffset": len(pb) + len(nb) + len(cb), "byteLength": len(ib), "target": 34963},
    ]
    acc = [
        {"bufferView": 0, "componentType": 5126, "count": n, "type": "VEC3", "min": pos.min(0).tolist(), "max": pos.max(0).tolist()},
        {"bufferView": 1, "componentType": 5126, "count": n, "type": "VEC3"},
        {"bufferView": 2, "componentType": 5126, "count": n, "type": "VEC4"},
        {"bufferView": 3, "componentType": 5125, "count": n, "type": "SCALAR"},
    ]
    gltf = {
        "asset": {"version": "2.0", "generator": "ct-gen-meshes"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0, "name": name}],
        "meshes": [{"name": name, "primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "COLOR_0": 2}, "indices": 3, "material": 0, "mode": 4}]}],
        "materials": [{"name": "Vertex", "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0.0, "roughnessFactor": 0.9}}],
        "accessors": acc,
        "bufferViews": views,
        "buffers": [{"byteLength": len(blob)}],
    }
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    blob += b"\0" * (-len(blob) % 4)
    total = 12 + 8 + len(js) + 8 + len(blob)
    with open(path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, total))
        f.write(struct.pack("<I4s", len(js), b"JSON") + js)
        f.write(struct.pack("<I4s", len(blob), b"BIN\0") + blob)


def read_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, ver, total = struct.unpack_from("<4sII", data, 0)
    assert magic == b"glTF" and ver == 2 and total == len(data), "bad GLB header"
    jl, jt = struct.unpack_from("<I4s", data, 12)
    assert jt == b"JSON"
    gltf = json.loads(data[20:20 + jl])
    off = 20 + jl
    bl, bt = struct.unpack_from("<I4s", data, off)
    assert bt == b"BIN\0"
    blob = data[off + 8:off + 8 + bl]
    prim = gltf["meshes"][0]["primitives"][0]
    pa = gltf["accessors"][prim["attributes"]["POSITION"]]
    pv = gltf["bufferViews"][pa["bufferView"]]
    pos = np.frombuffer(blob, dtype=np.float32, count=pa["count"] * 3, offset=pv["byteOffset"]).reshape(-1, 3)
    ia = gltf["accessors"][prim["indices"]]
    iv = gltf["bufferViews"][ia["bufferView"]]
    idx = np.frombuffer(blob, dtype=np.uint32, count=ia["count"], offset=iv["byteOffset"])
    assert idx.max() < len(pos)
    return pos[idx].reshape(-1, 3, 3)


def validate(name, tris):
    n = len(tris)
    a = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    area = np.linalg.norm(a, axis=1)
    degenerate = int((area < 1e-9).sum())
    flat = tris.reshape(-1, 3)
    lo, hi = flat.min(0), flat.max(0)
    ok = degenerate == 0 and np.isfinite(flat).all() and (hi - lo).max() < 20
    return {"tris": n, "min": lo.round(3).tolist(), "max": hi.round(3).tolist(), "size": (hi - lo).round(3).tolist(), "degenerate": degenerate, "ok": bool(ok)}


# ---------------------------------------------------------------- contact sheet

def sheet(assets, path):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from mpl_toolkits.mplot3d.art3d import Poly3DCollection

    names = list(assets)
    cols = 5
    rows = math.ceil(len(names) / cols)
    fig = plt.figure(figsize=(cols * 3.2, rows * 3.4), dpi=110)
    fig.patch.set_facecolor("#efe9dc")
    light = np.array([0.4, 0.8, -0.5])
    light /= np.linalg.norm(light)
    for i, name in enumerate(names):
        m = assets[name]
        ax = fig.add_subplot(rows, cols, i + 1, projection="3d")
        tris = np.array(m.tris)
        # plot with x right, y up, view from the front (-Z) slightly above; matplotlib z-up so map (x,z,y)
        T = tris[:, :, [0, 2, 1]]
        faces, fcols = [], []
        for t, c in zip(T, m.cols):
            n = np.cross(t[1] - t[0], t[2] - t[0])
            n = n / (np.linalg.norm(n) + 1e-12)
            nn = np.array([n[0], n[2], n[1]])
            sh = 0.55 + 0.45 * max(0.0, float(np.dot(nn, np.array([light[0], light[2], light[1]]) * -1 * -1)))
            faces.append(t)
            fcols.append(tuple(min(1, c[k] * sh) for k in range(3)))
        pc = Poly3DCollection(faces, facecolors=fcols, edgecolors=(0, 0, 0, 0.25), linewidths=0.3)
        ax.add_collection3d(pc)
        flat = T.reshape(-1, 3)
        mid = (flat.max(0) + flat.min(0)) / 2
        r = (flat.max(0) - flat.min(0)).max() / 2 * 1.02
        ax.set_xlim(mid[0] - r, mid[0] + r)
        ax.set_ylim(mid[1] - r, mid[1] + r)
        ax.set_zlim(mid[2] - r, mid[2] + r)
        ax.set_box_aspect((1, 1, 1))
        ax.view_init(elev=22, azim=-62)  # camera on the -Z (front) side
        ax.set_axis_off()
        ax.set_title(f"{name.replace('CT_Rocks_', '')}\n{len(m.tris)} tris", fontsize=9)
    fig.tight_layout()
    fig.savefig(path, facecolor=fig.get_facecolor())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sheet", default=os.path.join(OUT, "contact_sheet.png"))
    ap.add_argument("--no-sheet", action="store_true")
    args = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    assets = build_all()
    manifest = {}
    bad = []
    for name, mesh in assets.items():
        path = os.path.join(OUT, name + ".glb")
        write_glb(path, mesh, name)
        info = validate(name, read_glb(path))
        manifest[name] = info
        print(f"{name:<24} {info['tris']:>4} tris  size {info['size']}  {'OK' if info['ok'] else 'BAD'}")
        if not info["ok"]:
            bad.append(name)
    # merge: art/meshes/manifest.json also holds the Blender kit models (blender/build.py)
    path = os.path.join(OUT, "manifest.json")
    merged = json.load(open(path)) if os.path.exists(path) else {}
    merged.update(manifest)
    with open(path, "w") as f:
        json.dump(merged, f, indent=1, sort_keys=True)
    if not args.no_sheet:
        try:
            sheet(assets, args.sheet)
            print("contact sheet:", args.sheet)
        except ImportError:
            print("matplotlib missing: no contact sheet")
    if bad:
        raise SystemExit("invalid: " + ", ".join(bad))


if __name__ == "__main__":
    main()
