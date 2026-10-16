"""Sheet 08: Manual tool kit (starter hammer, steel hammer, jackhammer).

Origins (the hand point, where the player's grip attaches):
  Tool_StarterHammer / Tool_SteelHammer: origin = centre of the rubber grip; the handle runs up +Z
    (Roblox +Y) and the head sits at the top, striking faces along X. attach Strike = striking face.
  Tool_Jackhammer: origin = centre of the handlebar (both hands); body and bit hang down -Z
    (Roblox -Y). The Bit piece is separate (anim Plunge: slides along its axis); attach Tip = bit point.
"""

import math

from mathutils import Vector

from ctrkit import register

S08 = "08"
REF = "08_manual_tool_kit.png"


def chamfer_head(piece, length, side, loc, chamfer=0.22):
    """Hammer head: box along X with big 45-degree chamfers on its four long edges (octagonal ends)."""
    c = side * chamfer
    h = side / 2
    prof = [(-h + c, -h), (h - c, -h), (h, -h + c), (h, h - c), (h - c, h), (-h + c, h), (-h, h - c), (-h, -h + c)]
    # prism extrudes along Y; turn it so the length runs along X
    piece.prism(prof, length, loc=loc, rot=(0, 0, 90), bevel=0.03)


def grip(m, z0, z1, r=0.2):
    """Rubber grip with ridges between z0..z1 and amber rings at both ends."""
    rub, ring = m.slot("Rubber"), m.slot("Amber")
    n = 4
    seg = (z1 - z0) / n
    for i in range(n):
        zc = z0 + seg * (i + 0.5)
        rub.box((r * 2, r * 2, seg - 0.05), loc=(0, 0, zc), bevel=0.07)
    rub.box((r * 1.7, r * 1.7, z1 - z0), loc=(0, 0, (z0 + z1) / 2), bevel=0.04)
    for z in (z0 - 0.07, z1 + 0.06):
        ring.box((r * 2 + 0.08, r * 2 + 0.08, 0.13), loc=(0, 0, z), bevel=0.035)
    rub.box((r * 2, r * 2, 0.16), loc=(0, 0, z0 - 0.21), bevel=0.06)  # end knob


def hammer(m, steel_head=False):
    wood = m.slot("Wood")
    g0, g1 = -0.8, 0.8              # grip (origin in the middle)
    top = 2.85                       # head centre height
    grip(m, g0, g1, r=0.25)
    wood.box((0.34, 0.38, top - g1), loc=(0, 0, (g1 + top) / 2), bevel=0.05, taper=(0.9, 0.9))
    if steel_head:
        dark, face = m.slot("FrameDark"), m.slot("Steel")
        chamfer_head(dark, 1.15, 0.88, (0, 0, top), chamfer=0.18)
        for sx in (-1, 1):
            chamfer_head(face, 0.38, 1.02, (sx * 0.74, 0, top), chamfer=0.2)
            m.slot("SteelLight").box((0.06, 0.7, 0.7), loc=(sx * 0.95, 0, top), bevel=0.02)
        dark.box((0.5, 0.95, 0.12), loc=(0, 0, top - 0.48), bevel=0.03)  # collar
        L = 1.95
    else:
        head = m.slot("Steel")
        chamfer_head(head, 1.7, 0.9, (0, 0, top), chamfer=0.22)
        for sx in (-1, 1):
            m.slot("SteelLight").box((0.08, 0.6, 0.6), loc=(sx * 0.87, 0, top), bevel=0.02)
        L = 1.8
    m.attach["Strike"] = (L / 2, 0, top)
    m.attach["Grip"] = (0, 0, 0)
    m.extra["origin"] = "grip centre; handle up +Y, head striking faces along X"


@register("Tool_StarterHammer", S08, "Starter hammer: steel chamfered head, wood handle, ridged rubber grip with amber rings; origin = grip centre.",
          ref=(REF, (20, 150, 425, 455)))
def starter_hammer(m):
    hammer(m)


@register("Tool_SteelHammer", S08, "Steel hammer: dark steel head with polished end caps, wood handle, rubber grip; origin = grip centre.",
          ref=(REF, (440, 150, 845, 455)))
