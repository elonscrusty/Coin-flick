"""Quarry perimeter pass (Master Prompt 5 section 8 / pass four): rock strata, ground transitions and
edge utility pieces.

* Strata_Low / Strata_Mid / Strata_High / Strata_Shoulder: broad terraced cliff walls made of horizontal
  rock benches (tiers) that step back from the arena, each tier a row of big, slightly uneven faceted
  blocks with light sunlit caps on some tops. Calm skyline, few moss tufts,
  a gravel skirt and two or three grounded boulders at the foot. Box colliders per tier in the manifest
  (`colliders`). Front (-Y) faces the arena; origin = floor centre of the front foot line. Tiers reach
  3 studs below the floor so no gap shows on uneven ground.
* Rubble_Skirt: ground-to-cliff transition cluster (low gravel mound + a few scenery stones in the warm
  cliff colour, flatter than the collectible pile rocks so the two never read alike).
* Cart_Track / Track_Buffer / Mine_Cart: a short narrow-gauge track on a gravel bed with a buffer stop and an
  ore tub parked on it (utility cart bay at the quarry edge).
* Quarry_ToolShelter: lean-to tool shelter with a tool wall (shovels, sledges), workbench with vise,
  lantern; for an edge utility corner.
Blender axes as everywhere (Roblox = (-x, z, y)).
"""

import math
import random

from mathutils import Vector

import ctrkit as K
from ctrkit import register
from models.quarry import _crate, _barrel

K.HEX.setdefault("Gravel", "#8F8476")   # gravel skirts, track ballast
K.SLOT_MATERIAL.setdefault("Gravel", "Pebble")

S05 = "05"
REF = "05_quarry_environment_kit.png"
BELOW = -3.0   # tiers start below the floor


def _block(piece, x0, x1, y_front, y_back, z0, z1, rng, lean=0.5, chamfer=0.45):
    """One faceted strata block: front face leans back toward the top, chamfered top-front edge, small
    jitter on every corner so neighbouring blocks never line up like bricks."""
    j = lambda a=0.18: rng.uniform(-a, a)  # noqa: E731
    yf_top = y_front + lean
    pts = [
        Vector((x0 + j(), y_front + j(), z0)), Vector((x1 + j(), y_front + j(), z0)),
        Vector((x0 + j(), y_back, z0)), Vector((x1 + j(), y_back, z0)),
        Vector((x0 + 0.15 + j(), y_back, z1 + j(0.2))), Vector((x1 - 0.15 + j(), y_back, z1 + j(0.2))),
        # chamfered top-front edge
        Vector((x0 + 0.2 + j(), yf_top + chamfer + j(), z1 + j(0.15))), Vector((x1 - 0.2 + j(), yf_top + chamfer + j(), z1 + j(0.15))),
        Vector((x0 + j(), yf_top + j(), z1 - chamfer + j(0.1))), Vector((x1 + j(), yf_top + j(), z1 - chamfer + j(0.1))),
        # a slight bulge mid-face so the front is not one flat plane
        Vector(((x0 + x1) / 2 + j(0.5), y_front + (yf_top - y_front) * 0.45 - rng.uniform(0.05, 0.3), z0 + (z1 - z0) * rng.uniform(0.35, 0.6))),
    ]
    piece.hull(pts)


