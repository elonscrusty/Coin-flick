"""Sheet 07: Carry & crush station kit.

Table frame (Blender axes; Roblox = (-x, z, y)): the player works at the FRONT (-Y), the work top is
at z = 3.0, footprint about 7.2 x 3.6. Viewer's left (-X, Roblox +X = the player's left) holds the
input tray, the right (+X) the rubble bin and the basket dock. Attachable kit pieces are separate
models whose origin is their own bottom centre; the table records where each one sits (attach).
"""

import random

from mathutils import Vector

import ctrkit as K
from ctrkit import register

S07 = "07"
REF = "07_station_kit.png"
TOP = 2.5


def _rock(piece, seed, s, loc, shape="round"):
    piece.hull(K.rock_points(seed, (s, s * 0.95, s * 0.85), n=20, shape=shape), loc=loc, rot=(0, 0, seed * 37 % 360))


# ------------------------------------------------------------------ table

def table(m):
    """Pass 2 (docs/m4/QUARRY.md): a long, low, solid wooden work unit with dark steel corner posts and
    straps (the owner's quarry placement target): plank body on a dark plinth, steel rim, nameplate on
    the front, a wooden basket crate at the player's right end (Blender +X). Top at z = 3.0."""
    wood, wdark, frame = m.slot("Wood"), m.slot("WoodDark"), m.slot("Frame")
    dark, bolt = m.slot("FrameDark"), m.slot("SteelLight")
    W, D = 7.2, 3.5
    H = TOP
    # plinth + plank body
    dark.box((W - 0.2, D - 0.2, 0.3), loc=(0, 0, 0.15), bevel=0.05)
    wood.box((W - 0.3, D - 0.3, H - 0.55), loc=(0, 0, 0.3 + (H - 0.55) / 2), bevel=0.06)
    # vertical plank grooves on the four faces
    for sy in (-1, 1):
        for i in range(-3, 4):
            wdark.box((0.05, 0.07, H - 1.0), loc=(i * 0.85, sy * (D / 2 - 0.13), 1.25), bevel=0.0)
    for sx in (-1, 1):
        for i in (-1, 0, 1):
            wdark.box((0.07, 0.05, H - 1.0), loc=(sx * (W / 2 - 0.13), i * 0.85, 1.25), bevel=0.0)
    # top slab with plank seams and a steel rim
    wood.box((W, D, 0.34), loc=(0, 0, H - 0.17), bevel=0.06)
    for i in (-1, 0, 1):
        wdark.box((W - 0.7, 0.04, 0.03), loc=(0, i * 0.85, H + 0.005), bevel=0.0)
    for sy in (-1, 1):
        frame.box((W - 0.3, 0.2, 0.14), loc=(0, sy * (D / 2 - 0.1), H + 0.02), bevel=0.03)
    for sx in (-1, 1):
        frame.box((0.2, D - 0.3, 0.14), loc=(sx * (W / 2 - 0.1), 0, H + 0.02), bevel=0.03)
    # steel corner posts with caps, straps and bolts
    for sx in (-1, 1):
        for sy in (-1, 1):
            cx, cy = sx * (W / 2 - 0.27), sy * (D / 2 - 0.27)
            frame.box((0.62, 0.62, H + 0.04), loc=(cx, cy, (H + 0.04) / 2), bevel=0.07)
            dark.box((0.72, 0.72, 0.16), loc=(cx, cy, 0.08), bevel=0.05)
            for z in (0.5, 1.4, 2.2):
                bolt.bolt((cx, sy * (D / 2 + 0.03), z), normal=(0, sy, 0), r=0.08)
                bolt.bolt((sx * (W / 2 + 0.03), cy, z), normal=(sx, 0, 0), r=0.08)
            bolt.bolt((cx, cy, H + 0.1), normal=(0, 0, 1), r=0.1)
    # two horizontal straps along the front, back and ends
    for z in (0.7, 1.75):
        for sy in (-1, 1):
            frame.box((W - 1.0, 0.07, 0.24), loc=(0, sy * (D / 2 - 0.1), z), bevel=0.02)
        for sx in (-1, 1):
            frame.box((0.07, D - 1.0, 0.24), loc=(sx * (W / 2 - 0.1), 0, z), bevel=0.02)
    # nameplate (accent) in a steel frame on the front
    ny = -D / 2 - 0.02
    frame.box((1.9, 0.08, 0.78), loc=(0, ny + 0.03, 1.25), bevel=0.03)
    m.slot("Accent", "Metal").box((1.7, 0.08, 0.58), loc=(0, ny - 0.01, 1.25), bevel=0.03)
    m.attach["Nameplate"] = (0, ny - 0.06, 1.25)
    # wooden basket crate on the floor at the player's right end
    crate_at = Vector((W / 2 + 0.95, -0.1, 0))
    basket(m, crate_at, scale=0.8)
    m.attach["Dock"] = (crate_at.x, crate_at.y, 1.0)
    m.attach["ToolHook1"] = (-1.7, -D / 2 - 0.1, 1.75)
    m.attach["ToolHook2"] = (-1.2, -D / 2 - 0.1, 1.75)
    # work-top attachment points (kit models sit here, origin = their bottom centre)
    m.attach["Plate"] = (0.15, -0.05, TOP)
    m.attach["InputTray"] = (-2.35, -0.25, TOP)
    m.attach["RubbleBin"] = (2.35, -0.15, TOP)
    m.attach["Shield"] = (-0.35, D / 2 - 0.35, TOP)
    m.attach["Beacon"] = (2.95, D / 2 - 0.3, TOP + 0.04)
    m.attach["Stand"] = (0, -D / 2 - 3.2, 0)
    m.attach["MachineFeed"] = (0, D / 2 + 1.0, TOP)
    m.extra["top"] = TOP
    m.extra["collider"] = {"size": K.roblox_size((W, D, TOP)), "offset": K.to_roblox((0, 0, TOP / 2))}


