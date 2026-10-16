"""Sheet 11: Utility & workshop prop kit.

Same shape language as the station kit: dark steel bodies (Frame / FrameDark), amber trims and panels,
honey wood, rubber wheels, hex bolts, warm lamps. Every prop's origin is its floor centre (front -Y) unless
the note says otherwise. Decorative props record one bounding collider (`collider`) so the game can use a
single box instead of the mesh; small hand-sized props (bucket, trays, placard) are meant to be non-colliding.
"""

import math
import random

from mathutils import Vector

import ctrkit as K
from ctrkit import register

S11 = "11"
REF = "11_utility_prop_kit.png"


def _collider(m, size, centre):
    m.extra["collider"] = {"size": K.roblox_size(size), "offset": K.to_roblox(centre)}


def flared_walls(piece, bot, top, z0, z1, wall, front=True, sides=(-1, 1)):
    """Four sloped walls of an open bin: bottom (w, d) at z0 flaring to top (w, d) at z1, `wall` thick.
    Each wall is a hull of its outer face + the same face moved `wall` inward."""
    bw, bd = bot[0] / 2, bot[1] / 2
    tw, td = top[0] / 2, top[1] / 2
    faces = {
        "front": [(-bw, -bd, z0), (bw, -bd, z0), (tw, -td, z1), (-tw, -td, z1)],
        "back": [(-bw, bd, z0), (bw, bd, z0), (tw, td, z1), (-tw, td, z1)],
        "left": [(-bw, -bd, z0), (-bw, bd, z0), (-tw, td, z1), (-tw, -td, z1)],
        "right": [(bw, -bd, z0), (bw, bd, z0), (tw, td, z1), (tw, -td, z1)],
    }
    inward = {"front": (0, 1, 0), "back": (0, -1, 0), "left": (1, 0, 0), "right": (-1, 0, 0)}
    for k, quad in faces.items():
        if k == "front" and not front:
            continue
        n = Vector(inward[k]) * wall
        pts = [Vector(p) for p in quad] + [Vector(p) + n for p in quad]
        piece.hull(pts)
    return faces


def face_plate(piece, quad, outward, t=0.04, shrink=0.0, z_from=0.0, z_to=1.0):
    """Thin plate on a (possibly sloped) quad face: the part between fractions z_from..z_to of its height."""
    a, b, c, d = [Vector(p) for p in quad]
    lo_a, lo_b = a + (d - a) * z_from, b + (c - b) * z_from
    hi_a, hi_b = a + (d - a) * z_to, b + (c - b) * z_to
    side = (lo_b - lo_a).normalized() * shrink
    q = [lo_a + side, lo_b - side, hi_b - side, hi_a + side]
    o = Vector(outward) * t
    piece.hull([p + o * 0.2 for p in q] + [p + o for p in q])


def open_box(piece, floor, w, d, h, wall=0.12, loc=(0, 0, 0)):
    loc = Vector(loc)
    floor.box((w - 0.04, d - 0.04, 0.1), loc=loc + Vector((0, 0, 0.05)), bevel=0.02)
    piece.box((w, wall, h), loc=loc + Vector((0, -d / 2 + wall / 2, h / 2)), bevel=0.03)
    piece.box((w, wall, h), loc=loc + Vector((0, d / 2 - wall / 2, h / 2)), bevel=0.03)
    piece.box((wall, d, h), loc=loc + Vector((-w / 2 + wall / 2, 0, h / 2)), bevel=0.03)
    piece.box((wall, d, h), loc=loc + Vector((w / 2 - wall / 2, 0, h / 2)), bevel=0.03)


def wheel(m, at, r, w, axis="x", hub="Amber"):
    rot = (0, 90, 0) if axis == "x" else (90, 0, 0)
    m.slot("Rubber").cyl(r, r, w, seg=12, loc=at, rot=rot, bevel=0.03)
    m.slot(hub, "Metal").cyl(r * 0.5, r * 0.5, w + 0.06, seg=8, loc=at, rot=rot)
    m.slot("SteelLight").cyl(r * 0.18, r * 0.18, w + 0.14, seg=6, loc=at, rot=rot)


# ------------------------------------------------------------------ rubble selling hopper

@register("Prop_RubbleHopper", S11, "Rubble selling hopper: flared steel bin with amber side panels and hazard band on a braced steel "
          "frame, discharge ramp at the front, right-hand pillar with a beacon (Beacon piece) and a receipt printer "
          "(ReceiptLight = lit screen, Receipt = paper slip; toggle on a sale). 7 x 5 footprint, 5.6 tall. Attach `Deposit` "
          "= drop point above the bin, `Prompt` = receipt panel.", ref=(REF, (20, 20, 485, 345)))
