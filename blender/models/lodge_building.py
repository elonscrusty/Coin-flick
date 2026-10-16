"""Prospector Lodge (docs/lodge/MASTER_PROMPT_Claude_Blender.md sections 4, 6, 13, 14, 15, 20): the
structural building of the FIND THE GEODE lobby, plus its blank exterior title plaque.

Lodge_Building is ONE model (one FBX, one Roblox Model) holding material-specific pieces that are
already assembled: floor slab + flagstones, stone foundation / wall base, timber frame (posts, beams,
braces, window casings), cream plaster infill, glass (separate, transparent), five roof trusses, purlins,
ridge beam, boarded ceiling, slate-brown tiled roof + ridge cap, front door frame with two door leaves
(own pieces, hinge pivots, shown open ~100 degrees inward), porch, three broad steps and porch rails.
No furnishings (stalls, bays, boards, benches, lamps, rugs ... are separate assets).

Coordinates (Blender, 1 unit = 1 stud): origin (0, 0, 0) = finished interior floor top, centre of the
room. X right, Y toward the rear (hunt wall), Z up. Clear interior X -42..42, Y -34..34, floor top Z 0.
Walls 1.2 thick outside that box, eaves Z 26, ridge cap top Z 40 at X 0 (ridge runs along Y), roof
overhang 2, slab down to Z -1, foundation to Z -3.4, outside ground Z -3. Front door 18 x 14 at X 0 on
the front (-Y) wall; porch and steps reach Y -44. The build pipeline exports Roblox = (-x, z, y), so the
door faces Roblox -Z (docs/lodge/BUILD_NOTES.md has the placement table and the master prompt's mapping).

Pieces are split by material AND by region (front / rear / left / right / roof halves) so no MeshPart is
huge or over ~6k triangles. Box colliders (walls around the door opening, floor, porch, steps, rails) and
a hidden ramp over the steps are recorded in the manifest (`colliders`, `ramp`); the meshes themselves
should be CanCollide = false in game.

Lodge_Plaque: blank FIND THE GEODE plaque, 14 x 0.5 x 5, origin = back centre, face toward -Y; Face is
a flat dark board for a SurfaceGui (attach Text). Mount it at Lodge_Building attach `Plaque`.
"""

import math
import random

import bmesh
from mathutils import Vector

import ctrkit as K
from ctrkit import register
from models._lobbyparts import part

SHEET = "lodge"

# ------------------------------------------------------------------ palette (master prompt section 13)
for _k, _v, _m in (
    ("LodgeTimber", "#A9693F", "Wood"),        # WoodMain
    ("LodgeTimberDark", "#70452D", "Wood"),    # WoodDark: pegs, door battens, joists, plaque board
    ("LodgePlaster", "#E7D6B8", "SmoothPlastic"),
    ("LodgeStone", "#A79F90", "Slate"),        # StoneMain: foundation blocks, floor stones
    ("LodgeStoneLight", "#B4AA98", "Slate"),   # second floor-stone tone (low contrast)
    ("LodgeStoneDark", "#827B71", "Slate"),    # StoneDark: floor grout slab, wall-base blocks
    ("LodgeIron", "#343639", "Metal"),         # MetalDark: hinges, handles, plaque bolts
    ("LodgeRoof", "#634437", "Slate"),         # slate-brown roof tiles
    ("LodgeRoofDark", "#553A2F", "Slate"),     # second tile tone, roof base, ridge cap
    ("LodgeCeiling", "#C18E5E", "WoodPlanks"), # boarded ceiling seen from inside
    ("LodgeGlass", "#D9ECF2", "Glass"),        # clear, lightly tinted panes (transparency 0.7 in game)
):
    K.HEX.setdefault(_k, _v)
    K.SLOT_MATERIAL.setdefault(_k, _m)

# ------------------------------------------------------------------ dimensions (master prompt section 4)
IX, IY = 42.0, 34.0          # clear interior half extents
T = 1.2                      # wall thickness (outside the clear box)
OX, OY = IX + T, IY + T      # outer wall faces 43.2 / 35.2
EAVE = 26.0
RIDGE_TOP = 40.0
OVER = 2.0                   # roof overhang
GROUND = -3.0                # outside ground level
DOOR_W, DOOR_H = 18.0, 14.0
PORCH_Y = -39.8              # porch deck front edge; steps reach -44
STEP_RUN, STEP_RISE = 1.4, 0.75
TRUSS_Y = (-28.0, -14.0, 0.0, 14.0, 28.0)
# Roof underside line: passes the outer wall top (OX, EAVE), meets X 0 at UNDER0. Layers above it
# (perpendicular): boards 0..0.4, base 0.4..0.9, tiles 0.9..1.3; the ridge cap tops out at Z 40.
UNDER0 = 38.2
SLOPE = (UNDER0 - EAVE) / OX
ALPHA = math.atan(SLOPE)
ROOF_X = OX + OVER
ROOF_Y = OY + OVER

# window bands (z0, z1)
HIGH = (16.0, 24.0)          # front / rear high windows
SIDE_HIGH = (18.5, 24.5)     # side walls (Z 13.5..17.5 left as plaster for the posters above the stalls)
BAY_LOW = (3.0, 11.0)        # rear windows behind the hunt bays (quarry view)

POST = 1.4                   # post width along the wall
POST_N = 0.75                # post half depth (wall-normal)
BEAM_N = 0.7
PLASTER_N = 0.4
CORNER = 1.9


def under(x):
    """Z of the roof underside line at |x| (inside the walls; continues over the eaves)."""
    return EAVE + SLOPE * (OX - abs(x))


def V(x, y, z):
    return Vector((x, y, z))


# ------------------------------------------------------------------ walls
# A wall is described in (u, n, z): u along the wall (left to right seen from inside for front/rear,
# front to back for the sides), n = outward offset from the wall centre line, z up.
WALLS = {
    "Front": ("x", -(IY + T / 2), -1),
    "Rear": ("x", IY + T / 2, 1),
    "Left": ("y", -(IX + T / 2), -1),
    "Right": ("y", IX + T / 2, 1),
}


