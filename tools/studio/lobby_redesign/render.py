"""Draw the lobby plan (layout.json) as a top-down kid-friendly map PNG via headless Chromium."""
import json, math, subprocess, sys, random, os

L = json.load(open(sys.argv[1]))
OUT = sys.argv[2]
S = 3.0
X0, Z0, X1, Z1 = -160, -205, 160, 190
W, H = int((X1 - X0) * S), int((Z1 - Z0) * S)
def px(x): return (x - X0) * S
def pz(z): return (z - Z0) * S

g = []
add = g.append
rng = random.Random(3)

# outside: hills + cliffs ring
add(f'<rect x="0" y="0" width="{W}" height="{H}" fill="#3f8f35"/>')
for _ in range(140):
    x, z = rng.uniform(X0, X1), rng.uniform(Z0, Z1)
    if -150 < x < 150 and -196 < z < 182:
        continue
    r = rng.uniform(5, 9) * S
    add(f'<circle cx="{px(x):.0f}" cy="{pz(z):.0f}" r="{r:.0f}" fill="{rng.choice(["#2f7a2e", "#2a6d2a", "#367f30"])}" stroke="#1f5a22" stroke-width="2"/>')
# cliff band
add(f'<rect x="{px(-150):.0f}" y="{pz(-196):.0f}" width="{300*S:.0f}" height="{378*S:.0f}" rx="{30*S:.0f}" fill="#a26f45" stroke="#7b5232" stroke-width="5"/>')
# walk area grass with soft patches of four greens
add(f'<rect x="{px(-142):.0f}" y="{pz(-188):.0f}" width="{284*S:.0f}" height="{362*S:.0f}" rx="{20*S:.0f}" fill="#5cb53f"/>')
add('<clipPath id="walk"><rect x="%d" y="%d" width="%d" height="%d" rx="%d"/></clipPath>' % (px(-142), pz(-188), 284 * S, 362 * S, 20 * S))
patches = []
for _ in range(38):
    x, z = rng.uniform(-140, 140), rng.uniform(-186, 172)
    patches.append(f'<ellipse cx="{px(x):.0f}" cy="{pz(z):.0f}" rx="{rng.uniform(14,30)*S:.0f}" ry="{rng.uniform(10,22)*S:.0f}" fill="{rng.choice(["#68be48", "#52a83a", "#74c552", "#4c9f36"])}" opacity="0.75"/>')
add('<g clip-path="url(#walk)">' + "".join(patches) + "</g>")

items = L["items"]
def by(kind): return [i for i in items if i["kind"] == kind]

# plazas (peach tile, video colour)
for it in by("plaza"):
    add(f'<circle cx="{px(it["x"]):.0f}" cy="{pz(it["z"]):.0f}" r="{it["r"]*S:.0f}" fill="#eaa978" stroke="#c98a5c" stroke-width="4"/>')
    add(f'<circle cx="{px(it["x"]):.0f}" cy="{pz(it["z"]):.0f}" r="{it["r"]*S:.0f}" fill="url(#tiles)"/>')

# paths
for name, w, pts in L["paths"]:
    d = "M " + " ".join(f"{px(x):.0f},{pz(z):.0f}" for x, z in pts)
    add(f'<path d="{d}" fill="none" stroke="#b07f4f" stroke-width="{(w+1.5)*S:.0f}" stroke-linecap="round" stroke-linejoin="round"/>')
for name, w, pts in L["paths"]:
    d = "M " + " ".join(f"{px(x):.0f},{pz(z):.0f}" for x, z in pts)
    add(f'<path d="{d}" fill="none" stroke="#d9a873" stroke-width="{w*S:.0f}" stroke-linecap="round" stroke-linejoin="round"/>')

def rect(it, fill, stroke, sw=4, rx=6):
    cx, cz = px(it["x"]), pz(it["z"])
    w, d = it["w"] * S, it["d"] * S
    return (f'<rect x="{cx-w/2:.0f}" y="{cz-d/2:.0f}" width="{w:.0f}" height="{d:.0f}" rx="{rx}" fill="{fill}" stroke="{stroke}" '
            f'stroke-width="{sw}" transform="rotate({it["yaw"]} {cx:.0f} {cz:.0f})"/>')

