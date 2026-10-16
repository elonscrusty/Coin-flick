"""layout.json -> build_lobby.luau (Studio Edit-mode command-bar script). The data block is generated; the Luau
runtime below it moves the existing hooks, archives the old decor and builds the new ground dressing."""
import json, os, math, random, sys

L = json.load(open(sys.argv[1]))
OUT = sys.argv[2]
items = {i["name"]: i for i in L["items"]}

def catmull(pts, step=3.0):
    if len(pts) < 3:
        return pts
    P = [pts[0]] + pts + [pts[-1]]
    out = []
    for k in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[k - 1], P[k], P[k + 1], P[k + 2]
        n = max(2, int(math.dist(p1, p2) / step))
        for j in range(n):
            t = j / n
            t2, t3 = t * t, t * t * t
            out.append(tuple(round(0.5 * ((2 * p1[a]) + (-p0[a] + p2[a]) * t + (2 * p0[a] - 5 * p1[a] + 4 * p2[a] - p3[a]) * t2
                                          + (-p0[a] + 3 * p1[a] - 3 * p2[a] + p3[a]) * t3), 2) for a in (0, 1)))
    out.append(tuple(pts[-1]))
    return out

def lua(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(round(v, 3))
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, (list, tuple)):
        return "{" + ",".join(lua(x) for x in v) + "}"
    if isinstance(v, dict):
        return "{" + ",".join(f"{k}={lua(x)}" for k, x in v.items()) + "}"
    if v is None:
        return "nil"
    raise TypeError(v)

def at(name):
    i = items[name]
    return i["x"], i["z"], i["yaw"]

def face(frm, to):
    return round(math.degrees(math.atan2(to[0] - frm[0], -(to[1] - frm[1]))), 1)

# --- hooks: existing Studio objects moved to the plan (front = how their facing is measured)
hooks = []
def H(path, name, front="look", y=None, yaw=None, xz=None):
    x, z, yw = at(name) if name else (None, None, None)
    if xz:
        x, z = xz
    hooks.append(dict(path=path, x=x, z=z, yaw=yw if yaw is None else yaw, front=front, y=y))

H("FTP_Lobby.LobbySpawn", "LobbySpawn", yaw=0)
H("LobbyMeadow.StarterEggSpot", "StarterEggSpot", yaw=0)
H("FTP_Lobby.ShopRow.ShopEgg", "EggShop", yaw=items["EggShop"]["yaw"] + 180)  # mesh front = -LookVector (Studio check 10-15)
H("FTP_Lobby.ShopRow.ShopBackpack", "MyPetsShop", yaw=items["MyPetsShop"]["yaw"] + 180)
H("FTP_Lobby.ShopRow.ShopTower", "EventShop", yaw=items["EventShop"]["yaw"] + 180)
H("FTP_Lobby.Buildings.HatchStand", "HatchStand")  # by the main walk, apart from the EGG SHOP hut prompt
H("FTP_Lobby.ShopRow.ShopBook", "PetIndexShop", yaw=items["PetIndexShop"]["yaw"] + 180)
H("FTP_Lobby.Leaderboards.CoinsBoard", "CoinsBoard", front="gui", yaw=0)
H("FTP_Lobby.WhatsNewBoard", "WhatsNewBoard", front="gui", yaw=items["WhatsNewBoard"]["yaw"] + 180)  # first gui found is its back
H("LobbyMeadow.BattleArena.TrainPad", "TrainPad", yaw=90)
H("FTP_Lobby.Leaderboards.TowerFloorBoard", "TowerFloorBoard", front="gui", yaw=-90)
pile = items["EggPile"]
for k in range(1, 5):
    p = items[f"QueuePad{k}"]
    H(f"FTP_Lobby.QueuePads.QueuePad{k}", f"QueuePad{k}", front="ref:Countdown", yaw=face((p["x"], p["z"]), (pile["x"], pile["z"])))
