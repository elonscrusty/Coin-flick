"""Sheet 03: Start Hunt terminal kit (kiosk, screen housing, party ready lights, lamp bracket, geode
emblem, step tile, owned-station nameplate, party readiness floor beacon).

Origins are the floor centre and fronts face -Y (Roblox -Z) unless a note says otherwise. Screens,
buttons and plates are separate Slate pieces with an attach point at the centre of their front face:
the game puts a SurfaceGui there (Start Hunt / Solo / Party text, the four party slots). Glowing
parts are Lamp (Neon); ready lights are four separate pieces so the game can switch each one.
"""

import math

from mathutils import Euler, Vector

import ctrkit as K
from ctrkit import register
from models import _lobbyparts as L
from models._lobbyparts import V

S03 = "03"
REF = "03_start_terminal_kit.png"


# ------------------------------------------------------------------ shared builders

def emblem(m, at, r=1.0, face=(0, -1, 0), stone=None, crystal=None):
    """Geode emblem: chunky octagonal stone ring, dark face, amber crystal cluster. `at` = centre of
    the BACK face (it mounts on a wall); it faces -Y."""
    at = Vector(at)
    stone = stone or m.slot("Concrete")
    crystal = crystal or m.slot("Amber")
    t = 0.45 * r
    stone.prism(L.octagon(r, 22.5), t, loc=at + V(0, -t / 2, 0), bevel=0.07 * r)
    m.slot("Slate").prism(L.octagon(r * 0.72, 22.5), t, loc=at + V(0, -t / 2 - 0.06 * r, 0), bevel=0.03)
    L.crystal_cluster(crystal, at + V(0, -t - 0.05 * r, -0.05 * r), s=r * 0.62, seed=7, n=5, normal_y=True)
    return at + V(0, -t - 0.2 * r, 0)


def screen_housing(m, at, w=4.6, d=2.2, tilt=28, cheeks=True, screen_name="Screen"):
    """Sloped console: dark tilted slab with an Accent border round a Slate screen; stone side
    cheeks. `at` = floor centre. Returns the screen centre (front surface)."""
    at = Vector(at)
    frame, dark = m.slot("Frame"), m.slot("FrameDark")
    R = Euler((math.radians(tilt), 0, 0), "XYZ").to_matrix()
    h0 = 0.55
    centre = at + V(0, 0, h0 + math.sin(math.radians(tilt)) * d / 2 + 0.15)

    def P(x, y, z):
        return centre + R @ V(x, y, z)

    rot = (tilt, 0, 0)
    # underside block that carries the slab
    dark.box((w - 0.4, d * 0.8, h0 + 0.3), loc=at + V(0, 0.1, (h0 + 0.3) / 2), bevel=0.06)
    frame.box((w, d, 0.4), loc=P(0, 0, 0), rot=rot, bevel=0.08)
    acc = m.slot("Accent", "Metal")
    bw = 0.22
    acc.box((w - 0.35, bw, 0.12), loc=P(0, -d / 2 + 0.3, 0.24), rot=rot, bevel=0.03)
    acc.box((w - 0.35, bw, 0.12), loc=P(0, d / 2 - 0.3, 0.24), rot=rot, bevel=0.03)
    for sx in (-1, 1):
        acc.box((bw, d - 0.6 + bw, 0.12), loc=P(sx * (w / 2 - 0.29), 0, 0.24), rot=rot, bevel=0.03)
        for sy in (-1, 1):
            m.slot("SteelLight").bolt(P(sx * (w / 2 - 0.13), sy * (d / 2 - 0.13), 0.2), normal=R @ V(0, 0, 1), r=0.08)
    scr = m.piece(screen_name, "Slate", note="touch screen; SurfaceGui on its top face (party slots)")
    scr.box((w - 0.95, d - 1.0, 0.1), loc=P(0, 0, 0.23), rot=rot, bevel=0.02)
    if cheeks:
        stone = m.slot("Concrete")
        for sx in (-1, 1):
            x = sx * (w / 2 + 0.2)
            yb, yf = d / 2 + 0.1, -d / 2 - 0.1
            zf = (P(0, -d / 2, 0) - at).z + 0.05
            zb = (P(0, d / 2, 0) - at).z + 0.25
            prof = [(yf, 0), (yb, 0), (yb, zb), (yf, zf)]
            stone.prism(prof, 0.4, loc=at + V(x, 0, 0), rot=(0, 0, 90), bevel=0.06)
    return P(0, 0, 0.29), R @ V(0, 0, 1)


