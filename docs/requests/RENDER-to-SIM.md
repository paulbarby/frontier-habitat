# RENDER to SIM

## 2026-09-27 — V4 world: what RENDER reads, and the horizon data (V4 §1, §1.1)

RENDER started the terrain pilot on a placeholder (`presentation/terrain_v4.gd`) because the v4 world is not
published yet. When you publish, please tell me in `SIM-to-RENDER.md`. What RENDER will read:

1. **Heights.** `sim.world.size` (2560), `hstep`, `hn`, `heights` (row-major, `j * hn + i`), `height_at(x, z)`.
   fx_terrain draws any `hstep`; 2 m or 4 m both work. At 2 m (1281² samples) RENDER will build normals per
   chunk, not for the whole map.
2. **Feature lists** (for decals, dust and the map layers): `craters [{x, y, r, depth}]`, `plateaus`,
   `crevices [{pts, w, d}]`, `boulders [{x, y, r}]` (4–20 m; RENDER draws them with the rock models),
   mountain ranges if you keep a list.
3. **Horizon (the same data for solar output and for the shadows, V4 §1.1).** Proposal: SIM owns it, RENDER
   draws it. Algorithm (what RENDER uses now, 0.34 s in GDScript for 321² cells):
   - heights resampled to an **8 m grid**;
   - **8 azimuths**, 0 = +x, 45° steps toward +z;
   - for each azimuth, walk every grid line along that direction from its far end, keep the upper convex hull
     of the points ahead, the tangent to the hull = the horizon;
   - store the elevation angle / 90° as a byte: `horizon: PackedByteArray` (`(j * n + i) * 8 + azimuth`),
     `horizon_step = 8.0`, `horizon_n`, `horizon_origin`;
   - sun visibility = `smoothstep(h − 2°, h + 2°, sun elevation)`, `h` interpolated between the two nearest
     azimuths, bilinear between cells.
   If you publish those four fields, RENDER uses them as they are. If you choose other numbers, tell me the
   layout and RENDER follows. The sun path RENDER draws: `presentation/fx_sky.gd` `update()` (azimuth offset
   −40°, peak elevation 64°, daylight from the planet). Solar output should use the same path.
4. **Radiation** `rad_at(x, z)` and a grid (for the overlay, §5 map layers), **fog of war** as a grid of
   explored cells (8 m or 16 m) with a revision counter, so RENDER uploads it only when it changes.
5. The **start plateau centre** and whether the v3 810 m map sits inside the 2,560 m map (old saves keep their
   own size, V4 §0, so RENDER keeps both paths).

## 2026-09-25 — v3.1 §4.2 outdoor paths (RENDER)

1. RENDER now walks bodies on their own paths: indoor legs through doorways and corridor centre lines, outdoor
   legs straight when clear, else `sim.nav.path_out` (read only), string-pulled with a clearance of
   footprint + 0.3 m (tubes 1.45 m). Please confirm the nav grid blocks every structure footprint + 0.6 m and
   every corridor strip, with the test `v31_outside_paths_clear`.
2. An outdoor target inside a structure footprint is moved just outside it by RENDER. Seen in
   showcase_v3_late: suited colonists' positions inside the bio lab and a wind turbine circle.
3. scene_final (my test save, 53 colonists) queues many colonists at the lander: their sim position is "in" the
   lander while it is full. RENDER draws them on its deck; nothing to do unless you see it in your saves.

## 2026-09-25 — V3.1: an indoor colonist walked across open ground (showcase_v3_late)

Traced for the coordinator (the "indoor clothes outside" case). Colonist 3749, after an inbound cycle at airlock
3769 (375, 405), `where == "in"`, `bld` = habitat 2385 (463, 431). Its sim position goes in a straight line from
(380.3, 406.2) to (444.8, 398.0) in about 60 game seconds. From about (395, 403) on, that line is in no corridor
tube and no room: `region_of` = out at (404.8, 402.0), the nearest corridor centre line is several metres away.
The view used to follow it and drew an indoor body outdoors (63 samples in 10 game minutes).

RENDER now snaps such a target to the nearest corridor centre line within 14 m (`fx_npc_path.indoor_snap`), so
nothing shows. But the sim path itself leaves the corridors. Please check the indoor walk between an airlock and a
far room (probably the straight "wall point → next room centre" leg when the corridors bend or pass a junction).

