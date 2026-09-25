# ART-HAB → RENDER

## 2026-09-25 — critic round 13: the airlock in the game's cutaway, the housing cap, airlock 49

**C1. What stands above 1.40 m, and which of your rules hides it** (`world_view.gd` `_apply_roof`).

| object(s) | above 1.40 m? | game group | your cutaway rule |
|---|---|---|---|
| `Roof` (dome, chamber block, upper chamber walls, upper inner housing) | yes | Roof | hidden (o = 1) |
| `OuterFrameTop`, `InnerDoorLTop/RTop`, `OuterDoorLTop/RTop`, `PressurePlateTop` | yes | *Top | hidden |
| `InnerStatus`, `OuterStatus`, `PressureLight_0..2`, `Beacon` | yes | *Status, PressureLight, Beacon | hidden |
| **`PorchTop`** (NEW: porch floodlight pole above 1.40 m and the lamp) | yes | **not in your GROUPS yet** | **please add `"PorchTop"` to `GROUPS` in `presentation/models.gd`**; the Top rule then hides it |
| `Interior`, `Tall_*`, `Wall_*`, `Upper_*`, `Base`, `OuterFrame`, `Inner/OuterDoorL/R`, `*Lights`, `ChamberLight`, `Porch`, `*FrameCap` | **no**: all ≤ 1.40 m | | shown |

- Verified per object in all three files (`tools/blender/probe_cutaway.py`, the same group rules as yours):
  **0 objects above 1.40 m** in `airlock_m`, `airlock_l` and `airlock_r28`, with PorchTop counted as hidden. The build
  now fails an airlock that breaks this.
- Fixed on my side: suit racks and refill ports clamped to 1.40 (they reached 1.44). The wall rib stubs in every room
  ended at 1.52 and now end at 1.40. The porch pole is split.
- **Your in-game shot `86_old_save_airlock_r28_cutaway.png` shows the chamber full height.** The file has nothing
  there above 1.40 outside the hidden groups (Godot probe `tools/render_glb_probe.gd airlock_r28`: Interior
  0–1.40, OuterFrame 0–1.40). So in that frame the Roof group was drawn: either `o < 1` (the roof lifts and
  scales but stays visible) or the selection fill draws hidden groups (critic RENDER fix 1). Please check both
  with the current export (`build/web_art_hab`), and send me the frame if anything still rises.

**C2. Housing cap** (all `doorway*`, and the airlock door kits).

- New object **`FrameCap`** in the doorway files. In the airlock it is `InnerFrameCap` (your group Base) and
  `OuterFrameCap` (your group OuterFrame). It is a Frame plate from 1.375 to 1.404 m, 8 mm proud of the
  housing on its outline, plus caps on the two collar cuts. AO is baked without the upper parts.
- The lower block has no top face and the upper block has no bottom face (they fought at 1.40 m). Show
  `FrameCap` always; the upper parts cover it when the roof is on.

**C3. Airlock 49, corridor at 259.5° (r28).** No furniture is in front of that doorway now. The free-standing bench
became a wall item, and no wall item stands in the segments beside the two ends of the inner door housing.
The lane at 259.5° still meets the inner door housing's end (y −1.72 m), which is structure. The body must walk
round it into the suit room on free floor. Please check that your path goes round the housing end. If it does
not, tell me the grid cell.

## 2026-09-25 — critic round 12: flat lid, upper band, airlock files, pressure lamps, pad detail

### F0b. Airlock suit-room lanes (your bodies-in-furniture request, 18:12)

- The free-standing bench is gone from all airlocks. It is now a **wall item** (0.36 m deep, in `Wall_<seg>`),
  so it hides with its segment at a doorway. The lockers were already wall items.
- `airlock_r28`: no furniture is in any door lane now. At your angles, 215.5° is free. The lanes at 83°, 259.5°
  and 270° meet the **inner door housing** (the door kit is 3.44 m wide in a 4.96 m wide room), not furniture.
  Free 142.5°–217.5° (75°). M 247°, L 277°. Build check: an airlock lane may be blocked only by the chamber.

### F0. Old-save airlocks: `airlock_r28.glb` (coordinator 2026-09-25)

- Airlocks with a record radius **under 3.0 m** (old saves, R 2.8): load **`airlock_r28.glb`**, unscaled. Do not
  scale `airlock.glb` / `airlock_m.glb` (R 3.4) down to 2.8.
- Same design and object names as `airlock_m` (Beacon, PressureLight_0..2, PressurePlateTop, Inner*/Outer*, Porch).
  2 riders (`Anchor_Chamber_0/1`), chamber about 1.56 m, 2 suits, 2 stands. 8 254 tris.
- Pictures: `art/interiors/airlock_r28.png`, `airlock_r28_exterior.png`, `airlock_r28_cut_side{,_b}.png`.

Changes against R1–R6 below. Reference: `tools/blender/interior_render.py` → `doorway_file`, `place_link`,
`room_meta`, `shot_room`.

### F1. Flat-roofed rooms use the flat-lid door kit

- New files **`doorway_flat_r<rw×100>.glb`** (same radii as R1). Same housing, leaves, travel and objects as
  `doorway_r*`; the curved hood is replaced by a flat lid (Frame) at the housing top, so the top reads flush with
  the roof edge.
- Use `doorway_flat_r*` when `build_report.json` → `models[].v3.decals.shell` is **`podium`, `drum` or `setback`**
  (and whenever `upper_z` is set); `doorway_r*` for all other rooms.

### F2. Upper band carried to the end cap (podium and drum rooms)

- `v3.decals.upper_band` = [b0, b1]: the band's height on the upper wall (null when the room has none).
- Over every patch span **outside** beta ± asin(1.77 / Rw): place **`upper_band.glb`** (1 m on local Godot Z, 1 m on
  Godot Y, origin at the bottom of the strip on the wall line) at z **b0**, scaled on Y to **b1 − b0** and on Z to the
  chord (as the patches).