def wpt(wall, u, n, z):
    axis, c, out = WALLS[wall]
    if axis == "x":
        return V(u, c + out * n, z)
    return V(c + out * n, u, z)


def wbox(piece, wall, u0, u1, n0, n1, z0, z1, bevel=0.08):
    axis = WALLS[wall][0]
    a, b = wpt(wall, u0, n0, z0), wpt(wall, u1, n1, z1)
    lo = V(min(a.x, b.x), min(a.y, b.y), min(a.z, b.z))
    hi = V(max(a.x, b.x), max(a.y, b.y), max(a.z, b.z))
    size = hi - lo
    if min(size) <= 1e-4:
        return
    piece.box(tuple(size), loc=(lo + hi) / 2, bevel=bevel)


def rects_minus(u0, u1, z0, z1, holes):
    """Rectangle minus rectangular holes as a list of (u0, u1, z0, z1) boxes (row strips merged)."""
    us = sorted({u0, u1, *[h[0] for h in holes], *[h[1] for h in holes]})
    zs = sorted({z0, z1, *[h[2] for h in holes], *[h[3] for h in holes]})
    us = [u for u in us if u0 <= u <= u1]
    zs = [z for z in zs if z0 <= z <= z1]
    out = []
    for j in range(len(zs) - 1):
        za, zb = zs[j], zs[j + 1]
        run = None
        for i in range(len(us) - 1):
            ua, ub = us[i], us[i + 1]
            cu, cz = (ua + ub) / 2, (za + zb) / 2
            solid = not any(h[0] < cu < h[1] and h[2] < cz < h[3] for h in holes)
            if solid:
                run = (run[0], ub) if run else (ua, ub)
            elif run:
                out.append((run[0], run[1], za, zb))
                run = None
        if run:
            out.append((run[0], run[1], za, zb))
    # merge vertically identical strips
    merged = []
    for r in out:
        for k, m in enumerate(merged):
            if abs(m[0] - r[0]) < 1e-6 and abs(m[1] - r[1]) < 1e-6 and abs(m[3] - r[2]) < 1e-6:
                merged[k] = (m[0], m[1], m[2], r[3])
                break
        else:
            merged.append(r)
    return merged


def window(m, wall, u0, u1, z0, z1, glass, timber, transom=None):
    """Glazed opening: thin pane in the wall centre, casing boards, mullions (+ optional transom), sill."""
    wbox(glass, wall, u0, u1, -0.06, 0.06, z0, z1, bevel=0)
    c = 0.45
    wbox(timber, wall, u0 - c, u0, -0.58, 0.58, z0, z1, bevel=0.06)
    wbox(timber, wall, u1, u1 + c, -0.58, 0.58, z0, z1, bevel=0.06)
    wbox(timber, wall, u0 - c, u1 + c, -0.58, 0.58, z1, z1 + c, bevel=0.06)
    wbox(timber, wall, u0 - c - 0.2, u1 + c + 0.2, -0.85, 0.85, z0 - 0.4, z0, bevel=0.06)
    n = max(1, round((u1 - u0) / 4.8))
    for i in range(1, n):
        u = u0 + (u1 - u0) * i / n
        wbox(timber, wall, u - 0.17, u + 0.17, -0.3, 0.3, z0, z1, bevel=0.04)
    if transom is None and z1 - z0 >= 9.0:
        transom = z0 + (z1 - z0) * 0.62
    if transom:
        wbox(timber, wall, u0, u1, -0.3, 0.3, transom - 0.17, transom + 0.17, bevel=0.04)


def pegs(m, wall, u, z, n_face=POST_N + 0.02, both=True):
    """Two small square timber pegs on a joint (on the inside and outside face)."""
    peg = part(m, "Pegs", "LodgeTimberDark")
    for s in ((-1, 1) if both else (1,)):
        for dz in (-0.3, 0.3):
            wbox(peg, wall, u - 0.17, u + 0.17, s * n_face, s * (n_face + 0.1), z + dz - 0.17, z + dz + 0.17, bevel=0)


def block(piece, wall, u0, u1, n0, n1, z0, z1, face=1, ch=0.16):
    """Stone block with its visible face (n1 side if face > 0, else n0) chamfered inward: 12 triangles."""
    t = bmesh.new()
    vs = []
    for n in (n0, n1):
        shrink = ch if (n == n1) == (face > 0) else 0.0
        for (u, z) in ((u0 + shrink, z0 + shrink), (u1 - shrink, z0 + shrink), (u1 - shrink, z1 - shrink), (u0 + shrink, z1 - shrink)):
            vs.append(t.verts.new(wpt(wall, u, n, z)))
    a, b = vs[:4], vs[4:]
    t.faces.new(a)
    t.faces.new(b)
    for i in range(4):
        j = (i + 1) % 4
        t.faces.new((a[i], a[j], b[j], b[i]))
    bmesh.ops.recalc_face_normals(t, faces=t.faces)
    piece.add_bm(t)


def stone_row(pieces, wall, u0, u1, n0, n1, z0, z1, seed, avg=3.2, gap=0.1, face=1):
    rng = random.Random(seed)
    cuts = [u0]
    while cuts[-1] < u1 - avg * 0.6:
        cuts.append(cuts[-1] + avg * rng.uniform(0.7, 1.3))
    cuts[-1] = u1
    for i in range(len(cuts) - 1):
        p = pieces[rng.randrange(len(pieces))]
        lift = rng.uniform(-0.03, 0.06) * face
        if face > 0:
            block(p, wall, cuts[i] + gap / 2, cuts[i + 1] - gap / 2, n0, n1 + lift, z0 + gap / 2, z1 - gap / 2, face)
        else:
            block(p, wall, cuts[i] + gap / 2, cuts[i + 1] - gap / 2, n0 + lift, n1, z0 + gap / 2, z1 - gap / 2, face)


