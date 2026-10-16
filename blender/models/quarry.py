"""Sheet 05: Quarry environment kit.

Cliffs are broad, layered masses of chunky faceted rock columns (back rows tall, front rows low so the
silhouette steps down toward the arena), light top caps, a few moss tufts and front boulders. Every cliff
records simple box colliders in the manifest (`colliders`: one box per run of similar-height columns), so
the game never has to collide against the faceted mesh. Structures (walls, fence, gate, nook, crane, lamp)
use the station palette: dark steel, honey wood, amber trims, warm lamps.
Blender axes as everywhere (Roblox = (-x, z, y)); the front faces -Y, i.e. toward the arena.
"""

import math
import random

from mathutils import Vector

import ctrkit as K
from ctrkit import register

S05 = "05"
REF = "05_quarry_environment_kit.png"


# ------------------------------------------------------------------ cliffs

def _column(piece, cap, x, y, w, d, h, rng):
    """Faceted rock column: chamfered octagon footprint, waist and slightly inset, tilted top; a light cap
    hull sits on the top so the layered ledges read from the gameplay camera."""
    rings = []
    for zz, inset in ((0.0, 0.0), (h * rng.uniform(0.4, 0.62), rng.uniform(-0.03, 0.06)), (h, rng.uniform(0.06, 0.15))):
        ch = min(w, d) * rng.uniform(0.16, 0.3)
        hw, hd = w / 2 * (1 - inset), d / 2 * (1 - inset)
        ring = [(hw - ch, -hd), (hw, -hd + ch), (hw, hd - ch), (hw - ch, hd),
                (-hw + ch, hd), (-hw, hd - ch), (-hw, -hd + ch), (-hw + ch, -hd)]
        jz = 0.0 if zz == 0 else min(0.35, h * 0.04)
        rings.append([Vector((x + px + rng.uniform(-0.12, 0.12), y + py + rng.uniform(-0.12, 0.12),
                              zz + rng.uniform(-jz, jz))) for px, py in ring])
    piece.hull([p for r in rings for p in r])
    top = rings[-1]
    c = sum(top, Vector()) / len(top)
    cp = []
    for p in top:
        q = c + (p - c) * 0.9
        cp.append(Vector((q.x, q.y, p.z - 0.25)))
        cp.append(Vector((q.x, q.y, p.z + 0.22)))
    cap.hull(cp)
    return max(p.z for p in top) + 0.22


def _moss(piece, at, s, rng):
    for k in range(3):   # a clump of 3 lumpy blobs
        c = Vector((rng.uniform(-0.5, 0.5) * s, rng.uniform(-0.4, 0.4) * s, 0))
        r = s * rng.uniform(0.45, 0.65)
        piece.hull([Vector((math.cos(a) * r, math.sin(a) * r, 0)) for a in [i / 6 * math.tau for i in range(6)]] +
                   [Vector((math.cos(a) * r * 0.6, math.sin(a) * r * 0.6, r * 0.7)) for a in [i / 5 * math.tau + 0.3 for i in range(5)]],
                   loc=at + c)
    return
    pts = [Vector((math.cos(a) * s * rng.uniform(0.6, 1.0), math.sin(a) * s * rng.uniform(0.5, 0.9), rng.uniform(0, s * 0.35)))
           for a in [i / 7 * math.tau for i in range(7)]]
    pts += [Vector((0, 0, s * 0.5))]
    piece.hull(pts, loc=at)