## 2026-09-27 — V4 terrain on your generator: thanks; crater form and boulder counts (critic round 18)

RENDER now draws `sim.world` directly on v4 maps and takes your sun (`sun_angles`, 32° at noon) and your horizon
layout. For the picture, RENDER bakes the same quantity on the GPU once at load, from `w.heights`, at 8 m cells
(your map: 32 m) with your 13 bearings and your +1.5 m eye height: the shadow edge on a crater floor is then a
few metres wide. Checked against yours (`__fhr.cmd('v4hz x z')`): crater 1 floor view/sim 32.4/34.4, 32.7/34.2,
33.9/31.9, 33.1/32.4, 33.5/33.8 degrees; the start plateau within 1.5°. Solar output stays on your map. If you
want a finer SIM map later, say so and RENDER uses it as it is.

Critic round 18 asks for more crater and boulder form. RENDER paints what it can (rim lip, wall terraces as
normal bends, a rayed apron, floor debris; small cosmetic floor rocks under 2 m). Please consider carrying the
shape in the heights, so walking, the rover and the picture agree:
1. **Deep crater wall:** 2–3 slump terraces (benches 6–12 m wide) on the inner wall, and a rim lip 1–3 m above
   the rim crest; an ejecta apron that rises 1–2 m and falls off over 0.8 r outside the rim.
2. **Boulders on crater floors:** 10–25 rocks of kind 3 (r 1–4 m) on each floor, in `w.rocks`.
3. **Boulder fields:** 30–80 boulders per field with 3–4 giants (r 8–10 m); `terrain_v4.json` has 12–30 now.
4. **Crevices:** RENDER draws the crack from `pts`/`w` (dark core, rocky lips). Nothing needed.

Also: `sim.nav.grid` is null on v4 maps; the walk overlay is empty there until RENDER draws `sim.nav.coarse`
(with the map layers, milestone 3).

## 2026-09-27 — critic round 20: deposit visibility, plateau cliff edges

1. **Deposit rings** (critic: they show everywhere without an overlay). On v4 maps RENDER now shows the rings and
   words only with the overlay named `resources` (UI will switch it). To show a deposit after a survey, please add
   `state.deposits[i].known: bool` (true after a colonist, rover, hopper or the satellite surveys it; start-area
   deposits true). RENDER then draws known deposits without the overlay too.
2. **Plateau cliff outlines** stair-step on the 4 m grid (a disc edge 14 m high between two samples). If the cliff
   ramp in `_plateaus` spans at least 2–3 samples (smoothstep over 8–12 m), the outline becomes smooth; the
   triangles already split along the smaller height change.
3. **Vehicles:** RENDER has the drawing, lights, dust and ART-NPC's crew chain working on view-side demo vehicles
   (`presentation/fx_vehicles.gd`). When you publish vehicles, a record with `{id, kind (rover_small, rover_medium,
   hopper), pos, rot, speed, state (park, drive, hop, fly), crew: [agent ids with seat], cargo, from/to for a hop}`
   is enough; tell me your names and RENDER maps them.

## 2026-09-27 15:00 — the RENDER checks changed after today's 14:16–14:52 sim/content edits: please confirm

On the current tree the two showcase checks give different numbers from this morning (same RENDER code):
- airlock check, 10 min at speed 4: cycles 84 → 111 (showcase_v31) and 74 → 103 (showcase_v3_late);
- path check: scene_final (a) wall 37–39 at an **airlock id 141 that is not in the save** (built during the run),
  furniture 0.24 % (was 0.08 %), (e) 195 (was 152).
- A/B: the same failures with RENDER's new walker rules switched off (`v4i_nogate_noyield`), so they do not come
  from them.
Questions: (1) do the showcase saves now build new structures during the first 10 game minutes (construction,
placement, balance.json changed at 14:16, 14:43 and 14:51)? (2) Is a new airlock record's radius 2.8 m on the
810 m map? RENDER needs a stable save for its gates; if the saves now evolve, please tell me which save to use
(or a `freeze_build` option for tests).

## 2026-09-27 16:45 — what RENDER now reads for layers, fog, reactors, bases

- **Layers** (`view.set_overlay(name)`, the names UI's minimap buttons use): `radiation` (w.rad), `sun` (your
  horizon map + `sun_angles`), `resources` (deposits, `tier`), `explored`. Unsurveyed deposits show only with
  `resources` (your `surveyed` flag is read).
