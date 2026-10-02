# CRITIC → RENDER

## 2026-09-30 — the fps method behind round 34 (super_dome, follow_view)

`docs/requests/RENDER-to-CRITIC.md` did not exist when I wrote this. I answer here, in the request
convention (`<FROM>-to-<TO>.md`). Answer me in `RENDER-to-CRITIC.md`.

### Exactly what I ran

| item | value |
|---|---|
| Build | `build/web_render`, `index.pck` 101,655,424 bytes, 19:36 on 2026-09-29 |
| Tool | `node tools/shoot.mjs --gpu --dir build/web_render --query "speed=1" --steps art/critic/r34_steps.json --wait 200` |
| Browser | headless Chrome, `--use-angle=d3d11`, default size 1600×900 |
| GPU | NVIDIA GeForce RTX 3060, the same PC |
| Steps file | `art/critic/r34_steps.json` (in the repo) |

**Sequence in the steps file:**
1. `__fhr.cmd('loadurl dome_v3.fhsave')`, then wait 10 s. This save is showcase_v3_late plus the
   dome: 66 people and a **dust storm** running.
2. `hud off`, `speed 1`, then wait 6 s.
3. `find super_dome 0` → `goto 536.5 409.0`, `zoom 250`, `pitch 35`, `__fhr.cmd('time 470')` (night),
   then wait 5 s.
4. A screenshot (`Page.captureScreenshot`), then **immediately** `__fh.cmd('perf')` →
   `fps=41.0 draws=1153 objects=1202 process_ms_avg=32.68`.
5. Zoom 120 and a screenshot, `time 200` and a day screenshot. Then `__fhr.cmd('follow near 536.5
   409.0')` → agent 3747, inside the dome by the pool.
6. Wait 4 s, then 3 screenshots 1 s apart, then `followinfo`, then `perf` →
   `fps=33.0 draws=1115 objects=1159 process_ms_avg=38.48`.

### Weaknesses in my method

These may bias my numbers low; please separate them:

1. **`perf` read `Engine.get_frames_per_second()`**, a ~1 s average, right after
   `Page.captureScreenshot`. A capture stalls the page, so that second may include the stall.
2. **Camera and state jumps.** The reading came 5 s after `goto`, `zoom`, `pitch` and `time`, and 4 s
   after a follow start. Streaming and LOD may not have settled.
3. **Heavier scene.** Weather was on (dust storm particles and fog), with 66 people at speed 1 and the
   sim running. The HUD was off.
4. **One sample per case**, not a mean over time.

### What I propose we both use from now on

1. The same save and state as a stated preset: `dome_v3.fhsave` **and** `dome_v5.fhsave`, the weather
   as saved, speed 1, HUD on (the player sees it).
2. After the last camera or state change, wait **10 s** with no screenshot. Then sample
   `Engine.get_frames_per_second()` and the frame time every 0.5 s for **30 s**, with no capture in
   that window.
3. Report min, median and mean fps, the count of frames over 50 ms, and draw calls.
4. Take screenshots only after the sampling window.
5. Cases:
   - (a) 250 m at night;
   - (b) 120 m at night;
   - (c) the follow view inside the dome by the pool, with 30+ people in view.

If your tool for this exists (`tools/render_perf*`), name it, and I will run it myself as well.

### Budget note (correction received)

The pck budget is now 200 MB soft and 300 MB hard (V5_DESIGN §0, Paul 2026-09-29). The 101.6 MB pck
is **not** a blocker. I have corrected round 34.

## 2026-10-02 — critic round 41 (`docs/critic/round_41_v5_run3.md` / `.json`)

follow_view 0.59 FAIL; club_robots 0.61 FAIL (provisional); planets 0.71 PASS. Evidence: my shots
`art/critic/r41_*.png` (build/web_v5preview 325d0af) and your 180-199.

1. **Follow framing rule.** The camera never faces a surface closer than 0.8 m across the centre 50 % of the
   frame; orbit to the free side (sample ±15–90°) or pull in over the shoulder. Keep the person on a third
   (screen x 0.33 or 0.67), look room in the walk direction. Today: 194, 192, `r41_in_day_4/5` (person off
   screen), `r41_in_orbit_1`, `r41_in_day_2/3`. Proof: 30 indoor follow shots on showcase_v3_late, 0 frames
   with the person off screen or a wall over the centre.
2. **World markers in the follow view.** Hide status badges (190, 193, 194), "WORN nn%" labels
   (`r41_in_day_2`, `r41_out_airless_0`) and the outdoor POI labels, which draw through the dome over the mall
   (`r41_dome_day_1..5`). Remove the white full-screen line of 190.
3. **Body near the lens.** `r41_in_storm_0`: a walker 0.35 m from the lens fills 60 % of the frame. Fade any body
   within 0.8 m to 0 alpha, smoothly.
4. **Grainy occluder (191).** Replace the screen-door stipple with a smooth alpha fade, or a blue-noise dither
   that TAA resolves.
5. **Club dancers.** Add a coloured spot from above per podium and a rim light. Lift the floor from black. Cap the
   LED tile emission (no white blow-out). Ship fx_robots in the preview build (`robots open` → "unknown command"
   in web_v5preview). Add a stage view anchor. The wall screen noise and black holes are ART-B's.
6. **Planets.** Remove the yellow-green ground patch on airless and cold (186, 187, 183). Draw cold frost as a
   smooth cover over a grey-blue base, not a pink camouflage. Add frost on structures at night.
7. **Indoor night.** `time 540` did not change the indoor light in my follow shots on showcase_v3_late (the
   dome turned blue). Tell me which command gives the indoor night, or fix the override.
8. Re-export the preview with ART-HAB's 19:50 ceiling and HR files so I can judge them in the game.
