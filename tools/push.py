#!/usr/bin/env python3
"""Push the pizza-tycoon project files to GitHub via the REST API.

Usage: GITHUB_PAT=... python3 tools/push.py /home/user/pizza-tycoon "msg"

Creates blobs for each tracked file, builds a tree on top of the current
main HEAD, commits it, and fast-forwards the ref.
"""
import json
import os
import pathlib
import sys
import urllib.request

REPO = "PokeMatPok/pizza-tycoon"
BRANCH = "main"

FILES = [
    "default.project.json",
    "README.md",
    "SETUP.md",
    "update-game.ps1",
    "src/shared/Config.luau",
    "src/shared/Net.luau",
    "src/server/Main.server.luau",
    "src/server/services/ModelFactory.luau",
    "src/server/services/DataManager.luau",
    "src/server/services/Economy.luau",
    "src/server/services/CityMap.luau",
    "src/server/services/PlotManager.luau",
    "src/server/services/Production.luau",
    "src/server/services/OrderSystem.luau",
    "src/server/services/DeliveryZones.luau",
    "src/server/services/Pedestrians.luau",
    "src/server/services/Traffic.luau",
    "src/server/services/EventManager.luau",
    "src/server/services/Leaderboards.luau",
    "src/server/services/AdminService.luau",
    "src/client/Main.client.luau",
    "src/client/controllers/UIController.luau",
    "src/client/controllers/EffectsController.luau",
    "src/client/controllers/CityMapController.luau",
    "src/client/controllers/AdminController.luau",
    "tools/luacheck.py",
    "tools/push.py",
]


def api(method: str, path: str, token: str, body=None):
    url = f"https://api.github.com/repos/{REPO}/{path}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, method=method, data=data, headers={
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "Content-Type": "application/json",
    })
    with urllib.request.urlopen(req) as resp:
        raw = resp.read()
        return json.loads(raw) if raw else None


def main():
    root = pathlib.Path(sys.argv[1])
    message = sys.argv[2]
    token = os.environ["GITHUB_PAT"]

    head = api("GET", f"git/ref/heads/{BRANCH}", token)
    base_sha = head["object"]["sha"]
    print(f"base: {base_sha}")

    base_commit = api("GET", f"git/commits/{base_sha}", token)
    tree_items = []
    for rel in FILES:
        path = root / rel
        if not path.exists():
            print(f"WARN missing: {rel}")
            continue
        blob = api("POST", "git/blobs", token, {
            "content": path.read_text(encoding="utf-8"),
            "encoding": "utf-8",
        })
        tree_items.append({
            "path": rel,
            "mode": "100644",
            "type": "blob",
            "sha": blob["sha"],
        })
    tree = api("POST", "git/trees", token, {
        "base_tree": base_commit["tree"]["sha"],
        "tree": tree_items,
    })
    commit = api("POST", "git/commits", token, {
        "message": message,
        "tree": tree["sha"],
        "parents": [base_sha],
    })
    api("PATCH", f"git/refs/heads/{BRANCH}", token, {
        "sha": commit["sha"],
        "force": False,
    })
    print(f"pushed: {commit['sha']}")


if __name__ == "__main__":
    main()
