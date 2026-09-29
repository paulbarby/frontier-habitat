# SIM → UI

## 2026-09-24 — answers to UI-to-SIM (v3) and the names that are live now

### B. Your guesses — the real names

1. **Hazard API** (`sim/hazards.gd`), all read-only:
   - `sim.hazards.forecast()` → detected events not started yet, soonest first. Row:
     `{id, kind, name, eta_s, end_s, pos: Vector2, radius, severity 1..3, countered, advice, phase, at, end, whole_map}`
     plus `path: [Vector2, Vector2]` (dust devil) and `strikes: [{eta_s, pos, r, done}]` (meteor shower).
     `phase` is `"forecast"` or `"warning"` (warning = the last `warn_s` seconds). Scheduled (hidden)
     events never appear. For whole-map kinds (`wind_storm`, `dust_storm`, `solar_flare`) `whole_map`
     is true and `pos` is the map centre — treat it as "whole map".
   - `sim.hazards.active()` → the same rows for events happening now (`end_s` = seconds left).
   - `sim.hazards.at_risk()` → `[{id, name, wear, fail_at, eta_s, fault, item, first}]`, soonest failure
     first. `wear` and `fail_at` are 0..100. `eta_s` = -1 when the machine is idle. `item` = the part
     the maintenance and the repair use. `first` = "Maintain now" was ordered.
   - `sim.hazards.zone_at(pos)` → `{meteor, wind, quake}` 0.5..2.0.
   - `sim.hazards.info(building_id)` → `{machine, breach, dust, trip, health, wear?, fail_at?, fault?,
     item?, eta_s?, at_risk?, broken_by_wear?, maint_first?, charge?, charge_cap?, range?, shot_cost?}`
     (wear keys only for machines that have run; turret keys only for turrets).
   - `sim.hazards.event(id)` → the full record of a queued, active or recent event (the last 20 done
     ones), including `hits` (`[{id, dmg, breach?}]`, `[{turret, pos}]` for intercepts) and `result`
     (`{impacts, intercepted, cracks}`). Use this for your "after the event" line (your C4).
   - `sim.hazards.sites()` → meteor fragment sites `[{id, pos, surveyed, units}]`; command
     `survey_site {id}` puts one first. `sim.hazards.craters()` → `[{x, y, r, tick}]`.
   - `sim.hazards.sheltered()` → bool; `sim.hazards.setting()` → "off" | "mild" | "normal" | "hard".
2. **Shelter state**: `state.hazards.shelter` (bool). Prefer `sim.hazards.sheltered()`. The order ends
   by itself when no flare or meteor shower is forecast or active.
3. **`hazard_now`**: `{kind, x, y, severity, in}` or `{kind, pos: Vector2, severity}`. Optional:
   `in` (seconds until it starts, default 1), `duration` (s, weather), `radius` (meteor, quake),
   `length`/`dir` (dust devil). Kinds: meteor, meteor_shower, wind_storm, dust_storm, quake,
   solar_flare, dust_devil. Refused with `debug_only` unless `state.options.debug`.
4. **Building fields**: `breach` (bool) and turret `charge` (float) are on the building record.
   `dust` (bool) on solar arrays; `trip` (bool) on structures a flare switched off. Wear is NOT on
   the building: read `sim.hazards.info(id)` or `at_risk()`. Turret def keys: `turret: true`,
   `turret_range` (70 m; +30 with Meteor Defense II — use `info(id).range`), `charge_cap` 100,
   `shot_cost` 50, `charge_per_day` 240. Counter: `state.stats.meteors_intercepted`.
5. **Log codes**: `hazard_detected` (sev 1), `hazard_warning` (sev 2; dust storm keeps `storm_warning`),
   `hazard_start` (weather, dust devil; dust storm keeps `storm`), `hazard_impact` (meteor, quake),
   `hazard_end` (dust storm keeps `storm_end`), `hazard_intercepted`, `breach`, `breach_sealed`,
   `fault`, `maintained`, `repaired` (v2), `survey`, `shelter`.
   **Alert keys** (with the §2 hysteresis): `hazard:<event id>` (code `hazard`, warning; critical for a
   flare while people are outside and no shelter), `breach` (one alert for all breaches), `maintenance`
   (notice), `solar_dust` (notice), `shelter` (notice), `broken:<id>` (now names the fault and item),
   `output_blocked` (one alert for all machines; the old `blocked:<id>` keys are gone).
6. **Pack recipes**: yes, the recipe id is the item id: `pack_basic`, `pack_applied`, `pack_exotic`
   (`content/recipes.json`; `water_net` = units of network water a batch takes, `auto` = no staff).
7. **Options**: yes. `sim.new_game(seed, "tutorial", {hazards, debug, ...})`; `state.options.hazards`.

### C. Your additions — done

1. `sim.research.lab_info(lab)` now also has `rate` (RP per day, one-minute average) and `base_rate`
   (the same work without the pack boost), plus `packs {item: held}`, `credit {item: RP}`,
   `automation`, `tech`, `mult`, `mult_boosted`, `boosted`, `can_work`, `focus`.
2. `ship {action: "cargo", cargo}` → `{ok: true}`, no flight. `sim.ship.info()` has `cargo`,
   `cargo_items`, `cargos`.
3. `sim.load_state(state, {debug: true})` sets `state.options.debug` for a loaded save.
4. See `sim.hazards.event(id)` above.

### Other names you can use

- `sim.research.packs_of(tech)`, `boost_of(tech)`, `pack_stock()` → `{pack_basic, pack_applied, pack_exotic}`,
  `lock_reason(tech)`, `lab_can_work(lab)`, `cmd set_focus {id, branch}` (branch ids are the keys of
  `content.research_branches`: eng, life, agri, ind, energy, sci, space, **science, haz, suit**).
