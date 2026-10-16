"""Sheets 09 + 10: crushing machines (Auto Cracker, Hydraulic Press, Industrial Crusher).

Common frame (Blender axes; Roblox = (-x, z, y)): origin = floor centre of the machine, the FRONT (output side,
where the player stands) faces -Y, the long axis runs along X. Footprint is about 7.5-7.8 x 3.9-5.1 studs, so one machine
fits a station bay beside the 7 x 3.5 Station_Table (table work top z = 3.0, machines are 4 to 6.5 studs tall).

MOVING PARTS are separate pieces (= separate MeshParts, attributes Anim + Pivot, see MeshService). Joint pivots
and travel are recorded as attach points (Roblox studs from the model origin) and in the manifest `motion`
field, so the game can animate them without guessing. Everything else is static.
"""

import math

from mathutils import Euler, Vector

import ctrkit as K
from ctrkit import register

S09, S10 = "09", "10"
REF9, REF10 = "09_auto_cracker_kit.png", "10_advanced_processor_kit.png"


def _R(rot):
    return Euler([math.radians(a) for a in rot], "XYZ").to_matrix()


def xcyl(piece, r, length, c, seg=8, r2=None, bevel=0.0):
    """Cylinder along X centred at c (r at -X end, r2 at +X end)."""
    piece.cyl(r, r if r2 is None else r2, length, seg=seg, loc=c, rot=(0, 90, 0), bevel=bevel)


def ycyl(piece, r, length, c, seg=8, bevel=0.0):
    piece.cyl(r, r, length, seg=seg, loc=c, rot=(90, 0, 0), bevel=bevel)


def ui_face(m, at, tilt=0.0, w=0.9, h=0.8, buttons=("Red",), screen=True, bolts=True):
    """Control face: dark bezel, glowing yellow screen, round buttons. Local frame: x right, z up the face, -y outward;
    `tilt` turns the face about X (negative = leans back, face looks up)."""
    at = Vector(at)
    Rm = _R((tilt, 0, 0))

    def P(x, z, y=0.0):
        return at + Rm @ Vector((x, y, z))

    rot = (tilt, 0, 0)
    dk, lamp, sl = m.slot("FrameDark"), m.slot("Lamp"), m.slot("SteelLight")
    dk.box((w, 0.12, h), loc=P(0, 0), rot=rot, bevel=0.035)
    if screen:
        lamp.box((w * 0.66, 0.07, h * 0.42), loc=P(0, h * 0.2, -0.07), rot=rot, bevel=0.02)
    cols = {"Red": m.slot("Red"), "Green": m.slot("Green"), "Amber": m.slot("Amber")}
    n = len(buttons)
    for i, b in enumerate(buttons):
        x = (i - (n - 1) / 2) * 0.34 if n > 1 else 0.12
        cols[b].cyl(0.12, 0.1, 0.1, seg=8, loc=P(x, -h * 0.3, -0.09), rot=(tilt + 90, 0, 0), bevel=0.015)
    if n == 1:
        cols["Amber"].box((0.14, 0.08, 0.14), loc=P(-0.2, -h * 0.3, -0.08), rot=rot, bevel=0.02)
    if bolts:
        for sx in (-1, 1):
            for sz in (-1, 1):
                sl.bolt(P(sx * (w / 2 - 0.07), sz * (h / 2 - 0.07), -0.06), normal=Rm @ Vector((0, -1, 0)), r=0.04, h=0.04)


def lattice(piece, x0, x1, z0, z1, y, pitch=0.3, r=0.03):
    """Diamond mesh: 45 degree bars clipped to a rectangle (x, z) at depth y."""
    for sgn in (1, -1):
        k = z0 - sgn * x1 if sgn == 1 else z0 - sgn * x1
        kmin, kmax = min(z0 - sgn * x1, z0 - sgn * x0), max(z1 - sgn * x0, z1 - sgn * x1)
        k = kmin + pitch / 2
        while k < kmax:
            xa, xb = (z0 - k) * sgn, (z1 - k) * sgn
            lo, hi = max(min(xa, xb), x0), min(max(xa, xb), x1)
            if hi - lo > 0.1:
                piece.box_between((lo, y, sgn * lo + k), (hi, y, sgn * hi + k), (r * 2, r * 2), bevel=0.0)
            k += pitch


def octagon(w, h, cut):
    return [(-w / 2 + cut, -h / 2), (w / 2 - cut, -h / 2), (w / 2, -h / 2 + cut), (w / 2, h / 2 - cut),
            (w / 2 - cut, h / 2), (-w / 2 + cut, h / 2), (-w / 2, h / 2 - cut), (-w / 2, -h / 2 + cut)]


