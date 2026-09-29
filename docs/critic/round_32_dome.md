# Critic round 32 — `super_dome` after the round-28 fixes (Blender, provisional)

Date: 2026-09-29 · Critic (did not build the work) · Rubric: `docs/critic/v5_rubrics.md` §3.9 · Pass ≥ 0.65.
The full detail is in `round_32_dome.json`.

## Score

| subject | cons. | appeal | style | score | round 28 | result |
|---|---|---|---|---|---|---|
| super_dome | 0.82 | 0.76 | 0.78 | **0.79** | 0.76 | PASS, provisional |

## Round-28 fixes

| # | fix | result |
|---|---|---|
| 1 | Sign font | **Landed.** All 48 strings on the test sheet are correct, and BARBER and BOOKS read in the game views. ART-B's cause (a missing B, a small P) matches. One placement fault: from the atrium, RESTAURANT reads "R STAURANT" because a lift frame crosses the E. |
| 2 | Hotel rooms | **Landed.** Headboard bed, lamps, chairs, TV, desk, wardrobe, art, rug, curtains, bath door. Still plain: untextured boxes, and an empty middle floor. |
| 3 | Club | **Landed.** A light truss with spots, a raised stage, a booth and high tables, a panelled back wall. No bouncer or ADULTS ONLY sign in view. |
| 4 | Arcade | **Landed.** More cabinets, a PRIZES counter, a sit-down Prism Shift racer with a seat, neon floor arrows. |
| 5 | Upper floors | **Partly.** Bright windows break the grid at night. No balconies. |
| 6 | Cafe | **Landed.** Cakes, three menu boards, an A-frame sign. |
| 7 | Day glass fresnel | **Open.** |
| 8 | In-game evidence | **Open** (RENDER). |
| 9 | Robot dancers | **Open** (ART-NPC). |

**Tone check:** PASS for the set. Still owed: the bouncer and the sign at the door in view, and the
robot dancers.

## Gap to "a glittering city under glass"

| view | estimate (0.80 = glitters) |
|---|---|
| Night, 250 m | about 0.78. It needs balcony sparkle and the city reflected in the glass. |
| Day, 250 m | about 0.72. It needs a fresnel sky reflection. |
| Inside | about 0.79. The atrium, cafe, club and arcade feel like a resort mall; the hotel room is the plain part. |

## Fixes

1. **ART-B:** move the RESTAURANT plate or the lift frame.
2. **ART-B:** a club door with a bouncer post, a rope line and the ADULTS ONLY sign, in one render.
3. **ART-B: hotel room.** A textured quilt and pillows, a patterned rug, a small lounge set in the
   empty centre, and a warm lamp pool at night.
4. **ART-B:** balconies or planters with lights on every third upper unit.
5. **ART-B / RENDER:** a day-glass fresnel reflection.
6. **RENDER:** in-game evidence (250 m night with glow, draw calls, follow fps in the dome, the Prism
   Shift shader).
7. **ART-NPC:** the robot dancers, after the MPFB rebuild.

**Noted:** Paul chose MPFB/MakeHuman for the people, so the people subjects will be rated from zero
on the rebuild.
