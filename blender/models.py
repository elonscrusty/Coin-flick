"""COIN FLICK sample models. Each builder returns a Model; colours here are defaults, the game tints pieces by slot."""

import math

from cfkit import Model

TAU = math.tau


def coin():
    """Chunky gold coin lying flat: 3 wide, 0.8 thick, origin = centre. Star on top (heads), ring underneath."""
    m = Model("CF_Coin")
    rim = m.slot("Rim", "#e89a00")
    rim.cyl(1.5, 1.5, 0.8, seg=20, bevel=0.07)
    # raised bead ring just inside the rim
    for i in range(20):
        a = i / 20 * TAU
        rim.ball(0.1, loc=(math.cos(a) * 1.3, math.sin(a) * 1.3, 0.42), seg=5, rings=3)
    face = m.slot("Face", "#ffd23a")
    face.cyl(1.32, 1.32, 0.86, seg=20, bevel=0.03)
    mark = m.slot("Mark", "#8a4a00")
    mark.star(0.82, 0.38, 0.12, loc=(0, 0, 0.47))
    mark.cyl(0.55, 0.55, 0.1, seg=12, loc=(0, 0, -0.45))
    return m


def table():
    """Round coin table: top r 9, total height 3.6, origin = floor centre."""
    m = Model("CF_Table")
    top = m.slot("Top", "#d6965a")
    top.cyl(8.6, 8.6, 0.7, seg=24, loc=(0, 0, 3.25), bevel=0.05)
    rim = m.slot("Rim", "#96602f")
    rim.cyl(9.0, 9.0, 1.0, seg=24, loc=(0, 0, 3.0), bevel=0.12)
    trim = m.slot("Trim", "#ffd23a")
    for i in range(16):
        a = i / 16 * TAU
        trim.ball(0.28, loc=(math.cos(a) * 9.0, math.sin(a) * 9.0, 3.25), seg=5, rings=3)
    legs = m.slot("Legs", "#78502a")
    for i in range(4):
        a = i / 4 * TAU + TAU / 8
        x, y = math.cos(a) * 6.4, math.sin(a) * 6.4
        legs.cyl(0.85, 0.65, 2.6, seg=8, loc=(x, y, 1.3), bevel=0.05)
        legs.cyl(1.25, 1.25, 0.35, seg=8, loc=(x, y, 0.18), bevel=0.04)
    legs.cyl(1.2, 1.2, 0.5, seg=10, loc=(0, 0, 2.7))
    return m


def tree():
    """Round cartoon tree, about 9 tall, origin = base centre."""
    m = Model("CF_Tree")
    bark = m.slot("Bark", "#8a5a30")
    bark.cyl(0.95, 0.6, 3.4, seg=7, loc=(0, 0, 1.7), bevel=0.05)
    bark.cyl(1.25, 1.25, 0.5, seg=7, loc=(0, 0, 0.25))
    leaf = m.slot("Leaf", "#58c944")
    leaf2 = m.slot("LeafLight", "#8fe05a")
    blobs = [
        ((0, 0, 5.0), 2.9, leaf),
        ((-1.9, 0.3, 4.2), 2.1, leaf),
        ((1.9, -0.2, 4.4), 2.2, leaf),
        ((0.2, 1.8, 4.3), 2.0, leaf),
        ((0.1, -1.8, 4.1), 2.0, leaf),
        ((-0.8, 0.3, 6.6), 2.2, leaf2),
        ((1.0, -0.4, 6.4), 1.9, leaf2),
        ((0, 0, 7.6), 1.4, leaf2),
    ]
    for loc, r, piece in blobs:
        piece.ball(r, loc=loc, scale=(1, 1, 0.9), seg=8, rings=5)
    fruit = m.slot("Fruit", "#ff4f5e")
    for a, z in ((0.3, 4.1), (2.4, 5.0), (4.2, 4.4), (5.5, 5.6)):
        fruit.ball(0.32, loc=(math.cos(a) * 2.9, math.sin(a) * 2.9, z), seg=6, rings=4)
    return m


MODELS = {"CF_Coin": coin, "CF_Table": table, "CF_Tree": tree}