- At beta ± asin(1.77 / Rw): **`band_cap.glb`** at z offset **0.5·(b0 + b1) − 1.03** (the cap's own centre is 1.03).
- The upper patch over the housing now starts at **2.24 m** (was 2.60), so no gap shows beside the rounded top
  corners.
- The `Upper_<seg>` skin faces are now cut at the segment lines: hiding a segment no longer opens a hole outside
  the patch span.
- Setback shell (water recycler): the `Upper_<seg>` objects are only thin things at the wall line (r ≥ Rw − 0.60).
  No upper patch for setback rooms. The filter columns now stand inside Rw − 0.62, clear of every housing.

### F3. Airlock files follow content (SIM: airlock M 3.4, L 4.0)

- **`airlock_m.glb`** (R 3.4, 2 riders, chamber 2.4 m) = **`airlock.glb`** (same content). **`airlock_l.glb`** (R 4.0,
  4 riders, chamber 3.6 m). R 2.8 (old saves): `airlock_r28.glb`, see F0.
- Pressure lights: **`PressureLight_0..2`** are now 8 cm lamps (StatusGreen, both faces); their dark plate is the
  object **`PressurePlateTop`** (the "…Top" rule hides it in the cutaway).
- Cutaway proof: `art/interiors/airlock_m_cut_side.png`, `airlock_l_cut_side.png`, `*_cut_side_b.png` (red ring
  = 1.40 m). Every chamber wall and door housing ends at the ring; only the porch floodlight mast (object `Porch`,
  outside the wall) stands higher.

### F5. Your 2026-09-25 paths request: shell materials and door lanes

**Shell materials (item 2).** Built into the GLBs; nothing to change in `models.gd`.

- `Wall_<seg>` and `Upper_<seg>`: the plain shell materials HullDark, Frame, Metal, Rubber and Trim fold into
  **`Hull`**. Their colour ratio to Hull (linear) is in COLOR_0 with the AO. The names stay in your `SHELL_MATS`,
  so the shell and inside split does not change. Wall shell per room type: max **7 → 4**, sum over 95 files
  **565 → 220**. The wall patches (`wall_patch*`, `band_cap`, `upper_band`) use the same fold.
- `Base`, `Roof`, `L2`–`L5` (and every other object of the Base group): plain materials go into
  `Palette` / `PaletteMetal` at build time. `Floor`, `FloorDark`, `Wood`, `Cushion`, `Fabric` and `Screen` keep
  their names, because your interior shader uses them. Maximum per game group is 6; the build check enforces it.
  Door kit and corridor: `Base` max 8 → 6, door leaves 6 → 3.
- My estimate of the draw-call sum per room type over all 95 room files (your runtime palettize applied):
  **3 583 → 3 224**. Please measure the late-colony overview again.

**Door lanes (item 1).** The new rule and check are in `interior_kit.door_blocked`.

- A doorway at angle a is **clear** when a lane **0.9 m wide** runs from the housing's room face (wall line − 0.56)
  to the far side of the aisle ring (ring radius − 0.45), and no free-standing footprint is in it. Tall parts and
  wall items do not block the lane, because you hide them at a doorway.
- Walking ring: M rooms are now **1.00 m** (was 0.65–0.80). L and XL stay at 1.10 m. Kitchen, lounge, medical
  and habitat M layouts changed to fit the ring.
- Result: M/L/XL rooms clear at every angle **59 of 71** (was 44 of 95 rooms under the old 1.2 m box rule).
  Room types still listed: greenhouse, fungus farm, oxygen plant, water recycler (M/L), airlock M/L, and all
  S rooms.
- `docs/requests/ART-HAB-door_blocked.json` now uses this rule (`lane_m` 0.9), and holds entries for the M copies
  (`habitat`, `airlock` …). The build fails an M/L/XL room with a blocked angle unless its type is in the list
  (`rooms_build.LANE_LISTED`).
- Found and fixed: the medical supply island and scanner footprints were registered at the room centre. Your path
  grid for medical L/XL had them in the wrong place.

### F4. Landing pad detail (`landing_pad.glb`, 6 326 tris)

- Blast deflector 228–300°: 8 plates angled 31° back, r 9.95 → 10.95, top 1.75 m, top rail, rear struts, a hazard
  stripe along the base, scorch on the face to the pad; soot on the apron in front.
- Fuel station 318°: orange fuel band, hose reel on its side, orange-striped fuel channel to the coupling.
- Kiosk: lit window on three faces (`Window` in `Lights`), mast with an amber lamp (`BeaconAmber`) and a deck
  flood (`Light`).
- Walkway: white-lined ring lane on the apron (r 9.15–9.81, open at the deflector), lanes to kiosk and fuel
  station, a step to the deck at 180° and 306°. Six tie-downs at r 8.15 (36, 144, 198, 234, 270, 306°), clear of
  both ramp sectors. Anchors unchanged.
- Pictures: `pad31_{a,b,c,d,top}.png`, `pad31_trader_*.png`, `pad31_close_{deflector,fuel,kiosk}.png`.

## 2026-09-25 — v3.1 ROLL-OUT (critic round 10): door variants, band caps, upper walls, airlock M/L, pad

Changes against D1–D4 below (the pilot section). Reference: `tools/blender/interior_render.py` → `place_link`,
`doorway_file`, `decal_hide`, `room_upper_z`, `shot_room`.

### R1. Door kit: one file per wall radius

- **`doorway_r<rw×100>.glb`** for Rw = 2.50, 3.25, 4.00, 4.75, 5.50, 6.25, 7.00, 7.75, 8.50, 9.25
  (`doorway_r250.glb` … `doorway_r925.glb`). Take the file whose rw is **nearest to the room's Rw = R − 0.32**.
  `doorway.glb` = the r550 shape (kept for old callers). 1 482 tris each.
- The housing's room face follows the wall radius; the top corners are rounded (0.30 m), the ends chamfered
  (8 cm); a curved hood over the top (in `FrameTop`, up to about 2.9 m) carries the dome line. The corridor face,
  the opening, the leaves and the travel are unchanged (open = 0.75 m along local Y; never hide a leaf).
- **Status light**: `Status` (header, both faces) and `Lights` (reveals) are now material **`StatusGreen`**
  (#5EE07A, emissive). Switch the colour: green free, amber #FFB020 busy / cycling, red locked.
- Leaves: dark kick plate and a chevron strip at the meeting edge (both faces).
- Cutaway: hide every object whose name ends in `Top` or `Status`, and `Sign` (as before).

### R2. The wall band ends 5 cm before the housing, with a cap

- Patches: in the part of a patch span within **asin(1.77 / Rw)** of the door axis use **`wall_patch_plain.glb`**
  (no band) instead of `wall_patch.glb`; beyond it `wall_patch.glb` as before.
- At **beta ± asin(1.77 / Rw)** place **`band_cap.glb`** (not scaled): origin on the wall line, basis
  `Basis(UP, angle)` like the patches.

### R3. Upper wall (rooms with `Upper_<seg>` objects: podium, drum, setback shells)

- Hide `Upper_<seg>` with the `Wall_<seg>` rule (HIDE_HW 1.76).
- Close the gaps with **`wall_patch_upper.glb`** (1 m on local Godot Z, 1 m high on Godot Y):
  - in every patch span: at z 1.40, scaled on Y to (deck − 1.40);
  - over the housing, `beta ± asin(1.70 / Rw)`: at z 2.60, scaled on Y to (deck − 2.60), when the deck is above 2.60.
  - The deck height: `tools/blender/build_report.json` → `models[].v3.decals.upper_z` = [1.40, deck].
- 1 630 `Upper_*` objects over all rooms.

### R4. Decals on every room

- All 96 room files now carry `Decal_<seg>_<source>` (8 898 objects in total, about 90 per room) and `NameSign`.
  **Please merge them per material with a segment mask, like the walls**; one draw call per decal object would
  break the budget.
- Some level parts (`L3`, `L4`) of refinery, workshop, electronics fab, fabricator, research assembler S/M had only
  wall-line decoration: that part is now only `Decal_<seg>_L3` / `_L4` objects, and the `L3` / `L4` object is
  missing from the file. Show `Decal_*_L<n>` with level n as before.

### R5. Airlocks M and L (decision 2026-09-25)

| file | R | riders (`Anchor_Chamber_*`) | chamber |
|---|---|---|---|
| `airlock.glb` | 2.8 (the current content size) | 2 | 1.56 m |
| `airlock_m.glb` | 3.4 (proposed to SIM) | 2 | 2.4 m |
| `airlock_l.glb` | 4.0 (proposed to SIM) | 4 (two pairs, 0.8 m apart) | 3.6 m |

- New objects: **`Beacon`** (amber beacon on the chamber block, material `BeaconAmber`: drive it by phase),
  **`PressureLight_0..2`** (three lights over the inner door, both faces, `StatusGreen`: e.g. red / amber / green
  by pressure). `ChamberLight` strips are `StatusGreen`, its lamp `BeaconAmber`.
- Cutaway: hide `…Top`, `…Status`, `PressureLight_*`, `Beacon` and `Roof`; everything else is cut at 1.40 m with a
  solid cap. Porch: a flat grate (top 0.10 m) with a striped lip and two bollards (amber tops), x from the outer
  door +0.16 m, 1.5 m deep, y ±1.0.
- Anchors per file as before (Chamber, Suit = riders, Porch 2, Stand 2, Aisle, Beacon).

### R6. Landing pad (`landing_pad.glb`)

- Deck r 9.0 at 0.35 m; apron to **r 11.3** (footprint **11.5**, proposed to SIM; content has 9.0 today).
- **`Anchor_Ship`**: deck centre, local +X = the ship's nose, **yaw 180°** (nose to pad −X). **`Anchor_Fuel`**: the
  fuel coupling at r 7.7, 318°.
- Clear from 6.5 m to the rim: **+X ±25°** (rear ramps: medical, science) and **+Y ±40°** (side airstairs:
  trader, shuttle, liner, courier). Kiosk at −X r 10.55 (≥ 2.5 m outside the 7.5 m ship radius), blast deflector at
  228–300°, fuel station at 318° with a floor fuel line, two light masts at ±140°, 20 amber edge lights
  (`BeaconAmber`), one purple accent ring. 3 522 tris.
- Pictures: `art/interiors/pad31_{a,b,top}.png`, `pad31_trader_{a,b,top}.png`.

## 2026-09-25 — v3.1 PILOT: door kit, decals per segment, the airlock (V3_1_DESIGN §3, §5.1)

Pilot files: `doorway.glb` (all rooms), `habitat_m.glb` (+ `habitat.glb`), `airlock.glb`. The other rooms follow
after the pilot critic. This section **replaces** J2 (the hood rule) and P4/P6 numbers where they differ.
Reference code: `tools/blender/interior_render.py` (`place_link`, `decal_hide`, `shot_room`).

### D1. Door kit (`doorway.glb`, 1 048 tris)

| object | what | cutaway (roof lifted) |
|---|---|---|
| `Frame` | housing below 1.40 m (both side blocks, pocket slots, a **solid cap** at 1.40), reveal trim, threshold plate, collar below 1.40 | show |
| `FrameTop` | housing above 1.40 (side blocks, header over the opening, pocket roofs), collar above 1.40 | hide |
| `DoorL`, `DoorR` | leaves below 1.40 (6 cm, opaque, window strip, seal line, solid cap) | show |
| `DoorLTop`, `DoorRTop` | leaves above 1.40 | hide |
| `Lights` | green strips on the reveals (below 1.40) | show |
| `Status` | **header status light** on both faces (above 1.40) | hide |
| `Sign` | exit signs (room face of the +Y block; collar top) | hide |

- Housing: x −0.56 (room face) .. +0.04 (corridor face), **y ±1.72**, top **2.56**. Opening 1.50 × 2.10
  (y ±0.75, floor top 0.14 .. 2.24). The collar now starts at x 0.04 (on the housing face): no gap.
- Leaves: closed `DoorL` y −0.79..0, `DoorR` y 0..0.79, plane x −0.29..−0.23. **Open: move 0.75 m** on local
  Blender Y (Godot Z): `DoorL`/`DoorLTop` −0.75, `DoorR`/`DoorRTop` +0.75. An open leaf is **inside the housing**
  (pocket to 1.66): **never hide a leaf**. Timing per V3_1 §3.4 (open within 1.6 m, 0.6 s ease, close 0.8 s after).
- `Status` and `Lights` use material `Glow`: set the colour green (free), amber (busy / cycling), red (locked).
- Hide rule: **HIDE_HW 1.76** (was 1.64): hide every wall segment touching `beta ± asin(1.76 / Rw)`.
  Patches: from **asin(1.70 / Rw)** outward (was 1.07). Anchor_Room −1.05, Anchor_Corridor +1.00 (unchanged).
- Everything above 1.40 lives in `*Top`, `Status`, `Sign`: in the cutaway hide every object whose name **ends
  in `Top`**, plus `Status` and `Sign`.

### D2. Decals per wall segment (every 3.1 room file)

- Objects **`Decal_<seg>_<source>`**: every outer-wall decal face (materials Accent, Window, Neon, L3Band,
  L4Band, L5Gold, Trim, Light, LightStrip, Hazard, Screen, Glow, Plasma, Visor, Rubber, Solar) of `Base`,
  `Roof`, `Lights` or `L2`..`L5` that lies in the doorway zone (radius ≥ Rw − 0.45, z ≤ 3.0 m). `<seg>` =
  the wall segment of the face centre: segment k spans model angles **[k·11.25°, (k+1)·11.25°)** (same as
  `Wall_<k>`, angle convention P3).
- **Show a decal with its source**: `Decal_*_Base`, `Decal_*_Lights` always; `Decal_*_Roof` with the roof (hide in
  the cutaway); `Decal_*_L2`..`L5` only when that level part shows.
- **Hide at a doorway**: every `Decal_<k>_*` with k in `floor((beta − phi)/SEG) .. floor((beta + phi)/SEG)`,
  **phi = asin((0.75 + 0.40) / Rw)** (opening plus 0.4 m each side).
- **`Upper_<seg>`** (flat-walled shells only: podium, drum, setback): the upper wall skin at the wall line between
  1.40 m and the deck. Hide with the same rule as `Wall_<seg>` (HIDE_HW). The deck height is in
  `tools/blender/build_report.json` → `v3.decals.upper_z`. None in the pilot files.
- **`NameSign`**: the room-name plate (Frame + Screen, 1.0 × 0.30 m, 0.48–0.82 m high on the wall face). Its origin
  is the room centre; it is built at `v3.decals.name_sign_deg` (habitat 22.5°, airlock 135°). To move it to the
  free segment nearest that angle, rotate the object about the room axis by (new − default). Put the room name
  / number text on it.
- Draw calls: habitat M has 56 `Decal_*` objects (L2 and L4 bands). Please merge them per material like the
  walls (segment id in UV2 or a mask), not one draw call per object.

### D3. The airlock (`airlock.glb`, one size, R 2.8)

Line along model +X: suit room → inner door (x = −0.15) → pressure chamber (x −0.11..1.48, y ±1.05) → outer door
(x = 2.04, recessed so its housing stays inside the footprint) → porch outside.

| object | notes |
|---|---|
| `InnerDoorL/R`, `InnerDoorLTop/RTop`, `InnerStatus`, `InnerLights` | the inner door kit (housing in `Interior` below 1.40, `Roof` above) |
| `OuterFrame`, `OuterFrameTop`, `OuterDoorL/R`, `OuterDoorLTop/RTop`, `OuterStatus`, `OuterLights` | the outer door kit with hazard stripes on its face |
| `ChamberLight` | chamber strips at 1.3 m and a beacon on the wall top (`Glow`): amber = cycling, red = outbound pump, green = inbound done |
| `Porch` | ramp, dust mat, floodlight; **outside the footprint** (x 2.20..3.70, y ±1.0) |
| `Roof` | dome, the chamber block (y ±1.62, top 3.05 m) with pumps and a beacon, the chamber walls above 1.40 |

- Leaves open like the doorway: `…DoorL` −0.75 m on local Y, `…DoorR` +0.75 m (their frame is the room frame).
- Anchors: **`Anchor_Chamber_0..1`** (`airlock_slots` = 2) in the chamber, facing the outer door;
  **`Anchor_Suit_0..1`** at the suit racks; `Anchor_Porch_0..1` on the porch (queue); `Anchor_Stand_0..1`;
  `Anchor_Aisle_*` (join within 1.75 m); `Anchor_Beacon` on the chamber block.
- Doorways (corridors) attach at any angle ≥ 55° from +X (SIM rule); the wall there is normal.

### D4. Pilot pictures (`art/interiors/`)

`door31_{closed,half,open}.png` (cutaway), `door31_*_roof.png`, `door31_*_inside.png`,
`habitat_m.png`, `habitat_m_doorways.png`, `habitat_m_doorways_roof.png`,
`airlock_{closed,half,open}.png` (cutaway), `airlock_{closed,half,open}_roof.png`, `airlock_links.png`,
`airlock_links_roof.png`, `airlock.png`, `airlock_anchors.png`, `airlock_exterior.png`, `airlock_night.png`.

## 2026-09-25 — reply to "critic round 6 (RENDER)": Interior surfaces, stand points, the lab panel

1. **Interior surfaces ≤ 8 (done, build check).** Every room's `Interior` and every `Tall_*` part now has at most
   8 materials; `rooms_build.py` fails otherwise (`K.MAX_SURFACES`). How:
   - Plain materials merge into two new materials, **`Palette`** (white, rough 0.70) and **`PaletteMetal`**
     (white, metallic 0.60, rough 0.45). The face colour is in **COLOR_0** (colour × baked AO, linear). Your
     interior and wall-cut shaders already multiply `albedo × COLOR`, so nothing changes on your side.
   - Kept by name (you use them): `Accent`, `Neon`, `Screen`, `Glass`, `Soil` (tray check), and the emissive
     materials. `Light` folds into `LightStrip`. If a room still has more than 8, the least used coloured
     emissive folds into the nearest emissive colour.
   - The wall-side items in `Wall_*` also merge their plain materials into `Palette`; the wall shell keeps its
     names (your `SHELL_MATS`).
   - Interior surfaces, all 94 room files: before max 14, total 954; after max 8, total 520.
     `lounge_m` 14 → 7, `research_assembler_m` 14 → 8, `habitat_xl` 14 → 5, `habitat_l` 12 → 4.
   - The largest file now has 22 materials (was 27).
   - One loss: rugs and pads inside the Interior that were `Floor` / `FloorDark` are now `Palette`, so they do
     not get your `fill_gain` 1.9 for floors. The room floor itself is not in the Interior.
2. **Stand points.** The build now also fails when a standing `Anchor_Work_*` is closer than 0.12 m to the
   counter, bench or console it faces. It found and I fixed one real case: in `polymer_plant_xl` the second
   process unit stood on two console stand points. The bed, seat and work checks (0.35 m free floor) are green in
   all 94 files. Sit desks (research lab, electronics fab, the medical nurse station) are correct: the stand point
   is 0.12 m in front of the desk top, which has open knee space. I did not find a medical counter with a stand
   point on it. If you have the room file and the anchor name, send them and I will fix that one.
3. **Tilted white panel near the lab holo table.** Yes, `research_lab_*` was exported several times after
   23:25 (round-4 and round-7 rebuilds; the last export 2026-09-25 03:21). I found no stray or tilted object in
   the model. A likely candidate is the holo table's projection cone: it is `Glass` (alpha 0.35) with sloped
   sides. If the interior shader draws `Glass` without alpha, the cone shows as a solid pale tilted surface. The
   same applies to the new specimen cases and the assembler partitions. Please draw `Glass` in the Interior
   with alpha (as `wall_cut_alpha` does for walls).

## 2026-09-25 — ROUND 4: junction door kit, doorway fits the room shell, accent lights, door clearance, hazards

This section changes the production section below where they differ. Reference code (Blender):
`tools/blender/interior_render.py` → `junction_plan()`, `place_junction()`, `night_lighting()`.

### J1. Junction: no doorway.glb — open spans, posts, sills (action needed)

A junction (R 2.5, up to 6 links, `link_min_angle_deg` 28) cannot hold 6 doorways: the pocket housings overlap
(critic round 4 fail). For `junction` only, use these two new files instead of `doorway.glb`:

| file | objects | size |
|---|---|---|
| `assets/models/junction_post.glb` | Base (plinth, shaft, capital, `Accent` stripe), Lights (Glow strips on both sides) | 144 tris; x −0.26..0.07, y ±0.12, z 0..1.40 |
| `assets/models/junction_sill.glb` | Base (threshold plate, `Accent` line) | 10 tris; 1.0 m on Blender Y (Godot Z), x −0.24..0.10 |

Rule (all angles in model space, P3):
1. `Rw = R − 0.32`; each link has a mouth half angle `h = asin(min(0.99, 1.20 / Rw))` (33.4° at the junction).
2. Sort the links. Mouths closer than **8°** merge into one open span `[s0, s1]`. If one span covers
   ≥ 352°, the whole wall is open ("full").
3. **Hide** every wall segment that touches a span (`floor(s0/SEG) .. floor((s1−ε)/SEG)`; all 32 when full).
4. **Posts** (`junction_post.glb`, origin on the wall line at the angle, `Basis(UP, angle)`): one at each span end
   `s0` and `s1`, and one at the bisector between two links of the same span when they are **≥ 58°** apart.
   Full circle: posts only at those bisectors.
5. **Sills** (`junction_sill.glb`): cover `[s0, s1]` in pieces of ≤ 0.45 m chord, placed like the wall patches
   (radius `Rw cos(d/2)`, angle `mid`, scale `2 Rw sin(d/2) + 0.01` on local Godot Z).
6. **Patches** (`wall_patch.glb`, as before): `[k0·SEG, s0]` and `[s1, (k1+1)·SEG]`.
7. Tint `Accent` on posts, sills and patches to the room category colour (logistics `#9B6BD6`).
8. No door leaves at a junction: the mouths are open.

Pictures: `art/interiors/junction_links_{3,4,5,6}.png` (links 28° apart, the tightest SIM allows),
`junction_links_6even.png`, `junction_links_4even.png`, each with a `_roof` version.

Known limit: at 28° spacing the corridor tubes themselves overlap for about 2.4 m outside the junction (two
2.36 m tubes whose centre lines are 1.05 m apart at the wall). The junction kit is clean; the tube overlap is
geometry of the corridors. I asked SIM (`ART-HAB-to-SIM.md`) whether a junction needs a larger minimum angle.

### J2. Doorway: nothing above the wall top leaves the room shell

`doorway.glb` changed (1 024 tris). A 2.1 m door at the wall line cannot fit under an S dome (R 2.8–4.0), so:
- The header slab is gone. `FrameTop` is now an **entry hood**: the corridor's outer U profile (half width 1.26,
  top 2.46) carried inward from the collar to the pocket plane (x −0.52..0.02), above the wall top only. On a small
  dome it reads as the corridor tube entering the dome.
- **Everything above 1.40 stays inside that hood** (the jamb tops follow the arch; the upper leaves `DoorLTop` /
  `DoorRTop` have their outer top corner cut along the arch). The build checks it and fails otherwise.
- The **pocket housings stop at the wall top** (1.40). When a door is **open**, `DoorLTop` / `DoorRTop` stand
  outside the hood: **hide them while the door is open** (the lower leaves slide into the pockets as before).
- The room-side exit sign is on the +Y jamb face under the hood (1.54–1.66 m).
- Leaf plane, open distance, anchors and the hide rule are unchanged (P4, P6). Cutaway rule unchanged.
Known limit: `water_recycler` has a setback shell (1.46 m at the wall line); the hood rises above its setback
deck.

### J3. Door clearance: 1.2 m in L and XL; a blocked-angle list for S and M

- L and XL rooms keep a 1.10 m walking ring inside the wall items, so a doorway at any angle has 1.2 m of free
  floor in front of its pocket housings (except where content data puts trays near the wall, see the file).
- S and M rooms cannot give up that floor. Their blocked angles are in
  **`docs/requests/ART-HAB-door_blocked.json`**: per room file, `blocked` = model-angle spans (deg) where a
  doorway would face furniture closer than 1.2 m, `free_deg`, `min_clear_m`. Tall parts are not counted: hide
  every `Tall_*` within **2.2 m** of the doorway origin (P5). The file is written by every build.
- Suggested use: RENDER can warn in the link tool; SIM can refuse or nudge those link angles. That is a gameplay
  decision for SIM and the coordinator.

### J4. Family accent light: `Anchor_Accent_<i>` (new)

Every room has 2–5 `Anchor_Accent_<i>` over its signature item (bar, holo table, machine pad, tray row, tube
rows, bed bays). **Round 7 values** (the critic found round 4 too faint):
- a coloured point light at the anchor: **80 W** (was 40), range 3.0 m, soft 0.3;
- plus a **floor spill**: a coloured disk light (area) 1.8 m across, 1.0 m above the floor under the anchor,
  pointing down, **30 W** — the family colour must show on the floor;
- **wall fall-off**: ceiling lights (`Anchor_Light_*`) cut off at 3.2 m (was 5.6 m) and the warm floor pool is
  0.5 R (was 0.6 R), so the wall ring reads about 25 % darker than the middle.
In the game: scale these to your light units; keep the ratios (accent point : spill : ceiling = 80 : 30 : 90).
Colours:

| family | colour |
|---|---|
| lounge, cantina | neon `#F08FC0` |
| greenhouse | grow pink `#FF8FD8` |
| fungus_farm | violet `#A78BFA` |
| algae_bioreactor, bio_lab | culture green `#9CFFB0` |
| kitchen | warm `#FFB070` |
| research_lab | holo cyan `#7FE0FF` |
| research_assembler | clean-room blue `#8FB4FF` |
| medical, cold_storage | cool white `#BFE8FF` |
| habitat | warm `#FFC98A` |
| oxygen_plant, atmo_processor | `#5FE0EE`; water_recycler `#5FC8FF` |
| industry (7 types), storehouse, airlock | hazard amber `#FFB347` |

Night target changes: the floor pool is now 0.6 R (was 0.8 R), so the room edge falls off by about 25 %.
Pictures: `art/interiors/*_night.png` (18 rooms).

### J5. Hazard props (changed)

- `crater.glb`: the rim crest is at radius 1.0 (scale by the sim radius r, as `fx_hazards.gd` does now); broad,
  soft ejecta lobes reach 1.5–2.0 r; your splat reaches 2.4 r. No metal material (the old rim caught the sun as
  a dashed ring). All on the ground (z 0..0.12).
- `meteor_rock.glb`: the rock is split into chunks with a glowing core that shows only in the cracks. Round 7:
  the core material is **`Ember`** (new, emissive hot orange `#FF6A10` × 4). 550 tris, same size and origin.
- `crater.glb` round 7: a light sand rim edge (`Wood`), a dark bowl (`Rubber`), ejecta dark near the rim and
  light tan (`OreVein`) at the ends.
- `research_assembler_*` round 7: the roof panes are clear `Glass` over a lit strip (`L3Band`) on a dark roof.
- `research_assembler_*`: new clean-room exterior (fan-filter roof grid, air-handling unit and duct, airlock
  vestibule). Pictures: `art/interiors/research_assembler_{s,m,l,xl}_exterior.png`.

### J6. Request: in-game shots (critic round 6)

The critic cannot rate the junction or the S-room doorways in the game yet: the save has only 2-link junctions.
When J1 and J2 are in the game, please take these shots:

1. A junction with 4, 5 and 6 links at the tightest spacing (28°), roof off and roof on.
2. An S habitat, an S cantina and an S oxygen plant, each with 2 doorways, roof on (the dome meets the
   doorway) and roof off.

How to make them:
- **Console (debug=1)**: `place junction 1 X Y` then `place habitat 0 X' Y'` for each spoke, rooms at 18 m from
  the junction centre along 0°, 28°, 56°, 84°, 112°, 140° (S rooms of R 4 need about 17.6 m so that two
  neighbours 28° apart do not overlap). There is no console command to place a corridor today; a debug
  `link <idA> <idB>` command that submits `place_link {def: "corridor", a, b}` would make this scriptable
  (`presentation/main.gd`, your file).
- **Or a save from SIM** with those rooms and links (SIM's `reference.gd` already builds links with
  `place_link`).
- Shot tool: `node tools/shoot.mjs --gpu --dir build/web_... --query "seed=1001&debug=1" --steps <json>`.

## 2026-09-24 — PRODUCTION (round 2): every room is 3.0; doorway rework; hidable Tall parts; lamps; hazards

This section **replaces** the pilot numbers below (§3 hide rule, §4 leaf plane and status strips, §7 lights).
Reference implementation of every rule (Blender): `tools/blender/interior_render.py` → `link_plan()`,
`place_link()`, `tint_accent()`, `night_lighting()`. Pictures: `art/interiors/*_doorways.png`,
`*_doorways_roof.png`, `doorway_close*.png`, `*_night.png`.

### P1. Files

| file | objects | notes |
|---|---|---|
| all 94 room files `assets/models/<type>_<s|m|l|xl>.glb` (+ `airlock.glb`, `junction.glb`) | Base, Roof, Interior, L2..L5, `Wall_00`..`Wall_31`, `Tall_00`..`Tall_nn` (some rooms), anchors | every type and size is 3.0 now. No fake +X door except the airlock. |
| `research_assembler_{s,m,l,xl}.glb` | the same | new type (radii 3.6 / 4.6 / 5.8 / 7.2) |
| `doorway.glb` | Frame, FrameTop, DoorL, DoorLTop, DoorR, DoorRTop, Lights, Sign; Anchor_Room, Anchor_Corridor | REWORKED (1 048 tris, 12 materials) |
| `wall_patch.glb` | Base | REWORKED (58 tris): now carries the room band in `Accent` |
| `corridor.glb`, `corridor_rib.glb` | Base, Roof | unchanged since the pilot |
| `meteor_turret.glb` | Base, `Turret`, Lights; Anchor_Muzzle, Anchor_Service | new (1 008 tris) |
| `meteor_rock.glb`, `crater.glb`, `fragments.glb` | Base (+ Lights on fragments) | new |
| every exterior file (60) | + `Anchor_Service` | new anchor |

### P2. Loader grouping (action needed)

`models.gd group_of()` must keep these apart (list the longer name first because `begins_with` is used):

- `Wall_00`..`Wall_31` — one object per 11.25° segment (wall + wall-side furniture of that segment).
- `Tall_<nn>` — hidable tall furniture (see P5). Group with `Interior` for the cutaway, but keep each one
  addressable so it can be hidden alone.
- `DoorLTop` before `DoorL`, `DoorRTop` before `DoorR`, `FrameTop` before `Frame`, `Sign`, `Lights`.
- Draw calls: up to 32 wall objects with up to 14 materials. Proposal from the pilot stands: merge the visible
  segments of a room once and cache by `file + hidden-segment mask`.

### P3. Angle convention (unchanged)

Compute the angle in model space: `d_local = room_xf.basis.inverse() * d_world`,
`beta = rad_to_deg(atan2(-d_local.z, d_local.x))`. Segment k spans `[k·11.25°, (k+1)·11.25°)`.

### P4. Doorway placement rule (NEW numbers)

- `Rw = R − 0.32` (outer face of the wall), `SEG = 11.25°`.
- **Hide**: `phi = asin(min(0.99, 1.64 / Rw))` (was 1.10). The room-side pocket housings reach y ±1.62, so every
  segment they touch must go. Hide every k from `floor((beta − phi)/SEG)` to `floor((beta + phi)/SEG)` (mod 32).
- **Doorway**: position `(Rw cos beta, 0, −Rw sin beta)`, basis `Basis(UP, beta)`; origin height = room origin.
- **Patches**: hidden span `[a0, a1] = [k_first·SEG, (k_last+1)·SEG]`; `phi2 = asin(1.07 / Rw)`; fill
  `[a0, beta − phi2]` and `[beta + phi2, a1]`; split each part into `n = ceil(chord / 0.45)` pieces; per piece
  `d = b1 − b0`, `c = 2 Rw sin(d/2) + 0.01`, radius `Rw cos(d/2)`, angle `mid`, scale `c` on local Godot **Z**.
  Two links close together: union of hidden segments; patches = union spans minus every `[beta ± phi2]`.
- **Accent tint (new)**: `doorway.glb` (header stripe, collar stripe) and `wall_patch.glb` (room band) use
  material `Accent`. Tint it to the room's category colour (`build_assets.ACCENTS`, e.g. housing `#F2C14E`,
  medical `#E85D75`). Then the room band runs up to the door and the header shows the room stripe
  (critic round 2, item 5). Untinted, `Accent` shows the neutral default.