def strata_cliff(m, seed, W, tiers, slope=0.0, moss=2, boulders=2, skirt=True):
    """tiers: list of (front_y, top_z) from the front (lowest) tier to the back (highest). Every tier is a
    row of blocks spanning the width; its back reaches the next tier's front (the last tier goes 6 deep).
    slope: extra height per stud toward +X (a falling or rising skyline). Tier ends drop a little."""
    rng = random.Random(seed)
    rock, dark, lip, moss_p = m.slot("Cliff"), m.slot("CliffDark"), m.slot("RockLight"), m.slot("Moss")
    colliders = []
    tops = []
    prev_top = BELOW
    for ti, (yf, top) in enumerate(tiers):
        yb = tiers[ti + 1][0] + 1.0 if ti + 1 < len(tiers) else yf + 6.0
        z0 = BELOW   # every tier stands on the floor: no overhang voids from any side
        tw = W * (1 - 0.05 * ti)
        x = -tw / 2
        piece = rock if ti % 2 == 0 else dark
        while x < tw / 2 - 0.5:
            bw = rng.uniform(5.0, 8.5)
            if tw / 2 - (x + bw) < 3.5:
                bw = tw / 2 - x
            xc = x + bw / 2
            edge = abs(xc) / (tw / 2)
            zt = top + slope * xc - edge ** 3 * (top - max(z0, 0)) * 0.3 + rng.uniform(-0.9, 0.9)
            zt = max(zt, z0 + 1.2)
            bpiece = piece if rng.random() < 0.7 else (dark if piece is rock else rock)
            yfb = yf + rng.uniform(-0.7, 0.5)
            _block(bpiece, x - 0.15, x + bw + 0.15, yfb, yb, z0, zt, rng, lean=rng.uniform(0.4, 1.1), chamfer=rng.uniform(0.4, 0.9))
            # sunlit top: a thin light cap set back from the face (reads as a ledge, not a plank)
            if rng.random() < 0.6:
                lip.box((bw * rng.uniform(0.6, 0.85), (yb - yf) * 0.6, 0.25), loc=(xc + rng.uniform(-0.5, 0.5), yf + 1.2 + (yb - yf) * 0.3, zt - 0.05),
                        rot=(rng.uniform(-2, 2), rng.uniform(-2, 2), 0), bevel=0.1)
            tops.append((xc, yf + 1.5, zt))
            x += bw
        colliders.append({"size": K.roblox_size((tw, yb - yf, top + 0.5)), "offset": K.to_roblox((0, (yf + yb) / 2, (top + 0.5) / 2))})
        prev_top = top
    # few moss tufts on tier tops (subdued, sparse)
    for xc, y, zt in rng.sample(tops, min(moss, len(tops))):
        for k in range(2):
            r = rng.uniform(0.35, 0.55)
            c = Vector((xc + rng.uniform(-1.2, 1.2), y + rng.uniform(-0.2, 0.4), zt + 0.2))
            moss_p.hull([c + Vector((math.cos(a) * r, math.sin(a) * r * 0.8, 0)) for a in [i / 6 * math.tau for i in range(6)]] +
                        [c + Vector((0, 0, r * 0.6))])
    # foot: gravel skirt + grounded boulders (scenery, warm cliff tone)
    yf0 = tiers[0][0]
    if skirt:
        for k in range(3):
            xg = (k - 1) * W * 0.3 + rng.uniform(-2, 2)
            _gravel_mound(m.slot("Gravel"), Vector((xg, yf0 - 0.6, 0)), rng.uniform(4.5, 7.0), 2.4, rng.uniform(0.6, 0.9), rng)
    for i in range(boulders):
        xb = rng.uniform(-W * 0.4, W * 0.4)
        sz = rng.uniform(1.2, 2.0)
        pts = K.roughen(K.rock_points(rng.randrange(1 << 20), (sz * 1.3, sz, sz * 0.7), n=16, shape="cube"), seed + i, count=8)
        (dark if i % 2 else rock).hull(pts, loc=(xb, yf0 - sz * 0.5, -0.1), rot=(0, 0, rng.uniform(0, 360)))
    m.extra["colliders"] = colliders


def _gravel_mound(piece, at, w, d, h, rng, n=14):
    """Low flat gravel mound: an elliptical hull, flat on the floor, highest along its back."""
    pts = []
    for i in range(n):
        a = i / n * math.tau
        pts.append(at + Vector((math.cos(a) * w / 2 * rng.uniform(0.9, 1.0), math.sin(a) * d / 2 * rng.uniform(0.85, 1.0), -0.05)))
    for i in range(7):
        a = i / 7 * math.tau + 0.3
        pts.append(at + Vector((math.cos(a) * w * 0.32, math.sin(a) * d * 0.22 + d * 0.12, h * rng.uniform(0.7, 1.0))))
    piece.hull(pts)


