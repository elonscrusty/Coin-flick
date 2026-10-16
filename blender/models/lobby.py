"""Sheet 01: Lobby building kit (equipment workshop, specimen gallery, Start Hunt kiosk shelter,
leaderboard alcove, public courtyard shelter, equipment storage shed).

Every building is one model whose origin is the floor centre of its footprint (ground level, not
the top of its foundation) and whose open front / entrance faces -Y (Roblox -Z). To keep MeshParts
a sane size each building splits its slots into named pieces (Foundation, Posts, Roof, Walls,
Interior ...). Surfaces the game writes on (signs, the leaderboard, the kiosk screen) are separate
Slate pieces with an attach point at the centre of their front face; lights are Lamp (Neon) with
Light* attach points for PointLights; display spots in the gallery are Display* attach points.
"""

import math

from mathutils import Vector

import ctrkit as K
from ctrkit import register
from models import _lobbyparts as L
from models._lobbyparts import V, part
from models.courtyard import bench

S01 = "01"
REF = "01_lobby_building_kit.png"


def _collider(m, w, d, h):
    m.extra["collider"] = {"size": K.roblox_size((w, d, h)), "offset": K.to_roblox((0, 0, h / 2))}


def foundation(m, w, d, h=1.0, front_blocks=6, seed=1):
    """Dark base course + stone slab platform (top at z = h)."""
    base = part(m, "FoundationBase", "FrameDark")
    stone, stone2 = part(m, "Foundation", "Concrete"), part(m, "Foundation2", "ConcreteDark")
    base.box((w, d, h * 0.5), loc=(0, 0, h * 0.25), bevel=0.08)
    L.block_course([stone, stone2], -w / 2, w / 2, -d / 2 + 0.6, h * 0.45, h, 1.2, front_blocks, seed=seed, gap=0.08)
    L.block_course([stone2, stone], -w / 2, w / 2, d / 2 - 0.6, h * 0.45, h, 1.2, front_blocks, seed=seed + 1, gap=0.08)
    for sx in (-1, 1):
        L.block_course([stone, stone2], -d / 2 + 1.2, d / 2 - 1.2, sx * (w / 2 - 0.6), h * 0.45, h, 1.2, max(2, int(d / 4)),
                       seed=seed + 2 + sx, gap=0.08, along="y")
    stone.box((w - 2.3, d - 2.3, h * 0.55), loc=(0, 0, h - h * 0.275), bevel=0.06)


def steel_post(m, x, y, z0, z1, s=1.2, bands=(), name="Posts"):
    posts = part(m, name, "Frame")
    bolt = part(m, "Bolts", "SteelLight")
    if z1 > z0 + 0.05:
        posts.box((s, s, z1 - z0), loc=(x, y, (z0 + z1) / 2), bevel=0.08)
    for z in bands:
        posts.box((s + 0.35, s + 0.35, 0.7), loc=(x, y, z), bevel=0.06)
        for nx, ny in ((0, -1), (1, 0), (-1, 0), (0, 1)):
            for o in (-0.3, 0.3):
                bolt.bolt((x + nx * (s / 2 + 0.18) + (o if ny else 0), y + ny * (s / 2 + 0.18) + (o if nx else 0), z),
                          normal=(nx, ny, 0), r=0.09)


def stone_pedestal(m, x, y, z0, h, s=2.0, name="PostStone"):
    stone = part(m, name, "Concrete")
    stone.box((s, s, h), loc=(x, y, z0 + h / 2), bevel=0.1)
    part(m, "PostCaps", "FrameDark").box((s + 0.1, s + 0.1, 0.3), loc=(x, y, z0 + h + 0.1), bevel=0.05)


def crate(m, at, s=1.2, name="Props"):
    at = Vector(at)
    w = part(m, name, "Wood")
    e = part(m, name + "Trim", "WoodDark")
    w.box((s, s, s), loc=at + V(0, 0, s / 2), bevel=0.05)
    for sx in (-1, 1):
        for sy in (-1, 1):
            e.box((0.16, 0.16, s + 0.02), loc=at + V(sx * (s / 2 - 0.05), sy * (s / 2 - 0.05), s / 2), bevel=0.03)
    e.box((s + 0.02, s + 0.02, 0.14), loc=at + V(0, 0, s - 0.07), bevel=0.03)
    e.box_between(at + V(-s / 2 + 0.1, -s / 2 - 0.02, 0.1), at + V(s / 2 - 0.1, -s / 2 - 0.02, s - 0.1), (0.14, 0.06))


def barrel(m, at, r=0.55, h=1.4, name="Props"):
    at = Vector(at)
    part(m, name + "Steel", "Frame").cyl(r, r, h, seg=10, loc=at + V(0, 0, h / 2))
    for z in (0.2, h - 0.2):
        part(m, name + "Bands", "FrameDark").cyl(r + 0.04, r + 0.04, 0.12, seg=10, loc=at + V(0, 0, z))


def hammer_icon(piece, at, s=1.0, rot_y=0.0):
    """Flat crossed-hammer emblem facing -Y (two handles + heads) centred at at."""
    at = Vector(at)
    for sgn in (-1, 1):
        a = sgn * 40
        piece.box((0.22 * s, 0.1, 1.5 * s), loc=at, rot=(0, a, 0), bevel=0.02)
        ang = math.radians(a)
        hx, hz = math.sin(ang) * 0.6 * s, math.cos(ang) * 0.6 * s
        piece.box((0.8 * s, 0.12, 0.34 * s), loc=at + V(hx, -0.01, hz), rot=(0, a, 0), bevel=0.03)


# ------------------------------------------------------------------ 1. equipment workshop

