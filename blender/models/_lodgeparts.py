"""Shared parts for the Prospector Lodge furnishings (docs/lodge/, MASTER_PROMPT sections 7-14).

Not a sheet module (leading underscore): lodge_stalls.py and lodge_decor.py import it. It adds the
lodge furnishing palette to ctrkit.HEX (names start with "Fn" so they never collide with the
structural Lodge_Building kit or older kits) and the builders the stalls, bays, boards and decor share:
counters, striped awnings, blank sign boards, lanterns, crates, rug borders.

Conventions (as every kit model): 1 unit = 1 stud, +Z up, FRONT faces -Y, origin = floor centre
(bottom centre) unless the model note says otherwise (signs, posters, wall lanterns and emblems: centre
of the back face). Text never lives in a mesh: every sign / board face is its own blank piece with an
attach point at the centre of its front face for a SurfaceGui (Face = Front in Roblox).
"""

import math
import random

import bmesh
from mathutils import Vector

import ctrkit as K

# ------------------------------------------------------------------ palette (MASTER_PROMPT section 13)

PALETTE = {
    "FnWood": ("#A9693F", "Wood"),           # WoodMain
    "FnWoodDark": ("#70452D", "Wood"),       # WoodDark: frames, battens, kick plates
    "FnWoodLight": ("#BC7E4E", "Wood"),      # countertops, plank faces
    "FnSignWood": ("#8A5532", "Wood"),       # blank sign faces (SurfaceGui text, cream letters, dark stroke)
    "FnPegboard": ("#C38D5B", "WoodPlanks"),  # pegboard sheet
    "FnHandle": ("#9A5A2E", "Wood"),         # hammer handle
    "FnMetal": ("#343639", "Metal"),         # MetalDark: lantern frames, latches, chains, bolts
    "FnSteel": ("#8E9AA6", "Metal"),         # hammer head
    "FnGold": ("#E1B443", "Metal"),          # emblems, trophy
    "FnPadGold": ("#C9A042", "SmoothPlastic"),  # muted gold hunt pad trim (not emissive)
    "FnSilver": ("#C3C8CE", "SmoothPlastic"),
    "FnBronze": ("#C47A3A", "SmoothPlastic"),
    "FnCharcoal": ("#282B30", "SmoothPlastic"),  # BoardCharcoal: leaderboard faces, pad centres
    "FnAwningCream": ("#FFF0D0", "Fabric"),
    "FnAwningRed": ("#D94D52", "Fabric"),
    "FnAwningPurple": ("#9555BF", "Fabric"),
    "FnBacking": ("#E7D6B8", "SmoothPlastic"),  # Plaster tone: cabinet backing
    "FnPlanter": ("#ECE4D6", "SmoothPlastic"),  # cream planter
    "FnSoil": ("#4E3726", "Ground"),
    "FnLeaf": ("#659B35", "Grass"),          # PlantGreen
    "FnLeafDark": ("#4C7E27", "Grass"),
    "FnStem": ("#5C7F2C", "Grass"),
    "FnPane": ("#F2C063", "SmoothPlastic"),  # lantern panes: warm, not glowing
    "FnCore": ("#FFE9A8", "Neon"),           # small diamond light core (the only Neon)
    "FnRugRed": ("#B5412F", "Fabric"),
    "FnRugGold": ("#E39A3B", "Fabric"),
    "FnPaper": ("#EBDDBF", "SmoothPlastic"),  # poster paper
    "FnInk": ("#6B5444", "SmoothPlastic"),   # poster marks
    "FnRock": ("#8C8780", "Slate"),          # basket rocks, crystal-cluster bases
    "FnRockDark": ("#6F6A64", "Slate"),
    "FnGeodeShell": ("#8A857E", "Slate"),    # neutral grey display-geode shell
    "FnRim": ("#E4DACD", "SmoothPlastic"),   # pale inner mineral rim
    "FnShade": ("#1E1A24", "SmoothPlastic"),
    "CrystalViolet": ("#9B5DE5", "SmoothPlastic"),
    "CrystalBlue": ("#55B7E8", "SmoothPlastic"),
    "CrystalAmber": ("#E8B54B", "SmoothPlastic"),
    "LiningViolet": ("#43226F", "SmoothPlastic"),
    "LiningBlue": ("#1C4A6E", "SmoothPlastic"),
    "LiningAmber": ("#6B4513", "SmoothPlastic"),
    "FnGlass": ("#DCEBF0", "Glass"),         # cabinet glass (transparency 0.7 in game)
}
for _k, (_hex, _mat) in PALETTE.items():
    K.HEX.setdefault(_k, _hex)
    K.SLOT_MATERIAL.setdefault(_k, _mat)

