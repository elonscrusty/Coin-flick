"""Master Prompt 7 lobby pieces (Pass B): three different destination silhouettes and a compact seller.

One restrained palette for the whole lobby: warm medium wood, slate-grey stone, charcoal metal, pale label
faces, subdued green, ONE amber accent (used once per piece at most). Origins are the floor centre and
fronts face -Y (Roblox -Z), like every other kit model. Text never lives in the mesh: the game puts a
fitted SurfaceGui on the named screen / plaque pieces (attach points mark their front centres).

  Lobby7_StartTerminal  waist-high entry console (START HUNT): sloped readiness screen, wood cheeks
  Lobby7_ToolCounter    short equipment-service counter with a small pegboard backdrop and a vice (UPGRADES)
  Lobby7_InfoLectern    short slanted lectern for the Collection corner (its title sits on the cabinet)
  Lobby7_SellChute      compact receiving bin + chute + service base with one small status lamp
  Lobby7_ShrubBed       low planting pocket in the same faceted family as Court_Tree
"""

import math
import random

from mathutils import Euler, Vector

import ctrkit as K
from ctrkit import register
from models import _lobbyparts as L
from models._lobbyparts import V

S = "M7"

# the Master 7 lobby palette (MeshCatalog takes the colours from the manifest)
K.HEX.setdefault("Charcoal", "#3B3E44")     # charcoal metal (not the bluish Frame steel)
K.HEX.setdefault("CharcoalLight", "#5C6068")
K.HEX.setdefault("SlateStone", "#76787A")   # slate-grey stone
K.HEX.setdefault("SlateStoneDark", "#5B5D60")
K.HEX.setdefault("Label", "#E8E2D4")        # pale neutral label / screen face
K.HEX.setdefault("WarmAmber", "#D9A441")    # the ONE accent, muted
K.HEX.setdefault("Sage", "#6E8C5E")         # subdued greens
K.HEX.setdefault("SageDark", "#557049")
K.SLOT_MATERIAL.setdefault("Charcoal", "Metal")
K.SLOT_MATERIAL.setdefault("CharcoalLight", "Metal")
K.SLOT_MATERIAL.setdefault("SlateStone", "Slate")
K.SLOT_MATERIAL.setdefault("SlateStoneDark", "Slate")
K.SLOT_MATERIAL.setdefault("Label", "SmoothPlastic")
K.SLOT_MATERIAL.setdefault("WarmAmber", "SmoothPlastic")
K.SLOT_MATERIAL.setdefault("Sage", "Grass")
K.SLOT_MATERIAL.setdefault("SageDark", "Grass")


def side_prism(piece, profile_yz, width, x=0.0, bevel=0.05):
    """Extrude a side profile [(y, z), ...] along X (width centred on x)."""
    piece.prism(profile_yz, width, loc=(x, 0, 0), rot=(0, 0, 90), bevel=bevel)


# ------------------------------------------------------------------ START HUNT terminal

@register("Lobby7_StartTerminal", S, "Waist-high START HUNT entry console: slate stone plinth with a front step line, charcoal "
          "body with a sloped top, wood side cheeks, one pale readiness Screen piece (SurfaceGui; attach Screen = front centre, "
          "ScreenNormal = its facing) and one muted amber lip along the front edge. 3.8 x 2.4 footprint, 3.6 tall (screen slope about 39 degrees, readable from the approach).")
