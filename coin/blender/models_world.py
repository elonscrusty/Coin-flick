"""COIN FLICK world models: trees, props, fence, gate pillar, fountain, sky pieces.

Rules: chunky low-poly, bright cartoon, nothing gross or scary, no flags. Units = studs, +Z up, origin = floor centre
(sky pieces: see each docstring). Slot names are letters/digits only. The game repaints slots from the theme
(Leaf, LeafLight, Bark, Stone, Roof, Wood, Envelope...) so the colours here are only defaults.
Each model stays well under 1500 faces.
"""

import math

from cfkit import Model

TAU = math.tau


def around(n, r, fn, start=0.0):
    for i in range(n):
        a = start + i / n * TAU
        fn(i, a, math.cos(a) * r, math.sin(a) * r)


def pie(piece, r, h, a0, a1, z=0.0, r_top=0.0, cx=0.0, cy=0.0):
    """A wedge of a cone (like a pizza slice with a sloped top) from angle a0 to a1, base at height z."""
    import bmesh as _bm

    bm = piece.bm
    v = bm.verts.new
    c0 = v((cx, cy, z))
    ct = v((cx, cy, z + h))
    b0 = v((cx + math.cos(a0) * r, cy + math.sin(a0) * r, z))
    b1 = v((cx + math.cos(a1) * r, cy + math.sin(a1) * r, z))
    t0 = v((cx + math.cos(a0) * r_top, cy + math.sin(a0) * r_top, z + h))
    t1 = v((cx + math.cos(a1) * r_top, cy + math.sin(a1) * r_top, z + h))
    f = bm.faces.new
    f((c0, b1, b0))
    f((ct, t0, t1))
    f((b0, b1, t1, t0))
    f((c0, b0, t0, ct))
    f((c0, ct, t1, b1))
    _bm.ops.recalc_face_normals(bm, faces=bm.faces)


# Trees ----------------------------------------------------------------------------------------------------------


def tree_oak():
    """Round cartoon oak, 9.6 tall. Slots Bark, Leaf, LeafLight (theme foliage), Fruit."""
    m = Model("CF_Tree")
    bark = m.slot("Bark", "#8a5a30")
    bark.cyl(0.95, 0.6, 3.6, seg=8, loc=(0, 0, 1.8), bevel=0.05)
    bark.cyl(1.45, 1.1, 0.7, seg=8, loc=(0, 0, 0.35))
    around(3, 1.2, lambda i, a, x, y: bark.cyl(0.35, 0.15, 1.0, seg=5, loc=(x * 1.1, y * 1.1, 0.3), rot=(math.sin(a) * 0.9, -math.cos(a) * 0.9, 0)))
    bark.box((0.35, 0.35, 1.5), loc=(0.5, 0, 4.3), rot=(0, 0.5, 0))
    leaf = m.slot("Leaf", "#58c944")
    light = m.slot("LeafLight", "#8fe05a")
    for loc, r, p in [
        ((0, 0, 5.2), 3.0, leaf), ((-2.1, 0.3, 4.4), 2.2, leaf), ((2.1, -0.2, 4.6), 2.3, leaf),
        ((0.2, 2.0, 4.5), 2.1, leaf), ((0.1, -2.0, 4.3), 2.1, leaf), ((-0.9, 0.4, 6.9), 2.4, light),
        ((1.1, -0.5, 6.7), 2.0, light), ((0, 0, 8.0), 1.6, light), ((-1.8, -1.4, 6.0), 1.5, light),
    ]:
        p.ball(r, loc=loc, scale=(1, 1, 0.9), seg=8, rings=5)
    fruit = m.slot("Fruit", "#ff4f5e")
    for a, z in ((0.3, 4.2), (2.4, 5.2), (4.2, 4.6), (5.5, 5.8), (1.2, 6.4)):
        fruit.ball(0.34, loc=(math.cos(a) * 3.0, math.sin(a) * 3.0, z), seg=6, rings=4)
    return m


