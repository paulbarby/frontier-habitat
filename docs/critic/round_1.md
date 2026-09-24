# Critic round 1 — pilot: astronaut suit

Date: 2026-09-24 · Critic (did not build the work) · Rubric: V3_DESIGN §9 · Pass ≥ 0.65
(0.50 placeholder, 0.65 shippable indie, 0.80 good, 0.90 excellent).

## Scores

| subject | consistency | appeal | style | score | result |
|---|---|---|---|---|---|
| npc_suit | 0.78 | 0.70 | 0.76 | **0.75** | PASS |
| npc_animation (provisional, 5 pilot clips) | 0.76 | 0.58 | 0.65 | **0.66** | PASS, marginal, provisional |

## Evidence I looked at

- `art/npc/turnaround_suit.png`, `clips_suit.png`, `transitions.png`, `deform_suit.png`
- `art/npc/npc_report.md` (43 pass, 0 fail, 3 pending), `art/npc/godot_check.json` (11 transition
  tests pass; 19 failures = the 19 clips not built yet)
- `assets/models/astronaut_suit.glb`: materials read from the file; clip motion ranges measured by
  `art/critic/anim_range.mjs`
- In-game, `build/web_render` (built 16:51), `load=res://content/saves/showcase_day9.fhsave`:
  `art/critic/r1_ingame_a0_z9.png`, `r1_ingame_a4_z9.png`, `r1_ingame_a8_z25.png`,
  `r1_night_a1633_z10.png`, `r1_night_z28.png`; crops `r1_crop_a0.png`, `r1_crop_a4.png`,
  `r1_crop_z25.png`, `r1_crop_front.png`; frame strips `r1_seq_walk_a.png`, `r1_seq_walk_b.png`.
- Style reference: `art/key_art.png`, `art/screenshots/03_close_greenhouse.png`,
  `art/models/_review_habitat.png`.

Gap: the indoor variant and 19 clips do not exist yet. No in-game sit sequence was available.

## npc_suit — 0.75, PASS

What works. At 30–80 px the figure reads at once as an astronaut: white body, gold visor, grey pack,
role stripe on the arms and the helmet (orange, green and blue seen in game). The palette is the v2
palette (SuitMain sRGB ≈ 232/234/238, graphite Frame, one accent). The detail density matches the
bevelled room and exterior models. Every contract part is there: visor, lamps, neck ring, hard upper
torso, pack with vents, antenna, wrist rings, thick-soled boots, chest box. In game close up
(`r1_crop_front.png`) it looks clean and believable.

What holds it under 0.80:
- **Night.** Outside at night the suits go dim grey. At 28 m zoom I could not find a colonist
  (`r1_night_z28.png`). The lamps are tiny white spheres that also read as floating dots by day.
- **Chest box** is a blank white label.
- **Close up**: facets and grey AO speckles on the legs and pelvis; a pelvis bulge; 6-sided finger
  tubes.
- **Arm line**: arms hang about 20° out (A-pose); in idle it looks like a mannequin.
- Bellows at knees and elbows are thin lines; hard torso and soft limbs have the same finish.