CRYSTALS = {"Violet": ("CrystalViolet", "LiningViolet"), "Blue": ("CrystalBlue", "LiningBlue"),
            "Amber": ("CrystalAmber", "LiningAmber")}


def V(x, y, z):
    return Vector((x, y, z))


def part(m, name, slot, material=None, **kw):
    """A named piece (cached per model)."""
    key = ("part", name)
    if key not in m._slots:
        m._slots[key] = m.piece(name, slot, material, **kw)
    return m._slots[key]


def collider(m, size, centre):
    """Record a simple box collider (Roblox axes) in the manifest; MeshService/LobbyBuilder turns these into
    invisible anchored Parts. Render meshes themselves should be CanCollide = false."""
    m.extra.setdefault("colliders", []).append({"size": K.roblox_size(size), "offset": K.to_roblox(centre)})


def attach(m, name, p):
    m.attach[name] = tuple(round(c, 4) for c in p)


def ring_rect(piece, outer_w, outer_d, band, z0, h, loc=(0, 0, 0)):
    """Flat rectangular band (frame) of width `band` lying on z0, `h` tall. Four boxes, no overlaps."""
    o = Vector(loc)
    w, d = outer_w, outer_d
    piece.box((w, band, h), loc=o + V(0, -d / 2 + band / 2, z0 + h / 2), bevel=0)
    piece.box((w, band, h), loc=o + V(0, d / 2 - band / 2, z0 + h / 2), bevel=0)
    piece.box((band, d - 2 * band, h), loc=o + V(-w / 2 + band / 2, 0, z0 + h / 2), bevel=0)
    piece.box((band, d - 2 * band, h), loc=o + V(w / 2 - band / 2, 0, z0 + h / 2), bevel=0)


# ------------------------------------------------------------------ counters

def counter(m, w=24.0, d=5.5, h=4.0, y_front=-4.0, cabinet=None, panels=3):
    """Wooden stall counter: front panels between posts with plank seams, dark kick plate, overhanging top.
    Front face at y_front; countertop surface at z = h. cabinet=(x0, x1, z0, z1, depth) cuts a glazed
    display recess into the front (Collection). Returns the countertop height."""
    wood, dark, light = m.slot("FnWood"), m.slot("FnWoodDark"), part(m, "Countertop", "FnWoodLight")
    yb = y_front + d
    yc = (y_front + yb) / 2
    top_t = 0.42
    zt = h - top_t
    core_f = y_front + 0.18                  # core front face (posts / rails stand proud of it)
    # countertop with a front + side overhang
    light.box((w + 0.6, d + 0.45, top_t), loc=(0, yc - 0.2, h - top_t / 2), bevel=0.1)
    # core body (split around a display cabinet when there is one)
    if cabinet is None:
        wood.box((w - 0.3, yb - core_f, zt - 0.05), loc=(0, (core_f + yb) / 2, zt / 2), bevel=0.06)
    else:
        x0, x1, c0, c1, cd = cabinet
        wood.box((w - 0.3, yb - core_f, c0), loc=(0, (core_f + yb) / 2, c0 / 2), bevel=0.06)
        wood.box((w - 0.3, yb - core_f, zt - c1), loc=(0, (core_f + yb) / 2, (c1 + zt) / 2), bevel=0.06)
        for a, b in ((-w / 2 + 0.15, x0), (x1, w / 2 - 0.15)):
            wood.box((b - a, yb - core_f, c1 - c0), loc=((a + b) / 2, (core_f + yb) / 2, (c0 + c1) / 2), bevel=0.04)
        back = core_f + cd
        wood.box((x1 - x0, yb - back, c1 - c0), loc=((x0 + x1) / 2, (back + yb) / 2, (c0 + c1) / 2), bevel=0.04)
        part(m, "Backing", "FnBacking").box((x1 - x0 - 0.1, 0.08, c1 - c0 - 0.1), loc=((x0 + x1) / 2, back - 0.04, (c0 + c1) / 2), bevel=0.0)
        light.box((x1 - x0 + 0.1, cd + 0.1, 0.16), loc=((x0 + x1) / 2, core_f + cd / 2, c0 + 0.08), bevel=0.04)   # display shelf
        g = m.piece("Glass", "FnGlass", transparency=0.7, note="cabinet glass; transparent in game")
        g.render_hide = True
        g.box((x1 - x0 - 0.1, 0.06, c1 - c0 - 0.1), loc=((x0 + x1) / 2, y_front + 0.12, (c0 + c1) / 2), bevel=0.0)
        # trim around the opening
        for zz in (c0 - 0.12, c1 + 0.12):
            dark.box((x1 - x0 + 0.5, 0.3, 0.24), loc=((x0 + x1) / 2, y_front + 0.1, zz), bevel=0.05)
    # kick plate and top rail across the front
    dark.box((w - 0.1, 0.3, 0.45), loc=(0, y_front + 0.2, 0.225), bevel=0.06)
    wood.box((w - 0.2, 0.32, 0.42), loc=(0, y_front + 0.16, zt - 0.21), bevel=0.06)
    # posts: corners + panel stiles
    stiles = [-w / 2 + 0.35 + i * (w - 0.7) / panels for i in range(panels + 1)]
    if cabinet is not None:
        stiles = [-w / 2 + 0.35, cabinet[0] - 0.3, cabinet[1] + 0.3, w / 2 - 0.35]
    for x in stiles:
        dark.box((0.7, 0.4, zt - 0.03), loc=(x, y_front + 0.2, (zt - 0.03) / 2), bevel=0.07)
    for sx in (-1, 1):
        dark.box((0.7, 0.7, zt - 0.03), loc=(sx * (w / 2 - 0.35), yb - 0.35, (zt - 0.03) / 2), bevel=0.07)
    # vertical plank seams on the front panels (thin, barely proud: no z-fight, no deep grooves)
    seam = part(m, "Seams", "FnWoodDark")
    for a, b in zip(stiles[:-1], stiles[1:]):
        if cabinet is not None and a > cabinet[0] - 1 and b < cabinet[1] + 1:
            continue
        span = b - a - 0.7
        n = max(2, int(round(span / 1.3)))
        for i in range(1, n):
            x = a + 0.35 + span * i / n
            seam.box((0.07, 0.04, zt - 0.9), loc=(x, core_f - 0.02, 0.45 + (zt - 0.9) / 2), bevel=0.0)
    # side panels: a simple frame rail on each end
    for sx in (-1, 1):
        dark.box((0.2, d - 1.2, 0.3), loc=(sx * (w / 2 - 0.05), yc, zt * 0.55), bevel=0.04)
    return h