def tree_palm():
    """Leaning palm, 9.2 tall. Slots Bark, Leaf (frond), Nut."""
    m = Model("CF_TreePalm")
    bark = m.slot("Bark", "#c58b52")
    for i in range(5):
        t = i / 4
        bark.cyl(0.85 - 0.25 * t, 0.7 - 0.25 * t, 1.9, seg=8, loc=(t * t * 1.8, 0, 0.95 + i * 1.6), rot=(0, -0.12 - 0.05 * i, 0), bevel=0.04)
        bark.cyl(1.0 - 0.25 * t, 1.0 - 0.25 * t, 0.2, seg=8, loc=(t * t * 1.8, 0, 0.5 + i * 1.6))
    leaf = m.slot("Leaf", "#3fbf57")
    light = m.slot("LeafLight", "#7fe06a")
    top = (1.9, 0, 8.4)
    leaf.ball(1.2, loc=(top[0], top[1], top[2] + 0.2), seg=6, rings=4)
    for i in range(8):
        a = i / 8 * TAU
        dx, dy = math.cos(a), math.sin(a)
        p = leaf if i % 2 == 0 else light
        # a frond: a long leaf-shaped blob drooping outwards, plus a drooping tip
        p.ball(1.0, loc=(top[0] + dx * 2.8, top[1] + dy * 2.8, top[2] + 0.2), scale=(3.4, 1.0, 0.28), seg=8, rings=4, rot=(0, 0.25, a))
        p.ball(1.0, loc=(top[0] + dx * 5.6, top[1] + dy * 5.6, top[2] - 0.9), scale=(2.4, 0.8, 0.25), seg=7, rings=4, rot=(0, 0.75, a))
    nut = m.slot("Nut", "#7a4a2a")
    for a in (0.3, 2.4, 4.4):
        nut.ball(0.5, loc=(top[0] + math.cos(a) * 0.7, top[1] + math.sin(a) * 0.7, top[2] - 0.7), seg=6, rings=4)
    return m


def tree_pine():
    """Cheerful pine, 10 tall. Slots Bark, Leaf, LeafLight, Snow."""
    m = Model("CF_TreePine")
    bark = m.slot("Bark", "#8a5a30")
    bark.cyl(0.8, 0.55, 2.8, seg=7, loc=(0, 0, 1.4))
    leaf = m.slot("Leaf", "#2fae5e")
    light = m.slot("LeafLight", "#58cf72")
    for i, (r, z) in enumerate(((3.6, 3.2), (3.0, 5.0), (2.3, 6.8), (1.5, 8.4))):
        (leaf if i % 2 == 0 else light).cone(r, 3.0, seg=8, loc=(0, 0, z + 0.6))
    m.slot("Snow", "#ffffff").cone(0.7, 1.3, seg=8, loc=(0, 0, 9.4))
    return m


def tree_candy():
    """Lollipop tree, 10.4 tall: a round striped candy on a white stick. Slots Stick, Candy, Stripe."""
    m = Model("CF_TreeCandy")
    m.slot("Stick", "#ffffff").cyl(0.5, 0.5, 6.4, seg=8, loc=(0, 0, 3.2))
    candy = m.slot("Candy", "#ff6fae")
    candy.ball(3.0, loc=(0, 0, 7.4), seg=10, rings=7)
    stripe = m.slot("Stripe", "#ffffff")
    for z, r in ((5.6, 1.9), (7.4, 3.05), (9.2, 1.9)):
        stripe.cyl(r, r, 0.55, seg=10, loc=(0, 0, z))
    stripe.ball(0.7, loc=(0, 0, 10.4 - 0.5), seg=6, rings=4)
    m.slot("Sprinkle", "#ffd23a").ball(0.35, loc=(2.0, 1.6, 8.4), seg=5, rings=3)
    return m