@register("Lobby_Workshop", S01, "Open-front equipment workshop 23 x 15, about 13 tall: stone foundation + front steps, stone pedestals with steel posts, timber shed roof sloping to the back, back and side walls, workbench + tool board, shelf, compressor, crossed-hammer Sign (Slate), hanging lanterns. Origin ground centre, open front -Y.",
          ref=(REF, (5, 70, 940, 520)))
def workshop(m):
    W, D, H = 22.0, 14.0, 1.0
    foundation(m, W, D, H, front_blocks=7, seed=3)
    L.steps(part(m, "Steps", "Concrete"), V(0, -D / 2, H), 10.0, 3, rise=0.33, run=0.6)
    wood = part(m, "RoofBeams", "Wood")
    walls = part(m, "Walls", "Plaster")
    trim = part(m, "WallTrim", "Wood")
    # posts: stone pedestals, steel posts with bolted bands
    zf_top, zb_top = 11.6, 10.0       # roof beam tops front / back (shed roof falls to the back)
    # Master Prompt 4 sec. 11: only the two outer front posts (no posts across the display frontage),
    # slimmer steel and a low stone foot so the equipment behind them stays visible.
    for x in (-W / 2 + 1.0, W / 2 - 1.0):
        stone_pedestal(m, x, -D / 2 + 1.0, H, 1.3, s=1.7)
        steel_post(m, x, -D / 2 + 1.0, H + 1.3, zf_top - 0.6, s=1.15, bands=(H + 1.8, 7.4, zf_top - 1.2))
    for x in (-W / 2 + 1.0, W / 2 - 1.0):
        stone_pedestal(m, x, D / 2 - 1.0, H, 1.3, s=1.7)
        steel_post(m, x, D / 2 - 1.0, H + 1.3, zb_top - 0.6, s=1.15, bands=(H + 1.8, zb_top - 1.2))
    for x in (-W / 2 + 1.0, W / 2 - 1.0):
        L.wall_light(m, (x, -D / 2 + 0.2, 6.0), (0, -1, 0), h=1.5)
    # roof frame: front + back beams, side beams, rafters, deck, dark cap
    wood.box((W + 1.6, 1.1, 1.2), loc=(0, -D / 2 + 1.0, zf_top - 0.6), bevel=0.1)
    wood.box((W + 1.6, 1.1, 1.2), loc=(0, D / 2 - 1.0, zb_top - 0.6), bevel=0.1)
    for x in (-W / 2 + 1.0, -3.8, 3.8, W / 2 - 1.0):  # roof beams stay; the middle ones hang from the front beam
        wood.box_between((x, -D / 2 + 1.0, zf_top - 0.9), (x, D / 2 - 1.0, zb_top - 0.9), (0.9, 1.0))
    rafters = part(m, "Rafters", "Wood")
    for i in range(8):
        x = -W / 2 + 2.3 + i * (W - 4.6) / 7
        rafters.box_between((x, -D / 2 - 0.6, zf_top + 0.2), (x, D / 2 + 0.6, zb_top + 0.2), (0.55, 0.6))
    ang = math.degrees(math.atan2(zf_top - zb_top, D - 2.0))
    deck = part(m, "RoofDeck", "WoodDark")
    deck.box((W + 2.6, D + 2.6, 0.35), loc=(0, 0, (zf_top + zb_top) / 2 + 0.7), rot=(-ang, 0, 0), bevel=0.06)
    cap = part(m, "Roof", "FrameDark")
    cap.box((W + 2.4, D + 2.4, 0.3), loc=(0, 0, (zf_top + zb_top) / 2 + 1.0), rot=(-ang, 0, 0), bevel=0.06)
    fascia = part(m, "Fascia", "Wood")
    fy = -D / 2 - 1.45
    fz = (zf_top + zb_top) / 2 + 0.85 - fy * math.tan(math.radians(ang))
    fascia.box((W + 3.1, 0.7, 1.2), loc=(0, fy, fz - 0.15), rot=(-ang, 0, 0), bevel=0.08)
    by_ = D / 2 + 1.45
    fascia.box((W + 3.1, 0.7, 1.2), loc=(0, by_, (zf_top + zb_top) / 2 + 0.7 - by_ * math.tan(math.radians(ang))), rot=(-ang, 0, 0), bevel=0.08)
    for sx in (-1, 1):
        fascia.box((0.7, D + 3.1, 1.2), loc=(sx * (W / 2 + 1.45), 0, (zf_top + zb_top) / 2 + 0.7), rot=(-ang, 0, 0), bevel=0.08)
    # back wall + half side walls (cream panels framed in timber)
    walls.box((W - 2.4, 0.5, zb_top - H - 1.0), loc=(0, D / 2 - 1.0, H + (zb_top - H - 1.0) / 2), bevel=0.06)
    for sx in (-1, 1):
        walls.box((0.5, D / 2 - 1.0, 3.2), loc=(sx * (W / 2 - 1.0), D / 4 - 0.5, H + 1.6), bevel=0.06)
        trim.box((0.7, D / 2 - 0.6, 0.45), loc=(sx * (W / 2 - 1.0), D / 4 - 0.3, H + 3.2), bevel=0.05)
    trim.box((W - 2.4, 0.7, 0.45), loc=(0, D / 2 - 1.15, H + 3.2), bevel=0.05)
    for x in (-6.5, 0.0, 6.5):
        trim.box((0.5, 0.7, zb_top - H - 1.0), loc=(x, D / 2 - 1.15, H + (zb_top - H - 1.0) / 2), bevel=0.05)
    # interior: workbench + tool board (left), sign (centre), shelf + compressor (right)
    inter = part(m, "Interior", "Wood")
    steel = part(m, "InteriorSteel", "Frame")
    bx, by = -4.0, D / 2 - 2.1
    inter.box((7.0, 1.7, 0.35), loc=(bx, by, H + 2.6), bevel=0.06)
    inter.box((6.6, 1.4, 1.5), loc=(bx, by + 0.1, H + 0.85), bevel=0.06)
    for i in range(3):
        steel.box((1.9, 0.08, 0.35), loc=(bx - 2.2 + i * 2.2, by - 0.62, H + 1.25), bevel=0.02)
    inter.box((6.6, 0.3, 2.8), loc=(bx, D / 2 - 1.4, H + 4.6), bevel=0.06)
    tools = part(m, "Tools", "Steel")
    for i in range(5):
        x = bx - 2.6 + i * 1.3
        inter.box((0.16, 0.12, 1.7), loc=(x, D / 2 - 1.62, H + 4.3), bevel=0.02)
        tools.box((0.75 if i % 2 else 0.5, 0.2, 0.32), loc=(x, D / 2 - 1.66, H + 5.2), bevel=0.04)
    sign = m.piece("Sign", "Slate", note="workshop sign board (crossed hammers); SurfaceGui optional")
    sign.box((4.4, 0.25, 2.4), loc=(4.0, D / 2 - 1.4, H + 6.8), bevel=0.06)
    trim.box((4.9, 0.3, 2.9), loc=(4.0, D / 2 - 1.27, H + 6.8), bevel=0.06)
    hammer_icon(part(m, "SignIcon", "Amber"), V(4.0, D / 2 - 1.6, H + 6.8), s=1.1)
    m.attach["Sign"] = (4.0, D / 2 - 1.6, H + 6.8)
    sx0 = 7.6
    for z in (H + 0.15, H + 1.8, H + 3.4, H + 5.0):
        inter.box((3.4, 1.4, 0.2), loc=(sx0, D / 2 - 2.0, z), bevel=0.04)
    for x in (sx0 - 1.6, sx0 + 1.6):
        inter.box((0.22, 1.4, 5.1), loc=(x, D / 2 - 2.0, H + 2.55), bevel=0.04)
    for i, z in enumerate((H + 1.9, H + 3.5)):
        for j in range(3):
            (part(m, "Crates", "Amber") if (i + j) % 2 else steel).box((0.8, 0.9, 0.8), loc=(sx0 - 1.0 + j * 1.0, D / 2 - 2.0, z + 0.5), bevel=0.06)
    red = part(m, "Compressor", "Red")
    red.cyl(0.75, 0.75, 2.2, seg=10, loc=(4.8, 1.0, H + 1.05), rot=(0, 90, 0))
    for sgn in (-1, 1):
        red.cyl(0.6, 0.3, 0.25, seg=10, loc=(4.8 + sgn * 1.2, 1.0, H + 1.05), rot=(0, sgn * 90, 0))
    steel.box((1.0, 0.8, 0.7), loc=(4.6, 1.0, H + 2.1), bevel=0.06)
    for sx in (-1, 1):
        part(m, "Wheels", "Rubber").cyl(0.3, 0.3, 0.2, seg=8, loc=(4.8 + sx * 0.7, 1.75, H + 0.3), rot=(90, 0, 0))
    # hanging lanterns from the rafters
    glow = m.piece("Glow", "Lamp")
    lf = part(m, "Lanterns", "Frame")
    for i, (x, y) in enumerate(((-6.2, -2.0), (0.0, -2.0), (6.2, -2.0), (-3.0, 2.5), (3.0, 2.5))):
        zt = zf_top + 0.2 - (y + D / 2 + 0.6) / (D + 1.2) * (zf_top - zb_top) - 0.3
        c = L.hanging_lantern(m, (x, y, zt), drop=0.5, s=0.75, frame=lf, glow=glow)
        m.attach["Light%d" % (i + 1)] = tuple(c)
    # planters + crate at the front corners
    L.planter_box(m, V(-W / 2 + 0.2, -D / 2 - 1.3, 0), 3.2, 2.0, 1.3, seed=11, blocks=2)
    L.planter_box(m, V(W / 2 - 0.2, -D / 2 - 1.3, 0), 3.2, 2.0, 1.3, seed=13, blocks=2)
    crate(m, (-W / 2 + 2.6, -D / 2 + 2.6, H), 1.5)
    m.attach["Counter"] = (bx, by - 1.0, H)
    m.attach["Entrance"] = (0, -D / 2 - 2.0, 0)
    _collider(m, W, D, H)


