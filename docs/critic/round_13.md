# Critic round 13 — final v3.1 round, in game

Date: 2026-09-25 · Critic (did not build the work) · Rubric: V3_DESIGN §9, V3_1 §8 · Pass ≥ 0.65 ·
Same calibration as rounds 1–12. The full detail and owners are in `round_13.json`.

## Scores

| subject | cons. | appeal | style | score | before | result |
|---|---|---|---|---|---|---|
| doors | 0.78 | 0.74 | 0.78 | **0.77** | 0.79 (Blender) | PASS |
| doorway_decals | 0.82 | 0.78 | 0.80 | **0.80** | 0.79 | PASS |
| airlock | 0.72 | 0.68 | 0.76 | **0.72** | 0.79 (Blender) | PASS |
| npc_paths | 0.78 | 0.74 | 0.76 | **0.76** | new | PASS |
| ships (with the pad, landing, take-off) | 0.80 | 0.78 | 0.80 | **0.79** | 0.78 | PASS |
| visitors | 0.78 | 0.76 | 0.78 | **0.77** | 0.76 | PASS |
| npc_interaction | 0.74 | 0.70 | 0.76 | **0.73** | 0.71 | PASS, not dropped |
| npc_ingame | 0.78 | 0.74 | 0.78 | **0.77** | 0.77 | PASS, not dropped |
| interior_lighting | 0.76 | 0.74 | 0.76 | **0.75** | 0.75 | PASS, not dropped |
| interior_ingame | 0.78 | 0.74 | 0.76 | **0.76** | 0.75 | PASS, not dropped |

**No fails.** The airlock drops from 0.79 (Blender) to 0.72 because of how it reads in game.

## Evidence

- **RENDER:** `art/critic_input/render/80–98`, with `95_path_check_final.json` and
  `96_airlock_check_final.json`.
- **My own:** `build/web_render` (20:29), `showcase_v31.fhsave` unstaged, speed 1 and 4, `debug=1`
  and `ship medical`. The files are in `art/critic/r13/` and `r13_*.png`.

## Paul's complaints

| complaint | result |
|---|---|
| Colonists through walls or habitats | **Answered.** Path check: wall 0, outside intrusion 0, over 499,476 samples. None seen in my shots. |
| Paths clip furniture | **Answered.** 0.083% and 0.122% (target ≤ 0.2%). Most of the rest is at one airlock corridor. |
| Jerky airlock entry and exit | **Motion answered:** no teleports, no suit swap in the chamber, riders never off the path. **Reading not yet:** the selected airlock is covered by cyan slabs, and the tall housings hide the riders. |
| Doors half done | **Answered.** Full leaves, open and closed. The cutaway cap is torn. |
| Decals over doorways | **Answered.** 0 of 176 doorways. |
| No indoor clothes outside | **True.** `wrong_clothes` 0, and none seen. |
| Doors never open on both sides of a pumping chamber | **True.** No timeline row has both doors open, and pressure never changes with a door open. The "pump" label starts before the door has closed. |

## Fixes by owner

**RENDER**
1. **Airlock selection.** A selected airlock draws its chamber block and housings as solid cyan
   slabs. Leave tall parts out of the selection fill.
2. **Selection rings.** Selected rooms show 2–3 stacked cyan rings above the wall. One ring at the
   floor is enough.
3. **Landing dust.** Add a dust ring below 20 m at landing. Show one take-off strip with engine glow
   and the legs folding.
4. **Visitors at night.** Give visitors the helmet lamp halo; the inspector cannot be found at 45 m
   at night.
5. **Door states.** Prove the amber and red door states in a frame.
6. **Path check.** Explain `e_void` 138 (bodies near the lander). Confirm that the hidden jumps are
   > 25 m.

**ART-HAB**
1. **Airlock height.** The chamber walls and housings are still full height in game. The round-12
   fix is still open.
2. **Housing cap.** Give the door housing a clean cap at 1.40 m as its own object.
3. **Airlock 49 corridor.** The corridor at 259.5° opens onto furniture. Move the item.

**SIM**
1. **Pump phase.** Enter `pump` only after both doors are closed.
2. **Porch zone.** Keep crate piles and pods ≥ 2.5 m from an outer door (with RENDER).

**ART-NPC**
1. **Tourists.** Show a standing tourist from the back, to verify the colour on the lower legs.

## Latest score of every subject

| subject | score | round | | subject | score | round |
|---|---|---|---|---|---|---|
| npc_suit | 0.82 | 5 | | interior_links | 0.71 | 7 |
| npc_indoor | 0.72 | 5 | | interior_ingame | 0.76 | 13 |
| npc_animation | 0.78 | 5 | | doorways | 0.79 | 8 |
| npc_interaction | 0.73 | 13 | | interior_lighting | 0.75 | 13 |
| npc_ingame | 0.77 | 13 | | hazard_props | 0.70 | 7 |
| interior_habitat | 0.79 | 7 | | hazard_visuals | 0.70 | 8 |
| interior_comfort | 0.75 | 7 | | doors | 0.77 | 13 |
| interior_medical | 0.75 | 7 | | doorway_decals | 0.80 | 13 |
| interior_food | 0.76 | 7 | | airlock | 0.72 | 13 |
| interior_industry | 0.76 | 7 | | npc_paths | 0.76 | 13 |
| interior_science | 0.73 | 7 | | ships | 0.79 | 13 |
| interior_life | 0.77 | 7 | | landing_pad | 0.75 | 12 |
| interior_logistics | 0.77 | 7 | | visitors | 0.77 | 13 |

All 26 subjects pass. The mean is 0.76. `npc_suit` and `doorway_decals` reach 0.80. The lowest are
`hazard_props` and `hazard_visuals` at 0.70.