def ready_light(m, at, name, h=0.9):
    """One ready lamp: dark cube housing with a glowing face front and back, on a short stem."""
    at = Vector(at)
    frame, dark = m.slot("Frame"), m.slot("FrameDark")
    dark.box((0.34, 0.34, h * 0.35), loc=at + V(0, 0, h * 0.175), bevel=0.03)
    frame.box((0.8, 0.62, 0.8), loc=at + V(0, 0, h * 0.35 + 0.4), bevel=0.07)
    glow = m.piece(name, "Lamp", note="party ready light: on (Neon amber) when that member is ready")
    glow.box((0.56, 0.68, 0.56), loc=at + V(0, 0, h * 0.35 + 0.4), bevel=0.03)
    frame.box((0.86, 0.66, 0.12), loc=at + V(0, 0, h * 0.35 + 0.82), bevel=0.03)
    for sx in (-1, 1):
        m.slot("Brass").bolt(at + V(sx * 0.3, -0.32, h * 0.35 + 0.08), normal=(0, -1, 0), r=0.06)
    return at + V(0, -0.4, h * 0.35 + 0.4)


# ------------------------------------------------------------------ kiosk

@register("Terminal_Kiosk", S03, "Start Hunt kiosk (warm timber pass): stone plinth, four timber posts with a low gabled plank roof, hanging timber title board (Title), carved stone pickaxe emblem on a stone back block, wooden counter with Solo / Party plaques, two stone planters with shrubs, two hanging lanterns (Glow). 9.0 x 5.4, about 7.8 tall, origin floor centre, front -Y. SurfaceGuis go on the wood plaques (attach points).",
          ref=(REF, (10, 60, 1075, 510)))
