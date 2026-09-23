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