STRATA = {
    # name: (seed, W, tiers [(front_y, top_z)], slope, note, ref crop)
    "Low": (101, 28, [(-4.0, 4.5), (1.0, 9.0)], 0.0, "two low benches (front row filler)",
            (REF, (0, 640, 760, 790))),
    "Mid": (113, 30, [(-6.0, 5.0), (-0.5, 10.0), (5.0, 14.5)], 0.0, "three benches, broad mid-height wall",
            (REF, (760, 640, 1536, 790))),
    "High": (127, 30, [(-6.0, 6.5), (0.0, 13.0), (6.0, 19.0)], 0.08, "tall back wall rising to +X",
            (REF, (240, 85, 505, 250))),
    "Shoulder": (139, 24, [(-4.5, 4.5), (1.0, 8.5), (6.0, 12.0)], -0.25, "terraces falling away to +X (road cuts, row ends)",
            (REF, (995, 90, 1290, 250))),
}


def _strata_builder(key):
    seed, W, tiers, slope, note, ref = STRATA[key]
    depth = tiers[-1][0] + 6.0 - tiers[0][0]

    def build(m):
        strata_cliff(m, seed, W, tiers, slope)
        m.attach["Foot"] = (0, tiers[0][0], 0)
    register("Strata_%s" % key, S05, "Strata cliff %s: %s; %d wide x %.0f deep, top %.0f. Horizontal benches of big faceted blocks with "
             "light caps, gravel skirt and boulders at the foot. Origin floor centre of the front foot line (tiers reach "
             "3 below the floor), front (-Y) faces the arena; box colliders per tier in manifest `colliders`."
             % (key, note, W, depth, tiers[-1][1]), ref=ref)(build)


for _k in STRATA:
    _strata_builder(_k)


# ------------------------------------------------------------------ layered strata walls
# Quarry-face walls built from thin, uneven rock layers (bedding planes) instead of stacked boxes: every layer
# is a few hull segments whose fronts step in and out, the face leans back, layers alternate Cliff / CliffDark
# with a rare light bed, and tall broken columns stand on the top. Used by ArenaKit.strata (variants A-C).

