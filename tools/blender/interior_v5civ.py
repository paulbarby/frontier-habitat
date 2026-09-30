"""Frontier Habitat 5.0 - ART-HAB: interiors of the civic modules (docs/V5_DESIGN.md section 7).

retail           counter with till(s) (Work), gondola shelves and clothes rails (browse points = Stand), display
                 tables, a fitting booth (L); aliases Anchor_Counter (= Work_0), Anchor_Browse_<i> (= Stand_<i>)
park             lawn, a gravel jogging loop and cross paths, trees, flower beds, benches (Seat, 2 per bench),
                 lamp posts, a pond with a fountain (L, XL), a wedding arch (L, XL); Anchor_Jog_<i> round the loop,
                 Anchor_Wedding
academy          student desks in rows facing the teacher board (Seat = Anchor_Class_<i>), the teacher's desk
                 (Work_0 = Anchor_Teach), instructor consoles (Work_1.. = Anchor_Console_<i>), shelves, a reading rug
security_office  front desk (Work_0 = Anchor_Desk_0), monitor console (Work_1 = Anchor_Desk_1), lockers
                 (Stand = Anchor_Locker_<i>), a briefing table (Seat), a holding bench, an equipment rack
jail             cells with bars, a bunk, WC and basin each (Anchor_Cell_<i> = Anchor_Bed_<i> beside the bunk, the bed
                 convention),
                 the guard desk (Work_0 = Anchor_Guard), a visiting table (Seat), a yard at L (Anchor_Yard_<i> =
                 the yard Stands)
Anchor counts follow content/buildings.json `furniture` (checked by rooms_build.py).
"""
import random
from math import sin, cos, radians, degrees, hypot, sqrt, atan2, pi

import rooms_kit as K
import interior_kit as IK
import interior_furniture as FU
import interior_rooms as IR
import interior_v5 as V5
from rooms_kit import T, RX, RY, RZ, FLOOR_Z, WALL_TOP
from interior_kit import F, Plan, bbox, plate_x, plate_y, plate_z, SEAT_BACK, BED_BACK, BED_Z, BENCH_Z, CONSOLE_AHEAD


def at(plan, x, y, yaw):
    return plan.n.at(T(x, y, 0.0), RZ(yaw))


def off(x, y, yaw, lx, ly=0.0):
    c, s = cos(radians(yaw)), sin(radians(yaw))
    return x + c * lx - s * ly, y + s * lx + c * ly


def anchor(plan, kind, x, y, yaw, lx=0.0, ly=0.0, alias=None):
    ax, ay = off(x, y, yaw, lx, ly)
    plan.anchor(kind, ax, ay, yaw)
    if alias:
        plan.rm.anchor(alias, (ax, ay, F), yaw)


def polar(r, a):
    return r * cos(radians(a)), r * sin(radians(a))


def fill(plan, items, max_items=60, target=2.45):
    """Greedy filler: while the largest empty patch is wider than `target`, put the biggest item that fits
    (0.3 m clear round it) at its centre.  items: [(fn(plan, x, y, k), radius)]."""
    rm = plan.rm
    people = [a[1][:2] for a in rm.anchors if a[0].startswith(("Anchor_Bed", "Anchor_Seat", "Anchor_Work",
                                                               "Anchor_Stand", "Anchor_Cell"))]
    k = 0
    for _ in range(max_items):
        patch, where = IR.empty_patch(plan, people=people)
        if patch <= target or where is None:
            break
        dp = min([hypot(where[0] - px, where[1] - py) for px, py in people] or [99.0])
        fit = [it for it in items if it[1] <= patch / 2.0 - 0.3 and it[1] + 0.45 <= dp]
        if not fit:
            break
        fit.sort(key=lambda it: -it[1])
        fn, r = fit[k % min(len(fit), 3)]
        fn(plan, where[0], where[1], k)
        plan.circle(where[0], where[1], r, tag="fill")
        k += 1
    return IR.empty_patch(plan, people=people)


def f_plant(plan, x, y, k):
    FU.pot_plant(plan.n, x, y, r=0.22, h=0.44, s=1.0, seed=k)


def f_tall(plan, x, y, k):
    FU.tall_plant(plan.n, x, y, seed=k + 5)


def _crates(plan, x, y, k):
    """Gear crates, stacked."""
    FU.crate(plan.n, x - 0.18, y, s=0.5, mat="HullDark", band="Accent", yaw=15.0 * k)
    FU.crate(plan.n, x + 0.22, y + 0.1, s=0.42, mat="Hull", band="Frame", yaw=-10.0 * k)
    FU.crate(plan.n, x - 0.1, y, s=0.36, z=F + 0.5, mat="Cargo", band="Frame", yaw=5.0 * k)


def _day_table(plan, x, y, k):
    """A round steel table with three fixed stools (the jail's day room)."""
    n = plan.n
    with n.at(T(x, y, 0.0)):
        FU.table_round(n, r=0.42, h=0.74, top="Metal", edge="Frame")
    for j in range(3):
        a = 120.0 * j + 30.0 * k
        with n.at(T(x + 0.72 * cos(radians(a)), y + 0.72 * sin(radians(a)), 0.0)):
            FU.stool(n, seat="HullDark")


def f_bench(plan, x, y, k):
    with at(plan, x, y, degrees(atan2(y, x)) + 180.0):
        V5.bench(plan.n, L=1.2)


# --------------------------------------------------------------------------------------
# RETAIL
# --------------------------------------------------------------------------------------
GOODS = ("Accent", "Fabric", "Cushion", "CushionLight", "Hull", "Glow", "Wood", "HullDark")


def gondola(p, L=2.2, h=1.30, seed=0):
    """A double-sided shop shelf along local Y (length L), goods on both faces (+X and -X)."""
    rng = random.Random(seed)
    bbox(p, -0.30, 0.30, -L / 2, L / 2, F, F + 0.10, "HullDark", mats={"-z": None})
    bbox(p, -0.03, 0.03, -L / 2, L / 2, F + 0.10, F + h, "Hull")
    for sy in (-1, 1):
        bbox(p, -0.32, 0.32, sy * L / 2 - 0.03, sy * L / 2 + 0.03, F, F + h + 0.04, "Frame", mats={"-z": None})
    bbox(p, -0.30, 0.30, -L / 2, L / 2, F + h, F + h + 0.04, "Accent")
    for zi, z in enumerate((F + 0.14, F + 0.52, F + 0.90)):
        bbox(p, -0.29, 0.29, -L / 2 + 0.03, L / 2 - 0.03, z - 0.02, z, "Frame")
        for sx in (-1, 1):
            y = -L / 2 + 0.08
            while y < L / 2 - 0.16:
                w = rng.uniform(0.08, 0.20)
                hh = rng.uniform(0.12, 0.30)
                if rng.random() < 0.85:
                    x0, x1 = (0.05, 0.27) if sx > 0 else (-0.27, -0.05)
                    bbox(p, x0, x1, y, min(L / 2 - 0.06, y + w), z, z + hh, rng.choice(GOODS))
                y += w + 0.025


def clothes_rail(p, L=1.6, seed=0):
    """A clothes rail along local Y with hanging garments."""
    rng = random.Random(seed)
    for sy in (-1, 1):
        p.vcyl(0.0, sy * L / 2, F, F + 1.45, 0.025, seg=6, mat="Metal", cap0=False)
        bbox(p, -0.25, 0.25, sy * L / 2 - 0.03, sy * L / 2 + 0.03, F, F + 0.04, "Frame", mats={"-z": None})
    p.cyl((0.0, -L / 2, F + 1.45), (0.0, L / 2, F + 1.45), 0.018, seg=6, mat="Metal")
    y = -L / 2 + 0.1
    while y < L / 2 - 0.1:
        c = rng.choice(("Fabric", "Accent", "Cushion", "CushionLight", "Hull", "Glow"))
        ln = rng.uniform(0.55, 0.95)
        bbox(p, -0.24, 0.24, y, y + 0.05, F + 1.42 - ln, F + 1.40, c)
        y += 0.09