def start_terminal(m):
    stone, stone2 = m.slot("SlateStone"), m.slot("SlateStoneDark")
    body, wood, amber = m.slot("Charcoal"), m.slot("Wood"), m.slot("WarmAmber")
    # plinth: one low slab and a slightly smaller dressed top
    stone2.box((3.8, 2.4, 0.22), loc=(0, 0, 0.11), bevel=0.05)
    stone.box((3.4, 2.0, 0.16), loc=(0, 0.05, 0.3), bevel=0.04)
    z0 = 0.38
    # body side profile (y, z): front lower, sloped top rising to the back
    yf, yb = -0.75, 0.75
    zf, zb = 2.3, 3.5
    prof = [(yf, z0), (yb, z0), (yb, zb), (yf, zf)]
    side_prism(body, prof, 2.9, bevel=0.06)
    # wood cheeks, a little proud of the body, following the same slope
    for sx in (-1, 1):
        prof_c = [(yf - 0.08, z0), (yb + 0.08, z0), (yb + 0.08, zb + 0.12), (yf - 0.08, zf + 0.12)]
        side_prism(wood, prof_c, 0.22, x=sx * 1.56, bevel=0.05)
    # recessed kick panel at the foot of the front
    m.slot("CharcoalLight").box((2.5, 0.08, 0.5), loc=(0, yf - 0.03, z0 + 0.35), bevel=0.02)
    # the screen on the slope
    ang = math.degrees(math.atan2(zb - zf, yb - yf))
    R = Euler((math.radians(ang), 0, 0), "XYZ").to_matrix()
    mid = V(0, (yf + yb) / 2, (zf + zb) / 2)
    n = R @ V(0, 0, 1)
    scr = m.piece("Screen", "Label", material="SmoothPlastic", note="readiness screen; the game puts a SurfaceGui on its top face")
    scr.box((2.5, 1.25, 0.06), loc=mid + n * 0.04, rot=(ang, 0, 0), bevel=0.01)
    body.box((2.7, 1.45, 0.05), loc=mid + n * 0.005, rot=(ang, 0, 0), bevel=0.01)
    # the one accent: a slim lip along the front edge of the slope (where the hands rest)
    amber.box((2.9, 0.12, 0.1), loc=V(0, yf - 0.02, zf - 0.02), bevel=0.02)
    m.attach["Screen"] = tuple(mid + n * 0.08)
    m.attach["ScreenNormal"] = tuple(n)


# ------------------------------------------------------------------ UPGRADES tool counter

@register("Lobby7_ToolCounter", S, "Short equipment-service counter: charcoal steel frame with a wood front, steel worktop "
          "with a vice, a small pegboard backdrop (charcoal frame, wood board) holding a few generic tool silhouettes and a "
          "short sloped steel awning; one muted amber edge on the worktop. 6.4 x 2.6 footprint, counter 3.1 tall, backdrop "
          "top 6.6. Attach Sign = centre of the sign strip above the board, Screen = the small order screen on the worktop.")
