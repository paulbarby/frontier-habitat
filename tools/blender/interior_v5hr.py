"""Frontier Habitat 5.0 (docs/V5_DESIGN.md section 17.1) - ART-HAB: the HR office interior, sizes S / M / L.

Stations (section 17.1), with SIM's anchor kinds (Work / Seat / Stand) and named aliases at the same points:
  reception desk     Work_0 = Anchor_Reception_0 (the HR officer, seated, facing the queue); Anchor_Queue_0..2 in
                     front of it (stand points for people queueing, facing the desk; not counted as Stands)
  interview room     low walls (1.30 m) with a door; a small table and two chairs facing each other:
                     Seat_0 = Anchor_Interview_0 (the officer's side), Seat_1 = Anchor_Interview_1 (the visitor)
  feedback kiosk     "WELLBEING.AI" (it answers every complaint with a breathing exercise): Stand_0 = Anchor_Kiosk_0
  filing             filing cabinets on the wall: Stand_1 = Anchor_Filing_0
  M, L               a second / third officer desk (Work_1, Work_2 = Anchor_Desk_1, _2) with a visitor chair (Seat)
  M, L               the suggestion box with a padlock (Stand_2 = Anchor_Suggest_0); L: a water cooler
                     "HYDRATE (MANDATORY)" (Stand_3 = Anchor_Cooler_0)
  waiting chairs     the remaining Seats, beside the queue
Satire (V5 15.3, original names): the wellbeing kiosk, a padlocked suggestion box, a ficus, "SYNERGY" and
"YOUR FEELINGS ARE VALID (PENDING REVIEW)" signs, a "TAKE A NUMBER (ANY NUMBER)" ticket post, tissues on the table.
"""
from math import sin, cos, radians, degrees, atan2

import interior_kit as IK
import interior_furniture as FU
import interior_rooms as IR
import interior_v5 as V5
import interior_props as PR
from rooms_kit import T, RX, RY, RZ, P
from interior_kit import F, Plan, bbox, plate_x, plate_y, plate_z, SEAT_BACK
from interior_families import sit_desk
from interior_v5civ import at, off, anchor, polar, fill, f_plant, _group_table

WALL_H = 1.30


def pwall(plan, A, B, gaps=()):
    """A low partition (1.30 m, like the residences) from A to B; gaps [(t, width)] along it; with V5.PARTTOP the top
    to 2.10 m goes in the PartTop object (waits for RENDER)."""
    n = plan.n
    L = ((B[0] - A[0]) ** 2 + (B[1] - A[1]) ** 2) ** 0.5
    ang = degrees(atan2(B[1] - A[1], B[0] - A[0]))
    cuts = sorted((t - w_ / 2, t + w_ / 2) for t, w_ in gaps)
    pieces, t = [], 0.0
    for c0, c1 in cuts:
        if c0 > t + 0.04:
            pieces.append((t, c0))
        t = max(t, c1)
    if L - t > 0.04:
        pieces.append((t, L))
    with n.at(T(A[0], A[1], 0.0), RZ(ang)):
        for t0, t1 in pieces:
            bbox(n, t0, t1, -0.05, 0.05, F, F + 0.10, "HullDark", mats={"-z": None})
            bbox(n, t0, t1, -0.045, 0.045, F + 0.10, F + WALL_H - 0.04, "Hull", mats={"-z": None, "+z": None})
            bbox(n, t0 - 0.005, t1 + 0.005, -0.06, 0.06, F + WALL_H - 0.04, F + WALL_H, "Frame")
            for sy in (-1, 1):
                plate_y(n, sy * 0.0456, t0 + 0.03, t1 - 0.03, F + 0.92, F + 0.97, "Accent", facing=sy)
        for c0, c1 in cuts:
            for tt in (c0, c1):
                if 0.05 < tt < L - 0.05:
                    bbox(n, tt - 0.035, tt + 0.035, -0.075, 0.075, F, F + WALL_H + 0.05, "Frame", mats={"-z": None})
    if V5.PARTTOP:
        q = V5.part_top(plan)
        with q.at(T(A[0], A[1], 0.0), RZ(ang)):
            for t0, t1 in pieces:
                bbox(q, t0, t1, -0.045, 0.045, F + WALL_H, F + V5.PART_H - 0.03, "Hull", mats={"-z": None, "+z": None})
                bbox(q, t0 - 0.005, t1 + 0.005, -0.06, 0.06, F + V5.PART_H - 0.03, F + V5.PART_H, "Frame",
                     mats={"-z": None})
    ca, sa = cos(radians(ang)), sin(radians(ang))
    for t0, t1 in pieces:
        tm = 0.5 * (t0 + t1)
        plan.rect(A[0] + ca * tm, A[1] + sa * tm, 0.5 * (t1 - t0), 0.07, ang, tag="wall")


