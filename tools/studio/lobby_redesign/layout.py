"""Lobby redesign plan v2 (real sizes from the Studio dump 2026-10-14). One source of truth for the plan picture,
the overlap check and the Studio build spec. World studs, ground y=0, north = -Z (up in the picture), +X right.
Story: spawn in the south looks straight north at the leaderboard tree (Void Dragon on top) with the Training Tower
castle behind it. FIND (egg pile + queue pads) west, FIGHT (battle ring) east, TRAIN (castle court) north,
HOME (spawn, shops) south; three yards down each side."""
import json, math, random, sys
from shapely.geometry import Point, Polygon, LineString, box
from shapely import affinity

# walkable area (inside the existing collision walls x +-146, z -192..178), rounded corners
WALK = box(-142, -188, 142, 174).buffer(-20).buffer(20)

def face(frm, to):  # yaw deg clockwise from north (-Z) so the object's front looks at `to`
    return round(math.degrees(math.atan2(to[0] - frm[0], -(to[1] - frm[1]))), 1)

items = []

def add(name, kind, pos, r=None, w=None, d=None, yaw=0.0, hook=None, label=None, solid=True, model=None, note=""):
    it = dict(name=name, kind=kind, x=pos[0], z=pos[1], r=r, w=w, d=d, yaw=yaw, hook=hook, label=label,
              solid=solid, model=model, note=note)
    items.append(it)
    return it

def shape(it):
    # world axis boxes, the same test the Studio overlap scan uses (a rotated row's box is bigger than the row)
    return true_shape(it).envelope

TRUE_PAIRS = []

def true_shape(it):
    if it["r"]:
        return Point(it["x"], it["z"]).buffer(it["r"], 32)
    w, d = it["w"], it["d"]
    p = Polygon([(-w / 2, -d / 2), (w / 2, -d / 2), (w / 2, d / 2), (-w / 2, d / 2)])
    p = affinity.rotate(p, it["yaw"], origin=(0, 0))
    return affinity.translate(p, it["x"], it["z"])

C = (0, 0)
# ---------------- centre: SHOP SQUARE (carter 10-15: "in the middle should be the shop / pet index / pet inventory /
# event shop"). Four shop buildings on the diagonals face a small Void Dragon fountain; the spokes come in between.
C = (0, 0)
add("DragonFountain", "knoll", C, r=13, hook="VoidStatueSpot on a pool island (Plinth false, Height 20)", label="")
add("CentrePlaza", "plaza", C, r=37, solid=False).update(ring="8a4fd8")
def shop(name, deg, w, d, hook, label, model):
    a = math.radians(deg)
    p = (round(48 * math.sin(a), 1), round(-48 * math.cos(a), 1))
    add(name, "shop", p, w=w, d=d, yaw=face(p, C), hook=hook, model=model, label=label)
shop("EggShop", 315, 27, 27, "Buildings/EggShop counter (Panel RobuxShop)", "EGG\nSHOP", "ShopRow.ShopEgg")
shop("PetIndexShop", 45, 25, 19, "prompt Panel PetIndex (Collection, Index tab)", "PET\nINDEX", "ShopRow.ShopBook")
shop("MyPetsShop", 225, 24, 23, "prompt Panel MyPets (Collection, Pets tab)", "MY\nPETS", "ShopRow.ShopBackpack")
shop("EventShop", 135, 26, 26, "sign EVENT SHOP - COMING SOON (no prompt yet)", "EVENT\nSHOP", "ShopRow.ShopTower x0.75")
# the hatch stand (coin "Buy Eggs") greets new players beside the main walk, well away from the EGG SHOP hut's prompt
# (round 5: both used R and stood 8 studs apart)
add("HatchStand", "shop", (-24, 102), r=4, yaw=90, hook="Buildings/HatchStand (Buy Eggs prompt), faces the main walk", label="")

