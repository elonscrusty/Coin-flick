"""COIN FLICK coin-side models: mega coin, gift box, five helper characters, eight hats.

Colours are defaults; the game tints pieces by slot name (see src/shared/MeshCatalog.luau).
Characters face -Y in Blender (front view), origin = floor centre, about 4 studs tall.
Hats: origin = the top of the head, +Z up, sized for a 1.2-wide head like HatBuilder's.
"""

import math

from cfkit import Model

TAU = math.tau


def mega_coin():
    """Huge showpiece coin: 4 wide, 1.1 thick, big star with gems on the rim. Origin = centre."""
    m = Model("CF_MegaCoin")
    rim = m.slot("Rim", "#e89a00")
    rim.cyl(2.0, 2.0, 1.1, seg=24, bevel=0.14)
    for z in (0.58, -0.58):
        for i in range(20):
            a = i / 20 * TAU
            rim.ball(0.13, loc=(math.cos(a) * 1.62, math.sin(a) * 1.62, z), seg=5, rings=3)
    face = m.slot("Face", "#ffd23a")
    face.cyl(1.76, 1.76, 0.94, seg=24, bevel=0.05)
    mark = m.slot("Mark", "#8a4a00")
    mark.star(1.2, 0.55, 0.2, loc=(0, 0, 0.5))
    mark.cyl(0.8, 0.8, 0.14, seg=12, loc=(0, 0, -0.5))
    gem = m.slot("Gem", "#ff5fb0")
    for i in range(6):
        a = i / 6 * TAU + TAU / 12
        gem.ball(0.2, loc=(math.cos(a) * 2.0, math.sin(a) * 2.0, 0), seg=6, rings=4)
    return m


def gift_box():
    """Present: 2.4 cube with ribbon and bow, origin = floor centre."""
    m = Model("CF_GiftBox")
    box = m.slot("Box", "#ff5fa8")
    box.box((2.4, 2.4, 1.9), loc=(0, 0, 0.95), bevel=0.1)
    lid = m.slot("Lid", "#ff86bf")
    lid.box((2.6, 2.6, 0.5), loc=(0, 0, 2.05), bevel=0.1)
    ribbon = m.slot("Ribbon", "#ffe14a")
    ribbon.box((0.5, 2.62, 1.92), loc=(0, 0, 0.96))
    ribbon.box((2.62, 0.5, 1.92), loc=(0, 0, 0.96))
    ribbon.box((0.52, 2.7, 0.54), loc=(0, 0, 2.05))
    ribbon.box((2.7, 0.52, 0.54), loc=(0, 0, 2.05))
    ribbon.ball(0.5, loc=(-0.55, 0, 2.6), scale=(1.2, 0.7, 0.9), seg=6, rings=4)
    ribbon.ball(0.5, loc=(0.55, 0, 2.6), scale=(1.2, 0.7, 0.9), seg=6, rings=4)
    ribbon.ball(0.3, loc=(0, 0, 2.55), seg=6, rings=4)
    return m


def _helper(name, body, cap, extra="#ffd23a"):
    """Chunky round buddy: body ball, head ball, face, arms and feet. Returns (model, slots)."""
    m = Model(name)
    b = m.slot("Body", body)
    b.ball(1.15, loc=(0, 0, 1.3), scale=(1, 0.9, 1), seg=10, rings=6)
    skin = m.slot("Head", "#ffdcb4")
    skin.ball(0.88, loc=(0, 0, 3.0), seg=10, rings=6)
    skin.ball(0.28, loc=(-1.25, -0.1, 1.5), seg=6, rings=4)  # hands
    skin.ball(0.28, loc=(1.25, -0.1, 1.5), seg=6, rings=4)
    feet = m.slot("Feet", "#ffffff")
    feet.ball(0.42, loc=(-0.55, -0.25, 0.3), scale=(1, 1.3, 0.7), seg=6, rings=4)
    feet.ball(0.42, loc=(0.55, -0.25, 0.3), scale=(1, 1.3, 0.7), seg=6, rings=4)
    eye = m.slot("Eye", "#1c1c28")
    eye.ball(0.14, loc=(-0.3, -0.78, 3.12), seg=6, rings=4)
    eye.ball(0.14, loc=(0.3, -0.78, 3.12), seg=6, rings=4)
    cheek = m.slot("Cheek", "#ff8fa8")
    cheek.ball(0.15, loc=(-0.5, -0.7, 2.88), scale=(1, 0.5, 0.7), seg=5, rings=3)
    cheek.ball(0.15, loc=(0.5, -0.7, 2.88), scale=(1, 0.5, 0.7), seg=5, rings=3)
    capslot = m.slot("Cap", cap)
    ex = m.slot("Extra", extra)
    return m, capslot, ex