def layered_wall(m, seed, W, layers, depth, batter, columns, talus=4):
    """layers: list of layer heights from the floor up. depth: back-to-front size. batter: how far the face
    steps back per layer. columns: number of tall broken columns on top."""
    rng = random.Random(seed)
    rock, dark, lip = m.slot("Cliff"), m.slot("CliffDark"), m.slot("RockLight")
    z = BELOW
    yfront = 0.0
    top = 0.0
    j = lambda a=0.2: rng.uniform(-a, a)  # noqa: E731
    for li, hgt in enumerate(layers):
        z1 = z + hgt
        yf = yfront + rng.uniform(-0.3, 0.3)
        # horizontal segments of this layer; their edges shift layer to layer so seams never stack
        edges = [-W / 2 + (li % 2) * 1.6]
        while edges[-1] < W / 2 - 4:
            edges.append(edges[-1] + rng.uniform(8.0, 14.0))
        edges[-1] = W / 2
        taper = 1.0 - 0.03 * li
        for a, b in zip(edges[:-1], edges[1:]):
            a, b = a * taper, b * taper
            yfs = yf + rng.uniform(-1.1, 0.6)      # this segment juts out or sits back
            zt = z1 + rng.uniform(-0.25, 0.3)
            lean = batter * rng.uniform(0.7, 1.3)
            pts = [
                Vector((a + j(), yfs + j(), z)), Vector((b + j(), yfs + j(), z)),
                Vector((a + j(), depth, z)), Vector((b + j(), depth, z)),
                Vector((a + 0.2 + j(), yfs + lean + j(), zt)), Vector((b - 0.2 + j(), yfs + lean + j(), zt)),
                Vector((a + 0.3 + j(), depth, zt)), Vector((b - 0.3 + j(), depth, zt)),
                # a notch low on the face: reads as a bedding crack
                Vector(((a + b) / 2 + j(0.4), yfs - rng.uniform(0.05, 0.35), z + (zt - z) * rng.uniform(0.3, 0.55))),
            ]
            pick = dark if (li % 2) else rock
            if rng.random() < 0.18:
                pick = dark if pick is rock else rock
            pick.hull(pts)
            top = max(top, zt)
        # thin light bed on some layers, set back so it reads as a ledge catching the sun
        if li >= 1 and rng.random() < 0.55:
            wx = rng.uniform(W * 0.25, W * 0.6)
            xc = rng.uniform(-W / 2 + wx / 2, W / 2 - wx / 2) * taper
            lip.box((wx, 1.8, 0.22), loc=(xc, yfront + batter + 1.2, z1 - 0.02), rot=(rng.uniform(-2, 2), rng.uniform(-2, 2), 0), bevel=0.08)
        yfront += batter
        z = z1
    # broken columns on the top: narrow, tall, leaning slightly, different heights
    for c in range(columns):
        cw = rng.uniform(6.0, 9.0)
        xc = -W / 2 * 0.7 + (c + rng.uniform(0.3, 0.7)) * W * 0.7 / max(columns, 1)
        ch = rng.uniform(2.0, 4.0)
        yb = rng.uniform(depth * 0.45, depth * 0.8)
        yf = yb - rng.uniform(4.0, 5.0)
        pts = [
            Vector((xc - cw / 2 + j(), yf + j(), z - 0.5)), Vector((xc + cw / 2 + j(), yf + j(), z - 0.5)),
            Vector((xc - cw / 2 + j(), yb, z - 0.5)), Vector((xc + cw / 2 + j(), yb, z - 0.5)),
            Vector((xc - cw / 2 * 0.7 + j(), yf + 0.6 + j(), z + ch + j(0.3))), Vector((xc + cw / 2 * 0.7 + j(), yf + 0.6 + j(), z + ch + j(0.5))),
            Vector((xc - cw / 2 * 0.6, yb - 0.4, z + ch * 0.9)), Vector((xc + cw / 2 * 0.6, yb - 0.4, z + ch * 0.85)),
        ]
        (rock if c % 2 else dark).hull(pts)
        top = max(top, z + ch)
    # grounded talus at the foot (scenery)
    for i in range(talus):
        sz = rng.uniform(1.1, 2.1)
        pts = K.roughen(K.rock_points(rng.randrange(1 << 20), (sz * 1.4, sz, sz * 0.7), n=16, shape="cube"), seed + i, count=8)
        (dark if i % 2 else rock).hull(pts, loc=(rng.uniform(-W * 0.42, W * 0.42), -sz * 0.45, -0.1), rot=(0, 0, rng.uniform(0, 360)))
    m.extra["colliders"] = [{"size": K.roblox_size((W * 0.96, depth + 1.0, top + 0.5)), "offset": K.to_roblox((0, (depth - 1.0) / 2, (top + 0.5) / 2))}]


LAYERED = {
    # name: (seed, W, layer heights, depth, batter, columns, note)
    "A": (211, 30, [2.8, 2.2, 3.0, 2.0, 2.6], 9.0, 0.7, 2, "six bedded layers, three broken columns"),
    "B": (223, 28, [3.4, 2.0, 2.8, 3.2], 8.0, 1.0, 2, "five layers, steeper step-back"),
    "C": (237, 32, [2.4, 3.0, 2.0, 2.6, 3.0, 2.2], 10.0, 0.6, 3, "seven thin beds, tall broken crown"),
}


def _layered_builder(key):
    seed, W, layers, depth, batter, columns, note = LAYERED[key]

    def build(m):
        layered_wall(m, seed, W, layers, depth, batter, columns)
        m.attach["Foot"] = (0, 0, 0)
    register("Cliff_Strata_%s" % key, S05, "Layered cliff wall %s: %s; %d wide x %.0f deep. Thin uneven rock beds (Cliff / CliffDark, rare "
             "RockLight ledge), leaning face, broken columns on top, talus at the foot. Origin floor centre of the front foot line "
             "(layers reach 3 below the floor), front (-Y) faces the arena; box collider in manifest `colliders`." % (key, note, W, depth),
             ref=(REF, (0, 640, 760, 790)))(build)


for _k in LAYERED:
    _layered_builder(_k)


# ------------------------------------------------------------------ ground transition

@register("Rubble_Skirt", S05, "Ground-to-cliff transition: low gravel mound 8 x 3.4 with five scenery stones (warm cliff tone, flat, "
          "never pile-like) and chips. Origin floor centre, front (-Y) faces the arena. Decorative, no collision.",
          ref=(REF, (0, 860, 700, 1024)))
