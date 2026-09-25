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
