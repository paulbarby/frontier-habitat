# ART-NPC → RENDER

## 2026-09-24 — pilot suit delivered; answers to RENDER-to-ART-NPC.md

**Files:** `assets/models/astronaut_suit.glb`, `assets/models/astronaut_anims.json`.
Report: `art/npc/npc_report.md` (43 pass, 0 fail, 3 pending = indoor variant and the non-pilot clips).

**What is in the GLB**
- Armature object `Rig` (→ one `Skeleton3D`, 24 bones, section 3.2 names) and one skinned mesh `Body`.
  The suit has 8 materials: `SuitMain`, `SuitAccent` (the role colour), `Visor` (gold, metallic 0.95, rough 0.14), `Pack`,
  `Frame`, `Trim`, `Rubber` and `Light` (emissive: the pack status lights, the helmet lamps, the chest and wrist displays).
  COLOR_0 = baked AO.
- Clips: `idle` 120 f, `walk` 32 f, `sit_enter` 58 f, `sit_idle` 150 f, `sit_exit` 53 f at 30 fps.
  In `astronaut_anims.json`, `frames` is the index of the last frame (length = frames / 30 s). A loop's last frame
  equals its first frame.
- `root` and `prop.L/R` have no tracks. They are constant, so the exporter drops them and they stay at rest. `hips`
  has position and rotation tracks. Every other bone has a rotation track.
- `prop.R` / `prop.L`: the bone head is the grip centre, 3.5 cm off the palm and 7.5 cm from the wrist. Bone +Y
  points along the fingers.
- Stand rest = `idle` frame 0. Sit rest = `sit_idle` frame 0. The feet stay on the stand point during
  sit_enter and sit_exit (1 cm shift). No root motion.

**1. Walk speed (your item 1)**
- The walk has been re-timed in the swing phase. The worst bone step at 1x is now **8.88° per frame**. It is
  measured as your check measures it: the larger of the world rotation and the rotation relative to the parent.
  Before it was 12.67° (shin.R, relative to the parent), the same value your check got. So the walk now plays
  up to about **1.6x (1.7 m/s)** before it passes 15°. The 1.1x cap can go up.
  `speed_mps` 1.05, `stride_m` 1.12. Foot slide in contact is 0.94 cm at 1x.
- `run` as the normal colony pace at about 3.4 m/s: **agreed; I will build it in the next round** (it is not a pilot
  clip). **One risk that I report now:** your target is a step under 13° at 30 fps. At 3.4 m/s that is
  **390°/s at the knee**. A believable jog has a peak knee speed of about 600–900°/s. I will make a
  low, shuffling suit jog to fit the limit and report the measured value. If the jog then looks stiff,
  the orchestrator must choose: a higher limit for `run`, or run clips at 60 fps. It is not my decision.

**2. Heads (your item 2):** agreed. The indoor file will have `Head_0` … `Head_3` as separate skinned mesh objects
with exactly those names.

**3. Size for layout:** stand pose: x −0.42 … +0.24 m, |y| ≤ 0.46 m, top 1.848 m. Sit pose: the life-support
pack reaches x = −0.69 m, between z 0.55 and 1.2 m. Also see ART-NPC-to-ART-HAB.md.

## 2026-09-24 — full delivery (both variants, 24 clips); this section replaces the pilot notes above where they differ

**Files:** `assets/models/astronaut_suit.glb` (6,839 triangles), `assets/models/astronaut_indoor.glb`
(5,932 triangles: `Body` 3,300 + `Head_0..3` 600 / 696 / 628 / 708), `assets/models/astronaut_anims.json`.
`art/npc/npc_report.md`: 234 passed, 0 failed, 0 pending. Both files have the same skeleton (rest difference 0.000000) and
identical clips (your shared bake is correct).

**What changed from the pilot**
- All 24 clips. `root` has no track; `hips` has position + rotation; `prop.L` / `prop.R` now have position + rotation
  tracks (they move in the carry clips); every other bone has rotation only. No scale tracks.
- `walk` 1.05 m/s, stride 1.12 m (32 f). **`run` 3.40 m/s, stride 2.27 m (20 f, 0.667 s)**: a light jog with a flight
  phase (6 of 20 frames) and a 3.5 cm bob. `injured_walk` 0.675 m/s, stride 0.90 m. `carry_walk` = walk legs
  (1.05 m/s). Walk and run share the phase convention: left heel strike at phase 0.
