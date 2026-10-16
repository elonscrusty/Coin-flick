"""Prospector Lodge furnishings, decor inventory (MASTER_PROMPT section 12, sheets AssetSheet_02/03/05).

P01 Lodge_Bench, P02 Lodge_Crate, P03 Lodge_Cashbox, P04 Lodge_RockBasket, P05 Lodge_Planter,
P06 Lodge_Plant, P07 Lodge_Lantern, P08 Lodge_WallLantern, P09 Lodge_Chandelier, P10 Lodge_EntryRug,
P11 Lodge_RunnerRug, P12 Lodge_PosterGeode, P13 Lodge_PosterMineral, P14 Lodge_SpecimenTray,
P15 Lodge_SpecimenPedestal, P16 Lodge_TrophyEmblem, P17 Lodge_HammerEmblem, plus the Collection display
geodes (Lodge_DisplayGeode_Violet / _Blue / _Amber) and removable crystal clusters (Lodge_CrystalCluster_*).

Origins: floor centre (bottom centre) except wall pieces (wall lantern, posters, hammer emblem): centre of
the back face, which sits on the wall / sign plane; their front faces -Y. Rugs are flat slabs (0.04) with
broad border bands; no woven geometry.
"""

import math
import random

from mathutils import Matrix, Vector

import ctrkit as K
from ctrkit import register
from models import _lodgeparts as P
from models import geodes as G
from models._lodgeparts import V, part, attach, collider
from models.gallery import ring_prism

S = "L"
R2 = "AssetSheet_02_Upgrades.png"
R3 = "AssetSheet_03_Collection.png"
R4 = "AssetSheet_04_Hunts_Leaderboards.png"
R5 = "AssetSheet_05_Decor.png"


# ------------------------------------------------------------------ P01 bench

@register("Lodge_Bench", S, "P01 simple wood bench 12 x 3 x 3: two thick seat planks (top z 3), square legs, end rails, low "
          "stretcher. Attach Seat1..3 (seat top).", ref=(R5, (0, 0, 452, 305)))
def bench(m):
    wood, dark = m.slot("FnWood"), m.slot("FnWoodDark")
    seat = part(m, "Seat", "FnWoodLight")
    for sy in (-1, 1):
        seat.box((12.0, 1.44, 0.5), loc=(0, sy * 0.76, 2.75), bevel=0.1)
    for sx in (-1, 1):
        x = sx * 4.6
        for sy in (-1, 1):
            wood.box((0.85, 0.85, 2.5), loc=(x, sy * 0.85, 1.25), bevel=0.08)
        dark.box((0.75, 2.7, 0.45), loc=(x, 0, 2.27), bevel=0.06)
        dark.box((0.55, 1.6, 0.4), loc=(x, 0, 0.75), bevel=0.05)
    dark.box((8.6, 0.5, 0.45), loc=(0, 0, 0.75), bevel=0.06)
    for i, x in enumerate((-3.5, 0.0, 3.5)):
        attach(m, "Seat%d" % (i + 1), (x, 0, 3.0))
    collider(m, (12.0, 3.0, 3.0), (0, 0, 1.5))


# ------------------------------------------------------------------ P02 crate

@register("Lodge_Crate", S, "P02 closed braced crate, 2.8 cube: plank body, dark edge battens, X brace on four sides, corner "
          "bolts. Attach Top.", ref=(R5, (455, 0, 835, 305)))
def crate(m):
    P.braced_crate(m, 2.8)
    attach(m, "Top", (0, 0, 2.8))
    collider(m, (2.8, 2.8, 2.8), (0, 0, 1.4))


# ------------------------------------------------------------------ P03 cashbox

@register("Lodge_Cashbox", S, "P03 small counter cashbox 2 x 1.2 x 1: plank box, slightly larger lid, dark battens, metal "
          "latch on the front and a low carry handle.", ref=(R2, (1400, 540, 1660, 728)))