def rubble_hopper(m):
    frame, dark, amber, bolt, slate = m.slot("Frame"), m.slot("FrameDark"), m.slot("Amber", "Metal"), m.slot("SteelLight"), m.slot("Slate")
    z0, z1 = 2.2, 4.4
    # legs: square posts with amber sleeves and dark feet
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * 2.3, sy * 1.6
            dark.box((0.95, 0.95, 0.45), loc=(x, y, 0.22), bevel=0.06)
            frame.box((0.7, 0.7, z0 + 0.2), loc=(x, y, (z0 + 0.2) / 2 + 0.3), bevel=0.06)
            amber.box((0.8, 0.8, 0.9), loc=(x, y, 1.2), bevel=0.06)
    # base frame + hazard band under the bin
    frame.box((5.4, 3.9, 0.5), loc=(0, 0, z0 - 0.2), bevel=0.07)
    slate.box((4.4, 0.06, 0.38), loc=(0, -1.97, z0 - 0.2), bevel=0.01)
    K.hazard_stripes(amber, 4.4, 0.38, (0, -2.0, z0 - 0.2), count=7, slant=0.9, depth=0.03, margin=0.02)
    # flared bin: dark walls, amber panels on the outer faces
    faces = flared_walls(frame, (4.6, 3.2), (6.6, 4.6), z0, z1, 0.22)
    dark.box((4.4, 3.0, 0.2), loc=(0, 0, z0 + 0.1), bevel=0.03)
    face_plate(amber, faces["front"], (0, -1, 0), 0.06, shrink=0.15, z_from=0.04, z_to=0.78)
    face_plate(amber, faces["left"], (-1, 0, 0), 0.06, shrink=0.15, z_from=0.04, z_to=0.78)
    face_plate(amber, faces["right"], (1, 0, 0), 0.06, shrink=0.15, z_from=0.04, z_to=0.78)
    # rim lip
    for sy in (-1, 1):
        dark.box((6.9, 0.32, 0.22), loc=(0, sy * 2.3, z1 + 0.05), bevel=0.04)
    for sx in (-1, 1):
        dark.box((0.32, 4.9, 0.22), loc=(sx * 3.3, 0, z1 + 0.05), bevel=0.04)
    # discharge ramp at the front: sloped chute with amber side rails
    ramp_a, ramp_b = Vector((0, -1.9, 1.6)), Vector((0, -4.2, 0.15))
    mid = (ramp_a + ramp_b) / 2
    ang = math.degrees(math.atan2(ramp_a.z - ramp_b.z, ramp_a.y - ramp_b.y))
    dark.box((2.2, (ramp_a - ramp_b).length, 0.14), loc=mid, rot=(ang, 0, 0), bevel=0.03)
    for sx in (-1, 1):
        amber.box((0.16, (ramp_a - ramp_b).length, 0.4), loc=mid + Vector((sx * 1.15, 0, 0.15)), rot=(ang, 0, 0), bevel=0.04)
    frame.box((2.6, 0.6, 1.3), loc=(0, -1.9, 1.4), bevel=0.06)
    # right pillar with beacon + receipt printer
    px = 3.8
    dark.box((1.0, 1.0, 0.4), loc=(px, -1.0, 0.2), bevel=0.05)
    frame.box((0.75, 0.75, 5.0), loc=(px, -1.0, 2.7), bevel=0.07)
    frame.box((0.9, 0.9, 0.3), loc=(px, -1.0, 5.25), bevel=0.05)
    beacon = m.piece("Beacon", "Lamp", note="beacon lens on the pillar; brighten on a sale")
    beacon.box((0.6, 0.6, 0.45), loc=(px, -1.0, 5.65), bevel=0.06)
    dark.box((0.72, 0.72, 0.12), loc=(px, -1.0, 5.94), bevel=0.03)
    # printer box on the pillar's front
    pb = Vector((px, -1.6, 3.4))
    frame.box((1.1, 0.6, 1.1), loc=pb, bevel=0.08)
    amber.box((1.15, 0.62, 0.18), loc=pb + Vector((0, 0, 0.6)), bevel=0.04)
    m.piece("ReceiptLight", "Lamp", note="receipt screen glow; on while a receipt prints").box((0.7, 0.06, 0.4), loc=pb + Vector((0, -0.31, 0.15)), bevel=0.02)
    slate.box((0.7, 0.08, 0.08), loc=pb + Vector((0, -0.31, -0.2)), bevel=0.0)
    m.piece("Receipt", "Cream", material="SmoothPlastic", note="paper slip; show / slide out on a sale").box(
        (0.5, 0.03, 0.65), loc=pb + Vector((0, -0.36, -0.55)), rot=(-8, 0, 0), bevel=0.0)
    for sx in (-1, 1):
        bolt.bolt(pb + Vector((sx * 0.42, -0.31, -0.42)), normal=(0, -1, 0), r=0.06)
    for sx in (-1, 1):
        for z in (z0 + 0.4, z1 - 0.3):
            bolt.bolt((sx * 2.9, -2.1 - (z - z0) * 0.32, z), normal=(0, -1, 0.3), r=0.08)
    m.attach["Deposit"] = (0, 0, z1 + 1.0)
    m.attach["Prompt"] = tuple(pb + Vector((0, -0.4, 0)))
    m.attach["Output"] = tuple(ramp_b + Vector((0, 0, 0.1)))
    _collider(m, (7.0, 5.0, z1 + 0.2), (0, 0, (z1 + 0.2) / 2))


# ------------------------------------------------------------------ generator

@register("Prop_Generator", S11, "Compact generator: amber body in a dark tubular roll cage, control panel with lit indicator "
          "(Indicator piece), vent grille, fuel cap. 3.2 x 2.2 x 2.6.", ref=(REF, (910, 115, 1210, 345)))
