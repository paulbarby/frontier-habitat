# Critic round 6 — first in-game round

Date: 2026-09-24 · Critic (did not build the work) · Rubric: V3_DESIGN §9 · Pass ≥ 0.65 · Same
calibration as rounds 1–5. The full lists with owners are in `round_6.json`.

## Scores

| subject | cons. | appeal | style | score | result |
|---|---|---|---|---|---|
| npc_interaction | 0.62 | 0.60 | 0.68 | **0.63** | **FAIL** |
| npc_ingame | 0.74 | 0.70 | 0.76 | **0.73** | PASS |
| doorways (in game) | 0.74 | 0.70 | 0.74 | **0.73** | PASS |

## Evidence

- **RENDER shots** in `art/critic_input/render/`, 20–40, read with `index.md`. These are staged with
  `use fill`.
- **My own shots**: `build/web_render` (23:25) with `showcase_v3_late.fhsave`, simulation running at
  speed 1, no staging.
  - `art/critic/r6/`: 9 rooms by day (overview and zoom 9), 2 junctions, the airlock, 14 followed
    colonists (`r6_agents_grid.png`), a frame strip (`r6_run_grid.png`), and night shots (suits at
    12 and 28 m, habitat 51, cantina).
  - Crops: `r6_crop_bedstand.png`, `r6_crop_airlock_stack.png`.

## BLOCKER for the next in-game rounds (RENDER, ask SIM if needed)

Flat brown terrain slabs show through room floors and cover corridors in `showcase_v3_late`:

| where | shot |
|---|---|
| Around the kitchen, over the corridors | `r6/kitchen_a.png`, `r6/kitchen_z9.png` |
| Over half the floor of habitat 1821 | `r6/hab1821_z9.png` |
| Right half of habitat 51, at night | `r6/night_hab51_z9.png` |
| Another habitat | `r6/ag_15.png` |
| Beside junction 3831 | `r6/junction3831.png` |

The ground under every structure and corridor must be flat on the 810 m map. If this stays,
`interior_*`, `interior_lighting` and `doorways` will fail in the next in-game round.

## FAIL: npc_interaction, 0.63

Staged, the system works: sitting at tables and at the cantina bar, sleeping, kneel repair and crate
carry all read, and the sit and lie strips (22, 23) are smooth. In unstaged play it breaks the
contract's own checks.

Fixes, most important first:
1. **RENDER**: bodies stack into each other.
   - 3–4 colonists stand in one spot in the airlock (`r6_crop_airlock_stack.png`).
   - 2 suits are merged at the crate pile.
   - 2 colonists share one lab desk, and 2 overlap at the kitchen table.

   Give every body its own view-side slot: first the anchors, then `Anchor_Stand_*`, then a ring of
   free points 0.6 m apart. No two bodies may be within 0.45 m.
2. **RENDER**: two colonists at one bed in habitat 51, one kneeling on it and one standing inside the
   neighbouring bed (`r6_crop_bedstand.png`). Never give one bed to two bodies. A colonist who waits
   for a bed waits on an aisle point.
3. **ART-HAB**: the bed stand points in the bays of 2 must be on free floor, ≥ 0.35 m from the
   neighbour bed and bedside unit. Add this to the build check.
4. **RENDER**: a carrier with a medical crate walks through the holo table in the research lab
   (`r6/lab_z9.png`). Carriers inside rooms follow the aisle graph too.
5. **RENDER**: a tilted white panel floats near the holo table in the lab. Find it and fix it.

I saw no suited colonist in a bed or eating.

## npc_ingame, 0.73 PASS

- **Day:** the suits read well.
- **Night:** helmet halos make outside colonists findable at 28 m.
- **Crowds:** the indoor skin tones vary.

Fixes:
1. **RENDER**: remove the body overlap (fix 1 above). It is the main thing that makes crowds look
   broken.
2. **RENDER**: halve the radius and intensity of the close-range lamp ground pool below 15 m zoom.
   In shot 29 it is larger than the colonist.
3. **RENDER**: supply a 30 fps strip of 10 consecutive frames at zoom 6, for walk and for run. I could
   not verify foot slide, because my capture step was about 0.5 s.
4. **ART-NPC / RENDER**: show the round-5 hair colours in game. Shots 20–26 predate them.
5. **RENDER**: `follow` centres on the simulation position, so the colonist is often off screen.
   Centre on the body.

## doorways, 0.73 PASS

- **In game:** the round-2 faults are gone. There are no cyan fragments, the frames fit, and the
  patches close the gap on every room type seen (31–34 and my shots).
- **Not in the evidence:** a junction with 4–6 links (both junctions in this save have 2 links in
  line), the S-room fix, and a door opening for a colonist.

Fixes:
1. **ART-HAB**: deliver the junction rework, with a save or scene that has 4 and 6 links.
2. **ART-HAB**: show the S-room doorway in game.
3. **RENDER**: include one open-close strip.