def rubble_skirt(m):
    rng = random.Random(211)
    _gravel_mound(m.slot("Gravel"), Vector((0, 0.3, 0)), 8.0, 3.4, 0.55, rng)
    rock, dark = m.slot("Cliff"), m.slot("CliffDark")
    for i, (x, y, s) in enumerate(((-2.6, 0.6, 1.5), (-0.6, 0.9, 1.1), (1.6, 0.5, 1.7), (3.0, 1.0, 0.9), (0.4, -0.4, 0.7))):
        pts = K.roughen(K.rock_points(300 + i, (s * 1.3, s, s * 0.55), n=14, shape="cube"), 40 + i, count=6)
        (dark if i % 2 else rock).hull(pts, loc=(x, y, 0.05 + (0.2 if abs(y) > 0.5 else 0)), rot=(0, 0, rng.uniform(0, 360)))
    chips = m.slot("Gravel")
    for i in range(9):
        s = rng.uniform(0.25, 0.45)
        chips.hull(K.rock_points(400 + i, (s, s, s * 0.6), n=8), loc=(rng.uniform(-3.8, 3.8), rng.uniform(-1.6, -0.6), 0), rot=(0, 0, rng.uniform(0, 360)))


# ------------------------------------------------------------------ cart track

GAUGE = 1.5


def _track(m, x0, x1, sleepers=True):
    ballast, sleeper, rail = m.slot("Gravel"), m.slot("WoodDark"), m.slot("Steel")
    L = x1 - x0
    xc = (x0 + x1) / 2
    ballast.box((L, 3.0, 0.24), loc=(xc, 0, 0.12), taper=(1.0, 0.8), bevel=0.06)
    if sleepers:
        n = max(2, int(L / 0.95))
        for i in range(n):
            x = x0 + L * (i + 0.5) / n
            sleeper.box((0.5, 2.4, 0.2), loc=(x, 0, 0.32), bevel=0.04)
    for sy in (-1, 1):
        rail.box((L, 0.16, 0.24), loc=(xc, sy * GAUGE / 2, 0.54), bevel=0.03)
        rail.box((L, 0.34, 0.06), loc=(xc, sy * GAUGE / 2, 0.44), bevel=0.01)


@register("Cart_Track", S05, "Narrow-gauge track segment 8 long (X), sleepers on a gravel bed, rail tops at 0.66; gauge 1.5. Origin floor "
          "centre; tiles along X every 8 studs (attach Next). Decorative, walkable (no collision needed).",
          ref=(REF, (0, 700, 520, 900)))
def cart_track(m):
    _track(m, -4.0, 4.0)
    m.attach["Next"] = (8.0, 0, 0)
    m.attach["Rail"] = (0, 0, 0.66)


@register("Track_Buffer", S05, "Track buffer stop: 3 of track ending in a timber stop block with an amber bumper beam facing -X. "
          "Origin floor centre; the track runs in from -X.", ref=(REF, (0, 700, 520, 900)))
def track_buffer(m):
    _track(m, -1.5, 1.5)
    timber, frame, amber = m.slot("Timber"), m.slot("Frame"), m.slot("Amber", "Metal")
    timber.box((0.9, 2.6, 1.2), loc=(1.05, 0, 0.6 + 0.24), bevel=0.08)
    for sy in (-1, 1):
        timber.box_between((1.5, sy * 1.0, 0.25), (0.75, sy * 1.0, 1.4), (0.35, 0.35))
        frame.cyl(0.18, 0.18, 0.4, seg=8, loc=(0.4, sy * 0.75, 1.0), rot=(0, 90, 0))
    amber.box((0.25, 2.4, 0.45), loc=(0.55, 0, 1.0), bevel=0.05)
    m.slot("SteelLight").bolt((0.42, -0.9, 1.0), normal=(-1, 0, 0), r=0.08)
    m.slot("SteelLight").bolt((0.42, 0.9, 1.0), normal=(-1, 0, 0), r=0.08)


@register("Mine_Cart", S05, "Ore tub cart for Cart_Track: dark steel tub with amber rim band, chassis, four flanged wheels on the 1.5 "
          "gauge, a heap of grey rubble inside (scenery only). 3.2 long x 2.1 wide x 2.4 tall; origin floor centre "
          "(wheels sit on rails at 0.66 when placed on a track's origin).", ref=(REF, (1150, 420, 1400, 600)))
