# Critic round 7 — interiors after the round-4 rework (Blender renders)

Date: 2026-09-25 · Critic (did not build the work) · Rubric: V3_DESIGN §9 · Pass ≥ 0.65 · Same
calibration as rounds 1–6. Full fix lists are in `round_7.json`.

## Scores

| subject | cons. | appeal | style | score | round 4 | result |
|---|---|---|---|---|---|---|
| interior_habitat | 0.80 | 0.78 | 0.80 | **0.79** | 0.77 | PASS |
| interior_comfort | 0.76 | 0.74 | 0.76 | **0.75** | 0.73 | PASS |
| interior_medical | 0.76 | 0.72 | 0.76 | **0.75** | 0.73 | PASS |
| interior_food | 0.78 | 0.74 | 0.76 | **0.76** | 0.71 | PASS |
| interior_industry | 0.78 | 0.72 | 0.78 | **0.76** | 0.72 | PASS |
| interior_science | 0.76 | 0.68 | 0.74 | **0.73** | 0.71 | PASS |
| interior_life | 0.78 | 0.74 | 0.78 | **0.77** | 0.66 | PASS |
| interior_logistics | 0.78 | 0.74 | 0.78 | **0.77** | 0.74 | PASS |
| interior_links | 0.72 | 0.66 | 0.74 | **0.71** | 0.647 FAIL | PASS |
| doorways (Blender) | 0.78 | 0.74 | 0.78 | **0.77** | 0.73 | PASS, provisional |
| interior_lighting (target) | 0.72 | 0.68 | 0.72 | **0.71** | 0.69 | PASS, provisional |
| hazard_props | 0.72 | 0.66 | 0.72 | **0.70** | 0.67 | PASS |

**No fails.** Nothing reaches 0.80.

## Evidence

- `art/interiors/`: 172 files.
- My grids in `art/critic/`: `r7_junction.png`, `r7_habitat.png`, `r7_comfort.png`,
  `r7_medical.png`, `r7_food.png`, `r7_ind_l.png`, `r7_ind_xl.png`, `r7_life.png`,
  `r7_sci_logi.png`, `r7_doors.png`, `r7_night.png`, `r7_haz.png`.
- The maker's log: `docs/progress/ART-HAB.md`, 2026-09-25 section.

## The maker's changes, checked against the images

| change | result |
|---|---|
| Junction door kit, tested with 3–6 links | **True.** The hub is clean. The pocket housings are gone. |
| Industry machines scale, stock, trenches | **True.** Mine, refinery and glassworks have no second unit. |
| Life-support centres (atmo column, water plinth, oxygen plinth) | **True.** This is the largest gain in the round. |
| Fungus caps and violet canopy; clear algae tubes | **True.** |
| Cantina neon, back bar, booths | **Partly.** The grey band under the booth reads as a stain. |
| Crater, meteor rock, assembler exterior | **True.** New faults are listed below. |
| Door hood | **True.** The header box is gone. |
| Night accent lights | **Present, but faint.** |
| Habitat curtains, bed shapes, reading corner | Curtains and bed shapes: **true.** The reading corner does not read. |
| Bio-lab bench equipment; research lab S/M desks | **Present**, but too small or too few to read. |

## Known open points, checked

1. **Tubes at 28° overlap outside the hub: true.** Two 2.36 m tubes at angle t stop overlapping at
   2.36 / sin(t) from the centre:

   | angle | distance |
   |---|---|
   | 28° | 5.0 m |
   | 45° | 3.3 m |
   | 60° | 2.7 m |

   **SIM:** set a minimum of 55° between links at a junction, or use a hub radius that meets that
   distance.
2. **The hood stands out on small domes: true.** It reads as a tube joint and is acceptable.
3. **S/M rooms cannot give 1.2 m at every door angle: true.** The build tool must refuse a blocked
   angle, or the room must hide the furniture there. Show this in game.
4. **L/XL rooms look emptier near the wall: true** for industry XL and atmo XL.

## Top fixes (all subjects are under 0.80)

1. **SIM**: a junction link spacing ≥ 55°, as above.
2. **ART-HAB, science**: research lab S/M still read empty. Add a sample-rack section, a screen wall
   and a specimen case. Make the assembler glass tint visible.
3. **ART-HAB, hazard_props**:
   - Crater: add a rim with a lighter edge and a darker bowl, and fade the ejecta ends; it reads as a
     flat brown splat.
   - Meteor rock: hot orange crack glow.
   - Assembler roof: use Glass, not opaque white panes.
4. **ART-HAB / RENDER, lighting**: double the family accent strength and give each a floor spill. Add
   25% more fall-off at the wall ring.
5. **ART-HAB, comfort**:
   - The cantina booth floor band reads as a stain.
   - Fill the empty tile in cantina M–XL.
   - Give lounge S/M the armchair pair.
6. **ART-HAB, industry XL and atmo XL**: stock zones or auxiliary units on the empty ring.
7. **ART-HAB, bio-lab**: bench equipment 30% larger, a sample fridge and a glove box.
8. **ART-HAB, habitat M**: break the four-way symmetry, and make the reading corner visible.
