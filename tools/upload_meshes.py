"""Upload built COIN FLICK models to Roblox (Open Cloud Assets API, assetType Model), then regenerate MeshIds/MeshCatalog.

    ROBLOX_API_KEY=... ROBLOX_USER_ID=<owner user id> python3 tools/upload_meshes.py [--only CF_Coin,CF_Tree] [--force]

Run it on the owner's PC (the cloud container cannot reach apis.roblox.com). The key is only read from the
environment and is never printed or saved. Ids are only ever taken from the API response; a failed upload keeps
the previous id (or 0, which means the game keeps using its Part stand-ins). A model whose FBX changed since its
last upload (sha1 in art/meshes/uploaded_hashes.json) is uploaded again; --force re-uploads everything selected.
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


def request(method, url, key, body=None, content_type=None):
    req = urllib.request.Request(url, data=body, method=method)
    req.add_header("x-api-key", key)
    if content_type:
        req.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(req, timeout=180) as resp:
            return json.loads(resp.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"HTTP {e.code}: {e.read().decode(errors='replace')[:600]}")


def upload(path, name, key, user_id):
    boundary = uuid.uuid4().hex
    meta = {
        "assetType": "Model",
        "displayName": f"CoinFlick_{name}"[:50],
        "description": f"Coin Flick model {name}",
        "creationContext": {"creator": {"userId": str(user_id)}},
    }
    with open(path, "rb") as f:
        data = f.read()
    body = b"".join(
        [
            f'--{boundary}\r\nContent-Disposition: form-data; name="request"\r\nContent-Type: application/json\r\n\r\n{json.dumps(meta)}\r\n'.encode(),
            f'--{boundary}\r\nContent-Disposition: form-data; name="fileContent"; filename="{name}.fbx"\r\nContent-Type: model/fbx\r\n\r\n'.encode(),
            data,
            f"\r\n--{boundary}--\r\n".encode(),
        ]
    )
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
    with open(path, "rb") as f:
        return hashlib.sha1(f.read()).hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()
    key = os.environ.get("ROBLOX_API_KEY")
    user_id = os.environ.get("ROBLOX_USER_ID")
    if not key or not user_id:
        sys.exit("Set ROBLOX_API_KEY and ROBLOX_USER_ID first.")
    ids = json.load(open(IDS)) if os.path.exists(IDS) else {}
    hashes = json.load(open(HASHES)) if os.path.exists(HASHES) else {}
    manifest = json.load(open(MANIFEST))
    only = {x for x in args.only.split(",") if x}
    failed = []
    for name, entry in sorted(manifest.items()):
        if only and name not in only:
            continue
        path = os.path.join(MESHES, entry["file"])
        if not os.path.exists(path):
            print(f"{name:<24} missing {path} (build it first)")
            failed.append(name)
            continue
        h = sha1(path)
        if ids.get(name) and hashes.get(name) == h and not args.force:
            continue
        try:
            ids[name] = upload(path, name, key, user_id)
            hashes[name] = h
            print(f"{name:<24} -> {ids[name]}")
        except Exception as err:  # never print the key: errors only carry the API reply
            ids.setdefault(name, 0)
            failed.append(name)
            print(f"{name:<24} FAILED: {err}")
        json.dump(dict(sorted(ids.items())), open(IDS, "w"), indent=1)
        json.dump(dict(sorted(hashes.items())), open(HASHES, "w"), indent=1)
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "gen_mesh_catalog.py")], check=False)
    if failed:
        sys.exit("Failed: " + ", ".join(failed))


if __name__ == "__main__":
    main()
