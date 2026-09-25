# ART-NPC progress

Owner: ART-NPC (astronaut models and animations, V3_DESIGN.md section 3). Files: `tools/blender/npc_*.py`,
`assets/models/astronaut_*`, `art/npc/**`.

Build (Git Bash, background only):
`"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python tools/blender/npc_build.py -- --variant suit`
Check and sheets:
`"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python tools/blender/npc_verify.py -- --pilot --renders`
Godot probe (after `node tools/godot.mjs import`): `node tools/godot.mjs script res://art/npc/npc_probe.gd`

## v3 — 2026-09-24 — pilot: suit model, skeleton, idle / walk / sit clips

**Landed**

| file | what |
|---|---|
| `assets/models/astronaut_suit.glb` | armature `Rig` (24 bones, section 3.2) + one skinned mesh `Body`; 6,781 triangles (budget 7,000), 3,905 vertices; 8 materials; COLOR_0 AO; clips idle, walk, sit_enter, sit_idle, sit_exit |
| `assets/models/astronaut_anims.json` | fps, height, skeleton, clip metadata (frames, kind, pose_from/to, loop, walk speed_mps 1.05 / stride_m 1.12), furniture numbers, pose-state rest frames |
| `tools/blender/npc_common.py` | skeleton, SkinPart (a weight rule per vertex, smooth chain blends, max 4, normalised), rig + skinned mesh, pose solver (world-aligned FK, 2-bone leg IK with heel / ball pivots, arm IK with forearm pronation), Hermite timeline with ease and per-bone lag, action baking, atomic GLB export |
| `tools/blender/npc_suit.py` | suit geometry: HUT, waist bearing and bellows, pelvis, chest control box, umbilical, pack (thermal covers, vents, two status lights, grab rail, antenna, battery module), helmet (gold visor, frame rim, role stripe, two lamps, neck ring), arms (shoulder bearing, role stripe, elbow bellows, wrist ring, wrist computer), gloves, legs (thigh bearing, knee bellows, pocket), boots (thick sole, cuff, toe bumper) |
| `tools/blender/npc_anims.py` | STAND and SIT rest poses, idle (4 s), walk (32 f, heel strike, flat, heel-off, swing; hips lowered automatically where a leg would over-reach), sit_enter, sit_idle (5 s, with a hand tap), sit_exit |
| `tools/blender/npc_build.py` | build driver |
| `tools/blender/npc_verify.py`, `npc_render.py` | section 3.5 checks on the exported file (raw glTF and evaluated in Blender) and the render sheets |
| `art/npc/npc_report.md/.json` | 43 pass, 0 fail, 3 pending (pilot scope) |
| `art/npc/turnaround_suit.png`, `clips_suit.png`, `transitions.png`, `deform_suit.png` | sheets (deform = extra: joint close-ups) |
| `art/npc/npc_probe.gd`, `godot_probe.json` | Godot import probe: 1 Skeleton3D, 24 bones, skinned `Body` with 8 surfaces, 5 clips at the right lengths |

Measured: loop seams 0.000°; enter/exit ends vs rest poses 0.000°; walk foot slide 0.94 cm; worst bone step per 30 fps
frame (larger of world and parent-relative): walk 8.88°, sit_enter 10.03°, sit_exit 12.30°; mesh never below −0.0015 m;
stand top 1.848 m; seated lowest point over the seat 0.460 m.

Fixed during the pilot (seen in my own renders): claw-like gloves → gloved fingers with a palm pad; a 118° wrist twist
on the seated hand tore the gauntlet → arm IK now puts 80% of the pronation in the forearm; "I"-shaped seam
on the pack → covers and a service panel; walk knee step 12.67° → 8.88° (it failed at 1.3x playback).

**Next** (after the pilot critic round): the critic's fixes; indoor variant (`Jumpsuit`, `Skin`, `Head_0`…`Head_3`);
the other 19 clips; `run` as the normal colony pace (RENDER request); the section 3.5 checks for both files.