- The pilot's 13° target for run is dropped (V3_DESIGN §3.5, 24 Sep): run's largest step at 1x is 22.1°.
- New materials (the loader keeps them; none needs tinting): `SuitHard` (#E8EAED, rough 0.45, the helmet and the hard
  upper torso), `LightGreen` / `LightAmber` (pack status lights, emissive 3), `Light` is now #FFF4E0 emissive 4
  (helmet lamp lenses only), `Screen` and `LightStrip` (the same values as ART-HAB's, chest box and wrist screens).
  Indoor: `Jumpsuit`, `Skin` (tint per colonist), `Hair` (tint per colonist), `SuitAccent` (role colour: shoulder
  panels, collar, cuffs, pocket flaps, hair ties), `Frame`, `Trim`, `Rubber`.
- **Crate (carry_idle, carry_walk):** attach the crate at `prop.R` with **no offset and no rotation**. In those clips
  the `prop.R` origin is the crate's bottom centre and its basis is the character basis (Godot: x forward, y up). I
  checked this in Godot (`art/npc/npc_probe.gd` → `godot_probe.json`): origin (0.418, 0.802, 0.0), basis 4.5° from
  identity (the crate leans with the chest). Crate size: up to 0.40 m. Your present code adds an offset
  `(0.05, -0.18, -0.12)` and scales 0.8; please remove the offset. Outside the carry clips `prop.R` rides the hand
  (grip centre), as before.
- `collapse` ends exactly on `dead` frame 0 (on the ground, lying on the left side, head to +Y), which matches your
  lie-state loop `dead`. `sleep` frame 0 is on the bed (mattress top 0.55 m, centre line 0.55 m behind the stand
  point, head to +Y).

**Your check (`tools/npc_check.gd`, run by me on these files): 140 tests, 28 failures. Every pose-to-pose test (24/24)
and every clip test (48/48) passes.** The failures and what I found:
1. **Triangles = 0 is a reporting bug in `presentation/fx_npc.gd` line ~418:** triangles are counted only
   `if DisplayServer.get_name() != "headless"`, and `npc_check.gd` runs headless. `surface_get_arrays()` works headless
   (my probe counts 6,839 and 5,932 that way).
2. **Cross-fade blending (24 failures, `loop stand` idle/idle_look ↔ work_console/work_bench/talk, worst 45.9° hand.L).**
   `lerp_xf()` (`fx_npc.gd` line 531) lerps the basis vectors of the GLOBAL bone transforms. Between two orientations
   more than about 90° apart that basis shrinks and skews, and the rotation you read back from it jumps. In one earlier
   build a palm-up hand against a palm-down hand read as a 139° pop. I removed the palm-up and palm-down pairs, which
   dropped the worst pop from 155° to 46°, but the arms-down vs hands-on-console change is about 100° at the forearm and
   the hand. **Proposals:** (a) blend with quaternion slerp (local rotations, sign-aligned) instead of the matrix lerp;
   (b) cross-fade loops whose largest bone change is big for longer: for example `fade = max(0.25 s, angle / 300°/s)`
   — 0.25 s for a 100° change means ≥ 13°/frame average and more at the eased peak, so §3.5's 15° cannot pass with any
   pose. (b) changes §3.4's fixed 0.25 s: **the orchestrator decides**.
3. **`locomotion idle -> walk -> run -> stop` (2, shin.L 39.5°, limit 27.7°):** the walk→run blend, the same lerp_xf
   effect on the shin (walk knee 13°, run swing knee up to about 100°). Slerp should clear it.
4. **`carry on/off while walking` (2, prop.R 80.5°):** prop.R has no mesh weights; it jumps from the hand to the
   crate frame when carrying starts. Proposal: leave `prop.*` out of the pop test (nothing is drawn by it).

## 2026-09-24 — critic round 3 changes (replaces the crate note above)

- **Crate:** `prop.R` now has **no keys in any clip**; it keeps its place in the right hand. Attach the crate to `prop.R`
  with the fixed local transform `carry.prop_R_offset` in `astronaut_anims.json` (Godot bone space:
  `Transform3D(Basis(basis_x, basis_y, basis_z), origin)`, the basis values are columns). Its origin is the crate's
  bottom centre. Checked in Godot (`art/npc/npc_probe.gd`): in carry_idle frame 0, prop.R global × offset = origin
  (0.418, 0.802, 0.000), basis 0.0° from identity. The crate now rides the hand, so carry on/off no longer moves prop.R.
- **Hair:** the head meshes use material `Hair` for the hair and the brows. Your shader tints it by name (mode 3,
  four colours), so no change is needed on your side. The eyes, lids and mouth are `Frame` (not tinted).
- **Work, desk and talk loops** now keep the wrist near its idle bend (the forearm takes the palm turn), so hand
  rotations change little between loops.
- **`tools/npc_check.gd` on these files: PASS, 140 tests, 0 failures, `ok: true`.** Triangles 6,839 (suit) and 5,936
  (indoor). Items 1–4 of my previous note are closed.

## 2026-09-24 — critic round 5: skin tone 5 and the hair colours

- **Skin tone 5 (the lightest) reads grey-white.** Please change it in `shaders/npc_skin.gdshader` (`palette6`, the
  last value) from linear `vec3(0.93, 0.68, 0.52)` to **`vec3(0.91, 0.60, 0.42)`** (sRGB about #F5CDAF: more red and
  yellow, less grey). `art/npc/turnaround_indoor.png` shows it with this value.
- **Hair colours:** your rule `hc = (tone + head * 3) % 4` gives all four colours in the game, because `_look()` draws
  head and tone from independent hashes. The near-black row in my earlier sheet was my own sampling (head = tone % 4
  always gives hc 0). The sheet now shows all four colours. Note: colour 0 (0.016, 0.012, 0.010) and colour 1
  (0.055, 0.030, 0.017) both read near-black at 55 px; lifting colour 1 to about (0.10, 0.05, 0.025) would separate them.
  That is your choice.
- `tools/npc_check.gd` on the new files: PASS, 140 tests, 0 failures.


## 2026-09-25 — v3.1: `suit_swap` clip and visitor looks (V3_1 §5.4, §6.4)

### 1. `suit_swap` — please add it to `tools/npc_check.gd`

- New clip in both files: `suit_swap`, 60 frames = 2.0 s, oneshot, `stand` → `stand`. Metadata in
  `astronaut_anims.json`: `clips.suit_swap = {frames: 60, duration_s: 2.0, kind: oneshot, pose_from: stand,
  pose_to: stand, cut_frame: 30}`.
- **Cut at frame 30 (1.0 s).** Both hands hold the helmet sides (wrists 1.62 m high, 0.225 m out). The pose is still
  from about frame 26 to frame 31. `npc_verify` measures it: identical in both files at frame 30 (0.0000°), 0.26°
  between frames 29 and 31. The clip data is the same in both files, so your shared bake gives the same pose.
- Sequence: stand → hands out in front → helmet sides (hold across the cut) → chest seals → hands past the belt → stand.
- Largest bone step 14.24° per frame (forearm.L, frame 12). Starts and ends on the stand rest pose (0.000°).
- Please add to `npc_check.gd`: `clip suit_swap at 1x` (both variants), `idle -> suit_swap -> idle`, and the cut
  itself: suit frame 30 vs indoor frame 30 identical.

### 2. Visitor looks — how to select them

**Files.** The body files do not change for visitors. The attachments are in new files:
`assets/models/astronaut_visitor_suit.glb` and `assets/models/astronaut_visitor_indoor.glb`. Each holds the rig
(identical to the body files: same 24 joints, same order, same rest pose; verified) and five skinned meshes
`Vis_trader`, `Vis_tourist`, `Vis_medical`, `Vis_science`, `Vis_inspector`. The files have no clips. Drive them with
the suit bake, as you do for the indoor meshes.

**Look code.** Proposal: `look = (8 + v) * 64 + head * 8 + tone` for a visitor with look `v` (0..6). Colonists keep
`role * 64 + head * 8 + tone` with role 0..7. So `look / 64 >= 8` means a visitor and `v = look / 64 - 8`.

| v | kind | set | how it reads at 30 px |
|---|---|---|---|
| 0 | trader | 0 | orange body, grey helmet/HUT/pack |
| 1 | tourist | 0 | white body, cyan helmet and HUT |
| 2 | tourist | 1 | white body, lime helmet and HUT |
| 3 | tourist | 2 | white body, magenta helmet and HUT |
| 4 | medical | 0 | white body, red pack, red crosses |
| 5 | science | 0 | blue body, white helmet/HUT/pack, mast above the helmet |
| 6 | inspector | 0 | black body, gold stripes and crest; indoor: black peaked cap |

Tourist set: pick it from a hash of the visitor id. Table: `astronaut_anims.json` → `visitors.looks[v]`.

**Colours (shader).** For a visitor, replace the albedo of each surface whose material name is a key of
`looks[v].suit` (suit model) or `looks[v].indoor` (indoor model) with that colour. Linear values are in
`suit_linear` / `indoor_linear`. This is the rule you use now for `SuitAccent` (mode 1): `tint = colour / albedo`.
Groups:
- suit: `SuitMain`, `SuitHard`, `Pack`, `SuitAccent`;
- indoor: `Jumpsuit`, `SuitAccent`.

A proposal: a new mode 4 for `SuitMain` / `SuitHard` / `Pack` / `Jumpsuit`, and a `vis_cols[7 * 4]` uniform per
material. Mode 1 (`SuitAccent`) then reads the visitor accent when `role >= 8`. Colonists (role < 8) do not change.

**Attachments.** Treat `Vis_<kind>` like `Head_N`: one MultiMesh per mesh, and draw it only for the visitors whose
`looks[v].kind` is that kind (collapse the vertices for all other instances, as you do with `head_id`). Materials on
the attachments are plain (`VisRed`, `VisGold`, `VisGrey`, `VisWhite`, `VisDark`, `Rubber`, `Trim`, `Frame`,
`Screen`, `LightGreen`). The exception is `SuitAccent`, which takes the visitor accent colour (tourist camera strap
and pennant).

> [!IMPORTANT]
> Indoor inspectors must not use head 1 (the high bun). The cap does not fit it. Use head 0, 2 or 3 (JSON:
> `visitors.heads_not_allowed.inspector = [1]`).

**Triangles per visitor on screen.**
- suit: Body 6,839 + the largest attachment (trader, 112) = 6,951 ≤ 7,000;
- indoor: Body 3,356 + the largest head 708 + the largest attachment (science, 566) = 4,630 ≤ 6,000.

The attachment files: suit 466 triangles, indoor 1,814 (all five meshes).

**Sheets:** `art/npc/visitors_lineup.png` (all looks next to a colonist: front, back, and at 55 px and 30 px with the
game camera) and `art/npc/visitors_turnaround.png` (each kind: four sides, close-up, 55 px).

**Checked:** `npc_verify` 279 passed, 0 failed, 0 pending. Each attachment stays within 2 cm of the body in every
clip, and none goes below z −0.01. `npc_check.gd` on the new body files: PASS, 140 tests, 0 failures (it has no
suit_swap tests yet). `godot.mjs check`: 156 scripts, 0 failed. **Not tested:** the visitor files inside the game
(this needs your loader and shader change).


## 2026-09-25 — critic round 12: visitor changes (replaces parts of the v3.1 section above)

**1. Mesh names and the head rule (changed).** The rule "indoor inspectors never use head 1" is **removed**. Every
head can be used for every visitor. The indoor visitor file now has two inspector meshes:
- `Vis_inspector_h023`: closed cap; draw it for heads 0, 2 and 3.
- `Vis_inspector_h1`: the crown top is a ring, and the bun of head 1 rises through it; draw it for head 1.

**Rule:** draw `Vis_<kind>` for visitors of that kind. When the name ends in `_h<digits>`, draw it only when the
head number is one of those digits. The suit file still has one mesh per kind (it has no heads). JSON:
`visitors.meshes = {suit: [...5 names], indoor: [...4 names, "Vis_inspector_h023", "Vis_inspector_h1"]}`.
`visitors.heads_not_allowed` is removed.

**2. New plain materials** (attachments only):
- `VisGraphite` #3A3F47.
- `VisHiVis` #E4F218, emission #E4F218 at 0.5.
- `VisGoldReflect` #D9A93A, metal 0.3, emission #D9A93A at 0.8.

The emission stands in for a retro-reflective trim, so it can be seen at night. Your loader already reads the emission
from the material. If you have a night reflect effect, apply it to these two materials.

**3. What changed on the models**
- Indoor tourist: gaiters and boot covers in `SuitAccent` (the tour colour).
- Indoor trader: the vest is `VisGraphite`, with a `VisHiVis` band and hi-vis shoulder straps.
- Suit inspector: `VisGoldReflect` bands round both thighs and shins, and two stripes across the pack. The cuff rings
  are removed (triangle budget).
- The colour table (`visitors.looks`) and the look code are unchanged.

**4. Triangles per visitor on screen**
- suit: at most 6,839 + 150 (inspector) = 6,989 ≤ 7,000.
- indoor: at most 4,064 + 878 (tourist) = 4,942 ≤ 6,000.

**Checked:** `npc_verify` 281 passed, 0 failed. `npc_check.gd`: PASS, 140 tests, 0 failures. `godot.mjs check`:
157 scripts, 0 failed. **Not tested:** visitors in the game.


## 2026-09-27 — v4.0: vehicle clips and the radiation look (V4 §5, §8, §11)

### 1. New clips (both files, the same data in suit and indoor)

| clip | kind | frames | pose from → to | frame | cut frame |
|---|---|---|---|---|---|
| `drive_sit` | loop | 120 (4.0 s) | vehicle → vehicle | seat | — |
| `ride_sit` | loop | 150 (5.0 s) | vehicle → vehicle | seat | — |
| `board` | enter | 60 (2.0 s) | stand → vehicle | door | **60** (last frame) |
| `alight` | exit | 60 (2.0 s) | vehicle → stand | door | **0** (first frame) |
| `board_r` | enter | 60 | stand → vehicle | door (mirror) | **60** |
| `alight_r` | exit | 60 | vehicle → stand | door (mirror) | **0** |

- **New pose state `vehicle`**, rest pose = `ride_sit` frame 0 (`pose_rest.vehicle` in the JSON). `drive_sit`
  differs from it only in the arms (hands on the grips), as `sit_type` differs from `sit_idle`: cross-fade between them.
- **Two frames of reference.** All values are in `astronaut_anims.json` → `vehicle_seat`.
  - **Seat frame** (`drive_sit`, `ride_sit`): the origin is on the cabin floor, facing forward. The seat is the chair
    contract: top 0.46 m, centre 0.30 m behind the origin. Place the body at the seat anchor that ART-B gives.
  - **Door frame** (`board`, `alight`): the origin is on the ground beside the vehicle, facing the vehicle's forward
    direction. The seat is on the character's right: `seat_offset = (0.0, -0.52, 0.32)` (the seat-frame origin in
    the door frame). The `_r` clips are the mirror images: seat on the left, `seat_offset = (0.0, +0.52, 0.32)`.
    Use them for a right-hand door.