def label(x, z, text, size=26, color="#ffffff", dy=0):
    lines = text.split("\n")
    out = []
    for k, ln in enumerate(lines):
        yy = pz(z) + dy + (k - (len(lines) - 1) / 2) * size * 1.05
        out.append(f'<text x="{px(x):.0f}" y="{yy:.0f}" font-size="{size}" fill="{color}" stroke="#2b1a0e" stroke-width="{size/5:.1f}" '
                   f'paint-order="stroke" text-anchor="middle" dominant-baseline="middle" font-family="Arial Black, Arial, sans-serif" font-weight="900">{ln}</text>')
    return "".join(out)

# plots: lawn, fence, gate gap on the inner side
for it in by("plot"):
    add(rect(it, "#7cc157", "#8a5a32", 7, 10))
    gx = it["x"] + (it["w"] / 2 if it["x"] < 0 else -it["w"] / 2)
    add(f'<rect x="{px(gx)-6:.0f}" y="{pz(it["z"])-24:.0f}" width="12" height="48" fill="#d9a873"/>')
    for k in range(4):  # pet spots (grid)
        for j in range(3):
            add(f'<circle cx="{px(it["x"] + (-16 + k*10.5)*(1 if it["x"]<0 else -1)):.0f}" cy="{pz(it["z"] - 16 + j*16):.0f}" r="6" fill="#ffffff" opacity="0.45"/>')
    add(label(it["x"], it["z"], it["label"], 30))

# tower castle
for it in by("tower"):
    add(rect(it, "#b9b4c4", "#6e6880", 6, 4))
    for dx in (-18, 18, 0):
        add(f'<circle cx="{px(it["x"]+dx):.0f}" cy="{pz(it["z"] + (0 if dx else -4)):.0f}" r="{(9 if dx else 12)*S:.0f}" fill="#d9483b" stroke="#8e2a22" stroke-width="5"/>')
    add(f'<rect x="{px(-5):.0f}" y="{pz(-150)-8:.0f}" width="{10*S:.0f}" height="16" fill="#5bd4f0" stroke="#1d6e86" stroke-width="3"/>')
    add(label(0, -150, "door", 18, "#ffffff", 26))

# knoll + tree + dragon
for it in by("knoll"):
    add(f'<circle cx="{px(0):.0f}" cy="{pz(0):.0f}" r="{it["r"]*S:.0f}" fill="#cfc6b8" stroke="#8d877f" stroke-width="5"/>')
    add(f'<circle cx="{px(0):.0f}" cy="{pz(0):.0f}" r="{(it["r"]-1.5)*S:.0f}" fill="#5fc4ef" stroke="#2a7fa8" stroke-width="4"/>')
    # dragon silhouette (purple) on top
    add(f'<g transform="translate({px(0):.0f},{pz(-2):.0f}) scale(0.55)">'
        '<path d="M-60,0 C-40,-50 -10,-30 0,-12 C10,-30 40,-50 60,0 C30,-10 15,0 0,6 C-15,0 -30,-10 -60,0 Z" fill="#6b3fc4" stroke="#2c124f" stroke-width="5"/>'
        '<ellipse cx="0" cy="8" rx="13" ry="24" fill="#8a5be0" stroke="#2c124f" stroke-width="5"/>'
        '<circle cx="0" cy="-20" r="11" fill="#8a5be0" stroke="#2c124f" stroke-width="5"/></g>')
    add(label(0, 0, "VOID DRAGON FOUNTAIN", 22, "#e3c8ff", 56))

# fountain
for it in by("fountain"):
    add(f'<circle cx="{px(it["x"]):.0f}" cy="{pz(it["z"]):.0f}" r="{it["r"]*S:.0f}" fill="#dcd6cf" stroke="#9a8f86" stroke-width="5"/>')
    add(f'<circle cx="{px(it["x"]):.0f}" cy="{pz(it["z"]):.0f}" r="{it["r"]*S*0.7:.0f}" fill="#62c7ef"/>')

