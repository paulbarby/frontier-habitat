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
