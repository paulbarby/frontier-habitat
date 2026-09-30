# v5 clip plan — every people clip, for retargeting (ART-NPC, 2026-09-30)

Status: the plan for all v5 people clips. **Done** = built, verified and in `people_<v>.glb`. **Planned** = not built.
The robot clips are in `assets/models/robot_manifest.json`; the vehicle clips are in the astronaut files.

## 1. Conventions (all clips)

- 30 fps. Character space: X forward, Y left, Z up, metres. The origin is on the floor between the feet. The root never
  moves; the hips carry all travel. No scale keys.
- Authored at 1.80 m on the v3 skeleton (24 bones) + `jaw` + `lids`. A variant of height h plays the same pose
  functions at s = h / 1.80.
  - Positions scale by s. Seats, beds, desks and consoles keep their world heights (`people_anims.retarget`).
- **Pose states** (every clip starts and ends on one): `stand`, `sit` (seat 0.46 m), `kneel`, `lie` (bed 0.55 m),
  `stool` (bar stool 0.76 m), `vehicle`. A loop starts and ends on its state's rest pose, so clips chain.
- **Pairs:** `assets/models/npc_pairs.json`.
  - Partner B stands at `distance_m` along A's forward axis and faces A (`facing_deg`).
  - Both partners start at `sync_s`. Distances are for two 1.80 m people; scale by the mean s.
- **Face:** blinks in every clip (`lids`, 0.29 s, deterministic per clip). `jaw` in talking clips (amplitude below).
- **Limits** (checked by `npc_verify`): bone step < 15°/frame (not for locomotion or falls); loop seams ≤ 1°; nothing
  below the floor; contacts within 2–2.5 cm; partners not inside each other beyond 2 cm.

## 2. How the clips retarget to another rig

The clips are **pose functions**, not keyframes: each frame is a `Pose` of parameters.

| parameter group | meaning |
|---|---|
| `hips.x/y/z`, `hips.rx/ry/rz` | pelvis offset and turn, character space |
| `spine`, `chest`, `neck`, `head`, `shoulder.S`: `.rx/.ry/.rz` | FK turns about world-aligned axes in the parent frame |
| `arm.S.x/y/z` + `hand.S.wx/wy/wz`, `arm.S.ik` | wrist target and hand orientation, character space (IK) |
| `upper_arm/forearm/hand.S.r*` | FK arm, used when `arm.S.ik` = 0 |
| `foot.S.x/y/z/pitch/yaw/roll`, `knee.S.out`, `toe.S.ry` | ankle target and foot orientation (leg IK) |
| `jaw.ry`, `lids.ry` | face bones |

`npc_common.Solver` turns a Pose into bone rotations for **any rig with the same joint set**, from that rig's own rest
pose (`Solver.set_rest_from_rig`). The ends stay where the clip puts them on every rig: hands on handles, feet on
the floor, hips on the seat.

**Route A (recommended for MPFB): skin the MPFB meshes to the v3 skeleton.**
- Place the v3 joints on the MPFB body (per variant) and transfer the weights.
- Every clip then plays with no retarget, and RENDER's code and `people_manifest.json` do not change.
- Cost: a weight transfer per variant, and fewer spine and finger bones than MPFB's rig.

**Route B: bake the same pose functions on MPFB's game-engine rig.**
- Map the bones; add the extra spine bones as a share of `spine`/`chest`.
- The MPFB names below are **not yet confirmed**: MPFB is not installed (waiting for the download).

  | v3 | MPFB game_engine (to confirm) |
  |---|---|
  | root / hips | root / pelvis |
  | spine / chest | spine_01 / spine_02 + spine_03 (split the turn 50/50) |
  | neck / head | neck_01 / head |
  | shoulder.L / upper_arm.L / forearm.L / hand.L | clavicle_l / upperarm_l / lowerarm_l / hand_l |
  | thigh.L / shin.L / foot.L / toe.L | thigh_l / calf_l / foot_l / ball_l |
  | prop.L | a new bone under hand_l (the palm-centre socket) |
  | jaw / lids | jaw / (eyelid bones or shape keys) |

- Cost: the Solver needs the new joint list, and RENDER must change its bone names. It gives finger bones, which
  the v3 skeleton does not have.

