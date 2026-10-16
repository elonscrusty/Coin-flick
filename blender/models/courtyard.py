"""Sheet 02: Courtyard & navigation kit (paving, pads, planters, tree, bench, walls, fences, arch,
lamps, sign frame, path arrow, bollard).

Every model's origin is its floor centre (bottom centre) and its front faces -Y (Roblox -Z), so
`kit:PivotTo(CFrame.lookAt(pos, pos + dir))` makes the front face along `dir`. Paving pieces are
sized on a 4-stud grid (walkway 8 x 4 / 8 x 8 corner, pad 10 x 10, arrow tile 6 x 6). Glowing parts
are the Lamp slot (Neon); attach points named Light* are where the game puts PointLights.
"""

import math

import ctrkit as K
from ctrkit import register
from models import _lobbyparts as L
from models._lobbyparts import V

S02 = "02"
REF = "02_courtyard_nav_kit.png"


# ------------------------------------------------------------------ paving

def _paving_base(m, outline_boxes, h=0.4):
    dark = m.slot("FrameDark")
    for (w, d, cx, cy) in outline_boxes:
        dark.box((w, d, h), loc=(cx, cy, h / 2), bevel=0.06)


@register("Court_WalkwayStraight", S02, "Walkway straight, 8 long (X) x 4 wide, slabs on a dark base course, top at y 0.8, origin floor centre.",
          ref=(REF, (325, 50, 620, 290)))
def walkway_straight(m):
    W, D = 8.0, 4.0
    _paving_base(m, [(W, D, 0, 0)])
    stone = m.slot("Concrete")
    # two rows of slabs, staggered seams; a darker curb slab at one end like the sheet
    for j, y in enumerate((-D / 4, D / 4)):
        L.block_course([stone], -W / 2 + 0.05, W / 2 - 0.75, y, 0.35, 0.8, D / 2 - 0.08, 3, seed=j + 4, gap=0.08)
    m.slot("FrameDark").box((0.65, D, 0.75), loc=(W / 2 - 0.33, 0, 0.375), bevel=0.07)
    m.extra["collider"] = {"size": K.roblox_size((W, D, 0.8)), "offset": K.to_roblox((0, 0, 0.4))}


@register("Court_WalkwayCorner", S02, "Walkway L corner, 8 x 8 outline with a 4 x 4 notch at the back-right, top at y 0.85, origin floor centre of the 8 x 8 square.",
          ref=(REF, (20, 50, 320, 290)))
def walkway_corner(m):
    _paving_base(m, [(8, 4, 0, -2), (4, 4, -2, 2)])
    stone, stone2 = m.slot("Concrete"), m.slot("ConcreteDark")
    # front leg (along X) and left leg (along Y), each 4 wide; a raised darker curb on the outside
    L.block_course([stone], -3.4, 3.4, -2.0, 0.35, 0.75, 2.8, 2, seed=2, gap=0.08)
    for y in (0.35, 2.4):
        stone.box((2.75, 1.9, 0.4), loc=(-2.0, y, 0.55), bevel=0.07)
    # curb: a ring of chunky kerb blocks just inside the L outline, a little higher than the slabs
    for (a, b, c, along) in ((-4.0, 4.0, -3.7, "x"), (-3.4, 0.0, 3.7, "y"), (0.3, 3.4, -0.3, "x"),
                             (-0.6, 4.0, -0.3, "y"), (-4.0, -0.6, 3.7, "x"), (-3.4, 3.4, -3.7, "y")):
        L.block_course([stone2, stone], a, b, c, 0.0, 0.85, 0.6, max(1, int((b - a) / 2.2)), seed=7, gap=0.06, along=along)
    m.extra["collider"] = {"size": K.roblox_size((8, 8, 0.85)), "offset": K.to_roblox((0, 0, 0.42))}


@register("Court_StationPad", S02, "Station floor pad (courtyard version), 10 x 10 dark tiles, light rim, Accent corner brackets, top at y 0.45, origin floor centre.",
          ref=(REF, (625, 50, 920, 290)))
