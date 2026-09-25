# ART-B asset report

Written by `tools/blender/ext_verify.py` (Blender 5.2.1 LTS). Every file is re-imported into Blender and checked:
object names, anchors, materials, COLOR_0 (vertex-colour AO) on every mesh, triangles vs budget, horizontal
radius vs footprint (level parts included), and that the size-M copy `<id>.glb` equals `<id>_m.glb`.

Rebuild everything (Git Bash, from the project root):

```bash
B="C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"
for s in meridian colonists crops energy life industry singles props; do
  "$B" --background --factory-startup --python tools/blender/ext_$s.py; done
"$B" --background --factory-startup --python tools/blender/ext_render.py -- --thumbs all --sheets all
"$B" --background --factory-startup --python tools/blender/ext_verify.py
```


## Meridian and debris (`tools/blender/ext_meridian.py`)

| file | triangles | budget | per object | radius / footprint | z min .. max | KB | flags |
|---|---:|---:|---|---|---|---:|---|
| `meridian.glb` | 20564 | 30000 | Damage1 1392, Damage2 618, Damage3 634, EngineGlow 336, Hull 13794, Lights 566, Scaffold 3224 | 23.65 / - | -2.00 .. 9.82 | 1044 | ok anchors: Anchor_Engine_L, Anchor_Engine_R, Anchor_Ramp |
| `debris_a.glb` | 296 | 900 | Base 296 | 2.24 / - | -0.24 .. 0.99 | 24 | ok |
| `debris_b.glb` | 568 | 900 | Base 568 | 1.68 / - | -0.08 .. 1.32 | 26 | ok |
| `debris_c.glb` | 468 | 900 | Base 468 | 2.25 / - | -0.07 .. 1.03 | 34 | ok |

## Colonists (`tools/blender/ext_colonists.py`)

| file | triangles | budget | per object | radius / footprint | z min .. max | KB | flags |
|---|---:|---:|---|---|---|---:|---|
| `colonist_suit.glb` (+ `colonist.glb`) | 1438 | 1500 | ArmL 178, ArmR 178, Body 754, LegL 164, LegR 164 | 0.44 / - | 0.00 .. 1.82 | 75 | ok |
| `colonist_indoor.glb` | 1244 | 1500 | ArmL 184, ArmR 184, Body 636, LegL 120, LegR 120 | 0.42 / - | 0.00 .. 1.78 | 60 | ok |

## Crops (`tools/blender/ext_crops.py`)

| file | triangles | budget | per object | radius / footprint | z min .. max | KB | flags |
|---|---:|---:|---|---|---|---:|---|
| `crop_potato.glb` (+ `crop.glb`) | 2670 | 4500 | Stage1 330, Stage2 918, Stage3 1422 | 1.48 / - | 0.00 .. 0.55 | 244 | ok |
| `crop_wheat.glb` | 2120 | 4500 | Stage1 560, Stage2 390, Stage3 1170 | 1.50 / - | 0.00 .. 0.74 | 148 | ok |
| `crop_greens.glb` | 2664 | 4500 | Stage1 384, Stage2 840, Stage3 1440 | 1.43 / - | 0.01 .. 0.22 | 258 | ok |
| `crop_tomato.glb` | 2480 | 4500 | Stage1 208, Stage2 832, Stage3 1440 | 1.36 / - | -0.00 .. 0.95 | 188 | ok |
| `crop_soybean.glb` | 2340 | 4500 | Stage1 378, Stage2 810, Stage3 1152 | 1.37 / - | 0.00 .. 0.47 | 221 | ok |
| `crop_herbs.glb` | 2088 | 4500 | Stage1 392, Stage2 800, Stage3 896 | 1.40 / - | -0.00 .. 0.45 | 202 | ok |
| `crop_mushroom.glb` | 3408 | 4500 | Stage1 976, Stage2 1216, Stage3 1216 | 1.47 / - | 0.00 .. 1.45 | 218 | ok |
| `crop_algae.glb` | 2310 | 4500 | Stage1 658, Stage2 826, Stage3 826 | 0.59 / - | 0.00 .. 2.07 | 116 | ok |

## Energy (sized) (`tools/blender/ext_energy.py`)

