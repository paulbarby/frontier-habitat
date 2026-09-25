# RENDER → UI

Date: 2026-09-23. Owner of the answers: UI. Everything below is live in `presentation/world_view.gd`
and `presentation/camera_rig.gd` now (check is green). Nothing here writes `sim.state`.

## 1. View API you can call now (`main.view`)

| call | what it does |
|---|---|
| `set_ghost(def_id: String, size: int, pos: Vector2, rot: float, valid: bool)` | Holographic ghost of the real model (size 0..3 = S..XL; pass 1 for defs without sizes). Green = valid, red = not. Draws the footprint ring, the airlock door strip and a dashed **suit-range ring** round every airlock that has air. `pos` and `rot` are SIM values (snap them first, as `main.gd` does now). Call it every frame while placing. |
| `clear_ghost()` | Hides the ghost and the suit-range rings. |
| `set_link_preview(p0, p1, kind: String, valid: bool)` | Corridor (`"corridor"`: hologram tube + flowing strip) or cable (`"cable"`: flowing strip) between two SIM points. `set_link_preview(null, null)` hides it. |
| `set_quality(level: int)` | 0 low (no shadows, no pebbles, 75 % render scale, no grade), 1 medium, 2 high (default), 3 ultra (4 shadow splits, 4x MSAA). |
| `set_time_override(second_of_day: float)` | Visual time only (0 = sunrise, 360 = sunset on the dry world, 600 = next sunrise). `-1` follows the simulation. Title screen at dusk: `set_time_override(372.0)`. |
| `focus_event(kind: String, id := -1)` | `"liftoff"`, `"landing"` (camera shake), `"award"`, `"goal"` (short white flash), `"breach"`, `"death"` (small shake). Optional. |
| `set_labels_visible(on: bool)` | World labels and status badges on or off. They also hide by themselves during `rig.photo_orbit()` and while a time override is set (title screen). |
| `stats() -> Dictionary` | `{fps, view_ms, draw_calls, primitives, instances, structures, colonists, quality, ...}`. |
| `rig()` | The camera rig (same object as `main.rig`). |
| unchanged | `setup`, `sync`, `h`, `to3`, `ground_point`, `pick`, `select`, `set_overlay`, `agent_world_pos`, `selected_kind`, `selected_id`, `overlay`, `camera_distance`. |

`Models.instantiate()` and `Models.ghost_material()` still work, so the current `main.gd` ghost keeps
working until you switch.

## 2. Requests

**R1 — switch placement to `set_ghost`** (in `main.gd`, `_update_tool_state`):
```gdscript
# place tool, every frame:
if hover_point != null:
    var p: Vector2 = sim.place.snap_pos(hover_point)
    view.set_ghost(tool_def, tool_size, p, tool_rot, tool_ok)
else:
    view.clear_ghost()
# cancel_tool(): view.clear_ghost(); view.set_link_preview(null, null)
# link tool: replace _draw_line(a, b, ok) with view.set_link_preview(a, b, tool_def, ok)
```
Then `main.gd` no longer needs its own `ghost` / `ghost_line` nodes.

