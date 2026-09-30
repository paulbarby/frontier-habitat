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

## 5. v5.0 super dome — PILOT files, groups, floors, materials (V5 §7, §8) — 2026-09-29

**Files** (all share one origin: the dome centre on the ground; no offsets or rotations between them). Contract in
`tools/blender/dome_common.py`; summary in `assets/models/dome_manifest.json` (floors, groups, stages, venues, anchors).

| file | top-level nodes | tris |
|---|---|---|
| `dome_shell.glb` | `Foundation`, `Promenade`, `Gates`, `Dome` | 17 526 |
| `dome_floor1.glb` | `Floor_1` (Struct_1, Shell_1, Lamps_1, Venue_<id> + VenueLamps_<id> × 12) | 12 498 |
| `dome_floor2.glb` … `dome_floor4.glb` | `Floor_2` … `Floor_4` (Struct, Shell, Lamps) | 8 640 / 9 216 / 9 216 |
| `dome_floor5.glb` | `Floor_5`, `Floor_Roof` | 12 360 |
| `dome_atrium.glb` | `Atrium`, `Lifts`, `Lift_0` … `Lift_3` | 6 890 |

Imported size (`.godot/imported/*.scn`): **1.83 MB** in total (my allocation is now +30 MB).

**Floors (Blender Z = Godot Y):** floor tops L1 0.30, L2 5.30, L3 9.50, L4 13.70, L5 17.90, roof 22.10; slab 0.35.
The slab of level n (n ≥ 2) is in `Floor_<n>`: its underside (with the downlights) is the ceiling of level n−1.
**Floor cutaway:** viewing floor k → hide `Floor_<n>` for n > k, `Floor_Roof`, `Dome` (and optionally `Lifts`).
`art/dome/pilot_cutaway_L1.png` is exactly that rule for k = 1.

**Group meaning / build stages** (node extras `stage`): `Foundation` → `Floor_<n>/Struct_<n>` (level_n) →
`Floor_Roof` → `Dome` → fit-out (`Shell_<n>`, `Lamps_<n>`, `Atrium`, `Promenade`, then `Venue_<id>` one by one).
`Gates` and `Lifts` (shafts) come with the structure. There is no separate scaffold mesh yet (next step).

**Lifts:** `Lift_<i>` (i = 0..3) are the cabs, rest at L1. Move them along local +Y (Godot) to `extras.stops`
(metres above rest: 0, 5.0, 9.2, 13.4, 17.6, 21.8), `speed_mps` 1.5. Doors face the gallery (+X local = outwards).