def cliff_rows(m, seed, rows, boulders=3, moss=5):
    """rows: list of (a, b, depth, hfunc, kind). a, b = (x, y) ends of an axis-aligned line; columns
    (depth `depth` across the line) are packed along it; hfunc(t) gives the target height at t in [0, 1].
    Returns nothing; writes pieces + colliders into m."""
    rng = random.Random(seed)
    rock, dark, cap, moss_p = m.slot("Cliff"), m.slot("CliffDark"), m.slot("RockLight"), m.slot("Moss")
    colliders = []
    tops = []
    for (a, b, depth, hfunc) in rows:
        a, b = Vector((*a, 0)), Vector((*b, 0))
        along_x = abs(b.x - a.x) >= abs(b.y - a.y)
        L = (b - a).length
        u = (b - a).normalized()
        s = 0.0
        cols = []
        while s < L - 0.6:
            w = min(max(3.6, L * rng.uniform(0.2, 0.32)) * rng.uniform(0.9, 1.15), 7.5)
            if L - s - w < 2.0:
                w = L - s + 0.3
            t = (s + w / 2) / L
            h = hfunc(t) * rng.uniform(0.86, 1.07)
            dd = depth * rng.uniform(0.85, 1.05)
            cen = a + u * (s + w / 2)
            off = rng.uniform(-0.25, 0.25)
            cx, cy = (cen.x, cen.y + off) if along_x else (cen.x + off, cen.y)
            cw, cd = (w, dd) if along_x else (dd, w)
            if h > 1.2:
                piece = dark if rng.random() < 0.25 else rock
                top = _column(piece, cap, cx, cy, cw, cd, h, rng)
                cols.append((cx, cy, cw, cd, h))
                tops.append((cx, cy, cw, cd, top))
            s += w * rng.uniform(0.84, 0.92)
        # colliders: runs of neighbouring columns with similar heights merge into one box
        run = []

        def flush():
            if not run:
                return
            xs0 = min(c[0] - c[2] / 2 for c in run) + 0.25
            xs1 = max(c[0] + c[2] / 2 for c in run) - 0.25
            ys0 = min(c[1] - c[3] / 2 for c in run) + 0.25
            ys1 = max(c[1] + c[3] / 2 for c in run) - 0.25
            hh = sum(c[4] for c in run) / len(run) * 0.97
            colliders.append({"size": K.roblox_size((xs1 - xs0, ys1 - ys0, hh)),
                              "offset": K.to_roblox(((xs0 + xs1) / 2, (ys0 + ys1) / 2, hh / 2))})
            run.clear()

        for c in cols:
            if run and abs(c[4] - sum(r[4] for r in run) / len(run)) > 2.2:
                flush()
            run.append(c)
        flush()
    # moss tufts on a few tops, boulders along the front foot
    for cx, cy, cw, cd, top in rng.sample(tops, min(moss, len(tops))):
        _moss(moss_p, Vector((cx + rng.uniform(-cw, cw) * 0.25, cy + rng.uniform(-cd, cd) * 0.25, top - 0.1)),
              rng.uniform(0.7, 1.1), rng)
    front = [r for r in rows if abs(r[1][0] - r[0][0]) >= abs(r[1][1] - r[0][1])]
    if front and boulders:
        a, b, depth, _ = min(front, key=lambda r: r[0][1])
        for i in range(boulders):
            x = a[0] + (b[0] - a[0]) * rng.uniform(0.1, 0.9)
            sz = rng.uniform(1.1, 1.9)
            pts = K.roughen(K.rock_points(rng.randrange(1 << 20), (sz * 1.2, sz, sz * 0.8), n=16, shape="cube"), i + seed, count=8)
            (dark if i % 2 else rock).hull(pts, loc=(x, a[1] - depth / 2 - sz * 0.3, 0), rot=(0, 0, rng.uniform(0, 360)))
            _moss(moss_p, Vector((x + 0.6, a[1] - depth / 2 - sz * 0.9, 0)), 0.45, rng) if i == 0 else None
    m.extra["colliders"] = colliders


def _bump(t, c, wdt):
    return math.exp(-((t - c) / wdt) ** 2)


def straight_cliff(m, seed, W, D, back_h, mid=0.7, front=0.4):
    """Three rows parallel to X: back (tall), middle, front (low ledge). back_h(t) is the back-row height."""
    rows = [
        ((-W / 2 + W * 0.04, D / 2 - D * 0.22), (W / 2 - W * 0.04, D / 2 - D * 0.22), D * 0.46, back_h),
        ((-W / 2 + W * 0.02, 0.0), (W / 2 - W * 0.02, 0.0), D * 0.44, lambda t: back_h(t) * mid),
        ((-W / 2, -D / 2 + D * 0.2), (W / 2, -D / 2 + D * 0.2), D * 0.42, lambda t: back_h(t) * front),
    ]
    cliff_rows(m, seed, rows)


CLIFFS = {
    # name: (seed, W, D, back-row height(t), note, crop)
    "A": (11, 16, 11, lambda t: 6 + 8.5 * _bump(t, 0.42, 0.3), "tall central peak, stepped shoulders", (15, 55, 220, 250)),
    "B": (23, 20, 12, lambda t: 6.5 + 2.5 * _bump(t, 0.3, 0.2) + 2.2 * _bump(t, 0.72, 0.18), "broad mid-height block mass", (240, 85, 505, 250)),
    "C": (37, 14, 9, lambda t: 10 + 7 * _bump(t, 0.4, 0.3), "tall narrow column cluster", (515, 50, 735, 250)),
    "D": (41, 18, 12, lambda t: 4 + 10 * _bump(t, 0.52, 0.22), "stepped pyramid around a central spire", (750, 60, 975, 250)),
    "E": (53, 24, 11, lambda t: 4.0 + 6.5 * _bump(t, 0.8, 0.13) + 1.6 * _bump(t, 0.45, 0.2), "long low ledge (backdrop filler)", (995, 90, 1290, 250)),
    "F": (67, 16, 11, lambda t: 6 + 9 * _bump(t, 0.68, 0.22), "peak to the right, low steps on the left", (1295, 60, 1525, 250)),
}