def mine_cart(m):
    frame, dark, amber = m.slot("Frame"), m.slot("FrameDark"), m.slot("Amber", "Metal")
    base = 0.66
    for sx in (-1, 1):
        for sy in (-1, 1):
            dark.cyl(0.36, 0.36, 0.18, seg=10, loc=(sx * 0.95, sy * GAUGE / 2, base + 0.34), rot=(90, 0, 0))
            dark.cyl(0.44, 0.44, 0.06, seg=10, loc=(sx * 0.95, sy * (GAUGE / 2 - 0.12), base + 0.34), rot=(90, 0, 0))
    frame.box((2.8, 1.5, 0.3), loc=(0, 0, base + 0.75), bevel=0.06)
    zt0 = base + 0.9
    # tapered tub: walls lean out
    frame.box((2.6, 1.7, 0.18), loc=(0, 0, zt0 + 0.09), bevel=0.04)
    for sy in (-1, 1):
        frame.box((3.1, 0.16, 1.3), loc=(0, sy * 0.92, zt0 + 0.65), rot=(sy * -8, 0, 0), bevel=0.04)
    for sx in (-1, 1):
        frame.box((0.16, 1.9, 1.3), loc=(sx * 1.47, 0, zt0 + 0.65), rot=(0, sx * 8, 0), bevel=0.04)
    for sy in (-1, 1):   # rim band (an open frame, the rubble shows inside)
        amber.box((3.35, 0.22, 0.18), loc=(0, sy * 1.0, zt0 + 1.28), bevel=0.04)
    for sx in (-1, 1):
        amber.box((0.22, 2.15, 0.18), loc=(sx * 1.58, 0, zt0 + 1.28), bevel=0.04)
    for sx in (-1, 1):
        m.slot("SteelLight").bolt((sx * 1.1, -1.0, zt0 + 0.7), normal=(0, -1, 0), r=0.08)
        frame.box((0.25, 0.25, 0.25), loc=(sx * 1.65, 0, base + 0.75), bevel=0.04)  # couplers
    rub = m.slot("Cliff")
    m.slot("Gravel").box((2.8, 1.7, 0.3), loc=(0, 0, zt0 + 1.0), bevel=0.08)
    for i, (x, y, s) in enumerate(((-0.8, -0.2, 0.9), (0.2, 0.3, 1.0), (0.95, -0.3, 0.75), (-0.2, -0.45, 0.6), (0.5, 0.45, 0.55))):
        rub.hull(K.rock_points(500 + i, (s, s * 0.9, s * 0.7), n=12, shape="cube"), loc=(x, y, zt0 + 1.0), rot=(0, 0, i * 50))


# ------------------------------------------------------------------ tool shelter

@register("Quarry_ToolShelter", S05, "Lean-to tool shelter 9 x 5, eave 5.4 front / 4.6 back: concrete slab, timber posts, plank roof on a "
          "steel fascia, plank back wall with a tool board (shovels, sledges), workbench with a vise, lantern (Lamp). Origin "
          "floor centre, open front -Y; attach Light. Colliders: back wall + slab.", ref=(REF, (925, 420, 1125, 550)))