# ---------------- south: HOME. spawn looks north into the shop square
SP = (0, 138)
add("SpawnPlaza", "plaza", SP, r=24, solid=False).update(ring="f2c230")
add("LobbySpawn", "spawn", (0, 128), w=8, d=6, hook="FTP_Lobby.LobbySpawn (faces north)", label="SPAWN")
add("StarterEggSpot", "egg", (22, 108), r=6, hook="StarterEggSpot (beside the walk, never on it)", label="free egg")
add("CoinsBoard", "board", (22, 160), w=24, d=6, yaw=face((22, 160), SP), hook="Leaderboards/CoinsBoard", label="")
add("WhatsNewBoard", "board", (-22, 160), w=10, d=3, yaw=face((-22, 160), SP), hook="WhatsNewBoard", label="")

# ---------------- north: TRAIN. castle (47 x 52, door at z -150 faces south), tile court in front
COURT = (0, -112)
add("Lobby_PetTower", "tower", (0, -159), w=47, d=52, yaw=180, hook="LobbyMeadow.Tower (unchanged) + Buildings/TowerEntrance at door z -150",
    model="Lobby_PetTower", label="TRAINING TOWER")
add("TrainCourt", "plaza", COURT, r=22, solid=False).update(ring="2fa7d6")
add("TrainPad", "trainpad", (-17, -116), r=6, hook="BattleArena.TrainPad (attr TrainPad)", label="TRAIN")
add("TowerFloorBoard", "board", (25, -114), w=24, d=6, yaw=-90, hook="Leaderboards/TowerFloorBoard", label="")
add("TowerExit", "spot", (0, -140), w=4, d=4, solid=False, hook="TowerExit (faces south)")

# signposts at the two big junctions (arrows to FIND / FIGHT / TRAIN / SHOPS / YARDS)
add("SpawnRosette", "spot", (0, 140), r=6.5, hook=None, label="")  # round 22: keeps lawn bushes off the spawn rosette
add("SignpostSpawn", "prop", (-19, 113), r=5,  # round 21: r=5 keeps lamps out from under its arms
    model="P_SignPost", label="")

# water: two round ponds flanking the castle (round 6 runner: add water)
add("PondWest", "pond", (-44, -152), r=10, label="")
add("PondEast", "pond", (44, -152), r=10, label="")

# ---------------- west: FIND. egg pile, 4 queue pads in an arc facing the tree
HUNT = (-108, -36)
add("HuntPlaza", "plaza", (-98, -36), r=24, solid=False).update(ring="f0a020")
add("EggPile", "pile", HUNT, r=13, label="EGG PILE\nPLAY HUNT", model="egg pile (hunt eggs, decor)")
for i, deg in enumerate((-75, -35, 35, 75)):
    a = math.radians(deg)
    p = (round(HUNT[0] + 25 * math.cos(a), 1), round(HUNT[1] + 25 * math.sin(a), 1))
    add(f"QueuePad{i+1}", "pad", p, r=5, hook=f"QueuePads/QueuePad{i+1} (+Countdown)", label=str(i + 1))
add("QueueBoard", "board", (-132, -36), w=14, d=3, yaw=90, hook="QueueBoard / PlayBanner", label="")

# ---------------- east: FIGHT. stone battle ring, PvpPad in the middle, boards behind
BAT = (104, -36)
add("BattlePlaza", "plaza", (98, -36), r=24, solid=False).update(ring="e0443a")
add("BattleRing", "battlering", BAT, r=15, hook="BattleArena.BattlePad (attr PvpPad) at centre", label="BATTLE")
add("FightBoard", "board", (133, -36), w=16, d=3, yaw=-90, hook="FightBoard", label="")
add("RarestPetBoard", "board", (112, -74), w=24, d=6, yaw=face((112, -74), BAT), hook="Leaderboards/RarestPetBoard", label="")

# ---------------- yards: 3 west, 3 east, gates face the middle lane
PLOT_W, PLOT_D = 59, 59  # after the 90 deg turn: 53 across (x), 57 along (z)
for i, (x, z) in enumerate(((-104, 106), (104, 106), (-104, 38), (104, 38), (-104, -126), (104, -126))):  # Plot1-2 nearest spawn
    add(f"Plot{i+1}", "plot", (x, z), w=PLOT_W, d=PLOT_D, hook=f"Plots/Plot{i+1} (gate faces {'east' if x < 0 else 'west'})",
        label=f"YARD {i+1}")


