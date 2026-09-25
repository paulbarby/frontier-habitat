# Critic round 14 — airlock and doors after the round-13 fixes

Date: 2026-09-25 · Critic (did not build the work) · Pass ≥ 0.65 · Same calibration as rounds 1–13.
The full detail is in `round_14.json`.

## Scores

| subject | cons. | appeal | style | score | before | result |
|---|---|---|---|---|---|---|
| airlock | 0.80 | 0.76 | 0.78 | **0.78** | 0.72 | PASS |
| doors | 0.80 | 0.78 | 0.80 | **0.79** | 0.77 | PASS |
| ships (update) | — | — | — | **0.80** | 0.79 | PASS |
| visitors (update) | — | — | — | **0.78** | 0.77 | PASS |

## Evidence

- **RENDER:** `art/critic_input/render/99–106`.
- **My own:** `build/web_render` (22:16). Airlock 49 in `showcase_v31` and `showcase_v3_late`,
  selected and not selected, with `tallparts 49`. The files are in `art/critic/r14/` and
  `r14_grid.png`.

## Verified

- **Cutaway height.** `tallparts 49` answers "open 1.00 |", so no part is drawn above 1.45 m, in both
  saves, selected or not. The riders in the chamber are visible from every angle.
- **Selection.** One floor ring, no cyan slabs.
- **Door caps.** Clean at 1.40 m.
- **Door states.** Green, amber, open and red are all shown (102).
- **Ships.** A dust ring below 20 m (100). Take-off with engine glow and the legs folding (101).
- **Inspector at night.** Findable at 45 m through the halo (103).
- **Tourists.** The lower-leg colours show from behind (104).

## Claim not borne out

**"Pump starts only after the door is shut."**
- SIM's code says so (`sim/agents.gd:301–303`).
- RENDER's check file 106 (22:24, on the 22:16 build) still shows a door fully open at the start of
  11 of 13 pump rows. Example: `f140 airlock 49 pump out | inner 1.00 outer 0.00 p 1.00`.
- The pressure still never changes with a door open.
- Either the view's door lags the sim phase, or the build predates SIM's change.

**SIM / RENDER:** settle which, and re-run the check. The target is 0 pump rows with a door open.

## Remaining fixes

1. **SIM / RENDER:** the view door follows the sim phase, as above.
2. **SIM / RENDER:** crate piles still sit on the porch edge of airlock 49. Keep them ≥ 2.5 m from the
   outer door.
3. **ART-HAB:** the cut caps read as large flat dark lids. Use the Frame colour with a 3 cm light edge.
4. **RENDER:** two tourists pass through a doorway interpenetrating each other (104). Keep 0.45 m
   between bodies in doorways too.
5. **RENDER:** `e_void` 152 in the path check is still unexplained.