def build_wall(m, wall, posts, holes, windows, beams, brace_spans, base_gaps=(), seed=0):
    """posts: [(u, width)], holes: plaster holes [(u0, u1, z0, z1)], windows: [(u0, u1, z0, z1)],
    beams: [(u0, u1, z0, z1)], brace_spans: [(post_u, dir)] knee braces in the lower panels."""
    timber = part(m, "Timber" + wall, "LodgeTimber", "Wood")
    plaster = part(m, "Plaster" + wall, "LodgePlaster")
    glass = part(m, "Glass" + wall, "LodgeGlass", transparency=0.7)
    span = IX if WALLS[wall][0] == "x" else IY
    ulo, uhi = -(span + T) + CORNER - 0.3, (span + T) - CORNER + 0.3
    for r in rects_minus(ulo, uhi, 0.0, EAVE, holes):
        wbox(plaster, wall, r[0], r[1], -PLASTER_N, PLASTER_N, r[2], r[3], bevel=0)
    for u, w in posts:
        wbox(timber, wall, u - w / 2, u + w / 2, -POST_N, POST_N, 0.0, EAVE + 0.3, bevel=0.1)
    for b in beams:
        wbox(timber, wall, b[0], b[1], -BEAM_N, BEAM_N, b[2], b[3], bevel=0.08)
    for w in windows:
        window(m, wall, *w, glass, timber)
    for pu, d in brace_spans:   # lower-panel knee braces (sheet 01 wall segment)
        a = wpt(wall, pu + d * POST / 2, 0, 8.6)
        b = wpt(wall, pu + d * (POST / 2 + 4.2), 0, 12.9)
        timber.box_between(a, b, 1.1, bevel=0.06)
    # pegs where beams cross posts
    for u, w in posts:
        for b in beams:
            if b[0] < u < b[1]:
                pegs(m, wall, u, (b[2] + b[3]) / 2)
    # interior stone base (one row of blocks) and exterior wall base (three rows) with gaps at the door
    stone, dark = part(m, "Base" + wall, "LodgeStone"), part(m, "BaseDark" + wall, "LodgeStoneDark")
    runs = [(ulo - 0.3, uhi + 0.3)]
    for g0, g1 in base_gaps:
        new = []
        for r0, r1 in runs:
            if g1 <= r0 or g0 >= r1:
                new.append((r0, r1))
                continue
            if g0 > r0:
                new.append((r0, g0))
            if g1 < r1:
                new.append((g1, r1))
        runs = new
    for k, (r0, r1) in enumerate(runs):
        stone_row([dark, stone], wall, r0, r1, -0.75, -0.5, 0.0, 2.5, seed + 11 * k, avg=3.6, face=-1)
        outer = (r0 - 0.9, r1 + 0.9)
        rows = ((GROUND - 0.4, -0.9), (-0.9, 0.9), (0.9, 2.6))
        for j, (z0, z1) in enumerate(rows):
            stone_row([stone, dark, stone], wall, outer[0], outer[1], 0.45, 1.05, z0, z1, seed + 100 * j + 7 * k,
                      avg=3.0 + 0.4 * (j % 2))
    # sill beam on top of the outer stone base
    for r0, r1 in runs:
        wbox(timber, wall, r0, r1, -0.5, 1.1, 2.6, 3.4, bevel=0.08)


def segments_windows(edges, z0, z1, margin=1.5):
    """One window per segment between consecutive post centres."""
    out = []
    for a, b in zip(edges, edges[1:]):
        out.append((a + margin, b - margin, z0, z1))
    return out


def walls(m):
    cu = OX - CORNER / 2   # corner post centre along front/rear walls
    cy = OY - CORNER / 2
    # ---------------- front (door wall)
    dp = DOOR_W / 2 + 0.8                       # door post centres (1.6 wide)
    fposts = [(-dp, 1.6), (dp, 1.6), (-25.5, POST), (25.5, POST)]
    fedges_l = [-cu, -25.5, -dp]
    fedges_r = [dp, 25.5, cu]
    fwin = segments_windows(fedges_l, *HIGH) + segments_windows(fedges_r, *HIGH)
    fholes = [(-DOOR_W / 2 - 0.0, DOOR_W / 2, -1, DOOR_H)] + fwin
    fbeams = [(-cu, -dp, 12.9, 13.9), (dp, cu, 12.9, 13.9),
              (-cu, -dp, 15.2, 16.0), (dp, cu, 15.2, 16.0),
              (-cu, cu, 25.0, 26.4),
              (-dp - 0.8, dp + 0.8, DOOR_H, DOOR_H + 1.6)]    # door header
    build_wall(m, "Front", fposts, fholes, fwin, fbeams, [(-25.5, -1), (-25.5, 1), (25.5, -1), (25.5, 1)],
               base_gaps=[(-dp - 0.8, dp + 0.8)], seed=1)
    # ---------------- rear (hunt wall): low windows behind the three bays + high windows
    rp = [-30.0, -18.0, -6.0, 6.0, 18.0, 30.0]
    rposts = [(u, POST) for u in rp]
    redges = [-cu] + rp + [cu]
    rwin = segments_windows(redges, *HIGH)
    rlow = [(-18 + 1.2, -6 - 1.2, *BAY_LOW), (-6 + 1.2, 6 - 1.2, *BAY_LOW), (6 + 1.2, 18 - 1.2, *BAY_LOW)]
    rbeams = [(-cu, cu, 12.9, 13.9), (-cu, cu, 15.2, 16.0), (-cu, cu, 25.0, 26.4)]
    build_wall(m, "Rear", rposts, rwin + rlow, rwin + rlow, rbeams,
               [(-30, -1), (30, 1)], seed=2)
    # ---------------- sides
    sposts = [(u, POST) for u in TRUSS_Y]
    sedges = list(TRUSS_Y)
    swin = segments_windows(sedges, *SIDE_HIGH)
    sbeams = [(-cy, cy, 12.9, 13.9), (-cy, cy, 17.6, 18.5), (-cy, cy, 25.0, 26.4)]
    braces = [(-28, 1), (-14, -1), (14, 1), (28, -1), (-28, -1), (28, 1)]
    for wall, seed in (("Left", 3), ("Right", 4)):
        build_wall(m, wall, sposts, swin, swin, sbeams, braces, seed=seed)
    # ---------------- corner posts (bigger, with a stone corner block below)
    timber = part(m, "Corners", "LodgeTimber", "Wood")
    stone = part(m, "BaseCorners", "LodgeStone")
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * (OX - CORNER / 2), sy * (OY - CORNER / 2)
            timber.box((CORNER, CORNER, EAVE + 0.4 - 2.6), loc=(x, y, 2.6 + (EAVE + 0.4 - 2.6) / 2), bevel=0.12)
            timber.box((CORNER + 0.5, CORNER + 0.5, 1.0), loc=(x + sx * 0.12, y + sy * 0.12, 3.1), bevel=0.1)
            stone.box((CORNER + 1.0, CORNER + 1.0, 2.6 - GROUND + 0.4), loc=(x + sx * 0.3, y + sy * 0.3, (2.6 + GROUND - 0.4) / 2),
                      bevel=0.16)


