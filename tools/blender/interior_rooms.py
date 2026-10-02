"""
Frontier Habitat 3.0 - ART-HAB room interiors for every room type and size (Blender 5.2, --background only).

build_room_v3(rm) runs the v2 EXTERIOR builder of the type in "v3 mode" (rooms_kit.Room.build_base makes the
foundation and the 32 wall segments, no fake +X door except the airlock's real one), throws away the v2 interior,
moves wall-mounted exterior details into their wall segments, and builds the 3.0 interior of the type here.

Every family has its own layout language (round-2 critique: "rooms must not look alike"):
  habitat      cabins (S) / bays of two beds with privacy screens round a commons (M, L, XL)
  comfort      lounge: conversation islands on rugs facing a media wall; cantina: straight bar + a bistro grid
  medical      treatment bays in a row with curtains + a nurse station; bio-lab: bench rows + a fume hood
  food         kitchen: galley line + long mess tables in rows; greenhouse / fungus: tray grid + walkways;
               algae: a grid of glowing culture columns round a pump skid
  industry     one machine on a hazard plinth, a control line, walkways painted on a grate floor
  science      research lab: desk pods round a holo table; assembler: a conveyor line with a robot arm
  life         equipment islands with a service walkway
  logistics    storehouse / cold storage: parallel rack aisles
  links        airlock: suit bay; junction: an open hub
Anchor counts come from content/buildings.json `furniture` (SIM, final) and are checked by rooms_build.py.
"""
import math
import os
import random
from math import sin, cos, radians, degrees, hypot, sqrt, atan2, asin, pi
from mathutils import Vector

import rooms_kit as K
import interior_kit as IK
import interior_furniture as FU
from rooms_kit import P, T, RX, RY, RZ, polar, FLOOR_Z, WALL_TOP, SOIL_Z
from interior_kit import (F, Plan, bbox, plate_x, plate_y, plate_z, ui_screen, furniture_of, seg_mid, SEAT_BACK,
                          BED_BACK, CONSOLE_AHEAD, BENCH_AHEAD)

BED_W, BED_L = FU.BED_W, FU.BED_L
GAP = 0.55                       # between the two beds of a bay (the inner bed's stand point is in it)
BAY_HW = GAP / 2 + BED_W + 0.035  # half width of a bay (blanket overhang)
BAY_L = BED_L + 0.07 + 0.035      # head back line to the foot of the blanket


def at(p, x, y, yaw):
    return p.at(T(x, y, 0), RZ(yaw))


def world(p, x, y, z):
    v = p._stack[-1] @ Vector((x, y, z))
    return v.x, v.y, v.z


def lamp_cb(plan, p):
    return lambda x, y, z: plan.lamp(*world(p, x, y, z))


