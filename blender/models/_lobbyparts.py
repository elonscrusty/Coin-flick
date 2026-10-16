"""Shared parts for the lobby kits (sheets 01 lobby buildings, 02 courtyard, 03 start terminal).

Not a sheet module (leading underscore: build.py does not import it on its own); lobby.py,
courtyard.py and terminal.py import it. Adds the extra colour slots those kits need to ctrkit.HEX.
"""

import math
import random

from mathutils import Vector

import ctrkit as K

# extra slots for the lobby kits (MeshCatalog takes each piece's colour from the manifest palette)
K.HEX.setdefault("ConcreteDark", "#A39883")   # second stone tone (block rows, paving edges)
K.HEX.setdefault("Leaf", "#5E9E3A")           # shrubs, tree canopy
K.HEX.setdefault("LeafDark", "#3F7A2C")
K.HEX.setdefault("Soil", "#5A4130")
K.HEX.setdefault("Window", "#CFE2E8")         # clear window glass (Glass, transparency 0.6)
K.HEX.setdefault("Red", "#C4402F")            # workshop compressor tank
K.HEX.setdefault("Plaster", "#E2CDA2")        # warm interior wall panels
K.SLOT_MATERIAL.setdefault("ConcreteDark", "Concrete")
K.SLOT_MATERIAL.setdefault("Leaf", "Grass")
K.SLOT_MATERIAL.setdefault("LeafDark", "Grass")
K.SLOT_MATERIAL.setdefault("Soil", "Ground")
K.SLOT_MATERIAL.setdefault("Window", "Glass")


def V(x, y, z):
    return Vector((x, y, z))


def part(m, name, slot, material=None, **kw):
    """A named piece (cached per model). Buildings split each slot into a few named pieces
    (Roof, Posts, Walls ...) so no single MeshPart grows too big."""
    key = ("part", name)
    if key not in m._slots:
        m._slots[key] = m.piece(name, slot, material, **kw)
    return m._slots[key]


# ------------------------------------------------------------------ lights

def lantern(m, at, s=1.0, frame=None, glow=None):
    """Square lantern standing on `at` (bottom centre): base, corner posts, glowing core, pyramid
    cap. Returns the light centre."""
    at = Vector(at)
    fr = frame or m.slot("Frame")
    lamp = glow or m.slot("Lamp")
    w, h = 0.8 * s, 1.15 * s
    fr.box((w * 0.85, w * 0.85, 0.16 * s), loc=at + V(0, 0, 0.08 * s), bevel=0.03 * s)
    lamp.box((w - 0.1 * s, w - 0.1 * s, h - 0.3 * s), loc=at + V(0, 0, 0.15 * s + (h - 0.3 * s) / 2), rot=(180, 0, 0),
             taper=(0.8, 0.8), bevel=0.02)
    for sx in (-1, 1):
        for sy in (-1, 1):
            fr.box_between(at + V(sx * w * 0.4, sy * w * 0.4, 0.1 * s), at + V(sx * w / 2, sy * w / 2, h - 0.08 * s), 0.13 * s, bevel=0.02)
    fr.box((w + 0.26 * s, w + 0.26 * s, 0.15 * s), loc=at + V(0, 0, h - 0.06 * s), bevel=0.03 * s)
    fr.box((w + 0.16 * s, w + 0.16 * s, 0.36 * s), loc=at + V(0, 0, h + 0.19 * s), taper=(0.35, 0.35), bevel=0.02)
    fr.box((0.2 * s, 0.2 * s, 0.18 * s), loc=at + V(0, 0, h + 0.44 * s), bevel=0.02)
    return at + V(0, 0, h * 0.55)


def hanging_lantern(m, top, drop=0.8, s=1.0, frame=None, glow=None):
    """Lantern hanging `drop` below `top` on a short rod + ring. Returns the light centre."""
    top = Vector(top)
    fr = frame or m.slot("Frame")
    fr.box((0.45 * s, 0.45 * s, 0.12 * s), loc=top - V(0, 0, 0.06 * s), bevel=0.02)
    fr.box((0.08 * s, 0.08 * s, drop), loc=top - V(0, 0, drop / 2), bevel=0.01)
    base = top - V(0, 0, drop + 1.6 * s)
    return lantern(m, base, s, frame=fr, glow=glow)


def wall_light(m, at, normal=(0, -1, 0), h=1.4, w=0.45, frame=None, glow=None):
    """Tall amber wall light (housing + glowing pane) centred at `at` on a wall facing `normal`."""
    at, n = Vector(at), Vector(normal).normalized()
    fr = frame or m.slot("Frame")
    lamp = glow or m.slot("Lamp")
    along_x = abs(n.y) > 0.5
    sz = (w, 0.2, h) if along_x else (0.2, w, h)
    fr.box(sz, loc=at + n * 0.1, bevel=0.04)
    lz = (w - 0.16, 0.12, h - 0.3) if along_x else (0.12, w - 0.16, h - 0.3)
    lamp.box(lz, loc=at + n * 0.2, bevel=0.03)
    cap = (w + 0.1, 0.3, 0.12) if along_x else (0.3, w + 0.1, 0.12)
    for dz in (-h / 2, h / 2):
        fr.box(cap, loc=at + n * 0.15 + V(0, 0, dz), bevel=0.03)
    return at + n * 0.4