- **Fog of war:** RENDER draws `state.fog = {cell, side, data: PackedByteArray 0..255}` when it exists (dim, grey,
  hazed ground outside explored cells). Tell me your format if it differs.
- **Reactor:** RENDER reads `b.reactor.stage` ("", "warning", "critical", "breach") and `state.rad_zones`
  [{x, y, r, level}]; blast ring radius = max(60 m, 5 × reactor radius) until you publish the content radius.
- **Bases:** `view.jump_base(id)` (debug `base <id|next>`) flies the camera to a base from `sim.bases`.
- Tests: the gates now call `sim.set_freeze_build(true)` and run without the 14 ms step cap (`main.step_cap_us`),
  so both checks give the same numbers run to run.

## 2026-09-27 — depot bays: please use ART-HAB's `Anchor_Bay_<i>` positions

RENDER now draws a vehicle parked at a depot bay at ART-HAB's `Anchor_Bay_<i>` (inside the hangar, facing out
through its door; `rover_depot_l`: x −1.85, z +5.0 / +0.3 / −4.7, +X out; `_m`: bays 0 and 1). SIM's `bays()` puts
them 7 m apart in a row radius + 5 m in front of the depot, so the drawn vehicle and SIM's position differ by
about 10 m: a colonist walks to SIM's board point outside and then climbs into a vehicle drawn inside the hangar
(the view hides the jump behind the step-up clip, but the walk ends in the wrong place). Please place the bays at
the model anchors (rotated and scaled with the depot record), with the board point beside the vehicle on the
door side. Tell me when it is in; RENDER then drops its own override.


## 2026-09-27 - debug `reactor_stage breach` does not breach while the core has coolant

- `debug_stage` sets `heat = stage_breach` (100). The next `_reactor_second` adds `heat_rate` (negative with coolant) BEFORE `stage_of`, so the heat is under 100 and the stage stays `critical`. Same cause: each debug stage shows 1 s late or not at all when it is exactly on its threshold.
- Seen on `content/saves/showcase_v4.fhsave`, reactor 3830: warning -> critical, never breach in 45 s at speed 4.
- Request: make the debug stage set the heat a margin over the threshold (for example +5), or check the stage before cooling on that second, or add `reactor_stage breach` as a direct call of `_breach_reactor`.
- RENDER's probe (`tools/render_v4_showcase_probe.gd`) sets `rx.heat = 130` one second after the command as a work-round. With that, `reactor_breach` logs, the 140 m rad zone appears and the view explodes. The view path is proven; only the debug command is short.


## 2026-09-28 - two log entries without the entity, and a parking spot on a 30 deg slope

1. `reactor_breach` and `unstable_blast` are logged with `ents = []` (`sim/reactors.gd` `_breach_reactor` and `_unstable_second`). The view needs the structure to place the explosion. RENDER now uses the risky structure of that def that disappeared in the same sync, but please log `[int(b["id"])]` as the first entity, as `toxic_leak` and `satellite_launched` do.
2. `showcase_v4.fhsave`: expedition rover (view id 2) is parked at (1933, 752) on the crater rim flank; the ground under it is 30 deg nose-up, 7.5 deg roll. It reads as a rover tipping over. RENDER now caps the body tilt at 24 deg, but a parking spot (and a stop at the end of a route) should be on ground under about 15 deg. Can `nearest_walkable` for a vehicle stop prefer a flat cell?


## 2026-09-28 - an outside colonist walks through a corridor (Frontier game)

- `tools/render_path_check.gd v4` on `build/web_render/frontier_game.fhsave` (`tools/render_frontier_save.gd 2 1001`: new `frontier` game, reference campaign `all`, 2 days): colonist 98, `where = out`, SIM position (1328.3, 1301.7) then (1331.8, 1301.1) is inside a corridor tube (2 samples, 7 frames apart). The drawn body follows SIM's path, so the crossing is in SIM's route.
- Request: outside routes should not cross a corridor tube on the v4 map (or tell RENDER if a crossing point exists by design, and where, so the view can draw a step-over).
- For information: on `showcase_v4` the path check is clean (wall 0, outside 0, slide 0, teleport 0).
- Critic round 22 asked whether the 40 ms average processing at speed 4 on a new Frontier game is the sim. It is not: measured per frame at speed 4 on a new Frontier game, the sim steps take 0.19 ms, the view 1.24 ms, the HUD 0.08 ms (GPU build, 60 fps). The 40 ms figure is Godot's whole-frame process time; with software WebGL (SwiftShader) it is 700 ms. No action for SIM.


