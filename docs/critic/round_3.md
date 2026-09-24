# Critic round 3 — full astronaut delivery

Date: 2026-09-24 · Critic (did not build the work) · Rubric: V3_DESIGN §9 · Pass ≥ 0.65 ·
Rated from zero, same calibration as rounds 1–2 (0.50 placeholder, 0.65 shippable indie,
0.80 good, 0.90 excellent).

## Scores

| subject | consistency | appeal | style | score | result |
|---|---|---|---|---|---|
| npc_suit | 0.82 | 0.77 | 0.82 | **0.80** | PASS |
| npc_indoor | 0.70 | 0.60 | 0.68 | **0.66** | PASS, marginal |
| npc_animation | 0.78 | 0.72 | 0.76 | **0.75** | PASS on the clips; provisional until `godot_check.json` is ok |

## Evidence I looked at

- `art/npc/turnaround_suit.png`, `turnaround_indoor.png` (4 heads), `clips_suit.png`,
  `clips_indoor.png` (24 clips × 4 frames, with furniture), `transitions.png`, `deform_suit.png`,
  `deform_indoor.png`, `npc_report.md` (234 pass, 0 fail, 0 pending, 11 info),
  `godot_check.json` (140 tests, 28 failures, `ok: false`), all at 22:15–22:17.
- My own: `art/critic/r3_side_by_side.png` (Blender `--background` render of both GLBs, rest pose,
  indoor with `Head_1`); crops `r3_in_face.png`, `r3_in_55.png`, `r3_suit_packtop.png`,
  `r3_suit_helmet.png`; the sheets split for reading: `r3_clips_*_{a,b,c}.png`,
  `r3_trans_{a,b,c}.png`.

**Gap:** no in-game NPC shots this round, because RENDER has not integrated the indoor variant or the
new clips. The night read, speed-matched playback, crowd variety and bodies through furniture are
rated in the `npc_interaction` round.

## Round-1 fixes: did they land?

| fix | result |
|---|---|
| run as the normal pace | **Landed.** 3.40 m/s, 6 of 20 frames in flight, hip bob 3.5 cm, foot slide 1.0 cm. |
| walk knee bend 10–15° | **Landed.** Knee 6.3–14.8° with the heel down. The stance leg reads straight. |
| a visible idle | **Landed.** Hip shift 6.4 cm, chest turn 16.9°, a look at the wrist panel. |
| arms 9° from the body | **Landed.** 9.3°. |
| flush helmet lamps | **Landed.** No more floating dots. |
| green and amber pack lights | **Landed.** The amber light does not show at 55 px. |
| lit chest screen with a hose | **Landed.** Cyan screen, 2 buttons, a hose under the arm. |
| smoother leg shading | **Partly.** The flat facets are gone. Grey AO smudges remain on the thighs and lower torso. |
| night read in game | **Not verifiable.** There were no in-game shots. |

## The maker's list: checked

| claim | verified |
|---|---|
| simple low-poly faces with a small round nose | **Partly.** The face is simple, but the nose is a large wedge, not small. This is the main fault of `npc_indoor`. |
| mitten-like hands | True for both variants. |
| slightly boxy shoulder panels | True for both variants. |
| crop and bob differ only a little at 55 px | **Worse than stated.** All four heads look the same at 55 px (`r3_in_55.png`). |
| helmet close to the machine when kneeling | True. The visor comes within a few cm of the machine face in `repair_kneel`. |
| a suited sleeper sinks 3 cm | True. This is acceptable only if RENDER never puts a suit in a bed. |

## npc_suit — 0.80, PASS (good)

It reads at 30, 55 and 80 px as a white astronaut with a gold visor and a role stripe. Close up it is
clean: a hard upper torso, 3-rib bellows, a chamfered two-panel pack, the lit chest box and hose, the
lamp housings, thick boots. It matches the building palette and the building detail density. No fix is
required. Optional polish, most useful first:
1. Clamp AO on `SuitMain` to ≥ 0.65, or blur the bake 2 more passes (thigh and pelvis smudges).
2. Separate the index finger from the glove block.
3. Put a 1 cm bevel on the shoulder plates.
4. Make both pack lenses 3 cm, emissive 4, so the amber light shows at 55 px.
5. `repair_kneel`: lean the chest back 6–8° and keep the helmet ≥ 8 cm from the machine.