def light_strip(m, at, normal, h, w=0.3, frame=None, glow=None):
    """Recessed vertical light strip (pillar fronts): dark surround + neon bar."""
    at, n = Vector(at), Vector(normal).normalized()
    fr = frame or m.slot("FrameDark")
    lamp = glow or m.slot("Lamp")
    along_x = abs(n.y) > 0.5
    fr.box((w + 0.16, 0.08, h + 0.16) if along_x else (0.08, w + 0.16, h + 0.16), loc=at + n * 0.03, bevel=0.02)
    lamp.box((w, 0.08, h) if along_x else (0.08, w, h), loc=at + n * 0.07, bevel=0.02)


# ------------------------------------------------------------------ greenery

def shrub(piece, at, size, seed, n=4, piece2=None):
    """Leafy clump: a few faceted blobs (alternating two greens when piece2 is given)."""
    rng = random.Random(seed)
    at = Vector(at)
    for i in range(n):
        s = size * rng.uniform(0.5, 0.8)
        a = rng.uniform(0, math.tau)
        r = size * 0.28 * (0 if i == 0 else 1)
        off = V(math.cos(a) * r, math.sin(a) * r, 0)
        pts = K.rock_points(rng.randrange(1 << 30), (s, s, s * rng.uniform(0.8, 1.0)), n=14, flat_bottom=0.1)
        tgt = piece2 if (piece2 is not None and i % 2) else piece
        tgt.hull(pts, loc=at + off, rot=(0, 0, rng.uniform(0, 360)))


def rosette(piece, at, r, seed, n=7, h=None, piece2=None):
    """Leafy rosette: thin pointed leaves fanning up and out from `at` (planter shrubs)."""
    rng = random.Random(seed)
    at = Vector(at)
    h = h or r * 0.9
    for i in range(n):
        a = i / n * math.tau + rng.uniform(-0.3, 0.3)
        d, side = V(math.cos(a), math.sin(a), 0), V(-math.sin(a), math.cos(a), 0)
        ln = r * rng.uniform(0.75, 1.1)
        up = h * rng.uniform(0.55, 1.0)
        tip = at + d * ln + V(0, 0, up)
        mid = at + d * ln * 0.5 + V(0, 0, up * 0.75)
        w = ln * 0.3
        pts = [at + d * 0.05, mid + side * w, mid - side * w, tip, mid + V(0, 0, 0.07)]
        (piece2 if piece2 is not None and i % 2 else piece).hull(pts)
    # a few upright centre leaves
    for i in range(3):
        a = rng.uniform(0, math.tau)
        d, side = V(math.cos(a), math.sin(a), 0), V(-math.sin(a), math.cos(a), 0)
        tip = at + d * r * 0.25 + V(0, 0, h * 1.15)
        mid = at + d * r * 0.12 + V(0, 0, h * 0.6)
        piece.hull([at, mid + side * r * 0.18, mid - side * r * 0.18, tip, mid + d * 0.06])


def flowers(piece, at, area, count, seed, s=0.16):
    rng = random.Random(seed)
    for _ in range(count):
        x, y = rng.uniform(-area[0] / 2, area[0] / 2), rng.uniform(-area[1] / 2, area[1] / 2)
        piece.box((s, s, s), loc=Vector(at) + V(x, y, rng.uniform(0, 0.15)), rot=(0, 0, rng.uniform(0, 90)), bevel=0.02)


def planter_box(m, at, w, d, h, seed=1, blocks=3, leaf=True, flower=0, base=None):
    """Stone planter: dark plinth, beige block walls, soil, shrubs. `at` = bottom centre."""
    at = Vector(at)
    stone, dark = m.slot("Concrete"), base or m.slot("FrameDark")
    dark.box((w, d, 0.3), loc=at + V(0, 0, 0.15), bevel=0.05)
    wall = 0.38
    bw = (w - 0.04 * (blocks - 1)) / blocks
    for i in range(blocks):
        x = -w / 2 + bw / 2 + i * (bw + 0.04)
        for sy in (-1, 1):
            stone.box((bw, wall, h - 0.3), loc=at + V(x, sy * (d / 2 - wall / 2), 0.3 + (h - 0.3) / 2), bevel=0.06)
    for sx in (-1, 1):
        stone.box((wall, d - 2 * wall - 0.02, h - 0.3), loc=at + V(sx * (w / 2 - wall / 2), 0, 0.3 + (h - 0.3) / 2), bevel=0.06)
    m.slot("Soil").box((w - 2 * wall, d - 2 * wall, 0.2), loc=at + V(0, 0, h - 0.18), bevel=0.02)
    if leaf:
        lp, lp2 = m.slot("Leaf"), m.slot("LeafDark")
        iw, idp = w - 0.7, d - 0.7
        nx = max(1, int(round(iw / 1.2)))
        ny = max(1, int(round(idp / 1.2)))
        r = min(iw / nx, idp / ny) * 0.75
        for i in range(nx):
            for j in range(ny):
                x = -iw / 2 + iw * (i + 0.5) / nx + (0.15 if j % 2 else -0.15)
                y = -idp / 2 + idp * (j + 0.5) / ny
                rosette(lp, at + V(x, y, h - 0.1), r, seed + i * 7 + j * 3, n=7, h=r * 0.95, piece2=lp2)
    if flower:
        flowers(m.slot("Amber"), at + V(0, 0, h + 0.35), (w - 1.0, d - 0.9), flower, seed + 3)