def cashbox(m):
    wood, dark, metal = m.slot("FnWood"), m.slot("FnWoodDark"), m.slot("FnMetal")
    wood.box((1.9, 1.1, 0.62), loc=(0, 0, 0.31), bevel=0.05)
    part(m, "Lid", "FnWoodLight").box((2.0, 1.2, 0.22), loc=(0, 0, 0.74), bevel=0.05)
    for z in (0.1, 0.5):
        dark.box((1.96, 1.16, 0.1), loc=(0, 0, z), bevel=0.02)
    for sx in (-1, 1):
        dark.box((0.12, 1.16, 0.62), loc=(sx * 0.92, 0, 0.31), bevel=0.02)
    metal.box((0.3, 0.08, 0.36), loc=(0, -0.6, 0.6), bevel=0.02)
    metal.tube([(-0.32, 0, 0.85), (-0.32, 0, 1.0), (0.32, 0, 1.0), (0.32, 0, 0.85)], 0.05, seg=6)


# ------------------------------------------------------------------ P04 rock basket

@register("Lodge_RockBasket", S, "P04 slatted rock basket 3 x 2 x 1.8: corner posts with feet, open side slats, heap of grey "
          "faceted rocks (Rocks piece, can be hidden for an empty basket). Attach Top.", ref=(R5, (1255, 0, 1672, 305)))
def rock_basket(m):
    wood, dark = m.slot("FnWood"), m.slot("FnWoodDark")
    w, d, h = 3.0, 2.0, 1.3
    for sx in (-1, 1):
        for sy in (-1, 1):
            dark.box((0.28, 0.28, h), loc=(sx * (w / 2 - 0.14), sy * (d / 2 - 0.14), h / 2), bevel=0.04)
    wood.box((w - 0.3, d - 0.3, 0.14), loc=(0, 0, 0.3), bevel=0.03)
    for z in (0.45, 0.95):
        for sy in (-1, 1):
            wood.box((w - 0.2, 0.14, 0.3), loc=(0, sy * (d / 2 - 0.1), z), bevel=0.04)
        for sx in (-1, 1):
            wood.box((0.14, d - 0.4, 0.3), loc=(sx * (w / 2 - 0.1), 0, z), bevel=0.04)
    rocks, rocks2 = m.piece("Rocks", "FnRock"), m.piece("Rocks2", "FnRockDark")
    rng = random.Random(41)
    spots = [(-0.85, -0.35, 0.37), (0.0, -0.4, 0.37), (0.85, -0.3, 0.37), (-0.8, 0.4, 0.37), (0.15, 0.4, 0.37), (0.9, 0.4, 0.37),
             (-0.35, 0.0, 0.85), (0.5, 0.05, 0.85)]
    for i, (x, y, z) in enumerate(spots):
        s = rng.uniform(0.8, 1.0)
        P.faceted_rock(rocks if i % 3 else rocks2, (x, y, z), (s, s * 0.85, s * 0.8), rng.randrange(1 << 20), n=12)
    attach(m, "Top", (0, 0, 1.3))


# ------------------------------------------------------------------ P05 planter / P06 plant

def planter_shell(m, bot=1.75, top=2.2, h=2.4):
    """Tapered cream planter: one solid tapered body (narrow end down), a top rim band, soil inside the rim."""
    shell = m.slot("FnPlanter")
    body_h = h - 0.22
    shell.box((top - 0.1, top - 0.1, body_h), loc=(0, 0, body_h / 2), rot=(180, 0, 0), taper=(bot / top, bot / top), bevel=0.06)
    P.ring_rect(shell, top + 0.1, top + 0.1, 0.28, body_h - 0.02, 0.24)
    m.slot("FnSoil").box((top - 0.5, top - 0.5, 0.12), loc=(0, 0, body_h + 0.04), bevel=0.02)
    return body_h + 0.1


@register("Lodge_Planter", S, "P05 cream planter 2.2 x 2.2 x 2.4: tapered smooth walls, top rim band, soil. Attach Plant "
          "(soil top, where Lodge_Plant goes).", ref=(R5, (455, 305, 835, 610)))
def planter(m):
    top = planter_shell(m)
    attach(m, "Plant", (0, 0, top))
    collider(m, (2.2, 2.2, 2.4), (0, 0, 1.2))


def leaf(piece, base, ang, elev, length, width, droop=0.5, fold=0.06):
    """Broad pointed leaf: two flat faceted segments (rising, then drooping) with a raised mid-rib."""
    base = Vector(base)
    d = V(math.cos(ang), math.sin(ang), 0)
    side = V(-math.sin(ang), math.cos(ang), 0)
    e1, e2 = elev, elev - droop
    l1, l2 = length * 0.55, length * 0.45
    mid = base + d * math.cos(e1) * l1 + V(0, 0, math.sin(e1) * l1)
    tip = mid + d * math.cos(e2) * l2 + V(0, 0, math.sin(e2) * l2)
    w0, w1 = width * 0.25, width / 2
    piece.hull([base + side * w0, base - side * w0, mid + side * w1, mid - side * w1, base + V(0, 0, fold), mid + V(0, 0, fold)])
    piece.hull([mid + side * w1, mid - side * w1, tip, mid + V(0, 0, fold), tip + V(0, 0, fold * 0.5)])


