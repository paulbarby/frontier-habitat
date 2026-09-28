# SIM progress

Owner: SIM agent. Files: `sim/**`, `content/**`, `tests/**`.
Contract: `docs/AAA_DESIGN.md` sections 2 to 10; version 3: `docs/V3_DESIGN.md`.
The v3 sections are at the END of this file.

## 2026-09-23, milestone 1: schema 2 and the new systems in place

What landed (code is in `sim/`, all parse):

- `Persistence.SCHEMA = 2`. `migrate()` upgrades a version-1 save: `raw_food` becomes `potato`
  in every inventory, hold, task and in the ledger; new building, agent and state fields get
  defaults. `sim.load_state()` places the Meridian on a version-1 save that has none.
- New modules: `items.gd`, `sizes.gd`, `upgrades.gd`, `research.gd`, `nutrition.gd`,
  `goals.gd`, `awards.gd`, `ship.gd`, `events.gd` (hazard stub).
- Every simulation read of a building definition now uses the effective definition
  `sim.bd(b)` (size and level applied). `sim.bdef(def_id)` is still the base (size M, level 1).
- Kitchens cook dishes from `dishes.json` with a menu planner. Colonists pick a dish, get
  nutrition, and remember their last 6 dishes.
- Trays grow the crop of their plan (`crops.json`); cycle, yield, biomass, water per crop.
- Spoilage (exact integer accumulators), automatic machines, multi-recipe machines,
  research, goals, awards, the Meridian, chart series, daily rows, difficulty, immigration.

Still to do in this order: tests for all of it, new starting party balance, the reference
campaign (research, sizes, upgrades, crops, dishes, industry, forward airlock, ship repair),
soak tests, showcase saves, performance check, dust storm (stretch).

## 2026-09-24, milestone 2: tests, speed, texts

- `tests/cases_v2.gd`: 15 new tests, all pass (content integrity, sizes, levels, upgrade
  flow with the ledger, research with special items, crop yields, kitchen menu, nutrition,
  spoilage, goal sustain timer and pod, awards once, Meridian placement on all tutorial
  seeds and all three planets, Meridian stages and maintenance, chart series, v1 save
  migration). Run them with `node tools/godot.mjs test v2_`. Exclude long runs with
  `node tools/godot.mjs test !long_`.
- Full suite before the speed work: 36 of 37 passed; the one failure (a10) counted a goal
  reward pod as demolition salvage and is fixed in the test.
- Speed: a tick with 20 colonists and 59 structures went from 1.19 ms to 0.62 ms (static
  network facts are cached per component; crops update once per second).
- The Meridian footprint is 44 m (ART-B request, answered in `docs/requests/ART-B-to-SIM.md`).
- Loaded v1 save: the false "1 colonists are starving" alert is fixed. A colonist who is on
  the way to food or water, or drinking first, is not reported; the alert needs 12 s at the
  critical level without such a plan. Test: `v2_migration_v1_save` runs the save 2 days:
  no starving or thirst alert, nobody dies.
- Texts: counts use `sim/text.gd` ("1 colonist is", "3 colonists are", "1 second").
  Items have `one` and `plural` names: `sim.items.amount(id, n)` -> "3 hull plates",
  `sim.items.list_text({item: n})` -> "2 electronics, 10 steel".
- The starting party is now 2 technicians, 2 growers, 2 operators, 1 medic, 1 scientist.
  The opening still survives day 3 on all five tutorial seeds (a12).
- Reference driver (`sim/reference.gd`) now understands `need`, `cmd`, `upgrade`, `size`,
  `near: ship`, `face: ship` and `a: "*nearest"`; the campaign steps are in
  `content/reference_layout.json` (group `campaign`).

## 2026-09-24, milestone 3: the reference campaign plays to the Meridian

- The full reference campaign (`demo=all`, group `all`) now runs research, sizes (L solar,
  L battery, L habitat), upgrades (kitchen L2 and L3, research lab L2, mine L2, refinery L3),
  several crops (potato, soybean, tomato, greens, wheat, herbs), several dishes (mashed
  potatoes, garden salad, soy stew, herb potatoes, tofu stir-fry, ...), the industry chain
  next to the mine (refinery, glassworks, electronics fab, fabricator, workshop, regolith
  harvester), a forward airlock near the Meridian, the survey and the hull.
  Seed 1001, measured: chapter 1 day 2.5, chapter 2 about day 4 to 8, chapter 3 about day
  18 to 22, survey done, hull patched day 25, systems day 26.4. No deaths.
- Simulation changes made for this (all tested by the full suite, 37 of 37 pass):
  - Construction plans that are not started are no longer walls for walking.
  - A plan out of suit range lets go of its reserved stock and waits 60 s before it
    reserves again; a task out of suit range rests 15 s for everybody.
  - Goods that cannot be reached no longer mark the machine they go to as unreachable.
  - Machines take their inputs before construction plans reserve the rest.
  - Specialists prefer their own work more strongly (balance `specialist_bonus` 80).
  - Kitchens stop at 2.1 days of dishes (2.6 with cold storage); growers do not plant a
    crop the colony already has plenty of; recipes can have `stock_max` (spare parts 16,
    glass 30, electronics 40, hull plates 30, composite 20, medicine 12, polymer 80).
    Machine block code `stock_full` = "enough in stock".
  - Tuning: industry priority 2 by default; a mine batch gives 2 ore; refining and polymer
    20 work, spare parts 30 work; machines keep 4 batches of input; lander rations 48.
- New block codes on buildings: `stock_full`; on upgrades `upgrade.block` =
  `materials:<item>` or `suit_range`.

## 2026-09-24, milestone 4: final state of the SIM work

Tests: 40 of 40 pass, full suite 356 s (`node tools/godot.mjs test`). Long runs only:
`test long_`. Everything else: `test !long_`.

Reference campaign, seed 1001 (`long_campaign_chapters_seed_1001`, storms on):

| event | day |
|---|---|
| chapter 1 (Touchdown) done | 2.5 |
| balanced diet / food supply | 3.5 / 4.2 |
| chapter 2 (Sustain) done | 4.2 |
| first upgrade to level 3 | 7.5 |
| 20 colonists | 11.5 |
| 50 steel made | 13.0 |
| 20 electronics made, chapter 3 (Industry) done | 21.8 |
| survey and hull (both finished before chapter 4 opened) | 21.8 |
| systems (dev tool run) | 23.3 |

20 alive, 0 deaths, ledger `{}` every day, 22 techs, 89 structures, no refused command.
Other tutorial seeds (dev tool `tests/dev/campaign.gd`, not a test): hull on 1002 day 24.6,
1003 day 21.6, 1005 day 27.0; **1004 opens chapter 4 on day 19.3 but does not survey by
day 27** (the forward airlocks wait for steel that the machines take first).

Speed (`long_perf_60_colonists_150_structures`, this machine only, i7-14700K): 1.35 to
1.63 ms per tick with 68 colonists and 150 structures (was 2.31 ms). The brief asks for
about 1 ms: **not met**. Changes: a colonist outside keeps its walk-back estimate for 10 s
or 6 m (was two A* searches with smoothing every second); the comms-tower lookup no longer
scans every building every tick; power plans are arrays; networks without water structures
get no water numbers; needs constants are worked out once per tick. The rest is spread over
many systems (power, act, jobs, think, needs, alerts: 0.1 to 0.3 ms each).

Changes since milestone 3:

- **Dust storm on** (`balance.storm.enabled` true). Never before day 6 (after the tutorial's
  `no_disaster_days` 5), then every 3 to 5 days, 90 to 180 s, 60 s warning. Solar output x0.2,
  walking outside x0.5. Game option `options.storms` (default true;
  `sim.new_game(seed, scenario, {storms: false})`). Test `v2_dust_storm_timing_effects_and_save`.