- Lab block codes: `no_packs` (new), plus v2 `no_project`, `waiting_items`, `no_power`, `disabled`.
  Assembler block codes: `no_water`, `no_input`, `stock_full`, `output_blocked`, `flare`, `no_power`.
- Machine block `fault` while broken by wear.
- `sim.agents.suit_cap()` = seconds of air in a full suit now (research suit_1/suit_2). The colonist
  inspector's suit bar should use it instead of `bal.suit_air_seconds` (`ui/hud/inspector_sections.gd:829`).
- Research tree: 45 techs, new branches `science`, `haz`, `suit`; `sci` is now named
  "Survey and medicine". Tier-1 techs have `boost` (packs that double them); others have `packs`.
- `state.map_size` (810 new games, 256 old saves); `sim.world.size` stays the one to read.

## 2026-09-24 (later) — C1 and C2 are live

- C1: `sim.research.lab_info(lab)` has `rate` and `base_rate` (RP per day, one-minute averages).
- C2: `ship {action: "cargo", cargo}` returns `{ok: true}` and does not fly.
Both are covered by `tests/cases_v3.gd` (`v3_lab_focus_and_supply_cargo`, `v3_research_packs_boost_and_conservation`).

## 2026-09-24 — version-3 showcase saves (810 m map, hazards "normal")

Made by `node tools/godot.mjs script res://tests/make_showcase_saves.gd` (seed 1001). Load with the
boot param `load=res://content/saves/<file>`. The v2 saves (`showcase_early/mid/late/day9`, 256 m) stay.

- `content/saves/showcase_v3_mid.fhsave` — day 13.1, 26 colonists, 93 structures: research lab and
  assembler, industry chain, a level-3 and an L structure, past hazards (craters, fragment piles).
- `content/saves/showcase_v3_late.fhsave` — day 25.0, 66 colonists, 141 structures, every room type
  (cantina, bio-lab, fungus farm, algae bioreactor, recycler, atmosphere processor, two research
  assemblers, XL habitats …), a meteor turret, the forward airlock outpost at the Meridian (hull done,
  stage 2), fragment sites (one far out, from a meteor at 190 m), Refinery 1 at 80 % of its failure
  threshold (in `sim.hazards.at_risk()`), and one breached corridor (Corridor 42). Technicians start to
  maintain and seal within about a minute of play, so shoot at speed 0 or right after the load.
  Part of this colony is set-up, not play (placed finished, one supply pod of rations and water).

## 2026-09-25 — v3.1: airlock cycle phases (V3_1_DESIGN §5.2) are live

- `state.buildings[id].lock.cyc` (airlocks and the lander hatch; `{}` while idle) now has
  `phase` ∈ `enter`, `seal`, `pump`, `open`, `exit` and `pt` (seconds left in that phase), besides
  `agents` (riders), `dir` ("in" = coming in from outside, "out" = going out), `t` (seconds left in
  the cycle) and `total` (cycle length). The phase is updated every tick.
- Shares of the cycle: `balance.airlock_phases` = [0.15, 0.1, 0.5, 0.1, 0.15]. At 10 s a cycle is
  enter 1.5 s, seal 1.0 s, pump 5.0 s, open 1.0 s, exit 1.5 s; an unpowered airlock takes 20 s,
  the same shares. Cycle length did not change. Riders per cycle: `sim.agents.lock_slots(b)` (size M 2,
  size L 4, the lander hatch 2; see the airlock sizes section below).
- `dir "out"`: `pump` lets the air out (amber → red). `dir "in"`: `pump` fills the chamber (→ green).
  Riders are inside the airlock (`agent.where == "lock"`, `agent.bld` = the airlock) for the whole
  cycle. At the end of `exit` an inbound rider is at the airlock centre (`b.pos`) inside and an
  outbound rider at `sim.nav.door_pos(b)` (1.6 m outside the outer wall, on the door axis; was 1.3 m).
- Read helper: `sim.agents.lock_info(id)` → `{cycling, dir, phase, pt, t, total, riders, waiting_in,
  waiting_out}`.
- Queue: `lock.queue` = `[{a, dir}]`, people waiting (inbound ones stand outside).

## 2026-09-25 — v3.1 ships, visitors, credits, trade: names (all live)

**Commands**
- `traffic_answer {id, grant: bool, accept?: int}` — grant (default) or deny an arrival until it
  lands; `accept` = settlers a shuttle may leave (-1 = as many as there are free beds, default).
  Codes: `unknown`, `too_late`.
- `trade {id, buy: {item: n}, sell: {item: n}}` — at a LANDED ship. Buying pays at once and drops
  the units as a pile at the pad (carriers store them). Selling orders units; carriers take them to
  the ship's hold; each unit is paid as it arrives. Codes: `no_ship`, `no_stock`, `no_credits`,
  `not_wanted`, `too_many`, `no_stock_colony`. Result has `cost`.
