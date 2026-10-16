"""Sheet 06: Rock pickup & fracture kit.

Every whole rock (Rock_01..12) is one model with three pieces, origin = floor centre (bottom):
  Body       the neutral grey rock (Slate material)
  Hairline   thin dark crack ribbons on the front half (stage B); hidden (Transparency 1) until used
  Wide       wider, branching cracks (stage C); hidden until used
Stage D uses Rock_Split (three chunks, separate pieces that fly apart) and stage E Rock_Rubble.
Grit_Patch is non-interactive ground detail. No colour or glow on any crack (the brief: neutral
until the server resolves the round).
"""

import math
import random

from mathutils import Vector

import ctrkit as K
from ctrkit import register

S06 = "06"
REF = "06_rock_fracture_kit.png"


def _base_flat(pts, lo=0.12):
    zmin = min(p.z for p in pts)
    for p in pts:
        p.z -= zmin
    for p in pts:
        if p.z < lo:
            p.z = 0.0 if p.z < lo * 0.6 else p.z
    return pts


def two_lobes(seed, a, b, off):
    pa = K.rock_points(seed, a, n=20)
    pb = K.rock_points(seed + 1, b, n=18)
    return pa, [p + Vector(off) for p in pb]


def tapered(seed, size, top_scale, n=20, shape="round"):
    pts = K.rock_points(seed, size, n=n, shape=shape)
    h = size[2]
    for p in pts:
        k = 1 - (1 - top_scale) * (p.z / h)
        p.x *= k
        p.y *= k
    return pts


def barrel(seed, size):
    r = random.Random(seed)
    sx, sy, sz = size
    pts = []
    for ring, (z, k) in enumerate(((0.0, 0.78), (0.25, 1.0), (0.75, 1.0), (1.0, 0.75))):
        for i in range(7):
            a = i / 7 * math.tau + ring * 0.45
            pts.append(Vector((math.cos(a) * sx / 2 * k * r.uniform(0.9, 1.04), math.sin(a) * sy / 2 * k * r.uniform(0.9, 1.04),
                               z * sz + r.uniform(-0.04, 0.04) * (0 < z < 1))))
    return _base_flat(pts)


def triangular(seed):
    r = random.Random(seed)
    pts = [Vector(p) for p in [(-1.05, -0.75, 0), (1.05, -0.7, 0), (0.05, 0.95, 0), (-0.9, 0.35, 0.1), (0.95, 0.4, 0.1),
                               (0.05, -0.85, 0.15), (0.0, -0.05, 1.9), (0.12, 0.1, 1.85), (-0.45, -0.35, 0.95),
                               (0.5, -0.32, 0.95), (0.05, 0.5, 0.9)]]
    for p in pts:
        p += Vector((r.uniform(-0.05, 0.05), r.uniform(-0.05, 0.05), 0))
    return _base_flat(pts)


def chunk(seed, size, n=16, shape="cube", top=1.0, flat_bottom=0.2):
    """Chunky faceted boulder: a rounded-cube hull with few, broad facets (pass 2: no spikes, no
    towers; height never more than ~1.1 x the width)."""
    pts = K.rock_points(seed, size, n=n, shape=shape, flat_bottom=flat_bottom)
    h = size[2]
    for p in pts:
        k = 1 - (1 - top) * (p.z / h)
        p.x *= k
        p.y *= k
    return pts


def wedge():
    # sloping top, one high shoulder: a doorstop-like boulder, still wider than tall
    pts = chunk(1, (2.5, 2.1, 1.9), n=15, top=0.85)
    for p in pts:
        p.z *= 1.0 - 0.28 * max(0.0, (p.x + 1.25) / 2.5) * (p.z / 1.9)
    return pts