# ------------------------------------------------------------------ 2. specimen gallery

@register("Lobby_Gallery", S01, "Specimen gallery 26 x 16, about 15 tall: stone foundation + steps with wooden rails, two glazed wings (Windows piece, Glass), stone pillars, a gabled entrance block with a geode Emblem, hip roofs, five display pedestals inside (Display1..5 attach = pedestal tops). Origin ground centre, entrance -Y.",
          ref=(REF, (950, 120, 1530, 500)))
def gallery(m):
    W, D, H = 26.0, 16.0, 1.2
    foundation(m, W, D, H, front_blocks=8, seed=5)
    L.steps(part(m, "Steps", "Concrete"), V(0, -D / 2, H), 6.0, 3, rise=0.4, run=0.65)
    stone, stone2 = part(m, "Walls", "Concrete"), part(m, "Walls2", "ConcreteDark")
    frame = part(m, "WindowFrames", "Frame")
    wood = part(m, "Timber", "Wood")
    roof = part(m, "Roof", "FrameDark")
    glass = m.piece("Windows", "Window", transparency=0.6, note="display windows, Glass material, transparency 0.6")
    wy = -D / 2 + 1.6           # wing front wall line
    ey = -D / 2 + 0.9           # entrance block front line
    top = 9.0
    # wings: low stone sill, big window, timber lintel, dark band; side + back walls
    for sx in (-1, 1):
        x0, x1 = sx * 4.6, sx * (W / 2 - 1.2)
        xa, xb = min(x0, x1), max(x0, x1)
        xc, ww = (xa + xb) / 2, xb - xa
        stone2.box((ww, 0.9, 1.3), loc=(xc, wy, H + 0.65), bevel=0.08)
        glass.box((ww - 0.4, 0.12, 4.6), loc=(xc, wy, H + 1.3 + 2.3), bevel=0.02)
        for x in (xa + 0.15, xc, xb - 0.15):
            frame.box((0.35, 0.5, 4.8), loc=(x, wy, H + 1.3 + 2.4), bevel=0.04)
        frame.box((ww, 0.5, 0.3), loc=(xc, wy, H + 1.3 + 0.1), bevel=0.04)
        wood.box((ww + 0.4, 1.0, 0.8), loc=(xc, wy, H + 6.4), bevel=0.08)
        stone.box((ww, 0.8, top - H - 6.8), loc=(xc, wy + 0.1, H + 6.8 + (top - H - 6.8) / 2), bevel=0.06)
        stone.box((0.8, D - 2.4, top - H), loc=(sx * (W / 2 - 1.2), 0.6, H + (top - H) / 2), bevel=0.08)
        # hip roof over the wing
        roof.box((ww + 2.4, D + 0.6, 1.9), loc=(xc + sx * 0.3, 0.4, top + 0.95), taper=(0.78, 0.8), bevel=0.1)
        wood.box((ww + 2.5, D + 0.7, 0.35), loc=(xc + sx * 0.3, 0.4, top + 0.1), bevel=0.06)
        # display pedestals behind the glass
        for k, x in enumerate((xc - ww / 4, xc + ww / 4)):
            part(m, "Pedestals", "FrameDark").box((1.8, 1.8, 0.5), loc=(x, wy + 2.4, H + 0.25), bevel=0.06)
            part(m, "PedestalTops", "Concrete").box((1.5, 1.5, 1.6), loc=(x, wy + 2.4, H + 0.5 + 0.8), bevel=0.08)
            m.attach["Display%d" % (k + (1 if sx < 0 else 3))] = (x, wy + 2.4, H + 2.1)
    stone.box((W - 2.4, 0.8, top - H), loc=(0, D / 2 - 0.4, H + (top - H) / 2), bevel=0.08)
    # pillars: corners and flanking the entrance, with dark caps, wall lights on the entrance pair
    for x in (-W / 2 + 1.0, -4.6, 4.6, W / 2 - 1.0):
        y = ey - 0.2 if abs(x) < 5 else wy - 0.2
        part(m, "PillarBases", "FrameDark").box((2.2, 2.2, 0.5), loc=(x, y, H + 0.25), bevel=0.06)
        part(m, "Pillars", "Concrete").box((1.8, 1.8, top - H + 0.6), loc=(x, y, H + (top - H + 0.6) / 2), bevel=0.1)
        part(m, "PillarCaps", "FrameDark").box((2.2, 2.2, 0.6), loc=(x, y, top + 0.9), bevel=0.06)
        if abs(x) < 5:
            L.wall_light(m, (x, y - 0.9, 5.4), (0, -1, 0), h=1.6)
    # entrance block: door frame, timber panel above, gable with emblem, gable roof
    for sx in (-1, 1):
        stone.box((1.4, 0.8, 6.0), loc=(sx * 3.0, ey, H + 3.0), bevel=0.06)
        wood.box((0.45, 0.9, 5.3), loc=(sx * 2.1, ey - 0.05, H + 2.65), bevel=0.05)
    wood.box((4.7, 0.9, 0.5), loc=(0, ey - 0.05, H + 5.3), bevel=0.05)
    part(m, "EntrancePanel", "WoodDark").box((7.4, 0.7, top + 0.6 - (H + 5.55)), loc=(0, ey + 0.05, (H + 5.55 + top + 0.6) / 2), bevel=0.06)
    gz0, gz1 = top + 0.6, 14.2
    part(m, "Gable", "Wood").prism([(-4.6, gz0), (4.6, gz0), (0, gz1)], 0.8, loc=(0, ey + 0.1, 0), bevel=0.06)
    part(m, "GableTrim", "Wood").box((8.6, 1.0, 0.5), loc=(0, ey, gz0), bevel=0.06)
    run = math.hypot(5.6, gz1 - gz0 + 0.6)
    ang = math.degrees(math.atan2(gz1 - gz0 + 0.6, 5.6))
    for sx in (-1, 1):
        roof.box((run, D + 1.2, 0.6), loc=(sx * 2.7, 0.3, (gz0 + gz1) / 2 + 0.25), rot=(0, sx * ang, 0), bevel=0.08)
    part(m, "RoofRidge", "Wood").box((2.2, 2.2, 1.6), loc=(0, ey + 1.6, gz1 + 0.75), bevel=0.1)
    # the centre block's own side walls (behind the gable)
    for sx in (-1, 1):
        stone.box((0.8, D - 2.0, top - H), loc=(sx * 4.2, 0.9, H + (top - H) / 2), bevel=0.06)
    em = part(m, "Emblem", "Amber", "Neon")
    part(m, "EmblemFrame", "Frame").prism(L.octagon(1.35), 0.4, loc=(0, ey - 0.3, 11.4), bevel=0.06)
    L.gem(em, V(0, ey - 0.6, 11.35), 1.05)
    m.attach["Emblem"] = (0, ey - 0.8, 11.4)
    m.attach["Sign"] = (0, ey - 0.4, H + 7.3)
    # back centre display + entrance rails + planters
    part(m, "Pedestals", "FrameDark").box((2.2, 2.2, 0.5), loc=(0, D / 2 - 3.0, H + 0.25), bevel=0.06)
    part(m, "PedestalTops", "Concrete").box((1.9, 1.9, 1.7), loc=(0, D / 2 - 3.0, H + 0.5 + 0.85), bevel=0.08)
    m.attach["Display5"] = (0, D / 2 - 3.0, H + 2.2)
    rail = part(m, "Rails", "Wood")
    for sx in (-1, 1):
        x = sx * 3.3
        rail.box((0.45, 0.45, 1.6), loc=(x, -D / 2 - 1.75, 0.8), bevel=0.05)
        rail.box((0.45, 0.45, 2.3), loc=(x, -D / 2 + 0.1, H + 1.1 - 0.4), bevel=0.05)
        rail.box_between((x, -D / 2 - 1.75, 1.55), (x, -D / 2 + 0.1, H + 1.6), (0.32, 0.32))
    for sx in (-1, 1):
        L.planter_box(m, V(sx * (W / 2 - 1.0), -D / 2 - 1.2, 0), 2.4, 2.0, 1.4, seed=20 + sx, blocks=1)
        L.planter_box(m, V(sx * 8.8, -D / 2 - 0.9, 0), 4.6, 1.4, 1.1, seed=24 + sx, blocks=2)
    glow = m.piece("Glow", "Lamp")
    c = L.hanging_lantern(m, (0, ey + 3.0, top), drop=0.6, s=0.8, glow=glow, frame=part(m, "Lanterns", "Frame"))
    m.attach["Light1"] = tuple(c)
    m.attach["Entrance"] = (0, -D / 2 - 2.2, 0)
    _collider(m, W, D, H)