H("FTP_Lobby.QueuePads.PlayBanner", "PlayBanner", front="none", y=24)
H("LobbyMeadow.BattleArena.BattlePad", "BattleRing", yaw=-90)
H("FTP_Lobby.Leaderboards.RarestPetBoard", "RarestPetBoard", front="gui")
for k in range(1, 7):
    H(f"FTP_Lobby.Plots.Plot{k}", f"Plot{k}", front="ref:PlotSign", yaw=90 if items[f"Plot{k}"]["x"] < 0 else -90)
H("LobbyMeadow.Hooks.Games.WhackStump", "WhackStump", yaw=face((-40, 74), (0, 74)))
for k in range(1, 4):
    H(f"LobbyMeadow.Hooks.Events.EventSpot{k}", f"EventSpot{k}", front="none")
for k in range(1, 6):
    H(f"LobbyMeadow.Hooks.Secrets.HiddenEgg{k}", f"HiddenEgg{k}", front="none")
H("FTP_Lobby.Buildings.SecretEgg", "SecretEgg", front="none")
cx, cz = items["CampfireNook"]["x"], items["CampfireNook"]["z"]
H("LobbyMeadow.Hooks.Seats.Campfire", None, front="none", xz=(cx, cz), yaw=0)
for k in range(1, 4):
    a = math.radians(-30 + 120 * (k - 1))
    p = (round(cx + 5.5 * math.sin(a), 1), round(cz - 5.5 * math.cos(a), 1))
    H(f"LobbyMeadow.Hooks.Seats.CampfireLog{k}", None, xz=p, yaw=face(p, (cx, cz)) + 90)
for k in range(1, 5):
    a = math.radians(30 + 120 * ((k - 1) % 3) + (60 if k == 4 else 0))
    p = (round(cx + 10 * math.sin(a), 1), round(cz - 10 * math.cos(a), 1))
    H(f"LobbyMeadow.Hooks.Seats.Bench{k}", None, xz=p, yaw=face(p, (cx, cz)))

# --- new things the plan adds
fightboard = dict(x=items["FightBoard"]["x"], z=items["FightBoard"]["z"], yaw=-90)
egg_shop_counter = True  # EggShop Counter goes in front of the ShopEgg building

# --- decor clones from ServerStorage.LobbyKitV2
decor = []
for i in L["items"]:
    if i["kind"] == "tree":
        decor.append(dict(m=i["model"], x=i["x"], z=i["z"], yaw=i["yaw"], s=i.get("scale", 1)))
    elif i["kind"] == "lamp":
        decor.append(dict(m="LampPost_Yellow", x=i["x"], z=i["z"], yaw=0, s=0.75))  # round 8: smaller lamps
    elif i["kind"] == "flowers":
        decor.append(dict(m="FlowerBed_Big_Mixed", x=i["x"], z=i["z"], yaw=random.Random(i["x"]).uniform(0, 360), s=1))
    elif i["kind"] in ("flowerrow", "feature"):
        decor.append(dict(m=i["model"], x=i["x"], z=i["z"], yaw=i["yaw"], s=1))
    elif i["kind"] == "prop" and not i["model"].startswith("P_"):
        decor.append(dict(m=i["model"], x=i["x"], z=i["z"], yaw=i["yaw"], s=1))
# built stand-ins (runtime PROPS table): egg crates, hay bales, braziers, planters, pet bowls and balls
ponds = [dict(x=i["x"], z=i["z"], r=i["r"]) for i in L["items"] if i["kind"] == "pond"]
props = [dict(m=i["model"], x=i["x"], z=i["z"], yaw=i["yaw"]) for i in L["items"] if i["kind"] == "prop" and i["model"].startswith("P_")]
# each zone gets its own ground under its plaza (round 6 runner: "too much green")
zones = [dict(x=-100, z=-36, r=60, c="b8cc5e", m="Grass", name="FindMeadow", flowers=True),
         dict(x=100, z=-36, r=58, c="b06a44", m="Ground", name="FightDirt"),
         dict(x=0, z=-118, r=56, c="62c088", m="Grass", name="TrainTeal"),
         dict(x=0, z=-114, r=34, c="c2c8cc", m="Slate", name="TrainFlagstone"),
         dict(x=0, z=138, r=32, c="a8dc68", m="Grass", name="SpawnLawn")]