def steel_hammer(m):
    hammer(m, steel_head=True)


@register("Tool_Jackhammer", S08, "Jackhammer: amber body, two black grips on a crossbar, vents, hose stub, silver bit (separate Bit piece); origin = handlebar centre.",
          ref=(REF, (855, 150, 1525, 455)))
def jackhammer(m):
    amber, rub, dark, steel = m.slot("Amber", "SmoothPlastic"), m.slot("Rubber"), m.slot("FrameDark"), m.slot("SteelLight")
    bit = m.piece("Bit", "SteelLight", anim="Plunge", pivot=(0, 0, -3.1), note="drill bit; slides along Roblox Y for the hammering motion")
    # handlebar (origin): one continuous steel bar through the body, rubber grip sleeves on both ends
    dark.box((3.5, 0.3, 0.3), loc=(0, 0, 0), bevel=0.06)
    dark.box((1.2, 0.38, 0.38), loc=(0, 0, 0), bevel=0.06)
    for sx in (-1, 1):
        rub.box((1.1, 0.4, 0.4), loc=(sx * 1.17, 0, 0), bevel=0.08)            # sleeve
        for i in range(3):                                                    # ridges on the sleeve
            rub.box((0.16, 0.46, 0.46), loc=(sx * (0.8 + i * 0.36), 0, 0), bevel=0.06)
        rub.box((0.18, 0.5, 0.5), loc=(sx * 1.76, 0, 0), bevel=0.07)          # end cap
    # body: chunky amber block with chamfered corners, narrowing at the bottom
    body_top, body_bot = -0.15, -1.85
    amber.box((1.15, 0.95, 0.45), loc=(0, 0, body_top - 0.22), bevel=0.12)
    amber.box((1.25, 1.0, 1.05), loc=(0, 0, -0.95), bevel=0.14, taper=(1.0, 1.0))
    amber.box((1.0, 0.85, 0.42), loc=(0, 0, body_bot + 0.3), bevel=0.1, taper=(1.18, 1.12))
    # dark side panels and front vent slots
    for sx in (-1, 1):
        dark.box((0.08, 0.7, 1.0), loc=(sx * 0.64, 0, -0.95), bevel=0.03)
    for i in range(3):
        dark.box((0.62, 0.06, 0.09), loc=(0, -0.51, -0.62 - i * 0.2), bevel=0.02)
    dark.box((0.9, 0.08, 0.1), loc=(0, -0.48, -1.47), bevel=0.02)
    # collar + chuck
    dark.box((0.78, 0.72, 0.3), loc=(0, 0, body_bot - 0.05), bevel=0.06)
    dark.cyl(0.3, 0.26, 0.35, seg=8, loc=(0, 0, body_bot - 0.36))
    # hose stub with a steel coupling, out of the right side going back
    hz = -1.2
    steel.cyl(0.13, 0.13, 0.22, seg=8, loc=(0.75, 0.15, hz), rot=(0, 90, 0))
    rub.tube([(0.86, 0.15, hz), (1.15, 0.3, hz - 0.15), (1.35, 0.55, hz - 0.55), (1.4, 0.75, hz - 1.0)], 0.1, seg=8)
    # bit: hex shank + chisel point
    bt = body_bot - 0.55
    # one solid bit: collar inside the chuck, hex shank, point (cone tip pointing down), all overlapping
    bit.cyl(0.2, 0.2, 0.3, seg=6, loc=(0, 0, bt + 0.05))
    bit.cyl(0.16, 0.16, 1.0, seg=6, loc=(0, 0, bt - 0.45))
    bit.cyl(0.165, 0.0, 0.62, seg=6, loc=(0, 0, bt - 1.24), rot=(180, 0, 0))
    m.attach["Tip"] = (0, 0, bt - 1.55)
    m.attach["Grip"] = (0, 0, 0)
    m.attach["HoseEnd"] = (1.4, 0.75, hz - 1.0)
    m.extra["origin"] = "handlebar centre; body and bit hang down -Y"
    _ = (math, Vector)