def generator(m):
    frame, dark, amber, slate, bolt = m.slot("Frame"), m.slot("FrameDark"), m.slot("Amber", "Metal"), m.slot("Slate"), m.slot("SteelLight")
    for sx in (-1, 1):
        for sy in (-1, 1):
            m.slot("Rubber").box((0.4, 0.4, 0.2), loc=(sx * 1.3, sy * 0.8, 0.1), bevel=0.04)
    dark.box((2.9, 1.9, 0.35), loc=(0, 0, 0.35), bevel=0.06)
    amber.box((2.7, 1.75, 1.6), loc=(0, 0, 1.3), bevel=0.12)
    amber.box((2.2, 1.4, 0.3), loc=(0, 0, 2.2), bevel=0.08)
    slate.box((0.35, 0.35, 0.18), loc=(-0.6, 0.2, 2.42), bevel=0.04)
    dark.box((0.5, 0.3, 0.12), loc=(0.5, 0.0, 2.4), bevel=0.03)
    # front: dark control panel with sockets, grille on the right side
    dark.box((2.1, 0.12, 1.15), loc=(0, -0.9, 1.25), bevel=0.04)
    for i, x in enumerate((-0.65, -0.15)):
        frame.box((0.35, 0.08, 0.5), loc=(x, -0.98, 1.3), bevel=0.03)
    frame.box((0.55, 0.08, 0.6), loc=(0.55, -0.98, 1.35), bevel=0.03)
    m.piece("Indicator", "Lamp", note="running light; lit while powered").box((0.18, 0.06, 0.18), loc=(0.45, -1.02, 1.5), bevel=0.02)
    for x in (0.45, 0.68):
        slate.cyl(0.07, 0.07, 0.08, seg=6, loc=(x, -1.02, 1.15), rot=(90, 0, 0))
    for i in range(5):
        slate.box((0.06, 1.2, 0.08), loc=(1.37, 0, 0.85 + i * 0.2), bevel=0.0)
    amber.box((0.4, 0.1, 0.6), loc=(-1.1, -0.92, 1.3), bevel=0.03)
    # roll cage: two tubular loops plus cross bars
    for sx in (-1, 1):
        x = sx * 1.55
        slate.tube([(x, -1.0, 0.25), (x, -1.0, 2.3), (x, -0.85, 2.6), (x, 0.85, 2.6), (x, 1.0, 2.3), (x, 1.0, 0.25)], 0.09, seg=8)
    for sy in (-1, 1):
        slate.tube([(-1.55, sy * 1.0, 0.3), (1.55, sy * 1.0, 0.3)], 0.08, seg=8)
    slate.tube([(-1.55, 0.85, 2.6), (1.55, 0.85, 2.6)], 0.08, seg=8)
    bolt.bolt((-1.55, -1.1, 1.4), normal=(0, -1, 0), r=0.07)
    bolt.bolt((1.55, -1.1, 1.4), normal=(0, -1, 0), r=0.07)
    _collider(m, (3.3, 2.2, 2.7), (0, 0, 1.35))


# ------------------------------------------------------------------ air compressor

@register("Prop_Compressor", S11, "Air compressor: horizontal dark tank with amber domed ends and band, motor block on top, "
          "pressure gauge, handle, two wheels and a foot. 3.8 long x 1.8 x 2.6 tall; attach `Hose` = outlet.",
          ref=(REF, (1235, 120, 1520, 345)))
def compressor(m):
    frame, dark, amber, slate, bolt = m.slot("Frame"), m.slot("FrameDark"), m.slot("Amber", "Metal"), m.slot("Slate"), m.slot("SteelLight")
    R, L, cz = 0.72, 2.6, 1.05
    frame.cyl(R, R, L, seg=14, loc=(0, 0, cz), rot=(0, 90, 0))
    for sx in (-1, 1):
        amber.cyl(R, R * 0.55, 0.42, seg=14, loc=(sx * (L / 2 + 0.21), 0, cz), rot=(0, sx * 90, 0))
        amber.cyl(R * 1.03, R * 1.03, 0.2, seg=14, loc=(sx * (L / 2 - 0.02), 0, cz), rot=(0, 90, 0))
    amber.cyl(R * 1.04, R * 1.04, 0.3, seg=14, loc=(0.1, 0, cz), rot=(0, 90, 0))
    # motor + shroud on top
    dark.box((1.1, 0.9, 0.2), loc=(-0.3, 0, cz + R + 0.05), bevel=0.04)
    frame.box((1.1, 1.0, 0.8), loc=(-0.3, 0, cz + R + 0.55), bevel=0.1)
    for i in range(4):
        slate.box((0.06, 1.02, 0.5), loc=(-0.65 + i * 0.22, 0, cz + R + 0.55), bevel=0.0)
    dark.box((0.9, 0.7, 0.18), loc=(-0.3, 0, cz + R + 1.03), bevel=0.04)
    # gauge
    frame.cyl(0.08, 0.08, 0.4, seg=6, loc=(-1.05, 0, cz + R + 0.15))
    frame.cyl(0.26, 0.26, 0.12, seg=12, loc=(-1.05, -0.06, cz + R + 0.42), rot=(90, 0, 0))
    m.slot("Cream", "SmoothPlastic").cyl(0.2, 0.2, 0.04, seg=12, loc=(-1.05, -0.13, cz + R + 0.42), rot=(90, 0, 0))
    slate.box((0.03, 0.02, 0.14), loc=(-1.02, -0.16, cz + R + 0.45), rot=(0, 30, 0), bevel=0.0)
    # handle (back right)
    slate.tube([(0.9, -0.45, cz + R - 0.05), (1.3, -0.45, cz + R + 0.75), (1.75, -0.45, cz + R + 0.75)], 0.07, seg=8)
    slate.tube([(0.9, 0.45, cz + R - 0.05), (1.3, 0.45, cz + R + 0.75), (1.75, 0.45, cz + R + 0.75)], 0.07, seg=8)
    m.slot("Rubber").cyl(0.1, 0.1, 1.0, seg=8, loc=(1.75, 0, cz + R + 0.75), rot=(90, 0, 0))
    # wheels (left end) and foot (right end)
    for sy in (-1, 1):
        wheel(m, (-1.1, sy * 0.85, 0.4), 0.4, 0.22, axis="y", hub="Frame")
    frame.cyl(0.08, 0.08, 1.9, seg=6, loc=(-1.1, 0, 0.4), rot=(90, 0, 0))
    dark.box((0.2, 0.9, 0.5), loc=(1.0, 0, 0.35), bevel=0.04)
    m.slot("Rubber").box((0.4, 1.0, 0.12), loc=(1.0, 0, 0.06), bevel=0.03)
    bolt.bolt((0.3, -R - 0.02, cz), normal=(0, -1, 0), r=0.07)
    m.attach["Hose"] = (-1.05, -R, cz)
    _collider(m, (3.8, 1.9, 2.6), (0, 0, 1.3))


# ------------------------------------------------------------------ wheelbarrow / handcart

@register("Prop_Wheelbarrow", S11, "Wheelbarrow: flared dark steel tray, amber tube frame and legs, rubber wheel at the front (-Y), "
          "rubber grips at the back. 1.9 wide x 4.6 long x 1.9 tall.", ref=(REF, (15, 395, 310, 580)))