# ------------------------------------------------------------------ gables (front + rear above the eaves)

def gable(m, wall, glazed=14.0):
    timber = part(m, "Gable" + wall, "LodgeTimber", "Wood")
    plaster = part(m, "GablePlaster" + wall, "LodgePlaster")
    glass = part(m, "GableGlass" + wall, "LodgeGlass", transparency=0.7)
    y = WALLS[wall][1]
    zb = EAVE + 0.4
    g = glazed + 0.7
    for s in (-1, 1):   # plaster triangles outside the glazing
        prof = [(s * g, zb), (s * OX, zb), (s * OX, under(OX) - 0.05), (s * g, under(g) - 0.05)]
        if s > 0:
            prof = prof[::-1]
        plaster.prism([(x, z) for x, z in prof], 2 * PLASTER_N, loc=(0, y, 0))
    gl = [(-glazed, zb), (glazed, zb), (glazed, under(glazed)), (0, under(0)), (-glazed, under(glazed))]
    glass.prism(gl, 0.12, loc=(0, y, 0))
    # posts / mullions up to the roof line
    for x in (-glazed, -glazed / 2, 0.0, glazed / 2, glazed):
        w = POST if abs(x) in (0.0, glazed) else 0.5
        dn = POST_N if w == POST else 0.32
        timber.box((w, 2 * dn, under(x) - zb), loc=(x, y, (under(x) + zb) / 2), bevel=0.06)
    # transom across the glazing, and a collar at the top
    zt = 31.0
    timber.box((2 * glazed, 0.6, 0.4), loc=(0, y, zt), bevel=0.04)
    # gable rafters (barge rafters inside the wall plane, just under the roof)
    for s in (-1, 1):
        a = V(s * (OX + 0.2), y, under(OX + 0.2) - 0.65)
        b = V(0, y, under(0) - 0.65)
        timber.box_between(a, b, 1.3, bevel=0.08)
    # diagonal braces in the plaster triangles
    for s in (-1, 1):
        a = V(s * (g + 0.2), y, zb + 0.4)
        b = V(s * (g + 9.5), y, under(g + 9.5) - 1.2)
        timber.box_between(a, b, 1.1, bevel=0.06)
    # tie / collar beam at the eaves line across the gable
    timber.box((2 * OX, 2 * BEAM_N, 0.8), loc=(0, y, EAVE + 0.4), bevel=0.08)


# ------------------------------------------------------------------ trusses, purlins, ridge

def trusses(m):
    tr = part(m, "Trusses", "LodgeTimber", "Wood")
    peg = part(m, "TrussPegs", "LodgeTimberDark")
    w = 1.2
    for y in TRUSS_Y:
        zt = EAVE - 0.5
        tr.box((2 * IX + 0.6, w, 1.4), loc=(0, y, zt), bevel=0.1)               # tie beam (Z 24.8..26.2)
        tr.box((1.4, w, under(0) - 0.6 - (zt + 0.7)), loc=(0, y, (under(0) - 0.6 + zt + 0.7) / 2), bevel=0.1)  # king post
        for s in (-1, 1):
            a = V(s * (IX + 0.2), y, under(IX + 0.2) - 0.7)
            b = V(0, y, under(0) - 0.7)
            tr.box_between(a, b, 1.25, bevel=0.1)                                # principal rafter
            tr.box_between(V(s * 0.6, y, zt + 0.9), V(s * 20.0, y, under(20.0) - 1.2), 0.95, bevel=0.08)  # strut
            q0, q1 = zt + 0.7, under(28.0) - 0.9                                   # queen post
            tr.box((0.8, w + 0.02, q1 - q0), loc=(s * 28.0, y, (q0 + q1) / 2), bevel=0.06)
            # knee brace from the wall post to the tie beam
            tr.box_between(V(s * (IX - 0.3), y, 19.2), V(s * (IX - 5.6), y, zt - 0.6), 0.85, bevel=0.06)
            for dz in (-0.3, 0.3):
                peg.box((0.34, w + 0.24, 0.34), loc=(s * 36.5, y, zt + dz), bevel=0)
        for dz in (-0.3, 0.3):
            peg.box((0.34, w + 0.24, 0.34), loc=(0, y, zt + dz), bevel=0)
    # purlins and ridge beam along Y (between the gables), wall plates on the side walls
    roof = part(m, "RoofFrame", "LodgeTimber", "Wood")
    L = 2 * OY
    roof.box((1.5, L, 1.5), loc=(0, 0, under(0) - 0.75), bevel=0.1)
    for x in (12.0, 24.0, 35.0):
        for s in (-1, 1):
            roof.box((1.0, L, 1.0), loc=(s * x, 0, under(x) - 0.55), bevel=0.08)