def wall_sign(p, lines, w, z0, z1, x=0.0, bg="Fabric", ink="Hull"):
    """A flat sign on the plane x (facing +X), centred on y = 0."""
    bbox(p, x, x + 0.02, -w / 2, w / 2, z0, z1, "Frame")
    plate_x(p, x + 0.021, -w / 2 + 0.02, w / 2 - 0.02, z0 + 0.02, z1 - 0.02, bg)
    h = PR.fit_h(lines, w - 0.10, (z1 - z0 - 0.08) / (1.5 * len(lines)))
    PR.text_lines(p, lines, 0.0, z1 - 0.05, h, ink, x=x + 0.023, gap=0.5)


def kiosk(p):
    """WELLBEING.AI: a tall kiosk, its screen faces +X (the visitor stands at +0.55)."""
    bbox(p, -0.20, 0.20, -0.32, 0.32, F, F + 0.10, "Frame", bevel=0.01)
    bbox(p, -0.12, 0.12, -0.24, 0.24, F + 0.10, F + 1.70, "Hull", bevel=0.03)
    bbox(p, -0.13, 0.13, -0.25, 0.25, F + 1.70, F + 1.86, "Accent", bevel=0.02)
    with p.at(T(0.12, 0.0, F + 1.20), RY(-12.0)):
        bbox(p, 0.0, 0.03, -0.24, 0.24, -0.28, 0.30, "HullDark", bevel=0.006)
        plate_x(p, 0.031, -0.22, 0.22, -0.26, 0.28, "Screen")
        PR.text(p, "HOW ARE YOU?", 0.0, 0.22, 0.036, "Neon", x=0.032)
        PR.text_lines(p, ("1 GREAT", "2 GREAT", "3 OTHER*"), -0.03, 0.14, 0.030, "LightStrip", x=0.032, gap=0.5)
        PR.text(p, "*BREATHE IN", 0.0, -0.20, 0.022, "LightStrip", x=0.032)
    with p.at(T(0.121, 0.0, 0.0)):
        PR.text(p, "WELLBEING.AI", 0.0, F + 1.78, 0.034, "Hull", x=0.012)
    # a breathing-exercise ring that never stops (a lit ring on the column)
    with p.at(T(0.122, 0.0, F + 0.75), RY(90.0)):
        p.torus(0.10, 0.012, "Glow", seg=14, tseg=3)


def suggestion_box(p):
    """A wooden box on a post, the slot on top, a big padlock on the front: 'SUGGESTIONS (LOCKED FOR YOUR SAFETY)'."""
    p.vcyl(0.0, 0.0, F, F + 0.95, 0.04, seg=6, mat="Frame")
    bbox(p, -0.20, 0.20, -0.18, 0.18, F + 0.95, F + 1.30, "Wood", bevel=0.012)
    bbox(p, -0.12, 0.12, -0.012, 0.012, F + 1.299, F + 1.305, "Rubber")
    bbox(p, 0.20, 0.25, -0.07, 0.07, F + 1.02, F + 1.12, "Hazard", bevel=0.01)
    with p.at(T(0.225, 0.0, F + 1.12), RY(90.0)):
        p.torus(0.045, 0.012, "Metal", seg=10, tseg=4)
    plate_x(p, 0.201, -0.17, 0.17, F + 1.15, F + 1.27, "Hull")
    PR.text(p, "SUGGESTIONS", 0.0, F + 1.235, 0.020, "Rubber", x=0.202)
    PR.text(p, "(LOCKED FOR YOUR SAFETY)", 0.0, F + 1.18, 0.012, "Rubber", x=0.202)


