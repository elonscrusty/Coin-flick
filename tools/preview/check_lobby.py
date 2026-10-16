#!/usr/bin/env python3
"""Lobby placement audit (Master Prompt 4 sections 17 and 54), run on a preview scene JSON.

    bash tools/preview/render.sh lobby --device phone-1108 --outdir /tmp/lobby --set hud=off
    python3 tools/preview/check_lobby.py /tmp/lobby/lobby-phone-1108.json

Reports (1) static parts that stand in a functional clear zone of the pet park (main path, ring path, spawn walk,
stall, board, hatch stand and news fronts, tower approach; bounding boxes, flat floor ignored) and (2) the bounding box of the big landmarks so their
scale can be compared with the avatar (about 5 studs tall). Exits 1 when a clear zone is blocked.
The renderer scene has no parent names, so landmarks are found by part name or by region.
"""

import json
import sys

# keep in step with LobbyBuilder.ClearZones (world X / Z; the pet park, ground top FLOOR, src/shared/ParkConfig.luau)
ZONES = [
    ("SpawnWalk", -6, 6, 96, 124),
    ("MainSouth", -4.5, 4.5, 50, 92),
    ("MainNorth", -4.5, 4.5, -96, -50),
    ("RingSouth", -84, 84, 40, 48),
    ("RingNorth", -84, 84, -48, -40),
    ("RingWest", -48, -40, -84, 84),
    ("RingEast", 40, 48, -84, 84),
    ("ClearingWalk", -4, 4, -30, 30),
    ("UpgradesFront", -43, -36, 101, 123),
    ("PetBookFront", 36, 43, 101, 123),
    ("SellerFront", -30, -22, 118, 124),
    ("EggShopFront", -5, 5, -100, -96),
    ("TowerApproach", -92, -86, -4, 4),
    ("BoardFront", 20, 27, -14, 14),
    ("HatchFront", 14, 28, -90, -86),
    ("NewsFront", 15, 29, 99, 104),
]
FLOOR = 0.0
IGNORE_NAMES = {"HumanoidRootPart", "Head", "UpperTorso", "LowerTorso", "Torso", "LeftArm", "RightArm", "LeftLeg",
                "RightLeg", "LeftHand", "RightHand", "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm",
                "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg", "LeftFoot", "RightFoot",
                "CT_Rocks_LobbySpawn", "CT_Rocks_Plaza", "CT_Rocks_Ground", "Rubber"}  # Rubber = the stand-in avatar's boots
# Lodge_Building shell pieces that sit on the four corner posts: their bounding box spans the hall, the mesh does not
IGNORE_NAMES |= {"Corners", "BaseCorners"}
# parts that belong to the walking surface or the kiosk the aisle leads to
SURFACE = ("Aisle", "AisleEdge", "Seam", "Route", "Band", "Forecourt", "Pad", "Step", "Bounds")


def aabb(p):
    cf, size = p["cf"], p["size"]
    r = [cf[3:6], cf[6:9], cf[9:12]]
    hx = [sum(abs(r[i][j]) * size[j] / 2 for j in range(3)) for i in range(3)]
    return (cf[0] - hx[0], cf[0] + hx[0], cf[1] - hx[1], cf[1] + hx[1], cf[2] - hx[2], cf[2] + hx[2])


def main(path):
    d = json.load(open(path))
    parts = d["world"]["parts"]
    bad = 0
    for name, x0, x1, z0, z1 in ZONES:
        hits = {}
        for p in parts:
            if p["name"] in IGNORE_NAMES or p["name"].startswith(SURFACE) or p.get("transparency", 0) >= 0.95:
                continue
            ax0, ax1, ay0, ay1, az0, az1 = aabb(p)
            if abs(p['cf'][0]) < 3 and 105 < p['cf'][2] < 111:  # the stand-in avatar at the spawn
                continue
            if ay1 < FLOOR + 0.5 or ay0 > FLOOR + 2.8:  # flat floor pieces and anything above head height cannot block walking
                continue
            if ax1 > x0 and ax0 < x1 and az1 > z0 and az0 < z1:
                hits.setdefault(p["name"], []).append((round(p["cf"][0], 1), round(p["cf"][1], 1), round(p["cf"][2], 1)))
        print(f"{name}: {'CLEAR' if not hits else 'BLOCKED by ' + str(hits)}")
        bad += len(hits)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main(sys.argv[1])
