# UI → RENDER

Date: 2026-09-24.

## 1. Camera speed setting — `rig.pan_speed`

**What:** a float property on `presentation/camera_rig.gd`, default `1.0`, that multiplies the keyboard
and edge-pan speed (`var speed: float = distance * 0.9 * delta * pan_speed`), and ideally the Q/E turn speed.

**Why:** Paul's brief asks for a camera speed setting. The settings screen already has the slider
(50%–200%, saved as `camera_speed`). `main.apply_settings()` sets it with
`if "pan_speed" in rig: rig.set("pan_speed", value)`, so it starts working the moment the property exists.
Nothing else is needed.

---
**RENDER answer (2026-09-24): done.** `rig.pan_speed` (default 1.0) multiplies keyboard and edge pan speed
and the Q/E turn speed. Also new since the first contract: `view.set_labels_visible(bool)` (world labels
and status badges; they are hidden automatically in `photo_orbit` and while `set_time_override` is active).

**Done (2026-09-24):** `rig.pan_speed` exists; `main.apply_settings()` now sets it directly from the
Camera speed slider. Placement uses only `set_ghost` / `clear_ghost` / `set_link_preview`; the old
ghost nodes are gone from `main.gd`.

---

## 2026-09-24 — version 3 (V3_DESIGN §4.5, §8)

### 2. Camera shake setting — `shake_enabled`

**What:** a bool `shake_enabled` (default true) on `camera_rig.gd` (and on `world_view.gd` if the view
shakes anything itself). When false, `shake()` does nothing and quakes/impacts do not move the camera.

**Why:** §4.5 says the quake shake must respect a settings toggle. Settings → Camera → "Camera shake"
exists now (key `camera_shake`). `main.apply_settings()` sets `shake_enabled` on the rig and the view when
the property exists. **Until then** `main._process` writes `rig._shake = 0.0` every frame while the
setting is off (the rig runs after main, so the frame has no shake). That touches your private variable;
it goes away the moment `shake_enabled` exists.

### 3. `interior <building id>` (automation, §8)

`main.gd` selects the room, moves the camera to it, sets `target_distance` = radius x 2.8 + 8 (14..45 m)
and pitch 58°, and calls `view.open_interior(id)` **if it exists**. Your cutaway already opens the roof
of the selected room, so nothing is required. If you want a better framing (for example a fixed interior
camera), add `open_interior(id)` and it is used.

### 4. Overlay name `hazard`

The minimap has a "Hazard zones" button and the O key cycles `"" → power → water → air → walk →
hazard`. Both call `view.set_overlay("hazard")` (§1 names it `hazard`). The minimap paints the zone
fields itself from `sim.hazards.zone_at`.

### 5. Camera range on the 810 m map (for information)

`main.gd` sets `rig.bounds` to the whole map as before. The minimap view outline now reaches up to
0.9 x the map size (was 320 m), and the minimap can zoom to the colony. I do not touch
`max_distance`; §1 gives zoom-out to about 450 m to you.


---
**RENDER answer (2026-09-24, v3):**
- **2. done.** `rig.shake_enabled` (default true) and `view.shake_enabled`: when false, `shake()` does nothing and
  any running shake stops at once. You can drop the `rig._shake = 0.0` workaround.
- **3. done.** `view.open_interior(id)`: selects the room (its roof and the level parts on it open, the doorway
  top parts hide), jumps the camera to it, distance radius x 2.8 + 8 (14..45 m), pitch 58°.
- **4. done.** `view.set_overlay("hazard")` tints the terrain by the zone fields (meteor red, wind cyan, quake
  violet; only above-average risk is coloured; contour lines at x1.25 and x1.5). It reads
  `sim.world.hazard_at` (or `sim.hazards.zone_at`) once, 8 m per texel.
- **5.** `rig.max_distance` is now 0.56 x map size (454 m on the 810 m map, 200 m on 256 m saves); the camera far
  plane and the fog scale with it.
---

## 2026-09-25 — version 3.1

**Answers (thank you):** shake_enabled, open_interior, overlay `hazard`, max_distance — all used; the UI
workaround that zeroed `rig._shake` is removed. The minimap zone colours now match your overlay (meteor red,
wind cyan, quake violet).

### 6. Frame stalls of about 140 ms while the simulation runs (they make the web audio crackle)

**What I measured** (web build `build/web_ui`, headless Chrome, real GPU, `showcase_v3_late.fhsave`, speed 1,
automation command `spikes` = frames over 100 ms):

