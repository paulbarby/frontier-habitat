# Critic round 42 — follow_view (rubric 3.4)

Date: 2026-10-04 · Critic · Build `build/web_v5play3` (e9b1d35, pck 186.2 MB) · Rubric `docs/critic/v5_rubrics.md` §3.4,
V5_DESIGN §15 (roofs on, freer camera), `docs/V5_RUN3.md` item 1 · Pass >= 0.65.

## Evidence

- 170+ in-game shots of my own, headless Chrome on the GPU (`tools/shoot.mjs` logic, 1600x900, HUD on), in
  `art/critic/r42/follow_view/`. One session, save `showcase_v5.fhsave` (134-140 people).
- Real input, not only debug commands: key V, Tab, Q, R, Esc, Y; right drag (orbit, pitch); middle drag (free look);
  wheel (zoom); a left click on another speaker's bubble (CDP input events).
- A 30-shot framing sheet (Tab every 5.5 s): `sheet30/f00..f29.png`, `sheet30_0..2.png`.
- 12-frame strips at 1x and 4x: `strips/`, `strip_in1.png`, `strip_dome1.png`, `strip_in4.png`.
- Follow probe (`tools/render_follow_probe.mjs`), two runs: `fprobe_a/`, `fprobe_b/`.
- fps sampled 20 s per case from `window.__fhr.fps` (`r5_fps_*.png`).
- **Load warning.** Other critics ran browsers at the same time. CPU load was 70-85 % during every
  measurement. The fps and probe numbers are lower bounds.

**Not seen:** a follow on an upper apartment-block floor (no walker there); a natural dust storm (I forced
`storm 1`; the wind storm and the solar flare were natural events).

## Score

| consistency | appeal | style | score | result |
|---|---|---|---|---|
| 0.60 | 0.55 | 0.66 | **0.60** | **FAIL** (round 41: 0.59) |

Appeal is capped at 0.60: a body passes through the followed person's coat (`crop_stormdome0.png`).

## Definition of done, item 1