# name, label, hulls (list of point lists), crack seed
ROCKS = [
    ("Rock_01_Wedge", "Wedge", lambda: [wedge()], (10, 160, 138, 375)),
    ("Rock_02_Oval", "Oval", lambda: [chunk(21, (2.3, 2.1, 1.9), n=20, shape="round")], (140, 165, 272, 375)),
    ("Rock_03_SquatBoulder", "Squat boulder", lambda: [chunk(31, (2.7, 2.3, 1.6), n=18, top=0.8)], (272, 175, 425, 375)),
    ("Rock_04_Oblong", "Oblong", lambda: [chunk(41, (2.9, 1.9, 1.7), n=16, top=0.82)], (425, 165, 552, 375)),
    ("Rock_05_TallLump", "Chunky block", lambda: [chunk(51, (2.0, 1.9, 2.1), n=16, top=0.7)], (552, 135, 662, 375)),
    ("Rock_06_FlatStone", "Flat stone", lambda: [chunk(61, (2.7, 2.3, 1.1), n=16, top=0.85, flat_bottom=0.3)], (662, 185, 802, 375)),
    ("Rock_07_AngularChunk", "Angular chunk", lambda: [chunk(71, (2.2, 2.1, 2.0), n=13, top=0.75)], (800, 160, 908, 375)),
    ("Rock_08_RoundedCube", "Rounded cube", lambda: [chunk(81, (2.1, 2.0, 1.9), n=26)], (912, 170, 1042, 375)),
    ("Rock_09_RiverStone", "Asymmetric river stone", lambda: [chunk(91, (2.4, 2.0, 1.8), n=18, shape="round", top=0.8)], (1042, 160, 1162, 380)),
    ("Rock_10_SmallBarrel", "Small drum rock", lambda: [barrel(101, (1.9, 1.8, 1.6))], (1165, 180, 1275, 380)),
    ("Rock_11_Triangular", "Triangular stone", lambda: [chunk(111, (2.4, 2.2, 1.8), n=11, top=0.7)], (1272, 175, 1402, 380)),
    ("Rock_12_LumpyBoulder", "Lumpy boulder", lambda: list(two_lobes(121, (2.3, 2.1, 1.7), (1.7, 1.6, 1.3), (-0.15, 0.1, 0.9))), (1395, 155, 1525, 375)),
]


def rock_hulls(i):
    """The roughened hull point sets of whole rock i (0-based); every model uses these."""
    return [K.roughen(h, (i + 1) * 1000 + j, count=24, amount=0.07) for j, h in enumerate(ROCKS[i][2]())]


def build_rock(m, hulls, seed, at=(0, 0, 0), stages=("Hairline", "Wide"), preview=False, show=None):
    """Body (+ optional crack pieces). show = which crack piece is visible in the render."""
    body = m.preview_piece("P_Body%d" % seed, "Rock") if preview else m.piece("Body", "Rock")
    for h in hulls:
        body.hull(h, loc=at, bevel=0.02)
    pts = [p for h in hulls for p in h]
    for st in stages:
        crack = m.preview_piece("P_%s%d" % (st, seed), "Crack") if preview else m.piece(
            st, "Crack", note="crack stage %s: hidden (Transparency 1) until this stage" % ("B" if st == "Hairline" else "C"))
        if st == "Hairline":
            K.crack_strips(crack, pts, seed + 5, cracks=2, width=0.025, wander=0.06, loc=at)
        else:
            K.crack_strips(crack, pts, seed + 5, cracks=2, width=0.05, wander=0.1, loc=at)
            K.crack_strips(crack, pts, seed + 9, cracks=2, width=0.045, wander=0.16, loc=at)
        if show is not None and st != show:
            crack.render_hide = True
        elif show is None:
            crack.render_hide = True
    return body


def _reg(name, label, fn, crop, i):
    @register(name, S06, f"Whole rock {i + 1:02d} ({label}): Body + Hairline + Wide crack pieces, origin floor centre.", ref=(REF, crop))
    def _build(m):
        build_rock(m, rock_hulls(i), (i + 1) * 100)
        m.extra["shape"] = i + 1


for _i, (_n, _l, _f, _c) in enumerate(ROCKS):
    _reg(_n, _l, _f, _c, _i)


def split_chunks(hull, gap=0.35):
    """Three convex chunks of a rock hull (two cuts), pushed apart from the centre."""
    c = Vector((0, 0, max(p.z for p in hull) * 0.5))
    planes = [((c, Vector((1, 0.15, 0.35)).normalized())), ((c, Vector((-1, 0.3, 0.25)).normalized()))]
    a = K.clip_hull(hull, [planes[0]])                                  # left of cut 1
    rest = K.clip_hull(hull, [(planes[0][0], -planes[0][1])])
    b = K.clip_hull(rest, [planes[1]])
    d = K.clip_hull(rest, [(planes[1][0], -planes[1][1])])
    out = []
    for chunk in (a, b, d):
        if len(chunk) < 4:
            continue
        cen = sum(chunk, Vector()) / len(chunk)
        push = Vector((cen.x - c.x, cen.y - c.y, 0)).normalized() * gap
        out.append([p + push for p in chunk])
    return out