def tool_counter(m):
    steel, dark, wood = m.slot("Charcoal"), m.slot("CharcoalLight"), m.slot("Wood")
    stone, amber, light = m.slot("SlateStoneDark"), m.slot("WarmAmber"), m.slot("SteelLight")
    W, D, H = 6.0, 1.7, 3.0
    y0 = -0.35  # counter centre (front is -Y)
    stone.box((W + 0.4, D + 0.4, 0.2), loc=(0, y0, 0.1), bevel=0.04)
    # frame legs + rails
    for sx in (-1, 1):
        for sy in (-1, 1):
            steel.box((0.22, 0.22, H - 0.4), loc=(sx * (W / 2 - 0.15), y0 + sy * (D / 2 - 0.15), 0.2 + (H - 0.4) / 2), bevel=0.03)
    steel.box((W, D, 0.14), loc=(0, y0, 0.55), bevel=0.03)
    # wood front panel (planks) and a lower shelf with a few boxes
    for i in range(5):
        x = -W / 2 + 0.35 + i * (W - 0.7) / 4
        wood.box(((W - 0.6) / 5 - 0.04, 0.1, H - 0.95), loc=(x * 0.98, y0 - D / 2 + 0.04, 0.62 + (H - 0.95) / 2), bevel=0.02)
    # worktop: steel plate on a wood bearer, the amber edge only on the front
    wood.box((W + 0.1, D + 0.1, 0.16), loc=(0, y0, H - 0.25), bevel=0.03)
    steel.box((W + 0.2, D + 0.2, 0.12), loc=(0, y0, H - 0.11), bevel=0.03)
    amber.box((W + 0.2, 0.08, 0.1), loc=(0, y0 - D / 2 - 0.12, H - 0.12), bevel=0.02)
    # bench vice on the left end
    vx = -W / 2 + 0.7
    dark.box((0.7, 0.6, 0.35), loc=(vx, y0 - 0.25, H + 0.15), bevel=0.04)
    dark.box((0.5, 0.18, 0.45), loc=(vx, y0 - 0.62, H + 0.2), bevel=0.03)
    light.cyl(0.05, 0.05, 0.9, seg=6, loc=(vx, y0 - 0.9, H + 0.2), rot=(0, 90, 0))
    # small order screen on a stem, right of centre (SurfaceGui on its face)
    sx_ = 2.15
    dark.box((0.16, 0.16, 0.3), loc=(sx_, y0 + 0.35, H + 0.15), bevel=0.02)
    steel.box((1.4, 0.12, 0.85), loc=(sx_, y0 + 0.3, H + 0.72), rot=(-12, 0, 0), bevel=0.03)
    scr = m.piece("Screen", "Label", material="SmoothPlastic", note="order screen; SurfaceGui on its front face")
    scr.box((1.2, 0.04, 0.68), loc=(sx_, y0 + 0.22, H + 0.73), rot=(-12, 0, 0), bevel=0.0)
    m.attach["Screen"] = (sx_, y0 + 0.19, H + 0.73)
    # pegboard backdrop behind the counter: framed board, a few generic tool silhouettes (not tied to the catalog)
    by = y0 + D / 2 + 0.35
    bw, bh, bz = 5.6, 2.4, H + 0.35 + 1.2
    for sx in (-1, 1):
        steel.box((0.24, 0.24, bz + bh / 2), loc=(sx * (bw / 2 + 0.12), by, (bz + bh / 2) / 2), bevel=0.03)
    wood.box((bw, 0.12, bh), loc=(0, by, bz), bevel=0.02)
    steel.box((bw + 0.48, 0.2, 0.18), loc=(0, by, bz - bh / 2 - 0.09), bevel=0.03)
    steel.box((bw + 0.48, 0.2, 0.18), loc=(0, by, bz + bh / 2 + 0.09), bevel=0.03)
    pegs = m.slot("SlateStoneDark")
    for ix in range(9):
        for iz in range(4):
            pegs.cyl(0.035, 0.035, 0.04, seg=6, loc=(-bw / 2 + 0.4 + ix * (bw - 0.8) / 8, by - 0.08, bz - bh / 2 + 0.35 + iz * (bh - 0.7) / 3), rot=(90, 0, 0))
    fy = by - 0.12
    # hammer
    dark.box((0.14, 0.08, 1.3), loc=(-1.9, fy, bz - 0.1), bevel=0.02)
    light.box((0.6, 0.14, 0.3), loc=(-1.9, fy, bz + 0.62), bevel=0.04)
    # wrench
    light.box((0.14, 0.08, 1.2), loc=(-0.9, fy, bz), rot=(0, 18, 0), bevel=0.02)
    light.cyl(0.22, 0.22, 0.08, seg=6, loc=(-0.72, fy, bz + 0.58), rot=(90, 0, 0))
    # chisel set: three bars of different length
    for i, ln in enumerate((1.0, 0.85, 0.7)):
        dark.box((0.1, 0.08, ln), loc=(0.15 + i * 0.3, fy, bz + 0.1 - (1.0 - ln) / 2), bevel=0.02)
    # tape coil + pick
    dark.cyl(0.3, 0.3, 0.12, seg=10, loc=(1.5, fy, bz + 0.45), rot=(90, 0, 0))
    light.box((1.0, 0.08, 0.14), loc=(2.0, fy, bz - 0.55), rot=(0, -20, 0), bevel=0.02)
    dark.box((0.1, 0.08, 1.0), loc=(2.1, fy, bz - 0.2), bevel=0.02)
    # short sloped awning over the board
    aw = bw + 0.9
    steel.box((aw, 1.1, 0.1), loc=(0, by - 0.42, bz + bh / 2 + 0.42), rot=(-14, 0, 0), bevel=0.02)
    for sx in (-1, 1):
        steel.box_between((sx * (bw / 2 + 0.12), by, bz + bh / 2 + 0.2), (sx * (bw / 2 + 0.12), by - 0.85, bz + bh / 2 + 0.3), 0.1, bevel=0.02)
    # sign strip on the awning front (SurfaceGui sits on the game's own sign board)
    m.attach["Sign"] = (0, by - 0.98, bz + bh / 2 + 0.95)
    m.attach["Backdrop"] = (0, by - 0.12, bz)