def tree_crystal():
    """Space crystal tree, 8.2 tall. Slots Stem, Crystal (bright cyan), CrystalB (violet)."""
    m = Model("CF_TreeCrystal")
    m.slot("Stem", "#9aa0c8").cyl(1.0, 0.6, 2.2, seg=6, loc=(0, 0, 1.1))
    a = m.slot("Crystal", "#5be6ff", "Neon")
    b = m.slot("CrystalB", "#b98cff", "Neon")
    spikes = [(0, 0, 2.2, 1.0, 6.0, 0, 0, a), (1.3, 0.4, 2.0, 0.8, 4.4, 0.28, 0.14, b), (-1.2, -0.6, 2.0, 0.8, 4.0, -0.28, -0.2, b),
              (0.2, 1.4, 2.0, 0.7, 3.6, -0.2, 0.1, a), (-0.5, -1.4, 2.0, 0.7, 3.4, 0.2, -0.2, a)]
    for x, y, z, r, h, rx, ry, p in spikes:
        axis = (math.cos(rx) * math.sin(ry), -math.sin(rx), math.cos(rx) * math.cos(ry))
        body, tip = h * 0.7, h * 0.35
        p.cyl(r, r * 0.9, body, seg=6, loc=(x + axis[0] * body / 2, y + axis[1] * body / 2, z + axis[2] * body / 2), rot=(rx, ry, 0))
        p.cone(r * 0.9, tip, seg=6, loc=(x + axis[0] * (body + tip / 2), y + axis[1] * (body + tip / 2), z + axis[2] * (body + tip / 2)), rot=(rx, ry, 0))
    return m


def castle_tower():
    """Castle tower, 11.2 tall with a cone roof. Slots Stone, StoneLight, Roof (theme accent), Window. No flag."""
    m = Model("CF_Tower")
    stone = m.slot("Stone", "#c9ccd8")
    stone.cyl(2.6, 2.3, 7.0, seg=10, loc=(0, 0, 3.5), bevel=0.05)
    stone.cyl(3.0, 3.0, 0.7, seg=10, loc=(0, 0, 0.35))
    light = m.slot("StoneLight", "#eceef5")
    light.cyl(3.0, 3.0, 0.7, seg=10, loc=(0, 0, 7.2))
    around(8, 2.7, lambda i, a, x, y: light.box((1.1, 1.0, 0.9), loc=(x, y, 7.8), rot=(0, 0, a)))
    m.slot("Roof", "#ff6a6a").cone(3.2, 3.4, seg=10, loc=(0, 0, 9.5))
    win = m.slot("Window", "#3a4e8a")
    for z in (3.0, 5.4):
        win.box((0.9, 0.5, 1.5), loc=(0, -2.4, z))
        win.box((0.9, 0.5, 1.5), loc=(0, 2.4, z))
    m.slot("Trim", "#ffd23a").ball(0.5, loc=(0, 0, 11.4), seg=6, rings=4)
    return m


# Props ----------------------------------------------------------------------------------------------------------


def bush():
    m = Model("CF_Bush")
    leaf = m.slot("Leaf", "#4fc455")
    light = m.slot("LeafLight", "#86e060")
    for loc, r, p in [((0, 0, 1.4), 1.7, leaf), ((1.5, 0.3, 1.1), 1.3, leaf), ((-1.4, -0.2, 1.1), 1.3, leaf),
                      ((0.2, 0.2, 2.3), 1.3, light), ((0.7, -0.9, 1.7), 1.0, light)]:
        p.ball(r, loc=loc, scale=(1, 1, 0.9), seg=7, rings=5)
    berry = m.slot("Berry", "#ff5a7a")
    for a in (0.5, 2.0, 3.6, 5.0):
        berry.ball(0.28, loc=(math.cos(a) * 1.9, math.sin(a) * 1.6, 1.6), seg=5, rings=3)
    return m


def rock():
    m = Model("CF_Rock")
    stone = m.slot("Stone", "#a9afc0")
    light = m.slot("StoneLight", "#d3d8e6")
    stone.box((3.4, 2.6, 2.0), loc=(0, 0, 1.0), rot=(0, 0.05, 0.4), bevel=0.45)
    stone.box((2.0, 1.8, 1.7), loc=(1.9, 0.9, 0.8), rot=(0.1, 0, 1.0), bevel=0.4)
    light.box((1.8, 1.4, 1.0), loc=(-0.4, 0.2, 2.1), rot=(0.1, 0.15, 0.7), bevel=0.35)
    light.box((1.1, 0.9, 0.8), loc=(-2.0, -1.2, 0.4), rot=(0, 0.1, 0.2), bevel=0.25)
    return m