@register("Station_Table", S07, "Crushing table body: plank top, steel caps/legs/feet, braces, bolts, nameplate, hooks, dock arm. Kit pieces attach at the recorded points.",
          ref=(REF, (10, 45, 1530, 470)))
def station_table(m):
    table(m)


@register("Station_Assembled", S07, "PREVIEW ONLY reference: the table with every kit piece placed at its attach point (not for upload; the game assembles the kit).",
          ref=(REF, (10, 45, 1530, 470)))
def station_assembled(m):
    table(m)
    at = {k: Vector(v) for k, v in m.attach.items()}
    for p in m.pieces:
        p.preview = True
    plate(m, at["Plate"], preview=True)
    input_tray(m, at["InputTray"], preview=True)
    rubble_bin(m, at["RubbleBin"], preview=True, fill=True)
    shield(m, at["Shield"], preview=True)
    beacon(m, at["Beacon"], preview=True)
    basket(m, at["Dock"] - Vector((0, 0, 1.5)), preview=True, scale=0.7)
    rk = m.preview_piece("PreviewRocks", "Rock")
    _rock(rk, 5, 1.05, at["Plate"] + Vector((0, 0, 0.32)))
    for i, (x, y) in enumerate(((-0.4, 0.2), (0.35, 0.25), (0.1, -0.3))):
        _rock(rk, 11 + i, 0.62, at["InputTray"] + Vector((x, y, 0.2)))
    m.extra["preview_only"] = True


# ------------------------------------------------------------------ kit pieces (each origin = bottom centre)

def _pp(m, name, slot, preview, material=None):
    """Piece helper: shared slot piece normally, or a preview-only copy inside the assembly."""
    if preview:
        return m.preview_piece("P_" + name + "_" + slot + (material or ""), slot)
    return m.slot(slot, material)