def ticket_post(p):
    p.vcyl(0.0, 0.0, F, F + 1.10, 0.03, seg=6, mat="Frame")
    p.vcyl(0.0, 0.0, F, F + 0.03, 0.18, seg=10, mat="Frame")
    bbox(p, -0.08, 0.08, -0.10, 0.10, F + 1.10, F + 1.30, "SignalRed", bevel=0.015)
    plate_x(p, 0.081, -0.09, 0.09, F + 1.12, F + 1.28, "Hull")
    PR.text_lines(p, ("TAKE A", "NUMBER"), 0.0, F + 1.26, 0.026, "Rubber", x=0.082, gap=0.4)
    PR.text(p, "(ANY NUMBER)", 0.0, F + 1.145, 0.012, "Rubber", x=0.082)


def filing_cabinet(p, w=0.45, d=0.55, seed=0):
    """A four-drawer filing cabinet, the drawers face +X (back at x = 0)."""
    bbox(p, 0.0, d, -w / 2, w / 2, F, F + 1.30, ("Hull", "HullDark", "Hull")[seed % 3], bevel=0.01)
    for k in range(4):
        z = F + 0.08 + 0.30 * k
        plate_x(p, d + 0.002, -w / 2 + 0.03, w / 2 - 0.03, z, z + 0.26, "CushionLight" if k == seed % 4 else "Hull")
        bbox(p, d, d + 0.03, -0.07, 0.07, z + 0.17, z + 0.20, "Metal")
        plate_x(p, d + 0.003, -0.06, 0.06, z + 0.06, z + 0.11, "Hazard" if k == 1 else "Hull")


def cooler(p):
    bbox(p, -0.16, 0.16, -0.16, 0.16, F, F + 0.95, "Hull", bevel=0.02)
    p.vcyl(0.0, 0.0, F + 0.95, F + 1.38, 0.13, seg=10, mat="Glass")
    plate_x(p, 0.161, -0.06, 0.06, F + 0.70, F + 0.80, "WaterBlue")
    PR.text_lines(p, ("HYDRATE", "(MANDATORY)"), 0.0, F + 0.62, 0.022, "Rubber", x=0.162, gap=0.4)


def interview_room(plan, cx, cy, W, D, door_y):
    """A room W (x) x D (y) centred at (cx, cy), the door on its +X wall at door_y (local).  Returns the two seat
    anchors' points."""
    n = plan.n
    x0, x1, y0, y1 = cx - W / 2, cx + W / 2, cy - D / 2, cy + D / 2
    pwall(plan, (x1, y0), (x1, y1), gaps=[(door_y + D / 2, 0.90)])
    pwall(plan, (x0, y1), (x1, y1))
    pwall(plan, (x0, y0), (x1, y0))
    # the table and two chairs facing each other along Y
    with n.at(T(cx - 0.15, cy, 0.0)):
        FU.table_round(n, r=0.40, h=0.74, top="Wood", edge="Accent", clutter=False)
        bbox(n, -0.10, 0.10, -0.07, 0.07, F + 0.74, F + 0.84, "Hull")          # tissues
        bbox(n, -0.03, 0.03, -0.02, 0.02, F + 0.84, F + 0.88, "Hull")
        plate_x(n, 0.101, -0.06, 0.06, F + 0.76, F + 0.82, "WaterBlue")
    plan.circle(cx - 0.15, cy, 0.42, tag="table")
    seats = []
    for sy, alias in ((-1, "Interview_0"), (1, "Interview_1")):
        x_, y_ = cx - 0.15, cy + sy * 0.78
        yaw = 90.0 if sy < 0 else -90.0
        with at(plan, x_, y_, yaw):
            FU.chair(n, seat=("Fabric", "CushionLight")[sy > 0])
        plan.rect(x_, y_, 0.24, 0.24, yaw, tag="seat")
        seats.append((x_, y_, yaw, alias))
    # the inner sign on the -Y wall, facing +Y (into the room)
    with n.at(T(cx - 0.15, y0 + 0.06, 0.0), RZ(90.0)):
        wall_sign(n, ("YOUR FEELINGS", "ARE VALID", "(PENDING REVIEW)"), 1.0, F + 0.95, F + 1.26, bg="CushionLight",
                  ink="Rubber")
    # the door sign outside
    with n.at(T(x1 + 0.06, cy - D / 2 + 0.35, 0.0)):
        wall_sign(n, ("INTERVIEW", "ROOM 1"), 0.42, F + 0.98, F + 1.24, bg="Accent", ink="Hull")
    return seats


