# UI → SIM

## 2026-09-24 — version 3 (V3_DESIGN §2, §4, §5, §8)

The interface calls the contract names now and falls back safely when a name is missing
(`.get()` and `has_method`). Below: what the UI reads today, what it guessed, and four small
additions it needs. File references are to `ui/data.gd` unless named.

### A. Already matched to your code (no action; tell me if a name changes)

| UI reads | your code |
|---|---|
| `sim.research.lab_info(lab: Dictionary)` → `focus, mult, mult_boosted, boosted, can_work, packs` | `sim/research.gd` |
| `sim.research.lock_reason(tech) -> String` (shown under "Why it cannot run now") | `sim/research.gd` |
| content `techs[t].packs {item: n}` (nodes and detail panel) | `content/research.json` |
| `set_focus {id, branch}` ("" = no focus) | `sim/commands.gd` |
| `sim.ship.info().cargo`, `.cargos {kind: {item: n}}` | `sim/ship.gd` |
| `ship {action: "supply_run", cargo}` | `sim/ship.gd` |
| `maintain {id}`, `shelter {on}`, `hazard_now {...}` | `sim/commands.gd` |
| issue field `live` (false while an alert waits `clear_after`) → card shows "CLEARING", dimmed | `sim/alerts.gd` |

### B. Guesses — please confirm or tell me the real name

1. **Hazard API** (§4.4): `sim.hazards.forecast()`, `active()`, `at_risk()`, `zone_at(pos)`.
   Rows read: forecast `{id, kind, name, eta_s, pos, radius, severity, countered, advice}`; active rows
   the same plus `end` (tick) or `left_s`; at_risk `{id, wear, fail_at, eta_s, fault}`; zone_at
   `{meteor, wind, quake}` (0.5..2.0). `pos` may be a Vector2 or `[x, y]`; `null` = whole map.
2. **Shelter state**: the UI reads `state.hazards.shelter` (bool, or `{on: bool}`), else
   `state.policies.shelter`. Which one is it?
3. **`hazard_now` payload** from `__fh.cmd("hazard <kind> [x y] [sev]")`:
   `{kind, severity, x, y, pos: Vector2(x, y)}` (x, y, pos only when given). Use whichever you like.
4. **Building fields**: `wear` 0..100, `fail_at`, `fault` ("mechanical" | "electrical" | "seal"),
   `breach` (bool or Dictionary), turret `charge`; turret def keys `turret: true` or
   `intercept_range` (m), `charge_cap`, `charge_per_shot`; turret `stats.intercepts`.
5. **Log codes the UI toasts once each** (`ui/hud/watchers.gd` HAZARD_LOG): `hazard_impact` or
   `impact`, `hazard_end`, `breach`, `fault`, `repaired`, `intercepted`, `maintained`. Detection and
   warnings should come as **alerts** (warning or critical): the UI toasts each alert key once, per §2.
   Tell me your codes and I change one table.
6. **Pack recipes**: the Labs page shows `recipes[<pack item id>]` (for example `recipes.pack_basic`)
   as "Recipe: water 1 -> 1 pack". Is the recipe id the item id?
7. **`options.hazards`** ("off" | "mild" | "normal" | "hard") and **`options.debug`** (bool) are passed in
   `sim.new_game(seed, "tutorial", options)` from the new-colony screen and the boot parameters
   `hazards=` and `debug=1`. `state.options.hazards` is shown on the Hazards page.

### C. Needed additions

1. **Per-lab rate.** §8 asks for "each lab's rate (base vs boosted)". `lab_info` gives multipliers only.
   Please add `rate` (RP per game day of this lab, a one-minute average like `rp_rate()`) and, if easy,
   `base_rate` (the same without packs). The UI shows them as soon as the keys exist.
2. **Set the cargo without a flight.** The Meridian panel lets the player pick the cargo. Today the only
   way to store the choice is `ship {action: "supply_run", cargo}`, which also flies. An unknown action
   keeps the cargo but returns `invalid`, so the player sees "Refused". Please accept
   `ship {action: "cargo", cargo}` → `{ok: true}`. Until then the UI keeps the pick locally and sends it
   with the next "Supply run" press.
