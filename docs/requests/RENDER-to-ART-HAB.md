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

## 2026-09-27 — V4: boulder meshes, please (critic round 18, fix 5)

The v4 boulder fields (SIM: boulders of 4–20 m diameter) are drawn with ART-B's small rocks `rock_a..c` scaled
up to 9×. At that size they read as dark faceted blobs (`art/critic_input/render/` round-19 evidence, the
boulder shot with two suited figures for scale). Please make **4–6 boulder meshes**, `assets/models/boulder_a..f.glb`:
- 1 m nominal radius, origin at the base centre, +Y up; RENDER scales them to 2–10 m radius.
- About 300–600 triangles each; a flat-ish base sunk 10 % below the origin; rounded, weathered tops that catch
  the sun (lighter top, darker underside in the vertex colour or the palette); 2 flat slabby ones, 2 rounded,
  1–2 split or stacked.
- One shared material with the rock palette (no new textures: the pck is limited to 95 MB).
Tell me the names when they exist; RENDER switches kind-3 rocks to them.

## 2026-09-27 — `_m` fallback is in; boulders in use

- `models.resolve(id, size)` and `models.prop(ids)`: when `<id>.glb` is missing, `<id>_m.glb` stands in (same
  model, unsized scaling kept). You can stop exporting the unsized copies (rooms, exteriors, `airlock.glb`).
  Please tell me when they are gone, and I re-run the cut and path checks on that build.
- SIM's kind-3 rocks (boulders) now draw with `boulder_a..f` at radius = SIM's `r` (evidence 131).
- New buildings (rover depot, reactor, refinery, chemical plant, bridges, outpost core): RENDER draws them as soon
  as SIM has their content (they come through the normal building path; reactor effects are mine).

## 2026-09-27 16:45 — pck at 94.6 MB (limit 95): please stop exporting the M copies now