def kiosk(m):
    stone, stone2 = m.slot("Concrete"), m.slot("ConcreteDark")
    wood, wood2 = m.slot("Wood"), m.slot("WoodDark")
    steel = m.slot("Frame")
    # plinth: stone base course plus a paved slab, one step lower at the front
    stone2.box((9.0, 5.4, 0.35), loc=(0, 0, 0.175), bevel=0.06)
    L.block_course([stone, stone2, stone], -4.2, 4.2, -2.45, 0.2, 0.65, 0.5, 5, seed=3, gap=0.06)
    L.block_course([stone2, stone], -4.2, 4.2, 2.45, 0.2, 0.65, 0.5, 4, seed=5, gap=0.06)
    stone.box((8.4, 4.6, 0.4), loc=(0, 0, 0.45), bevel=0.05)
    zf = 0.65
    # stone back block carrying the emblem
    yb = 1.45
    stone2.box((5.0, 1.1, 3.9), loc=(0, yb, zf + 1.95), bevel=0.08)
    L.block_course([stone, stone2], -2.4, 2.4, yb - 0.62, zf + 0.1, zf + 3.8, 0.18, 4, seed=11, gap=0.06)
    stone.box((5.4, 1.3, 0.32), loc=(0, yb, zf + 4.06), bevel=0.06)
    # emblem: stone octagon with a darker face and a crossed pickaxe
    ez, ey = zf + 2.15, yb - 0.6
    stone.prism(L.octagon(1.45, 22.5), 0.32, loc=(0, ey - 0.16, ez), bevel=0.05)
    stone2.prism(L.octagon(1.12, 22.5), 0.2, loc=(0, ey - 0.34, ez), bevel=0.03)
    pick = m.slot("Slate")
    fy = ey - 0.52
    for sx in (-1, 1):
        lo = (-sx * 0.82, fy, ez - 0.82)
        hi = (sx * 0.82, fy, ez + 0.82)
        wood2.box_between(lo, hi, 0.2, bevel=0.03)
        # curved head across the top end
        c = Vector(hi)
        d = Vector((sx, 0, 1)).normalized()
        pv = Vector((-sx, 0, 1)).normalized()
        pts = [c - pv * 0.85 - d * 0.18, c - pv * 0.42 + d * 0.05, c + pv * 0.42 + d * 0.05, c + pv * 0.85 - d * 0.18]
        for i in range(3):
            pick.box_between(pts[i], pts[i + 1], (0.24, 0.2), bevel=0.03)
    m.attach["Emblem"] = (0, fy - 0.1, ez)
    # wooden counter in front of the back block
    cy = -0.55
    wood.box((4.4, 1.5, 1.5), loc=(0, cy, zf + 0.75), bevel=0.06)
    wood2.box((4.8, 1.8, 0.2), loc=(0, cy, zf + 1.6), bevel=0.05)
    for sx in (-1, 1):
        wood2.box((0.3, 1.52, 1.5), loc=(sx * 2.0, cy, zf + 0.75), bevel=0.04)
    for sx, nm in ((1, "Party"), (-1, "Solo")):
        b = m.piece(nm, "WoodDark", note=nm + " plaque; SurfaceGui on its front")
        b.box((1.7, 0.1, 0.8), loc=(sx * 1.1, cy - 0.78, zf + 0.82), bevel=0.02)
        m.attach[nm] = (sx * 1.1, cy - 0.85, zf + 0.82)
    m.attach["Screen"] = (0, cy - 0.85, zf + 0.82)
    # stone planters with shrubs between counter and posts
    for sx in (-1, 1):
        L.planter_box(m, (sx * 3.1, -1.2, 0.55), 1.4, 1.5, 0.9, seed=30 + sx, blocks=2, leaf=True)
    # four timber posts, iron brackets
    ph = 5.6
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * 4.0, sy * 2.2
            wood.box((0.62, 0.62, ph), loc=(x, y, zf + ph / 2), bevel=0.06)
            wood2.box((0.8, 0.8, 0.3), loc=(x, y, zf + 0.15), bevel=0.04)
            steel.box((0.72, 0.72, 0.18), loc=(x, y, zf + ph - 0.7), bevel=0.03)
    # beams and roof
    zr = zf + ph
    for y in (-2.2, 2.2):
        wood2.box((8.9, 0.55, 0.5), loc=(0, y, zr + 0.1), bevel=0.05)
    for sx in (-1, 1):
        wood2.box((0.55, 4.8, 0.5), loc=(sx * 4.0, 0, zr + 0.1), bevel=0.05)
    th = 20
    rise = 1.65 * math.tan(math.radians(th))
    for sy in (-1, 1):
        wood.box((9.8, 3.3, 0.3), loc=(0, sy * 1.55, zr + 0.55 + rise / 2 + 0.1), rot=(-sy * th, 0, 0), bevel=0.05)
        for i in range(8):
            x = -4.5 + 9.0 * (i + 0.5) / 8
            wood2.box((0.1, 3.3, 0.06), loc=(x, sy * 1.55, zr + 0.78 + rise / 2 + 0.1), rot=(-sy * th, 0, 0), bevel=0.01)
    wood2.box((9.9, 0.45, 0.35), loc=(0, 0, zr + 0.55 + rise + 0.18), bevel=0.05)
    # gable end filling and a timber title board hanging at the front between the posts
    for sx in (-1, 1):
        wood.box_between((sx * 4.4, -1.9, zr + 0.4), (sx * 4.4, 0, zr + 0.55 + rise), (0.18, 0.3), bevel=0.02)
    wood2.box((5.8, 0.4, 1.45), loc=(0, -2.3, zr - 0.75), bevel=0.06)
    t = m.piece("Title", "WoodDark", note="START HUNT title; SurfaceGui on its front")
    t.box((5.4, 0.1, 1.15), loc=(0, -2.55, zr - 0.75), bevel=0.02)
    m.attach["Title"] = (0, -2.62, zr - 0.75)
    for sx in (-1, 1):
        steel.box_between((sx * 2.7, -2.25, zr - 0.2), (sx * 3.95, -2.25, zr + 0.1), 0.18, bevel=0.02)
    # hanging lanterns at the front posts
    glow = m.piece("Glow", "Lamp")
    for sx in (-1, 1):
        c = L.hanging_lantern(m, (sx * 3.2, -1.9, zr - 0.2), drop=0.35, s=0.8, glow=glow)
    m.attach["Light"] = tuple(c)
    m.attach["Prompt"] = (0, -1.8, 1.8)
    m.extra["collider"] = {"size": K.roblox_size((9.0, 5.4, 7.8)), "offset": K.to_roblox((0, 0, 3.9))}