# ------------------------------------------------------------------ 3. start hunt kiosk shelter

@register("Lobby_KioskShelter", S01, "Start Hunt kiosk shelter 9.6 x 6.4, about 9.6 tall: stone base, stone back wall, steel side pillars with wall lights, dark kiosk body with a tilted Screen (Slate, SurfaceGui START HUNT) in an Accent frame, timber counter, thick timber roof, hanging lantern. Origin ground centre, front -Y.",
          ref=(REF, (20, 615, 395, 915)))
def kiosk_shelter(m):
    W, D, H = 9.6, 6.4, 0.7
    stone, stone2, frame, dark, wood = (m.slot("Concrete"), m.slot("ConcreteDark"), m.slot("Frame"), m.slot("FrameDark"), m.slot("Wood"))
    dark.box((W, D, 0.35), loc=(0, 0, 0.175), bevel=0.06)
    L.block_course([stone, stone2], -W / 2, W / 2, -D / 2 + 0.7, 0.3, H, 1.4, 4, seed=2)
    stone.box((W - 0.4, D - 1.6, H - 0.3), loc=(0, 0.6, 0.3 + (H - 0.3) / 2), bevel=0.05)
    # back wall (stone courses) with angled stone shoulders round the kiosk
    for k, (z0, z1) in enumerate(((H, 2.4), (2.4, 4.1), (4.1, 5.8), (5.8, 7.6))):
        L.block_course([stone, stone2], -3.4, 3.4, D / 2 - 0.9, z0, z1, 1.0, 3 + k % 2, seed=30 + k, gap=0.08)
    for sx in (-1, 1):
        stone.box((1.2, 2.0, 5.2), loc=(sx * 2.4, 1.6, H + 2.6), taper=(0.7, 1.0), bevel=0.08)
    # steel side pillars on stone pedestals, wall lights
    for sx in (-1, 1):
        x = sx * (W / 2 - 0.9)
        stone.box((1.6, 1.6, 1.8), loc=(x, 1.4, H + 0.9), bevel=0.08)
        frame.box((1.0, 1.0, 8.4 - H - 1.8), loc=(x, 1.4, H + 1.8 + (8.4 - H - 1.8) / 2), bevel=0.07)
        for z in (H + 2.2, 7.6):
            frame.box((1.3, 1.3, 0.45), loc=(x, 1.4, z), bevel=0.05)
        L.wall_light(m, (x, 0.9, 4.8), (0, -1, 0), h=1.4)
    # kiosk body: dark block with a timber counter and a tilted screen
    dark.box((3.8, 1.8, 3.2), loc=(0, 1.2, H + 1.6), bevel=0.08)
    frame.box((4.0, 2.0, 0.35), loc=(0, 1.2, H + 3.3), bevel=0.05)
    wood.box((4.6, 1.0, 0.35), loc=(0, 0.0, H + 1.6), bevel=0.05)
    frame.box((3.6, 0.8, 1.3), loc=(0, 0.25, H + 0.75), bevel=0.06)
    acc = m.slot("Accent", "Metal")
    acc.box((3.0, 0.3, 2.2), loc=(0, 1.15, H + 4.6), rot=(-12, 0, 0), bevel=0.06)
    scr = m.piece("Screen", "Slate", note="START HUNT screen; SurfaceGui on its front")
    scr.box((2.6, 0.2, 1.8), loc=(0, 1.0, H + 4.6), rot=(-12, 0, 0), bevel=0.04)
    frame.box((3.4, 0.6, 2.6), loc=(0, 1.45, H + 4.6), rot=(-12, 0, 0), bevel=0.06)
    m.attach["Screen"] = (0, 0.87, H + 4.6)
    # roof: thick timber slab on beams, dark under-trim, hanging lantern
    for y in (-D / 2 + 0.8, 1.4):
        wood.box((W + 0.6, 0.8, 0.7), loc=(0, y, 8.4 + 0.35), bevel=0.08)
    m.slot("WoodDark").box((W + 1.0, D + 0.4, 0.5), loc=(0, -0.2, 9.0), bevel=0.06)
    for i in range(4):
        x = -W / 2 - 0.4 + (W + 0.8) * (i + 0.5) / 4
        wood.box(((W + 0.8) / 4 - 0.05, D + 0.6, 0.55), loc=(x, -0.2, 9.5), bevel=0.08)
    glow = m.piece("Glow", "Lamp")
    c = L.hanging_lantern(m, (0, -1.4, 8.75), drop=0.3, s=0.8, glow=glow)
    m.attach["Light"] = tuple(c)
    # props: crate left, planter right
    crate(m, (-W / 2 + 0.4, -D / 2 - 0.5, 0), 1.2)
    L.planter_box(m, V(W / 2 - 0.3, -D / 2 - 0.4, 0), 1.6, 1.6, 1.0, seed=40, blocks=1)
    m.attach["Prompt"] = (0, -0.8, 2.5)
    _collider(m, W, D, H)