Fixes, most important first:
1. **Night read.** Replace the white lamp spheres at the visor corners with two lamp housings
   4 × 3 × 3 cm, flush on the helmet sides; emissive only on a forward lens (#FFF4E0, strength 4).
   Pack status lights: two 2 cm lenses, one green #5EE07A, one amber #FFB547 (both plain white now).
   RENDER: an additive halo on the helmet lamps at night, so an outside colonist is findable at
   25–30 m zoom.
2. **Chest box**: Screen material (cyan UI pattern, emissive 1.0) and two accent buttons. Add an
   umbilical hose ≈ 2.5 cm diameter from the pack lower right to the chest box.
3. **Shading**: weighted normals or auto-smooth 40° on limbs and pelvis; re-bake AO with more samples
   and a blur; clamp AO ≥ 0.55 on SuitMain.
4. **Pelvis**: take 2–3 cm off the front and sides of the crotch and hip volume.
5. **Arm line**: in the clips, upper arms 8–10° from the body, elbows bent 12–15°, hands turned in.
6. **Bellows**: 3 ribs at each knee and elbow, 0.8–1.0 cm proud, Trim. Hard upper torso: a seam line
   and roughness 0.45 (limbs 0.68).
7. **Gloves**: 8-sided fingers, rounded tips, grouped 2 + 2 plus thumb, Rubber palm (take the
   triangles from hidden pack faces; 6,781 of 7,000 used).
8. **Pack**: 1 cm chamfer on every box edge; split the white back panel into two with a recessed seam.
9. **Seated depth**: the pack reaches 0.69 m behind the stand point, so a chair back at 0.30 m cuts
   through it. Suited colonists sit only on backless seats; indoors they use the indoor variant. Keep
   ≥ 2 cm between the pack bottom and the seat top (it touches now).

## npc_animation (provisional) — 0.66, marginal PASS

Technical quality is excellent: loop seams 0.000°, enter/exit ends on the rest poses 0.000°, foot
slide 0.94 cm, walk stride 1.12 m = 1.05 m/s × 1.067 s, no root motion, Godot transitions with no
pops. The sit trio is good: the weight goes forward over the knees, the hands push on the thighs, the
body settles on the 0.46 m seat.

The two clips a player sees most are the weak ones:
- **walk**: shin flex measured 28–30° through the whole stance phase, 70° peak in swing. The knees
  never straighten, so it reads as a crouch or a sneak, not a heavy suit.
- **idle**: the motion exists (hips 4.8 cm, head 7.8°, chest 2.9° over 4 s) but is under the game
  camera's resolution. At 30–80 px it looks frozen.
- **run** is missing, so in game RENDER plays walk at about 3.2× for normal travel and colonists
  scurry (`r1_seq_walk_b.png`). This is scope, not a fault of the pilot, but it is what Paul sees now.

Fixes, most important first:
1. **run** first (3.4 m/s light suited jog: short flight phase, knee lift ≈ 70°, elbows 60–70°,
   3–4 cm bob).
2. **walk**: stance knee 10–15° at heel strike and mid-stance; swing peak 60–70°; keep the 3 cm hip
   bob and add a 5° forward lean.
3. **idle**: one readable action per loop: head and upper-body turn 15–20° and back, 6–8 cm weight
   shift, one small hand move (a look at the wrist panel). Seam stays 0°.
4. **sit_idle**: lift the gloves 1 cm off the thighs (they press in).
5. sit_enter / sit_exit: no change apart from the pack clearance (npc_suit fix 9).

This score covers these 5 clips only. The full set is rated again from zero.

## What must be true for the full NPC delivery to pass

1. `astronaut_indoor.glb` has the same skeleton (names, rest pose, lengths). It has a navy #243247
   jumpsuit with SuitAccent shoulder panels and collar, a calm face, and 4 hair variants that differ
   at 55 px by silhouette, not only by colour. Skin takes 6 tones. ≤ 6,000 triangles. It has the same
   palette and detail density as the suit. A `turnaround_indoor.png` has the 30/55/80 px views.
2. All 24 clips are in both GLBs. `clips_suit.png` and `clips_indoor.png` exist. `npc_report.md` shows
   0 failed and 0 pending. `godot_check.json` shows `ok: true` and the real triangle count (it shows
   0 now).
3. run ≈ 3.4 m/s with foot slide ≤ 2 cm. The carry crate sits at `prop.R` and does not cut the chest
   or the pack. The hands of work_console and work_bench are on a 1.0 m and a 0.9 m surface.
   repair_kneel hands are on a panel 0.45 m ahead at 0.4 m. sleep lies on a 0.55 m mattress with
   the head to local +Y. collapse and dead do not put the pack into the ground.
4. The idle and walk fixes above are done, and npc_suit fixes 1–3 at least.
5. There are in-game sequences as §9 asks: walk → sit → eat → stand, walk → lie → sleep → get up,
   and kneel repair, with close shots by day and by night. An outside colonist is findable at night
   at 25–30 m zoom.
6. The in-game shots show no body through beds, chairs or walls.

## Seen in passing (later rounds, not scored)

- Colonists stand inside beds in the habitat (`r1_crop_a4.png`, `r1_seq_walk_a.png`,
  `r1_ingame_day2_z9.png`).
- A colonist passes through a room wall (`r1_seq_walk_b.png`, frame 5).
- In some close shots the habitat round wall is not drawn (`r1_ingame_day2_z9.png`). It can be the
  cutaway.
- Tooling: `godot_check.json` reports suit triangles 0. Some critic PNGs got `.godot/imported` cache
  entries before I added `art/critic/.gdignore`. They do no harm.
