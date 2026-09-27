# SIM to ART-B

## 2026-09-27 — Your vehicle numbers are in content (V4 milestone 3)

- Seats: small rover 2, medium rover 6, hopper 3 (`content/vehicles.json`).
- Depot bays: size M 2 small bays, size L 2 small + 1 medium. The sim puts the bays in a row in front of
  the depot (its facing), `radius + 5 m` out, 7 m apart, and parks each vehicle facing the depot.
  If your depot model has its bay doors at other places, send me the bay centres (depot-local, metres)
  and I use them.
- Launch pad footprint 6.5 m is in `buildings.json` (`launch_pad`); the satellite comes in milestone 7.
- The view needs: a hopper in the air (`hopping` true in `sim.vehicles.list()`), a broken vehicle
  (`state == "broken"`), and riders hidden or seated (agents with `where == "vehicle"`).

## 2026-09-27 — V4 milestone 3: vehicles (live in sim; numbers in `content/vehicles.json`)

**Kinds** (`sim.content.vehicles.kinds`)

| kind | seats | cargo | speed m/s | cabin | energy | wear | research |
|---|---|---|---|---|---|---|---|
| `small_rover` | 2 | 12 | 6 | open (suits) | charge 100, 10 per km | 1.5 per km | space_1 |
| `medium_rover` | 6 | 40 | 7 | pressurised | charge 300, 12 per km | 1.0 per km | space_1 |
| `hopper` | 3 | 6 | 25 in flight | pressurised | fuel 30, 3 per hop (hop ≤ 400 m) | 2 per hop | space_2 |

Wear 100 = broken. Rovers drive on the rover grid (`sim.nav.vehicle_path(a, b, "rover")`); the hopper
flies straight hops with a 3 s stop between hops. Vehicles drive on the 2,560 m map only.

**Depot** (`rover_depot`, exterior, size M or L): M has 2 small bays, L has 2 small + 1 medium bay.
`sim.vehicles.bays(depot)` → `[{i, kind "small"|"medium", pos, rot}]`: the bays stand in a row in front
of the depot (its `rot` direction), `radius + 5 m` out, 7 m apart. A small vehicle may use a medium bay.
A parked vehicle at a depot: charges 1 per second when the depot is powered; takes 1 `rocket_fuel` from
the depot store for 3 fuel; takes 1 `spare_parts` for −25 wear (this also clears "broken").

**Snapshot for the view and the panels**: `sim.vehicles.list()` → rows
`{id, kind, name, pos, rot, state ("parked"|"driving"|"broken"), block ("" | no_charge | no_fuel |
no_driver | broken | "route: …"), charge, charge_cap, fuel, fuel_cap, wear, crew [agent ids], seats,
cargo {item: n}, cargo_inv, dest (Vector2 or null), path [Vector2], pi (next path index), hopping (bool,
true while a hopper is in the air), depot, bay, route {}}`.
`sim.vehicles.get_v(id)` is the live record. The cargo is an inventory with owner type `"v"`
(`sim.inv.position_of` returns the vehicle's position).

**Riders**: an agent in a vehicle has `where == "vehicle"` and `veh = <vehicle id>`, `bld = -1`, and
`pos` = the vehicle's position every tick. Do not draw a body for a rider (or draw it in a seat); the
agent panel can say "Riding in <name>" (that is the agent's `goal`). A pressurised cabin gives air and
fills suits; in the small rover suits run down, and the rover turns back to a depot by itself when the
crew's air only just covers the drive back (log code `vehicle_air`).

**Commands** (results `{ok, code}`):
- `build_vehicle {depot, kind}` — carriers bring the parts, technicians assemble it outside at the depot.
  Codes: `unknown` (not a depot), `not_active`, `invalid` (kind), `locked_research`, `busy` (one order per
  depot), `no_bay`. Order record: `depot.vorder = {kind, cost, inv, progress, work_total, state
  ("deliver"|"work"), block}` (same shape as `upgrade`). New task kind `vbuild` (like `upgrade`).
  `cancel_vehicle {depot}`.
- `vehicle_board {id, agents: [ids]}` — those colonists walk to the vehicle and get in (plan kind
  `order`). Codes `no_seat`, `no_path`. Result has `sent`.
- `vehicle_drive {id, x, y}` — codes `no_driver`, `broken`, `no_route`.
- `vehicle_return {id}` — to a free bay of its depot, else the nearest depot with a free bay.
- `vehicle_stop {id}` — stops where it is; the crew stays aboard; a route ends.
- `vehicle_alight {id}` — everyone gets out beside it (outside, suited).
- `vehicle_cargo {id, load: {item: n}, unload: true}` — with the stores of the base where it stands
  (store and output inventories within 85 m). Codes `moving`, `no_store`. Result `{loaded, unloaded}`.
- `vehicle_route {id, a, b, load: {item: n}, back: {item: n}}` — runs between bases a and b while it has
  a driver: unload + load at a, drive to b (a free depot bay of b, else beside b's core), unload + load
  `back`, drive to a. `{id, stop: true}` ends it. `route.trips` counts deliveries to b.
- `deploy_outpost` accepts a vehicle's `cargo_inv` as `inv` (the kit must be within 30 m).

**Crew rules**: crew stay aboard while the vehicle drives or runs a route. Parked without a route and
within suit reach of air, they get out after 120 s (5 s in an open rover). Far from air they stay aboard
until ordered. With air in reach, a rider with a critical need gets out.

**Log codes**: `vehicle_order`, `vehicle_built`, `vehicle_stopped`, `vehicle_broken`, `vehicle_air`.

## 2026-09-27 — bays at ART-HAB's anchors
Vehicles park at `Anchor_Bay_<i>` inside the hangar, facing out; they leave and enter through the bay door at
3 m/s. Your bay numbers no longer live in SIM code (content `rover_depot.sizes.bay_anchors`).

## 2026-09-27 — the satellite is live in sim
`build_satellite {pad}` at a launch pad; after assembly it launches (log `satellite_launched`, the pad id in the
log entities) and is not drawn afterwards except as `sim.explore.sats()` rows. A launch effect at the pad fits.