# ---------------- hangout hooks kept (LobbyHangout): a campfire nook, the whack stump, event lawns, secret eggs
add("CampfireNook", "nook", (42, 90), r=12, hook="Hooks.Seats: Campfire + CampfireLog1-3 + Bench1-4 round it", label="campfire")
add("WhackStump", "game", (-40, 74), r=5, hook="Hooks.Games.WhackStump", label="whack")
add("EventSpot1", "event", (-30, -70), r=8, hook="Hooks.Events.EventSpot1 (open lawn)")
add("EventSpot2", "event", (30, -70), r=8, hook="Hooks.Events.EventSpot2 (open lawn)")
add("EventSpot3", "event", (0, 72), r=6, solid=False, hook="Hooks.Events.EventSpot3 (lawn beside the main walk)")
for i, p in enumerate(((-116, -180), (104, 172), (-104, 172), (66, -184), (-60, -184))):  # round 22: eggs 2-3 clear of the tower buttresses
    add(f"HiddenEgg{i+1}", "secret", p, r=1, hook=f"Hooks.Secrets.HiddenEgg{i+1} (tucked by the wall)")
add("SecretEgg", "secret", (132, -88), r=1, hook="Buildings/SecretEgg (badge egg)")
add("PlayBanner", "spot", (-108, -36), w=1, d=1, solid=False, hook="QueuePads.PlayBanner, 22 up over the pile")

# ---------------- zone arches: big sign over each spoke where it enters its zone (posts are the footprint)
ARCHES = [("FIND", "f0a020", (-76, -35.5), 90), ("FIGHT", "e0443a", (76, -35.5), 90), ("TRAIN", "2fa7d6", (0, -90), 0)]  # hero gates: posts +-13, opening 21
for text, col, (ax, az), yaw in ARCHES:
    a = math.radians(yaw)
    ox, oz = math.cos(a) * 13, math.sin(a) * 13  # posts 9 left/right across the path
    add(f"Arch{text}_L", "archpost", (round(ax - ox, 1), round(az - oz, 1)), r=3, label=text)
    add(f"Arch{text}_R", "archpost", (round(ax + ox, 1), round(az + oz, 1)), r=3, label=text)

# ---------------- paths (name, width, points): curvy, every one ends at a real place
paths = [
    ("Main", 24, [(0, 116), (6, 102), (7, 86), (-2, 66), (0, 50), (0, 35)]),
    ("ToTower", 18, [(0, -35), (0, -48), (-5, -62), (-3, -78), (0, -92)]),
    ("ToHunt", 18, [(-35, 0), (-48, 0), (-56, -14), (-63, -27), (-70, -34), (-78, -36)]),
    ("ToBattle", 18, [(35, 0), (48, 0), (56, -14), (63, -27), (70, -34), (78, -36)]),
    ("WestLane", 14, [(-62, -138), (-64, -112), (-62, -90), (-61, -64), (-61, -10), (-63, 18), (-64, 40), (-62, 70), (-63, 100), (-54, 120), (-38, 124), (-22, 128)]),
    ("EastLane", 14, [(62, -138), (64, -112), (62, -90), (61, -64), (61, -10), (63, 18), (64, 40), (62, 70), (63, 100), (54, 120), (38, 124), (22, 128)]),
    ("WestLoop", 11, [(-16, 57), (-40, 62), (-62, 60)]),
    ("EastLoop", 11, [(16, 57), (40, 62), (62, 60)]),
    ("CourtWest", 11, [(-20, -112), (-44, -118), (-62, -124)]),
    ("CourtEast", 11, [(20, -112), (44, -118), (62, -124)]),
]
# a short spur from the lane into every yard gate (gates face the lanes; front fence at x -+74.5)
for k, (x, z) in enumerate(((-104, 106), (104, 106), (-104, 38), (104, 38), (-104, -126), (104, -126))):
    sg = 1 if x < 0 else -1
    paths.append((f"Yard{k+1}", 7, [(-sg * 62, z), (-sg * 66, z), (-sg * 69.5, z)]))  # ends at the gate, clear of the yard soil