# ------------------------------------------------------------------ awning

def awning(m, slot_a, slot_b, width=25.0, rear=(3.7, 12.5), front=(-3.3, 10.5), stripes=11, drop=1.15, t=0.2):
    """Striped fabric awning: one sloped roof from rear (y, z) down to front (y, z), a rounded nose, and a
    hanging valance with one scallop per stripe; side flaps under the ends. Stripes alternate between
    pieces AwningA (slot_a) and AwningB (slot_b); both outer stripes are A."""
    pa, pb = part(m, "AwningA", slot_a), part(m, "AwningB", slot_b)
    yr, zr = rear
    yf, zf = front
    sw = width / stripes
    nose = [(0.0, 0.0), (-0.22, -0.1), (-0.38, -0.3), (-0.42, -0.45)]
    yv = yf + nose[-1][0]
    zv = zf + nose[-1][1]
    for i in range(stripes):
        p = pa if i % 2 == 0 else pb
        x0, x1 = -width / 2 + i * sw, -width / 2 + (i + 1) * sw
        # roof slope (a thin slab between rear and front edges)
        pts = []
        for x in (x0, x1):
            for (y, z) in ((yr, zr), (yf, zf)):
                pts += [V(x, y, z), V(x, y, z - t)]
        p.hull(pts)
        # rounded nose
        pts = []
        for x in (x0, x1):
            for (dy, dz) in nose:
                pts.append(V(x, yf + dy, zf + dz))
            pts += [V(x, yf + 0.05, zf - t), V(x, yv + t, zv - 0.05)]
        p.hull(pts)
        # valance with a scallop
        prof = [(x0, zv + 0.02), (x1, zv + 0.02), (x1, zv - drop)]
        for k in range(1, 8):
            a = k / 8
            prof.append((x1 - a * sw, zv - drop - math.sin(math.pi * a) * sw * 0.26))
        prof.append((x0, zv - drop))
        p.prism(prof, t * 0.8, loc=(0, yv + t * 0.4, 0))
    # side flaps (A) under each end of the slope
    for sx in (-1, 1):
        x = sx * (width / 2 - 0.06)
        pts = []
        for dx in (-0.06, 0.06):
            pts += [V(x + dx, yr, zr - t), V(x + dx, yf, zf - t), V(x + dx, yv, zv - drop * 0.75),
                    V(x + dx, yr, zr - 0.7)]
        pa.hull(pts)


def awning_z(y, rear=(3.7, 12.5), front=(-3.3, 10.5)):
    (yr, zr), (yf, zf) = rear, front
    return zf + (y - yf) * (zr - zf) / (yr - yf)