3. **Debug on a loaded save.** `debug=1` with `load=<save>` cannot set `options.debug` (the UI must not
   write state). Please give a way: for example `sim.load_state(state, {debug: true})` or a
   `sim.set_debug(on)` that is not saved. Until then `hazard <kind>` works only in a new game started
   with `debug=1`.
4. **(Optional) `sim.hazards.info(id)`** fields the UI could show on click: `hits`, `result` after the
   event (damaged structures, breaches, people hurt) — for an "after the event" toast line.

### D. UI side of §2 (for your test)

`ui/hud/alert_gate.gd` + `tools/ui/test_alert_gate.gd`: a toast only for a new key (warning or
critical), never again for 180 s after it cleared; notices never toast; `blocked:<id>` keys count as
one alert `output_blocked`. Run: `node tools/godot.mjs script res://tools/ui/test_alert_gate.gd`.

### E. Update 2026-09-24 (later) — your hazards.gd landed; UI now uses it

Matched: `forecast()` / `active()` rows (`end_s`, `whole_map`), `info(bid)` for wear, fault,
item, breach and turret, `at_risk()`, `sheltered()`, `zone_at()`, `turret_range(b)`, log codes
`hazard_detected/start/impact/intercepted/end`, `breach_sealed`, `shelter`, `survey` (toasted
once each; `breach`, `fault`, `maintained`, `hazard_warning` are not toasted because your alerts
cover them), `load_state(state, {debug: true})`, `hazard_now {in}`. Items B1–B5 and C3 are closed.
Still open: **C1** per-lab `rate`, **C2** `ship {action: "cargo"}`.
## 2026-09-25 — version 3.1 (UI)

Used as published in SIM-to-UI (thank you): `sim.traffic.forecast() / ships() / credits() / free_beds()`,
`traffic_answer {id, grant, accept}`, `trade {id, buy, sell}`, `traffic_now {kind, in}` (my `__fh` command
`ship <kind> [s]`), `state.credits`, visitor agents (`kind`, `vkind`, `ship`, `visit`), log codes
`ship_*` and `trade`, `lock.cyc.phase` (airlock sounds). Test: `node tools/godot.mjs script
res://tools/ui/test_ships_ui.gd` (14 checks on showcase_v3_late: pad, cable, trader, shuttle, liner, sale, visitors).

### Requests

1. **Choose which settlers stay.** §6.5 asks for "pick which immigrants to accept (role, needs)". `accept` is
   a count. Please accept `traffic_answer {id, grant, accept_idx: [i, ...]}` (indexes into `offer.roles`). The
   shuttle dialog then shows one check box per settler instead of the count. Until then it says: "The shuttle
   chooses which of them stay."
2. **Orbit time left.** In `orbit`, `t_s` is 0 (`t` = arrival tick). The UI computes the wait itself from
   `at + orbit_hold_h`. A `t_s` = seconds before the ship leaves would be simpler and safer.
3. **(For information)** A new landing pad needs a cable before ships come (`powered`). The traffic panel is
   empty until then. If you want, a notice alert "Landing pad has no power: ships cannot land" helps players.
## 2026-09-25 (later) — door sectors: the name the UI calls

The link tool and the room ghost draw the door sectors on the wall ring (green free, red blocked) and show
your refusal sentence (`sim.place.reason_text(code)`) as the placement hint. Please publish:

- `sim.place.blocked_sectors(def_id: String, size: int) -> Array` = the blocked ranges `[[a0, a1], ...]` in
  **model degrees** (0 = model +X, counter-clockwise from above; the content angle is this + the room's
  `rot`), the same numbers as `docs/requests/ART-HAB-door_blocked.json` (airlocks: chamber and porch side
  included). `[]` = every angle free.

Until it exists the UI reads a copy of ART-HAB's file (`assets/ui/door_blocked_fallback.json`) and only
WARNS ("Equipment blocks this side of ..."); with your method present it stops warning and shows your
refusal. When you publish, I delete the copy. Also 1 and 2 of your answer (settlers by person, orbit
`t_s`): thank you, the shuttle dialog will use `accept_idx`.
**Update 2026-09-25 (later):** found and used your `door_ranges` / `link_angle_ok_for` (the UI now asks
`link_angle_ok_for` for every arc point, so the ring and your refusal always agree). No need for
`blocked_sectors`; the ART-HAB copy is deleted. Settlers by person (`accept_idx`) and orbit `t_s`: in use.
## 2026-09-27 — V4 helpers and SIM-driven screens: names I need (V4_DESIGN §5, §6)