def shop_counter(p, w=1.8, seed=0):
    """Shop counter: the customer side faces +X (front at x = 0.30), the keeper stands at x = -0.75 facing +X.
    A till screen, a card reader, a small gift display."""
    zt = F + 1.00
    bbox(p, -0.30, 0.30, -w / 2, w / 2, F, zt - 0.04, "Hull", bevel=0.015)
    plate_x(p, 0.301, -w / 2 + 0.05, w / 2 - 0.05, F + 0.12, zt - 0.10, "Accent")
    plate_x(p, 0.302, -w / 2 + 0.05, w / 2 - 0.05, zt - 0.20, zt - 0.17, "LightStrip")
    bbox(p, -0.34, 0.34, -w / 2 - 0.02, w / 2 + 0.02, zt - 0.04, zt, "Wood", bevel=0.01)
    with p.at(T(-0.05, -w / 4, zt), RZ(180.0)):
        bbox(p, -0.08, 0.08, -0.06, 0.06, 0.0, 0.02, "Frame")
        bbox(p, -0.02, 0.02, -0.02, 0.02, 0.02, 0.22, "Frame")
        with p.at(T(0.0, 0.0, 0.34), RY(-15.0)):
            IK.ui_screen(p, 0.36, 0.24, seed=seed)
    bbox(p, 0.08, 0.20, 0.05, 0.15, zt, zt + 0.05, "HullDark")
    rng = random.Random(seed)
    for k in range(4):
        y = w / 4 - 0.25 + 0.14 * k
        bbox(p, -0.1, 0.1, y, y + 0.1, zt, zt + rng.uniform(0.08, 0.18), rng.choice(("Accent", "Fabric", "Glow")))


def display_table(p, r=0.55, seed=0):
    """A round display table with gadgets (small boxes with screens) and gift boxes."""
    FU.table_round(p, r=r, h=0.80, top="Hull", edge="Accent")
    rng = random.Random(seed)
    for k in range(5):
        a = 72.0 * k + rng.uniform(-10, 10)
        x, y = 0.32 * r * 1.4 * cos(radians(a)), 0.32 * r * 1.4 * sin(radians(a))
        with p.at(T(x, y, F + 0.80), RZ(a)):
            if k % 2:
                bbox(p, -0.08, 0.08, -0.05, 0.05, 0.0, 0.015, "HullDark")
                plate_z(p, 0.016, -0.07, 0.07, -0.04, 0.04, "Screen")
            else:
                bbox(p, -0.07, 0.07, -0.07, 0.07, 0.0, 0.12, rng.choice(("Accent", "Fabric", "CushionLight")))
                bbox(p, -0.075, 0.075, -0.012, 0.012, 0.0, 0.125, "Hull")


def pie_floor(plan, r, a0, a1, mat, z=F + 0.004, step=10.0):
    """A floor zone: the sector a0..a1 (deg) of the disc r, as a fan."""
    n = plan.n
    k = max(1, int((a1 - a0) / step + 0.999))
    c = n.v((0.0, 0.0, z))
    pts = [n.v((r * cos(radians(a0 + (a1 - a0) * i / k)), r * sin(radians(a0 + (a1 - a0) * i / k)), z))
           for i in range(k + 1)]
    for i in range(k):
        n.f([c, pts[i], pts[i + 1]], mat)


def mannequin(p, col="Fabric"):
    p.vcyl(0, 0, F, F + 0.03, 0.18, seg=10, mat="Frame", cap0=False)
    p.vcyl(0, 0, F + 0.03, F + 0.95, 0.02, seg=6, mat="Metal", cap0=False)
    p.lathe([(0.10, F + 0.85), (0.17, F + 1.05), (0.19, F + 1.35), (0.14, F + 1.52), (0.06, F + 1.56),
             (0.0, F + 1.56)], col, seg=10, smooth=True)
    p.sphere((0, 0, F + 1.68), 0.09, "Hull", seg=8, rings=4)


