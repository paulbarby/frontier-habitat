# Critic round 42: people (close-up, outfits, animation)

Date: 2026-10-04. Critic. Rubric: `docs/critic/v5_rubrics.md` §3.1-3.3. Pass >= 0.65.
Build: `build/web_v5play3` (commit e9b1d35, pck 186.2 MB). The people GLBs in the build are the same as the
files on disk (`git diff e9b1d35 -- assets/models/people_*` is empty), so the sheets in `art/people/` show the shipped models.
Evidence: 468 in-game shots of my own, `art/critic/r42/people/` (crops of the faults are in `crops/`). Saves:
showcase_v5 and showcase_v3_late. Sheets that I looked at: closeup, outfits, wardrobe, uniforms, clips,
paired, cheer/dance_c, enter/exit, the run strip and the audit `audit_final41.md`.

## STOP: tone breach (§0) in the shipped build

The women's and girls' swimwear does not cover the chest.

- `swimwear` on f1, f2, f3 and **c2 (girl)** is a band below the bust with two thin straps. The breasts are bare. On f1 and
  f2 the nipples are modelled and visible.
  - Sheet: `art/people/people_wardrobe.png` (swimwear column) and `people_outfits.png` (f1 swimwear).
  - Crop: `art/critic/r42/people/crops/swimwear_chest_f1_f1w_f2_c2.png`.
- **It is in the game now.** On loading showcase_v5, 4 bodies draw swimwear (`npc.draw_keys`: p_f2 x2, p_m2, p_m3).
  "Tourist 2" (f2) sits on a dome bench with her chest bare: `swr_36816_b.png`, crop
  `crops/swimwear_ingame_f2_chest_swr_36816_b.png`.
- SIM gives swimwear to everyone at the pool venue, and this test comes before the child test (`sim/people.gd:769-771`).
  So a girl at the pool gets the c2 swimwear.
- Rubric hard cap: people_outfits is capped at 0.40. The orchestrator must hold the release until this is fixed.
- Fix (ART-NPC): a modest one-piece with a full front and back to the collar bones, on every female and girl body. Remove the
  bare-breast cut. Delete the nipple detail on all swimwear bodies. Re-render the wardrobe sheet. SIM: test the child before the
  pool, or give children a separate child swimsuit.

## Scores

| subject | cons. | appeal | style | score | result |
|---|---|---|---|---|---|
| people_closeup | 0.65 | 0.64 | 0.68 | **0.66** | PASS (marginal) |
| people_outfits | 0.60 | 0.55 | 0.45 | **0.40** (cap; raw 0.53) | **FAIL, STOP** |
| people_animation | 0.60 | 0.55 (cap 0.60) | 0.68 | **0.61** | **FAIL** |

Definition of done: item 2 (critic people >= 0.65) is not met. Item 3 (no seated or lying body overlaps furniture) is not met.

## Faults

