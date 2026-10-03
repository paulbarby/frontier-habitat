# ART-HAB progress (3.0: habitat interiors, doorways, corridors, new buildings)

Owner: ART-HAB. Took over the v2 room pipeline of ART-A and the exterior scripts of ART-B
(see `docs/progress/ART-A.md`, `ART-B.md`). Files owned: `tools/blender/build_assets.py`, `rooms_*.py`,
`interior_*.py`, `ext_*.py`, `ext_common.py`; `assets/models/` + `assets/thumbs/` except `astronaut_*`;
`assets/textures/props/`; `art/interiors/**`.

## 2026-10-04 critic r42 PE-01 (far rooms half as bright)
- Cause: far Base floors baked into Palette lost the game's interior shader fill (Floor/FloorDark are INTERIOR_ONLY); far materials named Palette.001. Fix in rooms_far.py: far floors keep material "Floor" (white, colour in COLOR_0), exact material names. Verified with tools/arthab_farcheck.gd: far floors now on the interior shader path.
- RESULT 159 far files rebuilt; draw calls roof off 795, roof on 831 (near 3,649 / 4,009); import done; check 347 scripts 0 failed; nav bake 160 grids; pck 186.22 MB. RENDER asked to re-measure luminance.

## 2026-10-04 package transport models (V5_DESIGN 18.5) + far glow fix
- `tools/blender/interior_transport.py`: transport_tube (36 tris), transport_bracket (164), transport_junction (398), transport_port (210), transport_hub_s/m/l/xl (1,462 each); 0 flags; 102 KB in the pck.
- Storehouse / cold storage: hub pad + Anchor_Hub (longest rack row, 1.0 m bay), decks 2.90/2.90/3.10/3.30; 8 files rebuilt 0 flags, door_blocked unchanged.
- Far files: glow kept by area, folded only into a matching glow (RENDER: habitat window glow); 159 rebuilt, draw calls unchanged (636 / 672).
- RESULT import done; check 346 scripts 0 failed; nav bake 160 grids / 162 occluder grids; pck 186.18 MB. Renders art/interiors/transport/. SIM and RENDER told; no critic round 42 file yet.

## 2026-10-03 far files, all groups (coordinator: roof-on overview 33.8 fps)
- RESULT `rooms_far.py --groups all`: 159 files with Base, Interior, Roof, L2..L5; roof-on draw calls 4,009 -> 672 (25.2 -> 4.2 per type), triangles -45 %; roof-off 3,649 -> 636. Far files 28.3 MB imported; pck 185.95 MB. Import done; check 317 scripts 0 failed; nav bake 160 grids / 162 occluder grids. RENDER told.

## 2026-10-03 far meshes (roof-off view: 10 ms, 821 draw calls)
- `tools/blender/rooms_far.py` -> `assets/models/<id>_far.glb` (159 files): objects Base + Interior (game group names), Palette (colour in COLOR_0) + 1 glow; down-facing and < 14 cm faces removed; no decimate (smeared colours).
- RESULT roof-off groups: draw calls 3,649 -> 636 (22.9 -> 4.0 per type), triangles 2,809,461 -> 1,097,770 (-61 %); pck +18.9 MB (175.8 MB). Option "all groups" measured: +28 MB. Import done; check 317 scripts 0 failed; nav bake 160 grids / 162 occluder grids (far files skipped). RENDER asked to agree the form and load beyond 80 m.

## 2026-10-03 airlock_r28 (RENDER doorway gate: 16 beam frames)
- r28 already had the raise + RoofChamber + soffit (Roof min z 2.55). The gate's hits are RoofChamber (inner housing ends, chamber walls) at old-save angles 78-138 / 222-282 deg, all blocked; builder check now tests r28 at all 360 deg: 0 hits. 319 glb scanned: no other model takes doorways.
- RESULT airlock m/l/r28 + junction rebuilt 0 flags; import done; check 317 scripts 0 failed; nav bake 160 grids / 162 occluder grids. RENDER asked to re-run the gate and count RoofChamber as structure, or order a new r28 layout.

## 2026-10-03 doorway head room (Paul's fault: roof beams across the corridor doors in the follow view)
- Check `tools/blender/interior_doorclear.py` (in rooms_build, report v3.door_headroom): no roof / ceiling / band part below 2.49 m (door top 2.24 + 0.25) inside a door opening + 1.5 m at any free angle. Before: 122 of 160 files hit (lowest 1.32 m). After: 0.
- Fix (Paul: raise, not cut): `interior_eave.py` lifts dome and setback roofs 1.20 m on a drum (1.40 -> eave 2.60, Upper_<seg>, upper_z [1.40, 2.65]) in 47 files; podium decks min 2.60 (10 types); ceiling MIN_Z 2.52, LINER_MIN 2.55; airlock RoofChamber object + skirts to 2.55; porch lamps, kitchen chimney, wall-line level bolts.
- RESULT 160 files rebuilt 0 flags; import done; check 314 scripts 0 failed; nav bake 160 grids / 160 room metas / 162 occluder grids; door_blocked unchanged; tris +0.4 %. Doorway follow renders (in/out) for habitat_m, lounge_m, water_recycler_m, electronics_fab_m, airlock_m, junction: opening clear. RENDER asked: setback upper patch, junction mouth upper patch, in-game check.

## 2026-10-03 v5 run 3 RESUME — indoor fps numbers + cuts, industry layouts, eye views re-rendered
- Perf vs 325d0af (157 files): tris 3.563 M -> 3.843 M (+7.9 %; critic-41 build was 3.912 M), mesh nodes 24,679 -> 29,315, draw groups (group x material) 6,746 -> 7,222, materials 2,560 -> 2,617. Ceiling + band 221 k tris, partitions 12.6 k. Cuts: liner about half the faces, ribs every 4th line, 4 band rows (was 6), fewer sensors/vents, signs merged into their `Upper_<seg>_Band` (-454 nodes), partition tops in their own `PorchTop_Part`. Asks to RENDER (ART-HAB-to-RENDER.md 2026-10-03): draw RoofCeil / Band / PorchTop_Part only near the camera room, no shadows, check occluder cost.
- Industry: control line per type (straight / arc round the machine / staggered); Work anchors moved, names unchanged. Academy class chairs moved (x - 0.38). Light colour per role in v3.ceiling.light; texture atlas proposed to RENDER, not built (needs UVs + a RENDER material).
- RESULT 160 room files rebuilt (0 flags), import done, check 312 scripts 0 failed, render_nav_bake 160 grids / 162 occluder grids, seat check 1 overlap (academy_m Seat_0, 70 mm, its own chair edge; sent to RENDER), pck 154.9 MB (was 156.1), room .scn 70.04 MB, door_blocked unchanged.
- RESULT beauty + eye renders for all 46 room types in art/interiors; I judged all eye sheets: no view inside geometry, bands, signs, walkway paint and role colours visible in every room. Remaining: seat-check anchor pick (RENDER), atlas (RENDER decision), fps profile (RENDER).

## 2026-10-02 v5 run 3 — 2.1 m partitions + critic 41 fixes (STOPPED by the user; models consistent)
- Built: unit partitions 1.30-2.10 m in `PorchTop` / `F<k>_PorchTop` (boxes in build report v3.partitions for RENDER), tube unit ceilings 2.40 m + FRIDGE.AI screen + roombot, slab undersides (block), no liner under the tube vault, role light colours (v3.ceiling.light), security black/red band, industry ceiling variants (crane / duct grid / truss) + type-coloured band + walkway paint, floor wear, junction totem + lost-and-found, storage aisle-end signs + floor numbers, water-recycler filter column, HR waiting rows + 2 reception jokes + new badge, auto eye-camera spots in `interior_render.py`.
- RESULT all 160 room files rebuilt 20:20-21:00 (0 flags), import done, check 312 scripts 0 failed, render_nav_bake 160 grids, seat check 1 overlap (shin) > 20 mm, pck 156.1 MB, my room .scn 71.3 MB. Changed models needing a nav rebake: ALL room files (already rebaked once after the last import).
- Not done: re-render of the eye views after these fixes (art/interiors eye renders predate them), texture atlas (needs RENDER shader support), console/bench moved per industry type, VR headset joke.

## 2026-10-02 v5 run 3 round 2 (coordinator) — ceilings, surfaces, density, industry heroes; the HR office