# ------------------------------------------------------------------ 4. leaderboard alcove

@register("Lobby_LeaderboardAlcove", S01, "Leaderboard alcove 13 x 5.4, about 9.5 tall: stone pillars with wall lights, timber-framed Board (Slate, SurfaceGui for the top hunters list), thick timber roof, hanging lantern, bench, planters. Origin ground centre, front -Y; Board attach = board face centre.",
          ref=(REF, (415, 615, 775, 915)))
def leaderboard_alcove(m):
    W, D, H = 12.6, 5.4, 0.6
    stone, stone2, frame, dark, wood = (m.slot("Concrete"), m.slot("ConcreteDark"), m.slot("Frame"), m.slot("FrameDark"), m.slot("Wood"))
    dark.box((W - 2.0, D, 0.3), loc=(0, 0, 0.15), bevel=0.06)
    L.slab_grid(stone, V(0, 0, 0.3), W - 2.2, D - 0.2, 4, 2, h=H - 0.3, gap=0.08)
    for sx in (-1, 1):
        x = sx * 4.3
        dark.box((2.2, 2.2, 0.5), loc=(x, 1.2, H + 0.25), bevel=0.06)
        stone.box((1.9, 1.9, 7.2), loc=(x, 1.2, H + 0.5 + 3.6), bevel=0.1)
        stone2.box((2.0, 2.0, 0.5), loc=(x, 1.2, H + 2.6), bevel=0.06)
        wood.box((0.5, 0.5, 6.6), loc=(x - sx * 1.0, 0.5, H + 0.5 + 3.3), bevel=0.05)
        L.wall_light(m, (x, 0.25, 5.4), (0, -1, 0), h=1.5)
    # board: timber frame, dark board face
    wood.box((6.8, 0.7, 0.6), loc=(0, 1.6, H + 7.3), bevel=0.06)
    wood.box((6.8, 0.7, 0.5), loc=(0, 1.6, H + 2.0), bevel=0.06)
    dark.box((6.4, 0.5, 5.2), loc=(0, 1.75, H + 4.6), bevel=0.06)
    board = m.piece("Board", "Slate", note="leaderboard face; SurfaceGui (TOP HUNTERS list) on its front")
    board.box((5.8, 0.15, 4.6), loc=(0, 1.42, H + 4.65), bevel=0.04)
    m.attach["Board"] = (0, 1.34, H + 4.65)
    stone.box((6.8, 1.0, 1.6), loc=(0, 2.1, H + 0.8), bevel=0.08)
    # roof
    for y in (-0.9, 2.2):
        wood.box((W - 1.4, 0.8, 0.7), loc=(0, y, H + 7.95), bevel=0.08)
    m.slot("WoodDark").box((W - 1.0, D, 0.45), loc=(0, 0.6, H + 8.5), bevel=0.06)
    for i in range(5):
        x = -(W - 0.8) / 2 + (W - 0.8) * (i + 0.5) / 5
        wood.box(((W - 0.8) / 5 - 0.05, D + 0.4, 0.6), loc=(x, 0.6, H + 9.0), bevel=0.08)
    glow = m.piece("Glow", "Lamp")
    c = L.hanging_lantern(m, (0, -0.5, H + 7.6), drop=0.25, s=0.75, glow=glow)
    m.attach["Light"] = tuple(c)
    bench(m, at=(0, -1.1, H), length=4.6)
    m.attach["Seat"] = (0, -1.1, H + 1.65)
    for sx in (-1, 1):
        L.planter_box(m, V(sx * (W / 2 - 0.9), -0.6, 0), 1.8, 1.8, 1.5, seed=50 + sx, blocks=1)
    _collider(m, W, D, H)


