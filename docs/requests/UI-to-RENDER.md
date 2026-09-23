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