# --------------------------------------------------------------------------------------
# Wall-item sets
# --------------------------------------------------------------------------------------
def wall_set(plan, extra=None):
    """The common wall-item builders: {kind: fn(p, w, d, k)}."""
    def cab(deco):
        return lambda p, w, d, k: FU.wi_cabinet(p, w=w, d=d, deco=deco, seed=k, lamp_cb=lamp_cb(plan, p))
    out = {
        "wardrobe": lambda p, w, d, k: FU.wi_wardrobe(p, w=w, d=d, h=1.20),
        "lockers": lambda p, w, d, k: FU.wi_lockers(p, w=w, d=min(d, 0.40), h=1.10),
        "shelf": lambda p, w, d, k: FU.wi_shelf(p, w=w, d=min(d, 0.36), h=1.15, seed=k),
        "planter": lambda p, w, d, k: FU.wi_planter(p, w=w, d=min(d, 0.36), seed=k),
        "desk": lambda p, w, d, k: FU.wi_desk(p, w=w, d=min(d, 0.44), seed=k),
        "tap": lambda p, w, d, k: FU.wi_tap(p, w=min(w, 0.62), d=min(d, 0.40)),
        "panel": lambda p, w, d, k: FU.wi_panel(p, w=w, seed=k),
        "vent": lambda p, w, d, k: FU.wi_vent(p, w=w, seed=k),
        "poster": lambda p, w, d, k: FU.wi_poster(p, w=w, seed=k),
        "plant": lambda p, w, d, k: FU.wi_plant(p, w=w, seed=k),
        "cabinet": cab(None),
        "cab_lamp": cab("lamp+plant"),
        "cab_books": cab("lamp+books"),
        "cab_plant": cab("plant"),
        "cab_box": cab("box"),
        "medcab": lambda p, w, d, k: FU.wi_medcab(p, w=w, d=min(d, 0.36)),
        "toolwall": lambda p, w, d, k: FU.wi_toolwall(p, w=w, seed=k),
        "rack": lambda p, w, d, k: FU.wi_rack(p, w=w, d=d, seed=k),
        "fridge": lambda p, w, d, k: FU.wi_fridge(p, w=min(w, 0.72), d=d),
        "suitrack": lambda p, w, d, k: FU.wi_suitrack(p, w=w),
        "freezer": lambda p, w, d, k: FU.wi_freezer(p, w=w, d=d),
        "bottles": lambda p, w, d, k: FU.wi_bottles(p, w=w, seed=k),
        "cable": lambda p, w, d, k: FU.wi_cable(p, w=w, seed=k),
    }
    import interior_props as PR          # 5.0 (V5 15.3): parody / satire wall pieces
    out.update(PR.WALL_KINDS)
    out.update(extra or {})
    return out


DEPTHS = {"shelf": 0.36, "planter": 0.36, "desk": 0.62, "tap": 0.40, "panel": 0.08, "vent": 0.08, "poster": 0.08,
          "plant": 0.40, "lockers": 0.40, "medcab": 0.36, "toolwall": 0.30, "suitrack": 0.40, "bottles": 0.30,
          "cable": 0.20, "aiposter": 0.08, "filmposter": 0.08, "notice": 0.08, "vibeposter": 0.08, "kettle": 0.42,
          "shrine": 0.40,
          "agents": 0.08, "menu": 0.08}


def stand_at_wall(plan, placed, kind):
    """A stand anchor in the walking ring in front of the first wall item of `kind`, facing it."""
    for k, kd in sorted(placed.items()):
        if kd == kind:
            a = seg_mid(k)
            r = plan.wall_front - 0.28
            plan.anchor("Stand", r * cos(radians(a)), r * sin(radians(a)), a)
            return True
    return False


# (critic round 4) the family accent light of each room: Anchor_Accent_<i> over these footprints.  RENDER colours
# it by the family (docs/requests/ART-HAB-to-RENDER.md): neon, grow light, holo glow, hazard amber ...
ACCENT_TAGS = {
    "habitat": ("table", "pod"), "lounge": ("media", "island"), "cantina": ("bar", "booth"),
    "kitchen": ("cook",), "medical": ("curtain", "desk"), "bio_lab": ("hood", "bench"),
    "research_lab": ("holo", "desk"), "research_assembler": ("line",), "greenhouse": ("tray",),
    "fungus_farm": ("rack",), "algae_bioreactor": ("tubes",), "storehouse": ("rack",), "cold_storage": ("freezer", "rack"),
    "oxygen_plant": ("machine", "tanks"), "water_recycler": ("machine", "uv"), "atmo_processor": ("machine", "comp"),
    "airlock": ("suit", "bench"), "junction": ("post",),
}


def accents(plan):
    rm = plan.rm
    tags = ACCENT_TAGS.get(rm.tid, ("machine", "machine2", "line"))
    nmax = 2 if rm.single else (2, 3, 4, 5)[rm.size]
    pts = [(r[0], r[1]) for r in plan.rects if r[5] in tags] + [(c[0], c[1]) for c in plan.circles if c[3] in tags]
    chosen = []
    for (x, y) in pts:
        if all(hypot(x - a, y - b) > 1.6 for a, b in chosen):
            chosen.append((x, y))
        if len(chosen) >= nmax:
            break
    for (x, y) in chosen:
        z = min(F + 1.9, rm.headroom(x, y) - 0.15)
        i = plan.count.get("Accent", 0)
        plan.count["Accent"] = i + 1
        rm.anchor("Accent_%d" % i, (x, y, z), 0.0)