1. **Why is this colonist idle?** The UI now explains structures from `b.block` (all codes are mapped; an unknown
   code is shown by name). For colonists it can only guess from `goal == "Idle"`, needs and `backoff`. Please add
   `sim.agents.why(agent) -> {code, text}` (for example `no_job_for_role`, `jobs_unreachable`, `needs_first`,
   `waiting_airlock`, `refused_order`) so the inspector says the real reason.
2. **Fog of war** (milestone 7): `sim.explore.known(pos) -> bool` or a grid I can paint; the minimap and the
   planner overlay "explored" use it.
3. **Vehicles** (milestone 3): the list (`id, kind, pos, fuel/charge, cargo, seats, crew, wear, route`), the
   range from a position (for the "vehicles" planner overlay), and the command names for board, drive, route.
4. **Orders**: the command names and refusal codes for go to, board, drive, explore, survey, work at, stay,
   return, job priorities and allowed jobs; and how an order in progress shows in the agent record.
5. **Reactor**: the state record (temperature, coolant, fuel, phase warning/critical/breach, forecast seconds,
   blast radius) and the commands SCRAM, cool, evacuate with their refusal codes.
6. **Tech tree 4.0**: the new branches (vehicles, exploration, radiation, logistics, deep tech) come through
   `research.json`; the codex and the research screen read them as they land. Nothing needed unless the record
   shape changes.
7. **Outpost Kit deploy tool**: I use `sim.bases.check_outpost(pos, rot)` for the preview and `deploy_outpost`;
   please confirm the kit's inventory can be a vehicle hold once vehicles exist (you wrote "from milestone 3").
## 2026-09-27 (later) — the shapes the UI screens use now (mock), for your v4 names

The orders, vehicle and reactor screens are built against a mock with these shapes (`ui/v4_data.gd` header).
If yours differ, tell me the real names and I switch the adapter; the screens do not change.
- `sim.vehicles.list()` → `[{id, kind (small_rover|medium_rover|hopper|satellite), name, pos, charge 0..1, fuel 0..1,
  range_m, cargo {item: n}, cargo_cap, seats, crew [agent ids], wear 0..100, state (parked|driving|charging|exploring|broken),
  base, route (null | {from, to, load {item: n}, unload})}]`
- `sim.orders.of(agent_id)` → `{kind, target, status (active|done|refused), reason, since}`; `sim.orders.priority(agent, job)` 0..3
  with jobs `build, haul, produce, farm, cook, research, medical, repair`.
- `sim.reactors.list()` → `[{id, name, pos, power_out, temp, temp_max, coolant 0..1, fuel_rods, phase (normal|warning|critical|breach),
  next_phase_s, blast_r, zone_r, scram}]`
- Commands: `order_give {agents, kind, target, force}` (refusal codes seen by the UI: `no_air`, `radiation`, `no_seat`, `busy`,
  `not_in_base`), `order_cancel {agents}`, `set_priority {agent, job, value}`, `vehicle_order {id, kind, target}` (`out_of_range`),
  `vehicle_route {id, from, to, load}` (`wrong_vehicle`), `vehicle_route_clear {id}`, `reactor_scram / reactor_cool / reactor_evacuate {id}`.
## 2026-09-27 — vehicles switched to your live names; one debug command asked

The vehicle screen, routes, the rover depot panel (Vehicles tab: bays, the build order with progress and Cancel,
a Build button per kind) and the Outpost Kit from a vehicle's cargo now use your commands: `build_vehicle`,
`cancel_vehicle`, `vehicle_board`, `vehicle_drive`, `vehicle_return`, `vehicle_stop`, `vehicle_alight`,
`vehicle_cargo`, `vehicle_route {id, a, b, load, back}` / `{id, stop: true}`, `deploy_outpost` with `cargo_inv`.
Orders and the reactor stay on the UI mock until you publish them. I see `sim/orders.gd` (kinds go, stay, return,
board, work_at, survey; `agent.order`, `agent.jobs`): I will switch when it is in SIM-to-UI.md.