def ring_hull(piece, x0, r0, x1, r1, yc, zc, n=8, rot_off=22.5, bevel=0.04):
    """Faceted drum along X from x0 (radius r0) to x1 (radius r1) around axis (yc, zc)."""
    pts = []
    for x, r in ((x0, r0), (x1, r1)):
        for k in range(n):
            a = math.radians(rot_off + k * 360 / n)
            pts.append(Vector((x, yc + r * math.cos(a), zc + r * math.sin(a))))
    piece.hull(pts, bevel=bevel)


def rubble(piece, count, area, size, seed, z, origin=(0, 0, 0)):
    piece.box((area[2] - area[0] - 0.1, area[3] - area[1] - 0.1, 0.16), loc=(Vector(origin) + Vector(((area[0] + area[2]) / 2, (area[1] + area[3]) / 2, z - 0.1))),
              bevel=0.03)
    K.scatter_rocks(piece, count, area, size, seed=seed, z=z, origin=origin)


def prev_rock(m, seed, s, loc):
    m.preview_piece("PreviewRocks", "Rock").hull(K.rock_points(seed, (s, s * 0.95, s * 0.85), n=20), loc=loc, rot=(0, 0, seed * 37 % 360))


# ====================================================================== 09 AUTO CRACKER

B9 = 0.65   # top of the base slab


@register("Auto_Cracker", S09,
          "Auto cracker: base, feed roller conveyor (-X), cracking chamber with JawL/JawR (separate, slide along X), hood window, motor (+X), "
          "control panel, output rubble bin + Fill. Front -Y.",
          ref=(REF9, (10, 45, 1530, 420)))