def flowers():
    m = Model("CF_Flowers")
    m.slot("Bed", "#a4a9bb").box((4.6, 2.2, 0.6), loc=(0, 0, 0.3), bevel=0.15)
    m.slot("Soil", "#6d4a35").box((4.2, 1.8, 0.2), loc=(0, 0, 0.62))
    stem = m.slot("Stem", "#46b84a")
    petals = [m.slot("Petal", "#ff5a86"), m.slot("PetalB", "#ffd23a"), m.slot("PetalC", "#b685ff")]
    heart = m.slot("Heart", "#fff2a0")
    for i, (x, y, h) in enumerate(((-1.6, 0.3, 1.5), (-0.6, -0.4, 1.9), (0.5, 0.4, 1.6), (1.5, -0.3, 2.0), (0.0, 0.5, 2.1))):
        stem.cyl(0.07, 0.07, h, seg=4, loc=(x, y, 0.7 + h / 2))
        petals[i % 3].ball(0.55, loc=(x, y, 0.8 + h), scale=(1, 1, 0.6), seg=6, rings=4)
        heart.ball(0.27, loc=(x, y, 0.95 + h), seg=5, rings=3)
    return m


def mushroom():
    m = Model("CF_Mushroom")
    m.slot("Stem", "#fff1d6").cyl(0.7, 0.9, 1.7, seg=8, loc=(0, 0, 0.85))
    m.slot("Cap", "#ff4f5e").ball(1.9, loc=(0, 0, 1.8), scale=(1, 1, 0.62), seg=9, rings=5)
    spot = m.slot("Spot", "#ffffff")
    for a, r, z in ((0.3, 1.3, 2.4), (2.2, 1.2, 2.3), (4.1, 1.3, 2.35)):
        spot.ball(0.34, loc=(math.cos(a) * r, math.sin(a) * r, z), scale=(1, 1, 0.5), seg=5, rings=3)
    spot.ball(0.4, loc=(0, 0, 2.95), scale=(1, 1, 0.5), seg=5, rings=3)
    return m


def lamp():
    m = Model("CF_Lamp")
    post = m.slot("Post", "#4a5068")
    post.cyl(0.5, 0.35, 6.4, seg=8, loc=(0, 0, 3.2))
    post.cyl(1.0, 1.0, 0.6, seg=8, loc=(0, 0, 0.3))
    post.cyl(0.9, 0.5, 0.5, seg=8, loc=(0, 0, 6.6))
    m.slot("Lamp", "#fff0a0", "Neon").ball(1.1, loc=(0, 0, 7.6), seg=8, rings=5)
    m.slot("Cap", "#ffd23a").cone(1.0, 0.8, seg=8, loc=(0, 0, 8.9))
    return m


def bench():
    m = Model("CF_Bench")
    wood = m.slot("Wood", "#d6965a")
    for z in (1.9, 2.3):
        wood.box((4.6, 0.55, 0.3), loc=(0, -0.1, z), bevel=0.05)
    wood.box((4.6, 0.3, 0.45), loc=(0, -0.7, 2.7), rot=(-0.18, 0, 0))
    wood.box((4.6, 0.3, 0.45), loc=(0, -0.75, 3.2), rot=(-0.18, 0, 0))
    leg = m.slot("Leg", "#6a7088")
    for x in (-2.0, 2.0):
        leg.box((0.4, 1.4, 1.9), loc=(x, -0.3, 0.95), bevel=0.05)
    return m


def umbrella():
    """Beach umbrella 4.8 tall with 8 alternating canopy panels. Slots Pole, Canopy (theme accent), Stripe, Cap."""
    m = Model("CF_Umbrella")
    m.slot("Pole", "#ffffff").cyl(0.2, 0.2, 4.6, seg=6, loc=(0, 0, 2.3))
    canopy = m.slot("Canopy", "#ff5a86")
    stripe = m.slot("Stripe", "#ffffff")
    for i in range(8):
        pie(canopy if i % 2 == 0 else stripe, 3.1, 1.5, i / 8 * TAU, (i + 1) / 8 * TAU, z=3.4, r_top=0.25)
    m.slot("Cap", "#ffd23a").ball(0.35, loc=(0, 0, 5.0), seg=5, rings=3)
    return m