# 4.0 (V4_DESIGN section 2, critic round 17 fix 4): the 1.5 x rooms are filled BY FUNCTION: no empty floor patch
# wider than V4_MAX_PATCH outside the walkways.  A greedy filler puts a family item in the centre of the largest
# empty patch (keeping 0.7 m round it free and clear of every people anchor) until no patch is wider.
V4_MAX_PATCH = 1.9          # 5.0 (V5 15.3): was 2.5; the role decor (small pieces) fills the patches between 1.9 and 2.5 m
V4_MIN_HEAD = 2.0           # decor stands only where the roof is at least this high (tall racks 1.9 m)
V4_KINDS = {"housing": ["lounge", "lockers", "plant", "reading", "light"],
            "comfort": ["lounge", "gametable", "plant", "reading", "light"],
            "food": ["serving", "pantry", "planter", "cart", "bottles", "plant"],
            "industry": ["wbench", "racks", "crates", "pallets", "cart"],
            "science": ["deskpod", "server", "specimen", "glovebox", "labfridge", "plant"],
            "medical": ["labfridge", "cart", "bench", "plant"],
            "life_support": ["tanks", "unit", "cart", "plant"],
            "logistics": ["pallets", "racks", "crates", "cart"]}


def d_lounge(plan, x, y, yaw, k):
    """A lounge corner: a two-seat sofa facing a low table (decor: no seat anchors)."""
    n = plan.n
    with at(n, x, y, yaw):
        with n.at(T(-0.45, 0, 0)):
            FU.sofa(n, n=2, fabric=("Cushion", "Fabric")[k % 2])
        bbox(n, 0.25, 0.85, -0.45, 0.45, F, F + 0.38, "Wood", bevel=0.02)
        FU.pot_plant(n, 0.55, 0.30, r=0.12, h=0.25, s=0.6, seed=k, z0=F + 0.38)
    return 1.05


def d_lockers(plan, x, y, yaw, k):
    """Two tall lockers back to back (decor)."""
    n = plan.n
    with at(n, x, y, yaw):
        for sx in (-0.26, 0.26):
            with n.at(T(sx, 0, F), RZ(0.0 if sx < 0 else 180.0)):
                K.locker(n, w=0.9, d=0.48, h=1.75)
    return 0.62


def d_wbench(plan, x, y, yaw, k):
    """A second-line workbench with a vice, a tool board and a stool (decor)."""
    n = plan.n
    with at(n, x, y, yaw):
        K.workbench(n, w=1.8, d=0.75, stripe="Accent")
    return 1.0


def d_deskpod(plan, x, y, yaw, k):
    """Two lab desks back to back with a divider (unstaffed stations: no work anchors)."""
    n = plan.n
    c, s_ = cos(radians(yaw)), sin(radians(yaw))
    # Paul 2026-10-01: back to back, each top from the divider out (they overlapped by 0.56 m before)
    for side in (-1, 1):
        _FAMX.sit_desk(plan, x + side * 0.65 * c, y + side * 0.65 * s_, yaw + (0.0 if side > 0 else 180.0),
                       w=1.2, d=0.62, monitors=1, seed=k + side, work=False, chair=True)
    with at(n, x, y, yaw + 90.0):
        bbox(n, -0.62, 0.62, -0.025, 0.025, F + 0.74, F + 1.08, "Hull", bevel=0.01)
    return 1.30