# ------------------------------------------------------------------ kit pieces

@register("Terminal_ScreenHousing", S03, "Terminal screen housing: tilted dark slab, Accent border, Slate Screen piece, stone side cheeks; 5.0 x 2.6, origin floor centre; Screen attach = screen centre.",
          ref=(REF, (385, 520, 695, 865)))
def screen_housing_model(m):
    sc, _ = screen_housing(m, V(0, 0, 0), w=4.6, d=2.4, tilt=30)
    m.attach["Screen"] = tuple(sc)


@register("Terminal_ReadyLights", S03, "Party ready indicators: four lamps (Light1..Light4, Neon pieces, switch per member) on a dark rail with feet; 6.4 long, origin floor centre.",
          ref=(REF, (15, 520, 380, 865)))
def ready_lights(m):
    frame, dark = m.slot("Frame"), m.slot("FrameDark")
    frame.box((6.4, 0.6, 0.45), loc=(0, 0, 0.75), bevel=0.07)
    for sx in (-1, 1):
        dark.box((0.8, 0.9, 0.55), loc=(sx * 2.7, 0, 0.275), bevel=0.06)
        frame.box((0.5, 0.5, 0.4), loc=(sx * 2.7, 0, 0.55 + 0.1), bevel=0.04)
        m.slot("Brass").bolt((sx * 3.1, -0.31, 0.75), normal=(0, -1, 0), r=0.07)
    for i in range(4):
        x = -2.25 + i * 1.5
        p = ready_light(m, (x, 0, 0.97), "Light%d" % (i + 1), h=0.6)
        m.attach["Light%d" % (i + 1)] = tuple(p)
    for i in range(5):
        m.slot("Brass").bolt((-3.0 + i * 1.5, -0.31, 0.75), normal=(0, -1, 0), r=0.06)


@register("Terminal_LampBracket", S03, "Lamp and bracket: dark steel post with a wooden arm and brace, lantern hanging on a chain (Glow piece); arm reaches to -X (viewer's left); origin floor centre of the post.",
          ref=(REF, (700, 520, 955, 865)))
def lamp_bracket(m):
    frame, wood = m.slot("Frame"), m.slot("Wood")
    m.slot("FrameDark").box((0.9, 0.9, 0.3), loc=(0, 0, 0.15), bevel=0.05)
    wood.box((0.6, 0.6, 4.6), loc=(0, 0, 0.3 + 2.3), bevel=0.07)
    frame.box((0.74, 0.74, 0.5), loc=(0, 0, 0.55), bevel=0.04)
    wood.box((3.2, 0.6, 0.6), loc=(-1.1, 0, 4.6), bevel=0.08)
    wood.box_between((-0.05, 0, 3.0), (-1.4, 0, 4.4), (0.4, 0.4))
    frame.box((0.72, 0.72, 0.8), loc=(0, 0, 4.6), bevel=0.05)
    frame.box((0.3, 0.7, 0.7), loc=(-2.5, 0, 4.6), bevel=0.04)
    for z in (4.75, 4.45):
        m.slot("SteelLight").bolt((0, -0.37, z), normal=(0, -1, 0), r=0.07)
    # chain: alternating links
    for i in range(4):
        z = 4.25 - i * 0.22
        frame.box((0.14, 0.06 if i % 2 else 0.14, 0.24), loc=(-2.2, 0, z), bevel=0.02)
    glow = m.piece("Glow", "Lamp")
    c = L.lantern(m, (-2.2, 0, 2.05), s=1.05, glow=glow)
    m.attach["Light"] = tuple(c)


@register("Terminal_GeodeEmblem", S03, "Geode emblem: octagonal stone ring, dark face, amber crystal cluster (Crystal piece). Wall mount: origin = centre of the BACK face, it faces -Y (Roblox -Z). 2.4 across.",
          ref=(REF, (960, 520, 1210, 865)))