- **What the cut frame means.**
  - `board`: the last frame equals `ride_sit` frame 0 moved by `seat_offset` (measured: 0.000°, hips 0.0 mm). At frame
    60, move the body origin from the door point to the seat anchor and play the seat loops. Nothing on screen moves.
  - `alight`: frame 0 equals the same pose. At frame 0, move the body origin from the seat anchor to the door point.
  - Door point = seat anchor − `seat_offset` (rotated with the vehicle).
- **Measured in `npc_verify`:**
  - largest bone step: board 13.69°, alight 12.75°, drive_sit 1.86°, ride_sit 1.21° per frame;
  - loop seams 0.000°; stand start and end 0.000°;
  - no vertex through the cabin floor (0.32 m, beyond the sill at y −0.22) or the seat;
  - drive_sit wrists within 3.4 cm of the grips (the grips move with the steering);
  - the seated top is below 1.60 m (headroom); the rearmost point (suit pack) is at x −0.685 m.
- For a pressurised cabin with a rear door (medium rover), V4 §8 allows a fade at the door. The seat loops still apply
  inside.
- Please add these clips to `npc_check.gd`:
  - each clip at 1x;
  - `idle -> board -> ride_sit` with the origin moved at the cut;
  - `ride_sit -> drive_sit` cross-fade;
  - `ride_sit -> alight -> idle`.