FRONT = {"C": (0.75, 0.32), "E": (0.6, 0.45), "B": (0.75, 0.45)}   # middle / front row height ratios


def _cliff_builder(key):
    seed, W, D, hf, note, crop = CLIFFS[key]

    def build(m):
        straight_cliff(m, seed, W, D, hf, *FRONT.get(key, (0.7, 0.4)))
    register("Cliff_%s" % key, S05, "Cliff module %s: %s, %d x %d footprint, origin floor centre, front (-Y) faces the arena. "
             "Box colliders in manifest `colliders`." % (key, note, W, D), ref=(REF, crop))(build)


for _k in CLIFFS:
    _cliff_builder(_k)


@register("Cliff_Corner", S05, "Ledged cliff corner: L-shaped (back + left arms), inner corner faces the arena (-Y, +X). "
          "Origin floor centre of the 12 x 12 footprint; box colliders in manifest `colliders`.", ref=(REF, (15, 415, 180, 545)))
def cliff_corner(m):
    S = 12.0
    rows = [
        ((-S / 2, S / 2 - 2.2), (S / 2, S / 2 - 2.2), 4.2, lambda t: 9.5 - 2.5 * t),     # back arm
        ((-S / 2 + 2.2, S / 2 - 4.4), (-S / 2 + 2.2, -S / 2), 4.2, lambda t: 9.0 - 3.5 * t),  # left arm
        ((-S / 2 + 3.6, S / 2 - 5.2), (S / 2 - 1.0, S / 2 - 5.2), 2.6, lambda t: 4.6 - 1.4 * t),  # ledge (back)
        ((-S / 2 + 5.0, S / 2 - 7.0), (-S / 2 + 5.0, -S / 2 + 1.0), 2.4, lambda t: 4.2 - 1.8 * t),  # ledge (left)
    ]
    cliff_rows(m, 79, rows, boulders=0, moss=4)


# ------------------------------------------------------------------ retaining walls

def _wall_run(m, a, b, H, T, seed, block=1.6):
    """Coursed stone wall from a to b (axis aligned), height H, thickness T: dark core + bevelled blocks."""
    rng = random.Random(seed)
    stone, core = m.slot("Stone"), m.slot("RockDark")
    a, b = Vector((*a, 0)), Vector((*b, 0))
    L = (b - a).length
    u = (b - a).normalized()
    along_x = abs(u.x) > 0.5
    mid = (a + b) / 2
    core.box((L if along_x else T - 0.2, T - 0.2 if along_x else L, H - 0.05), loc=(mid.x, mid.y, H / 2), bevel=0.02)
    courses = 3
    ch = H / courses
    for c in range(courses):
        s = -block / 2 if c % 2 else 0.0
        while s < L - 0.05:
            s0, s1 = max(s, 0.0), min(s + block * rng.uniform(0.85, 1.15), L)
            if s1 - s0 > 0.3:
                cen = a + u * ((s0 + s1) / 2)
                ln = s1 - s0 - 0.08
                sz = (ln, T, ch - 0.08) if along_x else (T, ln, ch - 0.08)
                stone.box(sz, loc=(cen.x, cen.y, ch * (c + 0.5)), bevel=0.09)
            s = s1
    # coping course on top
    cap = (L + 0.1, T + 0.16, 0.22) if along_x else (T + 0.16, L + 0.1, 0.22)
    stone.box(cap, loc=(mid.x, mid.y, H + 0.11), bevel=0.06)


def _pier(m, x, y, H, s=1.5):
    stone = m.slot("Stone")
    stone.box((s, s, H), loc=(x, y, H / 2), bevel=0.1)
    stone.box((s + 0.2, s + 0.2, 0.26), loc=(x, y, H + 0.13), bevel=0.07)


@register("RetainingWall_Low", S05, "Low retaining wall section, 8 long x 1.2 thick x 2.4 tall + end pier. Origin floor centre; "
          "tiles along X every 8 studs. Collider = its bounding box.", ref=(REF, (190, 455, 345, 545)))
def retaining_wall(m):
    _wall_run(m, (-4.0, 0), (3.25, 0), 2.4, 1.2, 3)
    _pier(m, 3.25, 0, 3.0)
    m.attach["Next"] = (8.0, 0, 0)


@register("RetainingWall_Corner", S05, "Retaining wall corner: two 5-stud arms (along +X and +Y) meeting at a corner pier, with end piers. "
          "Origin floor centre of the corner pier.", ref=(REF, (370, 445, 525, 545)))
