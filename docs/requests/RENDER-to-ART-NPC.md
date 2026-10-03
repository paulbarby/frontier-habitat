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

## 2026-10-01 — RENDER: npc_check and the V5 clips (decision, tell me if you disagree)

- `npc_check` failed 12: the 6 V5 clips (`talk_gesture_a`, `laugh`, `argue`, `hug`, `sit_bar_stool`, `dance_a`) are
  not in `astronaut_suit.glb` / `astronaut_indoor.glb`.
- **Decision (RENDER, mirrors your vehicle-clip rule):** each file family owns its clips. The astronaut files need the
  v3 + v4 vehicle clips, NOT the V5 clips; the people files need the v3 + V5 clips, NOT the vehicle clips (people wear
  the suit outside). Suited people do not hug, dance or sit on a bar stool (all indoor venues).
- **Done in RENDER:** `fx_npc.gd` counts a clip as missing only for its own family (`VEHICLE_CLIPS`, `V5_CLIPS`); the
  astronaut `in` fallback maps `talk_gesture_a` / `argue` / `laugh` -> `talk` and `dance_a` -> `idle_look`.
- **Nothing to do for you** unless you want suited social clips. Please name the final people files (all six variants
  and the children) in a dated section when they are done: I start the people-loader work then.

## 2026-10-02 - the full MPFB set is in the game; four notes (RENDER)

**Drawn now:** all 8 variants (m1-m3, f1-f3, c1, c2; children from their own files), LOD1 beyond 12 m (shares the LOD0
clips: same skeleton and bind, verified in the bake), all 11 adult outfits + school (the outfit table held only 8:
medical, science and security were drawn as command; fixed), 62 adult / 48 child clips baked (everything in
people_manifest.json but lie_*_r, sleep_r, sleep_turn, drive_sit). SIM's `people.action` drives the shows: fights
(fight_idle / punch / hit_react, fall_down held then get_up), escort and cuffed walks (replace the walk cycle),
protest_fist, teach, sit_class, sit_bench, child_play, dance_a/b/c (Konami egg = dance_c), shop_browse, play_arcade,
jog. Robot dancers dance at the Club's anchors (cycle a/b/c/pole, idle when closed).

1. **Poses without enter/exit clips** (`stool`: drink_bar, sit_bar_stool; `bunk`: sleep_cell; `lounger`:
   lounge_pool; `water`: swim) are NOT drawn yet: my pose machine reaches a state only through its enter/exit clips.
   Either give me `stool_enter/exit` (and the others), or confirm that a cut (no blend) into these loops at the anchor
   is acceptable to you and the critic, and I cut.
2. **Planted foot height** (`tools/render_ground_check.gd`, bone heights against frame 0 of idle, every body of
   showcase_v5 for 15 s at 1x and 4x, 0.8 s windows): median 0 mm, but the lowest planted foot of a stride is
   **1.0-1.7 cm below** the standing foot in 5 % of walk windows (p5 -10.5 mm, p1 -16.7 mm, all variants) and in
   the run (p5 -12 mm). Please check walk and run for the planted toe/ankle dipping under the floor near the end of
   stance (your npc_verify measures soles; my numbers are ankle and toe joints, so a 1 cm dip may be the heel roll).
3. **Hair** (orchestrator, UI shot `docs/shots/ui19_follow_hud_1920.png`, Ike Brandt in the dome): the hair reads as
   a pale mop. Your hair base textures are near-white detail maps (m1: opaque texels mean RGB 205); my tint (mode 3)
   multiplies them. If that person's hair is meant to be dark, please check his variant's hair tone index and the
   texture; the transparent texels of m1's hair are light blue-grey (207, 223, 229): with mipmaps they bleed a pale
   fringe into the alpha-clipped edges. Filling the transparent texels with the hair colour (dilation) would fix that.
4. Same shot: "the far arm looks missing" - it was hidden by the dithered pillar in front (fixed on my side: the
   camera now swings round sight-line occluders, and the near fade is a narrow 0.5-0.7 m ring). Tell me if you see an
   arm missing in an open view.

## 2026-10-03 - ground check: the people walk 2 cm under their idle stance (RENDER)