### 2. Radiation look (look 7)

- A colonist work look for radiation zones. It is selected like the visitor looks:
  `look = (8 + 7) * 64 + head * 8 + tone`.
- Colours, from `visitors.looks[7]`:
  - suit: `SuitMain` hazard yellow #F2C230; `SuitHard` #1E2024 (black HUT and helmet); `Pack` #26282D;
    `SuitAccent` #1E2024;
  - indoor: `Jumpsuit` #F2C230; `SuitAccent` #1E2024.
- Attachment `Vis_radiation` in both visitor files:
  - suit: black shoulder shields, a lead-grey apron on the waist, a dosimeter (screen and amber light) on the right
    chest, black bands on the shins;
  - indoor (reactor rooms): dosimeter, apron, shin bands, respirator.
- JSON: `visitors.work_looks = {radiation: 7}`. The role colour does not show while the look is on.
- The shoulder shields, dosimeter, apron and respirator take their weights from the body mesh under them (weight
  transfer), so they bend exactly like the suit.

### 3. Numbers

- **Triangles per character on screen:**
  - suit: at most 6,839 + 160 (radiation) = 6,999 ≤ 7,000;
  - indoor: at most 4,064 + 878 (tourist) = 4,942 ≤ 6,000.
- **Size effect (Godot imported .scn, the files that go in the pck):** 1,023,237 → 1,226,464 bytes (+0.20 MB).
  - The six new clips: suit +97 KB, indoor +97 KB.
  - The radiation meshes: +9 KB.
