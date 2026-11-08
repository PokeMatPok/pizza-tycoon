# Pizza Tycoon

A competitive Pizza Connection 2-style management tycoon for Roblox, set in
a living open-world city: supply chain → kitchen → storefront → district
delivery competition, sabotage (heists), random city events, staff upkeep,
and leaderboards. Server-authoritative; all 3D assets are procedurally
generated in code (zero meshes).

## The city

- **Real scale**: pedestrians are classic R6 avatars with a walk cycle,
  cars are full-size sedans, and restaurants seat real players — the
  district blocks, crosswalks, traffic lights, bus stops, parked cars,
  food carts and plazas are all sized for a 5-stud Roblox character.
- **Five districts**, each with distinct traits, architecture and gameplay
  effects — the **CITY MAP** button (right edge of the screen) opens a live
  minimap: click a district to see prices/traffic/theft/zone pot, and fast
  travel to its plaza.
  - **Skyline Heights** (rich downtown): priciest plot, +50% sale prices,
    biggest zone pot, glass skyscrapers.
  - **Trattoria Quarter** (old town): +20% prices, +10% foot traffic,
    brick buildings, most pedestrians.
  - **Maple Suburbs**: baseline prices, low theft, green family houses.
  - **Foundry Flats** (industrial): cheapest plot, +25% customers but -20%
    prices and high theft.
  - **Marina Bay** (waterfront): +35% prices, +30% tourist customers,
    sandy ground and palms.
- **Living streets**: low-poly cars drive the road grid and pedestrians
  stroll the sidewalks. They spawn only near players and despawn when
  nobody is around; density rises and falls in a slow rush-hour wave and
  spikes during events (Rush Hour, Festival...).
- **One restaurant plot per district** — location choice is strategic.
- **One delivery zone per district**: the van pot is scaled by district
  wealth and paid out every 60s split by contribution share.

## Gameplay loop

- **Buy one of five district restaurants** (Neon Slice, Nonna's Trattoria,
  Family Slice, Steel Crust, Surf & Slice), each with 3 purchasable
  expansions (+15% oven speed, +10% customers each).
- **Supply chain:** order shipments (Basic/Toppings/Bulk) into your
  warehouse (capacity tiers). Ovens consume ingredients and bake the recipe
  you've unlocked and set active (Margherita → Meat Feast).
- **Storefront:** AI customers walk in through the storefront and buy ready
  pizzas at a price scaled by recipe, marketing tier, district and events.
- **Competition:** send vans to district delivery zones; pots split by each
  player's contribution share. Needs hired drivers (upkeep per minute).
- **Sabotage:** send heist crews to steal from rivals' warehouses — security
  upgrades counter them, and failed heists compensate the victim.
- **Events:** Rush Hour, Pizza Festival, Thief Hour, Economic Boom rotate
  randomly and scale customers, prices, zone pots, theft AND street
  traffic.
- **Meta:** in-memory session top-10 by revenue + all-time OrderedDataStore.

## Architecture

```
default.project.json        Rojo mapping
src/shared/Config.luau     ALL game balance + city layout (single source of truth)
src/shared/Net.luau        typed remote access (server creates)
src/server/Main.server.luau  service bootstrap: Init phase then Start phase
src/server/services/
  ModelFactory    procedural 3D "model service": parts, buildings, cars, peds
  DataManager     DataStore persistence, retries, session lock, autosave
  Economy         single transaction gate for all money
  CityMap         open world: districts, roads, buildings, plazas, map state
  PlotManager     district lots, restaurant buildings, prompts, signs
  Production      oven baking, staff upkeep, warehouse theft (1s tick)
  OrderSystem     AI customer flow and counter sales
  DeliveryZones   one shared zone per district, payout cycles
  Pedestrians     sidewalk NPC strollers (near-player culling, rush waves)
  Traffic         road NPC cars (near-player culling, rush waves)
  EventManager    global event rotation
  Leaderboards    session top-10 broadcast + all-time OrderedDataStore
src/client/
  Main.client.luau + UIController (HUD, banner, leaderboard)
                  + EffectsController (floating +$ text)
                  + CityMapController (CITY button, live minimap, fast travel)
```

The Main bootstrap scripts are paste-tolerant: they resolve `services` /
`controllers` folders case-insensitively, whether they sit next to Main or
inside it, and print a clear warning naming anything they cannot find.

Design rules used to keep it bug-free:
- **Server-authoritative**: clients only render; every purchase validates ownership, cost, capacity and tier server-side.
- **One money gate** (`Economy.Transact`), integer-only cash, no negative balances.
- **No NPC Humanoids**: customers/pedestrians/thieves/heist crews are tweened blocky figures — no rig/physics bugs, no pathfinding failures.
- **Visibility-culled NPCs**: cars/peds only exist near players; movement steps at a capped 12 Hz to keep replication cheap.
- **All DataStore calls** are pcall-wrapped with retries; failed loads fall back to fresh data instead of corrupting play.
- **Config-driven balance**; nothing is hard-coded inside services.
- Loops are per-service with pcall guards so one failure never kills the whole simulation.