# ------------------------------------------------------------------ COLLECTION lectern

@register("Lobby7_InfoLectern", S, "Short Collection lectern: slate stone foot, tapered charcoal column, slanted wood reading "
          "top with a pale Screen piece (SurfaceGui) and a slim wood lip. 1.6 x 1.3 footprint, 3.2 tall. Attach Screen.")
def info_lectern(m):
    stone, stone2 = m.slot("SlateStone"), m.slot("SlateStoneDark")
    body, wood = m.slot("Charcoal"), m.slot("Wood")
    stone2.box((1.6, 1.3, 0.2), loc=(0, 0, 0.1), bevel=0.04)
    stone.box((1.3, 1.0, 0.25), loc=(0, 0, 0.32), bevel=0.04)
    body.box((0.75, 0.55, 2.25), loc=(0, 0.05, 0.45 + 1.12), taper=(0.85, 0.85), bevel=0.04)
    ang = 32
    top = V(0, 0.0, 2.85)
    wood.box((1.55, 1.05, 0.14), loc=top, rot=(ang, 0, 0), bevel=0.03)
    R = Euler((math.radians(ang), 0, 0), "XYZ").to_matrix()
    n = R @ V(0, 0, 1)
    scr = m.piece("Screen", "Label", material="SmoothPlastic", note="SurfaceGui on its top face")
    scr.box((1.25, 0.78, 0.04), loc=top + n * 0.08, rot=(ang, 0, 0), bevel=0.0)
    wood.box((1.55, 0.1, 0.12), loc=top + R @ V(0, -0.52, 0.12), rot=(ang, 0, 0), bevel=0.02)
    m.attach["Screen"] = tuple(top + n * 0.11)
    m.attach["ScreenNormal"] = tuple(n)


# ------------------------------------------------------------------ seller

@register("Lobby7_SellChute", S, "Compact rubble receiving bin: flared charcoal bin with a short wood front lip, sloped steel "
          "chute inside, slate service base with a small output tray, one small status Lamp piece on a short post and a "
          "pale Plaque piece on the front (SurfaceGui). Amber only on the bin rim front. 3.8 x 3.0 footprint, rim 3.2 high.")
