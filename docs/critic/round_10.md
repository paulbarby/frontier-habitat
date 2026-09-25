# Critic round 10 — v3.1 pilot: doors, doorway decals, airlock (Blender renders)

Date: 2026-09-25 · Critic (did not build the work) · Rubric: V3_DESIGN §9 and V3_1 §3, §5.1, §8 ·
Pass ≥ 0.65 · Same calibration as rounds 1–9. The full detail with owners is in `round_10.json`.

## Scores

| subject | cons. | appeal | style | score | result |
|---|---|---|---|---|---|
| doors | 0.76 | 0.72 | 0.76 | **0.75** | PASS, provisional |
| doorway_decals | 0.80 | 0.74 | 0.78 | **0.77** | PASS, provisional |
| airlock | 0.76 | 0.74 | 0.78 | **0.76** | PASS, provisional |

All three pass as pilots. None reaches 0.80. The in-game round decides: door motion, decals on every
room type, and the airlock cycle with riders.

## Evidence

- `art/interiors/door31_{closed,half,open}{,_roof,_inside}.png`
- `habitat_m_doorways*.png`
- `airlock_{closed,half,open}{,_roof}.png`
- `airlock.png`, `airlock_anchors.png`, `airlock_links*.png`, `airlock_exterior.png`,
  `airlock_night.png`
- My grids: `art/critic/r10_doors.png`, `r10_airlock.png`, `r10_airlock2.png`, `r10_hab.png`

## Paul's points

| point | result |
|---|---|
| The doors "are half done" | **Answered.** The leaves are full height, opaque and solid. Closed, half and open read as a real sliding door. Nothing is hidden, and the cutaway caps are solid. |
| Decals must not cover doorways | **None found** in the renders. The bands and portholes stop before each housing. Only habitat M and the airlock are split so far. |
| The airlock needs a middle chamber | **Answered.** From above it reads as suit room → grated chamber → porch. The exterior reads as an airlock at game distance: chamber block, hazard stripes, pumps, beacon. |

## Fixes, most important first

**doors (ART-HAB)**
1. **Housing shape.** The housing is a flat 3.4 × 2.56 m slab. Inside it reads as a wardrobe wall;
   outside it is a plate stuck on the dome.
   - Curve its room face to the wall radius and chamfer its corners 8 cm.
   - Let the dome skin run over it, or give it a curved hood.
2. **Status light.** Make it a clear green emissive strip (#5EE07A), with amber and red states for
   RENDER. The pale mint bar now reads as a lamp.
3. **Leaves.** Add a darker kick plate and a chevron strip at the meeting edge, so a closed door reads
   at game distance.

**doorway_decals**
1. **ART-HAB:** end each band 5 cm before the housing with a small end cap, not a raw cut.
2. **RENDER:** run the in-game acceptance test on every room type, after all rooms are split.

**airlock (ART-HAB unless named)**
1. **Cutaway.** The chamber walls and door housings stand at full height (about 2.5 m) and hide the
   suit room and the chamber. Cut them to 1.40 m with solid caps, like every room.
2. **Chamber length.** Lengthen it from 1.6 m to 2.4 m for 2 bodies 0.8 m apart.
3. **Beacon.** Replace the white ball with an amber beacon housing that RENDER drives by phase. Add a
   3-light pressure indicator above the inner door.
4. **Dome step.** Fair the step between the dome and the chamber block.
5. **Porch.** The black bars read as stairs into the ground. Make it a flat grate with a
   hazard-striped lip and bollards.
6. **SIM / RENDER:** keep a 2.5 m clear zone in front of the outer door. Show it in the placement
   ghost, and keep outside paths off it.
7. **Size.** One airlock size only. Record the decision in the contract, or build S/M/L as V3_1 §5.1
   says.