def plant_into(m, at=(0, 0, 0), s=1.0, seed=7):
    """Bushy angular plant: short stems from one base, broad faceted pointed leaves arching out, a few
    upright centre leaves. About 3 x 3 x 4."""
    at = Vector(at)
    lf, lf2, stem = m.slot("FnLeaf"), m.slot("FnLeafDark"), m.slot("FnStem")
    rng = random.Random(seed)
    n = 9
    for i in range(n):
        ang = i / n * math.tau + rng.uniform(-0.2, 0.2)
        h = rng.uniform(0.35, 1.5) * s
        r = rng.uniform(0.05, 0.2) * s
        top = at + V(math.cos(ang) * r, math.sin(ang) * r, h)
        stem.box_between(at + V(0, 0, 0.02), top, 0.12 * s, bevel=0.0)
        elev = math.radians(rng.uniform(48, 64) if h > 0.9 * s else rng.uniform(30, 44))
        leaf(lf if i % 2 else lf2, top, ang, elev, rng.uniform(1.9, 2.3) * s, rng.uniform(1.0, 1.25) * s,
             droop=math.radians(rng.uniform(40, 60)))
    for i in range(3):   # upright centre leaves
        ang = i / 3 * math.tau + rng.uniform(-0.4, 0.4)
        top = at + V(0, 0, 1.7 * s)
        stem.box_between(at, top, 0.13 * s, bevel=0.0)
        leaf(lf2 if i % 2 else lf, top, ang, math.radians(80), 2.1 * s, 0.85 * s, droop=math.radians(30))


@register("Lodge_Plant", S, "P06 angular leaf plant insert, about 3 x 3 x 4: stems from one base, broad faceted pointed leaves "
          "in two greens. Origin = stem base; place on Lodge_Planter attach Plant.", ref=(R5, (0, 305, 452, 610)))
def plant(m):
    plant_into(m)


# ------------------------------------------------------------------ P07 / P08 lanterns

@register("Lodge_Lantern", S, "P07 portable lantern 0.9 x 0.9 x 1.6: dark metal frame, warm panes (FnPane, not glowing), small "
          "Neon diamond core on each face, pyramid roof, ring handle. Attach Light (PointLight, keep Range <= 12).",
          ref=(R5, (1255, 305, 1672, 610)))
def lantern(m):
    c = P.lantern(m, (0, 0, 0))
    attach(m, "Light", tuple(c))


@register("Lodge_WallLantern", S, "P08 wall lantern 1.2 x 1.5 x 2.2: wood back plate, dark bracket arm, hanging lantern. Origin = "
          "centre of the back plate's back face (on the wall); front -Y. Attach Light.", ref=(R5, (840, 305, 1252, 610)))
def wall_lantern(m):
    wood, metal = m.slot("FnWood"), m.slot("FnMetal")
    wood.box((0.8, 0.26, 2.2), loc=(0, -0.13, 0), bevel=0.06)
    for z in (-0.75, 0.75):
        metal.bolt((0, -0.26, z), normal=(0, -1, 0), r=0.08)
    metal.box((0.18, 1.3, 0.2), loc=(0, -0.85, 0.75), bevel=0.03)
    metal.box_between((0, -0.27, -0.2), (0, -0.95, 0.68), (0.14, 0.14), bevel=0.02)
    metal.box((0.12, 0.12, 0.2), loc=(0, -1.2, 0.58), bevel=0.02)
    c = P.lantern(m, (0, -1.2, -0.85), s=0.8)
    attach(m, "Light", tuple(c))


# ------------------------------------------------------------------ P09 chandelier

def chain(piece, a, b, link=0.42, t=0.07, w=0.2):
    a, b = Vector(a), Vector(b)
    n = max(2, int((b - a).length / link))
    for i in range(n):
        p0 = a + (b - a) * (i / n)
        p1 = a + (b - a) * ((i + 1.15) / n)
        piece.box_between(p0, p1, (w, t) if i % 2 else (t, w), bevel=0.0)