def buddy():
    m, cap, ex = _helper("CF_Buddy", "#5ac8ff", "#ff5a5a")
    cap.ball(0.92, loc=(0, 0, 3.25), scale=(1, 1, 0.7), seg=10, rings=5)  # cap dome
    cap.box((1.1, 0.8, 0.14), loc=(0, -0.85, 3.2), bevel=0.04)  # brim
    ex.ball(0.16, loc=(0, 0, 3.78), seg=6, rings=4)  # button
    return m


def zippy():
    m, cap, ex = _helper("CF_Zippy", "#6edc5a", "#ffdc3c")
    cap.cone(0.7, 1.0, seg=6, loc=(0, 0, 3.95))  # spiky hair
    cap.cone(0.4, 0.8, seg=5, loc=(-0.55, 0, 3.7), rot=(0, 0.6, 0))
    cap.cone(0.4, 0.8, seg=5, loc=(0.55, 0, 3.7), rot=(0, -0.6, 0))
    # lightning bolt on the tummy
    ex.box((0.5, 0.14, 0.7), loc=(0.1, -1.0, 1.65), rot=(0, 0, -0.35))
    ex.box((0.5, 0.14, 0.7), loc=(-0.1, -1.0, 1.1), rot=(0, 0, 0.35))
    return m


def chompy():
    m, cap, ex = _helper("CF_Chompy", "#ff963c", "#ff78be")
    # donut hat: ring of balls with sprinkles
    for i in range(10):
        a = i / 10 * TAU
        cap.ball(0.22, loc=(math.cos(a) * 0.5, math.sin(a) * 0.5, 3.85), seg=5, rings=3)
    ex.ball(0.1, loc=(0.5, 0, 4.08), seg=4, rings=3)
    ex.ball(0.1, loc=(-0.5, 0.1, 4.08), seg=4, rings=3)
    ex.ball(0.1, loc=(0, -0.5, 4.08), seg=4, rings=3)
    ex.ball(0.1, loc=(0, 0.5, 4.08), seg=4, rings=3)
    # big happy mouth
    mouth = m.slot("Mouth", "#b02848")
    mouth.ball(0.3, loc=(0, -0.7, 2.6), scale=(1.4, 0.4, 0.8), seg=6, rings=4)
    return m


def twinkle():
    m, cap, ex = _helper("CF_Twinkle", "#ff82c8", "#96e1ff")
    cap.star(0.8, 0.36, 0.2, loc=(0, 0, 4.05), rot=(math.pi / 2, 0, 0))  # star on top
    ex.star(0.3, 0.14, 0.12, loc=(-1.5, -0.2, 2.6), rot=(math.pi / 2, 0, 0))  # floating sparkles
    ex.star(0.24, 0.11, 0.1, loc=(1.55, 0.1, 3.2), rot=(math.pi / 2, 0, 0))
    ex.star(0.2, 0.09, 0.1, loc=(1.2, -0.3, 0.9), rot=(math.pi / 2, 0, 0))
    return m


def king():
    m, cap, ex = _helper("CF_King", "#a064f0", "#ffc828")
    cap.cyl(0.62, 0.7, 0.36, seg=10, loc=(0, 0, 3.85))
    for i in range(5):
        a = i / 5 * TAU
        cap.cone(0.16, 0.45, seg=5, loc=(math.cos(a) * 0.58, math.sin(a) * 0.58, 4.2))
    ex.ball(0.14, loc=(0, -0.62, 3.9), seg=6, rings=4)
    cape = m.slot("Cape", "#e8384f")
    cape.box((1.9, 0.2, 1.8), loc=(0, 0.95, 1.5), rot=(-0.12, 0, 0), bevel=0.05)
    trim = m.slot("Trim", "#fff5dc")
    trim.box((2.0, 0.24, 0.3), loc=(0, 0.93, 2.35), rot=(-0.12, 0, 0))
    return m


def _hat(name):
    return Model(name)


def hat_party():
    m = _hat("CF_HatParty")
    a = m.slot("Cone", "#ff6ebe")
    a.cyl(0.55, 0.04, 1.9, seg=10, loc=(0, 0, 1.05))
    b = m.slot("Brim", "#ffdc3c")
    b.cyl(0.6, 0.6, 0.1, seg=12, loc=(0, 0, 0.05))
    b.ball(0.2, loc=(0, 0, 2.05), seg=6, rings=4)
    st = m.slot("Stripe", "#46a0ff")
    st.cyl(0.46, 0.4, 0.2, seg=10, loc=(0, 0, 0.7))
    st.cyl(0.3, 0.25, 0.2, seg=10, loc=(0, 0, 1.15))
    return m


def hat_cone():
    m = _hat("CF_HatCone")
    base = m.slot("Base", "#e15f14")
    base.box((1.4, 1.4, 0.14), loc=(0, 0, 0.07), bevel=0.03)
    body = m.slot("Cone", "#ff821e")
    body.cyl(0.5, 0.12, 1.1, seg=10, loc=(0, 0, 0.7))
    band = m.slot("Band", "#ffffff")
    band.cyl(0.36, 0.28, 0.22, seg=10, loc=(0, 0, 0.7))
    return m