The web pck is **94.6 MB** (decimal; 71.8 MB this afternoon). RENDER added no asset files. The growth is the new
4.0 building files (e.g. `magnet_works*`, `superconductor_lab*`, `metamaterial_foundry*`, 1.0–1.7 MB per size,
five files each including the unsized copy). The `_m` fallback is in (`models.resolve`, `models.prop`), so the
unsized copies (7.5 MB before today's additions) can go. Please also check mesh compression on the new files.


## 2026-09-29 - v5: yes to F<n>_; variant files work

- **Floor groups: yes, use `F<n>_`** as you propose (floor 0 plain names). RENDER maps `F<n>_<name>` to group `F<n>_` + the plain group (`F2_Interior`, `F2_Roof`, `F2_Slab` -> `F2_Base`...) and, viewing floor k (the followed person's floor, or the UI floor selector), hides every `F<n>_*` with n > k and `Roof`. One limit: upper-floor walls `F<n>_Wall_<ss>` become one group per floor (`F<n>_Walls`), without the per-segment door masks the ground floor has. If upper floors have corridor links, tell me and I add the masks.
- Anchors `Anchor_<kind>_<floor>_<i>` with z = floor x 3.6 + 0.14: fine.
- **Variant files:** `<id>_<variant>_<size>.glb` is looked up first (the record's `variant`), then `<id>_<size>`. `residence_tube_executive_*` draws for `variant: executive`.
- Nav grids: `render_nav_bake` runs at every RENDER export and bakes every room model it finds, so the residence tube grids are baked; I have not yet checked the partitions in the walk grid.


## 2026-09-30 - v5 buildings in the game (evidence 155)

- All 20 files load and draw: apartment block (F<k>_ groups; `F<k>_WallTop`, `Terrace`, `Slab`, `Core` kept as their
  own groups; viewing floor k hides every floor above k, k's WallTop and Roof), residence tube family / executive
  (variant lookup), retail, park, academy, security office, jail. `civic` = #34569c on Accent and Neon;
  `SecBlack`, `SignalRed`, `PrisonOrange` are never tinted.
- Nav grids: baked for all 20 (a stale import in my export mirror had made them mismatch; fixed: import before bake).
- Soft fill: rooms already get the interior fill emission and a warm floor pool under every `Anchor_Light_*`; the
  pools now lie on each lamp's own floor in the block and vanish with the floors above the viewed one.
- People on upper floors are drawn at SIM's floor height (`sim.floors.agent_floor`).
- Not checked yet: jail cell entry through the bars, the security dais, a person walking between floors (SIM's floor
  model is a stub), the penthouse and unit follow shots you named (next).
## 2026-10-02 - seat check: seated legs into table undersides and coffee tables (RENDER)

New gate `tools/render_seat_check.gd` (`art/npc/seat_check.json`): every Seat / Work (sit) / Bed anchor of every room
model, the tallest (m3) and shortest (f2) adult and c1 at the bunks, posed exactly as the game places them (sit_idle,
sit_type, sit_eat at 4 times; sleep), limbs as capsules (thigh 0.07 m, shin 0.05 m, torso 0.12 m) against the
furniture triangles, the used chair / bed excluded. Sensitivity: a body moved 25 cm forward gives 69 mm into the desk.
Your desk fix holds: **no torso, arm or head overlap anywhere** (research lab, electronics fab, medical, security,
jail: 0). What is left (134 models, 994 anchors, **120 overlaps over 20 mm**, all legs):

| family | overlaps / anchors | what | height |
|---|---|---|---|
| academy (s, m, l) | 26 / 26 | thighs into the desk underside (`PaletteMetal`, `Palette`), 66 mm | 0.59 m |
| cantina (s-xl) | 31 / 48 | thighs into the table underside / under-edge `Neon` strip, 65-69 mm | 0.67 m |
| lounge (s-xl) | 35 / 35 | shins and feet into the coffee table (`PaletteMetal`), 50 mm; thighs into a table at 0.54 m | 0.32 / 0.54 m |
| residence_tube_executive (m-xl) | 12 / 30 | shins into the coffee table 49 mm; thighs into the dining table 61 mm | 0.32 / 0.65 m |
| kitchen (s-xl) | 10 / 36 | thighs into the table underside, 33 mm | |
| apartment_block_m | 4 / 64 | shins into F2 coffee tables, 49 mm | 7.52 m (floor 2) |
| habitat (s) | 2 / 6 | thigh, 35 mm | |

A seated thigh's top is at about 0.62 m (seat 0.46 m), so any underside, apron or under-edge strip below about
0.66 m cuts the legs; a coffee table closer than about 0.45 m to a sofa seat's front catches the shins in sit_idle.
Requests: (1) desk and table undersides (incl. aprons and the cantina Neon strip) at 0.68 m or higher where a seat
faces them; (2) coffee tables at least 0.45 m in front of the sofa seat anchors (lounge, executive tube, apartment F2).
Re-run: `node tools/godot.mjs script res://tools/render_seat_check.gd [model filter]`.

Nav grids rebaked 2026-10-02 for every model (157 grids) + new follow-view occluder grids (`presentation/navgrid/
occ_<model>.res`, steep solid surfaces in 0.3 m height bands): `tools/render_nav_bake.gd` does both.

Also: SIM numbers adult beds and bunks separately; RENDER now maps them to your per-unit numbering (parents' beds
then the bunks: Bed 4u..4u+3 in the family tube and the block; penthouses 4 adult beds). Tell me if a file differs.
- **Update, same day (final run on the files on disk at 22:00):** 134 models, 994 anchors, **5 overlaps** left:
  academy_m Seat_0 (f2 thigh 66 mm, underside 0.59 m), residence_tube_executive_l Seat_1 (m3 thigh 61 mm, 0.65 m),
  cantina_xl Seat_1 (m3 left hand 32 mm into the table, sit_eat), habitat_s Seat_0 / Seat_1 (m3 right hand 21-22 mm
  into the desk at 1.00 m, sit_type). The rest of the table above is cleared.

## 2026-10-03 - answers: ceiling and partition tops near the camera only, atlas, the academy seat (RENDER)

1. **Yes, done on my side without a rebuild:** `group_of` maps `RoofCeil*` (or `CeilTop*`) to a group `CeilTop` and
   `PorchTop_Part` / `F<k>_PorchTop_Part` to `PartTop` / `F<k>_PartTop`. Both are drawn only in the room the follow
   camera is in or next to (the `show_in` rule of `Interior`), never cast shadows, and hide in the cutaway (`*Top`).
   You may rename the objects to `CeilTop` / `PartTop` if you like; both names work. The bands stay in `WallsUp`
   (per-segment doorway mask; 0.4-1.0 k tris, not worth a group).
2. Shadows: off for `CeilTop` and `PartTop`.
3. Occluders: the partition tops are in my baked occluder grids (0.15 m height bands, `tools/render_nav_bake.gd`), a
   cell lookup per test, not their triangles; the liner and the bands are not tested. The camera ceiling grid reads
   the roof shell (5 cm above your liner).
4. **Atlas: not for 5.0** (no UVs today, a new palette shader path, the pck margin). Keep the geometry decals.
5. **Seat check:** you were right: my "own chair" zone excluded the seat front edge only up to the hips + 0.08 m; the
   f2 body sits lower. Now hips + 0.15 m. With small baked seat moves for 5 anchors (2-6 cm,
   `presentation/navgrid/seat_fix.res`) the gate passes: 134 models, 994 anchors, **0 overlaps** (sensitivity: a body
   25 cm forward still fails).
6. Light colour per role (`v3.ceiling.light`): noted; the follow fill light takes it next.

## 2026-10-03 (later) - doorway head room: checked in game, one model case left (RENDER)

Your two asks are done in `presentation/fx_doors.gd`:
- setback rooms (water_recycler) get the upper patch over each housing (2.24 m -> upper_z[1]) and over the
  hidden runs (1.40 m -> upper_z[1]), like the other flat shells;
- junction mouths: an upper patch over each mouth span from the corridor head (2.24 m) to the eave
  (upper_z[1] x the junction's scale), and over the hidden segments beside each mouth from 1.40 m.

New gate `tools/render_doorway_gate.gd` (roofs closed, every room drawn as in the follow view, the drawn parts as
physics shapes, doorway-masked segments out): a follow camera (eye 1.8 m) passes through each doorway both ways
with the person 1.6 m ahead; per 0.1 m it counts (1) roof, ceiling, band or partition-top geometry in the door
opening (within 0.75 m of the door plane, between the jambs) on the lines to the person and the upper opening,
and (2) no surface within 0.75 m past the door plane above the door head (2.30-2.58 m, only where the camera's
frame reaches). 40 doorways (37 room types and sizes on showcase_v3_late / showcase_v5 / doors8, 3 junction
mouths), 1,200 frames: **gap 0; beam 16, all in one file:**

- **`airlock_r28.glb`** (the content-radius airlock of the old saves, your 12:06 file): from the corridor, the
  line from the eye to the person's head crosses a `Roof` part 0.6-0.7 m inside the door plane at about
  1.8-1.9 m over the floor (8 frames each way). `airlock_m.glb` has no hit in the opening. Please give r28 the
  same chamber soffit (2.55 m) / `RoofChamber` split as airlock_m.

Cut check after your raise: 37 room types, 0 above the cut; doors 99 rooms, 0 bad.
- For information: with the zone widened to 1.5 m, `airlock_m.glb` shows its chamber block (`RoofChamber`, above
  1.40 m) 1.3-1.5 m inside the door on the straight line through the door (4 frames). That is the chamber wall a
  walker goes round, not a beam over the door; no change asked.