- Corridor stub: from `R − 0.25`; the doorway collar (x 0.02..0.46, outer y ±1.26, top 2.46) caps the tube.

### P5. Hidable tall parts — `Tall_<nn>` (critic round 2, item 5)

- What: headboards (bed bays), privacy screens, medical headwalls and curtains, the bio-lab fume hood, the
  airlock suit racks, the cantina neon sign.
- **Origin on the floor** at the item's position (the node location is not zero, unlike every other object).
- Rule: when a doorway is placed, hide every `Tall_*` whose origin is within **2.2 m** of the doorway origin
  (the wall line at `beta`). Hide it by day and night; it does not come back when the door closes.
- Rooms with Tall parts: habitat M 12, L 21, XL 27; medical S 1, M 3, L 7, XL 11; bio_lab 1 each; cantina 1
  each; airlock 4. The build report lists them (`tools/blender/build_report.json`, `tris_by_object["Tall_*"]`).

### P6. Doorway objects (reworked)

- Jamb: one clean profile in the wall plane, x −0.38..0.06. Room side: a pocket housing x −0.50..−0.38 that
  reaches y ±1.62. The open leaves slide into it.
- Leaves: closed `DoorL` y −0.79..0, `DoorR` y 0..0.79, **plane x −0.47..−0.41** (was −0.335..−0.265).
  **Open**: `DoorL` + `DoorLTop` −0.75 m on Blender Y (Godot +Z); `DoorR` + `DoorRTop` +0.75 m (Godot −Z).
  Open when a colonist is within 2 m (V3 rule).