- **Checked:** `npc_verify` 356 passed, 0 failed. `npc_check.gd`: PASS, 145 tests, 0 failures (it has no vehicle
  tests yet). `godot.mjs check`: 181 scripts, 0 failed.
- **Not tested:** the clips in the game, and the origin move at the cut.

Sheets:
- `art/npc/vehicle_clips.png` (board and alight with the seat pose placed at `seat_offset`, and both loops, suit and
  indoor, with a stand-in cabin);
- `art/npc/clips_suit.png` and `clips_indoor.png` (all clips);
- `art/npc/visitors_lineup.png` and `visitors_turnaround.png` (with the radiation look).


## 2026-09-27 — vehicle clips, revision 2 (after ART-B's small rover fit)

- **New clips: `step_up`, `step_down`, `step_up_r`, `step_down_r`**, 60 frames each (2.0 s), stand → stand.
  - Ground frame: the origin is at the ground point (`Anchor_Ground_N`), facing the rover's forward direction.
    `step_offset` = (0.0, −0.53, 0.50) for the left door, (0.0, +0.53, 0.50) for the right door.
  - **Cut frames:** `step_up` **60**: its last frame is the stand pose moved by `step_offset`; move the body origin to
    `Anchor_Board_N` and play `board`. `step_down` **0**: its first frame is the same pose; move the origin from
    `Anchor_Board_N` to the ground point.
  - Full chain: `step_up` → `board` → `ride_sit` / `drive_sit` … `alight` → `step_down`. Every hand-over is exact:
    0.000° and 0.0 mm, measured.
- **drive_sit:** the hands now stay on ART-B's fixed handles. The palm is 0.9 cm from the handle axis at worst, and
  the hands travel 1.6 cm (it was 5.6 cm).
- **Handle positions** (`vehicle_seat` in the JSON) are ART-B's measured ones:
  - grips (0.298, ±0.142, 0.925);
  - grab handle (0.261, 0.316, 0.725).
  - The palm centre (prop.S) is on the handle axis.
- The frames, cut frames and offsets of `board` / `alight` are unchanged.
- **Size (imported .scn):** 1,226,464 → 1,341,337 bytes (+0.11 MB, the four step clips).
- **Checked:** `npc_verify` 408 passed, 0 failed (it includes a no-intersection check on ART-B's rover for all ten
  crew clips). `npc_check.gd`: PASS, 145 tests, 0 failures (no vehicle tests yet). `godot.mjs check`: 191 scripts,
  0 failed.
- **Not tested:** the chain in the game.
- Please add to `npc_check.gd`: `step_up -> board -> ride_sit` and `alight -> step_down`, with the origin moved at each
  cut.


## 2026-09-29 — v5.0 people, PILOT (V5_DESIGN §1): build against `people_manifest.json`

The pilot is ready for CRITIC. Structure and names are final unless a later dated section says otherwise. The
`astronaut_*` files are unchanged; your current code does not break.

- **Files:** `assets/models/people_<variant>.glb`, one per variant. Pilot: `people_m1.glb` (1.80 m), `people_f1.glb`
  (1.68 m). Index: `assets/models/people_manifest.json` (`variants`, `outfits`, `draw`, `clips`, `furniture`).
- **Skeleton:** v3 (24 bones, same names, parents, bind directions) + `jaw` and `lids` under `head` = 26 bones. Each
  variant's rig is the v3 rig scaled by height / 1.80, applied (no scale keys, the root never moves).
- **Draw rule per person:** show `Head_<v>`, `Hair_<v>` and ONE `Outfit_<id>`; hide every other `Outfit_*`. The outfit
  mesh includes the visible skin (forearms, hands), so no body mesh is under it.
- **Materials / tint:**
  - `SkinFace` (head): skin tone as v3 mode 2; the face texture multiplies (base colour factor is white).
  - `Skin` (arms, hands in the outfit meshes): v3 mode 2.
  - `Hair`: v3 mode 3; the strand texture multiplies.
  - `SuitAccent`: department colour, v3 mode 1 (the uniform stripe).
  - **`ClothTint`: NEW. Please add a mode for a per-person clothes colour** (f1 casual tee now; more outfits later).
    Until then it keeps its own colour (navy).
  - All others plain: Eye (textured), Mouth, LipInner, Teeth, Coverall, Cotton, Denim, Leather, Sole, Rubber, Metal,
    Nail. `COLOR_0.r` = baked AO, as v3.
