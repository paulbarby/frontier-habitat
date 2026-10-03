# Critic round 42: planets_exteriors

Date: 2026-10-04. Build `build/web_v5play3` (e9b1d35, pck 186.2 MB). Rubric `docs/critic/v5_rubrics.md`, V5_DESIGN §15.5, §15.7.
Shots: `art/critic/r42/planets_exteriors/` (my own, `tools/shoot.mjs --gpu`, 1600x900, HUD on).

## Method

- showcase_v5 with the look override `planet dry|cold|airless`. Times 150 s (day), 348 s (dusk), 470 s (night).
  Cameras: 24-34 m close, 40 m at 10° (horizon), 62 m, 110 m, 250 m, 600 m, and all roofs off at 62-140 m.
- Real planets: `newgame 1001 cold|airless|dry`. These show the minimap, the build bar and the real night.
- Far meshes: `farlod 1` against `farlod 0` at 140 m with all roofs off, and a 70/80/88/96 m sweep.
- People LOD: `npclod -1` against `npclod 0` at 90 m.

## Score

| consistency | appeal | style | score | result |
|---|---|---|---|---|
| 0.70 | 0.66 | 0.74 | **0.70** | PASS (round 41: 0.71) |

## What works

- The 3 planets differ at a glance. Dry is rust with a warm haze. Cold is blue-white with frost. Airless is grey
  regolith under a black sky, with stars by day.
- Dry dusk and dry night are the best views in the game (`dry_dusk_horizon_a`, `dry_night_horizon_b`).
- Airless: a forced storm (`storm 1`) gives no dust, and the sky stays black (`airless_storm_horizon`).
- Round 41 faults now fixed:
  - Airless new game: the Wind Turbine is locked, "This planet has no air" (`new_airless_buildpower`).
  - The minimap follows the real planet: cold blue-white, airless grey, dry rust (`sheet_new_day`).
  - The cold frost is a smooth cover. Structures get frost at night on cold (`cmp_night_roofs`).
- After the roof raise, the habitat domes keep good proportions (`t3_airlock45`).
- The super dome reads at 110 m and 250 m, by day and at night.
- People LOD: at 90 m the automatic LOD looks the same as LOD0, with no pop (`ab_people_lod90`).
- All roofs off (the key-Y path) cuts every roof and keeps the greenhouse glass (`t7_c_roofsoff_90`).

## Faults (most important first)

| id | sev | owner | fault | fix |
|---|---|---|---|---|
| PE-01 | major | ART-HAB | Far room meshes are half as bright as the near rooms. Floor luminance far 50/64/59/51, near 119/126/117/98, ground 114/114 (`ab_far_on_off`). Past 80 m with all roofs off, rooms become dark blurred discs. | Bake the far vertex colours from the near albedo, with no AO darkening. Keep the far mean within 10 % of the near mean. RENDER: dither or cross-fade the swap over 0.5 s. |
| PE-02 | major | RENDER | A radiation zone in showcase_v5 (1450,1280, r 140 m) draws as a flat olive disc over the east half of the colony. On airless: 122,113,67 inside, 152,140,136 outside (`t10_airless_top450`). This is the round-41 "green patch". The fog-rim change did not touch it. | Draw a hazard: a hatched, pulsing edge ring and a light fill (alpha ≤ 0.15) in the planet palette. Past 300 m, show the ring only. |
| PE-03 | minor | SIM | showcase_v5 has that 140 m radiation zone and no reactor (`v4state`: reactors []). | Remove the zone from the showcase, or give it a cause and an alert. |
| PE-04 | major | RENDER | Cold at midday is a white-out. The ground has mean 226, std 13.5 at 160 m. The craters almost go (`t6_cold_day_160`, `new_cold_day`). | Frost albedo about 0.72. Show the grey-blue regolith on slopes and crater rims. Make the frost normals stronger. Target std ≥ 25. |
| PE-05 | major | RENDER | A real airless night is black. The ground mean is 3/255 at 62 m and 160 m, 25 s after the change (`t6_airless_night_160`). The look override gives 39 at the same hour, so the shot sheets do not show what a player gets. | Use the planet-shine as a cool key light on airless nights, or raise the ambient. Target an open-ground mean of 15-25. Check it in a real airless game. |
| PE-06 | major | RENDER | A stale selection outline. `select()` sets `_outline_sig = ""`, so clearing the selection never frees `_outline`. If you clear it before the roof is half open, the Roof outline stays. When the roof opens, it draws as a solid cyan half shell (`t9_noplanet_habitat`, `t9_planet_tube`). Reproduced 2 of 2 with select and then an instant clear. Not reproduced with a 0.15 s gap. | In `_sync_selection`, free `_outline` when `want_sig == ""`. Or do not reset `_outline_sig` in `select()`. |
| PE-07 | major | RENDER | The overview camera goes into the super dome ring building. Select the dome, zoom to 34 m, pitch 20°: you see dark rooms, a pillar and a sofa from inside the walls (`dry_day_dome_close`, all 3 planets). | Keep the overview eye outside the dome shell, or cut the ring storeys when the eye is inside. |
| PE-08 | minor | RENDER | On cold nights the frost overlay covers the lit roof windows, so they show grey (`cmp_night_roofs`, middle). | Do not put the overlay on emissive window parts, or add the emission after it. |
| PE-09 | minor | RENDER | The cold storm is warm grey-beige: sky 153,141,136. The clear cold sky is 175,185,198 (`t4_cold_storm_low`). | Use a cool white blizzard palette and snow streaks. |
| PE-10 | minor | RENDER | On airless, vent plumes rise and billow like steam (`crop_airless_plumes`). | On airless, use a short, fast fan that fades in 1-2 m, with no rise. |
| PE-11 | minor | RENDER | Some boulders stay rust-orange on airless (`crop_airless_rocks`). | Grey every rock material on airless. |
| PE-12 | minor | UI | In low views, POI tags and status words stack on the skyline: RICH DEPOSIT, WRECK, BROKEN, HULL BREACH, FULL (`airless_day_horizon_b`). | Hide POI tags below 20° pitch. Do not let two tags overlap. |
| PE-13 | minor | ART-B | The 8 kiosks at the dome base are plain boxes with flat black roofs (`crop_dry_dome_base`). | Add a canopy, a sign and a lit door frame to each. |

## Gap

- To reach 0.80: fix PE-01, PE-02, PE-04, PE-05, PE-06 and PE-07.
- To reach 0.90: weather that you can see at eye height on each planet (snow streaks, dust sheets) and
  terrain detail that holds at 600 m.

## Notes for other critics

- Shot scripts that select and then clear at once (`select <def>` then `deselect`) get the PE-06 cyan shells.
- The look override `planet <x>` does not change the minimap or the real night light. Judge those in a
  `newgame` on that planet.
- The first shot taken 25-35 s after `loadurl showcase_v5.fhsave` is black. Wait 60 s.