def d_serving(plan, x, y, yaw, k):
    """A serving line: a counter with a sneeze guard and food trays (decor)."""
    n = plan.n
    with at(n, x, y, yaw):
        bbox(n, -0.35, 0.35, -1.0, 1.0, F, F + 0.88, "Hull", bevel=0.02)
        bbox(n, -0.37, 0.37, -1.02, 1.02, F + 0.88, F + 0.92, "Metal", bevel=0.008)
        for j in range(4):
            bbox(n, -0.22, 0.22, -0.85 + 0.45 * j, -0.50 + 0.45 * j, F + 0.92, F + 0.97,
                 ("Plant", "Wood", "Accent", "Plant")[j])
        bbox(n, -0.02, 0.02, -1.0, 1.0, F + 1.15, F + 1.40, "Glass")
        bbox(n, -0.03, 0.03, -1.0, 1.0, F + 1.40, F + 1.43, "Frame")
    return 1.05


def d_pantry(plan, x, y, yaw, k):
    """A pantry island: two shelf racks back to back full of stores (decor)."""
    n = plan.n
    with at(n, x, y, yaw):
        for sx in (-0.30, 0.30):
            with n.at(T(sx, 0, F), RZ(0.0 if sx < 0 else 180.0)):
                K.shelf_rack(n, w=1.6, d=0.5, h=1.7, levels=4, fill=0.85, seed=k * 3 + (sx > 0))
    return 0.95


def _register_v4_decor():
    import interior_roles_decor as _RD        # 5.0 (V5 15.3): role decor (vending, server cabinet, gnome ...)
    _RD.register_decor(_FAMX.DECOR, _FAMX.NEED, V4_KINDS)
    for k_, f_, r_ in (("lounge", d_lounge, 1.05), ("lockers", d_lockers, 0.62), ("wbench", d_wbench, 1.0),
                       ("deskpod", d_deskpod, 1.30), ("serving", d_serving, 1.05), ("pantry", d_pantry, 0.95)):
        _FAMX.DECOR.setdefault(k_, f_)
        _FAMX.NEED.setdefault(k_, r_)


