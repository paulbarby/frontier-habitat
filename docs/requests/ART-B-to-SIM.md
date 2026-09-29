# ART-B to SIM

## 1. Meridian footprint capsule vs the model (2026-09-23)

**What.** `sim/ship.gd` `segment_of()` uses `length` 40 as the total length: segment x -13 .. +13,
radius 7, so the capsule covers x -20 .. +20. The model `assets/models/meridian.glb` measures
(Blender x along the ship axis, y across it, ship centre = building `pos`):

| part | x min | x max | max abs(y) |
|---|---:|---:|---:|
| Hull (ship with the rear ramp) | -21.95 | 21.53 | 6.96 |
| Damage1 (dirt berm in front of the buried nose) | -13.25 | 23.64 | 6.90 |
| Damage3 (scrap behind the engines) | -22.95 | -7.52 | 7.00 |
| Anchor_Ramp (foot of the rear ramp) | -22.21 | | 0.04 |

**Effect now.** Your end access points (x = +/-21.2) land on the rear ramp (good) and next to the
buried nose (acceptable). The side access points (y = +/-8.2) are clear of the hull. But a building can
be placed 1.5 to 2 m inside the nose or the tail, because those parts are outside the capsule.

**Proposal (low priority).** Set `length` to 44 (segment -15 .. +15, covers x -22 .. +22). The end access
points then move to x = +/-23.2, which is clear of the ramp foot and the berm.

### SIM answer (2026-09-24): accepted, done

- The footprint is now 44 m: `balance.json` `ship.capsule_length` = 44 and
  `buildings.json` `meridian.shape.capsule_length` = 44 (both read the same; radius 7).
  The record carries it: building `length` = 44, `radius` = 7. `Ship.segment_of(b)` gives
  segment x -15 .. +15 in ship space, so the capsule covers x -22 .. +22.
- Access points (`sim.nav.access_points(ship)`, from `sim/ship.gd` `access_candidates()`):
  both sides at y = +/-8.2 at 0 %, 20 %, 50 %, 80 % and 100 % of the segment (x = -15, -9, 0,
  +9, +15), and the two ends at x = +/-23.2 on the axis. Only walkable ones are used.
- Axis: the sim's `rot` is the direction of ship-space +x (the nose, as in the asset
  contract: front +X). The rear ramp is at -x. The end point at x = -23.2 is the ramp foot
  side, so carriers and workers who come from behind the ship use the ramp.
- The world generator picks the crash site with the new length (sites can move slightly
  from the ones measured before this change; still 55 to 75 m from the lander).

## v5.0 — super dome PILOT: footprint, floors, venues, anchors (V5 §7, §8) — 2026-09-29

Files and all numbers: `assets/models/dome_manifest.json` (written by `tools/blender/dome_build.py`).
- **Footprint:** dome radius 48.0 m; the plinth reaches r 49.6; the 12 gate blocks reach **r 51.0**. Height 38 m
  (crown mast 40.5). Proposed structure radius for placement: **51 m**.
- **Door slots (12 large gates):** `Anchor_Gate_<i>` at r 51.6 on the ground, bearing 30° × i, +X outwards (the
  corridor joins here); `Anchor_GateIn_<i>` at r 46.0 inside.
- **Floors:** L1 0.30, L2 5.30, L3 9.50, L4 13.70, L5 17.90, roof 22.10 (m above the ground). Each anchor has extras
  `floor` and `height`. Vertical links: 4 glass lifts (`Anchor_Lift_<i>_<floor>`, i = 0..3 at bearings 45, 135, 225,
  315°, floor 6 = roof); ramps/stairs come after the pilot.
- **Ring plan:** 24 sectors of 15° (sector s centred on bearing 15° × s); ring r 20–34; fronts at r 23; gallery
  r 20–23. L1 passages (open to the atrium) at sectors 0, 6, 12, 18.
- **L1 venues (pilot):** grocery, clinic, barber, cafe, restaurant, credit, hotel, bar, comms, clothing, electronics,
  gifts: each `Anchor_Venue_<id>` (door), `Anchor_Work_<id>_<k>` (staff), and `Anchor_Seat_<id>_<k>` for cafe,
  restaurant and bar. Please say if your venue ids differ; I will rename to yours.
- **Planned for L2 (next):** gaming lounge (with the Prism Shift cabinet), Club (stage, podiums, DJ booth, booths,
  bouncer point), gym, and the remaining businesses. **L3–L5:** 24 unit slots per floor now (`Anchor_Unit_<floor>_<s>`);
  tell me the split you want for 30 units (24 standard/family, 6 executive = 2 sectors each) + hotel rooms.
- **Atrium:** pool (`Anchor_Swim_<k>`, `Anchor_Lounger_<k>`, slide, lifeguard), fountain and park benches
  (`Anchor_Bench_<k>`), event stage (`Anchor_Stage`), plaza points.

## v5.0 — super dome after the pilot: L2 venues, units, build stages — 2026-09-29

- **L2 venues:** beauty, arcade (label GAME ZONE; the PRISM SHIFT cabinet at `Anchor_ArcadePrism_arcade_0`), shoes,
  books, gym, toys, foodcourt, club (6 sectors; bouncer point `Anchor_Bouncer_club_0`), jewels, travel, flowers,
  tailor, vacant (TO LET). Each has `Anchor_Venue_<id>` and staff / customer anchors (`Anchor_<Kind>_<id>_<k>`).
- **Units:** L3 24 hotel rooms, L4 24 family units, L5 6 executive units (2 sectors) + 12 hotel rooms → 30 units
  (24 + 6) and 36 hotel rooms. `Anchor_Unit_<floor>_<s>` with extras unit_kind and sectors; beds, seats, desks inside.
- **Build stages:** `assets/models/dome_manifest.json` → `build_stages` (foundation, level_1..5, dome_frame,
  dome_glass, fitout, fitout_<venue>). If your stage ids differ, tell me and I rename the node extras.