def path_shape(w, pts):
    return LineString(pts).buffer(w / 2, 8)

PATHS = [(n, w, pts, path_shape(w, pts)) for n, w, pts in paths]
ENDS_OK = {"nook", "game", "spawn", "pad", "trainpad", "egg", "battlering", "tower", "pile", "knoll", "plot", "shop", "board"}

def problems_for(it, others, gap=2.0):
    bad = []
    sh = shape(it)
    for o in others:
        if o is it or not o["solid"] or (o["kind"] == "cliff" and it["kind"] == "cliff"):
            continue
        dd = sh.distance(shape(o))
        if {it["name"], o["name"]} in TRUE_PAIRS or {it["kind"], o["kind"]} == {"shop", "prop"}:  # round 16: a shop's 45-degree box is far bigger than the hut  # meant to stand together: real footprints, not world boxes
            dd = true_shape(it).distance(true_shape(o))
        if dd < gap:
            bad.append((it["name"], o["name"], round(dd, 1)))
    sh_true = true_shape(it)  # flat paths don't block in the Studio box scan; test the real footprint against them
    for n, w, pts, ps in PATHS:
        if not ps.intersects(sh_true):
            continue
        ends = Point(pts[-1]).buffer(w).intersects(sh_true) or Point(pts[0]).buffer(w).intersects(sh_true)
        if it["kind"] in ENDS_OK and ends and ps.intersection(sh_true).area < w * 14:
            continue
        bad.append((it["name"], "path " + n, round(ps.intersection(sh_true).area, 1)))
    if it["kind"] != "cliff" and not WALK.contains(sh):
        bad.append((it["name"], "outside walk area", 0))
    return bad

def all_problems():
    bad = []
    solids = [i for i in items if i["solid"]]
    for k, it in enumerate(solids):
        bad += problems_for(it, solids[k + 1:])
    return bad

CLIFF = {"Cliff_Natural_A": (22.3, 11.8), "Cliff_Natural_B": (25.3, 13.9)}
def place_cliffs():
    rng = random.Random(21)
    def run(x0, z0, x1, z1, yaw):
        n = int(math.dist((x0, z0), (x1, z1)) / 16)  # round 17: smaller cliffs, closer together
        for k in range(n + 1):
            t = k / n
            m = rng.choice(list(CLIFF))
            sc = round(rng.uniform(0.8, 1.0), 2)  # round 17: lower walls (runner: they hid the hills)
            add(f"Cliff{len(items)}", "cliff", (round(x0 + (x1 - x0) * t + rng.uniform(-2, 2), 1), round(z0 + (z1 - z0) * t + rng.uniform(-2, 2), 1)),
                w=round(CLIFF[m][0] * sc, 1), d=round(CLIFF[m][1] * sc, 1), yaw=round(yaw + rng.uniform(-12, 12), 1), model=m).update(scale=sc)
    run(-152, -184, -152, 170, 90)
    run(152, -184, 152, 170, -90)
    run(-138, -199, 138, -199, 180)
    run(-138, 186, 138, 186, 0)
    # round 15: the corner watchtowers stand inside the cliff line on the ground plate (round 14 had them buried in
    # the cliffs at +-152), 1.45x tall (about 35 studs) so they clear the 19-28 stud cliff tops
    # round 16: 1.9x (about 46 tall, runner: "~50% taller") and a little further in so the wider base stays on the plate
    for c in ((-131, -170), (131, -170), (-131, 163), (131, 163)):
        add(f"Cliff{len(items)}", "cliff", c, w=21.7, d=21.7, yaw=180 if c[1] < 0 else 0, model="WallTower_Stone_v1").update(scale=1.9)  # square to the walls (a turned box needs more room)