@register("Lodge_Chandelier", S, "P09 ring chandelier: wood ring (diameter 9.5) with six lanterns (diameter 10 overall, body 3 "
          "tall) and four simplified low-poly chains to a ceiling block 8 above the origin. Origin = bottom centre (lantern "
          "bottoms); placed at z 23 the chains reach z 31. Attach Light1..6, Ceiling. Non-colliding.",
          ref=(R5, (0, 610, 452, 941)))
def chandelier(m):
    ringp = part(m, "Ring", "FnWood")
    outer = [(math.cos(math.radians(15 * i)) * 4.75, math.sin(math.radians(15 * i)) * 4.75) for i in range(24)]
    inner = [(math.cos(math.radians(15 * i)) * 4.0, math.sin(math.radians(15 * i)) * 4.0) for i in range(24)]
    ring_prism(ringp, outer, inner, 0.7, loc=(0, 0, 2.55), rot=(90, 0, 0))
    metal = m.slot("FnMetal")
    outer2 = [(x * 1.005, y * 1.005) for x, y in outer]
    inner2 = [(x * 0.995 * 4.6 / 4.75, y * 0.995 * 4.6 / 4.75) for x, y in outer]
    ring_prism(metal, outer2, inner2, 0.16, loc=(0, 0, 2.2), rot=(90, 0, 0))   # dark band under the ring
    for k in range(6):
        a = math.radians(30 + 60 * k)
        p = V(math.cos(a) * 4.45, math.sin(a) * 4.45, 0)
        c = P.lantern(m, p, s=1.0)
        metal.box((0.12, 0.12, 0.62), loc=p + V(0, 0, 1.95), bevel=0.02)
        attach(m, "Light%d" % (k + 1), tuple(c))
    hub = part(m, "Ceiling", "FnWoodDark")
    hub.box((1.4, 1.4, 0.45), loc=(0, 0, 7.78), bevel=0.06)
    metal.box((0.7, 0.7, 0.25), loc=(0, 0, 7.45), bevel=0.04)
    ch = part(m, "Chains", "FnMetal")
    for k in range(4):
        a = math.radians(45 + 90 * k)
        chain(ch, (math.cos(a) * 4.35, math.sin(a) * 4.35, 2.9), (math.cos(a) * 0.25, math.sin(a) * 0.25, 7.35))
    attach(m, "Ceiling", (0, 0, 8.0))


# ------------------------------------------------------------------ P10 / P11 rugs

def rug(m, w, d, bands):
    """Flat 0.04 rug: concentric non-overlapping bands (red / gold), no woven geometry."""
    red, gold = part(m, "RugField", "FnRugRed"), part(m, "RugBorder", "FnRugGold")
    ow, od = w, d
    for i, b in enumerate(bands):
        P.ring_rect(gold if i % 2 else red, ow, od, b, 0.0, 0.04)
        ow, od = ow - 2 * b, od - 2 * b
    red.box((ow, od, 0.04), loc=(0, 0, 0.02), bevel=0.0)


@register("Lodge_EntryRug", S, "P10 entry rug 14 x 8 x 0.04: red field with two gold border bands (flat slab bands, Fabric). "
          "Non-colliding.", ref=(R5, (455, 610, 835, 941)))
def entry_rug(m):
    rug(m, 14.0, 8.0, (0.55, 0.22, 0.4, 0.14))


@register("Lodge_RunnerRug", S, "P11 upgrade runner 16 x 4 x 0.04 (same bands, narrower). Non-colliding.",
          ref=(R2, (1100, 540, 1390, 905)))
def runner_rug(m):
    rug(m, 16.0, 4.0, (0.4, 0.18, 0.3, 0.12))


# ------------------------------------------------------------------ P12 / P13 posters

def poster_frame(m):
    frame, paper = part(m, "Frame", "FnWood"), part(m, "Paper", "FnPaper")
    P.ring_rect(frame, 8.0, 4.0, 0.36, 0, 0.25, loc=(0, 0, 0))   # built lying flat, turned upright below
    paper.box((7.3, 3.3, 0.1), loc=(0, 0, 0.06), bevel=0.0)
    return frame, paper


