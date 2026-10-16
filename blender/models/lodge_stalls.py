"""Prospector Lodge furnishings, main assemblies (docs/lodge/MASTER_PROMPT_Claude_Blender.md sections 7-11).

  Lodge_UpgradesStall     red-and-cream awning stall: counter, back panel, canopy brackets, UPGRADES sign
                          board (blank SignFace), pegboard with the starter hammer
  Lodge_CollectionStall   purple-and-cream awning stall: counter with a glazed lower display, three
                          specimen spots on the counter, COLLECTION sign board (blank SignFace)
  Lodge_HuntBays          three 10 x 10 pads (muted gold trim), low dividers, rear frame, START HUNT sign
                          (blank SignFace), Bay01..03_Interact markers, Emblem / lantern mount points
  Lodge_HuntPad           one pad on its own (reuse), Lodge_BayDivider one low divider
  Lodge_Leaderboard       one board frame used twice (SOLO FINDS, COMPETITIVE WINS): blank BoardFace for a
                          SurfaceGui, trophy mount, crate feet
  Lodge_RubbleSell        small side counter with a back sign board (blank SignFace) and a basket emblem

Origin = floor centre, front = -Y (Roblox -Z), like every kit model. Attachment names and sizes are listed
in docs/lodge/FURNISHING_NOTES.md (with the room placement in Roblox axes).
"""

import math

from mathutils import Vector

import ctrkit as K
from ctrkit import register
from models import _lodgeparts as P
from models._lodgeparts import V, part, attach, collider

S = "L"
R2 = "AssetSheet_02_Upgrades.png"
R3 = "AssetSheet_03_Collection.png"
R4 = "AssetSheet_04_Hunts_Leaderboards.png"

W, D = 24.0, 8.0
Y_FRONT, Y_BACK = -4.0, 4.0
REAR = (3.55, 12.5)
FRONT = (-3.2, 10.55)


def stall_frame(m, awning_b):
    """Back posts, back panel, top beam, canopy brackets, awning and sign shared by both stalls."""
    wood, dark = m.slot("FnWood"), m.slot("FnWoodDark")
    posts = part(m, "Posts", "FnWood")
    py = 3.45
    for sx in (-1, 1):
        x = sx * (W / 2 - 0.5)
        posts.box((0.95, 0.95, 12.7), loc=(x, py, 6.35), bevel=0.1)
        dark.box((1.15, 1.15, 0.3), loc=(x, py, 12.75), bevel=0.06)       # post cap
        dark.box((1.15, 1.15, 0.4), loc=(x, py, 0.2), bevel=0.06)         # post foot
        # canopy bracket: an arm forward under the awning edge + a diagonal knee brace
        posts.box((0.6, py - FRONT[0] + 0.3, 0.45), loc=(x, (py + FRONT[0]) / 2 - 0.15, 10.0), bevel=0.06)
        posts.box_between((x, py - 0.4, 7.4), (x, 0.4, 9.85), (0.5, 0.5), bevel=0.06)
    # back panel (vertical planks) between the posts, and the top beam carrying the awning
    wood.box((W - 1.9, 0.3, 11.6), loc=(0, 3.75, 5.9), bevel=0.06)
    P.plank_seams_y(part(m, "Seams", "FnWoodDark"), -W / 2 + 1, W / 2 - 1, 3.6, 4.2, 11.6, pitch=1.4)
    posts.box((W - 0.2, 0.7, 0.7), loc=(0, py, 12.05), bevel=0.08)
    posts.box((W - 0.2, 0.5, 0.45), loc=(0, FRONT[0] + 0.15, 10.0), bevel=0.06)   # front beam (behind the valance)
    P.awning(m, *awning_b, width=W + 1.0, rear=REAR, front=FRONT, stripes=11)
    # sign on the front fascia, standing over the valance
    P.sign_board(m, 12.0, 3.0, back_y=-3.82, cz=11.25)
    for sx in (-1, 1):   # two short hangers tie the sign back to the front beam
        dark.box((0.35, 0.65, 0.35), loc=(sx * 4.5, -3.5, 10.4), bevel=0.04)
    collider(m, (W, 5.5, 4.0), (0, -1.25, 2.0))
    collider(m, (W, 1.2, 12.7), (0, 3.6, 6.35))


@register("Lodge_UpgradesStall", S, "UPGRADES stall (MASTER sec. 7): 24 wide x 8 deep x 13 tall, counter top z 4, red/cream awning "
          "(AwningA red, AwningB cream, 11 stripes, rear z 12.5 / front z 10.55), blank SignFace 11.5 x 2.5 on the front fascia, "
          "Pegboard 8 x 5 with the starter hammer. Attach: SignFace, Prompt, Cashbox, Basket, Lantern, Runner.",
          ref=(R2, (12, 95, 440, 530)))