def wheelbarrow(m):
    frame, dark, amber = m.slot("Frame"), m.slot("FrameDark"), m.slot("Amber", "Metal")
    z0 = 1.0
    flared_walls(frame, (1.1, 1.5), (1.8, 2.6), z0, z0 + 0.85, 0.09)
    dark.box((1.05, 1.45, 0.1), loc=(0, 0, z0 + 0.05), bevel=0.02)
    for sx in (-1, 1):
        frame.box((0.12, 2.65, 0.12), loc=(sx * 0.92, 0, z0 + 0.88), bevel=0.03)
    for sy in (-1, 1):
        frame.box((1.9, 0.12, 0.12), loc=(0, sy * 1.32, z0 + 0.88), bevel=0.03)
    wy = -1.75
    wheel(m, (0, wy, 0.45), 0.45, 0.35, axis="x")
    for sx in (-1, 1):
        x = sx * 0.5
        amber.tube([(sx * 0.22, wy, 0.45), (x, -0.6, z0 - 0.05), (x, 1.2, z0 - 0.05), (sx * 0.55, 2.55, 1.35)], 0.07, seg=8)
        amber.tube([(x, 0.9, z0 - 0.05), (x, 1.1, 0.12)], 0.06, seg=8)
        m.slot("Rubber").cyl(0.1, 0.1, 0.12, seg=8, loc=(x, 1.1, 0.06))
        m.slot("Rubber").cyl(0.1, 0.1, 0.5, seg=8, loc=(sx * 0.56, 2.65, 1.39), rot=(-74, 0, 0))
    amber.tube([(-0.5, 0.9, z0 - 0.05), (0.5, 0.9, z0 - 0.05)], 0.05, seg=6)
    m.attach["Load"] = (0, 0, z0 + 0.2)
    _collider(m, (1.9, 4.6, 1.9), (0, 0.4, 0.95))


@register("Prop_Handcart", S11, "Flatbed handcart: honey plank deck on a steel frame, four rubber wheels with amber hubs, "
          "upright steel handle with an amber grip at the back (+Y). 2.4 x 3.6 deck, 3.6 tall.", ref=(REF, (255, 385, 470, 580)))
def handcart(m):
    frame, wood, amber, bolt = m.slot("Frame"), m.slot("Wood"), m.slot("Amber", "Metal"), m.slot("SteelLight")
    W, D, z = 2.4, 3.6, 0.95
    for sx in (-1, 1):
        frame.box((0.2, D, 0.22), loc=(sx * (W / 2 - 0.1), 0, z - 0.15), bevel=0.04)
    for sy in (-1, 1):
        frame.box((W, 0.2, 0.22), loc=(0, sy * (D / 2 - 0.1), z - 0.15), bevel=0.04)
    n = 5
    pw = (D - 0.2) / n
    for i in range(n):
        wood.box((W - 0.2, pw - 0.06, 0.16), loc=(0, -D / 2 + 0.1 + pw * (i + 0.5), z + 0.04), bevel=0.04)
        for sx in (-1, 1):
            bolt.bolt((sx * (W / 2 - 0.25), -D / 2 + 0.1 + pw * (i + 0.5), z + 0.12), r=0.05)
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * (W / 2 - 0.35), sy * (D / 2 - 0.45)
            frame.box((0.3, 0.3, 0.3), loc=(x, y, z - 0.35), bevel=0.04)
            wheel(m, (x + sx * 0.12, y, 0.38), 0.38, 0.24, axis="x")
    # handle: two uprights, a mid rail and the amber grip
    for sx in (-1, 1):
        frame.tube([(sx * (W / 2 - 0.2), D / 2 - 0.1, z - 0.1), (sx * (W / 2 - 0.2), D / 2 + 0.1, z + 2.0),
                    (sx * (W / 2 - 0.35), D / 2 + 0.12, z + 2.55)], 0.08, seg=8)
    frame.tube([(-W / 2 + 0.2, D / 2 + 0.05, z + 1.2), (W / 2 - 0.2, D / 2 + 0.05, z + 1.2)], 0.07, seg=8)
    amber.cyl(0.13, 0.13, W - 0.5, seg=8, loc=(0, D / 2 + 0.12, z + 2.6), rot=(0, 90, 0))
    m.attach["Load"] = (0, 0, z + 0.12)
    _collider(m, (W, D + 0.3, z + 0.2), (0, 0.1, (z + 0.2) / 2))


# ------------------------------------------------------------------ crates / chest / pallet

def crate(m, s):
    wood, batten, bolt = m.slot("Wood"), m.slot("WoodDark"), m.slot("SteelLight")
    wood.box((s - 0.06, s - 0.06, s - 0.06), loc=(0, 0, s / 2), bevel=0.04)
    b = max(0.14, s * 0.12)
    h = s / 2
    for sx in (-1, 1):
        for sz in (-1, 1):
            batten.box((b, s, b), loc=(sx * (h - b / 2), 0, h + sz * (h - b / 2)), bevel=0.03)
            batten.box((s, b, b), loc=(0, sx * (h - b / 2), h + sz * (h - b / 2)), bevel=0.03)
        for sy in (-1, 1):
            batten.box((b, b, s), loc=(sx * (h - b / 2), sy * (h - b / 2), h), bevel=0.03)
    # plank seams on every side face
    seam = m.slot("Timber")
    for k in (-1, 1):
        off = k * s / 6
        for sy in (-1, 1):
            seam.box((0.04, 0.02, s - 2 * b), loc=(off, sy * (h - 0.02), h), bevel=0.0)
            seam.box((0.02, 0.04 if False else s - 2 * b, 0.04), loc=(sy * (h - 0.02), 0, h + off), bevel=0.0)
    # diagonal brace on the front, back and both ends
    for sy in (-1, 1):
        batten.box_between((-h + b, sy * (h + 0.01), b * 1.2), (h - b, sy * (h + 0.01), s - b * 1.2), (b * 0.85, 0.06), bevel=0.02)
    for sx in (-1, 1):
        batten.box_between((sx * (h + 0.01), -h + b, s - b * 1.2), (sx * (h + 0.01), h - b, b * 1.2), (0.06, b * 0.85), bevel=0.02)
    for sx in (-1, 1):
        for sz in (0, 1):
            bolt.bolt((sx * (h - b / 2), -h - 0.0, b / 2 + sz * (s - b)), normal=(0, -1, 0), r=0.05 + s * 0.012)
    _collider(m, (s, s, s), (0, 0, s / 2))


