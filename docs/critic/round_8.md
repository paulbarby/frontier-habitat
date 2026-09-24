# Critic round 8 — final in-game round

Date: 2026-09-25 · Critic (did not build the work) · Rubric: V3_DESIGN §9 · Pass ≥ 0.65 · Same
calibration as rounds 1–7. Full fix lists with owners are in `round_8.json`.

## Scores

| subject | cons. | appeal | style | score | before | result |
|---|---|---|---|---|---|---|
| npc_interaction | 0.72 | 0.68 | 0.74 | **0.71** | 0.63 FAIL (r6) | PASS |
| npc_ingame | 0.78 | 0.74 | 0.78 | **0.77** | 0.73 (r6) | PASS |
| doorways (in game) | 0.80 | 0.76 | 0.80 | **0.79** | 0.73 (r6) | PASS |
| interior_lighting (in game) | 0.76 | 0.74 | 0.76 | **0.75** | 0.71 (r7, target) | PASS |
| interior_ingame | 0.78 | 0.72 | 0.76 | **0.75** | new | PASS |
| hazard_visuals | 0.72 | 0.66 | 0.72 | **0.70** | new | PASS |

**No fails.**

**Family at risk alone:** `fungus_farm`, and the greenhouse, in `scene_final` (about 0.63). The grow
beds are empty in that save, so at the game camera the room reads as black frames over brown slabs.
I have no in-game shot with crops.

## Evidence

- **RENDER shots** in `art/critic_input/render/`, read with `index.md`: 13–17, 20–26 (re-shot), and
  41–63.
- **My own unstaged shots** from `build/web_render` (`index.pck` 03:56), in `art/critic/r8/`:
  - `scene_final.fhsave`, loaded with `__fhr.cmd('loadurl scene_final.fhsave')`: 8 rooms by day and 3
    by night (`r8_rooms_grid.png`).
  - `showcase_v3_late.fhsave` with the simulation running: 5 rooms (`r8_v3_grid.png`).
  - `showcase_v3_late.fhsave` with `debug=1`: meteor, quake, wind storm, dust devil and flare
    (`r8_hz_grid.png`).

  This save runs a dust storm, which washes my hazard shots. RENDER's 13–17 are in clear weather.

## Checks asked

| check | result |
|---|---|
| Lab holo table / white panel | The white panel was not seen. The holo cone renders as an **opaque white lampshade**, so interior `Glass` is drawn opaque. |
| No suited colonist in a bed or eating | **None seen** in any shot. |
| Spacing between bodies | **Held** in rooms. **Fails** in the `scene_final` airlock: about 25 bodies packed, some standing past the wall line (`r8_airlock_crop.png`). |
| Carriers through furniture | **None seen.** One colonist clips a door jamb (`r8_kitchen_door.png`). |
| Terrain through floors | **Fixed.** None seen. |

## Verified in game

- **Sequences:** the sit, lie and kneel strips keep the body visible through every blend (50–52).
- **Movement:** run at 3.4 m/s with planted feet and the crate held (42); walk (41).
- **Night read:** helmet halos (54, 55); the lamp pool is halved close up (45).
- **Crowd variety:** skin tones and hair shapes vary (44).
- **Doorways:** the junction kit is clean with 4 links at 60° and 3 links at 56° (56). The S-room
  hoods meet the dome cleanly (57). The doors open and close for colonists (43).
- **Night interiors:** bright, with the family accents visible (60–62).
- **Meteor:** ring, streak, fireball, shockwave, crater with air jets (13–16).
- **Quake:** cracks (17).
- **Turret:** intercept tracer and air burst (63).

## Top fixes

1. **RENDER, airlock crowd.** Queue the extra bodies in the corridor on points 0.8 m apart, or let
   them wait outside in suits. No body may stand past the wall.
2. **RENDER / ART-HAB, interior Glass.** Draw it transparent (alpha 0.25–0.35, cyan tint, emissive
   edge). The holo cone and the assembler glass depend on it.
3. **RENDER, hazards in weather.**
   - Draw the meteor ring and the quake cracks without fog.
   - Give the wind storm its own dust sheets and turbine spin-up.
   - Show the flare aurora as a sky tint that the top-down camera sees.
   - Add a larger intercept burst and a muzzle flash.
4. **RENDER, fungus farm and greenhouse.** Supply an in-game shot of both with crops at mid growth.
5. **RENDER, night.** The outer lower wall band glows as a solid white ring. Halve it or make it a thin
   line. Add a warm pool over the kitchen cook line.
6. **RENDER, doorway.** Walk bodies through the door on its centre line (the jamb clip).
7. **ART-NPC / RENDER, hair colour.** Make the 4 hair colours clearly distinct (auburn, dark blonde)
   so a crowd shows them.
8. **ART-HAB, lounge.** Lighten the rug and the sofa island so the seating reads at the game camera.

## Final summary — latest score of every subject

| subject | score | round | result |
|---|---|---|---|
| npc_suit | 0.82 | 5 | PASS |
| npc_indoor | 0.72 | 5 | PASS |
| npc_animation | 0.78 | 5 | PASS |
| npc_interaction | 0.71 | 8 | PASS |
| npc_ingame | 0.77 | 8 | PASS |
| interior_habitat | 0.79 | 7 | PASS |
| interior_comfort | 0.75 | 7 | PASS |
| interior_medical | 0.75 | 7 | PASS |
| interior_food | 0.76 | 7 | PASS |
| interior_industry | 0.76 | 7 | PASS |
| interior_science | 0.73 | 7 | PASS |
| interior_life | 0.77 | 7 | PASS |
| interior_logistics | 0.77 | 7 | PASS |
| interior_links | 0.71 | 7 | PASS |
| interior_ingame | 0.75 | 8 | PASS |
| doorways | 0.79 | 8 | PASS |
| interior_lighting | 0.75 | 8 | PASS |
| hazard_props | 0.70 | 7 | PASS |
| hazard_visuals | 0.70 | 8 | PASS |

All 19 subjects pass. The mean is 0.75. Only `npc_suit` reaches 0.80 ("good"). The rest are
shippable indie quality, between 0.70 and 0.79.