def place_decor():
    rng = random.Random(11)
    kit = {"Tree_Round_B_v2": (10.2, 9.2), "Tree_DarkGreen": (10.1, 8.5), "Tree_Olive": (9.7, 8.2),
           "Tree_AutumnOrange": (10.2, 8.4), "Tree_Pine_B_v2": (8.5, 8.6), "Tree_Pine_A_v2": (6.1, 6.7), "Tree_Round_S_v2": (5.8, 4.9)}
    trees = [(k, round(math.hypot(*v) / 2, 2)) for k, v in kit.items()]
    def fits(it, gap=3.0):
        if problems_for(it, items, gap):
            return False
        items.append(it)
        return True
    # zone foliage: the Blender colour variants (the runtime falls back to the old species if they're not imported yet)
    ZONE = {"FIGHT": ["Tree_Round_Autumn_v1"], "TRAIN": ["Tree_Round_BlueGreen_v1", "Tree_Pine_B_v2"], "FIND": ["Tree_Round_Golden_v1"]}
    kit.update({"Tree_Round_Autumn_v1": (10.2, 9.2), "Tree_Round_BlueGreen_v1": (10.2, 9.2), "Tree_Round_Golden_v1": (10.2, 9.2)})
    def zone_pick(x, z, default):
        zn = "FIGHT" if x > 55 and -90 < z < 20 else "FIND" if x < -55 and -90 < z < 20 else "TRAIN" if z < -95 else None
        if not zn:
            return default
        m = rng.choice(ZONE[zn])
        return (m, round(math.hypot(*kit[m]) / 2, 2))
    def tree(n, x, z, k, sc=1.0):
        k = zone_pick(x, z, k)
        return dict(name=f"Tree{n}", kind="tree", x=round(x, 1), z=round(z, 1), r=round(k[1] * sc, 2), w=None, d=None,
                    yaw=round(rng.uniform(0, 360)), hook=None, label=None, solid=True, model=k[0], note="", scale=round(sc, 2))
    n = 0
    for _ in range(3000):  # tree belt along the walls
        if n >= 70:
            break
        edge = rng.choice(["W", "E", "N", "S"])
        if edge in "WE":
            x, z = (-1 if edge == "W" else 1) * rng.uniform(131, 137), rng.uniform(-180, 168)
        else:
            x, z = rng.uniform(-130, 130), (rng.uniform(-182, -176) if edge == "N" else rng.uniform(166, 170))
        if fits(tree(n, x, z, rng.choice(trees), rng.uniform(1.0, 1.35))):
            n += 1
    # a few tidy groves (2-4 trees each) in the open lawns; the rest of the lawn stays open
    groves = [(-40, 102), (44, 100), (-84, 8), (84, 8), (-84, -84), (84, -84), (-34, -100), (34, -98),
              (-22, -50), (22, -50), (-46, 18), (46, 18), (-30, 82), (100, 76), (-100, 76), (100, -94), (-100, -94)]
    for gx, gz in groves:
        placed = 0
        for _ in range(200):
            if placed >= 3:
                break
            a, r = rng.uniform(0, 6.28), rng.uniform(0, 12)
            if fits(tree(n, gx + r * math.cos(a), gz + r * math.sin(a), rng.choice(trees[:4] + trees[6:]), rng.uniform(0.9, 1.2)), gap=2.5):
                n += 1
                placed += 1
    # lawn features: a flower bed, a bush trio or a rock every ~24 studs where the lawn is open
    feats = [("FlowerBed_Big_Mixed", 5.8), ("Bush_Round_A_v2", 2.4), ("Bush_Blossom_v2", 2.5), ("Rock_Natural_A", 3.9),
             ("Bush_Round_B_v2", 2.4), ("FlowerBed_Big_Mixed", 5.8), ("Bush_Round_A_v2", 2.4)]
    for gx in range(-130, 131, 13):  # round 27: denser (runner: bare grass)
        for gz in range(-178, 167, 13):
            x, z = gx + rng.uniform(-6, 6), gz + rng.uniform(-6, 6)
            m, r = rng.choice(feats)
            fits(dict(name=f"Feat{len(items)}", kind="feature", x=round(x, 1), z=round(z, 1), r=r, w=None, d=None,
                      yaw=round(rng.uniform(0, 360)), hook=None, label=None, solid=True, model=m, note=""), gap=3.0)