def plate(m, at=(0, 0, 0), preview=False):
    """Crush plate: steel slab (top at 0.3, the rock rests there) inside a raised yellow / black hazard
    border (pass 2, owner's quarry target)."""
    at = Vector(at)
    steel, bolt, dark = _pp(m, "Plate", "Steel", preview), _pp(m, "Plate", "SteelLight", preview), _pp(m, "Plate", "FrameDark", preview)
    amber, slate = _pp(m, "Plate", "Amber", preview), _pp(m, "Plate", "Slate", preview)
    w, d = 2.7, 2.1
    dark.box((w + 0.12, d + 0.12, 0.12), loc=at + Vector((0, 0, 0.06)), bevel=0.04)
    steel.box((w, d, 0.2), loc=at + Vector((0, 0, 0.2)), bevel=0.05)
    # hazard border: alternating amber / black blocks around the plate edge, standing 0.03 proud of the slab
    bw, seg = 0.26, 0.4
    z = 0.315
    for axis, length, off in (("x", w - 0.04, d / 2 - bw / 2 - 0.02), ("x", w - 0.04, -(d / 2 - bw / 2 - 0.02)),
                              ("y", d - 2 * bw - 0.08, w / 2 - bw / 2 - 0.02), ("y", d - 2 * bw - 0.08, -(w / 2 - bw / 2 - 0.02))):
        n = max(2, round(length / seg))
        step = length / n
        for i in range(n):
            c = -length / 2 + step * (i + 0.5)
            piece = amber if i % 2 == 0 else slate
            if axis == "x":
                piece.box((step - 0.01, bw, 0.06), loc=at + Vector((c, off, z)), bevel=0.0)
            else:
                piece.box((bw, step - 0.01, 0.06), loc=at + Vector((off, c, z)), bevel=0.0)
    for sx in (-1, 1):
        for sy in (-1, 1):
            bolt.bolt(at + Vector((sx * (w / 2 + 0.0), sy * (d / 2 - 0.5), 0.2)), normal=(sx, 0, 0), r=0.07)


@register("Station_AnvilPlate", S07, "Anvil plate, origin bottom centre; rocks rest on top at y 0.3.", ref=(REF, (500, 545, 705, 705)))
def station_plate(m):
    plate(m)
    m.attach["Rock"] = (0, 0, 0.3)


def tray_box(m, name, at, size, preview, wall=0.2, stripes=False, tilt=0):
    """Wooden bin with dark steel corner posts and a steel top rim (pass 2): plank walls, dark floor."""
    at = Vector(at)
    wood, wdark = _pp(m, name, "Wood", preview), _pp(m, name, "WoodDark", preview)
    frame, dark, bolt = _pp(m, name, "Frame", preview), _pp(m, name, "FrameDark", preview), _pp(m, name, "SteelLight", preview)
    w, d, h = size
    rot = (tilt, 0, 0)
    from mathutils import Euler, Matrix
    R = Euler([__import__("math").radians(a) for a in rot], "XYZ").to_matrix()

    def P(x, y, z):
        return at + R @ Vector((x, y, z))

    dark.box((w - 2 * wall + 0.02, d - 2 * wall + 0.02, 0.12), loc=P(0, 0, 0.08), rot=rot, bevel=0.03)
    wood.box((w, wall, h), loc=P(0, -d / 2 + wall / 2, h / 2), rot=rot, bevel=0.04)
    wood.box((w, wall, h), loc=P(0, d / 2 - wall / 2, h / 2), rot=rot, bevel=0.04)
    wood.box((wall, d - 0.05, h), loc=P(-w / 2 + wall / 2, 0, h / 2), rot=rot, bevel=0.04)
    wood.box((wall, d - 0.05, h), loc=P(w / 2 - wall / 2, 0, h / 2), rot=rot, bevel=0.04)
    # plank seams on the long faces
    for sy in (-1, 1):
        wdark.box((w - 0.5, 0.03, 0.04), loc=P(0, sy * (d / 2 + 0.005), h * 0.5), rot=rot, bevel=0.0)
    # steel corner posts, top rim on the long sides, bolts
    for sx in (-1, 1):
        for sy in (-1, 1):
            frame.box((0.34, 0.34, h + 0.06), loc=P(sx * (w / 2 - 0.12), sy * (d / 2 - 0.12), (h + 0.06) / 2), rot=rot, bevel=0.05)
            bolt.bolt(P(sx * (w / 2 - 0.13), sy * (d / 2 + 0.06), h - 0.16), normal=R @ Vector((0, sy, 0)), r=0.065)
            bolt.bolt(P(sx * (w / 2 + 0.06), sy * (d / 2 - 0.13), h - 0.16), normal=R @ Vector((sx, 0, 0)), r=0.065)
    for sy in (-1, 1):
        frame.box((w - 0.5, 0.1, 0.1), loc=P(0, sy * (d / 2 - 0.05), h), rot=rot, bevel=0.02)
    for sx in (-1, 1):
        frame.box((0.1, d - 0.5, 0.1), loc=P(sx * (w / 2 - 0.05), 0, h), rot=rot, bevel=0.02)
    return P


def input_tray(m, at=(0, 0, 0), preview=False, tilt=0):
    return tray_box(m, "Tray", at, (2.1, 1.65, 0.8), preview, tilt=tilt)