# ------------------------------------------------------------------ 5. courtyard shelter

@register("Lobby_Shelter", S01, "Public courtyard shelter 14 x 14, about 12.5 tall: stone platform + front steps, four stone columns with steel brackets, timber beams and knee braces, dark hip roof, benches on three sides, centre planter, hanging lantern. Origin ground centre, open front -Y.",
          ref=(REF, (785, 615, 1195, 915)))
def shelter(m):
    W, H = 14.0, 0.9
    dark, frame = m.slot("FrameDark"), m.slot("Frame")
    stone = part(m, "Platform", "Concrete")
    dark.box((W, W, 0.4), loc=(0, 0, 0.2), bevel=0.06)
    L.slab_grid(stone, V(0, 0, 0.35), W - 0.3, W - 0.3, 4, 4, h=H - 0.35, gap=0.08)
    L.steps(part(m, "Steps", "Concrete"), V(0, -W / 2, H), 5.0, 2, rise=0.4, run=0.6)
    cols = part(m, "Columns", "Concrete")
    wood = part(m, "Beams", "Wood")
    c = W / 2 - 1.2
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * c, sy * c
            dark.box((1.8, 1.8, 0.6), loc=(x, y, H + 0.3), bevel=0.06)
            cols.box((1.4, 1.4, 6.8), loc=(x, y, H + 0.6 + 3.4), bevel=0.1)
            steel_post(m, x, y, H + 3.6, H + 3.6, s=1.4, bands=(H + 3.9, H + 7.0))
            wood.box_between((x, y, H + 5.6), (x - sx * 1.8, y, H + 7.6), (0.45, 0.45))
            wood.box_between((x, y, H + 5.6), (x, y - sy * 1.8, H + 7.6), (0.45, 0.45))
    zb = H + 7.9
    for s in (-1, 1):
        wood.box((W - 0.8, 0.9, 1.0), loc=(0, s * c, zb), bevel=0.08)
        wood.box((0.9, W - 0.8, 1.0), loc=(s * c, 0, zb), bevel=0.08)
    rafters = part(m, "Rafters", "Wood")
    for i in range(5):
        x = -c + 2 * c * (i + 0.5) / 5
        rafters.box((0.45, W - 1.6, 0.5), loc=(x, 0, zb + 0.4), bevel=0.05)
    part(m, "Soffit", "WoodDark").box((W + 1.2, W + 1.2, 0.3), loc=(0, 0, zb + 0.75), bevel=0.05)
    roof = part(m, "Roof", "FrameDark")
    roof.box((W + 1.8, W + 1.8, 2.6), loc=(0, 0, zb + 0.9 + 1.3), taper=(0.28, 0.28), bevel=0.12)
    part(m, "RoofCap", "Frame").box((4.6, 4.6, 0.45), loc=(0, 0, zb + 0.9 + 2.6 + 0.15), bevel=0.06)
    for s in (-1, 1):
        part(m, "Fascia", "Wood").box((W + 1.9, 0.4, 0.55), loc=(0, s * (W / 2 + 0.85), zb + 0.95), bevel=0.05)
        part(m, "Fascia", "Wood").box((0.4, W + 1.9, 0.55), loc=(s * (W / 2 + 0.85), 0, zb + 0.95), bevel=0.05)
    bench(m, at=(0, c - 1.4, H), length=5.0)
    bench(m, at=(-c + 1.4, -0.3, H), length=4.4, rot_z=90)
    bench(m, at=(c - 1.4, -0.3, H), length=4.4, rot_z=-90)
    L.planter_box(m, V(0, -0.6, H), 3.2, 2.0, 1.1, seed=60, blocks=2, flower=6)
    glow = m.piece("Glow", "Lamp")
    cc = L.hanging_lantern(m, (0, -1.5, zb + 0.6), drop=0.7, s=0.85, glow=glow)
    m.attach["Light"] = tuple(cc)
    for sx in (-1, 1):
        L.planter_box(m, V(sx * (W / 2 - 1.0), -W / 2 - 1.0, 0), 2.0, 1.6, 1.0, seed=62 + sx, blocks=1)
    _collider(m, W, W, H)