| # | severity | owner | fault | where | fix |
|---|---|---|---|---|---|
| 1 | blocker | ART-NPC, SIM | Bare-breast swimwear on women and girls (see STOP). | `crops/swimwear_*` | See STOP. |
| 2 | blocker | RENDER | Party guests stand on the same point. 3 to 5 bodies merge into one; heads come out of chests. Census: 5 bodies at (1140.3, 1275.1), 4 at (1135.4, 1270.2), 4 at (1128.6, 1286.8). | `da1_c.png`, `dc2_a..e.png`, `egg_b_s0.png`, `crops/party_*`. Steps: load showcase_v5 with debug=1, `partydemo throw`, speed 3 for 20 s. Positions: `party_clip_census.txt`. | Give each guest a separate slot at the venue (ring or grid, >= 0.6 m apart). Never put two bodies on one anchor. Test: no two drawn bodies within 0.4 m. |
| 3 | blocker | RENDER (ART-HAB anchor) | Seated body through the bench back: the man's torso is in front of the backrest from behind (about 10 cm through). Thighs inside the bench seat during sit_enter. | `si1_a.png`, `crops/bench_back_through_body_si1_a.png`, `crops/thighs_in_bench_seat_sit_enter_swr_36816_b.png`. Correct case for compare: `crops/bench_ok_reference_sb1_a.png`. | Move the bench seat anchor forward 0.12 m, or measure the hip from the backrest. Run the seat check on park benches with all 8 bodies and on sit_enter frames. |
| 4 | major | RENDER | Leisure clips are never drawn: `ACT_UNREACHED = drink_bar, sit_bar_stool, sleep_cell, lounge_pool, swim` (`presentation/fx_npc.gd:2609`). People at the pool sit on park benches in swimwear. Nobody uses a bar stool. The enter/exit clips for stool, bunk, lounger and water exist since 2026-10-03 (b). | `swq_46086.png` (man in trunks on a park bench), `swr_36816_b.png`. | Draw these 5 acts with the new enter/exit clips. Put swimmers in the water at the Swim_0..5 anchors, loungers at Lounger_0..9, drinkers at Seat_bar_0..n. |
| 5 | major | RENDER | Social body language is never drawn. SIM's talk anim (talk_gesture_a/b, laugh, argue, sulk, flirt_lean) goes only to the bubbles. hug, kiss_brief, handshake, slap and hold_hands_walk play only in tabloid photos. Romance talk shows two people walking or sitting still. | `tk2_a..d.png` ("Talking with Amir (romance)": seated idle). Code: `fx_bubbles.gd:212` reads `anim`; `fx_npc.gd` never does. | Play the talk anim on the speaker for the line time. Play the paired clips with `npc_pairs.json` at couple, date and wedding events. |
| 6 | major | SIM | About a third of the names do not match the body sex. `name_sex` lists 40 names; every other name gets a random sex (`sim/people.gd:455`). Seen: Mona, Agnes, Vera, Irina, Siena on male bodies; Amir, Otto, Sergio, Mehmet, Carlos on female bodies; children Stefan and Timo on the girl body, Rhea on the boy body. 38 of about 94 names after the first 40. | Follow card in `tk2_a.png` (Agnes Boateng, m2), `dc2_a.png` (Amir Fontana, f3), `fc_7560_front.png` (Stefan, c2). Name census: `art/critic/r42/people/name_census.txt` (id:name:body). | Add the sex to every entry of `content/names.json` (first names), and pick the name from the list of the person's sex. Migrate old saves by name. |
| 7 | major | SIM | Party guests wear work uniforms. `outfit()` makes casual only for sleep, rec and housing; a party is none of these. | `da1_a..e.png` (technician coverall and security vest at a party). | Return casual when `a.party` is set or `plan_kind == "party"`. |
| 8 | major | RENDER (ART-HAB anchor) | Medical bed: the lying body floats about 0.3 m above the mattress, feet in the air. Staged with `use 2174 bed 2561 0 lie sleep`. | `st_med_a.png`, `st_med_c.png`, `crops/med_bed_float_st_med_a.png`. | Use the medical bed's mattress height for the lie offset. Add medical beds to the lie gate. |
| 9 | major | ART-NPC | Child casual_a: a band of skin and underwear shows at the back of the waist in walk. The adult hem fix (`extend_hem`) did not reach the children. | `c1_b_s3.png`, `crops/child_waist_gap_c1_b_s3.png`. | Extend c1/c2 tops 5 cm over the waistband; check in walk, run and sit. |
| 10 | minor | ART-NPC | Hair reads as a glossy shell at follow distance (f1 bob in black, f3 bun). m1 hairline is still a hard cut edge. | `r1_b_s0.png`, `fc_2172_front.png`. | Alpha strand cards at the hairline and a rougher hair material (no specular streak over the whole shell). |
| 11 | minor | ART-NPC | Sleep poses look sprawled (one leg raised, torso turned 90 degrees from the hips). Shoes stay on in bed. | `sl_m_d.png`, `sl_c2_d.png`, `sl_f2_a.png`. | A calmer side and back sleep pose; hide shoes in bed (bare feet mesh or a blanket). |
| 12 | minor | ART-NPC | No clips for the party acts `toast` and `sing` (SIM `party.action_of`); the guest stands idle. | `sim/party.gd:555-558`, manifest clip list. | Add toast (raise cup) and sing (sway, hand on chest) clips, or map them to cheer and dance_a. |
| 13 | minor | ART-NPC | Audit faults left: fight_idle slide 2.5-2.7 cm, dance_c slide up to 3.2 cm (c2), drink_bar snap 8.5 deg/frame, swim neck 71 deg, kneel_exit slide 2.2 cm. | `art/people/audit_final41.md`. | Fix before these clips are drawn (faults 4, 5). |
| 14 | minor | RENDER | The follow camera aims at adult eye height for a child; the child's face is at the bottom of the frame. In a doorway a walker passes through the followed runner. | `fc_7556_front.png`, `r1_b_s5.png`. | Aim at the followed body's own head height. Hold the second walker for 0.5 s at a door. |
| 15 | minor | RENDER | Probe in1: locomotion clip changes 22.1 per minute while walking straight; head jitter 2.44 px (DoD < 0.5 px). dome1: 7.7 per minute, 1.63 px. | `render_follow_probe.mjs --cases in1,dome1`; `art/critic/r42/people/in1.json`, `dome1.json`. | Hysteresis on the idle/walk/run switch (follow view owner checks the jitter). |