# ------------------------------------------------------------------ sign boards

def sign_board(m, w, h, back_y, cz, x=0.0, name="SignFace", face_slot="FnSignWood", rot_tilt=0.0, bolts=True):
    """Blank wooden sign: dark backing board with a raised plain face (piece `name`, SurfaceGui target).
    back_y = y of the board's back face; the face points to -Y. Records attach `name` (front centre)
    and extra `<name>Size` (face width, height)."""
    frame = part(m, "SignFrame", "FnWoodDark")
    face = part(m, name, face_slot)
    bt, ft = 0.24, 0.1
    frame.box((w, bt, h), loc=(x, back_y - bt / 2, cz), bevel=0.08)
    face.box((w - 0.5, ft, h - 0.5), loc=(x, back_y - bt - ft / 2 + 0.01, cz), bevel=0.03)
    if bolts:
        b = part(m, "Bolts", "FnMetal")
        for sx in (-1, 1):
            for sz in (-1, 1):
                b.bolt((x + sx * (w / 2 - 0.13), back_y - bt, cz + sz * (h / 2 - 0.13)), normal=(0, -1, 0), r=0.09)
    attach(m, name, (x, back_y - bt - ft, cz))
    m.extra[name + "Size"] = [round(w - 0.5, 3), round(h - 0.5, 3)]


# ------------------------------------------------------------------ lanterns

def lantern(m, at, s=1.0, frame=None, pane=None, core=None, handle=True):
    """Portable lantern standing on `at`: dark base + roof, four corner posts, four warm panes with a
    small diamond light core on each face. 0.9 x 0.9 x 1.6 at s = 1. Returns the light centre."""
    at = Vector(at)
    fr = frame or m.slot("FnMetal")
    pn = pane or m.slot("FnPane")
    cr = core or m.slot("FnCore")
    w = 0.9 * s
    fr.box((w, w, 0.16 * s), loc=at + V(0, 0, 0.08 * s), bevel=0.03 * s)
    fr.box((w * 0.82, w * 0.82, 0.08 * s), loc=at + V(0, 0, 0.2 * s), bevel=0)
    body0, body1 = 0.24 * s, 1.08 * s
    pn.box((w * 0.7, w * 0.7, body1 - body0), loc=at + V(0, 0, (body0 + body1) / 2), bevel=0.02 * s)
    for sx in (-1, 1):
        for sy in (-1, 1):
            fr.box((0.12 * s, 0.12 * s, body1 - body0 + 0.04 * s), loc=at + V(sx * w * 0.36, sy * w * 0.36, (body0 + body1) / 2), bevel=0)
    # diamond core on each face
    dz = (body0 + body1) / 2
    ds = 0.34 * s
    for ang in (0, 90, 180, 270):
        a = math.radians(ang)
        n = V(math.sin(a), -math.cos(a), 0)
        c = at + V(0, 0, dz) + n * (w * 0.35 + 0.01 * s)
        side = V(math.cos(a), math.sin(a), 0)
        pts = []
        for q in (0, 0.03 * s):
            o = c + n * q
            pts += [o + V(0, 0, ds * 0.62), o - V(0, 0, ds * 0.62), o + side * ds * 0.4, o - side * ds * 0.4]
        cr.hull(pts)
    # top frame + pyramid roof + handle
    fr.box((w, w, 0.12 * s), loc=at + V(0, 0, body1 + 0.06 * s), bevel=0.03 * s)
    fr.box((w * 0.95, w * 0.95, 0.24 * s), loc=at + V(0, 0, body1 + 0.24 * s), taper=(0.4, 0.4), bevel=0.02 * s)
    if handle:
        fr.box((0.16 * s, 0.16 * s, 0.1 * s), loc=at + V(0, 0, body1 + 0.4 * s), bevel=0)
        top = at + V(0, 0, body1 + 0.45 * s)
        for sx in (-1, 1):
            fr.box((0.06 * s, 0.06 * s, 0.14 * s), loc=top + V(sx * 0.14 * s, 0, 0.05 * s), bevel=0)
        fr.box((0.34 * s, 0.06 * s, 0.06 * s), loc=top + V(0, 0, 0.13 * s), bevel=0)
    return at + V(0, 0, dz)


# ------------------------------------------------------------------ crates