# yard dressing: flower rows just inside the front fence either side of the gate, a gold claim disc at the gate
yards = []
for k in range(1, 7):
    p = items[f"Plot{k}"]
    sgn = 1 if p["x"] < 0 else -1  # +1: gate on the east side
    gx = p["x"] + sgn * (p["w"] / 2 - 0.5)
    yards.append(dict(gx=round(gx - sgn * 2.5, 1), gz=p["z"], fx=round(p["x"] + sgn * (p["w"] / 2 + 1.5), 1), sg=sgn, px=p["x"], hw=round(p["w"] / 2, 1), hd=round(p["d"] / 2, 1)))

# cliff ring just outside the collision walls (x +-146, z -192..178), facing in, with pines behind
rng = random.Random(21)
cliffs = []
for i in L["items"]:
    if i["kind"] == "cliff":
        cliffs.append(dict(m=i["model"], x=i["x"], z=i["z"], yaw=i["yaw"], s=i["scale"]))
pines = []
tries = 0
while len(pines) < 140 and tries < 20000:  # round 12: a fuller belt outside the walls (as many as fit)
    tries += 1  # pine belt on the hills behind the cliffs, never touching each other
    side = rng.choice("WENS")
    if side in "WE":
        x, z = (-1 if side == "W" else 1) * rng.uniform(174, 196), rng.uniform(-215, 205)
    else:
        x, z = rng.uniform(-196, 196), (rng.uniform(-232, -214) if side == "N" else rng.uniform(203, 220))
    sc = rng.uniform(1.3, 2.0)
    r = 6.2 * sc
    if all(math.dist((x, z), (p[0], p[1])) > r + p[2] + 1 for p in pines):
        pines.append((x, z, r, sc))
def quad_trees(x, z):  # each side of the island leans toward its zone colour (west gold, east autumn, north blue-green)
    if x < -150 and -120 < z < 60:
        return ["Tree_Pine_B_v2", "Tree_Round_Golden_v1", "Tree_Pine_A_v2"]  # round 29: more pines (runner)
    if x > 150 and -120 < z < 60:
        return ["Tree_Pine_B_v2", "Tree_Round_Autumn_v1", "Tree_Pine_A_v2"]
    if z < -200:
        return ["Tree_Round_BlueGreen_v1", "Tree_Pine_B_v2", "Tree_Pine_A_v2"]
    return ["Tree_Pine_B_v2", "Tree_Pine_A_v2", "Tree_Pine_B_v2", "Tree_DarkGreen"]
for x, z, r, sc in pines:
    cliffs.append(dict(m=rng.choice(quad_trees(x, z)), x=round(x, 1), z=round(z, 1),
                       yaw=rng.uniform(0, 360), s=round(sc * 1.35, 2), lift=8))  # r29e: 1.35x (runner: "pines small and sparse")

# --- paths (smoothed) and plazas
ZONECOL = {"ToHunt": "f0a020", "ToBattle": "e0443a", "ToTower": "2fa7d6", "Main": "f2c230"}
paths = [dict(w=w, pts=catmull([tuple(p) for p in pts]), plank=n.startswith("Yard"), arrows=ZONECOL.get(n))
         for n, w, pts in L["paths"]]
plazas = [dict(x=i["x"], z=i["z"], r=i["r"], ring=i.get("ring")) for i in L["items"] if i["kind"] == "plaza"]
arches = []
for t in ("FIND", "FIGHT", "TRAIN"):
    l, r_ = items[f"Arch{t}_L"], items[f"Arch{t}_R"]
    arches.append(dict(icon={"FIND": "\U0001F95A", "FIGHT": "\u2694\ufe0f", "TRAIN": "\u2b50"}[t], text=t,
                       sub={"FIND": "EGG HUNT", "FIGHT": "BATTLE", "TRAIN": "TOWER"}[t],
                       col={"FIND": "f0a020", "FIGHT": "e0443a", "TRAIN": "2fa7d6"}[t], lx=l["x"], lz=l["z"], rx=r_["x"], rz=r_["z"]))