| window (20 s each, alternated) | frames over 100 ms |
|---|---|
| HUD off | 4 (142, 139, 144, 140 ms), then 0 |
| HUD on | 1 (134 ms), then 1 (141 ms) |
| paused (speed 0), HUD on | 0 |

The simulation is not the cause: `simprof 300` in the same build = mean 2.3–2.5 ms, max 18.7 ms per tick, no
tick over 50 ms. The HUD is not the cause (same with it hidden). So the stalls come from the view while the colony
moves: my guess is work when a body enters or leaves a room, or a first-time model or material load. Please find
and spread that work.

**Why it matters:** the web build mixes audio on the main thread. `audio/driver/output_latency.web` is now 150 ms
(was the default 50). With 150 ms the new colony has 0 dropouts at 30–42 fps, but the late save still has about
6 dropouts in 20 s (one per stall); 200 ms does not help. Tools: `node tools/ui/audio_glitch_probe.mjs
build/web_<you> --query "load=res://content/saves/showcase_v3_late.fhsave&title=0" --speed 1 --seconds 20` counts
dropouts; `__fh.cmd('spikes')` lists frames over 100 ms since the last call.

### 7. World sounds — `main.audio.world(name, pos)` is live (V3_1 §2.2)

- `var h: int = main.audio.world(name, pos)` — `pos` a Vector3 (world) or a Vector2 (content point). Returns a
  handle, or -1 (unknown name, beyond 120 m, or 3 nearer ones of that name play).
- Loops (`airlock_pump`, `ship_descent`, `storm_loop`) play until `main.audio.world_stop(h)`; they stop by
  themselves after 30 / 40 / 300 s if you forget. `main.audio.world_move(h, pos)` follows a moving ship.
- Names: `door_slide`, `airlock_seal`, `airlock_pump`, `airlock_vent`, `ship_descent`, `ship_touchdown` (also starts
  the `mus_arrival` cue), `ship_takeoff`, `ramp`, `meteor_impact`, `turret_fire`, `quake_rumble`, `storm_loop`,
  plus `airlock` and `construct`. Level: full within 12 m of the camera focus, silent at 120 m.
- Test from the browser: `__fh.cmd('world door_slide <x> <y>')`.
---

## 2026-09-25 — answer to "long frames about 61 s after page load" (UI)

Measured in `build/web_ui` (headless Chrome, real GPU, speed 4) with `__fh.cmd('spikes')`, which now splits each frame
over 50 ms into script time: simulation, `view.sync`, HUD, audio (ambience and music calls).

| moment | frames over 50 ms | sim | view.sync | HUD | audio |
|---|---|---|---|---|---|
| 0–1 s after ready (both saves) | 3 of 96–148 ms | 1–18 | **94–242** | 0–5 | 0 |
| sunset, game time ≈ 354 s of the day (showcase_v31: 70.6–73.5 s after engine start; v3_late: 105–106 s) | 3 of 139–147 ms | 2–14 | 7–13 | 0–2 | 0 |
| 35–70 s after ready, v3_late (day) | 0 | | | | |

- **The ~61 s frames are sunset**, not a timer: both saves stand near dusk, so sunset falls about a minute into play. The
  script parts are small; the rest of the frame is engine work outside scripts.
- **Reproduced without the simulation:** paused, `time 380` (view to night only): one frame of 108 ms the first time,
  none when switched back and forth again. Music switched to night, tension, day while paused (`mus night|tension|day`):
  no frame over 50 ms. So it is first-use night rendering work in the view (night lights or materials, the shader variants
  they need). Please warm the night variants at start, like the flame and dust shaders.
- **Right after ready** `view.sync` itself takes 94–242 ms of wall time in 2 frames (your stats said 10–11 ms; they may
  not count the whole call).
- Checked and not the cause: autosave (every 300 s, none in these windows), minimap texture upload, music load and
  crossfade, ambience loops, HUD refresh, charts.
- **door_slide:** the UI no longer plays it (it played it at the inbound airlock "open" phase); yours in `fx_doors.gd` and
  `fx_airlock.gd` are the only ones now.
**UI note 2026-09-25 (later):** `presentation/world_view.gd:559` `_night_warmup` prints "SCRIPT ERROR: Trying to cast a
freed object." at exit in headless runs (`tools/ui/test_window_bounds.gd`). The tests still pass; it looks like the
warm-up runs after its node is freed.