def chandelier_hook(m):
    """Short iron hook plate under the centre king post (chandelier suspension point Z 31)."""
    iron = part(m, "Iron", "LodgeIron", "Metal")
    iron.box((1.0, 1.4, 0.3), loc=(0, 0, 31.15), bevel=0.04)
    iron.cyl(0.18, 0.18, 0.5, seg=6, loc=(0, 0, 30.75))
    m.attach["Chandelier"] = (0, 0, 31.0)


# ------------------------------------------------------------------ roof

def _slope_center(s, d, h):
    """Point at horizontal distance d from the ridge on side s (+1 right / -1 left), h studs above the
    underside line (measured perpendicular to the slope)."""
    x = s * d
    nrm = V(s * math.sin(ALPHA), 0, math.cos(ALPHA))
    return V(x, 0, under(d)) + nrm * h


def roof(m):
    ang = math.degrees(ALPHA)
    Lh = ROOF_X                         # horizontal reach from the ridge to the eave edge
    Ls = Lh / math.cos(ALPHA)           # slope length
    for s, side in ((-1, "L"), (1, "R")):
        rot = (0, s * ang, 0)
        # boarded ceiling (seen from inside): planks running down the slope
        ceil = part(m, "Ceiling" + side, "LodgeCeiling")
        n = int(2 * ROOF_Y / 2.0)
        bw = 2 * ROOF_Y / n
        for i in range(n):
            y = -ROOF_Y + bw * (i + 0.5)
            c = _slope_center(s, Lh / 2, 0.2)
            ceil.box((Ls + 0.3, bw - 0.1, 0.4), loc=(c.x, y, c.z), rot=rot, bevel=0)
        # solid roof base (closes every seam)
        base = part(m, "RoofBase" + side, "LodgeRoofDark")
        c = _slope_center(s, Lh / 2, 0.65)
        base.box((Ls + 0.4, 2 * ROOF_Y, 0.5), loc=(c.x, 0, c.z), rot=rot, bevel=0)
        # tile courses, slightly flatter than the roof so each lower edge steps out over the next course
        tiles = [part(m, "RoofTiles" + side, "LodgeRoof"), part(m, "RoofTiles" + side + "2", "LodgeRoofDark")]
        rng = random.Random(7 if s < 0 else 8)
        courses = 12
        cl = Ls / courses
        for k in range(courses):
            dmid = (k + 0.5) * cl * math.cos(ALPHA)
            c = _slope_center(s, dmid, 1.08)
            tl = 4.6
            off = (tl / 2) if k % 2 else 0.0
            y0 = -ROOF_Y - off
            while y0 < ROOF_Y:
                a, b = max(y0, -ROOF_Y), min(y0 + tl, ROOF_Y)
                if b - a > 0.3:
                    p = tiles[0] if rng.random() < 0.8 else tiles[1]
                    p.box((cl + 0.25, b - a - 0.12, 0.36), loc=(c.x, (a + b) / 2, c.z), rot=(0, s * (ang - 2.2), 0), bevel=0)
                y0 += tl
        # eave fascia board and rafter tails under the overhang
        fas = part(m, "RoofTrim", "LodgeTimber", "Wood")
        e = _slope_center(s, ROOF_X - 0.2, 0.25)
        fas.box((0.5, 2 * ROOF_Y + 0.6, 1.3), loc=(e.x + s * 0.1, 0, e.z - 0.15), bevel=0.06)
        for y in list(TRUSS_Y) + [-(OY - CORNER / 2), OY - CORNER / 2]:
            a = V(s * (OX - 0.4), y, under(OX) - 0.75)
            b = V(s * (ROOF_X - 0.4), y, under(ROOF_X - 0.4) - 0.55)
            fas.box_between(a, b, 0.9, bevel=0.06)
        # barge boards along the gable edges (front and rear)
        for gy in (-ROOF_Y - 0.25, ROOF_Y + 0.25):
            c = _slope_center(s, Lh / 2, 0.75)
            fas.box((Ls + 0.4, 0.5, 1.6), loc=(c.x, gy, c.z), rot=rot, bevel=0.06)
    # ridge cap: dark log-like beam along Y, top at Z 40
    cap = part(m, "RidgeCap", "LodgeRoofDark")
    ztop = RIDGE_TOP
    cap.box((2.4, 2 * ROOF_Y + 1.2, 0.5), loc=(0, 0, ztop - 0.75), bevel=0.08)
    cap.cyl(0.85, 0.85, 2 * ROOF_Y + 1.6, seg=8, loc=(0, 0, ztop - 0.85), rot=(90, 0, 0), scale=(1.0, 1.0))
    trim = part(m, "RoofTrim", "LodgeTimber", "Wood")
    for gy in (-ROOF_Y - 0.6, ROOF_Y + 0.6):
        trim.box((1.6, 0.6, 1.6), loc=(0, gy, ztop - 1.4), bevel=0.08)


# ------------------------------------------------------------------ floor

def _clip_half(poly, p, nrm):
    """Keep the part of polygon `poly` (list of (x, y)) with (q - p) . nrm <= 0."""
    out = []
    for i in range(len(poly)):
        a, b = poly[i - 1], poly[i]
        da = (a[0] - p[0]) * nrm[0] + (a[1] - p[1]) * nrm[1]
        db = (b[0] - p[0]) * nrm[0] + (b[1] - p[1]) * nrm[1]
        if db <= 0:
            if da > 0:
                t = da / (da - db)
                out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
            out.append(b)
        elif da <= 0:
            t = da / (da - db)
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return out


