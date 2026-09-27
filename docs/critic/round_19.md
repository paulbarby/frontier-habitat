# Critic round 19 — v4.0 `vehicles`, full set (Blender renders)

Date: 2026-09-27 · Critic (did not build the work) · Rubric: V3_DESIGN §9, V4_DESIGN §5 · Pass ≥ 0.65 ·
Same calibration as rounds 1–18. The full detail is in `round_19.json`.

## Score

| subject | cons. | appeal | style | score | before | result |
|---|---|---|---|---|---|---|
| vehicles (5 models) | 0.74 | 0.72 | 0.72 | **0.73** | 0.71 | PASS, provisional |

| model | alone | note |
|---|---|---|
| rover_small | 0.77 | All 5 round-16 fixes landed. It now reads as a work vehicle, not a toy. |
| rover_medium | 0.72 | The role reads. The bullet-train nose and the loud purple band hold it down. |
| hopper | 0.68 | Lander-like, but a smooth white egg. It is the weakest. |
| satellite | 0.72 | Clear and simple. It is only shown on a flat background. |
| launch_pad | 0.74 | Reads at once. The scale is right. |

**No model is below 0.65.**

## Round-16 fixes (small rover)

All five landed:
1. graphite fenders with an orange lip;
2. fenders tucked 7 cm over the tyre, a skid plate, and a body 10 cm lower;
3. lugged dark tyres with bolted rims;
4. the bed lamp halved, with amber corner markers;
5. a tilted roof with a frame edge.

## What works

- **One family.** A shared wheel kit, the codes RV-01, MR-02, HP-03 and LP-01, hazard stripes,
  off-white and graphite bodies, the colony orange.
- **Roles read at game distance.**
- **Scale** next to colonists is right.
- **Night.** One consistent pattern: white front, red rear, amber markers.

## Fixes (ART-B), most important first

1. **Medium rover nose.** Use a faceted, framed cab with dark glass by day, as on the trader. Add a
   bumper with a winch.
2. **Medium rover colour.** Narrow the purple band to 20–25 cm and desaturate it. Add the orange
   fender lip, so both rovers read as one fleet.
3. **Hopper.**
   - Facet the egg into 8–10 panels with seams and plates.
   - Add a hard belly ring and a framed canopy.
   - Fair the vestibule in with a collar.
   - Give the thrusters bells like the ships'.
4. **Night.** Medium rover portholes in warm #FFD9A0 at 50%, not flat yellow.
5. **Satellite.** Add one render in context (over the planet, or on the rocket).

## Evidence

- `art/vehicles/*`.
- My grids: `art/critic/r19_night.png`, `r19_misc.png`.