**Not tested / known limits**
- Not seen in the game by me. RENDER reports that it loads and plays in the web build (RENDER-to-ART-NPC.md). I ran
  only the Godot import probe.
- The 15° step limit is not checked at playback rates other than 1x, except for walk at 1.3x.
- Skinning at extreme poses (arms overhead, deep kneel, lying) is not tested yet. No pilot clip uses them.
- The seated suit's pack reaches x −0.69 m. Chairs with backs collide with suited colonists (sent to ART-HAB).
- The renders use EEVEE with Standard view transform. They are not the game's lighting.

## v3 — 2026-09-24 — full delivery: round-1 fixes, indoor variant, 24 clips

Pilot critic (docs/critic/round_1.md): npc_suit 0.75, npc_animation 0.66 (provisional).

**Landed**

| file | what |
|---|---|
| `assets/models/astronaut_suit.glb` | 6,839 triangles (≤ 7,000); 13 materials; 24 clips |
| `assets/models/astronaut_indoor.glb` | `Body` 3,300 + `Head_0` 600, `Head_1` 696, `Head_2` 628, `Head_3` 708 = 5,932 (≤ 6,000; one colonist shows 3,900–4,008); same skeleton; the same 24 clips |
| `assets/models/astronaut_anims.json` | 24 clips; walk 1.05 m/s, run 3.40 m/s, injured_walk 0.675 m/s; furniture; carry contract; collapse ends on dead |
| `tools/blender/npc_indoor.py` (new) | jumpsuit body, knee pads, work boots, four heads (crop, bun, bob, ponytail) |
| `tools/blender/npc_suit.py`, `npc_common.py`, `npc_anims.py`, `npc_build.py`, `npc_render.py`, `npc_verify.py` | see below |
| `art/npc/npc_report.md/.json` | **234 passed, 0 failed, 0 pending** (11 for information) |
| `art/npc/turnaround_suit.png`, `turnaround_indoor.png`, `clips_suit.png`, `clips_indoor.png`, `transitions.png`, `deform_suit.png`, `deform_indoor.png` | sheets |
| `art/npc/npc_probe.gd`, `godot_probe.json` | Godot import probe: triangles, clips, the prop.R basis in carry |