def station_pad(m):
    W = 10.0
    m.slot("FrameDark").box((W, W, 0.3), loc=(0, 0, 0.15), bevel=0.06)
    rim = m.slot("Steel")
    for sx in (-1, 1):
        rim.box((0.35, W, 0.42), loc=(sx * (W / 2 - 0.175), 0, 0.21), bevel=0.05)
        rim.box((W - 0.7, 0.35, 0.42), loc=(0, sx * (W / 2 - 0.175), 0.21), bevel=0.05)
    L.slab_grid(m.slot("Slate"), V(0, 0, 0.12), W - 0.8, W - 0.8, 2, 2, h=0.32, gap=0.1)
    acc = m.slot("Accent", "Metal")
    for sx in (-1, 1):
        for sy in (-1, 1):
            acc.box((1.4, 0.5, 0.3), loc=(sx * (W / 2 - 0.7), sy * (W / 2 - 0.25), 0.45), bevel=0.05)
            acc.box((0.5, 1.4, 0.3), loc=(sx * (W / 2 - 0.25), sy * (W / 2 - 0.7), 0.45), bevel=0.05)
    m.attach["Table"] = (0, 0.6, 0.44)
    m.extra["collider"] = {"size": K.roblox_size((W, W, 0.44)), "offset": K.to_roblox((0, 0, 0.22))}


@register("Court_PathArrow", S02, "Path arrow inset: 6 x 6 paving tile with a dark inset and a glowing chevron (Arrow piece, Neon) pointing to the front (Roblox -Z), origin floor centre.",
          ref=(REF, (920, 535, 1215, 755)))
def path_arrow(m):
    W = 6.0
    m.slot("FrameDark").box((W, W, 0.25), loc=(0, 0, 0.125), bevel=0.05)
    stone = m.slot("Concrete")
    for sx in (-1, 1):
        L.block_course([stone, m.slot("ConcreteDark")], -W / 2, W / 2, sx * (W / 2 - 0.5), 0.0, 0.5, 1.0, 3, seed=3 + sx, along="y")
        L.block_course([stone], -W / 2 + 1.05, W / 2 - 1.05, sx * (W / 2 - 0.5), 0.0, 0.5, 1.0, 2, seed=5 + sx)
    m.slot("Slate").box((W - 2.0, W - 2.0, 0.36), loc=(0, 0, 0.18), bevel=0.04)
    arrow = m.piece("Arrow", "Lamp", note="glowing chevron; pulse it to guide players")
    # chevron (two bars meeting at the front, -Y)
    for sx in (-1, 1):
        arrow.box((0.7, 2.3, 0.1), loc=(sx * 0.68, 0.25, 0.4), rot=(0, 0, sx * -45), bevel=0.03)
    m.attach["Light"] = (0, 0, 0.6)
    m.extra["collider"] = {"size": K.roblox_size((W, W, 0.45)), "offset": K.to_roblox((0, 0, 0.225))}


# ------------------------------------------------------------------ greenery

@register("Court_Planter", S02, "Stone planter 6 x 2.6 x 1.5 with shrubs and yellow flowers, origin floor centre.",
          ref=(REF, (925, 50, 1210, 290)))
def planter(m):
    L.planter_box(m, V(0, 0, 0), 6.0, 2.6, 1.5, seed=4, blocks=3, flower=10)


@register("Court_Tree", S02, "Small low-poly tree in a square stone planter (3.6 x 3.6), about 9 tall, origin floor centre.",
          ref=(REF, (1215, 0, 1520, 290)))
