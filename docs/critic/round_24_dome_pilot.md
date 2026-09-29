# Critic round 24 — v5.0 `super_dome` pilot (provisional, Blender only)

Date: 2026-09-29 · Critic (did not build the work) · Rubric: `docs/critic/v5_rubrics.md` §3.9 ·
Pass ≥ 0.65. The full detail is in `round_24_dome_pilot.json`.

## Score

| subject | cons. | appeal | style | score | result |
|---|---|---|---|---|---|
| super_dome (pilot) | 0.74 | 0.62 | 0.68 | **0.68** | PASS, provisional |

## Evidence

- `art/dome/pilot_overview_day.png`, `pilot_overview_night.png` (no bloom), `pilot_atrium_pool.png`,
  `pilot_gallery_L1.png`, `pilot_cutaway_L1.png`.
- `assets/models/dome_manifest.json` and `art/dome/dome_report.json`.
- The maker's log: `docs/progress/ART-B.md` (v5).
- My crops: `art/critic/r24_signs.png`, `r24_night_ring.png`.

**Gap:** no 250 m view and no in-game shot. The people are v3 placeholders and were not judged.

## What works

- **Geometry.** The contract geometry reads: a geodesic dome over a 5-storey ring, an open atrium,
  12 gates, the promenade, 4 glass lifts.
- **L1 plan.** It is clear from above: 12 venues with distinct interiors and signed glass fronts.
- **The atrium** is the best image: pool, slide, loungers, fountain plaza, park strip, event stage,
  concentric paving.
- **The gallery** at person height has depth: colonnade, down-lights, glass balustrades, a glass lift.
- **Size.** 76 k triangles, 1.83 MB (the allowance is +4 MB).

## Gap to Paul's aim, "a glittering city under glass"

| view | now | estimate |
|---|---|---|
| **Night overview** | The outer face is a dark navy wall with a grid of identical flat beige windows, so it reads as an office block in a cage. No neon, signs or pool glow show from outside; the glass is dark grey with white node dots. Bloom is missing, but bloom alone will not fix uniform, dim lights. | about 0.60 (0.80 = glitters) |
| **Day overview** | The dense white frame reads as a cage. The glass has no reflection, so the dome reads as wireframe. | — |
| **Inside** | The atrium starts to feel like a resort. The gallery feels like an empty mall: bare shop floors and no goods in the windows. | about 0.70 |

## Fixes (ART-B unless named), most important first

1. **Night facade.**
   - Vary the window light per unit: 3–4 warm tones and one cool tone, with 20–30% of the windows
     dark.
   - Add light strips on the gallery slab edges.
   - Add signs and neon on the L1–L2 outer face.

   Target: at least 4 light colours visible at 250 m at night.
2. **Frame.** Struts about 60% of their current width, in graphite or brushed metal, not white. Node
   lights smaller and warmer, at every second node only.
3. **Glass (ART-B / RENDER).** A fresnel sky reflection (25–40% at grazing angles) and a faint tint,
   so the dome reads as glass. RENDER checks the glass sorting against the ring.
4. **Signs.** "CREDIT" renders as "CREDTT" (a broken letter I). RESTAURANT, HOTEL and CAFE are cut by
   the lift and the columns. Fix the glyph, and keep each plate clear of columns and lifts.
5. **Pool glow.** A cyan underwater light and warm lamp pools on the plaza, so the atrium is the bright
   heart at night.
6. **Fill the venues by type.** Shelf rows, racks and mannequins, pharmacy shelves, barber chairs, the
   hotel desk and sofas. Put goods in the windows.
7. **Toy props.** Replace the pastel plank benches and lumpy trees with the colony bench and the v4
   greenhouse trees.
8. **Pool water.** Add depth and a tile or lane pattern, not flat light blue.
9. **Next evidence (ART-B).** The 250 m overview by day and night, and one render with bloom or an
   emission pass.
10. **Next evidence (RENDER).** The in-game 250 m night shot with glow, and the draw-call count.