# ------------------------------------------------------------------ 6. storage shed

@register("Lobby_StorageShed", S01, "Equipment storage shed 8 x 7, about 8.8 tall: stone base, vertical plank walls, steel corner posts, gabled dark roof (ridge along X, door under the front eave), X-braced Door (animated Swing about its left hinge, DoorBrace moves with it), vent, wall lamp, crates + barrel. Origin ground centre, door -Y.",
          ref=(REF, (1195, 615, 1530, 915)))
def storage_shed(m):
    W, D, H = 7.2, 6.4, 0.6
    stone, dark, frame = m.slot("Concrete"), m.slot("FrameDark"), m.slot("Frame")
    planks, wdark = m.slot("Wood"), m.slot("WoodDark")
    dark.box((W + 1.0, D + 1.0, 0.3), loc=(0, 0, 0.15), bevel=0.05)
    stone.box((W + 0.6, D + 0.6, H - 0.3), loc=(0, 0, 0.3 + (H - 0.3) / 2), bevel=0.05)
    zt = 5.8                         # eave height
    door_w, door_h = 3.0, 4.3
    pw = 0.6
    # walls of vertical planks (front leaves the door opening)
    nx = int(W / pw)
    for i in range(nx):
        x = -W / 2 + pw * (i + 0.5)
        for sy in (-1, 1):
            if sy < 0 and abs(x) < door_w / 2 + 0.05:
                planks.box((pw - 0.06, 0.35, zt - (H + door_h)), loc=(x, sy * D / 2, H + door_h + (zt - H - door_h) / 2), bevel=0.04)
                continue
            planks.box((pw - 0.06, 0.35, zt - H), loc=(x, sy * D / 2, H + (zt - H) / 2), bevel=0.04)
    ny = int(D / pw)
    for j in range(ny):
        y = -D / 2 + pw * (j + 0.5)
        for sx in (-1, 1):
            planks.box((0.35, pw - 0.06, zt - H), loc=(sx * W / 2, y, H + (zt - H) / 2), bevel=0.04)
    wdark.box((W - 0.2, D - 0.2, zt - H - 0.1), loc=(0, 0, H + (zt - H) / 2), bevel=0.02)   # inner core (no gaps)
    # gables on the two sides (ridge runs along X; the door is under the front eave)
    ridge = 7.5
    for sx in (-1, 1):
        planks.prism([(-D / 2 - 0.1, zt), (D / 2 + 0.1, zt), (0, ridge - 0.2)], 0.35, loc=(sx * W / 2, 0, 0), rot=(0, 0, 90), bevel=0.04)
    # corner posts + eave band
    for sx in (-1, 1):
        for sy in (-1, 1):
            frame.box((0.6, 0.6, zt - H + 0.2), loc=(sx * W / 2, sy * D / 2, H + (zt - H + 0.2) / 2), bevel=0.06)
    for sy in (-1, 1):
        frame.box((W + 0.6, 0.5, 0.4), loc=(0, sy * D / 2, zt), bevel=0.05)
    for sx in (-1, 1):
        frame.box((0.5, D + 0.6, 0.4), loc=(sx * W / 2, 0, zt), bevel=0.05)
    # roof: two dark slabs, ridge along X, timber fascia on the gable edges
    half = D / 2 + 0.9
    rise = ridge - zt + 0.3
    ang = math.degrees(math.atan2(rise, half))
    run = math.hypot(half, rise)
    roof = part(m, "Roof", "FrameDark")
    for sy in (-1, 1):
        roof.box((W + 1.4, run, 0.45), loc=(0, sy * half / 2, zt + rise / 2 + 0.15), rot=(-sy * ang, 0, 0), bevel=0.08)
        for sx in (-1, 1):
            part(m, "Fascia", "Wood").box((0.35, run, 0.5), loc=(sx * (W / 2 + 0.75), sy * half / 2, zt + rise / 2 + 0.05),
                                          rot=(-sy * ang, 0, 0), bevel=0.05)
        part(m, "Fascia", "Wood").box((W + 1.5, 0.4, 0.45), loc=(0, sy * (half + 0.05), zt - 0.05), bevel=0.05)
    roof.box((W + 1.5, 0.6, 0.4), loc=(0, 0, ridge + 0.25), bevel=0.06)
    # door (animated swing about its left hinge) with an X brace
    y = -D / 2 - 0.15
    hinge = (-door_w / 2, y, H)
    door = m.piece("Door", "WoodDark", anim="Swing", pivot=hinge, note="door leaf; swings about its left edge (Pivot)")
    brace = m.piece("DoorBrace", "Frame", anim="Swing", pivot=hinge, note="door brace; moves with Door")
    for i in range(5):
        x = -door_w / 2 + door_w * (i + 0.5) / 5
        door.box((door_w / 5 - 0.05, 0.25, door_h - 0.1), loc=(x, y, H + door_h / 2), bevel=0.03)
    for z in (H + 0.3, H + door_h - 0.3):
        brace.box((door_w - 0.1, 0.12, 0.35), loc=(0, y - 0.15, z), bevel=0.03)
    for sx in (-1, 1):
        brace.box((0.3, 0.12, door_h - 0.1), loc=(sx * (door_w / 2 - 0.2), y - 0.15, H + door_h / 2), bevel=0.03)
    brace.box_between((-door_w / 2 + 0.35, y - 0.17, H + 0.45), (door_w / 2 - 0.35, y - 0.17, H + door_h - 0.45), (0.3, 0.1))
    brace.box_between((door_w / 2 - 0.35, y - 0.17, H + 0.45), (-door_w / 2 + 0.35, y - 0.17, H + door_h - 0.45), (0.3, 0.1))
    frame.box((door_w + 0.6, 0.45, 0.4), loc=(0, -D / 2 - 0.05, H + door_h + 0.2), bevel=0.05)
    for sx in (-1, 1):
        frame.box((0.35, 0.45, door_h), loc=(sx * (door_w / 2 + 0.15), -D / 2 - 0.05, H + door_h / 2), bevel=0.04)
    m.attach["Door"] = (0, y - 0.3, H + door_h / 2)
    # vent on the right of the front, lamp above the door
    vx, vz = 2.4, 5.05
    frame.box((1.4, 0.3, 1.0), loc=(vx, -D / 2 - 0.15, vz), bevel=0.04)
    for k in range(4):
        dark.box((1.15, 0.2, 0.12), loc=(vx, -D / 2 - 0.3, vz - 0.33 + k * 0.22), rot=(25, 0, 0), bevel=0.01)
    frame.box((0.25, 0.9, 0.25), loc=(-1.0, -D / 2 - 0.55, 5.5), bevel=0.03)
    glow = m.piece("Glow", "Lamp")
    c = L.hanging_lantern(m, (-1.0, -D / 2 - 0.95, 5.5), drop=0.12, s=0.7, glow=glow)
    m.attach["Light"] = tuple(c)
    # props: crates + barrel at the right front, shrubs
    crate(m, (W / 2 + 0.5, -D / 2 - 0.9, 0), 1.3)
    crate(m, (W / 2 + 0.6, -D / 2 - 0.9, 1.3), 0.95)
    crate(m, (W / 2 + 0.6, -D / 2 + 0.6, 0), 1.1)
    barrel(m, (W / 2 - 0.8, -D / 2 - 1.2, 0))
    L.rosette(m.slot("Leaf"), V(-W / 2 - 0.4, -D / 2 - 0.6, 0), 0.9, 70, n=8, piece2=m.slot("LeafDark"))
    L.rosette(m.slot("Leaf"), V(W / 2 + 1.0, D / 2 - 1.6, 0), 0.8, 71, n=7, piece2=m.slot("LeafDark"))
    _collider(m, W + 1.0, D + 1.0, ridge)