def auto_cracker(m):
    con, fr, dk = m.slot("Concrete"), m.slot("Frame"), m.slot("FrameDark")
    steel, sl, am, rub = m.slot("Steel"), m.slot("SteelLight"), m.slot("Amber"), m.slot("Rubber")
    wood, slate = m.slot("Wood"), m.slot("Slate")
    hw = wood   # housing in timber
    CZ = 2.3    # jaw axis height
    JY = 0.1
    # ---- base slab, feet, front pad
    con.box((7.4, 3.0, 0.45), loc=(0, 0, 0.2 + 0.225), bevel=0.07)
    con.box((3.2, 1.7, 0.45), loc=(0, -2.15, 0.2 + 0.225), bevel=0.07)
    for sx in (-1, 1):
        for sy, ys in ((-1, -1.2), (1, 1.2)):
            dk.box((0.95, 0.7, 0.2), loc=(sx * 3.1, sy * 1.15, 0.1), bevel=0.04)
    for sx in (-1, 1):
        dk.box((0.95, 0.7, 0.2), loc=(sx * 1.2, -2.7, 0.1), bevel=0.04)
    # ---- cracking chamber housing (cream walls, open front, dark liner)
    for sx in (-1, 1):
        hw.box((0.5, 2.4, 3.05), loc=(sx * 1.5, 0, B9 + 1.525), bevel=0.07)
    hw.box((2.5, 0.6, 3.05), loc=(0, 0.9, B9 + 1.525), bevel=0.06)
    hw.box((3.5, 2.4, 0.5), loc=(0, 0, 3.45), bevel=0.09)
    hw.prism([(-1.2, 0), (1.2, 0), (1.2, 0.15), (0.6, 0.35), (-0.6, 0.35), (-1.2, 0.15)], 3.3, loc=(0, 0, 3.7), rot=(0, 0, 90), bevel=0.07)
    slate.box((2.5, 0.12, 2.2), loc=(0, 0.58, 2.3), bevel=0.03)                       # liner on the back wall
    dk.box_between((0, 0.95, 1.75), (0, -1.75, 0.98), (2.5, 0.16), bevel=0.03)       # chute to the bin
    for sx in (-1, 1):                                                              # dark front posts and side plates
        fr.box((0.3, 0.3, 3.05), loc=(sx * 1.36, -1.35, B9 + 1.525), bevel=0.05)
        fr.box((0.12, 2.0, 2.4), loc=(sx * 1.79, 0, 2.3), bevel=0.04)
        for z in (1.2, 2.0, 2.8):
            sl.bolt((sx * 1.36, -1.51, z), normal=(0, -1, 0), r=0.07)
    fr.box((3.0, 0.32, 0.5), loc=(0, -1.35, 3.2), bevel=0.05)                      # lintel
    for sx in (-1, 1):
        sl.bolt((sx * 1.36, -1.51, 3.2), normal=(0, -1, 0), r=0.08)
    # ---- side hubs (amber discs) and jaw shaft bearings
    for sx in (-1, 1):
        steel.cyl(0.72, 0.72, 0.28, seg=10, loc=(sx * 2.0, JY, CZ), rot=(0, 90, 0), bevel=0.03)
        steel.cyl(0.4, 0.4, 0.4, seg=8, loc=(sx * 2.1, JY, CZ), rot=(0, 90, 0), bevel=0.03)
        sl.cyl(0.18, 0.18, 0.15, seg=8, loc=(sx * 2.35, JY, CZ), rot=(0, 90, 0))
    # ---- JAWS (separate moving pieces)
    open_face, thick, closed_shift = 0.55, 0.7, 0.45
    for name, sign in (("JawL", -1), ("JawR", 1)):
        jaw = m.piece(name, "SteelLight", anim=name + "_SlideX", pivot=(sign * (open_face + thick / 2), JY, CZ),
                      note=f"crusher jaw; slides along X toward the middle by {closed_shift} studs (attach {name}_Closed); the "
                           "shaft stub passes through the hub")
        x_face, x_back = sign * open_face, sign * (open_face + thick)
        pts = []
        for x, r in ((x_face, 0.6), (x_back, 0.9)):
            for k in range(8):
                a = math.radians(22.5 + k * 45)
                pts.append(Vector((x, JY + r * math.cos(a), CZ + r * math.sin(a))))
        jaw.hull(pts, bevel=0.05)
        xcyl(jaw, 0.2, 0.95, (sign * (open_face + thick + 0.35), JY, CZ), seg=8)
        m.attach[name + "_Open"] = (sign * (open_face + thick / 2), JY, CZ)
        m.attach[name + "_Closed"] = (sign * (open_face + thick / 2 - closed_shift), JY, CZ)
    # ---- hood: dark frame + glass pane + hazard lip
    for sx in (-1, 1):
        fr.box_between((sx * 1.25, -1.45, 1.95), (sx * 1.25, -1.55, 3.0), (0.14, 0.14), bevel=0.02)
    fr.box((2.6, 0.14, 0.14), loc=(0, -1.5, 3.0), bevel=0.02)
    dk.box((2.7, 0.28, 0.3), loc=(0, -1.5, 1.85), bevel=0.05)
    K.hazard_stripes(am, 2.5, 0.26, (0, -1.655, 1.85), count=5, slant=0.8, depth=0.03, margin=0.03)
    glass = m.piece("Hood", "GlassClear", transparency=0.72, note="protective window, clear Glass, transparency 0.72 so the jaws and the rock stay visible")
    if not __import__("os").environ.get("CTR_NOGLASS"):
        glass.box((2.45, 0.08, 1.05), loc=(0, -1.5, 2.45), bevel=0.02)
    # ---- motor (+X): coupling, ribbed body, amber end cap, base
    dk.box((1.6, 1.7, 0.45), loc=(2.75, 0, B9 + 0.225), bevel=0.06)
    for sx in (1,):
        xcyl(steel, 0.38, 0.5, (2.2, JY, 2.0), seg=8)
        xcyl(steel, 0.6, 0.3, (2.4, JY, 2.0), seg=8, bevel=0.03)
    xcyl(fr, 1.0, 1.2, (2.95, JY, 2.0), seg=10, bevel=0.03)
    for i in range(6):
        xcyl(dk, 1.06, 0.09, (2.45 + i * 0.2, JY, 2.0), seg=10)
    xcyl(dk, 0.95, 0.42, (3.5, JY, 2.0), seg=10, bevel=0.04)
    xcyl(dk, 0.7, 0.1, (3.74, JY, 2.0), seg=8)
    dk.box((0.5, 0.5, 0.18), loc=(2.9, JY, 3.0), bevel=0.03)
    # ---- control panel (front right): cream body with a leaning face
    px, py = 2.75, -1.0
    hw.prism([(-0.55, 0), (0.55, 0), (0.55, 1.9), (0.0, 1.9), (-0.55, 1.05)], 1.25, loc=(px, py, B9), rot=(0, 0, 90), bevel=0.05)
    face_c = (px, py - 0.275 - 0.03, B9 + 1.475)
    ui_face(m, face_c, tilt=-32.7, w=1.0, h=0.95, buttons=("Red",))
    # ---- feed roller conveyor (-X)
    for sx in (-1, 1):
        pass
    for lx in (-3.45, -1.95):
        for ly in (-0.75, 0.75):
            dk.box((0.34, 0.34, 1.35), loc=(lx, ly, B9 + 0.675), bevel=0.04)
            sl.bolt((lx, ly - 0.18 if ly < 0 else ly + 0.18, 1.3), normal=(0, -1 if ly < 0 else 1, 0), r=0.06)
    for ly in (-1, 1):
        fr.box((2.0, 0.3, 0.45), loc=(-2.7, ly * 0.8, 2.15), bevel=0.05)
        wood.box((1.75, 0.2, 0.5), loc=(-2.7, ly * 1.0, 1.65), bevel=0.04)
        for lx in (-3.4, -2.0):
            am.box((0.34, 0.55, 0.62), loc=(lx, ly * 0.8, 2.2), bevel=0.05)
            sl.bolt((lx, ly * 1.08, 2.25), normal=(0, ly, 0), r=0.06)
    for i in range(7):
        ycyl(fr, 0.2, 1.5, (-3.5 + i * 0.28, 0, 2.3), seg=8)
    # ---- output bin (front) with Fill
    bx, by = 0, -2.25
    dk.box((2.55, 1.45, 0.14), loc=(bx, by, B9 + 0.07), bevel=0.03)
    for sx in (-1, 1):
        fr.prism([(-0.72, 0), (0.72, 0), (0.72, 0.95), (-0.72, 0.62)], 0.15, loc=(sx * 1.2, by, B9), rot=(0, 0, 90), bevel=0.02)
    fr.box((2.55, 0.15, 0.65), loc=(bx, by - 0.65, B9 + 0.325), bevel=0.03)
    am.box((2.9, 0.22, 0.28), loc=(bx, by - 0.78, B9 + 0.62), bevel=0.05)
    for sx in (-1, 1):
        am.box((0.22, 0.26, 0.85), loc=(sx * 1.38, by - 0.76, B9 + 0.45), bevel=0.05)
        sl.bolt((sx * 1.38, by - 0.9, B9 + 0.7), normal=(0, -1, 0), r=0.06)
    fill = m.piece("Fill", "Rock", note="rubble heap in the output bin; show as the bin fills, hide when empty")
    rubble(fill, 16, (-1.05, -2.8, 1.05, -1.7), (0.3, 0.5), 7, B9 + 0.15)
    # ---- brass plate + vent on the base side
    m.slot("Brass").box((0.06, 0.55, 0.3), loc=(3.74, -0.4, 2.9), bevel=0.02)
    # ---- preview rocks (sheet comparison only)
    for i, x in enumerate((-3.5, -2.9, -2.3)):
        prev_rock(m, 3 + i, 0.8, (x, 0, 2.5))
    prev_rock(m, 21, 1.1, (0, JY, 1.7))
    # ---- attach points
    m.attach.update({"FeedStart": (-3.5, 0, 2.5), "FeedEnd": (-1.95, 0, 2.5), "Chamber": (0, JY, 1.7), "Output": (0, -2.2, B9 + 0.2),
                     "Panel": face_c, "Light": (2.75, -1.3, B9 + 2.0)})
    m.extra["motion"] = {
        "JawL": "slide along Roblox X; Blender -X side = Roblox +X side; home = JawL_Open, end = JawL_Closed (0.4 studs toward the middle)",
        "JawR": "slide along Roblox X; Blender +X side = Roblox -X side; home = JawR_Open, end = JawR_Closed (0.4 studs toward the middle)",
        "Hood": "static glass (hide or raise to open)",
    }