def shell():
    """Scallop shell 1.6 tall: a fan of ridges. Slots Shell, Ridge."""
    m = Model("CF_Shell")
    s = m.slot("Shell", "#ffb8d0")
    ridge = m.slot("Ridge", "#fff0f5")
    n = 7
    for i in range(n):
        a0 = math.radians(20 + i * 20)
        pie(s if i % 2 == 0 else ridge, 2.6, 1.0, a0, a0 + math.radians(20), z=0.0, r_top=2.0, cx=0, cy=-1.3)
    s.cyl(0.7, 0.7, 0.6, seg=6, loc=(0, -1.3, 0.3))
    return m


def candy_cane():
    """Candy cane 6.2 tall, hook curling over to +X. Slots Red, White."""
    m = Model("CF_CandyCane")
    red = m.slot("Red", "#ff3d5a")
    white = m.slot("White", "#ffffff")
    for i in range(5):
        (red if i % 2 == 0 else white).cyl(0.55, 0.55, 1.1, seg=8, loc=(0, 0, 0.55 + i * 1.0))
    for i in range(6):
        a = math.pi - i / 5 * math.pi
        x, z = 1.5 + 1.5 * math.cos(a), 5.1 + 1.5 * math.sin(a)
        (red if i % 2 == 1 else white).cyl(0.55, 0.55, 1.05, seg=8, loc=(x, 0, z), rot=(0, math.pi - a, 0))
    return m


def crystals():
    m = Model("CF_Crystals")
    a = m.slot("Crystal", "#5be6ff", "Neon")
    b = m.slot("CrystalB", "#c08cff", "Neon")
    for i, (x, y, h, r, p) in enumerate(((0, 0, 4.2, 0.9, a), (1.4, 0.5, 2.8, 0.7, b), (-1.3, -0.4, 3.2, 0.7, b), (0.3, -1.4, 2.0, 0.6, a), (-0.6, 1.3, 2.2, 0.55, a))):
        p.cyl(r, r, h * 0.7, seg=6, loc=(x, y, h * 0.35))
        p.cone(r, h * 0.35, seg=6, loc=(x, y, h * 0.7 + h * 0.175))
    m.slot("Base", "#8a90b8").cyl(2.4, 2.0, 0.5, seg=8, loc=(0, 0, 0.25))
    return m


# Yard frame -----------------------------------------------------------------------------------------------------


def fence_post():
    """One fence post 3.2 tall with a gold ball cap. Slots Wood (theme fence), Cap."""
    m = Model("CF_FencePost")
    m.slot("Wood", "#ffffff").box((0.9, 0.9, 3.2), loc=(0, 0, 1.6), bevel=0.1)
    m.slot("Cap", "#ffd23a").ball(0.62, loc=(0, 0, 3.35), seg=6, rings=4)
    return m


def fence_section():
    """4 long (along X) fence part, rails + pickets, 3.0 tall. Slot Wood (theme fence), Accent."""
    m = Model("CF_FenceSection")
    wood = m.slot("Wood", "#ffffff")
    for z in (1.0, 2.1):
        wood.box((4.0, 0.34, 0.4), loc=(0, 0, z), bevel=0.05)
    acc = m.slot("Accent", "#ffd23a")
    for x in (-1.5, -0.5, 0.5, 1.5):
        wood.box((0.4, 0.3, 2.6), loc=(x, 0, 1.3), bevel=0.05)
        acc.cone(0.28, 0.45, seg=4, loc=(x, 0, 2.8))
    return m


def arch_pillar():
    """Gate pillar, 20 tall and thin (0.5 wide: keeps the view clear). Slots Pillar, Band (theme border), Cap, Base."""
    m = Model("CF_ArchPillar")
    m.slot("Pillar", "#fffcf5").box((0.5, 0.5, 20.0), loc=(0, 0, 10.0))
    band = m.slot("Band", "#ffd23a")
    for i in range(1, 5):
        band.box((0.7, 0.7, 0.5), loc=(0, 0, i * 2.9))
    m.slot("Base", "#e4e8f2").box((1.1, 1.1, 0.7), loc=(0, 0, 0.35), bevel=0.1)
    m.slot("Cap", "#ffcd32").ball(0.65, loc=(0, 0, 20.4), seg=7, rings=5)
    return m


