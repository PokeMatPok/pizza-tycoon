# Pizza Tycoon

A competitive Pizza Connection 2-style management tycoon for Roblox:
supply chain → kitchen → storefront → city-wide competitive delivery zones,
sabotage (heists), random city events, staff upkeep, and leaderboards.
Server-authoritative; all 3D assets are procedurally generated in code.

## Gameplay loop

- **Buy one of three themed plots** (Neapolitan Alley, Neon Slice Downtown, Harborside Bazaar), each with 3 purchasable expansions (+15% oven speed, +10% customers each).
- **Supply chain:** order shipments (Basic/Toppings/Bulk) into your warehouse (capacity tiers). Ovens consume ingredients and bake the recipe you've unlocked and set active (Margherita → Meat Feast).
- **Storefront:** AI customers buy ready pizzas at a price scaled by recipe, marketing tier, and active events.
- **Competition:** shared delivery zones (Downtown, Stadium, Airport) pay out pots every 60s, split by each player's van contribution share. Needs hired drivers (upkeep per minute).
- **Sabotage:** send heist crews to steal from rivals' warehouses — security upgrades counter them, and failed heists compensate the victim.
- **Events:** Rush Hour, Pizza Festival, Thief Hour, Economic Boom rotate randomly and scale customers, prices, zone pots, and theft.
- **Meta:** in-memory session top-10 by revenue + all-time OrderedDataStore.

## Architecture

```
default.project.json        Rojo mapping
src/shared/Config.luau     ALL game balance (single source of truth)
src/shared/Net.luau        typed remote access (server creates)
src/server/Main.server.luau  service bootstrap: Init phase then Start phase
src/server/services/
  ModelFactory    procedural 3D "model service" (parts, no meshes)
  DataManager     DataStore persistence, retries, session lock, autosave
  Economy         single transaction gate for all money
  PlotManager     plots, prompts (buy/upgrade/hire/unlock/expand/heist), signs
  Production      oven baking, staff upkeep, warehouse theft (1s tick)
  OrderSystem     AI customer flow and counter sales (fractional spawn rates)
  DeliveryZones   shared competitive zones and payout cycles
  EventManager    global event rotation
  Leaderboards    session top-10 broadcast + all-time OrderedDataStore
src/client/
  Main.client.luau + UIController (HUD, banner, leaderboard)
                  + EffectsController (floating +$ text)
```

The Main bootstrap scripts are paste-tolerant: they resolve `services` /
`controllers` folders case-insensitively, whether they sit next to Main or
inside it, and print a clear warning naming anything they cannot find.

Design rules used to keep it bug-free:
- **Server-authoritative**: clients only render; every purchase validates ownership, cost, capacity and tier server-side.
- **One money gate** (`Economy.Transact`), integer-only cash, no negative balances.
- **No NPC Humanoids**: customers/thieves/heist crews are tweened blocky figures — no rig/physics bugs, no pathfinding failures.
- **All DataStore calls** are pcall-wrapped with retries; failed loads fall back to fresh data instead of corrupting play.
- **Config-driven balance**; nothing is hard-coded inside services.
- Loops are per-service with pcall guards so one failure never kills the whole simulation.

## Swapping in real 3D models

ModelFactory's builders return regular Models, so you can replace any
builder's body with a `MeshPart` later without touching game logic. Good sources:

- **Roblox Creator Store** — free community assets, e.g. https://create.roblox.com/store/asset/618028755/pizza-mesh (safest licensing, one-click into Studio).
- **Meshy** — AI text-to-3D with a native Roblox Bridge (exports to Creator Hub with textures): https://www.meshy.ai/use-cases/free-game-assets/roblox-developers and https://www.meshy.ai/tags/pizza
- **Sloyd** — parametric low-poly generator, CC BY 4.0, exports GLB/FBX/OBJ: https://www.sloyd.ai/free-3d-models/roblox
- **CGTrader / Sketchfab** — large libraries; check each model's license before uploading: https://www.cgtrader.com/3d-models/pizza
- **Roblox Cube** — Roblox's own open-source 3D foundation model: https://github.com/Roblox/cube/

Workflow: generate/download → import into Studio as MeshParts → place in
`ReplicatedStorage.Shared.Assets` → swap the corresponding `ModelFactory.*` builder to
`ClonedMeshPart:Clone()` with the same pivot behavior.

## Setup

See `SETUP.md` (Studio paste-in or Rojo).