# shops
shopcol = {"EggShop": ("#f4c84a", "#a4761b"), "PetIndexShop": ("#58a9e8", "#2a5f8f"), "MyPetsShop": ("#58b83a", "#2c6e22"), "EventShop": ("#e0443a", "#8e2a22"), "HatchStand": ("#f08a4b", "#9a4c1f")}
for it in by("shop"):
    f, s = shopcol.get(it["name"], ("#f4c84a", "#a4761b"))
    if it["r"]:
        add(f'<circle cx="{px(it["x"]):.0f}" cy="{pz(it["z"]):.0f}" r="{it["r"]*S:.0f}" fill="{f}" stroke="{s}" stroke-width="5"/>')
    else:
        add(rect(it, f, s, 6, 10))
    add(label(it["x"], it["z"], it["label"], 22 if it["r"] else 26, "#ffffff", 0 if not it["r"] else 30))

# boards
for it in by("board"):
    add(rect(it, "#6b4423", "#3d2512", 4, 3))

# egg pile + pads
for it in by("pile"):
    rr = random.Random(5)
    add(f'<circle cx="{px(it["x"]):.0f}" cy="{pz(it["z"]):.0f}" r="{it["r"]*S:.0f}" fill="#c99a63" stroke="#8a6438" stroke-width="4"/>')
    for _ in range(26):
        a, r = rr.uniform(0, 6.28), rr.uniform(0, it["r"] - 2.5)
        add(f'<ellipse cx="{px(it["x"] + r*math.cos(a)):.0f}" cy="{pz(it["z"] + r*math.sin(a)):.0f}" rx="9" ry="12" '
            f'fill="{rr.choice(["#fff4d6", "#ffe08a", "#bfe8ff", "#ffd1e0", "#d7f5c4"])}" stroke="#7a5a3a" stroke-width="2"/>')
for it in by("pad"):
    add(f'<circle cx="{px(it["x"]):.0f}" cy="{pz(it["z"]):.0f}" r="{it["r"]*S:.0f}" fill="#ffd23f" stroke="#ffffff" stroke-width="5"/>')
    add(label(it["x"], it["z"], it["label"], 24, "#ffffff"))

# battle ring
for it in by("battlering"):
    add(f'<circle cx="{px(it["x"]):.0f}" cy="{pz(it["z"]):.0f}" r="{it["r"]*S:.0f}" fill="#9a958e" stroke="#5c5852" stroke-width="7"/>')
    add(f'<circle cx="{px(it["x"]):.0f}" cy="{pz(it["z"]):.0f}" r="{it["r"]*S*0.55:.0f}" fill="#e8463a" stroke="#ffffff" stroke-width="5"/>')
    add(label(it["x"], it["z"], "VS", 30))

# train pad
for it in by("trainpad"):
    add(f'<circle cx="{px(it["x"]):.0f}" cy="{pz(it["z"]):.0f}" r="{it["r"]*S:.0f}" fill="#46c4e8" stroke="#ffffff" stroke-width="5"/>')
    add(label(it["x"], it["z"], "TRAIN", 20))

# starter egg
for it in by("egg"):
    add(f'<ellipse cx="{px(it["x"]):.0f}" cy="{pz(it["z"]):.0f}" rx="11" ry="14" fill="#fff1b8" stroke="#c4911c" stroke-width="4"/>')
    add(label(it["x"] + 16, it["z"] - 7, "free egg", 18, "#fff1b8"))