for _name, _s, _crop in (("Prop_CrateSmall", 1.6, (480, 450, 620, 575)), ("Prop_CrateMedium", 2.2, (625, 415, 800, 575)),
                         ("Prop_CrateLarge", 3.0, (805, 390, 1012, 575))):
    register(_name, S11, "Wooden crate %.1f studs: honey boards, dark battens on every edge, diagonal braces, corner bolts. "
             "Stackable (attach `Top`)." % _s, ref=(REF, _crop))(
        (lambda s: (lambda m: (crate(m, s), m.attach.__setitem__("Top", (0, 0, s)))))(_s))


@register("Prop_SteelChest", S11, "Steel storage chest: dark body with amber corner guards and latches; the Lid piece hinges at "
          "the back top edge (attrs Anim=Open, Pivot). 3.4 x 1.7 x 1.6.", ref=(REF, (1025, 430, 1282, 585)))
def steel_chest(m):
    frame, dark, amber, slate = m.slot("Frame"), m.slot("FrameDark"), m.slot("Amber", "Metal"), m.slot("Slate")
    W, D, H = 3.3, 1.6, 1.05
    frame.box((W, D, H), loc=(0, 0, H / 2), bevel=0.08)
    dark.box((W + 0.06, D + 0.06, 0.12), loc=(0, 0, 0.06), bevel=0.03)
    for i in range(3):
        dark.box((W - 0.8, 0.06, 0.08), loc=(0, -D / 2 - 0.01, 0.3 + i * 0.22), bevel=0.0)
    lid = m.piece("Lid", "Frame", anim="Open", pivot=(0, D / 2, H), note="lid; hinges at the back top edge (X axis)")
    lid.box((W + 0.1, D + 0.1, 0.5), loc=(0, 0, H + 0.25), bevel=0.1, taper=(0.95, 0.9))
    for sx in (-1, 1):
        for sy in (-1, 1):
            amber.box((0.42, 0.42, 0.42), loc=(sx * (W / 2 - 0.12), sy * (D / 2 - 0.12), H + 0.28), bevel=0.06)
            amber.box((0.36, 0.36, 0.3), loc=(sx * (W / 2 - 0.12), sy * (D / 2 - 0.12), 0.2), bevel=0.05)
        amber.box((0.32, 0.12, 0.55), loc=(sx * 0.9, -D / 2 - 0.05, H + 0.05), bevel=0.04)
        slate.box((0.14, 0.06, 0.18), loc=(sx * 0.9, -D / 2 - 0.12, H - 0.05), bevel=0.0)
        slate.box((0.12, D - 0.6, 0.3), loc=(sx * (W / 2 + 0.04), 0, H * 0.62), bevel=0.03)
    _collider(m, (W + 0.1, D + 0.1, H + 0.5), (0, 0, (H + 0.5) / 2))


@register("Prop_Pallet", S11, "Wooden pallet: top deck boards on three dark stringers, bottom boards. 3.4 x 2.6 x 0.6; attach `Top`.",
          ref=(REF, (1290, 440, 1525, 580)))
def pallet(m):
    wood, dark = m.slot("Wood"), m.slot("WoodDark")
    W, D = 3.4, 2.6
    for x in (-W / 2 + 0.25, 0, W / 2 - 0.25):
        dark.box((0.45, D, 0.3), loc=(x, 0, 0.27), bevel=0.03)
    for i in range(6):
        y = -D / 2 + 0.2 + i * (D - 0.4) / 5
        wood.box((W, 0.34, 0.1), loc=(0, y, 0.47), bevel=0.025)
    for y in (-D / 2 + 0.2, 0, D / 2 - 0.2):
        wood.box((W, 0.36, 0.1), loc=(0, y, 0.06), bevel=0.025)
    m.attach["Top"] = (0, 0, 0.52)
    _collider(m, (W, D, 0.52), (0, 0, 0.26))


# ------------------------------------------------------------------ stone bin / bucket / trays

@register("Prop_StoneBin", S11, "Stacked stone bin: open dark steel box with corner posts and hazard-striped sides, filled with "
          "rock chunks (Fill piece). 3.2 x 2.3 x 1.5.", ref=(REF, (15, 610, 310, 805)))
def stone_bin(m):
    frame, dark, slate, amber = m.slot("Frame"), m.slot("FrameDark"), m.slot("Slate"), m.slot("Amber", "Metal")
    W, D, H = 3.0, 2.1, 1.25
    open_box(frame, dark, W, D, H, wall=0.14)
    for sx in (-1, 1):
        for sy in (-1, 1):
            frame.box((0.32, 0.32, H + 0.25), loc=(sx * (W / 2 + 0.02), sy * (D / 2 + 0.02), (H + 0.25) / 2), bevel=0.05)
    slate.box((W - 0.6, 0.04, 0.5), loc=(0, -D / 2 - 0.02, 0.45), bevel=0.01)
    K.hazard_stripes(amber, W - 0.6, 0.5, (0, -D / 2 - 0.045, 0.45), count=5, slant=0.8, depth=0.03, margin=0.02)
    for sx in (-1, 1):
        slate.box((0.04, D - 0.6, 0.5), loc=(sx * (W / 2 + 0.02), 0, 0.45), bevel=0.01)
        K.hazard_stripes(amber, D - 0.6, 0.5, (sx * (W / 2 + 0.045), 0, 0.45), rot=(0, 0, 90), count=4, slant=0.8, depth=0.03, margin=0.02)
    for sy in (-1, 1):
        frame.box((W, 0.18, 0.16), loc=(0, sy * (D / 2), H + 0.02), bevel=0.04)
    fill = m.piece("Fill", "Rock", note="rock chunks heaped in the bin")
    fill.box((W - 0.4, D - 0.4, 0.5), loc=(0, 0, H - 0.4), bevel=0.04)
    rng = random.Random(5)
    for i, (x, y) in enumerate(((-0.9, -0.4), (0.0, -0.45), (0.9, -0.35), (-0.5, 0.45), (0.5, 0.45), (0.0, 0.05))):
        s = rng.uniform(0.75, 0.95)
        fill.hull(K.rock_points(30 + i, (s, s * 0.9, s * 0.8), n=14, shape="cube"), loc=(x, y, H - 0.3), rot=(0, 0, rng.uniform(0, 360)))
    _collider(m, (W + 0.4, D + 0.4, H + 0.3), (0, 0, (H + 0.3) / 2))