def _stone(piece, poly, z0, z1, chamfer=0.1):
    """Flat flagstone: polygon footprint, top face shrunk by `chamfer` (soft edge without bevel tris)."""
    cx = sum(p[0] for p in poly) / len(poly)
    cy = sum(p[1] for p in poly) / len(poly)
    t = bmesh.new()
    bot, top = [], []
    for x, y in poly:
        d = math.hypot(x - cx, y - cy) or 1
        k = max(0.0, (d - chamfer) / d)
        bot.append(t.verts.new((x, y, z0)))
        top.append(t.verts.new((cx + (x - cx) * k, cy + (y - cy) * k, z1)))
    t.faces.new(top)
    n = len(poly)
    for i in range(n):
        j = (i + 1) % n
        t.faces.new((bot[i], bot[j], top[j], top[i]))
    bmesh.ops.recalc_face_normals(t, faces=t.faces)
    piece.add_bm(t)


def floor(m):
    grout = part(m, "FloorSlab", "LodgeStoneDark")
    grout.box((2 * OX, 2 * OY, 0.95), loc=(0, 0, -1.0 + 0.95 / 2), bevel=0)       # Z -1 .. -0.05
    rng = random.Random(42)
    cell = 3.1
    sites = []
    nx, ny = int(2 * IX / cell) + 1, int(2 * IY / cell) + 1
    for i in range(nx):
        for j in range(ny):
            x = -IX + (i + 0.5) * (2 * IX / nx) + rng.uniform(-0.38, 0.38) * cell
            y = -IY + (j + 0.5) * (2 * IY / ny) + rng.uniform(-0.38, 0.38) * cell
            sites.append((x, y))
    tones = {}
    for (x, y) in sites:
        poly = [(-IX, -IY), (IX, -IY), (IX, IY), (-IX, IY)]
        for (ox, oy) in sites:
            if (ox, oy) == (x, y) or abs(ox - x) > 2.6 * cell or abs(oy - y) > 2.6 * cell:
                continue
            mid = ((x + ox) / 2, (y + oy) / 2)
            poly = _clip_half(poly, mid, (ox - x, oy - y))
            if len(poly) < 3:
                break
        if len(poly) < 3:
            continue
        # grout gap: shrink toward the centroid
        cx = sum(p[0] for p in poly) / len(poly)
        cy = sum(p[1] for p in poly) / len(poly)
        poly = [(cx + (px - cx) * 0.965, cy + (py - cy) * 0.965) for px, py in poly]
        # drop near-duplicate vertices
        clean = []
        for p in poly:
            if not clean or math.hypot(p[0] - clean[-1][0], p[1] - clean[-1][1]) > 0.08:
                clean.append(p)
        if len(clean) > 2 and math.hypot(clean[0][0] - clean[-1][0], clean[0][1] - clean[-1][1]) < 0.08:
            clean.pop()
        if len(clean) < 3:
            continue
        half = "Front" if cy < 0 else "Rear"
        tone = "LodgeStone" if rng.random() < 0.55 else "LodgeStoneLight"
        key = (tone, half)
        if key not in tones:
            tones[key] = part(m, "Floor" + ("A" if tone == "LodgeStone" else "B") + half, tone)
        _stone(tones[key], clean, -0.06, 0.0, chamfer=0.09)
    # threshold stone in the door opening (front wall zone)
    part(m, "Threshold", "LodgeStone").box((DOOR_W, T, 0.4), loc=(0, -(IY + T / 2), -0.2), bevel=0.06)


# ------------------------------------------------------------------ doors

def door_leaf(m, side):
    """Door leaf 8.5 x 0.5 x 13.5 hung at the door post, open 100 degrees inward. side -1 = left."""
    name = "DoorL" if side < 0 else "DoorR"
    hx, hy = side * (DOOR_W / 2 - 0.1), -IY + 0.35       # hinge axis (bottom point)
    pivot = (hx, hy, 0.15)
    wood = part(m, name, "LodgeTimber", "WoodPlanks", anim="Swing", pivot=pivot)
    batt = part(m, name + "Battens", "LodgeTimberDark", "Wood", anim="Swing", pivot=pivot)
    iron = part(m, name + "Iron", "LodgeIron", "Metal", anim="Swing", pivot=pivot)
    # local frame: ux runs along the leaf away from the hinge (closed = toward the centre), vx = leaf normal
    angle = math.radians(100.0) * (1 if side < 0 else -1)
    ux = V(math.cos(angle), math.sin(angle), 0) * (1 if side < 0 else -1)   # along the leaf, away from hinge
    vx = V(-ux.y, ux.x, 0)                                                   # leaf normal
    o = V(hx, hy, 0.15)
    W, H, Tk = 8.5, 13.5, 0.45
    rotz = math.degrees(math.atan2(ux.y, ux.x))

    def put(piece, u0, u1, v0, v1, z0, z1, bevel=0.05):
        c = o + ux * ((u0 + u1) / 2) + vx * ((v0 + v1) / 2) + V(0, 0, (z0 + z1) / 2)
        piece.box((u1 - u0, v1 - v0, z1 - z0), loc=c, rot=(0, 0, rotz), bevel=bevel)

    planks = 4
    pw = W / planks
    for i in range(planks):
        put(wood, i * pw + 0.04, (i + 1) * pw - 0.04, -Tk / 2, Tk / 2, 0, H, bevel=0.05)
    for f in (-1, 1):   # battens + diagonal brace on both faces
        v0, v1 = (Tk / 2, Tk / 2 + 0.22) if f > 0 else (-Tk / 2 - 0.22, -Tk / 2)
        for z in (1.2, H / 2, H - 1.2):
            put(batt, 0.3, W - 0.3, v0, v1, z - 0.4, z + 0.4, bevel=0.04)
        for z_a, z_b in ((1.6, H / 2 - 0.4), (H / 2 + 0.4, H - 1.6)):
            a = o + ux * 0.9 + vx * ((v0 + v1) / 2) + V(0, 0, z_a)
            b = o + ux * (W - 0.9) + vx * ((v0 + v1) / 2) + V(0, 0, z_b)
            batt.box_between(a, b, 0.6, bevel=0.04)
        # strap hinges and a ring handle
        for z in (1.2, H - 1.2):
            put(iron, 0.0, 3.2, v1 if f > 0 else v0 - 0.08, (v1 + 0.08) if f > 0 else v0, z - 0.25, z + 0.25, bevel=0.02)
        hv = (v1 + 0.15) if f > 0 else (v0 - 0.15)
        c = o + ux * (W - 0.9) + vx * hv + V(0, 0, 6.6)
        iron.cyl(0.32, 0.32, 0.12, seg=8, loc=c, rot=(90, 0, rotz))
        iron.cyl(0.42, 0.42, 0.08, seg=8, loc=c - V(0, 0, 0.55), rot=(90, 0, rotz))
    # hinge barrels on the axis
    for z in (1.2, H - 1.2):
        iron.cyl(0.18, 0.18, 0.7, seg=6, loc=o + V(0, 0, z))
    return name