def tree(m):
    L.planter_box(m, V(0, 0, 0), 4.0, 4.0, 1.0, seed=9, blocks=2, leaf=False)
    lp, lp2 = m.slot("Leaf"), m.slot("LeafDark")
    for i, (x, y) in enumerate(((-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0))):
        L.rosette(lp, V(x, y, 0.85), 0.75, 40 + i, n=7, piece2=lp2)
    bark = m.slot("WoodDark")
    bark.cyl(0.6, 0.42, 2.6, seg=7, loc=(0, 0, 0.8 + 1.3))
    bark.cyl(0.75, 0.45, 0.5, seg=7, loc=(0, 0, 1.05))
    bark.box_between((0.0, 0, 2.6), (-1.5, -0.3, 3.9), 0.42)
    bark.box_between((0.0, 0, 2.9), (1.6, 0.4, 4.1), 0.4)
    bark.box_between((0.0, 0, 3.0), (0.2, 1.3, 4.0), 0.36)
    leaf, leaf2 = lp, lp2
    blobs = [((0, 0, 4.4), 3.6, 1), ((-2.0, -0.4, 3.7), 2.6, 2), ((2.1, 0.3, 3.8), 2.6, 3), ((0.3, -1.7, 3.8), 2.5, 4),
             ((-0.2, 1.8, 3.9), 2.5, 5), ((-1.0, 0.5, 5.6), 2.6, 6), ((1.1, -0.4, 5.5), 2.4, 7), ((0.1, 0.2, 6.6), 2.2, 8),
             ((-1.6, -1.4, 4.4), 2.0, 9), ((1.6, 1.4, 4.6), 2.0, 10)]
    for i, (c, s, seed) in enumerate(blobs):
        pts = K.rock_points(seed * 13, (s, s, s * 0.85), n=16, flat_bottom=0.05)
        (leaf if i % 3 else leaf2).hull(pts, loc=c, rot=(0, 0, seed * 40))


# ------------------------------------------------------------------ furniture

def bench(m, at=(0, 0, 0), length=5.0, rot_z=0):
    """Wooden bench: 3 seat planks, 2 back planks on chunky dark steel end frames. `at` = floor centre."""
    import mathutils
    R = mathutils.Matrix.Rotation(math.radians(rot_z), 3, "Z")
    o = V(*at)

    def P(x, y, z):
        return o + R @ V(x, y, z)

    rot = (0, 0, rot_z)
    wood, frame, bolt = m.slot("Wood"), m.slot("Frame"), m.slot("SteelLight")
    for i in range(3):
        wood.box((length, 0.42, 0.2), loc=P(0, -0.5 + i * 0.47, 1.55), rot=rot, bevel=0.05)
    for i in range(2):
        wood.box((length - 0.2, 0.2, 0.45), loc=P(0, 0.5, 2.2 + i * 0.55), rot=rot, bevel=0.05)
    for sx in (-1, 1):
        x = sx * (length / 2 - 0.55)
        frame.box((0.5, 1.6, 0.36), loc=P(x, 0, 1.28), rot=rot, bevel=0.05)          # seat rail
        frame.box((0.44, 1.3, 1.0), loc=P(x, -0.05, 0.62), rot=rot, bevel=0.06)       # chunky leg block
        frame.box((0.38, 0.36, 1.85), loc=P(x, 0.72, 2.05), rot=rot, bevel=0.05)      # back post
        frame.box((0.52, 0.5, 0.2), loc=P(x, 0.72, 3.02), rot=rot, bevel=0.04)        # post cap
        frame.box((0.66, 1.7, 0.3), loc=P(x, 0.0, 0.15), rot=rot, bevel=0.05)         # foot
        bolt.bolt(P(x + sx * 0.22, 0, 1.28), normal=R @ V(sx, 0, 0), r=0.07)
        bolt.bolt(P(x + sx * 0.19, 0.72, 2.45), normal=R @ V(sx, 0, 0), r=0.07)


@register("Court_Bench", S02, "Wooden bench (5 long), dark steel end frames, seat top at y 1.65, origin floor centre; Seat attach = seat centre.",
          ref=(REF, (20, 300, 320, 525)))
def court_bench(m):
    bench(m)
    m.attach["Seat"] = (0, 0, 1.65)


# ------------------------------------------------------------------ walls + fences

@register("Court_PerimeterWall", S02, "Low perimeter wall 10 long x 1.4 deep x 3 tall: dark base course, beige blocks, taller end block at -X; origin floor centre.",
          ref=(REF, (325, 300, 620, 525)))
def perimeter_wall(m):
    Wl = 10.0
    dark = m.slot("FrameDark")
    dark.box((Wl, 1.5, 0.7), loc=(0, 0, 0.35), bevel=0.07)
    stone, stone2 = m.slot("Concrete"), m.slot("ConcreteDark")
    L.block_course([stone, stone2, stone], -Wl / 2 + 1.5, Wl / 2, 0, 0.7, 2.6, 1.3, 4, seed=3, gap=0.08)
    stone.box((1.45, 1.45, 3.0), loc=(-Wl / 2 + 0.75, 0, 0.7 + 1.5 - 0.35), bevel=0.08)
    stone2.box((1.25, 1.25, 0.65), loc=(-Wl / 2 + 0.75, 0, 3.0 + 0.33), bevel=0.08)
    m.extra["collider"] = {"size": K.roblox_size((Wl, 1.5, 3.0)), "offset": K.to_roblox((0, 0, 1.5))}


