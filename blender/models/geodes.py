"""Sheet 12: Geode specimens (construction kit), Pass C rebuild (docs/m7/GEODE.md).

A specimen is assembled in game from separate meshes that share ONE frame, like the sheet's
"construction reference": a Geode_Shell[_B|_C] (rough dark outer stone with real side and back volume,
open to the FRONT -Y, plus Lining / Shade / Druse pieces for the cavity), the matching narrow
Geode_Rim[_B|_C], one or more Geode_Cluster_A..F crystal clusters, and Geode_Stand. Shell and rim of one
shape share the specimen origin (bottom centre of the flat underside): place both at the same CFrame.
A cluster's origin is its base centre; put it at the shell's "Cluster" attach point. The whole specimen
sits on the stand's "Geode" attach point.

What changed against the first kit (the "sticker" look): the rim is a narrow lip (12% of the opening
radius, not 25%), the cavity is deeper with a dark shade band just inside the rim, the lining is one dark
tone, the druzy points are a mineral-coloured piece (Druse) instead of dark flecks, crystals are fewer, bigger
and have clear planes, and the underside is cut flat so the shell rests on its stand. Three shell
silhouettes (A rounded, B wide, C tall) share the builder.

Colour per mineral in game (MeshPart.Color): Crystal1..3 pieces use slot Crystal (alternate crystals, so
the game can step their brightness and read separate planes), Druse uses Crystal at a dimmer tone,
Lining and Shade use dark shades of the crystal colour, Shell/Rim stay rock and chalk.
"""

import math
import random

import bmesh
from mathutils import Matrix, Vector

import ctrkit as K
from ctrkit import register

S12 = "12"
REF = "12_geode_specimens.png"

K.HEX.update({
    "GeodeShell": "#675E54",   # rough grey-brown outer stone
    "Rim": "#CDBFAE",          # narrow mineral rim: warm chalk, not white
    "Crystal": "#9B5DE5",      # default amethyst; recoloured per mineral
    "Lining": "#3C2468",       # cavity wall, a dark shade of the crystal colour
    "Shade": "#1C1230",        # shadow band just inside the rim
    "GlassClear": "#D6E4EA",   # display cabinet glass (transparent in game)
})
K.SLOT_MATERIAL.update({"GeodeShell": "Slate", "Rim": "SmoothPlastic", "Crystal": "SmoothPlastic",
                        "Lining": "SmoothPlastic", "Shade": "SmoothPlastic", "GlassClear": "SmoothPlastic"})

# Mineral colours used ONLY for the preview renders (the game maps its own Config.Minerals colours).
SAFE_SEEDS = (12, 22, 27, 12, 22, 27)   # compat with gallery.py: seed value picks shell shape A/B/C (12, 22, 27)

PREVIEW_MINERALS = {
    "Amethyst": ("#9A5CF0", "#3C2468"),
    "RoseQuartz": ("#F589AE", "#5A2540"),
    "Citrine": ("#F8AE2E", "#5A3A10"),
    "Emerald": ("#2DB565", "#0F4228"),
    "SkyBlue": ("#4A98F5", "#173C6E"),
    "DeepRed": ("#DA2F40", "#561018"),
    "IcyCyan": ("#66D6F0", "#1E5A6C"),
    "Quartz": ("#E8EAF2", "#5A5C66"),
    "Smoky": ("#73604F", "#2A211A"),
}

# Shell silhouettes: outer half sizes (studs), opening angle from the front axis, outline lumps, wall noise.
SHAPES = {
    "A": dict(seed=12, g=(1.25, 1.12, 1.18), a0=62, lump=[0.6, 1.4, 0.3], noise=0.10, stand=1.0),
    "B": dict(seed=22, g=(1.5, 1.05, 1.0), a0=66, lump=[2.1, 0.5, 4.0], noise=0.11, stand=1.2),
    "C": dict(seed=27, g=(1.1, 1.2, 1.42), a0=58, lump=[3.3, 2.2, 1.1], noise=0.10, stand=0.95),
}
SUFFIX = {"A": "", "B": "_B", "C": "_C"}
M, N = 18, 7               # azimuth segments around the opening, rings from the opening to the back pole
F_SHELL_IN = 0.80          # shell inner surface (hidden behind the lining)
F_LINING = 0.745           # cavity wall seen through the opening
FLAT = 0.10                # fraction of GZ cut off the underside (flat bed that rests on the stand)
RIM_IN, RIM_OUT = 0.86, 0.985   # narrow mineral rim