def sell_chute(m):
    stone, stone2 = m.slot("SlateStone"), m.slot("SlateStoneDark")
    steel, steel2, wood, amber = m.slot("Charcoal"), m.slot("CharcoalLight"), m.slot("Wood"), m.slot("WarmAmber")
    # service base
    stone2.box((3.8, 3.0, 0.25), loc=(0, 0, 0.125), bevel=0.05)
    stone.box((3.2, 2.4, 1.6), loc=(0, 0.1, 0.25 + 0.8), bevel=0.08)
    # bin: flared walls (front lower), from z 1.85 to the rim
    z0, z1f, z1b = 1.85, 2.95, 3.35
    w0, w1 = 2.8, 3.5
    d0, d1 = 2.0, 2.6
    # side walls as prisms (y, z) along X
    for sx in (-1, 1):
        prof = [(-d0 / 2, z0), (d0 / 2, z0), (d1 / 2, z1b), (-d1 / 2, z1f)]
        side_prism(steel, prof, 0.16, x=sx * ((w0 + w1) / 4), bevel=0.03)
    # back wall
    steel.box((w1, 0.16, z1b - z0), loc=(0, (d0 + d1) / 4, (z0 + z1b) / 2), rot=(-14, 0, 0), bevel=0.03)
    # front wall (lower) with the wood lip and amber rim strip
    steel.box((w1, 0.16, z1f - z0), loc=(0, -(d0 + d1) / 4, (z0 + z1f) / 2), rot=(14, 0, 0), bevel=0.03)
    wood.box((w1 + 0.2, 0.32, 0.2), loc=(0, -d1 / 2 - 0.02, z1f + 0.05), bevel=0.04)
    amber.box((w1 + 0.1, 0.06, 0.08), loc=(0, -d1 / 2 - 0.2, z1f + 0.06), bevel=0.01)
    # bin floor: chute sloping to the output side (+X)
    steel2.box((w0 - 0.1, d0 - 0.1, 0.1), loc=(0, 0, z0 + 0.25), rot=(0, 8, 0), bevel=0.02)
    # output tray on the right side of the base
    steel.box((0.9, 1.4, 0.35), loc=(1.95, 0.0, 0.55), bevel=0.03)
    steel2.box((0.7, 1.2, 0.1), loc=(1.95, 0.0, 0.7), bevel=0.01)
    rng = random.Random(4)
    for i in range(4):
        pts = K.rock_points(rng.randrange(1 << 30), (0.32, 0.3, 0.22), n=10, flat_bottom=0.2)
        stone2.hull(pts, loc=(1.9 + rng.uniform(-0.2, 0.2), -0.4 + i * 0.27, 0.78))
    # status lamp: short post at the back left, a small warm lens
    px, py = -1.55, 1.15
    steel.box((0.18, 0.18, 1.6), loc=(px, py, 3.0 + 0.8), bevel=0.03)
    steel.box((0.36, 0.36, 0.12), loc=(px, py, 4.66), bevel=0.02)
    lamp = m.piece("Lamp", "WarmAmber", material="SmoothPlastic", note="status lamp lens (no neon: a modest PointLight goes here)")
    lamp.box((0.3, 0.3, 0.3), loc=(px, py, 4.87), bevel=0.04)
    steel.box((0.38, 0.38, 0.08), loc=(px, py, 5.06), bevel=0.02)
    m.attach["Lamp"] = (px, py, 4.87)
    # front plaque on the service base (SELL RUBBLE text goes on the game's sign; this is the price/plate face)
    plaque = m.piece("Plaque", "Label", material="SmoothPlastic", note="front plate; SurfaceGui on its front face")
    plaque.box((2.2, 0.05, 0.75), loc=(0, -1.12, 1.1), bevel=0.0)
    m.attach["Plaque"] = (0, -1.16, 1.1)
    m.attach["Deposit"] = (0, 0, 3.6)


# ------------------------------------------------------------------ planting pocket

@register("Lobby7_ShrubBed", S, "Low planting pocket: slate stone curb (4.4 x 2.4, 0.6 tall), soil, three faceted shrubs and "
          "two rosettes in the same faceted family as Court_Tree, subdued greens, no flowers. Origin floor centre.")
def shrub_bed(m):
    stone, stone2 = m.slot("SlateStone"), m.slot("SlateStoneDark")
    w, d, h = 4.4, 2.4, 0.6
    stone2.box((w, d, 0.16), loc=(0, 0, 0.08), bevel=0.04)
    wall = 0.3
    for sy in (-1, 1):
        stone.box((w, wall, h - 0.16), loc=(0, sy * (d / 2 - wall / 2), 0.16 + (h - 0.16) / 2), bevel=0.05)
    for sx in (-1, 1):
        stone.box((wall, d - 2 * wall, h - 0.16), loc=(sx * (w / 2 - wall / 2), 0, 0.16 + (h - 0.16) / 2), bevel=0.05)
    m.slot("Soil").box((w - 2 * wall, d - 2 * wall, 0.2), loc=(0, 0, h - 0.12), bevel=0.02)
    leaf, leaf2 = m.slot("Sage"), m.slot("SageDark")
    L.shrub(leaf, (-1.1, 0.1, h - 0.1), 1.35, seed=21, n=3, piece2=leaf2)
    L.shrub(leaf2, (0.35, -0.15, h - 0.1), 1.6, seed=33, n=4, piece2=leaf)
    L.shrub(leaf, (1.45, 0.25, h - 0.1), 1.1, seed=45, n=3, piece2=leaf2)
    L.rosette(leaf2, (-0.4, -0.55, h - 0.05), 0.45, seed=5, n=6)
    L.rosette(leaf, (1.0, -0.6, h - 0.05), 0.4, seed=9, n=6)