def fence_post(m, at, light_normals):
    at = V(*at)
    frame, dark = m.slot("Frame"), m.slot("FrameDark")
    dark.box((1.15, 1.15, 0.5), loc=at + V(0, 0, 0.25), bevel=0.06)
    frame.box((0.9, 0.9, 3.4), loc=at + V(0, 0, 0.5 + 1.7), bevel=0.07)
    dark.box((1.1, 1.1, 0.3), loc=at + V(0, 0, 3.9 + 0.15), bevel=0.06)
    for n in light_normals:
        L.light_strip(m, at + V(0, 0, 2.3) + V(*n) * 0.45, n, 1.7, w=0.22)


def fence_run(m, a, b, rails=3):
    a, b = V(*a), V(*b)
    d = b - a
    along_x = abs(d.x) > abs(d.y)
    L_ = d.length
    c = (a + b) / 2
    stone = m.slot("Concrete")
    frame = m.slot("Frame")
    base = (L_, 0.9, 0.9) if along_x else (0.9, L_, 0.9)
    L.block_course([stone, m.slot("ConcreteDark")], (a.x if along_x else a.y), (b.x if along_x else b.y),
                   (c.y if along_x else c.x), 0.0, 0.9, 0.9, max(1, int(L_ / 3)), seed=5, along="x" if along_x else "y")
    _ = base
    for i in range(rails):
        z = 1.5 + i * 0.75
        frame.box((L_, 0.32, 0.38) if along_x else (0.32, L_, 0.38), loc=c + V(0, 0, z), bevel=0.05)


@register("Court_FenceStraight", S02, "Fence straight: 8 long, stone sill, 3 dark rails, end posts with amber light strips; origin floor centre.",
          ref=(REF, (625, 300, 920, 525)))
def fence_straight(m):
    fence_run(m, (-3.6, 0, 0), (3.6, 0, 0))
    for sx in (-1, 1):
        fence_post(m, (sx * 4.0, 0, 0), [(0, -1, 0), (0, 1, 0)])
    frame = m.slot("Frame")
    frame.box((0.6, 0.6, 3.6), loc=(0, 0, 1.8), bevel=0.06)
    m.slot("Lamp").box((0.3, 0.3, 0.1), loc=(0, 0, 3.62), bevel=0.02)
    m.extra["collider"] = {"size": K.roblox_size((9.2, 1.2, 4.2)), "offset": K.to_roblox((0, 0, 2.1))}


@register("Court_FenceCorner", S02, "Fence corner: L of two 4-long runs meeting at a lit corner post at (-X, +Y); origin floor centre of the L's 5 x 5 box.",
          ref=(REF, (925, 300, 1210, 525)))
def fence_corner(m):
    c = (-2.0, 2.0, 0)
    fence_run(m, (-1.6, 2.0, 0), (2.4, 2.0, 0))
    fence_run(m, (-2.0, 1.6, 0), (-2.0, -2.4, 0))
    fence_post(m, c, [(0, -1, 0), (1, 0, 0)])
    fence_post(m, (2.6, 2.0, 0), [(0, -1, 0)])
    fence_post(m, (-2.0, -2.6, 0), [(1, 0, 0)])


# ------------------------------------------------------------------ arch

@register("Court_EntranceArch", S02, "Entrance arch: two stone pillars with light strips, dark segmented arch and a geode emblem (Emblem piece, amber crystal); 14 wide, about 11.5 tall, walk-through 9 wide; origin floor centre.",
          ref=(REF, (1215, 290, 1520, 525)))
