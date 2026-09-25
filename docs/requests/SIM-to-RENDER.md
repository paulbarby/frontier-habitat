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