## 3. Clip table

Times are in seconds at 30 fps. "Keys" are the key poses; loops end on their first key.

### 3.1 v3 clips (done, all variants)

| clip | frames | kind | from → to | keys / notes |
|---|---|---|---|---|
| idle | 120 | loop | stand | weight shift 6.5 cm, upper body turn 16°, a look at the wrist panel |
| idle_look | 180 | loop | stand | head scan left and right |
| walk | 32 | loop | stand | stride 1.12 m per cycle; in place |
| run | 20 | loop | stand | stride 2.27 m per cycle; in place |
| carry_walk / carry_idle | 32 / 90 | loop | stand | crate on `prop.R` (bottom centre 0.39, 0, 0.78) |
| work_console | 120 | loop | stand | hands on a console at 1.0 m, 0.45 m ahead |
| work_bench | 120 | loop | stand | hands on a bench |
| talk | 120 | loop | stand | gestures; jaw 4.5° |
| kneel_enter / repair_kneel / kneel_exit | 53 / 120 / 68 | enter / loop / exit | stand ↔ kneel | |
| sit_enter / sit_idle / sit_eat / sit_type / sit_exit | 58 / 150 / 120 / 120 / 53 | | stand ↔ sit | seat 0.46 m, back 0.30 m |
| lie_enter / sleep / lie_exit | 112 / 180 / 95 | | stand ↔ lie | bed 0.55 m |
| injured_walk | 40 | loop | stand | stride 0.90 m |
| collapse / dead | 69 / 30 | oneshot / hold | stand → lie | a fall: no step limit |
| cheer | 90 | oneshot | stand | |

### 3.2 v5 pilot clips (done, m1 and f1)

| clip | frames | kind | keys (s: pose) | contacts / pair / face |
|---|---|---|---|---|
| talk_gesture_a | 120 | loop | 4 gestures in 4 s (A1–A4) | jaw 5° |
| laugh | 73 | oneshot | 0 stand, 0.58 head back and right hand on chest, 1.15 lean in, 1.70 recover, 2.30 stand | shoulders shake 5.2 Hz; jaw 7–10° |
| argue | 90 | loop | 3 s: point, open palms, fist; with pauses | jaw 7° |
| hug | 103 | oneshot, paired | 0 stand, 0.55 reach, 1.00 hold, 1.55 squeeze, 2.10 hold, 2.70 release, 3.30 stand | pair: 0.30 m, 180°, sync 0 |
| sit_bar_stool | 150 | loop | on the stool; right foot on the footrest | stool seat 0.76, footrest 0.30 (r 0.20), counter at x 0.33, z 1.07 |
| dance_a | 120 | loop | 120 bpm step-touch, 8 beats | — |

### 3.3 v5 clips (planned)

