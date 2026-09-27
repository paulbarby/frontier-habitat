# ART-B progress

Owner: ART-B (exterior, special, crop, colonist and prop models). Scripts: `tools/blender/ext_*.py`.
Rebuild a group: `"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python tools/blender/ext_<group>.py`

## 2026-09-23 — milestone 1: library and the Meridian

**Landed**

| file | objects | triangles | notes |
|---|---|---:|---|
| `assets/models/meridian.glb` | Hull, Damage1, Damage2, Damage3, Scaffold, Lights, EngineGlow; empties Anchor_Engine_L, Anchor_Engine_R, Anchor_Ramp | 20 564 | COLOR_0 AO on every mesh |
| `assets/models/debris_a.glb` / `debris_b.glb` / `debris_c.glb` | Base | 296 / 568 / 468 | torn hull panel, crushed tank, twisted truss |

Scripts: `tools/blender/ext_common.py` (shared library: Part builder, materials, AO bake, atomic export,
checks), `tools/blender/ext_meridian.py`, `tools/blender/ext_render.py` (thumbnails and check sheets).
Check sheet: `tools/blender/previews_ext/meridian__states.png`.

**Meridian conventions (for RENDER and SIM)**

- Ship length along X, nose at +X, rear ramp at -X. Tilt is baked into the mesh: pitch 4.0 deg nose down
  (pivot on the ground at x = -13), roll 2.0 deg with the -Y side down. In Godot this is rotation.z = -4 deg,
  rotation.x = +2 deg. To show the ship level (test flight), add rotation.z += 4 deg and rotation.x -= 2 deg.
- The nose goes down to z = -2.0 (below ground). The terrain hides it; do not clip it.
- Extents (Blender x, y): Hull x -21.95 .. 21.53, |y| <= 6.96. With Damage1 (dirt berm at the nose):
  x up to 23.64. Rear debris (Damage3): x down to -22.95. All objects |y| <= 7.00.
- `Damage1` = hull breaches, torn plates, missing panels, scorch, the dirt berm round the nose, scrap on the
  ground. `Damage2` = shattered cockpit glass, a blown side window, cables out of the breaches, open avionics
  hatch, snapped antenna. `Damage3` = soot and crumpled nozzle on the engines, torn cowl, broken landing
  leg, engine scrap and a lost nozzle ring behind the ship. With all three hidden the ship is intact.
- `Scaffold` = four towers at the breaches, two light masts, plates and a cable reel. Work-light lenses
  use the `Light` material inside Scaffold.
- `Lights` = cockpit panes, side windows, porthole rows, rear-door glow, running lights, nose floodlights
  (Window / Light materials, emissive). `EngineGlow` = nozzle discs, glow rings, short flame cones (Plasma).
- Anchors: local +X = exhaust direction (engines) or the walking direction away from the ship (ramp).
  Anchor_Ramp is at the foot of the rear ramp, (x -22.2, y 0, z 0), 1.2 m beyond the hull on purpose.

**Next**: colonists, crops, sized exteriors, singles, props, thumbnails.

## 2026-09-24 — milestone 2: colonists and crops

**Landed**

| file | objects | triangles | notes |
|---|---|---:|---|
| `assets/models/colonist_suit.glb` (+ copy `colonist.glb`, the v1 name) | Body, ArmL, ArmR, LegL, LegR | 1 438 | EVA suit, big helmet with `Visor`, backpack `Pack`; SuitAccent = shoulder pads, chest band, helmet lamps, knee pads, cuffs |
| `assets/models/colonist_indoor.glb` | Body, ArmL, ArmR, LegL, LegR | 1 244 | jumpsuit top in SuitAccent (role colour), grey trousers, head with `Skin` and `Hair` |
| `assets/models/crop_potato.glb` (+ copy `crop.glb`) | Stage1, Stage2, Stage3 | 330 / 918 / 1 422 | soil ridges, bushes, white flowers, tubers |
| `crop_wheat.glb` | same | 560 / 390 / 1 170 | green shoots, dense green field, dense golden field with ears |
| `crop_greens.glb` | same | 384 / 840 / 1 440 | lettuce rosettes to round heads |
| `crop_tomato.glb` | same | 208 / 832 / 1 440 | trellis, vines, yellow flowers, red fruit |
| `crop_soybean.glb` | same | ~380 / 810 / ~1 150 | trifoliate plants, yellowing bushes with pod clusters |
| `crop_herbs.glb` | same | ~340 / ~800 / ~950 | chives with flowers, basil, parsley, rosemary |
| `crop_mushroom.glb` | same | ~1 050 / ~1 250 / ~1 110 | three-shelf rack with substrate blocks, caps on top, oyster shelves on the sides; rack is in every stage |
| `crop_algae.glb` | same | 658 / 826 / 826 | seven glass tubes on a plinth, 1.2 m across, 1.9 m tall; culture rises and glows |

