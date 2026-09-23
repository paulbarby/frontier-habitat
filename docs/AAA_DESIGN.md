# Frontier Habitat 2.0 — the AAA upgrade contract

Version 2.0 · 23 September 2026 · Owner: orchestrator

This file is the contract between the people and agents that build version 2.0.
Every agent reads all of it before it starts, and again when it is not sure.
The numbers live in `content/*.json`. This file says what they mean.

Paul's request, in his words: *"upgrade this to a better visual style and make it a AAA with
goals, and awards, and more variation in the building shapes … model some more advanced
buildings and also 4 size options and level 5 with special research … a base goal e.g. full
supply, O2 supply, food supply, repair and space ship maintenance, and expand the inventory
system for more variations of items as well as food combinations for macro and more detail
with graphs and charts and super cool AAA interface … make it a full AAA game."*

---

## 0. Ground rules for every agent

1. **Never open a window on Paul's desktop.** No Godot editor, no game window, no
   `--resolution` runs, no Blender GUI. Use:
   - `node tools/godot.mjs check | test [filter] | script <res://x.gd> [args] | import | export <dir>`
   - `node tools/shoot.mjs --gpu --dir build/web_<you> --query "<boot params>" --out <png> [--steps s.json]`
     for screenshots of a web export (invisible headless Chrome, real GPU).
   - Blender only with `--background`.
2. **Godot editor operations (import, export) only through `tools/godot.mjs`.** It holds a lock.
   Export to your own folder `build/web_<you>/`. Only the orchestrator writes `build/web/`.
3. **No downloads, no package installs, no network.** Fonts: Inter
   (`C:\Program Files\Blender Foundation\Blender 5.2\5.2\datafiles\fonts\Inter.woff2`, SIL OFL)
   and JetBrains Mono (`C:\Users\paulb\Claude\eden-onboarding\video\tier-0-self-serve\assets\fonts\JetBrainsMono-*.woff2`, SIL OFL).
   **Already copied** to `assets/fonts/`: Inter.woff2 (body), SpaceGrotesk-Regular/Bold.ttf
   (headings, display), JetBrainsMono-500/700.woff2 (numbers). Licences: `assets/fonts/LICENSES.md`.
4. **File ownership (§15).** Edit only files you own. If you need a change in a file you do not
   own, write it to `docs/requests/<you>-to-<owner>.md` (what, why, exact proposal) and carry on.
5. **Keep the game runnable.** Run `node tools/godot.mjs check` before you stop any step. Never
   leave a parse error on disk for long: other agents run the same project.
6. **The simulation is authoritative** (spec 13). Presentation and interface read state and
   submit commands. They never write `sim.state`.
7. **Determinism and conservation stay.** Same seed + same commands = same state digest.
   Every item unit is in exactly one inventory. The ledger (`sim.inv.audit()`) must stay `{}`.
