"""Frontier Habitat 5.0 round 2 (coordinator 2026-10-02): floor variety by role, after the room is built.

  work mats   an anti-fatigue mat under every Work anchor (the person stands on it): dark rubber with a hazard edge
              (industry, logistics, life support, distillery) or an accent edge (the rest)
  dance floor a lit checker under the bar's mirror ball, when the centre is free
  wait spots  painted 'WAIT HERE' circles in medical rooms, footprints included

Everything lies flat 4-8 mm over the floor (walkable, no footprint) in the Interior part.
"""
from math import sin, cos, radians

from rooms_kit import T, RZ
from interior_kit import F, plate_z
import interior_props as PR

HAZARD_ROLES = ("industry", "logistics", "life", "distillery")


def work_mats(rm, n, role):
    put = 0
    edge = "Hazard" if role in HAZARD_ROLES else "Accent"
    for (name, pos, yaw) in rm.anchors:
        if not name.startswith("Anchor_Work_"):
            continue
        x, y, z = pos
        if z > F + 0.05:
            continue                                   # on a dais or an upper floor: no mat
        with n.at(T(x, y, 0.0), RZ(yaw)):
            plate_z(n, F + 0.005, -0.38, 0.22, -0.42, 0.42, "Rubber")
            for (x0, x1, y0, y1) in ((-0.38, 0.22, -0.42, -0.38), (-0.38, 0.22, 0.38, 0.42)):
                plate_z(n, F + 0.007, x0, x1, y0, y1, edge)
        put += 1
    return put


def dance_floor(plan, n):
    if plan.dist(0.0, 0.0) < 1.0:
        return 0
    s = 0.36
    for i in range(-2, 2):
        for j in range(-2, 2):
            plate_z(n, F + 0.005, i * s, (i + 1) * s, j * s, (j + 1) * s, "Neon" if (i + j) % 2 else "HullDark")
    return 1


def wait_spots(plan, n):
    rr = 0.5 * (plan.wall_front + plan.r_max)
    put = 0
    for a in (60.0, 240.0):
        x, y = rr * cos(radians(a)), rr * sin(radians(a))
        if plan.dist(x, y) < 0.5:
            continue
        with n.at(T(x, y, 0.0)):
            n.lathe([(0.42, F + 0.006), (0.36, F + 0.006)], "WaterBlue", seg=16, smooth=False, caps=False)
        PR.floor_text(n, "WAIT HERE", x, y, a + 180.0, 0.07, "WaterBlue")
        put += 1
    return put


def floor_detail(rm):
    import interior_roles as RO
    plan = getattr(rm, "plan", None)
    if plan is None or rm.tid in ("corridor", "apartment_block"):
        return 0
    role = RO.role_for(rm)
    n = plan.n
    put = work_mats(rm, n, role)
    if role == "bar":
        put += dance_floor(plan, n)
    if role == "medical":
        put += wait_spots(plan, n)
    if put:
        PR.USED["floor_detail"] = PR.USED.get("floor_detail", 0) + put
    return put
