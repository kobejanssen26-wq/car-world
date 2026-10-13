# Car World — explore, scavenge, build, drive

A Roblox (Luau) open-world game: search garages, barns, scrapyards, warehouses and hidden stashes for car
parts, assemble a car at a garage, drive to harder regions, find rarer parts, upgrade, repeat.

Everything is code: the world (terrain, roads, bridge, tunnel, buildings, props), all UI and all systems are
generated at runtime from the scripts in `src/`. There are no hand-placed models, so the project is a plain
[Rojo](https://rojo.space) project.

## Quick start

1. Install Rojo (CLI + Studio plugin): <https://rojo.space/docs/v7/getting-started/installation/>
2. `rojo build default.project.json -o CarWorld.rbxl` and open the file in Studio
   (or `rojo serve` and click *Connect* in the Studio plugin).
3. In Studio: **Game Settings → Security → Enable Studio Access to API Services** (needed for DataStore saving;
   without it the game runs with an in-memory profile and prints a warning).
4. Press **Play** (or *Start* with 2+ players to test multiplayer). Terrain generates at start-up, hub first;
   you spawn as soon as the hub is ready and the rest of the map fills in over the next ~10–30 s.

`default.project.json` already sets `StreamingEnabled`, `Gravity` and `Players.CharacterAutoLoads = false`
(the server loads characters after the player's data has loaded and the hub terrain exists).

## Where things live in Studio

| Source | Studio location | Role |
|---|---|---|
| `src/shared/*` | `ReplicatedStorage.Shared` | pure data + logic used by both sides (parts catalogue, stats, loot, profile mutations, world math, tyre model, remotes) |
| `src/server/*` | `ServerScriptService.Server` | `Main` (Script) + services (ModuleScripts) |
| `src/client/*` | `StarterPlayer.StarterPlayerScripts.Client` | `Main` (LocalScript) + UI + vehicle controller |
| *(created at runtime)* | `ReplicatedStorage.Remotes` | RemoteEvents `State, Notify, Loot, OpenGarage, Discovered`; RemoteFunction `GarageAction` |
| *(created at runtime)* | `Workspace.World`, `Workspace.Vehicles`, `Workspace.Terrain` | generated world and player vehicles |

### Modules

**Shared** — `Parts` (32 parts, 8 slots, 4 rarities), `VehicleStats` (parts → performance), `Profile` (all inventory /
garage / economy mutations as pure functions), `Loot` (loot rolls), `Rarity`, `Config` (tuning), `WorldData`
(biomes, roads, height function, bridge/tunnel features), `Tire` (tyre force model), `Remotes`.

**Server** — `DataService` (DataStore: session lock, `UpdateAsync`, retries with backoff, never saves an unloaded
profile, kicks instead of handing out a blank profile), `Sessions` (profiles + state snapshots), `WorldBuilder`
(chunked voxel terrain, roads, props, landmarks), `SiteBuilder` + `Sites` (31 locations and their containers),
`LootService`, `GarageService` (all client requests), `VehicleService` (vehicle models, ownership, fuel, damage).

**Client** — `Hud`, `InventoryPanel`, `GaragePanel`, `MapPanel` (fog-of-war map + waypoints), `Ambience` (per-biome
fog + banner), `VehicleController` (physics), `State`, `UIKit`.

## Gameplay

* **Start**: $150, no car. Dusty Junction (hub) has the garage; *Old Joe's Yard* 90 studs west holds a guaranteed
  starter kit (7 common parts → a complete car). The garage shop sells Common parts (at a markup) so nobody is soft-locked.
* **Search** crates/toolboxes/trunks (hold the prompt). Loot = part rarity roll (by location tier) × part category
  (barns → frames/tanks, garages → engines/gearboxes, scrapyards → frames/tyres …). Containers refill after 15 min (persisted).
  Hidden stashes always hold something Rare+ and are announced only when you walk up to them; notes at sites hint at them.
* **Build** at a garage terminal: install parts per slot, compare a candidate part against the installed one
  (stat bars show the delta), see missing parts and assembly progress. Up to 3 vehicle projects. Sell spare parts, refuel, repair.
* **Drive**: "Drive it" spawns the car on the pad; one car per player; only the owner can take the driver seat.
  Controls: WASD / arrows / gamepad / mobile thumbstick (Roblox's default controls feed the VehicleSeat).
  `I` bag, `M` map, `R` flip upright, on-screen buttons for touch. **TOW** brings a stranded car back to the nearest garage for a small fee.
* **Progress**: road gradients are capped per road (`WorldData.Roads[].maxGrade`) and the UI shows each car's *max climb angle*:

| Region | Tier | Road grade | Needs (roughly) |
|---|---|---|---|
| Rustwood Valley (hub) | 1 | 5% | any starter car |
| Pinewood Forest / Iron Flats | 2 | 8–12% | starter car, marginal; Uncommon engine helps |
| Redrock Mesa (dirt, sand) | 3 | 12% dirt | good tyres + suspension (rough-road grip), more fuel |
| Highcrest (pass, bridge, tunnel) | 3–4 | 12–30% | Rare engine + big battery, crawler/sport gearbox |
| Frostpeak | 4 | 38% | near-Legendary build, all-terrain tyres, long-range tank |

* **Trade-offs**: engine power is capped by battery output (UI warns); tall gearbox = top speed, crawler = hill torque;
  slicks = best road grip/braking but hopeless off-road; long-travel suspension keeps grip on rough surfaces; armour adds
  durability and weight; bigger engines burn much more fuel; weight lowers acceleration.

## Server authority / anti-exploit

* The client never sends items, prices or positions. Its only requests are `GarageAction(action, payload)` with
  validated strings, a token-bucket rate limit, a proximity check to a service point and ownership checks on every uid / vehicle id.
* Searching is a server-side `ProximityPrompt`: distance, cooldown, loot roll, inventory space and grant all happen on the server;
  the container is marked looted *before* items are granted and nothing is granted if the bag would overflow.
* Parts exist only as ids in the profile (`items["<uid>"]`). Installing removes the uid before the part is placed, so items cannot be
  duplicated; vehicles are *records*, the world model is a view, and spawning a second one destroys the first.
* Driver seat is owner-only (others are ejected); parked cars are anchored. Fuel, damage and a speed sanity check run on the server.
* Saving: see `DataService`. Profiles are sanitised by `Profile.reconcile` on load (unknown parts, mismatched slots, bad numbers are dropped).

## Tests (what is and isn't verified)

`tests/run.sh` runs plain-Luau unit tests (needs the [`luau`](https://github.com/luau-lang/luau/releases) CLI: `LUAU=/path/to/luau tests/run.sh`):

* `stats_test` – part→stat formulas, battery limit, trade-offs, progression bands.
* `profile_test` – inventory/garage/economy mutations (no dupes, caps, swap, sell, refuel, repair), data sanitising, loot distributions per tier.
* `world_test` – every road respects its max grade, terrain matches road elevation (with building pads applied), bridge ravine
  and tunnel mound exist, all 31 sites are inside the play circle, off roads, on flat pads.
* `physics_test` – a planar simulation using the exact `Tire` model: stable at full throttle, reaches ~93–97% of stat top speed,
  corners in the right direction, brakes, no spin-out at speed, coasts to rest, slicks lose grip off-road.

Also done: `rojo build` succeeds; every file compiles with `luau-compile`; `luau-analyze` reports no unknown locals/typos
(only Roblox-provided globals are unknown to the stand-alone analyser).

**Not tested (no Roblox runtime in the build environment):** everything that needs the engine — terrain `WriteVoxels`,
building/vehicle model geometry, the 3-D ray-cast suspension in `VehicleController`, ProximityPrompts, UI layout, DataStore.
Treat the first Studio run as the real test; see the checklist below.

## First-run checklist (Studio)

1. Output shows `[CarWorld] World complete (...)`; no red errors. Terrain visible around the plaza immediately.
2. Walk to Old Joe's Yard (west), search all 4 crates → bag has 7 parts + $60.
3. Walk to the garage terminal (NW building), *+ New vehicle*, install all 7 → "✔ READY", press *Drive it*, refuel.
4. Get in (walk onto the seat or use the "Get in" prompt) and drive. If the car feels too stiff/floaty tune
   `VehicleStats.suspension` (server) and the spring `k`/`c` in `VehicleController`; grip/handling lives in `Tire`.
5. Stop, leave the seat: the car parks (anchored). Rejoin: money, items, vehicles, discovered places persist; a spawned car doesn't.
6. Test with 2 players: the other player cannot enter your driver seat, can ride the passenger seat, sees your nameplate.

## Known limitations / next steps

* Wheels are static visuals (no spin/steer animation); suspension travel is not visualised.
* Terrain/props are generated per server start (deterministic, ~10–30 s); a production version could pre-bake terrain into the place file.
* Map is a stylised overview (not a rendered satellite image); on very small phones it is scaled down.
* No audio, no day/night cycle, no trading between players; hooks: `Profile` (add a trade action) and `GarageService`.
* The 3-D vehicle solver tuning (spring/damping, centre-of-mass height) is analytical, not play-tested.