def upgrades_stall(m):
    P.counter(m, w=W, d=5.5, h=4.0, y_front=Y_FRONT)
    stall_frame(m, ("FnAwningRed", "FnAwningCream"))
    # pegboard above the counter, against the back panel
    pb = m.piece("Pegboard", "FnPegboard")
    px, pz = -2.0, 7.7
    pb.box((8.0, 0.25, 5.0), loc=(px, 3.47, pz), bevel=0.06)
    trim = part(m, "SignFrame", "FnWoodDark")
    for sz in (-1, 1):
        trim.box((8.3, 0.3, 0.22), loc=(px, 3.45, pz + sz * 2.55), bevel=0.04)
    for sx in (-1, 1):
        trim.box((0.22, 0.3, 5.3), loc=(px + sx * 4.1, 3.45, pz), bevel=0.04)
    dots = part(m, "PegHoles", "FnWoodDark")
    for i in range(9):
        for j in range(5):
            x = px - 3.4 + i * 0.85
            z = pz - 1.9 + j * 0.95
            if -2.1 < x - px < 2.6 and -1.4 < z - pz < 1.6:
                continue   # hidden behind the hammer
            dots.box((0.13, 0.03, 0.13), loc=(x, 3.33, z), bevel=0.0)
    bolt = part(m, "Bolts", "FnMetal")
    for sx in (-1, 1):
        for sz in (-1, 1):
            bolt.bolt((px + sx * 3.75, 3.33, pz + sz * 2.2), normal=(0, -1, 0), r=0.09)
    # starter hammer hung on two pegs, head up-right
    d = Vector((-0.62, 0, -0.78)).normalized()
    head = Vector((px + 1.2, 3.0, pz + 1.25))
    P.hammer(m, head, d, length=3.5)
    for t in (0.9, 2.3):
        peg = head + d * t + Vector((0, 0, -0.23))
        bolt.box((0.12, 0.5, 0.12), loc=(peg.x, 3.1, peg.z), bevel=0.02)
    # attach points
    attach(m, "Prompt", (0, -4.3, 3.0))
    attach(m, "Cashbox", (5.2, -1.6, 4.0))
    attach(m, "Basket", (9.2, -1.5, 4.0))
    attach(m, "Lantern", (-10.6, -2.6, 4.0))
    attach(m, "Tool", (head.x, 3.0, head.z))
    attach(m, "Runner", (0, -8.2, 0))   # floor runner centre in front of the counter (8 studs of access kept)
    m.extra["face"] = "local -Y (Roblox -Z): the counter side players stand at"


@register("Lodge_CollectionStall", S, "COLLECTION stall (MASTER sec. 8): same base as Upgrades with a purple/cream awning "
          "(AwningA purple, AwningB cream), a glazed lower display (Glass piece, Backing, shelf at z 0.95) and three specimen "
          "spots on the counter. Attach: SignFace, Prompt, Specimen1..3 (pedestal spots), Shelf1..3 (tray spots), Lantern.",
          ref=(R3, (5, 50, 560, 455)))
def collection_stall(m):
    cab = (-8.6, 8.6, 0.8, 3.05, 1.7)
    P.counter(m, w=W, d=5.5, h=4.0, y_front=Y_FRONT, cabinet=cab)
    stall_frame(m, ("FnAwningPurple", "FnAwningCream"))
    # shallow display backing behind the counter (warm plaster panel framed in dark wood)
    back = part(m, "Backing", "FnBacking")
    back.box((18.0, 0.12, 4.6), loc=(0, 3.55, 6.9), bevel=0.02)
    trim = part(m, "SignFrame", "FnWoodDark")
    for sz in (-1, 1):
        trim.box((18.4, 0.3, 0.24), loc=(0, 3.5, 6.9 + sz * 2.4), bevel=0.04)
    for sx in (-1, 1):
        trim.box((0.24, 0.3, 5.0), loc=(sx * 9.1, 3.5, 6.9), bevel=0.04)
    for i, x in enumerate((-7.0, 0.0, 7.0)):
        attach(m, "Specimen%d" % (i + 1), (x, -1.3, 4.0))
    for i, x in enumerate((-5.6, 0.0, 5.6)):
        attach(m, "Shelf%d" % (i + 1), (x, Y_FRONT + 0.18 + 0.9, 0.96))
    attach(m, "Prompt", (0, -4.3, 3.0))
    attach(m, "Lantern", (10.6, -2.6, 4.0))
    m.extra["face"] = "local -Y (Roblox -Z): the counter side players stand at"