| check | result | evidence |
|---|---|---|
| straight walk indoors: head < 0.5 px, camera < 2 mm | **FAIL** | in1 run A 1.36 px / 4.09 mm; run B 1.63 px / 5.66 mm |
| straight walk at 4x | **FAIL** | in4 run A walk 34.5 px / 18.9 mm, 24 pops, 56 frames person off screen; run B 36.4 px / 20.2 mm, 28 pops, 84 off screen (no straight segment in either run) |
| dome | **FAIL** | dome1 run A 1.83 px / 4.13 mm; run B 1.81 px / 4.49 mm (RENDER's web run of 2026-10-02: 0.09 / 0.42) |
| outdoors | PASS | out1 0.056 px / 0.233 mm |
| roofs on | PASS | every indoor shot has a ceiling; Y in the follow view gives a toast, roofs stay on (`r6_roofsoff_follow_y.png`) |
| no weather inside | **FAIL** | wind-storm streaks and flare curtains drawn over indoor scenes (finding 1) |
| no body through the camera | **FAIL** | `r6_meteor_in_1.png`: a stippled pale disc over 35 % of the frame |

## What works

- V follows the selected person; the follow card shows name, rank, satisfaction, needs, activity, partner,
  the last 3 lines and File / Next / Switch / Exit (`r3_v.png`). The HUD dims to 35 %. Esc returns to the
  overview with the HUD bright (`r3_esc.png`).
- Tab goes to the next person (`r3_tab.png`). A click on another speaker's bubble switches the follow and the
  card (`r4_bubble_click_pair.png`).
- Orbit 360 (right drag: 90, 180, 360 deg), pitch high and low, zoom 1.46-3.3 m indoors, free look (middle drag),
  R returns behind the shoulder, Q swaps the shoulder. All respond (`sheet_r3_controls.png`).
- Bubbles: glass style, gold rim on the followed speaker, 14 px text, above the heads, never over the
  followed face (`r3_v.png`, `r4_tk1.png`, `r4_try18.png`).
- No beam across a doorway in any of my doorway frames (`strip_in1.png` frames 10-11, `sheet30/f27.png`).
- World markers are gone from the follow view (round 41 fault fixed), except one dashed line (finding 8).
- Good shots exist: dome gallery (`r1_dome_0.png`), greenhouse with bubble (`r1_kitchen_0.png`), corridor
  with bubble (`sheet30/f11.png`), outdoor suit by night with helmet lamp and stars (`r2_night_out_0/1.png`),
  outdoor by day on the right third (`r1_out_1.png`).

## Findings (most severe first)

| # | sev | owner | fault | evidence | fix |
|---|---|---|---|---|---|
| 1 | blocker | RENDER | Weather inside. The wind-storm streaks and the solar-flare aurora are screen-space post effects with no indoor term. | `r6_roofsoff_follow.png` (cantina bar), `sheet_r6.png` (apartment, residence tube), `r6_meteor_in_0/1.png` (green-violet curtains on a storehouse ceiling). Code: `fx_hazards.gd:133-136`, `fx_post.gd` `wind`/`aurora`, `post_grade.gdshader:48-62`; `world_view._follow_indoor` sets only `sky.indoor`. | Multiply `post.wind`, `post.aurora` and the flare grade by `(1 - _indoor)` (0.15 under a glass roof). Add the post terms to the weather gate (it counts particles only). |
| 2 | blocker | RENDER | Smoothness targets not met (DoD 1). At 4x the person leaves the frame for about 1 s at a room-to-corridor turn. | `fprobe_a/*.json`, `fprobe_b/in1.json`; `strips/in4_07.png` (empty floor, no person). | Drive the 4x camera from a 1 s look-ahead of the planned route, not the body. Off-screen guard: when the head leaves the centre 60 %, turn the aim first. Re-run the probe 3 times on an idle machine and report. |
| 3 | major | RENDER | Framing: the person is not in the frame, or a wall or pillar fills the centre. Sheet: 4 of 30 bad (f01, f07, f09, f25), 5 marginal (f08, f15, f19, f23, f26). | `sheet30/f01.png` (floor and a pot), `f09.png` (pillar, wall; the bubble shows but no person), `r2_restube_0.png` (residence tube, no person), `r4_talk_paused.png` (retail, no person), `r1_lounge_1.png` (wall over 60 %). | The frame test must also need the head inside the centre 70 % of the frame. If no shoulder shot passes, use a wide shot: 2.6 m high, 25 deg down, person on a third. Proof: 3 sheets of 30, 0 bad. |
| 4 | major | RENDER | No framing rule for a lying or seated person. The camera stays at standing height behind the body: mattress and legs fill the frame, the head is cut. | 12 of 30 sheet shots are sleepers; `r1_apt_0/1.png`, `r3_tab.png`, `sheet30/f25.png` (shoes), `sheet30/f07.png` (the back fills 70 %). | For `sleep`, `lie_*` and `sit_*`: a side shot, pivot at the chest, 1.6 m to the side, 1.2 m high, 20 deg down, head on the upper third. |
| 5 | major | RENDER | Bodies pass through each other at doors and corridor mouths (appeal cap). | `crop_stormdome0.png` (a torso cuts into the followed white coat), `crop_airlock0.png` (two faces about 0.15 m apart, shoulders merged). | Keep the separation pass on every frame for bodies within 3 m of the followed person. In a tube or door, one person waits or steps aside 0.35 m. Minimum centre distance 0.45 m. Add a doorway separation gate. |
| 6 | major | RENDER | A body at the lens with a dithered fade; a see-through ghost body. | `crop_meteor1.png` (stippled pale disc, left 35 %), `crop_kitchen1.png` (window frame visible through a face at 0.6 m). | Move the camera off the body's line first (swap side or pull in); finish the fade before 0.35 m; no dither at the edge. |
| 7 | major | RENDER + UI | The bubble of a speaker off screen is clamped onto the HUD; a bubble at the right edge is cut by the rail. | `r4_talk_a.png`, `r4_talk_paused.png` (bubble over the top bar and the card), `r4_try18.png` (text under the right rail). | Clamp bubbles into the free view rectangle (UI publishes it). For a speaker off screen, show a small edge chip with an arrow. |
| 8 | major | RENDER | fps in the follow view is 19-23 median (min 12-19) with 140 people; draws 1,061-1,297; view 18-19 ms. Under load, so not a fair test, but >= 45 is not proven. | `r5_fps_room/dome/out/restube.png`. | Re-run `render_perf` on an idle machine; publish median and frames over 50 ms for the 4 cases. |
| 9 | minor | RENDER | A white dashed ring line is drawn through the dome wall in the follow view (probably the airlock suit-range ring, `fx_ghost.gd`). | `crop_tk1_line.png`, `r1_corr_0.png`. | Hide the suit-range rings in the follow view. |
| 10 | minor | UI | The left column stays full in the follow view: card 340x330, the REQUEST banner at full strength, dock tabs, minimap (about 390 px, 24 % of the width). | `r3_v.png`, `r4_tk1.png`. | Dim or fold the REQUEST banner into the dock badge while following; H hides all but the card. |
| 11 | minor | RENDER | The super dome by night is flat and brown at eye height. | `r2_night_dome_0/1.png`. | Warm practical lights in the gallery shop fronts at night; a cooler sky through the glass. |

## Gap to 0.80 and 0.90

- **0.80:** 0 bad frames in 3 sheets of 30; a lying / seated shot rule; no weather or flare inside; no body
  overlap; the probe targets met at 1x and 4x; bubbles inside the free view; 45 fps proven.
- **0.90:** a depth cue (soft background blur), cinematic shot choice per activity (talk two-shot, work close-up),
  and the §15.2 watch mode.
