# Critic round 2 — interior pilot: habitat M, doorway, lighting

Date: 2026-09-24 · Critic (did not build the work) · Rubric: V3_DESIGN §9 · Pass ≥ 0.65 ·
Same calibration as round 1 (0.50 placeholder, 0.65 shippable indie, 0.80 good, 0.90 excellent).

## Scores

| subject | consistency | appeal | style | score | result |
|---|---|---|---|---|---|
| interior_habitat | 0.78 | 0.72 | 0.70 | **0.73** | PASS |
| doorways (Blender only) | 0.72 | 0.66 | 0.74 | **0.71** | PASS, provisional |
| interior_lighting | 0.60 | 0.55 | 0.55 | **0.57** | FAIL, provisional |

## Evidence I looked at

- `art/interiors/`: `habitat_m.png`, `habitat_m_doorways.png`, `habitat_m_doorways_roof.png`,
  `habitat_m_night.png`, `habitat_m_anchors.png`, `habitat_m_detail.png`, `doorway_close.png`,
  `doorway_close_roof.png`, `ingame_habitat_m_day.png`, `ingame_habitat_m_night.png`.
- `assets/models/habitat_m.glb` (material list read from the file: 25 materials; `Wall_05` has 7).
- `docs/progress/ART-HAB.md`, `docs/requests/ART-HAB-to-RENDER.md`.
- My in-game shots, `build/web_sim` (17:04, the newest export, which carries the current
  presentation code), save `showcase_day9`, habitat id 36, room deselected:
  `art/critic/r2_rt_unsel_y120.png`, `r2_rt_unsel_z7_y200.png`, `r2_rt_unsel_z7_y290.png`,
  `r2_rt_unsel_night_y120.png`, `r2_rt_unsel_night_z7.png`; selected: `r2_rt_habitat_day.png`,
  `r2_rt_habitat_night.png`; crops `r2_crop_ingame_day.png`, `r2_crop_ingame_night.png`,
  `r2_crop_door_left.png`, `r2_crop_rt_doorL.png`, `r2_crop_rt_doorR.png`.

Evidence gaps: `build/web_render` was mid-export (no `index.html`), so I used `build/web_sim`. The
coordinator said the doorways are not placed in the game yet; that build does place them, but as
work in progress. I rated the doorway art from the Blender pictures and list the in-game faults for
RENDER.

## The maker's known weaknesses — checked

| claim | verified | note |
|---|---|---|
| Radial layout, beds differ only by blanket colour | yes | Reads as a dial from the game camera. Fix 1–2. |
| Cabinet ring is dense | yes | A near-solid band of wardrobes and shelves. Fix 5. |
| Doorway 0.8 m from the back of a headboard | yes | `habitat_m_doorways.png`, left door. Doorway fix 1. |
| 32 flat wall faces show seams close up | yes, minor | Visible on the outer wall and the inner face. Fix 8. |
| Room dark at night in game until RENDER adds lights | yes | Dim navy, not muddy black. Lighting fix 1. |

## interior_habitat — 0.73, PASS

What works. In game close up (`r2_rt_unsel_z7_y200.png`) the room is readable, warm and tidy:
panel floor, cove strips, beds with pillows, drawers and headboard lights, bedside units with warm
lamps, wardrobes, shelves, a desk, planters, a water unit. The furniture is built to the NPC numbers.
The stand-ins in `habitat_m_anchors.png` lie on the beds and sit on the chairs correctly. The palette
and detail density match the v2 buildings and the suit. The housing yellow is on one feature (the
rug ring), as §7.3 asks. 13,844 of 15,000 triangles.

What holds it under 0.80: 8 identical beds on 8 spokes make a clock face. There is much wood and few
frontier cues (no pipes, ribs or vents), so it reads as a hotel room. The wall ring is a solid band.
The near headboards hide the pillows in the cutaway. The table and rug are a small focal point.

Fixes, most important first:
1. **Break the clock face.** 4 bays of 2 beds side by side (sharing one bedside unit), with a 1.2 m
   privacy screen (Frame edge, Cushion fabric panel) between bays. Keep the §3.3 anchor numbers; the
   anchors move with the beds.
2. **Bed variety**: 3 dressings (flat; a turned-down fold at the head that shows a 25 cm white
   sheet; a folded throw at the foot), 1 or 2 pillows, a personal item on half of the bedside units.
   Neighbouring beds are never the same.
3. **Blankets**: a 3–4 cm rolled overhang on the sides and foot, a 1.5 cm bevel.
4. **Frontier cues**: a two-pipe run (5 cm, Metal) above the skirting; 8 wall-top rib stubs
   (Frame, 8 × 8 cm) every 45°; 2 vent grilles. Wardrobes: a Hull/Frame carcass with wood door
   inserts (half the wood area).