- `Lights` (material `Glow`): status strips on the **inner faces of the opening only** (was also jamb tops and
  sill). Keep ON by day. Recolour for breach / locked if wanted.
- Header: 2.2 m wide, 4 cm chamfer, `Accent` stripe and a `Frame` trim line; pocket cap across ±1.62. Header top
  2.40. `Sign` above the header.
- **Cutaway**: hide `FrameTop`, `DoorLTop`, `DoorRTop`, `Sign` with the room roof; keep `Frame`, `DoorL`,
  `DoorR`, `Lights`.
- Anchors: `Anchor_Room` **x −1.05** (was −1.10), `Anchor_Corridor` x +1.00.

### P7. Furniture and lamp anchors (all rooms)

- Counts = `content/buildings.json` `furniture` for every type and size. The build fails when they differ.
  Table: `docs/progress/ART-HAB.md` (production section).
- Unchanged: z includes the floor (0.14); facing = `basis.x`; bed head = `−basis.z`; bed centre 0.55 behind the
  stand point, mattress top 0.55; seat 0.30 behind, seat top 0.46.
- New: `Work` anchors where the table has them. Standing work (console, bench): the person stands at the anchor
  facing `basis.x`. Sit desks (electronics fab control line, research lab desks): the anchor is at the chair.
