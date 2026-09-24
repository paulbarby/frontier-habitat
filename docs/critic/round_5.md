# Critic round 5 — astronauts after the round-3 fixes

Date: 2026-09-24 · Critic (did not build the work) · Rubric: V3_DESIGN §9 · Pass ≥ 0.65 · Same
calibration as rounds 1–4.

## Scores

| subject | cons. | appeal | style | score | result | round 3 |
|---|---|---|---|---|---|---|
| npc_suit | 0.83 | 0.79 | 0.83 | **0.82** | PASS | 0.80 |
| npc_indoor | 0.76 | 0.68 | 0.72 | **0.72** | PASS | 0.66 |
| npc_animation | 0.82 | 0.74 | 0.78 | **0.78** | PASS (no longer provisional) | 0.75 |

## Evidence

- `art/npc/` sheets (22:47–22:48): turnarounds, clip sheets, deform sheets, transitions.
- `npc_report.md`: 235 pass, 0 fail.
- `godot_check.json`: 140 tests, 0 failures, `ok: true`.
- Blender render of both models (rest pose): `art/critic/r5_side_by_side.png`.
- Crops: `r5_heads.png`, `r5_55px.png`, `r5_tones.png`, `r5_suit_rows.png`, `r5_in_rows.png`.

**Gap:** there are no in-game NPC shots. They come in the `npc_interaction` round.

## The maker's claims, checked against the images

| claim | result |
|---|---|
| Face: nose −40%, mouth, jaw, eyes, brows | **Mostly landed.** The nose is still a pointed wedge in the three-quarter view. |
| Neck shorter and thicker, skull wider | **Landed.** |
| Hair silhouettes | **Partly.** The bun and the bob read at 55 px. The crop and the ponytail still look the same. |
| Hair tinted in 4 colours by RENDER | **Not shown.** Every head in the skin-tone row has near-black hair. |
| Body mass, crotch, shoulder roll, patches, wrist unit | **Landed.** |
| Hands: index finger apart, curl, thumb in | **Landed** on both variants. |
| Six skin tones shown | **Landed.** Tone 5 reads grey-white. |
| repair_kneel 8° more upright | **Landed** for indoor. In the sheet the suit visor still looks close to the panel. |
| talk nod, carry_walk elbow give, prop.R without keys | **Landed.** |
| Suit AO floor and blur, 3 cm pack lenses | **Landed.** The thigh smudges are gone. |
| npc_check | **Landed.** Blends between standing loops and the work and talk clips now peak at 10°; before they reached 29–46°. |

## Fixes (every subject is under 0.80 except npc_suit)

**npc_indoor**
1. Make the ponytail show from behind and from the side at 55 px: 30% thicker, 4 cm further out, a
   lighter tie band. Give the crop a visible hairline edge.
2. Show the 4 hair colours in the sheet.
3. Round the nose bridge and lower the tip 5 mm.
4. Warm skin tone 5 (more red and yellow, less grey) so it does not read as a mannequin.
5. Bevel the finger edges.

**npc_animation**
1. talk: raise the peak hand to chest height, and add a second hand that answers.
2. repair_kneel on the suit: keep ≥ 6 cm between the visor front and the panel. Measure the visor,
   not the helmet centre.
3. RENDER: show in the `npc_interaction` round that no suited colonist uses a bed or `sit_eat`.

**npc_suit** (optional): the visor clearance in repair_kneel, as above.