# ------------------------------------------------------------------ hunt bays

PAD = 10.0
PAD_TOP = 0.12
BAY_X = (-12.0, 0.0, 12.0)
DIV_X = (-18.0, -6.0, 6.0, 18.0)
REAR_Y = 5.6


def pad(m, x, k):
    """One hunt pad at x: charcoal centre + muted gold bevelled trim (top 0.12), corner studs."""
    centre = part(m, "PadCentre", "FnCharcoal")
    trim = part(m, "Trim%d" % k if k else "Trim", "FnPadGold")
    band = 0.55
    centre.box((PAD - 2 * band + 0.02, PAD - 2 * band + 0.02, 0.08), loc=(x, 0, 0.04), bevel=0.0)
    # trim: four bevelled strips sloping down to the floor on the outside
    for sy in (-1, 1):
        trim.box((PAD, band, PAD_TOP), loc=(x, sy * (PAD / 2 - band / 2), PAD_TOP / 2), bevel=0.05, taper=(1.0, 0.7))
    for sx in (-1, 1):
        trim.box((band, PAD - 2 * band, PAD_TOP), loc=(x + sx * (PAD / 2 - band / 2), 0, PAD_TOP / 2), bevel=0.05, taper=(0.7, 1.0))
    stud = part(m, "PadStuds", "FnWoodDark")
    for sx in (-1, 1):
        for sy in (-1, 1):
            stud.cyl(0.16, 0.13, 0.05, seg=8, loc=(x + sx * (PAD / 2 - band / 2), sy * (PAD / 2 - band / 2), PAD_TOP + 0.02))


def divider(m, x, y0=-5.0, y1=REAR_Y, h=3.0, post=None, rail=None):
    """Low wooden divider along Y: square posts with caps, two rails. Stays ~3 high (sightlines open)."""
    post = post or part(m, "Dividers", "FnWood")
    cap = part(m, "Caps", "FnWoodDark")
    rail = rail or post
    for y in (y0, y1):
        post.box((0.75, 0.75, h), loc=(x, y, h / 2), bevel=0.08)
        cap.box((0.95, 0.95, 0.22), loc=(x, y, h + 0.08), bevel=0.05)
    for z in (1.15, 2.35):
        rail.box((0.32, y1 - y0 - 0.5, 0.42), loc=(x, (y0 + y1) / 2, z), bevel=0.06)
    mid = (y0 + y1) / 2
    post.box((0.5, 0.5, 2.6), loc=(x, mid, 1.3), bevel=0.05)


@register("Lodge_HuntBays", S, "Three-bay START HUNT assembly (MASTER sec. 9): 36 wide x 12 deep, pads 10 x 10 at x -12/0/+12 "
          "(top 0.12, PadCentre charcoal, Trim1..3 muted gold), low dividers at x -18/-6/6/18 (3 high), rear frame posts + beam, "
          "18 x 3.5 START HUNT sign (blank SignFace, centre z 11.5) under a timber arch. Attach Bay01..03_Interact (pad centre "
          "top), Bay01..03_Entry, Emblem (crossed-hammer back centre), Lantern1..4 (post fronts). Visual only: the existing hunt "
          "controller owns behaviour.", ref=(R4, (0, 0, 835, 325)))
