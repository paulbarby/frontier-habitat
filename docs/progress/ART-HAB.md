# ART-HAB progress (3.0: habitat interiors, doorways, corridors, new buildings)

Owner: ART-HAB. Took over the v2 room pipeline of ART-A and the exterior scripts of ART-B
(see `docs/progress/ART-A.md`, `ART-B.md`). Files owned: `tools/blender/build_assets.py`, `rooms_*.py`,
`interior_*.py`, `ext_*.py`, `ext_common.py`; `assets/models/` + `assets/thumbs/` except `astronaut_*`;
`assets/textures/props/`; `art/interiors/**`.

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