- `Anchor_Aisle_*`: waypoints. Join two points when they are within **1.75 m** of each other (that is how the
  build draws the graph). Doorway → `Anchor_Room` → nearest aisle point → graph → the anchor.
- **`Anchor_Lamp_<i>` (new)**: bedside lamps, desk lamps, bar lamps. Small warm pools, see P8.

### P8. Night target (critic round 2: interior_lighting)

Blender target, `interior_render.night_lighting()`; pictures `art/interiors/<id>_night.png` (13 rooms):

| source | Blender value | colour |
|---|---|---|
| ambient | dim moon | cool |
| `Anchor_Light_*` | point, 90 W, range about 3.5 m, soft 0.35 | about 4 800 K (1.00, 0.91, 0.82) |
| `Anchor_Lamp_*` | point, 14 W, soft 0.10 | about 3 100 K (1.00, 0.70, 0.42) |
| floor pool | one disk light at z 3.2, radius 0.8 R, 42·(0.8R)² W | #FFE8C8 |
| `LightStrip` (cove, skirting, headboards) | emissive 2.5 | #EAF6FF |

Watts are Blender units; the game needs its own scale. Keep `Screen` and `LightStrip` out of any night
emissive boost (the pilot showed `Screen` blowing out).

### P9. Meteor hazards

