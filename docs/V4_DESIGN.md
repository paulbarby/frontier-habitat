# Frontier Habitat 4.0 — exploration, vehicles, multi-base, deep tech, new interface

Version 4.0 · 27 September 2026 · Owner: orchestrator

This file is the contract for version 4.0. It adds to `docs/V3_1_DESIGN.md`, `docs/V3_DESIGN.md` and
`docs/AAA_DESIGN.md`. **Every agent reads V3_DESIGN §0, §9, §10, V3_1_DESIGN §0 and all of this file
before it starts.** Where the files disagree, this file wins. Numbers live in `content/*.json`.

Paul's request (27 September 2026, lightly cleaned):
*"The habitats are hard to identify when trying to find a module, as they all look very similar. We
need an advanced rover depot and rovers, small and medium: small are for around the base, medium is
for base to base. Also multi-base. The overall scale of the habitats needs to be bigger. Have
multiple advanced materials, and expand the research tree, the tech tree and the crafting tree —
just increase complexity — and add more helpers. Redo the windows system, it is clunky, and change
the style of the UI to be more refined, almost like a glass theme with space-age metal frames,
rivets and seam lines. Make sure the version is shown in the menu. Expand the planet to be 10×
bigger, with more diverse landscapes and geography, including crevices, massive boulders, mountains
that you have to go around, plateaus that are higher, and massive craters that are deep, get little
sun and have proper shadows. Have radiation levels, and the best materials and finds are in
dangerous areas. Allow exploration with rovers, hoppers and a satellite, and more control over NPCs,
e.g. giving goals such as 'board rover', and the player can give it a map point to explore. So more
exploration. Structure the resources for maximum fun and growing diversity: the basics get you
started, the mid level lets you get more advanced, and the final high-end stuff is a massive benefit
but dangerous and costly — mistakes at this level destroy entire bases, e.g. nuclear accidents. Make
it fun."*

---

## 0. Ground rules

All earlier ground rules apply: never open a window on Paul's desktop; Godot only through
`node tools/godot.mjs`; Blender only with `--background`; export to `build/web_<you>/`; keep `check`
clean; simulation authoritative and deterministic; ledgers stay `{}`; player text in plain STE
English; report honestly, including what you did not test.

**Budgets (web, `shoot.mjs --gpu`, this PC):**
- Overview of the v4 showcase (2 bases, ~100 colonists, 6 vehicles) ≥ 50 fps at quality high;
  draw calls ≤ 1,500; no frame over 50 ms in 120 s after load (except under the load cover).
- Sim tick ≤ 2.5 ms median at 100 colonists + 6 vehicles over 2 bases; world generation ≤ 4 s.
- **`index.pck` ≤ 95 MB (hard: GitHub refuses files over 100 MB).** It is 79.7 MB now. Every art
  agent reports its size effect; use mesh compression, shared materials, lower-bitrate audio.
- Save schema 5. v3.x, v3 and v2 saves load and play on their own map size.

**Visual gate.** CRITIC (V3_DESIGN §9, pass ≥ 0.65). Pilots first (§12).

---

## 1. The planet — 10× bigger and diverse (SIM generates; RENDER draws)

- **Size:** 2,560 m × 2,560 m (10× the area of 810 m). The start plateau stays flat and safe (≥ 125 m).
- **Terrain features**, deterministic from the seed, each with content-tunable counts:
  - **Mountain ranges:** impassable on foot and for rovers above slope 0.6; you go around them. Passes
    exist. Peaks carry exotic finds.
  - **High plateaus:** 20–60 m above the plain, reached by ramps or by hoppers; good sun, windy.
  - **Deep craters:** 200–600 m wide, 40–120 m deep. The floor gets little sun (real horizon shadow,
    §1.1): solar output there is 10–30 %. Cold traps hold **water ice and helium-3**.
  - **Crevices:** long narrow cracks, 3–15 m wide, 10–40 m deep. Rovers cannot cross; bridges
    (buildable) or hoppers can. They hold **rare earths**.
  - **Boulder fields:** massive boulders 4–20 m; they block building and slow rovers.
  - Dunes, flats and the existing canyons and ridges.