GX, GY, GZ = SHAPES["A"]["g"]
A0 = math.radians(SHAPES["A"]["a0"])
NOISE = SHAPES["A"]["noise"]
CENTER = Vector((0, 0, GZ * (1 - FLAT)))
CLUSTER_AT = (0.0, 0.0, 0.0)
LUMP = [0.6, 1.4, 0.3]


def _set_shape(key):
    """Select shell A / B / C: sizes, opening angle, lumps and the cluster base point inside the cavity."""
    global GX, GY, GZ, A0, CENTER, CLUSTER_AT, NOISE
    sh = SHAPES[key]
    GX, GY, GZ = sh["g"]
    A0 = math.radians(sh["a0"])
    NOISE = sh["noise"]
    CENTER = Vector((0, 0, GZ * (1 - FLAT)))
    CLUSTER_AT = (0.0, 0.0, CENTER.z - GZ * 0.64)
    LUMP[:] = sh["lump"]
    return sh


_set_shape("A")


def _noise_grid(seed):
    rng = random.Random(seed)
    grid = [[rng.uniform(-NOISE, NOISE) for _ in range(M)] for _ in range(N)]
    pole = rng.uniform(-0.05, 0.05)
    return grid, pole


def _lump(b):
    """Low-frequency outline lumps around the opening (the sheet's heart-ish blob silhouettes)."""
    return 0.09 * math.sin(2 * b + LUMP[0]) + 0.07 * math.cos(3 * b + LUMP[1]) + 0.04 * math.sin(5 * b + LUMP[2])


def _pt(a, b, f, n, clamp=False):
    d = Vector((math.sin(a) * math.cos(b), -math.cos(a), math.sin(a) * math.sin(b)))
    k = f * (1 + n + _lump(b) * min(1.0, math.sin(a) * 1.3))
    p = CENTER + Vector((d.x * GX * k, d.y * GY * k, d.z * GZ * k))
    if clamp:
        p.z = max(p.z, 0.0)   # flat underside: the specimen rests on its stand
    return p


