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