- **Radiation field** (`sim.world.rad_at(x, z)`, mSv/h): low on the plain; higher on peaks,
  crater rims and near **uranium/thorium deposits**; spikes during solar flares; reactor leaks
  add to it. Colonists accumulate dose (suit and habitat shielding reduce it); high dose causes
  sickness and death. Research gives shielding.
- **Where the good things are:** each material tier (§4) is placed so that basic materials are on
  the safe plain, mid materials at moderate distance and risk, and high-end materials only in
  dangerous places (deep dark craters, radiation fields, crevice floors, peaks).
- **Nav:** hierarchical (region graph + local grid) so paths across 2.5 km stay fast. Vehicles have
  their own passability (rover slope limit, hopper jump range).

### 1.1 Shadows and light (RENDER)
Craters are dark because the terrain blocks the sun: a baked horizon map from the heightmap gives
each point its sun visibility for the current sun angle (sim uses the same data for solar output).
Real-time shadows near the camera; horizon shadows everywhere. Deep crater floors read as dark and
cold, with lights of any base inside them standing out.

## 2. Bases and scale (SIM, ART-HAB, RENDER, UI)

- **Multi-base.** The colony can have several bases anywhere on the map. A base = a connected
  corridor network with its own power, water and air. A new base is founded by an **Outpost Kit**
  (a crafted item carried by a medium rover and deployed: a small lander-like core with air for 3
  days). Each base has a name; alerts, stocks and charts can filter by base.
- **Logistics between bases:** medium rovers run **routes** (load at base A, unload at base B) set by
  the player. Colonists can transfer between bases by rover.
- **Bigger habitats.** New rooms are built at **1.5× the v3 radius** for every size (S–XL); corridors
  1.25× wider. Colonist size does not change, so rooms get more floor and more furniture. Old saves
  keep their radii (RENDER already scales by saved radius).

## 3. Finding a module — every family reads differently (ART-HAB, RENDER, UI)

Paul: "the habitats are hard to identify … they look all very similar."
1. **Silhouette per family** (the roof and upper wall): habitat = low dome with windows; comfort =
   dome with a glass skylight; medical = white dome with a red cross on the roof; food = glass
   greenhouse vault / fungus hood; industry = flat roof with stacks and vents; science = dome with a
   sensor mast; life support = tanks and pipes on the roof; logistics = flat roof with a crane;
   power = vertical, distinct. Each family must be recognisable **from the overview camera without
   labels** (critic test at 110 m and 250 m).
2. **Roof badge:** a large family icon painted on the roof, readable at 250 m.
3. **Family colour** on the band (exists) made stronger.
4. **UI:** a **Find** box (type "kitchen" → list with base, size, status → click jumps the camera),
   a minimap with family icons, an optional label layer by family, and a highlight of all rooms of
   one type.

## 4. Materials, crafting and the tech tree (SIM owns content; UI shows)

### 4.1 Three tiers
| tier | purpose | examples (SIM finalises) | where |
|---|---|---|---|
| basic | get started | regolith, metal ore → metal, silicates → glass, water ice, polymer | safe plain |
| mid | grow and specialise | steel alloy, titanium, ceramics, composites, electronics, carbon fibre, batteries, rover parts | moderate distance, crevice edges, plateau |
| high-end | massive benefit, dangerous and costly | uranium ore → fuel rods, helium-3, rare-earth magnets, superconductors, graphene, exotic crystal, metamaterials | deep dark craters, radiation fields, crevice floors, peaks |

- **Crafting tree:** ≥ 60 items and ≥ 40 recipes (now 37 items, 14 recipes). Multi-step chains, by-products,
  and recipes that need a specific building level. Each high-end item has at least a 3-step chain.
- **Research tree:** ≥ 80 techs (now 45) in branches (engineering, life, industry, energy, vehicles,
  exploration, radiation, logistics, deep tech). Tier-3 techs need high-end materials or finds.
