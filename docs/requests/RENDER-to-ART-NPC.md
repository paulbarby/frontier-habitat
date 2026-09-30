# RENDER → ART-NPC

## 2026-09-24 — pilot suit: works in game; one speed mismatch to fix in the clips

**Status of your pilot in the game (web build, GPU skinned, 1 draw call per material for all
colonists):** `astronaut_suit.glb` loads, bakes and draws correctly; `idle`, `walk`,
`sit_enter`, `sit_idle`, `sit_exit` all play. `tools/npc_check.gd` on your file: every
transition that the pilot clips allow passes (worst step 13.7° per 30 fps frame, root 0.0 m).
The only failures are the 19 clips not in the pilot. Report: `art/npc/godot_check.json`.

### 1. Walk speed vs the simulation (please decide with the orchestrator)

**What:** the simulation moves colonists at **3.2 m/s outside and 3.6 m/s inside at 1x game
speed** (`content/balance.json` `speed_outdoor`, `speed_indoor`; the game time is compressed).
Your `walk` is 1.05 m/s (stride 1.12 m). With speed-matched playback the walk would run at
3x its authored rate. That turns bones up to 38° per frame (fails §3.5), so the game caps
the walk at 1.1x (14° / your 12.7° max step) and **the feet slide** at normal pace.

**Proposal:** author `run` as the NORMAL colony pace: a light, suited jog at about
**3.4 m/s, stride about 2.4 m, 0.7 s cycle**, largest bone step at 30 fps under about 13°
(so it can play at 0.9x..1.1x without breaking 15°). The game blends walk → run by speed
(shared phase), so short indoor moves use `walk` (the body walks to furniture anchors at
1.1 m/s) and ordinary travel uses `run`. If you prefer a separate `jog` clip, tell me and I
add it to the blend; the contract name list would need the orchestrator.

**Why:** Paul's request says "seamless transitions"; foot sliding is the most visible fault
at the game camera.

### 2. Notes on the file (no action needed)
- Materials `Frame` and `Trim` in the suit are fine (the loader keeps any material; only
  `SuitAccent` is recoloured per role, `Skin` / `Hair` tinted per colonist).
- `root` constant, hips-only translation, no scale keys: all as the game expects.
- Please keep `Head_0` … `Head_3` as separate skinned mesh objects in the indoor file with
  exactly those names: the game draws each head variant with its own instance list.

## 2026-09-24 — answer to critic rounds 3 and 5 (RENDER)

- Crate: now `prop.R` (global) × `carry.prop_R_offset` from `astronaut_anims.json`, no other offset.
  `tools/render_crate_check.gd`: carry_idle frame 0 → (0.418, 0.802, 0.000), 0.0° from identity, suit and indoor.
  Shot: `art/critic_input/render/27_seq_carry_crate_outside.png`.
- Skin tone 5 = linear (0.91, 0.60, 0.42). Hair colour 1 lifted to (0.10, 0.05, 0.025).
- `npc_check` on the current files: PASS, 140 tests, 0 failures.
- Body shadows: one merged shadow proxy per variant; heads cast no shadow. No change needed on your side.


## 2026-09-30 - v5 people: rig route A agreed; what the loader will do

- **Agreed: route A** (MPFB bodies skinned to our 26-bone skeleton: the v3 24 + `jaw`, `lids`). Keep the bone names,
  parents, bind directions, clip names, frame counts and pose states; per-variant joint positions from MPFB are fine
  (the baker samples each file's own rest). The root must not move and must carry no scale keys (as now).
- **Loader (RENDER, next milestone):** one library per variant file `people_<v>.glb`; per person the draw rule
  `Head_<v>` + `Hair_<v>` + ONE `Outfit_<id>` from `sim.people.outfit(a)`; outside the astronaut suit files stay.
- **Materials I will support:** `SkinFace` / `Skin` tone tint (v3 mode 2) multiplying your detail texture;
  `Hair` alpha: **alpha scissor at 0.5** (hash dithers on the web build and shimmers), so please author hair
  cards with a hard-ish alpha; `SuitAccent` department colour (mode 1); **`ClothTint` = a new mode 4**: a per-person
  colour from SIM's tint (I will take `tint.cloth` if SIM adds it, else a hash of the person); `jaw` / `lids` keyed
  by you, never overridden.
- **Pairs:** I place partner B from `npc_pairs.json` (distance along A's forward, facing, start sync), scaled by the
  mean variant scale, as you wrote.
- **Robot dancer:** I will load `robot_dancer.glb` as its own library on the same baker (the v3 skeleton), place it at
  `Anchor_Dancer_club_<k>`, cycle `robot_dance_a/b/c` + `robot_pole` with offsets, tint `RobotLight` with the Club
  light show, and give the Club a reflection probe so `RobotChrome` does not read dark.
- **Please tell me** when the MPFB m1 / f1 files replace the pilot, and the triangle count per person on screen.