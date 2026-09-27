# Critic round 22 — final v4.0 round, in game

Date: 2026-09-28 · Critic (did not build the work) · Rubric: V3_DESIGN §9, V4_DESIGN §10, §13 · Pass ≥ 0.65 ·
Same calibration as rounds 1–21. The full detail with owners is in `round_22.json`.

## Scores

| subject | cons. | appeal | style | score | before | result |
|---|---|---|---|---|---|---|
| vehicles (in game) | 0.76 | 0.74 | 0.74 | **0.75** | 0.73 (Blender) | PASS |
| reactor_and_disaster | 0.72 | 0.68 | 0.70 | **0.70** | new | PASS |
| exploration | 0.72 | 0.68 | 0.70 | **0.70** | new | PASS |
| room_identity (real colony) | 0.78 | 0.74 | 0.76 | **0.76** | 0.72 | PASS |
| terrain_v4 | 0.76 | 0.74 | 0.76 | **0.75** | 0.71 | PASS |
| ui_theme (new v4 screens) | 0.80 | 0.76 | 0.76 | **0.77** | 0.77 | PASS |
| npc_ingame / interior_ingame / doors / airlock / npc_paths | — | — | — | 0.77 / 0.76 / 0.79 / 0.78 / 0.76 | same | not dropped |

**No fails.**

## Evidence

- **RENDER:** `art/critic_input/render/125–141`.
- **UI:** `docs/shots/ui4_*`, `ui5_*`, `ui6_*`.
- **Models:** `art/interiors/v4b/`.
- **My own:** `build/web_render` (09-28 01:53).
  - `showcase_v4` with `debug=1`: base jumps, reactor stage commands, the radiation layer, 300 m and
    700 m overviews, interiors by day and night.
  - A new Frontier game (seed 1001).

  The files are in `art/critic/r22/`, with grids in `art/critic/r22_*.png`.

## What landed

- **Vehicles.** Crew boarding chain, driving with suspension, wheel spin and dust, the hopper's
  spool-up, flight and landing, and a launch-pad lift-off, all from SIM data. Night lights.
- **Reactor.** It reads as a reactor. Warning ring, critical glow at night, and a breach with flash,
  fireball, shock ring, crater and radiation zone. The refinery blast and chemical leak are drawn too.
- **Exploration.** Fog, POI beams with labels, the satellite scan band and a launch. Radiation, sun and
  resource layers.
- **Room identity in the real colony.**
  - At 110 m every family is named at once.
  - At 250 m, 6 of 8 families are certain by day and by night; logistics and industry get confused.
- **Terrain.** The round-20 fixes landed: crater floors readable by day, lofted crevices, broken
  tiling, no rings without the overlay, real boulder meshes.
- **UI.** Tech tree, codex, reactor, vehicles, orders, priorities, depot, dose and advisor all follow
  the theme.

## Fixes by owner

**RENDER**
1. **Radiation zone.** A flat hatched disc with a bright ring reads as a UI target. Make it a ground
   stain with a soft pulsing edge. Show the hard ring only with the layer or a warning on.
2. **Breach scale.** Double the fireball, and add a dust column for 8–10 s and a second slow shock
   ring.
3. **Warning ring.** Thicken it to 3–4 px.
4. **Fog edge.** A 16 m staircase at the overview. Blur 2–3 cells and add a warm rim. Show relief
   faintly under the fog.
5. **POIs.** Give each a readable model or decal 6–12 m across. Now only the beam and ring read.
6. **Hopper.** Add a ground-lit dust ring and a landing glow, so a hop reads from 150 m.
7. **Crevice walls.** Rock noise to break the ribbed "picket fence" pattern.
8. **Camera.** On the frontier map, check that zoom works. My `zoom` did not change the view.
9. **Paths.** Run `render_path_check.gd` on `showcase_v4` and the frontier map. No v4 path check was
   supplied.

**ART-HAB**
1. **Rover depot.** It is the least detailed building: a plain box. Add roof ribs, bay frames with
   stripes and status lights, an annex and an accent band.
2. **Logistics vs industry at 250 m.** A visible crane (6–8 m) and a lighter roof for logistics.
3. **Outpost core.** A lit ring deck and a flag mast, so a second base reads as a base.
4. **Boulders.** Use the rock colour with lit tops and a dust skirt. Now they are dark brown lumps.

**SIM / RENDER**
1. **Parking.** The expedition rover parks on a 30° flank (known). Park only on ≤ 10°, and clamp the
   body tilt at 15°.
2. **Reactor stage.** `reactor stage <x>` advanced one phase and lagged in my run; after "breach" the
   reactor reported "warning". Make it set the named stage (SIM / UI).

**UI**
1. **Empty windows.** Size the routes, vehicles and priorities windows to their content.
2. **Tech tree text.** Node text to 12 px, and locked text to TEXT_2.

## Latest score of every subject

| subject | score | round | | subject | score | round |
|---|---|---|---|---|---|---|
| npc_suit | 0.82 | 5 | | hazard_props | 0.70 | 7 |
| npc_indoor | 0.72 | 5 | | hazard_visuals | 0.70 | 8 |
| npc_animation | 0.78 | 5 | | doors | 0.79 | 22 |
| npc_interaction | 0.73 | 13 | | doorway_decals | 0.80 | 13 |
| npc_ingame | 0.77 | 22 | | airlock | 0.78 | 22 |
| interior_habitat | 0.79 | 7 | | npc_paths | 0.76 | 22 |
| interior_comfort | 0.75 | 7 | | ships | 0.80 | 14 |
| interior_medical | 0.75 | 7 | | landing_pad | 0.75 | 12 |
| interior_food | 0.76 | 7 | | visitors | 0.78 | 14 |
| interior_industry | 0.76 | 7 | | ui_theme | 0.77 | 22 |
| interior_science | 0.73 | 7 | | vehicles | 0.75 | 22 |
| interior_life | 0.77 | 7 | | room_identity | 0.76 | 22 |
| interior_logistics | 0.77 | 7 | | terrain_v4 | 0.75 | 22 |
| interior_links | 0.71 | 7 | | reactor_and_disaster | 0.70 | 22 |
| interior_ingame | 0.76 | 22 | | exploration | 0.70 | 22 |
| doorways | 0.79 | 8 | | interior_lighting | 0.75 | 13 |

All 32 subjects pass. The mean is 0.76. Three reach 0.80: `npc_suit`, `doorway_decals` and `ships`.
The lowest are `hazard_props`, `hazard_visuals`, `reactor_and_disaster` and `exploration`, at 0.70.