- `traffic_now {kind, in?}` — debug only (`state.options.debug`), a ship of that kind in `in`
  seconds (default 60). Map your `__fh` command `ship <kind>` to this. (The sim command `ship` is the
  Meridian's and stays.) Kinds: trader, shuttle, liner, medical, science, inspector.

**Reads** (`sim.traffic`)
- `forecast()` → arrivals shown to the player (one day ahead), soonest first; `ships()` → ships in
  orbit/landing/landed/boarding/takeoff. Row: `{id, kind, name, phase, answer, eta_s, at, stay_s,
  people, offer, text, pad, pad_pos, t_s (seconds left in the phase), visitors [agent ids], accept,
  result, stock? {item: units on board}, orders? {item: {n, paid, price}}}`.
  `offer`: trader `{sells {item: {units, price}}, buys {item: {units, price}}}`; science `{buys}`;
  shuttle `{roles [..]}`; liner/medical/inspector `{people, fee}`. `text` = one plain sentence.
- phases: `forecast`, `orbit`, `landing`, `landed`, `boarding`, `takeoff`, then `gone`, `denied`, `left`.
- `find(id)`, `ship(id)`, `credits()` (balance), `credits_audit()`, `free_beds()`.
- `state.credits = {balance, earned, spent, by {start, meals, fees, trade}}` (start 100 in a new game,
  0 after migration).
- Visitors: agents with `kind == "visitor"`, `role "visitor"`, `vkind` (trader/shuttle/liner/medical/
  science/inspector), `ship` (arrival id, -1 = left behind, waits for the next ship of its kind),
  `visit {ate, rec, slept, paid, treated, study, tour, toured}`. `sim.alive_count()` counts colonists
  only. Add `"visitor": "Visitor"` to your role labels if you show roles.
- Log codes: `ship_forecast`, `ship_orbit`, `ship_landing`, `ship_landed`, `ship_takeoff`, `ship_gone`,
  `ship_denied`, `ship_left`, `trade`.
- A landing pad record has `ship` = arrival id while a ship stands or lands on it (-1 / absent).

## 2026-09-25 — v3.1 airlock sizes M and L, landing pad 11.5 m, porch zone (critic round 10; live)

**Airlock sizes**
- The airlock has two sizes: M (index 1, radius 3.4 m, 2 riders per cycle) and L (index 2, radius
  4.0 m, 4 riders). `sim.sizes.sizes_of("airlock")` → `[1, 2]`. Show only these two size buttons (use
  `sizes_of`, not `has_sizes`: S and XL are refused with code `no_size`).
- L needs the research Engineering 1: `sim.sizes.allowed("airlock", 2)` → `{ok: false, code:
  "locked_research", research: "eng_1"}` until then. Placement code `locked_research`.
- Riders per cycle of a built airlock: `sim.agents.lock_slots(b)`; also `sim.bd(b).airlock_slots`.
- Airlocks of a save from before 3.1 keep radius 2.8 m and 2 riders.
- New landing pads: radius 11.5 m (was 9.0). Old pads keep their radius.

**Porch zone** (show it while the player places an airlock, and, if you like, the zones of the
airlocks already built while placing anything)
- Preview of a new airlock: `sim.place.door_strip_for(def_id, pos, rot, size)` → `{p0, p1, half_width,
  porch_length}` (`{}` for a structure without a door). The zone is the strip from `p0` (the outer
  door, on the footprint edge) to `p1` (3.5 m out, `balance.door_strip_length`), `half_width` 1.6 m
  (`balance.door_strip_half_width`) to each side. `porch_length` 2.5 m is the porch itself (paths cross
  it only to use the door); the whole strip is what placement keeps free.
- Built airlocks and the lander hatch: `sim.place.door_strips()` → `[{id, p0, p1, half_width,
  porch_length}]`, by id.
- Placement refuses: a structure on the strip of an existing door (`blocks_entrance`), a corridor across
  it (`blocks_entrance`), a new airlock whose strip covers a structure or a corridor
  (`blocked_entrance`). Sentences: `sim.place.reason_text(code)`.
- A save from before 3.1 can already have something on a porch. The sim leaves it; only new
  placements are refused.
- Showcase: `content/saves/showcase_v31.fhsave` — two pads, a trader and a liner landed (open the trade
  panel on the trader), tourists in a cantina, an airlock mid-cycle. Credits: 600 (see the later
  section below).

## 2026-09-25 (later) — your v3.1 requests 1 and 2 (live)

1. **Settlers by person:** `traffic_answer {id, grant, accept_idx: [i, ...]}` (indexes into
   `offer.roles`; `accept_ids` is the same). Exactly those settlers join. Repeats are dropped, the list
   is sorted; an index outside the list, or `accept_idx` on a ship that is not a shuttle, gives code
   `invalid`. The row then has `accept_idx` and `accept` = its size. The old `accept: n` still works
   and clears an earlier `accept_idx`. Test `v31_settlers_by_person_and_orbit_time`.
2. **Orbit time left:** in `orbit`, `t_s` = seconds before the ship gives up and leaves
   (`at + orbit_hold_h`). Other phases unchanged.
- `showcase_v31.fhsave` now has **600 credits** (booked as start credits), so a purchase at the landed
  trader works. Test `v31_showcase_purchase`: credits go down by the price, the goods lie as a pile at
  the pad, carriers store them (in that busy colony the first pick-up comes after about 450 s).

## 2026-09-25 — door clearance: corridors only on free sides of a room (live)

- New refusal code for `place_link` (corridor) and `sim.place.check_link`: **`door_blocked`**, text
  (`sim.place.reason_text`): "The door would open onto equipment. Choose another side of the room." The
  result also has `room` = the id of the room whose side is blocked. On an airlock this is the chamber and
  porch side (door ±53.5°). Old corridors stay.
- Allowed sides for the ghost and the link tool:
  - a planned room: `sim.place.link_sectors_for(def_id, size, rot)`;
  - a built room: `sim.place.link_sectors(b)`.
  Both return `[{from, to}]`: world angles in radians (sim angle, `Vector2.angle()`), `from < to`,
  counter-clockwise; `[{from: 0, to: TAU}]` = free all round, `[]` = no free side. A corridor from the
  room centre in direction `a` is allowed when `a` (or `a ± TAU`) lies in a sector:
  `sim.place.link_angle_ok_for(def_id, size, rot, a)` / `sim.place.link_angle_ok(b, a)`.
- Turning a room changes its free sides: show them turning with the ghost.

## 2026-09-25 — visitors never raise colony alerts (integration bug in showcase_v31; live)

- Cause: the lander-air alert counted every living agent without a bed, so the liner's 6 tourists gave a
  constant CRITICAL "The lander air has ended. 6 people have no other bed".
- Now no colony alert counts visitors: lander air, hunger, thirst, hurt, rescue, starving/deficiency,
  mono diet, breach occupants, unpowered rooms with people, flare "colonists outside", and the airlock
  congestion air margin (the queue length still counts everyone). Also colonists only: average morale,
  the tutorial "move" step, housing goals, the nutrition charts (`nutrition.colony()`), death causes.
- Visitors DO count in use: `metrics.forecast()` food days, water days and `o2_need` use colonists +
  visitors; new field `forecast().visitors`. `pop` stays colonists (`sim.alive_count()`);
  `sim.visitor_count()` is new.
- For the traffic panel: `sim.traffic.notices()` → `[{code, count, text}]`. Today one code:
  `tourists_no_bed`, text e.g. "3 tourists have no bed. The fee drops." (a tourist who does not sleep
  pays 20 % less). Show it there, not in the alert list.
- Test `v31_visitors_raise_no_colony_alerts`.

## 2026-09-27 — V4 milestone 1: the 2,560 m planet (live)

- New game on the v4 planet: `sim.new_game(seed, "frontier", options)` (scenario "frontier", 2,560 m).
  Make it the default of the new-game screen; keep "tutorial" (810 m) as the first-landing option.
  `options.map_size` also exists (256, 810, 2560) for tools.
- Overlays and tooltips: `sim.world.rad_at(x, y)` (mSv/h), `sim.world.terrain_at(p)` (plain name),
  `sim.world.sun_vis(p, elev, bearing)` with `sim.world.sun_angles(...)` (see SIM-to-RENDER), deposits
  with `kind` and `tier` in `state.deposits`.
- The whole map is 2,560 m: the minimap needs a zoom; fog of war comes in milestone 7.

## 2026-09-27 — V4 milestone 2: bases, Outpost Kit, filters (live)

**Bases** (`sim.bases`)
- `sim.bases.list()` → `[{id, name, core, pos, structures, colonists, beds}]` by id. A new game has one
  base, "Landing base", round the lander (old saves get it on load).
- `sim.bases.base_of(structure_id)`, `sim.bases.base_at(pos)`, `sim.bases.base_of_agent(agent)` (where it
  is now), `sim.bases.home_of(agent)` (its bed's base), `sim.bases.name_of(id)`, `sim.bases.core_of(id)`.
- Filters: every alert in `state.issues` has **`base`** (the base id, −1 = the whole colony);
  `sim.bases.totals(base_id)` = stock of one base in the `inv.totals()` shape (its structures, its ground
  piles, what its colonists carry). Per-base numbers for charts: use `list()` (colonists, beds,
  structures) for now; tell me which series you want per base and I add them.
- Commands: `rename_base {id, name}` (1–32 characters; codes `unknown`, `invalid`);
  `deploy_outpost {x, y, rot, inv, name?}` — takes one `outpost_kit` from inventory `inv` (a ground pile,
  a store or, from milestone 3, a vehicle hold) within 30 m of the place, and sets up an **outpost core**
  there: a new base with its own air for 3 days. Codes: `no_kit`, `kit_far`, `too_close_base` (closer
  than 300 m to another base's core), and the usual placement codes. Result `{id: base id, core}`.
  Preview: `sim.bases.check_outpost(pos, rot)` → "ok" or a code.
- New alert code `core_expiry` (key `core_expiry:<base id>`): "<base name>: the core air ends in …". The
  lander's own `lander_expiry` is unchanged.
- Colonists work, sleep and take core beds at the base they are at; moving between bases comes with
  vehicles (milestone 3).

**Items and buildings**
- Item `outpost_kit` ("Outpost Kit"); recipe `outpost_kit` at the fabricator (16 steel, 8 polymer,
  4 electronics, 4 spare parts; 160 work). Building `outpost_core` (not placeable directly; comes from the
  kit): 4 beds, 120 storage, a hatch, air for 3 days.

**Scale on the v4 map** — new rooms are 1.5 × the v3 radius (every size; `sim.sizes.def_for` already
gives the scaled radius), corridors are `sim.corridor_r()` = 1.5 m in radius (1.2 on older maps).
Exterior structures keep their size. Use the record's `radius` for built structures, the def's for ghosts.

## 2026-09-27 — V4 rules and the 1.5 × rooms (live)

- Rooms are 1.5 × the v3 radius on every map for NEW structures (`sim.sizes.def_for(...).radius`); airlock
  and junction unchanged; old records keep their radius. New games walk 4.0 m/s inside and 3.5 m/s outside,
  carry 4 units and have 130 s of suit air; saves from before V4 keep the v3 numbers (read `sim.bal`, which
  is the right table for the loaded game: never `sim.content.balance` directly).
- `sim.set_freeze_build(on)` for test tools (no construction change while on).

## 2026-09-27 — Corridor links per room (Paul's rule, live for new links)

- A room takes at most **S 4, M 6, L 7, XL 8** corridors. Airlocks and junctions keep their own rules.
- New links on one room are at least `max(28°, door angle)` apart. Door angle = the chord of the door
  housing (3.44 m + 0.3 m gap) at the wall radius (`radius − 0.32`).
- API: `sim.place.max_links(room)`, `sim.place.link_min_angle(room)`, `sim.place.door_angle(radius)`.
- New refusal code **`links_full`**: "This room has all the corridors it can take (S 4, M 6, L 7, XL 8)."
  It comes before `door_blocked` and `ports_full`.
- Old saves keep every link they have. Balance keys: `room_max_links` [4,6,7,8], `door_housing_m` 3.44,
  `door_gap_m` 0.3.

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

## 2026-09-27 — V4 milestone 4: orders (live in sim, `sim/orders.gd`)

**Order a colonist or a group**: command `order {agents: [ids], kind, …, confirm?}`.

| kind | fields | what the colonist does | ends |
|---|---|---|---|
| `go` | x, y, stay? | walks there (into a room if the point is in one) | on arrival (with `stay: true` it becomes `stay`) |
| `stay` | x, y | walks there and stays | when cleared |
| `return` | — | walks to the core of its home base (else a room with air of that base) | on arrival |
| `board` | v | walks to the vehicle and gets in | when seated |
| `work_at` | b | takes only tasks of that structure (any role) | when cleared or the structure is gone |
| `survey` | site | surveys that hazard site (any role); POIs join in milestone 7 | when surveyed |

Result: `{ok (any accepted), code, text, accepted: [ids], refused: {id: {code, text, confirmable}}}`.
Preview for the cursor: `sim.orders.check(agent, payload)` → `{ok, code, text, confirmable}`.

**Refusals** (text is ready for the player, STE):
- `suit_range` "The suit air is not enough to go there and come back." — confirmable
- `exposed_stay` "The colonist cannot stay outside: the suit air ends." — confirmable
- `radiation` "The radiation there is too high (x.x mSv/h)." (above `balance.order_rad_refuse` = 1.0) — confirmable
- `no_path`, `in_vehicle`, `in_airlock`, `no_vehicle`, `no_seat`, `no_building`, `no_site`, `no_base`,
  `not_colonist` (visitors), `dead`, `unknown`, `invalid`.
- With `confirm: true` a confirmable order runs and the colonist does NOT turn back for air or shelter
  while it runs (the player accepted the risk). Show the reason and a confirm button.

**Rules**: an order overrides the colonist's own choices; critical thirst, hunger and exhaustion still
interrupt it and the order continues after. An unconfirmed order that runs out of air margin ends (log
code `order_ended`, "…: the order ended (low suit air).").
`order_clear {agents}` ends orders. Agent field `order` (absent = none):
`{kind, p, b, v, site, stay, confirm, t}`; `agent.goal` says "Going to the ordered place",
"Staying here (order)", "Returning to base (order)", "Working at <name> (order)", "Survey (order)".

**Own job priorities**: `set_jobs {agent, jobs: {category: 0..3}}` (0 = not allowed) and
`set_jobs {agent, clear: true}`. Categories = `sim.orders.job_categories()` (construction, food,
industry, logistics, repair). Agent field `jobs` (absent = colony priorities). A task already taken is
finished first.

**Vehicles**: `vehicle_explore {id, x, y, r}` — the driver takes the vehicle round 8 points on a circle
of r (50–600 m); unreachable points are left out. Row field `explore` in `sim.vehicles.list()` ({} or
`{pts, i, c, r}`). Other vehicle commands end an explore. Driving and boarding orders stay the vehicle
commands of milestone 3 (`vehicle_board` equals `order kind board` for a group).

## 2026-09-27 — debug-only commands for screenshots and the preview (your request)

Only while `state.options.debug` is true (`new_game(..., {debug: true})`, or a loaded save with
`sim.load_state(state, {debug: true})`); otherwise the code is `debug_only`. Each one is written to the log
(code `debug`) and is a recorded command, so a replay stays exact. File: `sim/debug_cmds.gd`.

- `spawn_vehicle {kind, x?, y?, depot?}` (alias `debug_vehicle`): a finished vehicle in a free bay of `depot`,
  else at (x, y), else beside the lander. Result `{ok, code, id}`; codes `invalid`, `no_bay`, `no_place`.
- `place_finished {def, x, y, rot?, size?}` (alias `debug_building`): a finished structure after the normal
  placement check; research does not lock it. Result `{ok, code, id}`; the placement codes.
- `finish_building {id}`: a plan or a half-built structure is finished at once. Codes `unknown`, `not_building`.
- Reserved for later milestones: `reactor_stage {id, stage}` (milestone 6) and `reveal {x, y, r}` (milestone 7).

Orders are published above in this file ("V4 milestone 4: orders"): the live names are `order`,
`order_clear`, `set_jobs`, `vehicle_explore` (not the mock `order_give`, `order_cancel`, `set_priority`).

## 2026-09-27 — V4 milestone 5: materials, crafting, tech tree (content live)

Counts: **72 items, 46 recipes (+ cook), 82 techs**. All in content; nothing new to call except below.

- Item category **`find`** ("Finds", order 9): `data_core`, `derelict_parts`, `meteorite_sample`,
  `blueprint_fragment` (points of interest give them in milestone 7).
- Three tiers of materials. Basic: ore, silicate, ice, metal (steel), glass, polymer. Mid: alloy, titanium,
  ceramic, graphite, carbon_fiber, acid, coolant, battery_cell, rover_parts, slag (by-product). High-end:
  yellowcake → fuel_rod, he3_regolith → he3_gas → he3_fuel, rare_earth_ore → rare_earth_oxide → magnet /
  superconductor, graphite → graphene, exotic → purified_crystal → crystal_lattice → metamaterial.
- Recipes can have **`min_level`** (2 for alloy_graphite, superconductor, metamaterial, hull_plate_ti,
  electronics_graphene). `set_recipe` refuses with code **`level_low`**; `prod.machine_block` gives
  `level_low` too. Show "Needs level 2" on the recipe.
- A recipe can make two items (by-product): `alloy` and `titanium` also make `slag`.
- **Mining by deposit kind** (v4 map): a mine gives what its deposit holds —
  `sim.prod.deposit_info(deposit)` → `{item, research?, per_batch?}`; `sim.prod.deposit_locked(deposit)`.
  A locked deposit gives `machine_block` code **`deposit_locked`** ("Research <tech> first to mine this").
  Content: `terrain_v4.deposit_items`. Old maps: iron ore as before.
- Techs: new branches `mat`, `nuc`, `veh`, `explore`, `rad`, `deep` (plus the old ones). New `unlocks` keys:
  `deposits` [deposit kinds] and `orders` [command names] (`logi_routes` unlocks `vehicle_route`; code
  `locked_research` before it). Tier 4 of the new branches uses `pack_advanced`; tier 5 uses `pack_deep`.
  Effects of `exp_*`, `rad_*` and `nuc_safety` arrive with milestones 6 and 7 (their text says so).
- New buildings (ART-HAB's): rooms `steel_mill`, `titanium_smelter`, `ceramics_kiln`, `carbon_works`,
  `battery_plant`, `parts_works`, `magnet_works`, `superconductor_lab`, `metamaterial_foundry` (staffed,
  S–XL); automatic exteriors (no staff, like the research assembler) `fuel_rod_plant`, `he3_separator`,
  `graphene_reactor`, and now placeable `chemical_plant`, `crystal_refinery`. `launch_pad` needs `exp_sat`;
  `fission_reactor` needs `nuc_reactor`.
- Vehicle bonuses: `sim.vehicles.charge_cap(v)` (row `charge_cap` includes research).
- **Food margin (new games)**: each settler lands with 8 ration meals (a ground pile at the landing place;
  log code `settler_supplies`). Research-pack machines leave an item alone while a planned structure waits
  for it. Saves from before V4 keep the old rules.

## 2026-09-27 — "stay" at the lander fixed; indoor orders never check suit air

Your finding is fixed: an order whose walk stays inside (no open ground, no airlock) is never refused for suit
air. `stay` in the room the colonist is in is accepted even with an empty suit. Test
`v4_indoor_orders_need_no_air`. (Walking outside, the hatch or airlock fills the suit first; long walks are still
refused.) Depot bays moved inside the hangar (see SIM-to-RENDER.md); a colonist boards at the bay door.

## 2026-09-27 — V4 milestone 6: reactor, disasters, radiation dose (live in sim, `sim/reactors.gd`)

**Reactor rows**: `sim.reactors.list()` → `[{id, name, pos, heat, stage ("ok"|"warning"|"critical"|"breach"),
rate (heat per s), next_stage, next_phase_s (-1 = not coming), running, scram, scram_left_s, evac, fuel_s, rods,
coolant, blast_r (60), zone_r (140)}]`. `sim.reactors.forecast(building)` gives the same forecast for one.
Heat: 20 cold, 40 running; warning 60, critical 85, breach 100. Running adds 0.05/s, a damaged or worn
reactor more; coolant (1 unit per 150 s) takes 0.06/s off, without coolant only 0.01/s. So a reactor without
coolant reaches warning in 500 s, critical in ~1100 s, breach in ~1500 s — the forecast says when.
One fuel rod runs 1,200 s. Carriers keep 2 rods and 8 coolant in its buffer (urgent when hot).

**Commands**: `reactor_scram {id}` (fission stops after 12 s; `done` if already), `reactor_restart {id}`
(`too_hot` at warning or above), `reactor_cool {id}` (dumps up to 4 coolant, −12 heat each; `no_coolant`),
`reactor_evacuate {id}` → `{moved, stuck}`: colonists within 140 m get a confirmed `stay` order in the nearest
room with air outside the zone (`agent.order.evac` = reactor id); the orders end when the core is safe again.
Debug only: `reactor_stage {id, stage}` (ok | warning | critical | breach; breach explodes on the next second).

**Breach**: every structure within 60 m is destroyed (log `destroyed`, contents lost; the lander and other
special structures are damaged instead), everyone within 60 m dies, vehicles break; a radiation zone of 140 m
(60 mSv/h at the centre, halving every 2 days). Log `reactor_breach`.

**Other risky plants**: crystal refinery without power while a batch runs → alert `unstable_power` with a
countdown (45 s), then an explosion of 14 m (log `unstable_blast`). A chemical plant below health 50 leaks: a
toxic zone of 30 m for 2 days hurts people outside in it (alert and log `toxic_leak`).

**Zones**: `sim.reactors.zones()` → `[{kind "rad"|"toxic", x, y, r, peak | dmg, t0, half_s | until, src}]`.
`sim.reactors.rad_at(Vector2)` = the ground (v4 map) + zones, mSv/h (use this for the radiation overlay now,
not `world.rad_at`). `sim.reactors.toxic_at(Vector2)` = damage per day.

**Dose**: `agent.dose` (mSv; absent = 0). Inside a room a tenth of the outside rate, a pressurised cabin 0.3.
It halves slowly (5 % a day; 20 % with Radiation Medicine). Alerts `rad_dose` at 250 mSv (warning) and 750
(critical); above 1,000 it hurts ("radiation sickness"). Research Dosimetry and Shielded Suits cut the dose
10 % and 30 %. Orders into ground above 1 mSv/h are refused unless confirmed.

**Alert codes**: `reactor_warning`, `reactor_critical`, `reactor_fuel`, `unstable_power`, `toxic_leak`, `rad_dose`.
**Log codes**: `reactor_warning`, `reactor_critical`, `reactor_ok`, `reactor_scram`, `reactor_cool`,
`reactor_evacuate`, `reactor_breach`, `destroyed`, `unstable_warning`, `unstable_blast`, `toxic_leak`.

## 2026-09-27 — V4 milestone 7: fog of war, points of interest, finds, satellite (live, `sim/explore.gd`)

Only on the 2,560 m map; older maps have no fog (`sim.explore.active()` false, `explored()` always true).

**Fog**: `sim.explore.fog()` → `{cell: 16.0, n: 160, bits: PackedByteArray n*n (row j*n+i, 1 = explored), rev,
count}`. Upload the texture only when `rev` changes. `sim.explore.explored(Vector2)`, `explored_share()` (0..1).
The landing area (300 m) is known at the start. Colonists outside reveal 40 m round them, rovers 120 m, hoppers
200 m (+25 % with Survey Methods). A revealed deposit becomes `surveyed` (log `deposit_found`).

**POIs**: `sim.explore.pois()` → `[{id, kind, x, y, found, visited, need}]`; content `terrain_v4.explore.pois`
(name, desc, finds). Kinds: `wreck` (5), `derelict_probe` (3), `meteorite_field` (4), `cave` (4, near mountain
feet), `anomaly` (3, anywhere, often only a hopper reaches it), `rich_deposit` (4). 380–1,180 m from the
landing. Show only `found` ones. A POI is visited when a colonist comes within 20 m (`need`: `any`,
`on_foot` = somebody outside, not only in a vehicle, `scientist` = a scientist among them). Finds go into
the cargo of a vehicle there, else a ground pile at the POI. Anomaly: +200 research points. Rich deposit: a
new deposit (1,500 units, `rich: true`). Logs `poi_found`, `poi_visited` (with what was found).
Order: `order {agents, kind: "survey", poi}` walks there (suit and radiation refusals as usual; confirm).

**Satellite**: `build_satellite {pad}` (a launch pad; research Orbital Survey; the parts are carried there,
technicians assemble it, then it launches; it uses the depot order record `vorder` with kind "satellite").
`sim.explore.sats()` → `[{id, name, bands_done, bands (16), next_s, band, uplink}]`. With an uplink (any
powered comms tower) it maps one band (a strip across the map) every 60 s; the POIs in it are found; with
Deep Scan the deposits in it are surveyed too. Logs `satellite_launched`, `satellite_done`.

**Debug**: `reveal {x, y, r}` (debug=1 only).
**Content**: blueprint fragments → 3 advanced packs at the research assembler (`pack_blueprint`, Survey Methods).

## 2026-09-27 — V4 milestone 8: save schema 5, `showcase_v4.fhsave`

- Saves are **schema 5**. Migration: v1–v3 as before; v4 (V3.1) → 5 adds `bases`. Saves from before V4 keep
  the v3 balance and their map size (256 or 810 m). A v4 save made during development gets fog on load.
- **`content/saves/showcase_v4.fhsave`** (made by `tests/make_showcase_v4.gd`, day 12, seed 1001, hazards normal):
  2,560 m map, 20 colonists, two bases (landing base and "Crater camp", ~440 m apart), a size L rover depot with
  a medium rover on a route to the camp (10 metal each way out), an expedition rover with two people at a deep
  crater rim, a fission reactor (2 rods, 8 coolant, ~170–280 m from the lander), a launch pad, comms tower and
  battery, and a survey satellite with 5 of 16 bands mapped (fog about 36 % explored). Debug is off in the
  save; load it with `debug=1` to use the debug commands (for example `reactor_stage` for the disaster shots).

## 2026-09-27 — branch names and item tiers are in content (your two asks)

- `research.json` `branches` has 16 rows: the 6 new ones use your names and colours (`mat` Materials, `nuc` Nuclear,
  `veh` Vehicles, `explore` Exploration, `rad` Radiation, `deep` Deep tech), rows 10–15. `BRANCH_EXTRA` can go.
- Every item in `items.json` has `"tier": 1 | 2 | 3` (the numbers your reader takes) and `"tier_name": "basic" |
  "mid" | "high"`. 32 basic, 20 mid, 20 high. Raw deposits follow their deposit tier; finds: derelict parts and
  blueprint fragments mid, data cores and meteorite samples high; electronics, composite, hull plates and rocket
  fuel mid (V4 §4.1 table).

## 2026-09-27 — showcase_v4 rebuilt: the uplink has power

Your finding is fixed. The comms tower and the launch pad are on their own powered grid (two solar arrays, two charged
batteries, cables). The satellite maps a new band every 60 s after load (6 of 16 at load; 8 or more after 130 s). The
base also got a size L habitat joined by a corridor, so all 20 colonists have beds: no critical alert at load (it was
"The lander air has ended. 4 people have no other bed.", true for the day-12 reference base). Test `v4_showcase` now
checks the uplink, both structures' power, new bands and no critical alert.

## 2026-09-28 — the long frame after a debug `reveal`

Measured natively on showcase_v4 (`tests/dev/reveal_time.gd`): `reveal` touches only the fog cells within r (no fog
rebuild), then one loop over the deposits and POIs (under 100 entries) and one log line per find; no path planning.
reveal() itself 0.06 ms (r 100) to 2.1 ms (r 4,000); the whole tick with the command 1.2–2.9 ms; a satellite band
1.4 ms. In the test `long_v4_tick_max` a 1,000 m reveal that finds a POI takes 1.3 ms. So the 126 ms you measured is
not the reveal: most likely it was the old 50–78 ms walk-search ticks (now fixed: worst tick in 900 s of showcase_v4
16–20 ms), or several sim ticks run in one web frame to catch up. If it comes back with the current build, send me
the tick number and the command.

## 2026-09-28 — rovers never drive through a corridor; depot bays stay open

- Built corridor tubes close the rover grid (half a rover's width added). A drive's first and last straight
  stretches must also clear every tube and structure. A drive that finds no way returns code `no_route`; the
  vehicle does not move, `block` = `no_route`, and the row has `block_text` "No route: the way is blocked"
  (log `vehicle_stopped` once). The check is bounded: closed areas of the rover grid are found once per change
  (a fill of at most 6,000 cells), so a closed-in start or end fails at once (no whole-map search).
- A driving vehicle plans the rest of its way again when structures change (never through a new tube).
- Placement refuses, with code `depot_blocked` "This would block the rover depot.": a corridor or structure on a
  bay's taxi stretch or 6 m in front of a bay door; anything that would cut every bay of a depot from open ground
  (planned structures count as built); and a new depot whose bay doors face something already there.
- A depot closed in already (an old save) is left as it is: its vehicles say "no route", other placements near it
  are not refused for it, and the game goes on.
- showcase_v4 rebuilt (the depot faces open ground; the route rover drives its route). Test
  `v4_rover_tubes_and_blocks`.

## 2026-09-28 — every lock explained (Paul was stuck on the workshop)

- **`sim.place.lock_info(def_id, size = 1)`** → `{locked, kind ("stage" | "research" | "size" | "unknown" | ""), text,
  stage, tech}`. `text` is plain STE with the requirement and the progress now, for example
  "Unlocks at stage Stable outpost: 8 colonists (now 6), 1 day with safe reserves (now 0.4)." or
  "Research Rover Parts first." or "Research Structural Engineering first for size L." Show it on a locked
  build button and in the placement hint. `sim.place.stage_text(i)` gives the stage sentence alone.
- The refusal texts use it: `sim.place.reason_text("locked" | "locked_research" | "no_size")` now returns the
  lock text of the structure checked last (the preview's `check_building`), and a refused `place_building`
  command result has `text` (the same sentence). You need no change for the toast; the build menu can call
  `lock_info` directly.
- Balance: the **workshop** (spare parts) is open from the landing (was stage 2, Growing settlement). Old games
  get it at once.

## 2026-09-28 — "Output blocked" popping in and out (Paul)

SIM side, measured on a Frontier game and in `v3_alert_output_blocked_300s_frontier`: the key `output_blocked` is
stable (one key for all machines; the text and entity list change, the key does not), it is raised after 20 s and
cleared only after 30 s without the condition, on every map and rule set. What did flip every few seconds was the
issue's `live` field: false for each moment a carrier took one unit and the buffer was not full. From now on `live`
stays true until the condition has been gone for 10 s (`balance.alerts.live_hold`), so a short drop no longer shows
as "clearing". If the panel still blinks, it is the UI's own list handling of the text change (the machine list in
the text can change while the key stays).

## 2026-09-28 — storage on every structure (Paul)

`sim.inventory` is the same object as `sim.inv`.

- **`sim.inventory.contents(x)`**, x = a building record or a vehicle record (`sim.vehicles.get_v(id)`) →
  `{capacity, used, free, full, items {item: n}, reserved {item: n},
    buffers {in {…}, out {…}, in_cap, out_cap, in_used, out_used},
    other {fill, site, upgrade, build, ship, trade, floor: {item: n}} (only the ones it has),
    spoil {item: seconds until the next unit spoils}, cold (bool), all {item: n}}`.
  `capacity/used/items/reserved` are its store: storehouse, cold storage, lander, outpost core, depot store,
  or a vehicle's cargo; a machine without a store shows its output buffer there. Machine buffers (kitchens with
  their ingredients and dishes, research assemblers with packs, refineries, …) are in `buffers`. `floor` = ground
  piles inside a room. `spoil` only where the item spoils (not in cold storage, not in input buffers).
- **`sim.inventory.by_structure(base_id = -1)`** → one row per structure or vehicle with an inventory, then
  "On the ground" (`kind` "ground", id -1) and "Carried" (`kind` "carried", id -2):
  `[{id, name, def, kind ("structure" | "vehicle" | "ground" | "carried"), base, capacity, used, full,
  items {item: n}}]`. With a base id, only that base (vehicles and piles by where they are). All rows together
  are every unit in the world; test `v4_inventory_contents` checks that against the ledger.

## 2026-09-29 — "OUT OF REACH" 30-50 m from an airlock (Paul)

- **Cause found (SIM):** a colonist already outside with a part-used suit tried a plan's task, could not do it on
  the air it had left, and marked the task "suit_range" **for everybody** (the task rested 15 s for all, and after
  20 s of such marks the plan was flagged too far: block `suit_range`, which your status shows as "OUT OF REACH").
  Carriers work outside a lot, so this happened near airlocks. Now such a refusal counts only for that colonist;
  only a refusal with a full suit (or from inside) marks the task for everybody. Distances, suit numbers, the
  airlock choice and the access points were checked and are right (all exterior types 30-54 m from an airlock:
  in reach, and none is flagged in half a day of play).
- **`sim.agents.reach_info(b)`** → `{ok, why ("ok" | "no_air" | "no_access" | "no_path" | "too_far"), text,
  walk_m (on foot from the best airlock door to the best access point; -1 when none), straight_m, reach_m (the
  limit, one way), lock (id or -1), lock_name, point}`. `text` is ready STE, e.g. "Too far: 162 m on foot from
  Airlock 2; a suit allows 141 m out and back." Please show it in the inspector for blocks `suit_range` and
  `unreachable` instead of a bare "OUT OF REACH" (it runs up to 24 walk searches: call it on selection, not every
  frame).

## 2026-09-29 — "OUT OF REACH": your hypothesis was right (the mark stayed)

- The "unreachable" mark (your OUT OF REACH) was cleared only when the walking graph changed. It was set after
  three failed walks to the structure, and walks also fail for reasons that are not the structure: a colonist
  re-planning its walk from a cell that a neighbour under construction had just closed. Near a busy airlock with
  structures going up round it, that marked a plan 30-50 m away and it stayed marked.
- Fix: (1) before a structure is marked, SIM checks a walk from the airlocks with air to it (`reach_info`); if one
  exists, only that task fails and work goes on; (2) a mark now ends after 120 s at the latest and the colony tries
  again (logged once per map state); (3) the earlier fix stays: a part-used suit outside no longer marks a task too
  far for everybody. `reach_info` is unchanged.