def rubble_bin(m, at=(0, 0, 0), preview=False, fill=False):
    P = tray_box(m, "Bin", at, (2.1, 1.65, 0.8), preview)
    if fill:
        rp = m.preview_piece("P_BinRubble", "Rock") if preview else m.piece("Fill", "Rock", note="rubble fill; show / raise as the bin fills")
        rp.box((1.72, 1.28, 0.2), loc=P(0, 0, 0.22), bevel=0.04)
        K.scatter_rocks(rp, 26, (-0.85, -0.6, 0.85, 0.6), (0.18, 0.32), seed=7, z=0.28, origin=P(0, 0, 0))


@register("Station_InputTray", S07, "Input tray (queued rocks), hazard stripes on the front, origin bottom centre. Accent = stripes.",
          ref=(REF, (15, 500, 268, 705)))
def station_input_tray(m):
    input_tray(m)
    for i, (x, y) in enumerate(((-0.45, 0.2), (0.4, 0.25), (0.05, -0.3))):
        _rock(m.preview_piece("PreviewRocks", "Rock"), 11 + i, 0.62, (x, y, 0.16))
    m.attach["Slots"] = (0, 0, 0.16)


@register("Station_RubbleBin", S07, "Rubble (output) bin with a separate Fill piece (rubble heap, hide when empty), origin bottom centre.",
          ref=(REF, (270, 515, 505, 705)))
def station_rubble_bin(m):
    rubble_bin(m, fill=True)
    m.attach["Output"] = (0, 0, 0.3)


def shield(m, at=(0, 0, 0), preview=False):
    at = Vector(at)
    frame, bolt = _pp(m, "Shield", "Frame", preview), _pp(m, "Shield", "SteelLight", preview)
    glass = m.preview_piece("P_ShieldGlass", "GlassClear") if preview else m.piece("Glass", "GlassClear", transparency=0.45,
                                                                                note="clear shield pane, Glass material, transparency 0.45")
    if preview:
        glass.transparency = 0.45
        glass.material = "Glass"
    w, h = 3.1, 1.45
    gx0 = at.x
    # pane with clipped top corners
    prof = [(-w / 2, 0), (w / 2, 0), (w / 2, h - 0.35), (w / 2 - 0.35, h), (-w / 2 + 0.2, h), (-w / 2, h - 0.2)]
    glass.prism(prof, 0.08, loc=at + Vector((0, 0, 0.55)))
    # left post: bent pipe from the table top over to the pane; right post: square post + clamp
    lx = gx0 - w / 2 - 0.22
    frame.box((0.45, 0.45, 0.16), loc=at + Vector((-w / 2 - 0.22, 0, 0.08)), bevel=0.04)
    frame.tube([at + Vector((-w / 2 - 0.22, 0, 0.1)), at + Vector((-w / 2 - 0.22, 0, 1.55)),
                at + Vector((-w / 2 - 0.05, 0, 1.75)), at + Vector((-w / 2 + 0.15, 0, 1.75))], 0.09, seg=8)
    frame.box((0.36, 0.3, 1.9), loc=at + Vector((w / 2 + 0.16, 0, 0.95)), bevel=0.05)
    for z in (0.75, 1.55):
        frame.box((0.42, 0.26, 0.2), loc=at + Vector((-w / 2 - 0.08, 0, z)), bevel=0.04)
        frame.box((0.36, 0.26, 0.2), loc=at + Vector((w / 2 - 0.02, 0, z)), bevel=0.04)
        bolt.bolt(at + Vector((w / 2 + 0.16, -0.16, z)), normal=(0, -1, 0), r=0.06)
    _ = lx


@register("Station_Shield", S07, "Amber shield glass on two steel posts (left bent pipe), origin bottom centre of the pane line. Glass piece separate (Glass, transparency 0.45).",
          ref=(REF, (740, 75, 1010, 175)))
def station_shield(m):
    shield(m)