**Ceilings (every room type; `tools/blender/interior_ceiling.py`, hooked in `rooms_build.build_one`):**
- Object `RoofCeil` (RENDER's `group_of` -> `Roof`: hidden in the cutaway, drawn with the roof on): a panelled liner
  5 cm under any roof shape (polar grid, ray casts against the built Roof part; no liner under glass or lit faces),
  radial ribs (four with light strips), a ring rib, a cove light strip at the liner edge, a crown ring light, smoke
  sensors and vents. Low decks (2.32 m) get a flush liner with painted seams and a flush light ring.
- Role pieces: crane rail + hazard bridge + trolley + hook ("MAX LOAD: 1 INTERN") over industry / logistics (sized to
  the head room, placed where the machine leaves room), violet grow-light bars (farm), mirror ball + pendants +
  "LAST ORDERS: NEVER" (cantina), pot rack + pendants (kitchen), equipment ring rail with hanging chart monitors (labs),
  surgical lights (medical), round ducts (life support), copper pipes (distillery), banners (retail), a planet mobile
  "THE CLOUD" (academy), camera domes (security), cage lamps (jail), pendants with shades (housing, lounge, HR), and a
  hanging double-sided role sign.
- Rule for RENDER's camera ceiling grid: every hanging face at 2.45 m or higher; the liner is 5 cm under the roof.
- `Upper_<seg>_Band` / `Upper_<seg>_Sign` (`WallsUp`, masked per segment at a doorway): a panelled skin over the
  upper wall from 1.42 m to the ceiling (dome rooms showed the bare dome ring and the shell's outside paint band; podium
  rooms the back of the upper skin) with an accent stripe, and 2-5 big role signs at eye level (1.5-2.3 m), e.g.
  "SHOES OFF / ROBOTS TOO", "ASK A DOCTOR / NOT A CHATBOT", "WORK SMARTER / NOT HUMANER".
- `interior_render.py` hides `RoofCeil*` with the roof in the cutaway renders (as the game does).

**Surfaces and density:** work mats under every Work anchor (hazard edge in industry, accent elsewhere), a lit dance
floor in the cantina when the centre is free, "WAIT HERE" spots in medical rooms (`interior_surfaces.py`); table
clutter on every table by role (food trays, bottles, mugs; tablets, notebooks; toolboxes, wrenches; toys at home;
`interior_props.table_clutter`, 60-90 triangles a table).

**Industry identity:** one signature element per industry type on its machine (`interior_heroes.py`): mine sheave
wheel, refinery flue stack, polymer extruder spool, workshop giant wrench "EMPLOYEE OF THE MONTH", glassworks chimney
and glass sculpture, electronics clean-room hood, fabricator giant rubber duck half printed, steel exhaust hood, titanium
cooling tower, ceramics brick chimney, carbon fibre oven, battery "BIG CELL ENERGY" mascot, parts robot arm, magnet
giant horseshoe, superconductor maglev pod, metamaterial violet tesseract; and a floor colour per type inside the
machine's hazard line (`interior_fam_ind.ZONE`).

**Unit partitions 2.1 m:** code ready behind `FH_PARTTOP=1` (objects `PartTop` / `F<k>_PartTop`), NOT built: it needs
RENDER's yes (a group hidden in the cutaway and when shut) and a follow-camera rule that keeps the eye in the person's
unit. Asked in ART-HAB-to-RENDER.md 17:50; RENDER's 19:05 entry (the seat check) does not answer it.

**HR office (V5 section 17.1), `hr_office_{s,m,l}.glb`:** `rooms_v5hr.py` (civic drum, coral band, glazed wellness
pavilion with a ficus, lit roof sign "WE ARE LISTENING* / *TO MUSIC", badge `hr` = speech bubble with a heart) and
`interior_v5hr.py` (reception counter with "CHIEF PEOPLE OFFICER" plate and stress balls, a queue line "PLEASE QUEUE
(EMOTIONALLY)" with a "TAKE A NUMBER (ANY NUMBER)" post, interview rooms with tissues and "YOUR FEELINGS ARE VALID
(PENDING REVIEW)", the WELLBEING.AI kiosk ("HOW ARE YOU? 1 GREAT 2 GREAT 3 OTHER*"), filing banks, standing desks
"STANDING ONLY", the padlocked suggestion box "(LOCKED FOR YOUR SAFETY)", a water cooler "HYDRATE (MANDATORY)",
"SYNERGY" / staff-survey wall pieces). SIM's counts and anchor names (SIM-to-ART-HAB.md 2026-10-02) are used exactly;
until content has the def the builder uses `rooms_build_defs.HR_OFFICE` with the same numbers. Anchor table in
ART-HAB-to-SIM.md 19:10. Door angles: M, L free; S blocks three spans (307 deg free).

**Numbers (round 2 + HR):**

| | round 1 | round 2 |
|---|---|---|
| room GLB total | 264.6 MB (157 files) | 297.5 MB (160 files with HR) |
| triangles | 3,562,874 | 3,946,263 |
| room models in the pck (.scn) | 63.18 MB | 70.68 MB (+7.50 MB: round 2 about +6.2, HR +1.3) |
| pck `build/web_art_hab` (all agents) | 171.5 MB | 181.5 MB at 18:50; 155.0 MB at 19:45 (other agents' files fell by about 26 MB; my room files -0.17 MB between) |
| over budget / flags | 0 / 0 | 0 / 0 (budget + ceiling allowance S/M/L/XL 1900/2600/3200/3800) |

**Seat check (RENDER request 2026-10-02, `tools/render_seat_check.gd`):** 120 overlaps > 20 mm -> **5**. Fixes: bar
counter front recessed under a 0.30 m top (knee room; neon fins on the recess), glasses / tip jar / card reader on
the staff half; table_rect leg frames at the ends of the LONG axis (centre posts) and no apron; coffee tables 0.72 of
the asked size on corner legs; sofa plinth set back to a toe kick; the school desk top 0.76 m and its shelf at the
back; table clutter only at the ends of long tables (none on round tables, off-centre on coffee tables). Left (sent to
RENDER): academy_m Seat_0 thigh 66 mm, residence_tube_executive_l Seat_1 thigh 61 mm (both into a rail at seat height
beside the chair), cantina_xl Seat_1 hand 32 mm, habitat_s Seat_0/1 hands 21-22 mm.

**Checks:** RESULT rooms_build 157 + 3 built, 0 flags. RESULT godot.mjs check 310 scripts, 0 failed. RESULT
render_nav_bake 160 grids, 160 room metas. RESULT interior_desk_selftest PASS. RESULT render_seat_check 994 anchors,
5 overlaps > 20 mm (FAIL; was 120).

**Renders** (`art/interiors/`, looked at): every room type day / night / exterior / follow views `_eye0..2`, the HR
office S/M/L. Notes: ART-HAB-to-RENDER.md 19:10, ART-HAB-to-SIM.md 19:10.

**Not done / not tested:** the 2.1 m partitions (waiting for RENDER); in the game (the ceiling under RENDER's roof
two-sided rule, the WallsUp mask on `Upper_<seg>_Band/_Sign`, the camera ceiling with the liner); HR in SIM content.

## 2026-10-02 v5 run 3 (Opus ART-HAB) — detail pass reviewed, size cut, all rooms rebuilt, renders

**Art review of the prop kit** (showcase room with all 32 wall kinds, eye views of every room type):
- Dark text on light boards was `HullDark` (#8a929c) on `Hull` (#d9dde2), contrast near 2: it did not read in the
  follow view. `interior_props.INK` maps it to `Rubber` (#2b2d33) in every `text()` call (posters, boards, labels,
  floor marks). The poster `CushionLight` background had the same fault and is fixed by the same map.
- Repetition: an industry M room had 18 boards (two of each kind); every industry type showed the same set in the
  same order. Now each kind stands once in S/M/L (twice in XL), the role's signature piece comes first (safety
  board, still label, plant leaderboard ...) and the rest start at an offset from the room type, so two industry
  rooms differ. The kettle station, agents screen, menu board and GPU shrine stand once in S/M, twice in L/XL
  (`interior_kit.SAT_ONCE`); free-standing role decor once per room (plants, gnome, crates twice in XL).
- Photo walls: frames 1.5 x larger (they were 0.2 m wide and did not read). Wanted posters: the names (the joke)
  are short lines at 28 mm instead of 19 mm.
- Residences: the table pendant lamp hung at 1.56-1.79 m (head height; it filled the follow camera): now
  2.05-2.28 m (`interior_v5.pendant`).

**Size rules** (all in code, documented at the constants):
- `interior_props.text`: glyphs are the fewest non-overlapping rectangles (exact search, 15 % fewer quads); text
  under `GREEK_H` 19 mm is one bar per word (a 2 mm font pixel is below one screen pixel in the follow view);
  `keep=True` keeps desk plates readable.
- `interior_roles.Enricher`: `QUOTA` (4, 7, 10, 13) role wall pieces by size, spread evenly round the 32 slots;
  `KIND_CAP` (1, 1, 1, 2). The vending machine's snacks are cards behind the glass (-300 triangles).
- Academy S: a lighter wall pattern and two library shelves (it was the last file over budget).
- The build report records `_text_big/_mid/_greek` and `d_*` (free-standing decor) triangles in `props_tris`.

**Numbers:**

| | before (handover files) | after |
|---|---|---|
| room GLB total | 298.2 MB (pre-kit 227.6) | **264.6 MB** |
| triangles | 4,062,025 | 3,562,874 |
| files over budget | 19 | **0** (157 built, 0 flags) |
| room models in the pck (imported .scn) | about 71 MB (est.) | **63.2 MB** |
| pck `build/web_art_hab` | 160.5 MB (start of run) | **171.5 MB** (all agents; 170.3 MB at my first export, the +1.2 MB came from other agents' files; my files did not change between the two) |

Detail-pass share of the pck: part 2/3 about +8.8 MB (GLB +37 MB x scn ratio 0.239), part 1 +3.2 MB (estimate of
2026-10-01): about +12 MB for the whole pass. Not measured against a pre-kit export.

**Checks:** RESULT `rooms_build` 157 built, 0 flags (all within budget; no density flag; academy M empty patch 1.56 m,
retail L 2.11 m). RESULT `interior_desk_selftest` PASS. RESULT `godot.mjs import` done; `check` 298 scripts, 0 failed.
RESULT `render_nav_bake` 157 grids, 157 room metas (after the last import). `content/door_blocked.json`: one change,
storehouse_xl lane 0.81 -> 1.04 m (SIM told).

**Renders** (`art/interiors/`, looked at): every room type (M file; residence L, executive L, apartment block)
day, night, exterior and three follow views at 1.8 m over the shoulder (`<id>_eye0..2.png`); unit and penthouse
follow views `residence_tube_l_unit_eye0..1`, `residence_tube_executive_l_unit_eye0..1`,
`apartment_block_m_unit_eye0..1`; apartment floors `apartment_block_m_floor0..2`; paired desks
`research_lab_m_spot0.png`. Notes: `docs/requests/ART-HAB-to-RENDER.md` (157 changed files, nav rebake done, a
proposal), `ART-HAB-to-SIM.md`.

**Open / not done:**
- Residences in the follow view: 1.30 m unit partitions read as cubicles at eye height 1.8 m. Partition tops in
  the Roof group are proposed to RENDER (needs their follow camera to stay on the person's side of a partition).
- The 17 industry types still share one layout language at a distance (machine centre, consoles, crates); the role
  props differ by type now but the silhouettes do not.
- Not tested: in the game (RENDER's cut, path and seat checks on this build); `check_desk_seats` for the academy and
  security desks (they use table footprints).

## 2026-10-02 v5 run 3 — HANDOVER (stopped by the coordinator; the Opus ART-HAB agent takes over visual work)

**Changed (code, all in tools/blender):**
- **Wall-piece depth rule** (the posters that sank into the panel): the wall facet is a chord, so its panel stands Ri*(1-cos 5.625 deg) = 0.5 % of Ri (3 cm at M, 6 cm at XL) in front of radius Ri; the old slot origin sat 2 cm behind Ri, and WALL_OFF 3.5 cm was too small on big rooms (jail, distillery, all XL). `interior_kit.wall_slot` now puts the slot origin ON the panel (x = 0), `Plan.wall_items` gives builders the depth `d - shift` so item fronts stay where the plan put them, and `Plan.check_piece` flags any flat wall face that lies behind the panel or is cut by the skirting (z < 0.29), the pipe run (z 0.345-0.475, 7 cm deep) or the cove light (z 1.255-1.335, 4 cm). Flat pieces live in z 0.50-1.24 (`interior_props.ZLO/ZHI`, `WALL_OFF = 0.004`). Back plates of racks, shelves, sample racks, mushroom shelves, toolwall, suit rack, bench brackets moved to 7.5-8 cm; wall screens (`wi_panel`, `wi_desk`) lowered. Result: 0 `piece` flags on all 158 files; jail_m and distillery_m posters render clear of the panel (`art/interiors/jail_m_props*.png`, `distillery_m_props*.png`).
- **Prop kit part 2 and 3** (V5 15.3 in every room type): `interior_roles.py` (30 wall kinds by room role: safety board, foreman bot, roster, hard hats, gauges, extinguisher, AGI countdown, vending machine, time clock, whiteboard, seed rack, plant leaderboard, air board with duck, inventory screen, barcodes, eye chart, AI diagnosis, peer-review poster, wanted board, tally marks, blackboard, route signs, photo wall, shop signs, suit check, air fryer, jukebox, recipe screen, still label; one motto sign per room type in `MOTTOS`; `ROLE_OF` / `ROLE_KINDS` tables; `Enricher` replaces filler wall kinds inside `Plan.wall_items`, so every family gets them without a builder change) and `interior_roles_decor.py` (11 free-standing pieces: snack corner, whiteboard stand, server cabinet, tool trolley, crates with stencils, drone dock, gnome with VR headset, plant with a chat stake, ring light, three bins, kiosk; capped per kind by `cap_for`, registered into `interior_families.DECOR` and the `V4_KINDS` lists by `interior_rooms._register_v4_decor`). New poster kinds in `interior_props`: captcha, travel, wellness, cat (wall kind `vibeposter`). Also: painted floor texts on the walking ring (`interior_roles.floor_marks`, called from `interior_rooms.finish`), a joke label on every standing console (`interior_furniture.console`), airlock chamber notices and suit-check screen, residence unit walls use photo walls and the new posters (`interior_v5.wall_art`), `V4_MAX_PATCH` 2.5 -> 1.9 m. Build check: `rooms_build` flags a room with fewer than 4 prop kinds or no satire piece (`airlock_r28`: 1); the build report has `props` and `props_tris` per file; the interior triangle budget is now v3 x 1.8 for every room type.
- **Tools:** `interior_render.py` modes `wall` (low look along the wall: `--angles a,b --span 5`), `eye` (the follow camera: 0.55 m right, 1.9 m behind, 1.8 m high, fov 50, a stand-in figure; `--eye auto` or `--eye "x,y,yaw[,floor];..."`, `--night` for lamps) and `spot` (`--spot "x,y,azimuth,elev,half"` with figures); env overrides `FH_MODEL_DIR`, `FH_THUMB_DIR`, `FH_REPORT_DIR`, `FH_ART_DIR`, `FH_DOOR_OUT` for scratch and parallel builds; `interior_roles_show.py` (empty room showing chosen wall kinds via `FH_ROLE_SHOW`); `interior_desk_selftest.py`.
- **Desks (ORCH 2026-10-01):** `blender --background --factory-startup --python tools/blender/interior_desk_selftest.py` -> RESULT PASS: the real research lab M passes `check_desk_seats` (2 desk seats, 6 desk bodies), a seat moved inside a desk top is flagged, a seat with its screens behind it is flagged. Render of the paired desks (monitors at the divider, chairs and figures on the open sides, figures facing the screens) is in the old session scratchpad `...scratchpadart
esearch_lab_m_spot0.png`; re-render it into `art/interiors` with `--only spot --spot "0,2.85,-60,28,2.4"`.

**Models on disk (valid, loadable; not yet imported into Godot):** all 158 room files rebuilt 15:49-15:57 by six parallel `rooms_build.py --only <group> --no-thumbs` runs (FH_REPORT_DIR and FH_DOOR_OUT per run, then merged into `tools/blender/build_report.json/.md`, `content/door_blocked.json` and `docs/requests/ART-HAB-door_blocked.json`). They were built BEFORE the last code edits (floor marks, console label, caps of role pieces, residence photo walls, size-dependent filler chance, triangle recording), so the code on disk and the files differ: **rebuild all once more.** Numbers of this build: GLB total 227.6 -> 298.2 MB (+70.6 MB; at the pck ratio 0.30 about +21 MB, measure with an export), triangles 3.03 M -> 4.06 M. 19 files over budget, nothing else flagged: 17 S files (S budget 18,000: 18,061 to 22,207) plus academy_m 27,256 / 27,000 and distillery_m 29,131 / 27,000; the edit `Enricher.FILLER_CHANCE` by size (0.5 / 0.7 / 0.8 / 0.85) and `HEAVY` skip in S is written but not yet built (a scratch test: lounge_s 18,200, academy_s 19,434 still over; academy_m 26,838 ok). Next: trim S further (fewer fills or cheaper pieces: wanted 1,022 tris, stilllabel 874, plantboard 862, vending 736, seedrack 712, whiteboard 684, foreman 640, fryer 638), rebuild, `door_blocked` is unchanged by this work except storehouse_xl (the baseline run of 15:47 rewrote it once with the depth rule; SIM has not been told).
- **Not done:** the day / night / exterior renders of every changed room and the eye views for the critic (use `interior_render.py --file <id> --only beauty,night,exterior`, `--only props`, `--only eye --eye auto`); the residence / penthouse eye views (`--eye "x,y,yaw,floor"`); `node tools/godot.mjs import` and `check`; the list of changed models for RENDER in `docs/requests/ART-HAB-to-RENDER.md` (all 158 room files) and the nav rebake; the SIM note (door_blocked); `check_desk_seats` coverage of the academy and security desks (they use table footprints, not `sit_desk`); the S-size budget; the critic carry-over (academy M bare floor, retail L patches: the filler change should close them, measure `plan.v4_patch`); measuring the pck.

## 2026-10-01 v5 (2) — desks, jail beds, detail pass §15.3 (PAUSED by the user)

- Done: desk pods back to back (research lab, `deskpod` decor), table chairs moved so stand points are 0.12 m off the edge, check `interior_kit.check_desk_seats`; jail `Anchor_Bed_<i>` = `Cell_<i>`; distillery night/L/S/XL renders; academy floor AI timeline; prop kit `interior_props.py` (pixel-font parody posters, screens with content, desk clutter and job plates, chatbot kettle, subscription toaster, GPU shrine, agents booking screen, menu, neon); every room type rebuilt 0 flags except jail and distillery (built earlier today with the kit but before the 3.5 cm wall-piece offset). Import + check 293 scripts 0 failed; pck 160.0 MB (detail pass about +3.2 MB, estimate from GLB +10.6 MB x scn ratio 0.30). Notes to SIM and RENDER written (first part).
- **Nav rebake (RENDER): every room model** — all room types S–XL, airlock_m/_l/_r28, junction, residence_tube (+executive), apartment_block_m, retail, park, academy, security_office, jail, distillery (all rebuilt 2026-10-01).
- Not done: jail + distillery rebuild with the wall offset (posters partly sink into the wall panel there); renders after the final rebuild (the close views in `art/interiors/*_props*.png` predate the offset); RENDER note listing the detail-pass files; residence follow-view check.

## 2026-10-01 v5 — distillery (PAUSED by the user)

- Distillery S/M/L/XL built (`rooms_distillery.py`, `interior_distillery.py`, `Copper` material, badge "distillery"): 14,430 / 18,015 / 26,058 / 36,702 tris (budget 18k / 27k / 39.6k / 54k), 0 flags, verify ok, thumbs, import params set, Godot import + check 292 scripts 0 failed; `content/door_blocked.json` rewritten (distillery 360° free; SIM not yet told).
- Code only, NOT rebuilt: jail `Anchor_Bed_<i>` = `Anchor_Cell_<i>` (`interior_v5civ.cell`); the jail files on disk lack Bed anchors. Not done: distillery night renders and S/L renders, RENDER nav-bake request, SIM note, critic carry-over (academy M front floor).

## 2026-09-30 (3) — bed anchors (coordinator decision) and critic round 37

- **Beds:** upper bunk anchors in every family unit (tube, block), the third penthouse bedroom anchored; counts
  match SIM's content (tube family 8/12/16, block 48). Names posted in `ART-HAB-to-SIM.md`.
- **Round 37:** retail L — a second gadget run, a cafe zone (coffee bar, two or three tables with chairs, wood
  floor), the filler now places short shelf runs and displays only (no small scatter); academy M/L — a library wall
  of four shelves on the −X −Y arc and a second lab bench; the retail bag badge is white Light (bright at night);
  executive — a large bordered rug under the beds, a round rug under the dining table, a rug in the XL office, a bath
  mat, pictures in every room.
- Build 0 flags; Godot check 265 scripts 0 failed; export 102.3 MB (all agents); my v5 share 11.93 MB.
- Blender polishing stops here (coordinator); next is RENDER support in game.

## 2026-09-30 (2) — critic round 35 fixes

1. **Colours to the V5 contract:** new materials `SecBlack` #1B1F24, `SignalRed` #D93A3A (+ `SignalRedGlow`),
   `PrisonOrange` #FF7A1A (+ `PrisonOrangeGlow`) in `build_assets.MATERIALS`. Security: black band, red coping, red
   deck ring, red mast bands, red beacon, red glow ring, red shield. Jail: prison-orange band, orange top band on the
   perimeter wall, orange tower bands, orange glow ring, orange padlock. No Fabric / Hazard / Ember / BeaconAmber left
   on either.
2. **Re-rendered with the new kit:** `jail_l`, `park_l`, `retail_l` (+ `_exterior`, `_night`), also `retail_m`,
   `academy_m`, `security_office_m`, the tube L family and executive (+ night); identity shots with the L sizes
   (`v4_identity_v5civic_{110m,250m}` + `_night_`).
3. **Fuller floors:** retail — a gadget gondola row, a two-lane till queue, a second fitting booth (M, L), filler to
   1.5 m; academy — a second class at −X (4 desks, own board; M, L), a library corner (arc of shelves, two armchairs,
   rug, floor lamp), the lab bench moved, filler to 1.6 m.
4. **Retail at night:** a light line on every canopy stripe edge, a Neon rim round the canopy, a Neon frame round
   the billboard.
5. **Executive set visible:** wood platform beds with a padded foot rail, deep red / dark duvets, a red tufted
   headboard wall in a wood frame, a sectional sofa with a chaise. Night: a soft ceiling fill per room in the
   residences' night render (a 2.6 m disk light over every `Anchor_Light_*`) — the look asked of RENDER.

Build: 0 flags (v5 triangle budget now v3 × 1.8). Godot check 264 scripts 0 failed; export 102.2 MB (all agents);
**my v5 share 11.92 MB**.

## 2026-09-30 — critic round 33 fixes done (resumed)

All fixes of `docs/critic/round_33_residences_civic.md` are in, built (21 files, 0 flags, verify ok), imported
(import params: no LOD, no shadow meshes, no tangents), Godot check 258 scripts 0 failed, export `build/web_art_hab`
101.8 MB (all agents). **My v5 share: 11.70 MB** (budget 25).

| fix | what |
|---|---|
| 1 own badges | retail shopping bag, academy mortarboard, security shield with a star in red (Ember), jail padlock in amber (BeaconAmber); `rm.badge_family`, `rooms_identity.ICONS` |
| 2 silhouettes | retail: striped canopy roof (a pink/white pinwheel from above), lit signs over every awning, a larger billboard; academy: schoolhouse hall with a gable roof and a clock tower, observatory; security: black drum, red band, red ring on the dark deck, 8 m lattice comms mast with a red beacon and dishes, watch tower with a light bar; jail: orange band, raised perimeter wall, four guard towers with floodlights, barred slits |
| 3 fill empty floors | filler target 1.8–1.9 m with type items (display tables, mannequins, promo bins; group-work tables, shelf islands; equipment racks; day-room tables); a fitting booth at every retail size; the jail S/M yard strip |
| 4 security command post | a raised dais (0.16 m, walkable) with the command desk facing a three-part monitor wall, a dispatch console (M), lockers, briefing table with a screen top, holding cell, front desk with the response line, map table |
| 5 night | a lit ring under every civic parapet (white, red for security, amber for jail), lit badges (emissive icons), lit signs, beacons, floodlights |
| 6 apartment block | a balcony per unit on the floor-1 band (wood deck, glass screens, table and chairs, loungers, planters, a lamp); bigger penthouse pools with a lit edge, parasols; lit eave bands on floor 0 and floor 1 |
| 7 executive / night fill | an executive bed set (upholstered platform, deep duvet, bolster; shared headboard wall), a pale sofa; a ceiling light anchor over **every room** of the tube and the block |

Identity shots re-rendered: `art/interiors/v4_identity_v5civic_{110m,250m}`, `_night_110m`, `_night_250m`;
`v4_identity_v5block_*` (same four). At 110 m by day all five civic modules read apart without labels.

Not tested: in the game (RENDER's floor rule for `F<k>_WallTop`, the extra Light anchors' cost).

## 2026-09-30 — PAUSED (Paul) during critic round 33 fixes

- **Done (built, 0 flags, verify ok, not yet imported/exported):** own badges (shopping bag, mortarboard, red
  shield, amber padlock); new silhouettes (retail striped canopy + lit signs + billboard; academy schoolhouse + clock
  tower; security black drum, red band, red deck ring, lattice comms mast with red beacon; jail orange band, raised
  perimeter wall, 4 guard towers with floodlights); lit glow rings; security command post (dais desk, monitor wall,
  dispatch, lockers, holding cell); denser retail/academy/jail (fitting booth all sizes, group tables, jail S yard
  strip); executive bed set; a ceiling light per room in tube and block; block balconies on floor 1, bigger
  penthouse pools and parasols, lit eave bands. Identity shots 110/250 m day/night re-rendered; interior renders
  of retail_m, academy_m, security_office_m, jail_s, residence_tube_executive_l, apartment_block_m floors rendered
  but **not reviewed**.
- **Half-done:** Godot import + `glb_import_params` for changed files, check, export and pck measure; progress and
  request notes for round 33 (RENDER: more Light anchors are a soft fill; SIM: jail S Yard_0).
- **Next step:** review the renders above, then `node tools/godot.mjs import`, import params, `check`, `export
  build/web_art_hab`, measure pck, write the round-33 report.

## 2026-09-29 (4) — v5: the civic modules (retail, park, academy, security office, jail), all sizes

- `tools/blender/rooms_v5civ.py` (exteriors) and `interior_v5civ.py` (interiors); 14 files, 0 flags, verify ok.

| type | sizes | exterior | interior |
|---|---|---|---|
| retail | S M L | shop windows all round, striped awnings, a lit sign pylon, skylights | sections on coloured floors (clothes, snacks, gadgets, gifts), till counter with a queue line, gondola rows, clothes rails with mannequins, display tables, promo bins, fitting booth (L), fridges and bottle shelves on the wall |
| park | M L XL | lattice glass dome, crown hub, lamp ring; badge on a plate over the crown | lawn, a gravel jogging loop and cross paths, trees, flower beds, bush clumps, benches, lamp posts; pond with a fountain (L, XL), wedding arch (L, XL) |
| academy | S M L | clerestory windows, an observatory dome with a telescope, the science mast | student desks in rows facing a teacher board, teacher desk, instructor console (L), holo globe, science corner (lab bench), children's reading rug, shelf islands |
| security_office | S M | armoured drum with slit windows, a watch tower with a blue/amber light bar, a radio mast with a beacon and a dish | front desk with a response line, monitor console (M), briefing table, lockers, a holding cell, map table, equipment racks, gear crates |
| jail | S M L | dark heavy drum with barred slit windows, a guard tower with a searchlight, a roof fence with floodlight masts | 2 / 4 / 8 barred cells (bunk, WC, basin), guard console, visiting table, day-room tables; at L a fenced yard with a hoop |

- New family `civic`: shield badge icon (`rooms_identity.ICONS`), accent **#34569c** (`build_assets.ACCENTS`) —
  proposed to RENDER (models.gd colour table) and SIM.
- Anchors follow `furniture` counts (Seat / Work / Stand) with SIM's names as aliases at the same points:
  `Counter`, `Browse_<i>`, `Jog_<i>`, `Wedding`, `Class_<i>`, `Teach`, `Console_<i>`, `Desk_<i>`, `Locker_<i>`,
  `Cell_<i>`, `Guard`, `Yard_<i>`.
- A greedy filler (`interior_v5civ.fill`) closes empty patches with type-fitting items; every file ≤ 2.5 m.
- pck: civic 5.24 MB (14 models + thumbnails). **My v5 total 11.23 MB** (budget 25). Export `build/web_art_hab`
  101.3 MB with all agents (v5 limit 200 soft / 300 hard). Godot check 258 scripts, 0 failed.

Renders: `art/interiors/{retail_m,park_l,academy_m,security_office_m,jail_l,jail_s,retail_l}.png`, `_exterior` for
the first five; identity `v4_identity_v5civic_{110m,250m}` (+ `_night_`).

Not tested: in the game; RENDER's use of the alias anchors; the park's jogging loop with real walkers.

## 2026-09-29 (3) — v5: the apartment block (XXL, 3 floors)

- `tools/blender/rooms_v5apt.py` (exterior, plan constants) and `interior_v5apt.py` (three floors). A stepped round
  block: floor 0 radius 20 with unit yards; floor 1 steps in to 15.4 (garden terrace with rails, planters, loungers
  at every living-room door); floor 2 (two penthouses) steps in to 11 under a flat roof, with a glass-roofed terrace
  (plunge pools, loungers, dining sets, planters) on the floor-1 roof; the lift and stair core rises through the roof
  as a lit crown carrying the house badge.
- Plan per floor: core (glass lift shaft, 16-step spiral stair), lift lobby ring, five shared rooms (floor 0 lobby
  with mail lockers, laundry, gym, play room, bike store; floor 1 library, laundry, hobby room, play room, lounge),
  round street with light lines, five family units between five spokes (parents' room, children's room with bunk,
  bath, living with kitchenette, table, pendant, sofa group), yards on floor 0. Penthouses: master bedroom with
  headboard wall and en-suite bath, living/dining/kitchen with lounge and reading corner, two more bedrooms, terrace
  door.
- Pipeline: `F<k>_` objects (`rooms_kit.floor_of`, own game group, own AO set, palette merge), cut check per floor,
  per-floor density and stand-point checks (`rm.floor_flags`), `FloorPlan` (shared anchor numbering, anchors lifted
  to the floor), budget 60,000 × floors; `interior_render.py --only floors` renders each floor's cutaway.
- Result: 0 flags; 144,855 tris (budget 180,000); empty patch 2.68 m on each floor; door slots 32 (need 6); anchors
  Bed 26, Seat 16, Stand 6, Unit 12, Lift 3, Door 6, Light 12.
- pck: `apartment_block_m.scn` 2.48 MB + thumbnail 0.06 MB. My v5 total so far **≈ 6.0 MB** (tube 3.45 + block 2.54).
  Export `build/web_art_hab` 94.8 MB (all agents). Godot check 257 scripts, 0 failed.

Not tested: in the game (RENDER floor hiding, per-floor nav, lift use); the terrace furniture and upper-floor rooms
from the follow view.

## 2026-09-29 (2) — v5: residence tube critic 27 fixes; sizes M and XL; content defs back

- **Content:** SIM's v5 defs are back in `content/buildings.json` (18:31, identical to my copy). The fallback
  (`v5_defs_snapshot.json` and the loader branch) is removed: content is the only source again.
- **Critic 27 fixes:**
  1. Empty ring → per-unit **yards** behind every cell (lawn for family, wood deck for executive; planter borders,
     a patio table and chairs or two loungers, a sandpit, a tree) and **corner lawns** beside the street ends.
     Largest empty patch now 2.16–2.63 m (all six files ≤ 2.7 m, the build gate).
  2. Executive: wood floors in every room except the bath, rugs, framed wall art (3 per unit), bookcases, an
     upholstered headboard wall with reading lights, a plant per room, a pendant lamp over the dining table.
  3. Night: pendant lamps with lamp anchors over every family and dining table; the street edge lines are
     LightStrip.
  4. Vault: HullDark foot band, seam lines between the ribs, larger porch lamps (Light) under the canopies and on
     the end walls; the executive ridge has a lit strip.
  5. Executive at 250 m: a gold stripe (L5Gold) along both sides of the vault; the terrace fills the −Y deck (pergola,
     cushioned loungers, low table, planters, bollard lamps). Lamps, ridge strip and terrace are in a `PorchTop`
     part (a known group, hidden with the roof in the cutaway), so the Roof group stays at ≤ 6 surfaces.
  6. Children's rooms: striped rug, red toy chest with coloured fronts, a small desk and stool from size L.
  7. 250 m night shot: `art/interiors/v4_identity_v5res_night_250m.png` (and `_night_110m`).
- **Sizes M and XL** built (Family and Executive). All six files: 0 flags, verify ok.

| file | tris / budget | empty patch | door slots |
|---|---|---|---|
| residence_tube_m | 23,014 / 24,000 | 2.16 | 14 |
| residence_tube_executive_m | 22,142 / 24,000 | 2.41 | 14 |
| residence_tube_l | 33,204 / 35,200 | 2.63 | 17 |
| residence_tube_executive_l | 28,756 / 35,200 | 2.63 | 17 |
| residence_tube_xl | 38,996 / 48,000 | 2.37 | 21 |
| residence_tube_executive_xl | 36,166 / 48,000 | 2.63 | 21 |

pck: residence tube total **3.45 MB** (6 models 3.12, 6 thumbnails 0.33); export `build/web_art_hab` 91.5 MB with
all agents' work. Godot check 256 scripts, 0 failed.

Renders: `residence_tube_{m,l,xl}.png` and `_exterior`, executive likewise; L also `_night`, `_anchors`;
identity day and night at 110 / 250 m.

Not tested: in the game (RENDER variant lookup, nav grids); the yards are open to the aisle ring (no back doors
from the units: the back rooms have no free wall for one).

## 2026-09-29 — v5.0 (V5_DESIGN §7): residence tube pilot (L, family + executive)

What landed:
- `tools/blender/rooms_v5.py` — exterior. A half-cylinder vault (radius 0.48 Rw, 16 segments) along model X on a
  2.55 m drum; Frame ribs every ~1.9 m, heavier end ribs; flat end walls with a glazed centre and mullions; a glazed
  porch (drum glass) and a sloped canopy with lamps at each end (0° / 180°); flat side decks. The house badge is
  drawn flat and wrapped onto the vault (no stretch), turned −35° for the game camera. Family: small windows in every
  other bay, skylights and vent units on the decks. Executive: ribbon windows in every bay, a lit ridge skylight,
  larger end glazing, a roof terrace (wood deck, planters, loungers, rail) on the −Y deck.
- `tools/blender/interior_v5.py` — interior. A street along X from porch to porch; cells on both sides; low unit
  walls (1.30 m, in Interior). Family unit: kitchenette, family table (4 chairs, 2 seats), parents' room (two beds),
  children's room (bunk bed, toy chest, rug, toys; desk at XL). Executive unit: bedroom (two beds, wardrobes, rug),
  en-suite bath (tub, shower, WC, basin), office (desk, chair, shelves), lounge (sofa, coffee table, rug, media wall,
  floor lamp, plant, sideboard), dining table, kitchenette. Commons cells: family play room + laundry; executive
  residents' lounge (bar, stools, armchairs). Garden strips (planters, benches, trees) behind the cells; entry
  corners (door mats, benches with coat hooks, mail lockers, plants) at the porches.
- `rooms_build.py`: `size_list` honoured; variants → one file per variant (`<id>_<size>`, `<id>_executive_<size>`),
  furniture per variant; door-slot minimum from `sizes.max_links`; v5 triangle budget = v3 × 1.6.
- `rooms_kit.load_buildings`: fallback `tools/blender/v5_defs_snapshot.json` for v5 ids that content lacks (SIM's
  defs left `content/buildings.json` at 18:30).
- `interior_render.py`, `rooms_v4shots.py`: variant file names.

Checks (both files): 0 flags; verify ok; radius 10.90 / 11.00; door slots 17 (need 5), no blocked angles; empty
patch 2.63 m; cut check ok. Family L 30,946 tris, Executive L 27,296 (budget 35,200).
Anchors: family Bed 9, Seat 6, Stand 3, Unit 3, Door 5; executive Bed 4, Seat 6, Stand 2, Unit 2, Door 5.

pck: `build/web_art_hab` 86.0 MB at 18:50 (other agents' v5 work included). Mine: residence_tube_l.scn 0.525 MB,
residence_tube_executive_l.scn 0.475 MB, 2 thumbnails 0.107 MB = **+1.11 MB** (budget +25 MB). Import params set
(no LOD, no shadow meshes, no tangents). Godot check 256 scripts, 0 failed.

Renders (`art/interiors/`): `residence_tube_l.png`, `_exterior`, `_night`, `_anchors`;
`residence_tube_executive_l.png`, `_exterior`, `_night`, `_anchors`; `v4_identity_v5res_110m.png`, `_250m.png`
(game camera, with habitat L and lounge L beside them).

Not tested: the files in the running game (RENDER has no variant lookup yet, no nav grid bake); people walking the
unit doors (RENDER planner clearance 0.30 m vs 0.84 m inner doors); M and XL (not built yet, layouts written);
night renders only looked at in Blender.

Next: CRITIC pilot rating → fixes → M, XL → apartment block (floors, lift/stair core, floor groups with RENDER) →
retail, park, academy, security office, jail.

## 2026-09-28 — critic round 22 fixes 1–4

- Rover depot: bay portal frames with hazard stripes and green status lamps, an Accent band round the walls, roof
  ribs, a side annex (office, window, door, roof unit, beacon).
- Logistics (storehouse, cold storage): the deck is light Hull (`rooms_identity.lighten_deck`) and a cargo crane
  with a 6–8 m Hazard-yellow jib (`cargo_crane`, kept inside the footprint).
- Outpost core: a ring deck with a LightStrip rim, a rail and struts; a 5 m flag mast with an Accent flag and a lamp.
- Boulders: new `Rock` (#a07458) with sun-lit tops (`ext_common.vc_gradient`) and a `Dust` skirt.
- Pictures: `art/interiors/v4b/`, `v4_identity_v4_logistics_*.png`.

## 2026-09-27 — SIM's 12 industry buildings, door slots, pck cleanup

- Rooms `rooms_v4ind.py` + `interior_fam_v4ind.py`: 9 types × S–XL; exteriors in `ext_v4.py`: fuel rod plant,
  He-3 separator, graphene reactor. Build 132 room files 0 flags; ext_verify 60 + new 0 flagged.
- Door slots (S 4 / M 6 / L 7 / XL 8 at 3.74 m spacing): `rooms_build.door_slots`; all 33 types pass; replaces the
  120° / 180° rule. `content/door_blocked.json` regenerated.
- Copies removed (40), import settings on every file: pck 94.4 → **77.2 MB**. Godot check 217 scripts / 0 failed.

## 2026-09-27 — 4.0 buildings (ext_v4.py) and the airlock and junction at 1.5 ×

- New: `boulder_a..f`, `rover_depot_m/_l` (ART-B bays, `Anchor_Bay_<i>`), `fission_reactor`, `crystal_refinery`,
  `chemical_plant`, `crevice_bridge_s/_l`, `outpost_core`. All pass ext_verify (60 older files 0 flagged).
- Airlock M 5.1, L 6.0 (chamber by size, dome +0.6), junction 3.75, as SIM asked; r28 stays.
- pck **71.5 MB**. Godot check: 4 UI scripts fail on `ui/theme/glass_frame.gd` (UI's work, not mine).
- Waiting: SIM's list of mid / high-end industry buildings; RENDER's `_m` fallback (then the copies go);
  corridors 1.25 × with RENDER.

## 2026-09-27 — v4.0 ROLL-OUT: every room at 1.5 ×, identity on every family (critic round 17 fixes 1–4)

- Round 17 fixes:
  1. The icons glow (Neon); the kitchen vault has Glow grow lights.
  2. The badge disc is HullDark with a Frame rim, 0.34–0.38 × Rw (was a black disc, 0.36–0.56).
  3. Lab: the mast is twice as thick, with a 1.5 m tilted dish, a bigger beacon and science-blue (Accent) gores.
  4. Density by function: the greedy filler (`interior_rooms.v4_decor`, build check ≤ 2.5 m +0.2 grid) and
     specific items: kitchen 3+ tables with the seats shared out, a prep island, a pantry wall; lab desk pods;
     workshop bench line; habitat lounge corner and lockers.
- Roll-out: `rooms_kit.V4STYLE` on by default, R = 1.5 × `tools/blender/v3_radii.json` (`FH_V3=1` builds the
  3.x rooms). Airlock and junction unchanged. Tray offsets × (built R / content R).
- Every other family: `rooms_identity.identity_pass` — the family badge on the largest smooth free roof patch
  (or a badge plate over the crown), industry stacks, a logistics crane, a science mast, a dome foot ring;
  medical keeps its big red cross.
- Build: 96 room files 0 flags, 30 link files 0 flags; `content/door_blocked.json` regenerated (23 files changed).
- **pck: 79.7 → 60.9 MB** (import settings: no LODs, no shadow meshes, no tangents) **→ 70.9 MB after the
  roll-out.** Godot check 192 scripts / 0 failed.
- Pictures: `art/interiors/v4_identity_v4_rollout_*.png`, `v4_identity_v4_families_*.png`.
- Open: corridors 1.25 × wider (door kit and fx_doors, with RENDER); the new buildings; RENDER's in-game identity
  test (fix 5); SIM's content radii.

## 2026-09-27 — v4.0 room identity PILOT (V4_DESIGN §2, §3)

- Pilot build mode: `FH_V4PILOT=1` builds rooms at 1.5 x the content radius into `build/v4pilot/` (outside the
  game assets; the live game and the pck do not change). `rooms_kit.V4STYLE` switches the identity on.
- Pilot rooms, M: habitat R 8.25, kitchen 6.90, workshop 7.50, research lab 7.50. All build checks pass.
- Identity (`tools/blender/rooms_identity.py`):
  - habitat: a low dome with 12 large lit windows and the house badge;
  - kitchen (food): a flat deck with a glass greenhouse vault, herb beds, the chimney and the leaf badge;
  - workshop (industry): the hall with two tall hazard-banded stacks, vent units and the gear badge;
  - research lab (science): a tall striped dome with a glowing sensor ring, a lattice sensor mast, a dish, a
    beacon and the atom badge.
- Badges: the family icon (Accent) on a dark disc with a light rim, 0.36–0.56 × Rw, turned for the game's
  default camera. Stronger band: the wall band is 0.38 m (was 0.19) with a Neon pin line; the podium upper
  band is 0.34 m.
- More furniture: family decor clusters on the extra floor (`interior_rooms.v4_decor`), clear of the
  people anchors and inside the door lanes.
- Pictures: `art/interiors/v4_identity_v4_{110m,250m}.png`, `_night_`, and before: `v4_identity_v3_before_*`;
  the room sheets are in `art/interiors/v4pilot/`.
- Size: the pilot GLBs are 26–57 % larger than v3 (habitat_m 1.14 → 1.44 MB). A 1.5 x roll-out needs mesh
  compression to stay under 95 MB; to be measured at the roll-out.

## 2026-09-26 — RENDER cut check 116: wall items above the cut

- My check measured the wall ring only; RENDER's measures every drawn vertex (the correct rule). Their run
  also overlapped my rebuild. Now: `fit_under_cut` scales every wall item under 1.396 m, and `cut_top_check`
  uses RENDER's rule. Build 96 files 0 flags; GLB probe 0 of 96 above the cut. Godot check 172 / 0 failed,
  export done. RENDER asked to re-run `render_cut_check.gd`.

## 2026-09-26 — Paul: cutaway top edge ("polygon bleeding")

- Cause: `Upper_*` skin and podium ribs drawn in the game cutaway (RENDER now hides them as WallsUp), plus
  wall-mounted items 1.44–1.48 m poking through the cut. Fix: `clamp_wall_tops`; check `cut_top_check`
  (96 files, 0 flagged). Tools: `probe_gamecut.py`, `probe_cutaway.py`. Godot check 172 / 0 failed, export done.

## 2026-09-25 — critic round 14: cut-wall caps

- FrameCap / InnerFrameCap / OuterFrameCap, collar caps and chamber wall caps: a light Trim plate (8 mm proud)
  with a Frame-coloured top inset 2.5 cm (`interior_links.cap_plate`, `cap_top`). Links 30 ok, airlocks 0 flags,
  cutaway probe 0 objects above 1.40 m. Godot re-imported, check green, exported.

## 2026-09-25 — critic round 13 (airlock in game, housing cap, airlock 49)

- Airlock cutaway: 0 objects above 1.40 m in the groups the game shows (probe + build check). Porch pole top →
  `PorchTop` (RENDER adds the group). Suit racks and refill ports clamped. Rib stubs in all rooms end at 1.40.
- `FrameCap` / `InnerFrameCap` / `OuterFrameCap`: clean cap plates at 1.40 m; the fighting top and bottom faces
  were removed; the collar cut is capped.
- Airlock 49 (r28, 259.5°): no wall item beside the inner door housing ends; bench already a wall item.
- Build: 96 rooms 0 flags, 30 links 0 flags; Godot check 169 / 0 failed; export pck 79.6 MB.

## 2026-09-25 — minimum free door angle, content door file, airlock bench

- Build check: S ≥ 120°, M/L/XL ≥ 180° free; airlock lanes may be blocked only by the chamber.
- `content/door_blocked.json` and the docs copy are written by every room build (the same file).
- Oxygen plant S 0° → 189°, M 78° → 221° (one plinth in the −Y half). Greenhouse, fungus L/XL: 360° with SIM's trays.
  Fungus M 184° (4 racks; 3 racks is SIM's decision).
- Airlock bench → wall item. r28 75° free, with no furniture in any lane.
- Build: 97 rows 0 flags; Godot check 167 scripts / 0 failed; export pck 79.6 MB.

## 2026-09-25 — coordinator decisions: door lanes to SIM, airlock_r28

- `airlock_r28.glb` (R 2.8, old saves): new design, 2 riders, chamber about 1.56 m. RENDER: use it for R < 3.0 (F0).
- `ART-HAB-door_blocked.json` is written by every room build; a `changes` list records what changed, and the
  build prints `door_blocked.json CHANGED` so I post it to SIM.
- Narrowed: habitat S 160° → 360° free (beds 0.12 m in, smaller table), kitchen S 251° → 336°, lounge S 332° → 341°.
  `Plan.lane_r()` gives layouts the radius that keeps every lane clear.
- Build: 96 room files 0 flags; links 30 ok; Godot check 165 scripts / 0 failed; export pck 79.5 MB.

## 2026-09-25 — critic round 12 fixes + RENDER paths request (door lanes, shell materials)

- Round 12:
  1. Airlock cutaway proof: `art/interiors/airlock_{m,l}_cut_side{,_b}.png` (red ring = 1.40 m).
  2. Water recycler: filter columns inside Rw − 0.62, clear of every door housing. Drum radius
     `min(old, Rw − 0.62 − 2·cr − 0.06)`.
  3. Flat lid `doorway_flat_r*` (Frame) for podium, drum and setback rooms.
  4. `upper_band.glb` strips to the band cap. Upper skin faces are cut at the segment lines. The patch over the
     housing starts at 2.24 m.
  5. Pressure lights: 8 cm lamps; the dark plate is `PressurePlateTop`. Picture: `airlock_m_pressure_lights.png`.
  6. Pad: angled deflector (rail, stripe, scorch), hose reel, fuel stripes, lit kiosk, mast lamp, walkway lanes,
     six tie-downs; 6 326 tris. Pictures: `pad31_*`, `pad31_close_*`.
- Airlock files follow content: `airlock_m` (= `airlock.glb`, R 3.4) and `airlock_l` (R 4.0).
- Door lanes: the check is `door_blocked` (a 0.9 m lane to the aisle ring). M ring 1.00 m. M/L/XL rooms clear at
  every angle: 59 of 71. The other types are listed for SIM. Kitchen, lounge, medical and habitat M layouts
  changed. Two footprint bugs fixed (medical supply island, scanner).
- Shell materials: the wall shell folds into Hull (max 7 → 4). Base, Roof and L parts use the palette (≤ 6 per
  group, build check). Link parts use the palette too.
- Build: 95 room files, 0 flags; 30 link files, 0 flags; exteriors 60, 0 flagged. Godot: import done, check
  163 scripts / 0 failed, export `build/web_art_hab` (pck 79.1 MB).

## 2026-09-25 — v3.1 ROLL-OUT (critic round 10, ART-B round 11)

| item | result |
|---|---|
| door kit | 10 radius variants `doorway_r250 .. r925.glb` (+ `doorway.glb` = r550): the room face follows the wall, rounded top corners, 8 cm chamfers, a curved hood; `StatusGreen` (#5EE07A) status strip and reveal lights; kick plates and a chevron strip at the meeting edge. 1 482 tris each. The open-leaf containment check stays. |
| band end | `wall_patch_plain.glb` (no band) and `band_cap.glb`: the wall band ends 5 cm before the housing (asin(1.77/Rw)) with a cap. |
| upper wall | `wall_patch_upper.glb` closes the upper wall of podium / drum / setback rooms beside and over a door housing (`Upper_<seg>` objects hide per segment). |
| decals | every room file split: 8 898 `Decal_<seg>_<source>` objects, 1 630 `Upper_<seg>`, a `NameSign` each. Level parts that were only wall decoration (L3/L4 of 11 files) exist now only as decals (build check adjusted). |
| airlock | sizes: `airlock.glb` R 2.8 (2 riders, chamber 1.56 m), `airlock_m.glb` R 3.4 (2 riders, chamber 2.4 m), `airlock_l.glb` R 4.0 (4 riders, chamber 3.6 m). Amber `Beacon` object, three `PressureLight_*` over the inner door, faired chamber block (block top meets the dome), a flat porch grate with a striped lip and two bollards. Cut at 1.40 m with solid caps in the cutaway (the upper parts are in Roof / `…Top`). |
| pad | `landing_pad.glb`: deck r 9.0, apron to r 11.3 (footprint 11.5, asked of SIM), `Anchor_Ship` (yaw 180) and `Anchor_Fuel`, ramp lanes +X ±25° and +Y ±40° clear from 6.5 m, kiosk at −X r 10.55, blast deflector 228–300°, fuel station at 318° with a floor fuel line, two light masts, 20 amber edge lights, one purple ring. 3 522 tris. |

Build: 96 room files, 0 flags; Interior at most 8 surfaces; largest file 22 materials; exteriors 60 files, 0
flagged; link parts 0 flags. Godot import, check (156 scripts, 0 failed), export `build/web_art_hab` (79.9 MB).

Requests: SIM (airlock radii M 3.4 / L 4.0, pad radius 11.5), ART-B (pad answer), RENDER (R1–R6).

Known weaknesses: about 90 decal objects per room (RENDER must merge them); door variants are nearest-radius
(up to about 6 cm of curve mismatch on the smallest rooms); airlock M and L and the new pad radius wait for SIM's
content; four amber edge lights stand in the ramp lanes (0.20 m, beyond the ramp feet); the upper wall patch is
plain (no band). Not tested: anything in the game.

## 2026-09-25 — v3.1 PILOT (V3_1_DESIGN §3 doors and decals, §5.1 airlock)

| item | result | files |
|---|---|---|
| door kit | `doorway.glb` rebuilt: a solid frame housing (x −0.56..0.04, y ±1.72, top 2.56) with the pockets inside it, full-height 6 cm opaque leaves with a window strip and a seal line, a threshold plate, a header status light (`Status`, Glow), solid caps at 1.40 m; an open leaf stays inside the housing (build check); the collar starts on the housing face (no gap). 1 048 tris. The J2 hood rule is gone. | `interior_links.py` |
| decals | every 3.1 room build splits outer-wall decal faces into `Decal_<seg>_<source>` objects (segment = the wall segment of the face centre), flat-walled shells also get `Upper_<seg>`; a movable `NameSign` plate. habitat M: 56 decal objects (L2 / L4 bands). | `interior_kit.split_decals`, `rooms_kit.build_file` |
| airlock | new layout: suit room → inner door kit → pressure chamber (grating, vents, pumps, gauge panel, beacon strips, window) → outer door kit (recessed, hazard stripes) → porch (ramp, dust mat, floodlight). Exterior: dome cut over the front, a chamber block with pumps and a beacon. Anchors Chamber 2, Suit 2, Porch 2, Stand 2. 6 740 tris; Interior 6 surfaces. | `interior_airlock.py`, `rooms_links.py` |
| renders | door kit closed / half / open, cutaway, roof on, inside; habitat M with doorways (decals hidden); airlock closed / half / open, cutaway and roof on, with links, anchors, exterior, night | `art/interiors/door31_*`, `habitat_m*`, `airlock*` |

Build: habitat M and airlock 0 flags (budget, Interior ≤ 8 surfaces, stand points, radius with the porch
exempt). The other rooms are not rebuilt yet (after the pilot critic).

Known weaknesses: the airlock is one size (content has one); the porch stands outside the footprint (SIM /
RENDER must keep the ground in front clear); the airlock chamber is 1.6 m long for 2 people; decal objects add
draw calls unless RENDER merges them; the dome meets the chamber block with a small step on the sides.
Not tested: anything in the game (RENDER integration).

## 2026-09-25 — round 8: lounge seating lighter

Lounge island rugs `RugLight` (#B4BFCC) and sofas `CushionLight` (#7D93B4) instead of navy `Cushion`; both merge
into `Palette` (Interior surfaces unchanged: S 6, M/L/XL 7). Build 94 rooms, 0 flags; lounge images re-rendered.

## 2026-09-25 — draw-call budget (RENDER request)

- `Interior` and every `Tall_*`: at most 8 materials, a build check (`rooms_kit.MAX_SURFACES`). Plain materials merge
  into `Palette` / `PaletteMetal` (the colour goes into COLOR_0 with the AO); named and emissive materials stay.
  Wall-side items in `Wall_*` also use the palette. Interior surfaces over the 94 files: max 14 → 8, total 954 → 520.
  Largest file: 27 → 22 materials. Before/after renders look the same (checked `cantina_l`, `research_lab_m`).
- New check: a standing worker is at least 0.12 m from the counter he faces; fixed `polymer_plant_xl` (the second
  unit stood on two console stand points).
- Build: 94 rooms, 0 flags.

## 2026-09-25 — ROUND 7 polish (critic `docs/critic/round_7.md`, fixes 2–8)

| item | change |
|---|---|
| research lab | sample-rack wall sections, screen-wall sections, specimen cases (glass case, glowing sample), server racks; S/M now carry 2–3 of these on the floor |
| assembler | partitions: two glass panes and a cyan border on all four edges; exterior roof: clear glass skylights over a lit strip on a dark roof (no more white panels) |
| crater / rock | crater: light sand rim edge, dark bowl, ejecta fading to light tan; rock: new emissive `Ember` (hot orange) in the cracks |
| night | accent lights 80 W (×2) + a coloured floor-spill disk light each; ceiling cut-off 3.2 m and floor pool 0.5 R (wall ring ~25 % darker); values in the RENDER request J4 |
| cantina / lounge | booth floor band removed; each booth stands on its own wood inlay with a neon edge; game tables, planters and lamps fill M–XL; lounge S/M get the armchair pair (reading corner) |
| industry XL / atmo XL | three marked stock zones (dashed border, pallets, crates, drums, ore bins ...) on the outer ring; atmo XL two more coolers |
| bio-lab | bench equipment 1.3× larger; glove boxes and sample fridges on the floor |
| habitat M | three bays in a row (20/90/160°) and one apart (250°); the open wedge holds the reading corner; screens only between close bays |

Build: 94 rooms, 0 flags (budget, materials, anchors, stand points, trays, AO).

## 2026-09-25 — ROUND 4 fixes (critic `docs/critic/round_4.md`) and round-6 items 1–2

| item | change | files |
|---|---|---|
| junction (FAIL 0.647) | own door kit: open spans, `junction_post.glb`, `junction_sill.glb`, patches; no pockets, no leaves; rule `junction_plan()`; tested 3/4/5/6 links at 28° and evenly spread | `interior_links.py`, `interior_render.py` |
| industry L/XL | the main machine scales with the size (plan ×1.05/1.32/1.62, height up to ×1.12, clamped to the room shell); a second unit of the same process on L/XL where it fits, joined by a conveyor or a pipe bridge; covered floor trenches (pipes) to the wall; feed risers; type-specific stock (ore bins, ingots, drums, glass sheets, reels, crates) instead of the grey cube | `interior_fam_ind.py` |
| life support | atmo: a central fractionation column to the ceiling with a platform, ladder, compressors piped to it, coolers; water: tanks grouped on a plinth with thick manifolds, UV skid and pumps; oxygen: two stack rows on a plinth, an O2 manifold, a storage-tank plinth; floor trenches | `interior_fam_ind.py` |
| fungus farm | the game's `crop_mushroom` is the shelf rack, so the room gives a bed, corner posts with violet strips and a violet canopy above the crop (nothing between 0.56 and 2.02 m over the bed); lighter floor; mushroom wall shelves; incubators | `interior_fam_farm.py` |
| algae | rows of clear tubes (Glass shell, glowing culture) on manifold skids | `interior_fam_farm.py` |
| cantina | neon bar front fins, a back bar (Tall) with lit bottles, table lamps with `Anchor_Lamp`, high-backed booths on a dark neon-rimmed floor band, standing high tables | `interior_families.py` |
| hazard props | crater: no metal, no dashed ring, broad soft ejecta to 1.5–2.0 r; meteor rock: chunks with the glow only in the cracks; research assembler: clean-room exterior + beauty renders | `ext_hazards.py`, `rooms_science.py` |
| doors | header slab removed; above 1.40 m everything sits inside an entry hood (the corridor profile carried in to the pocket plane; build check); pockets stop at 1.40 m; L/XL walking ring 1.10 m → 1.2 m door clearance; S/M blocked angles in `docs/requests/ART-HAB-door_blocked.json` (written by every build) | `interior_links.py`, `interior_kit.py`, `rooms_build.py` |
| night | `Anchor_Accent_<i>` per room + family colour table; floor pool 0.6 R | `interior_rooms.py`, `interior_render.py` |
| habitat | frosted curtain panels on a floor rail (no legs); M bays at 12/98/178/262°; three bed shapes (pad, slatted on legs, wingback with drawers); a reading corner in M/L; rugs under the XL table groups | `interior_furniture.py`, `interior_rooms.py` |
| medical / bio-lab / lab | medical XL scanner + supply islands, L supply island; floor line only in L/XL; bio-lab benches carry a microscope, centrifuge, screen and an overhead service spine; research lab S/M: 2 / 4 desks, server racks | `interior_families.py`, `interior_fam_sci.py`, `interior_furniture.py` |
| stand points (round 6) | build check: every `Anchor_Bed/Seat/Work` has 0.35 m free floor from any footprint except its own item (and, for a seat, its table); fixed habitat S chairs, lounge sofa L-corners, medical visitor chairs | `interior_kit.py` (`check_standpoints`) |
| in-game evidence (round 6) | request to RENDER for junction and S-room doorway shots, with a way to make them | `docs/requests/ART-HAB-to-RENDER.md` J6 |

Open questions to SIM (`docs/requests/ART-HAB-to-SIM.md`): junction spacing, trays near the wall, blocked door
angles.

Result: `rooms_build` 94 built, 0 flags (new checks: stand points, door envelope in `interior_links.py`);
`interior_links` doorway 1 024 tris, junction_post 144, junction_sill 10; hazards meteor_rock 550, crater 650;
Godot import done, check 143 scripts 0 failed, export `build/web_art_hab` (pck 61.8 MB). Renders: 172 files in
`art/interiors/` (all beauty images, 18 night, 9 doorway sets, junction_links_*, anchors, exteriors).

Known weaknesses (round 4):
1. At a junction with links 28° apart the corridor tubes overlap each other near the hub (SIM question 1).
2. S and M rooms do not give 1.2 m at every door angle; the angles are listed, not solved. Worst: habitat S,
   oxygen S (0° free), fungus farm (content trays), water recycler S.
3. When a door is open the upper leaves stand outside the hood: RENDER must hide `DoorLTop` / `DoorRTop` while
   open. Not tested in the game.
4. The entry hood rises above the water recycler's setback deck.
5. Mine, refinery and glassworks L/XL found no room for the second unit; only the scaled main machine.
6. Medical L gets no scanner (the 1.1 m ring leaves too little floor); XL has one.
7. The L/XL 1.1 m walking ring makes those floors look emptier near the wall.
8. Night renders are a Blender target; accent colours and watts need RENDER's tuning.
9. Not tested in the game: the junction kit, the hood, accent lights (RENDER integration).

## 2026-09-24 — PRODUCTION (round 2): every room type and size, doorway rework, hazards

### Result

- `rooms_build: 94 built, 0 with flags []` (all room types × S/M/L/XL, airlock, junction, research_assembler).
  The build fails on: budget (10k / 15k / 22k / 30k), more than 14 materials in an object, more than 26 in a
  file, anchor counts ≠ `content/buildings.json` `furniture`, a wall item outside its segment span, tray
  contract (greenhouse / fungus), AO missing, GLB re-import mismatch.
- Exteriors: 60 files rebuilt with `Anchor_Service`; `ext_verify.py` 60 files, 0 flags.
- New: `meteor_turret` (1 008 tris), `meteor_rock` (154), `crater` (483), `fragments` (438),
  `research_assembler_{s,m,l,xl}`; thumbnails `assets/thumbs/meteor_turret.png`, `research_assembler*.png`.
- Doorway reworked: `doorway.glb` 1 048 tris / 12 materials; `wall_patch.glb` 58 tris; corridor 94; rib 198.
- Godot: `import` done, `check` 141 scripts 0 failed, web export `build/web_art_hab` (pck 61.4 MB).
- RENDER contract rewritten: `docs/requests/ART-HAB-to-RENDER.md` (production section).

### Round-2 critic fixes

| item | what was done |
|---|---|
| 1 bays of 2 | habitat M/L/XL: beds in bays of 2 with a shared bedside; privacy screens (Fabric) on the bay bisectors; S = 4 cabin beds round a table; XL adds a central back-to-back pod |
| 2 variety | `dress(i)`: 3 bedding styles, pillow count, blanket colour (Fabric / Cushion / Accent), bedside items (books, plant, cup, tablet) |
| 3 less hotel | wall segments carry a rib stub every 4th segment, two Metal pipes, clamps, vents; wood only in small inserts |
| 4 cabinet ring | `wall_items(pattern, open_every)` leaves open segments; shelves, vents, panels, posters and taps mix with cabinets |
| 5 doorway | headboards and tall items near the wall are separate `Tall_<nn>` objects (floor origin) the game can hide; one jamb profile with a pocket housing; header with chamfer, Frame trim and `Accent` stripe; `wall_patch` carries the room band (`Accent`, tinted by the game) so the band reaches the door |
| 6 layout languages | see below |
| 7 night image | `interior_render.night_lighting()`: moon, ceiling points at `Anchor_Light_*`, warm points at `Anchor_Lamp_*`, a warm disk floor pool, ray tracing; 13 `*_night.png` |
| materials | ≤ 14 per object, ≤ 26 per file, enforced by the build |
| anchors | = SIM table for every size, enforced by the build |

### Layout language per family

| family | files | layout |
|---|---|---|
| habitat | `interior_rooms.py` | bays of 2 round the ring, screens, central table / pod |
| lounge | `interior_families.py` | media unit on one wall, sofa islands, coffee tables, reading lamps |
| cantina | same | bar counter on a chord with stools, bistro grid, neon sign (Tall) |
| medical | same | row of med beds with headwalls and curtains (Tall), scanner arch, nurse desk |
| bio_lab | same | parallel lab bench rows, fume hood (Tall), glow tank |
| kitchen | same | cook line on a chord with hoods, prep island, mess tables |
| greenhouse | `interior_fam_farm.py` | trays at the content tray offsets, grow-light bars, irrigation lines |
| fungus_farm | same | mushroom racks at the tray offsets |
| algae_bioreactor | same | grid of glow tubes |
| storehouse, cold_storage | same | rack aisles (pallets / freezers) |
| mine, refinery, polymer, workshop, glassworks, electronics_fab, fabricator | `interior_fam_ind.py` | one central machine per type, fitted inside the room (compact variant on S/M), a control line of consoles / benches / sit desks, hazard pad |
| oxygen_plant, water_recycler, atmo_processor | same | process plant: tanks, pumps, pipe runs |
| research_lab | `interior_fam_sci.py` | holo table centre, desk pods (staffed and unstaffed), dividers |
| research_assembler | same | line: water tank → conveyor → robot arm cell → stacker; pack racks |
| airlock | same | grate floor, bench, console, 4 suit racks (Tall), lockers |
| junction | same | floor medallion, direction arrows, info post |

### Counts (from `tools/blender/build_report.json`)

| file | tris / budget | file mats | anchors | Tall |
|---|---|---|---|---|
| habitat_s | 9992 / 10000 | 24 | Bed 4 Seat 2 Stand 2 Aisle 8 Light 2 Lamp 7 | 0 |
| habitat_m | 14682 / 15000 | 24 | Bed 8 Seat 4 Stand 2 Aisle 12 Light 4 Lamp 8 | 12 |
| habitat_l | 19568 / 22000 | 25 | Bed 14 Seat 6 Stand 3 Aisle 16 Light 5 Lamp 11 | 21 |
| habitat_xl | 25528 / 30000 | 25 | Bed 22 Seat 8 Stand 4 Aisle 21 Light 6 Lamp 15 | 27 |
| greenhouse_s/m/l/xl | 7370 / 8432 / 9986 / 10905 | 26 | Work 2/4/8/12, Stand 1/2/2/3 | 0 |
| kitchen_s/m/l/xl | 8256 / 10682 / 14384 / 17112 | 24–25 | Seat 4/6/10/16, Work 1/1/2/3, Stand 1/2/2/3 | 0 |
| storehouse_s/m/l/xl | 7750 / 10540 / 14532 / 18494 | 21–23 | Stand 1/2/3/4 | 0 |
| oxygen_plant_s/m/l/xl | 7526 / 8572 / 9378 / 11602 | 24 | Stand 1/2/2/3 | 0 |
| research_lab_s/m/l/xl | 8792 / 11136 / 14299 / 17491 | 24–25 | Work 1/2/3/4, Stand 1/2/2/3, Lamp 1/2/7/9 | 0 |
| mine_s/m/l/xl | 7996 / 8568 / 9686 / 11924 | 22–23 | Work 1/2/3/4, Stand 1/2/2/3 | 0 |
| refinery_s/m/l/xl | 7982 / 8166 / 9968 / 12238 | 21–22 | Work 1/1/2/3, Stand 1/2/2/3 | 0 |
| polymer_plant_s/m/l/xl | 7926 / 8766 / 10774 / 12872 | 21–23 | Work 1/1/2/3, Stand 1/2/2/3 | 0 |
| workshop_s/m/l/xl | 7630 / 8008 / 9526 / 11868 | 21–22 | Work 1/1/2/3, Stand 1/2/2/3 | 0 |
| glassworks_s/m/l/xl | 7862 / 8248 / 9286 / 11986 | 22–23 | Work 1/1/2/3, Stand 1/2/2/3 | 0 |
| electronics_fab_s/m/l/xl | 8048 / 8202 / 10890 / 13076 | 22–23 | Work 1/1/2/3, Stand 1/2/2/3, Lamp 1/1/2/3 | 0 |
| fabricator_s/m/l/xl | 7940 / 8654 / 10408 / 12178 | 22–23 | Work 1/1/2/3, Stand 1/2/2/3 | 0 |
| medical_s/m/l/xl | 7768 / 8912 / 11302 / 13911 | 22–23 | Bed 1/2/4/6, Seat 1/1/2/2, Stand 1/2/2/3, Lamp 1 | 1/3/7/11 |
| lounge_s/m/l/xl | 9600 / 10688 / 13968 / 17521 | 26 | Seat 3/6/10/16, Stand 2/3/4/6, Lamp 6/6/9/12 | 0 |
| cantina_s/m/l/xl | 8968 / 11662 / 14606 / 18131 | 25 | Seat 4/8/14/22, Stand 2/3/4/6, Lamp 3/3/5/6 | 1 |
| bio_lab_s/m/l/xl | 7080 / 8486 / 9791 / 12184 | 24–25 | Work 1/1/2/3, Stand 1/2/2/3 | 1 |
| fungus_farm_s/m/l/xl | 7178 / 8654 / 10148 / 11404 | 23–24 | Work 2/4/6/8, Stand 1/2/2/3 | 0 |
| algae_bioreactor_s/m/l/xl | 7890 / 8368 / 11018 / 13870 | 22–23 | Stand 1/2/2/3 | 0 |
| water_recycler_s/m/l/xl | 7622 / 8848 / 9430 / 10528 | 22–23 | Stand 1/2/2/3 | 0 |
| atmo_processor_s/m/l/xl | 7106 / 8210 / 10216 / 11854 | 19–21 | Stand 1/2/2/3 | 0 |
| cold_storage_s/m/l/xl | 6284 / 6998 / 8622 / 10380 | 22–23 | Stand 1/2/3/4 | 0 |
| research_assembler_s/m/l/xl | 8588 / 11592 / 12404 / 15650 | 23–25 | Stand 1/2/2/3 | 0 |
| airlock | 5810 / 15000 | 14 | Stand 2 | 4 |
| junction | 4938 / 15000 | 10 | Stand 1 | 0 |

Every room also has `Anchor_Light_*` (S 2, M 4, L 5, XL 6; airlock 3, junction 2), `Anchor_Aisle_*` and
`Anchor_Beacon`. Per-object materials: at most 14 (enforced).

### Commands (project root)

```
"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python tools/blender/rooms_build.py
"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python tools/blender/interior_links.py
"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python tools/blender/ext_hazards.py -- --thumbs
"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python tools/blender/interior_render.py -- --file habitat_m --only beauty,night,doorways,roof,anchors,close,detail
node tools/godot.mjs import && node tools/godot.mjs check
```

### Renders (`art/interiors/`, 147 files, looked at)

- Beauty cutaway `<id>_<size>.png` for all 23 sized types, `airlock.png`, `junction.png` (1400×960).
- Night (13): habitat_m, habitat_xl, lounge_l, cantina_m, medical_l, kitchen_m, greenhouse_m, research_lab_l,
  research_assembler_m, mine_l, storehouse_m, oxygen_plant_m, airlock.
- Doorways (+ `_roof`): habitat_m, habitat_l, kitchen_m, cantina_s, lounge_l, mine_xl, medical_m, junction, airlock.
- Anchors: habitat_s/m/l/xl, medical_l, kitchen_l, cantina_l, lounge_xl, research_lab_m, greenhouse_m,
  electronics_fab_l, workshop_m.
- Close: `doorway_close.png`, `doorway_close_roof.png`, `doorway_close_inside.png`, `habitat_m_detail.png`.
- In game (`build/web_art_hab`): `ingame_habitat_day.png`, `ingame_habitat_night.png`, `ingame_kitchen_day.png`,
  `ingame_greenhouse_day.png`, `ingame_refinery_day.png`, `ingame_storehouse_day.png`, `ingame_colony_day.png`.

### Known weaknesses (honest)

1. **No doorway in the game yet.** RENDER must group `Wall_*` / `Tall_*` / door parts, hide segments, place
   doorways and patches, and tint `Accent`. In my export the corridors meet the full wall. All doorway
   pictures are Blender compositions.
2. **Junction** with 4–6 links: neighbouring pocket housings overlap.
3. **S rooms**: the pocket housing and open leaves show a few cm outside the dome skin.
4. **Door clearance** to free-standing furniture is 0.83–0.98 m, not 1.2 m. Hiding `Tall_*` near a door helps;
   low furniture stays.
5. Greenhouse / fungus trays are at content-fixed offsets; some sit in the walking ring near the wall.
   Fungus crops overlap the racks (as in v2).
6. Some XL rooms (industry, life support, storage) are spacious; the machine does not grow with the room.
7. Research assembler glass reads grey, not clear.
8. The Blender night image is a target, not the game. Watts do not map one-to-one.
9. The crater scar (rays, ejecta) reaches 2.4× the rim radius; SIM / RENDER must agree on the scale.
10. `Anchor_Muzzle` is the rest position; RENDER rotates it with the turret.
11. Not tested: performance with 32 wall objects per room; RENDER integration; doorways in Godot.

## 2026-09-24 — v3 pilot (V3_DESIGN §0.1): wall segments, doorway, habitat M interior

### What landed

| file | content | triangles | materials |
|---|---|---:|---|
| `assets/models/habitat_m.glb` (+ `habitat.glb`) | Base, Roof, Interior, L2..L5, `Wall_00`..`Wall_31`; anchors Bed 8, Seat 4, Stand 2, Aisle 12, Light 4, Beacon 1 | 13 844 / 15 000 | 25 in the file; per object: Interior 12, each Wall_k at most 11 |
| `assets/models/doorway.glb` | Frame, FrameTop, DoorL, DoorLTop, DoorR, DoorRTop, Lights, Sign; Anchor_Room, Anchor_Corridor | 684 | |
| `assets/models/wall_patch.glb` | Base (straight 1 m wall slice, door-surround version) | 36 | |
| `assets/models/corridor.glb` | Base, Roof (1 m unit, scaled on X; end collars removed; floor light line, handrails) | 94 | |
| `assets/models/corridor_rib.glb` | Base, Roof (structural rib, not scaled) | 198 | |
| `assets/thumbs/habitat_m.png` (+ `habitat.png`) | new thumbnail (no +X door) | | |
| `art/interiors/*.png` | renders, see below; `.gdignore` keeps the folder out of the Godot export | | |

habitat_m per object: Base 996 · Roof 1 232 · Interior 4 892 · Wall_00..31 5 790 (wall + wall-side items) ·
L2 172 · L3 174 · L4 284 · L5 304. AO (COLOR_0) on every mesh, re-import check ok (AO 0.18..1.00).

New materials in `build_assets.MATERIALS`: `LightStrip` (#EAF6FF, emissive 2.5), `Screen` (#123C4C, emissive
#2FB8D8 × 0.45), `Wood` (#B08560), `Cushion` (#3C4A5E), `Floor` (#D9D4CB), `FloorDark` (#6B6F76).

### How it is built

- `tools/blender/interior_kit.py`: the 32 wall segments (one facet each, a panel joint, cove and skirting
  light strips), the Floor/FloorDark panel floor, furniture built to the NPC numbers (bed: mattress top
  0.55, centre line 0.55 behind the stand point, head to local +Y; chair: seat top 0.46, 0.30 behind),
  wall-side items built INTO their segment (`wall_slot`), anchor checks, `check_furniture` (counts =
  `content/buildings.json` `furniture` block, SIM's final table).
- `tools/blender/interior_habitat.py`: v3 habitat. Pilot = size M only; S/L/XL raise NotImplementedError
  and `rooms_build.py` falls back to the v2 builder for them.
- `tools/blender/rooms_build.py`: runs v3 builders when a type has one (`--v2` forces the old path);
  v3 budgets 10k / 15k / 22k / 30k; checks 32 segments, segment spans, anchors, furniture counts, at most
  14 materials per object. It no longer builds `corridor` (unless `--v2`).
- `tools/blender/interior_links.py`: doorway, wall patch, corridor, corridor rib → `interior_links_report.json`.
- `tools/blender/interior_render.py`: cutaway renders of the exported files; also the reference
  implementation of the doorway rule for RENDER (`link_plan`, `place_link`).

Commands (project root):
```
"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python tools/blender/rooms_build.py -- --only habitat --sizes m
"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python tools/blender/interior_links.py
"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python tools/blender/interior_render.py -- --file habitat_m [--links 38,197]
node tools/godot.mjs import
```

### Design decisions (for the CRITIC and RENDER)

- **Wall-side items live in the wall segments.** A doorway can be at any angle. Everything within
  0.42 m of the wall (wardrobes, low cabinets, shelves, desks with screens, planters, the water unit) is
  part of `Wall_k`, so it disappears with the segment. Free-standing furniture keeps a 0.65 m walking ring
  clear, so a doorway always opens onto floor.
- **The 32-segment gap.** With 11.25° segments the hidden span can be up to one segment wider than the
  2.2 m frame on each side (1.6 m at XL). No single doorway model can cover that for every radius, so the
  game fills the rest with `wall_patch.glb` pieces (scaled on one axis). Rule and numbers:
  `docs/requests/ART-HAB-to-RENDER.md` §3.
- **Cut at WALL_TOP.** Every doorway object is split at 1.40 m, so the cutaway shows a clean ring with
  the lower door frame, the leaves and the green status lights (jamb tops glow from above).
- **Collar.** The corridor is 2.36 m wide outside, wider than the 2.2 m frame, so the doorway has a
  U-collar (2.52 m wide, top 2.46) that caps the corridor tube. The frame itself is 2.2 m as specified.
- **Anchor z** is the real floor height (0.14); RENDER must not add FLOOR_Z again (V3 §6 wording says the
  view adds it; changed so that upper-deck anchors in L/XL work).
- **No +X door on habitat M** (V3 §7.2). `Anchor_Door` is gone from this file.
- Habitat M layout: 8 beds radial, heads at the wall, each with a bedside unit and a warm lamp;
  blankets alternate terracotta (`Fabric`) and navy (`Cushion`); round wood table, 4 shell chairs, navy rug
  with the housing accent ring; behind each bed a wardrobe and a low cabinet with a lamp / plant / books;
  in the gaps desks with screens, shelves, planters, wall screens and the water unit.

### Renders (`art/interiors/`) — looked at, one by one

| file | what |
|---|---|
| `habitat_m.png` | cutaway, 0 corridors, day |
| `habitat_m_night.png` | cutaway, night (moon + the 4 anchor lights as point lights) |
| `habitat_m_doorways.png` | cutaway, corridors at 38° and 197°: segments hidden, patches, doorways, corridor stubs with ribs |
| `habitat_m_doorways_roof.png` | the same with the roof on |
| `habitat_m_anchors.png` | stand-in figures on every bed / seat / stand anchor, discs on the aisle points |
| `habitat_m_detail.png` | close look at a bed, bedside unit and the wall items |
| `doorway_close.png`, `doorway_close_roof.png` | one doorway, cutaway with the leaves open; roof on |
| `ingame_habitat_m_day.png`, `ingame_habitat_m_night.png` | the real game (my export `build/web_art_hab`, demo colony, `select habitat`) |

Fixes made after looking: wall segments cut from 6.9k to 5.8k triangles (one facet per segment); planter
leaves left their segment (check caught it); 16 identical wardrobes → wardrobe + low cabinet per bed; a
1 cm sliver of ground showed between the faceted wall and the foundation (added a skirt); stand-in figures
rendered black (AO multiply); `Screen` blew out to solid cyan in the game at night (emission 0.9 → 0.45);
walking ring 0.55 → 0.65 m and headboards 1.08 → 0.96 m because a doorway can open onto a headboard;
stands 4 → 2 to match SIM's final table.

### Known weaknesses (honest)

1. **Doorways are not in the game yet.** RENDER must hide segments and place doorways/patches
   (request written). The doorway pictures are Blender compositions that follow the same rule. In the game
   today a room shows its full wall and a corridor ends open against it (the old stretched end collars
   are removed).
2. **Night interiors are dark in the game** until RENDER turns `Anchor_Light_*` into lights.
3. **Materials:** the §7.1 limit "≤ 14 materials" is met per object (Interior 12, Wall_k ≤ 11), not per
   file (25). The v2 exterior and L2..L5 parts alone use about 14 names (Trim, L3Band, L4Band, L5Gold,
   Neon, Light, Window, …), so a per-file limit of 14 cannot hold with the v2 exterior kept.
4. **Draw calls:** 32 wall objects with up to 11 materials each. Cheap only if RENDER merges the visible
   segments per room (proposed). Not measured.
5. Open door leaves slide beyond the 2.2 m frame into the wall. On rooms with R ≤ 4 m the leaf edge shows
   up to about 7 cm outside the outer wall face; more on the junction and airlock (small radius). Hidden on
   M and larger. The header can poke about 5 cm through the dome skin on S domes.
6. The wall is a 32-gon; close up the facets and a small shading step at each segment edge are visible.
7. The layout is radial like v2 (natural for a round room). Beds differ only by blanket colour.
   The wall ring of items is dense and reads as a band of cabinets from far away.
8. At some link angles the doorway opens 0.8 m from the back of a headboard (walkable, visually tight).
9. `wall_patch` uses a Trim band, so the category band stops next to a door (on purpose; may read as a
   patch).
10. Blender lighting is an approximation of the game (EEVEE, filmic, point lights at the light anchors).
11. Not tested: RENDER integration, performance, the doorway inside Godot (only in Blender), other room
    types (still v2), sizes S/L/XL of the habitat (still v2).

### Next (after the pilot critique)

Every room type and size with the v3 kit (anchors per SIM's table), junction and airlock interiors,
corridor detail review, `research_assembler` S–XL, `meteor_turret` (`Turret` pivot, `Anchor_Service`),
`meteor_rock`, `crater`, `fragments`, `Anchor_Service` on exterior machines, thumbnails, all renders.
