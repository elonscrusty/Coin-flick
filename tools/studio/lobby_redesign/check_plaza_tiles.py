"""Offline z-fight check for the plaza tiles (round 29). Mirrors runtime.luau section 5 (grout disc, tile rings in two
tones, centre disc) from layout.json and counts pairs of DIFFERENT colours whose top faces are within 0.01 in height
and whose real footprints overlap (separating-axis test, like glitch_scan.luau). Must print 0. Run: python3 check_plaza_tiles.py"""
import json, math, os, sys

L = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "layout.json")))
TONE_Y = {"efe0ad": 0.08}  # runtime.luau: tile centre height above the plaza base y
parts = []
for pz in (i for i in L["items"] if i["kind"] == "plaza"):
    y = 0.3
    parts.append(((pz["x"], pz["z"]), [(pz["r"] + 0.6, 0), (0, pz["r"] + 0.6)], y + 0.06, "efe0ad"))
    r, ring = 5.7, 0
    while r + 2.7 <= pz["r"] + 0.3:
        ring += 1
        n = max(6, math.floor(2 * math.pi * r / 6.5))
        for k in range(n):
            a = (k + (ring % 2) * 0.5) / n * 2 * math.pi
            ln = 2 * math.pi * r / n - 0.45
            tone = "efe0ad"
            c = (pz["x"] + r * math.sin(a), pz["z"] - r * math.cos(a))
            rad, tan = (math.sin(a), -math.cos(a)), (math.cos(a), math.sin(a))
            parts.append((c, [(rad[0] * 2.7, rad[1] * 2.7), (tan[0] * ln / 2, tan[1] * ln / 2)], y + TONE_Y[tone] + 0.06, tone))
        r += 6
    parts.append(((pz["x"], pz["z"]), [(2.7, 0), (0, 2.7)], y + 0.12 + 0.06, "efe0ad"))


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1]


def unit(v):
    m = math.hypot(*v)
    return (v[0] / m, v[1] / m)


def overlap(A, B):
    d = (B[0][0] - A[0][0], B[0][1] - A[0][1])
    for ax in (unit(A[1][0]), unit(A[1][1]), unit(B[1][0]), unit(B[1][1])):
        if abs(dot(d, ax)) >= sum(abs(dot(h, ax)) for h in A[1]) + sum(abs(dot(h, ax)) for h in B[1]) - 0.01:
            return False
    return True


bad = sum(1 for i in range(len(parts)) for j in range(i + 1, len(parts))
          if abs(parts[i][2] - parts[j][2]) < 0.01 and parts[i][3] != parts[j][3] and overlap(parts[i], parts[j]))
print(f"plaza tiles: {len(parts)} parts, z-fight pairs {bad}")
sys.exit(1 if bad else 0)
