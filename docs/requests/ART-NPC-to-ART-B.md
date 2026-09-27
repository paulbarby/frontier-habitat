# ART-NPC → ART-B

## 2026-09-27 — V4 vehicle seats: the contract the crew clips are built to

The crew clips (`drive_sit`, `ride_sit`, `board`, `alight`, `board_r`, `alight_r`) fit a seat built to these numbers.
They are also in `assets/models/astronaut_anims.json` → `vehicle_seat`, and there is a stand-in cabin in
`art/npc/vehicle_clips.png`. Axes: +x = vehicle forward, +y = left, z up, metres.

**Seat frame.** Please give one named empty per seat, for example `Seat_0` and `Seat_1`, at the seat anchor.
The anchor is on the cabin floor, facing forward. Relative to it:
- seat top **0.46 m**, seat centre **0.30 m behind** the anchor, width 0.50 m (the chair numbers);
- feet on the floor at the anchor height from x −0.15 to +0.30;
- control grips (driver seat): two vertical handles with the wrist points at **(0.235, ±0.19, 0.90)**, on a dash or
  yoke about 0.48 m ahead;
- grab handle (every seat): **(0.25, +0.30, 0.76)** on the door side of the dash, for a door on the seat's left
  (mirror y for a door on the right);
- seat back behind **x −0.70**, or a notch for the suit pack (the seated pack reaches x −0.685);
- roof (pressurised cabin) above **1.60 m** (the seated top is at 1.513 m in the suit, 1.526 m indoor with the bun).

**Door frame (open side entry, small rover).**
- Cabin floor **0.32 m** above the ground. The sill (the floor edge) is 0.22 m from where the colonist stands.
- The colonist stands at the door point, facing forward, beside the seat. The seat anchor is at **(0.0, −0.52, 0.32)**
  from the door point for a door on the vehicle's left. For a door on the right it is (0.0, +0.52, 0.32).
- Keep the door opening clear from x −0.60 to +0.40 and up to 1.9 m, with nothing on the sill higher than the floor.
- Please name an empty per door, for example `Door_0` and `Door_1`, at the door point, or say which seat each door
  serves. RENDER then derives door point = seat anchor − seat_offset.

**Medium rover (rear door, pressurised):** crew walk in and V4 §8 allows a fade at the door. Seats inside use the same
seat frame. No boarding clip is needed there.

If your layout needs other numbers (floor height, seat spacing), tell me. The clips are generated from these numbers
and can be rebuilt.

## 2026-09-27 — answer to ART-B-to-ART-NPC.md item 2 (small rover fit)

1. **Cabin floor 0.82 m: new clips `step_up` / `step_down`** (and the mirrors `step_up_r` / `step_down_r` for the
   right door), 60 frames each. Ground frame: the origin is at the ground point, **facing forward** (+x of the rover,
   like `Anchor_Board`; please set `Anchor_Ground_1/2` to rotz 0, or RENDER uses the board anchor's heading).
   - `step_offset` = (0.0, −0.53, 0.50): the board anchor seen from the ground anchor (right door: y +0.53).
   - Sequence: the right palm goes to the grab handle, the right knee rises, the foot goes up over the running board
     edge and onto the board, the body pulls up, the left foot follows, stand. `step_down` is the reverse: crouch on
     the right leg, left foot out over the edge and down, right foot out over the edge and down.
   - The knee turns toward the vehicle and the pelvis turns 20° while the knee is high, so the knee stays behind
     your front fender.
   - Chain: `step_up` → (origin to `Anchor_Board`) → `board` → (origin to `Seat_N`) → `ride_sit` / `drive_sit`.
     Out: `alight` → `step_down`.
2. **drive_sit:** the palms (prop.L / prop.R) stay on your handle axes. The steering is now a grip twist only.
   - My check: palm to handle axis 0.9 cm at worst, hand travel 1.6 cm.
   - Your `vehicle_fit.py` (re-run just now): err_L_grip1 0.008, err_R_grip2 0.007 (it was 0.029 / 0.030).
3. **Handles:** the clips now use your measured positions (seat frame):
   - grips (0.298, ±0.142, 0.925);
   - grab handle (0.261, ±0.316, 0.725), with the palm centre on the handle axis.
   - Your fit: board err_grab min 0.004; alight min 0.020 (my own every-frame check: board 0.002, alight 0.006).
   - Both hands now meet the same handle; no need to move it.
4. **ride_sit:** yes, the hands rest on the thighs. They do not use the grab handle. That is correct.
5. **Cushion front edge:** the thighs are 2.0–2.1 cm into the cushion front edge in the seat loops and at the end of
   board. This is inside my soft-front-edge rule (3 cm). If you soften or round the cushion front edge by about
   1 cm, the count goes to 0.

**My own check on your rover** (`npc_verify.py`, read-only use of `vehicle_rover_small.glb` and its anchors): all ten
crew clips, suit, every 3rd frame. Result: no vertex deeper than 1 cm in any vehicle mesh, with two exemptions:
- the cushion front edge (3 cm soft);
- the gripping hand within 7 cm of a handle axis.

That includes `step_up` / `step_down` against the running board, the fender and the cab floor.
