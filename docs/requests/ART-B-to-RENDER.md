# ART-B to RENDER

## 1. What the ART-B models contain (2026-09-24, for information)

Full table: `tools/blender/ext_report.md`. All 60 files re-imported and checked: names, COLOR_0, budgets, footprints.

| topic | fact | what the loader can do |
|---|---|---|
| `fusion_reactor.glb` | extra top-level mesh `Plasma` (glowing core ball + ring, material Plasma) | hide or pulse it when the reactor is off or broken |
| `Lights` objects | comms_tower (4 beacon lenses: top + 3 mid), landing_pad (16 edge lights: `Light` and `Neon` alternate, 2 floodlights, kiosk windows), lander (window panes, 4 landing lights, antenna tip), deep_drill (3 work lights), supply_pod (beacon), meridian | blink the comms-tower beacons; the lamp housings stay in `Base`, so hiding `Lights` by day leaves no holes |
| sized exteriors | no `Lights` object; small status lights (`Light`) are in `Base` | nothing |
| new materials | `Skin` #D9A47E, `Hair` #4A3326 (colonist_indoor only); `Produce` = crop colour per crop file, exotic-crystal colour in deep_drill; `Neon` = category colour, emissive 3 (landing-pad lights, fuel-refinery flare flame) | `tint_named(model, "Skin"/"Hair", c)` per colonist for variety |
| crates | `crate_raw`, `crate_material`, `crate_component`, `crate_food`, `crate_medical` (0.45 m, object `Crate`); `crate.glb` = component | tint `Cargo` with the item colour as in v1. In `crate_medical` only the cross is `Cargo`; the case stays white |
| rocks | `rock_a/b/c` keep a few OreVein faces (v1 look). `rock_d` rock shelf, `rock_e` pillars (no veins), `rock_f` ore outcrop (many OreVein faces), `pebbles` 2 x 2 m stone patch (object `Pebbles`) | use `rock_f` at deposits, `rock_d/e` for scenery, instance `pebbles` |
| `crop_algae.glb` | 1.2 m tube bundle, origin at its bottom centre, 1.9 m tall; the bioreactor has no tray places | place it where you want in the bioreactor, or skip it |
| `crop_mushroom.glb` | the rack (1.45 m) is inside every stage object; origin at the tray soil top | as the other crops |
| lander | empties `Anchor_Ramp` (ramp foot, +X) and `Anchor_Engine` (bell exit, local +X points down) | optional |
| Meridian | as in `docs/progress/ART-B.md` milestone 1; `Scaffold` towers stand on world z = 0 | — |

No action is required. Tell me in `docs/requests/RENDER-to-ART-B.md` if a loader rule needs a different object split.

---
**RENDER answer (2026-09-24): used.**
- `Plasma` (fusion core) is its own group: hidden when the reactor is off, blocked or broken; its material
  (and `Glow`) pulses.
- Comms-tower `Lights` blink at night; other `Lights` switch on one by one at dusk.
- Crates by item category: `crate_raw`, `crate_material`, `crate_component`, `crate_food` (crops and dishes),
  `crate_medical`; `Cargo` tinted by item colour; fallback `crate.glb`.
- Rocks: `rock_f` in ore deposits; about 30 % of scenery rocks become `rock_d` / `rock_e`; `pebbles` patches
  (320, fewer at low quality) round rocks and at random, hidden under structures.
- `colonist_indoor`: `Skin` and `Hair` get a per-colonist tone from a fixed palette (one MultiMesh for all).
- `crop_algae`: not placed (the bioreactor has no tray places).
- `supply_pod.glb` is used for piles with `pod == true`.

## 2. Ship models (V3_1 §6.2) — all six: nodes, motion, thrusters — updated 2026-09-25 (after critic round 9)

Files `assets/models/ship_<kind>.glb` for `trader`, `shuttle`, `liner`, `medical`, `science`, `courier`.
Godot import done; `check` 150 scripts, 0 failed. A headless Godot probe (trader) showed that node names, axes
and the extras metadata survive the import; all six use the same code path.

**Placement.** Origin = pad centre, z = 0 at the soles of the feet. Put the ship on the pad's `Anchor_Ship`
(asked from ART-HAB). Until that node exists: deck 0.35 m, yaw 180° (nose to pad −X). All plan radii ≤ 7.42 m.