| clip | frames | kind | from → to | keys (s: pose) | contacts / pair / face |
|---|---|---|---|---|---|
| talk_idle | 120 | loop | stand | small hand shifts, nods at 1.0 and 2.8 | jaw 3° |
| talk_gesture_b | 120 | loop | stand | counting on fingers (1.0), a shrug (2.2), open arms (3.2) | jaw 5° |
| listen_nod | 120 | loop | stand | head tilt 8°, nods at 0.8, 2.0, 3.2; arms folded | — |
| shout | 60 | oneshot | stand | 0.3 lean in, 0.5–1.4 mouth wide, a fist down at 0.9 | jaw 14° |
| sulk | 150 | loop | stand | shoulders down, head down 15°, a kick at the floor at 3.0 | — |
| wave | 60 | oneshot | stand | right hand up by 0.4, 3 waves at 2 Hz, down by 2.0 | — |
| handshake | 75 | oneshot, paired | stand | 0.5 hands meet at (0.40, −0.05, 1.00), 3 pumps to 1.8, release 2.1 | pair: 0.80 m, 180°, sync 0; `prop.R` of A and B meet |
| kiss_brief | 60 | oneshot, paired | stand | 0.6 heads meet, hold to 1.2, part by 1.7 (faces meet, no more) | pair: 0.35 m, 180°; adults only |
| hold_hands_walk | 32 | loop, paired | stand | walk; inner hands at side offset 0.45 m | pair: side-by-side 0.50 m, facing 0, phase 0 |
| flirt_lean | 120 | loop | stand | lean on one leg, hand on hip, head tilt, a laugh at 2.4 | — |
| slap | 45 | oneshot, paired | stand | 0.3 wind-up, 0.5 contact (open hand to the cheek zone), 0.9 recoil | pair with hit_react: 0.60 m, sync 0.5 |
| punch | 45 | oneshot, paired | stand | 0.25 wind-up, 0.45 contact at chest height, 0.9 recover (clumsy) | pair with hit_react: 0.70 m |
| hit_react | 45 | oneshot | stand | 0.45 hit, step back 0.15 m, hand to face or chest | reacts at the partner's contact time |
| fall_down | 50 | oneshot | stand → lie | knees buckle 0.3, side fall 0.9 (like collapse, shorter) | a fall: no step limit |
| get_up | 70 | exit | lie → stand | roll to a knee 0.8, stand 2.0 | — |
| fight_idle | 60 | loop | stand | guard up, bounce 2 Hz | — |
| protest_fist | 60 | loop | stand | fist up on each beat (1 Hz), shout | jaw 10° |
| handcuffed_walk | 32 | loop, paired | stand | walk; hands behind the back (`prop` bones together) | pair with escort_walk: side 0.45 m, phase 0 |
| escort_walk | 32 | loop, paired | stand | walk; left hand on the partner's upper arm | pair: see above |
| sit_bench | 150 | loop | sit | bench 0.45 m, no back: lean forward, forearms on thighs | seat as `sit` |
| drink_bar | 150 | loop | stool | as sit_bar_stool; glass on `prop.R`: lift 1.0–1.6, drink, down 2.2 | counter as sit_bar_stool |
| dance_b | 120 | loop | stand | 120 bpm: side-to-side two-step, arm swings across | — |
| dance_c | 120 | loop | stand | 120 bpm: bounce, arms up on beats 4 and 8, a half turn and back | — |
| swim | 40 | loop | stand (water) | breaststroke, body horizontal at the water line (anchor extras) | origin = water surface |
| lounge_pool | 150 | loop | lie | on a lounger (0.35 m, back raised 40°) | lounger numbers from ART-B |
| jog | 24 | loop | stand | stride 1.6 m; treadmill: stand point on the belt 0.24 m up | — |
| play_arcade | 120 | loop | stand | hands on the panel (ART-B cabinet numbers), button taps | panel from the anchor |
| shop_browse | 150 | loop | stand | look at shelf, pick up (`prop.R`) 1.5, look, put back 3.5 | shelf 1.1 m |
| sit_class | 150 | loop | sit | at a desk: writing, looking up | desk 0.72 m |
| teach | 150 | loop | stand | point at a board (x 0.8, z 1.6), turn to the class | — |
| sleep_cell | 180 | loop | lie | as sleep, on a bunk (0.45 m) | bed height from ART-HAB |
| child_play | 120 | loop | stand | (children, s ≈ 0.72) crouch and play with a toy, jump at 3.0 | — |
| child_run | 18 | loop | stand | stride 1.3 m per cycle (s ≈ 0.72) | — |

Clip count: 24 v3 + 6 pilot + 36 planned = **66** (the brief asks for 24 + ≥ 30).

## 4. Order of work after the MPFB decision

1. Agree the rig with RENDER (route A or B above) in `docs/requests/ART-NPC-to-RENDER.md`.
2. Rebuild the pilot on the chosen rig: m1 and f1, the 30 existing clips. `npc_verify` must stay green.
3. Build the planned clips in groups:
   - social: talk_idle, talk_gesture_b, listen_nod, wave, shout, sulk;
   - paired: handshake, kiss_brief, hold_hands_walk, slap, punch, hit_react, escort, handcuffed;
   - venues: sit_bench, drink_bar, dance_b/c, swim, lounge_pool, jog, play_arcade, shop_browse;
   - school and cell: sit_class, teach, sleep_cell;
   - falls: fall_down, get_up, fight_idle, protest_fist;
   - children.
4. Each group ships with verify checks (steps, seams, contacts, pair overlap), sheets and a dated RENDER note.