def hr_office(rm):
    s = rm.size
    fu = IK.furniture_of(rm)
    plan = Plan(rm)
    IK.build_floor_v3(rm, "panel", "radial", ring_step=1.30, radial=16, edge_band=0.64, inner_disc=1.25)
    n = plan.n
    R = plan.r_max
    # the reception desk (Work_0): the officer at -X faces the queue at +X
    rx = 0.33 * R
    sit_desk(plan, rx, 0.0, 180.0, w=1.5, monitors=1, seed=3)
    a = rm.anchors[-1]
    rm.anchor("Reception_0", a[1], a[2])
    with n.at(T(rx + 0.15, 0.55, F + 0.74)):                       # stress balls (a pyramid of three)
        for (bx, by, bz) in ((0.0, -0.05, 0.035), (0.0, 0.05, 0.035), (0.0, 0.0, 0.095)):
            n.sphere((bx, by, bz), 0.035, ("Fabric", "Hazard", "Plant")[int(bz > 0.05) + int(by > 0)], seg=6, rings=3)
    PR.desk_plate(n, rx + 0.50, -0.38, F + 0.74, "CHIEF PEOPLE OFFICER")
    # the queue: floor marks and three stand points facing the desk
    qx0 = rx + 1.05
    nq = 3 if R > 4.8 else 2
    for k in range(nq):
        qx = qx0 + 0.65 * k
        rm.anchor("Queue_%d" % k, (qx, 0.0, F), 180.0)
        with n.at(T(qx, 0.0, 0.0)):
            n.lathe([(0.22, F + 0.006), (0.17, F + 0.006)], "Hazard", seg=12, smooth=False, caps=False)
    PR.floor_text(n, "PLEASE QUEUE (EMOTIONALLY)", qx0 + 0.65 * (nq - 1) / 2, -0.42, 180.0, 0.07, "Rubber")
    with at(plan, qx0 - 0.2, 0.55, 180.0):
        ticket_post(n)
    plan.circle(qx0 - 0.2, 0.55, 0.20, tag="post")
    # the ficus by the desk
    FU.tall_plant(n, rx - 0.35, -1.25, seed=7)
    plan.circle(rx - 0.35, -1.25, 0.30, tag="plant")
    # the interview room on the -X side
    W, D = (2.4, 2.4) if R < 6.5 else (2.8, 2.8)
    icx = -(R - W / 2 - 0.15)
    seats = interview_room(plan, icx, 0.0, W, D, 0.55)
    nseat = 0
    for (x_, y_, yaw, alias) in seats:
        anchor(plan, "Seat", x_, y_, yaw, lx=SEAT_BACK, alias=alias)
        nseat += 1
    # the feedback kiosk (Stand_0) and filing (Stand_1)
    kx, ky = 0.10 * R, -0.52 * R
    with at(plan, kx, ky, 90.0):
        kiosk(n)
    plan.rect(kx, ky, 0.32, 0.22, 90.0, tag="kiosk")
    plan.anchor("Stand", kx, ky + 0.65, -90.0)
    rm.anchor("Kiosk_0", (kx, ky + 0.65, F), -90.0)
    nst = 1
    fa = 245.0 if R < 6.5 else 255.0
    for j in range(2 if R < 6.5 else 3):
        a_ = fa + j * (9.0 if R < 6.5 else 7.0)
        x, y = polar(R - 0.05, a_)
        with at(plan, x, y, a_ + 180.0):
            filing_cabinet(n, seed=j)
        plan.rect(*off(x, y, a_ + 180.0, 0.28), 0.28, 0.25, a_ + 180.0, tag="filing")
    x, y = polar(R - 0.05, fa + (4.5 if R < 6.5 else 7.0))
    anchor(plan, "Stand", x, y, fa + 4.5, lx=-(0.55 + 0.45), alias="Filing_0")
    nst += 1
    # M, L: officer desks with a visitor chair
    nwork = 1
    for j, (dx, dy, yaw) in enumerate(((-0.12 * R, 0.55 * R, 90.0), (-0.20 * R, -0.62 * R, -90.0))):
        if nwork >= fu["work_slots"]:
            break
        sit_desk(plan, dx, dy, yaw, w=1.2, monitors=2, seed=10 + j)
        a = rm.anchors[-1]
        rm.anchor("Desk_%d" % (j + 1), a[1], a[2])
        nwork += 1
        if nseat < fu["seats"]:
            vx, vy = off(dx, dy, yaw, -1.05)
            with at(plan, vx, vy, yaw):
                FU.chair(n, seat="CushionLight")
            plan.rect(vx, vy, 0.24, 0.24, yaw, tag="seat")
            anchor(plan, "Seat", vx, vy, yaw, lx=SEAT_BACK)
            nseat += 1
    # M, L: the suggestion box; L: the water cooler
    extras = [((0.36 * R, -0.42 * R), suggestion_box, "Suggest_0", 0.0), ((0.30 * R, 0.52 * R), cooler, "Cooler_0", 180.0)]
    for (ex, ey), fn, alias, yaw in extras:
        if nst >= fu["stands"]:
            break
        with at(plan, ex, ey, yaw):
            fn(n)
        plan.circle(ex, ey, 0.26, tag="stand")
        sx_, sy_ = off(ex, ey, yaw, 0.62)               # in front of it, facing it
        plan.anchor("Stand", sx_, sy_, yaw + 180.0)
        rm.anchor(alias, (sx_, sy_, F), yaw + 180.0)
        nst += 1
    # the waiting chairs beside the queue (the remaining Seats), facing the desk side
    k = 0
    while nseat < fu["seats"]:
        wx, wy = qx0 + 0.55 * k - 0.1, -1.05
        with at(plan, wx, wy, 90.0):
            FU.chair(n, seat=("Fabric", "Accent", "CushionLight")[k % 3])
        plan.rect(wx, wy, 0.24, 0.24, 90.0, tag="seat")
        anchor(plan, "Seat", wx, wy, 90.0, lx=SEAT_BACK)
        nseat += 1
        k += 1
    pattern = ["cab_plant", "r_synergy", "aiposter", "cab_books", "r_feelings", "notice", "planter", "r_survey"]
    plan.wall_items(pattern, IR.wall_set(plan), open_every=3, seed=17 + s, depth_of=IR.DEPTHS)
    fill(plan, [(lambda p_, x, y, k_: _group_table(p_, x, y, k_), 1.1), (f_plant, 0.25)], target=1.9, max_items=40)
    plan.lights()
    plan.aisles()
    plan.v4_patch = IR.empty_patch(plan)[0]


INTERIORS = {"hr_office": hr_office}