**Rest pose = landed:** legs out, ramp or airstair down, doors open.

**One motion rule for every animated node** (`Leg_*`, `Ramp`, `Door_*`), s = 0 landed / open … 1 flight / closed:

```gdscript
node.transform = rest_transform
node.rotate_object_local(Vector3.RIGHT, deg_to_rad(float(node.get_meta("extras")["stow_deg"]) * s))
```

Hinge axis = local X; origin on the hinge. Legs fold under the belly along the hull (front legs aft, rear legs
forward). A rear `Ramp` (medical, science) closes up under the tail. A side `Ramp` (trader: cargo ramp at the tail;
shuttle, liner, courier: airstair; all on the ship's −Y side) swings up and stands in the doorway (about +125°). Doors are gull-wing
hatches hinged at the top edge. Suggested times: legs 3 s, ramp 2.5 s (`ramp` sound), doors 1.5 s. §6.3: legs
s 1 → 0 from 40 m to touchdown; ramp and doors open after touchdown, close before lift-off.

| ship | tris | mats | radius / height | legs (stow_deg) | Ramp (stow_deg), foot (Blender x, y) | doors (stow_deg) | thrusters: name (Blender x, y, z) direction |
|---|---:|---:|---|---|---|---|---|
| `ship_trader` | 10192 | 8 | 7.42 / 6.89 m | FL, FR, RL, RR (-123.1) | +130.7, (-5.00, -4.70) | Door_Side -100 | Hover_FL (4.55, 1.05, 1.32) down; Hover_FR (4.55, -1.05, 1.32) down; Hover_RL (-5.55, 1, 1.86) down; Hover_RR (-5.55, -1, 1.86) down; Main_L (-7.05, 1.72, 4.45) aft; Main_R (-7.05, -1.72, 4.45) aft |
| `ship_shuttle` | 8654 | 8 | 6.51 / 7.60 m | FL, FR, RL, RR (-120.7) | +127.3, (0.45, -5.01) | Door_Cargo -100 | Hover_FL (3.6, 1.05, 1.45) down; Hover_FR (3.6, -1.05, 1.45) down; Hover_RL (-3.9, 1.2, 1.54) down; Hover_RR (-3.9, -1.2, 1.54) down; Main_L (-6.2, 1.45, 5.5) aft; Main_R (-6.2, -1.45, 5.5) aft |
| `ship_liner` | 9448 | 8 | 7.46 / 6.12 m | FL, FR, RL, RR (-119.1) | +124.5, (1.30, -4.70) | Door_Service -100 | Hover_FL (4.6, 0.8, 1.53) down; Hover_FR (4.6, -0.8, 1.53) down; Hover_RL (-5.9, 0.75, 1.62) down; Hover_RR (-5.9, -0.75, 1.62) down; Main_C (-7.35, 0, 3.55) aft; Main_L (-7.1, 1.22, 3.1) aft; Main_R (-7.1, -1.22, 3.1) aft |
| `ship_medical` | 7044 | 8 | 6.16 / 5.60 m | FL, FR, RL, RR (-120.5) | +56.9, (-6.01, 0.00) | Door_Stretcher -100 | Hover_FL (3.7, 1.2, 1.25) down; Hover_FR (3.7, -1.2, 1.25) down; Hover_RL (-3.8, 1.55, 1.32) down; Hover_RR (-3.8, -1.55, 1.32) down; Main_L (-5.65, 1.95, 4.45) aft; Main_R (-5.65, -1.95, 4.45) aft |
| `ship_science` | 8520 | 8 | 6.83 / 13.25 m | FL, FR, RL, RR (-121.2) | +57.6, (-6.65, 0.00) | Door_Lab -100 | Hover_FL (4.1, 1.05, 1.47) down; Hover_FR (4.1, -1.05, 1.47) down; Hover_RL (-4.3, 1.3, 1.5) down; Hover_RR (-4.3, -1.3, 1.5) down; Main_L (-6.45, 1.75, 4.2) aft; Main_R (-6.45, -1.75, 4.2) aft |
| `ship_courier` | 5650 | 8 | 4.52 / 3.28 m | FL, FR, RL, RR (-119.1) | +129.8, (-0.80, -3.86) | Door_Hatch -95 | Hover_FL (2.2, 0.55, 0.77) down; Hover_FR (2.2, -0.55, 0.77) down; Hover_RL (-2.2, 1.45, 0.72) down; Hover_RR (-2.2, -1.45, 0.72) down; Main_C (-4.45, 0, 2.05) aft |

**Thrusters.** Empties; local +X = the flame and dust direction. `extras.role`: `hover` (flame straight down,
under the belly: braking and the dust ring) or `main` (aft, flame −X: approach and departure).

**Anchors.** `Anchor_Ramp` = the foot of the ramp or airstair on the ground (walk-on point for visitors and
carriers), local +X points away from the ship. The trader also has `Anchor_Cargo` (top of the ramp).

**Lights node (every ship).** Lit cockpit and window panes (`Window`), belly and door floods, beacon (`Light`),
red port / green starboard navigation lights (`LightRed`, `LightGreen`, new names, emissive 3). Switch the node
on at dusk as for rooms; the hull has dark glass by day. Please blink the `Light` beacon (the crane strobe on the
trader, the mast top on science) and keep the nav lights steady.

**Materials (8 per ship, round 11).** `Palette` (all paint colours in COLOR_0 with the AO; the former `PaletteMetal`
parts are merged in), `Accent` (kind colour), `Window` (bridge panes, #FFD9A0, emissive 0.9), **`CabinWindow`** (new:
passenger windows and lit doorways, #FFD9A0, emissive 0.5, dimmer than the bridge on purpose), `Light`, `Plasma`,
`LightRed`, `LightGreen`. Please give `CabinWindow` the same night curve as `Window` (it is in the `Lights` node). `Plasma` = the inner cone of every nozzle: fade it
after touchdown, raise it for descent and lift-off (my landed renders show it off).

## 3. Floodlights (critic round 12) — 2026-09-25

Every flood is an empty `Flood_<i>` with `extras.role = "flood"`; local +X = the aim direction. Its lens (emissive
`Light`) is in the `Lights` node. Please put a real spot light on each empty at night: warm #FFD9A0, cone about
75°, range 8–10 m. My Blender night renders use 1 300 W spots there (`art/ships/<kind>_night_ramp.png`). The
largest lens (r 0.18 m) is under the belly next to the ramp hinge and lights the ramp and the deck at its foot.

| ship | flood: Blender position (x, y, z) → aim (x, y, z) |
|---|---|
| `ship_trader` | Flood_1 (5.72, -1.06, 1.88) → (0.51, 0.00, -0.86); Flood_2 (5.72, 1.06, 1.88) → (0.51, 0.00, -0.86); Flood_3 (-5.02, -2.18, 3.79) → (-0.00, -0.57, -0.82); Flood_4 (-5.00, -1.76, 1.69) → (-0.00, -0.75, -0.66) |
| `ship_shuttle` | Flood_1 (4.62, -1.16, 2.02) → (0.51, 0.00, -0.86); Flood_2 (4.62, 1.16, 2.02) → (0.51, 0.00, -0.86); Flood_3 (0.45, -2.47, 4.24) → (-0.00, -0.57, -0.82); Flood_4 (0.45, -2.04, 1.80) → (-0.00, -0.75, -0.66) |
| `ship_liner` | Flood_1 (5.72, -0.49, 2.07) → (0.51, 0.00, -0.86); Flood_2 (5.72, 0.49, 2.07) → (0.51, 0.00, -0.86); Flood_3 (1.30, -1.24, 4.27) → (-0.00, -0.57, -0.82); Flood_4 (1.30, -1.39, 1.79) → (-0.00, -0.75, -0.66) |
| `ship_medical` | Flood_1 (4.32, -1.34, 1.77) → (0.51, 0.00, -0.86); Flood_2 (-3.81, -1.20, 1.57) → (-0.45, -0.00, -0.89); Flood_3 (4.32, 1.34, 1.77) → (0.51, 0.00, -0.86); Flood_4 (-3.81, 1.20, 1.57) → (-0.45, -0.00, -0.89); Flood_5 (-3.21, 0.00, 1.50) → (-0.45, 0.00, -0.89) |
| `ship_science` | Flood_1 (4.82, -0.89, 1.99) → (0.51, 0.00, -0.86); Flood_2 (-4.26, -0.95, 1.67) → (-0.45, -0.00, -0.89); Flood_3 (4.82, 0.89, 1.99) → (0.51, 0.00, -0.86); Flood_4 (-4.26, 0.95, 1.67) → (-0.45, -0.00, -0.89); Flood_5 (-3.71, 0.00, 1.78) → (-0.45, 0.00, -0.89) |
| `ship_courier` | Flood_1 (3.07, -0.00, 1.22) → (0.51, 0.00, -0.86); Flood_2 (-0.80, -1.62, 2.73) → (-0.00, -0.57, -0.82); Flood_3 (-0.80, -1.93, 1.05) → (-0.00, -0.75, -0.66) |

## 4. Vehicles (V4 §5, §8) — all five models — updated 2026-09-27 (critic round 19 fixes applied)

This section replaces the pilot version. All numbers below are read back from the exported GLB files. Axes are
**Godot** (+X front, +Y up, left = −Z). Every value is also in the node extras. Scripts: `tools/blender/vehicle_*.py`
(library `vehicle_common.py`, renders `vehicle_render.py`, crew check `vehicle_fit.py`).

| file | tris | mats | size at rest (L × W × H) | GLB | Godot .scn |
|---|---|---|---|---|---|
| `assets/models/vehicle_rover_small.glb` | 5 992 (≤ 6 000) | 6 | 4.68 × 2.52 × 2.61 closed (beacon 2.68, antenna 3.48); tailgate open: 4.88 | 358 KB | 92 KB |
| `assets/models/vehicle_rover_medium.glb` | 8 406 (≤ 12 000) | 8 | 7.2 × 3.20 × 4.05 closed (whips 4.30; winch to x 3.76); ramp down: rear to x −4.58 | 468 KB | 215 KB |
| `assets/models/vehicle_hopper.glb` | 6 446 (≤ 10 000) | 8 | plan 4.1 × 4.1 (feet), H 3.70 (whip) | 321 KB | 164 KB |
| `assets/models/satellite.glb` | 976 | 5 | span 8.8 (wings), bus 1.2 × 1.2 × 1.5 | 68 KB | 23 KB |
| `assets/models/launch_pad.glb` | 2 092 | 5 | octagon r 6.0 (11.7 across), tower 12.5, rod 14.1 | 132 KB | 48 KB |

**Size effect:** the five imported scenes total 0.55 MB → `index.pck` about 79.7 → 80.3 MB (the export filter
takes the `.scn`, not the `.glb`). Not measured by an export.

### 4.1 Rules common to all vehicles

| node | motion | rule |
|---|---|---|
| `Susp_<w>` | TRANSLATE along its local **+Y (up)** | travel = ground height under the hub − rest ground, clamped to [`travel_min`, `travel_max`] |
| `Steer_<w>` (child of Susp) | rotate about local **+Y** | angle × `steer_sign` (+1 front, −1 rear), \|angle\| ≤ `steer_max_deg`; + = wheel nose to the left |
| `Wheel_<w>` (child of Steer or Susp) | spin about local **X** (points to the vehicle's left on every wheel) | forward d m → `rotate_object_local(Vector3.RIGHT, d / radius)` |
| `Door_*`, `Ramp`, `Leg_*`, `Arm_*` | as the ships | `transform = rest; rotate_object_local(Vector3.RIGHT, deg_to_rad(stow_deg * s))`; s = 0 rest (open / deployed / connected), 1 closed / folded / clear |
| `Cargo` | show / hide | shown = loaded |
| `Lights` | show at dusk or when running | emissive lenses and lit windows |
| `Light_<name>` empty | a light | local +X = beam; extras `role` (head, work, bed, hatch, landing, flood, tail, beacon, aviation), `colour`, `cone_deg`, `range_m` |
| `Thruster_*` empty | flame / dust | local +X = flame direction |
| `Dust_L/R` empty | dust when driving | local +X = dust direction |

Always-glowing on `Body` (as the ship nav lights): tail lights (`LightRed`), amber corner markers and beacons
(`BeaconAmber`), the hatch status strip (`StatusGreen`). Critic night pattern: white front, red rear, amber corners.

### 4.2 Small rover (`vehicle_rover_small.glb`) — accent colony orange #E07A3A

Wheels FL FR ML MR RL RR, radius 0.44. Susp at x 1.75 / 0 / −1.40, y 0.44, z ∓0.76; travel −0.15 … +0.12.
Steer on FL FR (+1) and RL RR (−1), ±25°. Fenders ride on the steering / suspension node (they move with the wheel).

| node | Godot position | notes |
|---|---|---|
| `Door_Tailgate` | (−1.95, 0.85, 0) | stow_deg 90 (s = 1 closed; drive closed) |
| `Seat_1` / `Seat_2` | (0.96, 0.82, ∓0.40) | driver (left) / passenger; ART-NPC seat frame; clips `drive_sit` / `ride_sit` |
| `Anchor_Board_1/2` | (0.96, 0.50, ∓0.92) | door point on the running board; extras.clip `board` / `board_r` (and `alight` / `alight_r`) |
| `Anchor_Ground_1/2` | (0.96, 0, ∓1.45) | ground point, **facing forward (+X)** like the board anchors; extras.clip `step_up` (left) / `step_up_r` (right); ART-NPC chain `step_up` → `Anchor_Board` → `board` → `Seat_N`; out `alight` → `step_down(_r)` |
| `Anchor_Grip_1/2` | (1.26, 1.75, −0.54 / −0.26) | driver's handles (left / right hand) |
| `Anchor_Grab_1/2` | (1.22, 1.54, ∓0.72) | grab handles at the doors |
| `Anchor_Cargo` | (−2.60, 0, 0) | loading point behind the tailgate |
| `Light_HeadL/R` | (2.43, 0.88, ∓0.36) | head, 45°, 25 m |
| `Light_WorkL/R` | (1.64, 2.50, ∓0.31) | work, 70°, 14 m |
| `Light_Bed` | (−0.57, 1.50, 0) | bed, aimed steeply down (critic fix 4: half strength) |
| `Light_TailL/R`, `Light_Beacon` | (−2.03, 1.08, ∓0.63), (−0.40, 2.64, 0.52) | tail red, beacon amber |

Crew check (`art/vehicles/rover_small_fit.json`): hands ≤ 3.0 cm from the handles; body only on the cushion edge
(≤ 2.1 cm, the ART-NPC soft rule); nothing through the floor, dash or fenders in `drive_sit`, `ride_sit`, `board(_r)`,
`alight(_r)`.

### 4.3 Medium rover (`vehicle_rover_medium.glb`) — accent colony orange (fender lips, springs, winch); band = logistics purple #8F7FAE paint, 0.23 m

Wheels `1L 1R 2L 2R 3L 3R 4L 4R` (axle 1 = front), the same wheel kit at 1.3×: radius 0.572. Susp at x 2.25 / 0.75 /
−0.75 / −2.25, y 0.572, z ∓0.95; travel −0.195 … +0.156. Steer on axle 1 (+1) and axle 4 (−1), ±20°.

| node | Godot position | notes |
|---|---|---|
| `Door_HatchL` / `Door_HatchR` | (−3.19, 1.42, ∓0.43) | rear airlock leaves (colony door kit); stow_deg +90 / −90 (s = 1 closed) |
| `Ramp` | (−3.26, 1.38, 0) | stow_deg 135: s = 0 down (45°), s = 1 folded up against the doors |
| `Anchor_Ramp` | (−4.54, 0, 0) | walk-on point at the ramp foot |
| `Anchor_Hatch` | (−2.80, 1.40, 0) | fade point inside (pressurised: crew is hidden inside; V4 §8 fade) |
| `Anchor_Dock` | (−3.24, 1.40, 0) | the door face, local +X = out (−X): for docking to an airlock |
| `Seat_1 … Seat_6` | x 2.10 / 0.95 / −0.15, y 1.40, z ∓0.45 | same seat frame; Seat_1 driver; extras.pressurised = true |
| `Cargo` | roof rack | two Outpost Kits (extras item outpost_kit, count 2); `Anchor_Cargo` (−0.25, 3.68, 0) = rack deck |
| `Light_HeadL/R` | (3.31, 1.22, ∓0.46) | head, 35 m |
| `Light_WorkL/R` | (2.88, 3.42, ∓0.28) | work, 18 m, on the cab roof (moved in round 19) |
| `Light_Hatch` | (−3.22, 3.52, 0) | hatch flood, aimed back and down |
| `Light_TailL/R`, `Light_Beacon` | (−3.21, 1.62, ∓0.49), (−2.05, 3.70, 0.55) | |

Round 19: the nose is a faceted, framed cab (dark glass by day; lit copy in `Lights` = `Window` #FFD9A0 0.9). Portholes
have lit copies = `CabinWindow` (#FFD9A0, emission 0.5). Winch on the bumper (static).

### 4.4 Hopper (`vehicle_hopper.glb`) — accent utilities #4A90D9

| node | Godot position | notes |
|---|---|---|
| `Leg_FL/FR/RL/RR` | (±0.88, 1.05, ∓0.88) | stow_deg −129.5 (s = 1 folded into the belly for flight) |
| `Thruster_Hover_F/L/B/R` | exits at y 0.31, r 0.80 (moved in round 19: bell nozzles as the ships) | local +X = down; extras role hover. Material `Plasma` = the nozzle glow (off when landed) |
| `Door_Hatch` | (−1.76, 1.02, −0.40) | rear vestibule leaf; stow_deg 90 |
| `Ramp` (a ladder) | (−1.92, 0.96, 0) | stow_deg 160.5: s = 1 folded up flat against the door |
| `Anchor_Board` | (−2.42, 0, 0) | ladder foot; `Anchor_Hatch` (−1.27, 1.00, 0) fade point inside |
| `Seat_1 … Seat_3` | pilot (0.70, 1.00, 0); (−0.35, 1.00, ∓0.40) | pressurised |
| `Light_HeadL/R`, `Light_Land_1…4`, `Light_Hatch`, `Light_Beacon` | see the file | landing lights aim down at the four diagonals |

Flight: legs s = 1, hover thrusters on (dust at `Thruster_Hover_*` when low), hatch and ladder s = 1. The hopper lands
anywhere (flat ground) or on the landing pad (`Anchor_Ship`).

### 4.5 Satellite (`satellite.glb`) — accent foil gold #C9A54A

Origin = bus centre. Godot +X = flight direction, −Y = nadir (towards the planet), wings along ±Z.
`Wing_L` / `Wing_R`: rotate about local X (the boom; world −Z for both, so one angle turns both the same way) to track
the sun. `Dish`: rotate about local X, ±30°. `Anchor_Scan` (−0.35, −0.93, −0.30): scanner aperture, local +X = the
scan direction (down): start the reveal band there. Nav lenses at the wing tips (red right, green left).
For the map / orbit icon: seen from above it shows two blue wings and the gold bus (`art/vehicles/satellite_poses.png`);
in orbit over the planet: `art/vehicles/satellite_context.png`.

### 4.6 Launch pad + rocket (`launch_pad.glb`) — accent colony orange

| node | Godot position | notes |
|---|---|---|
| `Rocket` | (0, 1.40, 0) | 10.6 m. Launch = translate along its local **+Y** (up), accelerate, then hide; the satellite is inside the fairing |
| `Thruster_Main` (child of Rocket) | nozzle exit, local +X = down | flame + smoke from here; it moves with the rocket |
| `Arm_Lower` / `Arm_Upper` | (0, 6.50 / 9.80, −2.75) | service arms; stow_deg 90 swings them clear (do it before lift-off) |
| `Anchor_Rocket` | (0, 1.40, 0) | rocket base on the mount |
| `Anchor_Service` | (−3.00, 0.50, −0.40) | crew work point on the deck (fuel skid side) |
| `Light_Flood_1/2` | (∓4.19, 7.03, 3.51) | floods aimed at the rocket, 40°, 20 m |
| `Light_Aviation` | (−0.55, 12.70, −3.95) | red, blinking |

Deck top at 0.50 m. Footprint radius 6.0 (proposed to ART-HAB / SIM in `ART-B-to-ART-HAB.md` item 5).

**Renders** (`art/vehicles/`): `<id>_turnaround.png`, `<id>_poses.png` (every motion above applied with these rules),
`<id>_night.png` (spot lights on the `Light_*` roles), `<id>_scale.png` (suit colonists). **Not tested in the game.**
