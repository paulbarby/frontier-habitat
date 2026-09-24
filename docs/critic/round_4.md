# Critic round 4 — every interior family, doorways, lighting target, hazard props

Date: 2026-09-24 · Critic (did not build the work) · Rubric: V3_DESIGN §9 · Pass ≥ 0.65 ·
Same calibration as rounds 1–3. The evidence is Blender renders only; in-game shots come in a later
round. The full fix lists are in `round_4.json`.

## Scores

| subject | cons. | appeal | style | score | result |
|---|---|---|---|---|---|
| interior_habitat | 0.78 | 0.76 | 0.76 | **0.77** | PASS |
| interior_comfort (lounge, cantina) | 0.76 | 0.70 | 0.72 | **0.73** | PASS |
| interior_medical (medical, bio_lab) | 0.76 | 0.70 | 0.74 | **0.73** | PASS |
| interior_food (kitchen, greenhouse, fungus, algae) | 0.74 | 0.68 | 0.72 | **0.71** | PASS |
| interior_industry (7 types) | 0.74 | 0.66 | 0.76 | **0.72** | PASS |
| interior_science (lab, assembler) | 0.74 | 0.66 | 0.72 | **0.71** | PASS |
| interior_life (oxygen, water, atmo) | 0.70 | 0.60 | 0.68 | **0.66** | PASS, just above the line |
| interior_logistics (storehouse, cold) | 0.76 | 0.70 | 0.76 | **0.74** | PASS |
| interior_links (airlock, junction, corridor) | 0.66 | 0.58 | 0.70 | **0.647** | **FAIL** |
| doorways (Blender only) | 0.74 | 0.68 | 0.76 | **0.73** | PASS, provisional |
| interior_lighting (night target) | 0.72 | 0.66 | 0.70 | **0.69** | PASS, provisional |
| hazard_props | 0.70 | 0.64 | 0.68 | **0.67** | PASS |

## Evidence

- All 147 files in `art/interiors/`, read as grids that I built: `art/critic/r4_<type>.png` (S/M/L/XL),
  `r4_ind_m.png`, `r4_ind_xl.png`, `r4_life.png`, `r4_logi.png`, `r4_sci.png`, `r4_links.png`,
  `r4_doors.png`, `r4_doors_roof.png`, `r4_night.png`.
- Hazard props: `tools/blender/previews_ext/{meteor_turret,crater,fragments,meteor_rock}__view.png`
  and `assets/thumbs/research_assembler.png`, collected in `r4_haz.png`.
- Crops: `r4_junction_crop.png`, `r4_cantina_s_roof_crop.png`.
- Maker's log: `docs/progress/ART-HAB.md`, the production section.

Gaps:
- There is no in-game evidence.
- The research assembler exterior exists only as a small blurred thumbnail.
- I did not measure the door clearance myself; the 0.83–0.98 m value is the maker's.

## Round-2 fixes

| fix | result |
|---|---|
| Bed bays with privacy screens | **Landed.** Bays of 2 in M/L/XL, cabin beds round a table in S, a central pod in XL. The screens read as signboards on legs. |
| Bedding variety | **Landed** as colour and bedding style. Shape variety is small at the game camera. |
| Less wood | **Landed.** |
| Cabinet ring broken up | **Landed.** |
| Doorway jamb, header and band | **Landed.** |
| A layout language for each family | **Landed.** Each family reads at a glance. |

## The maker's list: checked

| claim | verified |
|---|---|
| Junction pockets overlap at 4–6 links | **True, and severe.** This is the reason `interior_links` fails. |
| S rooms: parts show outside the dome | **True.** The header also sticks out like a shelf. |
| Door clearance 0.83–0.98 m | **Not measured.** It agrees with `doorway_close_inside.png`. |
| Trays in the walking ring; fungus crops overlap the racks | **True.** |
| XL industry, life and storage rooms look empty | **True** for industry and life support (the atmo processor is worst). Storage is acceptable. |
| Assembler glass reads grey | **True.** |
| Crater rim and ray radius do not match | **True.** The dashed orange ring is the bigger problem. |

## FAIL: interior_links, 0.647

The airlock and the corridor are good, and the junction with no links is good. With 4–6 links, the
doorway pocket housings in the junction overlap into a jagged pile of plates
(`r4_junction_crop.png`). A junction exists to join many corridors, so this is its normal case.

Fixes, most important first:
1. Give the junction its own door kit. Use a narrower frame with no side pockets (a door that slides
   up, or an open arch), or a polygonal junction wall with one flat facet for each link slot.
2. Test 3, 4, 5 and 6 links at the smallest spacing the simulation allows.
3. Keep the airlock and corridor as they are.

## Top fixes for the passes (all are under 0.80)

1. **interior_life / interior_industry, rooms empty at L and XL.** The main machine must grow with the
   room size. XL rooms now fill space with a repeated grey cube machine. Give the atmo processor a
   central column and pipe runs. Group the water recycler tanks on a plinth with thick pipes. Add cable
   trays and pipe runs to the wall in the industry rooms.
2. **Fungus farm** (the weakest room). Visible mushroom clusters, violet shelf light, a lighter floor,
   the tray overlap fixed.
3. **Algae bioreactor.** The chevron-striped columns look like barber poles. Use clear tubes with a
   glowing fluid, set in rows on manifolds.
4. **Cantina.** Bring the neon inside (bar front, back bar), warm pools over the tables, and a floor
   zone or booths to fill the empty grid.
5. **Hazard props.**
   - Crater: remove the dashed orange ring, which reads as a helipad. Use broad soft ejecta instead
     of star spikes, and fix the rim and ray radius.
   - Meteor rock: put the glow in cracks inside the silhouette, not in loose triangles.
   - Research assembler exterior: supply a beauty render and a clean-room silhouette.
6. **Doorways.**
   - S rooms: nothing may stand more than 1 cm proud of the dome skin.
   - Door clearance target 1.2 m: move low furniture too, or block those link angles.
7. **Science.**
   - The research lab at S and M needs more stations.
   - The assembler partitions need clear, tinted glass.
8. **Lighting target.**
   - Add distinct warm pools and 25% edge fall-off.
   - Add each family's accent light (neon, grow light, holo glow, hazard amber).
9. **Habitat.**
   - The screens become fabric panels on a rail, not the blanket terracotta.
   - Break the 4-fold pinwheel of the M room.
   - Make the beds differ in shape, not only colour.
10. **Medical and bio-lab.** Put equipment on the bio-lab benches and fill the empty half of medical L
    and XL.