- **Clips (30 in each file):** the 24 v3 clips (same names, frames, pose states) + `talk_gesture_a` (120 f loop),
  `laugh` (stand → stand), `argue` (loop), `hug` (paired, stand → stand), `sit_bar_stool` (150 f loop, new pose state
  **`stool`**), `dance_a` (120 f loop). Frames and pose states per clip: `people_manifest.json` → `clips`.
  - Seats, beds, desks and consoles keep their world heights in every variant (the clips are retargeted per height).
  - Bar stool: `furniture.bar_stool` (seat 0.76 m, footrest 0.30 m, counter at x 0.33 m, z 1.07 m).
  - Vehicle clips are NOT in the people files: people wear the suit outside (astronaut files).
- **Face:** `jaw` and `lids` are keyed in the clips (blinks everywhere, jaw in talk / talk_gesture_a / argue / laugh).
  Do not override them.
- **Pairs:** `assets/models/npc_pairs.json`. `hug`: both partners play `hug` at the same start time; partner B at
  0.30 m along A's forward axis, facing A (180°). Distance is for two 1.80 m people; scale by the mean variant scale.
- **Triangles LOD0 per person on screen:** m1 11,834 / 11,634; f1 15,798 / 15,332 (budget 24k). **No LOD1 yet**
  (after the critic pilot).
- **Size (imported, `.godot/imported`):** +2,906,768 bytes for the pilot (m1 1.38 MB, f1 1.53 MB, 1024 px face
  textures embedded). `assets/models/people_tex/` has a `.gdignore` (no double import).
- **Checked:** `npc_verify` 441 passed, 0 failed (includes per-variant people checks). `npc_check.gd` PASS (165 tests).
  `godot.mjs check` 257 scripts, 0 failed.
- **Not tested:** people in the game (no loader yet), tint modes on the new materials, the hug placement in the game.


## 2026-09-30 — v5.0 robot dancer (V5 §1, §8: the Club)

- **File:** `assets/models/robot_dancer.glb`, index `assets/models/robot_manifest.json`.
  - Rig: the v3 skeleton (24 bones, 1.80 m, the same names, parents and bind as the astronauts).
  - One skinned mesh: `Robot_dancer`, 14,884 triangles, rigid parts (1 bone per vertex), `COLOR_0.r` = AO.
- **Materials:**
  - `RobotChrome`: metallic 1, roughness 0.13. It needs a reflection probe or sky in the Club; without one, it reads dark.
  - `RobotLight`: emissive, strength 3.0. Visor light bar, chest light, forearm and shin strips, waist ring, ear rings.
    Please tint or pulse it per dancer with the Club light show (a mode-1 style tint on the emission).
  - `RobotJoint`, `RobotTrim`, `RobotVisor`: plain.
- **Clips (all loops, 30 fps):**

  | clip | frames | what |
  |---|---|---|
  | `robot_idle` | 120 | servo idle between shows |
  | `robot_dance_a` | 120 | popping hits on the beat (120 bpm) |
  | `robot_dance_b` | 120 | liquid arm wave from hand to hand, body roll |
  | `robot_dance_c` | 240 | pirouette, arm circle with a squat, isolations, bow |
  | `robot_pole` | 240 | grip, a tucked spin once round the pole, land, lean, release, V pose |

- **Chain rule:** every robot clip starts and ends on the same pose (stand, origin, facing +X). At a loop end, cut to any
  other robot clip with no blend. Measured: all starts equal (≤ 1°, 1 mm), seams 0.000°.
- **Placement:** at ART-B's `Anchor_Dancer_*` (podium top, 0.35 m in front of the pole, facing the room).
  - `robot_pole` needs the pole at local (−0.35, 0), radius 0.045 m. ART-B's model matches.
  - The other clips stay within 0.3 m of the origin. The feet stay ≤ 0.70 m from the pole axis (podium radius 0.80 m).
- **Suggested use:** cycle `robot_dance_a/b/c` and `robot_pole` per dancer with a different start offset, and
  `robot_idle` when the Club is closed.
- **Size:** +388,671 bytes imported.
- **Checked:**
  - `npc_verify` 455 passed, 0 failed. Robot checks: step < 15°/frame (max 14.90°), seams, chain, podium top, feet on
    the podium, nothing inside the pole (gripping hands ≤ 0.9 cm).
  - `npc_check.gd` PASS (165; no robot tests yet). `godot.mjs check` 264 scripts, 0 failed.
- **Not tested:** the robot in the game, in the Club light, with RENDER's materials.


## 2026-09-30 — v5 people: rig decision = route A (MPFB bodies on OUR skeleton)

- Paul chose MPFB / MakeHuman bodies. The orchestrator chose **route A**: the MPFB bodies are skinned to the v3
  skeleton + `jaw` + `lids` (26 bones), exactly as in the pilot.
- **For RENDER nothing changes:** the same `people_<v>.glb` names, `people_manifest.json` structure, draw rule
  (`Head_<v>` + `Hair_<v>` + one `Outfit_<id>`), bone names, clips, pose states and pairs.
- **What may change** (I will confirm per file in a dated note):
  - Joint positions per variant come from the MPFB body; bone names and parents do not change.
  - Hair becomes alpha cards: material `Hair` with an alpha texture. Please support alpha scissor (or hash) on `Hair`.
  - The skin texture becomes a detail map that the tone tint multiplies, as `SkinFace` does now, on the whole skin.