def ring_wall(piece, r0, r1, z0, z1, t, seg=12):
    """Open tapered tube wall (bucket sides) as `seg` hull slabs."""
    for i in range(seg):
        a0, a1 = i / seg * math.tau, (i + 1.05) / seg * math.tau
        pts = []
        for a in (a0, a1):
            c, s = math.cos(a), math.sin(a)
            pts += [Vector((c * r0, s * r0, z0)), Vector((c * r1, s * r1, z1)),
                    Vector((c * (r0 - t), s * (r0 - t), z0)), Vector((c * (r1 - t), s * (r1 - t), z1))]
        piece.hull(pts)


@register("Prop_Bucket", S11, "Steel bucket: tapered open pail, rim bands, wire bail with an amber grip. 1.3 tall (handle up 1.9).",
          ref=(REF, (355, 640, 495, 800)))
def bucket(m):
    frame, dark, amber, slate = m.slot("Frame"), m.slot("FrameDark"), m.slot("Amber", "Metal"), m.slot("Slate")
    ring_wall(frame, 0.48, 0.62, 0.0, 1.25, 0.07)
    dark.cyl(0.47, 0.47, 0.08, seg=12, loc=(0, 0, 0.1))
    ring_wall(frame, 0.665, 0.665, 1.12, 1.3, 0.12)
    ring_wall(frame, 0.52, 0.53, 0.0, 0.16, 0.1)
    for sx in (-1, 1):
        dark.box((0.1, 0.18, 0.2), loc=(sx * 0.63, 0, 1.0), bevel=0.02)
    pts = [(math.cos(a) * 0.66, 0, 1.0 + math.sin(a) * 0.75) for a in [i / 10 * math.pi for i in range(11)]]
    slate.tube(pts, 0.035, seg=6)
    amber.cyl(0.08, 0.08, 0.5, seg=8, loc=(0, 0, 1.75), rot=(0, 90, 0))


@register("Prop_PartsTray", S11, "Spare parts tray: low dark steel tray with flared walls holding an amber gear, a dark gear and "
          "a wrench. 2.2 x 1.4 x 0.5.", ref=(REF, (515, 640, 748, 800)))
def parts_tray(m):
    frame, dark, amber, light = m.slot("Frame"), m.slot("FrameDark"), m.slot("Amber", "Metal"), m.slot("SteelLight")
    flared_walls(frame, (1.9, 1.1), (2.2, 1.4), 0.0, 0.45, 0.08)
    dark.box((1.88, 1.08, 0.22), loc=(0, 0, 0.11), bevel=0.02)

    def gear(piece, at, r, teeth, h=0.14):
        piece.cyl(r, r, h, seg=teeth * 2, loc=at)
        for i in range(teeth):
            a = i / teeth * math.tau
            piece.box((r * 0.35, r * 0.3, h), loc=Vector(at) + Vector((math.cos(a), math.sin(a), 0)) * (r + 0.05),
                      rot=(0, 0, math.degrees(a)), bevel=0.01)
        m.slot("Slate").cyl(r * 0.3, r * 0.3, h + 0.02, seg=8, loc=at)

    gear(amber, (0.0, -0.05, 0.42), 0.36, 8, h=0.18)
    gear(m.slot("Steel"), (-0.6, -0.15, 0.36), 0.26, 7)
    light.box((0.95, 0.16, 0.07), loc=(0.45, 0.25, 0.5), rot=(0, -14, -28), bevel=0.02)
    light.prism([(-0.2, -0.14), (0.2, -0.14), (0.2, 0.16), (0.08, 0.16), (0.08, 0.02), (-0.08, 0.02), (-0.08, 0.16), (-0.2, 0.16)], 0.07,
                loc=(0.9, 0.48, 0.62), rot=(76, 0, 62))
    _collider(m, (2.2, 1.4, 0.5), (0, 0, 0.25))


@register("Prop_BoltContainer", S11, "Bolt container: deep dark steel tub with a raised back and flared walls, full of hex bolts. "
          "1.6 x 1.4 x 1.0.", ref=(REF, (760, 645, 948, 800)))
def bolt_container(m):
    frame, dark, light = m.slot("Frame"), m.slot("FrameDark"), m.slot("SteelLight")
    flared_walls(frame, (1.3, 1.1), (1.6, 1.4), 0.0, 0.9, 0.09)
    dark.box((1.35, 1.15, 0.6), loc=(0, 0, 0.3), bevel=0.02)
    rng = random.Random(9)
    for i in range(11):
        x, y = rng.uniform(-0.48, 0.48), rng.uniform(-0.4, 0.4)
        z = 0.72 + rng.uniform(0, 0.12)
        rot = (rng.uniform(-70, 70), rng.uniform(-70, 70), rng.uniform(0, 360))
        light.cyl(0.16, 0.16, 0.12, seg=6, loc=(x, y, z), rot=rot)
        from mathutils import Euler
        d = Euler([math.radians(a) for a in rot], "XYZ").to_matrix() @ Vector((0, 0, -0.22))
        light.cyl(0.07, 0.07, 0.36, seg=6, loc=Vector((x, y, z)) + d, rot=rot)
    _collider(m, (1.6, 1.4, 0.9), (0, 0, 0.45))