def retaining_corner(m):
    _wall_run(m, (0.6, 0), (5.0, 0), 2.4, 1.2, 5)
    _wall_run(m, (0, 0.6), (0, 5.0), 2.4, 1.2, 6)
    _pier(m, 0, 0, 3.2, 1.7)
    _pier(m, 5.4, 0, 3.0)
    _pier(m, 0, 5.4, 3.0)


# ------------------------------------------------------------------ fence

@register("Fence_Section", S05, "Wooden fence section: two bolted steel posts, two plank rails; 6 long x 3.2 tall. "
          "Origin floor centre; tiles along X every 6 studs (the next section shares the right post).", ref=(REF, (540, 430, 672, 530)))
def fence(m):
    frame, dark, wood, bolt = m.slot("Frame"), m.slot("FrameDark"), m.slot("Wood"), m.slot("SteelLight")
    L, H = 6.0, 3.2
    post = m.slot("Timber")
    for x in (-L / 2, L / 2):
        post.box((0.75, 0.75, H), loc=(x, 0, H / 2), bevel=0.08)
        frame.box((0.9, 0.9, 0.2), loc=(x, 0, H + 0.04), bevel=0.05)
        dark.box((0.95, 0.95, 0.4), loc=(x, 0, 0.2), bevel=0.06)
    for z in (1.15, 2.35):
        wood.box((L - 0.5, 0.3, 0.85), loc=(0, -0.15, z), bevel=0.07)
        for x in (-L / 2, L / 2):
            frame.box((0.85, 0.08, 0.7), loc=(x, -0.41, z), bevel=0.02)
            bolt.bolt((x, -0.45, z), normal=(0, -1, 0), r=0.12)
    m.attach["Next"] = (L, 0, 0)
    m.extra["collider"] = {"size": K.roblox_size((L + 0.5, 0.7, H)), "offset": K.to_roblox((0, -0.05, H / 2))}


# ------------------------------------------------------------------ lantern (gate, nook, wall lamp)

def lantern(m, at, s=1.0, lens_name="Lamp"):
    """Caged lantern hanging below `at` (top of its cap)."""
    at = Vector(at)
    frame, lamp = m.slot("Frame"), m.slot(lens_name)
    frame.box((0.5 * s, 0.5 * s, 0.14 * s), loc=at + Vector((0, 0, -0.07 * s)), bevel=0.03)
    frame.cyl(0.2 * s, 0.26 * s, 0.14 * s, seg=8, loc=at + Vector((0, 0, -0.2 * s)))
    lamp.cyl(0.2 * s, 0.2 * s, 0.6 * s, seg=8, loc=at + Vector((0, 0, -0.57 * s)))
    for a in range(4):
        ang = a * math.pi / 2 + math.pi / 4
        frame.box((0.06 * s, 0.06 * s, 0.66 * s), loc=at + Vector((math.cos(ang) * 0.22 * s, math.sin(ang) * 0.22 * s, -0.57 * s)), bevel=0.0)
    frame.cyl(0.28 * s, 0.2 * s, 0.14 * s, seg=8, loc=at + Vector((0, 0, -0.94 * s)))
    return at + Vector((0, 0, -0.57 * s))


# ------------------------------------------------------------------ gate

@register("Quarry_Gate", S05, "Quarry entrance gate: two steel posts on amber-collared plinths, header beam with knee braces, two hanging "
          "lanterns (Lamp piece). 13-stud clear opening, 11 tall. Origin floor centre; colliders = the two posts.",
          ref=(REF, (690, 420, 910, 550)))
