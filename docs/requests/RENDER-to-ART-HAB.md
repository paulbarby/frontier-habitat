# RENDER to ART-HAB

## 2026-09-25 — critic round 6 (RENDER)

1. **Interior material count.** Each material of the `Interior` group is one draw call per room type. After
   the 02:55–02:57 exports of `habitat_*` and `lounge_*`, `showcase_v3_late` went from 1 383 to 1 412 draw calls
   at the 110 m overview (HUD on), and from 1 396 to 1 426 at 450 m. The budget is 1 400. `lounge_m` Interior
   has 14 surfaces, `research_assembler_m` 14, `habitat_xl` 14, `habitat_l` 12. Please merge materials that share
   colour and roughness (or use a palette texture), so an Interior has 8 or fewer surfaces.
2. **Bed stand points (critic round 6, fix 3, yours).** In the bays of 2 the stand point must be on free floor,
   at least 0.35 m from the neighbour bed and the bedside unit. RENDER now gives each anchor to one body only
   and puts a waiting body on a free aisle point, but a stand point inside a bed still shows a body in the bed.
3. The research-lab "tilted white panel" of round 6 does not appear in the current build with the critic's own
   step file (`build/web_render/r6me_lab_z9.png`). If a model of that room changed between 23:25 and now, that
   explains it; otherwise tell me the time of the export.

## 2026-09-25 — v3.1 paths (RENDER): furniture in front of doorways; room shell materials

1. **Furniture in front of doorways (J3).** `tools/render_path_check.gd` (V3_1 §4.4) counts bodies standing in a
   furniture cell they do not use. After the new path system, 1.06 % of indoor samples remain; **93 % of them are
   within 1.5 m of a door opening**: the doorway faces an item with no walkable gap of 0.6 m (the path goes
   round it through a gap of 0.1–0.3 m). By room in showcase_v3_late (10 game minutes): habitat 879, airlock 459,
   kitchen 230, storehouse 173, refinery 165, polymer_plant 163, greenhouse 155, lounge 124, mine 100.
   Request: keep 0.6 m of free floor (at 0.20–1.90 m height) in a 1.6 m wide lane in front of every doorway
   angle that SIM allows, or give SIM a blocked-angle list it enforces. Grids to look at:
   `build/web_render/grid_<def>_<id>.png` (red furniture, dark wall, blue = within 0.30 m, green = room-side door
   point).
2. **Draw calls: room shell materials.** After the 3.1 rollout, `Base` of a room model has 8–11 surfaces
   (airlock_m 14, atmo_processor_xl 11, algae_bioreactor_m 11); the late-colony overview is at about 1 490 draw
   calls (budget 1 400; it was 1 383 before). Please merge the plain shell and decal materials of `Base` into
   `Palette` / `PaletteMetal` as you did for Interior, target ≤ 6 surfaces in `Base`. Emissive and tinted
   materials (Accent, Window, Neon, L3Band …) can stay.

## 2026-09-25 — v3.1 paths, round 2 (RENDER): `airlock_r28` lanes for old-save corridors

RENDER loads `airlock_r28.glb` unscaled for airlocks with a record radius under 3.0 m (your F0). Result: the
furniture count in the path check falls from 1.075 % to 0.605 % of indoor samples, and **86 % of what remains is
inside `airlock_r28`** (1 519 of 1 763 samples in 20 game minutes).

Cause: the old saves have corridors at model angles that `airlock_r28` blocks. Your list for `airlock_r28` is
`blocked [[-174.5, 142.5]]`, so only 142.5–185.5° is open. The corridors in the two test saves
(model angle = `sim/placement.gd` `model_angle(rot, world angle)`):

| save | airlock id | corridor model angles | blocked? |
|---|---|---|---|
| showcase_v3_late, scene_final | 49 | 259.5, 180.0 | 259.5 yes |
| showcase_v3_late, scene_final | 645 | 215.5, 270.0 | both yes |
| both | 2367 | 180.0 | no |
| showcase_v3_late (scene_final) | 3769 | 153.5, 83.0 (153.5) | 83.0 yes |
| showcase_v3_late | 6473 | 152.0 | no |

At 259.5° and 270° the body walks from the doorway into the Interior band at local z 0.7–1.3 (bench or rack,
`Interior/Palette` and `Interior/Accent`); there is no free floor round it (grid:
`build/web_render/grid_airlock_49.png`, red = furniture). SIM cannot move corridors in a loaded save.

Request: give `airlock_r28` a free 0.9 m lane from the ring to the chamber floor at about 83°, 215°, 260° and
270°, or tell me a layout rule I can apply (for example, hide one named object when a doorway is at a blocked
angle, the same as the `Tall_*` rule). The M and L files are not affected (no old save uses them).
## 2026-09-25 — answer to your critic round 13 note (C1–C3)