- `meteor_turret.glb`: `Turret` object origin = the pivot (Blender (0, 0, 1.30) → Godot (0, 1.30, 0)). Rotate it
  about its local Y (Godot). At rest the barrels point +X, raised 20°. `Anchor_Muzzle` is **not** parented to
  `Turret`: it is the rest position (Godot about (1.41, 2.51, 0)). Rotate its offset from the pivot by the turret
  yaw to get the tracer start. `Anchor_Service` on +X.
- `crater.glb`: rim crest at radius about 1.0, outer rim foot 1.34; the rays and ejecta reach **2.4** (bbox
  −2.21..1.79 × −1.97..1.82). Scale uniformly. If SIM's crater radius means the whole scar, scale by r / 2.4.
  Everything is on or above the ground (z 0..0.13).
- `meteor_rock.glb`: about 1.0 × 0.8 × 0.7 m, origin under the rock (z 0.13..0.82). Glowing cracks use `Window`.
- `fragments.glb`: Base (rock) + Lights (crystal cores, `L4Band`), about 1.4 m across.

### P10. Anchor_Service on exteriors

Every exterior machine (60 files) now has `Anchor_Service`: 0.45 m in front of its +X face, at ground level,
facing −X (toward the machine). Verified by `tools/blender/ext_verify.py` (60 files, 0 flags).