def _surface_solid(seed, f_out, f_in, clamp_out=False, rings=None):
    """Closed solid between two lumpy shell surfaces (outer factor f_out, inner f_in), open at the
    front: the two surfaces join with a lip strip around the opening. `rings` limits the solid to the
    first rings (a band around the opening) and closes it with a strip instead of the back pole."""
    nr = N if rings is None else rings
    grid, pole = _noise_grid(seed)
    bm = bmesh.new()
    sides = {}
    for side, f in (("o", f_out), ("i", f_in)):
        rr = []
        for i in range(nr):
            a = A0 + (math.pi - A0) * i / N
            rr.append([bm.verts.new(_pt(a, 2 * math.pi * j / M + (i % 2) * math.pi / M, f, grid[i][j],
                                        clamp_out and side == "o")) for j in range(M)])
        pv = bm.verts.new(CENTER + Vector((0, GY * f * (1 + pole), 0))) if rings is None else None
        sides[side] = (rr, pv)
    for side in ("o", "i"):
        rr, pv = sides[side]
        for i in range(nr - 1):
            r0, r1 = rr[i], rr[i + 1]
            for j in range(M):
                j1 = (j + 1) % M
                if i % 2 == 0:
                    bm.faces.new((r0[j], r0[j1], r1[j]))
                    bm.faces.new((r0[j1], r1[j1], r1[j]))
                else:
                    bm.faces.new((r0[j], r1[j1], r1[j]))
                    bm.faces.new((r0[j], r0[j1], r1[j1]))
        if rings is None:
            last = rr[nr - 1]
            for j in range(M):
                bm.faces.new((last[j], last[(j + 1) % M], pv))
    o0, i0 = sides["o"][0][0], sides["i"][0][0]
    for j in range(M):
        j1 = (j + 1) % M
        bm.faces.new((o0[j], o0[j1], i0[j1], i0[j]))
    if rings is not None:
        ol, il = sides["o"][0][nr - 1], sides["i"][0][nr - 1]
        for j in range(M):
            j1 = (j + 1) % M
            bm.faces.new((ol[j], il[j], il[j1], ol[j1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def shell_into(shell, lining, shade, druse, seed=12):
    """Shell (rough outer stone), Lining (cavity wall), Shade (band inside the rim), Druse (wall points)."""
    shell.add_bm(_surface_solid(seed, 1.0, F_SHELL_IN, clamp_out=True))
    lining.add_bm(_surface_solid(seed, F_SHELL_IN + 0.01, F_LINING))
    shade.add_bm(_surface_solid(seed, F_LINING - 0.004, F_LINING - 0.03, rings=3))
    # druzy: a few mineral points on the cavity wall, pointing into the cavity (bigger and fewer than before)
    grid, _ = _noise_grid(seed)
    rng = random.Random(seed * 3 + 5)
    for i in range(2, N):
        for j in range(M):
            if rng.random() < 0.62:
                continue
            a = A0 + (math.pi - A0) * (i - 0.5 + rng.uniform(-0.3, 0.3)) / N
            b = 2 * math.pi * (j + rng.uniform(0, 1)) / M
            p = _pt(a, b, F_LINING + 0.02, grid[i][j])
            d = (CENTER - p).normalized()
            druse.add_bm(crystal_bm(p, d, rng.uniform(0.06, 0.1), rng.uniform(0.2, 0.34), tip=1.9, spin=rng.uniform(0, 1)))


def rim_into(rim, seed=12):
    """Narrow mineral rim: a faceted lip lofted around the opening edge. Its width and height wander."""
    grid, _ = _noise_grid(seed)
    rng = random.Random(seed * 7 + 1)
    bm = bmesh.new()
    loops = []
    R = 2 * M
    for j in range(R):
        b = math.pi * j / M
        jj = (j // 2) % M
        n = grid[0][jj] if j % 2 == 0 else (grid[0][jj] + grid[0][(jj + 1) % M]) / 2
        w_in = RIM_IN + rng.uniform(-0.02, 0.025)
        w_out = RIM_OUT + rng.uniform(-0.01, 0.01)
        crown = (w_in + w_out) / 2
        rise = rng.uniform(0.0, 0.05)
        sec = [
            _pt(A0, b, w_in, n) + Vector((0, 0.16, 0)),                    # inner back (in the cavity)
            _pt(A0, b, w_in, n) + Vector((0, -0.05 - rise, 0)),            # inner front edge
            _pt(A0, b, crown, n) + Vector((0, -0.11 - rise, 0)),           # crown
            _pt(A0, b, w_out, n) + Vector((0, -0.04, 0)),                  # outer front edge
            _pt(A0, b, w_out, n) + Vector((0, 0.14, 0)),                   # outer back (inside the shell)
        ]
        loops.append([bm.verts.new(p) for p in sec])
    S = 5
    for j in range(R):
        a, c = loops[j], loops[(j + 1) % R]
        for k in range(S):
            k1 = (k + 1) % S
            bm.faces.new((a[k], a[k1], c[k1], c[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    rim.add_bm(bm)


# ------------------------------------------------------------------ crystals

def crystal_bm(base, direction, r, h, sides=6, tip=1.6, taper=0.92, spin=0.0):
    """One faceted crystal: hexagonal prism with a pointed pyramid tip, from base along direction."""
    bm = bmesh.new()
    tip_h = min(r * tip, h * 0.55)
    body = h - tip_h
    lo = [bm.verts.new((math.cos(spin + k * math.tau / sides) * r, math.sin(spin + k * math.tau / sides) * r, 0))
          for k in range(sides)]
    hi = [bm.verts.new((math.cos(spin + k * math.tau / sides) * r * taper, math.sin(spin + k * math.tau / sides) * r * taper, body))
          for k in range(sides)]
    apex = bm.verts.new((0, 0, h))
    bm.faces.new(list(reversed(lo)))
    for k in range(sides):
        k1 = (k + 1) % sides
        bm.faces.new((lo[k], lo[k1], hi[k1], hi[k]))
        bm.faces.new((hi[k], hi[k1], apex))
    d = Vector(direction).normalized()
    q = d.to_track_quat("Z", "Y" if abs(d.z) < 0.9 else "X")
    bm.transform(Matrix.Translation(Vector(base)) @ q.to_matrix().to_4x4())
    return bm


# (x, y, height, radius, extra lean) per crystal. Fewer and larger than the first kit: each crystal shows
# several clear planes. The lean outward grows with distance from the centre.
CLUSTERS = {
    "A": ("Cathedral: one tall central point, two flanking points, a few shorter ones in front.", [
        (0.0, 0.05, 1.2, 0.27, 0), (-0.32, 0.1, 0.92, 0.22, 0), (0.34, 0.08, 0.98, 0.23, 0),
        (-0.62, 0.0, 0.62, 0.19, 0), (0.64, 0.0, 0.66, 0.19, 0), (-0.14, -0.26, 0.52, 0.17, 0),
        (0.22, -0.28, 0.46, 0.16, 0), (0.0, -0.4, 0.3, 0.13, 0),
    ]),
    "B": ("Fan: medium points spread wide in a splayed fan.", [
        (0.0, 0.05, 0.92, 0.23, 0), (-0.3, 0.05, 0.84, 0.21, -8), (0.32, 0.05, 0.86, 0.21, 8),
        (-0.6, 0.02, 0.7, 0.19, -16), (0.62, 0.0, 0.72, 0.19, 16),
        (-0.12, -0.3, 0.44, 0.16, 0), (0.18, -0.32, 0.42, 0.16, 0),
    ]),
    "C": ("Low bed: a bed of short wide points.", [
        (x * 0.3 + (0.12 if row % 2 else 0), -0.3 + row * 0.26, 0.34 + 0.2 * random.Random(row * 13 + i).random()
         + (0.08 if row == 2 else 0), 0.17 + 0.03 * random.Random(i * 7 + row).random(), 0)
        for row in range(3) for i, x in enumerate(range(-2, 3)) if not (row == 0 and abs(x) == 2)
    ]),
    "D": ("Twin spire: two tall points side by side with shorter ones around.", [
        (-0.2, 0.08, 1.22, 0.26, -4), (0.22, 0.06, 1.12, 0.25, 5), (-0.56, 0.02, 0.72, 0.2, 0),
        (0.58, 0.0, 0.68, 0.2, 0), (0.0, -0.24, 0.52, 0.17, 0), (-0.32, -0.32, 0.38, 0.14, 0),
        (0.34, -0.32, 0.36, 0.14, 0),
    ]),
    "E": ("Spray: heights step down from a tall leaning point on one side.", [
        (-0.42, 0.06, 1.2, 0.26, 10), (-0.1, 0.05, 0.98, 0.23, 6), (0.2, 0.04, 0.8, 0.21, 2),
        (0.5, 0.02, 0.6, 0.18, 0), (-0.7, 0.0, 0.66, 0.19, 0),
        (-0.3, -0.28, 0.5, 0.16, 0), (0.1, -0.3, 0.4, 0.15, 0),
    ]),
    "F": ("Bloom: a ring of medium points leaning out around a low centre, for hollow specimens.", [
        (-0.58, 0.04, 0.78, 0.2, -20), (-0.28, 0.1, 0.88, 0.21, -10), (0.0, 0.12, 0.7, 0.2, 0),
        (0.3, 0.1, 0.9, 0.21, 10), (0.6, 0.04, 0.8, 0.2, 20),
        (-0.34, -0.26, 0.4, 0.16, 0), (0.0, -0.3, 0.34, 0.15, 0), (0.36, -0.26, 0.42, 0.16, 0),
    ]),
}


def cluster_into(pieces, key, seed=3):
    """Fill pieces[0..2] (Crystal1..3) with cluster `key`; origin = base centre, front = -Y."""
    rng = random.Random(seed + ord(key))
    for i, (x, y, h, r, lean) in enumerate(CLUSTERS[key][1]):
        out = Vector((x * 0.62, y * 0.6, 0))
        tilt = math.radians(lean) * 0.7 + x * 0.42    # splay outward (roll about Y)
        fwd = math.radians(9) + (-y) * 0.15           # lean toward the viewer
        d = Vector((math.sin(tilt), -math.sin(fwd), 1.0)).normalized()
        d += Vector((rng.uniform(-0.05, 0.05), rng.uniform(-0.05, 0.05), 0))
        pieces[i % 3].add_bm(crystal_bm(out, d, r, h, tip=rng.uniform(1.4, 1.9), spin=rng.uniform(0, 1)))
    # back row: a few medium points that fill the back of the cavity behind the main cluster
    tall = max(c[2] for c in CLUSTERS[key][1])
    for i, x in enumerate((-0.5, -0.16, 0.18, 0.5)):
        h = tall * rng.uniform(0.5, 0.7) * (1 - abs(x) * 0.5)
        d = Vector((x * 0.5 + rng.uniform(-0.1, 0.1), -0.08, 1.0)).normalized()
        pieces[(i + 1) % 3].add_bm(crystal_bm((x * 0.7, 0.22, 0.14), d, rng.uniform(0.2, 0.25), h, tip=rng.uniform(1.4, 1.8), spin=rng.uniform(0, 1)))


def fit_report(shape_key, cluster_key, scale=1.0):
    """Worst overshoot (studs) of any crystal tip outside the cavity ellipsoid of a shell shape (0 = inside)."""
    _set_shape(shape_key)
    rng = random.Random(3 + ord(cluster_key))
    worst = 0.0
    items = []
    for (x, y, h, r, lean) in CLUSTERS[cluster_key][1]:
        tilt = math.radians(lean) * 0.7 + x * 0.42
        fwd = math.radians(9) + (-y) * 0.15
        d = Vector((math.sin(tilt), -math.sin(fwd), 1.0)).normalized()
        items.append((Vector((x * 0.62, y * 0.6, 0)), d, h))
    for p0, d, h in items:
        tip = (p0 + d * h) * scale + Vector(CLUSTER_AT)
        e = Vector((tip.x / (GX * F_LINING), tip.y / (GY * F_LINING), (tip.z - CENTER.z) / (GZ * F_LINING)))
        over = (e.length - 1.0) if tip.y > -GY * math.cos(A0) * 0.7 else 0.0
        worst = max(worst, over)
    return worst


# ------------------------------------------------------------------ stand (sheet 12 wooden display stand)

PLANK_TOP = 0.32
STAND_TOP = 0.34
REST = PLANK_TOP - 0.015     # specimens rest on the planks, sunk a hair so there is never a gap


def stand_into(wood, dark, brass, frame, bolt, loc=(0, 0, 0)):
    o = Vector(loc)
    W, D = 2.9, 1.9
    for sy in (-1, 1):   # two planks with a seam
        wood.box((W - 0.1, D / 2 - 0.03, 0.3), loc=o + Vector((0, sy * D / 4, 0.17)), bevel=0.05)
    dark.box((W - 0.2, D - 0.2, 0.06), loc=o + Vector((0, 0, 0.04)), bevel=0.02)
    for sx in (-1, 1):
        for sy in (-1, 1):
            brass.box((0.44, 0.44, 0.38), loc=o + Vector((sx * (W / 2 - 0.17), sy * (D / 2 - 0.17), 0.19)), bevel=0.05)
            px, py = sx * (W / 2 - 0.3), sy * (D / 2 - 0.5)
            frame.box((0.2, 0.2, 0.62), loc=o + Vector((px, py, STAND_TOP + 0.28)), bevel=0.04)
            brass.box((0.3, 0.3, 0.12), loc=o + Vector((px, py, STAND_TOP + 0.6)), bevel=0.03)
            bolt.bolt(o + Vector((sx * (W / 2 + 0.05), sy * (D / 2 - 0.17), 0.2)), normal=(sx, 0, 0), r=0.06)
        # side rail linking the front and back post
        frame.box((0.16, D - 0.9, 0.14), loc=o + Vector((sx * (W / 2 - 0.3), 0, STAND_TOP + 0.36)), bevel=0.03)


# ------------------------------------------------------------------ whole specimen (previews)

def specimen_into(get, at=(0, 0, 0), scale=1.0, mineral="Amethyst", cluster="A", stand=True, shape="A", rot=0, tilt=0, seed=None):
    """Assemble shell + rim + cluster (+ stand) into preview pieces. get(name, slot) returns a piece."""
    if seed is not None:   # gallery.py passes a seed: 12 / 22 / 27 pick shell A / B / C
        shape = {12: "A", 22: "B", 27: "C"}.get(seed, "A")
    sh = _set_shape(shape)
    cry, lin = PREVIEW_MINERALS[mineral]
    T = (Matrix.Translation(Vector(at)) @ Matrix.Rotation(math.radians(rot), 4, "Z")
         @ Matrix.Rotation(math.radians(-tilt), 4, "X") @ Matrix.Scale(scale, 4))
    lift = Matrix.Translation((0, 0, REST)) if stand else Matrix.Identity(4)
    tmp = {k: K.Piece(k, "x") for k in ("shell", "lining", "shade", "druse", "rim", "c1", "c2", "c3")}
    shell_into(tmp["shell"], tmp["lining"], tmp["shade"], tmp["druse"], sh["seed"])
    rim_into(tmp["rim"], sh["seed"])
    cluster_into([tmp["c1"], tmp["c2"], tmp["c3"]], cluster)
    get("PrevShell", "GeodeShell").add_bm(tmp["shell"].bm, T @ lift)
    get("PrevLining_" + mineral, lin).add_bm(tmp["lining"].bm, T @ lift)
    get("PrevShade", "Shade").add_bm(tmp["shade"].bm, T @ lift)
    get("PrevDruse_" + mineral, cry).add_bm(tmp["druse"].bm, T @ lift)
    get("PrevRim", "Rim").add_bm(tmp["rim"].bm, T @ lift)
    cm = T @ lift @ Matrix.Translation(CLUSTER_AT)
    for k in ("c1", "c2", "c3"):
        get("PrevCrystal_" + mineral, cry).add_bm(tmp[k].bm, cm)
    if stand:
        st = {s: K.Piece(s, s) for s in ("Wood", "WoodDark", "Brass", "FrameDark", "SteelLight")}
        stand_into(st["Wood"], st["WoodDark"], st["Brass"], st["FrameDark"], st["SteelLight"])
        S = Matrix.Scale(sh["stand"], 4)
        for s, p in st.items():
            get("PrevStand" + s, s).add_bm(p.bm, T @ S)


def _prev(m):
    return lambda name, slot: m.preview_piece(name, slot)


# ------------------------------------------------------------------ registered models

def _shell_model(key):
    def build(m):
        sh = _set_shape(key)
        shell_into(m.piece("Shell", "GeodeShell"), m.piece("Lining", "Lining", note="cavity wall; dark shade of the mineral"),
                   m.piece("Shade", "Shade", note="shadow band inside the rim; very dark shade of the mineral"),
                   m.piece("Druse", "Crystal", note="wall points; recolour per mineral, a little dimmer than the clusters"), sh["seed"])
        m.attach["Cluster"] = CLUSTER_AT
        m.attach["Rim"] = (0, 0, 0)
        m.attach["Center"] = tuple(CENTER)
        m.extra["origin"] = "bottom centre of the flat underside; the matching Geode_Rim uses the same origin"
        m.extra["stand_scale"] = sh["stand"]
        m.extra["shape"] = key
        _set_shape("A")
    return build


def _rim_model(key):
    def build(m):
        sh = _set_shape(key)
        rim_into(m.piece("Rim", "Rim"), sh["seed"])
        m.extra["origin"] = "matching Geode_Shell origin (bottom centre of the flat underside)"
        _set_shape("A")
    return build


for _k in "ABC":
    _s = SUFFIX[_k]
    register("Geode_Shell" + _s, S12, "Hollow geode shell %s, open to the front (-Y), flat underside. Pieces: Shell (rough stone), Lining + Shade (cavity), Druse (wall points). Origin bottom centre; shares its frame with Geode_Rim%s." % (_k, _s),
             ref=(REF, (780, 735, 975, 975)))(_shell_model(_k))
    register("Geode_Rim" + _s, S12, "Narrow mineral rim that follows the opening of Geode_Shell%s. Same origin (place at the same CFrame)." % _s,
             ref=(REF, (975, 735, 1135, 975)))(_rim_model(_k))


def _cluster_model(key):
    def build(m):
        cluster_into([m.piece("Crystal%d" % (i + 1), "Crystal", note="recolour per mineral") for i in range(3)], key)
        m.extra["origin"] = "cluster base centre; place at Geode_Shell attach Cluster"
    return build


for _k in "ABCDEF":
    register("Geode_Cluster_" + _k, S12, "Crystal cluster %s. %s Pieces Crystal1..3 (slot Crystal) for per-mineral or stepped-brightness paint; origin base centre." % (_k, CLUSTERS[_k][0]),
             ref=(REF, (1135, 760, 1290, 975)))(_cluster_model(_k))


@register("Geode_Stand", S12, "Wooden specimen display stand: plank base, brass corner caps, dark cradle posts. Origin floor centre; the specimen rests on the planks at attach Geode.",
          ref=(REF, (335, 230, 610, 340)))
def geode_stand(m):
    stand_into(m.slot("Wood"), m.slot("WoodDark"), m.slot("Brass"), m.slot("FrameDark"), m.slot("SteelLight"))
    m.attach["Geode"] = (0, 0, REST)


@register("Geode_Assembled", S12, "PREVIEW ONLY: construction reference (shell, rim, cluster exploded) and the assembled amethyst specimen.",
          ref=(REF, (780, 700, 1510, 1000)))
def geode_assembled(m):
    get = _prev(m)
    sh = _set_shape("A")
    tmp = {k: K.Piece(k, "x") for k in ("shell", "lining", "shade", "druse", "rim", "c1", "c2", "c3")}
    shell_into(tmp["shell"], tmp["lining"], tmp["shade"], tmp["druse"], sh["seed"])
    rim_into(tmp["rim"], sh["seed"])
    cluster_into([tmp["c1"], tmp["c2"], tmp["c3"]], "A")
    cry, lin = PREVIEW_MINERALS["Amethyst"]
    get("ExShell", "GeodeShell").add_bm(tmp["shell"].bm, Matrix.Translation((-9, 0, 0)))
    get("ExLining", lin).add_bm(tmp["lining"].bm, Matrix.Translation((-9, 0, 0)))
    get("ExShade", "Shade").add_bm(tmp["shade"].bm, Matrix.Translation((-9, 0, 0)))
    get("ExDruse", cry).add_bm(tmp["druse"].bm, Matrix.Translation((-9, 0, 0)))
    get("ExRim", "Rim").add_bm(tmp["rim"].bm, Matrix.Translation((-6, 0, 0)))
    for k in ("c1", "c2", "c3"):
        get("ExCrystal", cry).add_bm(tmp[k].bm, Matrix.Translation((-3, 0, 0)))
    specimen_into(get, at=(0.6, 0, 0), mineral="Amethyst", cluster="A")
    m.extra["preview_only"] = True


@register("Geode_Lineup", S12, "PREVIEW ONLY: shells A/B/C with the six clusters in specimens painted as different minerals (game colours come from Config).",
          ref=(REF, (10, 40, 1525, 690)))
def geode_lineup(m):
    get = _prev(m)
    plan = (("A", "A", "RoseQuartz"), ("B", "B", "Amethyst"), ("C", "D", "Citrine"),
            ("A", "E", "Emerald"), ("B", "F", "SkyBlue"), ("C", "C", "DeepRed"))
    for i, (shape, key, mineral) in enumerate(plan):
        specimen_into(get, at=(-8 + i * 3.2, 0, 0), mineral=mineral, cluster=key, shape=shape)
    m.extra["preview_only"] = True


@register("Geode_Specimen", S12, "PREVIEW ONLY: one assembled specimen (amethyst, cluster A) on its stand, for close comparison with the sheet.",
          ref=(REF, (335, 50, 610, 355)))
def geode_specimen(m):
    specimen_into(_prev(m), mineral="Amethyst", cluster="A")
    m.extra["preview_only"] = True