def entrance_arch(m):
    stone, stone2, dark, frame = m.slot("Concrete"), m.slot("ConcreteDark"), m.slot("FrameDark"), m.slot("Frame")
    px = 5.6
    for sx in (-1, 1):
        x = sx * px
        dark.box((2.9, 2.9, 0.6), loc=(x, 0, 0.3), bevel=0.08)
        stone.box((2.4, 2.4, 3.2), loc=(x, 0, 0.6 + 1.6), bevel=0.1)
        stone2.box((2.3, 2.3, 3.0), loc=(x, 0, 3.8 + 1.5), bevel=0.1)
        stone.box((2.5, 2.5, 0.5), loc=(x, 0, 6.8 + 0.25), bevel=0.08)
        stone2.box((2.2, 2.2, 0.9), loc=(x, 0, 7.3 + 0.45), bevel=0.08)
        L.light_strip(m, (x, -1.2, 4.1), (0, -1, 0), 4.6, w=0.45)
        L.light_strip(m, (x, 1.2, 4.1), (0, 1, 0), 4.6, w=0.45)
        L.planter_box(m, V(x + sx * 2.1, -0.3, 0), 1.6, 1.6, 0.9, seed=30 + sx, blocks=1)
    # segmented arch between the pillar tops (dark steel), from z 7.0 at the pillars up to ~10.4
    R_out, R_in = 6.2, 4.9
    cz = 7.6 - 2.2
    n = 9
    a0, a1 = math.radians(21), math.radians(159)
    for i in range(n):
        t0, t1 = a0 + (a1 - a0) * i / n, a0 + (a1 - a0) * (i + 1) / n
        prof = [(math.cos(t0) * R_in, cz + math.sin(t0) * R_in), (math.cos(t0) * R_out, cz + math.sin(t0) * R_out),
                (math.cos(t1) * R_out, cz + math.sin(t1) * R_out), (math.cos(t1) * R_in, cz + math.sin(t1) * R_in)]
        frame.prism(prof, 1.8, bevel=0.06)
        # bolt band at the segment joints
        if i < n - 1:
            dark.box((0.25, 1.92, R_out - R_in + 0.1), loc=(math.cos(t1) * (R_in + R_out) / 2, 0, cz + math.sin(t1) * (R_in + R_out) / 2),
                     rot=(0, -math.degrees(t1) + 90, 0), bevel=0.03)
    # emblem at the crown: octagon steel ring, dark face, amber crystal
    ez = cz + R_out - 0.45
    frame.prism(L.octagon(2.3), 1.5, loc=(0, -0.2, ez), bevel=0.08)
    m.slot("Slate").prism(L.octagon(1.75), 1.5, loc=(0, -0.35, ez), bevel=0.05)
    emblem = m.piece("Emblem", "Amber", "Neon", note="amber gem on the arch crown (glows)")
    L.gem(emblem, V(0, -1.1, ez - 0.1), 1.5)
    m.attach["Emblem"] = (0, -1.3, ez)
    m.attach["Light"] = (0, -1.8, ez)


# ------------------------------------------------------------------ lamps

@register("Court_WallLamp", S02, "Wall lamp: back plate + arm + lantern (Glow piece, Neon). Origin = bottom centre of the back plate on the wall; the lamp sticks out to the front (-Y / Roblox -Z).",
          ref=(REF, (20, 535, 305, 755)))
def wall_lamp(m):
    frame, dark = m.slot("Frame"), m.slot("FrameDark")
    dark.box((0.9, 0.25, 2.2), loc=(0, -0.125, 1.1), bevel=0.05)
    for z in (0.35, 1.85):
        m.slot("SteelLight").bolt((0, -0.25, z), normal=(0, -1, 0), r=0.08)
    frame.box((0.35, 1.3, 0.3), loc=(0, -0.85, 1.7), bevel=0.04)
    frame.box((0.3, 0.5, 0.5), loc=(0, -0.45, 1.4), bevel=0.04)
    glow = m.piece("Glow", "Lamp")
    c = L.hanging_lantern(m, (0, -1.35, 1.7), drop=0.12, s=0.95, glow=glow)
    m.attach["Light"] = tuple(c)


@register("Court_StandingLamp", S02, "Standing lamp post, 1.5 x 1.5 x 4.7: dark base, glowing four-sided column (Glow piece), cap; origin floor centre.",
          ref=(REF, (310, 535, 605, 755)))