- **Finds** from exploration (§5): data cores, derelict parts, meteorite samples, blueprints —
  they unlock or speed up techs.

### 4.2 High-end danger (the fun and the risk)
- **Fission reactor:** huge power; needs fuel rods, coolant water and maintenance. Neglect, coolant
  loss, a quake or a meteor can start a **meltdown sequence** (warning → critical → breach). A
  breach explodes (destroys structures within its radius, content-defined, ~40–80 m), creates a
  long-lasting radiation zone and can **wipe out a base**. The player sees it coming (deterministic
  forecast from state) and can act: SCRAM, cool, evacuate.
- **Fusion reactor** (later): helium-3, superconductors; smaller blast risk but costly.
- **Other risky high-end:** exotic crystal refinery (unstable: fire/explosion on power loss),
  chemical plant (toxic leak). Each risk is visible, predictable from state, and preventable.
- Mistakes are allowed to cost a whole base; the colony survives if other bases exist.

## 5. Exploration and vehicles (SIM, ART-B, RENDER, UI)

- **Fog of war:** the map starts unexplored beyond the start area. Colonists, rovers, hoppers and the
  satellite reveal it.
- **Points of interest** (deterministic): wrecks, caves, anomalies, derelict probes, meteorite
  fields, rich deposits. Visiting one with the right vehicle and crew gives a find.
- **Vehicles** (each a sim agent with fuel/charge, cargo, crew seats, wear):
  - **Rover depot** (building, sizes M/L, advanced version): builds, charges, repairs and stores
    rovers; research gated.
  - **Small rover:** 2 seats, small cargo, short range; for work around the base (hauling, repairs
    far from airlocks, mining outposts).
  - **Medium rover:** 4–6 seats, large cargo, long range, pressurised cabin (crew can stay in it);
    for base-to-base routes, carrying Outpost Kits, and expeditions.
  - **Hopper:** short flights (100–400 m) over crevices and up to plateaus; fuel-hungry.
  - **Satellite:** built and launched from a launch pad; reveals the map in bands over time and
    shows radiation and deposits; needs an uplink.
- **Orders — more control over colonists (SIM + UI):** the player can select colonists (one or a
  group) and give orders: *go to point*, *board vehicle*, *drive to point / explore area*, *survey
  POI*, *work at*, *stay*, *return to base*. Also per-colonist job priorities and allowed jobs.
  Orders override the AI until done; the AI refuses orders that would kill the colonist (air,
  radiation) with a clear reason unless the player confirms.

## 6. Helpers (UI; SIM supplies data)

"More helpers" = help for the player:
- An **advisor** panel: "what to do next" from colony state (next goal steps, the biggest problem,
  unused potential).
- **Encyclopedia** (codex): every building, item, recipe, tech, hazard, vehicle — with where it
  comes from and what uses it (crafting tree view).
- **Planner overlays:** radiation, sun (crater shadow), resources, explored area, vehicle ranges.
- Rich tooltips on everything; "why is this stopped?" on every structure and colonist.

## 7. The interface — new window system and a refined glass style (UI)

- **Window manager:** one system for all windows. Windows open in predictable places, can be
  dragged, snap to edges, stack without covering the HUD essentials, remember their positions per
  window, close with Esc (last first), one click to close all, never leave the view (V3.1 rule), and
  scale with the interface scale. Fewer, larger windows with tabs instead of many small popups.
- **Style — "space-age glass":** frosted translucent glass panels (blurred background), brushed-
  metal frames with **rivets**, **seam lines** and bevelled corners, subtle inner glow on edges,
  refined typography, calm palette with family accent colours. Consistent across HUD, windows,
  buttons, tabs, lists, charts and menus. Performance: the blur must not break the frame budget.
- **Version** shown on the title/menu screen (from `project.godot` `application/config/version`,
  set to `4.0.0`) and in the settings "About".

## 8. Rovers and vehicles on screen (RENDER)
Vehicles drive on the terrain with suspension and wheel spin, dust trails, headlights at night;
hoppers take off and land with thrust and dust; the satellite is shown in orbit on the map and its
reveal bands on the minimap; colonists board and leave vehicles with an animation or a fade at the
door.

