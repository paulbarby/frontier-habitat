"""
Frontier Habitat 3.0 - ART-HAB interiors: farms (greenhouse, fungus farm, algae bioreactor) and logistics
(storehouse, cold storage).  Greenhouse and fungus farm keep the tray contract (content tray_offsets, soil top
0.55; checked by rooms_build.py); their Work anchor i stands next to tray i.
"""
import random
from math import sin, cos, radians, degrees, hypot, sqrt, atan2

import interior_kit as IK
import interior_furniture as FU
from rooms_kit import T, RZ, SOIL_Z
from interior_kit import F, Plan, bbox, plate_x, plate_y, plate_z, furniture_of
from interior_rooms import at, wall_set, DEPTHS, finish
from interior_families import fill_decor, console_at, chord_x, DECOR, NEED


def tray_work_anchors(plan, offs, hx=1.5, hy=0.7):
    """One Work anchor next to tray i, on the long side with more free floor, facing the tray."""
    for i, (cx, cy) in enumerate(offs):
        best, bd = None, -2.0
        for side in (-1, 1):
            y = cy + side * (hy + 0.33)
            d = plan.dist(cx, y)
            if hypot(cx, y) > plan.Ri - 0.45:
                d = -1.0
            if d > bd:
                best, bd = (cx, y, 90.0 if side < 0 else -90.0), d
        plan.anchor("Work", best[0], best[1], best[2])


def greenhouse(rm):
    import rooms_agri as RA
    s = rm.size
    fu = furniture_of(rm)
    plan = Plan(rm)
    IK.build_floor_v3(rm, "clean", "grid", grid=1.2)
    n = plan.n
    offs = RA.tray_offsets(rm)
    xs = sorted(set(round(o[0], 3) for o in offs))
    rows = sorted(set(round(o[1], 3) for o in offs))
    for (cx, cy) in offs:            # light walkway pads round each tray
        bbox(n, cx - 1.75, cx + 1.75, cy - 0.95, cy + 0.95, F, F + 0.006, "Floor", mats={"-z": None})
    for (cx, cy) in offs:
        RA.crop_tray(n, cx, cy)
        rm.trays.append((cx, cy))
        plan.rect(cx, cy, 1.52, 0.72, 0.0, tag="tray")
        n.cyl((cx - 1.45, cy - 0.62, SOIL_Z + 0.05), (cx + 1.45, cy - 0.62, SOIL_Z + 0.05), 0.025, seg=5,
              mat="WaterBlue", cap0=False, cap1=False)
        # grow lights: two narrow bars on posts along the long sides (the crop stays visible from above)
        for sy in (-1, 1):
            for sx in (-1, 1):
                bbox(n, cx + sx * 1.45 - 0.03, cx + sx * 1.45 + 0.03, cy + sy * 0.66 - 0.03, cy + sy * 0.66 + 0.03,
                     SOIL_Z + 0.08, F + 1.85, "Frame")
            bbox(n, cx - 1.48, cx + 1.48, cy + sy * 0.66 - 0.05, cy + sy * 0.66 + 0.05, F + 1.80, F + 1.88, "Frame")
            plate_z(n, F + 1.797, cx - 1.42, cx + 1.42, cy + sy * 0.66 - 0.035, cy + sy * 0.66 + 0.035, "Light")
    for y in rows:                   # floor manifold along each tray row
        x0, x1 = min(xs) - 1.6, max(xs) + 1.6
        n.cyl((x0, y - 0.78, F + 0.06), (x1, y - 0.78, F + 0.06), 0.045, seg=6, mat="WaterBlue")
    tray_work_anchors(plan, offs)
    fill_decor(plan, ["planter", "cart", "pallets"], max_n=(1, 2, 2, 3)[s], walk=0.7, seed=71 + s, align=0.0)
    plan.wall_items(["planter", "shelf", "tap", "toolwall", "planter", "cab_box", "panel"],
                    wall_set(plan), open_every=3, seed=71 + s, depth_of=DEPTHS, skip=ring_blocked(plan, offs))
    plan.stands(fu["stands"])
    finish(plan)


def plate_zd(p, z, x0, x1, y0, y1, mat):
    """Horizontal plate facing down (a light strip under a board)."""
    p.quad((x0, y0, z), (x0, y1, z), (x1, y1, z), (x1, y0, z), mat)