def standing_lamp(m):
    frame, dark = m.slot("Frame"), m.slot("FrameDark")
    glow = m.piece("Glow", "Lamp")
    dark.box((1.55, 1.55, 0.45), loc=(0, 0, 0.225), bevel=0.06)
    frame.box((1.25, 1.25, 0.9), loc=(0, 0, 0.45 + 0.45), bevel=0.06)
    glow.box((0.95, 0.95, 2.3), loc=(0, 0, 1.35 + 1.15), bevel=0.04)
    for sx in (-1, 1):
        for sy in (-1, 1):
            frame.box((0.3, 0.3, 2.4), loc=(sx * 0.5, sy * 0.5, 1.35 + 1.2), bevel=0.04)
    frame.box((1.1, 1.1, 0.22), loc=(0, 0, 2.0), bevel=0.03)
    frame.box((1.45, 1.45, 0.3), loc=(0, 0, 3.75 + 0.15), bevel=0.05)
    dark.box((1.3, 1.3, 0.5), loc=(0, 0, 4.05 + 0.25), taper=(0.7, 0.7), bevel=0.05)
    m.attach["Light"] = (0, 0, 2.5)


# ------------------------------------------------------------------ signage

@register("Court_SignFrame", S02, "Sign frame 6 wide x 4.6 tall: stone pillars, dark panel (Panel piece: put a SurfaceGui on its front) with an Accent top bar; origin floor centre.",
          ref=(REF, (610, 535, 915, 755)))
def sign_frame(m):
    stone, dark, frame = m.slot("Concrete"), m.slot("FrameDark"), m.slot("Frame")
    for sx in (-1, 1):
        x = sx * 2.65
        dark.box((1.1, 1.1, 0.5), loc=(x, 0, 0.25), bevel=0.05)
        stone.box((0.9, 0.9, 3.4), loc=(x, 0, 0.5 + 1.7), bevel=0.07)
        dark.box((1.05, 1.05, 0.35), loc=(x, 0, 3.9 + 0.17), bevel=0.05)
        L.light_strip(m, (x, -0.45, 2.3), (0, -1, 0), 1.9, w=0.2)
    frame.box((4.5, 0.55, 3.0), loc=(0, 0, 1.0 + 1.5), bevel=0.08)
    frame.box((5.2, 0.7, 0.45), loc=(0, 0, 4.1), bevel=0.06)
    panel = m.piece("Panel", "Slate", note="sign face; SurfaceGui on its front (Roblox -Z face)")
    panel.box((3.9, 0.12, 2.45), loc=(0, -0.3, 2.5), bevel=0.03)
    m.slot("Accent", "Neon").box((4.0, 0.1, 0.16), loc=(0, -0.38, 3.85), bevel=0.02)
    m.slot("Accent", "Neon").box((4.0, 0.1, 0.12), loc=(0, -0.38, 1.1), bevel=0.02)
    m.attach["Panel"] = (0, -0.37, 2.5)


@register("Court_KioskBollard", S02, "Kiosk bollard 1.6 x 1.6 x 3.2: dark post, glowing front window (Glow piece), slanted top screen (Screen piece); origin floor centre.",
          ref=(REF, (1220, 535, 1520, 755)))
def kiosk_bollard(m):
    frame, dark = m.slot("Frame"), m.slot("FrameDark")
    dark.box((1.7, 1.7, 0.35), loc=(0, 0, 0.175), bevel=0.05)
    frame.box((1.35, 1.35, 2.3), loc=(0, 0, 0.35 + 1.15), bevel=0.07)
    glow = m.piece("Glow", "Lamp")
    for n in ((0, -1), (0, 1), (-1, 0), (1, 0)):
        for o in (-0.3, 0.3):
            if n[1]:
                glow.box((0.26, 0.1, 1.5), loc=(o, n[1] * 0.68, 1.55), bevel=0.03)
            else:
                glow.box((0.1, 0.26, 1.5), loc=(n[0] * 0.68, o, 1.55), bevel=0.03)
    m.slot("Concrete").box((1.75, 1.75, 0.35), loc=(0, 0, 2.65 + 0.17), bevel=0.06)
    frame.prism([(-0.75, 0), (0.75, 0), (0.75, 0.55), (-0.75, 0.15)], 1.5, loc=(0, 0, 2.95), rot=(0, 0, 90), bevel=0.04)
    m.piece("Screen", "Slate").box((1.1, 1.1, 0.06), loc=(0, 0, 3.32), rot=(15, 0, 0), bevel=0.02)
    m.attach["Light"] = (0, -0.9, 1.55)