# --- egg pile: a dome of eggs on a straw nest
er = random.Random(9)
eggs = []
# round 15: brighter colours (runner: "egg pile small and pale"), a taller dome, bigger eggs
cols = ["ffd23f", "4fc3f7", "7bd96a", "ff8a3d", "b98cf0", "fff3b0", "5ad1c0", "ffffff"]
for layer, (rr, y, n) in enumerate(((11.5, 2.4, 18), (9.0, 6.4, 14), (6.4, 10.2, 10), (3.6, 13.8, 6), (0, 17.2, 1))):
    for k in range(n):
        a = 2 * math.pi * k / max(n, 1) + er.uniform(-0.15, 0.15) + layer
        rad = rr * er.uniform(0.75, 1.0)
        eggs.append(dict(x=round(pile["x"] + rad * math.cos(a), 2), y=round(y + er.uniform(-0.3, 0.3), 2), z=round(pile["z"] + rad * math.sin(a), 2),
                         s=round(er.uniform(4.6, 6.0), 2), c=er.choice(cols), tilt=round(er.uniform(-25, 25))))

# --- ground colour patches (subtle, four greens)
gp = []
pr = random.Random(4)
for _ in range(26):
    x, z = pr.uniform(-130, 130), pr.uniform(-175, 160)
    col = pr.choice(["8cc45c", "7ab84e", "98cc68", "82be54"])  # round 26: brighter greens (carter: "too bland on mobile")
    for _k in range(3):
        p = dict(x=round(x + pr.uniform(-10, 10), 1), z=round(z + pr.uniform(-10, 10), 1), r=round(pr.uniform(10, 20), 1), c=col)
        if all(math.hypot(p["x"] - q["x"], p["z"] - q["z"]) > p["r"] + q["r"] + 0.5 for q in gp):  # round 22: no overlaps (z-fight)
            gp.append(p)

data = dict(hooks=hooks, fightboard=fightboard, decor=decor, cliffs=cliffs, paths=paths, plazas=plazas, eggs=eggs,
            pile=dict(x=pile["x"], z=pile["z"], r=pile["r"]), battle=dict(x=items["BattleRing"]["x"], z=items["BattleRing"]["z"], r=items["BattleRing"]["r"]),
            patches=gp, ponds=ponds, props=props, zones=zones, shops=[dict(name=n, x=items[n]['x'], z=items[n]['z'], yaw=items[n]['yaw'], d=items[n]['d']) for n in ('PetIndexShop', 'MyPetsShop', 'EventShop')], yards=yards, arches=arches, knoll=dict(r=items["DragonFountain"]["r"]), starter=dict(x=items["StarterEggSpot"]["x"], z=items["StarterEggSpot"]["z"], r=items["StarterEggSpot"]["r"]), eggshop=dict(x=items["EggShop"]["x"], z=items["EggShop"]["z"], yaw=items["EggShop"]["yaw"], d=items["EggShop"]["d"]))
runtime = open(sys.argv[3]).read()
# round 29: shared/VibeGrade (pure, tested offline) inlined so the Studio build lifts colours with the same function
_vg = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../../src/shared/VibeGrade.luau")).read()
_vg = _vg.replace("--!strict\n", "", 1)
runtime = "local VibeGrade = (function()\n" + _vg + "end)()\n" + runtime
open(OUT, "w").write("-- GENERATED by tools/studio/lobby_redesign/gen_build.py from layout.json. Do not hand-edit the DATA line.\n"
                     "local DATA = " + lua(data) + "\n" + runtime)
print("wrote", OUT, len(open(OUT).read()) // 1024, "KB;", len(hooks), "hooks,", len(decor), "decor,", len(cliffs), "edge,",
      sum(len(p["pts"]) for p in paths), "path pts,", len(eggs), "eggs")
