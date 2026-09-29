# Critic round 28 — `super_dome` full build (Blender only, provisional)

Date: 2026-09-29 · Critic (did not build the work) · Rubric: `docs/critic/v5_rubrics.md` §3.9 and the
§0 tone rule · Pass ≥ 0.65. The full detail is in `round_28_dome_full.json`.

## Score

| subject | cons. | appeal | style | score | round 26 | result |
|---|---|---|---|---|---|---|
| super_dome | 0.80 | 0.72 | 0.76 | **0.76** | 0.74 | PASS, provisional |

## Tone check (§0) — the Club

**PASS for the set.**
- Dance floor with light tiles, three podiums with chrome poles, mirror ball, lit bar, lounge booths.
- No human dancers, no sexual imagery.

**Still owed:**
- The robot dancers (ART-NPC) are not in the evidence, so they are not checked yet.
- No bouncer or "ADULTS ONLY" sign is visible at the door. V5 §8 and §0 need them.

## Round-26 fixes

| # | fix | result |
|---|---|---|
| 1 | Break the upper grid, neon round the ring | **Partly.** Varied window widths and colours, and neon bands in 4 colours round L1–L2. No balconies or planters, so the upper floors still read as a grid. |
| 2 | Night glass | **Landed.** A warm shell glow and a lit edge ring. |
| 3 | Day glass reflection | **Partly.** A faint tint, no visible fresnel. |
| 4 | Signs | **Not landed, and the cause is the font, not the columns.** There is no letter B and the P is broken: "BARBER" renders as "AR ER", "BOOKS" as "OOKS", "PRISM SHIFT" as "FRISM SHIFT" (`art/critic/r28_signs_crop.png`). |
| 5 | Venue goods | **Partly.** L2 shelves carry coloured goods; the L1 cafe still shows boxes. |
| 6 | Pool | **Landed.** Lane lines. |
| 7 | In-game evidence | **Not yet** (RENDER). |

## Venues and levels

| part | result |
|---|---|
| Atrium at night | **The best image.** Escalators, neon on two levels, the lane pool, palms, warm lamps. It reads as a mall and a resort. |
| L2 from above | **Good.** Food court, gym, shops, the game zone with cabinets and VR rings, the Club. |
| Club, close up | **Bare.** The mood light works, but the walls are flat and grey, the bar is a box, and the floor is empty. |
| Arcade, close up | **Bare.** A large empty floor with 6 cabinets on one wall. The Prism Shift screen is flat pink, because the shader is RENDER's. |
| L3 hotel rooms | **The weakest part** (about 0.60 alone): a bed, a desk and a chair in big bare rooms. |
| L4 homes | **Good.** A full ring of furnished units. |
| Build stages | **Good.** Site crane → scaffold → dome frame → finished. |

## Gap to Paul's aim, "a glittering city under glass"

| view | now | estimate (0.80 = glitters) |
|---|---|---|
| **Night, 250 m** | Nearly there: a warm glass shell over multicoloured windows, neon bands and a bright atrium. The last step is sparkle on the upper floors and city lights reflected in the glass. | about 0.76 |
| **Day, 250 m** | A domed city with neon at street level. | about 0.72 |
| **Inside** | The atrium and galleries feel like a mall and a resort. The hotel rooms, club and arcade pull it down close up. | about 0.76 |

## Fixes, most important first

1. **ART-B: sign font.** Add B and fix P. Render every sign string on one test sheet.
2. **ART-B: hotel rooms.** A bed with a headboard and bedside lamps, a lounge chair, a wardrobe, a TV,
   a rug, a picture, curtains, a bathroom door. No empty patch over 2 m.
3. **ART-B: Club.**
   - A DJ booth on a raised stage.
   - A light truss with spots.
   - Booths in view.
   - A textured back wall.
   - A bouncer post and an ADULTS ONLY sign at the door.
4. **ART-B: arcade.**
   - 10–14 cabinets in rows, a prize counter, a neon floor, seating.
   - A sit-down racer cabinet shape for Prism Shift.
5. **ART-B: upper floors.** Balconies or planters on every third unit, and 3–5 very bright windows per
   side.
6. **ART-B: L1 cafe.** Cakes, cups and a menu board instead of boxes.
7. **ART-B / RENDER: day glass.** Fresnel at the grazing edge.
8. **RENDER: in-game evidence.** The 250 m night shot with glow, draw calls, follow-view fps inside the
   dome, and the arcade screen shader.
9. **ART-NPC: robot dancers.** Deliver them for the tone check.
