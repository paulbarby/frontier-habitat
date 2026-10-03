# Critic round 42 — performance_feel (new subject)

Date: 2026-10-04 · Critic · Build `build/web_v5play3` (e9b1d35, pck 186.2 MB) · Rubric `v5_rubrics.md`, budgets V5_DESIGN §0.
Evidence: `art/critic/r42/performance_feel/` (perf JSON and logs, frame traces, 94 shots, probe script `fh_feel.mjs`). Every shot cited here was looked at.

## Machine load (other agents ran during every measurement)

- PC: i7-14700K (28 threads), RTX 3060 8 GB, 64 GB RAM.
- During my runs: CPU 33-94 %, GPU 29-99 % before my own browser started, 3-9 other headless Chrome
  instances (8 other critics), 0-9 Blender/Godot processes. VRAM up to 7.7 of 8 GB.
- So the absolute numbers are pessimistic. The verdict does not depend on it: RENDER's own latest numbers
  (tier 3, its progress log, CPU 14-18 %) also fail: overview 30.1, roofs off 33.0, room follow 37.6, dome 36.7 fps.

## 1. fps presets (`render_perf.mjs --vsync --settle 10 --secs 30`)

| preset | target | pass a (title mode) | pass b (title=0, HUD on) | pass c (title mode) | result |
|---|---|---|---|---|---|
| v5_follow_room | 45 | 30.9 fps, median 30, 113 frames > 50 ms, max 333 ms | 16.8, 180, max 1,850 | 18.1, 215, max 517 | **FAIL** |
| v5_follow_dome | 45 | 36.7, median 59.9, 74, max 667 | 18.9, 190 | 26.4, 131, max 900 | **FAIL** |
| v5_overview | 45 | 25.3, median 29.9, 137, max 167 | 15.5, 260 | 21.0, 174 | **FAIL** |
| v5_roofs_off | 40 | 21.9, median 29.9, 160, max 117 | 17.0, 224 | 16.9, 233 | **FAIL** |

- CPU at the start of each window: a 33-59 %, b 44-67 %, c 53-77 %.
- §0 budget "no frame over 50 ms in 120 s after load": **FAIL** everywhere (74-260 in 30 s).
- Draw calls: overview 1,305-1,357 (≤ 1,700 PASS); room follow peaked at 1,895 once (pass b).
- Per frame: view script 13-26 ms, of which people (`agents`) 6-19 ms; sim tick `simprof 300` mean 9.5 ms,
  max 31.9 ms (budget median 3.0, max 12; CPU 94 % at that moment).
- **Method fault.** Without `title=0` the presets measure the title state: `loadurl` from the title leaves
  `on_title` true, so the HUD is hidden and the time is locked (`ov_notitle_a.png` vs `ov_title0_a.png`).
  Interleaved A/B on the overview: title mode 17.0 / 17.5 fps, play mode 14.2 / 15.4 fps (about 12 % lower).

## 2. Loading

| step | measured | note |
|---|---|---|
| to title, first visit (local disk, no network) | **63.7 s** (ready 54.0 s, loader lifts 63.7 s) | add 18-70 s to download 219 MB at 100-25 Mbit/s |
| to title, second visit | 43.0 s | |
| to a new game (`title=0`), shoot.mjs "ready after" | 24.2-40.3 s | the title colony costs about 25-30 s of the boot |
| load showcase_v5 from the title | about 9-10 s frozen (3.5 s + 5.6 s + 2 × 0.6 s gaps) | no feedback, title image frozen |
| load showcase_v5 cold (`title=0`) | 34.2 s, one frame of 24.6 s | then 8 s of black cover |
| Main menu from a game | 4.0-5.4 s frozen (4 runs) | then black, see 3 |

**Loader screen.** The art and glass panel are good (`load_player_2_*.png`). Faults:
- The bar stops at "Downloading the game 85 % 219.2 / 219.2 MB" for 32-53 s. The page main thread is
  blocked: the tip does not change, nothing moves, the text says "downloading" after the download is done.
- The game stages ("Loading the colony", "Building the planet") do not show in the title path; 85 % jumps to 95 %.

## 3. Black screens

- After a load the screen is fully black (RGB 0, HUD too) until the load cover lifts:
  `cov_t0_03/06/09s.png` black, `cov_t0_12s.png` visible; `bk_30s.png` black 30 s after the load (cover lifted
  by 45 s, `boot.cover_s` 5.02). The cover has no text.
- After Main menu: black at 4, 8 and 12 s in 2 of 4 runs (`hitch_player_to_title.png`, `hitch_play_to_title_4s/12s.png`).
  In the other runs the menu shows first at night with a black disc over the centre (`tt_1_after0.png`, `mm_03s.png`).
- 38 of 1,431 shots by the other r42 critics are fully black (most 25-30 s after `loadurl`).

## 4. Hitches when you open windows or change the view (synchronous command cost; machine loaded)

| action | sync ms | longest frame ms |
|---|---|---|
| Rag (J) | 360-440 | 550-667 |
| Colonists | 162-228 | 346-450 |
| Crew (U) | 152-173 | 283-400 |
| Codex / Research | 140-156 / 133-146 | 233-333 |
| Dashboard / Settings / Help | 67-83 / 58-61 / 29-32 | 133-300 |
| select HR office (camera jump) | 12-17 | 517-701 |
| zoom 250 m | 0.2 | 333-684 |
| over the shoulder (V) | 3.6-5.5 | 483-783 |
| person file, roofs toggle, dock tab | 1-26 | 133-283 |
| speed 3 (12 s) | — | 110-138 frames > 50 ms |

## Score

| consistency | appeal | style | score | result |
|---|---|---|---|---|
| 0.40 | 0.38 | 0.60 | **0.46** | **FAIL** |

Consistency is capped at 0.60 by the broken §0 fps and 50 ms budgets.

## What works

- pck 186.2 MB ≤ 200 MB; overview draws ≤ 1,700.
- A new small colony runs at a flat 60 fps (1,200 frames, 0 over 50 ms).
- Loader art, glass panel and tips; the tips name the v5 keys (V, J, U, L, Y) and features.
- The dome follow reached median 59.9 fps in the least loaded run.
- Cheap commands: person file 16 ms, dock tab 1.2 ms, roofs 2-3 ms, shoulder 3-6 ms.
- No crash or lasting hang in 24 browser sessions.

## Fixes (most important first)

1. RENDER + SIM — frame cost: people 6-19 ms and the view 13-26 ms per frame must fall to fit 22 ms; spread the
   sim tick (9.5 ms mean) over frames. Proof: the four presets ≥ 45/45/45/40 fps on an idle PC (CPU < 15 %, no other browsers).
2. RENDER — no frame over 50 ms: stream template loads before a camera jump, zoom or follow start.
3. RENDER + UI — the cover: draw the loader art and "Loading the colony" on it; never more than 5 s black.
4. UI — the loader: when the bytes are complete, say "Starting the engine" and run a CSS animation that does
   not need the main thread; RENDER: yield between boot stages so the stage text updates.
5. RENDER + UI — Main menu: save and install with a visible "Saving / Loading" panel; skip or cover the night
   warm-up (the black disc).
6. UI — keep built screens and refresh them; build long lists lazily. Rag, Colonists, Crew, Codex, Research < 50 ms.
7. RENDER — the title: slow or pause the colony behind the menu (title at 12.7 fps under load).
8. RENDER — presets: use `title=0` and wait for `boot.cover_s` before measuring.
9. SIM — re-measure the tick on an idle PC; the §0 budget is 3.0 ms median.