def upright(m, names):
    """Turn pieces built lying flat (z = depth from the wall, x/y = picture plane) upright: back face on
    y = 0, front -Y, picture centre at the origin."""
    r = Matrix.Rotation(math.radians(90), 4, "X")   # (x, y, z) -> (x, -z, y)
    for p in m.pieces:
        if p.name in names:
            p.bm.transform(r)


def oval(cx, cy, rx, ry, n=12, jitter=0.0, seed=1):
    rng = random.Random(seed)
    return [(cx + math.cos(math.tau * i / n) * rx * (1 + rng.uniform(-jitter, jitter)),
             cy + math.sin(math.tau * i / n) * ry * (1 + rng.uniform(-jitter, jitter))) for i in range(n)]


def relief(piece, outline, z0, h, ridge=None):
    """Low relief on the paper (flat build: z = height above the paper). ridge = extra raised points."""
    pts = [V(x, y, z0) for x, y in outline] + [V(x, y, z0 + h * 0.4) for x, y in outline]
    for x, y in (ridge or []):
        pts.append(V(x, y, z0 + h))
    piece.hull(pts)


def ink_lines(piece, x0, y0, rows, length, z0):
    for i in range(rows):
        piece.box((length * (0.6 + 0.4 * ((i * 7) % 3) / 2), 0.07, 0.02), loc=(x0, y0 - i * 0.22, z0 + 0.01), bevel=0.0)


@register("Lodge_PosterGeode", S, "P12 framed geode poster 8 x 0.25 x 4: wood frame, paper, low-relief geode slice, grey and "
          "brown rocks, a few ink marks. Origin = back face centre (wall plane); front -Y.", ref=(R5, (840, 610, 1252, 941)))
def poster_geode(m):
    poster_frame(m)
    rock, dark, brown, ink = part(m, "ArtRock", "FnRock"), part(m, "ArtRockDark", "FnRockDark"), part(m, "ArtBrown", "FnBronze"), part(m, "Ink", "FnInk")
    zp = 0.11
    relief(rock, oval(-2.2, -0.1, 1.05, 1.3, 11, 0.08, 3), zp, 0.12)
    relief(dark, oval(-2.2, -0.15, 0.62, 0.85, 10, 0.12, 5), zp + 0.05, 0.12)
    relief(part(m, "ArtRim", "FnRim"), oval(-2.2, -0.15, 0.38, 0.55, 9, 0.1, 6), zp + 0.1, 0.08)
    relief(rock, [(-0.2, -1.2), (0.75, -1.1), (1.0, 0.0), (0.45, 1.0), (-0.35, 0.4)], zp, 0.2, ridge=[(0.35, -0.1)])
    relief(dark, [(0.05, -0.85), (0.6, -0.75), (0.7, 0.0), (0.4, 0.55), (0.0, 0.2)], zp + 0.08, 0.14, ridge=[(0.38, -0.1)])
    relief(brown, [(1.75, -1.2), (2.85, -1.1), (3.1, -0.1), (2.55, 1.0), (1.85, 0.3)], zp, 0.22, ridge=[(2.45, -0.15), (2.2, 0.25)])
    ink_lines(ink, -3.0, 1.4, 2, 0.8, zp)
    ink_lines(ink, 2.6, -1.35, 2, 0.6, zp)
    relief(part(m, "ArtAmber", "FnRugGold"), [(2.8, 1.05), (3.2, 1.05), (3.0, 1.45)], zp, 0.05)
    upright(m, {"Frame", "Paper", "ArtRock", "ArtRockDark", "ArtBrown", "Ink", "ArtRim", "ArtAmber"})
    attach(m, "Face", (0, -0.25, 0))


@register("Lodge_PosterMineral", S, "P13 framed mineral poster 8 x 0.25 x 4: wood frame, paper, three faceted crystals in low "
          "relief (violet, blue, amber). Origin = back face centre; front -Y.", ref=(R5, (1255, 610, 1672, 941)))
def poster_mineral(m):
    poster_frame(m)
    zp = 0.11
    for x, slot, h in ((-2.4, "CrystalViolet", 1.4), (0.0, "CrystalBlue", 1.45), (2.4, "CrystalAmber", 1.35)):
        g = part(m, "Art" + slot, slot)
        outline = [(x, -h), (x + 0.6, -0.55), (x + 0.65, 0.45), (x, h), (x - 0.65, 0.45), (x - 0.6, -0.55)]
        relief(g, outline, zp, 0.3, ridge=[(x - 0.12, 0.35), (x + 0.15, -0.3)])
    ink_lines(part(m, "Ink", "FnInk"), -3.0, 1.45, 2, 0.7, zp)
    ink_lines(part(m, "Ink", "FnInk"), 3.0, -1.3, 2, 0.6, zp)
    upright(m, {"Frame", "Paper", "ArtCrystalViolet", "ArtCrystalBlue", "ArtCrystalAmber", "Ink"})
    attach(m, "Face", (0, -0.25, 0))