def hunt_bays(m):
    for k, x in enumerate(BAY_X, 1):
        pad(m, x, k)
    for x in DIV_X:
        divider(m, x)
    posts, dark = part(m, "Frame", "FnWood"), m.slot("FnWoodDark")
    # rear frame: tall posts on the divider lines, a beam across, knee braces, low rear rails per bay
    for x in DIV_X:
        posts.box((1.25, 1.25, 9.6), loc=(x, REAR_Y, 4.8), bevel=0.1)
        dark.box((1.5, 1.5, 0.45), loc=(x, REAR_Y, 0.22), bevel=0.06)
    posts.box((37.6, 1.15, 1.1), loc=(0, REAR_Y, 9.05), bevel=0.1)
    for x in DIV_X:
        for sx in (-1, 1):
            if abs(x + sx * 2.6) > 18.5:
                continue
            posts.box_between((x, REAR_Y - 0.05, 6.9), (x + sx * 2.6, REAR_Y - 0.05, 8.75), (0.45, 0.5), bevel=0.05)
    for bx in BAY_X:
        posts.box((10.8, 0.35, 0.4), loc=(bx, REAR_Y, 1.2), bevel=0.05)
        posts.box((10.8, 0.35, 0.4), loc=(bx, REAR_Y, 2.4), bevel=0.05)
    # sign: two posts up from the beam, sign board, arch over the top
    sign_back = REAR_Y - 0.5
    for sx in (-1, 1):
        posts.box((0.8, 0.8, 4.6), loc=(sx * 7.8, REAR_Y, 11.8), bevel=0.08)
        dark.box((1.0, 1.0, 0.25), loc=(sx * 7.8, REAR_Y, 14.2), bevel=0.05)
    P.sign_board(m, 18.0, 3.5, back_y=sign_back, cz=11.5)
    arch = part(m, "Arch", "FnWood")
    pts = []
    for i in range(9):
        a = i / 8
        x = -7.4 + 14.8 * a
        z = 13.15 + math.sin(math.pi * a) * 1.15
        pts.append((x, z))
    for (x0, z0), (x1, z1) in zip(pts[:-1], pts[1:]):
        arch.box_between((x0, REAR_Y - 0.05, z0), (x1, REAR_Y - 0.05, z1), (0.55, 0.6), bevel=0.05)
    # attach points
    for k, x in enumerate(BAY_X, 1):
        attach(m, "Bay%02d_Interact" % k, (x, 0, PAD_TOP))
        attach(m, "Bay%02d_Entry" % k, (x, -5.0, PAD_TOP))
    attach(m, "Emblem", (0, sign_back - 0.36, 13.55))
    for k, x in enumerate(DIV_X, 1):
        attach(m, "Lantern%d" % k, (x, REAR_Y - 0.5, 6.4))
    for k, x in enumerate(DIV_X, 1):
        attach(m, "PostLamp%d" % k, (x, -5.0, 3.19))
    m.extra["face"] = "local -Y: players walk in from the front edge of each pad"
    for x in DIV_X:
        collider(m, (0.8, 10.6, 3.0), (x, 0.3, 1.5))
    collider(m, (37.2, 1.0, 9.6), (0, REAR_Y, 4.8))


@register("Lodge_HuntPad", S, "One hunt bay pad for reuse: 10 x 10, top 0.12, charcoal PadCentre + muted gold Trim. Attach Interact.",
          ref=(R4, (835, 0, 1250, 325)))
def hunt_pad(m):
    pad(m, 0.0, 0)
    attach(m, "Interact", (0, 0, PAD_TOP))


@register("Lodge_BayDivider", S, "One low hunt-bay divider (10.6 long along Y, 3 high). Attach Lamp (front post top).",
          ref=(R4, (1255, 0, 1671, 325)))
def bay_divider(m):
    divider(m, 0.0, y0=-5.3, y1=5.3)
    attach(m, "Lamp", (0, -5.3, 3.19))
    collider(m, (0.8, 11.4, 3.0), (0, 0, 1.5))


# ------------------------------------------------------------------ leaderboards

@register("Lodge_Leaderboard", S, "World leaderboard frame (MASTER sec. 10), used for SOLO FINDS and COMPETITIVE WINS: 13 wide, "
          "2.5 deep, 17 tall with the trophy. BoardFace (charcoal, 11.5 x 11.1, lower edge z 3.5) is the blank SurfaceGui "
          "face; attach BoardFace (front centre), Trophy (bottom centre of the trophy emblem), Title (header strip).",
          ref=(R4, (836, 330, 1275, 625)))