# ------------------------------------------------------------------ cable / pipe / hose reel

@register("Prop_RolledCable", S11, "Rolled cable: rubber coil with three amber straps and a plug end. 2.3 across, 0.6 tall.",
          ref=(REF, (970, 640, 1225, 800)))
def rolled_cable(m):
    rub, amber, light = m.slot("Rubber"), m.slot("Amber", "Metal"), m.slot("SteelLight")
    r_tube = 0.14
    r_tube = 0.16
    for k, (R, z) in enumerate(((0.98, 0.16), (0.68, 0.16), (0.83, 0.44))):
        pts = [(math.cos(a) * R, math.sin(a) * R, z) for a in [i / 16 * math.tau + k * 0.12 for i in range(17)]]
        rub.tube(pts, r_tube, seg=8)
    for a in (0.3, 2.4, 4.3):
        c, s = math.cos(a), math.sin(a)
        amber.box((0.72, 0.26, 0.74), loc=(c * 0.83, s * 0.83, 0.3), rot=(0, 0, math.degrees(a) + 90), bevel=0.05)
    # free end with a plug
    rub.tube([(0.95 * math.cos(-1.9), 0.95 * math.sin(-1.9), 0.14), (-0.5, -1.25, 0.12), (-0.9, -1.45, 0.12)], r_tube, seg=8)
    amber.cyl(0.18, 0.16, 0.35, seg=8, loc=(-1.05, -1.52, 0.12), rot=(0, 90, 25))
    light.cyl(0.05, 0.05, 0.3, seg=6, loc=(-1.3, -1.63, 0.12), rot=(0, 90, 25))
    _collider(m, (2.2, 2.2, 0.6), (0, 0, 0.3))


@register("Prop_BentPipe", S11, "Bent pipe module: U-shaped dark steel pipe with amber flange collars, standing on two bolted "
          "base plates. 3.2 x 1.3 x 2.6.", ref=(REF, (1255, 615, 1525, 795)))
def bent_pipe(m):
    frame, dark, amber, bolt = m.slot("Frame"), m.slot("FrameDark"), m.slot("Amber", "Metal"), m.slot("SteelLight")
    X, r = 1.05, 0.42
    pts = [(-X, 0, 0.3)] + [(-math.cos(a) * X, 0, 1.6 + math.sin(a) * X) for a in [i / 10 * math.pi for i in range(11)]] + [(X, 0, 0.3)]
    frame.tube(pts, r, seg=12)
    for sx in (-1, 1):
        dark.box((1.3, 1.3, 0.22), loc=(sx * X, 0, 0.11), bevel=0.05)
        for dx in (-1, 1):
            for dy in (-1, 1):
                bolt.bolt((sx * X + dx * 0.48, dy * 0.48, 0.22), r=0.07)
        amber.cyl(r + 0.1, r + 0.1, 0.26, seg=12, loc=(sx * X, 0, 0.45))
        amber.cyl(r + 0.08, r + 0.08, 0.22, seg=12, loc=(sx * X, 0, 1.45))
    amber.cyl(r + 0.08, r + 0.08, 0.26, seg=12, loc=(0, 0, 1.6 + X), rot=(0, 90, 0))
    _collider(m, (2 * X + 1.3, 1.3, 1.6 + X + r), (0, 0, (1.6 + X + r) / 2))


@register("Prop_HoseReel", S11, "Hose reel: dark steel stand, two side discs, amber hose wound on the drum (Drum piece, attrs "
          "Anim=Spin, Pivot on the axle, axis X), crank handle, hose end with nozzle. 2.6 x 1.6 x 1.9.", ref=(REF, (140, 810, 458, 990)))
def hose_reel(m):
    frame, dark, amber, slate = m.slot("Frame"), m.slot("FrameDark"), m.slot("Amber", "Metal"), m.slot("Slate")
    cz = 1.05
    for sx in (-1, 1):
        dark.box((0.25, 1.5, 0.22), loc=(sx * 0.85, 0, 0.11), bevel=0.04)
        dark.prism([(-0.6, 0), (0.6, 0), (0.18, cz), (-0.18, cz)], 0.2, loc=(sx * 0.85, 0, 0), rot=(0, 0, 90), bevel=0.03)
    dark.box((1.9, 0.25, 0.2), loc=(0, 0, 0.3), bevel=0.04)
    drum = m.piece("Drum", "Amber", material="Rubber", anim="Spin", pivot=(0, 0, cz), note="wound hose; spins about the axle (X)")
    drum.cyl(0.62, 0.62, 1.2, seg=14, loc=(0, 0, cz), rot=(0, 90, 0))
    for i in range(5):
        drum.cyl(0.72, 0.72, 0.17, seg=14, loc=(-0.48 + i * 0.24, 0, cz), rot=(0, 90, 0))
    for sx in (-1, 1):
        frame.cyl(0.84, 0.84, 0.12, seg=14, loc=(sx * 0.68, 0, cz), rot=(0, 90, 0), bevel=0.02)
        slate.cyl(0.25, 0.25, 0.22, seg=8, loc=(sx * 0.78, 0, cz), rot=(0, 90, 0))
    frame.cyl(0.08, 0.08, 2.2, seg=6, loc=(0, 0, cz), rot=(0, 90, 0))
    frame.box((0.12, 0.12, 0.7), loc=(1.15, 0, cz - 0.3), bevel=0.02)
    amber.cyl(0.1, 0.1, 0.5, seg=8, loc=(1.38, 0, cz - 0.6), rot=(0, 90, 0))
    hose = m.slot("Amber", "Rubber")
    hose.tube([(-0.3, -0.6, cz - 0.1), (-0.7, -1.0, 0.35), (-1.1, -1.05, 0.12), (-1.6, -0.9, 0.12)], 0.09, seg=8)
    slate.cyl(0.11, 0.08, 0.35, seg=8, loc=(-1.78, -0.84, 0.12), rot=(0, 90, -15))
    _collider(m, (2.0, 1.6, 2.0), (0, 0, 1.0))