def tool_shelter(m):
    wood, timber, frame, conc = m.slot("Wood"), m.slot("Timber"), m.slot("Frame"), m.slot("Concrete")
    W, D, Hf, Hb = 9.0, 5.0, 5.4, 4.6
    conc.box((W + 0.4, D + 0.4, 0.3), loc=(0, 0, 0.15), bevel=0.06)
    z0 = 0.3
    for sx in (-1, 1):
        for sy, H in ((-1, Hf), (1, Hb)):
            timber.box((0.45, 0.45, H - z0), loc=(sx * (W / 2 - 0.25), sy * (D / 2 - 0.25), z0 + (H - z0) / 2), bevel=0.05)
            frame.box((0.6, 0.6, 0.3), loc=(sx * (W / 2 - 0.25), sy * (D / 2 - 0.25), z0 + 0.15), bevel=0.04)
    for sy, H in ((-1, Hf), (1, Hb)):
        timber.box((W + 0.3, 0.45, 0.45), loc=(0, sy * (D / 2 - 0.25), H - 0.2), bevel=0.05)
    ang = math.degrees(math.atan2(Hf - Hb, D))
    roof_z = (Hf + Hb) / 2 + 0.25
    for i in range(6):
        x = -W / 2 - 0.4 + (W + 0.8) * (i + 0.5) / 6
        wood.box(((W + 0.8) / 6 - 0.06, D + 1.2, 0.22), loc=(x, 0, roof_z), rot=(ang, 0, 0), bevel=0.04)
    frame.box((W + 1.0, 0.18, 0.35), loc=(0, -D / 2 - 0.62, Hf + 0.02), bevel=0.03)
    # back wall planks + tool board
    for i in range(10):
        x = -W / 2 + 0.4 + (W - 0.8) * (i + 0.5) / 10
        wood.box(((W - 0.8) / 10 - 0.05, 0.2, Hb - z0 - 0.3), loc=(x, D / 2 - 0.3, z0 + (Hb - z0 - 0.3) / 2), bevel=0.03)
    board = m.slot("WoodDark")
    board.box((4.2, 0.12, 2.0), loc=(-1.6, D / 2 - 0.45, 3.0), bevel=0.03)
    steel = m.slot("Steel")
    for i in range(4):
        x = -3.2 + i * 1.05
        board.box((0.12, 0.1, 1.5), loc=(x, D / 2 - 0.55, 3.15), bevel=0.02)            # handle
        if i % 2 == 0:
            steel.box((0.5, 0.08, 0.6), loc=(x, D / 2 - 0.56, 2.2), bevel=0.03)           # shovel blade
        else:
            steel.box((0.6, 0.3, 0.3), loc=(x, D / 2 - 0.6, 3.9), bevel=0.04)             # sledge head
    # workbench with a vise on the right
    bx = 2.2
    wood.box((3.4, 1.4, 0.22), loc=(bx, D / 2 - 1.2, 1.9), bevel=0.04)
    for sx in (-1, 1):
        for sy in (-1, 1):
            frame.box((0.18, 0.18, 1.6), loc=(bx + sx * 1.5, D / 2 - 1.2 + sy * 0.55, z0 + 0.8), bevel=0.02)
    wood.box((3.0, 1.1, 0.12), loc=(bx, D / 2 - 1.2, 0.8), bevel=0.02)
    frame.box((0.5, 0.4, 0.35), loc=(bx + 1.1, D / 2 - 1.75, 2.18), bevel=0.04)
    steel.box((0.12, 0.6, 0.12), loc=(bx + 1.1, D / 2 - 2.05, 2.18), bevel=0.02)
    m.slot("Amber", "Metal").box((0.9, 0.6, 0.5), loc=(bx - 0.8, D / 2 - 1.2, 2.26), bevel=0.05)     # tool box
    # lantern under the front beam
    lamp = m.slot("Lamp")
    frame.box((0.12, 0.12, 0.5), loc=(0, -D / 2 + 0.25, Hf - 0.65), bevel=0.01)
    frame.box((0.6, 0.6, 0.12), loc=(0, -D / 2 + 0.25, Hf - 0.95), bevel=0.02)
    lamp.box((0.45, 0.45, 0.6), loc=(0, -D / 2 + 0.25, Hf - 1.3), bevel=0.03)
    frame.box((0.55, 0.55, 0.1), loc=(0, -D / 2 + 0.25, Hf - 1.65), bevel=0.02)
    m.attach["Light"] = (0, -D / 2 + 0.25, Hf - 1.3)
    # a crate and barrel at the left front corner (inside the slab)
    _crate(m, (-3.4, -1.0, z0), 1.2)
    _barrel(m, (-2.1, -1.4, z0), r=0.45, h=1.2)
    m.extra["colliders"] = [
        {"size": K.roblox_size((W, 0.6, Hb)), "offset": K.to_roblox((0, D / 2 - 0.3, Hb / 2))},
        {"size": K.roblox_size((W + 0.4, D + 0.4, 0.3)), "offset": K.to_roblox((0, 0, 0.15))},
    ]