- **Balanced diet** (goal) and **Balanced** (award) use the mean nutrition over a window
  (`params.window` seconds: 600 and 1200) instead of a sustain timer. The goal counts only
  samples taken after it opened. Reason: nutrition falls every night, so a continuous
  timer passed by chance (day 3.9 in one run, day 17.2 in the next).
- **Hull plates** stop at the Meridian's remaining need (`recipes.hull_plate.stock_for:
  "ship"`, `sim.ship.future_need(item)`). Before, 28 extra plates took the steel the hull
  stage waited for.
- Reference layout: the third settler group is 3 technicians and 1 grower (technicians run
  every factory and were the steel bottleneck); the workshop waits for stage 2 (it was
  refused); a west airlock toward the wreck (`near: "ship_line"`).
- Reference driver: a mine far from the lander is matched to its step; an "around" step
  waits for its anchor; the mine may stand anywhere on a deposit; a junction avoids rocks,
  structures and corridors on both legs, and each retry takes the next place; it does not
  cancel a plan that a corridor was ordered to in the same second.
- `check_link` returns `gone` (not `same`) when one end no longer exists.
- Showcase saves regenerated: `content/saves/showcase_early.fhsave` (day 3.35),
  `showcase_mid.fhsave` (day 12: lab, industry, 3 dishes, level 3, size L),
  `showcase_late.fhsave` (day 20.3, Meridian stage 2). All audit `{}`.
- Dev tools in `tests/dev/`: `profile.gd [seed] [day] [ticks] [big]`, `campaign.gd`,
  `deaths.gd`, `locks_dbg.gd`, `deposit_dbg.gd`, `around_dbg.gd`. Arguments follow the script
  path directly (no `--`).

## 2026-09-24, milestone 5: nutrition is a moving average of the diet

Coordinator request. The linear decay (50 per day) drained every nutrient whose average
intake was below 50, so a normal mixed diet ended in a permanent "Low fat" alert.

- Model: each meal moves every value toward the dish's value by `nutrition.meal_weight` 0.4
  (`n = n + (dish - n) x 0.4`). A one-dish diet settles at that dish's values; a varied diet
  at their mean. Values drift toward 0 (`hungry_drift_per_day` 30) only while a colonist is
  critically hungry (hunger >= `need_critical`). `decay_per_day` is gone.
- Thresholds: `deficient_below` 20, `starved_below` 8. New colonists start at 50 (was 70),
  the ration level, so no goal is met by the start values.
- Start dishes as requested: mashed potato P20 C80 F30 V35, flatbread P30 C80 F25 V15,
  garden salad P15 C25 F25 V90.
- **The later dishes were re-tuned too.** With their old values (made to be *added*), the
  moving average gives soy stew + stir-fry + pizza a score of 54.6: never well fed. Only the
  feast reached 70. New values (P C F V): algae bar 80 45 30 35, herb potatoes 35 80 45 60,
  tomato pasta 45 85 45 60, soy stew 75 65 60 75, mushroom risotto 60 85 60 65, tofu stir-fry
  90 55 70 80, veggie pizza 65 85 75 70, colony feast 85 85 85 90. Rations stay 50 50 50 50.
- Checked (meal-by-meal, k 0.4): the three start dishes in turn settle at score about 39,
  lowest value 20 (above `starved_below` 8; potato and salad only: protein 17, a
  deficiency, which soybeans and algae fix). Soy stew + stir-fry + pizza in turn: score 72,
  every value 64 or more, well fed after every meal. Test `v2_nutrition_decay_and_eat`.
- Goal "Balanced diet" is now score 55 over one day (a level-2 kitchen mix: soy stew, herb
  potatoes, pasta). At 70 it needed the level-3 and level-4 kitchens, which belong to
  chapters 3 and 4. Award "Balanced" is now 70 over two days (was 80, which needed the feast).
- Campaign seed 1001: chapter 2 done day 6 (balanced diet 6.5), chapter 3 day 19, hull day
  21.1, 0 deaths. **End of run: nutrition score 66.0 (P69 C64 F59 V72), 0 colonists with a
  deficiency, 1 well fed.** Suite: `test !long_` 38 of 38 pass; `long_campaign` passes.
- Showcase saves regenerated. The script now skips moments with a critical alert (the old
  mid save had "The lander air has ended. 4 people have no other bed."). Early day 3.35
  score 49.1; mid day 12.7 score 61.8; late day 21.1 score 63.4, 2 well fed. No save has a
  nutrient deficiency or any alert above severity 1.
- Dev tool: `tests/dev/save_nutrition.gd <save>` prints nutrition and alerts of a save.

## What the interface can use now

Always read new fields with `.get(key, default)`: old saves are migrated, but be safe.

### Helpers (read-only)

| call | returns |
|---|---|
| `sim.bd(b)` | effective definition of a building record: size and level applied (radius, cost, power, storage, beds, trays, tray_offsets, work_slots, gen_*, caps). **Use this instead of `sim.bdef(b.def)` wherever the UI shows numbers of a placed building.** Read-only, cached. Extra keys: `size`, `level`, `level_mult`, `wear_mult`, `comfort`, `work_mult`. |
| `sim.sizes.def_for(def_id, size)` | effective definition of a size at level 1 (for the build bar and ghost: radius, cost, power) |
| `sim.sizes.sizes_of(def_id)` | `[0,1,2,3]` or `[1]` (one size only) |
| `sim.sizes.allowed(def_id, size)` | `{ok, code, research}`; code `ok`, `no_size`, `locked_research` (research names the tech) |
| `Sizes.size_name(i)` / `sim.sizes.SIZE_NAMES` | "S", "M", "L", "XL" |
| `sim.place.check_building(def_id, pos, rot, ignore_id := -1, size := 1)` | reason code; new codes `locked_research`, `no_size`, `overlap_ship`, `unknown` |
| `sim.place.reason_detail(def_id, size, code)` | sentence; for `locked_research` it names the tech ("Research Structural Engineering first.") |
| `sim.upgrades.check(b)` | `{ok, code, to, cost, research}`; codes `ok`, `not_upgradable`, `max_level`, `not_active`, `demolish`, `busy`, `locked_research` |
| `sim.upgrades.missing(b)` | upgrade materials still to deliver `{item: n}` |
| `sim.research.state_of(tech)` | `done`, `active`, `queued`, `available`, `locked` |
| `sim.research.rp_rate()` | research points per day (one-minute average) |
| `sim.research.fraction(tech)` / `remaining(tech)` | progress 0..1 / RP left |
| `sim.research.items_needed()` | items the active special project still waits for (`{}` when none) |
| `sim.research.bonus(key)` | colony bonus, e.g. `solar_mult` 0.2 = +20 % |
| `sim.research.building_unlocked(def)`, `crop_unlocked(crop)`, `recipe_unlocked(rid)`, `level_tech(def, level)` | gates |
| `sim.goals.chapter()` | open chapter index (0-based); equals the chapter count after victory |
| `sim.goals.list()` | every goal: `{id, name, desc, hint, chapter, state, value, target, since, sustain, done_tick, reward}`. For `balanced_diet` (score 55) `sustain` is 0 and `value` is the mean over the last day (0 until the goal has been open one full day). |
| `sim.goals.victory()` | bool |
| `sim.awards.list()` | every award: `{id, name, tier, desc, earned (tick or -1), value, target}` |
| `sim.awards.points()` | tier points of earned awards |
| `sim.nutrition.colony()` | `{protein, carbs, fat, vitamins, score, people}` |
| `sim.nutrition.score(a)`, `well_fed(a)`, `deficient(a)` (list of nutrients) | per colonist |
| `sim.metrics.series(name)` | `[[tick, value], ...]` (max 720) |
| `sim.metrics.series_names()` | every series that exists |
| `sim.metrics.forecast()` | v1 fields plus `dishes` (cooked, no rations) and `rations`; `meals` = all edible units |
| `sim.items.info(id)` | `{id, name, category, color, value, shelf_days, desc}`; dishes add `nutrition, taste, ingredients, kitchen_level, work_per_dish`; crops add `crop` |
| `sim.items.all()`, `dishes()`, `crops()`, `of_category(cat)` | id lists |
| `sim.items.amount(id, n)`, `sim.items.list_text(dict)` | "3 hull plates", "1 spare part"; `info()` also has `one` and `plural` names |
| `sim.prod.crops_for(def_id)` | unlocked crops for a tray building |
| `sim.prod.tray_fraction(tray)` | growth 0..1 of a tray (per-crop cycle) |
| `sim.prod.menu_of(kitchen)` | dishes this kitchen may cook now (level, not switched off) |
| `sim.prod.menu_pick(kitchen)` | the dish the next batch will cook ("" = none possible) |
| `sim.prod.recipe_id(b)` / `recipe_of(b)` | the recipe a machine runs now |
| `sim.ship.info()` | `{id, stage, stage_name, phase, progress, work_total, readiness, runs, away, flight_t, program, repairing, deliver{}, delivered{}, missing{}, run_block, next_run_in, can_run}` |
| `Ship.segment_of(b)` (`preload("res://sim/ship.gd")`) | the two ends of the Meridian's capsule axis |
| `sim.ship.future_need(item)` | units of an item the repair still needs (this stage and later) |
| `sim.events.storm()` | `{phase: "none"|"warning"|"active", at, end, count, scheduled}` or `{}` before day 5. The record is reused for the next storm. |
| `sim.events.active()` / `seconds_to_storm()` | storm now / seconds to the next one (-1 = none known) |

### State fields

| where | field | meaning |
|---|---|---|
| building | `size` 0..3 | S, M, L, XL (default 1) |
| building | `level` 1..5 | upgrade level |
| building | `radius` | already the effective radius of its size |
| building | `upgrade` | `{}` or `{to, cost{}, inv, progress, work_total, state: "deliver"|"work", block}` |
| building | `recipe_sel` | chosen recipe ("" = default) |
| building | `crop` | default crop of a tray building |
| building | `trays[i]` | `{state, growth, interrupt, work, crop (the plan), grow (crop in the tray now, "" when empty)}`. Growth is in seconds of that crop's cycle: use `sim.prod.tray_fraction(tray)`, not `bal.crop_cycle_seconds`. |
| building | `menu_off` | `{dish: true}` for a kitchen |
| building | `acc` | internal accumulators (machines, recycler pool) |
| building | `batch` | now also `outputs {item: n}` and, in a kitchen, `dish` |
| Meridian | `def: "meridian"`, `kind: "special"`, `pos`, `rot` (axis direction), `radius` 7, `length` 44, `inv_site` (the ship's store, role `ship`) | not part of any network |
| agent | `role` | adds `scientist` |
| agent | `nutrition` | `{protein, carbs, fat, vitamins}` 0..100, a moving average of the dishes eaten (dish values are levels, not amounts added) |
| agent | `diet` | last 6 dish ids |
| agent | `rec_bonus`, `medicated` | cantina morale bonus; treated with medicine now |
| agent | `ret_c` | internal: cached walk back to air |
| inventory | `spoil` | `{item: accumulator}` (internal) |
| inventory | `pod` | true on a supply pod pile (reward or supply run): draw a pod model |
| inventory | role `upg` | materials of an upgrade in progress; role `ship`: the Meridian's store |
| state | `research` | `{active, queue[], progress{}, done{tech: tick}, paid{}, rp_total, bank, rate, sec}` |
| state | `goals` | `{chapter, status{id: {state, value, target, since, done_tick, opened}}, victory (tick or -1), night, good_nights, pods}` |
| state | `awards` | `{id: tick}`; `award_track` is internal |
| state | `ship` | `{id, stage 0..5, phase, progress, readiness, runs, next_run_tick, away, return_tick, program "auto"|"on"|"hold", auto_runs, flight_t (0..1 during the test flight, else -1), maint}` |
| state | `stats` | `{produced{}, consumed{}, spoiled{}, cooked{}, eaten{}, cooked_total, harvests, heals, techs, upgrades, ship_stages, ship_runs, ship_maintenance, settlers, spoiled_today{}, spoiled_yesterday{}}` |
| state | `metrics.series` | `{name: [[tick, value], ...]}`: `pop, morale, nutrition, o2_stock, o2_make, o2_use, water_stock, water_in, water_out, power_gen, power_use, energy, food_days, rp_rate, ship_readiness` every 10 s; `item:<id>` every 60 s for every item the colony has had |
| state | `metrics.daily` | `[{day, pop, deaths, produced{}, consumed{}, spoiled{}}]`, one row per day (120 kept) |
| state | `options` | `{planet, difficulty, spoilage, storms}` |
| state | `policies.immigration` | `{open, roles[], cap}` |
| state | `events` | `{storm: {...}}` (see `sim.events.storm()`); `stats.storms` counts finished storms |
| state | `env` | `solar_mult`, `speed_mult` are 0.2 / 0.5 during a storm, else 1.0 |

### Commands (payloads as the design, results `{ok, code}`)

| kind | payload | codes |
|---|---|---|
| `place_building` | + `size` 0..3 | + `locked_research`, `no_size`, `overlap_ship` |
| `upgrade` / `cancel_upgrade` | `{id}` | see `upgrades.check` |
| `research` | `{tech}` | makes it active now; missing prerequisites are queued first; the old active project goes back to the front of the queue and keeps its RP |
| `research_queue` | `{techs: [..]}` | replaces the queue |
| `set_crop` | `{id, crop, tray: -1}` | `invalid`, `locked_research`. A growing tray keeps its crop; the plan applies at the next seeding |
| `set_recipe` | `{id, recipe}` | `invalid`, `locked_research`. Unused inputs are put down in the room as a pile |
| `set_dish` | `{id, dish, on}` | `invalid` |
| `set_immigration` | `{roles, cap, open}` | missing keys stay |
| `ship` | `{action: "survey"|"supply_run"|"hold"}` | `no_ship`, `not_operational`, `locked_research`, `no_comms`, `away`, `hold`, `readiness`, `no_fuel` |
| new game | `sim.new_game(seed, "tutorial", {planet, difficulty, storms})` | planets `dry`, `cold`, `airless`; difficulty `relaxed`, `standard`, `hard`; storms default true |

### New log codes and alert codes

Log: `research`, `research_start`, `research_paid`, `goal`, `chapter`, `victory`, `award`,
`upgraded`, `upgrade_planned`, `upgrade_cancelled`, `recipe`, `ship`, `ship_flight`,
`ship_run`, `spoiled`, `storm_warning`, `storm`, `storm_end`.
Alerts: `low_nutrient` (keys `low_protein` etc.), `food_variety`, `spoilage`, `research_idle`,
`research_items`, `ship_comms`, `ship_fuel`, `ship_readiness`.

### Behaviour changes from version 1

- Kitchens no longer turn raw food into `meals`. They cook dishes; `meals` is the emergency
  ration from the lander and from supply pods. The v1 tutorial step "food" now counts cooked
  dishes (`stats.cooked_total`).
- Greenhouse default crop is potato (5 potatoes + 2 biomass per harvest, v1: 4 raw food + 2).
- Admitted settlers without a role list now include a scientist.
- The medical bay has a 4-unit input buffer for medicine.
- Dust storms happen from day 6 (v1 had none).
- Refusal code `gone` for a link whose end no longer exists (v1 said `same`).
- A colonist outside re-plans the walk back to air every 10 s or 6 m, not every second; in
  between the estimate is the kept path plus the straight distance walked (never shorter).

---

# Version 3 (docs/V3_DESIGN.md)

## 2026-09-24, v3 milestone 1: alerts, 810 m map, furniture use, research packs, hazards

All five work items have code, content and tests. `node tools/godot.mjs check` is clean.
Save schema is **3**. New test file `tests/cases_v3.gd` (`node tools/godot.mjs test v3_`).

### 1. Alerts (§2)
- Hysteresis in `sim/alerts.gd` `_merge()`: raise after `balance.alerts.raise_after` by severity
  (notice 20 s, warning 5 s, critical 0 s); clear after `clear_after` 30 s false; short gaps do
  not reset the wait; a kept alert keeps its `first_tick`. `state.alert_track = {key: {since, last}}`.
- Each issue has `live` (false while it waits to clear).
- The per-machine `blocked:<id>` alerts are gone: one alert, key `output_blocked`, lists the
  machines in `entities` and in the text. The key never holds a number.
- Test `v3_alert_output_blocked_300s`: a harvester emptied by a "carrier" every 5 s for 300 s
  (120 block changes) raises `output_blocked` once and never clears it.

### 2. Map 810 (§1)
- `state.map_size` (new games 810, `content/scenarios.json`); v2 saves migrate to 256 and keep the
  v2 generator bit for bit. `sim.world.version` 2 or 3, `sim.world.margin` (8 new, 4 old;
  `balance.map_margin` 8, `map_margin_v2` 4). Code reads `world.margin`, never the balance key.
- World generation v3 (`sim/world_gen.gd _generate_v3`): broad swell + detail octaves, impact
  basin, fault line (low scarp), 2-3 rock ridges, 1-2 canyons, 3 crater fields, 3-5 silicate
  flats, start deposit 33-44 m, two ore fields 75-150 m, the rest to the edge, 3 exotic fields
  at least 220 m out (`deposits[i].exotic`), about 190 rocks (scattered, ridges, crater rims, rock
  fields), a flat plateau of radius 125 m (blend to 175 m). The Meridian keeps 55-75 m.
- Feature lists for the view: `world.ridges, canyons, craters, flats, basin, fault`.
- Hazard zones: `sim.world.hazard_at(pos)` / `sim.hazards.zone_at(pos)` -> `{meteor, wind, quake}`
  0.5..2.0 (basin meteor-prone, fault quake-prone, high ground and ridges windy). Grids
  `world.hz_meteor/hz_wind/hz_quake`, `hz_n` x `hz_n`, `hz_step` 16 m.
- Nav (`sim/nav.gd`): the terrain grid is built once per world; a map change only clears and
  marks structure cells (`_bcells`). Jump point search was measured and rejected (worst 178 ms
  for one trip round a canyon; plain A* worst 20 ms); paths stay cached per cell pair.
- Suits: `sim.agents.suit_cap()` = 90 s x (1 + bonus `suit_air_mult`): suit_1 135 s, suit_2 198 s;
  reach 85 m -> 206 m. Every suit read uses it.
- Tests use offsets from the lander (`unit_placement_reasons` no longer uses absolute x = 300).

### 3. Furniture use (§6)
- `agent.use = {kind, b, i, pose, act}` or `{}`; `sim.agents.use_of(id)`. Set when a plan step
  starts or ends. `i` = lowest free anchor; **-1 = all anchors of that kind taken** (fallback:
  eat/talk standing). Greenhouse/fungus work index = tray index. Service (outside) has no cap.
- Content: `buildings.json` `"furniture": {beds, seats, work_slots, stands, work_pose}` per room
  type and size; `sim.sizes.furniture(def_id, size)`. Table: `docs/requests/SIM-to-ART-HAB.md`.

### 4. Research packs (§5)
- Items `pack_basic`, `pack_applied`, `pack_exotic` (category `science`); recipes with the same
  ids (`auto`, `water_net` 1). Building `research_assembler` (room, automatic recipe machine,
  sizes S-XL, levels, family science, research `sci_packs_1`; `auto_speed` per size).
- Techs: 45 (was 29). Branches `science`, `haz`, `suit` added; `sci` renamed "Survey and medicine".
  Tier 1: `boost` packs (x2 when held); tier 2 basic; tier 3 basic + applied; tier 4 applied;
  tier 5 exotic packs (replaces the crystal delivery; `research.packs_paid` migrates v2 `paid`).
- A lab uses packs as whole units, spread over the RP (credit per lab in `acc["rp:<item>"]`):
  a tech uses exactly its pack count. Without packs tier 2+ does not move; with packs x2.
  Goal-reward RP still count without packs (they are not lab work).
- `sim.research.packs_of(t)`, `boost_of(t)`, `lab_packs()`, `lab_can_work(lab)`, `lab_boosted(lab)`,
  `lab_info(lab)` (incl. `rate`, `base_rate`), `pack_stock()`, `lock_reason(t)`, `focus_mult`,
  `network_bonus`. Command `set_focus {id, branch}` (+25 % / -10 %). Lab automation (30 % without
  a scientist), data network (+10 % per extra joined lab, max 30 %). Lab block `no_packs`.
- Supply-run cargo: `ship {action: "supply_run"|"cargo", cargo: science|medical|industrial}`;
  `sim.ship.cargo_choice()`, `cargo_items()`, `info().cargo/cargos`. Science = 12 basic + 4 applied.
- Goal pods now include packs (8 goals). Field samples: fragment sites (`sim.hazards.sites()`),
  survey task (scientist, 30 work): 40 RP, +1 exotic, +2 ore, sometimes an exotic pack;
  command `survey_site {id}`.
- `meteor_turret` def (exterior, research `haz_turret_1`, range 70 m, charge 100, shot 50).

### 5. Hazards (§4) - `sim/hazards.gd`
- `state.hazards = {next_id, queue, active, done_count, wear, next_at, seen, shelter, sites,
  craters, breached, start_tick, done}`. Queue planned every 60 s at least `horizon_days` 2 ahead
  from the `hazard` stream; impact-time variation uses hashes (no stream draw); machine failure
  thresholds are a hash of the building id and repair count. Whole-map weather never overlaps.
- Kinds: meteor, meteor_shower, wind_storm, dust_storm (the v2 storm, kept with its v2 timing),
  quake, solar_flare, dust_devil; breakdowns by wear. Rates, leads, warnings, damages in
  `balance.hazards`. `options.hazards` off/mild/normal/hard (`sim.new_game(..., {hazards, debug})`).
- Effects: craters (`sim.hazards.craters()`), fragment piles (`inv.fragment`), room/corridor
  `breach` (air leak `breach_drain_per_day` 4 each), health damage (v2 repair rule), turret
  intercepts, env multipliers (`env.solar_mult`, `speed_mult`, `wind_mult`), flare trip
  (`b.trip`), radiation, dust on panels (`b.dust`, cleaning task).
- Wear: machines (`sim.hazards.is_machine`) wear 4/day x level x difficulty x wind zone
  (exteriors) x storms; maintenance at 75 % of the threshold (62.5 % with Predictive
  Maintenance), technician, 20 work, 1 fault item; breakdown with a fault (mechanical -> spare
  part, electrical -> electronics, seal -> polymer). With hazards on, machines no longer lose v2
  health over time (the v3 wear replaces it); other structures keep the v2 rule.
- Commands: `shelter {on}` (ends by itself when no flare or shower is near), `maintain {id}`,
  `hazard_now {kind, x, y | pos, severity, in, duration, radius, length, dir}` (only with
  `state.options.debug`; `sim.load_state(state, {debug: true})` for a loaded save), `survey_site {id}`.
- API (§4.4): `forecast()`, `active()`, `at_risk()`, `zone_at(pos)`, `info(id)`, `event(id)`,
  `sites()`, `craters()`, `sheltered()`, `setting()`, `queue_all()` (tests only).
- Colonists: a shelter order (or a flare while hurt below 70 health) keeps them inside.
  Corridor breaches are sealed from inside, at the corridor mouth.
- Log codes: hazard_detected, hazard_warning (storm_warning for the dust storm), hazard_start,
  storm, hazard_impact, hazard_end, storm_end, hazard_intercepted, breach, breach_sealed, fault,
  maintained, survey, shelter. Alert keys: `hazard:<id>`, `breach`, `maintenance`, `solar_dust`,
  `shelter`, `broken:<id>` (names the fault and item).
- `sim.events` keeps the v2 read API (storm(), active(), seconds_to_storm()); the mirror
  `state.events.storm` is kept in the v2 shape.

### Job order and economy changes made for v3
- Repairs, breach seals and maintenance reserve their parts before construction; the Meridian's
  parts before construction and upgrades; a machine whose output stock is full no longer holds
  inputs (it held 4 steel in the electronics fab while at 40 electronics).
- Reference layout (`content/reference_layout.json`): research assembler RA (basic) and RA2
  (applied), research queue with the pack techs, an L wind turbine and an L battery, and 6 more
  settlers (4 technicians, 2 operators) once the L habitat stands.
- Balance found by playing the campaign with hazards on (seed 1001, 30 days): the first tuning
  killed the colony twice (7 cracked corridors at once; later breaches that waited for steel
  behind construction plans). Now: crack chance 0.2 and at most 3 per quake, breach drain 4/day,
  wind storm damage 2/min, repairs and seals first. 30 days: 26 alive, 0 deaths, hull day 24.5,
  systems day 26.5, 21 techs.

### Save schema 3 and migration
- `persistence.gd` SCHEMA 3; `_v2_to_v3`: map_size 256, options.hazards normal (debug false),
  hazards start one day after the load, the v2 storm -> a dust_storm event, research.packs_paid,
  agent.use {}, ship.cargo, alert_track from the shown issues, env.wind_mult.

### What was NOT tested
- In the web build only a boot of a new 810 m game and a demo at day 5 (both run;
  `build/web_sim`). No hazard was watched in the web build. World generation and nav times were
  measured on desktop only.
- The UI and RENDER sides of any v3 API.

## 2026-09-24, v3 milestone 2: all tests pass, perf, fixes after the pause

Full suite: **57 of 57 pass** (507 s, `node tools/godot.mjs test`). `check` clean.

Fixed after ART-HAB reported 3 failing sim tests:
- `unit_rng_streams`: the hazard planner now draws nothing until its 2-day horizon reaches the
  scenario's first disaster day, so the hazard stream is untouched in the first days (as in v2).
- `v2_migration_v1_save`: the v2->v3 migration no longer copies shown issues into the alert
  hysteresis (a stale "no water" alert survived the load for 30 s).
- `long_campaign_chapters_seed_1001`: the campaign now builds a second refinery (F2, next to the
  mine) and applied packs stop at 12 in stock (`recipes.pack_applied.stock_max`). Hull day 25.7
  (limit 27), 0 deaths, 26 alive. This test stays close to its limit with hazards on.

Perf: `beds_used()` counted every colonist for every habitat on each bed search (0.2 ms a tick at
70 colonists); it is now counted once per tick (kept exact on bed changes, deaths, spawns and
removals). Measured on this PC (i7-14700K, desktop, not web):
- tick at 70 colonists / 150 structures, hazards normal: 1.87 ms (`long_v3_perf_70_colonists`;
  1.61 ms in `tests/dev/think_prof.gd`, 2.1 ms before the fix). Budget 2.0 ms: met, small margin.
- world generation 810 m: 177-256 ms; nav terrain build 18-27 ms; graph rebuild after a map
  change under 1 ms; 24 paths of 250 m 73-128 ms total, worst 12-26 ms.
- buildable share for a room of radius 5: 86.3-87.9 % (seeds 1001-1005).

UI requests C1 (`lab_info().rate`, `base_rate`) and C2 (`ship {action: "cargo"}`) are done;
see `docs/requests/SIM-to-UI.md`.

Next / not done: showcase saves are still the v2 ones (256 m map); no v3 save with an 810 m
colony exists for RENDER perf shots. Web-build timings not measured.

## 2026-09-24, v3 milestone 3: 810 m showcase saves, tick margin

- `tests/make_showcase_saves.gd` now writes `content/saves/showcase_v3_mid.fhsave` (day 13.1,
  26 colonists) and `showcase_v3_late.fhsave` (day 25.0, 66 colonists, every room type, turret,
  forward airlock at the Meridian, fragment sites, a worn refinery, a breached corridor). Hazards
  "normal". The late colony is partly set-up (see the script header). The v2 saves stay.
  Test `v3_showcase_saves_load_and_run`. Names and notes in SIM-to-RENDER.md and SIM-to-UI.md.
- Tick: a lone solar array or turbine on no network now skips the general power path (same
  numbers). Measured 1.76-1.97 ms per tick at 70 colonists across runs while other agents used
  the PC (last full run 1.83 ms). The 1.7 ms target is NOT reliably met; the cheap remaining
  win (re-plan the walk back every 12 m, not 6 m) changes colonist behaviour and was not made.
- Full suite: 58 of 58 pass (510 s).

## 2026-09-24, CRITIC round 6 follow-up
- Test `long_v3_use_slots_unique` (72,000 ticks: 10-day hard-hazard campaign + both v3 showcase
  saves): no two living colonists share `(b, kind, i >= 0)`. Passes; no sim fix needed.
- Ground: the sim never flattens for structures (v2 or v3); on the 810 m map every structure of both
  showcase saves stands on exactly flat ground (0.000 m range, plateau height 0.637 m). Answer and
  view-side causes in `docs/requests/SIM-to-RENDER.md`. Dev tools: `tests/dev/ground_check.gd`,
  `tests/dev/uses_in.gd`.

## 2026-09-25, ART-HAB round 4 answers
- Junction: `link_min_angle_deg` 55 and `max_links` 6 (buildings.json); other rooms keep 28.
  `sim.place.link_min_angle(room)`. New links only; saves with closer corridors load unchanged.
  Test `v3_junction_min_link_angle_55`.
- Tray offsets moved inward (greenhouse L/XL, fungus S/M/L/XL; counts unchanged). Numbers in
  `docs/requests/SIM-to-ART-HAB.md`. Crater `r` = rim crest. Door clearance: no placement change.
- `long_v3_perf_70_colonists` now checks the median of three 1000-tick windows.
- Suite: 59 of 60 pass. `long_v3_perf_70_colonists` fails at 2.54 ms (median) while the PC is
  loaded by other agents: the same unchanged tick code measured 1.61-1.87 ms earlier today and
  2.14 ms now (`tests/dev/think_prof.gd`); a15 on the small colony went from 0.71 to 0.87 ms.

## 2026-09-25, tick budget work (70 colonists, `long_v3_perf_70_colonists`)
Median of three 1000-tick windows: **2.24 ms -> 1.78 ms** (windows 1.97 / 1.78 / 1.75); dev profile
(`tests/dev/profile.gd 1001 12 1000 big`) 2.26 -> 1.58 ms. Changes (determinism kept; same answers
unless noted):
- Walk revision (`state.rev.walk`) moves only when the walking map changes (`nav.signature()`:
  blocked cells + room graph; last value saved as `state.walk_sig`). Before, every cable, repair or
  breakdown made every walker plan its route again. Behaviour change: fewer re-plans.
- The outdoor path cache survives a rebuild when the blocked cells are unchanged.
- `nav.nearest_supplied_lock`: the second airlock's search is skipped when its straight distance
  already exceeds the path found (same answer).
- Walk back to air kept 20 s / 12 m (was 10 s / 6 m); the estimate stays on the safe side.
- Beds: room list cached per graph; the search stops for the tick once every bed is taken.
- `needs_tick`: breathable() inlined. Power: the off-grid list no longer rebuilds every tick (its
  key held `next_id`); lone solar arrays, turbines and batteries skip the general path.
- Reference driver `_resolve`: structures indexed by type once per call.
Full suite 60 of 60 pass (606 s). Campaign: hull day 25.2 (limit 27), 26 alive, 0 deaths.

## 2026-09-25, v3.1 (docs/V3_1_DESIGN.md sections 4.2, 5.2, 6.1, 7; critic round 10)
- **5.2 airlock phases:** `lock.cyc.phase` (enter, seal, pump, open, exit) and `pt`, shares
  `balance.airlock_phases`; cycle length unchanged. `sim.agents.lock_info(id)`. Test `v31_airlock_phases`.
- **4.2 outside paths:** solid = footprint / tube / wreck + 0.3 m (`nav.BODY_R`); the next 0.6 m
  (`nav_clearance`) and the airlock porch are walking weights (8 and 12), not walls. Solid + 0.6 m and
  solid + 0.71 m were built first and failed (gaps closed at the 0.6 m placement spacing; a13 fell to 8
  colonists, one variant killed 5 colonists and the campaign colony). Construction waits up to 60 s
  (`site_clear_wait_s`) while a body outside stands on the footprint; a closed-in colonist moves up to
  15 m to an open cell with a way back (`closed_in_moves`). Test `v31_outside_paths_clear`.
- **6.1 ships and visitors:** `sim/traffic.gd`, `content/ships.json`, `content/trade.json`; six kinds;
  hash schedule forecast one day ahead; grant/deny; orbit hold in hazards; visitors as agents; credits
  with `credits_audit()`; trade with carried goods; commands `traffic_answer`, `trade`, `traffic_now`
  (debug). Tests `v31_traffic_schedule_deterministic`, `v31_trader_trade_and_credits`,
  `v31_liner_visitors_beds_and_fees`, `v31_orbit_hold_deny_and_shuttle`, `v31_medical_science_inspector_visits`.
- **7 saves:** schema 4 (migration v1 → v2 → v3 → v4); `content/saves/showcase_v31.fhsave`. Tests
  `v31_save_mid_visit_and_schema_4`, `v31_showcase_save`; v2/v3 migration tests now expect 4.
- **Airlock sizes (critic round 10):** M 3.4 m / 2 riders, L 4.0 m / 4 riders (`size_list` [1, 2],
  `sizes.airlock_slots`), L after `eng_1`; old airlocks keep 2.8 m. `sim.agents.lock_slots(b)`. Landing
  pad 11.5 m for new pads. Test `v31_airlock_sizes`.
- **Porch zone:** placement also refuses a new airlock whose door strip covers a corridor; UI data
  `sim.place.door_strip_for(...)`, `sim.place.door_strips()`. Old saves keep what is there. Test
  `v31_porch_zone`.
- Reference layout: airlock L2 and its corridor at 620 s (was 1240 s). With the 3.4 m airlock the H1–L2
  corridor got its metal only after the mine corridor closed the north way round; its site was then out
  of suit range for good (96 m walk) and the colony stayed at 8.
- Full suite: 70 of 70 pass (741.6 s), then `v31_showcase_save` added and passed. a13: 26 colonists.
  Campaign: hull day 25.5 (limit 27), 26 alive, 0 deaths. `long_v3_perf_70_colonists`: median 1.840 ms
  (1.840 / 1.640 / 2.116), limit 2.0.
- Dev tools: `tests/dev/inside_dbg.gd`, `site_reach.gd`, `grid_map.gd`, `build_log.gd`, `site_watch.gd`,
  `ref_status.gd`, `goal_changes.gd`.

## 2026-09-25, v3.1 follow-ups (coordinator)
- `showcase_v31.fhsave`: 600 credits (maker books them as start credits). Test `v31_showcase_purchase`:
  4 composite for 92 credits, pile at the pad, all stored after about 1000 s, both ledgers {}.
- `traffic_answer {accept_idx | accept_ids: [i]}`: exactly those settlers (indexes into offer.roles);
  `accept: n` still works. Orbit `t_s` = seconds before the ship leaves. Test
  `v31_settlers_by_person_and_orbit_time`.
- Tick: traffic costs 0.004 ms/tick at 70 colonists (profile). Landing pads are now found from a cached
  id list (not a scan of every structure each second); the boarding list is not reallocated each tick.
- Bug fixed: `_choose` tie-break used `String(int)` (script error on inspector tours); now `str()`.
- Full suite 73 of 73 (645 s; one window 2.190 ms, median 1.970); after the `_choose` fix: v31 tests
  13 of 13, perf windows 1.366 / 1.491 / 1.667 ms.

## 2026-09-25, door clearance (ART-HAB data, coordinator decision)
- `content/door_blocked.json` (copy of `docs/requests/ART-HAB-door_blocked.json`, key `<def>_<size>`).
  New corridors may not leave a room at a blocked model angle (`beta = rot − world angle`); code
  `door_blocked`, "The door would open onto equipment. Choose another side of the room." On airlocks it
  is checked before the old 55° rule. Old corridors stay. UI: `sim.place.link_sectors_for(def, size, rot)`,
  `link_sectors(b)`, `link_angle_ok_for(...)`, `link_angle_ok(b, a)`.
- Reference driver turns a room (15° steps, smallest first) so the corridor to the room it joins leaves
  a free side; `door_blocked` joins the nearest accepting room like `ports_full`. Layout: O1 turned to
  180° (reference and `tests/helpers.gd` CORE_STEPS).
- Trays moved inward: greenhouse M/L/XL, fungus L/XL (numbers in SIM-to-ART-HAB). Fungus M cannot be
  freed. ART-HAB must rebuild and regenerate the door file; the copy keeps today's numbers until then.
- Test `v31_door_clearance` (33 checks). Full suite 74 of 74 (719.6 s). a13: 26 colonists. Campaign:
  hull day 25.5, 26 alive, 0 deaths. Perf 70 colonists: 1.366 / 1.418 / 1.506 ms (median 1.418).

## 2026-09-25, indoor path fix and critic round 13
- Indoor walk across open ground (RENDER report, colonist 3749 in showcase_v3_late): `agent.bld` named
  the destination during an indoor walk, so a new plan made mid-walk started inside the destination.
  Now `bld` = room of the last waypoint reached, `agent.at` = [room, position, next room]; a plan from a
  corridor starts from the shorter end; `path_in` walks along the corridor to the wall first and clamps a
  target outside its room. Test `v31_indoor_walks_stay_indoors` (4 days reference + 6000 ticks of
  showcase_v3_late, every tick; fails without the fix).
- Airlock phases in seconds (`airlock_phase_seconds`): enter 2.0, seal 1.0, open 1.0, exit 1.5, pump the
  rest; seal ≥ door 0.6 s + margin. Checks in `v31_airlock_phases`.
- Piles and drop points off porches (`pile_porch_clear` 2.5 m, off the door strip): `place.in_porch`,
  `place.clear_of_porches`. Test `v31_piles_clear_of_porches`.
- `nutrition.any_deficient` (no list per worker per tick).
- Full suite 76 of 76 (794.9 s). a13 26 colonists. Campaign hull day 24.9, 26 alive, 0 deaths. Perf 70
  colonists 1.805 / 1.874 / 1.698 ms (median 1.805); single runs today ranged 1.59–2.02 ms.

## 2026-09-25, tick budget after the path fix (target median ≤ 1.6 ms at 70 colonists)
- Measured first: the new corridor-first planning costs 0.03 ms/tick in total (nav.plan + path_out, 572
  calls in 3000 ticks), so route caching would not help. The cost was spread over per-tick loops.
- Changes (the game is identical: digest of the reference campaign at day 6 and day 13 unchanged):
  1. power: lone solar arrays / batteries fill a kept power_stats row (no new dictionary per tick);
  2. water_tick: only networks with a water structure (cached with the water plans);
  3. locks_tick: only structures with an airlock door (cached by structure count and rev.power);
  4. act: a body that only waits in an airlock queue with a valid route is skipped;
  5. bed counts kept across ticks (recount on add, death, leave, load);
  6. morale_second: constants read once; nutrition.morale_delta without copying the diet.
- Dev: `tests/dev/profile.gd <seed> <days> <ticks> v3perf` (the long_v3_perf set-up),
  `tests/dev/digest_run.gd <days>`.
- Perf test 3 runs: 1.385 / 1.452 / 1.489 ms median; full suite 76 of 76 (763 s), perf 1.613 there.
  Campaign hull day 24.9; a13 26 colonists.

## 2026-09-25, visitors are not the colony (integration bug)
- showcase_v31 showed a constant CRITICAL lander-air alert for the liner's 6 tourists (bed -1). Colony
  alerts, goals, charts and morale averages now count colonists only; food, water and air use in
  `metrics.forecast()` count visitors too (`forecast().visitors`, `sim.visitor_count()`). Traffic
  notice `sim.traffic.notices()` ("3 tourists have no bed. The fee drops."). Airlock congestion: queue
  length counts everyone, the air margin colonists only.
- Test `v31_visitors_raise_no_colony_alerts` (fails on the old lander rule). Full suite 77 of 77
  (799.8 s); perf 1.673 ms median in the suite run; campaign hull day 24.9; a13 26 colonists.

## 2026-09-27, v4 milestone 1: the 2,560 m planet (docs/V4_DESIGN.md sections 1 and 1.1)
- `sim/world_v4.gd` (generator) + `content/terrain_v4.json` (every number): mountain ranges with passes,
  plateaus 20–60 m with cliffs and ramps, deep craters 200–480 m wide / 40–120 m deep with a ramp,
  crevices 3–15 m, boulder fields (boulders 4–20 m), dunes, ridges, canyons, small craters, flats, a flat
  start plateau (125 m). Generation 0.5–0.8 s (budget 4 s): noise summed on lattices and upsampled once
  (Image cubic), features on their boxes only.
- Queries in `sim/world_gen.gd`: `rad_at`, `sun_angles`, `sun_vis` (horizon map 32 m × 13 bearings),
  `crevice_at`, `near_mountain`, `terrain_at`, `rocks_near` (64 m buckets, also used by placement).
- Materials by tier and danger (kind + tier on each deposit): metal/ice on the plain, titanium on plateaus,
  carbon by crevices, uranium/thorium far or on dangerous ground (radiation 2–6 mSv/h), deep ice and
  helium-3 on crater floors, rare earths by crevices, exotic crystal on mountain peaks (hopper only).
- Solar output × sun_vis on v4 maps (crater floors 0–40 % of the open sun; noon elevation 32°).
- `sim/nav_v4.gd`: hierarchical walking (8 m coarse grid + fine 1 m windows of 320 m, at most 8) and
  `vehicle_path` (rover grid: slope ≤ 0.6, no crevice, boulders + 4 m; hopper: hops ≤ hop_m).
  Signature from the structures, so a loaded game walks like the saved one.
- Scenario "frontier" (2,560 m); `options.map_size` override. v3 and v2 maps unchanged (digest of the
  reference campaign at day 6 identical).
- Tests `v4_world_generation`, `v4_radiation_and_sun`, `v4_nav_walk_drive_hop`, `v4_solar_output_uses_horizon`,
  `v4_frontier_game_plays`. Full suite 82 of 82 (797 s); v3 perf 1.803 ms; campaign hull day 24.9.

## 2026-09-27, v4 milestone 2: bases and scale (docs/V4_DESIGN.md section 2)
- `sim/bases.gd`: bases with a core (lander or outpost core), names, membership from the corridor +
  cable graph (else the nearest core), `list`, `base_of`, `base_at`, `base_of_agent`, `home_of`, `totals`,
  alert `base` field, `rename_base`, `deploy_outpost` (Outpost Kit within 30 m, 300 m from other cores).
- Outpost core (special, hatch, 4 beds, 120 storage, air 3 days from deployment: `air_until`); alert
  `core_expiry`; beds: cores are shelter (fallback to the core of the colonist's base).
- Locality with several bases: work and room beds only at the colonist's base.
- Scale on v4 maps: rooms 1.5 x radius (sizes), corridors 1.25 x (sim.corridor_r() in nav, placement,
  construction, hazards), corridor length limits x 1.5, reference layout x 1.5. v3 unchanged (digest).
- Critic round 18: crater lip, terraced walls, apron, floor boulders; mountain slope limit (steepest 2.3).
- v4 reference campaign: "crossing" fixed (an "around" place now moves on after a refused corridor).
- Tests: `v4_room_and_corridor_scale`, `v4_outpost_founds_a_base`, `v4_outpost_content_and_migration`,
  `v4_rover_reaches_high_end_ground`; world test checks spikes and rims.

## 2026-09-27, 1.5 x rooms live, V4 rules, content for ART-HAB's buildings
- buildings.json: the 23 room types at ART-HAB's 1.5 x radii (every map), greenhouse/fungus tray offsets x 1.5;
  airlock and junction unchanged; sizes.gd v4-only scaling removed; corridor_scale 1.0 until the wide tubes.
- V4 rules for new games (state.rules = 4): carry 3, walk 5.4 / 4.0 m/s, suit air 110 s, corridors 39 m, cables
  90 m, reference layout x 1.5 (balance.layout_scale). Saves before V4 use balance.legacy_v3 (showcase saves play
  as before: 85 / 76 airlock cycles in 10 min vs 86 / 75 on v3.1.1).
- Reference driver: keeps structures off ore deposits; "around" rings reach 30 m (second refinery was lost).
- sim.set_freeze_build(on) for RENDER's checks. state.deposits[i].surveyed (v4: known within 300 m).
- Content ids: rover_depot (M 9 / L 12), launch_pad 6.5, fission_reactor 12 (gen_const 120, water 8),
  crystal_refinery 8 and chemical_plant 9 and crevice_bridge (S/L) not placeable yet (stage 9).
- Industry list sent to ART-HAB (12 buildings).
- Full suite 86 of 86 (712 s): campaign hull day 24.2, a13 26 colonists, perf 1.846 ms (70 col), 1.536 (60).

## 2026-09-27, walk-speed cap, links per room, V4 milestone 3 (vehicles)
- Walking caps (coordinator): new games 4.0 m/s inside, 3.5 m/s outside. Other levers: carry 4, suit air
  130 s, reference layout x 1.3 (was 1.4; 1.4 no longer finished the hull after the access-point fix: the
  campaign is sensitive, trials 1.25 -> 24.4, 1.3 -> 22.9, 1.35 -> none). Old saves keep legacy_v3.
- Nav: access points snap to cell centres (a raw point could lie inside a neighbour's corridor tube).
- Links per room (Paul): S 4, M 6, L 7, XL 8; spacing max(28 deg, door-housing angle); code `links_full`;
  `place.max_links`, `place.link_min_angle`, `place.door_angle`; old saves keep links. v3 junction test
  now expects the door-housing angle for rooms.
- Vehicles: `sim/vehicles.gd`, `content/vehicles.json`. Depot bays, `build_vehicle` (parts carried, task
  `vbuild` by technicians), board / alight / drive / return / stop / cargo / route commands, charge, fuel,
  wear, repair and refuel at a depot, pressurised cabins, open-rover air guard, riders `where == "vehicle"`.
  Cargo inventory owner type "v"; an Outpost Kit deploys from a vehicle hold.
- Tests: `v4_vehicle_build_board_drive`, `v4_vehicle_rules`, `v4_vehicle_route`, `v4_room_link_counts`.
- Full suite 90 of 90 (766 s): campaign hull day 22.9, a13 26 colonists, perf 1.884 ms (70 col),
  1.920 ms (74 col, 150 structures).
- API sent to UI, RENDER, ART-B (new file SIM-to-ART-B.md) and the links rule to ART-HAB.

## 2026-09-27, V4 milestone 4 (orders)
- `sim/orders.gd`: `order` (go, stay, return, board, work_at, survey), `order_clear`, `set_jobs`
  (own job priorities, 0 = not allowed), `sim.orders.check` preview. Refusals with STE reasons:
  suit_range, exposed_stay, radiation (> 1.0 mSv/h, `balance.order_rad_refuse`) are confirmable;
  a confirmed order runs without the turn-back for air. Critical needs still interrupt an order.
- `vehicle_explore {id, x, y, r}`: a loop of 8 points round an area.
- Test `v4_orders` (38 checks). Full suite 91 of 91 (659 s): campaign hull 22.9, a13 26,
  perf 1.717 ms (70 col), 1.453 ms (74 col).

## 2026-09-27, debug commands; V4 milestone 5 (materials, crafting, tech tree, food margin)
- Debug-only (options.debug): `spawn_vehicle`, `place_finished`, `finish_building` (+ aliases), test
  `v4_debug_commands`.
- Content: 72 items, 46 recipes, 82 techs; 12 industry buildings (ART-HAB counts), chemical plant and
  crystal refinery placeable. High-end chains of 3+ steps. Mines give the item of their deposit kind, gated
  by research (`terrain_v4.deposit_items`); recipes with `min_level`; by-products (slag).
- Vehicle research: charge +50 %, wear -30 %, hopper fuel -30 %; `logi_routes` gates vehicle_route.
- Food margin (new games; old saves unchanged): 8 ration meals per settler; research-pack machines leave
  an item alone while a planned structure waits for it. Campaign at work speed 0.9 / 0.95 / 1.0 / 1.05 /
  1.1: no deaths in any (before: 26 malnutrition deaths at 1.05). Hull day: 27.4 / none / 24.2 / none /
  none — the hull timing is still sensitive (electronics for the fabricator at 1.05).
- Tests `v4_content_tree`, `v4_materials_in_play`, `v4_food_margin`.
- Coordinator fixes: depot bays at ART-HAB's Anchor_Bay_<i> (inside the hangar, facing out; taxi through
  the bay door at 3 m/s; board point on the apron); indoor-only orders never check suit air. Tests
  `v4_depot_bays`, `v4_indoor_orders_need_no_air`.
- Full suite 97 of 97 (812 s): campaign hull 24.2, a13 26 colonists, perf 1.908 ms (70 col), 1.692 ms (74 col).

## 2026-09-27, V4 milestone 6 (reactor, disasters, dose)
- `sim/reactors.gd`: fission reactor heat model with a forecast, fuel rods, coolant, SCRAM, restart, coolant
  dump, evacuation (confirmed stay orders), breach (60 m destroyed, 140 m radiation zone); unstable crystal
  refinery; toxic chemical plant; radiation zones; colonist dose with shielding, decay and sickness; alerts.
- `construction.destroy(b, cause)` (explosions); reactor power only while fission runs; `reactor_stage` debug.
- Tests `v4_reactor_meltdown` (28 checks), `v4_other_disasters`.

## 2026-09-27, V4 milestone 7 (fog, POIs, finds, satellite)
- `sim/explore.gd`: fog grid 16 m (160 x 160 bits, rev counter), reveal by colonists/rovers/hoppers, deposits
  surveyed on reveal; 23 POIs of 6 kinds (deterministic from the seed), visits by need, finds to the vehicle or
  the ground, anomaly RP, rich deposits; satellites from launch pads mapping bands with an uplink; `reveal` debug;
  survey orders to POIs; older v4 saves get fog on load.
- Tests `v4_fog_and_pois` (18), `v4_poi_visits` (20), `v4_satellite` (9). Milestone 6 suite: 99 of 99 old and
  M6 tests passed (campaign hull 24.2, perf 1.898 ms at 70 colonists).

## 2026-09-27, V4 milestone 8 (saves, showcase, perf) and the hull-timing cause
- Save schema 5 (`_v4_to_v5`), tests updated for schema 5. `showcase_v4.fhsave` + `tests/make_showcase_v4.gd`,
  test `v4_showcase` (14 checks).
- Perf: `long_v4_perf_100_colonists_6_vehicles`: 2.098 ms per tick median (1.923 / 2.098 / 2.261) with 100
  colonists and 6 vehicles driving (5 medium rovers, 1 hopper), budget 2.5 ms. Set-up: air topped up for 100
  (the day-12 reference base has 16 beds and O2 for 40).
- Hull-timing swing: cause found. With little silicate, the glassworks took every unit into its input buffer
  and the electronics fab waited for days; the fabricator blueprint (Meridian plates) waited for its
  electronics. Now machines that make an item a planned structure waits for take their inputs first (new
  games only). Campaign at work speed 0.9 / 0.95 / 1.0 / 1.05 / 1.1: hull day 29.1 / 27.3 / 24.6 / 27.0 / 26.6
  (before: 27.4 / none / 24.2 / none / none); no deaths in any.
- Full suite 104 of 104 (919 s; one schema-4 expectation in cases_v31 updated to 5 after the run and re-run
  alone): campaign hull 24.6, a13 26 colonists, perf 1.878 ms (70 col, old map), 1.796 ms (74 col),
  v4 perf 2.053 ms median (100 col + 6 vehicles).
- Content for UI: branch names for the 6 new branches; `tier` (1/2/3) and `tier_name` on all 72 items (test
  `v4_content_tree` checks both). Full suite 104 of 104 (886 s): campaign hull 24.6, a13 26, perf 1.875 ms (70 col),
  1.897 ms (74 col), v4 1.870 ms (100 col + 6 vehicles).
- showcase_v4 rebuilt (UI finding): powered uplink grid, satellite maps bands after load, an extra habitat so no
  critical alert at load; `v4_showcase` 19 checks.
- RENDER fixes (2026-09-28): blast log entries carry the id, pos, def and radii; debug `reactor_stage breach`
  breaches at once; vehicles park on ground under 15 deg (`park_spot`), showcase_v4 rebuilt; POI find measured at
  3.8–6.1 ms per tick (explore 0.2 ms): not a sim spike. Tests: v4_showcase 20, v4_reactor_meltdown 30,
  v4_other_disasters 7, vehicle, order, POI and satellite tests all pass.
- Frame budget: closed-pocket detection in nav_v4 windows (same answers, no whole-window failed A*), window
  prewarm at load/new game; worst tick in 900 s of showcase_v4 78 ms -> 16–20 ms; test `long_v4_tick_max` (30 ms).
  Parking 10 deg; reactor_stage exact and at once; test `v4_reactor_stage_debug`.
- Debug reveal / find timing: reveal 0.06–2.1 ms natively (r 100–4,000), tick 1.2–2.9 ms, satellite band 1.4 ms;
  `long_v4_tick_max` also times a 1,000 m reveal that finds a POI (1.3 ms). Full suite 106 of 106 (849 s):
  campaign hull 24.6, perf 1.864 ms (70 col), v4 1.736 ms (100 col + 6 vehicles), worst tick 19.5 ms.
- RENDER Frontier path check: the crossing was a blueprint corridor (design; RENDER to skip blueprints). Built tubes now
  close the coarse long-walk grid; long walks walk their end stretches on the fine grid. Test
  `v31_outside_paths_clear_frontier`. Full suite 107 of 107 (990 s): worst tick 17.7 ms, v4 perf 1.932 ms.
- Rovers: built tubes close the rover grid; clear end stretches; bounded no-route (closed rover areas);
  replan on change; placement code `depot_blocked` (bay aprons, depot cut-off, new depot facing structures);
  showcase_v4 rebuilt; test `v4_rover_tubes_and_blocks`. Full suite 108 of 108 (753 s), worst tick 19.8 ms.
- Locks: `place.lock_info` / `stage_text` with requirement and progress; refusal texts and the place_building
  result use it. Workshop stage 2 -> 0 (spare parts from the landing). Audit: no other repair, maintenance or
  survival structure or recipe had a stage gate (landing_pad stage 1 is traffic; crevice_bridge not in this
  version). Electrical faults need electronics, which come from research (Electronics fab, ind_2), not a stage.
  Test `v4_locks_explained`; cases_unit uses the landing pad for the stage lock now.
- Alert blinking: key stable and hysteresis applied on every map; `live` now holds 10 s (`alerts.live_hold`) so a
  momentary drop does not show as clearing. Test `v3_alert_output_blocked_300s_frontier` (also checks `live`).