# ====================================================================== 10 HYDRAULIC PRESS

@register("Hydraulic_Press", S10,
          "Hydraulic press (m4 rebuild, warm wood + steel, 4.95 studs tall): timber header on steel uprights, fixed cylinder sleeve, "
          "Piston + Platen (separate pieces, move together along Y), bed plate, feed conveyor (-X), controller cabinet (+X), "
          "output tray + Fill. Front -Y.",
          ref=(REF10, (20, 60, 1530, 540)))
def hydraulic_press(m):
    con, fr, dk = m.slot("Concrete"), m.slot("Frame"), m.slot("FrameDark")
    steel, sl, am, rub = m.slot("Steel"), m.slot("SteelLight"), m.slot("Amber"), m.slot("Rubber")
    wood, wdark = m.slot("Wood"), m.slot("WoodDark")
    # ---- concrete pads
    con.box((5.0, 2.7, 0.35), loc=(0, 0, 0.175), bevel=0.06)
    con.box((1.9, 2.0, 0.35), loc=(2.95, 0, 0.175), bevel=0.06)
    con.box((3.0, 1.4, 0.35), loc=(0, -1.75, 0.175), bevel=0.06)
    for lx in (-3.45, -2.5):
        for ly in (-0.75, 0.75):
            con.box((0.6, 0.6, 0.3), loc=(lx, ly, 0.15), bevel=0.05)
    # ---- base block (timber on a steel plinth), bed plate
    dk.box((4.2, 1.9, 0.3), loc=(0, 0, 0.5), bevel=0.05)
    wood.box((4.0, 1.8, 0.6), loc=(0, 0, 0.95), bevel=0.06)
    for i in (-1, 0, 1):
        wdark.box((0.05, 0.05, 0.5), loc=(i * 1.0, -0.91, 0.95), bevel=0.0)
    steel.box((2.7, 1.6, 0.25), loc=(0, 0, 1.375), bevel=0.05)
    for sx in (-1, 1):
        for sy in (-1, 1):
            sl.bolt((sx * 1.1, sy * 0.6, 1.5), r=0.09)
    # ---- uprights (steel with timber facings), header beam (timber, steel caps and straps)
    for sx in (-1, 1):
        fr.box((0.7, 1.7, 2.9), loc=(sx * 1.7, 0, 1.5 + 1.45), bevel=0.06)
        wood.box((0.12, 1.3, 2.3), loc=(sx * 1.7 - sx * 0.38, 0, 2.55), bevel=0.03)
        dk.box((0.9, 1.9, 0.3), loc=(sx * 1.7, 0, 1.6), bevel=0.05)
        for z in (2.0, 3.0, 3.9):
            sl.bolt((sx * 1.7, -0.88, z), normal=(0, -1, 0), r=0.08)
    wood.box((4.5, 1.9, 0.6), loc=(0, 0, 4.2), bevel=0.07)
    for sx in (-1, 1):
        fr.box((0.5, 2.0, 0.7), loc=(sx * 1.85, 0, 4.2), bevel=0.05)
    for z in (4.05, 4.35):
        fr.box((4.6, 0.06, 0.12), loc=(0, -0.97, z), bevel=0.01)
    K.hazard_stripes(am, 2.6, 0.32, (0, -0.99, 4.2), count=4, slant=0.9, depth=0.03, margin=0.03)
    # ---- fixed cylinder sleeve through the header (the rod slides out of its lower end)
    sl.cyl(0.62, 0.62, 1.5, seg=10, loc=(0, 0, 4.2), bevel=0.03)
    steel.cyl(0.78, 0.78, 0.16, seg=10, loc=(0, 0, 3.52), bevel=0.02)
    steel.cyl(0.78, 0.78, 0.16, seg=10, loc=(0, 0, 4.88), bevel=0.02)
    for k in range(6):
        a = k * 60 * math.pi / 180
        sl.bolt((math.cos(a) * 0.66, math.sin(a) * 0.66, 4.97), r=0.07)
    dk.box((0.4, 0.4, 0.4), loc=(0.72, 0, 4.4), bevel=0.04)
    am.cyl(0.24, 0.24, 0.12, seg=8, loc=(0.98, 0, 4.4), rot=(0, 90, 0))
    # ---- PISTON + PLATEN (moving, separate pieces; rod overlaps the sleeve so it never floats free)
    stroke = 1.25
    pis = m.piece("Piston", "SteelLight", anim="Piston_PressY", pivot=(0, 0, 3.2),
                  note=f"piston rod; moves with the platen {stroke} studs down along Roblox Y (attach Platen_Down)")
    pis.cyl(0.34, 0.34, 1.7, seg=8, loc=(0, 0, 4.1), bevel=0.02)
    pla = m.piece("Platen", "Steel", anim="Platen_PressY", pivot=(0, 0, 3.2),
                  note=f"press platen; moves {stroke} studs down along Roblox Y with the piston (attach Platen_Down)")
    pla.box((2.3, 1.5, 0.5), loc=(0, 0, 3.2), bevel=0.07)
    for sx in (-1, 1):
        pla.box((0.28, 1.1, 0.8), loc=(sx * 1.2, 0, 3.3), bevel=0.04)    # guide shoes riding the uprights
    m.attach["Platen_Open"] = (0, 0, 3.2)
    m.attach["Platen_Down"] = (0, 0, 3.2 - stroke)
    # ---- hose to the controller
    rub.tube([(0.98, 0, 4.4), (1.6, 0, 4.9), (2.6, 0, 4.9), (3.0, 0, 4.3), (3.0, 0, 3.7)], 0.17, seg=8)
    am.cyl(0.24, 0.24, 0.18, seg=8, loc=(3.0, 0, 3.62))
    # ---- controller cabinet (+X): timber body, steel frame
    wood.box((1.5, 1.5, 2.7), loc=(2.95, 0, 0.35 + 1.35), bevel=0.07)
    fr.box((1.6, 1.6, 0.25), loc=(2.95, 0, 3.15), bevel=0.04)
    for sy in (-1, 1):
        fr.box((0.12, 0.12, 2.7), loc=(2.3, sy * 0.7, 1.7), bevel=0.02)
        fr.box((0.12, 0.12, 2.7), loc=(3.6, sy * 0.7, 1.7), bevel=0.02)
    ui_face(m, (2.95, -0.8, 2.4), tilt=0, w=1.0, h=1.0, buttons=("Green", "Red"))
    for i in range(4):
        dk.box((1.0, 0.06, 0.1), loc=(2.95, -0.78, 0.9 + i * 0.2), bevel=0.01)
    # ---- feed conveyor (-X), inclined toward the press: timber slats on steel rails
    belt_a, belt_b = (-3.75, 0, 1.12), (-2.1, 0, 1.92)
    wdark.box_between(belt_a, belt_b, (1.25, 0.14), bevel=0.02)
    for i in range(7):
        t = (i + 0.5) / 7
        p = Vector((-3.75, 0, 1.2)) * (1 - t) + Vector((-2.1, 0, 2.0)) * t
        wood.box_between(p + Vector((0, -0.55, 0)), p + Vector((0, 0.55, 0)), (0.1, 0.1), bevel=0.0)
    for ly in (-1, 1):
        fr.box_between((-3.78, ly * 0.72, 1.3), (-2.05, ly * 0.72, 2.12), (0.14, 0.42), bevel=0.03)
        dk.box((0.3, 0.3, 0.85), loc=(-3.45, ly * 0.75, 0.3 + 0.425), bevel=0.04)
        dk.box((0.3, 0.3, 1.35), loc=(-2.5, ly * 0.75, 0.3 + 0.675), bevel=0.04)
        sl.bolt((-2.85, ly * 0.9, 1.55), normal=(0, ly, 0), r=0.07)
    dk.box((0.3, 1.8, 0.35), loc=(-2.05, 0, 1.95), bevel=0.04)
    # ---- output tray (front): timber bin with steel corners
    dk.box((2.6, 1.3, 0.12), loc=(0, -1.75, 0.41), bevel=0.02)
    wood.box((2.6, 0.15, 0.7), loc=(0, -2.3, 0.7), bevel=0.03)
    for sx in (-1, 1):
        wood.box((0.15, 1.35, 0.7), loc=(sx * 1.3, -1.75, 0.7), bevel=0.03)
        fr.box((0.2, 0.2, 0.95), loc=(sx * 1.38, -2.35, 0.78), bevel=0.04)
        fr.box((0.2, 1.5, 0.14), loc=(sx * 1.38, -1.75, 1.03), bevel=0.03)
    fr.box((2.9, 0.2, 0.14), loc=(0, -2.38, 1.03), bevel=0.03)
    fill = m.piece("Fill", "Rock", note="cracked rubble in the output tray; show when output is ready")
    rubble(fill, 14, (-1.1, -2.15, 1.1, -1.25), (0.28, 0.46), 5, 0.5)
    # ---- preview rocks
    for i, (x, y) in enumerate(((-3.3, 0.0), (-2.7, 0.1))):
        prev_rock(m, 4 + i, 0.8, (x, y, 1.45 + 0.35 * i + 0.2))
    prev_rock(m, 12, 1.05, (0, 0, 1.5))
    m.attach.update({"RockSpot": (0, 0, 1.5), "FeedStart": (-3.55, 0, 1.3), "FeedEnd": (-2.15, 0, 2.0), "Output": (0, -1.75, 0.5),
                     "Panel": (2.95, -0.85, 2.4), "Light": (2.95, -0.9, 3.4)})
    m.extra["motion"] = {
        "Piston": f"slide along Roblox Y by -{stroke} studs (Open = Platen_Open, Down = Platen_Down); moves with Platen",
        "Platen": f"slide along Roblox Y by -{stroke} studs; underside at Roblox Y 2.95 open, 1.7 down (bed plate top = 1.5)",
    }


