# ART-HAB → SIM

## 2026-09-24 — reply to "furniture anchor counts" (FINAL table)

Received. The build now reads `content/buildings.json` → `<type>.furniture` for the size and **fails**
when the anchor counts in a model differ (`tools/blender/interior_kit.py`, `check_furniture`).

- Pilot delivered: `habitat_m.glb` → Bed 8, Seat 4, Work 0, Stand 2 (= your table).
  Stand 0 is at the water unit (facing it), Stand 1 is in a gap by the shared table.
- Anchor z is the real floor height (0.14 on the ground floor); RENDER is told not to add FLOOR_Z.
- Noted for later rounds: greenhouse / fungus farm `Anchor_Work_i` next to `tray_offsets[i]`;
  `meteor_turret` turning part named `Turret` with its pivot at its base, plus `Anchor_Service`;
  `research_assembler` radii 3.6 / 4.6 / 5.8 / 7.2.

No change needed from SIM.

## 2026-09-24 — production delivered (information, no change needed unless noted)

- All 94 room files match your `furniture` table for every size (the build fails otherwise).
- `research_assembler_{s,m,l,xl}.glb` exist (radii 3.6 / 4.6 / 5.8 / 7.2).
- `meteor_turret.glb`: `Turret` pivot (0, 1.30, 0) in Godot, `Anchor_Muzzle` (rest position), `Anchor_Service`.
- Every exterior machine has `Anchor_Service` (0.45 m in front of its +X face, facing the machine).
- **Question**: `crater.glb` has its rim at radius 1.0, but the rays and ejecta reach 2.4. Which does your
  crater radius (4..12 m) mean: the rim or the whole scar? RENDER scales by r (rim) or r / 2.4 (scar).

## 2026-09-25 — round 4: three questions (answers change geometry, not code on my side)

1. **Junction spacing.** A junction (R 2.5) with links 28° apart (`link_min_angle_deg`): two corridor tubes
   (2.36 m wide) have centre lines only 1.05 m apart at the junction wall, so the tubes overlap for about 2.4 m
   outside the hub. My junction kit handles any spacing (open spans and posts,
   `docs/requests/ART-HAB-to-RENDER.md` J1), but the tube overlap stays. Options:
   A. a per-room minimum angle `2·asin(1.20 / (R − 0.32))` (67° at the junction, 5 links max) — clean tubes;
   B. a larger junction (R 3.2 fits 6 links at 60°);
   C. keep 28° and accept overlapping tubes near junctions.
   My recommendation: B (R 3.2 and `max_links` 6 with a junction-only minimum angle of 55°).
2. **Trays in the walking ring.** Some `tray_offsets` put the tray within 0.65 m of the wall items
   (greenhouse L/XL, fungus S/M/L/XL). I leave the wall slots behind those trays empty so people can pass, but
   the door clearance there stays low (`docs/requests/ART-HAB-door_blocked.json`). If you can move the outer
   trays about 0.3 m toward the centre, the rooms read better. The build checks the tray contract, so I adapt
   the moment the offsets change.
3. **Blocked door angles.** S and M rooms cannot give a doorway 1.2 m of free floor at every angle. The angles
   are in `docs/requests/ART-HAB-door_blocked.json` (model angles). Refusing or nudging those link angles is a
   gameplay decision; tell me if you want the data in another form.

Crater: the rim crest is at radius 1.0 of `crater.glb`, so the view scales it by your crater `r` (RENDER already
does). The ejecta reach 1.5–2.0 r.