PLAZA_PROPS = {
    # round 16: the Blender market stalls go on the north half of the square, clear of the spawn's view of the dragon
    "CentrePlaza": ["P_FruitStall", "P_PetStatue", "P_Bench_Wood", "P_Planter", "P_Planter", "P_Bench_Wood", "P_TreatStall", "P_PetStatue"],
    "SpawnPlaza": ["P_BalloonCart", "P_PetStatue", "P_Bench_Wood", "P_PetStatue", "P_Bench_Wood", "P_Planter", "P_Planter"],
    "HuntPlaza": ["P_EggCrate", "P_HayBale", "P_EggCrate", "P_HayBale", "P_EggCrate"],
    "BattlePlaza": ["P_Brazier"] * 4 + ["P_Bench_Stone"], "TrainCourt": ["P_StonePlanter"] * 4,
}
PROP_R = {"P_FruitStall": 5.1, "P_TreatStall": 4.4, "P_BalloonCart": 3.5, "P_PetStatue": 4.3, "P_Bench_Wood": 3.4, "P_Planter": 2.6, "P_EggCrate": 2.4, "P_HayBale": 2.4, "P_Brazier": 1.8, "P_Brazier_Blue": 1.8,
          "P_Bench_Stone": 3.2, "P_StonePlanter": 2.6, "P_PetBowl": 1.3, "P_PetBall": 1.0}
def place_props():
    def fits(it, gap):
        if problems_for(it, items, gap):
            return False
        items.append(it)
        return True
    for pz in [i for i in items if i["kind"] == "plaza"]:
        want = PLAZA_PROPS.get(pz["name"], [])
        placed = 0
        radii = (23, 20) if pz["name"] == "CentrePlaza" else (pz["r"] + 4, pz["r"] - 3)
        angs = (22.5, 67.5, 112.5, 157.5, 202.5, 247.5, 292.5, 337.5) if pz["name"] == "CentrePlaza" else range(0, 360, 10)
        for rr in radii:
            for deg in angs:
                if placed >= len(want):
                    break
                m = want[placed]
                a = math.radians(deg + (0 if pz['name'] == 'CentrePlaza' else placed * 37 % 10))
                p = (round(pz["x"] + rr * math.sin(a), 1), round(pz["z"] - rr * math.cos(a), 1))
                inside = rr < pz["r"]
                yaw = face(p, (pz["x"], pz["z"])) + (0 if inside or not m.startswith("Bench") else 0)
                if fits(dict(name=f"Prop_{pz['name']}_{placed}", kind="prop", x=p[0], z=p[1], r=PROP_R[m], w=None, d=None, yaw=yaw,
                             hook=None, label=None, solid=True, model=m, note=""), 2.5 if not inside or pz["name"] == "CentrePlaza" else 4.0):
                    placed += 1
                    if pz["name"] != "CentrePlaza":
                        pass
        print(f"  props {pz['name']}: {placed}/{len(want)}")
    # pet bowls and balls by each yard gate, on the lawn between the lane and the fence
    for k in range(1, 7):
        pl = [i for i in items if i["name"] == f"Plot{k}"][0]
        sg = 1 if pl["x"] < 0 else -1
        for j, (m, dz) in enumerate((("P_Planter", -11), ("P_Bench_Wood", 12))):  # round 25: bowls/balls read as loose discs
            fits(dict(name=f"Yard{k}_{m}_{j}", kind="prop", x=round(-sg * 71.2, 1), z=pl["z"] + dz, r=PROP_R[m], w=None, d=None,
                      yaw=90 * sg, hook=None, label=None, solid=True, model=m, note=""), 1.2)