8. **Player-facing text is plain English**: short sentences, one idea each, active voice,
   facts and numbers. No hype words. (Paul's standing rule: ASD-STE100 style.)
9. **Web first.** The target is the Godot 4.4.1 web export (WebGL 2, Compatibility renderer, no
   threads). Everything must work and look right there. Check with `tools/shoot.mjs --gpu`.
10. Report honestly: what works, what does not, what you did not test.

---

## 1. Art direction

**"Clean industrial frontier on a dusty orange world."**

- Structures: off-white composite hulls (`Hull`), dark graphite frames (`Frame`), brushed metal
  (`Metal`), warm emissive windows (`Window`), glass (`Glass`), and **one accent colour per
  category** (`Accent`) in bands, stripes and door frames. Panel seams, bolts, vents, pipes,
  antennas, handrails and hazard stripes give scale. Nothing is a plain primitive.
- **Every building family has its own silhouette** (§2). Size changes the silhouette, not only
  the scale: a bigger size adds modules, decks, annexes, towers.
- **Upgrade levels are visible**: L2 steel trim ring and an antenna; L3 a cyan band and a roof
  module; L4 violet band, radiator fins and a side annex; L5 a gold crown ring, a beacon and a
  glowing emblem. Objects `L2`…`L5` in each model (§11).
- **Baked ambient occlusion in vertex colour** on every model (the web renderer has no SSAO).
- Terrain: fine sand, gravel, rock shelves, craters, dark ore fields, wind streaks; paths that
  colonists walk wear visibly into the ground.
- Sky: warm butterscotch day, deep blue dusk with a large pale moon, stars at night; dust haze.
- Night: windows glow, beacons blink, door lights, landing lights, glow bloom.
- Interface palette: glass panels `#0B1220` at 86% with a 1 px border `#3EE0FF` at 30%;
  primary cyan `#3EE0FF`; warning amber `#FFB547`; critical red `#FF5A5F`; good green
  `#5EE07A`; research violet `#A78BFA`; award gold `#FFD166`. Chamfered corners, corner brackets,
  thin header strips, uppercase letter-spaced headings, tabular numbers.

Category accent colours (unchanged): life support `#29B6C6` · food `#6ABF4B` · housing `#F2C14E`
· industry `#E07A3A` · logistics `#9B6BD6` · utilities `#4A90D9` · medical `#E85D75` · comfort
`#F08FC0` · **science `#7C8CFF`** (new) · **space `#C9D3E0`** (new).

---

## 2. Buildings

`content/buildings.json` is the list. Four **sizes** — index 0..3 = **S, M, L, XL**. Size **M
(index 1) is the version-1 building**: same radius, cost and output, so old saves and old tests
stay valid. A building without a `sizes` block has one size.

**Levels 1..5.** Every building with `"levels": true` can be upgraded. Gates (balance.json
`levels`): L2 needs research `eng_1`, L3 `eng_2`, L4 `eng_3`, **L5 needs the special research of
the building's family** (§6, tier 5). Output, capacity and storage scale with level; power use
rises less. The building keeps working while it is upgraded.

| id | name | kind | cat. | family | silhouette | sizes | research |
|---|---|---|---|---|---|---|---|
| lander | Lander | special | logistics | – | capsule on four legs | – | start |
| solar_array | Solar Array | exterior | utilities | energy | tilted panel rows on frames; XL = field with tracker masts | S–XL | start |
| wind_turbine | Wind Turbine | exterior | utilities | energy | mast + nacelle + 3 blades; mast 6/9/13/18 m | S–XL | start |
| battery | Battery Bank | exterior | utilities | energy | cabinet rows on skids with fins | S–XL | start |
| fusion_reactor | Fusion Reactor | exterior | utilities | energy | torus of magnet coils, glowing core, 2 radiator wings | – | energy_3 |
| water_extractor | Water Extractor | exterior | life_support | life | lattice drill rig over a wellhead | S–XL | start |
| reservoir | Reservoir | exterior | life_support | life | horizontal tanks on cradles; XL = sphere | S–XL | start |
| oxygen_plant | Oxygen Plant | room | life_support | life | dome + electrolysis stacks through the roof | S–XL | start |
| water_recycler | Water Recycler | room | life_support | life | drum with filter columns and blue piping | S–XL | life_1 |
| atmo_processor | Atmosphere Processor | room | life_support | life | twin hyperbolic cooling towers | S–XL | life_2 |
| airlock | Airlock | room | life_support | – | armoured drum, heavy door on +X | – | start |
| habitat | Habitat | room | housing | habitat | dome with portholes; L/XL add a second deck | S–XL | start |
| lounge | Lounge | room | comfort | habitat | panorama glass dome | S–XL | start |
| cantina | Cantina | room | comfort | habitat | dome + neon sign + terrace canopy | S–XL | comfort_1 |
| medical | Medical Bay | room | medical | habitat | white dome, red cross roof | S–XL | start |
| bio_lab | Bio-Lab | room | medical | habitat | cluster of white pods, green cross | S–XL | med_1 |
| storehouse | Storehouse | room | logistics | habitat | wide low drum; L/XL add silos | S–XL | start |
| cold_storage | Cold Storage | room | logistics | habitat | frosted drum with radiator fins | S–XL | log_1 |
| greenhouse | Greenhouse | room | food | agri | geodesic glass dome over crop trays | S–XL | start |
| fungus_farm | Fungus Farm | room | food | agri | dark ribbed dome, violet grow lights | S–XL | agri_2 |
| algae_bioreactor | Algae Bioreactor | room | food | agri | ring of glowing green tubes around a core | S–XL | agri_3 |
| kitchen | Kitchen & Mess | room | food | agri | dome with extractor chimney | S–XL | start |
| research_lab | Research Lab | room | science | science | stacked hex pods + observatory dome with telescope | S–XL | start |
| mine | Mine | room | industry | industry | dome + lattice headframe + ore hopper | S–XL | start |
| refinery | Refinery | room | industry | industry | shed + furnace + chimney | S–XL | start |
| polymer_plant | Polymer Plant | room | industry | industry | round vats + pipe racks | S–XL | start |
| workshop | Workshop | room | industry | industry | shed + roof crane | S–XL | start |
| glassworks | Glassworks | room | industry | industry | kiln dome + stack + cooling bed | S–XL | ind_1 |
| electronics_fab | Electronics Fab | room | industry | industry | clean-room block with ducts, blue light | S–XL | ind_2 |
| fabricator | Fabricator | room | industry | industry | tall hall with gantry arm | S–XL | ind_3 |
| regolith_harvester | Regolith Harvester | exterior | industry | industry | tracked scoop + conveyor + hopper | S–XL | ind_1 |
| fuel_refinery | Fuel Refinery | exterior | industry | industry | spherical tanks + cracking column | S–XL | space_1 |
| deep_drill | Deep Core Drill | exterior | industry | industry | tall derrick with drill string | – | sci_2 |
| comms_tower | Comms Tower | exterior | logistics | – | lattice mast + dish + beacons | – | space_2 |
| landing_pad | Landing Pad | exterior | logistics | – | ringed pad with lights | – | start |
| junction | Junction | room | logistics | – | small hub | – | start |
| corridor, cable | links | link | – | – | as v1 | – | start |
| meridian | The Meridian | special | space | – | crashed 42 m colony ship (§9) | – | world |

**Round base rule.** Corridors meet a room wall at any angle, so every room has a round (or
16-sided) base ring and wall up to 1.4 m at its footprint radius. The variety is above that.

**Automatic machines** (no workers; need power and inputs from networks or hauling):
water extractor, oxygen plant, water recycler, atmosphere processor, algae bioreactor,
regolith harvester, fuel refinery, deep drill, fusion reactor. **Staffed machines** need a
specialist working inside: mine (operator), kitchen (operator), refinery, polymer plant,
workshop, glassworks, electronics fab, fabricator (technician), bio-lab (medic), research lab
(scientist). Multi-recipe machines let the player choose the recipe (fabricator,
electronics fab, bio-lab, kitchen = automatic menu).

---

## 3. Items — `content/items.json`

34 item types in 7 categories. Every physical unit is still in an inventory; carriers carry 2.

| category | items |
|---|---|
| raw | ore (Iron ore), silicate (Silicate sand), exotic (Exotic crystal) |
| material | metal (Steel), glass (Glass), polymer (Polymer), biomass (Biomass) |
| component | spare_parts, electronics, hull_plate, composite, rocket_fuel |
| medical | medicine |
| water | water (Water can) |
| crop | potato, wheat, soybean, tomato, greens, mushroom, algae, herbs |
| dish | meals (**Emergency ration** — the v1 id stays), mashed_potato, flatbread, garden_salad, algae_bar, herb_potatoes, tomato_pasta, soy_stew, mushroom_risotto, tofu_stirfry, veggie_pizza, colony_feast |

**Spoilage.** Items with `shelf_days` spoil in ordinary storage: each inventory keeps a
deterministic accumulator per item, `acc += count × dt / (shelf_days × day_length)`; each whole
unit of `acc` destroys one unit (ledger "destroyed", reason `spoiled`). Cold Storage and
machine input buffers do not spoil. Difficulty "relaxed" turns spoilage off.

v1 migration: `raw_food` → `potato`, `meals` stays (Emergency ration).

---

## 4. Crops — `content/crops.json`

A tray grows one crop. The player sets the crop per greenhouse (all trays) or per tray.
Default crop of a new greenhouse: `potato`.

| crop | grows in | cycle s | yield | biomass | water/day | research |
|---|---|---:|---:|---:|---:|---|
| potato | greenhouse | 300 | 5 | 2 | 4 | start |
| wheat | greenhouse | 300 | 5 | 3 | 4 | start |
| greens | greenhouse | 180 | 4 | 1 | 3 | start |
| tomato | greenhouse | 240 | 4 | 1 | 4 | agri_1 |
| soybean | greenhouse | 360 | 3 | 2 | 5 | agri_1 |
| herbs | greenhouse | 200 | 3 | 1 | 2 | agri_1 |
| mushroom | fungus_farm | 240 | 4 | 1 | 2 | agri_2 |
| algae | algae_bioreactor | continuous | 8/day (M) | 0 | 6 | agri_3 |

---

## 5. Dishes and nutrition — `content/dishes.json`

**One dish is one colonist's food for one day** (spec: one meal per colonist per day).
A kitchen batch uses the listed ingredients and makes as many dishes as it used ingredient
units. Better dishes need a higher kitchen level and more work per dish.

Each dish gives four nutrition values — **protein, carbs, fat, vitamins** — and a **taste**.

| dish | ingredients | kitchen L | work/dish | P | C | F | V | taste |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| meals (Emergency ration) | – (lander, supply) | – | – | 50 | 50 | 50 | 50 | 0 |
| mashed_potato | potato 2 | 1 | 8 | 12 | 85 | 15 | 30 | 3 |
| flatbread | wheat 2 | 1 | 8 | 20 | 85 | 12 | 10 | 2 |
| garden_salad | greens 1, tomato 1 | 1 | 8 | 10 | 20 | 10 | 90 | 4 |
| algae_bar | algae 1, wheat 1 | 1 | 8 | 80 | 45 | 25 | 35 | 1 |
| herb_potatoes | potato 2, herbs 1 | 2 | 10 | 15 | 80 | 25 | 40 | 7 |
| tomato_pasta | wheat 2, tomato 1 | 2 | 10 | 25 | 80 | 20 | 45 | 6 |
| soy_stew | soybean 1, potato 1, greens 1 | 2 | 10 | 55 | 50 | 40 | 55 | 6 |
| mushroom_risotto | mushroom 1, wheat 1, herbs 1 | 3 | 12 | 35 | 70 | 35 | 40 | 8 |
| tofu_stirfry | soybean 2, greens 1, herbs 1 | 3 | 12 | 85 | 30 | 55 | 60 | 8 |
| veggie_pizza | wheat 2, tomato 1, mushroom 1, herbs 1 | 4 | 16 | 40 | 75 | 60 | 50 | 11 |
| colony_feast | potato, wheat, soybean, tomato, greens, herbs (1 each) | 5 | 20 | 70 | 70 | 70 | 80 | 16 |

**Colonist nutrition** (`agent.nutrition`, 0..100 each, start 50): each meal moves every
value 40% toward the dish values (`nutrition.meal_weight` 0.4), so the values are a moving
average of what a colonist eats. Values drift toward 0 only while a colonist is critically
hungry. **Score** = mean of the four. (Dish values in the table above were re-tuned during
balancing; `content/dishes.json` is the source.)
- Well fed: score >= 70 and every value >= 40 -> morale +6, health regeneration x 1.5.
- Deficient: any value < 20 -> morale -8, work -10%, alert "Low protein" (etc.).
- Starved of a nutrient: any value < 8 -> health loss.
- Variety: distinct dishes in the last 6 meals >= 4 -> morale +5; only 1 -> morale -4.
- Taste: morale target + 0.5 x mean taste of the last 3 meals.
- Goal "Balanced diet": score 55 averaged over one day.

**Choosing what to eat** (deterministic): score = Σ max(0, 70 − n_d) × dish_d / 100
+ 0.6 × taste + 4 if not eaten in the last 3 meals. Highest wins; ties by item id.
**Kitchen menu planner**: each batch picks the unlocked dish (by kitchen level, not excluded by
the player) whose ingredients are in the input buffer and that best fills the **colony's**
average deficit, plus taste, plus a bonus when that dish is low in stock. The kitchen asks for
up to 4 units of every crop that any of its dishes uses.

---

## 6. Research — `content/research.json`

A **Research Lab** (scientist) turns work into research points (RP):
`RP = work points × 0.1 × level multiplier × research bonuses`. RP go to the **active project**;
when it completes the next project in the **queue** starts. 29 techs in 5 tiers. Tier 5 is
**special research**: RP **and exotic crystals delivered to a research lab**; each one unlocks
**Level 5** for one building family:

| tier 5 tech | family | L5 for |
|---|---|---|
| s_agri Quantum Hydroponics | agri | greenhouse, fungus farm, algae bioreactor, kitchen |
| s_energy Stellarator Containment | energy | solar, wind, battery, fusion |
| s_life Terraforming Catalysts | life | oxygen plant, water extractor, reservoir, recycler, atmosphere processor |
| s_ind Nanofabrication | industry | mine, refinery, polymer, workshop, glassworks, electronics, fabricator, harvester, fuel refinery, deep drill |
| s_hab Arcology Design | habitat | habitat, lounge, cantina, medical, bio-lab, storehouse, cold storage |
| (science family) | science | research lab L5 is unlocked by **s_hab** |

Sizes: S and M are free; **L needs `eng_1`, XL needs `eng_2`** (per building override allowed).

---

## 7. Base goals — `content/goals.json`

The mission is 5 **chapters**. A chapter's goals show when the chapter opens; the next chapter
opens when every goal of this one is done. Each goal is a **pure function of state** with an
optional **sustain** time (the condition must hold without a break). Rewards arrive as a
**supply pod**: a ground pile next to the lander (real units, ledger reason `reward`), plus RP.

1. **Touchdown** — Power online · Water flowing · First breath (base air) · Shelter (everyone
   has a base bed).
2. **Sustain** — **O2 supply** (make ≥ 120% of breathing, 1 day) · **Water supply** (≥ 1.5 days,
   1 day) · **Food supply** (dishes ≥ 2 days) · **Power supply** (a full night, no life-support
   shedding) · Balanced diet (nutrition ≥ 70 for 1 day).
3. **Industry** — Iron will (50 metal) · Silicon age (20 electronics) · Science (3 techs) ·
   Growing settlement (20 colonists) · First upgrade (any building L3).
4. **The Meridian** — Survey the wreck · Patch the hull · Restore systems · Fuel the engines ·
   Test flight (§9).
5. **Frontier** — **Full supply** (O2, water, food + nutrition, power, spares, all at once for
   3 days) · **Ship maintenance** (readiness ≥ 80% for 5 days) · Established colony (50) ·
   Pinnacle (any building L5) → **Victory: Frontier established** (continue in sandbox).

## 8. Awards — `content/awards.json`

32 medals in 4 tiers (bronze, silver, gold, platinum). The simulation records the tick when
each is earned in `state.awards`. The interface also keeps a **profile** of every award ever
earned on this device (`user://profile.json`) and shows a medal pop-up and a gallery.

## 9. The Meridian

World generation places the crashed colony ship **55–75 m from the lander** on flat ground, in
the direction with the fewest rocks. Footprint: a capsule 40 m long, radius 7 m. It is a
building record `def: "meridian"`, kind `special`. Repair stages (balance.json `ship`):

| stage | name | deliver | work | visual |
|---|---|---|---:|---|
| 0 | Wreck | – | 60 (survey, anyone) | damage, dust, no lights |
| 1 | Hull | hull_plate 30, metal 40 | 600 | scaffold on; Damage1 removed at the end |
| 2 | Systems | electronics 25, glass 10 | 500 | Damage2 removed, cabin lights on |
| 3 | Engines | rocket_fuel 40, composite 10 | 400 | Damage3 removed, engine glow |
| 4 | Test flight | readiness 100 | – | the ship lifts 20 m, hovers, lands |
| 5 | Operational | – | – | ready for maintenance and supply runs |

Work is exterior work from access points around the capsule (suit range applies: a forward
airlock near the wreck is the intended solution). **Maintenance**: readiness falls 8 per day
when operational; a maintenance task (technician, 40 work) uses 1 rocket_fuel + 1 spare_parts
and adds 15. **Supply runs** (research `space_2`): every 2 days, if readiness ≥ 60, the ship
flies (uses 10 fuel, −10 readiness) and returns the next day with a supply pod: exotic 4,
medicine 6, electronics 6, and up to 4 settlers if immigration is open and beds are free.

---

## 10. State and command contract (simulation ↔ interface)

New and changed **state** (always read with `.get(key, default)` for old saves):

| where | field | meaning |
|---|---|---|
| building | `size` int 0..3 (default 1) | S, M, L, XL |
| building | `level` int 1..5 (default 1) | upgrade level |
| building | `upgrade` {} or {to, cost{}, inv, progress, work_total, state} | an upgrade in progress |
| building | `recipe_sel` String | chosen recipe of a multi-recipe machine |
| building | `crop` String; `trays[i].crop` String | crop plan |
| building | `menu_off` {dish: true} | dishes this kitchen must not cook |
| agent | `role` adds `scientist` | |
| agent | `nutrition` {protein, carbs, fat, vitamins} | 0..100 |
| agent | `diet` Array of the last 6 dish ids | |
| state | `research` {active, queue[], progress{}, done{}, paid{}, rp_total} | |
| state | `goals` {chapter, status{id: {state, value, target, since, done_tick}}} | state = locked, active, done |
| state | `awards` {id: tick} | |
| state | `ship` {id, stage, readiness, runs, next_run_tick, away} | |
| state | `stats` {produced{}, consumed{}, spoiled{}, cooked{}, harvests, heals, …} | lifetime counters |
| state | `metrics.series` {name: [[tick, value], …]} | chart data, sampled every 10 s, 720 points |
| state | `metrics.daily` [{day, produced{}, consumed{}}] | one row per day |
| state | `options` {planet, difficulty, spoilage} | |
| state | `events` {storm: {...}} | hazards (stretch goal) |

Series names (at least): `pop`, `morale`, `nutrition`, `o2_stock`, `o2_make`, `o2_use`,
`water_stock`, `water_in`, `water_out`, `power_gen`, `power_use`, `energy`, `food_days`,
`rp_rate`, `ship_readiness`, and `item:<id>` for every item total.

New **commands** (payloads are Dictionaries; results as v1):

| kind | payload |
|---|---|
| place_building | + `size` 0..3 (default 1) |
| upgrade / cancel_upgrade | {id} |
| research | {tech} — make it active (moves to front of queue) |
| research_queue | {techs: [..]} |
| set_crop | {id, crop, tray: -1 for all} |
| set_recipe | {id, recipe} |
| set_dish | {id, dish, on: bool} |
| set_immigration | {roles: [..], cap: int, open: bool} |
| ship | {action: "survey" \| "supply_run" \| "hold"} |

Read-only helpers the interface may call (the SIM agent implements these names):
`sim.sizes.def_for(def_id, size) -> Dictionary` · `sim.sizes.allowed(def_id, size) -> {ok, code}`
· `sim.upgrades.check(b) -> {ok, code, to, cost, research}` · `sim.research.state_of(tech) ->
"done|active|queued|available|locked"` · `sim.research.rp_rate() -> float` ·
`sim.goals.chapter()`, `sim.goals.list()` · `sim.nutrition.colony() -> {protein, carbs, fat,
vitamins, score}` · `sim.metrics.series(name) -> Array` · `sim.items.info(id) -> Dictionary` ·
`sim.ship.info() -> Dictionary`.

---

**Other contract details**
- `sim.place.check_building(def_id, pos, rot, ignore_id := -1, size := 1)` — size is the 5th argument.
- A reward or supply-run pile is an ordinary ground pile whose inventory has `"pod": true`; the
  view draws a supply-pod model for it.
- Progress logs: each agent keeps `docs/progress/<AGENT>.md` (date, what landed, what is next).
  Requests between agents: `docs/requests/<FROM>-to-<TO>.md`. Read the requests addressed to you
  at every milestone.

## 11. Asset contract (Blender → Godot)

- Units metres, Blender Z up, glTF +Y up, origin at ground level at the footprint centre, front
  +X, doors +X. Apply rotation and scale; keep object origins at pivots (rotor hub, limb joints).
- **Files**: sized buildings `assets/models/<id>_s.glb`, `_m.glb`, `_l.glb`, `_xl.glb`; single-size
  `assets/models/<id>.glb`. The loader falls back `<id>_<size>` → `<id>` → a primitive.
- **Top-level objects**: rooms `Base`, `Roof`, `Interior`; exteriors `Base`; plus `L2`, `L3`, `L4`,
  `L5` (upgrade parts, shown when level ≥ n); `Rotor` (wind); `Lights` (emissive parts that turn
  on at night — optional); empties named `Anchor_<name>` are allowed (engine nozzles, door,
  chimney tops for smoke).
- **Materials by name** (v1 list stays): `Hull`, `HullDark`, `Frame`, `Metal`, `Rubber`, `Glass`,
  `Window`, `Accent`, `Solar`, `Soil`, `Plant`, `PlantDark`, `WaterBlue`, `Hazard`, `Ore`,
  `OreVein`, `Cargo`, `Fabric`, `Light`, `SuitMain`, `SuitAccent`, `Visor`, `Pack`; new: `Trim`
  (#B8C2CC metal), `L3Band` (#3EE0FF emissive 1.2), `L4Band` (#A78BFA emissive 1.2), `L5Gold`
  (#FFD166 metallic 0.9 emissive 0.6), `Neon` (category colour, emissive 3), `Frost` (#DDEFFF),
  `Glow` (#9CFFB0 emissive 3, algae), `Plasma` (#8FD8FF emissive 5, fusion core).
- **Vertex colour AO**: bake ambient occlusion into a colour attribute and export it as COLOR_0
  (`export_vertex_color='ACTIVE'`). White = open, dark = occluded, alpha 1. The loader multiplies.
- **Write atomically**: export to `<name>.tmp.glb`, then rename.
- **Greenhouse trays** must sit exactly at `content/buildings.json` → `greenhouse.sizes.tray_offsets[size]`
  (Blender X = content x, Blender Y = content y), tray 3.0 × 1.4 m, soil top at z = 0.55.
- **Crops**: `assets/models/crop_<crop>.glb` with `Stage1`, `Stage2`, `Stage3` at the origin,
  covering 2.8 × 1.2 m. Mushrooms and algae: shapes that fit their buildings' beds/tanks.
- **Colonists**: `colonist_suit.glb` (outside) and `colonist_indoor.glb` (no helmet, jumpsuit),
  objects `Body`, `ArmL`, `ArmR`, `LegL`, `LegR`, origins at joints; `SuitAccent` is recoloured
  per role in the game.
- **Meridian**: `assets/models/meridian.glb`, objects `Hull`, `Damage1`, `Damage2`, `Damage3`,
  `Scaffold`, `Lights`, `EngineGlow`; empties `Anchor_Engine_L`, `Anchor_Engine_R`,
  `Anchor_Ramp`. Length 42 m along X, lying on its belly, tilted 4°, half buried at the nose.
- **Thumbnails** for the build menu: `assets/thumbs/<id>_<size>.png` (or `<id>.png`), 256 × 256,
  transparent background, same 3/4 camera and studio light for all.
- **Budgets** (triangles): S 3k, M 4.5k, L 6.5k, XL 9k; Meridian 30k; crop stage 1.5k; colonist 1.5k.

## 12. Presentation contract (`presentation/world_view.gd` API used by `main.gd`)

`setup(sim)`, `sync(delta)`, `h(x, y)`, `to3(p, lift)`, `ground_point(camera, screen) -> Vector2|null`,
`pick(p, include_agents) -> {kind, id}`, `select(kind, id)`, `set_overlay(name)`,
`agent_world_pos(id)`, **new**: `set_ghost(def_id, size, pos, rot, valid)`, `clear_ghost()`,
`set_link_preview(p0, p1, kind, valid)` (null to hide), `set_quality(level 0..3)`,
`set_time_override(second_of_day or -1)` (visual only, for the title screen and screenshots),
`focus_event(kind, id)` (camera shake/flash hooks, optional).

## 13. Interface screens (UI agent)

Title screen (3D colony at dusk behind the menu) · New colony (planet cards, difficulty, seed) ·
HUD (resource bar with icons and trends, time and day dial, goals tracker, alerts, minimap,
build bar with thumbnails and S/M/L/XL chips, inspector with tabs) · Research tree · Goals ·
Awards gallery + pop-ups · Colony dashboard with charts · Inventory (all items by category,
stock, trend, spoilage) · Nutrition · Colonists list · Pause, save/load, settings.

## 14. Boot parameters and the automation hook

Browser: URL query. Desktop: user arguments (`-- --seed=1001`). Implemented in
`presentation/boot.gd` and `presentation/main.gd`.

| param | meaning |
|---|---|
| seed | world seed (default 1001) |
| load | `res://content/saves/<file>.fhsave` to load at start |
| demo | play the reference layout (`all` for the full campaign) |
| fast | simulate this many seconds before the first frame |
| speed | 0, 1, 2, 4 |
| open | a screen to open at start (menu, colony, research, goals, awards, dashboard, inventory) |
| title | 1 = start on the title screen |

`window.__fh = {ready, tick, day, last, cmd(text)}`. Commands: `speed n`, `fast s`, `demo`,
`overlay <name|off>`, `select <def>`, `open <screen>`, `close`, `zoom <m>`, `yaw <deg>`,
`pitch <deg>`. The UI agent may add commands; keep these working.

## 15. Ownership

| path | owner |
|---|---|
| `sim/**`, `content/**`, `tests/**` | **SIM** |
| `tools/blender/build_assets.py` and new `tools/blender/rooms_*.py`; `assets/models/` + `assets/thumbs/` for **room** types, airlock, junction, corridor | **ART-A** |
| `tools/blender/ext_*.py`; `assets/models/` + `assets/thumbs/` for **exterior, special, crop, colonist, prop** files; `assets/textures/props/` | **ART-B** |
| `presentation/world_view.gd`, `presentation/models.gd`, `presentation/camera_rig.gd`, new `presentation/fx_*.gd`, `shaders/**`, `assets/textures/terrain/`, `assets/textures/sky/` | **RENDER** |
| `presentation/main.gd`, `presentation/boot.gd`, `main.tscn`, `ui/**`, `assets/ui/**`, `assets/fonts/**`, `assets/audio/**`, `project.godot` | **UI** |
| `docs/AAA_DESIGN.md`, `export_presets.cfg`, `tools/godot.mjs`, `tools/shoot.mjs`, `tools/serve.mjs`, `build/web/` | **orchestrator** |

Content is shared data: SIM owns the files and may tune numbers; art agents read
`content/buildings.json` (radii, tray layouts); UI reads everything.
