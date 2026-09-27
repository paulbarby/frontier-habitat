# SIM → RENDER

## 2026-09-24 — v3 data for the view (all live in `sim/`)

### Map (V3_DESIGN §1)
- New games: `sim.world.size` 810 (`state.map_size`), `hstep` 2 m, `hn` 406 height samples per side,
  `sim.world.margin` 8. Old saves: 256 m, margin 4 (use `world.size`, never a constant).
- World features for decals and dressing (empty on 256 m maps):
  `world.ridges [{x0, y0, x1, y1, w, h}]`, `world.canyons [{pts: [Vector2], w, d}]`,
  `world.craters [{x, y, r}]` (terrain bowls), `world.flats [{x, y, r}]` (silicate flats),
  `world.basin {x, y, r}` (impact basin), `world.fault {x0, y0, x1, y1}` (fault line).
  Deposits: `state.deposits[i].exotic == true` marks an **exotic field** (violet crystals).
- Hazard overlay "hazard": `sim.world.hazard_at(pos)` → `{meteor, wind, quake}` 0.5..2.0, or the raw
  grids `world.hz_meteor / hz_wind / hz_quake` (PackedFloat32Array, `hz_n` × `hz_n`, spacing
  `hz_step` 16 m).
- World generation takes about 0.2–0.26 s on this PC (desktop); the nav build 25 ms.

### Furniture use (§6)
- `agent.use` / `sim.agents.use_of(id)` → `{kind, b, i, pose, act}` or `{}`.
  kind bed | seat | work | stand | service; pose stand | sit | lie | kneel;
  act sleep | eat | relax | work | repair | heal | talk | idle.
  `i` = anchor index; **-1 = every anchor of that kind is taken: use your standing ring (not a
  missing anchor — do not log it)**. For `service` (outside) `i` can be 0, 1, 2… (several people at
  one Anchor_Service: offset them). A survey of a fragment site is `service` with `b` = -1: kneel at
  the colonist's own position.
- Greenhouse / fungus farm: `work` index `i` = the tray index.
- Counts per size: `sim.sizes.furniture(def_id, size)` (table in `SIM-to-ART-HAB.md`).
- `use` changes only when a plan step starts or ends. A colonist walking has `{}`.

### Hazards (§4.5)
- Events: `sim.hazards.forecast()` (detected, not started), `sim.hazards.active()` (now). Rows have
  `kind, pos, radius, severity, eta_s, end_s, phase, whole_map`, `path` (dust devil: start and end;
  the devil's current spot is the event's `pos` while active), `strikes` (meteor shower:
  `[{eta_s, pos, r, done}]`). A meteor's `eta_s` counts down to impact: draw the target ring while
  forecast and the streak for the last 3 s.
- Impacts: `sim.hazards.craters()` → `[{x, y, r, tick}]` (permanent crater decals, newest last, max 80).
  Fragment piles: ground piles with `inventory.fragment == true`.
- Interceptions: log code `hazard_intercepted`; `sim.hazards.event(id).hits` has `{turret, pos}` for
  each shot (turret id + where the meteor burst).
- Weather: `state.env.solar_mult`, `state.env.speed_mult`, `state.env.wind_mult` (1.8 in a wind storm:
  spin the rotors up). `state.events.storm` is still kept in its v2 shape for the dust storm.
- Quake: an active `quake` event lasts `shake_s` (6 s): shake the camera then; crack decals at
  corridors with `breach == true`.
- Solar flare: active `solar_flare` event → aurora and grade; buildings with `trip == true` are off.
- Dust devil: active `dust_devil` → turning column at the event `pos`; solar arrays with `dust == true`.
- Breakdown: building `state == "broken"` and `sim.hazards.info(id).broken_by_wear` → sparks, smoke,
  a fault icon (`fault`: mechanical / electrical / seal).
- Breach: building `breach == true` (rooms and corridors) → white air jet.
- Turret: `meteor_turret` (exterior, one size). Charge `b.charge` (0..`charge_cap`), range
  `sim.hazards.info(id).range`.

## 2026-09-24 — version-3 showcase saves (810 m map, hazards "normal")

Made by `node tools/godot.mjs script res://tests/make_showcase_saves.gd` (seed 1001). Load with the
boot param `load=res://content/saves/<file>`. The v2 saves (`showcase_early/mid/late/day9`, 256 m) stay.

- `content/saves/showcase_v3_mid.fhsave` — day 13.1, 26 colonists, 93 structures: research lab and
  assembler, industry chain, a level-3 and an L structure, past hazards (craters, fragment piles).
- `content/saves/showcase_v3_late.fhsave` — day 25.0, 66 colonists, 141 structures, every room type
  (cantina, bio-lab, fungus farm, algae bioreactor, recycler, atmosphere processor, two research
  assemblers, XL habitats …), a meteor turret, the forward airlock outpost at the Meridian (hull done,
  stage 2), fragment sites (one far out, from a meteor at 190 m), Refinery 1 at 80 % of its failure
  threshold (in `sim.hazards.at_risk()`), and one breached corridor (Corridor 42). Technicians start to
  maintain and seal within about a minute of play, so shoot at speed 0 or right after the load.
  Part of this colony is set-up, not play (placed finished, one supply pod of rations and water).

## 2026-09-24 — answers to CRITIC round 6 (two colonists at one bed; terrain through floors)

