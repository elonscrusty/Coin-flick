"""COIN FLICK coin pets: puppy, piggy, bunny, dragon, space cat.

Chunky, cute, big eyes, nothing scary. About 2.5 studs tall, origin = floor centre, the pet FACES -Y in Blender
(the first thing the preview camera sees). Slots (colour pieces) are tinted by the game, so every pet uses the
same names where it can: Body, Belly, Foot, Ear, Eye, EyeShine, Nose; extras are named for what they are.
"""

import math

from cfkit import Model

TAU = math.tau


def critter(name, body, belly, foot, nose="#3b2a2a"):
    """Shared chunky body + head + big eyes + paws. Returns (model, body piece, head position)."""
    m = Model(name)
    b = m.slot("Body", body)
    # round body and a slightly wider head
    b.ball(0.88, loc=(0, 0.05, 0.86), scale=(1.0, 1.0, 0.95), seg=10, rings=6)
    b.ball(0.8, loc=(0, -0.12, 1.78), scale=(1.1, 1.0, 0.95), seg=10, rings=6)
    m.slot("Belly", belly).ball(0.6, loc=(0, -0.45, 0.78), scale=(0.9, 0.62, 1.0), seg=8, rings=5)
    f = m.slot("Foot", foot)
    for x in (-0.42, 0.42):
        f.ball(0.3, loc=(x, -0.52, 0.2), scale=(1.0, 1.25, 0.7), seg=7, rings=4)
        f.ball(0.3, loc=(x * 1.15, 0.45, 0.2), scale=(1.0, 1.2, 0.7), seg=7, rings=4)
    eye = m.slot("Eye", "#2a1a1a")
    shine = m.slot("EyeShine", "#ffffff")
    for s in (-1, 1):
        eye.ball(0.2, loc=(s * 0.34, -0.74, 1.9), scale=(0.9, 0.7, 1.15), seg=8, rings=5)
        shine.ball(0.075, loc=(s * 0.3, -0.89, 2.0), seg=5, rings=3)
    m.slot("Nose", nose).ball(0.13, loc=(0, -0.93, 1.66), scale=(1.2, 0.8, 0.9), seg=6, rings=4)
    return m, b


def puppy():
    m, body = critter("CF_PetPuppy", "#deaa6e", "#fff1d6", "#c78f55")
    ear = m.slot("Ear", "#a8693a")
    for s in (-1, 1):  # floppy ears hanging down the sides of the head
        ear.ball(0.3, loc=(s * 0.92, -0.05, 1.7), scale=(0.45, 0.85, 1.6), seg=7, rings=5, rot=(0, s * 0.18, 0))
    patch = m.slot("Patch", "#a8693a")
    patch.ball(0.34, loc=(0.4, -0.55, 2.0), scale=(1.0, 0.55, 1.0), seg=7, rings=4)
    m.slot("Tongue", "#ff7f9a").box((0.2, 0.08, 0.26), loc=(0, -0.9, 1.4), bevel=0.02)
    tail = m.slot("Tail", "#deaa6e")
    tail.cone(0.28, 0.9, seg=6, loc=(0, 0.95, 1.25), rot=(-0.9, 0, 0))
    return m


def piggy():
    m, body = critter("CF_PetPiggy", "#ffa0c8", "#ffd0e4", "#eb6496", nose="#b8426f")
    ear = m.slot("Ear", "#eb6496")
    for s in (-1, 1):  # perky folded ears
        ear.cone(0.34, 0.6, seg=5, loc=(s * 0.55, -0.05, 2.62), rot=(0.25, s * 0.5, 0))
    snout = m.slot("Snout", "#ff8fb8")
    snout.cyl(0.36, 0.36, 0.3, seg=10, loc=(0, -0.97, 1.6), rot=(math.pi / 2, 0, 0))
    m.slot("Blush", "#ff6f9e").ball(0.16, loc=(0.55, -0.72, 1.6), scale=(1, 0.4, 0.8), seg=6, rings=3)
    m.slot("Blush", "#ff6f9e").ball(0.16, loc=(-0.55, -0.72, 1.6), scale=(1, 0.4, 0.8), seg=6, rings=3)
    tail = m.slot("Tail", "#eb6496")
    for i in range(5):  # little curl
        a = i / 4 * 1.6 * math.pi
        tail.ball(0.1, loc=(math.cos(a) * 0.18, 0.95 + i * 0.05, 1.15 + math.sin(a) * 0.18), seg=5, rings=3)
    return m


