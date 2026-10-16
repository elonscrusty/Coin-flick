"""Put a Blender preview render next to the matching crop of the owner's reference sheet.

    python3 tools/ref_compare.py Station_Table Tool_Jackhammer     some models
    python3 tools/ref_compare.py --sheet 07                         every model from sheet 07
    python3 tools/ref_compare.py --all

Reads art/meshes/manifest.json (each Blender model records ref = {sheet, crop}) and
art/previews/<Name>.png (blender/build.py). Writes art/compare/<Name>.png: the reference crop on
top, the render (3/4, front, side) below, same width, so the two can be judged in one picture.
Needs Pillow (system python3).
"""

import argparse
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REFS = os.path.join(ROOT, "docs", "refs", "assets")
REF_DIRS = (REFS, os.path.join(ROOT, "docs", "lodge"))   # kit sheets + the Prospector Lodge asset sheets
MANIFEST = os.path.join(ROOT, "art", "meshes", "manifest.json")
PREVIEWS = os.path.join(ROOT, "art", "previews")
OUT = os.path.join(ROOT, "art", "compare")
WIDTH = 1320


def font(size):
    for f in ("DejaVuSans-Bold.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"):
        try:
            return ImageFont.truetype(f, size)
        except OSError:
            pass
    return ImageFont.load_default()


def sheet_path(sheet):
    for d in REF_DIRS:
        for fn in sorted(os.listdir(d)):
            if (fn == sheet or fn.startswith(sheet)) and fn.endswith(".png"):
                return os.path.join(d, fn)
    raise FileNotFoundError(sheet)


def compare(name, entry):
    ref = entry.get("ref")
    render = os.path.join(PREVIEWS, name + ".png")
    if not ref or not os.path.exists(render):
        print(f"{name}: no ref crop or no preview render, skipped")
        return None
    sheet = Image.open(sheet_path(ref["sheet"])).convert("RGB")
    crop = sheet.crop(tuple(ref["crop"]))
    scale = min(WIDTH / crop.width, 520 / crop.height)
    crop = crop.resize((int(crop.width * scale), int(crop.height * scale)), Image.LANCZOS)
    ren = Image.open(render).convert("RGB")
    ren = ren.resize((WIDTH, int(ren.height * WIDTH / ren.width)), Image.LANCZOS)
    head = 34
    out = Image.new("RGB", (WIDTH, head + crop.height + head + ren.height), (34, 38, 46))
    d = ImageDraw.Draw(out)
    d.text((10, 7), f"REFERENCE  sheet {ref['sheet']}  crop {ref['crop']}", fill=(244, 239, 229), font=font(18))
    out.paste(crop, ((WIDTH - crop.width) // 2, head))
    y = head + crop.height
    d.text((10, y + 7), f"BLENDER  {name}  ({entry.get('tris', '?')} tris, {len(entry.get('pieces', []))} pieces)",
           fill=(244, 190, 67), font=font(18))
    out.paste(ren, (0, y + head))
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".png")
    out.save(path)
    print(path)
    return path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("names", nargs="*")
    ap.add_argument("--sheet", default="")
    ap.add_argument("--all", action="store_true")
    args = ap.parse_args()
    with open(MANIFEST) as f:
        manifest = json.load(f)
    names = list(args.names)
    for k, v in manifest.items():
        if v.get("kind") in ("blender", "preview") and (args.all or (args.sheet and v.get("sheet") == args.sheet)):
            names.append(k)
    if not names:
        sys.exit("give model names, --sheet NN or --all")
    for n in names:
        if n not in manifest:
            print(f"{n}: not in manifest (build it first)")
            continue
        compare(n, manifest[n])


if __name__ == "__main__":
    main()