## 2026-09-29 - V5: talks() cost and the once-a-second tick spike

- `sim.social.talks()` rebuilds on every new tick. In the web build (`showcase_v3_late`, 66 people) one `talks_near` call costs **26-28 ms**. RENDER now asks once a second, but SIM's own `tick_second` also calls `talks()`.
- `simprof 100` on that save: mean **7.4 ms per tick**, every 10th tick (the once-a-second work) **51-66 ms**. V5 budget: 3.0 ms median, no tick over 12 ms. The spike shows as 60-90 ms frames once per game second at speed 1 (`spikes`: `sim65`, `sim71`...). Machine was loaded (about 20 % CPU: Blender, Python), so absolute numbers are high, but the ratio stands.
- Request: build talks in `tick_second` (or when a talk window starts) and let `talks()`/`talks_near()` return the stored list, so a caller pays nothing.
- In the 18-person `showcase_v4` `talks_near` round the followed person returned 0 talks for most of 60 s; the follow view needs visible conversations in rooms with 2+ people (maybe a higher chance near the followed person, or in canteens and rec rooms). RENDER uses `talks_near` fields `speaker`, `line`, `emote`, `started`, `line_index` (`LINE_TICKS` = 40 assumed; please expose it as a function if it changes).

## 2026-10-02 - super dome floor heights; anchors per floor (RENDER)

- **Dome floors:** content `super_dome.floor_height` is 6, so `floors.height_of` gives 0 / 6 / 12 / 18 / 24 m. ART-B's
  model has its floor tops at **0.30, 5.30, 9.50, 13.70, 17.90 m** (plaza, then 5.0 and 4.2 m apart; the lift stops in
  the view are 0, 5.0, 9.2, 13.4, 17.6). People on floor 4 stood 6.2 m above their floor. RENDER now places people
  at the model's floor tops (from the anchor heights), so nothing is needed for the picture; but anything of yours that
  uses metres (lift time per metre, a fall height, a camera height you pass to UI) is off. Please set
  `floor_height` to 4.2 and add a `floor_tops` list `[0.3, 5.3, 9.5, 13.7, 17.9]` if you want exact numbers.
- **Dome anchors:** the dome's anchors carry the venue in their names (Seat_cafe_3, Work_bar_0, Bed_3_2_1, Plaza_4);
  SIM's seat / work / bed index `i` for the dome is mapped by RENDER to the i-th anchor of that kind on the slot's floor
  (`floors.slot_floor`), sorted by name. If you want people at their venue's own seats, put the venue id in
  `agent.use` (e.g. `use.venue = "cafe"`) and I use `Seat_<venue>_<k>`.
- **Children's bunks:** `child_bed` slot `k` is drawn at the unit's bunk (`Bed_4u+2`, `Bed_4u+3`) and `bed` slot `i` at
  the parents' beds (`Bed_4u`, `Bed_4u+1`), from `floors.units(b)` (adult beds then bunks per unit). Before, adults
  were drawn in the bunks of the family tube.

## 2026-10-03 (later) - frame time at 134 people: SIM is small; one function to look at (RENDER)

Web build, showcase_v5 (134 people), follow view indoors, `split` (main.gd, mean ms per frame over 15-20 s):
sim 0.9-2.3 ms (step_ms 4-6.5 ms per tick at 10 ticks/s), view 9.8-21 ms, hud 0.2-0.4 ms, frame 21-41 ms; with
drawing off (`render 0`) the frame was 18.8 ms. The main costs were mine (bodies animated and drawn behind walls,
every structure batch drawn indoors, path planning): fixed in fx_npc / fx_instancer / fx_npc_path. No UI cost.

One SIM function in the long frames: **`sim.nav.path_out(a, b)`** (called by fx_npc_path.out_path for a body's
outdoor leg) took up to **22 ms natively** for one call (about 50-60 ms in the web build) in showcase_v5, for short
legs near the dome (e.g. (1167.9, 1302.4) -> (1172.1, 1302.6), y 11.2: bodies on the dome floor whose region reads
"out"). 12 calls in 30 s, 25.8 ms in all, so the mean is fine; the single calls make the spikes. Could path_out
cap its search (an expansion limit, or a quick fail when a and b are inside the same structure footprint)?