def gate(m):
    frame, dark, amber, bolt, wood = m.slot("Frame"), m.slot("FrameDark"), m.slot("Amber", "Metal"), m.slot("SteelLight"), m.slot("Timber")
    X, H = 7.2, 11.0
    for sx in (-1, 1):
        x = sx * X
        m.slot("Stone").box((2.6, 2.6, 0.7), loc=(x, 0, 0.35), bevel=0.1)
        amber.box((2.15, 2.15, 1.4), loc=(x, 0, 1.4), bevel=0.08)
        wood.box((1.75, 1.75, H - 1.5), loc=(x, 0, 1.5 + (H - 1.5) / 2), bevel=0.1)
        for z in (2.4, H - 2.6):
            frame.box((1.95, 1.95, 0.45), loc=(x, 0, z), bevel=0.05)
        for sy in (-1, 1):
            for z in (1.1, 1.7):
                for dx in (-0.6, 0.6):
                    bolt.bolt((x + dx, sy * 1.08, z), normal=(0, sy, 0), r=0.1)
        # knee braces
        wood.box_between((x - sx * 0.8, 0, H - 3.4), (x - sx * 2.8, 0, H - 1.2), (0.6, 0.7))
        frame.box((0.7, 0.8, 0.7), loc=(x - sx * 2.6, 0, H - 1.45), bevel=0.05)
    # header: dark timber beam wrapped by steel end caps
    wood.box((2 * X + 2.6, 1.4, 1.5), loc=(0, 0, H - 0.6), bevel=0.1)
    for sx in (-1, 1):
        frame.box((2.2, 1.7, 1.8), loc=(sx * X, 0, H - 0.6), bevel=0.08)
        amber.box((0.4, 1.75, 1.85), loc=(sx * (X + 1.2), 0, H - 0.6), bevel=0.05)
        for z in (H - 0.15, H - 1.05):
            for dx in (-0.6, 0.6):
                bolt.bolt((sx * X + dx, -0.86, z), normal=(0, -1, 0), r=0.11)
    for x in (-3.6, 3.6):
        frame.box((0.14, 0.14, 0.4), loc=(x, 0, H - 1.55), bevel=0.0)
        lantern(m, (x, 0, H - 1.7), 1.6)
    m.attach["Sign"] = (0, -0.65, H - 0.55)
    m.extra["colliders"] = [{"size": K.roblox_size((2.6, 2.6, H)), "offset": K.to_roblox((sx * X, 0, H / 2))} for sx in (-1, 1)]


# ------------------------------------------------------------------ storage nook

def _crate(m, at, s, seed=0):
    at = Vector(at)
    wood, batten = m.slot("Wood"), m.slot("WoodDark")
    wood.box((s, s, s), loc=at + Vector((0, 0, s / 2)), bevel=0.04)
    b = s * 0.12
    for sx in (-1, 1):
        for sz in (-1, 1):
            batten.box((b, s + 0.03, b), loc=at + Vector((sx * (s / 2 - b / 2 + 0.02), 0, s / 2 + sz * (s / 2 - b / 2 + 0.02))), bevel=0.02)
            batten.box((s + 0.03, b, b), loc=at + Vector((0, sx * (s / 2 - b / 2 + 0.02), s / 2 + sz * (s / 2 - b / 2 + 0.02))), bevel=0.02)
    batten.box_between(at + Vector((-s / 2 + b, -s / 2 - 0.02, b)), at + Vector((s / 2 - b, -s / 2 - 0.02, s - b)), (b * 0.9, 0.05), bevel=0.01)


def _barrel(m, at, r=0.55, h=1.3):
    at = Vector(at)
    m.slot("Wood").cyl(r * 0.9, r * 0.9, h, seg=10, loc=at + Vector((0, 0, h / 2)))
    m.slot("Wood").cyl(r, r, h * 0.6, seg=10, loc=at + Vector((0, 0, h / 2)))
    for z in (0.18, h - 0.18):
        m.slot("Frame").cyl(r * 0.97, r * 0.97, 0.1, seg=10, loc=at + Vector((0, 0, z)))


@register("Storage_Nook", S05, "Open-front storage nook: concrete slab, timber posts, sloped plank roof, plank back + side walls, "
          "crates and barrels inside, two lanterns. 12 x 6.5, front eave 6.4 tall. Origin floor centre; colliders = walls + slab.",
          ref=(REF, (925, 420, 1125, 550)))
