# Critic round 9 — v3.1 ships pilot: `ship_trader`

Date: 2026-09-25 · Critic (did not build the work) · Rubric: V3_DESIGN §9 and V3_1 §6.2 / §8 ·
Pass ≥ 0.65 · Same calibration as rounds 1–8. The full detail is in `round_9.json`.

## Score

| subject | cons. | appeal | style | score | result |
|---|---|---|---|---|---|
| ships (pilot: trader only) | 0.72 | 0.74 | 0.72 | **0.73** | PASS, provisional |

## Evidence

- `art/ships/`: `trader_turnaround.png`, `trader_on_pad.png`, `trader_on_pad_rear.png`,
  `trader_flight.png`, `trader_night.png`, `ship_report.json`.
- The maker's log: `docs/progress/ART-B.md`, v3.1 section.
- Style reference: `art/screenshots/15_meridian.png`, `art/key_art.png`, `art/models/_review_*.png`.
- My own: `art/critic/r9_gamedist.png`, the pad image at 12% scale, to judge the game-distance read.

**Gap:** there is no in-game shot (landing, leg and ramp motion, night).

## What works

- **Game distance:** it reads as a cargo freighter. The 4 orange pods and the crane give a clear
  "working ship" silhouette.
- **Palette:** off-white, graphite and one orange accent, which fits the colony.
- **Contract:** radius 7.44 m, height 6.0 m, 8,160 triangles, 6 materials, all named nodes present.
- **Flight pose:** clean. The legs fold, and the ramp and hatch close.

## Fixes (ART-B), most important first

1. **Nose and windows.** The rounded "bullet train" nose with flat pale-yellow panes reads as a toy
   bus, not as a Meridian sibling.
   - Make the cockpit a faceted, chamfered block with Frame mullions.
   - Windows are dark glass by day, warm emissive only at night.
2. **Hull language.** The smooth pill hull lacks the Meridian's detail. Add:
   - 2 hazard-stripe bands, at the ramp and at the hatch;
   - flank panel insets;
   - spine handrails and ladders;
   - a registration decal on each flank (for example "TR-07").
3. **Legs.** They are thin for the mass. Make the upper strut 40% thicker, and add a hydraulic ram and
   a 0.9 m foot pad.
4. **Engines.** The nozzles are empty black rings. Add a bell with an inner cone, a bronze rim, and
   Plasma on the cone for the flight glow.
5. **Night.** The ship has no running lights of its own. Add:
   - red and green nav lights on the pod ends;
   - a strobe on the crane mast;
   - 2 belly floods on the ramp;
   - lit cockpit windows.
6. **Cargo.** The cylinders alone read as fuel tanks. Add 1–2 ribbed, stencilled containers on the
   spine by the crane.
7. **Ramp.** The ramp sits under the two engine bells. Move it to one side of the tail, or raise the
   engines 0.5 m.
8. **File names.** `trader_on_pad.png` shows the tail and `trader_on_pad_rear.png` shows the nose.
   Swap the names.

## Pad (note only, ART-HAB, not scored)

- It reads as a plain helipad. That is acceptable as a base.
- In `trader_on_pad_rear.png` the kiosk stands about 1 m in front of the nose. Put it ≥ 2.5 m outside
  the ship footprint and the ramp lane (`Anchor_Ship`).
- Upgrade per §6.2:
  - amber or white edge lights, not pink;
  - a blast deflector;
  - a fuel line with a coupling at the ship's side;
  - the purple accent used once only.
- Keep ≥ 1 m of free deck round the largest ship for carriers.

## Keeping the six ships distinct

| ship | plan from the top | silhouette cue | dominant colour |
|---|---|---|---|
| trader | long, low, the widest | pods on the flanks, crane on the spine (done) | orange |
| shuttle | shorter and taller | continuous window row on both flanks, side airstairs, no pods | graphite + white |
| liner | the longest, a dart | swept nose, tail fins, panoramic windows, full-length colour band | comfort pink or a liner colour |
| medical | compact | large red cross on the roof (top-down read) and flanks, wide stretcher door | white + red |
| science | medium, the one tall ship | sensor dish on a mast, antenna array, belly instrument pods | science blue #7C8CFF |
| courier | the smallest (plan radius ~4 m), a wedge | one engine | black + gold |

All six share one design language:
- the same panel language, hazard stripes, legs and window treatment, so they read as one fleet;
- a different plan shape and one dominant colour each, so they differ at game distance.

**Land fixes 1–5 before the other five ships are built**, because they set the shared language.