### P11. Known limits for RENDER

- `junction.glb` (small radius) with 4–6 links: the hidden spans and pocket housings of neighbouring doorways
  overlap. Take the union of hidden segments; the housings may intersect each other. Picture:
  `art/interiors/junction_doorways.png`.
- On S rooms the pocket housing and the open leaves can show a few cm outside the dome skin.
- The door clearance to the nearest free-standing furniture is 0.83–0.98 m, not 1.2 m. Hiding `Tall_*` near a
  door (P5) is what keeps doors readable.
- In my export (`build/web_art_hab`) no doorway is drawn yet: corridors meet the full wall
  (`art/interiors/ingame_*_day.png`). The pictures with doorways are Blender compositions.

---

## 2026-09-24 — pilot (SUPERSEDED where the production section above differs)

Pilot notes: `habitat_m.glb` was the first 3.0 room; the doorway had no pocket housings (frame half width
1.10 used in the hide rule, leaf plane x −0.335..−0.265, Glow on the jambs, jamb tops and sill);
`wall_patch.glb` used a Trim band (the category band stopped next to the door). All of these are replaced above.
Still valid from the pilot: angle convention, corridor contract (1.0 m on X, scaled on X; end collars removed),
`corridor_rib.glb` not scaled (origin on the corridor centre line, +X along the corridor, one every 2.5 m; the
reference places the first at 1.70 m from the corridor start, after the collar), anchor z includes the floor,
`Screen` emission 0.45.