## npc_indoor — 0.66, marginal PASS

What works: the navy jumpsuit with accent shoulder panels, collar and cuffs matches the suit and the
rooms. The belt, pockets, knee pads and boots give it a working look. At the game camera the body
reads.

What holds it down: close up (where Paul will look at people in beds and at tables) the face is weak,
the neck is a long thin post, the limbs are thin next to the suit, and the four heads look the same at
55 px.

Fixes, most important first:
1. **Face**: reduce the nose projection by 40% and round the tip. Add a 3 cm soft mouth line and a
   rounder jaw. Make the eyes one step larger with a lid line. Lower and curve the brows so the face
   reads calm, not stern.
2. **Head and neck**: widen the skull 6–8%. Make the visible neck 3 cm shorter and 15% thicker.
3. **Hair at 55 px**: give each head a different silhouette. Crop: tight to the skull. Bob: to the
   jaw, +2 cm volume. Bun: +35% and set higher. Ponytail: to the collar, out 3 cm. If the game allows
   it, tint the hair from 4 colours; colour does more than shape at 55 px.
4. **Body mass**: upper arms and thighs +12–15% girth, forearms and calves +8%. Raise the crotch 4 cm.
5. **Shoulder panels**: a 1.5 cm bevel, following the shoulder curve.
6. **Hands**: separate the index finger, curl the others 20°, bring the thumb in 15°.
7. **Detail density**: a chest name patch in the role accent, a sleeve patch, leg seam lines and a
   small wrist unit (`Screen`).
8. **Evidence**: show the 6 skin tones in `turnaround_indoor.png`.

## npc_animation — 0.75, PASS on the clips, provisional

There are 24 of 24 clips in both files. Loop joins and rest poses are within 1°, and the hands and
bodies were measured against the furniture (console, bench, desk, seat, bed, panel, crate). The new
run, walk and idle are good. Sit, lie, kneel, collapse, dead and cheer all read clearly.

Fixes, most important first:
1. **Contract gate (§3.5)**: `godot_check.json` shows `ok: false` with 28 failures (14 per variant).
   - Every change between a standing loop and `work_console`, `work_bench` or `talk` pops `hand.L` or
     `hand.R` by 29–46° at blend frame 5.
   - Carry on/off pops `prop.R` by 80.5°.
   - idle → walk → run → stop pops `shin.L` by 39.5° (the limit there is 36.5°).
   A 0.25 s blend of 45° is about 6° per frame, so these steps mean the blend is not applied at that
   frame. That is RENDER's fix. ART-NPC can help: keep the work-clip hand orientation within 20° of
   idle.
2. **carry**: keep `prop.R` at one local rotation in every clip, and move the crate with the hand.
3. **repair_kneel**: lean back 6–8° for helmet clearance. The indoor head is also close to the panel.
4. **sit_eat on the suit**: the glove goes to a closed visor. RENDER plays eating only on the indoor
   variant.
5. **talk**: gestures 15° higher at the peak, plus a 10° head nod, so it reads at game size.
6. **carry_walk**: 5° of elbow give on each foot strike (the arms are locked now).
7. **Suits never use beds**: RENDER puts this rule in the state machine and its check.

## What must be true for the delivery to be final

1. `godot_check.json` shows `ok: true` for both variants.
2. `npc_indoor` fixes 1–3 are done, and the 6 skin tones are shown.
3. The `npc_interaction` round has in-game shots:
   - the suit outside by day and by night, findable at 25–30 m zoom;
   - indoor colonists in beds, on seats and at consoles;
   - a kneel repair at a real machine;
   - a crowd of 8+ indoor colonists at 55 px whose heads and skin tones differ.

   No suited colonist is in a bed, and no body goes through furniture or walls.