5. **Wall ring**: take out 1 item in 3 and show open wall (panel, screen, poster or plant). Lower some
   items to 1.2 m.
6. **Headboards**: 0.96 m → 0.80 m, or a Cushion pad on the top 30 cm with the light strip.
7. **Focal point**: rug radius 1.9 m, a table with an accent edge, a planter or light column at the
   centre.
8. **Facets**: a 3 cm Frame batten at every segment joint.
9. **Materials**: 25 per file against 14 in the contract. The orchestrator decides. RENDER measures
   the draw calls of one room with merged visible segments.

## doorways — 0.71, provisional PASS (Blender compositions only)

What works. The cutaway door reads at once as a door: sliding leaves, hazard stripes on the leaves
and the sill, green status strips on the jambs, a sign. The wall segments hide cleanly in Blender, the
patches close the gap, and the collar caps the corridor tube (`doorway_close.png`,
`habitat_m_doorways.png`). The style is on brief.

Fixes, most important first:
1. **Headboard clearance**: make each headboard its own object `Headboard_<i>`. RENDER hides it, or
   shows a 0.6 m low variant, when a doorway centre is within 1.3 m. Target: ≥ 1.2 m of clear floor in
   front of `Anchor_Room` at every angle.
2. **Jamb clutter**: one clean jamb profile 12 cm deep, one recessed leaf slot, the green strip on
   the inner face only.
3. **Outside collar**: it is a plain white box on the dome. Chamfer 4 cm, add a Frame trim line,
   continue the category stripe round it, add 2 latch blocks, and tuck its top under the dome's lower
   band.
4. **Band break**: continue the category band on `wall_patch` and stop it at the frame. The Trim band
   now reads as a repair.
5. **Small rooms**: the open leaves show up to 7 cm outside the wall at R ≤ 4 m. Shorten the travel or
   add pocket covers.
6. **RENDER, before the final rating** (seen in the work in progress): the cut segments' wall items
   show as cyan hologram fragments at the doorways, and frames overlap at the jambs
   (`r2_crop_rt_doorL.png`, `r2_crop_rt_doorR.png`). The same flat cyan fill is on other wall items
   (`r2_rt_unsel_z7_y200.png`, left shelf) with the room deselected, so it is not only the
   selection highlight.

## interior_lighting — 0.57, provisional FAIL

By day the interior is bright and good. At night the warm-white floor goes navy and the beds sink into
the dark. Only the lamps and the coves glow (`r2_rt_unsel_night_z7.png`). That is readable but cold
and dim, not the "light, bright, spacious" room of §7.3. The Blender night render is the day render
on a dark background, so it is not a target either.

Fixes, most important first:
1. **Night fill** (RENDER): keep the night grade out of the cutaway interior, or add a warm per-room
   floor pool (additive, radius 0.8 R, #FFE8C8) so the floor keeps ≥ 55% of its day brightness.
2. **Real lights** at `Anchor_Light_*` for the 2–4 rooms nearest the focus: ceiling 4,500–5,000 K,
   range 3.5 m. Lamps 3,000–3,300 K with a small warm pool on the bedside unit and the pillow.
3. **Cove spill**: a soft gradient 40 cm up the wall from the cove and 25 cm across the floor from the
   skirting strip, so the walls glow and not only the strip.
4. **Target render** (ART-HAB): re-render `habitat_m_night.png` with dim ambient, warm lamp pools, the
   4 ceiling lights and glowing coves. RENDER matches it.
5. Keep `Screen` at 0.45 and `LightStrip` out of the night emissive boost, as ART-HAB proposes.

## What must be true for the full interiors delivery to pass

1. Every room family of §9 at every size, built with the same kit, palette and detail density as
   habitat M after these fixes. Blender renders `art/interiors/<id>_<size>.png` and in-game cutaway
   shots by day and by night.
2. Doorways in game: rooms with 1, 2, 3 and 4 corridors at odd angles, by day and by night, close up
   and at the game camera. No fragments, no z-fighting. The doors slide when a colonist is within 2 m.
   ≥ 1.2 m of clear floor inside every doorway.
3. Interior lighting in game: bright warm-white floors by day and by night, real lights near the
   focus, fake pools elsewhere, inside the §0.2 budget (fps and draw calls reported).
4. The material-count conflict (25 against 14) is resolved, and the draw-call cost of 32 wall
   segments is measured.

## Seen in passing (npc_interaction, later round)

Colonists stand on beds, and two overlap (`r2_rt_unsel_z7_y290.png` right,
`r2_rt_unsel_z7_y200.png` top).