# World pieces ---------------------------------------------------------------------------------------------------


def fountain():
    """Round fountain, about 9.2 wide. Slots Basin, Stone, Water, Spray."""
    m = Model("CF_Fountain")
    m.slot("Basin", "#ffbe46").cyl(4.6, 4.6, 1.4, seg=14, loc=(0, 0, 0.7), bevel=0.1)
    stone = m.slot("Stone", "#ebe8f5")
    stone.cyl(4.7, 4.7, 0.4, seg=14, loc=(0, 0, 1.5))
    stone.cyl(0.85, 0.85, 3.2, seg=8, loc=(0, 0, 3.0))
    stone.cyl(2.2, 1.4, 0.8, seg=10, loc=(0, 0, 4.8))
    water = m.slot("Water", "#46b9ff", "SmoothPlastic")
    water.cyl(4.0, 4.0, 0.3, seg=14, loc=(0, 0, 1.6))
    water.cyl(1.9, 1.9, 0.2, seg=10, loc=(0, 0, 5.3))
    spray = m.slot("Spray", "#c8ebff")
    spray.ball(1.2, loc=(0, 0, 7.0), seg=7, rings=5)
    around(6, 2.4, lambda i, a, x, y: spray.ball(0.5, loc=(x, y, 5.7 - (i % 2) * 0.3), seg=5, rings=3))
    return m


def free_statue():
    """FREE PLOT trophy: coin stack on a pedestal, topped by a pink gem. Slots Stone, Gold, GoldDark, Gem."""
    m = Model("CF_FreeStatue")
    m.slot("Stone", "#fffaf0").box((4.0, 4.0, 1.4), loc=(0, 0, 0.7), bevel=0.2)
    gold = m.slot("Gold", "#ffcd28")
    dark = m.slot("GoldDark", "#e89a00")
    for i in range(6):
        (gold if i % 2 == 0 else dark).cyl(1.9, 1.9, 0.5, seg=14, loc=(0, 0, 1.65 + i * 0.5), bevel=0.05)
    gold.cyl(1.4, 1.4, 0.3, seg=12, loc=(0, 0, 4.85))
    m.slot("Gem", "#ff6fae").ball(1.0, loc=(0, 0, 5.9), scale=(1, 1, 1.25), seg=6, rings=4)
    return m


def island():
    """Floating island: origin = middle of the grass top. Green top, grey and white rock bowl, bushy tree. No brown."""
    m = Model("CF_Island")
    rock = m.slot("Rock", "#a5afc3")
    light = m.slot("RockLight", "#ebf0fa")
    rock.cyl(12.5, 3.0, 9.0, seg=10, loc=(0, 0, -5.0), bevel=0.2)
    rock.ball(4.0, loc=(0, 0, -9.6), scale=(1, 1, 0.8), seg=7, rings=4)
    light.ball(3.2, loc=(5.5, 3.0, -4.0), seg=6, rings=4)
    light.ball(2.4, loc=(-5.0, -4.0, -6.0), seg=6, rings=4)
    light.ball(2.0, loc=(1.5, -7.0, -3.5), seg=6, rings=4)
    grass = m.slot("Grass", "#6edc5f")
    grass.cyl(13.5, 13.5, 1.6, seg=14, loc=(0, 0, -0.2), bevel=0.15)
    around(14, 12.8, lambda i, a, x, y: grass.ball(1.2, loc=(x, y, -0.3), seg=5, rings=3))
    m.slot("Trunk", "#d7dce6").cyl(0.8, 0.6, 4.6, seg=7, loc=(-5.0, 2.0, 2.9))
    leaf = m.slot("Leaf", "#3cc864")
    leaf.ball(3.0, loc=(-5.0, 2.0, 6.6), seg=8, rings=5)
    leaf.ball(2.0, loc=(-3.4, 2.6, 5.6), seg=6, rings=4)
    leaf.ball(2.0, loc=(-6.4, 1.2, 5.6), seg=6, rings=4)
    flower = m.slot("Flower", "#ff5a86")
    flowerb = m.slot("FlowerB", "#ffd23a")
    for i, (x, y) in enumerate(((3.0, -3.5), (4.4, -1.2), (2.0, 3.8), (5.0, 2.6), (-1.5, -5.0))):
        (flower if i % 2 == 0 else flowerb).ball(0.6, loc=(x, y, 1.0), scale=(1, 1, 0.7), seg=5, rings=3)
    m.slot("Gold", "#ffcd28").cyl(2.0, 2.0, 0.6, seg=12, loc=(2.0, 0.0, 1.0))
    return m


