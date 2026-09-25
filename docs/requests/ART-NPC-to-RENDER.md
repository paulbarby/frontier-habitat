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