- **C1.** `PorchTop` is now in `GROUPS` (`presentation/models.gd`), so the *Top cutaway rule hides it. I checked
  in game, not in the file: the new debug command `__fhr.cmd('tallparts <room id>')` lists every drawn group of the
  room and of its doorway kits whose top is above 1.45 m. The round-13 "slabs" had two causes on my side:
  (1) the **selection outline** drew every group, including the hidden *Top, status and door-kit parts, as cyan
  slabs. It now draws only the structure body (Base, Roof, levels). Measured in game (showcase_v31, airlock 49,
  cutaway open 1.00): `tallparts 49` lists **no** drawn part of the airlock or its doorway kits above 1.45 m, both
  unselected and selected. Your files are right.
- **C2.** `FrameCap` goes to group Base and `OuterFrameCap` to OuterFrame, so both always show. Nothing to change.
- **C3.** Old-save doorways that meet the inner door housing (83°, 259.5°, 270°): the path goes round the housing
  through a corner point 0.55 m past it (`fx_airlock.walkway_route`), never through the chamber. The final airlock
  check has 0 shut-door crossings and 0 bodies in the chamber in the wrong clothes.
## 2026-09-26 — Paul's report: cut wall top (high priority)

Report: `docs/reports/paul_2026-09-26_cutaway_top_edge.webp` (storehouse, cutaway, 12–20 m: white slanted
shards on the cut wall top, a tall grey door-frame arch, black poles round the ring).

**Cause (RENDER side, fixed).** `models.gd` parsed your `Upper_NN` skin into group Walls. Its shell faces stayed
drawn in the cutaway at full height (the black ribs = the "poles"); its window, light and trim faces went into
WallsIn, which the cutaway shows (the white shards). The fx_doors `wall_patch_upper` pieces over the door housing
(2.24 m) made the arch; the upper band and band caps also stood above the cut. Now: `Upper_NN` is group
**WallsUp**, masked per segment like the wall, hidden with the roof; door patches whose top is above 1.42 m are
hidden per room while its roof is open. Your door kits pass: no kit vertex above 1.45 m.

**New check.** `node tools/godot.mjs script res://tools/render_cut_check.gd <label>` opens the cutaway of every
room on 3 saves and measures every drawn vertex (room, its doorway kits, its patches; segment masks applied).
Allowed above the cut: Interior, Tall. Output `build/web_render/cut_check_<label>.json`
(copy: `art/critic_input/render/116_cut_check.json`). `render_cut_probe.gd <def> ...` lists the GLB nodes.

**Request.** 8 room types of 28 still have a drawn wall vertex above 1.45 m. All are `Wall_NN` nodes of the
size-M files (group Walls; their non-shell materials land in WallsIn). Clamp the wall top to 1.40 m, or move the
part above 1.40 m into `Upper_NN`:

| file | nodes | top (model units, drawn) |
|---|---|---|
| `cantina_m.glb` | Wall_00, 07, 12, 19, 24, 31 | 1.526–1.540 (drawn 1.54) |
| `lounge_m.glb` | Wall_04, 16, 28 | 1.526–1.539 (drawn 1.53) |
| `greenhouse_m.glb` | Wall_04 | 1.480 |
| `habitat_m.glb` | Wall_00 | 1.480 (habitat S and L drawn 1.48 too) |
| `medical_m.glb` | Wall_03 | 1.480 |
| `storehouse_m.glb` | Wall_00, 03, 07, 09, 12, 16, 18, 21, 25, 27, 30 | 1.440 (under the 1.45 gate; above 1.40) |

The S, L and XL files have the same overshoot (probe run 2026-09-26): cantina S/L 1.530–1.540, lounge S/L
1.526–1.539, habitat S/L/XL, greenhouse S/L, medical S/L 1.480. Pass a file id to the probe
(`render_cut_probe.gd habitat_s cantina_l`).

`research_lab` (drawn 1.46): all its files are under 1.42. The 1.46 is RENDER's: an old-save record whose
radius differs from the def is drawn with a uniform scale (`models.building`, `s_radius`), so the wall height
grows with the radius. Not changed now (floor height, doors and walk grids use the same scale); I will scale
only X/Z after integration if the coordinator wants it. Nothing for you there.

## 2026-09-26 — re-run after your 11:00 rebuild: 28 of 28 pass

- `render_cut_check.gd after3` (showcase_v3_late, showcase_v31, scene_final; imports of 11:04): **28 of 28 room
  types pass**, 0 with a drawn vertex above 1.45 m (`art/critic_input/render/120_cut_check_28_of_28.json`).
- research_lab (1.46) was mine: a scaled record now draws Walls and WallsIn with Y scale 1/s in the cutaway.
- The frames you asked for (storehouse and habitat at Paul's zoom, 16 m, roof open, today's export, day and night):
  `art/critic_input/render/119_cut_storehouse_habitat_research_lab_day_night_r15.png`.
  Single frames: `build/web_render/cut_r15_<storehouse|habitat|research_lab>_<day|night>.png`.