def leaderboard(m):
    frame, dark = part(m, "Frame", "FnWood"), m.slot("FnWoodDark")
    fw, fh, fz0 = 11.5, 11.1, 3.5
    face = m.piece("BoardFace", "FnCharcoal", note="blank SurfaceGui face (Face = Front)")
    face.box((fw, 0.3, fh), loc=(0, 0.05, fz0 + fh / 2), bevel=0.02)
    frame.box((fw + 0.2, 0.35, fh + 0.2), loc=(0, 0.4, fz0 + fh / 2), bevel=0.04)   # back board
    for sx in (-1, 1):   # side posts
        frame.box((0.85, 1.0, 15.4), loc=(sx * (fw / 2 + 0.42), 0.15, 7.7), bevel=0.1)
        dark.box((1.05, 1.15, 0.3), loc=(sx * (fw / 2 + 0.42), 0.15, 15.45), bevel=0.05)
    frame.box((fw + 1.6, 0.95, 0.7), loc=(0, 0.15, fz0 + fh + 0.33), bevel=0.08)    # header beam
    frame.box((fw + 1.6, 0.95, 0.65), loc=(0, 0.15, fz0 - 0.33), bevel=0.08)        # bottom rail
    # crate feet + braces at the back
    for sx in (-1, 1):
        P.box_crate_feet(m, (sx * 5.35, 0.0, 0.0), 2.3, 2.5, 2.2, m.slot("FnWood"), dark)
        frame.box_between((sx * 6.4, 1.15, 2.2), (sx * 6.4, 0.6, 9.0), (0.4, 0.4), bevel=0.04)
    frame.box((fw - 1.0, 0.5, 0.5), loc=(0, 0.55, 2.4), bevel=0.05)
    # trophy mount plate on the header
    bolt = part(m, "Bolts", "FnMetal")
    for sx in (-1, 1):
        for z in (fz0 - 0.33, fz0 + fh + 0.33):
            bolt.bolt((sx * (fw / 2 + 0.42), -0.36, z), normal=(0, -1, 0), r=0.1)
    attach(m, "BoardFace", (0, -0.1, fz0 + fh / 2))
    attach(m, "Trophy", (0, 0.15, fz0 + fh + 0.68))
    attach(m, "Title", (0, -0.1, fz0 + fh - 1.1))
    m.extra["BoardFaceSize"] = [fw, fh]
    m.extra["face"] = "local -Y (Roblox -Z); SurfaceGui Face = Front on the BoardFace MeshPart"
    collider(m, (13.2, 2.5, 15.0), (0, 0.15, 7.5))


# ------------------------------------------------------------------ rubble sell

@register("Lodge_RubbleSell", S, "Small RUBBLE SELL side counter (MASTER sec. 11): 7 wide x 4 deep x 10 tall, counter top z 3.6, "
          "back sign board (blank SignFace 5.3 x 2.3) and a gold basket Emblem. Attach SignFace, Prompt, Lantern, Basket, Deposit.",
          ref=(R4, (1200, 630, 1671, 941)))
def rubble_sell(m):
    wood, dark = m.slot("FnWood"), m.slot("FnWoodDark")
    P.counter(m, w=7.0, d=2.9, h=3.6, y_front=-2.0, panels=2)
    for sx in (-1, 1):
        part(m, "Posts", "FnWood").box((0.7, 0.7, 9.7), loc=(sx * 3.15, 1.55, 4.85), bevel=0.08)
        dark.box((0.9, 0.9, 0.25), loc=(sx * 3.15, 1.55, 9.8), bevel=0.05)
    wood.box((5.6, 0.3, 6.2), loc=(0, 1.7, 6.6), bevel=0.06)          # back board
    P.plank_seams_y(part(m, "Seams", "FnWoodDark"), -2.8, 2.8, 1.55, 3.7, 9.6, pitch=1.4)
    P.sign_board(m, 5.8, 2.8, back_y=1.5, cz=8.2)
    # basket emblem (gold): flared tub with a band, slats and a handle arc, facing -Y
    gold = part(m, "Emblem", "FnGold")
    bz, by = 5.6, 1.45
    gold.prism([(-0.95, 0.35), (0.95, 0.35), (0.7, -0.6), (-0.7, -0.6)], 0.16, loc=(0, by - 0.08, bz))
    edge = part(m, "EmblemDark", "FnWoodDark")
    for x in (-0.45, 0.0, 0.45):
        edge.box((0.1, 0.04, 0.75), loc=(x, by - 0.18, bz - 0.15), bevel=0.0)
    gold.box((2.15, 0.2, 0.2), loc=(0, by - 0.1, bz + 0.42), bevel=0.04)
    pts = [(math.cos(math.radians(a)) * 0.7, math.sin(math.radians(a)) * 0.6 + 0.5) for a in range(0, 181, 30)]
    for (x0, z0), (x1, z1) in zip(pts[:-1], pts[1:]):
        gold.box_between((x0, by - 0.08, bz + z0), (x1, by - 0.08, bz + z1), (0.14, 0.14), bevel=0.02)
    attach(m, "Prompt", (0, -2.3, 2.8))
    attach(m, "Lantern", (2.6, -0.9, 3.6))
    attach(m, "Basket", (-1.4, -0.5, 3.6))
    attach(m, "Deposit", (0, -0.5, 3.6))
    m.extra["face"] = "local -Y (Roblox -Z)"
    collider(m, (7.0, 3.0, 3.6), (0, -0.55, 1.8))
    collider(m, (7.0, 0.8, 10.0), (0, 1.6, 5.0))