def retail(rm):
    s = rm.size
    fu = IK.furniture_of(rm)
    plan = Plan(rm)
    IK.build_floor_v3(rm, "clean", "grid", grid=1.0)
    n = plan.n
    R = plan.r_max
    # the sections: clothes (+Y), snacks (-Y, right), gadgets (+X), gifts by the till (-X)
    pie_floor(plan, R, 30.0, 150.0, "CushionLight")
    pie_floor(plan, R, 210.0, 330.0, "Floor")
    pie_floor(plan, R, -30.0, 30.0, "Wood")
    FU.rug_round(n, 1.1 + 0.2 * s, 0.0, 0.0, mat="RugLight", ring="Accent", seg=24)
    # the till counter at -X, the keeper(s) behind; a queue line of two posts and a belt
    cx = -(R - 0.95)
    cw = 1.6 + 0.3 * s
    with at(plan, cx, 0.0, 0.0):
        shop_counter(n, w=cw, seed=s)
    plan.rect(cx, 0.0, 0.34, cw / 2 + 0.02, 0.0, tag="counter")
    anchor(plan, "Work", cx, -cw / 4, 0.0, lx=-0.75, alias="Counter")
    for w_ in range(1, fu["work_slots"]):
        anchor(plan, "Work", cx, cw / 4, 0.0, lx=-0.75)
    for yq in (-cw / 2 - 0.2, cw / 2 + 0.2):
        n.vcyl(cx + 1.2, yq, F, F + 0.95, 0.03, seg=6, mat="Metal", cap0=False)
        n.vcyl(cx + 1.2, yq, F, F + 0.03, 0.14, seg=8, mat="Frame", cap0=False)
    n.cyl((cx + 1.2, -cw / 2 - 0.2, F + 0.90), (cx + 1.2, cw / 2 + 0.2, F + 0.90), 0.02, seg=4, mat="Accent")
    plan.rect(cx + 1.2, 0.0, 0.08, cw / 2 + 0.25, 0.0, tag="queue")
    browse = []
    # snacks: gondola rows along X in the -Y half
    k = 0
    y = -1.9
    while True:
        half = sqrt(max(0.0, (R - 0.35) ** 2 - (abs(y) + 0.35) ** 2)) - 0.2
        x0 = max(-half, cx + 1.7)
        L = half - x0
        if L < 1.4:
            break
        L = min(L, 2.8 + 0.4 * s)
        xm = x0 + L / 2
        with at(plan, xm, y, 90.0):
            gondola(n, L=L, seed=7 * k + s)
        plan.rect(xm, y, L / 2 + 0.03, 0.32, 0.0, tag="shelf")
        for sy in (-1, 1):
            browse.append((xm, y + sy * 0.78, -90.0 * sy))
        y -= 1.75
        k += 1
    # clothes: rails along X in the +Y half, mannequins at the ends, a mirror
    y = 1.9
    j = 0
    while True:
        half = sqrt(max(0.0, (R - 0.35) ** 2 - (abs(y) + 0.35) ** 2)) - 0.3
        x0 = max(-half, cx + 1.7)
        L = min(half - x0 - 1.0, 2.0 + 0.3 * s)
        if L < 1.0:
            break
        xm = x0 + L / 2
        with at(plan, xm, y, 90.0):
            clothes_rail(n, L=L, seed=j + 3)
        plan.rect(xm, y, L / 2 + 0.05, 0.28, 0.0, tag="rail")
        browse.append((xm, y - 0.75, 90.0))
        mx = xm + L / 2 + 0.55
        with at(plan, mx, y, 0.0):
            mannequin(n, col=("Fabric", "Accent", "Cushion", "CushionLight")[j % 4])
        plan.circle(mx, y, 0.22, tag="mannequin")
        y += 1.6
        j += 1
    # gadgets: a gondola row of boxed gadgets across +X (parallel to Y)
    gx0 = R * 0.30
    Lg = 2.0 * sqrt(max(0.0, (R - 0.5) ** 2 - (gx0 + 0.35) ** 2)) - 3.6
    if Lg > 1.2:
        with at(plan, gx0, -0.6, 0.0):
            gondola(n, L=min(Lg, 2.6), seed=41 + s)
        plan.rect(gx0, -0.6, 0.32, min(Lg, 2.6) / 2 + 0.03, 0.0, tag="shelf")
        browse.append((gx0 + 0.78, -0.6, 180.0))
    if R > 7.0 and Lg > 1.2:
        # a second gadget run beside the first (L)
        gx1 = gx0 + 1.75
        Lg1 = 2.0 * sqrt(max(0.0, (R - 0.5) ** 2 - (gx1 + 0.35) ** 2)) - 3.6
        if Lg1 > 1.2:
            with at(plan, gx1, -0.6, 0.0):
                gondola(n, L=min(Lg1, 2.6), seed=43 + s)
            plan.rect(gx1, -0.6, 0.32, min(Lg1, 2.6) / 2 + 0.03, 0.0, tag="shelf")
    if R > 5.0:
        # the cafe: a coffee bar and small tables with two chairs each, on a wood floor
        ca = -52.0
        cxb, cyb = polar(R - 0.75, ca)
        pie_floor(plan, R, ca - 16.0, ca + 16.0, "Wood", z=F + 0.005)
        with at(plan, cxb, cyb, ca + 180.0):
            bbox(n, -0.30, 0.30, -0.9, 0.9, F, F + 1.02, "HullDark", bevel=0.015)
            bbox(n, -0.34, 0.34, -0.95, 0.95, F + 1.02, F + 1.06, "Wood", bevel=0.01)
            bbox(n, -0.20, 0.10, 0.35, 0.70, F + 1.06, F + 1.46, "Metal", bevel=0.02)
            plate_x(n, 0.301, -0.85, 0.85, F + 0.80, F + 0.84, "LightStrip")
            for j in range(3):
                n.vcyl(0.05, -0.6 + 0.25 * j, F + 1.06, F + 1.16, 0.045, seg=8, mat=("Hull", "Fabric", "Accent")[j])
        plan.rect(cxb, cyb, 0.34, 0.95, ca + 180.0, tag="bar")
        for k, (dr, da) in enumerate(((2.0, -9.0), (2.0, 9.0), (3.3, 0.0))[:(2 if R < 7.0 else 3)]):
            tx_, ty_ = polar(R - 0.75 - dr, ca + da)
            with at(plan, tx_, ty_, 0.0):
                FU.table_round(n, r=0.36, h=0.74, top="Wood", edge="Accent")
            plan.circle(tx_, ty_, 0.36, tag="table")
            for sd in (-1, 1):
                chx, chy = off(tx_, ty_, ca + 90.0, 0.0, 0.0)
                chx, chy = tx_ + sd * 0.66 * cos(radians(ca + 90.0)), ty_ + sd * 0.66 * sin(radians(ca + 90.0))
                with at(plan, chx, chy, ca - 90.0 if sd > 0 else ca + 90.0):
                    FU.chair(n, seat=("Fabric", "CushionLight")[(k + sd) % 2])
                plan.rect(chx, chy, 0.24, 0.24, ca, tag="chair")
    # gadgets: display tables at +X
    for k in range((1, 2, 3, 3)[s]):
        a = (0.0, -18.0, 18.0)[k]
        x, y = polar(R * 0.62, a)
        with at(plan, x, y, 0.0):
            display_table(n, r=0.55, seed=k)
        plan.circle(x, y, 0.56, tag="display")
        browse.append(off(x, y, a + 180.0, 1.05) + (a,))
    # the till queue: two rope lines forming a lane toward the counter
    for yq in (-0.55, 0.55):
        for xq in (cx + 1.2, cx + 2.4):
            n.vcyl(xq, yq, F, F + 0.95, 0.03, seg=6, mat="Metal", cap0=False)
            n.vcyl(xq, yq, F, F + 0.03, 0.14, seg=8, mat="Frame", cap0=False)
        n.cyl((cx + 1.2, yq, F + 0.90), (cx + 2.4, yq, F + 0.90), 0.02, seg=4, mat="Accent")
        plan.rect(cx + 1.8, yq, 0.62, 0.06, 0.0, tag="queue")
    # gift stacks by the till
    for k in range(1 + s):
        gx, gy = cx + 1.9, (-1) ** k * (0.9 + 0.5 * (k // 2))
        _gift_stack(plan, gx, gy, k)
        plan.circle(gx, gy, 0.32, tag="gifts")
    if True:
        # a fitting booth with a curtain (Tall) at +X +Y (critic round 33: every size)
        bx, by = polar(R - 1.0, 50.0)
        tp = plan.tall(bx, by)
        with tp.at(T(bx, by, 0.0), RZ(50.0 + 180.0)):
            bbox(tp, 0.55, 0.6, -0.6, 0.6, F, F + 1.9, "Frame")
            bbox(tp, -0.6, 0.6, -0.6, -0.55, F, F + 1.9, "Frame")
            bbox(tp, -0.6, 0.6, 0.55, 0.6, F + 0.2, F + 1.85, "Fabric")
            bbox(tp, -0.6, -0.55, -0.6, 0.6, F + 0.2, F + 1.85, "Cushion")
            plate_z(tp, F + 0.005, -0.55, 0.55, -0.55, 0.55, "RugLight")
        plan.rect(bx, by, 0.62, 0.62, 50.0, tag="curtain")
        if R > 5.0:                                        # a second booth beside it
            bx2, by2 = polar(R - 1.0, 68.0)
            tp2 = plan.tall(bx2, by2)
            with tp2.at(T(bx2, by2, 0.0), RZ(68.0 + 180.0)):
                bbox(tp2, 0.55, 0.6, -0.6, 0.6, F, F + 1.9, "Frame")
                bbox(tp2, -0.6, 0.6, -0.6, -0.55, F, F + 1.9, "Frame")
                bbox(tp2, -0.6, 0.6, 0.55, 0.6, F + 0.2, F + 1.85, "Cushion")
                bbox(tp2, -0.6, -0.55, -0.6, 0.6, F + 0.2, F + 1.85, "Fabric")
                plate_z(tp2, F + 0.005, -0.55, 0.55, -0.55, 0.55, "RugLight")
            plan.rect(bx2, by2, 0.62, 0.62, 68.0, tag="curtain")
    # browse stands (the first that stand free)
    k = 0
    for (x, y, yaw) in browse:
        if k >= fu["stands"]:
            break
        if hypot(x, y) > R - 0.25 or plan.dist(x, y) < 0.30:
            continue
        if any(hypot(x - a[1][0], y - a[1][1]) < 0.7 for a in rm.anchors if a[0].startswith("Anchor_Stand")):
            continue
        anchor(plan, "Stand", x, y, yaw, alias="Browse_%d" % k)
        k += 1
    if k < fu["stands"]:
        plan.stands(fu["stands"] - k)
        for i in range(k, fu["stands"]):
            a = [q for q in rm.anchors if q[0] == "Anchor_Stand_%d" % i][0]
            rm.anchor("Browse_%d" % i, a[1], a[2])
    # wall items: fridges, bottles, shelves
    pattern = ["fridge", "bottles", "shelf", "freezer", "shelf", "cab_plant", "bottles"]
    sets = IR.wall_set(plan)
    sets.update(fridge=lambda p, w, d, k_: FU.wi_fridge(p, w=w, d=d),
                bottles=lambda p, w, d, k_: FU.wi_bottles(p, w=w, d=d, seed=k_),
                freezer=lambda p, w, d, k_: FU.wi_freezer(p, w=w, d=d))
    plan.wall_items(pattern, sets, open_every=4, seed=3 + s, depth_of=dict(IR.DEPTHS, fridge=0.42, freezer=0.42,
                                                                          bottles=0.30))
    fill(plan, [(lambda p_, x, y, k_: _end_unit(p_, x, y, k_), 0.75),
                (lambda p_, x, y, k_: _display(p_, x, y, k_), 0.6),
                (lambda p_, x, y, k_: _promo_bin(p_, x, y, k_), 0.40)], target=2.2, max_items=40)
    plan.lights()
    plan.aisles()
    plan.v4_patch = IR.empty_patch(plan)[0]


def _display(plan, x, y, k):
    """A display table with gadgets, or a mannequin pair (alternating)."""
    n = plan.n
    if k % 2 == 0:
        with at(plan, x, y, 0.0):
            display_table(n, r=0.55, seed=k)
    else:
        for j, dy in enumerate((-0.28, 0.28)):
            with at(plan, x, y + dy, degrees(atan2(-y, -x))):
                mannequin(n, col=("Fabric", "Accent", "CushionLight", "Cushion")[(k + j) % 4])


def _end_unit(plan, x, y, k):
    """A short shelf run (1.2 m gondola) turned to the room centre: the filler's aisle-forming unit."""
    yaw = degrees(atan2(y, x))
    with at(plan, x, y, yaw):
        gondola(plan.n, L=1.2, seed=70 + k)


def _promo_bin(plan, x, y, k):
    """A round promo bin full of goods with a price sign."""
    n = plan.n
    rng = random.Random(k)
    with n.at(T(x, y, 0.0)):
        n.lathe([(0.36, F), (0.38, F + 0.62), (0.33, F + 0.62), (0.31, F + 0.10), (0.0, F + 0.10)],
                lambda k_, i: ("Accent", "Frame", "Hull", "Hull")[k_], seg=14, smooth=False)
        for j in range(7):
            a = rng.uniform(0, 2 * pi)
            r = rng.uniform(0.0, 0.2)
            bbox(n, r * cos(a) - 0.07, r * cos(a) + 0.07, r * sin(a) - 0.05, r * sin(a) + 0.05, F + 0.5, F + 0.66,
                 rng.choice(GOODS))
        n.vcyl(0.0, 0.0, F + 0.62, F + 1.2, 0.012, seg=4, mat="Frame")
        bbox(n, -0.18, 0.18, -0.01, 0.01, F + 1.12, F + 1.34, "Screen")


def _gift_stack(plan, x, y, k):
    rng = random.Random(k)
    n = plan.n
    with at(plan, x, y, rng.uniform(0, 90)):
        for j, (s_, z) in enumerate(((0.5, 0.0), (0.36, 0.5), (0.24, 0.86))):
            c = rng.choice(("Accent", "Fabric", "CushionLight", "Glow"))
            bbox(n, -s_ / 2, s_ / 2, -s_ / 2, s_ / 2, F + z, F + z + s_ * 0.72, c)
            bbox(n, -s_ / 2 - 0.005, s_ / 2 + 0.005, -0.03, 0.03, F + z, F + z + s_ * 0.72 + 0.005, "Hull")


# --------------------------------------------------------------------------------------
# PARK
# --------------------------------------------------------------------------------------
def tree(plan, x, y, h, seed=0, crown=1.0):
    """A park tree: a trunk and a crown of leaf balls, h high (kept under the dome)."""
    n = plan.n
    rng = random.Random(seed)
    lim = plan.rm.headroom(x, y) - 0.3
    h = min(h, lim)
    n.vcyl(x, y, F, F + h * 0.55, 0.12 * crown, 0.08 * crown, seg=8, mat="Wood")
    for k in range(5):
        a = 72.0 * k + rng.uniform(0, 40)
        rr = 0.55 * crown
        cx, cy = x + rr * cos(radians(a)), y + rr * sin(radians(a))
        cz = F + h * rng.uniform(0.62, 0.78)
        n.sphere((cx, cy, cz), 0.62 * crown * rng.uniform(0.85, 1.1), "Plant" if k % 2 else "PlantDark", seg=8,
                 rings=5, smooth=True, scale=(1, 1, 0.85))
    n.sphere((x, y, F + h * 0.86), 0.7 * crown, "Plant", seg=8, rings=5, smooth=True, scale=(1, 1, 0.8))


def flower_bed(plan, x, y, r=0.6, seed=0):
    n = plan.n
    rng = random.Random(seed)
    with n.at(T(x, y, 0.0)):
        n.lathe([(r, F), (r, F + 0.22), (r - 0.08, F + 0.22), (r - 0.08, F + 0.18), (0.0, F + 0.18)],
                lambda k, i: ("Hull", "Hull", "Hull", "Soil")[k], seg=16, smooth=False)
    cols = ("Accent", "Fabric", "Glow", "CushionLight", "Hull")
    for k in range(9):
        a = rng.uniform(0, 2 * pi)
        rr = rng.uniform(0.0, r - 0.2)
        n.sphere((x + rr * cos(a), y + rr * sin(a), F + 0.28), 0.10, cols[k % len(cols)], seg=6, rings=3,
                 smooth=False)
    FU.leafy_plant(n, x, y, F + 0.20, s=0.7, n=6, seed=seed)


def _bushes(plan, x, y, seed=0):
    """A clump of round bushes (about 1.6 m across) with a few flowers."""
    n = plan.n
    rng = random.Random(seed)
    for k in range(4):
        a = 90.0 * k + rng.uniform(0, 60)
        r = rng.uniform(0.25, 0.45)
        n.sphere((x + r * cos(radians(a)), y + r * sin(radians(a)), F + 0.30), rng.uniform(0.32, 0.42),
                 "PlantDark" if k % 2 else "Plant", seg=8, rings=4, smooth=True, scale=(1, 1, 0.8))
    for k in range(3):
        a = rng.uniform(0, 2 * pi)
        n.sphere((x + 0.5 * cos(a), y + 0.5 * sin(a), F + 0.55), 0.08, ("Fabric", "Glow", "CushionLight")[k],
                 seg=6, rings=3, smooth=False)


def lamp_post(plan, x, y):
    n = plan.n
    n.vcyl(x, y, F, F + 0.05, 0.12, seg=8, mat="Frame", cap0=False)
    n.vcyl(x, y, F + 0.05, F + 2.2, 0.04, seg=6, mat="HullDark")
    n.sphere((x, y, F + 2.32), 0.16, "Window", seg=8, rings=4)
    plan.lamp(x, y, F + 2.3)


def path_ring(plan, r, w, mat="Floor"):
    plan.n.lathe_a([(r + w / 2, F + 0.006), (r - w / 2, F + 0.006)], [360.0 * (k + 0.5) / 64 for k in range(64)],
                   lambda k, i: mat, smooth=False)
    plan.n.lathe_a([(r + w / 2 + 0.05, F + 0.007), (r + w / 2, F + 0.007)], [360.0 * (k + 0.5) / 64 for k in range(64)],
                   lambda k, i: "Frame", smooth=False)
    plan.n.lathe_a([(r - w / 2, F + 0.007), (r - w / 2 - 0.05, F + 0.007)], [360.0 * (k + 0.5) / 64 for k in range(64)],
                   lambda k, i: "Frame", smooth=False)


def park(rm):
    s = rm.size
    fu = IK.furniture_of(rm)
    plan = Plan(rm)
    IK.build_floor_v3(rm, "panel", "radial", ring_step=1.4, radial=16, edge_band=0.62, inner_disc=1.2)
    n = plan.n
    R = plan.r_max
    # the lawn over the whole garden floor, the jogging loop and the cross paths
    n.lathe_a([(R + 0.1, F + 0.004), (0.0, F + 0.004)], [360.0 * (k + 0.5) / 64 for k in range(64)],
              lambda k, i: "Plant", smooth=False)
    rj = 0.66 * R
    path_ring(plan, rj, 1.1)
    for a in (45.0, 135.0, 225.0, 315.0):
        c_, s_ = cos(radians(a)), sin(radians(a))
        x0, y0, x1, y1 = 1.4 * c_, 1.4 * s_, (R + 0.1) * c_, (R + 0.1) * s_
        FU.floor_line(n, x0, y0, x1, y1, w=0.9, mat="Floor", z=F + 0.006)
    pond = s >= 2
    # the centre: a pond with a fountain (L, XL) or a flower bed (M)
    if pond:
        rp = 1.6 + 0.5 * (s - 2)
        with n.at(T(0.0, 0.0, 0.0)):
            n.lathe([(rp + 0.25, F), (rp + 0.25, F + 0.30), (rp, F + 0.30), (rp, F + 0.12), (0.0, F + 0.12)],
                    lambda k, i: ("Hull", "Frame", "Hull", "WaterBlue")[k], seg=32, smooth=False)
            n.vcyl(0.0, 0.0, F + 0.12, F + 0.7, 0.10, seg=10, mat="Frame")
            n.lathe([(0.45, F + 0.66), (0.40, F + 0.76), (0.05, F + 0.76)], "Hull", seg=16)
            n.cap_disc(0.38, F + 0.745, "WaterBlue", seg=16)
        for k in range(5):
            a = 72.0 * k + 20.0
            lx, ly = (rp - 0.6) * cos(radians(a)), (rp - 0.6) * sin(radians(a))
            with n.at(T(lx, ly, 0.0)):
                n.cap_disc(0.2, F + 0.125, "PlantDark", seg=8)
        plan.circle(0.0, 0.0, rp + 0.25, tag="pond")
        stands_c = [polar(rp + 0.75, a) + (a + 180.0,) for a in (30.0, 150.0, 270.0)]
    else:
        flower_bed(plan, 0.0, 0.0, r=0.95, seed=3)
        plan.circle(0.0, 0.0, 0.95, tag="bed")
        stands_c = [polar(1.7, a) + (a + 180.0,) for a in (30.0, 150.0, 270.0)]
    # benches along the loop, facing the middle (2 seats each)
    nb = (fu["seats"] + 1) // 2
    seats_left = fu["seats"]
    for k in range(nb):
        a = 360.0 * (k + 0.5) / nb + 22.5
        x, y = polar(rj + 0.95, a)
        yaw = a + 180.0
        with at(plan, x, y, yaw):
            V5.bench(n, L=1.4)
        plan.rect(x, y, 0.24, 0.72, yaw, tag="bench")
        for ly in (-0.35, 0.35):
            if seats_left > 0:
                anchor(plan, "Seat", x, y, yaw, lx=SEAT_BACK - 0.02, ly=ly)
                seats_left -= 1
        lx_, ly_ = polar(rj + 0.95, a + degrees(1.25 / (rj + 0.95)))
        if k % 2 == 0:
            lamp_post(plan, lx_, ly_)
            plan.circle(lx_, ly_, 0.14, tag="lamp")
    # trees and flower beds between the paths, outside and inside the loop
    tseed = 0
    for q in range(4):
        a = 90.0 * q
        for (r_, kind) in ((rj + 0.5 * (R - rj) + 0.2, "tree"), (0.5 * rj + (0.7 if pond else 0.4), "bed")):
            x, y = polar(r_, a)
            if kind == "tree":
                tree(plan, x, y, 3.0 + 0.5 * s, seed=tseed, crown=0.9 + 0.1 * s)
                plan.circle(x, y, 0.35, tag="tree")
            else:
                flower_bed(plan, x, y, r=0.55, seed=tseed)
                plan.circle(x, y, 0.55, tag="bed")
            tseed += 1
    # the wedding arch (L, XL) on the loop's far side, a white platform
    if s >= 2:
        a = 200.0
        wx, wy = polar(rj - 1.5, a)
        with at(plan, wx, wy, a):
            bbox(n, -0.7, 0.7, -1.1, 1.1, F, F + 0.10, "Hull", bevel=0.02)
            for sy in (-1, 1):
                n.vcyl(0.3, sy * 0.95, F + 0.10, F + 2.1, 0.05, seg=6, mat="Hull")
            prof = [(0.3, 0.95 * cos(radians(t)), F + 2.1 + 0.6 * sin(radians(t))) for t in range(0, 181, 20)]
            n.beam_path(prof, 0.10, 0.10, "Hull", up=(1, 0, 0))
            for k, (px, py, pz) in enumerate(prof[1:-1]):
                n.sphere((px, py, pz), 0.12, ("Fabric", "CushionLight", "Glow")[k % 3], seg=6, rings=3)
        plan.rect(wx, wy, 0.7, 1.1, a, tag="arch")
        ax_, ay_ = off(wx, wy, a, -0.35)
        rm.anchor("Wedding", (ax_, ay_, F + 0.10), a)
    # jogging points round the loop
    nj = 12 + 4 * s
    for k in range(nj):
        a = 360.0 * k / nj
        x, y = polar(rj, a)
        rm.anchor("Jog_%d" % k, (x, y, F), a + 90.0)
    # stands: by the pond / the bed, then free spots
    k = 0
    for (x, y, yaw) in stands_c:
        if k < fu["stands"] and plan.dist(x, y) >= 0.3:
            anchor(plan, "Stand", x, y, yaw)
            k += 1
    if k < fu["stands"]:
        plan.stands(fu["stands"] - k)
    plan.wall_items(["planter", "planter", "tap", "planter"], IR.wall_set(plan), open_every=3, seed=7 + s,
                    depth_of=IR.DEPTHS)
    fill(plan, [(lambda p_, x, y, k_: _bushes(p_, x, y, seed=80 + k_), 0.8),
                (lambda p_, x, y, k_: tree(p_, x, y, 2.6 + 0.4 * s, seed=40 + k_), 0.45),
                (lambda p_, x, y, k_: flower_bed(p_, x, y, r=0.5, seed=60 + k_), 0.5),
                (f_plant, 0.25)], max_items=90)
    plan.lights()
    plan.aisles()
    plan.v4_patch = IR.empty_patch(plan)[0]


# --------------------------------------------------------------------------------------
# ACADEMY
# --------------------------------------------------------------------------------------
def _group_table(plan, x, y, k):
    """Group work: a round table with four chairs and books (the second class)."""
    n = plan.n
    with n.at(T(x, y, 0.0)):
        FU.table_round(n, r=0.50, h=0.70, top="Wood", edge="Accent")
        for j in range(3):
            bbox(n, -0.2 + 0.15 * j, -0.05 + 0.15 * j, -0.12, 0.12, F + 0.70, F + 0.74, ("Fabric", "Accent", "Hull")[j])
    for j in range(4):
        a = 45.0 + 90.0 * j
        cx_, cy_ = x + 0.85 * cos(radians(a)), y + 0.85 * sin(radians(a))
        with at(plan, cx_, cy_, a + 180.0):
            FU.chair(n, seat=("Cushion", "Fabric", "CushionLight", "Cushion")[j])


def _shelf_island(plan, x, y, k):
    """Two low bookshelves back to back, turned to the room centre."""
    n = plan.n
    yaw = degrees(atan2(y, x)) + 90.0
    for sd in (-1, 1):
        with n.at(T(x, y, 0.0), RZ(yaw + (90.0 if sd > 0 else -90.0))):
            FU.wi_shelf(n, w=0.9, d=0.30, h=0.95, seed=k + sd)


def school_desk(p, seed=0):
    """A student desk (the pupil sits at +X... faces -X): body behind x = 0 like FU.desk, top 0.70."""
    zt = F + 0.70
    bbox(p, -0.50, 0.0, -0.40, 0.40, zt - 0.03, zt, "Wood", bevel=0.01)
    for sy in (-1, 1):
        bbox(p, -0.46, -0.04, sy * 0.36 - 0.02, sy * 0.36 + 0.02, F, zt - 0.03, "Frame", mats={"-z": None})
    bbox(p, -0.45, -0.05, -0.30, 0.30, F + 0.45, F + 0.48, "Frame")
    rng = random.Random(seed)
    bbox(p, -0.35, -0.12, -0.18, 0.18, zt, zt + 0.012, "Screen" if seed % 2 else "Hull")
    bbox(p, -0.30, -0.18, 0.22, 0.30, zt, zt + 0.08, rng.choice(("Accent", "Fabric", "CushionLight")))


def teacher_board(p, w=2.4):
    """A big board on two legs, facing +X: a screen with lesson bars."""
    for sy in (-1, 1):
        bbox(p, -0.06, 0.06, sy * (w / 2 + 0.05) - 0.04, sy * (w / 2 + 0.05) + 0.04, F, F + 2.0, "Frame",
             mats={"-z": None})
        bbox(p, -0.25, 0.25, sy * (w / 2 + 0.05) - 0.05, sy * (w / 2 + 0.05) + 0.05, F, F + 0.05, "Frame",
             mats={"-z": None})
    with p.at(T(0.03, 0.0, F + 1.35)):
        IK.ui_screen(p, w, 1.1, seed=2)


def academy(rm):
    s = rm.size
    fu = IK.furniture_of(rm)
    plan = Plan(rm)
    IK.build_floor_v3(rm, "panel", "grid", grid=1.2)
    n = plan.n
    R = plan.r_max
    # the board at +X facing -X; the teacher's desk in front of it
    bx = R - 0.35
    with at(plan, bx, 0.0, 180.0):
        teacher_board(n, w=2.0 + 0.3 * s)
    plan.rect(bx, 0.0, 0.25, 1.1 + 0.15 * s, 180.0, tag="board")
    tx = bx - 1.55
    with at(plan, tx, 0.0, 0.0):
        FU.desk(n, w=1.3, d=0.62, monitors=1, lamp_cb=IR.lamp_cb(plan, n), seed=1)
    plan.rect(tx - 0.31, 0.0, 0.31, 0.65, 0.0, tag="desk")
    anchor(plan, "Work", tx, 0.0, 180.0, lx=-0.45, alias="Teach")
    # student desks in rows facing +X (the pupils face the board)
    rows = {0: (2, 2), 1: (2, 4), 2: (3, 5), 3: (3, 5)}[s]
    nseat = fu["seats"]
    k = 0
    for ri in range(rows[0]):
        x = tx - 1.45 - 1.45 * ri
        cols = rows[1] if (ri < rows[0] - 1 or nseat - k >= rows[1]) else nseat - k
        for ci in range(cols):
            if k >= nseat:
                break
            y = (ci - (cols - 1) / 2.0) * 1.0
            with at(plan, x, y, 180.0):
                school_desk(n, seed=k)
            plan.rect(x + 0.25, y, 0.25, 0.40, 0.0, tag="desk")
            cx_ = x - 0.30
            with at(plan, cx_, y, 0.0):
                FU.chair(n, seat=("Cushion", "Fabric", "CushionLight")[k % 3])
            plan.rect(cx_, y, 0.24, 0.24, 0.0, tag="seat")
            anchor(plan, "Seat", cx_, y, 0.0, lx=SEAT_BACK, alias="Class_%d" % k)
            k += 1
    # instructor consoles on the side walls (Work 1..)
    for i in range(1, fu["work_slots"]):
        a = 115.0 if i == 1 else -115.0
        x, y = polar(R - 0.62, a)
        with at(plan, x, y, a + 180.0):
            FU.console(n, w=1.0)
        plan.rect(*off(x, y, a + 180.0, -0.28), 0.28, 0.52, a + 180.0, tag="console")
        ax, ay = off(x, y, a + 180.0, CONSOLE_AHEAD)
        plan.anchor("Work", ax, ay, a)
        rm.anchor("Console_%d" % (i - 1), (ax, ay, F), a)
    # the second class at -X (M, L): four desks facing a wall board (the pupils face -X)
    bx2 = -(R - 0.35)
    if R > 5.0:
        with at(plan, bx2, -0.6, 0.0):
            teacher_board(n, w=1.6)
        plan.rect(bx2, -0.6, 0.25, 0.9, 0.0, tag="board")
    for ri in range(2 if R > 5.0 else 0):
        for ci in range(2):
            x = bx2 + 1.6 + 1.45 * ri
            y = -0.6 + (ci - 0.5) * 1.0
            with at(plan, x, y, 0.0):
                school_desk(n, seed=20 + 2 * ri + ci)
            plan.rect(x - 0.25, y, 0.25, 0.40, 0.0, tag="desk")
            with at(plan, x + 0.30, y, 180.0):
                FU.chair(n, seat=("Fabric", "CushionLight")[(ri + ci) % 2])
            plan.rect(x + 0.30, y, 0.24, 0.24, 0.0, tag="chair2")
    # the library corner at +Y: shelves in an arc, two armchairs on a rug, a floor lamp
    la = 100.0
    for j in range(3):
        a = la - 14.0 + 14.0 * j
        x, y = polar(R - 0.55, a)
        with at(plan, x, y, a + 180.0):
            FU.wi_shelf(n, w=0.9, d=0.34, h=1.30, seed=30 + j)
        plan.rect(*off(x, y, a + 180.0, 0.17), 0.17, 0.46, a + 180.0, tag="shelf")
    lx_, ly_ = polar(R - 2.0, la)
    FU.rug_round(n, 1.0, lx_, ly_, mat="RugLight", ring="Accent", seg=18)
    for j, da in enumerate((-18.0, 18.0)):
        ax_, ay_ = polar(R - 2.0, la + da)
        with at(plan, ax_, ay_, la + da + 180.0):
            V5.armchair(n, fabric=("Fabric", "Cushion")[j])
        plan.rect(ax_, ay_, 0.42, 0.47, la + da + 180.0, tag="armchair")
    fx_, fy_ = polar(R - 2.6, la)
    with at(plan, fx_, fy_, 0.0):
        V5.floor_lamp(n, lamp_cb=IR.lamp_cb(plan, n))
    plan.circle(fx_, fy_, 0.18, tag="lamp")
    # the library wall on the -X -Y arc (4 shelves) and a second lab bench near the board side (M, L)
    if R > 5.0:
        for j in range(4):
            a = 208.0 + 12.0 * j
            x, y = polar(R - 0.42, a)
            with at(plan, x, y, a + 180.0):
                FU.wi_shelf(n, w=0.95, d=0.34, h=1.30, seed=50 + j)
            plan.rect(*off(x, y, a + 180.0, 0.17), 0.17, 0.48, a + 180.0, tag="shelf")
        lx2, ly2 = polar(0.62 * R, 318.0)
        with at(plan, lx2, ly2, 138.0):
            FU.lab_bench(n, w=1.6, d=0.7, seed=5)
        plan.rect(*off(lx2, ly2, 138.0, -0.35), 0.35, 0.8, 138.0, tag="bench")
        for sy in (-0.45, 0.45):
            sx_, sy_ = off(lx2, ly2, 138.0, 0.55, sy)
            with at(plan, sx_, sy_, 0.0):
                FU.stool(n)
            plan.circle(sx_, sy_, 0.2, tag="stool")
    # a reading corner for the children: a round rug, cushions, a low shelf
    rx, ry = polar(0.55 * R, -120.0)
    FU.rug_round(n, 0.9, rx, ry, mat="CushionLight", ring="Accent", seg=18)
    for j in range(3):
        cx_, cy_ = rx + 0.5 * cos(radians(120 * j)), ry + 0.5 * sin(radians(120 * j))
        n.sphere((cx_, cy_, F + 0.14), 0.24, ("Fabric", "Accent", "Cushion")[j], seg=8, rings=4, scale=(1, 1, 0.55))
    plan.circle(rx, ry, 0.9, tag="rug")
    # stands at the globe / the shelves
    gx, gy = polar(0.50 * R, 55.0)
    with at(plan, gx, gy, 0.0):
        FU.holo_table(n, r=0.55)
    plan.circle(gx, gy, 0.6, tag="holo")
    k = 0
    for (x, y, yaw) in (off(gx, gy, 0.0, -1.05) + (0.0,), off(gx, gy, 0.0, 1.05) + (180.0,)):
        if k < fu["stands"]:
            anchor(plan, "Stand", x, y, yaw)
            k += 1
    # the science corner: a lab bench with two stools
    lx, ly = polar(0.62 * R, 262.0)
    with at(plan, lx, ly, 40.0):
        FU.lab_bench(n, w=1.6, d=0.7, seed=3)
    plan.rect(*off(lx, ly, 40.0, -0.35), 0.35, 0.8, 40.0, tag="bench")
    for sy in (-0.45, 0.45):
        sx_, sy_ = off(lx, ly, 40.0, 0.55, sy)
        with at(plan, sx_, sy_, 0.0):
            FU.stool(n)
        plan.circle(sx_, sy_, 0.2, tag="stool")
    pattern = ["shelf", "cab_books", "poster", "shelf", "cab_plant", "desk", "shelf"]
    plan.wall_items(pattern, IR.wall_set(plan), open_every=3, seed=9 + s, depth_of=IR.DEPTHS)
    fill(plan, [(lambda p_, x, y, k_: _group_table(p_, x, y, k_), 1.1),
                (lambda p_, x, y, k_: _shelf_island(p_, x, y, k_), 0.55), (f_plant, 0.25)], target=1.6,
         max_items=80)
    plan.lights()
    plan.aisles()
    plan.v4_patch = IR.empty_patch(plan)[0]


# --------------------------------------------------------------------------------------
# SECURITY OFFICE
# --------------------------------------------------------------------------------------
def monitor_wall(p, n_cols=4, rows=2, w=0.9, h=0.55):
    """A wall of screens on a frame (faces +X): n_cols x rows panels from 0.75 m up, a status strip on top."""
    W = n_cols * (w + 0.06)
    for sy in (-1, 1):
        bbox(p, -0.12, 0.0, sy * W / 2 - 0.04, sy * W / 2 + 0.04, F, F + 0.75 + rows * (h + 0.06) + 0.1, "Frame",
             mats={"-z": None})
    bbox(p, -0.10, 0.0, -W / 2, W / 2, F + 0.60, F + 0.75 + rows * (h + 0.06), "HullDark")
    for r in range(rows):
        for c_ in range(n_cols):
            y = -W / 2 + 0.03 + (w + 0.06) * c_ + w / 2
            z = F + 0.78 + (h + 0.06) * r + h / 2
            with p.at(T(0.01, y, z)):
                IK.ui_screen(p, w, h, seed=r * n_cols + c_)
    plate_x(p, 0.02, -W / 2, W / 2, F + 0.75 + rows * (h + 0.06) + 0.02, F + 0.75 + rows * (h + 0.06) + 0.08,
            "Ember")


def security_office(rm):
    """A command post: a raised command desk facing a monitor wall, a dispatch console (M), lockers, a briefing
    table, a holding cell, the front desk and a map table."""
    s = rm.size
    fu = IK.furniture_of(rm)
    plan = Plan(rm)
    IK.build_floor_v3(rm, "dark", "grid", grid=1.0)
    n = plan.n
    R = plan.r_max
    # the monitor wall on the -X arc (three sections angled to the command desk)
    nsec = 3 if R > 5.0 else 2
    for j in range(nsec):
        a = 180.0 + (j - (nsec - 1) / 2.0) * (26.0 if R > 5.0 else 34.0)
        x, y = polar(R - 0.25, a)
        with at(plan, x, y, a + 180.0):
            monitor_wall(n, n_cols=2, rows=2, w=0.85, h=0.52)
        plan.rect(*off(x, y, a + 180.0, -0.06), 0.08, 0.95, a + 180.0, tag="screenwall")
    # the raised command dais with the command desk (Work_0) facing the wall
    dcx = -(R - 2.55)
    with n.at(T(dcx, 0.0, 0.0)):
        n.lathe([(1.35, F), (1.35, F + 0.16), (0.0, F + 0.16)], lambda k, i: ("Frame", "FloorDark")[k], seg=24,
                smooth=False)
        n.lathe_a([(1.37, F + 0.162), (1.25, F + 0.162)], [360.0 * (k + 0.5) / 24 for k in range(24)],
                  lambda k, i: "Fabric", smooth=False)
    cdx = dcx - 0.25
    with n.at(T(cdx, 0.0, 0.16)):
        FU.console(n, w=2.0)
        for j in (-1, 1):
            with n.at(T(-0.30, j * 0.62, F + 1.30), RZ(j * 18.0)):
                IK.ui_screen(n, 0.5, 0.34, seed=j + 5)
    plan.rect(cdx - 0.28, 0.0, 0.28, 1.02, 0.0, tag="console")
    wx = cdx + CONSOLE_AHEAD
    plan.anchor("Work", wx, 0.0, 180.0, z=F + 0.16)
    rm.anchor("Desk_0", (wx, 0.0, F + 0.16), 180.0)
    # the dispatch console (M): radios and a map screen, at +Y by the wall
    if fu["work_slots"] > 1:
        a = 120.0
        x, y = polar(R - 0.62, a)
        with at(plan, x, y, a + 180.0):
            FU.console(n, w=1.4)
            with n.at(T(-0.35, 0.0, F + 1.25)):
                IK.ui_screen(n, 0.9, 0.5, seed=7)
            for j in range(3):
                bbox(n, -0.45, -0.25, -0.5 + 0.35 * j, -0.3 + 0.35 * j, F + 0.9, F + 1.05, "HullDark")
        plan.rect(*off(x, y, a + 180.0, -0.28), 0.28, 0.72, a + 180.0, tag="console")
        ax, ay = off(x, y, a + 180.0, CONSOLE_AHEAD)
        plan.anchor("Work", ax, ay, a)
        rm.anchor("Desk_1", (ax, ay, F), a)
    # the front desk (reception) at +X with the response line
    dx = R - 1.2
    with at(plan, dx, 0.0, 0.0):
        shop_counter(n, w=1.6, seed=5)
    plan.rect(dx, 0.0, 0.34, 0.8, 0.0, tag="counter")
    for k in range(8):
        y0 = -1.4 + 0.35 * k
        FU.floor_line(n, dx + 0.9, y0, dx + 0.9, y0 + 0.17, w=0.12, mat="Hazard")
    # the briefing table (Seats) at +X +Y
    bx, by = polar(0.48 * R, 62.0)
    with at(plan, bx, by, 0.0):
        FU.table_rect(n, 0.7, 0.4, top="Hull", edge="Fabric")
        with n.at(T(0.0, 0.0, F + 0.745)):
            plate_z(n, 0.0, -0.45, 0.45, -0.25, 0.25, "Screen")
    plan.rect(bx, by, 0.7, 0.4, 0.0, tag="table")
    for k in range(fu["seats"]):
        sy = -1 if k % 2 == 0 else 1
        cx_ = bx + (-0.35 + 0.7 * (k // 2))
        cy_ = by + sy * 0.70
        yaw = 90.0 if sy < 0 else -90.0
        with at(plan, cx_, cy_, yaw):
            FU.office_chair(n)
        plan.rect(cx_, cy_, 0.26, 0.26, yaw, tag="seat")
        anchor(plan, "Seat", cx_, cy_, yaw, lx=SEAT_BACK)
    # lockers (Stands) at -Y by the wall
    lk = 0
    for a in (240.0, 262.0, 284.0)[:fu["stands"]]:
        x, y = polar(R - 0.05, a)
        with at(plan, x, y, a + 180.0):
            FU.wi_lockers(n, w=0.9, d=0.40, h=1.25, n=3)
        plan.rect(*off(x, y, a + 180.0, 0.2), 0.21, 0.46, a + 180.0, tag="lockers")
        anchor(plan, "Stand", *off(x, y, a + 180.0, 0.4 + 0.45), a, alias="Locker_%d" % lk)
        lk += 1
    # the holding cell at +X -Y, a bench outside it
    hcx, hcy = polar(R - 0.45, 322.0)
    cell(plan, *off(hcx, hcy, 142.0, 2.0), 142.0, None, W=1.6, Dd=2.0)
    bxx, byy = polar(R * 0.42, 300.0)
    with at(plan, bxx, byy, 120.0):
        V5.bench(n, L=1.2)
    plan.rect(bxx, byy, 0.24, 0.62, 120.0, tag="bench")
    # the map table in the middle
    with at(plan, 0.4, -0.2, 0.0):
        FU.holo_table(n, r=0.55)
    plan.circle(0.4, -0.2, 0.58, tag="holo")
    pattern = ["lockers", "rack", "panel", "lockers", "cab_lamp", "rack"]
    sets = IR.wall_set(plan)
    sets.update(rack=lambda p, w, d, k_: FU.wi_rack(p, w=w, d=d, seed=k_, mats=("HullDark", "Accent", "Hull")))
    plan.wall_items(pattern, sets, open_every=3, seed=4 + s, depth_of=dict(IR.DEPTHS, rack=0.42))
    fill(plan, [(lambda p_, x, y, k_: _rack_pair(p_, x, y, k_), 0.65), (lambda p_, x, y, k_: _crates(p_, x, y, k_), 0.45),
                (f_plant, 0.25)], target=1.9)
    plan.lights()
    plan.aisles()
    plan.v4_patch = IR.empty_patch(plan)[0]


def _rack_pair(plan, x, y, k):
    """Equipment racks back to back (helmets, vests, batons as coloured boxes)."""
    n = plan.n
    yaw = degrees(atan2(y, x))
    for sd in (-1, 1):
        with n.at(T(x, y, 0.0), RZ(yaw + (90.0 if sd > 0 else -90.0))):
            FU.wi_rack(n, w=1.1, d=0.32, h=1.25, seed=k + sd, mats=("HullDark", "Fabric", "Hull"))


# --------------------------------------------------------------------------------------
# JAIL
# --------------------------------------------------------------------------------------
def cell(plan, x, y, yaw, i, W=1.9, Dd=2.2):
    """A cell: back wall and side walls (1.30 m), a barred front with a barred door, facing local +X (toward the
    room centre).  Inside: a bunk on one side (Anchor_Cell_<i>, bed convention), a WC and a basin at the back."""
    n = plan.n
    with at(plan, x, y, yaw):
        # walls: back (x = -Dd) and sides (y = +-W/2)
        bbox(n, -Dd, -Dd + 0.10, -W / 2, W / 2, F, F + V5.WALL_H, "HullDark")
        for sy in (-1, 1):
            bbox(n, -Dd, 0.0, sy * W / 2 - 0.05, sy * W / 2 + 0.05, F, F + V5.WALL_H, "Hull")
            bbox(n, -Dd, 0.0, sy * W / 2 - 0.06, sy * W / 2 + 0.06, F + V5.WALL_H - 0.04, F + V5.WALL_H, "Frame")
        plate_z(n, F + 0.005, -Dd + 0.1, -0.05, -W / 2 + 0.05, W / 2 - 0.05, "FloorDark")
        # bars along the front, the door part (y > 0.1) slightly proud
        bbox(n, -0.05, 0.05, -W / 2, W / 2, F + V5.WALL_H - 0.06, F + V5.WALL_H, "Frame")
        bbox(n, -0.04, 0.04, -W / 2, W / 2, F, F + 0.06, "Frame")
        y_ = -W / 2 + 0.10
        while y_ < W / 2 - 0.06:
            xo = 0.03 if y_ > 0.1 else 0.0
            n.vcyl(xo, y_, F + 0.06, F + V5.WALL_H - 0.06, 0.018, seg=4, mat="Metal", cap0=False, cap1=False)
            y_ += 0.13
        bbox(n, 0.0, 0.07, 0.12, W / 2 - 0.05, F + 0.55, F + 0.60, "Frame")
        # a bunk along the -Y side wall, heads to the back (the bed frame: +Y = heads -> local -X)
        with n.at(T(-Dd + 0.12 + 1.02, -W / 2 + 0.05 + 0.40, 0.0), RZ(90.0)):
            bbox(n, -0.40, 0.40, -1.02, 1.02, F, F + BED_Z - 0.10, "Hull", bevel=0.02)
            bbox(n, -0.38, 0.38, -1.0, 1.0, F + BED_Z - 0.10, F + BED_Z, "CushionLight", bevel=0.03)
            bbox(n, -0.42, 0.42, -1.0, 0.4, F + BED_Z - 0.08, F + BED_Z + 0.03, "HullDark", bevel=0.015)
            bbox(n, -0.25, 0.25, 0.62, 0.92, F + BED_Z - 0.01, F + BED_Z + 0.09, "Hull", bevel=0.04)
        # WC and basin at the back on the +Y side
        with n.at(T(-Dd + 0.10, W / 2 - 0.35, 0.0)):
            V5.wc(n)
        with n.at(T(-Dd + 0.10 + 0.75, W / 2 - 0.05, 0.0), RZ(-90.0)):
            bbox(n, 0.0, 0.34, -0.22, 0.22, F + 0.72, F + 0.82, "Metal")
    # footprint (the whole cell is one block for the room plan) and the cell anchor beside the bunk
    plan.rect(*off(x, y, yaw, -Dd / 2), Dd / 2 + 0.05, W / 2 + 0.06, yaw, tag="cell")
    bx, by = off(x, y, yaw, -Dd + 0.12 + 1.02, -W / 2 + 0.05 + 0.40)
    ax, ay = off(bx, by, yaw, 0.0, 0.55)              # the bed's stand side (bed frame +X = cell +Y)
    if i is not None:
        plan.rm.anchor("Cell_%d" % i, (ax, ay, F), yaw + 90.0)
        # SIM 2026-10-01: the jail's furniture beds are the cells; the prisoner sleeps on Anchor_Bed_<i> = Cell_<i>
        plan.anchor("Bed", ax, ay, yaw + 90.0)


def jail(rm):
    s = rm.size
    fu = IK.furniture_of(rm)
    ncell = int(rm.bdef.get("sizes", {}).get("cells", [2, 4, 8, 8])[s])
    plan = Plan(rm)
    IK.build_floor_v3(rm, "dark", "grid", grid=1.0)
    n = plan.n
    R = plan.r_max
    W, Dd = 1.9, 2.2
    # cells round the room, fronts facing the centre
    if ncell <= 2:
        spots = [(-(R - 0.6), -1.0, 0.0), (-(R - 0.6), 1.0, 0.0)]
    else:
        rc = R - 0.27
        spots = []
        for k in range(ncell):
            a = 360.0 * k / ncell + (45.0 if ncell == 4 else 22.5)
            spots.append(polar(rc, a) + (a + 180.0,))
    for i, (x, y, yaw) in enumerate(spots):
        # (x, y) = the cell's back-wall line centre; the cell spans Dd toward the centre
        fx, fy = off(x, y, yaw, Dd)
        cell(plan, fx, fy, yaw, i, W=W, Dd=Dd)
    # the guard desk facing the cells (Work = Guard)
    # the console body is toward the cells; the guard stands behind it and looks over it at them
    if ncell <= 2:
        gx, gy, gyaw = (R - 2.0, 0.0, 0.0)
    elif ncell == 4:
        gx, gy, gyaw = (0.0, 0.3, 0.0)
    else:
        gx, gy, gyaw = polar(3.2, 0.0) + (180.0,)
    with at(plan, gx, gy, gyaw):
        FU.console(n, w=1.2)
    plan.rect(*off(gx, gy, gyaw, -0.28), 0.28, 0.62, gyaw, tag="console")
    ax, ay = off(gx, gy, gyaw, CONSOLE_AHEAD)
    plan.anchor("Work", ax, ay, gyaw + 180.0)
    rm.anchor("Guard", (ax, ay, F), gyaw + 180.0)
    # the visiting / day table (Seats)
    if ncell <= 4:
        vx, vy = (0.6, 2.0) if ncell <= 2 else (0.0, -2.6 if R > 5 else -2.2)
        if ncell == 4:
            vx, vy = polar(2.3, 0.0)
    else:
        vx, vy = polar(3.0, 180.0)
    with at(plan, vx, vy, 0.0):
        FU.table_rect(n, 0.5, 0.35, top="Hull", edge="Frame")
    plan.rect(vx, vy, 0.5, 0.35, 0.0, tag="table")
    for k in range(fu["seats"]):
        sy = -1 if k == 0 else 1
        cy_ = vy + sy * 0.65
        yaw = 90.0 if sy < 0 else -90.0
        with at(plan, vx, cy_, yaw):
            FU.stool(n)
        plan.rect(vx, cy_, 0.2, 0.2, 0.0, tag="seat")
        anchor(plan, "Seat", vx, cy_, yaw, lx=SEAT_BACK)
    # the yard (L): a fenced court in the middle with a hoop and a pull-up bar; the Yard stands
    stands = []
    if ncell >= 8:
        ry_ = 2.2
        n.lathe_a([(ry_, F + 0.006), (0.0, F + 0.006)], [360.0 * (k + 0.5) / 32 for k in range(32)],
                  lambda k, i: "Rubber", smooth=False)
        n.lathe_a([(ry_ + 0.06, F + 0.007), (ry_ - 0.02, F + 0.007)], [360.0 * (k + 0.5) / 32 for k in range(32)],
                  lambda k, i: "Accent", smooth=False)
        for k in range(20):
            if 4 <= k <= 6:
                continue                                  # the gate toward the guard desk
            a = 18.0 * k + 9.0 - 90.0
            n.vcyl(*polar(ry_ + 0.1, a), F, F + 1.28, 0.025, seg=4, mat="Frame", cap0=False)
        with at(plan, *polar(ry_ - 0.3, 90.0), -90.0):
            n.vcyl(0.0, 0.0, F, F + 1.9, 0.05, seg=6, mat="Frame")
            bbox(n, 0.02, 0.06, -0.4, 0.4, F + 1.7, F + 2.2, "Hull")
            with n.at(T(0.28, 0.0, F + 1.85), RY(90.0)):
                n.lathe([(0.2, 0.0), (0.2, 0.02), (0.18, 0.02)], "Hazard", seg=12, smooth=False)
        plan.circle(*polar(ry_ - 0.3, 90.0), 0.3, tag="hoop")
        for k in range(fu["stands"]):
            a = 360.0 * k / fu["stands"] + 45.0
            stands.append(polar(1.1, a) + (a + 180.0, "Yard_%d" % k))
    if ncell < 8:
        # a yard strip (critic round 33): rubber floor, a pull-up bar and a bench, at -Y
        yx, yy = 0.2, -(R - 1.3)
        with n.at(T(yx, yy, 0.0)):
            bbox(n, -1.4, 1.4, -0.7, 0.7, F, F + 0.008, "Rubber", mats={"-z": None})
            plate_z(n, F + 0.009, -1.35, 1.35, 0.62, 0.66, "Hazard")
            for sx in (-1, 1):
                n.vcyl(sx * 0.5 - 0.6, 0.3, F, F + 2.0, 0.035, seg=6, mat="Frame", cap0=False)
            n.cyl((-1.1, 0.3, F + 2.0), (-0.1, 0.3, F + 2.0), 0.025, seg=6, mat="Metal")
            with n.at(T(0.8, 0.0, 0.0), RZ(90.0)):
                V5.bench(n, L=1.1)
        plan.rect(yx - 0.6, yy + 0.3, 0.55, 0.1, tag="bar")
        plan.rect(yx + 0.8, yy, 0.55, 0.24, tag="bench")
        stands.append((yx - 0.6, yy - 0.3, 90.0, "Yard_0"))
    k = 0
    for (x, y, yaw, al) in stands:
        anchor(plan, "Stand", x, y, yaw, alias=al)
        k += 1
    if k < fu["stands"]:
        plan.stands(fu["stands"] - k)
    pattern = ["panel", "vent", "cab_lamp", "panel", "lockers"]
    plan.wall_items(pattern, IR.wall_set(plan), open_every=2, seed=6 + s, depth_of=IR.DEPTHS)
    fill(plan, [(lambda p_, x, y, k_: _day_table(p_, x, y, k_), 1.0), (f_bench, 0.75),
                (lambda p_, x, y, k_: _crates(p_, x, y, k_), 0.45)], target=1.9)
    plan.lights()
    plan.aisles()
    plan.v4_patch = IR.empty_patch(plan)[0]


INTERIORS = {
    "retail": retail,
    "park": park,
    "academy": academy,
    "security_office": security_office,
    "jail": jail,
}