def braced_crate(m, s, at=(0, 0, 0), wood=None, batten=None, bolt=None):
    """Closed braced crate (cube of side s): plank body, dark edge battens, an X brace on the four sides,
    corner bolts."""
    at = Vector(at)
    wood = wood or m.slot("FnWood")
    batten = batten or m.slot("FnWoodDark")
    bolt = bolt or part(m, "Bolts", "FnMetal")
    h = s / 2
    b = max(0.16, s * 0.1)
    wood.box((s - 0.08, s - 0.08, s - 0.08), loc=at + V(0, 0, h), bevel=0.04)
    for sx in (-1, 1):
        for sz in (-1, 1):
            batten.box((b, s, b), loc=at + V(sx * (h - b / 2), 0, h + sz * (h - b / 2)), bevel=0.03)
            batten.box((s, b, b), loc=at + V(0, sx * (h - b / 2), h + sz * (h - b / 2)), bevel=0.03)
        for sy in (-1, 1):
            batten.box((b, b, s), loc=at + V(sx * (h - b / 2), sy * (h - b / 2), h), bevel=0.03)
    t = 0.07
    for sy in (-1, 1):
        for d in (1, -1):
            batten.box_between(at + V(-h + b, sy * (h + t / 2 - 0.02), h - d * (h - b)), at + V(h - b, sy * (h + t / 2 - 0.02), h + d * (h - b)),
                               (b * 0.8, t), bevel=0.015)
    for sx in (-1, 1):
        for d in (1, -1):
            batten.box_between(at + V(sx * (h + t / 2 - 0.02), -h + b, h - d * (h - b)), at + V(sx * (h + t / 2 - 0.02), h - b, h + d * (h - b)),
                               (t, b * 0.8), bevel=0.015)
    for sx in (-1, 1):
        for sz in (-1, 1):
            bolt.bolt(at + V(sx * (h - b / 2), -h, h + sz * (h - b / 2)), normal=(0, -1, 0), r=0.07)


def box_crate_feet(m, at, w, d, h, wood, batten):
    """Small crate-style foot block (leaderboard / bay feet): box with a dark X on the front face."""
    at = Vector(at)
    wood.box((w, d, h), loc=at + V(0, 0, h / 2), bevel=0.06)
    b = 0.14
    for sz in (0, 1):
        batten.box((w + 0.04, d + 0.04, b), loc=at + V(0, 0, b / 2 + sz * (h - b)), bevel=0.03)
    for d_ in (1, -1):
        batten.box_between(at + V(-w / 2 + 0.12, -d / 2 - 0.02, h / 2 - d_ * (h / 2 - 0.2)), at + V(w / 2 - 0.12, -d / 2 - 0.02, h / 2 + d_ * (h / 2 - 0.2)),
                           (0.13, 0.06), bevel=0.015)


# ------------------------------------------------------------------ small shapes

def faceted_rock(piece, at, size, seed, n=14):
    pts = K.rock_points(seed, size, n=n, flat_bottom=0.12)
    piece.hull(pts, loc=at, rot=(0, 0, random.Random(seed).uniform(0, 360)))


def plank_seams_y(piece, x0, x1, y, z0, z1, pitch=1.2, t=0.04):
    """Vertical seam strips on a face lying in the XZ plane at y (faces -Y)."""
    n = max(2, int(round((x1 - x0) / pitch)))
    for i in range(1, n):
        x = x0 + (x1 - x0) * i / n
        piece.box((0.07, t, z1 - z0), loc=(x, y - t / 2, (z0 + z1) / 2), bevel=0.0)


def hammer(m, head_at, handle_dir, length=3.5, s=1.0, head=None, handle=None):
    """Starter hammer: faceted steel head + warm brown handle. head_at = centre of the head; the handle
    runs along handle_dir (unit vector in the XZ plane) away from the head. Lies in the XZ plane (faces -Y)."""
    head = head or part(m, "HammerHead", "FnSteel")
    handle = handle or part(m, "HammerHandle", "FnHandle")
    c = Vector(head_at)
    d = Vector(handle_dir).normalized()
    side = V(-d.z, 0, d.x)   # along the head
    end = c + d * (length - 0.45 * s)
    handle.box_between(c + d * 0.25 * s, end, (0.32 * s, 0.3 * s), bevel=0.06)
    hw, hh, hd = 0.75 * s, 0.32 * s, 0.32 * s
    pts = []
    for k, (a, r) in enumerate(((-hw, 0.85), (-hw * 0.8, 1.0), (hw * 0.55, 1.0), (hw, 0.7))):
        for dz in (-1, 1):
            for dy in (-1, 1):
                pts.append(c + side * a + d * dz * hh * r + V(0, dy * hd * r, 0))
    head.hull(pts)
    # a darker collar where the handle enters the head
    handle.box_between(c + d * 0.28 * s, c + d * 0.5 * s, (0.38 * s, 0.36 * s), bevel=0.05)