# ====================================================================== 10 INDUSTRIAL CRUSHER

@register("Industrial_Crusher", S10,
          "Industrial crusher (m4 rebuild, warm wood + steel, 4.4 studs tall): low hopper (+HopperFill), RollerL/RollerR spiked drums "
          "(separate, spin about the X axis), mesh guards, discharge conveyor toward the front, discharge bin + Fill, motor (+X), "
          "controller pedestal (-X). Front -Y.",
          ref=(REF10, (20, 555, 1530, 1000)))
def industrial_crusher(m):
    con, fr, dk = m.slot("Concrete"), m.slot("Frame"), m.slot("FrameDark")
    steel, sl, am, rub = m.slot("Steel"), m.slot("SteelLight"), m.slot("Amber"), m.slot("Rubber")
    wood, wdark, slate = m.slot("Wood"), m.slot("WoodDark"), m.slot("Slate")
    RZ, RY = 2.1, 0.0
    # ---- concrete slab, front pad, feet
    con.box((6.6, 3.4, 0.45), loc=(0.4, 0, 0.2 + 0.225), bevel=0.07)
    con.box((3.0, 1.7, 0.45), loc=(0, -2.45, 0.2 + 0.225), bevel=0.07)
    for sx in (-1, 1):
        for sy in (-1, 1):
            dk.box((1.0, 0.8, 0.2), loc=(0.4 + sx * 2.7, sy * 1.35, 0.1), bevel=0.04)
    for sx in (-1, 1):
        dk.box((0.9, 0.7, 0.2), loc=(sx * 1.2, -3.0, 0.1), bevel=0.04)
    # ---- body: steel plinths, timber end blocks with steel straps, timber back wall, top beam
    B = 0.65
    for sx in (-1, 1):
        dk.box((0.95, 2.8, 0.6), loc=(sx * 1.95, 0, B + 0.3), bevel=0.05)
        wood.box((0.8, 2.4, 2.0), loc=(sx * 1.95, 0, 1.25 + 1.0), bevel=0.07)
        for z in (1.6, 2.2, 2.8):
            fr.box((0.86, 2.46, 0.1), loc=(sx * 1.95, 0, z), bevel=0.02)
            sl.bolt((sx * 1.95, -1.25, z), normal=(0, -1, 0), r=0.08)
    dk.box((3.0, 0.8, 0.6), loc=(0, 0.95, B + 0.3), bevel=0.05)
    wood.box((3.2, 0.5, 2.0), loc=(0, 0.95, 2.25), bevel=0.06)
    wood.box((4.8, 2.4, 0.4), loc=(0, 0, 3.45), bevel=0.07)
    for sx in (-1, 1):
        fr.box((0.5, 2.5, 0.5), loc=(sx * 2.15, 0, 3.45), bevel=0.05)
    dk.box((3.0, 0.12, 1.8), loc=(0, 0.65, RZ), bevel=0.03)
    dk.box((3.2, 0.3, 0.4), loc=(0, -1.25, 3.2), bevel=0.05)    # front lintel under the hopper
    dk.box((3.2, 0.3, 0.3), loc=(0, -1.2, 1.3), bevel=0.04)
    # ---- low hopper (steel, timber rim)
    hop = [Vector((x, y, 3.65)) for x in (-1.4, 1.4) for y in (-0.9, 0.9)] + [Vector((x, y, 4.3)) for x in (-2.2, 2.2) for y in (-1.4, 1.4)]
    dk.hull(hop, bevel=0.06)
    for sy in (-1, 1):
        wood.box((4.6, 0.22, 0.3), loc=(0, sy * 1.4, 4.28), bevel=0.04)
    for sx in (-1, 1):
        wood.box((0.22, 3.0, 0.3), loc=(sx * 2.2, 0, 4.28), bevel=0.04)
    slate.box((4.0, 2.6, 0.1), loc=(0, 0, 3.8), bevel=0.02)
    hf = m.piece("HopperFill", "Rock", note="rocks heaped in the hopper (rock count / queue visual); hide when empty")
    K.scatter_rocks(hf, 6, (-1.5, -0.8, 1.5, 0.8), (0.55, 0.8), seed=9, z=3.85, flat=0.85)
    # ---- ROLLERS (spiked drums, separate pieces, axis along X)
    for name, cx in (("RollerL", -0.75), ("RollerR", 0.75)):
        r = m.piece(name, "SteelLight", anim=name + "_SpinX", pivot=(cx, RY, RZ),
                    note="spiked crushing drum; rotate about the Roblox X axis through the pivot (RollerL and RollerR counter-rotate)")
        ring_hull(r, cx - 0.65, 0.75, cx + 0.65, 0.75, RY, RZ, n=10, rot_off=18, bevel=0.04)
        xcyl(r, 0.28, 1.85, (cx + (-0.5 if cx < 0 else 0.5), RY, RZ), seg=8)
        for row, xo in enumerate((-0.4, 0.0, 0.4)):
            for k in range(8):
                a = math.radians(k * 45 + (22.5 if row % 2 else 0))
                d = Vector((0, math.cos(a), math.sin(a)))
                t = Vector((0, -math.sin(a), math.cos(a)))
                c = Vector((cx + xo, RY, RZ))
                pts = []
                for sx_, st_ in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
                    pts.append(c + d * 0.69 + Vector((1, 0, 0)) * sx_ * 0.22 + t * st_ * 0.2)
                    pts.append(c + d * 0.94 + Vector((1, 0, 0)) * sx_ * 0.07 + t * st_ * 0.07)
                r.hull(pts)
        m.attach[name] = (cx, RY, RZ)
    # ---- guards (steel octagon frames with diamond mesh), front of the roller ends
    for sx in (-1, 1):
        gx = sx * 1.725
        gy = -1.36
        fr.prism(octagon(1.15, 1.8, 0.3), 0.14, loc=(gx, gy, RZ))
        slate.prism(octagon(0.9, 1.55, 0.22), 0.1, loc=(gx, gy - 0.07, RZ))
        lattice(sl, gx - 0.43, gx + 0.43, RZ - 0.72, RZ + 0.72, gy - 0.1, pitch=0.3, r=0.025)
        for z in (RZ - 0.7, RZ + 0.7):
            sl.bolt((gx + sx * 0.4, gy - 0.07, z), normal=(0, -1, 0), r=0.06)
    am.box((1.2, 0.06, 0.28), loc=(0, -1.43, 3.2), bevel=0.01)       # one small hazard tag on the lintel
    # ---- discharge conveyor (to the front) + bin
    belt_a, belt_b = (0, 0.3, 1.38), (0, -2.0, 1.12)
    wdark.box_between(belt_a, belt_b, (1.7, 0.12), bevel=0.02)
    for i in range(9):
        t = (i + 0.5) / 9
        p = Vector(belt_a) * (1 - t) + Vector(belt_b) * t + Vector((0, 0, 0.08))
        wood.box((1.55, 0.08, 0.1), loc=p, bevel=0.0)
    for sx in (-1, 1):
        fr.box_between((sx * 0.98, 0.3, 1.52), (sx * 0.98, -2.05, 1.27), (0.14, 0.38), bevel=0.03)
        dk.box((0.3, 0.3, 0.75), loc=(sx * 1.0, -1.7, B + 0.38), bevel=0.04)
        sl.bolt((sx * 1.15, -1.0, 1.35), normal=(sx, 0, 0), r=0.07)
    bx, by, bw, bd = 0, -2.45, 2.55, 1.45
    dk.box((bw, bd, 0.14), loc=(bx, by, B + 0.07), bevel=0.03)
    wood.box((bw, 0.15, 0.7), loc=(bx, by - bd / 2 + 0.07, B + 0.35), bevel=0.03)
    for sx in (-1, 1):
        wood.box((0.15, bd, 0.7), loc=(sx * (bw / 2 - 0.07), by, B + 0.35), bevel=0.03)
        fr.box((0.22, bd + 0.1, 0.16), loc=(sx * (bw / 2 + 0.0), by, B + 0.74), bevel=0.04)
        fr.box((0.25, 0.25, 0.9), loc=(sx * (bw / 2), by - bd / 2, B + 0.45), bevel=0.04)
    fr.box((bw + 0.4, 0.22, 0.16), loc=(bx, by - bd / 2 - 0.02, B + 0.74), bevel=0.04)
    fill = m.piece("Fill", "Rock", note="crushed rubble in the discharge bin; show as output arrives, hide when empty")
    rubble(fill, 16, (-1.05, -3.0, 1.05, -1.95), (0.28, 0.5), 3, B + 0.15)
    # ---- motor (+X): steel body, timber mount, one amber collar
    wood.box((1.7, 1.8, 0.45), loc=(3.0, 0, B + 0.225), bevel=0.05)
    xcyl(steel, 0.3, 0.7, (2.5, RY, RZ), seg=8)
    xcyl(am, 0.58, 0.22, (2.45, RY, RZ), seg=8, bevel=0.03)
    fr.box((0.5, 1.5, 0.4), loc=(2.45, RY, RZ + 0.95), bevel=0.06)
    xcyl(fr, 0.95, 1.0, (3.05, RY, RZ), seg=10, bevel=0.03)
    for i in range(5):
        xcyl(dk, 1.0, 0.09, (2.7 + i * 0.2, RY, RZ), seg=10)
    xcyl(dk, 0.88, 0.3, (3.55, RY, RZ), seg=10, bevel=0.03)
    for i in range(4):
        dk.box((0.06, 1.2, 0.08), loc=(3.72, RY, RZ - 0.45 + i * 0.3), bevel=0.0)
    # ---- controller pedestal (-X, front): steel post, timber head
    con.box((0.85, 0.85, 0.3), loc=(-3.4, -0.5, 0.15), bevel=0.05)
    fr.box((0.3, 0.3, 1.5), loc=(-3.4, -0.5, 1.05), bevel=0.04)
    wood.box((1.15, 0.55, 1.0), loc=(-3.4, -0.5, 2.15), rot=(-20, 0, 0), bevel=0.06)
    ui_face(m, (-3.4, -0.5 - 0.3, 2.15 + 0.1), tilt=-20, w=0.95, h=0.85, buttons=("Green", "Red"))
    # ---- preview rocks
    for i, (x, y) in enumerate(((-1.0, 0.0), (0.0, 0.2), (1.0, -0.1))):
        prev_rock(m, 30 + i, 0.7, (x, y, 3.85))
    for i, y in enumerate((-0.4, -0.9, -1.4)):
        prev_rock(m, 50 + i, 0.4, ((-0.3, 0.3, -0.2)[i], y, 1.3))
    m.attach.update({"Hopper": (0, 0, 3.9), "Output": (0, -2.45, B + 0.2), "Panel": (-3.4, -0.85, 2.25), "Light": (-3.4, -0.9, 2.9),
                     "BeltStart": belt_a, "BeltEnd": belt_b})
    m.extra["motion"] = {
        "RollerL": "spin about the Roblox X axis through its pivot (attach RollerL); counter-rotate against RollerR",
        "RollerR": "spin about the Roblox X axis through its pivot (attach RollerR)",
    }
