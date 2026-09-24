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