# ------------------------------------------------------------------ stone

def block_course(pieces, x0, x1, y, z0, z1, depth, n, seed=0, gap=0.05, along="x", jitter=0.25):
    """A row of stone blocks between x0..x1 (or y0..y1 when along='y') alternating between pieces."""
    rng = random.Random(seed)
    L = x1 - x0
    cuts = [0.0]
    for i in range(1, n):
        cuts.append(L * i / n + rng.uniform(-jitter, jitter) * L / n)
    cuts.append(L)
    for i in range(n):
        a, b = x0 + cuts[i] + gap / 2, x0 + cuts[i + 1] - gap / 2
        p = pieces[(i + seed) % len(pieces)]
        c = (a + b) / 2
        if along == "x":
            p.box((b - a, depth, z1 - z0), loc=V(c, y, (z0 + z1) / 2), bevel=0.07)
        else:
            p.box((depth, b - a, z1 - z0), loc=V(y, c, (z0 + z1) / 2), bevel=0.07)


def slab_grid(piece, at, w, d, nx, ny, h=0.3, gap=0.06, bevel=0.07):
    """Paving slabs nx x ny on top of `at` (z = bottom of the slabs)."""
    at = Vector(at)
    sw, sd = (w - gap * (nx - 1)) / nx, (d - gap * (ny - 1)) / ny
    for i in range(nx):
        for j in range(ny):
            piece.box((sw, sd, h), loc=at + V(-w / 2 + sw / 2 + i * (sw + gap), -d / 2 + sd / 2 + j * (sd + gap), h / 2), bevel=bevel)


def steps(piece, at, w, n, rise=0.35, run=0.8, edge=None):
    """Front steps going DOWN toward -Y from `at` (top edge, centre). n steps."""
    at = Vector(at)
    for i in range(n):
        top = at.z - i * rise
        y = at.y - run * (i + 0.5)
        piece.box((w + i * 0.0, run + 0.02, top), loc=V(at.x, y, top / 2), bevel=0.06)
        if edge is not None:
            edge.box((w, 0.12, 0.08), loc=V(at.x, at.y - run * i - 0.08, top - 0.03), bevel=0.02)


def octagon(r, rot=22.5):
    return [(math.cos(math.radians(rot + 45 * i)) * r, math.sin(math.radians(rot + 45 * i)) * r) for i in range(8)]


def crystal_cluster(piece, at, s=1.0, seed=3, n=5, normal_y=False):
    """Amber crystal cluster: a tall centre crystal with shorter ones leaning out, all growing from
    one base point. Stands up +Z on `at`; normal_y=True flattens it for a wall emblem facing -Y
    (base 0.45 * s below `at`)."""
    spec = [(0.0, 1.5, 0.0, 0.32)] + [(sx * 0.26, 1.05, sx * 22, 0.26) for sx in (-1, 1)]
    spec += [(sx * 0.46, 0.62, sx * 44, 0.19) for sx in (-1, 1)][: max(0, n - 3)]
    at = Vector(at)
    base = at + (V(0, 0, -0.7 * s) if normal_y else V(0, 0, 0))
    sq = 0.6 if normal_y else 1.0
    for x, h, tilt, r in spec:
        a = math.radians(tilt)
        up = V(math.sin(a), 0, math.cos(a))
        side = V(math.cos(a), 0, -math.sin(a))
        b = base + V(x * s, 0, 0)
        pts = []
        for k in range(6):
            t = math.radians(60 * k)
            off = side * math.cos(t) * r * s + V(0, math.sin(t) * r * s * sq, 0)
            pts.append(b + off)
            pts.append(b + off * 1.0 + up * h * s * 0.62)
        pts.append(b + up * h * s)
        piece.hull(pts)


def gem(piece, at, s=1.0):
    """Faceted gem (hexagonal bipyramid, taller than wide) facing -Y, centred at `at`."""
    at = Vector(at)
    pts = []
    for i in range(6):
        a = math.radians(30 + 60 * i)
        pts.append(at + V(math.cos(a) * 0.55 * s, 0, math.sin(a) * 0.45 * s + 0.05 * s))
    pts += [at + V(0, 0, 1.0 * s), at + V(0, 0, -0.85 * s), at + V(0, -0.4 * s, 0.1 * s), at + V(0, 0.25 * s, 0)]
    piece.hull(pts)