### 1. Furniture slots are unique in the sim (checked)
New test `long_v3_use_slots_unique`: every tick of a 10-day hazard run ("hard", reference campaign)
and 6000 ticks from each v3 showcase save — 72,000 ticks — no two living colonists hold the same
`(use.b, use.kind, use.i)` with `i >= 0`. Habitat 1 (id 51) in `showcase_v3_late` at load: Yara Castell
`{bed, 51, i 2, lie, sleep}`, Marek Dufour `{stand, 51, i 0, stand, idle}` (drinking); no one else.
So a second body on one bed comes from the view. Things to check on your side:
- place the body only from `use` (not from the colonist's `pos` or a ring slot) while `use` is not `{}`;
- a colonist whose `use` changed from bed to `{}` (got up) must leave the anchor at once;
- `i == -1` means "no free anchor of that kind": the sim then already sets `kind: "stand"` (pose may
  stay `"lie"` for a sleeper in the lander overflow — never put it on a bed anchor).

### 2. Ground height: the rule and the numbers
- **The sim never flattens ground for a structure**, in v2 or in v3. `sim.world.height_at(x, y)`
  is the only terrain height and it is the same function as in v2 (bilinear on the 2 m grid;
  `hstep` 2, `hn` = size / 2 + 1 = 406 on the 810 m map). The heightfield never changes in a game.
- Placement only refuses slopes: rooms `slope_over(pos, r) <= 0.22` (max minus min height over the
  diameter), exteriors <= 0.30. So in v2 a room could stand on up to 0.22 x diameter of height
  difference; the round base (wall to 1.4 m) hid that.
- **On the 810 m map the start plateau is exactly flat** to 125 m from the lander (blend to 175 m).
  Measured with `tests/dev/ground_check.gd` on both v3 showcase saves: all 141 (late) and 93 (mid)
  structures and corridors have **0.000 m** height range under the footprint; every one stands at
  height 0.637 m. Habitat 1 (51), Habitat 2 (1821) and Junction 1 (3831) are 30, 47 and 16 m from the
  lander: 0.000 m range.
- So terrain through a floor on the plateau is not in the sim heightfield. Likely causes in the view:
  a detail displacement in the terrain shader (quality >= 2), a chunk LOD whose vertices are not on the
  2 m grid, the heightmap texture sampled with an offset (half a texel = 1 m), or the floor top placed
  below `height_at(centre) + 0.14`. A flat 0.637 m plateau with any displacement above ~0.1 m will show
  through a 0.14 m floor.
- Suggestion (your call): no displacement inside a structure footprint (or clamp the terrain to
  `height_at(centre) - 0.05` under every room disc and corridor capsule; `b.pos`, `b.radius`,
  `b.p0/p1`, corridor radius 1.2 m).

## 2026-09-25 — v3.1: airlock cycle phases (V3_1_DESIGN §5.2) are live

- `state.buildings[id].lock.cyc` (airlocks and the lander hatch; `{}` while idle) now has
  `phase` ∈ `enter`, `seal`, `pump`, `open`, `exit` and `pt` (seconds left in that phase), besides
  `agents` (riders), `dir` ("in" = coming in from outside, "out" = going out), `t` (seconds left in
  the cycle) and `total` (cycle length). The phase is updated every tick.
- Shares of the cycle: `balance.airlock_phases` = [0.15, 0.1, 0.5, 0.1, 0.15]. At 10 s a cycle is
  enter 1.5 s, seal 1.0 s, pump 5.0 s, open 1.0 s, exit 1.5 s; an unpowered airlock takes 20 s,
  the same shares. Cycle length did not change. Riders per cycle: `sim.agents.lock_slots(b)` (size M 2,
  size L 4, the lander hatch 2; see the airlock sizes section below).
- `dir "out"`: `pump` lets the air out (amber → red). `dir "in"`: `pump` fills the chamber (→ green).
  Riders are inside the airlock (`agent.where == "lock"`, `agent.bld` = the airlock) for the whole
  cycle. At the end of `exit` an inbound rider is at the airlock centre (`b.pos`) inside and an
  outbound rider at `sim.nav.door_pos(b)` (1.6 m outside the outer wall, on the door axis; was 1.3 m).
- Read helper: `sim.agents.lock_info(id)` → `{cycling, dir, phase, pt, t, total, riders, waiting_in,
  waiting_out}`.
- Queue: `lock.queue` = `[{a, dir}]`, people waiting (inbound ones stand outside).

## 2026-09-25 — v3.1 §4.2 outside paths: what the sim does, and what it found (corrected)

This replaces my first text of today, which said the grid blocks footprint + 0.6 m. That version was
built and measured, and it failed: see "Why not solid + 0.6 m".

- **Blocked cells** (the walking grid, 1 m cells): a cell is solid when its centre is within a started
  structure's footprint + 0.3 m, a corridor tube (radius 1.2 m) + 0.3 m, or the wreck + 0.3 m. A body
  walks on cell centres and on straight lines between open cells, so its centre stays at least about
  0.2 m outside every footprint and tube. (v3.0: the discs were 0.2 m SMALLER than the footprint, so a
  path could run inside a wall.)
- **Clearance band:** the next 0.6 m (`balance.nav_clearance`) costs 8 times as much to walk
  (`nav_clearance_weight`). Paths keep 0.6 m from walls wherever the ground allows. A gap narrower than
  that stays open. A path shortcut never crosses the band unless it starts or ends in it, and never
  passes a band cell that touches a solid cell.
- **Porch:** 2.5 m deep, 3.2 m wide in front of every airlock outer door costs 12 times as much
  (`porch_length`, `porch_half_width`, `porch_weight`). Paths go round a porch unless they use that door.
  Placement keeps a 3.5 m strip there free (see SIM-to-UI, porch zone).
- **Points:** outdoor access points at radius + 1.6 m (corridor: 2.8 m from the centre line); an airlock's
  outer door point `sim.nav.door_pos(b)` at radius + 1.6 m (was + 1.3 m).
- **Construction start:** a site with all its materials waits until nobody outside stands on its
  footprint (or corridor tube), at most 60 s (`balance.site_clear_wait_s`). So a structure no longer
  rises round a colonist.
- **Why not solid + 0.6 m:** placement allows 0.6 m between two structures, so a solid clearance closes
  every such gap. Measured: sites became unreachable and settlers stopped (a13: 8 colonists on day 13
  instead of 26); in one variant 5 colonists died outside with no way back, and the long campaign colony
  died. The clearance is therefore a walking cost, not a wall. This differs from the words of
  V3_1_DESIGN 4.2; the aim (no body inside a structure) holds.
- **Test `v31_outside_paths_clear`:** 8 days of the reference campaign, sampled every 0.5 s (9,600
  samples, about 17,500 samples of bodies outside): no body inside a footprint, a corridor tube or a
  blocked path cell; every footprint + 0.3 m is solid and every clearance band is weighted.
- **Sim positions that are not a walk** (animate them, V3_1_DESIGN 4.3):
  1. airlock cycle end: inbound riders jump to the airlock centre `b.pos` (inside); outbound to
     `door_pos(b)` (outside). During the cycle `agent.where == "lock"` and `agent.pos` does not move.
  2. a colonist outside who stands in a cell that became solid (a site that waited 60 s, rare) moves
     to the nearest open cell (up to about 5 m). A colonist outside whom new structures closed in (no walk to
     an airlock with air) moves up to 15 m to an open cell with a way back (stat `closed_in_moves`).
  3. visitors appear at the pad edge (`sim.nav.best_access(pad, colony centre)`) when a ship lands and
     disappear from `state.agents` when they board.
  4. `put_inside`/`put_outside` in tests only; loading a save (positions are exact, no jump).
  5. inside a room the sim walks straight lines: point → wall point on the line to the next room's
     centre → corridor → wall point → the room centre (when it crosses a room) → target. It knows no
     furniture; the inside path round furniture is yours (4.1).
- New airlocks are M (3.4 m) or L (4.0 m); old ones keep 2.8 m. Landing pads are 11.5 m (old ones keep
  9.0 m). Use `b.radius`, never the content radius, for a built structure.

## 2026-09-25 — v3.1 ships and visitors: what to draw

- `sim.traffic.ships()` rows: `{id, kind, phase, pad, pad_pos, t_s, ...}`. `landing`: `t_s` counts
  down the 20 s descent; `landed`; `boarding`; `takeoff`: `t_s` counts down 15 s. The pad building
  has `ship` = the arrival id from the start of `landing` to the end of `takeoff`.
- Visitors are agents with `kind == "visitor"` and `vkind` (trader, shuttle, liner = tourist, medical =
  patient, science, inspector); dress them by `vkind`. They use airlocks, rooms and `use` slots like
  colonists. A visitor who boards is REMOVED from `state.agents` (fade it out at the pad).
- Bought goods appear as a ground pile next to the pad; sold goods go into an inventory with role
  `trade` owned by the pad (no pile).

## 2026-09-25 — v3.1 showcase save and airlock sizes (for the path check and the pilots)

- `content/saves/showcase_v31.fhsave` (schema 4; made by `tests/make_showcase_v31.gd` from
  `showcase_v3_late`): day 25.2, 66 colonists, two landing pads (Landing pad 1 and 5, 11.5 m), a trader
  and a tourist liner **landed**, 6 visitors, 3 tourists in a cantina, an airlock in phase `pump` at the
  moment of the save. Its airlocks are the old 2.8 m ones (the save is from before 3.1). Credits 600
  (set up by the maker so a purchase can be shown). Test `v31_showcase_save`, `v31_showcase_purchase`.
- Airlock sizes: M radius 3.4 m (2 riders), L radius 4.0 m (4 riders); an old airlock record keeps
  2.8 m and 2 riders. Pick the model by `b.radius` (2.8 → `airlock.glb`) or by `b.size` (1 = M, 2 = L)
  for new ones. Riders: `sim.agents.lock_slots(b)`; `lock.cyc.agents` can now hold 4.
- Porch zones for drawing: `sim.place.door_strips()` → `[{id, p0, p1, half_width, porch_length}]`.

## 2026-09-25 — answer: the indoor walk across open ground (your report of today) is fixed

- Cause: while a body walks an indoor leg, `agent.bld` names the room the walk goes TO. When the plan was
  made again mid-walk (a new job, a changed walking map), the new walk started "inside" that destination
  room at the body's real position, so the first leg was a straight line from the corridor near airlock
  3769 to a wall point of Habitat 3 (2385), across open ground. Colonist 3749 in `showcase_v3_late` is
  exactly this case (reproduced at tick 147576).
- Fix: the sim keeps `agent.at = [room id, position]` = the room under the body (the room of the last
  waypoint reached; valid only at that exact position), and plans start there. An indoor walk that starts
  in a corridor walks along the corridor to the nearer useful end first (`at[2]` = the room at the
  corridor's other end). **Changed for you:** while walking indoors `agent.bld` is now the room of the
  last waypoint reached (the room the body is in, or the corridor out of it), no longer the destination.
  A target point outside its room (an old pile put down under the old rule) is walked to inside the room.
- Test `v31_indoor_walks_stay_indoors`: every tick of 4 days of the reference campaign and 6000 ticks of
  `showcase_v3_late`, every body with `where == "in"` is inside a room footprint or a corridor tube (1.2 m).
  Without the fix it fails on both. You can remove `indoor_snap` or keep it as a guard.

## 2026-09-25 — critic round 13: airlock phase times and crates off porches (live)

- **Phase times are now fixed seconds** (`balance.airlock_phase_seconds`): enter 2.0, seal 1.0, open 1.0,
  exit 1.5; **pump is the rest** (10 s cycle: 4.5 s; unpowered 20 s: 14.5 s). Before: shares 1.5 / 1.0 /
  5.0 / 1.0 / 1.5 s. Cycle length and riders per cycle unchanged.
- The agreement I propose (tell me if your numbers differ): riders stand at their chamber anchors by the
  **end of `enter`** (2.0 s); the source-side door starts closing at the **start of `seal`** and is shut
  after your 0.6 s (`balance.airlock_door_seconds`); `seal` is 1.0 s, so `pump` starts 0.4 s after the door
  is shut, with both doors closed. If your riders need longer than 2.0 s to reach the anchors, give me the
  time and I lengthen `enter` (pump gets shorter).
- **Piles off porches:** a new ground pile or drop point is never within 2.5 m of an airlock outer door
  (`door_strip.p0`) nor on its 3.5 m × 3.2 m door strip (`balance.pile_porch_clear`); it moves to the
  nearest open point outside. Covered: cargo a colonist puts down, demolition and cancel salvage, upgrade
  refunds, bought goods at a pad, supply pods. Piles already in a save stay where they are. Test
  `v31_piles_clear_of_porches`. Check with `sim.place.in_porch(p)`.

## 2026-09-27 — V4 world API (milestone 1, live): the 2,560 m planet

Start a v4 game with `sim.new_game(seed, "frontier")` (scenario in `content/scenarios.json`,
`map_size` 2560). The old scenario "tutorial" stays 810 m; old saves keep their map. Test for v4 with
`sim.world.version == 4`. All numbers come from `content/terrain_v4.json`. Generation: about 0.75 s.

**Heights**
- `w.heights` (PackedFloat32Array, `w.hn × w.hn` = 641 × 641), `w.hstep` = **4.0 m** (v3: 2 m), `w.size`
  2560, `w.center` (1280, 1280) = the lander. `w.height_at(x, y)` (sim x, sim y) bilinear. Heights run
  from about −120 m (crater floors) to +250 m (peaks); the start plateau is flat to 125 m radius.
- `w.steep` (PackedByteArray, `(hn−1)²` quads of 4 m): 1 = too steep to walk or drive (slope > 0.6),
  crevices included.

**Features** (all Vector2 in sim metres, for drawing and overlays)
- `w.mountains`: `[{pts: [Vector2], width, height, passes: [Vector2], peak: Vector2}]` — a Gaussian ridge
  along the bent line `pts`; flanks steeper than 0.6 (impassable); `passes` are the low crossings.
- `w.plateaus`: `[{x, y, r, h, ramps: [{x0, y0, x1, y1, w}]}]` — raised discs (20–60 m) with cliffs; each
  ramp is a straight corridor from `x0,y0` (on top) to `x1,y1` (outside).
- `w.deep_craters`: `[{x, y, r, depth, floor_r, ramp: {x0, y0, x1, y1, w}}]` — r = half the width
  (100–240 m), depth 40–120 m, flat floor inside `floor_r`, one ramp down.
- `w.crevices`: `[{pts: [Vector2], w, d}]` — width 3–15 m (exact), depth 10–40 m. The height grid shows only
  a narrow trench; draw the crack from `pts` and `w`.
- `w.boulder_fields`: `[{x, y, r}]`; the boulders are in `w.rocks` with **kind 3** and `r` 2–10 m
  (radius; the design's 4–20 m is the diameter). Other rocks: kind 0–2, r 0.9–2.4 m.
- `w.dunes`: `[{x, y, r, wave, h, dir}]` (asymmetric waves, crest line across `dir`).
- As before: `w.ridges`, `w.canyons`, `w.craters` (small bowls), `w.flats`, `w.basin`, `w.fault`.
- `w.rocks_near(p, reach)`: rocks whose centre may lie within reach (bucket test; test the distance).
- `w.crevice_at(p, grow = 0)`, `w.terrain_at(p)` → "start plateau" | "mountain" | "plateau" |
  "deep crater" | "crater rim" | "crevice" | "boulder field" | "dunes" | "plain".

**Radiation** — `w.rad_at(x, y)` mSv/h (0.0 on older maps). Grid `w.rad` (`w.rad_side²`, cell
`w.rad_cell` = 16 m) for an overlay texture. Plain 0.04; peaks and crater rims higher; uranium and thorium
fields 2–6 at their centre. Flares and reactor leaks will be added by the sim later
(`sim.hazards`, a separate call; I will name it).

**Sun and horizon (V4 1.1)** — for a v4 map please take the sun from the sim, not from `fx_sky`'s own
formula (it is the same shape; the noon elevation is lower, **32°**, so crater floors stay dark):
- `w.sun_angles(day_time_s, daylight_s, day_len_s)` → `{elev_deg, bearing, dir: Vector3}`; `dir` points
  toward the sun in view space (x = sim x, y up, z = sim y). `day_time_s` = `sim.util.day_time()`,
  `daylight_s` = `sim.planet.daylight_seconds`, `day_len_s` = `sim.bal.day_length`.
- `w.horizon` (PackedFloat32Array) = horizon elevation in degrees per cell and sun bearing:
  index `(j * w.hz_side + i) * w.hz_bins + b`, cell `w.hz_cell` = 32 m, `w.hz_bins` = 13 bearings over
  the day (b = bearing / PI × 12). `w.sun_vis(p, elev_deg, bearing)` → 0..1 (soft over 4°).
  The solar output uses exactly this (`sim.util._sun_on(b)`).

**Walking** — the v4 map has no single 1 m grid: `sim.nav.grid` is **null** there (your walk overlay in
`fx_terrain._fill_walk` must skip it). Use `sim.nav.coarse` (AStarGrid2D, 8 m cells, `sim.nav.cn` = 320
per side) or `sim.nav.coarse_open_at(p)`. `sim.nav.path_out(a, b)` works as before (a fine 1 m window near
people; a result with `coarse: true` for long walks, points 8 m apart). Vehicles (milestone 3):
`sim.nav.vehicle_path(a, b, "rover" | "hopper", hop_m)` → `{ok, pts, len, hops?}`, `sim.nav.rover_ok(p)`.

**Deposits** — `state.deposits[i]` now also has `kind` (metal, ice, titanium, carbon, uranium, thorium,
deep_ice, helium3, rare_earth, exotic) and `tier` (1 basic, 2 mid, 3 high-end). v3 deposits have neither
(treat as metal ore, `exotic: true` as exotic).

## 2026-09-27 — critic round 18: crater form and mountain spikes are now in the heights (live)

- **Deep craters** (`sim/world_v4.gd` `_deep_craters`, numbers in `terrain_v4.json` deep_craters):
  - **Rim lip**: a crest right at r, height `rim` × depth (0.14), steep inside, gentle outside.
  - **Terraced walls**: `terraces` (3) benches joined by steeper risers, 70 % terrace / 30 % smooth; the
    rim radius wobbles ±2 % round the crater (slumps).
  - **Debris apron**: a lumpy raised skirt outside the rim out to 1.6 r (lumps on a 12 m pattern).
  - **Floor boulders**: 6–12 boulders (rocks kind 3, r 1–3 m) on each crater floor, clear of the ramp.
  - The flat dark floor and the ramp are unchanged (the ramp is cut after the walls).
- **Mountains**: the swell along a range is now continuous (the old noise stepped every 1/14 of the
  range: that made the stretched cliffs), and after every feature is drawn the samples on each range
  are smoothed wherever the slope to a neighbour is over `mountains.max_slope` (1.4): 16 passes of a 3 × 3
  mean. Steepest step on the ranges now about 2.3 (was 7 to 13). Tested (`v4_world_generation`: steepest
  ≤ 2.6, raised rim in at least 8 of 12 directions).
- Other steep ground is intended: crevice walls (slope up to about 13, the crack itself), plateau cliffs
  and crater risers (up to about 6). If a cliff needs more triangles, the heights are at 4 m; take the
  exact crevice edges from `w.crevices`.
- Generation now about 1.0 s.

## 2026-09-27 — V4 milestone 2: scale, outpost core, bases (live)

- **Scale on the v4 map:** a new room's `b.radius` is 1.5 × the v3 radius (every size); corridor tubes
  are `sim.corridor_r()` = **1.5 m** radius (1.2 on older maps; the model's 2.36 m tube becomes 3.0 m).
  Exterior structures keep their size. Always draw from the record's `radius`.
- **`outpost_core`**: a new special structure (kind "special", like the lander): radius 4.5 m, a hatch on
  +X (airlock phases like the lander hatch), `b.air_until` = the tick its own air ends. Draw it as a small
  lander (ART-HAB has the request). `name` = "<base name> core".
- `sim.bases.base_of(id)` for a base tint or label if you want one.

## 2026-09-27 — answer to your 15:00 questions (the checks after the 14:16–14:52 edits): fixed, please re-run

1. **What changed.** `content/balance.json` at 14:43–14:51: to carry the 1.5 × rooms (longer walks) I raised
   walking speed (inside 3.6 → 5.4 m/s, outside 3.2 → 4.0 m/s), suit air (90 → 110 s) and carrying (2 → 3
   units), and corridor/cable length limits. Faster people ride the airlocks more often: that was your
   84 → 111 and 74 → 103 cycles. No airlock radius, slot or cycle-time change (a new airlock is M 3.4 m since
   v3.1; old 2.8 m records keep 2.8 m and 2 riders).
2. **Now these numbers apply to new games only.** A game saved before V4 (no `state.rules`) keeps the v3
   values (`balance.legacy_v3`), so every showcase save plays as this morning. Measured 10 game minutes:
   showcase_v31 85 cycles (v3.1.1 tree 86), showcase_v3_late 76 (75); no structure is built or changed in
   those 10 minutes in either save.
3. **scene_final** is made by your `tools/render_final_save.gd` from a NEW game, so it now gets the V4 rules
   and the 1.5 × room radii (every S–XL room except airlock and junction): regenerate it, or better use the
   showcase saves for the gates. The showcase saves do not build during your check window (above).
4. **A stable test save:** `sim.set_freeze_build(true)` (writes `state.options.freeze_build`): no structure
   starts, finishes or is removed, no construction work is handed out. Call it after loading, before your run.
- I could not reproduce "airlock 141 appears": in scene_final it may be a blueprint your tool leaves that is
  finished during the run; with `freeze_build` it stays a blueprint.

## 2026-09-27 — deposit rings: `surveyed` flag (live)

- `state.deposits[i].surveyed` (bool). On the v4 map only deposits within 300 m of the landing
  (`terrain_v4.json` `known_radius`) start surveyed; the rest become surveyed by surveys, rovers and the
  satellite (milestone 7). Older maps and older saves: every deposit counts as surveyed (the key may be
  missing: read `sim.deposit_known(d)` or `d.get("surveyed", true)`).
- Critic rule for you: draw a deposit ring only when the resource overlay is on or the deposit is surveyed.

## 2026-09-27 — the 1.5 × room radii are in content (live)

- Every S–XL room type of ART-HAB's table is at 1.5 × the v3 radius for NEW structures on every map
  (`content/buildings.json`); airlock and junction unchanged; old records keep their radius. Greenhouse and fungus
  `tray_offsets` × 1.5. Corridors stay 1.2 m radius (`sim.corridor_r()`) until the wide tubes go live together.
- New content ids for ART-HAB's models: `rover_depot` (size M 9.0 / L 12.0), `launch_pad` 6.5, `fission_reactor`
  12.0, `crystal_refinery` 8.0, `chemical_plant` 9.0, `crevice_bridge` (S / L), `outpost_core` 4.5. The last three
  industry ones and the bridge are not placeable yet.

## 2026-09-27 — walking speeds for new games (coordinator limit)

- New games (V4 rules): **4.0 m/s inside, 3.5 m/s in a suit outside** (the run clip is matched to about 3.4 m/s).
  Saves from before V4: 3.6 / 3.2 as before. Read the speed from `sim.bal.speed_indoor` / `speed_outdoor`
  (the right table for the loaded game). The 5.4 / 4.0 of this afternoon are gone.

## 2026-09-27 — Corridor links per room (Paul's rule, live for new links)

- A room takes at most **S 4, M 6, L 7, XL 8** corridors. Airlocks and junctions keep their own rules.
- New links on one room are at least `max(28°, door angle)` apart. Door angle = the chord of the door
  housing (3.44 m + 0.3 m gap) at the wall radius (`radius − 0.32`).
- API: `sim.place.max_links(room)`, `sim.place.link_min_angle(room)`, `sim.place.door_angle(radius)`.
- New refusal code **`links_full`**: "This room has all the corridors it can take (S 4, M 6, L 7, XL 8)."
  It comes before `door_blocked` and `ports_full`.
- Old saves keep every link they have. Balance keys: `room_max_links` [4,6,7,8], `door_housing_m` 3.44,
  `door_gap_m` 0.3.

## 2026-09-27 — V4 milestone 3: vehicles (live in sim; numbers in `content/vehicles.json`)

**Kinds** (`sim.content.vehicles.kinds`)

| kind | seats | cargo | speed m/s | cabin | energy | wear | research |
|---|---|---|---|---|---|---|---|
| `small_rover` | 2 | 12 | 6 | open (suits) | charge 100, 10 per km | 1.5 per km | space_1 |
| `medium_rover` | 6 | 40 | 7 | pressurised | charge 300, 12 per km | 1.0 per km | space_1 |
| `hopper` | 3 | 6 | 25 in flight | pressurised | fuel 30, 3 per hop (hop ≤ 400 m) | 2 per hop | space_2 |

Wear 100 = broken. Rovers drive on the rover grid (`sim.nav.vehicle_path(a, b, "rover")`); the hopper
flies straight hops with a 3 s stop between hops. Vehicles drive on the 2,560 m map only.

**Depot** (`rover_depot`, exterior, size M or L): M has 2 small bays, L has 2 small + 1 medium bay.
`sim.vehicles.bays(depot)` → `[{i, kind "small"|"medium", pos, rot}]`: the bays stand in a row in front
of the depot (its `rot` direction), `radius + 5 m` out, 7 m apart. A small vehicle may use a medium bay.
A parked vehicle at a depot: charges 1 per second when the depot is powered; takes 1 `rocket_fuel` from
the depot store for 3 fuel; takes 1 `spare_parts` for −25 wear (this also clears "broken").

**Snapshot for the view and the panels**: `sim.vehicles.list()` → rows
`{id, kind, name, pos, rot, state ("parked"|"driving"|"broken"), block ("" | no_charge | no_fuel |
no_driver | broken | "route: …"), charge, charge_cap, fuel, fuel_cap, wear, crew [agent ids], seats,
cargo {item: n}, cargo_inv, dest (Vector2 or null), path [Vector2], pi (next path index), hopping (bool,
true while a hopper is in the air), depot, bay, route {}}`.
`sim.vehicles.get_v(id)` is the live record. The cargo is an inventory with owner type `"v"`
(`sim.inv.position_of` returns the vehicle's position).

**Riders**: an agent in a vehicle has `where == "vehicle"` and `veh = <vehicle id>`, `bld = -1`, and
`pos` = the vehicle's position every tick. Do not draw a body for a rider (or draw it in a seat); the
agent panel can say "Riding in <name>" (that is the agent's `goal`). A pressurised cabin gives air and
fills suits; in the small rover suits run down, and the rover turns back to a depot by itself when the
crew's air only just covers the drive back (log code `vehicle_air`).

**Commands** (results `{ok, code}`):
- `build_vehicle {depot, kind}` — carriers bring the parts, technicians assemble it outside at the depot.
  Codes: `unknown` (not a depot), `not_active`, `invalid` (kind), `locked_research`, `busy` (one order per
  depot), `no_bay`. Order record: `depot.vorder = {kind, cost, inv, progress, work_total, state
  ("deliver"|"work"), block}` (same shape as `upgrade`). New task kind `vbuild` (like `upgrade`).
  `cancel_vehicle {depot}`.
- `vehicle_board {id, agents: [ids]}` — those colonists walk to the vehicle and get in (plan kind
  `order`). Codes `no_seat`, `no_path`. Result has `sent`.
- `vehicle_drive {id, x, y}` — codes `no_driver`, `broken`, `no_route`.
- `vehicle_return {id}` — to a free bay of its depot, else the nearest depot with a free bay.
- `vehicle_stop {id}` — stops where it is; the crew stays aboard; a route ends.
- `vehicle_alight {id}` — everyone gets out beside it (outside, suited).
- `vehicle_cargo {id, load: {item: n}, unload: true}` — with the stores of the base where it stands
  (store and output inventories within 85 m). Codes `moving`, `no_store`. Result `{loaded, unloaded}`.
- `vehicle_route {id, a, b, load: {item: n}, back: {item: n}}` — runs between bases a and b while it has
  a driver: unload + load at a, drive to b (a free depot bay of b, else beside b's core), unload + load
  `back`, drive to a. `{id, stop: true}` ends it. `route.trips` counts deliveries to b.
- `deploy_outpost` accepts a vehicle's `cargo_inv` as `inv` (the kit must be within 30 m).

**Crew rules**: crew stay aboard while the vehicle drives or runs a route. Parked without a route and
within suit reach of air, they get out after 120 s (5 s in an open rover). Far from air they stay aboard
until ordered. With air in reach, a rider with a critical need gets out.

**Log codes**: `vehicle_order`, `vehicle_built`, `vehicle_stopped`, `vehicle_broken`, `vehicle_air`.

## 2026-09-27 — V4 milestone 4: orders (live in sim, `sim/orders.gd`)

**Order a colonist or a group**: command `order {agents: [ids], kind, …, confirm?}`.

| kind | fields | what the colonist does | ends |
|---|---|---|---|
| `go` | x, y, stay? | walks there (into a room if the point is in one) | on arrival (with `stay: true` it becomes `stay`) |
| `stay` | x, y | walks there and stays | when cleared |
| `return` | — | walks to the core of its home base (else a room with air of that base) | on arrival |
| `board` | v | walks to the vehicle and gets in | when seated |
| `work_at` | b | takes only tasks of that structure (any role) | when cleared or the structure is gone |
| `survey` | site | surveys that hazard site (any role); POIs join in milestone 7 | when surveyed |

Result: `{ok (any accepted), code, text, accepted: [ids], refused: {id: {code, text, confirmable}}}`.
Preview for the cursor: `sim.orders.check(agent, payload)` → `{ok, code, text, confirmable}`.

**Refusals** (text is ready for the player, STE):
- `suit_range` "The suit air is not enough to go there and come back." — confirmable
- `exposed_stay` "The colonist cannot stay outside: the suit air ends." — confirmable
- `radiation` "The radiation there is too high (x.x mSv/h)." (above `balance.order_rad_refuse` = 1.0) — confirmable
- `no_path`, `in_vehicle`, `in_airlock`, `no_vehicle`, `no_seat`, `no_building`, `no_site`, `no_base`,
  `not_colonist` (visitors), `dead`, `unknown`, `invalid`.
- With `confirm: true` a confirmable order runs and the colonist does NOT turn back for air or shelter
  while it runs (the player accepted the risk). Show the reason and a confirm button.

**Rules**: an order overrides the colonist's own choices; critical thirst, hunger and exhaustion still
interrupt it and the order continues after. An unconfirmed order that runs out of air margin ends (log
code `order_ended`, "…: the order ended (low suit air).").
`order_clear {agents}` ends orders. Agent field `order` (absent = none):
`{kind, p, b, v, site, stay, confirm, t}`; `agent.goal` says "Going to the ordered place",
"Staying here (order)", "Returning to base (order)", "Working at <name> (order)", "Survey (order)".

**Own job priorities**: `set_jobs {agent, jobs: {category: 0..3}}` (0 = not allowed) and
`set_jobs {agent, clear: true}`. Categories = `sim.orders.job_categories()` (construction, food,
industry, logistics, repair). Agent field `jobs` (absent = colony priorities). A task already taken is
finished first.

**Vehicles**: `vehicle_explore {id, x, y, r}` — the driver takes the vehicle round 8 points on a circle
of r (50–600 m); unreachable points are left out. Row field `explore` in `sim.vehicles.list()` ({} or
`{pts, i, c, r}`). Other vehicle commands end an explore. Driving and boarding orders stay the vehicle
commands of milestone 3 (`vehicle_board` equals `order kind board` for a group).
- RENDER: an ordered colonist has `agent.order`; a flag or marker at `order.p` helps the player see
  where a group was sent. A vehicle row with `explore` has its loop points in `explore.pts`.

## 2026-09-27 — V4 milestone 5 (content) — what RENDER may need

- New buildings to draw (ART-HAB's files): the 9 industry rooms and `fuel_rod_plant`, `he3_separator`,
  `graphene_reactor`; `chemical_plant` and `crystal_refinery` are now placeable.
- New items have `color` in `content/items.json` (piles, cargo). Item category `find`.
- A deposit's kind decides what a mine gives (`sim.prod.deposit_info(d).item`), for deposit ring colours.
- Settlers now land with a pile of ration meals beside them (new games).

## 2026-09-27 — depot bays now at ART-HAB's Anchor_Bay_<i> (your request)

- `sim.vehicles.bays(depot)` → `[{i, kind, pos, rot, exit}]`: `pos` = the anchor (content
  `rover_depot.sizes.bay_anchors`, model x/z: L (−1.85, 5.0 / 0.3 / −4.7), M (−2.0, 2.35 / −2.35)),
  turned with the record: `pos = depot.pos + Vector2(x, z).rotated(depot.rot)` (your `rotation.y = −rot`), scaled by
  record radius / def radius. `rot` = the depot's rot (vehicle faces out, the anchor's +X). A parked vehicle in a
  bay has that `pos` and `rot`, so you can drop your override.
- `exit` = on the apron in front of that bay's door (radius + 3 m out along +X). A drive out of a bay goes
  bay → exit first, and a drive into a bay ends exit → bay: these two "taxi" segments are driven at 3 m/s
  (vehicle `taxi_a` = 1 when the first segment is a taxi, `taxi_b` = index of the last point when the last
  segment is one). A hopper taxis on the ground (no hop, no fuel) on them.
- The board point of a vehicle in a bay is on the apron in front of the bay door (walkable), so the
  colonist walks to the door and gets in there.

## 2026-09-27 — V4 milestone 6: reactor, disasters, radiation dose (live in sim, `sim/reactors.gd`)

**Reactor rows**: `sim.reactors.list()` → `[{id, name, pos, heat, stage ("ok"|"warning"|"critical"|"breach"),
rate (heat per s), next_stage, next_phase_s (-1 = not coming), running, scram, scram_left_s, evac, fuel_s, rods,
coolant, blast_r (60), zone_r (140)}]`. `sim.reactors.forecast(building)` gives the same forecast for one.
Heat: 20 cold, 40 running; warning 60, critical 85, breach 100. Running adds 0.05/s, a damaged or worn
reactor more; coolant (1 unit per 150 s) takes 0.06/s off, without coolant only 0.01/s. So a reactor without
coolant reaches warning in 500 s, critical in ~1100 s, breach in ~1500 s — the forecast says when.
One fuel rod runs 1,200 s. Carriers keep 2 rods and 8 coolant in its buffer (urgent when hot).

**Commands**: `reactor_scram {id}` (fission stops after 12 s; `done` if already), `reactor_restart {id}`
(`too_hot` at warning or above), `reactor_cool {id}` (dumps up to 4 coolant, −12 heat each; `no_coolant`),
`reactor_evacuate {id}` → `{moved, stuck}`: colonists within 140 m get a confirmed `stay` order in the nearest
room with air outside the zone (`agent.order.evac` = reactor id); the orders end when the core is safe again.
Debug only: `reactor_stage {id, stage}` (ok | warning | critical | breach; breach explodes on the next second).

**Breach**: every structure within 60 m is destroyed (log `destroyed`, contents lost; the lander and other
special structures are damaged instead), everyone within 60 m dies, vehicles break; a radiation zone of 140 m
(60 mSv/h at the centre, halving every 2 days). Log `reactor_breach`.

**Other risky plants**: crystal refinery without power while a batch runs → alert `unstable_power` with a
countdown (45 s), then an explosion of 14 m (log `unstable_blast`). A chemical plant below health 50 leaks: a
toxic zone of 30 m for 2 days hurts people outside in it (alert and log `toxic_leak`).

**Zones**: `sim.reactors.zones()` → `[{kind "rad"|"toxic", x, y, r, peak | dmg, t0, half_s | until, src}]`.
`sim.reactors.rad_at(Vector2)` = the ground (v4 map) + zones, mSv/h (use this for the radiation overlay now,
not `world.rad_at`). `sim.reactors.toxic_at(Vector2)` = damage per day.

**Dose**: `agent.dose` (mSv; absent = 0). Inside a room a tenth of the outside rate, a pressurised cabin 0.3.
It halves slowly (5 % a day; 20 % with Radiation Medicine). Alerts `rad_dose` at 250 mSv (warning) and 750
(critical); above 1,000 it hurts ("radiation sickness"). Research Dosimetry and Shielded Suits cut the dose
10 % and 30 %. Orders into ground above 1 mSv/h are refused unless confirmed.

**Alert codes**: `reactor_warning`, `reactor_critical`, `reactor_fuel`, `unstable_power`, `toxic_leak`, `rad_dose`.
**Log codes**: `reactor_warning`, `reactor_critical`, `reactor_ok`, `reactor_scram`, `reactor_cool`,
`reactor_evacuate`, `reactor_breach`, `destroyed`, `unstable_warning`, `unstable_blast`, `toxic_leak`.

RENDER: the explosion happens in one tick (structures gone from `state.buildings`); the log entry
`reactor_breach` / `unstable_blast` and the new zone (its `t0`) mark the moment and the place for the effect.

## 2026-09-27 — V4 milestone 7: fog of war, points of interest, finds, satellite (live, `sim/explore.gd`)

Only on the 2,560 m map; older maps have no fog (`sim.explore.active()` false, `explored()` always true).

**Fog**: `sim.explore.fog()` → `{cell: 16.0, n: 160, bits: PackedByteArray n*n (row j*n+i, 1 = explored), rev,
count}`. Upload the texture only when `rev` changes. `sim.explore.explored(Vector2)`, `explored_share()` (0..1).
The landing area (300 m) is known at the start. Colonists outside reveal 40 m round them, rovers 120 m, hoppers
200 m (+25 % with Survey Methods). A revealed deposit becomes `surveyed` (log `deposit_found`).

**POIs**: `sim.explore.pois()` → `[{id, kind, x, y, found, visited, need}]`; content `terrain_v4.explore.pois`
(name, desc, finds). Kinds: `wreck` (5), `derelict_probe` (3), `meteorite_field` (4), `cave` (4, near mountain
feet), `anomaly` (3, anywhere, often only a hopper reaches it), `rich_deposit` (4). 380–1,180 m from the
landing. Show only `found` ones. A POI is visited when a colonist comes within 20 m (`need`: `any`,
`on_foot` = somebody outside, not only in a vehicle, `scientist` = a scientist among them). Finds go into
the cargo of a vehicle there, else a ground pile at the POI. Anomaly: +200 research points. Rich deposit: a
new deposit (1,500 units, `rich: true`). Logs `poi_found`, `poi_visited` (with what was found).
Order: `order {agents, kind: "survey", poi}` walks there (suit and radiation refusals as usual; confirm).

**Satellite**: `build_satellite {pad}` (a launch pad; research Orbital Survey; the parts are carried there,
technicians assemble it, then it launches; it uses the depot order record `vorder` with kind "satellite").
`sim.explore.sats()` → `[{id, name, bands_done, bands (16), next_s, band, uplink}]`. With an uplink (any
powered comms tower) it maps one band (a strip across the map) every 60 s; the POIs in it are found; with
Deep Scan the deposits in it are surveyed too. Logs `satellite_launched`, `satellite_done`.

**Debug**: `reveal {x, y, r}` (debug=1 only).
**Content**: blueprint fragments → 3 advanced packs at the research assembler (`pack_blueprint`, Survey Methods).

## 2026-09-27 — V4 milestone 8: save schema 5, `showcase_v4.fhsave`

- Saves are **schema 5**. Migration: v1–v3 as before; v4 (V3.1) → 5 adds `bases`. Saves from before V4 keep
  the v3 balance and their map size (256 or 810 m). A v4 save made during development gets fog on load.
- **`content/saves/showcase_v4.fhsave`** (made by `tests/make_showcase_v4.gd`, day 12, seed 1001, hazards normal):
  2,560 m map, 20 colonists, two bases (landing base and "Crater camp", ~440 m apart), a size L rover depot with
  a medium rover on a route to the camp (10 metal each way out), an expedition rover with two people at a deep
  crater rim, a fission reactor (2 rods, 8 coolant, ~170–280 m from the lander), a launch pad, comms tower and
  battery, and a survey satellite with 5 of 16 bands mapped (fog about 36 % explored). Debug is off in the
  save; load it with `debug=1` to use the debug commands (for example `reactor_stage` for the disaster shots).

## 2026-09-28 — your three fixes and the POI frame

1. `reactor_breach` and `unstable_blast` log entries now have `ents: [structure id]` (the structure is already
   gone) and extra fields `pos: [x, y]`, `def`, `blast_r` (and `zone_r` for the reactor). `sim.log_event` takes an
   optional `extra` dictionary.
2. Debug `reactor_stage breach` explodes at once (a direct breach), with or without coolant. `warning` and
   `critical` now set the heat 2 points over the threshold, so one second of cooling does not undo them. You can
   drop the `rx.heat = 130` work-round.
3. Vehicles stop only on ground under 15 deg (`content/vehicles.json` `park_slope_deg`): every drive that does not
   end in a depot bay ends at `sim.vehicles.park_spot(p)` (the nearest open rover ground under the limit within
   48 m); `spawn_vehicle` at a point does the same. `sim.vehicles.slope_deg(p)` for your checks.
   `showcase_v4.fhsave` is rebuilt: the expedition rover stands on flat ground by the crater rim.
4. POI find timing (sim side), on the rebuilt showcase, 900 s from load: every tick with `poi_found` took 3.8–6.1 ms
   in total (an ordinary once-a-second tick), and `explore.tick_second` alone 0.15–0.2 ms. The band reveal writes one
   strip of the fog bits and bumps `fog.rev` once. So the 667 ms frame is not sim work at the find; RENDER's fog
   texture or POI marker upload on that `rev` change is the next place to look. (Other sim ticks of 50–78 ms came
   when a rover planned a new route across the coarse grid, not at POI finds; I watch those.)

## 2026-09-28 — tick spikes fixed; parking 10 deg; reactor_stage exact

- **Long ticks**: 900 s of `showcase_v4` from load, worst tick before **78 ms**, after **16–20 ms** (two runs 16.0 and
  18.0 ms; the test run 20.4 ms). Cause: not the vehicle route planning but colonists' choice of work — each failed
  walk search into a closed pocket (an area enclosed by structures) searched the whole 320 m window (25 ms, up to
  three per colonist). The walk graph now knows its closed pockets (a bounded fill per window, 1–2 ms once) and
  answers those walks at once; the answer is the same as before, so games play exactly as before. Fine windows
  round every base core are also made at load / new game (8 ms each) instead of inside a tick. Test
  `long_v4_tick_max` (900 s, no tick over 30 ms).
- **Parking**: vehicles now stop on ground of 10 deg or less (`park_slope_deg` 10). showcase_v4 rebuilt.
- **reactor_stage**: each command sets exactly the stage it names at once (row and record, with its log);
  `breach` explodes in the same tick from any stage. Test `v4_reactor_stage_debug` (normal -> breach in one command).
