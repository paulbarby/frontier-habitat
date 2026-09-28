# Critic round 23 — final v4.0 round

Date: 2026-09-28 · Critic (did not build the work) · Rubric: V3_DESIGN §9, V4_DESIGN §10 · Pass ≥ 0.65 ·
Same calibration as rounds 1–22. The full detail is in `round_23.json`.

## Scores

| subject | cons. | appeal | style | score | before | result |
|---|---|---|---|---|---|---|
| reactor_and_disaster | 0.76 | 0.72 | 0.74 | **0.74** | 0.70 | PASS |
| exploration | 0.76 | 0.72 | 0.74 | **0.74** | 0.70 | PASS |
| vehicles | 0.78 | 0.74 | 0.76 | **0.76** | 0.75 | PASS |
| room_identity | 0.80 | 0.76 | 0.78 | **0.78** | 0.76 | PASS |
| terrain_v4 | 0.78 | 0.76 | 0.78 | **0.77** | 0.75 | PASS |
| ui_theme | 0.82 | 0.78 | 0.78 | **0.79** | 0.77 | PASS |

**No fails.**

## Evidence

- **RENDER:** `art/critic_input/render/142–144`.
- **ART-HAB:** `art/interiors/v4b/`.
- **UI:** `docs/shots/ui7_*`.
- **My own:** `build/web_render` (09-28 18:11).
  - `showcase_v4` with `debug=1`: base jumps, a breach at 0.6, 2, 6 and 18 s, the zone by day and
    night, fog at 900 m.
  - A Frontier game: two crevices and two boulder fields.

  The files are in `art/critic/r23/`, with grids and crops in `art/critic/r23_*.png`.

## Round-22 fixes, checked

| fix | result |
|---|---|
| Radiation zone as a stain | **Landed.** It has a regular spiral pattern. |
| Bigger breach | **Landed.** A 2× fireball, a dust column for about 6 s, a second ring. |
| Warning ring 3–4 px | **Landed.** |
| `reactor stage` command | **Landed.** The breach fires at once. |
| Fog edge and relief under fog | **Landed.** |
| POI models | **Landed.** All 5 kinds, each with a 12 m mark. |
| Hopper dust and glow | **Landed** (143). |
| Rover tilt ≤ 15° | **Not verified.** No slope shot was supplied. |
| Depot detail | **Landed.** |
| Logistics light roof | **Landed.** Logistics and industry now differ at 250 m. The crane is too small to see there. |
| Outpost ring deck and flag | **Deck landed.** The flag does not read at 110 m. |
| Crevice walls | **Landed.** Rocky lips; the ends are square boxes. |
| Boulders | **Landed.** Lit tops, shadows, a dust skirt. |
| UI window sizes and tech-tree text | **Landed.** |

**Room identity in the real colony at 250 m:** 8 of 8 families by day (was 6 of 8), 7 of 8 by night.

## Remaining small fixes

1. **RENDER:** noise, not a spiral, in the radiation stain.
2. **RENDER:** the satellite scan draws as a flat cyan square and a pale ground cylinder that read as
   debug geometry (`r23_stray_crop.png`). Draw it as a soft moving light band.
3. **RENDER:** one shot of the expedition rover at the crater rim, to close the tilt fix.
4. **ART-HAB:** a larger outpost flag with a mast light.
5. **RENDER:** round the crevice ends.

## Final table — latest score of every subject

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
| interior_industry | 0.76 | 7 | | ui_theme | 0.79 | 23 |
| interior_science | 0.73 | 7 | | vehicles | 0.76 | 23 |
| interior_life | 0.77 | 7 | | room_identity | 0.78 | 23 |
| interior_logistics | 0.77 | 7 | | terrain_v4 | 0.77 | 23 |
| interior_links | 0.71 | 7 | | reactor_and_disaster | 0.74 | 23 |
| interior_ingame | 0.76 | 22 | | exploration | 0.74 | 23 |
| doorways | 0.79 | 8 | | interior_lighting | 0.75 | 13 |

All 32 subjects pass. The mean is 0.76. `npc_suit`, `doorway_decals` and `ships` reach 0.80. The
lowest are `hazard_props` and `hazard_visuals` at 0.70.