Scripts: `tools/blender/ext_colonists.py`, `tools/blender/ext_crops.py`.
Check sheets: `tools/blender/previews_ext/colonists__row.png`, `crops__stages.png`.

**Conventions**

- Colonists face +X, 1.8 m. Body origin on the ground; ArmL/ArmR origin at the shoulder joint, LegL/LegR at
  the hip joint (left = +Y). The limbs swing about Godot local Z, as in v1.
- New materials `Skin` (#D9A47E) and `Hair` (#4A3326), indoor colonist only. They can be tinted per
  colonist with `tint_named`, like SuitAccent.
- Crops: origin = centre of the soil surface; everything inside 2.8 x 1.2 m. Material `Produce` = the crop
  colour from `content/items.json`. Plant, PlantDark and Produce are double sided.
- `crop_mushroom` stands on the tray place (1.45 m tall). `crop_algae` has its origin at the bottom centre;
  the bioreactor has no tray places, so where to show it is RENDER's choice.


## 2026-09-24 — milestone 3: all exteriors, singles, props, thumbnails, report

**Landed** (all re-imported and checked by `tools/blender/ext_verify.py`: 60 files, 0 flags)

- Sized exteriors, S/M/L/XL, objects Base + L2..L5 (+ Rotor on wind turbines), size M also as `<id>.glb`:
  `solar_array` (1 table, 2 rows, 4 rows, tracker field), `wind_turbine` (mast 6/9/13/18 m; L/XL platform),
  `battery` (2, 3, 2x3, 2x4 cabinets), `water_extractor` (tripod, 3-leg, 4-leg derrick, twin rigs),
  `reservoir` (small tank, tank with walkway, twin tanks, sphere on legs), `regolith_harvester` (loader,
  conveyor + hopper, bucket wheel, bucket wheel + silo + stockpile), `fuel_refinery` (1..4 spheres, columns,
  flare stack). Triangles 1.6k .. 6.4k, all inside the footprint with the level parts.
- Level language on every levelled exterior: L2 steel ring + antenna, L3 cyan band + module, L4 violet band +
  finned annex, L5 gold crown + beacon + emblem. Script `tools/blender/ext_levels.py`.
- Singles: `fusion_reactor` (Base, Plasma, L2..L5), `deep_drill` (Base, Lights, L2..L5), `comms_tower`
  (Base, Lights), `lander` (Base, Lights, Anchor_Ramp, Anchor_Engine), `landing_pad` (Base, Lights).
- Props: `supply_pod` (Base, Lights), `crate_raw/material/component/food/medical` (+ `crate.glb`),
  `rock_a` .. `rock_f`, `pebbles`.
- Thumbnails `assets/thumbs/`: 28 sized, 6 singles, `meridian.png` (intact, lights on), extra
  `meridian_wreck.png` (as found), 8 `crop_<crop>.png` (Stage3). Shared camera and light with ART-A.
- Report `tools/blender/ext_report.md`; check sheets `tools/blender/previews_ext/*__sheet.png`,
  `crops__stages.png`, `meridian__states.png`, `props__sheet.png`, `singles__sheet.png`, `_thumbs_sheet.png`.

**Requests written**: `ART-B-to-SIM.md` (Meridian capsule length), `ART-B-to-RENDER.md` (object and material
facts), `ART-B-to-ART-A.md` item 3 (v1 names overwritten by `build_assets.py` without `--only`).
Fixed on ART-A's report: my previews applied AO twice; thumbnails re-rendered.

**Not done / not tested**: nothing was run in Godot by ART-B.

## 2026-09-25 — v3.1: ship models (§6.2), pilot `ship_trader`

**Landed**

- `assets/models/ship_trader.glb`: a boxy freighter with four orange cargo pods, a crane arm on the spine,
  two aft engines, four belly hover thrusters, a rear cargo ramp and a gull-wing side hatch. 8 160 triangles,
  6 materials (Palette, PaletteMetal, Accent, Window, Light, Plasma), plan radius 7.44 m, height 6.0 m,
  COLOR_0 on every mesh. Godot import done; `check` 149 scripts, 0 failed. A headless Godot probe
  confirms the node names and the `extras.stow_deg` metadata.
- Nodes: `Hull`, `Leg_FL/FR/RL/RR`, `Ramp`, `Door_Side`, `Thruster_Hover_FL/FR/RL/RR`, `Thruster_Main_L/R`,
  `Anchor_Ramp`, `Anchor_Cargo`. Motion rule and values in `docs/requests/ART-B-to-RENDER.md` item 2.
- Scripts: `tools/blender/ship_common.py` (contract, lofted hull, legs, ramp, palette, export with extras,
  checks), `tools/blender/ship_trader.py`, `tools/blender/ship_render.py`. `ext_common.py` and
  `ext_render.py` (now ART-HAB's) are imported read-only, not edited.
- Renders `art/ships/`: `trader_turnaround.png` (8 views), `trader_on_pad.png`, `trader_on_pad_rear.png`
  (landed on the current pad, ramp open), `trader_flight.png` (legs folded, ramp and hatch closed, 4 m up),
  `trader_night.png`. Report `art/ships/ship_report.json`.
- Requests: `ART-B-to-ART-HAB.md` item 1 (pad footprint, `Anchor_Ship`, ramp lane), `ART-B-to-RENDER.md` item 2.

**Found:** on the current pad the kiosk stands at −X, where the ramp lands at yaw 0. The renders use yaw 180°
until the pad has `Anchor_Ship`.

**Next:** pilot critic → the other five ships (shuttle, liner, medical, science, courier).

**Not tested:** anything in the running game (landing, leg and ramp motion, night).

## 2026-09-25 — v3.1: critic round 9 fixes and the other five ships

**Trader fixes (round 9, 1–8):** faceted chamfered bridge with frame mullions, dark glass by day and lit panes
in `Lights` at night; hazard frames at the ramp opening and the hatch; flank panel insets; spine rails; a
flank ladder; registration `TR-07` on the front pods; legs 40 % thicker with a hydraulic ram and a 1.0 m foot;
engine bells with a bronze rim and a glowing inner cone (`Plasma`); red/green nav lights on the pod noses, a
crane strobe, belly floods over the ramp, a lit hold; two ribbed containers on the spine; engines raised 0.5 m
(clear of the ramp); pad render names swapped. 10 290 triangles, 8 materials.

**Five new ships** (`tools/blender/ship_fleet.py`), same language, critic table outlines and colours:

| ship | look | tris | radius / height |
|---|---|---:|---|
| shuttle | short and tall, graphite + white, two continuous window rows, side airstair, yellow stripe | 8 266 | 6.51 / 7.60 |
| liner | the longest, a dart, pink band, panoramic window band, observation blister, three fins, three engines | 8 768 | 7.42 / 6.12 |
| medical | compact and wide, white + red, crosses on the roof and flanks, 2.8 m rear ramp, stretcher hatch | 6 984 | 6.16 / 5.60 |
| science | medium, #7C8CFF deck, 13 m dish mast (the tall one), antenna array, belly instrument pods | 8 460 | 6.83 / 13.25 |
| courier | the smallest wedge (~4.5 m), black + gold chevrons, one engine | 5 448 | 4.52 / 3.47 |

All: 8 materials, COLOR_0, registration codes (SH-12, LN-03, MD-21, SC-09, CR-01), nav lights, Lights node.
Godot import done, `check` 150 scripts 0 failed. `art/ships/.gdignore` added (renders are not game assets).

**Renders** (`art/ships/`): per ship `<kind>_turnaround.png`, `_on_pad.png`, `_on_pad_rear.png`, `_flight.png`,
`_night.png`; `fleet_lineup.png`, `fleet_top.png`. Requests updated: `ART-B-to-RENDER.md` item 2 (all six
tables), `ART-B-to-ART-HAB.md` item 2.

**Not tested:** anything in the running game.

## 2026-09-25 — v3.1: critic round 11 fixes 1–8

| fix | change |
|---|---|
| 1 shuttle top | graphite roof, yellow centre stripe, raised passenger deck (0.6–0.75 m, rear two thirds) with its own window strip and a yellow stripe |
| 2 liner dart | 2.5 m tapered nose (no bridge block), swept delta wings with pink leading edges and winglets (plan span 6.6 m), pink band on the roof spine |
| 3 cockpits | bus windscreen (shuttle), wraparound band (liner), bubble canopy (courier); trader, medical and science keep the faceted bridge |
| 4 night windows | `Window` #FFD9A0 emissive 0.9 (bridge), new `CabinWindow` #FFD9A0 emissive 0.5 (passenger windows, lit doorways); mullions dark. `PaletteMetal` merged into `Palette` to stay at 8 materials |
| 5 night renders | `<kind>_night_ramp.png` from the ramp side for every ship (the belly and door floods are in view) |
| 6 trader ramp | a cargo ramp on the −Y side of the tail (stands in the doorway when stowed); rear legs 0.5 m forward; rear hover thrusters moved |
| 7 flight renders | near top-down camera (80°), ship centred over the pad (the parallax made it look off-centre) |
| 8 insets | 3 flank panel insets per side on shuttle, medical and science |

Triangles: trader 10 192, shuttle 8 654, liner 9 448, medical 7 044, science 8 520, courier 5 650; all 8 materials,
radius ≤ 7.46 m, height ≤ 13.25 m. Godot import done; `check` 151 scripts, 0 failed. The RENDER table in
`docs/requests/ART-B-to-RENDER.md` item 2 was regenerated from the GLB files (the trader ramp, thrusters and
materials changed). ART-HAB note: item 3. Not tested in the running game.

## 2026-09-25 — v3.1: critic round 12 (floodlights)

- Every ship: a large lit lens (r 0.18 m, `Light` in `Lights`) under the belly next to the ramp hinge, aimed at the
  ramp and the deck at its foot (steeper for the rear ramps of medical and science).
- Every flood is now an empty `Flood_<i>` (`extras.role = "flood"`, local +X = aim): 3–5 per ship. Positions and
  aims for all six ships: `docs/requests/ART-B-to-RENDER.md` item 3.
- Blender night renders place a warm 1 300 W spot on every `Flood_*`; `<kind>_night_ramp.png` re-rendered for all six.
- Triangles now: trader 10 296, shuttle 8 758, liner 9 552, medical 7 156, science 8 632, courier 5 746; 8 materials.
  Godot import done; `check` 157 scripts, 0 failed. Not tested in the running game.

## 2026-09-27 — v4.0: small rover pilot (V4 §5)

- `assets/models/vehicle_rover_small.glb` from `tools/blender/vehicle_rover_small.py` (library
  `tools/blender/vehicle_common.py`; 9 more glyphs added to `ship_common.GLYPHS`, ships unchanged).
- 6 wheels (r 0.44 m, staggered tread, amber hub caps), 6 coil-over struts that rise between body and fender (visible
  above the fender line), front and rear axles steer, faceted white hood with an amber stripe, graphite chassis and
  roll cage, solar sunshade, 4 headlights, 4 roof work lights, bed lamp, red tail lights, amber beacon, whip antenna,
  2 seats (low backs for the suit pack), cargo bed with drop tailgate and a removable `Cargo` load, code RV-01.
- 5 900 triangles (limit 6 000), 6 materials, COLOR_0 AO (wheels baked with self-shadow only, as they spin).
  L 4.31 × W 2.60 × H 2.66 m (antenna 3.46 m). GLB 308 KB; Godot `.scn` 156 KB.
- Nodes: `Body`, `Susp_*` → `Steer_*` → `Wheel_*`, `Door_Tailgate`, `Cargo`, `Lights`, `Light_*` (9), `Seat_1/2`,
  `Anchor_Board_1/2`, `Anchor_Controls`, `Anchor_Cargo`, `Dust_L/R`. Contract: `ART-B-to-RENDER.md` item 4.
- Renders `art/vehicles/`: `rover_small_turnaround.png`, `_scale.png` (suit colonists: seated in `Seat_2`, at the
  boarding point, at the tailgate), `_poses.png` (steer, suspension, tailgate), `_night.png`. `.gdignore` added.
- Requests: RENDER item 4, ART-HAB item 4 (depot bays), ART-NPC item 1 (driver pose). Godot import done; `check`
  179 scripts, 0 failed. Not tested in the running game.

## 2026-09-27 — v4.0: critic round 16 fixes, ART-NPC seat contract, medium rover, hopper, satellite, launch pad

**Round 16 fixes (small rover, 5 992 tris, 6 mats):** 1 graphite cycle fenders with a thin orange lip (accent now
colony orange #E07A3A everywhere, no yellow); 2 fenders 7 cm over the tyre and 3 cm thick, bare-metal skid plate,
body 10 cm lower; 3 dark tyres with 16 staggered block lugs, recessed rims with 5 bolts; 4 bed lamp half strength and
aimed down, amber corner markers; 5 roof tilted 3° with a frame edge. Wheel, strut and fender parts are a shared kit
(`vehicle_common.WheelKit`).

**ART-NPC seat contract (`ART-NPC-to-ART-B.md`):** small rover rebuilt to it — front axle to x 1.75, seats at
x 0.96, running boards 0.32 m under the floor at the door points, dash at +0.46, roof 1.62 m, handles at the measured
grip centres. `tools/blender/vehicle_fit.py` plays their clips on the exported rover: hands ≤ 3.0 cm, body only on the
cushion edge (≤ 2.1 cm). Differences written back in `ART-B-to-ART-NPC.md` item 2 (floor 0.82 m, not 0.32; hands
travel 5.6 cm in drive_sit; grab-hand points).

**New models:** medium rover (8 446 tris, 7 mats; 8 wheels, kit at 1.3×, pressurised hull, portholes, rear
airlock hatch in the door-kit style + ramp, roof rack with two Outpost Kits, reactor pack, dish, 6 seats), hopper
(4 162 tris, 8 mats; lander capsule, bubble canopy, 4 folding legs, 4 hover thrusters, tanks, rear vestibule + ladder,
3 seats), satellite (976 tris; sun-tracking wings, dish, scanner anchor), launch pad (2 092 tris; deck, mount, tower,
2 service arms, rocket node with Thruster_Main, floods).

Renders `art/vehicles/<id>_{turnaround,poses,night,scale}.png` (satellite: turnaround, poses). RENDER table:
`ART-B-to-RENDER.md` item 4 (replaced). ART-HAB: item 5. Size effect: the five `.scn` total 0.48 MB (pck ≈ 80.2 MB,
estimate). Godot import done; `check` 187 scripts, 0 failed. Not tested in the running game.

## 2026-09-27 — v4.0: critic round 19 fixes 1–5

1. Medium rover: faceted, framed cab (the trader's cockpit part; dark glass by day), bumper with winch and tow hooks.
2. Medium rover: band 0.23 m, desaturated purple #8F7FAE as paint; Accent = colony orange (fender lips, springs).
3. Hopper: 10-panel faceted body with seams, 4 access plates, hard belly ring, framed canopy (base ring + spine),
   vestibule faired into the hull with a collar frame and junction seams, 4 bell nozzles (the ships' engine_bell).
4. Medium rover portholes lit with CabinWindow (#FFD9A0, 0.5).
5. `art/vehicles/satellite_context.png`: in orbit over the planet limb.
Tris: medium 8 406 (8 mats), hopper 6 446 (8 mats). Moved nodes: medium Light_Work*, hopper Thruster_Hover_* (RENDER
item 4 updated). Size: the five .scn total 0.55 MB (pck ≈ 80.3 MB, estimate). `check` 189 scripts, 0 failed.
Not tested in the running game.