- **Timing:** the pilot is rebuilt first (m1, f1; uniform_engineering, casual_a), then CRITIC. The other variants
  follow after that.


## 2026-09-30 — v5 people: MPFB pilot built (m1, f1) — what your code must handle

- **Files and names unchanged:** `people_m1.glb`, `people_f1.glb`, `people_manifest.json` (`version` 5.0-mpfb-pilot).
  - The rig is ours: 26 bones, the same names and parents. All 30 clips, pose states and pairs are unchanged.
  - Joint positions now come from each MPFB body.
- **Draw rule unchanged:** `Head_<v>` + `Hair_<v>` + one `Outfit_<id>`.
  - `Head_<v>` now holds only the eyes, brows, lashes and teeth.
  - The face and all visible skin are in each `Outfit_<id>`. Covered skin is removed per outfit.
- **Materials (please check your tint lookup):**

  | material | handling |
  |---|---|
  | `Skin` | tint mode 2; the texture is a detail map around white. There is no `SkinFace` any more. |
  | `Hair`, `Hair_brows`, `Hair_lashes` | tint mode 3, alpha MASK (cutoff 0.5). **Match on the name prefix `Hair`.** |
  | `SuitAccent` | the uniform polo; department colour (mode 1); the texture multiplies |
  | `ClothTint` | the casual tee; per-person colour (still needs your new mode) |
  | `Coverall`, `Cloth_*`, `Eye`, `Teeth` | plain textured; the colour is baked in, do not tint |

- **Normal maps:** some garments have them (256 px).
- **Triangles on screen:** 23.4k per person (budget 24k). **No LOD1 yet.** The MakeHuman low proxies (about 3.2k
  triangles) are the plan for LOD1.
- **Size:** 12.45 MB imported for m1 + f1 (about 6.2 MB per variant).
- **Robot dancer update (CRITIC round 38 fixes):**
  - `robot_dance_b` is now a step routine with a full turn.
  - Knee bounce on the beat in dances a, b and c.
  - Hip block, thicker thighs, knee plates.
  - The names, frames and chain rule do not change. 16,056 triangles, 412,530 bytes imported.
- **Not tested:** people in the game, your tint modes on the new material set, alpha MASK hair in your shader.


## 2026-10-02 — v5 people FULL SET, final for the people loader (file names, manifest fields, rig notes)

This replaces the pilot notes above where they differ. All files are one consistent build (2026-10-02 20:39-20:48).

### Files (assets/models/)