# ------------------------------------------------------------------ porch, steps, rails

def porch(m):
    deck = part(m, "Porch", "LodgeTimber", "WoodPlanks")
    joist = part(m, "PorchFrame", "LodgeTimberDark", "Wood")
    stone, dark = part(m, "PorchStone", "LodgeStone"), part(m, "PorchStoneDark", "LodgeStoneDark")
    half = 14.0
    y0, y1 = -OY, PORCH_Y
    depth = y0 - y1
    # deck planks run across the door (along X), top at Z 0
    n = int(depth / 1.0)
    pw = depth / n
    for i in range(n):
        y = y0 - pw * (i + 0.5)
        deck.box((2 * half, pw - 0.08, 0.4), loc=(0, y, -0.2), bevel=0.05)
    joist.box((2 * half - 0.6, depth - 0.3, 1.0), loc=(0, (y0 + y1) / 2, -0.9), bevel=0)
    joist.box((2 * half + 0.2, 0.6, 0.8), loc=(0, y1 - 0.0, -0.6), bevel=0.06)          # front rim board
    # stone piers under the deck
    for x in (-half + 1.0, half - 1.0):
        stone.box((2.2, depth - 0.2, -GROUND - 0.4), loc=(x, (y0 + y1) / 2, (GROUND - 0.4) / 2 - 0.2), bevel=0.14)
    for x in (-half + 3.2, half - 3.2):
        dark.box((2.0, 2.0, -GROUND - 0.4), loc=(x, y1 + 1.2, (GROUND - 0.4) / 2 - 0.2), bevel=0.14)
    # three broad steps down to the ground
    sw = 2 * 10.0
    for i in range(3):
        top = -(i + 1) * STEP_RISE
        yy = y1 - STEP_RUN * (i + 0.5)
        h = top - (GROUND - 0.3)
        deck.box((sw, STEP_RUN + 0.06, 0.35), loc=(0, yy, top - 0.175), bevel=0.05)
        joist.box((sw - 0.4, STEP_RUN, h - 0.35), loc=(0, yy + 0.05, top - 0.35 - (h - 0.35) / 2), bevel=0.04)
    for s in (-1, 1):   # stone cheeks beside the steps
        stone.box((1.4, 3 * STEP_RUN, -GROUND), loc=(s * (10.0 + 0.7), y1 - 1.5 * STEP_RUN, GROUND / 2 - 0.2), bevel=0.14)
    # rails: porch sides (along Y) and the front returns beside the steps
    rail = part(m, "Rails", "LodgeTimber", "Wood")
    ph = 3.6

    def post(x, y, h=ph, s=0.95):
        rail.box((s, s, h), loc=(x, y, h / 2), bevel=0.08)
        rail.box((s + 0.25, s + 0.25, 0.3), loc=(x, y, h + 0.15), bevel=0.06)

    for sx in (-1, 1):
        xs = sx * (half - 0.5)
        post(xs, y0 - 0.6)
        post(xs, y1 + 0.5)
        for z, th in ((3.0, 0.5), (1.5, 0.4)):
            rail.box((0.45, (y0 - 0.6) - (y1 + 0.5), th), loc=(xs, (y0 + y1) / 2 - 0.05, z), bevel=0.05)
        # front return beside the steps, with a lantern post at the step edge
        xi = sx * 10.9
        post(xi, y1 + 0.5, h=ph + 0.5, s=1.1)
        for z, th in ((3.0, 0.5), (1.5, 0.4)):
            rail.box((abs(xs - xi), 0.45, th), loc=((xs + xi) / 2, y1 + 0.5, z), bevel=0.05)
        rail.box((0.4, 0.3, 1.1), loc=((xs + xi) / 2, y1 + 0.5, 2.25), bevel=0.04)
        m.attach["PorchLantern" + ("L" if sx < 0 else "R")] = (xi, y1 + 0.5, ph + 0.8)


# ------------------------------------------------------------------ colliders