# flower beds and lamps
for it in by("flowers"):
    add(f'<circle cx="{px(it["x"]):.0f}" cy="{pz(it["z"]):.0f}" r="{it["r"]*S:.0f}" fill="#3e8f2c" stroke="#2c6e22" stroke-width="3"/>')
    rr = random.Random(int(it["x"] * 7 + it["z"]))
    for _ in range(10):
        a, r = rr.uniform(0, 6.28), rr.uniform(0, it["r"] - 1)
        add(f'<circle cx="{px(it["x"] + r*math.cos(a)):.0f}" cy="{pz(it["z"] + r*math.sin(a)):.0f}" r="4" fill="{rr.choice(["#ff5f5f", "#ffd23f", "#b46cf0", "#ffffff"])}"/>')
for it in by("lamp"):
    add(f'<circle cx="{px(it["x"]):.0f}" cy="{pz(it["z"]):.0f}" r="6" fill="#ffe27a" stroke="#6b4423" stroke-width="3"/>')

# trees
tcol = {"Tree_Round_B_v2": "#3f9a2e", "Tree_DarkGreen": "#2f7d2a", "Tree_Olive": "#7d9a3a", "Tree_AutumnOrange": "#e08a2e",
        "Tree_Pine_B_v2": "#2a6d2a", "Tree_Pine_A_v2": "#2a6d2a", "Tree_Round_S_v2": "#55ab3c"}
for it in by("tree"):
    add(f'<circle cx="{px(it["x"])+3:.0f}" cy="{pz(it["z"])+4:.0f}" r="{it["r"]*S:.0f}" fill="#000" opacity="0.18"/>')
    add(f'<circle cx="{px(it["x"]):.0f}" cy="{pz(it["z"]):.0f}" r="{it["r"]*S:.0f}" fill="{tcol.get(it["model"], "#3f9a2e")}" stroke="#1f5a22" stroke-width="3"/>')

# spawn arrow
for it in by("spawn"):
    x, z = px(it["x"]), pz(it["z"])
    add(f'<path d="M{x-20:.0f},{z+14:.0f} L{x:.0f},{z-26:.0f} L{x+20:.0f},{z+14:.0f} Z" fill="#ffffff" stroke="#2b1a0e" stroke-width="4"/>')
    add(label(it["x"], it["z"] + 8, "SPAWN", 24))

# zone banners
def banner(x, z, text, col):
    w = len(text) * 30 + 40
    add(f'<g transform="translate({px(x):.0f},{pz(z):.0f})"><rect x="{-w/2}" y="-28" width="{w}" height="56" rx="16" fill="{col}" stroke="#ffffff" stroke-width="5"/>'
        f'<text x="0" y="3" font-size="34" fill="#fff" text-anchor="middle" dominant-baseline="middle" font-family="Arial Black, Arial" font-weight="900" stroke="#2b1a0e" stroke-width="5" paint-order="stroke">{text}</text></g>')
banner(0, -92, "2 TRAIN", "#2fa7d6")
banner(-104, 4, "1 FIND", "#f0a020")
banner(104, 4, "3 FIGHT", "#e0443a")
banner(0, 84, "START", "#5a3fc0")
banner(0, 66, "SHOPS", "#8a4fd8") if False else None
add(label(-104, -70, "EGG PILE = PLAY HUNT", 20))
add(label(104, -60, "BATTLE PAD", 22))
add(label(-24, -116, "", 18))

svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">'
       '<defs><pattern id="tiles" width="30" height="30" patternUnits="userSpaceOnUse"><rect width="30" height="30" fill="none" stroke="#d48f5f" stroke-width="2"/></pattern></defs>'
       + "".join(g) + "</svg>")
html = f'<html><body style="margin:0;background:#3f8f35">{svg}</body></html>'
open(OUT + ".html", "w").write(html)
chrome = "/opt/pw-browsers/chromium-1194/chrome-linux/chrome"
subprocess.run([chrome, "--headless", "--no-sandbox", "--disable-gpu", "--hide-scrollbars", f"--window-size={W},{H+200}",
                f"--screenshot={OUT}", "file://" + os.path.abspath(OUT + ".html")], check=True, capture_output=True)
from PIL import Image; Image.open(OUT).crop((0, 0, W, H)).save(OUT)
print("wrote", OUT, W, H)
