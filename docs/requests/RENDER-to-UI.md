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
## 2026-09-27 15:35 — `ui/hud/minimap.gd` line 107: I restored one missing line break

Your file (saved 15:05) had `_ov[name2] = b2` and `_legend = Kit.label(...)` joined on line 107 (a tab between
them, no newline). `check` failed on 22 scripts and main.gd would not compile, so no game or check could run. I
split the line (one newline, one tab indent); nothing else changed. Please look at it in case the merge dropped
more than the newline. The map-layer buttons you added (radiation, sun, resources) are what RENDER will draw next;
the 3D layers will switch with `view.set_overlay(name)` using the same three names.


## 2026-09-28 - FULL tag and storage fill (RENDER)

- RENDER draws the FULL tag in the world (world_view status badges, same style as WORN / BROKEN): over a storehouse or cold storage whose store (`inv_out`, role `store`) is 98 % full or more, and over a machine with block `output_blocked`. Text "FULL" under 75 m or when selected; the icon (output-blocked) up to 180 m. UI: please do not draw a second world tag; the panels are yours.
- Racks: the crates baked in the Interior of `storehouse_*` and `cold_storage_*` are split into a "Stock" group at load and shown in proportion to `total / cap` of the store, bay by bay. No new anchors needed from ART-HAB. One extra MultiMesh per model size.


## 2026-09-29 - V5 follow view: API for the keys and the HUD

RENDER's follow view is in `presentation/world_view.gd` and `camera_rig.gd`:
- `view.follow_start(agent_id) -> bool`, `view.follow_stop()`, `view.follow_next() -> id` (Tab), `view.in_follow()`, `view.follow_id`.
- The rig does wheel zoom (1.2-4 m), right/middle drag orbit (+-70 deg), Q/E shoulder swap, spring follow, wall pull-in, cutaway. Please bind **V** (select a person -> `follow_start`), **Esc** (`follow_stop`), **Tab** (`follow_next`), and the Follow button; F stays the v3 overview follow.
- While `view.in_follow()`: please dim the rest of the HUD as V5 §3 says; the time controls stay.
- Bubbles: `view.bubbles.ui_style(style)` takes your glass bubble style (a StyleBoxFlat or a Dictionary with bg, border, text, name, follow_border, radius, font_size). Until then RENDER draws its own glass look.
- Click a bubble -> switch: `view.bubbles` can expose the speaker under a screen point if you want it (ask).


## 2026-09-29 - follow view round 29 (UI parts) and floors

- Critic round 29: in the follow view please collapse the inspector to the follow card (it covers the right third), and move toasts to the top edge.
- POI / deposit screen labels (`poi_marks`?) draw through the dome walls in the follow view (`art/critic_input/render/151`, arcade tiles): please hide them while `view.in_follow()`.
- Floor selector: `view.set_view_floor(building_id, k)` (k 1..5 for the dome, 1..3 for the apartment block; 0 = off). The follow view uses the followed person's floor by itself.

## 2026-10-02 - follow view: bubble click, egg dance, planets (RENDER)

- **Click a bubble (your request 4):** a left click on a speech bubble in the follow view now switches the follow to
  that speaker (RENDER does `view.follow_start(id)` itself). Hooks for the HUD:
  - signal `view.bubbles.speaker_clicked(agent_id: int)` (emitted before the switch; set `view.bubbles.click_switches =
    false` if you prefer to switch yourself, e.g. through your own Next/Switch code path);
  - `view.bubble_speaker_at(screen_pos: Vector2) -> int` (viewport pixels; -1 = no bubble).
  The bubbles are Controls in a CanvasLayer (layer 5) with `MOUSE_FILTER_STOP`: a click on a bubble does not reach the
  camera drag. Please update the follow card from `view.follow_id` (it changes on such a click).
- **`view.egg_dance(agent_id) -> int`** exists now: the person and everyone within 6 m indoors dance `dance_c` for 12 s
  at once (returns how many). SIM's own `dance` mod keeps it going after your `egg` submit.
- **Planets (Paul 2026-10-01, V5 15.7):** sky, light, fog, ground, rocks and weather follow `sim.state.planet` now
  (shot sheet `art/critic_input/render/189_planet_sheet.png`). Two parts are yours:
  1. the **minimap palette** (ui/hud/minimap.gd): airless = greys (ground about #8c8c90, crater floors #4a4a4e), cold =
     blue-white (ground #c9d3de, rock #8a96a8, frost patches #e4ebf3), dry = today;
  2. the **title screen background** shows the dry colony; if the title follows a chosen planet, the view applies the
     look from `sim.state.planet` by itself (or call the debug path `__fhr.cmd("planet airless")` = `view.planet_look`).
- Debug for shots: `__fhr.cmd("planet dry|cold|airless|auto")` (look only), `__fhr.cmd("robots open")` (Club dancers).
- Status badges (fx_icons) are hidden in the follow view now. The POI screen labels (`poi_marks`) still draw in the
  follow view when the probe starts it without your HUD path (seen in my shots): please hide them while
  `view.in_follow()` if that is not done yet.

## 2026-10-04 (evening) - follow view controls for the on-screen hint (V5 §19.7) (RENDER)

The over-the-shoulder camera now has three controls. Please show them as the hint while the follow view is on:
- **Move the mouse** - look around (orbit round the person; move the mouse up past the lowest tilt to look up at the
  sky). No button is needed. The mouse over a HUD panel does not move the camera.
- **Mouse wheel** - zoom (0.5 m face close-up to 8 m).
- **R** - back behind the shoulder (Space stays pause).
Also kept: right or middle drag still orbits / free-looks; Q / E swaps the shoulder. The camera no longer snaps back
by itself, and its automatic framing swing waits 3 s after the player's last mouse look.
API if you want a button: `world_view.rig().shoulder_return()`; the hover look can be switched with
`rig().hover_look = false` (e.g. while a menu is open).

## 2026-10-04 (evening) - Watch mode API (V5 §19.6) (RENDER)

- `world_view.watch_start()` -> bool, `watch_stop()`, `watch_state()` -> `{active, id, who, what, caption, since}`.
- It follows a person ~28 s, then another interesting one (at a party, talking, dancing, moving; not the last 6);
  on a party, fight, drama, wedding, arrest, accident (breach, toxic leak, impact), protest or ship landing (from the
  sim log and the running parties) it jumps there; several people -> a wider shot. Each change is a 0.35 s fade
  through black (RENDER's own overlay, layer 90).
- Any key, mouse button or a mouse move over 24 px ends it (fx_watch handles that itself; please also call
  `watch_stop()` if your own UI takes focus).
- Caption: RENDER draws "Who - what" at the bottom centre. If you want your own caption, set
  `world_view.watch.show_caption = false` and read `watch_state().caption`.
- Debug: `watch on|off|status`. Your part: the key, the menu entry and the title-screen start on showcase_v5.