def colliders(m):
    boxes = []

    def add(name, lo, hi):
        lo, hi = V(*lo), V(*hi)
        boxes.append({"name": name, "size": K.roblox_size(tuple(hi - lo)), "offset": K.to_roblox((lo + hi) / 2)})

    add("Floor", (-OX, -OY, -1.0), (OX, OY, 0.0))
    add("WallLeft", (-OX, -OY, 0), (-IX, OY, EAVE))
    add("WallRight", (IX, -OY, 0), (OX, OY, EAVE))
    add("WallRear", (-OX, IY, 0), (OX, OY, EAVE))
    add("WallFrontL", (-OX, -OY, 0), (-DOOR_W / 2, -IY, EAVE))
    add("WallFrontR", (DOOR_W / 2, -OY, 0), (OX, -IY, EAVE))
    add("WallFrontTop", (-DOOR_W / 2, -OY, DOOR_H), (DOOR_W / 2, -IY, EAVE))
    add("GableFront", (-20, -OY, EAVE), (20, -IY, 34))
    add("GableRear", (-20, IY, EAVE), (20, OY, 34))
    add("Ceiling", (-OX, -OY, EAVE), (OX, OY, EAVE + 1.0))   # keeps players off the trusses
    add("Porch", (-14, PORCH_Y, GROUND), (14, -OY, 0.0))
    for i in range(3):
        top = -(i + 1) * STEP_RISE
        add("Step%d" % (i + 1), (-10, PORCH_Y - STEP_RUN * (i + 1), GROUND), (10, PORCH_Y - STEP_RUN * i, top))
    for sx in (-1, 1):
        add("RailSide" + ("L" if sx < 0 else "R"), (sx * 14 - 0.5, PORCH_Y, 0), (sx * 14 + 0.5, -OY, 3.6))
        a, b = sorted((sx * 10.4, sx * 14.0))
        add("RailFront" + ("L" if sx < 0 else "R"), (a, PORCH_Y, 0), (b, PORCH_Y + 1.0, 3.6))
    m.extra["colliders"] = boxes
    # hidden smooth ramp over the steps for mobile (wedge from the porch edge down to the ground)
    run = 3 * STEP_RUN
    drop = -GROUND
    length = math.hypot(run, drop)
    mid = V(0, PORCH_Y - run / 2, GROUND / 2 - 0.05)
    m.extra["ramp"] = {"size": K.roblox_size((20.0, length, 0.4)), "offset": K.to_roblox(mid),
                       "tiltDeg": round(math.degrees(math.atan2(drop, run)), 2),
                       "note": "Invisible CanCollide box, rotate about Roblox X so its -Z end is lower (ground) and its +Z end meets the porch top."}


# ------------------------------------------------------------------ the model

@register("Lodge_Building", SHEET,
          "Prospector Lodge structural shell, 84 x 68 interior: stone floor + foundation, timber frame, cream plaster, "
          "rear quarry windows, 5 trusses, tiled pitched roof (eaves Z 26, ridge Z 40), front door 18 x 14 with open "
          "leaves (DoorL / DoorR, anim Swing), porch, steps, rails. Origin = interior floor centre; door faces -Y "
          "(Roblox -Z). Meshes non-colliding; use manifest colliders + ramp.")
def lodge_building(m):
    floor(m)
    walls(m)
    gable(m, "Front", glazed=14.0)
    gable(m, "Rear", glazed=14.0)
    trusses(m)
    chandelier_hook(m)
    roof(m)
    door_leaf(m, -1)
    door_leaf(m, 1)
    porch(m)
    colliders(m)
    m.attach["Plaque"] = (0, -(OY - 0.2), 19.5)
    m.attach["Door"] = (0, -IY, 0)
    m.attach["Spawn"] = (0, -30.0, 0)
    m.attach["PorchFront"] = (0, PORCH_Y - 3 * STEP_RUN, GROUND)
    m.extra["origin"] = "Interior floor top, room centre. Door faces Roblox -Z. Outside ground Y -3."


@register("Lodge_Plaque", SHEET,
          "Blank exterior title plaque (FIND THE GEODE via SurfaceGui on Face, attach Text), 14 x 0.5 x 5, "
          "origin = back centre, face toward -Y. Mount at Lodge_Building attach Plaque.")
def lodge_plaque(m):
    frame = part(m, "Frame", "LodgeTimber", "Wood")
    face = part(m, "Face", "LodgeTimberDark", "Wood")
    crest = part(m, "Crest", "LodgeTimberDark", "Wood")
    iron = part(m, "Bolts", "LodgeIron", "Metal")
    W, H, D = 14.0, 5.0, 0.5
    # flat writing face (planar front for the SurfaceGui), z -2.5 .. 1.2
    face.box((12.4, 0.3, 3.3), loc=(0, -D + 0.15 + 0.02, -0.65), bevel=0.04)
    # back board + frame boards around the face
    frame.box((13.0, 0.25, 3.9), loc=(0, -0.125, -0.6), bevel=0.04)
    frame.box((13.4, 0.42, 0.45), loc=(0, -0.29, 1.32), bevel=0.06)
    frame.box((13.4, 0.42, 0.45), loc=(0, -0.29, -2.27), bevel=0.06)
    for s in (-1, 1):
        frame.box((0.55, 0.45, 4.2), loc=(s * 6.75, -0.27, -0.55), bevel=0.06)
        frame.box((0.9, 0.45, 0.75), loc=(s * 6.55, -0.27, -2.0), bevel=0.06)   # end cleats (sheet 06 #1)
        frame.box((0.9, 0.45, 0.75), loc=(s * 6.55, -0.27, 0.9), bevel=0.06)
    # mountain crest above the board
    prof = [(-6.4, 1.3), (-4.6, 1.95), (-3.3, 1.65), (-1.4, 2.5), (0.2, 1.85), (1.6, 2.3), (3.4, 1.7), (4.8, 2.05), (6.4, 1.3)]
    crest.prism(prof + [(6.4, 1.1), (-6.4, 1.1)], 0.3, loc=(0, -0.2, 0))
    for x in (-6.75, 6.75):
        for z in (-1.7, 0.6):
            iron.bolt((x, -0.5, z), normal=(0, -1, 0), r=0.13)
    for x in (-3.5, 0, 3.5):
        iron.bolt((x, -0.5, 1.32), normal=(0, -1, 0), r=0.11)
        iron.bolt((x, -0.5, -2.27), normal=(0, -1, 0), r=0.11)
    m.attach["Text"] = (0, -D, -0.65)
    m.extra["origin"] = "Back centre (Z = plaque centre); face toward Roblox -Z."
    m.extra["textFace"] = {"size": [12.4, 3.3], "note": "SurfaceGui on Face, Front face, text FIND THE GEODE"}