def geode_emblem(m):
    crystal = m.piece("Crystal", "Amber")
    emblem(m, (0, 0, 0), r=1.2, crystal=crystal)
    m.extra["origin"] = "back face centre (wall mount)"


@register("Terminal_StepTile", S03, "Kiosk step / paving tile 6 x 4 x 0.75: dark base course, stone slabs with chunky end blocks; origin floor centre.",
          ref=(REF, (1215, 520, 1530, 865)))
def step_tile(m):
    stone, stone2 = m.slot("Concrete"), m.slot("ConcreteDark")
    m.slot("FrameDark").box((6.0, 4.0, 0.3), loc=(0, 0, 0.15), bevel=0.05)
    L.block_course([stone, stone2], -3.0, 3.0, -1.0, 0.25, 0.75, 1.95, 3, seed=8, gap=0.08)
    L.block_course([stone2, stone], -3.0, 3.0, 1.0, 0.25, 0.75, 1.95, 2, seed=9, gap=0.08)
    m.extra["collider"] = {"size": K.roblox_size((6, 4, 0.75)), "offset": K.to_roblox((0, 0, 0.375))}


@register("Terminal_Nameplate", S03, "Owned station nameplate (compact): stone base, dark plate (Plate piece, SurfaceGui for the owner's name), two posts with lamp tops (Glow); 6.2 long x 1.9 tall, origin floor centre.",
          ref=(REF, (15, 875, 765, 1010)))
def nameplate(m):
    stone, frame, dark = m.slot("Concrete"), m.slot("Frame"), m.slot("FrameDark")
    dark.box((6.2, 1.0, 0.25), loc=(0, 0, 0.125), bevel=0.05)
    stone.box((5.6, 0.85, 0.35), loc=(0, 0, 0.25 + 0.175), bevel=0.06)
    frame.box((4.4, 0.45, 1.15), loc=(0, 0, 0.6 + 0.575), bevel=0.07)
    plate = m.piece("Plate", "Slate", note="owner / station name; SurfaceGui on its front")
    plate.box((4.0, 0.1, 0.8), loc=(0, -0.24, 1.175), bevel=0.03)
    m.attach["Plate"] = (0, -0.3, 1.175)
    glow = m.piece("Glow", "Lamp")
    for sx in (-1, 1):
        x = sx * 2.65
        frame.box((0.8, 0.8, 1.9), loc=(x, 0, 0.25 + 0.95), bevel=0.07)
        glow.box((0.5, 0.86, 0.5), loc=(x, 0, 1.6), bevel=0.03)
        dark.box((0.9, 0.9, 0.18), loc=(x, 0, 2.2), bevel=0.04)
    m.attach["Light"] = (0, -0.6, 1.6)


@register("Terminal_FloorBeacon", S03, "Party readiness floor beacon: round dark disk 4.4 across with a glowing ring (Ring piece, Neon) and a dark Face (Decal/SurfaceGui party icon on top); origin floor centre, top at y 0.45.",
          ref=(REF, (770, 875, 1530, 1010)))
def floor_beacon(m):
    frame, dark = m.slot("Frame"), m.slot("FrameDark")
    m.slot("ConcreteDark").cyl(2.2, 2.15, 0.35, seg=16, loc=(0, 0, 0.175))
    frame.cyl(2.05, 2.0, 0.2, seg=16, loc=(0, 0, 0.4))
    ring = m.piece("Ring", "Lamp", note="ready ring; pulse / switch on when the party is ready")
    ring.cyl(1.75, 1.75, 0.12, seg=16, loc=(0, 0, 0.5))
    face = m.piece("Face", "Slate", note="party icon face; Decal / SurfaceGui on the top")
    face.cyl(1.45, 1.45, 0.16, seg=16, loc=(0, 0, 0.52))
    for i in range(8):
        a = i * math.tau / 8 + math.tau / 16
        m.slot("SteelLight").bolt((math.cos(a) * 1.9, math.sin(a) * 1.9, 0.5), r=0.08)
    m.attach["Face"] = (0, 0, 0.6)
    m.attach["Light"] = (0, 0, 1.0)
    m.extra["collider"] = {"size": K.roblox_size((4.4, 4.4, 0.6)), "offset": K.to_roblox((0, 0, 0.3))}