def beacon(m, at=(0, 0, 0), preview=False):
    at = Vector(at)
    frame, dark = _pp(m, "Beacon", "Frame", preview), _pp(m, "Beacon", "FrameDark", preview)
    lens = m.preview_piece("P_BeaconLens", "Lamp") if preview else m.piece("Lens", "Lamp", anim="Blink",
                                                                          note="beacon lens, Neon; recolour per station state, blink/spin")
    if preview:
        lens.material = "Neon"
    frame.box((0.42, 0.42, 0.14), loc=at + Vector((0, 0, 0.07)), bevel=0.04)
    frame.box((0.24, 0.24, 0.95), loc=at + Vector((0, 0, 0.55)), bevel=0.04)
    dark.cyl(0.24, 0.26, 0.16, seg=8, loc=at + Vector((0, 0, 1.08)), bevel=0.03)
    lens.cyl(0.2, 0.18, 0.42, seg=8, loc=at + Vector((0, 0, 1.37)), bevel=0.03)
    dark.cyl(0.23, 0.15, 0.12, seg=8, loc=at + Vector((0, 0, 1.64)), bevel=0.02)
    for a in range(4):
        import math
        x, y = math.cos(a * math.pi / 2 + math.pi / 4) * 0.22, math.sin(a * math.pi / 2 + math.pi / 4) * 0.22
        dark.box((0.05, 0.05, 0.42), loc=at + Vector((x, y, 1.37)), bevel=0.0)


@register("Station_Beacon", S07, "Beacon lamp on a post; Lens piece (Neon, Blink) is separate, origin bottom centre. Light point = lens centre.",
          ref=(REF, (1005, 70, 1065, 180)))
def station_beacon(m):
    beacon(m)
    m.attach["Light"] = (0, 0, 1.37)


def basket(m, at=(0, 0, 0), preview=False, scale=1.0, filled=False):
    at = Vector(at)
    wood, frame, bolt = _pp(m, "Basket", "Wood", preview), _pp(m, "Basket", "Frame", preview), _pp(m, "Basket", "SteelLight", preview)
    s = scale
    w, d, h = 2.0 * s, 1.6 * s, 1.2 * s
    t = 0.14 * s

    def V(x, y, z):
        return at + Vector((x, y, z))

    wood.box((w - 0.1 * s, d - 0.1 * s, 0.14 * s), loc=V(0, 0, 0.1 * s), bevel=0.03)
    # slatted walls: two boards per side with a groove
    for k in range(2):
        z = 0.12 * s + (k + 0.5) * (h - 0.12 * s) / 2
        bh = (h - 0.12 * s) / 2 - 0.03 * s
        wood.box((w - 0.2 * s, t, bh), loc=V(0, -d / 2 + t / 2, z), bevel=0.035)
        wood.box((w - 0.2 * s, t, bh), loc=V(0, d / 2 - t / 2, z), bevel=0.035)
        wood.box((t, d - 0.2 * s, bh), loc=V(-w / 2 + t / 2, 0, z), bevel=0.035)
        wood.box((t, d - 0.2 * s, bh), loc=V(w / 2 - t / 2, 0, z), bevel=0.035)
    # steel corner straps, top rim band, bottom band
    for sx in (-1, 1):
        for sy in (-1, 1):
            frame.box((0.26 * s, 0.26 * s, h + 0.04 * s), loc=V(sx * (w / 2 - 0.06 * s), sy * (d / 2 - 0.06 * s), h / 2), bevel=0.04 * s)
            for z in (0.25 * s, h - 0.22 * s):
                bolt.bolt(V(sx * (w / 2 - 0.06 * s), sy * (d / 2 + 0.07 * s), z), normal=(0, sy, 0), r=0.06 * s)
    for sy in (-1, 1):
        frame.box((w - 0.2 * s, 0.1 * s, 0.14 * s), loc=V(0, sy * (d / 2 + 0.01 * s), h - 0.05 * s), bevel=0.03 * s)
    for sx in (-1, 1):
        frame.box((0.1 * s, d - 0.2 * s, 0.14 * s), loc=V(sx * (w / 2 + 0.01 * s), 0, h - 0.05 * s), bevel=0.03 * s)
    # bail handle: pivots on the side walls, square steel bar arching over (along X)
    hz = h + 0.95 * s
    for sx in (-1, 1):
        frame.box((0.12 * s, 0.34 * s, 0.34 * s), loc=V(sx * (w / 2 + 0.07 * s), 0, h - 0.3 * s), bevel=0.03 * s)
    frame.box_between(V(-w / 2 - 0.1 * s, 0, h - 0.3 * s), V(-w / 2 - 0.1 * s, 0, hz - 0.12 * s), (0.17 * s, 0.22 * s))
    frame.box_between(V(w / 2 + 0.1 * s, 0, h - 0.3 * s), V(w / 2 + 0.1 * s, 0, hz - 0.12 * s), (0.17 * s, 0.22 * s))
    frame.box((w + 0.37 * s, 0.24 * s, 0.24 * s), loc=V(0, 0, hz), bevel=0.06 * s)
    if filled:
        rocks = m.preview_piece("P_BasketRocks", "Rock") if preview else m.piece("Rocks", "Rock", note="5 rocks; hide for the empty look")
        for i, (x, y, z, r) in enumerate(((-0.45, -0.3, 0.55, 0.78), (0.45, -0.28, 0.55, 0.78), (0.0, 0.33, 0.6, 0.8),
                                          (-0.22, -0.02, 0.98, 0.74), (0.3, 0.1, 1.0, 0.72))):
            _rock(rocks, 40 + i * 7, r * s, V(x * s, y * s, z * s - 0.1 * r * s))
    return hz