def bunny():
    m, body = critter("CF_PetBunny", "#f6f6fa", "#ffffff", "#ffd0dc", nose="#ff7f9a")
    ear = m.slot("Ear", "#f6f6fa")
    inner = m.slot("EarInner", "#ffb0c8")
    for s in (-1, 1):  # tall ears
        ear.ball(0.3, loc=(s * 0.42, 0.0, 3.0), scale=(0.62, 0.42, 2.2), seg=8, rings=6, rot=(0, s * 0.12, 0))
        inner.ball(0.2, loc=(s * 0.42, -0.12, 3.0), scale=(0.5, 0.3, 2.0), seg=7, rings=5, rot=(0, s * 0.12, 0))
    tail = m.slot("Tail", "#ffffff")
    tail.ball(0.38, loc=(0, 0.98, 0.78), seg=8, rings=5)
    cheeks = m.slot("Blush", "#ffb0c8")
    for s in (-1, 1):
        cheeks.ball(0.15, loc=(s * 0.58, -0.7, 1.6), scale=(1, 0.4, 0.8), seg=6, rings=3)
    m.slot("Tooth", "#ffffff").box((0.2, 0.06, 0.2), loc=(0, -0.9, 1.45), bevel=0.02)
    return m


def dragon():
    m, body = critter("CF_PetDragon", "#6ed26e", "#fff0a0", "#4fb04f", nose="#2f7a35")
    horn = m.slot("Horn", "#fff6dc")
    for s in (-1, 1):  # two stubby horns
        horn.cone(0.2, 0.62, seg=6, loc=(s * 0.45, -0.1, 2.72), rot=(0, s * 0.25, 0))
    wing = m.slot("Wing", "#ffc83c")
    for s in (-1, 1):  # small round wings on the back
        wing.ball(0.55, loc=(s * 0.82, 0.55, 1.35), scale=(0.28, 0.9, 1.0), seg=8, rings=5, rot=(0, s * 0.5, 0.2 * s))
    spike = m.slot("Spike", "#ffc83c")
    for i, (y, z) in enumerate(((0.55, 1.78), (0.9, 1.45), (1.12, 1.0), (1.2, 0.55))):
        spike.cone(0.2 - i * 0.02, 0.45, seg=5, loc=(0, y, z), rot=(-0.6 - i * 0.2, 0, 0))
    tail = m.slot("Tail", "#6ed26e")
    tail.ball(0.34, loc=(0, 1.2, 0.35), scale=(0.8, 1.3, 0.8), seg=7, rings=4)
    tail.ball(0.2, loc=(0, 1.85, 0.3), scale=(0.8, 1.2, 0.8), seg=6, rings=4)
    tip = m.slot("Spike", "#ffc83c")
    tip.cone(0.2, 0.4, seg=5, loc=(0, 2.25, 0.3), rot=(-math.pi / 2, 0, 0))
    snout = m.slot("Snout", "#8be38b")
    snout.ball(0.34, loc=(0, -0.85, 1.58), scale=(1.15, 0.8, 0.8), seg=8, rings=5)
    cheeks = m.slot("Blush", "#ff9a7a")
    for s in (-1, 1):
        cheeks.ball(0.14, loc=(s * 0.6, -0.68, 1.62), scale=(1, 0.4, 0.8), seg=6, rings=3)
    return m


def spacecat():
    m, body = critter("CF_PetSpaceCat", "#9682ff", "#d9d0ff", "#6a58d8", nose="#ff7f9a")
    ear = m.slot("Ear", "#9682ff")
    inner = m.slot("EarInner", "#ff9ac0")
    for s in (-1, 1):  # pointy cat ears
        ear.cone(0.42, 0.8, seg=4, loc=(s * 0.6, -0.1, 2.68), rot=(0, s * 0.3, math.pi / 4))
        inner.cone(0.24, 0.5, seg=4, loc=(s * 0.6, -0.22, 2.64), rot=(0, s * 0.3, math.pi / 4))
    whisk = m.slot("Whisker", "#ffffff")
    for s in (-1, 1):
        for dz, tilt in ((0.05, 0.18), (-0.1, -0.1)):
            whisk.box((0.7, 0.04, 0.04), loc=(s * 0.82, -0.78, 1.62 + dz), rot=(0, 0, s * tilt), bevel=0.01)
    collar = m.slot("Collar", "#5adcff")
    collar.cyl(0.78, 0.78, 0.2, seg=12, loc=(0, -0.1, 1.2))
    star = m.slot("Star", "#ffd23a")
    star.cyl(0.04, 0.04, 0.5, seg=5, loc=(0, -0.05, 2.9))
    star.star(0.3, 0.14, 0.12, loc=(0, -0.05, 3.25), rot=(math.pi / 2, 0, 0))
    tail = m.slot("Tail", "#9682ff")
    for i in range(6):  # curly tail
        t = i / 5
        tail.ball(0.2 - 0.02 * i, loc=(0, 1.0 + 0.3 * math.sin(t * math.pi), 0.45 + t * 1.5), seg=6, rings=4)
    m.slot("Stripe", "#6a58d8").box((0.9, 0.05, 0.2), loc=(0, 0.5, 1.65), bevel=0.02)
    return m


MODELS = {
    "CF_PetPuppy": puppy,
    "CF_PetPiggy": piggy,
    "CF_PetBunny": bunny,
    "CF_PetDragon": dragon,
    "CF_PetSpaceCat": spacecat,
}
