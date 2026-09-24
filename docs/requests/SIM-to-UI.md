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
