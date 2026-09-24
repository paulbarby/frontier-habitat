# ART-NPC → ART-HAB

## 2026-09-24 — furniture numbers and the seated suit

**Furniture numbers:** they are in `assets/models/astronaut_anims.json` → `furniture`, the same values as V3_DESIGN §3.3:
seat_z 0.46, seat_back 0.30, bed_z 0.55, bed_back 0.55, console_z 1.0, console_ahead 0.45, bench_z 0.9,
panel_ahead 0.45, panel_z 0.4.
`tools/blender/npc_verify.py` checks the seat contact: in the `sit_idle` rest pose, the lowest body point over the seat is
**0.460 m**.

**Seated suit (astronaut_suit), for your seat design:** the life-support pack sits behind the seat. In the anchor frame
(stand point at the origin, +X = facing), the pack reaches **x = −0.69 m, between z 0.55 m and 1.20 m**. Between z 0.46 and 0.56 m the body
reaches x = −0.38 m (measured). A seat back behind x = −0.38 m that rises more than about 0.08 m above the seat top
cuts into the pack of a suited colonist. Indoor colonists use `astronaut_indoor` (no pack), so this matters
only where suited colonists sit (airlock benches, outdoor seats). I will send the indoor back line when that variant exists.

## 2026-09-24 — full delivery: furniture as the NPC clips use it

Checked by `tools/blender/npc_verify.py` on the exported files (both variants play the same clips):
- **Seat** (top 0.46 m, centre 0.30 m behind the stand point): the lowest body point over the seat is 0.456 m (suit)
  and 0.474 m (indoor). The thighs rest on the seat's front edge. The check treats the front 3 cm of a 0.44 m-deep seat
  as soft (≤ 2 cm press). Suited colonists: nothing is lower than 0.612 m behind x = −0.40 m, so a seat back behind
  x = −0.40 m must stay under about 0.60 m. The seat feet are at x −0.02 m (under the knees).
- **Bed** (mattress top 0.55 m, centre line 0.55 m behind, head to +Y): the indoor sleeper's lowest point is 0.544 m and
  the head is 0.54 m towards +Y from the hips. Getting in and out, the colonist sits on the mattress edge (thighs on
  the front 5 cm, which the check treats as soft) and puts the feet under it, so keep the plinth set 8 cm in from
  the mattress edge, as in your `bed_v3`. The sleeper lies on the left side facing +X (the room side).
- **Console** (top 1.0 m): the hands (wrist to fingertip) span x 0.33–0.52 m ahead of the stand point. **Bench** (top
  0.9 m): x 0.27–0.48 m. **Desk for sit_type and sit_eat** (top 0.74 m): x 0.25–0.44 m; the knees go under the desk
  (knee joint at x 0.16 m, z 0.46 m; the top of the knee about 0.10 m higher). **Panel** (repair_kneel): the hands
  reach x 0.44–0.46 m; the kneeling body spans x −0.61 m (the right foot behind) to +0.46 m, so keep 0.62 m clear
  behind the service anchor.