def cloud():
    """Fluffy cloud about 40 wide, origin = centre. Slots Cloud, CloudShade."""
    m = Model("CF_Cloud")
    c = m.slot("Cloud", "#ffffff")
    s = m.slot("CloudShade", "#e2f0ff")
    for loc, r, p in [((0, 0, 0), 8.0, c), ((11, 2, -1), 6.0, s), ((-11, -1, -1.5), 6.0, s), ((5, -3, 4), 5.5, c),
                      ((-5, 3, 3), 5.0, c), ((17, 0, -3), 4.0, c), ((-17, 1, -3.5), 3.8, c)]:
        p.ball(r, loc=loc, scale=(1, 1, 0.8), seg=8, rings=5)
    return m


def balloon():
    """Hot-air balloon, origin = the knot under the envelope (basket hangs below). Slots Envelope (any colour), Stripe, Basket, String."""
    m = Model("CF_Balloon")
    m.slot("Envelope", "#ff4664").ball(5.0, loc=(0, 0, 6.0), scale=(1, 1, 1.2), seg=10, rings=7)
    m.slot("Stripe", "#ffffff").cyl(4.7, 4.7, 1.8, seg=10, loc=(0, 0, 6.3))
    m.slot("Knot", "#b02848").cone(1.0, 1.6, seg=6, loc=(0, 0, 0.7), rot=(math.pi, 0, 0))
    string = m.slot("String", "#a0a6b8")
    for a in (0.0, math.pi / 2, math.pi, 3 * math.pi / 2):
        string.cyl(0.1, 0.1, 5.0, seg=4, loc=(math.cos(a) * 0.9, math.sin(a) * 0.9, -2.5), rot=(math.sin(a) * 0.12, -math.cos(a) * 0.12, 0))
    m.slot("Basket", "#f2f2f8").box((2.6, 2.6, 1.6), loc=(0, 0, -5.6), bevel=0.2)
    return m


def plaza_tile():
    """Round plaza floor, 44 wide, 0.4 thick: six colour rings (origin = floor centre). Slots RingA..RingF."""
    m = Model("CF_PlazaTile")
    cols = ["#f5dea0", "#ffd0e8", "#cfe9ff", "#ffe27a", "#d6f5c0", "#ffffff"]
    for i, (d, col) in enumerate(zip((44, 40, 34, 30, 26, 24), cols)):
        m.slot("Ring" + "ABCDEF"[i], col).cyl(d / 2, d / 2, 0.2, seg=24, loc=(0, 0, 0.1 + i * 0.02))
    star = m.slot("Star", "#ffc83c")
    star.star(9.0, 4.5, 0.1, points=8, loc=(0, 0, 0.3))
    return m


MODELS = {
    "CF_Tree": tree_oak,
    "CF_TreePalm": tree_palm,
    "CF_TreePine": tree_pine,
    "CF_TreeCandy": tree_candy,
    "CF_TreeCrystal": tree_crystal,
    "CF_Tower": castle_tower,
    "CF_Bush": bush,
    "CF_Rock": rock,
    "CF_Flowers": flowers,
    "CF_Mushroom": mushroom,
    "CF_Lamp": lamp,
    "CF_Bench": bench,
    "CF_Umbrella": umbrella,
    "CF_Shell": shell,
    "CF_CandyCane": candy_cane,
    "CF_Crystals": crystals,
    "CF_FencePost": fence_post,
    "CF_FenceSection": fence_section,
    "CF_ArchPillar": arch_pillar,
    "CF_Fountain": fountain,
    "CF_FreeStatue": free_statue,
    "CF_Island": island,
    "CF_Cloud": cloud,
    "CF_Balloon": balloon,
    "CF_PlazaTile": plaza_tile,
}