| file | triangles | budget | per object | radius / footprint | z min .. max | KB | flags |
|---|---:|---:|---|---|---|---:|---|
| `solar_array_s.glb` | 1586 | 3000 | Base 408, L2 408, L3 136, L4 156, L5 478 | 2.11 / 2.2 | 0.00 .. 1.99 | 118 | ok anchors: Anchor_Service |
| `solar_array_m.glb` (+ `solar_array.glb`) | 2098 | 4500 | Base 920, L2 408, L3 136, L4 156, L5 478 | 3.11 / 3.2 | 0.00 .. 2.34 | 152 | ok anchors: Anchor_Service |
| `solar_array_l.glb` | 2990 | 6500 | Base 1812, L2 408, L3 136, L4 156, L5 478 | 4.31 / 4.4 | 0.00 .. 2.79 | 213 | ok anchors: Anchor_Service |
| `solar_array_xl.glb` | 3698 | 9000 | Base 2224, L2 408, L3 248, L4 340, L5 478 | 5.51 / 5.6 | -0.02 .. 3.74 | 248 | ok anchors: Anchor_Service |
| `wind_turbine_s.glb` | 2498 | 3000 | Base 848, L2 408, L3 248, L4 268, L5 478, Rotor 248 | 1.08 / 1.2 (rotor 1.87) | -0.05 .. 8.28 | 158 | ok anchors: Anchor_Service |
| `wind_turbine_m.glb` (+ `wind_turbine.glb`) | 2618 | 4500 | Base 968, L2 408, L3 248, L4 268, L5 478, Rotor 248 | 1.51 / 1.6 (rotor 2.23) | -0.05 .. 11.77 | 168 | ok anchors: Anchor_Service |
| `wind_turbine_l.glb` | 2954 | 6500 | Base 1304, L2 408, L3 248, L4 268, L5 478, Rotor 248 | 2.00 / 2.2 (rotor 2.75) | -0.05 .. 16.47 | 190 | ok anchors: Anchor_Service |
| `wind_turbine_xl.glb` | 2954 | 9000 | Base 1304, L2 408, L3 248, L4 268, L5 478, Rotor 248 | 2.49 / 2.8 (rotor 3.27) | -0.05 .. 22.16 | 190 | ok anchors: Anchor_Service |
| `battery_s.glb` | 1786 | 3000 | Base 608, L2 408, L3 136, L4 156, L5 478 | 1.25 / 1.3 | 0.00 .. 2.48 | 125 | ok anchors: Anchor_Service |
| `battery_m.glb` (+ `battery.glb`) | 2140 | 4500 | Base 962, L2 408, L3 136, L4 156, L5 478 | 1.76 / 1.8 | 0.00 .. 2.76 | 149 | ok anchors: Anchor_Service |
| `battery_l.glb` | 2674 | 6500 | Base 1496, L2 408, L3 136, L4 156, L5 478 | 2.45 / 2.5 | 0.00 .. 2.91 | 185 | ok anchors: Anchor_Service |
| `battery_xl.glb` | 3118 | 9000 | Base 1940, L2 408, L3 136, L4 156, L5 478 | 3.16 / 3.2 | 0.00 .. 3.08 | 219 | ok anchors: Anchor_Service |

## Life support (sized) (`tools/blender/ext_life.py`)

| file | triangles | budget | per object | radius / footprint | z min .. max | KB | flags |
|---|---:|---:|---|---|---|---:|---|
| `water_extractor_s.glb` | 2266 | 3000 | Base 864, L2 408, L3 248, L4 268, L5 478 | 1.83 / 1.9 | 0.00 .. 4.36 | 148 | ok anchors: Anchor_Service |
| `water_extractor_m.glb` (+ `water_extractor.glb`) | 2828 | 4500 | Base 1426, L2 408, L3 248, L4 268, L5 478 | 2.53 / 2.6 | 0.00 .. 5.66 | 170 | ok anchors: Anchor_Service |
| `water_extractor_l.glb` | 3320 | 6500 | Base 1918, L2 408, L3 248, L4 268, L5 478 | 3.33 / 3.4 | 0.00 .. 7.16 | 203 | ok anchors: Anchor_Service |
| `water_extractor_xl.glb` | 3800 | 9000 | Base 2398, L2 408, L3 248, L4 268, L5 478 | 4.13 / 4.2 | 0.00 .. 6.16 | 222 | ok anchors: Anchor_Service |
| `reservoir_s.glb` | 2074 | 3000 | Base 672, L2 408, L3 248, L4 268, L5 478 | 2.13 / 2.2 | 0.00 .. 2.93 | 124 | ok anchors: Anchor_Service |
| `reservoir_m.glb` (+ `reservoir.glb`) | 2586 | 4500 | Base 1184, L2 408, L3 248, L4 268, L5 478 | 2.93 / 3.0 | 0.00 .. 4.28 | 148 | ok anchors: Anchor_Service |
| `reservoir_l.glb` | 3166 | 6500 | Base 1764, L2 408, L3 248, L4 268, L5 478 | 3.93 / 4.0 | 0.00 .. 4.06 | 174 | ok anchors: Anchor_Service |
| `reservoir_xl.glb` | 2886 | 9000 | Base 1484, L2 408, L3 248, L4 268, L5 478 | 4.93 / 5.0 | -0.01 .. 7.08 | 174 | ok anchors: Anchor_Service |

