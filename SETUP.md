# Pizza Tycoon — Setup Guide

Two ways to get the game running. **Option A (no tools needed)** works fully inside Roblox Studio. **Option B** uses the Rojo CLI for a proper workflow.

## Option A: Paste into Studio (recommended to start)

1. Open Roblox Studio → create a new **Baseplate** place (then delete the baseplate; the game builds its own ground).
2. In the Explorer, create this structure (folder/script names can use any capitalization — the Main scripts find them case-insensitively, and the `services` folder may sit next to Main or inside it):
   ```
   ReplicatedStorage
     Shared            (Folder)
       Config          (ModuleScript)
       Net             (ModuleScript)
   ServerScriptService
     Server            (Folder)
       Main            (Script)
       services        (Folder)
         ModelFactory  (ModuleScript)
         DataManager   (ModuleScript)
         Economy       (ModuleScript)
         CityMap       (ModuleScript)
         PlotManager   (ModuleScript)
         Production    (ModuleScript)
         OrderSystem   (ModuleScript)
         DeliveryZones (ModuleScript)
         Pedestrians   (ModuleScript)
         Traffic       (ModuleScript)
         EventManager  (ModuleScript)
         Leaderboards  (ModuleScript)
   StarterPlayer
     StarterPlayerScripts
       Client          (Folder)
         Main          (LocalScript)
         controllers   (Folder)
           UIController       (ModuleScript)
           EffectsController  (ModuleScript)
           CityMapController  (ModuleScript)
   ```
3. For each `.luau` file in `src/`, open the matching script in Studio and paste the file contents:
   - `Main.server.luau` → the `Main` Script
   - `Main.client.luau` → the `Main` LocalScript
   - every other `*.luau` → the matching ModuleScript
4. In Studio settings, enable **Game Settings → Security → Enable Studio Access to API Services** so DataStores work in Studio test.
5. Press **Play**. You spawn near the city center; use the **CITY MAP** button on the right edge to pick a district (click a district, then Teleport), and use the **Buy Restaurant** prompt on its lot.

If something is misplaced, the Main scripts now print a clear warning telling you exactly which script name they could not find, instead of hanging.

## Option B: Rojo (proper dev workflow, pairs great with Zed)

```bash
# install once
aftman add rojo-rbx/rojo  # or: cargo install rojo
# from this project folder
rojo serve default.project.json
```
Then in Studio: open the Rojo plugin → Connect. Save a file in Zed and it syncs instantly.

## How to play / verify it works

1. You start with **$500**. Pick a district with the **CITY MAP** button (right edge), teleport there, and buy its restaurant (prices range from $175 in Foundry Flats to $550 in Skyline Heights).
2. Order a **Basic Supplies** shipment at the warehouse (crates arrive after ~12s).
3. Buy **Stone Oven** ($100) at the oven. Pizzas start baking automatically.
4. Customers walk to your counter and buy ready pizzas (watch the green **+$** popups).
5. Hire a **Driver** ($150), then run pizzas (10 per van) to the district delivery zones ($ markers on the map). Every 60s each zone pays out its pot (richer districts = bigger pots), split by contribution share — compete with other players!
6. Compete harder: use the **Send Heist Crew** prompt on a rival's warehouse to steal ingredients (fails against high security — and you pay them).
7. Watch out for **Thief Hour**, ride **Rush Hour** and the **Pizza Festival** events.

## Where the 3D models come from

Every prop (buildings, cars, pedestrians, trees, pizzas, crates, ovens, vans, zones) is generated at runtime by
`src/server/services/ModelFactory.luau` — zero uploaded assets required. To upgrade to
real meshes later, see `README.md` → "Swapping in real 3D models".

## Tuning the game

All balance lives in `src/shared/Config.luau`: prices, tier costs, recipe stats, event
definitions, zone pots, theft and heist chances, plot themes and positions.
