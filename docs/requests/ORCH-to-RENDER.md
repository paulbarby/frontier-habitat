# Orchestrator to RENDER

## 2026-10-01 — Paul: people sit inside desks (do after ART-HAB's desk fix)

Evidence: `docs/requests/shots/paul_2026-10-01_desk_seat.webp`. ART-HAB turns the paired desks 180 deg and
moves the seat anchors (ORCH-to-ART-HAB.md). Then: rebake nav grids; check that a seated body is placed on
the chair at the anchor, facing the screen, and never overlaps the desk box (add this to a render check:
seated body capsule vs furniture boxes, every seat anchor of every room type, 0 overlaps).

## 2026-10-01 — Paul: grounding, and more camera freedom in the over-the-shoulder view

1. Grounding: people float when they run. Check the drawn body's foot height against the floor/terrain each
   frame (with ART-NPC's clip fixes); no body may float or sink by more than 1 cm when a foot is planted.
2. Camera freedom: the player must be able to look around freely and see the person: full orbit around the
   person (360 deg, not +-70), wider pitch (from low near the floor to high above), zoom from close face
   shot to about 8 m, a free-look mode that keeps the camera on the person but lets the mouse look anywhere,
   and a smooth return behind the shoulder. Keep the wall rule and the smoothing measured on 2026-10-01
   (re-run tools/render_follow_probe.mjs after the change).
3. Scope change (V5_DESIGN.md §15): a viewer mode is coming. Design the camera code so that a cinematic
   "watch" mode (automatic shots of people and the colony) can be added later.

## 2026-10-01 — Paul: roofs ON in the over-the-shoulder view; an "all roofs off" toggle

1. Over-the-shoulder view: keep every roof and upper wall ON (no cutaway), for an enclosed feel. Today the
   follow view cuts away rooms near the camera, and `_follow_collide` skips walls of open rooms; with roofs
   on, the camera must stay inside the room by the wall rule and under the ceiling (add a ceiling height
   limit per room/floor). Light the interior so it reads with the roof on. Re-run the follow probe.
2. All-roofs-off toggle (Paul and a friend asked for it): one view state that cuts away every roof and upper
   wall in the whole colony at once (the same cutaway rule as today: nothing above 1.40 m except allowed
   parts), in the normal camera; off = today's automatic cutaway. Expose it as `view.set_roofs_off(bool)` and
   a debug command; UI adds the button, key and setting (ORCH-to-UI.md). In the follow view the toggle does
   not apply (roofs stay on), unless Paul asks otherwise. Check perf with all roofs off on showcase_v5.

## 2026-10-01 — Paul: terrain, environment, background and sky must match the planet option

Planets: `dry`, `cold`, `airless` (content/scenarios.json). Paul: "the terrain and environment / background and
sky setting should reflect the different options for environments". Do, per planet:
- `airless`: black sky with sharp stars visible in daylight, no haze or fog, no dust in the air, hard black
  shadows (no sky fill light), grey regolith palette, sharp crater rims, no wind effects (dust, flags,
  particles), Earth/planet or a far moon in the sky optional; sun a hard white disc.
- `cold`: pale cold sky, frost and ice on the ground, snow-dusted rock, blue-white palette, ice fog in
  craters, breath-cold light; frost on structures at night.
- `dry`: today's ochre/rust look, dusty haze, dust devils.
Terrain colour, rock and boulder materials, skybox, sun and ambient light, fog, particle weather, the title
screen background colony and the minimap palette follow the planet. A shot sheet per planet (day, dusk,
night) in art/critic_input/render/ for the critic. Coordinate with SIM (ORCH-to-SIM.md, same date) so effects
follow the planet's hazard table.

## 2026-10-01 (later) — Paul: atmosphere effects inside habitats (over-the-shoulder view)

Evidence: `docs/requests/shots/paul_2026-10-01_storm_indoors.webp` (day 28, follow view of Asha Verrin working
at Refinery 1, indoors: wind-storm streak particles fill the whole screen in front of the camera).
Paul: "atmosphere effects and sounds should not be inside the habitats, esp. on the over-shoulder view; it is
very annoying and disrupting".
Do: weather particles (wind streaks, dust, storm haze, rain-like streaks, dust devils) are never drawn inside
a room or corridor volume, and never between the camera and the person when the camera is indoors. Indoors
the storm shows only through windows/open cutaway sky (and maybe light flicker or a creak, subtle). In the
normal top view, particles over a room's footprint are clipped too (roof on or off). Add a render check: camera
indoors during a storm → 0 weather particles inside room volumes in view. Audio part: ORCH-to-UI.md.

## 2026-10-01 (end of run) — REGRESSION, do first: indoor follow camera jerk 16.4 mm (was 1.79 mm)

Orchestrator probe on build/web_v5preview (commit bdc6276), `render_follow_probe.mjs --cases in1,out1 --secs 15`:
in1 straight: head 0.552 px, cam 16.4 mm (target < 0.5 px, < 2 mm; 1.79 mm before roofs-on); walk cam 12.2 mm;
out1 straight 0.071 px, 0.17 mm (OK). CSV build/web_v5preview_probe/in1.csv: single-frame VERTICAL jumps of
+-90..102 mm (rows 105-110, cut=1, pull rising 0.80 -> 0.83, i.e. while the wall pull-in releases), then
29-45 mm alternating with uneven dt (0.021/0.029 s). Suspects: the hard ceiling clamp
`eye.y = minf(eye.y, minf(_sh_cy - 0.3, cy - 0.12))` and the hard wall clamp (SH_HARD) acting every frame
after the springs (camera_rig.gd ~lines 334-358); the ceiling value steps between room and corridor.
Fix so the final eye is continuous (springs after clamps, or clamps as soft constraints with a hard limit
only for real penetration), keep roofs on and the wall rule, re-run in1/in4/out1/dome1.

## 2026-10-02 — Paul: parties (V5_DESIGN.md §16): idle people walk to each other and talk (face each other,
talk gestures, bubbles); party guests gather, dance (dance clips; robot dancers in the club), toast, stand in
small groups; drama poses (slap, argue, fight, proposal kneel, hug) at the right spot. After SIM's API.

## 2026-10-02 — Paul: HR department → V5_DESIGN.md §17 (your parts as listed there).