## 9. Content and saves (SIM)
Save schema 5 (bases, vehicles, fog, dose, reactors, new items). Migrations: v3.x → 5 keeps the 810 m
map; v2 keeps 256 m. New showcase `showcase_v4.fhsave`: 2 bases on the 2,560 m map, a rover route
between them, a reactor, an expedition rover at a crater rim, satellite partly revealing.

## 10. CRITIC subjects for 4.0
| subject | evidence |
|---|---|
| `ui_theme` | the new glass/metal style on HUD, windows, menus (pilot: one window + HUD bar) |
| `room_identity` | overview shots at 110 m and 250 m: can each family be named without labels? |
| `terrain_v4` | mountains, plateaus, deep dark craters, crevices, boulder fields; day and night |
| `vehicles` | rover depot, small and medium rover, hopper, satellite and launch pad; in-game driving and flight |
| `reactor_and_disaster` | reactor model, meltdown warning, explosion and radiation zone |
| `exploration` | fog, POIs, finds, satellite reveal |
Plus the earlier subjects must not drop.

## 11. Ownership
As V3_1_DESIGN §10, plus:
| path | owner |
|---|---|
| `tools/blender/vehicle_*.py`, `assets/models/vehicle_*`, `satellite*`, `launch_pad*`, `art/vehicles/**` | **ART-B** |
| rover depot, reactor, new industry buildings, room identity (roofs, badges), scaled rooms | **ART-HAB** |
| `sim/**`, `content/**`, `tests/**` (world gen, nav, bases, vehicles, orders, tiers, reactor, radiation, fog, POIs) | **SIM** |
| terrain v4 drawing, horizon shadows, vehicles, fog drawing, overlays, disaster effects | **RENDER** |
| window manager, theme, helpers, codex, find, orders UI, vehicles UI, multi-base UI, version | **UI** |
| visitor/colonist changes (radiation suit variant, driver pose) | **ART-NPC** |
| `docs/V4_DESIGN.md`, `tools/audio_probe.mjs`, `build/web/` | **orchestrator** |

## 12. Order of work and pilots
1. **SIM:** world 2,560 m + features + radiation + horizon sun data + hierarchical nav (so RENDER and
   ART can start) → bases and Outpost Kit → vehicles and orders → tiers, crafting, tech tree →
   reactor and disasters → fog, POIs, finds, satellite → saves, showcase, tests, perf.
2. **UI:** theme + window manager pilot (HUD bar + one window) → **critic pilot** → all screens →
   version → find, helpers, codex → orders, vehicles, multi-base, tech tree UI.
3. **ART-HAB:** room identity pilot (habitat, kitchen, workshop, lab at 1.5× scale) → **critic
   pilot** → all rooms at 1.5× → rover depot, reactor, new industry buildings.
4. **ART-B:** small rover pilot → **critic pilot** → medium rover, hopper, satellite + launch pad.
5. **RENDER:** terrain v4 + horizon shadows pilot → **critic pilot** → vehicles, fog, overlays,
   reactor disaster, multi-base camera → perf.
6. **ART-NPC:** driver/seated-in-vehicle pose, radiation suit variant.
7. **CRITIC:** pilots, then full rounds.
8. **Orchestrator:** integrate, build, tests, audio probe, pck size, critic final, report.

## 13. Changes from Paul, 27 September 2026 (afternoon)
- **Door sounds** only right up close: `door_slide` full at camera distance ≤ 10 m and source ≤ 3 m from the focus,
  silent at 18 m / 8 m, 6 dB quieter, one at a time (UI).
- **Corridor links per room:** S up to 4, M 6, L 7, XL 8 (airlock and junction unchanged). Minimum link spacing = door
  housing width (3.44 m + 0.3 m) as an angle at the wall radius, and ≥ 28° (SIM). Every room's free door sectors hold
  that many slots (ART-HAB build check, replaces the 120°/180° rule). RENDER checks 8 doorways on XL.