def hat_cowboy():
    m = _hat("CF_HatCowboy")
    h = m.slot("Felt", "#96603a")
    h.cyl(1.05, 1.05, 0.12, seg=14, loc=(0, 0, 0.06), bevel=0.03)
    h.cyl(0.55, 0.5, 0.6, seg=12, loc=(0, 0, 0.42))
    h.ball(0.5, loc=(0, 0, 0.75), scale=(1, 1, 0.45), seg=8, rings=4)
    h.cyl(1.0, 0.7, 0.2, seg=14, loc=(0, 0, 0.2))  # brim rolls up towards the crown
    band = m.slot("Band", "#f04646")
    band.cyl(0.57, 0.57, 0.14, seg=12, loc=(0, 0, 0.2))
    return m


def hat_chef():
    m = _hat("CF_HatChef")
    w = m.slot("White", "#ffffff")
    w.ball(0.78, loc=(0, 0, 1.15), seg=8, rings=5)
    for a in range(4):
        ang = a / 4 * TAU
        w.ball(0.48, loc=(math.cos(ang) * 0.6, math.sin(ang) * 0.6, 0.9), seg=7, rings=4)
    band = m.slot("Band", "#cdd7eb")
    band.cyl(0.5, 0.5, 0.5, seg=12, loc=(0, 0, 0.25))
    return m


def hat_propeller():
    m = _hat("CF_HatPropeller")
    cap = m.slot("Cap", "#46a0ff")
    cap.cyl(0.6, 0.6, 0.35, seg=12, loc=(0, 0, 0.18))
    cap.ball(0.6, loc=(0, 0, 0.35), scale=(1, 1, 0.5), seg=8, rings=4)
    stripe = m.slot("Stripe", "#ffdc3c")
    stripe.cyl(0.62, 0.62, 0.1, seg=12, loc=(0, 0, 0.08))
    pin = m.slot("Pin", "#232330")
    pin.cyl(0.07, 0.07, 0.4, seg=6, loc=(0, 0, 0.7))
    blade = m.slot("Blade", "#f04646")
    blade.box((1.6, 0.3, 0.06), loc=(0, 0, 0.9), rot=(0.12, 0, 0))
    blade2 = m.slot("BladeB", "#ffdc3c")
    blade2.box((0.3, 1.6, 0.06), loc=(0, 0, 0.92), rot=(0, 0.12, 0))
    return m


def hat_duck():
    m = _hat("CF_HatDuck")
    y = m.slot("Body", "#ffdc3c")
    y.ball(0.6, loc=(0, 0.1, 0.45), scale=(1, 1.15, 0.9), seg=8, rings=5)
    y.ball(0.38, loc=(0, -0.25, 1.05), seg=8, rings=5)
    o = m.slot("Beak", "#ff821e")
    o.box((0.4, 0.3, 0.14), loc=(0, -0.62, 1.0), bevel=0.04)
    e = m.slot("Eye", "#232330")
    e.ball(0.07, loc=(-0.18, -0.52, 1.15), seg=5, rings=3)
    e.ball(0.07, loc=(0.18, -0.52, 1.15), seg=5, rings=3)
    return m


def hat_tophat():
    m = _hat("CF_HatTop")
    d = m.slot("Felt", "#232330")
    d.cyl(0.8, 0.8, 0.1, seg=14, loc=(0, 0, 0.05), bevel=0.02)
    d.cyl(0.5, 0.5, 1.0, seg=14, loc=(0, 0, 0.6), bevel=0.03)
    r = m.slot("Band", "#f04646")
    r.cyl(0.52, 0.52, 0.18, seg=14, loc=(0, 0, 0.24))
    return m


def hat_crown():
    m = _hat("CF_HatCrown")
    g = m.slot("Gold", "#ffc828")
    g.cyl(0.58, 0.58, 0.32, seg=12, loc=(0, 0, 0.16), bevel=0.03)
    gem = m.slot("Gem", "#f04646")
    gem2 = m.slot("GemB", "#46a0ff")
    for i in range(5):
        a = i / 5 * TAU
        x, y = math.cos(a) * 0.5, math.sin(a) * 0.5
        g.cone(0.16, 0.5, seg=5, loc=(x, y, 0.55))
        (gem if i % 2 == 0 else gem2).ball(0.1, loc=(x, y, 0.85), seg=5, rings=3)
    return m


MODELS = {
    "CF_MegaCoin": mega_coin,
    "CF_GiftBox": gift_box,
    "CF_Buddy": buddy,
    "CF_Zippy": zippy,
    "CF_Chompy": chompy,
    "CF_Twinkle": twinkle,
    "CF_King": king,
    "CF_HatParty": hat_party,
    "CF_HatCone": hat_cone,
    "CF_HatCowboy": hat_cowboy,
    "CF_HatChef": hat_chef,
    "CF_HatPropeller": hat_propeller,
    "CF_HatDuck": hat_duck,
    "CF_HatTop": hat_tophat,
    "CF_HatCrown": hat_crown,
}
