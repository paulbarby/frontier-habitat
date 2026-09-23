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
