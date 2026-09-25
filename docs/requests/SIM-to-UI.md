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
