"""Sheet 04: Geode gallery kit.

Floor furniture has its origin at the floor centre with the front facing -Y (Roblox -Z). Wall-mounted
pieces (Gallery_WallNiche, Gallery_OwnerNameplate, Gallery_IndexBoard, Gallery_WallLamp) have y = 0 on
the wall plane and stick out toward -Y; their origin is noted per model. Specimen places are attach
points Slot1..N (where the bottom of a scaled Geode_Shell or a Geode_Stand goes) with Label1..N on the
small label plates; the specimens drawn in the previews are preview-only (the game places the owner's
real specimens, built from the sheet-12 geode kit).
"""

import math

import bmesh
from mathutils import Vector

import ctrkit as K
from ctrkit import register

from models.geodes import SAFE_SEEDS, specimen_into

S04 = "04"
REF = "04_gallery_kit.png"
MINERALS = ("Amethyst", "SkyBlue", "Citrine", "Emerald", "DeepRed", "Amethyst", "Quartz", "Smoky", "RoseQuartz")
CLUSTERS = "ABCDEAEBD"


# ------------------------------------------------------------------ helpers

def ring_prism(piece, outer, inner, depth, loc=(0, 0, 0), rot=(0, 0, 0)):
    """Frame between two outlines (x, z) with the same vertex count, `depth` thick along Y."""
    bm = bmesh.new()
    n = len(outer)
    of = [bm.verts.new((x, -depth / 2, z)) for x, z in outer]
    ob = [bm.verts.new((x, depth / 2, z)) for x, z in outer]
    inf = [bm.verts.new((x, -depth / 2, z)) for x, z in inner]
    inb = [bm.verts.new((x, depth / 2, z)) for x, z in inner]
    for k in range(n):
        k1 = (k + 1) % n
        bm.faces.new((of[k], of[k1], inf[k1], inf[k]))
        bm.faces.new((ob[k], inb[k], inb[k1], ob[k1]))
        bm.faces.new((of[k], ob[k], ob[k1], of[k1]))
        bm.faces.new((inf[k], inf[k1], inb[k1], inb[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return piece.add_bm(bm, K.mat(loc, rot))


def rect(w, h, cx=0.0, cz=0.0):
    return [(cx - w / 2, cz - h / 2), (cx + w / 2, cz - h / 2), (cx + w / 2, cz + h / 2), (cx - w / 2, cz + h / 2)]


def octo(piece, w, ch, z0, h, loc=(0, 0, 0), d=None):
    """Chamfered square block (w x d, corners cut by ch) from z0 up h."""
    d = d or w
    o = Vector(loc)
    pts = []
    for z in (z0, z0 + h):
        for x, y in ((w / 2 - ch, d / 2), (w / 2, d / 2 - ch), (w / 2, -d / 2 + ch), (w / 2 - ch, -d / 2),
                     (-w / 2 + ch, -d / 2), (-w / 2, -d / 2 + ch), (-w / 2, d / 2 - ch), (-w / 2 + ch, d / 2)):
            pts.append(o + Vector((x, y, z)))
    return piece.hull(pts)


def octo_ring(piece, w, ch, z0, h, t, loc=(0, 0, 0)):
    """Thin chamfered-square band (outer w, wall t) lying flat, from z0 up h."""
    def outline(w2, c2):
        return [(w2 / 2 - c2, w2 / 2), (w2 / 2, w2 / 2 - c2), (w2 / 2, -w2 / 2 + c2), (w2 / 2 - c2, -w2 / 2),
                (-w2 / 2 + c2, -w2 / 2), (-w2 / 2, -w2 / 2 + c2), (-w2 / 2, w2 / 2 - c2), (-w2 / 2 + c2, w2 / 2)]
    o = Vector(loc)
    # ring_prism works in XZ with depth along Y: build upright then lay it flat (rot X 90)
    ring_prism(piece, outline(w, ch), outline(w - 2 * t, ch * (w - 2 * t) / w), h, loc=o + Vector((0, 0, z0 + h / 2)), rot=(90, 0, 0))


def glass(m, note):
    """Transparent glass piece. Exported and painted in game, but left out of the preview renders: the
    offline renderer draws thin transparent panes as frosted noise that hides the specimens."""
    g = m.piece("Glass", "GlassClear", transparency=0.72, note=note)
    g.render_hide = True
    return g


def diamond(piece, size, loc, depth=0.08):
    s = size / 2
    piece.prism([(0, -s), (s * 0.8, 0), (0, s), (-s * 0.8, 0)], depth, loc=loc, bevel=0.015)


def plinth_label(m, at, k, base=(1.1, 0.8, 0.3), preview=None):
    """Small dark specimen plinth with a cream label plate on its front; records SlotK and LabelK."""
    at = Vector(at)
    w, d, h = base
    m.slot("FrameDark").box((w, d, h), loc=at + Vector((0, 0, h / 2)), bevel=0.05)
    m.slot("Cream", "SmoothPlastic").box((w * 0.6, 0.05, h * 0.55), loc=at + Vector((0, -d / 2 - 0.02, h / 2)), bevel=0.012)
    m.attach["Slot%d" % k] = tuple(at + Vector((0, 0.05, h)))
    m.attach["Label%d" % k] = tuple(at + Vector((0, -d / 2 - 0.05, h / 2)))


def dress(m, scale, keys, stand=False, minerals=None):
    """Preview-only specimens on Slot attach points."""
    get = lambda name, slot: m.preview_piece(name, slot)  # noqa: E731
    for i, k in enumerate(keys):
        p = m.attach["Slot%d" % k]
        mineral = minerals[i] if minerals else MINERALS[(k - 1) % 9]
        specimen_into(get, at=p, scale=scale, mineral=mineral, cluster=CLUSTERS[(k - 1) % 9],
                      stand=stand, seed=SAFE_SEEDS[k % len(SAFE_SEEDS)])


# ------------------------------------------------------------------ 1. glass specimen cabinet

def cabinet(m):
    W, D, H = 7.0, 2.6, 8.6
    dark, wood, wdark, amber, lamp = m.slot("FrameDark"), m.slot("Wood"), m.slot("WoodDark"), m.slot("Amber", "Metal"), m.slot("Lamp")
    PL = 1.1
    # plinth: dark body, wood front panels, amber diamond, amber trim
    dark.box((W, D, PL), loc=(0, 0, PL / 2), bevel=K.BEVEL_BIG)
    for sx in (-1, 1):
        wood.box((W / 2 - 1.0, 0.1, 0.6), loc=(sx * (W / 4 + 0.15), -D / 2 - 0.02, 0.5), bevel=0.03)
    diamond(amber, 0.62, (0, -D / 2 - 0.05, 0.55))
    amber.box((W - 0.2, 0.08, 0.1), loc=(0, -D / 2 - 0.01, PL - 0.08), bevel=0.02)
    # corner posts and crown
    top = H - 0.85
    for sx in (-1, 1):
        for sy in (-1, 1):
            dark.box((0.36, 0.36, top - PL), loc=(sx * (W / 2 - 0.2), sy * (D / 2 - 0.2), (top + PL) / 2))
    wood.box((W - 0.1, D - 0.1, 0.5), loc=(0, 0, top + 0.25), bevel=0.05)
    dark.box((W + 0.3, D + 0.3, 0.35), loc=(0, 0, H - 0.17), bevel=0.08, taper=(0.96, 0.92))
    for sx in (-1, 1):
        dark.box((0.6, D + 0.4, 0.6), loc=(sx * (W / 2 - 0.05), 0, top + 0.3), bevel=0.06)
    # back panel with column dividers
    wdark.box((W - 0.5, 0.14, top - PL), loc=(0, D / 2 - 0.22, (top + PL) / 2), bevel=0.02)
    for x in (-W / 6 + 0.05, W / 6 - 0.05):
        wood.box((0.12, 0.1, top - PL - 0.2), loc=(x, D / 2 - 0.32, (top + PL) / 2), bevel=0.02)
    # deck + two shelves with glowing front edges
    tiers = [PL + 0.1, PL + 2.25, PL + 4.4]
    for z in tiers:
        wood.box((W - 0.42, D - 0.5, 0.18), loc=(0, 0.05, z), bevel=0.04)
        lamp.box((W - 0.6, 0.05, 0.06), loc=(0, -D / 2 + 0.29, z - 0.04), bevel=0.0)
    # downlights under the crown
    for x in (-W / 3 + 0.1, 0, W / 3 - 0.1):
        dark.cyl(0.32, 0.32, 0.08, seg=10, loc=(x, 0, top - 0.04))
        lamp.cyl(0.24, 0.24, 0.06, seg=10, loc=(x, 0, top - 0.1))
    # glass: front + sides (one transparent piece)
    gl = glass(m, "cabinet glass (transparent)")
    gl.box((W - 0.4, 0.06, top - PL), loc=(0, -D / 2 + 0.2, (top + PL) / 2), bevel=0.0)
    for sx in (-1, 1):
        gl.box((0.06, D - 0.4, top - PL), loc=(sx * (W / 2 - 0.2), 0, (top + PL) / 2), bevel=0.0)
    # 3 x 3 specimen places, numbered left to right (viewer's left = -X), top row first
    k = 1
    for z in reversed(tiers):
        for x in (-W / 3 + 0.1, 0, W / 3 - 0.1):
            plinth_label(m, (x, -0.05, z + 0.09), k)
            k += 1
    m.attach["Light"] = (0, 0, top - 0.2)


@register("Gallery_Cabinet", S04, "Glass specimen cabinet: dark plinth + crown, wood shelves with glowing edges, 3 downlights, clear Glass piece, 9 specimen plinths (Slot1..9 / Label1..9, top row first).",
          ref=(REF, (20, 60, 840, 510)))
def gallery_cabinet(m):
    cabinet(m)
    dress(m, 0.55, range(1, 10))


# ------------------------------------------------------------------ 2. wall display niche

def niche_outline(w, h, ch, bottom=0.0):
    return [(-w / 2, bottom), (w / 2, bottom), (w / 2, h - ch), (w / 2 - ch, h), (-w / 2 + ch, h), (-w / 2, h - ch)]


@register("Gallery_WallNiche", S04, "Wall display niche: chamfered dark frame, amber inner trim, wood-lined recess, downlight, plinth + label (Slot1 / Label1). Origin = bottom centre on the wall plane (y 0), sticks out to -Y.",
          ref=(REF, (855, 85, 1080, 450)))
def gallery_niche(m):
    W, H, D = 3.6, 6.2, 1.3
    dark, wood, amber, lamp = m.slot("FrameDark"), m.slot("Wood"), m.slot("Amber", "Metal"), m.slot("Lamp")
    outer = niche_outline(W, H, 1.0)
    inner = [(-1.25, 1.1), (1.25, 1.1), (1.25, H - 1.3), (0.55, H - 0.5), (-0.55, H - 0.5), (-1.25, H - 1.3)]
    ring_prism(dark, outer, inner, D, loc=(0, -D / 2, 0))
    # wood back wall + lining just inside the frame opening
    wood.prism(inner, 0.12, loc=(0, -0.12, 0))
    lin = [(x * 0.97, z + (0.03 if z < 2 else -0.03)) for x, z in inner]
    ring_prism(wood, inner, lin, D - 0.3, loc=(0, -D / 2 - 0.05, 0))
    # amber trim around the opening, on the frame front
    trim_o = [(x * 1.08, z + (-0.1 if z < 2 else 0.09)) for x, z in inner]
    ring_prism(amber, trim_o, inner, 0.06, loc=(0, -D - 0.02, 0))
    dark.box((W + 0.1, D + 0.25, 0.95), loc=(0, -(D + 0.25) / 2, 0.475), bevel=K.BEVEL_BIG)   # thick sill
    # sill bracket (amber chevron bar) on the sill front
    amber.box((1.7, 0.06, 0.14), loc=(0, -D - 0.27, 0.62), bevel=0.02)
    for sx in (-1, 1):
        amber.box_between((sx * 0.85, -D - 0.27, 0.62), (sx * 1.15, -D - 0.27, 0.3), (0.14, 0.06), bevel=0.02)
    # downlight
    dark.cyl(0.42, 0.42, 0.1, seg=10, loc=(0, -D / 2 - 0.1, H - 0.58))
    lamp.cyl(0.34, 0.34, 0.06, seg=10, loc=(0, -D / 2 - 0.1, H - 0.65))
    m.attach["Light"] = (0, -D / 2 - 0.1, H - 0.8)
    plinth_label(m, (0, -0.62, 1.1), 1, base=(1.3, 0.8, 0.4))
    dress(m, 0.66, [1])


# ------------------------------------------------------------------ 3/4. pedestals

def pedestal(m, empty=False):
    dark, wood, amber, conc = m.slot("FrameDark"), m.slot("Wood"), m.slot("Amber", "Metal"), m.slot("Concrete")
    octo(dark, 2.9, 0.7, 0, 0.55)
    octo(dark, 2.6, 0.6, 0.55, 0.12)
    octo(dark, 2.0, 0.42, 0.67, 1.85)
    for k in range(4):   # concrete inset panels on the four faces
        a = math.radians(90 * k)
        n = Vector((math.sin(a), -math.cos(a), 0))
        conc.box((1.15, 0.08, 1.35), loc=n * 1.0 + Vector((0, 0, 1.58)), rot=(0, 0, 90 * k), bevel=0.02)
    octo(dark, 2.3, 0.5, 2.52, 0.14)
    octo(wood, 2.7, 0.62, 2.66, 0.5)
    octo_ring(amber, 2.82, 0.66, 3.12, 0.14, 0.18)
    if empty:
        octo(dark, 2.62, 0.6, 3.12, 0.06)
        octo(conc, 2.1, 0.48, 3.18, 0.02)
        glow = m.piece("SlotGlow", "Lamp", note="empty-slot highlight ring; show while the owner is placing a specimen")
        octo_ring(glow, 2.3, 0.53, 3.18, 0.04, 0.08)
        m.attach["Slot1"] = (0, 0, 3.2)
    else:
        octo(dark, 2.45, 0.56, 3.12, 0.12)
        plinth_label(m, (0, 0, 3.24), 1, base=(1.5, 1.1, 0.25))


@register("Gallery_Pedestal", S04, "Individual pedestal: octagonal dark base and column with concrete insets, wood + amber top. Specimen at Slot1.",
          ref=(REF, (1110, 95, 1300, 460)))
def gallery_pedestal(m):
    pedestal(m)
    get = lambda name, slot: m.preview_piece(name, slot)  # noqa: E731
    specimen_into(get, at=m.attach["Slot1"], scale=0.82, mineral="SkyBlue", cluster="A", stand=False, seed=27)


@register("Gallery_PedestalEmpty", S04, "Empty-slot pedestal: same body, recessed concrete top with a SlotGlow ring piece (toggle for placement). Specimen goes at Slot1.",
          ref=(REF, (1325, 210, 1515, 460)))
def gallery_pedestal_empty(m):
    pedestal(m, empty=True)


# ------------------------------------------------------------------ 5. countertop showcase

@register("Gallery_Showcase", S04, "Countertop showcase: dark counter base, glass case with brass corner posts and a wood lid, wood back with dividers, downlights, 3 specimen plinths (Slot1..3 / Label1..3).",
          ref=(REF, (15, 545, 345, 750)))
def gallery_showcase(m):
    W, D, B, G = 6.0, 2.3, 1.1, 2.1
    dark, wood, wdark, brass, lamp = m.slot("FrameDark"), m.slot("Wood"), m.slot("WoodDark"), m.slot("Brass"), m.slot("Lamp")
    dark.box((W + 0.2, D + 0.2, B), loc=(0, 0, B / 2), bevel=K.BEVEL_BIG)
    brass.box((W, D, 0.12), loc=(0, 0, B + 0.06), bevel=0.03)
    wood.box((W - 0.25, D - 0.25, 0.1), loc=(0, 0, B + 0.15), bevel=0.02)
    lamp.box((W - 0.4, 0.05, 0.05), loc=(0, -D / 2 + 0.16, B + 0.2), bevel=0.0)
    wdark.box((W - 0.3, 0.12, G - 0.2), loc=(0, D / 2 - 0.16, B + 0.1 + G / 2), bevel=0.02)
    for x in (-W / 6, W / 6):
        wood.box((0.1, 0.08, G - 0.3), loc=(x, D / 2 - 0.24, B + 0.1 + G / 2), bevel=0.01)
    zt = B + 0.1 + G
    for sx in (-1, 1):
        for sy in (-1, 1):
            brass.box((0.16, 0.16, G), loc=(sx * (W / 2 - 0.1), sy * (D / 2 - 0.1), B + 0.1 + G / 2), bevel=0.03)
    # wood lid with chamfered top edge and a brass band
    ring_prism(brass, rect(W + 0.1, D + 0.1), rect(W - 0.3, D - 0.3), 0.16, loc=(0, 0, zt + 0.06), rot=(90, 0, 0))
    wood.box((W - 0.2, D - 0.2, 0.08), loc=(0, 0, zt + 0.1), bevel=0.02)
    for x in (-W / 3, 0, W / 3):
        lamp.cyl(0.24, 0.24, 0.05, seg=10, loc=(x, 0, zt - 0.03))
    gl = glass(m, "showcase glass (transparent)")
    gl.box((W - 0.3, 0.05, G - 0.05), loc=(0, -D / 2 + 0.1, B + 0.1 + G / 2), bevel=0.0)
    for sx in (-1, 1):
        gl.box((0.05, D - 0.3, G - 0.05), loc=(sx * (W / 2 - 0.1), 0, B + 0.1 + G / 2), bevel=0.0)
    for k, x in enumerate((-W / 3, 0, W / 3), start=1):
        plinth_label(m, (x, -0.05, B + 0.2), k, base=(1.1, 0.8, 0.3))
    m.attach["Light"] = (0, 0, zt - 0.2)
    dress(m, 0.55, (1, 2, 3), minerals=("SkyBlue", "Citrine", "DeepRed"))


# ------------------------------------------------------------------ 6. three-tier shelf

@register("Gallery_Shelf", S04, "Three-tier open specimen shelf: tall dark side posts with amber inner strips, wood back with dividers, overhanging wood boards with amber ends, 9 plinths (Slot1..9 / Label1..9, top row first).",
          ref=(REF, (350, 505, 665, 750)))
def gallery_shelf(m):
    W, D, H = 6.4, 1.7, 6.6
    dark, wood, wdark, amber = m.slot("FrameDark"), m.slot("Wood"), m.slot("WoodDark"), m.slot("Amber", "Metal")
    for sx in (-1, 1):
        dark.box((0.5, D - 0.1, H), loc=(sx * (W / 2 - 0.25), 0.05, H / 2), bevel=K.BEVEL_BIG, taper=(0.9, 0.95))
        amber.box((0.1, 0.1, H - 0.7), loc=(sx * (W / 2 - 0.6), -D / 2 + 0.25, H / 2 + 0.2), bevel=0.02)
    wood.box((W + 0.5, D + 0.15, 0.55), loc=(0, 0, 0.27), bevel=0.07)
    wdark.box((W - 0.9, 0.14, H - 0.6), loc=(0, D / 2 - 0.15, H / 2 + 0.25), bevel=0.02)
    for x in (-W / 6 + 0.05, W / 6 - 0.05):
        wood.box((0.1, 0.08, H - 0.8), loc=(x, D / 2 - 0.25, H / 2 + 0.25), bevel=0.02)
    tiers = [0.55, 2.55, 4.55]
    for z in tiers[1:]:
        wood.box((W + 0.4, D - 0.1, 0.22), loc=(0, -0.05, z - 0.11), bevel=0.04)
        for sx in (-1, 1):
            amber.box((0.22, D - 0.05, 0.24), loc=(sx * (W / 2 + 0.12), -0.05, z - 0.11), bevel=0.03)
    k = 1
    for z in reversed(tiers):
        for x in (-W / 3 + 0.25, 0, W / 3 - 0.25):
            plinth_label(m, (x, -0.1, z), k, base=(1.05, 0.75, 0.3))
            k += 1
    dress(m, 0.58, range(1, 10))


# ------------------------------------------------------------------ 7. label plaque

@register("Gallery_LabelPlaque", S04, "Specimen label plaque: wood base, dark slanted frame, cream face (attach Text at the face centre).",
          ref=(REF, (685, 570, 860, 720)))
def gallery_plaque(m):
    dark, wood = m.slot("FrameDark"), m.slot("Wood")
    wood.box((1.7, 0.95, 0.2), loc=(0, 0, 0.1), bevel=0.05)
    # wedge profile in (y, z), extruded along X
    prof = [(-0.36, 0), (0.36, 0), (0.36, 0.62), (-0.36, 0.16)]
    dark.prism(prof, 1.45, loc=(0, 0, 0.2), rot=(0, 0, 90), bevel=0.03)
    slope = math.degrees(math.atan2(0.46, 0.72))
    face = m.slot("Cream", "SmoothPlastic")
    n = Vector((0, -math.sin(math.radians(slope)), math.cos(math.radians(slope))))   # slanted face normal
    m.slot("Amber", "Metal").box((1.26, 0.04, 0.7), loc=Vector((0, 0, 0.59)) + n * 0.005, rot=(-(90 - slope), 0, 0), bevel=0.01)
    face.box((1.1, 0.04, 0.56), loc=Vector((0, 0, 0.59)) + n * 0.025, rot=(-(90 - slope), 0, 0), bevel=0.01)
    m.attach["Text"] = (0, -0.04, 0.6)
    m.extra["text_face_tilt_deg"] = round(90 - slope, 1)


# ------------------------------------------------------------------ 8. specimen stand

@register("Gallery_SpecimenStand", S04, "Specimen stand: octagonal dark base, wood cradle arms with amber brackets; the specimen leans back on it (attach Specimen, tilt in extra).",
          ref=(REF, (870, 515, 1035, 720)))
def gallery_specimen_stand(m):
    dark, wood, conc = m.slot("FrameDark"), m.slot("Wood"), m.slot("Concrete")
    octo(dark, 2.5, 0.6, 0, 0.22, d=2.0)
    octo(dark, 2.3, 0.55, 0.22, 0.16, d=1.8)
    wood.box((1.6, 0.08, 0.3), loc=(0, -1.02, 0.2), bevel=0.02)          # wood front band
    octo(conc, 1.3, 0.3, 0.38, 0.14, d=1.0)                              # raised pad under the specimen
    for sx in (-1, 1):
        wood.box((0.28, 0.6, 1.15), loc=(sx * 0.82, 0.12, 0.38 + 0.55), rot=(-10, 0, 0), bevel=0.05)
    m.attach["Specimen"] = (0, 0.05, 0.5)
    m.extra["specimen_tilt_deg"] = 15   # lean the specimen back (top toward +Y) by this much
    get = lambda name, slot: m.preview_piece(name, slot)  # noqa: E731
    specimen_into(get, at=(0, 0.05, 0.5), scale=0.62, mineral="DeepRed", cluster="D", stand=False, seed=40, tilt=15)


# ------------------------------------------------------------------ 9. owner nameplate

@register("Gallery_OwnerNameplate", S04, "Owner nameplate: wood board, dark face plate, brass bolts (attach Text). Origin = bottom centre on the wall plane.",
          ref=(REF, (1050, 580, 1255, 720)))
def gallery_nameplate(m):
    wood, dark, bolt = m.slot("Wood"), m.slot("Slate"), m.slot("Brass")
    wood.box((3.9, 0.2, 1.15), loc=(0, -0.1, 0.575), bevel=0.06)
    dark.box((3.45, 0.08, 0.78), loc=(0, -0.23, 0.575), bevel=0.03)
    ring_prism(m.slot("Amber", "Metal"), rect(3.6, 0.92, 0, 0.575), rect(3.45, 0.78, 0, 0.575), 0.1, loc=(0, -0.24, 0))
    for sx in (-1, 1):
        for sz in (-1, 1):
            bolt.bolt((sx * 1.55, -0.27, 0.575 + sz * 0.26), normal=(0, -1, 0), r=0.06)
    m.attach["Text"] = (0, -0.28, 0.575)


# ------------------------------------------------------------------ 10. mineral index board

@register("Gallery_IndexBoard", S04, "Mineral index board: wood frame, dark corner caps, amber diamonds, 6 cards with a raised gem (pieces Gem1..6, slot Crystal: colour per mineral; attach Card1..6). Origin = bottom centre on the wall plane.",
          ref=(REF, (1275, 480, 1525, 725)))
def gallery_index(m):
    W, H = 5.6, 5.2
    wood, dark, amber, bolt = m.slot("Wood"), m.slot("FrameDark"), m.slot("Amber", "Metal"), m.slot("Brass")
    ring_prism(wood, rect(W, H, 0, H / 2), rect(W - 0.8, H - 0.8, 0, H / 2), 0.3, loc=(0, -0.15, 0))
    ring_prism(dark, rect(W - 0.75, H - 0.75, 0, H / 2), rect(W - 1.0, H - 1.0, 0, H / 2), 0.24, loc=(0, -0.14, 0))
    m.slot("Concrete", "SmoothPlastic").box((W - 0.95, 0.1, H - 0.95), loc=(0, -0.06, H / 2), bevel=0.0)
    for sx in (-1, 1):
        for sz in (0, 1):
            z = 0.25 + sz * (H - 0.5)
            dark.box((0.6, 0.4, 0.6), loc=(sx * (W / 2 - 0.25), -0.2, z), bevel=0.05)
            bolt.bolt((sx * (W / 2 - 0.25), -0.4, z), normal=(0, -1, 0), r=0.07)
    for z in (0.2, H - 0.2):
        diamond(amber, 0.55, (0, -0.34, z))
    card, rim = m.slot("Cream", "SmoothPlastic"), m.slot("Rim")
    k = 1
    for row in range(2):
        for col in range(3):
            x, z = (col - 1) * 1.45, H / 2 + 0.95 - row * 1.95
            card.box((1.3, 0.06, 1.75), loc=(x, -0.13, z), bevel=0.02)
            # mini geode icon: pale rim egg with a faceted gem (own piece, colour per mineral) in front
            egg = [Vector((math.sin(a) * 0.4 * (1 - 0.18 * math.cos(a)), 0, -math.cos(a) * 0.46)) for a in
                   (math.radians(t) for t in range(0, 360, 30))]
            rim.hull([p + Vector((0, dy, 0)) for p in egg for dy in (-0.05, 0.03)], loc=(x, -0.2, z + 0.25))
            gem = m.piece("Gem%d" % k, "Crystal", note="card gem; colour per mineral")
            pts = [p * 0.72 + Vector((0, dy, 0)) for p in egg for dy in (-0.06, 0.0)] + [Vector((0, -0.14, 0.02))]
            gem.hull(pts, loc=(x, -0.21, z + 0.25))
            dark.box((0.85, 0.04, 0.08), loc=(x, -0.17, z - 0.42), bevel=0.0)
            dark.box((0.6, 0.04, 0.07), loc=(x, -0.17, z - 0.58), bevel=0.0)
            m.attach["Card%d" % k] = (x, -0.2, z)
            k += 1


# ------------------------------------------------------------------ 11. bench

@register("Gallery_Bench", S04, "Gallery bench: three wood planks on two dark trapezoid legs with a wood stretcher.",
          ref=(REF, (25, 790, 390, 975)))
def gallery_bench(m):
    wood, dark = m.slot("Wood"), m.slot("FrameDark")
    for i in range(3):
        wood.box((6.2, 0.6, 0.5), loc=(0, (i - 1) * 0.63, 1.8), bevel=0.08)
    for sx in (-1, 1):
        x = sx * 2.0
        dark.box((0.95, 1.7, 1.05), loc=(x, 0, 0.52), bevel=K.BEVEL_BIG, taper=(0.72, 0.85))
        dark.box((0.68, 1.45, 0.52), loc=(x, 0, 1.3), bevel=0.08, taper=(1.45, 1.2))
    wood.box((3.4, 0.36, 0.36), loc=(0, 0, 1.0), bevel=0.05)
    m.attach["Seat1"] = (-1.4, 0, 2.05)
    m.attach["Seat2"] = (1.4, 0, 2.05)


# ------------------------------------------------------------------ 12. gallery wall lamp

@register("Gallery_WallLamp", S04, "Gallery wall lamp: pointed dark backplate with amber trim, arm, lantern with glowing panes (Glow piece, Neon; attach Light). Origin = backplate centre on the wall plane.",
          ref=(REF, (395, 790, 625, 975)))
def gallery_lamp(m):
    dark, amber, frame = m.slot("FrameDark"), m.slot("Amber", "Metal"), m.slot("Frame")
    plate = [(-0.42, -1.1), (0, -1.45), (0.42, -1.1), (0.42, 1.1), (0, 1.45), (-0.42, 1.1)]
    dark.prism(plate, 0.2, loc=(0, -0.1, 0), bevel=0.03)
    inner = [(x * 0.62, z * 0.7) for x, z in plate]
    trim_i = [(x * 0.48, z * 0.6) for x, z in plate]
    ring_prism(amber, inner, trim_i, 0.05, loc=(0, -0.22, 0))
    # arm
    dark.box((0.24, 0.6, 0.24), loc=(0, -0.5, 0.35), bevel=0.04)
    dark.box_between((0, -0.25, -0.3), (0, -0.7, 0.3), (0.14, 0.14))
    # hexagonal lantern: tapered base, glowing panes between corner posts, tapered cap + finial
    cx, cy, cz = 0, -0.95, 0.15
    frame.cyl(0.2, 0.42, 0.22, seg=6, loc=(cx, cy, cz - 0.62))
    frame.cyl(0.42, 0.42, 0.08, seg=6, loc=(cx, cy, cz - 0.47))
    frame.cyl(0.08, 0.2, 0.22, seg=6, loc=(cx, cy, cz - 0.84))
    dark.cyl(0.46, 0.46, 0.1, seg=6, loc=(cx, cy, cz + 0.42))
    dark.cyl(0.46, 0.14, 0.3, seg=6, loc=(cx, cy, cz + 0.62))
    dark.cyl(0.12, 0.12, 0.18, seg=6, loc=(cx, cy, cz + 0.85))
    dark.cyl(0.14, 0.02, 0.12, seg=6, loc=(cx, cy, cz + 1.0))
    for k in range(6):
        a = math.radians(60 * k)
        frame.box((0.07, 0.07, 0.85), loc=(cx + math.cos(a) * 0.36, cy + math.sin(a) * 0.36, cz - 0.03), rot=(0, 0, 60 * k), bevel=0.015)
    m.piece("Glow", "Lamp", note="lantern panes (Neon); dim/brighten for lights").cyl(0.33, 0.33, 0.82, seg=6, loc=(cx, cy, cz - 0.03))
    m.attach["Light"] = (cx, cy, cz)