# ------------------------------------------------------------------ placard / work light / spare plate

@register("Prop_WarningPlacard", S11, "Warning placard: amber A-frame sign with a dark warning triangle and an amber '!' on both "
          "faces, dark feet. 1.5 wide x 1.7 tall.", ref=(REF, (560, 825, 690, 980)))
def warning_placard(m):
    amber, slate, dark = m.slot("Amber"), m.slot("Slate"), m.slot("FrameDark")
    H, lean = 1.6, 14
    for sy in (-1, 1):
        a = math.radians(lean)
        y0 = sy * (math.sin(a) * H / 2 + 0.05)
        rot = (sy * lean, 0, 0)
        amber.box((1.4, 0.08, H), loc=(0, y0, H / 2 * math.cos(a) + 0.08), rot=rot, bevel=0.04)
        out = Vector((0, sy * math.cos(a), math.sin(a))) * 0.05
        c = Vector((0, y0, H / 2 * math.cos(a) + 0.02)) + out
        slate.prism([(-0.5, -0.38), (0.5, -0.38), (0.0, 0.5)], 0.04, loc=c, rot=rot)
        up = Vector((0, -sy * math.sin(a), math.cos(a)))   # along the leaning panel
        amber.box((0.12, 0.04, 0.36), loc=c + out * 0.7 + up * 0.05, rot=rot, bevel=0.0)
        amber.box((0.12, 0.04, 0.11), loc=c + out * 0.7 + up * -0.24, rot=rot, bevel=0.0)
        dark.box((1.5, 0.3, 0.14), loc=(0, sy * (math.sin(a) * H + 0.05), 0.07), bevel=0.03)
    dark.box((1.3, 0.25, 0.12), loc=(0, 0, H * math.cos(math.radians(lean)) + 0.08), bevel=0.03)


@register("Prop_WorkLight", S11, "Work light: dark housing with a 4-pane lens (Lens piece, Lamp) on an amber U-yoke, amber tube "
          "legs with rubber feet. 1.7 wide x 1.9 tall; add a SpotLight at attach `Light` (facing -Y).", ref=(REF, (865, 825, 1040, 985)))
def work_light(m):
    dark, amber, rub, frame = m.slot("FrameDark"), m.slot("Amber", "Metal"), m.slot("Rubber"), m.slot("Frame")
    hz = 1.25
    for sx in (-1, 1):
        amber.tube([(sx * 0.75, -0.55, 0.1), (sx * 0.75, 0.0, 0.5), (sx * 0.75, 0.55, 0.1)], 0.07, seg=8)
        amber.tube([(sx * 0.75, 0.0, 0.5), (sx * 0.75, 0.0, hz)], 0.07, seg=8)
        for sy in (-1, 1):
            rub.box((0.3, 0.3, 0.14), loc=(sx * 0.75, sy * 0.55, 0.07), bevel=0.04)
        dark.cyl(0.14, 0.14, 0.14, seg=8, loc=(sx * 0.72, 0, hz), rot=(0, 90, 0))
    dark.box((1.3, 0.5, 1.05), loc=(0, 0, hz), rot=(-8, 0, 0), bevel=0.08)
    frame.box((1.1, 0.08, 0.85), loc=(0, -0.26, hz + 0.03), rot=(-8, 0, 0), bevel=0.02)
    lens = m.piece("Lens", "Lamp", note="lit lens panes")
    for dx in (-0.25, 0.25):
        for dz in (-0.19, 0.19):
            lens.box((0.42, 0.06, 0.32), loc=(dx, -0.31, hz + dz + 0.03), rot=(-8, 0, 0), bevel=0.01)
    dark.box((0.5, 0.2, 0.12), loc=(0, 0, hz + 0.6), bevel=0.03)
    m.attach["Light"] = (0, -0.35, hz)


@register("Prop_SparePlate", S11, "Spare rock-processing plate: thick octagonal steel plate with a raised octagon, grooves and "
          "corner bolt holes, lying flat. 4.0 x 3.0 x 0.5.", ref=(REF, (1145, 830, 1525, 990)))
def spare_plate(m):
    steel, dark, light = m.slot("Steel"), m.slot("FrameDark"), m.slot("SteelLight")

    def octagon(w, d, c):
        return [(-w / 2 + c, -d / 2), (w / 2 - c, -d / 2), (w / 2, -d / 2 + c), (w / 2, d / 2 - c),
                (w / 2 - c, d / 2), (-w / 2 + c, d / 2), (-w / 2, d / 2 - c), (-w / 2, -d / 2 + c)]

    def slab(piece, w, d, c, z0, z1, bevel):
        pts = [Vector((x, y, z)) for x, y in octagon(w, d, c) for z in (z0, z1)]
        piece.hull(pts, bevel=bevel)

    slab(dark, 4.0, 3.0, 0.7, 0.0, 0.14, 0.03)
    slab(steel, 3.85, 2.85, 0.65, 0.1, 0.36, 0.06)
    slab(steel, 2.6, 1.7, 0.4, 0.3, 0.5, 0.06)
    for i in range(4):
        dark.box((2.2, 0.06, 0.03), loc=(0, -0.55 + i * 0.37, 0.505), bevel=0.0)
    for x, y in ((-1.55, 0), (1.55, 0), (-0.95, -1.15), (0.95, -1.15), (-0.95, 1.15), (0.95, 1.15)):
        dark.cyl(0.12, 0.12, 0.04, seg=8, loc=(x, y, 0.37))
        light.bolt((x * 0.82, y * 0.8, 0.36), r=0.07) if abs(y) > 0 else None
    _collider(m, (4.0, 3.0, 0.5), (0, 0, 0.25))