def empty_patch(plan, step=0.3, people=None):
    """(largest empty-patch diameter in m, its centre): floor inside r_max, measured to the nearest footprint or
    the r_max edge; floor within 0.9 m of a people anchor counts as their free floor, not as empty."""
    rm = plan.rm
    if people is None:
        people = _people(rm)
    best, where = 0.0, None
    m = int(plan.r_max // step)
    for i in range(-m, m + 1):
        for j in range(-m, m + 1):
            x, y = i * step, j * step
            r = hypot(x, y)
            if r > plan.r_max - 0.2:
                continue
            if any(hypot(x - ax, y - ay) < 0.9 for (ax, ay) in people):
                continue
            if rm.headroom(x, y) < V4_MIN_HEAD:
                continue
            e = min(plan.dist(x, y), plan.r_max - r)
            if e > best:
                best, where = e, (x, y)
    return 2.0 * best, where


def _people(rm):
    return [a[1][:2] for a in rm.anchors
            if a[0].startswith(("Anchor_Bed", "Anchor_Seat", "Anchor_Work", "Anchor_Stand", "Anchor_Tray",
                                "Anchor_Chamber", "Anchor_Suit"))]


def _fit_under_roof(rm, part, n0, gap=0.05):
    """A decor item (the vertices added since n0) taller than the roof over it is scaled down in height about the
    floor, as a whole."""
    vs = part.verts[n0:]
    if not vs:
        return
    top = max(v.z for v in vs)
    lim = min(rm.headroom(v.x, v.y) for v in vs) - gap
    if top <= lim:
        return
    k = (lim - F) / max(1e-6, top - F)
    for v in vs:
        if v.z > F:
            v.z = F + (v.z - F) * k


def v4_decor(plan, max_items=40):
    rm = plan.rm
    _register_v4_decor()
    kinds = [k_ for k_ in V4_KINDS.get(rm.tid, V4_KINDS.get(rm.cat, ["plant", "cart"])) + ["cart", "plant", "light"]
             if k_ in _FAMX.DECOR]
    kinds = list(dict.fromkeys(kinds))
    if not kinds:
        return 0
    people = _people(rm)
    placed, tried = 0, set()
    used_n = {}
    k = 0
    for _ in range(max_items * 3):
        if placed >= max_items:
            break
        # the largest patch not yet tried
        best, where = 0.0, None
        step = 0.3
        m = int(plan.r_max // step)
        for i in range(-m, m + 1):
            for j in range(-m, m + 1):
                x, y = i * step, j * step
                if (i, j) in tried:
                    continue
                r = hypot(x, y)
                if r > plan.r_max - 0.2 or any(hypot(x - ax, y - ay) < 0.9 for (ax, ay) in people):
                    continue
                if rm.headroom(x, y) < V4_MIN_HEAD:        # under a ledge or a low roof part: not decor floor
                    continue
                e = min(plan.dist(x, y), plan.r_max - r)
                if e > best:
                    best, where, wij = e, (x, y), (i, j)
        if where is None or 2.0 * best <= V4_MAX_PATCH:
            break
        x, y = where
        # the biggest family item that leaves 0.7 m round it and keeps clear of the people anchors
        order = sorted(kinds, key=lambda q: -_FAMX.NEED[q])
        rot = order[k % len(order):] + order[:k % len(order)]
        done = False
        for kind in sorted(rot, key=lambda q: -_FAMX.NEED[q]):
            need = _FAMX.NEED[kind]
            if need > best - 0.6 or hypot(x, y) > plan.r_max - need - 0.05:
                continue
            import interior_roles_decor as _RD
            if used_n.get(kind, 0) >= _RD.cap_for(kind, rm):          # role decor: a few of each, not a field of bins
                continue
            if min(rm.headroom(x + need * cos(radians(a_)), y + need * sin(radians(a_))) for a_ in range(0, 360, 45))                     < V4_MIN_HEAD:
                continue
            if any(hypot(x - ax, y - ay) < need + (0.9 if need > 0.6 else 0.65) for (ax, ay) in people):
                continue
            yaw = degrees(atan2(y, x)) + 90.0
            n0 = len(plan.n.verts)
            rr = _FAMX.DECOR[kind](plan, x, y, yaw, k)
            _fit_under_roof(rm, plan.n, n0)
            plan.circle(x, y, rr, tag="decor")
            used_n[kind] = used_n.get(kind, 0) + 1
            placed += 1
            k += 1
            done = True
            break
        if not done:
            tried.add(wij)
    plan.v4_patch = empty_patch(plan, people=people)[0]
    return placed


def finish(plan, lights=None, aisle=True):
    if K.V4STYLE and K.R_SCALE > 1.0 and not os.environ.get("FH_NO_V4DECOR"):
        v4_decor(plan)
    import interior_roles as _RO
    _RO.floor_marks(plan)                  # 5.0 (V5 15.3): painted lane texts on the walking ring
    plan.lights(lights)
    accents(plan)
    if aisle:
        plan.aisles()


# --------------------------------------------------------------------------------------
# HABITAT
# --------------------------------------------------------------------------------------
BLANKETS = (("Fabric", "Cushion"), ("Cushion", "Fabric"), ("Accent", "Cushion"), ("Fabric", "Accent"),
            ("Cushion", "Accent"), ("Accent", "Fabric"))


def dress(i):
    """Neighbouring beds are never dressed the same: (dressing, pillows, blanket, throw, personal item)."""
    b, t = BLANKETS[(i * 5) % len(BLANKETS)]
    return (i % 3, 1 + (i // 2) % 2, b, t, FU.PERSONAL[(i * 2) % len(FU.PERSONAL)])


def bay(plan, hx, hy, dirdeg, i0, tall=True, screen_side=None):
    """Two beds side by side, heads on the line through (hx, hy) (the head-board back line), heads toward dirdeg.
    One shared bedside unit between the heads.  Adds 2 bed anchors (numbers i0, i0+1)."""
    n = plan.n
    rm = plan.rm
    c, s = cos(radians(dirdeg)), sin(radians(dirdeg))

    def to_w(bx, by):             # bay frame -> room: bx along dirdeg (toward the head), by lateral (ccw)
        return hx + c * bx - s * by, hy + s * bx + c * by
    xc = -(0.07 + BED_L / 2)
    for j, by in enumerate((-(GAP / 2 + BED_W / 2), GAP / 2 + BED_W / 2)):
        i = i0 + j
        dr, pil, bl, th, item = dress(i)
        wx, wy = to_w(xc, by)
        yaw = dirdeg - 90.0                    # bed frame +Y = toward the head
        hb = None
        if tall:
            ox, oy = to_w(0.0, by)
            hb = plan.tall(ox, oy)
        with at(n, wx, wy, yaw):
            FU.bed(n, dressing=dr, pillows=pil, blanket=bl, throw=th, side=1, hb=hb, style=(i * 2 + i // 3) % 3)
        plan.rect(wx, wy, BED_L / 2 + 0.07, BED_W / 2 + 0.035, dirdeg, tag="bed%d" % i)
        sx, sy = to_w(xc, by - BED_BACK)
        plan.anchor("Bed", sx, sy, yaw)
    # shared bedside unit in the gap at the heads
    ux, uy = to_w(-0.27, 0.0)
    _, _, _, _, item = dress(i0)
    with at(n, ux, uy, dirdeg - 90.0):
        FU.bedside(n, item=item, seed=i0, lamp_cb=lamp_cb(plan, n))
    plan.rect(ux, uy, 0.21, 0.23, dirdeg, tag="bed%d" % i0)


def habitat(rm):
    s = rm.size
    fu = furniture_of(rm)
    plan = Plan(rm, clear=0.65 if s < 1 else None)
    IK.build_floor_v3(rm, "panel", "radial", ring_step=1.30, radial=16, edge_band=0.64, inner_disc=1.25)
    n = plan.n
    beds = fu["beds"]
    seats = fu["seats"]
    rmax = plan.r_max
    seat_pts = []
    if s == 0:
        # cabins: four beds along the ring (long side to the wall), a bedside unit at each head, a table between
        half = (BED_L + 0.07 + 0.44) / 2
        d_out = sqrt(min(rmax, plan.lane_r()) ** 2 - half * half)     # inside the door lanes (2026-09-25)
        rc = d_out - BED_W / 2 - 0.035
        for i in range(beds):
            th = 45.0 + 360.0 * i / beds
            c, sn = cos(radians(th)), sin(radians(th))
            # bed frame: +Y (head) = clockwise tangent, +X (stand side) = toward the centre
            yaw = th + 180.0
            off = -0.22                                   # the bed sits toward the foot, the unit at the head
            tx, ty = sn, -c                               # clockwise tangent
            bx, by = rc * c + tx * off, rc * sn + ty * off
            dr, pil, bl, thr, item = dress(i)
            with n.at(T(bx, by, 0), RZ(th + 180.0)):
                FU.bed(n, dressing=dr, pillows=pil, blanket=bl, throw=thr, side=1, style=i % 3)
                with n.at(T(0.0, BED_L / 2 + 0.07 + 0.22, 0)):
                    FU.bedside(n, item=item, seed=i, lamp_cb=lamp_cb(plan, n))
            plan.rect(bx + tx * 0.22, by + ty * 0.22, half, BED_W / 2 + 0.035, th + 90.0, tag="bed%d" % i)
            sx, sy = (rc - BED_BACK) * c + tx * off, (rc - BED_BACK) * sn + ty * off
            plan.anchor("Bed", sx, sy, th + 180.0)
        r_t, r_c, n_c, a0 = 0.36, 0.68, seats, 105.0 # beds 0.12 m further in (door lanes)
        tables = [(0.0, 0.0, r_t, r_c, n_c, a0)]
        rug_r = 1.0
    else:
        nb = beds // 2
        if s == 3:
            ring_n = nb - 2
        else:
            ring_n = nb
        r_head = sqrt(rmax * rmax - (BAY_HW + 0.015) ** 2)
        a_off = {1: 0.0, 2: 0.0, 3: 20.0}[s]
        angs = [a_off + 360.0 * k / ring_n for k in range(ring_n)]
        if s == 1:
            angs = [10.0, 90.0, 170.0, 260.0]           # three bays in a row, one apart (critic round 7; 1.0 m ring)
        i = 0
        for th in angs:
            bay(plan, r_head * cos(radians(th)), r_head * sin(radians(th)), th, i)
            i += 2
        # privacy screens on the bisectors between neighbouring ring bays
        for k in range(ring_n):
            nxt = angs[(k + 1) % ring_n] + (360.0 if k == ring_n - 1 else 0.0)
            if nxt - angs[k] > 90.0:
                continue                                # an open wedge: no screen
            bis = 0.5 * (angs[k] + nxt)
            r1, r0 = r_head - 0.05, r_head - (0.80 if s == 1 or nxt - angs[k] < 64.0 else 1.25)   # M: 1.0 m ring
            rmid = 0.5 * (r0 + r1)
            mx, my = rmid * cos(radians(bis)), rmid * sin(radians(bis))
            tp = plan.tall(mx, my)
            with at(tp, mx, my, bis):
                FU.curtain_screen(tp, r1 - r0)
            plan.rect(mx, my, (r1 - r0) / 2, 0.04, bis, tag="screen")
        if s == 3:
            # central pod: two bays back to back, heads on the y axis, a tall divider between the heads
            bay(plan, 0.03, 0.0, 0.0, i, tall=False)
            bay(plan, -0.03, 0.0, 180.0, i + 2, tall=False)
            with at(n, 0.0, 0.0, 90.0):
                FU.curtain_screen(n, 2 * BAY_HW + 0.1, h=1.25)
            plan.rect(0.0, 0.0, BAY_HW + 0.05, 0.05, 90.0, tag="pod")
            tables = [(0.0, 3.1, 0.55, 0.95, 4, 45.0), (0.0, -3.1, 0.55, 0.95, 4, 45.0)]
            rug_r = 0.0
        else:
            r_t = (0.0, 0.62, 0.85)[s]
            tables = [(0.0, 0.0, r_t, r_t + 0.52, seats, 45.0 if s == 1 else 0.0)]
            rug_r = (0.0, 1.8, 2.4)[s]
    # commons: rug, tables, chairs, a planter centrepiece
    if rug_r:
        FU.rug_round(n, rug_r, mat="Cushion", ring="Accent", seg=18 if s == 1 else 24)
    if s == 3:
        for (tx, ty, r_t, r_c, n_c, a0) in tables:
            FU.rug_round(n, r_c + 0.45, tx, ty, mat="Cushion", ring="Accent", seg=20)
    k = 0
    for (tx, ty, r_t, r_c, n_c, a0) in tables:
        with n.at(T(tx, ty, 0)):
            FU.table_round(n, r=r_t, edge="Accent")
            n.vcyl(0, 0, F + 0.74, F + 0.86, 0.10, 0.08, seg=10, mat="Hull", cap0=False)
            FU.leafy_plant(n, 0, 0, F + 0.84, s=0.55, n=5, seed=5 + k)
        plan.circle(tx, ty, r_t, tag="table")
        for j in range(n_c):
            a = a0 + 360.0 * j / n_c
            cx, cy = tx + r_c * cos(radians(a)), ty + r_c * sin(radians(a))
            with at(n, cx, cy, a + 180.0):
                FU.chair(n)
            plan.rect(cx, cy, 0.25, 0.24, a + 180.0, tag="seat%d" % k)
            px, py = tx + (r_c - SEAT_BACK) * cos(radians(a)), ty + (r_c - SEAT_BACK) * sin(radians(a))
            plan.anchor("Seat", px, py, a + 180.0)
            k += 1
    if s == 1:
        # the reading corner in the open wedge between the last bay and the first
        a = 0.5 * (angs[-1] + angs[0] + 360.0) - 17.0     # toward the 260 bay: the 10-deg bay stands its bed on this side
        rr = r_head - 1.1
        x, y = rr * cos(radians(a)), rr * sin(radians(a))
        rr_ = _FAMX.d_reading(plan, x, y, a + 90.0, 1)
        plan.circle(x, y, rr_, tag="reading")
    elif s == 2:
        _FAMX.place_reading(plan, seed=17 + s)
    # wall items: a wardrobe or lockers behind the beds, cabinets with lamps, one water unit, open wall
    pattern = ["tap", "wardrobe", "cab_lamp", "aiposter", "shelf", "lockers", "kettle", "cab_books", "planter",
               "wardrobe", "notice", "desk", "cab_plant", "filmposter", "lockers", "shelf"]     # 5.0 (V5 15.3)
    placed = plan.wall_items(pattern, wall_set(plan), open_every=2 if s == 0 else 3, seed=7 + s, depth_of=DEPTHS,
                             open_kinds=("poster", "aiposter", "notice", "plant", "panel", "filmposter"))
    # stands: at the water unit, then round the commons, then the walking ring
    need = fu["stands"]
    if stand_at_wall(plan, placed, "tap"):
        need -= 1
    cands = []
    for (tx, ty, r_t, r_c, n_c, a0) in tables:
        for j in range(n_c):
            a = a0 + 360.0 * (j + 0.5) / n_c
            for rr in (r_c + 0.50, r_c + 0.75):
                cands.append((tx + rr * cos(radians(a)), ty + rr * sin(radians(a)), a + 180.0))
    plan.stands(need, cands)
    finish(plan)


# --------------------------------------------------------------------------------------
# Dispatcher
# --------------------------------------------------------------------------------------
INTERIORS = {
    "habitat": habitat,
}


def v2_builders():
    out = {}
    for m in ("rooms_habitat", "rooms_agri", "rooms_life", "rooms_science", "rooms_industry", "rooms_links",
              "rooms_v4ind", "rooms_v5", "rooms_v5apt", "rooms_v5civ", "rooms_distillery"):
        out.update(getattr(__import__(m), "BUILDERS", {}))
    return out


def build_room_v3(rm):
    """rm: a fresh rooms_kit.Room.  Raises NotImplementedError when the type has no 3.0 interior yet."""
    if rm.tid not in INTERIORS:
        raise NotImplementedError(rm.tid)
    rm.v3_mode = True
    rm.keep_door = rm.tid == "airlock"
    v2 = v2_builders()
    v2[rm.tid](rm)
    if K.V4STYLE:
        import rooms_identity as RI       # 4.0: the family badge on every room type without its own branch
        RI.identity_pass(rm)
    if not rm.v3:                  # a v2 builder that did not call build_base
        raise NotImplementedError(rm.tid + ": no base")
    rm.interior = P("Interior")
    rm.trays = []
    rm.rooms_hi = list(rm.rooms_hi)
    IK.route_wall_zone(rm)
    INTERIORS[rm.tid](rm)


import interior_families as _FAM     # noqa: E402  (uses the helpers above)
_FAMX = _FAM
INTERIORS.update(_FAM.INTERIORS)
for _mod in ("interior_fam_farm", "interior_fam_ind", "interior_fam_sci", "interior_airlock_reg", "interior_fam_v4ind",
             "interior_v5", "interior_v5apt", "interior_v5civ", "interior_distillery"):
    try:
        INTERIORS.update(__import__(_mod).INTERIORS)
    except ModuleNotFoundError as _exc:
        if _exc.name != _mod:
            raise
V3_BUILDERS = {tid: build_room_v3 for tid in INTERIORS}