| file | content |
|---|---|
| `people_m1.glb` `people_m2.glb` `people_m3.glb` `people_f1.glb` `people_f2.glb` `people_f3.glb` | adults, LOD0: armature `Rig`, `Head_<v>`, `Hair_<v>`, `Outfit_uniform`, `Outfit_casual_a`, `Outfit_casual_b`, `Outfit_casual_c`, `Outfit_swimwear`, 9 `Addon_*` meshes, every clip |
| `people_c1.glb` `people_c2.glb` | children, LOD0: `Head_<v>`, `Hair_<v>`, `Outfit_school`, `Outfit_casual_a`, `Outfit_casual_b`, `Outfit_swimwear`; no add-ons; children's clip list (no adult-only clips) |
| `people_<v>_lod1.glb` | LOD1 (beyond 12 m): the same mesh names, the same skeleton and bind, NO clips (use the LOD0 file's clips) |
| `people_tex_shared/*.png` | the textures the glb files reference (external) |
| `people_manifest.json` | everything below |
| `npc_pairs.json` | paired clips (placement of partner B) |
| `astronaut_suit.glb`, `astronaut_indoor.glb`, `astronaut_visitor_suit.glb`, `astronaut_visitor_indoor.glb`, `astronaut_anims.json` | rebuilt with the same names and draw rules |
| `robot_dancer.glb`, `robot_manifest.json` | unchanged |

### people_manifest.json fields

- `skeleton.bones` (31) and `skeleton.face_bones` (`jaw`, `lids`, `brow.L/R`, `mouth.L/R`, `lids_low`).
- `variants.<v>`: `sex`, `child`, `height_m`, `scale`, `file`, `lod1_file`, `head`, `hair`, `outfits`, `addons`,
  `triangles`, `triangles_lod1`, `triangles_on_screen` (`outfit_and_addons`, `with_head_and_hair` per outfit id),
  `triangles_on_screen_lod1`, `clips` (the clips this variant has), `look`, `source`, `assets`.
- `variants.<v>.outfits.<outfit id>`: a mesh name (casual, swimwear, school) or `{mesh, addons, base_rgb, accent_rgb?}`
  (the six uniforms and `prison` share `Outfit_uniform`: draw it with the listed `Addon_*` and tint `UniformBase*` with
  `base_rgb`; `accent_rgb` overrides the department colour for `SuitAccent*`).
- `outfits` (who / look per outfit id), `addons` (what each `Addon_*` is), `draw` (per-person rule and the material
  table), `clips.<name>` (`frames`, `duration_s`, `kind`, `pose_from`, `pose_to`, `loop`, and where present
  `speed_mps`, `stride_m`, `furniture`, `pair`, `mirror_of`, `children_only`, `note`), `furniture`, `pose_states`,
  `textures`, `credits`.

### Draw rule (unchanged)

`Head_<v>` + `Hair_<v>` + ONE `Outfit_<mesh>` + that outfit's `Addon_*`. Hide every other `Outfit_*` and `Addon_*`.
Material table as in `draw.materials` (Skin* tone tint, Hair* tint + alpha clip 0.5, SuitAccent* department colour,
UniformBase* `base_rgb`, ClothTint* per-person colour; everything else plain).

### Rig and clip notes

- Bones, parents and bind directions as before. Root never moves; no scale keys; hips carry the translation.
- The clip data now contains: shoulder rhythm (the clavicles move with the arms), soft elbow and wrist limits, and a
  surface guard (hands and elbows on the mattress and on the floor). Nothing to do on your side.
- Frame counts that changed (manifest is the source; re-read it): people: lie_enter / lie_enter_r 304 -> 392, lie_exit / lie_exit_r 308 -> 404, sleep_turn 309 -> 270, argue 105 -> 102, laugh 75 -> 76, talk_gesture_b 121 -> 120, shout 88 -> 91, wave 96 -> 100, kiss_brief 100 -> 89, slap 71 -> 74, punch 81 -> 88, hit_react 76 -> 78, protest_fist 84 -> 80, shop_browse 161 -> 162, teach 164 -> 162; astronauts (`astronaut_anims.json`): lie_enter 304 -> 392, lie_exit 308 -> 404, step_up / step_up_r 60 -> 63
- `npc_pairs.json`: hug `distance_m` 0.44 -> 0.48; hold_hands_walk `side_offset_m` 0.50 -> 0.64; slap `sync_s` 0.76 -> 0.86; punch `sync_s` 0.74 -> 0.90; `hand_contact: true` added to hug, kiss_brief, slap, punch. `hand_contact: true` means the hands touch the partner by design (information only).
- Children on adult seats: their feet hang (they cannot reach the floor); on the bed they hop up onto the mattress.
- Outfits now share one sole height per body (soles raised up to 19 mm on the thicker-soled outfits), so every outfit
  stands on the floor (the clips have one ankle offset per body).
- Shoes stay on in bed: they are part of the `Outfit_*` mesh. If you want them hidden in bed, ask; it needs a separate
  shoe mesh per outfit (more draw calls).

### Import settings (people files)

`meshes/generate_lods=false` (LOD1 is its own file), `meshes/create_shadow_meshes=false`,
`meshes/ensure_tangents=false` (no normal maps: your people shader samples albedo only); textures in
`people_tex_shared/` lossy (0.85) with mipmaps.

### Sizes (imported) and triangles

- Imported (`.godot/imported`): people scenes LOD0 22.3 MB (2.3-3.0 MB per body), LOD1 2.9 MB, shared textures 6.3 MB (51 files): **people total 31.5 MB**. Astronaut files 1.6 MB, robot 0.4 MB.
- Unused textures (146 + 6 files, 15.6 MB source) moved out of the imported tree to `art/people/_tmp/stale_tex/`.
- Triangles per person on screen, LOD0: body + outfit + add-ons <= 14,000 (V5 §1); with head and hair 18.0k-20.3k. LOD1: outfit 1,900; with head, hair and add-ons 2.6k-3.3k (uniform_security 3,259 and uniform_command 3,174 are over 3k by the vest / jacket add-ons).

### Not tested by me

People in the game, your tint modes on these materials, alpha-clip hair in your shader, LOD switching.

## 2026-10-03 — people: motion-capture walk and run; answers to your 2026-10-02 notes

All files are again one consistent build (2026-10-03 07:08-07:16). `npc_verify` 604/0, your `npc_check` PASS 165/0.

- **walk and run are motion capture now** (CMU takes 143_32 and 143_01, retargeted to our skeleton; credit in
  `art/people/people_credits.md` and the manifest `credits`). Names, bones and pose states unchanged.
  - `walk`: 34 frames (was 32), `speed_mps` 1.156, `stride_m` 1.31 (was 1.05 / 1.12).
  - `run`: 21 frames (was 20), `speed_mps` 3.296, `stride_m` 2.307 (was 3.405 / 2.27).
  - Please re-read `people_manifest.json` for the speed match. The astronaut files keep the hand-keyed walk and run.
- **Your note 2 (planted foot dip):** on the clips, the ankle and ball joints of walk and run never go below their idle
  frame-0 height by more than 1.6 mm (m1, f1: ankles +0.9..+2.2 mm, balls -1.6..+0.3 mm; was the hand-keyed gait).
  If your ground check still shows 1-1.7 cm dips, they come from the blend or the playback rate; tell me the clip pair.
- **work_console -> talk pop (15.4 deg):** fixed in `talk` (the first gesture rises over 0.9 s; forearm peak 11.7 -> 9.2
  deg/frame). Your `npc_check`: PASS 165 tests, 0 failures. `talk` frame count unchanged.
- **Your note 3 (pale hair fringe):** every alpha texture (Hair*, brows, lashes) now has the visible hair colour under
  the clip (mean colour + 3 px dilation), so mipmaps no longer bleed a pale edge.
- **Your note 1 (stool / bunk / lounger / water):** no enter/exit clips this run. A cut into these loops at the anchor
  is acceptable to me for 5.0 (a short cross-fade if your pose machine allows one). Ask again if the critic objects.
- `npc_pairs.json`: hug has `arm_contact: true` (the arms rest on the partner by design; information only).
- Sizes: people imported 30.5 MB (LOD0 22.3, LOD1 2.9, textures 5.3).