## Industry (sized) (`tools/blender/ext_industry.py`)

| file | triangles | budget | per object | radius / footprint | z min .. max | KB | flags |
|---|---:|---:|---|---|---|---:|---|
| `regolith_harvester_s.glb` | 2102 | 3000 | Base 924, L2 408, L3 136, L4 156, L5 478 | 2.13 / 2.2 | -0.00 .. 3.07 | 147 | ok anchors: Anchor_Service |
| `regolith_harvester_m.glb` (+ `regolith_harvester.glb`) | 2686 | 4500 | Base 1508, L2 408, L3 136, L4 156, L5 478 | 2.93 / 3.0 | -0.00 .. 3.25 | 184 | ok anchors: Anchor_Service |
| `regolith_harvester_l.glb` | 3174 | 6500 | Base 1996, L2 408, L3 136, L4 156, L5 478 | 3.73 / 3.8 | -0.00 .. 3.55 | 214 | ok anchors: Anchor_Service |
| `regolith_harvester_xl.glb` | 3720 | 9000 | Base 2318, L2 408, L3 248, L4 268, L5 478 | 4.60 / 4.6 | -0.02 .. 4.73 | 242 | ok anchors: Anchor_Service |
| `fuel_refinery_s.glb` | 2854 | 3000 | Base 1452, L2 408, L3 248, L4 268, L5 478 | 2.53 / 2.6 | -0.00 .. 4.73 | 174 | ok anchors: Anchor_Service |
| `fuel_refinery_m.glb` (+ `fuel_refinery.glb`) | 3710 | 4500 | Base 2308, L2 408, L3 248, L4 268, L5 478 | 3.43 / 3.5 | -0.00 .. 6.61 | 219 | ok anchors: Anchor_Service |
| `fuel_refinery_l.glb` | 4424 | 6500 | Base 3022, L2 408, L3 248, L4 268, L5 478 | 4.33 / 4.4 | -0.00 .. 7.68 | 253 | ok anchors: Anchor_Service |
| `fuel_refinery_xl.glb` | 6400 | 9000 | Base 4998, L2 408, L3 248, L4 268, L5 478 | 5.33 / 5.4 | -0.00 .. 8.75 | 359 | ok anchors: Anchor_Service |

## Single-size structures (`tools/blender/ext_singles.py`)

| file | triangles | budget | per object | radius / footprint | z min .. max | KB | flags |
|---|---:|---:|---|---|---|---:|---|
| `fusion_reactor.glb` | 7338 | 9000 | Base 5132, L2 408, L3 248, L4 416, L5 478, Plasma 656 | 6.22 / 6.5 | -0.05 .. 4.86 | 366 | ok anchors: Anchor_Service |
| `deep_drill.glb` | 4088 | 6500 | Base 2650, L2 408, L3 248, L4 268, L5 478, Lights 36 | 3.44 / 3.5 | -0.04 .. 15.23 | 271 | ok anchors: Anchor_Service |
| `comms_tower.glb` | 2440 | 4500 | Base 2248, Lights 192 | 2.35 / 2.5 | -0.05 .. 24.35 | 160 | ok anchors: Anchor_Service |
| `lander.glb` | 4076 | 6500 | Base 3904, Lights 172 | 5.96 / 5.5 | -0.03 .. 8.18 | 203 | ok anchors: Anchor_Engine, Anchor_Ramp |
| `landing_pad.glb` | 6326 | 9000 | Base 5592, Lights 734 | 11.42 / 11.5 | 0.00 .. 4.43 | 331 | ok anchors: Anchor_Fuel, Anchor_Service, Anchor_Ship |

## Props (`tools/blender/ext_props.py`)

| file | triangles | budget | per object | radius / footprint | z min .. max | KB | flags |
|---|---:|---:|---|---|---|---:|---|
| `supply_pod.glb` | 780 | 1500 | Base 756, Lights 24 | 1.57 / - | 0.00 .. 1.62 | 44 | ok |
| `crate_raw.glb` | 76 | 400 | Crate 76 | 0.33 / - | 0.00 .. 0.44 | 10 | ok |
| `crate_material.glb` | 304 | 400 | Crate 304 | 0.32 / - | 0.00 .. 0.40 | 24 | ok |
| `crate_component.glb` (+ `crate.glb`) | 158 | 400 | Crate 158 | 0.32 / - | 0.00 .. 0.43 | 15 | ok |
| `crate_food.glb` | 160 | 400 | Crate 160 | 0.32 / - | 0.00 .. 0.43 | 15 | ok |
| `crate_medical.glb` | 188 | 400 | Crate 188 | 0.32 / - | 0.00 .. 0.45 | 16 | ok |
| `rock_a.glb` | 178 | 600 | Rock 178 | 1.42 / - | -0.03 .. 1.15 | 18 | ok |
| `rock_b.glb` | 196 | 600 | Rock 196 | 1.34 / - | -0.03 .. 0.98 | 19 | ok |
| `rock_c.glb` | 108 | 600 | Rock 108 | 0.68 / - | -0.03 .. 1.05 | 12 | ok |
| `rock_d.glb` | 146 | 600 | Rock 146 | 1.86 / - | -0.03 .. 1.04 | 16 | ok |
| `rock_e.glb` | 188 | 600 | Rock 188 | 0.99 / - | -0.03 .. 2.16 | 19 | ok |
| `rock_f.glb` | 210 | 600 | Rock 210 | 1.24 / - | -0.03 .. 0.76 | 21 | ok |
| `pebbles.glb` | 316 | 600 | Pebbles 316 | 1.24 / - | -0.02 .. 0.13 | 33 | ok |