**Asked:** a debug-only command to put a vehicle (and a finished depot) on the map, like the hazard and traffic
debug commands (`debug_only` without debug), e.g. `debug_vehicle {kind, x, y, depot}` and
`debug_building {def, x, y, rot, size}` (spawn_active). The web screenshots of the live vehicle screens need it;
the UI does not write state itself.
## 2026-09-27 — orders switched to your live names; one finding

The orders window (Go to, Stay at, Stay here, Survey a hazard site, Work at, Return, Board, Cancel), the confirm
step and the Priorities tab (your five categories, `set_jobs` and `clear`) now use `order`, `order_clear`,
`sim.orders.check` (preview before sending, your STE texts shown as they are; "Confirm anyway" only when every
refusal is `confirmable`), and `vehicle_explore {id, x, y, r: 150}`. The reactor stays on the UI mock.

**Finding:** in a new Frontier game (paused, a few ticks run), `order {kind: "stay", x, y}` at the lander's own
position, for a colonist who is inside the lander, is refused with `suit_range` ("The suit air is not enough to go
there and come back."). `room_at` returns the lander (57) and `atmo_comp` has it. Staying in the room it is in
should not need suit air. Test: `tools/ui/test_v4_screens.gd` prints a NOTE line when this happens.
## 2026-09-27 — milestone 5 in the UI; two content additions asked

The research tree shows all 82 projects in 16 lanes, the codex and crafting tree cover all 72 items with a tier,
and "why stopped?" explains `level_low` (reads `recipe_of(b).min_level`) and `deposit_locked` (reads
`sim.prod.deposit_info(d)` for the deposit under the mine).

**Asked (content, not code):**
1. `research.json` `branches` has 10 rows. The techs use 6 more: `mat`, `nuc`, `veh`, `explore`, `rad`, `deep`.
   The UI adds names, colours and rows for them (`ui/data.gd BRANCH_EXTRA`: Materials, Nuclear, Vehicles,
   Exploration, Radiation, Deep tech). Please add them to `branches` so there is one source.
2. `items.json` has no tier. The UI computes one (`ui/data.gd TIER_SEED` for raw and base materials, then the
   highest input tier over the cheapest recipe; basic 1, mid 2, high-end 3). Please add `"tier": 1|2|3` to each
   material, component and pack. The UI reads `tier` first when it is there.

## 2026-09-27 — milestones 6 to 8 in the UI; one finding in showcase_v4

The UI mock is removed. The reactor window, the banner and the confirm steps use `sim.reactors.list()` and
`reactor_scram`, `reactor_restart`, `reactor_cool`, `reactor_evacuate` (your refusal codes show as text:
`too_hot`, `no_coolant`, `done`, `running`). Dose (`agent.dose`) is on the colonist card and in the colonists
list. Points of interest (`sim.explore.pois()`, found ones only) are in Find, on the minimap and as tags in the
3D view; the Survey order sends `{kind: "survey", poi}`. The minimap draws the fog (`sim.explore.fog()`, remade
only when `rev` changes), the satellite (`sim.explore.sats()`) and its mapped bands. The launch pad has a
Satellite tab with `build_satellite {pad}`.

**Finding:** in `content/saves/showcase_v4.fhsave`, Comms Tower 1 and Launch pad 1 have `powered = false` at
load and after 300 ticks, so `explore.uplink()` is false and Survey satellite 1 does not map (5 of 16 bands
stay). The note says the save has "comms tower and battery". Test: `tools/ui/test_v4_live.gd` prints
"NOTE satellite uplink at load: false".

## 2026-09-28 — locks shown everywhere; the output-blocked alert comes and goes

`sim.place.lock_info` is used on the build cards (with a one-line form the UI makes), the placement hint, the
codex ("How to unlock") and the advisor. Thank you.

**Finding (alert flicker):** in `showcase_v4`, with a powered mine whose output buffer is kept full, the issue
`output_blocked` is in `state.issues` at 60 s, gone at 120 s and back at 180 s (test
`tools/ui/test_alert_steady.gd`). Between, the mine runs a batch (block ""), so the condition is off longer than
`clear_after`. The UI now holds this alert 180 s from its first clear, so the panel is steady; the log may
still show it cleared and raised. Please check whether a machine with a full buffer and a finished batch should
count as blocked through the batch.
