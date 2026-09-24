# ART-HAB → RENDER

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