@register("Basket_Empty", S07, "Carry basket (wood slats, steel straps, bail handle), origin bottom centre; Grip attach = handle top centre.",
          ref=(REF, (30, 735, 255, 975)))
def basket_empty(m):
    hz = basket(m)
    m.attach["Grip"] = (0, 0, hz)


@register("Basket_Filled", S07, "Carry basket with 5 rocks (Rocks piece separate), origin bottom centre; Grip attach = handle top centre.",
          ref=(REF, (290, 735, 530, 975)))
def basket_filled(m):
    hz = basket(m, filled=True)
    m.attach["Grip"] = (0, 0, hz)


@register("Station_BasketDock", S07, "Wall/table basket dock: back plate + cup bracket, origin bottom centre of the back plate.",
          ref=(REF, (725, 535, 865, 705)))
def basket_dock(m):
    frame, dark, bolt = m.slot("Frame"), m.slot("FrameDark"), m.slot("SteelLight")
    frame.box((1.2, 0.3, 1.9), loc=(0.15, 0.3, 0.95), bevel=0.08)
    for x in (-0.25, 0.55):
        for z in (0.35, 1.6):
            bolt.bolt((x, 0.14, z), normal=(0, -1, 0), r=0.08)
    # cup: U-shaped open box in front of the plate
    dark.box((1.2, 0.95, 0.12), loc=(-0.05, -0.32, 0.55), bevel=0.04)
    frame.box((1.2, 0.16, 0.6), loc=(-0.05, -0.72, 0.8), bevel=0.05)
    frame.box((0.16, 0.95, 0.6), loc=(-0.6, -0.32, 0.8), bevel=0.05)
    frame.box((0.16, 0.95, 0.6), loc=(0.5, -0.32, 0.8), bevel=0.05)
    frame.box((1.2, 0.5, 0.25), loc=(-0.05, -0.15, 0.4), bevel=0.04)
    m.attach["Basket"] = (-0.05, -0.32, 0.62)


@register("Station_Sign", S07, "Station sign: framed dark panel with a cream rock icon on a post, origin bottom centre. Border = Accent.",
          ref=(REF, (895, 530, 1020, 705)))
def station_sign(m):
    frame, dark = m.slot("Frame"), m.slot("Slate")
    frame.box((0.34, 0.34, 0.2), loc=(0, 0, 0.1), bevel=0.04)
    frame.box((0.22, 0.22, 1.7), loc=(0, 0, 0.95), bevel=0.04)
    acc = m.slot("Accent", "Metal")
    acc.box((1.7, 0.16, 1.3), loc=(0, 0, 2.3), bevel=0.06)
    dark.box((1.46, 0.06, 1.06), loc=(0, -0.08, 2.3), bevel=0.03)
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.slot("SteelLight").bolt((sx * 0.72, -0.09, 2.3 + sz * 0.52), normal=(0, -1, 0), r=0.045)
    icon = m.slot("Cream")
    pts = K.rock_points(9, (0.75, 0.22, 0.68), n=14)
    icon.hull([Vector((p.x, p.y * 0.5, p.z)) for p in pts], loc=(0, -0.13, 1.96))
    m.attach["Face"] = (0, -0.12, 2.3)


@register("Station_LoadingChute", S07, "Loading chute: steel hopper + sloped trough on a wooden A-frame, origin floor centre; rocks enter the hopper (attach In) and leave at Out.",
          ref=(REF, (1030, 465, 1240, 705)))