**Materials** (new names in bold; the others you already handle):
| material | use |
|---|---|
| `Glass` | dome panels, balustrades, shop fronts, lift glass. **Double-sided** in these files (seen from inside and outside) |
| **`Water`** | pool surface, fountain (alpha 0.78, emission #3AB8E8 × 0.35): please give it your water look and a night glow |
| **`SignCyan` `SignMagenta` `SignAmber` `SignGreen`** | shop sign letters, bottle shelf strips, stage lights (emission 3.0, like Neon) |
| `LightStrip` | the gallery edge strips (rings of light at night) |
| `Light` | downlights under every slab, dome node lights (1 per geodesic vertex), lamp posts, pool lights |
| `CabinWindow` | outer windows, shop back walls, unit windows (night curve as the ships) |
| `Screen` | shop screens, directory boards |

**Draw calls:** 58 mesh nodes in the 7 files; the groups are already merged per floor / per venue, so one dome is
about 58 × (materials per node, 2–6) surfaces before your per-group merge. Please keep `Glass` in its own sorted
pass (large transparent dome).

**Anchors** (all carry extras `floor`, `height`): `Anchor_Gate_<i>` / `Anchor_GateIn_<i>` (12 gates),
`Anchor_Venue_<id>` (door point in the colonnade, +X into the venue), `Anchor_Work_<id>_<k>`, `Anchor_Seat_<id>_<k>`,
`Anchor_Lift_<i>_<floor>` (floor 6 = roof), `Anchor_Unit_<floor>_<sector>` (L3–L5), `Anchor_Lounger_<k>`,
`Anchor_Swim_<k>` (at the water line), `Anchor_SlideTop/End`, `Anchor_Lifeguard`, `Anchor_Bench_<k>`,
`Anchor_Stage`, `Anchor_Plaza_<k>`, `Anchor_Crown`. Full list in the manifest.

**Arcade screen (V5 §4.5):** comes with the gaming lounge (after the pilot): the Prism Shift cabinet screen will be
its own material **`ArcadeScreen`** on a quad with UV 0..1, for your attract-loop shader.

Renders: `art/dome/pilot_overview_day.png`, `pilot_overview_night.png`, `pilot_atrium_pool.png`,
`pilot_gallery_L1.png`, `pilot_cutaway_L1.png` (Blender, not the game). **Not tested in the game.**

## 6. Super dome after critic round 24 — glass, window tones, lights — 2026-09-29

1. **Glass (fix 3, please match in the game).** `Glass` is now #9CC9DC, alpha 0.22, double-sided. The Blender
   preview adds a fresnel term: opacity 0.18 facing the camera → 0.62 at grazing angles (Layer Weight, blend 0.35),
   roughness 0.04, reflecting the sky. Please give the dome glass the same: a faint tint, 25–40 % sky reflection at
   grazing angles, and check its sort order against the ring building (it covers everything).
2. **New emissive materials** (register them for the night curve like `CabinWindow`):
   `WindowAmber` (#FFB45E, 0.75), `WindowCream` (#FFF1D6, 0.6), `WindowCool` (#B8DCFF, 0.6). Windows now mix
   `CabinWindow`, `Window`, these three, and 12–26 % dark glass (Palette). The dome joint lights are `WindowAmber`.
3. **Light anchors** (real lights, your choice of count; extras role / colour / cone / range):
   `Light_Lamp_P0..23` (promenade lamp posts, warm), `Light_Lamp_A0..5` (atrium lamp posts, warm #FFC88A),
   `Light_Pool_0..3` (under the pool water, cyan #38D8FF, aim up). The pool's underwater lenses are `SignCyan`.
4. **Floor lines** on the outer face: `SignMagenta` (L1), `SignCyan` (L2), `LightStrip` (L3, L5), `SignAmber` (L4).
   L2 carries the outward venue signs and 4 neon billboards (`Screen` panels framed in the Sign colours).
5. `Water` is now #1D78A8, alpha 0.58, emission #38D8FF × 0.55; the pool is 1.6 m deep with a tile grid.

## 7. Super dome: L2 venues, accommodation, construction stages, round 26 glass — 2026-09-29

**New / changed files:** `dome_floor2.glb` (13 venues), `dome_floor3..5.glb` (units and hotel rooms, `Unit_<floor>_<s>`
nodes under `Floor_<n>`), `dome_scaffold.glb` (new). Full list and the stage table: `assets/models/dome_manifest.json`.

1. **PRISM SHIFT cabinet (V5 4.5):** node `ArcadeScreen_PrismShift` (child of `Floor_2`), one quad, material
   **`ArcadeScreen`** (#05060A, emission #FF4FD8 × 0.5 as a stand-in), **TEXCOORD_0 = 0..1**: u to the player's right,
   v up. Please put your attract-loop shader on it. The player stands at `Anchor_ArcadePrism_arcade_0` (extras
   egg prism_shift, clip play_arcade). The other 8 cabinets use `Screen`.
2. **Club** (`Venue_club`, L2 sectors 13–18): LED dance floor tiles (Sign materials), 3 podiums with chrome poles, light
   rig with coloured lamps, LED wall (`Screen`), DJ booth, 4 booths, bar, disco ball. Anchors: `Anchor_Dancer_club_<k>`
   (robot dancers on the podium tops, 0.35 m in front of the pole; extras pole [x, y] = the pole axis, clip robot_pole), `Anchor_DJ_club_0`,
   `Anchor_Dance_club_<k>`, `Anchor_Booth_club_<k>`, `Anchor_Seat_club_<k>` (bar stools), `Anchor_Stage_club_0`,
   `Anchor_Work_club_0` (bartender), **`Anchor_Bouncer_club_0`** (outside the door, extras adults_only). The club's
   outer windows are blacked out.
3. **Gym:** `Anchor_Gym_gym_<k>` with extras machine (treadmill: clip jog, stands on the belt at +0.24 m; bike; weights).
4. **Units (L3–L5):** `Anchor_Unit_<floor>_<s>` (door), `Anchor_Bed_<floor>_<s>_<k>` (ART-NPC bed rule; extras
   `head` "+Y" or "-Y" — on the right side of a double bed the stand point is mirrored, `mirror` true),
   `Anchor_Seat_...` (clip sit_eat at tables), `Anchor_Desk_...`. L3 = 24 hotel rooms; L4 = 24 family units; L5 = 6
   executive (2 sectors) + 12 hotel rooms.
5. **Construction (`dome_scaffold.glb`):** `Site` (fence, cabins, stacks, 4 flood masts), `Scaffold_1..5`, `Crane`
   with **`Crane_Jib`** (turn about its local Y in Godot; extras jib_length 30, hook_height 38). `Dome` now has two
   stages: `Dome_Frame` (stage dome_frame) then `Dome_Glass` + `Dome_Lights` (dome_glass). The manifest lists what to
   show and hide at each stage (`build_stages`). Picture: `art/dome/build_stages.png`.
6. **Round 26 glass (please match):** by day a fresnel sky reflection (opacity 0.14 facing → 0.72 grazing, specular
   1.0); **by night an emissive rim at grazing angles**: emission colour #FFB873 × fresnel × 0.8, so the shell shows the
   city lights. Geometry added: a `LightStrip` ring at the crown and along the dome foot (in `Dome_Lights`).
7. **New emissive materials:** `WindowRose` (#FFB0D0, 0.6), `WindowTV` (#5A8CFF, 0.85): coloured and TV-blue rooms on
   L3–L5. L2 has a second (upper) neon band all round (`Sign*` strips + the L2 venue names).
8. **Seats beside tables:** café, restaurant and food-court seat anchors now stand 0.45 m from the table centre on the
   chair side, facing the table (critic round 26: no body in a table top).

## 8. Super dome after critic round 28 — day glass spec, racer cabinet — 2026-09-29

1. **Day glass (fix 7), the exact numbers I use in the Blender preview, please match in the game shader:**
   - base tint #9CC9DC; opacity = mix(0.12, 0.85, F) with F = Schlick-like facing term: `F = pow(1 - dot(N, V), 2.2)`
     (Blender Layer Weight "Facing", blend 0.45); roughness 0.03; specular 1.0;
   - reflection = sky colour (horizon #C79E85 → zenith #5C6B8F) × F; this gives 25–40 % reflection at the grazing
     edge of the dome silhouette and almost none facing the camera;
   - night: add emission #FFB873 × F × 0.8 (the city light caught at grazing angles);
   - both faces (the material is double-sided); sort after the ring building.
2. **PRISM SHIFT is now a sit-down racer** (`Venue_arcade`, room centre, screen towards the entrance). The screen node
   `ArcadeScreen_PrismShift` is a 1.0 × 0.6 m quad, tilted 8° back, UV 0..1 as before. The player uses **drive_sit**:
   `Anchor_ArcadePrism_arcade_0` is the stand point, the wheel is at the drive_sit grip height. Floor underglow
   `SignCyan` / `SignMagenta`.
3. **Arcade:** 14 upright cabinets (6 on the back wall, 2 back-to-back blocks of 4) + the racer; prize counter with
   `PRIZES` sign; neon floor (Sign strips on the carpet); sofas and stools.
4. **Club:** raised DJ riser with steps, a light truss with 12 spot cans (coloured lenses, aimed at the dance floor
   centre — good spots for your light cones), acoustic back-wall panels with neon seams, two booths facing the stage,
   4 cocktail tables, a back bar with lit bottles and pendants, a bouncer lectern, and an **ADULTS ONLY / 21+** sign on
   the front beside the door.
5. **Upper floors:** balconies on every third unit are now 1.7 m deep with planters, a table and a lamp; about 7 % of
   the L3–L5 windows use `Light` (very bright rooms).

## 9. FINAL day-glass spec + round 32 changes — 2026-09-29 (critic round 32, fix 5)

This replaces the glass numbers in §6.1, §7.6 and §8.1. I read `shaders/dome_glass.gdshader` and list only the
differences. Source of truth for every number: `glass_preview()` in `tools/blender/dome_render.py`.

**Correction.** §8.1 gave `F = pow(1 - dot(N, V), 2.2)` and §6/§7 gave the rim colour as #FFB873. Both were my
errors. Blender's Layer Weight "Facing" with blend 0.45 is `F = 1 - pow(|N·V|, 0.9)` (nearly linear), and the rim
colour is linear (1.0, 0.72, 0.45) = sRGB **#FFDDB3**.

| Term | Game now | Blender preview (the renders CRITIC scored) | Change |
|---|---|---|---|
| Opacity curve | `pow(1-ndv, 3)`, 0.14 → 0.72 | `F = 1 - pow(ndv, 0.9)`; `mix(0.12, 0.85, F)` | use F for ALPHA; `alpha_face` 0.12, `alpha_graze` 0.85 |
| Sky reflection weight | `fres * 1.25` (Schlick, F0 0.04) | Principled specular, F0 about 0.08, times the alpha above | keep Schlick for the colour mix, F0 **0.08** |
| Tint | #9CC9DC × 0.55 | base colour linear (0.55, 0.72, 0.80) = sRGB **#C4DEE8**, lit | `tint` #C4DEE8, keep × 0.55 unshaded |
| Night rim | `rim_color * fres * 1.1`, sRGB #FFB873 | emission (1.0, 0.72, 0.45) linear × `mix(0.12, 0.85, F)` × 0.8 | `rim_color` source_color **vec3(1.0, 0.867, 0.702)**; rim = rim_color × A × 0.8 × night |
| Sky colours | the game sky | stand-in gradient only | keep the game sky |
| Roughness / glint | glint pow 220 | roughness 0.03 | keep |
| Sides, sort | cull_disabled, priority −2, no depth write | double-sided | keep |

Drop-in for the fragment (everything else in the file stays):

```glsl
float ndv = clamp(dot(n, v), 0.0, 1.0);
float F = 1.0 - pow(ndv, 0.9);                        // Blender Layer Weight Facing, blend 0.45
float A = mix(alpha_face, alpha_graze, F);            // 0.12 -> 0.85
float fres = 0.08 + 0.92 * pow(1.0 - ndv, 5.0);       // Schlick, F0 0.08 (Specular IOR Level 1.0)
vec3 col = mix(tint * mix(0.55, 0.12, night), sky, clamp(fres * 1.25, 0.0, 1.0)) + sun_color * glint * 3.0;
vec3 rim = rim_color * A * 0.8 * night * (0.55 + 0.45 * low);   // keep your low-dome and crown terms
ALBEDO = col + rim;
ALPHA = clamp(A + glint * 0.6, 0.0, 0.95);
```

Expected result: the shell reads as glass across the whole silhouette (not only the rim). Facing the camera at 12 %
opacity the ring building shows through clearly. Check it against `art/dome/overview_250_day.png` and
`overview_250_night.png`. If the ring building is too hazy in game, lower `alpha_graze` to 0.72 first; do not change F.

**Round 32 model changes (all in the files now, imported, `check` 258 scripts, 0 failed):**

1. **Hotel rooms (L3, L5):** 108 new anchors `Anchor_Lamp_<floor>_<s>_<k>` (72 on L3, 36 on L5) (extras role `lamp`, colour #FFB45E,
   range_m 3.0, optional true): two bedside lamps and one floor lamp per room. They are good spots for a small warm
   OmniLight when the player views that floor at night; the lamp shades are `WindowAmber`. Two new `Anchor_Seat_...`
   per room (armchairs in the middle lounge set).
2. **Balconies (every third unit, L3–L5):** a `WindowAmber` strip on the rail top (0.10 m) and one on the slab edge,
   and `SignAmber` planter lights. They need the night emission curve only; no light nodes.
3. **Club front:** the double door has a lit `SignMagenta` frame; the ADULTS ONLY / 21+ sign is larger (0.18 m / 0.24 m
   letters) and sits beside the door, clear of the frame. Picture: `art/dome/L2_club_door.png`.
4. **RESTAURANT (L1)** sign moved 11° away from the lift: clear of the lift frame and the palm from the atrium view.

Sizes after this round: imported `.scn` total 7.74 MB (8 files); glb 21.4 MB on disk. Merged template: 119 surfaces
(your probe, `merged`), unchanged.

## 10. Critic round 34 fixes + dome cost figures for the fps check — 2026-09-30

**Changed (`dome_floor1.glb` only; imported, `check` 259 scripts, 0 failed):**

1. **L1 bar back bar:** four units, each with a mirror (`Palette:#aebcc6`, wood frame), 3 wood shelves of 12 bottles
   (body + shoulder + neck), a `SignAmber` light under each shelf and a `SignMagenta` bar on top. There is a dark lining
   on the back wall (no outside view behind the bar). The bar has no back lightbox now. Window display: 5 lit bottles
   plus 4 bottles on a riser. Picture: `art/dome/L1_bar_back.png`.
2. **RESTAURANT sign:** `SIGN_SHIFT` 11° → 13°, at the far end of the restaurant front, next to CREDIT. The lift frame
   posts are at 131.5–138.5°; the plate is now 151.6–159.4°. A very oblique camera can still put a post in front of
   a sign; no sign position removes that for every camera.

**Dome cost (from the glb files, 2026-09-30).** Total 263 k tris (+53 k scaffold, construction only).

| file | tris | primitives | materials | biggest groups |
|---|---|---|---|---|
| dome_shell | 24 412 | 16 | 10 | Promenade_Props 11 040, Dome_Frame 7 208 |
| dome_floor1 | 59 426 | 85 | 16 | Venue_* 38 004, VenueLamps_* 18 022 |
| dome_floor2 | 61 386 | 105 | 18 | Venue_* 27 085, VenueLamps_* 19 489, Lamps_2 8 594 |
| dome_floor3 | 43 476 | 100 | 16 | **Unit_* 29 712**, Shell_3 5 628 |
| dome_floor4 | 23 016 | 53 | 19 | **Unit_* 8 256**, Lamps_4 5 748 |
| dome_floor5 | 37 226 | 89 | 18 | **Unit_* 18 540**, Shell_5 5 474 |
| dome_atrium | 14 424 | 27 | 11 | Atrium_Ground 10 948 |

The merged dome is 119 surfaces of about 1,100–1,360 draws in the scene (about 10 %). So by draw calls the dome is not
the main cost. If your fps check still points at the dome, these are the reductions, in order of value:

1. **Hide the unit interiors unless that floor is cut away (no art change).** The L3–L5 fronts and outer windows are
   opaque tone quads, so no `Unit_<n>_<s>` interior can be seen from outside or from the atrium while its floor is
   closed. In the merged template, keep `Unit_*` of each floor as a separate merged group ("fit-out units") and show
   it only when that floor is the cut floor. Saving: **56.5 k tris (21 %)**, and the surfaces of that group on 3 floors.
2. **Distance LOD for the L1/L2 venue interiors (no art change).** Beyond about 150 m, hide `Venue_*` and keep
   `VenueLamps_*` (the lit parts: bottles, screens, signs). Saving: 65 k tris at 250 m. At that distance the lit
   parts carry the "city under glass".
3. **Fewer emissive materials (art change, mine, on request).** Each floor has 16–19 materials, of which about 10 are
   emissive (`Window*`, `Sign*`, `Light*`, `Screen`). I can bake them into ONE emissive material with vertex colour and
   an emission-strength channel (COLOR_0 alpha). That takes each floor from 16–19 to about 7 surfaces
   (about −50 surfaces for the dome). It needs your night curve to read one material instead of ten. Tell me before
   I start; it changes the material contract.
4. **Promenade_Props (11 k) and Atrium_Ground (11 k):** I can halve the tree and palm leaf counts (−8 k) if needed.

**A possible cause outside the dome.** I ran Blender renders on this machine on 2026-09-29 from about 19:20 to 19:47
(critic images are stamped 19:51), and on 2026-09-30 about 20:00–20:15. Your note in `docs/progress/RENDER.md` measured
39–42 fps with Blender running against 56 fps without. I do not know when the critic's perf runs took place. Please
check it against the run times before you cut geometry.

## 11. Club door frame for critic round 38 — please match in game — 2026-09-30

CRITIC round 38 asks for the bouncer and the ADULTS ONLY sign at the club door in one frame, in game. The Blender
version exists: `art/dome/L2_club_door.png` (bouncer at the lectern, both rope lines, the lit door frame, ADULTS ONLY /
21+). Please shoot the same frame in game. Numbers in Godot axes (Y up), relative to the dome origin, before the
building transform:

| item | value |
|---|---|
| camera position | (−11.62, 7.80, 15.41) — L2 gallery, 2.5 m above the L2 floor (5.30) |
| look-at point | (−10.88, 6.60, 20.04) |
| fov | vertical 64° (16 mm on a 36 mm sensor at 1800 × 1000; horizontal 97°) |
| bouncer | `Anchor_Bouncer_club_0` at (−9.01, 5.30, 18.75), extras `adults_only` true; clip idle |
| light | night; two point lights near the door help: warm at (−10.60, 8.50, 18.36), magenta at (−12.93, 8.30, 16.55) |
| show | Floor_1, Floor_2 and the atrium; floors 3–5, roof and dome may stay (the camera is under the L3 slab) |

The club has blacked-out outer windows and a closed front. The robot dancers are inside, so this frame cannot also
show them. For "robots + light show + bouncer + sign in one frame", use the L2 cutaway (floors 3–5 and the roof off)
from above the atrium at mid-distance, looking down at sectors 13–18 (angle 195°–285°): the door and the sign face
the atrium at 240°, and the podiums are behind them.
