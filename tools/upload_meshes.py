"""Upload built meshes to Roblox (Open Cloud Assets API, assetType Model) and regenerate MeshIds/MeshCatalog.

    ROBLOX_USER_ID=20194281 python3 tools/upload_meshes.py --only Station_Table,Rock_01_Wedge
    ROBLOX_USER_ID=20194281 python3 tools/upload_meshes.py            every Blender kit model not uploaded yet
    ROBLOX_USER_ID=20194281 python3 tools/upload_meshes.py --legacy   also the old CT_Rocks_*.glb meshes

* Blender kit models (blender/build.py, manifest kind "blender") upload art/meshes/<Name>.fbx; each FBX
  holds one mesh per piece, so the asset is a Model of MeshParts that MeshService colours from
  MeshCatalog. Preview-only compositions are never uploaded.
* The cloud environment injects the x-api-key header for apis.roblox.com; ROBLOX_API_KEY also works.
* A model whose FBX changed since its upload (sha1 in art/meshes/uploaded_hashes.json) is uploaded
  again as a new asset; --force re-uploads everything selected. Ids are only ever taken from the API
  response (never invented); failures keep the previous id (or 0) and print the exact API error.
* Afterwards tools/gen_mesh_catalog.py writes src/shared/MeshIds.luau and src/shared/MeshCatalog.luau.
"""

import argparse
import hashlib
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MESHES = os.path.join(ROOT, "art", "meshes")
IDS = os.path.join(MESHES, "uploaded_ids.json")
HASHES = os.path.join(MESHES, "uploaded_hashes.json")
MANIFEST = os.path.join(MESHES, "manifest.json")
API = "https://apis.roblox.com/assets/v1"
TYPES = {"glb": "model/gltf-binary", "fbx": "model/fbx", "obj": "model/obj"}


def request(method, url, key, body=None, content_type=None):
    req = urllib.request.Request(url, data=body, method=method)
    if key:
        req.add_header("x-api-key", key)
    if content_type:
        req.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(req, timeout=180) as resp:
            return json.loads(resp.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"HTTP {e.code}: {e.read().decode(errors='replace')[:600]}")


def upload(path, name, key, user_id):
    ext = path.rsplit(".", 1)[1]
    boundary = uuid.uuid4().hex
    meta = {
        "assetType": "Model",
        "displayName": f"CTR_{name}"[:50],
        "description": f"Crack the Rocks mesh model {name}",
        "creationContext": {"creator": {"userId": str(user_id)}},
    }
    with open(path, "rb") as f:
        data = f.read()
    body = b"".join([
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"request\"\r\nContent-Type: application/json\r\n\r\n{json.dumps(meta)}\r\n".encode(),
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"fileContent\"; filename=\"{name}.{ext}\"\r\nContent-Type: {TYPES[ext]}\r\n\r\n".encode(),
        data,
        f"\r\n--{boundary}--\r\n".encode(),
    ])
    op = request("POST", f"{API}/assets", key, body, f"multipart/form-data; boundary={boundary}")
    op_path = op.get("path") or f"operations/{op.get('operationId')}"
    for _ in range(90):
        if op.get("done"):
            break
        time.sleep(2)
        op = request("GET", f"{API}/{op_path}", key)
    if not op.get("done"):
        raise RuntimeError("upload did not finish in time")
    if "error" in op:
        raise RuntimeError(json.dumps(op["error"]))
    return int(op["response"]["assetId"])


def sha1(path):
    return hashlib.sha1(open(path, "rb").read()).hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--legacy", action="store_true", help="also upload the legacy CT_Rocks_*.glb meshes")
    args = ap.parse_args()
    key = os.environ.get("ROBLOX_API_KEY")
    user_id = os.environ.get("ROBLOX_USER_ID")
    if not user_id:
        sys.exit("Set ROBLOX_USER_ID first (20194281 for this game).")
    ids = json.load(open(IDS)) if os.path.exists(IDS) else {}
    hashes = json.load(open(HASHES)) if os.path.exists(HASHES) else {}
    manifest = json.load(open(MANIFEST)) if os.path.exists(MANIFEST) else {}
    only = {x for x in args.only.split(",") if x}

    files = []
    for name, entry in sorted(manifest.items()):
        if entry.get("kind") == "blender":
            files.append((name, os.path.join(MESHES, entry["file"]), entry.get("sheet")))
        elif args.legacy and os.path.exists(os.path.join(MESHES, name + ".glb")):
            files.append((name, os.path.join(MESHES, name + ".glb"), None))
    failed = []
    for name, path, sheet in files:
        if only and name not in only and sheet not in only:
            continue
        if not os.path.exists(path):
            print(f"{name:<28} missing {path} (build it first)")
            failed.append(name)
            continue
        h = sha1(path)
        unchanged = path.endswith(".glb") or hashes.get(name) == h  # legacy glb ids predate the hash file
        if ids.get(name) and unchanged and not args.force:
            continue
        try:
            ids[name] = upload(path, name, key, user_id)
            hashes[name] = h
            print(f"{name:<28} -> {ids[name]}")
        except Exception as err:
            ids.setdefault(name, 0)
            failed.append(name)
            print(f"{name:<28} FAILED: {err}")
        json.dump(dict(sorted(ids.items())), open(IDS, "w"), indent=1)
        json.dump(dict(sorted(hashes.items())), open(HASHES, "w"), indent=1)
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "gen_mesh_catalog.py")], check=False)
    if failed:
        sys.exit("Failed: " + ", ".join(failed))


if __name__ == "__main__":
    main()