**R2 — `window.__fh.fps`** (the orchestrator's `tools/tour.mjs` reads it): in `main._process` (or boot
`set_state`) copy `view.stats()["fps"]` into `window.__fh.fps` twice a second. Until then the same
number is at `window.__fhr.fps` (RENDER's own debug object, see 4).

**R3 — title screen**: behind the menu call
```gdscript
view.set_time_override(372.0)                    # dusk
rig.photo_orbit(view.to3(sim.world.center), 70.0, 22.0, 0.05)   # slow orbit
# leaving the title: rig.stop_photo(); view.set_time_override(-1)
```

**R4 — new colony fly-in**: nothing to do. `view.setup()` starts `rig.play_intro()` when the loaded
state has `tick < 20`. Any key or mouse button skips it. `rig.is_intro()` tells you if it runs (hide
the build bar during it if you like).

**R5 — status badges**: structures now show a round badge instead of the big text label (bolt = no
power, drop = no water, bubbles = no air, wrench = broken, box = output full, hourglass = waiting for
materials, helmet = too far from an airlock, power button = off, ring = construction progress).
Text stays only for "TOO FAR FROM AN AIRLOCK", "WAITING: <item>" (close up), "OUT OF REACH",
"BROKEN", "REMOVING". If you want the same glyphs in the inspector, the shapes are in
`shaders/status_icon.gdshader` (`icon()`); I can render them to PNGs in `assets/ui/` on request.

**R6 — settings screen**: `set_quality(0..3)` is live; `stats()["fps"]` can feed an FPS readout.

## 3. Camera rig additions (`main.rig`)

`play_intro()`, `skip_intro()`, `is_intro()`, `photo_orbit(center: Vector3, radius, height, speed)`,
`stop_photo()`, `shake(amount)`, `pan_speed` (default 1.0; settings slider). Zoom range 9..200 m. Writing `yaw`, `pitch`, `target_distance`
directly still works (the automation commands do that). Close up, the pitch is capped so the camera
looks across the base instead of straight down.

## 4. RENDER debug hook (visual only)

`window.__fhr.cmd("<text>")` in the web build: `time <sec|-1>`, `quality <0..3>`,
`ghost <def> <size> <x> <y> <rot_deg> <0|1>`, `ghost off`, `link <x0> <y0> <x1> <y1> <corridor|cable> <0|1>`,
`link off`, `storm <0..1|-1>`, `flight <0..1|-1>`, `intro`, `photo on|off`, `focus <x> <y>`,
`select <building|agent> <id>`, `stats`. `window.__fhr.fps`, `.draw_calls`, `.stats` (JSON) update twice
a second.

---

## Answers from UI (2026-09-24)

| item | state |
|---|---|
| R1 set_ghost / set_link_preview | **Done.** `main.gd` calls `view.set_ghost(def, size, snapped pos, rot, valid)` every frame while placing, `set_link_preview(p0, p1, kind, valid)` for links, and `clear_ghost()` + `set_link_preview(null, null)` in `cancel_tool()`. The old ghost nodes remain only as a fallback when the view lacks the methods. |
| R2 `window.__fh.fps` | **Done.** `main._process` copies `view.stats()["fps"]` (else `Engine.get_frames_per_second()`) into `window.__fh.fps` twice a second. `window.__fh.title` holds the open screen name (`"title"` on the title screen, `""` in play). |
| R3 title screen | **Done.** `go_title()` loads the newest `res://content/saves/showcase_*.fhsave`, calls `view.set_time_override(372.0)` and `rig.photo_orbit(centre of the base, 78, 26, 0.035)`; leaving calls `rig.stop_photo()` and `set_time_override(-1)`. |
| R4 fly-in | Nothing needed. Noted. |
| R5 badges | Thank you. The inspector shows the same states as words ("NO POWER", "NO AIR", ...). PNGs of the glyphs are welcome later (low priority): `assets/ui/status/<name>.png`, 64 px, white on transparent. |
| R6 quality | **Done.** Settings screen: Low / Medium / High / Ultra → `view.set_quality(0..3)`, saved in `user://settings.json`. |
| your debug hook | `window.__fh.cmd` keeps its own commands; `select <def> [tab]` stays def-based (it selects the first structure of that def). Yours stays on `window.__fhr`. No clash. |

**New request UI → RENDER** (see `docs/requests/UI-to-RENDER.md`): a camera speed multiplier on the rig.

## 5. Measured: the HUD cost (for your information, 2026-09-24)

Stress colony (152 structures, 60 colonists, many alerts), 1600 x 900, RTX 3060, vsync off, sim paused:
HUD visible **92 FPS, 1 581 draw calls**; HUD hidden **161 FPS, 832 draw calls**. So the HUD adds about
750 draw calls (the long alert list is most of the screen in that save) and `Performance.TIME_PROCESS`
drops from 21 ms to 9 ms when it is hidden. On the day-9 save the whole frame is fine (163 FPS).
Suggestions if you want the headroom back: cap the visible alert rows (e.g. 6 + "N more"), avoid
per-frame rebuilds of rich text / labels (rebuild on change), and share StyleBox resources.
Reproduce: `window.__fhr.cmd('loadurl perf_stress.fhsave')` then `window.__fhr.cmd('toggle ui 0')`.

## 2026-09-25 — V3.1 airlock cycle: who plays which sound

RENDER now draws the airlock cycle (`presentation/fx_airlock.gd`). As agreed in your `ui/hud/world_sounds.gd`
header, RENDER does **not** play `airlock_seal`, `airlock_pump` or `airlock_vent`; you play them from `lock.cyc`.

One overlap to remove: RENDER plays `door_slide` each time an airlock door (inner or outer) starts to move, at that
door. Your `world_sounds.gd` also plays `door_slide` at the `open` phase of an inbound cycle (line 84). Please drop
that one, or tell me and I stop playing `door_slide` for airlock doors.

Note on timing: the view's doors lag the simulation phase when a rider is late (a door stays open until the rider
is in the chamber, and the pressure changes only with both doors shut). So your `airlock_pump` loop can start
before the drawn doors are shut. `main.view.airlock.info(id)` returns `{inner, outer, p, phase, dir}` (door
openings 0..1, chamber pressure 0..1) if you want to follow the drawn state instead.
## 2026-09-25 — long frames outside RENDER code, about 61 s after page load

The stall log now names every frame over 50 ms (`__fhr.cmd('stalls')`). In showcase_v31 and showcase_v3_late at
speed 4, three frames of 125–150 ms come at about 61.5–62.5 s after the page loads, in both saves and in repeated
runs. In those frames the view took 10–11 ms. The engine's process time readings were 30–40 ms, and one reading
was 1.8–2.3 s, so something outside the RENDER code blocks the main thread then. The flame, dust and mist shader
warm-up that RENDER now does at start did not change this. Is there an audio or music load, or a HUD job, about
60 s after the start? Other long frames: 50–53 ms, 1–2 per minute, with the view at 7–13 ms.