## Thumbnails (`assets/thumbs/`, 256 x 256, transparent, level parts hidden)

`battery_l.png`, `battery_m.png`, `battery_s.png`, `battery_xl.png`, `comms_tower.png`, `crop_algae.png`, `crop_greens.png`, `crop_herbs.png`, `crop_mushroom.png`, `crop_potato.png`, `crop_soybean.png`, `crop_tomato.png`, `crop_wheat.png`, `deep_drill.png`, `fuel_refinery_l.png`, `fuel_refinery_m.png`, `fuel_refinery_s.png`, `fuel_refinery_xl.png`, `fusion_reactor.png`, `lander.png`, `landing_pad.png`, `meridian.png`, `meridian_wreck.png`, `regolith_harvester_l.png`, `regolith_harvester_m.png`, `regolith_harvester_s.png`, `regolith_harvester_xl.png`, `reservoir_l.png`, `reservoir_m.png`, `reservoir_s.png`, `reservoir_xl.png`, `solar_array_l.png`, `solar_array_m.png`, `solar_array_s.png`, `solar_array_xl.png`, `water_extractor_l.png`, `water_extractor_m.png`, `water_extractor_s.png`, `water_extractor_xl.png`, `wind_turbine_l.png`, `wind_turbine_m.png`, `wind_turbine_s.png`, `wind_turbine_xl.png`

**Result:** 60 files checked, 0 with flags.

## Conventions and limits

- AO: BVH ray cast per face corner (`ext_common.bake_ao`), FLOAT_COLOR corner attribute `AO`, exported as COLOR_0
  (UNSIGNED_SHORT normalized). White = open. Optional objects (L2..L5, Rotor, Damage*, Scaffold, Stage*) do not
  darken the main object. Same method as ART-A.
- New material names: `Skin`, `Hair` (indoor colonist), `Produce` (per file: crop colour; exotic-crystal colour in
  `deep_drill`). `Neon` = category colour, emissive 3 (landing-pad edge lights, fuel-refinery flare).
- `fusion_reactor` has an extra top-level mesh `Plasma` (core and ring), so the game can hide it when the reactor is off.
- Single-size structures and props use a `Lights` object for emissive lenses (comms tower beacons, landing-pad edge
  lights, lander windows, deep-drill work lights, supply-pod beacon). Sized exteriors keep small status lights in Base.
- Meridian: tilt baked in (pitch 4 deg nose down, roll 2 deg -Y down); nose reaches z = -2.0. Hull x -21.95 .. 21.53;
  with the dirt berm x up to 23.64. The SIM capsule (length 40) covers x -20 .. 20 (see docs/requests/ART-B-to-SIM.md).
- `crop_algae` has no tray place in the bioreactor; it is a 1.2 m accessory with its origin at the bottom centre.
- Copies with v1 names: `solar_array`, `wind_turbine`, `battery`, `water_extractor`, `reservoir`,
  `regolith_harvester`, `fuel_refinery` (= size M), `colonist` (= suit), `crop` (= potato), `crate` (= component).
  Running v1 `build_assets.py` without `--only` would overwrite some of them (docs/requests/ART-B-to-ART-A.md).

## Weak spots

- Sized exteriors use 30-60 % of their triangle budgets; detail is in shape, not in triangle count.
- Vertex AO on long thin parts (colonist limbs, lattice legs) shows soft streaks near joints; it is faint at game distance.
- Mushroom caps (item colour #C8B8A6) have low contrast against the brown substrate blocks.
- The Meridian hull is smooth-lofted; its damage is decals and plates on top of the intact hull, so breaches have no
  real depth. Sand drifts were removed because they read as paint.
- Not tested in Godot (no Godot runs by this agent): COLOR_0 multiply, KHR emissive strength, Glass blending, Rotor spin
  axis and limb pivots are checked only in Blender.