# ------------------------------------------------------------------ P14 tray / P15 pedestal

@register("Lodge_SpecimenTray", S, "P14 empty wood display tray 2.5 x 1.8 x 0.25. Attach Specimen (tray floor).",
          ref=(R3, (950, 465, 1265, 690)))
def specimen_tray(m):
    wood, light = m.slot("FnWood"), part(m, "Floor", "FnWoodLight")
    light.box((2.3, 1.6, 0.08), loc=(0, 0, 0.04), bevel=0.02)
    P.ring_rect(wood, 2.5, 1.8, 0.16, 0.0, 0.25)
    attach(m, "Specimen", (0, 0, 0.08))


@register("Lodge_SpecimenPedestal", S, "P15 compact specimen pedestal 2.7 x 2.7 x 1.2: plinth, body, overhanging top. Attach "
          "Specimen (top centre).", ref=(R3, (570, 465, 940, 690)))
def specimen_pedestal(m):
    wood, dark = m.slot("FnWood"), m.slot("FnWoodDark")
    dark.box((2.4, 2.4, 0.22), loc=(0, 0, 0.11), bevel=0.05)
    wood.box((2.0, 2.0, 0.72), loc=(0, 0, 0.58), bevel=0.06)
    part(m, "Top", "FnWoodLight").box((2.7, 2.7, 0.28), loc=(0, 0, 1.06), bevel=0.07)
    attach(m, "Specimen", (0, 0, 1.2))


# ------------------------------------------------------------------ P16 trophy / P17 crossed hammers

@register("Lodge_TrophyEmblem", S, "P16 trophy emblem 1.8 x 1 x 1.9: gold faceted cup with two handles on a stem, dark wood "
          "plinth. Origin bottom centre (leaderboard attach Trophy).", ref=(R4, (500, 640, 790, 870)))
def trophy(m):
    gold, dark = part(m, "Trophy", "FnGold"), m.slot("FnWoodDark")
    dark.box((1.0, 0.8, 0.32), loc=(0, 0, 0.16), bevel=0.05)
    gold.box((0.7, 0.55, 0.14), loc=(0, 0, 0.39), bevel=0.03)
    gold.cyl(0.13, 0.16, 0.45, seg=8, loc=(0, 0, 0.68))
    pts = []
    for z, r in ((0.88, 0.18), (1.05, 0.46), (1.45, 0.58), (1.86, 0.6)):
        for i in range(8):
            a = math.radians(22.5 + 45 * i)
            pts.append(V(math.cos(a) * r, math.sin(a) * r * 0.75, z))
    gold.hull(pts)
    for sx in (-1, 1):
        gold.tube([(sx * 0.5, 0, 1.68), (sx * 0.86, 0, 1.62), (sx * 0.8, 0, 1.2), (sx * 0.45, 0, 1.12)], 0.08, seg=6)


@register("Lodge_HammerEmblem", S, "P17 crossed-hammer emblem 3 x 0.5 x 3: two gold hammers crossed at 45 degrees over a dark "
          "outline backing. Origin = back face centre; front -Y (hunt sign attach Emblem).", ref=(R4, (840, 650, 1100, 880)))
def hammer_emblem(m):
    gold, dark = part(m, "Emblem", "FnGold"), part(m, "EmblemBack", "FnWoodDark")
    for sx in (-1, 1):
        a = math.radians(45 * sx)
        d = V(math.sin(a), 0, -math.cos(a))          # handle direction from the head (down-out)
        side = V(math.cos(a), 0, math.sin(a))
        head_c = -d * 1.15
        for piece, grow, y0, y1 in ((dark, 0.14, 0.0, -0.22), (gold, 0.0, -0.22, -0.5)):
            yc, t = (y0 + y1) / 2, abs(y1 - y0)
            piece.box_between(head_c + V(0, yc, 0), head_c + d * 2.45 + V(0, yc, 0), (0.34 + grow * 2, t), bevel=0.03)
            hw, hh = 0.78 + grow, 0.23 + grow
            pts = []
            for k in (-1, 1):
                for q in (-1, 1):
                    for yy in (y0, y1):
                        pts.append(head_c + side * k * hw * (1.0 if k > 0 else 0.8) + d * q * hh + V(0, yy, 0))
            piece.hull(pts)
    attach(m, "Face", (0, -0.5, 0))