def storage_nook(m):
    wood, dark, frame, conc = m.slot("Wood"), m.slot("Timber"), m.slot("Frame"), m.slot("Concrete")
    W, D, Hf, Hb = 12.0, 6.5, 6.4, 5.6
    conc.box((W + 0.6, D + 0.6, 0.4), loc=(0, 0, 0.2), bevel=0.08)
    z0 = 0.4
    for sx in (-1, 0, 1):
        for sy in (-1, 1):
            if sx == 0 and sy == -1:
                continue
            x, y = sx * (W / 2 - 0.35), sy * (D / 2 - 0.35)
            h = (Hf if sy < 0 else Hb) - z0
            dark.box((0.6, 0.6, h), loc=(x, y, z0 + h / 2), bevel=0.06)
            frame.box((0.8, 0.8, 0.3), loc=(x, y, z0 + 0.15), bevel=0.05)
    # beams under the roof (front, back, ends)
    dark.box((W + 0.3, 0.55, 0.55), loc=(0, -D / 2 + 0.35, Hf - 0.55), bevel=0.05)
    dark.box((W + 0.3, 0.55, 0.55), loc=(0, D / 2 - 0.35, Hb - 0.55), bevel=0.05)
    slope = math.degrees(math.atan2(Hf - Hb, D))
    for sx in (-1, 0, 1):
        dark.box((0.45, D + 0.4, 0.45), loc=(sx * (W / 2 - 0.35), 0, (Hf + Hb) / 2 - 0.05), rot=(slope, 0, 0), bevel=0.04)
    # roof planks running front to back, overhanging
    n = 9
    pw = (W + 1.6) / n
    for i in range(n):
        x = -(W + 1.6) / 2 + pw * (i + 0.5)
        wood.box((pw - 0.06, D + 1.8, 0.28), loc=(x, -0.1, (Hf + Hb) / 2 + 0.32), rot=(slope, 0, 0), bevel=0.04)
    # back wall planks (horizontal) + side half walls
    for i in range(6):
        z = z0 + 0.45 + i * 0.85
        if z > Hb - 0.4:
            break
        dark.box((W - 0.6, 0.22, 0.78), loc=(0, D / 2 - 0.35, z), bevel=0.04)
    for sx in (-1, 1):
        for i in range(2):
            wood.box((0.22, D - 0.9, 0.78), loc=(sx * (W / 2 - 0.35), 0.2, z0 + 0.45 + i * 0.85), bevel=0.04)
    # stock: crates and barrels against the back
    _crate(m, (-3.8, 1.4, z0), 2.0)
    _crate(m, (-3.8, 1.4, z0 + 2.0), 1.5)
    _crate(m, (-1.6, 1.6, z0), 1.7)
    _crate(m, (2.4, 1.5, z0), 1.9)
    _crate(m, (2.4, 1.5, z0 + 1.9), 1.3)
    _crate(m, (0.5, 0.2, z0), 1.4)
    _barrel(m, (4.3, 1.7, z0), 0.7, 1.6)
    _barrel(m, (4.2, -0.2, z0), 0.6, 1.4)
    _barrel(m, (0.4, 1.9, z0), 0.65, 1.5)
    _barrel(m, (-1.9, -0.7, z0), 0.55, 1.3)
    for x in (-3.0, 3.0):
        lantern(m, (x, -D / 2 + 0.35, Hf - 0.83), 1.2)
    m.extra["colliders"] = [
        {"size": K.roblox_size((W + 0.6, D + 0.6, 0.4)), "offset": K.to_roblox((0, 0, 0.2))},
        {"size": K.roblox_size((W, 0.6, Hb)), "offset": K.to_roblox((0, D / 2 - 0.35, Hb / 2))},
        {"size": K.roblox_size((0.6, D, 2.9)), "offset": K.to_roblox((-W / 2 + 0.35, 0, 1.45))},
        {"size": K.roblox_size((0.6, D, 2.9)), "offset": K.to_roblox((W / 2 - 0.35, 0, 1.45))},
    ]


# ------------------------------------------------------------------ large crane + bucket

def _truss(frame, web, a, b, depth, thick=0.5, n=8, up=Vector((0, 0, 1))):
    """Two chords from a to b (offset by depth along `up`) with zig-zag web members."""
    a, b = Vector(a), Vector(b)
    top_a, top_b = a + up * depth, b + up * depth
    frame.box_between(a, b, (thick, thick))
    frame.box_between(top_a, top_b, (thick, thick))
    for i in range(n):
        p0 = a + (b - a) * (i / n)
        p1 = top_a + (top_b - top_a) * ((i + 0.5) / n)
        p2 = a + (b - a) * ((i + 1) / n)
        web.box_between(p0, p1, (thick * 0.55, thick * 0.55), bevel=0.0)
        web.box_between(p1, p2, (thick * 0.55, thick * 0.55), bevel=0.0)


@register("Crane_Large", S05, "Large gantry crane (background, supported): two braced A-frame trestles on amber footings, solid deck girder "
          "with amber railing, operator cab with lit windows, inclined truss boom on an amber mast; the bucket is the separate "
          "Crane_Bucket model hung at attach `Bucket` (preview shows it). 24 long x 7 deep x 16 tall; origin floor centre; "
          "colliders = the two trestles.", ref=(REF, (1150, 390, 1400, 550)))
def crane(m):
    crane_body(m)
    crane_bucket_parts(m, Vector(m.attach["Bucket"]), preview=True)