@register("Rock_Split", S06, "Stage D: the angular chunk split into three chunk pieces (Chunk1..3) slightly apart; tween them outward. Origin floor centre.",
          ref=(REF, (448, 465, 605, 665)))
def rock_split(m):
    hull = rock_hulls(6)[0]
    for i, ch in enumerate(split_chunks(hull)):
        zmin = min(p.z for p in ch)
        m.piece("Chunk%d" % (i + 1), "Rock", note="split chunk; origin of the model is the floor centre").hull(
            [p - Vector((0, 0, zmin * 0.85)) for p in ch], bevel=0.03)


def rubble(piece, seed, at=(0, 0, 0), count=14, spread=1.3):
    r = random.Random(seed)
    at = Vector(at)
    for i in range(count):
        s = r.uniform(0.25, 0.65) if i > 3 else r.uniform(0.6, 0.85)
        a, d = r.uniform(0, math.tau), r.uniform(0, spread) * (0.4 if i <= 3 else 1)
        pts = K.rock_points(r.randrange(1 << 30), (s, s * 0.9, s * 0.8), n=12)
        piece.hull(pts, loc=at + Vector((math.cos(a) * d, math.sin(a) * d, 0)), rot=(0, 0, r.uniform(0, 360)), bevel=0.02)


@register("Rock_Rubble", S06, "Stage E: rubble heap left after crushing (one piece), origin floor centre.", ref=(REF, (600, 505, 770, 665)))
def rock_rubble(m):
    rubble(m.slot("Rock"), 5)


@register("Grit_Patch", S06, "Decorative ground grit (non-interactive, no collision), origin floor centre, about 5 x 3 studs.",
          ref=(REF, (650, 775, 965, 935)))
def grit_patch(m):
    K.scatter_rocks(m.slot("Rock"), 26, (-2.6, -1.5, 2.6, 1.5), (0.12, 0.42), seed=17, flat=0.75)


@register("Rock_FractureSequence", S06, "PREVIEW ONLY: intact / hairline / wider / split / rubble of the angular chunk, laid out like the sheet.",
          ref=(REF, (15, 465, 770, 700)))
def fracture_sequence(m):
    hull = rock_hulls(6)[0]
    build_rock(m, [hull], 700, at=(-6.4, 0, 0), stages=(), preview=True)
    build_rock(m, [hull], 700, at=(-3.6, 0, 0), stages=("Hairline",), preview=True, show="Hairline")
    m.pieces[-1].render_hide = False
    b = build_rock(m, [hull], 700, at=(-0.8, 0, 0), stages=("Wide",), preview=True, show="Wide")
    m.pieces[-1].render_hide = False
    _ = b
    sp = m.preview_piece("P_Split", "Rock")
    for ch in split_chunks(hull):
        zmin = min(p.z for p in ch)
        sp.hull([p - Vector((0, 0, zmin * 0.85)) + Vector((2.3, 0, 0)) for p in ch], bevel=0.03)
    rubble(m.preview_piece("P_Rubble", "Rock"), 5, at=(5.3, 0, 0))
    m.extra["preview_only"] = True


@register("Rock_Lineup", S06, "PREVIEW ONLY: the 12 whole rocks in a row like the sheet.", ref=(REF, (10, 130, 1525, 380)))
def lineup(m):
    x = 0.0
    for i, (_n, _l, fn, _c) in enumerate(ROCKS):
        hulls = rock_hulls(i)
        xs = [p.x for h in hulls for p in h]
        w = max(xs) - min(xs)
        x += w / 2 + 0.25
        body = m.preview_piece("P_Rocks", "Rock")
        for h in hulls:
            body.hull([p - Vector((min(xs) + w / 2, 0, 0)) for p in h], loc=(x, 0, 0), bevel=0.035)
        x += w / 2 + 0.25
    m.extra["preview_only"] = True