def loading_chute(m):
    frame, dark, wood, bolt = m.slot("Frame"), m.slot("FrameDark"), m.slot("Wood"), m.slot("SteelLight")
    import math
    L, ang = 4.4, 38.0
    a = math.radians(ang)
    lo = Vector((0, -L / 2 * math.cos(a), 0.35))
    hi = Vector((0, L / 2 * math.cos(a), 0.35 + L * math.sin(a)))
    mid = (lo + hi) / 2
    # trough: floor + two side walls, tilted about X
    rot = (ang, 0, 0)
    dark.box((1.3, L, 0.12), loc=mid, rot=rot, bevel=0.03)
    for sx in (-1, 1):
        frame.box((0.14, L, 0.55), loc=mid + Vector((sx * 0.72, 0, 0.2)), rot=rot, bevel=0.04)
    # lip at the bottom
    frame.box((1.58, 0.2, 0.32), loc=lo + Vector((0, -0.05, 0.05)), bevel=0.04)
    # hopper at the top: open flared box (floor + four walls leaning outward)
    top = hi + Vector((0, 0.3, 0.2))
    dark.box((1.3, 1.0, 0.12), loc=top, bevel=0.03)
    for sy in (-1, 1):
        frame.box((1.7, 0.14, 0.9), loc=top + Vector((0, sy * 0.62, 0.42)), rot=(sy * -14, 0, 0), bevel=0.04)
    for sx in (-1, 1):
        frame.box((0.14, 1.35, 0.9), loc=top + Vector((sx * 0.78, 0, 0.42)), rot=(0, sx * 14, 0), bevel=0.04)
    for sx in (-1, 1):
        bolt.bolt(top + Vector((sx * 0.55, -0.75, 0.5)), normal=(0, -1, 0), r=0.06)
    # wooden A-frame support behind / under the high end
    yb = hi.y - 0.2
    for sx in (-1, 1):
        wood.box_between((sx * 0.55, yb + 0.6, 0.0), (sx * 0.55, yb - 0.05, hi.z - 0.1), (0.3, 0.3), bevel=0.04)
        wood.box((0.42, 0.42, 0.18), loc=(sx * 0.55, yb + 0.6, 0.09), bevel=0.04)
    wood.box((1.4, 0.26, 0.26), loc=(0, yb + 0.3, hi.z * 0.5), bevel=0.04)
    frame.box((1.2, 0.4, 0.42), loc=(0, lo.y + 0.45, 0.21), bevel=0.04)
    m.attach["In"] = tuple(top + Vector((0, 0, 0.3)))
    m.attach["Out"] = tuple(lo + Vector((0, -0.2, 0.2)))
    _ = random


@register("Station_FloorPad", S07, "Station floor pad: dark steel plate, raised rim, hazard-stripe border (Accent), origin floor centre; top at y 0.3.",
          ref=(REF, (1250, 550, 1525, 705)))
def floor_pad(m):
    frame, dark, steel, acc, sl = m.slot("Frame"), m.slot("FrameDark"), m.slot("Steel"), m.slot("Accent"), m.slot("Slate")
    W, D = 10.0, 7.0
    dark.box((W, D, 0.22), loc=(0, 0, 0.11), bevel=0.08)
    band = 0.55
    # inner plate (2 panels with a seam)
    for sx in (-1, 1):
        frame.box((W / 2 - band - 0.18, D - 2 * band - 0.3, 0.1), loc=(sx * (W / 4 - band / 2 + 0.03), 0, 0.26), bevel=0.04)
    # hazard border on the top face: dark band + amber diagonal stripes
    for sy in (-1, 1):
        sl.box((W - 0.2, band, 0.06), loc=(0, sy * (D / 2 - band / 2 - 0.1), 0.25), bevel=0.02)
        K.hazard_stripes(acc, W - 0.2, band, (0, sy * (D / 2 - band / 2 - 0.1), 0.29), rot=(90, 0, 0), count=11, slant=0.9,
                         depth=0.03, margin=0.03)
    for sx in (-1, 1):
        sl.box((band, D - 2 * band - 0.2, 0.06), loc=(sx * (W / 2 - band / 2 - 0.1), 0, 0.25), bevel=0.02)
        K.hazard_stripes(acc, D - 2 * band - 0.2, band, (sx * (W / 2 - band / 2 - 0.1), 0, 0.29), rot=(90, 0, 90), count=7,
                         slant=0.9, depth=0.03, margin=0.03)
    m.extra["top"] = 0.3
    _ = steel