def place_accents():
    rng = random.Random(5)
    def fits(it, gap):
        if problems_for(it, items, gap):
            return False
        items.append(it)
        return True
    # flower rows lining the main walk and the four spokes (alternating red / yellow / purple), and lamps
    cols = ["FlowerRow_Red", "FlowerRow_Yellow", "FlowerRow_Purple"]
    for pname, w, pts in paths[:8]:
        dense = []
        for (x1, z1), (x2, z2) in zip(pts, pts[1:]):
            L = math.hypot(x2 - x1, z2 - z1)
            k = 0
            while k * 13 + 6 < L:
                t = (k * 13 + 6) / L
                dense.append((x1 + (x2 - x1) * t, z1 + (z2 - z1) * t, (x2 - x1) / L, (z2 - z1) / L))
                k += 1
        for i, (x, z, dx, dz) in enumerate(dense):
            yaw = math.degrees(math.atan2(dx, -dz)) + 90
            for side in (1, -1):
                nx, nz = -dz * side, dx * side
                if i % 2 == 0:  # lamps and flower rows take turns down both sides of the walk
                    q = (x + nx * (w / 2 + 2.4), z + nz * (w / 2 + 2.4))
                    fits(dict(name=f"Lamp_{pname}_{i}_{side}", kind="lamp", x=round(q[0], 1), z=round(q[1], 1), r=1.4, w=None,
                              d=None, yaw=0, hook=None, label=None, solid=True, model="LampPost_Yellow", note=""), 2.0)  # built at 0.75 scale
                else:
                    p = (x + nx * (w / 2 + 2.0), z + nz * (w / 2 + 2.0))
                    fits(dict(name=f"Row_{pname}_{i}_{side}", kind="flowerrow", x=round(p[0], 1), z=round(p[1], 1), r=None,
                              w=12.3, d=2.1, yaw=round(yaw, 1), hook=None, label=None, solid=True, model=cols[(i + (side > 0)) % 3], note=""), 2.0)
def place_zone_kit():
    """round 18: the Blender kit 1015b pieces that need room on the plan (hatch nest + hunt board in FIND, straw dummies
    round the FIGHT ring). Each takes the first candidate spot that clears everything by 3 studs."""
    def first(name, model, r, cands, yaw_to):
        for c in cands:
            it = dict(name=name, kind="prop", x=round(c[0], 1), z=round(c[1], 1), r=r, w=None, d=None, yaw=face(c, yaw_to),
                      hook=None, label=None, solid=True, model=model, note="")
            if not problems_for(it, items, 3.0):
                items.append(it)
                return it
        print("  no room for", name)
    ring = lambda cx, cz, rr, degs: [(cx + rr * math.sin(math.radians(d)), cz - rr * math.cos(math.radians(d))) for d in degs]
    first("HatchNest", "P_HatchNest", 6.7, ring(-108, -36, 33, range(200, 340, 10)) + ring(-108, -36, 37, range(180, 360, 10)), (-108, -36))
    first("HuntBoard", "P_HuntBoard", 3.6, [(-118, -66), (-134, -58), (-134, -14)], (-108, -36))
    n = 0
    for c in ring(104, -36, 21, range(0, 360, 15)):
        if n >= 4:
            break
        if first(f"Dummy{n}", "P_Dummy", 1.6, [c], (104, -36)):
            n += 1
    print("  dummies", n)
    # round 19 (runner: "stalls ringing the shop square"): more market stalls on the square's outer ring, between the
    # shops and the side walks, never on the south side (the spawn's view of the dragon)
    for j, deg in enumerate((72, 108, 252, 288, 18, 342)):
        m = ("P_FruitStall", "P_TreatStall")[j % 2]
        cands = ring(0, 0, 44, (deg, deg + 4, deg - 4)) + ring(0, 0, 46, (deg, deg + 4, deg - 4))
        first(f"RingStall{j}", m, PROP_R[m], cands, (0, 0))

if __name__ == "__main__":
    place_cliffs()
    core = all_problems()
    print("core overlaps:", len(core))
    for b in core:
        print("  ", b)
    place_props()
    place_zone_kit()
    place_accents()
    place_decor()
    bad = all_problems()
    json.dump({"items": items, "paths": paths}, open(sys.argv[1] if len(sys.argv) > 1 else "layout.json", "w"), indent=1)
    from collections import Counter
    print("items", len(items), dict(Counter(i["kind"] for i in items)))
    print("final overlaps:", len(bad))
    for b in bad:
        print("  ", b)