def crane_body(m):
    frame, dark, amber, bolt, lamp = m.slot("Frame"), m.slot("FrameDark"), m.slot("Amber", "Metal"), m.slot("SteelLight"), m.slot("Lamp")
    X, Y, Z = 8.5, 2.6, 8.0
    for sx in (-1, 1):
        x = sx * X
        for sy in (-1, 1):
            for dx in (-1, 1):   # A-frame: two posts per side splay outward at the foot
                fx = x + dx * 1.9
                dark.box((1.7, 1.7, 0.35), loc=(fx, sy * Y, 0.18), bevel=0.05)
                amber.box((1.35, 1.35, 1.0), loc=(fx, sy * Y, 0.85), bevel=0.07)
                frame.box_between((fx, sy * Y, 1.3), (x + dx * 0.7, sy * Y * 0.85, Z - 0.6), (0.95, 0.95))
                bolt.bolt((fx, sy * Y - 0.7, 0.85), normal=(0, -1, 0), r=0.1) if sy < 0 else None
            # X brace + tie inside each A-frame (front / back face)
            dark.box_between((x - 1.5, sy * Y, 2.0), (x + 0.9, sy * Y, Z - 1.4), (0.42, 0.42))
            dark.box_between((x + 1.5, sy * Y, 2.0), (x - 0.9, sy * Y, Z - 1.4), (0.42, 0.42))
            frame.box((3.4, 0.5, 0.5), loc=(x, sy * Y, 2.0), bevel=0.05)
        # side braces between the front and back A-frames
        for dx in (-1, 1):
            dark.box_between((x + dx * 1.2, -Y, 3.0), (x + dx * 1.0, Y * 0.85, Z - 1.2), (0.36, 0.36))
        frame.box((2.4, 2 * Y + 0.8, 0.9), loc=(x, 0, Z - 0.5), bevel=0.07)
    # deck girder
    L = 12.0
    frame.box((2 * L, 2 * Y + 1.6, 1.3), loc=(0, 0, Z + 0.6), bevel=0.1)
    dark.box((2 * L - 0.6, 2 * Y + 0.6, 0.5), loc=(0, 0, Z - 0.2), bevel=0.06)
    for x in range(-11, 12, 2):
        dark.box((0.25, 0.12, 1.0), loc=(x, -Y - 0.85, Z + 0.6), bevel=0.02)
    m.slot("WoodDark").box((2 * L - 0.8, 2 * Y + 1.0, 0.16), loc=(0, 0, Z + 1.32), bevel=0.03)
    # amber railing along the front and back edges
    for sy in (-1, 1):
        y = sy * (Y + 0.6)
        amber.box((2 * L - 0.6, 0.16, 0.16), loc=(0, y, Z + 2.35), bevel=0.03)
        amber.box((2 * L - 0.6, 0.12, 0.12), loc=(0, y, Z + 1.85), bevel=0.02)
        for x in range(-11, 12, 2):
            amber.box((0.16, 0.16, 1.0), loc=(x + 0.5, y, Z + 1.85), bevel=0.02)
    # operator cab (left end of the deck)
    cx, cz = -L + 2.2, Z + 1.4
    amber.box((3.4, 3.2, 0.5), loc=(cx, 0, cz + 0.25), bevel=0.05)
    frame.box((3.0, 2.8, 3.0), loc=(cx, 0, cz + 2.0), bevel=0.08)
    dark.box((3.5, 3.3, 0.4), loc=(cx, 0, cz + 3.7), bevel=0.06)
    dark.box((1.2, 1.2, 0.5), loc=(cx - 0.5, 0.4, cz + 4.1), bevel=0.05)
    for wx in (-0.6, 0.6):
        lamp.box((0.9, 0.08, 1.2), loc=(cx + wx, -1.42, cz + 2.3), bevel=0.02)
    lamp.box((0.08, 1.6, 1.2), loc=(cx + 1.52, 0, cz + 2.3), bevel=0.02)
    # boom: truss from beside the cab rising to the right, amber mast under it, head block + sheave
    base, head = Vector((cx + 2.0, 0, Z + 3.0)), Vector((L - 1.2, 0, Z + 7.2))
    amber.box((1.6, 1.8, 1.4), loc=base + Vector((0, 0, -0.7)), bevel=0.07)
    for sy in (-1, 1):
        _truss(frame, dark, base + Vector((0, sy * 0.55, 0)), head + Vector((0, sy * 0.55, 0)), 1.1, 0.42, n=8,
               up=Vector((-0.31, 0, 0.95)))
    for t in (0.12, 0.5, 0.88):
        p = base + (head - base) * t
        dark.box((0.35, 1.5, 0.35), loc=p, bevel=0.03)
    mast = Vector((3.0, 0, Z + 1.4))
    for sy in (-1, 1):
        amber.box_between(mast + Vector((-1.4, sy * 0.6, 0)), base + (head - base) * 0.55 + Vector((0, sy * 0.6, -0.1)), (0.45, 0.45))
        amber.box_between(mast + Vector((1.4, sy * 0.6, 0)), base + (head - base) * 0.55 + Vector((0, sy * 0.6, -0.1)), (0.45, 0.45))
    frame.box((1.8, 1.8, 1.8), loc=head + Vector((0.2, 0, 0.3)), bevel=0.08)
    dark.cyl(0.75, 0.75, 0.5, seg=10, loc=head + Vector((-0.3, 0, 1.4)), rot=(90, 0, 0))
    amber.box((0.4, 1.9, 0.4), loc=head + Vector((-0.3, 0, 1.4)), bevel=0.04)
    # hoist under the deck centre: sheave block + two cables down to the bucket
    hx = 0.0
    dark.box((1.4, 1.4, 0.6), loc=(hx, 0, Z - 0.75), bevel=0.06)
    by = 3.6
    for dx in (-0.2, 0.2):
        m.slot("Slate").box((0.1, 0.1, Z - 1.05 - by), loc=(hx + dx, 0, by + (Z - 1.05 - by) / 2), bevel=0.0)
    m.attach["Bucket"] = (hx, 0, by)
    m.extra["colliders"] = [{"size": K.roblox_size((5.6, 2 * Y + 1.8, Z)), "offset": K.to_roblox((sx * X, 0, Z / 2))} for sx in (-1, 1)]