def mushroom_cluster(n, x, y, z, rng, k=4, h=0.10, r=0.07):
    """A small cluster of capped mushrooms (stems Frost, caps Wood) standing on z."""
    for m in range(k):
        a = radians(360.0 * m / k + rng.uniform(-25, 25))
        d = rng.uniform(0.02, 0.07)
        hh = h * rng.uniform(0.7, 1.25)
        rr = r * rng.uniform(0.7, 1.2)
        mx, my = x + d * cos(a), y + d * sin(a)
        n.vcyl(mx, my, z, z + hh, rr * 0.25, seg=4, mat="Frost", cap0=False, cap1=False, smooth=False)
        with n.at(T(mx, my, z + hh)):
            n.lathe([(0.0, -0.2 * rr), (rr, 0.0), (0.0, 0.45 * rr)], "Wood", seg=5, smooth=True)


def wi_mushroom_shelf(p, w=0.80, d=0.36, h=1.20, seed=0):
    """Wall shelf (x 0 = wall .. d = room side) of substrate blocks with mushroom clusters, a violet grow strip
    under each board."""
    rng = random.Random(seed)
    plate_x(p, 0.02, -w / 2, w / 2, F, F + h, "HullDark")
    for sy in (-1, 1):
        bbox(p, 0.0, d, sy * w / 2 - 0.025, sy * w / 2 + 0.025, F, F + h, "Frame")
    for z in (F + 0.10, F + 0.52, F + 0.94):
        bbox(p, 0.02, d, -w / 2 + 0.025, w / 2 - 0.025, z, z + 0.03, "Frame")
        if z < F + 0.9:
            plate_zd(p, z + 0.40, 0.05, d - 0.04, -w / 2 + 0.05, w / 2 - 0.05, "L4Band")
        for jj in range(2):
            yy = -w / 4 + w / 2 * jj
            bbox(p, 0.06, d - 0.06, yy - 0.15, yy + 0.15, z + 0.03, z + 0.17, "Soil")
            mushroom_cluster(p, d / 2, yy + rng.uniform(-0.05, 0.05), z + 0.17, rng, k=2, h=0.09, r=0.07)


def fungus_farm(rm):
    """Fungus farm (critic round 4): the game's crop_mushroom model IS the shelf rack (1.45 m, three shelves), so
    the room gives each tray a bed, four corner posts with violet grow strips and a violet light canopy ABOVE the
    crop (nothing between 0.56 and 2.02 m over the bed); a lighter floor; mushroom shelves on the wall; a
    spawn-bag cart and incubator cabinets in the free floor."""
    import rooms_agri as RA
    s = rm.size
    fu = furniture_of(rm)
    plan = Plan(rm)
    IK.build_floor_v3(rm, "panel", "grid", grid=1.0)
    n = plan.n
    rng = random.Random(40 + s)
    offs = RA.tray_offsets(rm)
    top = min(F + 2.18, rm.headroom(0.0, 0.0) - 0.10)
    for (cx, cy) in offs:
        bbox(n, cx - 1.72, cx + 1.72, cy - 0.92, cy + 0.92, F, F + 0.006, "Floor", mats={"-z": None})
        RA.crop_tray(n, cx, cy, body="HullDark", stripe="L4Band")
        rm.trays.append((cx, cy))
        plan.rect(cx, cy, 1.52, 0.72, 0.0, tag="rack")
        for sx in (-1, 1):
            for sy in (-1, 1):
                x, y = cx + sx * 1.47, cy + sy * 0.67
                bbox(n, x - 0.035, x + 0.035, y - 0.035, y + 0.035, SOIL_Z + 0.08, top, "Frame")
                # violet strip on the inner face of each post (the grow light of the crop shelves)
                plate_y(n, y - sy * 0.037, x - 0.02, x + 0.02, SOIL_Z + 0.25, top - 0.15, "L4Band", facing=-sy)
        for sy in (-1, 1):
            bbox(n, cx - 1.50, cx + 1.50, cy + sy * 0.67 - 0.045, cy + sy * 0.67 + 0.045, top - 0.07, top, "Frame")
        for k in range(3):
            xx = cx - 1.0 + 1.0 * k
            bbox(n, xx - 0.05, xx + 0.05, cy - 0.70, cy + 0.70, top - 0.06, top - 0.01, "Frame")
            plate_zd(n, top - 0.062, xx - 0.035, xx + 0.035, cy - 0.62, cy + 0.62, "L4Band")
        n.cyl((cx - 1.5, cy + 0.72, top + 0.04), (cx + 1.5, cy + 0.72, top + 0.04), 0.025, seg=5, mat="WaterBlue",
              cap0=False, cap1=False)
    tray_work_anchors(plan, offs)
    fill_decor(plan, ["incubator", "cart", "bottles"], max_n=(1, 1, 2, 3)[s], walk=0.7, seed=81 + s, align=0.0)
    plan.wall_items(["mushroom", "vent", "mushroom", "cable", "panel", "mushroom", "fridge"],
                    tray_wall_set(plan, offs), open_every=3, seed=81 + s, depth_of=dict(DEPTHS, mushroom=0.36),
                    skip=ring_blocked(plan, offs))
    plan.stands(fu["stands"])
    finish(plan)