# ------------------------------------------------------------------ display geodes + crystal clusters

GEODE_SCALE = (1.42, 1.12, 1.12)


def display_geode(m, color):
    cry, lin = P.CRYSTALS[color]
    sh = G._set_shape("C")
    T = Matrix.Diagonal((*GEODE_SCALE, 1.0))
    tmp = {k: K.Piece(k, "x") for k in ("shell", "lining", "shade", "druse", "rim", "c1", "c2", "c3")}
    G.shell_into(tmp["shell"], tmp["lining"], tmp["shade"], tmp["druse"], sh["seed"])
    G.rim_into(tmp["rim"], sh["seed"])
    G.cluster_into([tmp["c1"], tmp["c2"], tmp["c3"]], "A")
    m.piece("Shell", "FnGeodeShell").add_bm(tmp["shell"].bm, T)
    m.piece("Lining", lin, note="cavity wall").add_bm(tmp["lining"].bm, T)
    m.piece("Shade", "FnShade").add_bm(tmp["shade"].bm, T)
    m.piece("Druse", cry, note="wall points").add_bm(tmp["druse"].bm, T)
    m.piece("Rim", "FnRim").add_bm(tmp["rim"].bm, T)
    cm = T @ Matrix.Translation(G.CLUSTER_AT) @ Matrix.Scale(1.05, 4)
    for i, k in enumerate(("c1", "c2", "c3")):
        m.piece("Crystal%d" % (i + 1), cry).add_bm(tmp[k].bm, cm)
    G._set_shape("A")
    m.extra["origin"] = "bottom centre of the flat underside; opening faces -Y"


for _c in ("Violet", "Blue", "Amber"):
    register("Lodge_DisplayGeode_" + _c, S, "Collection display geode (%s), about 3.1 x 2.4 x 3.3: hollow neutral grey shell, "
             "pale inner rim, dark cavity lining, druzy points and a cathedral crystal cluster (Crystal1..3) inside the "
             "cavity. Decorative preview only; not a collectible." % _c.lower(),
             ref=(R3, {"Violet": (0, 700, 430, 941), "Blue": (430, 700, 850, 941), "Amber": (850, 700, 1265, 941)}[_c]))(
        (lambda c: (lambda m: display_geode(m, c)))(_c))


CLUSTER_SPEC = [(0.0, 0.05, 1.15, 0.2, 0), (-0.3, 0.1, 0.85, 0.17, -16), (0.32, 0.05, 0.9, 0.17, 14),
                (-0.55, -0.1, 0.55, 0.14, -30), (0.58, -0.08, 0.6, 0.14, 28), (0.12, -0.32, 0.5, 0.13, 6), (-0.2, -0.3, 0.42, 0.12, -8)]


def crystal_cluster(m, color):
    cry, _ = P.CRYSTALS[color]
    base = m.piece("Base", "FnRock")
    base.hull(K.rock_points(19, (1.6, 1.15, 0.42), n=16, flat_bottom=0.1))
    rng = random.Random(5)
    pieces = [m.piece("Crystal%d" % (i + 1), cry) for i in range(2)]
    for i, (x, y, h, r, lean) in enumerate(CLUSTER_SPEC):
        a = math.radians(lean)
        d = Vector((math.sin(a), -0.12, math.cos(a)))
        pieces[i % 2].add_bm(G.crystal_bm((x, y, 0.2), d, r, h, tip=rng.uniform(1.5, 1.9), spin=rng.uniform(0, 1)))
    m.extra["origin"] = "base centre"


for _c in ("Violet", "Blue", "Amber"):
    register("Lodge_CrystalCluster_" + _c, S, "Removable small crystal cluster (%s) on a grey rock base, about 1.7 x 1.2 x 1.35; "
             "sits on a Lodge_SpecimenTray." % _c.lower(), ref=(R3, (1275, 500, 1672, 690)))(
        (lambda c: (lambda m: crystal_cluster(m, c)))(_c))
