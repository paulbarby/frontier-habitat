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