def crane_bucket_parts(m, at=Vector((0, 0, 0)), preview=False):
    """Clamshell grab hanging below `at` (the hook)."""
    def P(slot, material=None):
        return m.preview_piece("P_Bucket_" + slot, slot) if preview else m.slot(slot, material)

    frame, dark, amber, bolt = P("Frame"), P("FrameDark"), P("Amber", "Metal"), P("SteelLight")
    if preview:
        amber.material = "Metal"
    hz = -1.3   # hinge height below the hook
    dark.box((0.5, 0.5, 0.4), loc=at + Vector((0, 0, -0.2)), bevel=0.05)
    frame.box((1.4, 0.8, 0.6), loc=at + Vector((0, 0, -0.7)), bevel=0.07)
    amber.box((1.5, 0.85, 0.16), loc=at + Vector((0, 0, -0.52)), bevel=0.04)
    for sx in (-1, 1):
        dark.box_between(at + Vector((sx * 0.5, 0, -0.9)), at + Vector((sx * 1.55, 0, hz - 0.75)), (0.22, 0.22))
    prof = [(0.0, 0.05), (1.45, -0.05), (1.8, -0.6), (1.6, -1.3), (0.95, -1.75), (0.0, -1.85)]
    for name, sx in (("ShellL", -1), ("ShellR", 1)):
        if preview:
            p = m.preview_piece("P_Bucket_" + name, "Frame")
        else:
            p = m.piece(name, "Frame", anim="Open", pivot=(sx * 0.1, 0, hz), note="clamshell half; swings about the hinge (Y axis)")
        pts = [(sx * x, z) for x, z in prof]
        if sx < 0:
            pts.reverse()
        p.prism(pts, 2.0, loc=at + Vector((sx * 0.06, 0, hz)), bevel=0.07)
        amber.box((0.18, 2.06, 0.3), loc=at + Vector((sx * 1.62, 0, hz - 1.0)), rot=(0, sx * 18, 0), bevel=0.03)
        for y in (-1.02, 1.02):
            bolt.bolt(at + Vector((sx * 0.9, y, hz - 0.8)), normal=(0, 1 if y > 0 else -1, 0), r=0.1)
    frame.cyl(0.18, 0.18, 2.3, seg=8, loc=at + Vector((0, 0, hz)), rot=(90, 0, 0))


@register("Crane_Bucket", S05, "Clamshell grab bucket for Crane_Large. Origin = the hook (top centre); the bucket hangs below it. "
          "ShellL / ShellR swing about the hinge (attrs Anim=Open, Pivot) to drop rubble.", ref=(REF, (1255, 470, 1300, 530)))
def crane_bucket(m):
    crane_bucket_parts(m)


# ------------------------------------------------------------------ wall lamp

@register("Wall_Lamp", S05, "Wall lamp: bolted wall plate, curved steel arm, caged amber lantern (Lamp piece = the glow). "
          "Origin = back centre of the wall plate (sits on the wall surface, front -Y); add a PointLight at attach `Light`.",
          ref=(REF, (1420, 425, 1525, 530)))
def wall_lamp(m):
    frame, dark, bolt = m.slot("Frame"), m.slot("FrameDark"), m.slot("SteelLight")
    dark.box((0.62, 0.16, 1.15), loc=(0, -0.08, 0), bevel=0.04)
    for z in (0.4, -0.4):
        bolt.bolt((0, -0.16, z), normal=(0, -1, 0), r=0.08)
    frame.tube([(0, -0.16, 0.25), (0, -0.7, 0.42), (0, -1.15, 0.45), (0, -1.4, 0.3)], 0.08, seg=8)
    frame.box_between((0, -0.16, -0.3), (0, -0.75, 0.38), (0.09, 0.09), bevel=0.02)
    c = lantern(m, (0, -1.4, 0.25), 1.0)
    m.attach["Light"] = tuple(c)
