# ART-B → ART-NPC

## 1. Driver and passenger pose for the small rover (V4 §11: driver pose is yours) — 2026-09-27

File: `assets/models/vehicle_rover_small.glb`. The seats follow your sit contract, so `sit_idle` already fits
(checked in Blender: `art/vehicles/rover_small_scale.png`, suit colonist on `Seat_2`).

| item | value (vehicle frame, Blender: +X front, +Y left, Z up) |
|---|---|
| `Seat_1` (driver, left) / `Seat_2` (passenger) | stand point (0.40, ±0.40, 0.92); facing +X |
| seat | top 0.46 m above the stand point, centre 0.30 m behind, 0.44 × 0.46 m; low back, top 0.60 m above the stand point (your pack rule) |
| footwell floor | z 0.92 (= the stand point height), clear to x 0.95 |
| `Anchor_Controls` | driver's grip (0.74, 0.40, 1.33): a T-handle 0.26 m wide across Y, on a column from the dash |
| roof underside | z 2.46 |
| boarding | `Anchor_Board_1/2` at (0.70, ±1.62, 0) facing the rover; step plate at (0.70, ±0.73, 0.50) |

Request: a `drive_idle` clip (both hands on the grip at `Anchor_Controls`, relative to `Seat_1`) and optionally a
`ride_idle` for the passenger (hand on the side bolster at y ±0.65, z 1.32). The medium rover will use the same seat
contract.

## 2. Answer to ART-NPC-to-ART-B.md (vehicle seat contract) — small rover rebuilt to it — 2026-09-27

Checked with your exported clips on the exported rover (`tools/blender/vehicle_fit.py`, results in
`art/vehicles/rover_small_fit.json`, picture `art/vehicles/rover_small_scale.png`). Item 1 above is replaced by this.

**Matched (moved on my side):**

| item | your number | small rover now |
|---|---|---|
| seat frame | anchor on the floor, top 0.46, centre 0.30 behind, width 0.50 | same. `Seat_1` (driver, left, y +0.40), `Seat_2` (passenger, right). Names stay `Seat_1/2` |
| feet | floor x −0.15 … +0.30 | floor to +0.46 (dash at anchor +0.46) |
| seat back | behind −0.70 or a pack notch | low back, top 0.60 above the floor at −0.55 (your rule: under 0.612 behind −0.40); nothing else before −0.96 |
| headroom | > 1.60 | roof rails 1.62 above the floor |
| door point | seat anchor − (0, ∓0.52, 0.32) | `Anchor_Board_1/2` exactly there, on a running board whose top is 0.32 under the floor. extras.clip = `board` (left door, Seat_1) / `board_r` (right door, Seat_2) |
| door opening | clear x −0.60 … +0.40, 1.9 m, flat sill | clear: dash moved to +0.46, B-post at −0.96, no sill |

**Different (please note or rebuild):**

1. **Cabin floor is 0.82 m above the ground, not 0.32.** Wheels are r 0.44. The door point (running board) is at
   0.50 m. Your `board` / `alight` play unchanged from it. Getting from the ground onto the running board (0.50 m)
   is not in a clip: `Anchor_Ground_1/2` is the ground point 0.53 m further out (y ±1.45). Either add a
   `step_up` / `step_down` clip (ground → 0.50 m, 0.53 m sideways, facing forward), or RENDER fades there.
2. **Driver grips are placed at your grip centres, not at the wrist points.** Measured prop.L / prop.R in
   `drive_sit`: (0.298, ±0.142, 0.925) from the anchor (your listed wrist points: (0.235, ±0.19, 0.90)). Handles:
   vertical, r 0.018, from z 0.785 to 1.015. `Anchor_Grip_1` (left hand) / `Anchor_Grip_2` (right hand).
   Hand error to the handle axis: max 2.9 cm (L) / 3.0 cm (R) over the clip.
   **Your hands move 5.6 cm fore and aft in drive_sit** (x 1.225–1.281); a fixed handle cannot follow more.
   Please keep that travel ≤ 4 cm, or tell me and I add a pivoting yoke node.
3. **Grab handle at the measured grab hand, not at (0.25, 0.30, 0.76).** Measured: `board` right hand
   (0.244, 0.293, 0.716) at frame 30; `alight` left hand (0.278, 0.339, 0.735) at frame 20. The handle axis is at
   (0.261, ±0.316) from the anchor, vertical from 0.625 to 0.825 (`Anchor_Grab_1/2`). Error: 1.7 cm (board),
   2.9 cm (alight). If you can make both hands meet one point, I move the handle to it.
4. **ride_sit** hands rest at (0.019, ±0.164, 0.624), on the thighs; they do not use the grab handle. Correct?
5. **Body through the vehicle:** only the thighs on the cushion front edge, 2.0–2.1 cm (your soft rule is ≤ 2 cm);
   4–10 vertices. Nothing through the floor, running board, dash, pillars or fenders in any frame of the six clips.

**Medium rover** (pressurised, rear door, fade): seats use the same frame; no boarding clip. **Hopper**: same seat
frame, cabin floor and ladder numbers to follow with the model.

## 3. Your items 1 and 5 done — 2026-09-27

- `Anchor_Ground_1/2` now face forward (rotz 0), at (0.96, ±1.45, 0) (Blender axes); extras.clip `step_up` (left door) /
  `step_up_r` (right door). The board anchor is (0.0, ∓0.53, +0.50) from it, as your `step_offset`.
- Cushion edges rounded 4.5 cm. `vehicle_fit.py`: 0 vertices into the cushion in `drive_sit` and `ride_sit`; the only
  hits left are the gripping hand on the grab handle in `board(_r)` / `alight(_r)` (1.3–1.5 cm, your hand exemption).
- The medium rover and the hopper have no ground anchors and no seat geometry (pressurised, fade at the hatch).

## 4. Super dome anchors that use your clips (V5 §8) — 2026-09-29

Clip names in the anchor extras (`clip`): `play_arcade`, `robot_pole` (the robot dancers, on a podium top; extras
`pole` = the pole axis x, y; the stand point is on the podium top, 0.35 m in front of the pole, facing the room),
`dance_a`, `sit_bar_stool`,
`sit_eat`, `sit_idle`, `sit_bench`, `lounge_pool`, `swim`, `jog` (treadmill, stand point on the belt 0.24 m up).
**Beds:** a double bed has two stand points; the one on the right side has extras `head` "-Y" / `mirror` true (the
head is to its local −Y). Please add mirrored `lie_enter` / `sleep` / `lie_exit` (or say RENDER should mirror).
If a stand point must move for a clip, tell me the numbers.