Not tested: fights in game (no fight happened in my runs; there is no debug start), hug and kiss in the world (never drawn,
fault 5), escort and cuffed walk at close range (the camera hit a wall in `esc_*`, `cuf_*`), robot dancers.

## What works

- Mocap walk and run look natural at follow distance: arm swing, forward lean, planted feet (`w2_m_b_s0..5`, `r1_b_*`).
- Idle arms are relaxed and bent now (`i1_d_s1.png`); round 41's stiff arms are fixed.
- At 1.5 m in game a face reads as a person: brows, eyes, nose, lips, skin texture (`fc_2172_front.png`).
- 8 bodies and tint make a crowd of many people. Spread in showcase_v5: f1 15, f2 24, f3 25, m1 17, m2 19, m3 23, c1 5, c2 3.
- Uniforms now follow the contract: coverall with stripe, tool belt and boots; security vest with red armband
  (`fc_2172_front.png`); food apron and green (`wb1_a.png`); prison orange (sheet).
- Desk, bench and table poses: no body in a desk or a table (`st_wb_c.png`, `st_desk2_b.png`, `st_eat1_c.png`). Children sit at
  class desks (`st_kid1_b.png`) and lie on bunk mattresses (`sl_c_b.png`, `sl_c_d.png`).
- dance_a, dance_c and the Konami dance read as party moves, PG, with no T-pose in about 40 frames (`dc2_*`, `egg_*`).
- Paired clips meet in the tabloid photos: hug, kiss_brief, handshake, argue, punch (`photos.png`). Tone PG-13.

## Gap to 0.80 and 0.90

- **0.80:** faults 1-9 fixed; social and leisure clips drawn in the world; strand hair; matte cloth with folds; calmer sleep.
- **0.90:** facial expressions in the talk lines (smile, frown, laugh with teeth); per-variant gestures; secondary motion
  (hair, hands); skin with subsurface.

## Fix order

1. ART-NPC + SIM: modest swimwear (STOP).
2. RENDER: one body per slot at parties and venues.
3. RENDER / ART-HAB: bench and medical bed offsets; seat and lie gates on these furniture types.
4. RENDER: draw swim, lounger, stool, bar and cell clips.
5. RENDER: talk anim and paired clips in the world.
6. SIM: name sex for every name; casual at parties.
7. ART-NPC: child hem, hair, sleep pose, toast/sing, audit leftovers.