**Round-1 fixes done** — suit: flush 4×3×3 cm helmet lamp housings with a forward lens (`Light` #FFF4E0, emissive 4);
green and amber pack status lights; chest box with a lit `Screen`, UI bars, two accent buttons; 2.5 cm hose from the
pack; `SuitHard` (rough 0.45) on the helmet and HUT with a seam line; three Trim ribs at the knees and elbows; 14-sided
legs; AO with 96 samples, neighbour blur and floors (SuitMain ≥ 0.55); pelvis 2–3 cm smaller; 8-sided gloved fingers
in two pairs with rounded tips and rubber palms; chamfered pack covers; the pack is 3 cm higher (0.61 m clear of the
seat behind x −0.40 m). Animation: run (3.40 m/s jog, flight phase, 3.5 cm bob); walk with a 6–15° knee while the
heel is down; idle with a 6.4 cm weight shift, a 17° upper-body turn and a look at the wrist panel; arms 9.3° from
the body; sit gloves 1 cm up.

**Tools added:** monotone spline tangents (no overshoot), forearm pronation that fades at ±180° (no wrist flips), arm
IK frames from the elbow bend plane, elbow poles in world terms, chest-relative arm and prop targets, prop.R placement
in Godot's identity basis, quaternion signs start in w ≥ 0.

**Measured in Godot** (`node tools/godot.mjs script res://tools/npc_check.gd`, RENDER's check, run by me): 140 tests, 28
failures. Every pose-to-pose test (24/24) and every clip test (48/48) passes. The failures: 24 loop cross-fades between
arms-down loops and work/talk loops (worst 45.9°), 2 walk→run (39.5°), 2 carry on/off (prop.R, no mesh). The cause is
RENDER's matrix-lerp blending and the fixed 0.25 s fade (docs/requests/ART-NPC-to-RENDER.md). The triangle count of 0 is
a headless guard in `fx_npc.gd`.

**Not done / not tested**
- No in-game sequences, and no night shots of an outside colonist at 25–30 m zoom. Those are RENDER's (critic item 5).
- The per-clip contact checks use my furniture proxies at the §3.3 numbers, not ART-HAB's models.
- Shared clips mean body-specific contact is a compromise: sleep is tuned to the indoor body (the suit sinks 3.2 cm
  into a mattress), kneel and dead to the suit (indoor dead lies 2.7 cm above the ground). Seat: suit 0.456 m,
  indoor 0.474 m.
- Tolerances I chose, stated in the check names: the seat's front 3 cm and the mattress's front 5 cm are soft; body may
  press ≤ 2 cm into the seat.
- `collapse` has no per-frame limit in my check (a fall; worst 22.1°).

## v3 — 2026-09-24 — critic round 3 fixes

Round 3 scores: npc_suit 0.80, npc_animation 0.75 (provisional), npc_indoor 0.66.

**Done**
- Indoor face: the nose projects 40 % less and has a round tip; a 3 cm mouth line; a rounder jaw; bigger eyes with
  lid lines; lower, thinner, curved brows. Skull 7 % wider, head 1.2 cm lower, collar 1.8 cm higher (visible neck
  3 cm shorter), neck 15 % thicker.
- Hair silhouettes: tight crop, high bun 35 % bigger, jaw-length bob with 2 cm more volume, ponytail to the collar
  3 cm further out. Hair and brows use material `Hair` (RENDER tints four colours by name).
- Indoor body: upper arms and thighs 13–15 % thicker, forearms and calves 8 %; crotch 4 cm higher, with glute volume
  at the back (the seat contact stays at 0.468 m); rounded shoulder-panel edge roll; name patch in the role accent,
  sleeve patch, leg seam lines, a wrist unit with a screen. Hands (both variants): index finger apart, the other
  fingers curled 20° more, thumb 15° further in.
- `turnaround_indoor.png` shows the six skin tones with RENDER's palette and hair-colour rule.
- Clips: repair_kneel 8° more upright with the shoulders forward (helmet 0.357 m ≤ 0.37 m, hands reach 0.45 m);
  talk gestures 6–8 cm higher with a 10° nod; carry_walk elbows give 1.2 cm at each foot strike; work, desk and
  talk wrists stay near the idle bend; prop.R has no keys (the crate has a fixed offset); a mid key in lie_enter lifts
  the hips.
- Suit polish: AO floor 0.65 on SuitMain and 4 blur passes; pack lenses 3 cm at emissive 4.

**Measured:** `npc_verify` 235 passed, 0 failed, 0 pending (12 for information). RENDER's `npc_check.gd`: PASS, 140
tests, 0 failures. Triangles: suit 6,839, indoor 5,936 (Body 3,356 + heads 584 / 672 / 632 / 692).

**Not done:** sit_eat on the suit (the glove goes to the closed visor). RENDER plays eating only on the indoor variant,
per the critic. No in-game shots (RENDER).

## v3 — 2026-09-24 — critic round 5 polish (suit 0.82, indoor 0.72, animation 0.78)

- Ponytail 30 % thicker (radius 3.8 cm), 4 cm further out, a light `Trim` tie band. Crop: a raised hairline roll.
- Nose: tip 5 mm lower, a rounded bridge.
- Sheet: the skin-tone row now uses head/tone pairs that show all four hair colours with RENDER's rule; tone 5 is shown
  with the warmer value sent to RENDER (0.91, 0.60, 0.42 linear).
- talk: the peak hand at chest height (wrist 1.285 m); the other hand answers.
- New check: the suit visor front in repair_kneel is 9.9 cm from the panel (need ≥ 6 cm), measured on the `Visor` faces.
- `npc_verify` 236 passed, 0 failed, 0 pending. `npc_check.gd` PASS (140 tests, 0 failures). Indoor 5,964 triangles
  (Body 3,356 + heads 588 / 676 / 636 / 708), suit 6,839.

## v3.1 — 2026-09-25 — `suit_swap` clip and visitor looks (V3_1 §5.4, §6.4)

- `suit_swap` (both variants): 60 frames, 2.0 s. Hands go out in front, then to the helmet sides and hold across the
  cut at frame 30. Then the hands go to the chest seals, past the belt, and back to the stand pose. Every key is FK,
  converted from IK designs (`ik_to_fk`), so no IK weight changes and the hold is exactly still. The torso and head
  in the chest key are the same as at the cut, so nothing moves early. Largest step 14.24° per frame. Cut frame:
  identical in both files, 0.26° between frames 29 and 31. `clips.suit_swap.cut_frame = 30`.
- Visitor looks (`tools/blender/npc_visitors.py`): 7 looks (trader, tourist × 3 sets, medical, science, inspector) as
  colour groups on the existing materials, plus one skinned attachment per kind in the new files
  `assets/models/astronaut_visitor_suit.glb` and `astronaut_visitor_indoor.glb` (rig + `Vis_<kind>`, no clips).
  - suit: trader belt and pouches; tourist camera and pennant; medical red crosses; science sensor mast;
    inspector gold crest, badge and cuff rings.
  - indoor: trader grey vest; tourist camera, bag and sunglasses; medical crosses, arm band and stethoscope;
    science white lab jacket; inspector epaulettes, gold cords, badge and peaked cap.
  - The peaked cap was added after the first lineup. The first lineup showed the indoor inspector and the navy/orange
    technician colonist nearly the same at 30 px.
  - Palette and selection rule: `astronaut_anims.json` → `visitors`. Request to RENDER: 2026-09-25 section.
- `npc_verify` new checks:
  - visitor files: meshes, the same skeleton and joint order, COLOR_0, weights;
  - triangles per visitor on screen;
  - the palette table: 5 kinds, 3 tourist sets, groups;
  - the suits differ from each other and from the colonist suit;
  - each attachment stays within 2 cm of the body under it (same main bone) in every clip;
  - no attachment point below z −0.01.
  - The hip pouch was flattened to 2.2 cm; the dead pose had put it 1.4 cm into the ground.
- Sheets: `art/npc/visitors_lineup.png`, `art/npc/visitors_turnaround.png`; all other sheets re-rendered (the suit swap
  is on `transitions.png` and both clip sheets).

**Measured:** `npc_verify` 279 passed, 0 failed, 0 pending, 12 info. `npc_check.gd`: PASS, 140 tests, 0 failures
(no suit_swap tests yet: RENDER's file). `godot.mjs check`: 156 scripts, 0 failed. Triangles per character on screen:
suit 6,951 max, indoor 4,630 max.

**Not done / not tested:** visitors in the game (RENDER: loader, shader modes, look code). The indoor inspector cap
does not fit head 1 (the bun), so RENDER must skip that head. Night readability of the black inspector suit is not
checked. The cut-frame pose is not checked in Godot.

## v3.1 — 2026-09-25 — critic round 12 (visitors 0.76)

1. Indoor tourists: gaiters from below the knee pad over the ankle, and boot covers (the boot upper, 3.5 % larger,
   with weights taken at the unscaled point), in the tour colour. At 30 px they now differ from the scientist.
2. Indoor trader: graphite vest with a hi-vis band and hi-vis shoulder straps.
3. Suit inspector: reflective gold bands on the thighs and shins, and two stripes on the pack (weak emission).
   Crest cut to 6 segments and cuff rings removed, to stay under 7,000 triangles (6,989).
4. Inspector cap: second version `Vis_inspector_h1` with a ring crown round the bun. The rule that RENDER skips
   head 1 is removed. The mesh name suffix `_h<digits>` gives the heads.

`npc_verify` 281 passed, 0 failed. `npc_check.gd` PASS (140 tests, 0 failures). `godot.mjs check` 157 scripts,
0 failed. Sheets re-rendered.

**Not tested:** night rendering in the game; visitors in the game.