def ring_blocked(plan, offs, hx=1.52, hy=0.72):
    """Wall segments behind a tray that reaches into the walking ring: left empty, so people can pass between the
    tray and the wall (the tray positions are content data)."""
    out = []
    for k in range(IK.NSEG):
        a = IK.seg_mid(k)
        for dd in (-0.35, 0.0, 0.35):
            aa = a + degrees(dd / plan.wall_front)
            x, y = (plan.wall_front - 0.05) * cos(radians(aa)), (plan.wall_front - 0.05) * sin(radians(aa))
            if any(max(abs(x - cx) - hx, 0.0) ** 2 + max(abs(y - cy) - hy, 0.0) ** 2 < (plan.clear + 0.05) ** 2
                   for (cx, cy) in offs):
                out.append(k)
                break
    return out


def tray_wall_set(plan, offs):
    ws = wall_set(plan)
    ws["mushroom"] = lambda p, w, d, k: wi_mushroom_shelf(p, w=w, d=min(d, 0.36), seed=k)
    return ws


def d_incubator(plan, x, y, yaw, k):
    """Incubator cabinet with a glass door (spawn bags inside) and a violet lamp."""
    n = plan.n
    with at(n, x, y, yaw):
        bbox(n, -0.35, 0.35, -0.35, 0.35, F, F + 1.55, "Hull", bevel=0.03)
        plate_x(n, 0.352, -0.28, 0.28, F + 0.20, F + 1.40, "Frost")
        for j in range(4):
            plate_x(n, 0.354, -0.24, 0.24, F + 0.30 + 0.28 * j, F + 0.32 + 0.28 * j, "L4Band")
        bbox(n, -0.30, 0.30, -0.30, 0.30, F + 1.55, F + 1.62, "Frame")
    return 0.55


def culture_tube(n, x, y, z0, z1, r, seg=8):
    """Clear photobioreactor tube: a glass shell (Glass) round a glowing green culture (Glow), frame collars."""
    n.vcyl(x, y, z0, z0 + 0.14, r + 0.05, seg=seg, mat="Frame", cap0=False)
    n.vcyl(x, y, z0 + 0.14, z1 - 0.14, r * 0.72, seg=seg, mat="Glow", cap0=False, cap1=False)
    n.vcyl(x, y, z0 + 0.14, z1 - 0.14, r, seg=seg, mat="Glass", cap0=False, cap1=False)
    n.vcyl(x, y, z1 - 0.14, z1, r + 0.05, seg=seg, mat="Frame", cap0=False)
    n.vcyl(x, y, z1, z1 + 0.10, 0.04, seg=5, mat="Metal", cap0=False)


