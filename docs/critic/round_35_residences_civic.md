# Critic round 35 — `residences` and `civic_modules` after the round-33 fixes

Date: 2026-09-30 · Critic · Rubric: `docs/critic/v5_rubrics.md` §3.7, §3.8 · Pass ≥ 0.65. Blender and
game-camera identity shots; provisional. The full detail is in `round_35_residences_civic.json`.

## Scores

| subject | cons. | appeal | style | score | round 33 | result |
|---|---|---|---|---|---|---|
| civic_modules | 0.72 | 0.70 | 0.74 | **0.72** | 0.65 | PASS, provisional |
| residences | 0.80 | 0.76 | 0.80 | **0.79** | 0.77 | PASS, provisional |

**Evidence gap:** jail L (and its exterior), park L and retail L were not re-rendered; they predate
the fixes.

## civic_modules

**Identity without labels.**

| view | result | round 33 |
|---|---|---|
| 110 m day | **5 of 5** | 3 of 5 |
| 250 m day | **5 of 5.** Canopy stripes, schoolhouse roof, mast, four towers, glass dome. | 2 of 5 |
| 250 m night | **4 of 5.** Retail goes dark. | 2 of 5 |

**Security vs jail.** They are now distinct by silhouette (mast vs four towers) and badge (shield vs
lock). The colour is still off the contract:
- security reads orange-red;
- the jail band is yellow-amber, which is the housing accent.

V5 wants security black and red, and the jail prison orange.

**Round-33 fixes.**

| # | fix | result |
|---|---|---|
| 1 | Own badges | **Landed.** |
| 2 | Silhouettes | **Landed.** Jail L was not re-rendered. |
| 3 | Retail canopy and billboard | **Landed.** No shop-front signs on the wall. |
| 4 | Empty floors | **Partly.** Security is fuller. Retail M and academy M look unchanged (40–50% empty). |
| 5 | Security command post | **Landed.** A monitor wall over a ringed desk, a holding cell, lockers. |
| 6 | Night | **Landed.** |

**Fixes (ART-HAB).**
1. **Colours.** Security black and red (band #1B1F24, shield #D93A3A). Jail prison orange (#FF7A1A).
2. **Re-render** jail L, park L and retail L with the new kit.
3. **Fill retail M and academy M.**
   - **Retail:** shelf rows, a fitting room, a till queue.
   - **Academy:** a second class, a library corner, a lab bench.
4. **Retail at night.** Light the canopy stripes and the billboard.

## residences

**Round-33 fixes.**

| # | fix | result |
|---|---|---|
| 1 | Balconies on floor 1 | **Landed.** |
| 2 | Block exterior | **Landed.** Striped balconies, a penthouse terrace with umbrellas and pools, lit units at night. |
| 3 | Executive furniture set | **Not visible.** The Executive L render looks the same as round 33. |
| 4 | Night fill | **Partly.** The tube rooms away from the lamps are still dim. |
| 5 | In-game evidence | **Open.** |

**Fixes.**
1. **ART-HAB:** show, or build, the executive set.
2. **ART-HAB:** a soft ceiling fill for the tube rooms at night.
3. **RENDER / ART-HAB:** the in-game cutaway, the floor selector, and the follow view in a unit and a
   penthouse.
