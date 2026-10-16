#!/usr/bin/env python3
"""Rendered check of the pet park signs and boards (owner brief 2026-10-10, docs/lodge/VISUAL_PASS_REPORT.md).

Renders the lobby from the player views that should show each lodge sign / board and reads the renderer's SurfaceGui
numbers (`<png>.surfaces.json`, tools/preview/renderer/page/surfaces.js): for every SurfaceGui, the text pixels that
are visible from the camera (`inkPx`) and the text pixels it would show with nothing in front of it (`openPx`).
A sign FAILS when, from its view,
  * it is missing or has no text (no SurfaceGui text at all = a blank face),
  * fewer than MIN_INK text pixels are visible (blank, too small, or the face points away: SurfaceGuis are one-sided),
  * less than MIN_VISIBLE of its text is visible (covered by geometry).
--selftest first breaks the PET PARK arch sign three ways (SurfaceGui on the wrong face, a plank in front, disabled) and
expects each to be caught. Prints one [PASS] / [FAIL] line per check and "SIGN-FACES PASS" / "SIGN-FACES FAIL".
Offline preview only: this is the renderer's approximation of Roblox, not a Studio test.

    python3 tools/preview/check_signs.py [--device pc] [--keep DIR] [--selftest] [--ref GIT_REF]
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))

MIN_INK = 150
MIN_VISIBLE = 0.85

# view (lobby --set eye=...) -> [(label, path suffix of the SurfaceGui, text it must contain)]
CHECKS = {
    "spawn": [
        ("PET PARK arch sign", "CT_Park_Plaza/ParkSign/Face/Label", "PET PARK"),
    ],
    "news": [
        ("WHAT'S NEW heading", "CT_Park_WhatsNew/WhatsNewSign/Face/Label", "WHAT'S NEW"),
        ("WHAT'S NEW notes", "CT_Park_WhatsNew/WhatsNewText/Label", "Pet Park"),
    ],
    "boards": [
        ("RAREST PET heading", "CT_Rocks_Leaderboard_Biggest/Heading/Label", "RAREST PET"),
        ("HIGHEST FLOOR heading", "CT_Rocks_Leaderboard_Tower/Heading/Label", "HIGHEST FLOOR"),
        ("RAREST PET board face", "BoardMounts/Mount_Biggest/BoardGui", ""),
        ("HIGHEST FLOOR board face", "BoardMounts/Mount_Tower/BoardGui", ""),
    ],
    "nests": [("queue board", "QueueBoard/QueueGui", "STEP ON TO PLAY")],
    "upgradessign": [("UPGRADES sign", "CT_Rocks_Upgrades/CT_Rocks_Upgrades_Stall/Title/Label", "UPGRADES")],
    "collectionsign": [("PET BOOK sign", "CT_Rocks_Collection/CT_Rocks_Collection_Stall/Title/Label", "PET BOOK")],
    "seller": [("SHELL SELL sign", "CT_Rocks_SellHopper/SellSign/Label", "SHELL SELL")],
    "eggshop": [("EGG SHOP sign", "EggShop/ShopSign/Face/Label", "EGG SHOP")],
    "hatch": [("HATCH STAND sign", "CT_Park_HatchStand/HatchSign/Face/Label", "HATCH STAND")],
    "plot": [("plot name sign", "Plot1/Nameplate/Face/Label", "Park")],
    "likepost": [("plot LIKE sign", "Plot1/LikeSign/Label", "LIKES")],
    "tower": [("PET TOWER sign", "TowerEntrance/TowerSign/Face/Label", "PET TOWER")],
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--device", default="pc")
    ap.add_argument("--keep", default=None, help="write the renders here instead of a temp folder")
    ap.add_argument("--ref", default=None, help="render a committed version (render.sh --ref)")
    ap.add_argument("--selftest", action="store_true", help="also break the PET PARK arch sign three ways and expect FAILs")
    args = ap.parse_args()
    out = args.keep or tempfile.mkdtemp(prefix="ctr-signs-")
    os.makedirs(out, exist_ok=True)
    extra = ["--ref", args.ref] if args.ref else []

    def render(view, tag, more):
        png = os.path.join(out, f"{view}{tag}-{args.device}.png")
        js = os.path.join(out, f"{view}{tag}-{args.device}.json")
        r = subprocess.run(["bash", os.path.join(HERE, "render.sh"), "lobby", "--device", args.device, "--set", f"eye={view}",
                            "--set", "hud=off", "--out", png, "--json", js] + more + extra, cwd=REPO, capture_output=True, text=True)
        sj = png[:-4] + ".surfaces.json"
        if r.returncode != 0 or not os.path.exists(sj):
            print(f"[FAIL] render {view}{tag}: exit {r.returncode}\n{r.stdout[-2000:]}\n{r.stderr[-2000:]}")
            return None
        return json.load(open(sj))

    def judge(surfaces, suffix, text):
        found = [s for s in surfaces if s["path"].endswith(suffix)]
        if not found:
            return False, "no SurfaceGui with text"
        s = found[0]
        ok_text = text == "" or text in s["text"].replace(" | ", " ")
        frac = s["inkPx"] / s["openPx"] if s["openPx"] else 0
        ok = ok_text and s["inkPx"] >= MIN_INK and frac >= MIN_VISIBLE
        return ok, f"text '{s['text'][:60]}', visible text px {s['inkPx']} of {s['openPx']} ({frac * 100:.0f}%), face {s['face']}"

    fails = []
    if args.selftest:
        label, suffix, text = CHECKS["spawn"][0]
        for mode in ("flip", "cover", "off"):
            surfaces = render("spawn", "-" + mode, ["--set", f"signtest={mode}"])
            ok, detail = judge(surfaces or [], suffix, text)
            caught = surfaces is not None and not ok
            print(f"[{'PASS' if caught else 'FAIL'}] selftest: a {mode} PET PARK arch sign is caught ({detail})")
            if not caught:
                fails.append("selftest " + mode)
    for view, checks in CHECKS.items():
        surfaces = render(view, "", [])
        if surfaces is None:
            fails.append(f"render {view}")
            continue
        for label, suffix, text in checks:
            ok, detail = judge(surfaces, suffix, text)
            print(f"[{'PASS' if ok else 'FAIL'}] {label} ({view}, {args.device}): {detail}")
            if not ok:
                fails.append(label)
    print("SIGN-FACES PASS" if not fails else "SIGN-FACES FAIL: " + ", ".join(fails))
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
