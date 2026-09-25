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