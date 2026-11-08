#!/usr/bin/env python3
"""Push the pizza-tycoon working tree to GitHub via the REST API.

Usage:
  GITHUB_PAT=<fine-grained PAT> python3 tools/push.py <project-root> "commit message"

The PAT is read from the environment, never stored in the repo.
"""
import base64, json, os, sys, urllib.request

PAT = os.environ["GITHUB_PAT"]
OWNER, REPO = "PokeMatPok", "pizza-tycoon"
BRANCH = "main"

def api(method, path, body=None):
    url = f"https://api.github.com/repos/{OWNER}/{REPO}/{path}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, method=method, data=data, headers={
        "Authorization": f"Bearer {PAT}",
        "Accept": "application/vnd.github+json",
        "Content-Type": "application/json",
        "User-Agent": "pizza-tycoon-pusher",
    })
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")

FILES = [
    "default.project.json", "README.md", "SETUP.md", "update-game.ps1",
    "tools/luacheck.py", "tools/push.py",
    "src/shared/Config.luau", "src/shared/Net.luau",
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
    "src/client/Main.client.luau",
    "src/client/controllers/UIController.luau",
    "src/client/controllers/CityMapController.luau",
    "src/client/controllers/EffectsController.luau",
]

def main():
    root = sys.argv[1]
    status, ref = api("GET", f"git/ref/heads/{BRANCH}")
    if status != 200:
        print("ref failed:", status, ref); sys.exit(1)
    head = ref["object"]["sha"]
    print("head:", head)

    status, commit0 = api("GET", f"git/commits/{head}")
    if status != 200:
        print("commit fetch failed:", status, commit0); sys.exit(1)

    tree = []
    for path in FILES:
        with open(os.path.join(root, path), "rb") as f:
            content = base64.b64encode(f.read()).decode()
        status, blob = api("POST", "git/blobs", {"content": content, "encoding": "base64"})
        if status not in (200, 201):
            print("blob failed:", path, status, blob); sys.exit(1)
        tree.append({"path": path, "mode": "100644", "type": "blob", "sha": blob["sha"]})

    status, t = api("POST", "git/trees", {"base_tree": commit0["tree"]["sha"], "tree": tree})
    if status not in (200, 201):
        print("tree failed:", status, t); sys.exit(1)
    print("tree:", t["sha"])

    status, c = api("POST", "git/commits", {
        "message": sys.argv[2],
        "tree": t["sha"],
        "parents": [head],
    })
    if status not in (200, 201):
        print("commit failed:", status, c); sys.exit(1)
    print("commit:", c["sha"])

    status, r = api("PATCH", f"git/refs/heads/{BRANCH}", {"sha": c["sha"], "force": False})
    if status != 200:
        print("ref update failed:", status, r); sys.exit(1)
    print("pushed:", c["sha"])

main()
