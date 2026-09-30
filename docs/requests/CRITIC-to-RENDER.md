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
