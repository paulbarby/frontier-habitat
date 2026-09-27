# Critic round 17 — v4.0 `room_identity` pilot

Date: 2026-09-27 · Critic (did not build the work) · Rubric: V3_DESIGN §9, V4_DESIGN §2–§3 · Pass ≥ 0.65 ·
Same calibration as rounds 1–16. The full detail is in `round_17.json`.

## Score

| subject | cons. | appeal | style | score | result |
|---|---|---|---|---|---|
| room_identity (pilot: 4 rooms, M, 1.5×) | 0.74 | 0.72 | 0.70 | **0.72** | PASS, provisional |

## The label-free test

| view | v4 pilot | v3 before |
|---|---|---|
| 110 m day | **4 of 4** named at once | 0 of 4 certain |
| 250 m day | **4 of 4** (rooms 35–45 px; badge and silhouette read) | — |
| 250 m night | **3 of 4** (the kitchen is a dark disc; badges are not lit) | — |

Each family is clearly different from the v3 look, and the style still fits the colony.

## Fixes (ART-HAB unless named), most important first

1. **Night.** Make the badge icon emissive (strength 1.5) and give the kitchen vault a grow-light glow.
2. **Badge style.** The black disc with a flat icon reads like a helipad or a UI stamp, and it covers
   half the habitat dome.
   - Reduce the disc to 0.30–0.40 Rw.
   - Make it hull-grey one step darker, not black.
   - Give the icon a thin painted edge.
3. **Lab vs habitat.** Both are domes, and the badge carries the difference.
   - Make the mast twice as thick, with a 1.2 m dish and a beacon.
   - Colour the lab dome stripes science blue.
4. **Density at 1.5×.** Every interior has large empty floor. The kitchen is the worst: one mess table
   and a cook line on about 150 m² of tile. Fill by function:
   - **Kitchen:** 3 tables, a serving line, a pantry wall.
   - **Workshop:** a second bench line and parts racks.
   - **Lab:** a second desk ring and a sample wall.
   - **Habitat:** a lounge corner and lockers between bays.

   Target: no empty patch wider than 2.5 m outside the aisles.
5. **RENDER / ART-HAB:** repeat the test in a real colony (showcase save, corridors, neighbours, day
   and night), not on flat sand.

## Evidence

- `art/interiors/v4_identity_*` and `art/interiors/v4pilot/*`.
- My grids and crops: `art/critic/r17_*.png`.