`tools/render_ground_check.gd` on showcase_v5 (people_*.glb of 08:54-08:58 today): FAIL, 13,927 of 15,592
windows sink. Walk indoors p50 -22.0 mm, run about -21 mm, work_bench -22 mm, with the body's ground offset 0
(the body is drawn on the floor): the lowest foot of the walk / run cycle is about 22 mm below the foot at frame 0
of the same library's idle clip. Every people library shows it (p_f1..f3, p_m1..m3, LOD0 and LOD1). Before these
files the gate stood at p5 -8.5 mm. Please check the idle frame 0 foot height against the walk / run contact
frames (or tell me the stance reference to use). Detail: `art/npc/ground_check.json`.

## 2026-10-03 (later) - the "T-pose" in an indoor night shot: not reproduced; arms-out frames found in cheer and dance_c

The shot (showcase_v3_late, `time 540`, follow view of Asha Verrin 2) showed the followed person with both arms
straight out at shoulder height in a doorway. I could not reproduce it in a second run (16 shots, the same
person, `npcpose` each 1.5 s: walk, idle, idle_look, suit_swap, run - all drawn right). No core clip is missing
from any library (p_m1..m3, p_f1..f3: only child_play / child_run; p_c1 / p_c2 miss the adult social clips, which
fall back to idle). New scan `tools/render_tpose_scan.gd` (every frame of every clip: both hands within 0.15 m
of shoulder height and over 0.55 m out from the spine) finds this pose only in swim / swim_enter / swim_exit and in:
- **`cheer`**, frames 18-68 of 90, every adult library (4-5 sampled frames each);
- **`dance_c`**, frames 42-110 of 120, every adult library (14 sampled frames each).
A colonist standing free cheers when the colony gets an award (fx_npc), so `cheer` is the most likely clip in that
shot. If the arms-out section reads as a T-pose at eye level, please bend the elbows or raise the hands in
cheer (and dance_c), or tell me and I take cheer out of the follow-view person's clips.

## 2026-10-03 (night) - a far LOD2 for the people, please (RENDER, coordinator)

All roofs off / the overview at 110 m: the 134 people are 1.7 M triangles and 228 draw calls (about 5 ms a frame in
the web build). LOD1 is 12.9 k triangles per library over 21 parts (6 k per body drawn). Please make
`people_<v>_lod2.glb` for p_m1..m3, p_f1..f3, p_c1, p_c2:
- **a few hundred triangles per body** (target 300-500), the same skeleton and bind as LOD0 (the LOD0 clips are
  shared, as for LOD1), so my loader takes it like LOD1;
- **one mesh part per outfit at most** (better: one part with the outfit colours in vertex colour or the palette),
  no separate heads, hair or add-ons (one draw call per library and outfit);
- feet at the same height as LOD0 (the ground gate measures the planted foot).
I draw LOD2 beyond 40 m from the camera (LOD1 from 12 m as now). Tell me the file names when they are in.

## 2026-10-03 (evening) - LOD2 people: loaded, colour contract confirmed; one model case (RENDER)

Your `people_<v>_lod2.glb` files are in the game. Beyond 40 m from the camera (2 m hysteresis) a person is drawn
from `LOD2_<outfit id>` (one draw call per library and outfit). The people shader decodes your contract as
written: RGB from `COLOR_0` (linear), mode = round(A x 255) / 16, the tint of that mode multiplies RGB (1 department
stripe, 2 skin tone, 3 hair colour, 5 the person's clothes colour, 6 the outfit's `base_rgb`); no AO term at LOD2.
The `slot` bits are read but not used: LOD0 gives every `ClothTint_*` material of a person the same colour, so
LOD2 does the same. **Contract confirmed; no format change wanted.** Debug command `npclod 0|1|2|-1`.

Check (web build, daylight, every person forced to LOD0 and then LOD2, about 15 m from the camera): silhouettes,
skin, hair and uniform colours read the same. One case to fix, please:
- **The lab coat (`uniform_science`, `Addon_labcoat`): the dark uniform shows through the white coat** in large
  patches on the chest, back and sleeves (`docs/requests/shots/render_lod2_coat.png`, left LOD0, right LOD2;
  LOD0 also shows small patches). The coat surface needs a little more offset from the body at LOD2, or the body
  faces under the coat removed.
- For information: a brown dress in `docs/requests/shots/render_lod2_pair.png` reads darker at LOD2 (left LOD0,
  right LOD2). At 40 m this is a few pixels; no change asked unless you see a wrong mean colour.

Ground gate (`tools/render_ground_check.gd`): LOD2 bodies are measured like LOD0 (same skeleton and clips).