def algae_bioreactor(rm):
    """Algae bioreactor (critic round 4): rows of clear tubes with a glowing culture, each row on a manifold skid
    with a feed pipe below and a gas header above; a pump skid and the console in the central aisle."""
    s = rm.size
    fu = furniture_of(rm)
    plan = Plan(rm)
    IK.build_floor_v3(rm, "clean", "grid", grid=1.25)
    n = plan.n
    rmax = plan.r_max
    hr = rm.headroom(0.0, 0.0)
    ztop = min(F + 1.95, hr - 0.30)
    tr = 0.20 + 0.02 * s
    pitch_t = 2 * tr + 0.26
    rows = []
    y = 1.05
    while y + tr + 0.3 < rmax - 0.2:
        rows += [y, -y]
        y += 1.55
    # the central aisle: pump skid and a buffer tank, a console
    with at(n, 0.0, 0.0, 0.0):
        bbox(n, -0.75, 0.75, -0.40, 0.40, F, F + 0.10, "Frame", bevel=0.01)
    FU.pump(n, -0.30, 0.0, 0.0)
    FU.tank(n, 0.40, 0.0, 0.9, 0.30, mat="Metal", band="Accent", legs=False, seg=10)
    plan.rect(0.0, 0.0, 0.8, 0.45, 0.0, tag="skid")
    for yy in rows:
        half = chord_x(plan, abs(yy) + tr + 0.3, 0.15)
        nt = int((2 * half - 0.4) // pitch_t)
        if nt < 2:
            continue
        L = (nt - 1) * pitch_t
        # skid, feed manifold, gas header on two end frames
        bbox(n, -L / 2 - 0.30, L / 2 + 0.30, yy - 0.30, yy + 0.30, F, F + 0.10, "Frame", bevel=0.01)
        plate_z(n, F + 0.102, -L / 2 - 0.25, L / 2 + 0.25, yy - 0.25, yy + 0.25, "HullDark")
        sy = -1.0 if yy > 0 else 1.0                       # the manifolds run on the aisle side
        n.cyl((-L / 2 - 0.25, yy + sy * (tr + 0.10), F + 0.24), (L / 2 + 0.25, yy + sy * (tr + 0.10), F + 0.24),
              0.07, seg=6, mat="Metal")
        n.cyl((-L / 2 - 0.10, yy, ztop + 0.14), (L / 2 + 0.10, yy, ztop + 0.14), 0.06, seg=6, mat="WaterBlue")
        for sx in (-L / 2 - 0.22, L / 2 + 0.22):
            bbox(n, sx - 0.04, sx + 0.04, yy - 0.04, yy + 0.04, F + 0.10, ztop + 0.20, "Frame")
        for k in range(nt):
            x = -L / 2 + pitch_t * k
            culture_tube(n, x, yy, F + 0.10, ztop, tr, seg=8)
            n.cyl((x, yy + sy * tr, F + 0.24), (x, yy + sy * (tr + 0.10), F + 0.24), 0.03, seg=4, mat="Metal",
                  cap0=False, cap1=False)
        plan.rect(0.0, yy, L / 2 + 0.32, 0.32 + 0.10, 0.0, tag="tubes")
        # feed from the pump to the row
        n.cyl((0.0, 0.0, F + 0.08), (0.0, yy + sy * (tr + 0.10), F + 0.08), 0.05, seg=5, mat="Metal")
        FU.floor_line(n, -L / 2 - 0.3, yy + sy * 0.55, L / 2 + 0.3, yy + sy * 0.55, w=0.05, mat="Accent")
    console_at(plan, 1.35, 0.0, 180.0, w=0.8, work=False)
    fill_decor(plan, ["cart", "bottles", "drums"], max_n=(0, 0, 1, 2)[s], walk=0.7, seed=91 + s, align=0.0)
    plan.wall_items(["shelf", "vent", "cable", "panel", "fridge"], wall_set(plan), open_every=3, seed=91 + s,
                    depth_of=DEPTHS)
    plan.stands(fu["stands"], [(-1.3, 0.0, 0.0), (2.0, 0.0, 180.0), (-2.0, 0.0, 0.0)])
    finish(plan)


def pallet_rack(plan, x, y, L, h=2.1, cold=False, seed=0):
    """Pallet rack along X (length L, depth 1.0), 3 beam levels with loads."""
    n = plan.n
    rng = random.Random(seed)
    up = "Trim" if cold else "Hazard"
    nb = max(1, int(L / 1.35))
    bay = L / nb
    with at(n, x, y, 0.0):
        for b in range(nb + 1):
            xx = -L / 2 + bay * b
            for sy in (-0.45, 0.45):
                bbox(n, xx - 0.04, xx + 0.04, sy - 0.04, sy + 0.04, F, F + h, up)
            n.beam((xx, -0.45, F + h * 0.5), (xx, 0.45, F + h * 0.5), 0.03, 0.03, "Frame")
        for lv, z in enumerate((F + 0.08, F + 0.80, F + 1.52)):
            for sy in (-0.45, 0.45):
                bbox(n, -L / 2, L / 2, sy - 0.04, sy + 0.04, z, z + 0.08, "Frame")
            for b in range(nb):
                xx = -L / 2 + bay * (b + 0.5)
                if rng.random() < 0.82:
                    if cold:
                        bbox(n, xx - bay * 0.4, xx + bay * 0.4, -0.40, 0.40, z + 0.08, z + 0.55,
                             rng.choice(("Frost", "Hull", "Accent")), bevel=0.02)
                    else:
                        with n.at(T(xx, 0, z + 0.08 - F)):
                            FU.pallet(n, 0.0, 0.0, 0.0, load=rng.choice((1, 1, 2)), seed=seed * 7 + b + lv)
        if cold:
            bbox(n, -L / 2, L / 2, -0.06, 0.06, F + h - 0.04, F + h, "Frame")
            plate_z(n, F + h + 0.001, -L / 2, L / 2, -0.05, 0.05, "L3Band")
    plan.rect(x, y, L / 2 + 0.05, 0.52, 0.0, tag="rack")


def racks_room(rm, cold=False):
    import rooms_habitat as RH
    s = rm.size
    fu = furniture_of(rm)
    plan = Plan(rm)
    IK.build_floor_v3(rm, "frost" if cold else "grate", "grid", grid=1.3)
    n = plan.n
    rmax = plan.r_max
    D = getattr(rm, "D", None) or 2.7
    h = min(2.1, D - 0.35)
    pitch = 2.7
    nrows = max(1, int((2 * rmax - 1.6) // pitch))
    ys = [(j - (nrows - 1) / 2) * pitch for j in range(nrows)]
    for j, y in enumerate(ys):
        L = min(6.8, 2 * chord_x(plan, abs(y) + 0.55, 0.1) - 1.4)
        if L < 1.4:
            continue
        pallet_rack(plan, 0.3, y, L, h=h, cold=cold, seed=j + 10 * s)
        for sy in (-1, 1):
            FU.floor_line(n, 0.3 - L / 2, y + sy * 0.70, 0.3 + L / 2, y + sy * 0.70, w=0.06,
                          mat="L3Band" if cold else "Hazard")
    gaps = [y + pitch / 2 for y in ys[:-1]] or [ys[0] - 1.4]
    if cold:
        for yy in gaps:
            xx = -chord_x(plan, abs(yy) + 0.5, 0.2) + 0.9
            with at(n, xx, yy, 0.0):
                bbox(n, -0.7, 0.7, -0.40, 0.40, F, F + 0.85, "Frost", bevel=0.03)
                bbox(n, -0.66, 0.66, -0.36, 0.36, F + 0.85, F + 0.90, "Glass")
                plate_y(n, -0.402, -0.6, 0.6, F + 0.68, F + 0.72, "Accent", facing=-1)
            plan.rect(xx, yy, 0.72, 0.42, 0.0, tag="freezer")
    elif s >= 1:
        yy = gaps[0]
        fx = -chord_x(plan, abs(yy) + 0.6, 0.3) + 1.6
        RH.forklift(n, fx, yy, 0.0)
        plan.rect(fx + 0.2, yy, 1.05, 0.5, 0.0, tag="forklift")
    fill_decor(plan, ["pallets", "cart"], max_n=(0, 1, 2, 3)[s], walk=0.75, seed=101 + s, align=0.0)
    items = ["freezer", "rack", "freezer", "panel", "lockers"] if cold else ["rack", "toolwall", "rack", "lockers",
                                                                              "cable", "rack"]
    plan.wall_items(items, wall_set(plan), open_every=3, seed=101 + s, depth_of=DEPTHS)
    cands = [(-rmax * 0.45, yy, 0.0) for yy in gaps] + [(rmax * 0.45, yy, 180.0) for yy in gaps]
    plan.stands(fu["stands"], cands)
    finish(plan)


def storehouse(rm):
    racks_room(rm, cold=False)


def cold_storage(rm):
    racks_room(rm, cold=True)


DECOR["incubator"] = d_incubator
NEED["incubator"] = 0.55

INTERIORS = {
    "greenhouse": greenhouse,
    "fungus_farm": fungus_farm,
    "algae_bioreactor": algae_bioreactor,
    "storehouse": storehouse,
    "cold_storage": cold_storage,
}
