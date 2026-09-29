"""
Frontier Habitat 5.0 - super dome accommodation, levels 3-5 (V5 section 8): 30 units (24 standard / family on L4,
6 executive on L5, 2 sectors each) and 36 tourist hotel rooms (24 on L3, 12 on L5). ART-B. Used by dome_floors.py.

Per unit: front on the gallery (door, windows, number plate, planter or bench), interior seen in the floor cutaway,
and anchors: Anchor_Unit_<floor>_<s> (door, +X into the unit), Anchor_Bed_<floor>_<s>_<k> (ART-NPC bed rule: the
stand point; mattress top 0.55 m, bed centre line 0.55 m behind, head to local +Y), Anchor_Seat_<floor>_<s>_<k>,
Anchor_Desk_<floor>_<s>. extras: unit kind (hotel / family / executive), sectors, floor, height.
"""
from math import radians

import dome_common as D
import dome_floors as F
from dome_common import pol, T, RZ, GRAPHITE, WHITE
from mathutils import Vector

BED_TOP = 0.55


def plan(n):
    """[(kind, first sector, sectors)] for level n"""
    if n == 3:
        return [("hotel", s, 1) for s in range(24)]
    if n == 4:
        return [("family", s, 1) for s in range(24)]
    out = [("executive", s, 2) for s in range(0, 12, 2)]
    return out + [("hotel", s, 1) for s in range(12, 24)]


def frame(p, a, r, z):
    """a local frame at (r, a): +X towards the atrium, +Y along the ring (increasing angle)"""
    return p.at(T(*pol(r, a, z)), RZ(a + 180.0))


def bed(p, a, r, z, double=True, cover="#4a6fa5", yaw=0.0):
    """a bed along local Y (head at +Y), at radius r, bearing a (local X faces the atrium)"""
    w = 1.6 if double else 0.94
    with frame(p, a, r, z):
        with p.at(RZ(yaw)):
            p.box((0, 0, 0.2), (w, 2.04, 0.4), GRAPHITE)
            p.box((0, 0, 0.47), (w - 0.04, 2.0, 0.16), "Palette:#f2f0ea", mats={"+z": "Palette:" + cover})
            p.box((0, 0.98, 0.8), (w, 0.08, 0.9), "Palette:#6b4f3a")                      # headboard
            p.box((0, 0.78, 0.58), (w - 0.2, 0.36, 0.1), "Palette:#f2f0ea")                 # pillows


def sofa(p, a, r, z, L=2.0, col="#b35a4a", yaw=0.0):
    with frame(p, a, r, z):
        with p.at(RZ(yaw)):
            p.box((0, 0, 0.22), (0.9, L, 0.44), "Palette:" + col)
            p.box((-0.35, 0, 0.62), (0.2, L, 0.5), "Palette:" + col)


def table(p, a, r, z, w=1.4, d=0.9, chairs=4, col=None):
    col = col or D.WOOD
    with frame(p, a, r, z):
        p.box((0, 0, 0.74), (d, w, 0.05), col)
        p.box((0, 0, 0.36), (0.1, 0.1, 0.72), GRAPHITE)
        for k in range(chairs):
            sx = -1 if k % 2 else 1
            y = (k // 2 - (chairs / 2 - 1) / 2) * 0.7
            p.box((sx * (d / 2 + 0.3), y, 0.45), (0.42, 0.42, 0.06), "Palette:#3c4a5e")


def kitchenette(p, lt, a, r, z, w=2.2):
    with frame(p, a, r, z):
        p.box((0, 0, 0.45), (0.6, w, 0.9), "Palette:#e6e3dc", mats={"+z": "Palette:#8a929c"})
        p.box((0.05, -w / 2 + 0.35, 0.92), (0.4, 0.5, 0.02), "Palette:#2c3036")            # hob
        p.box((0.2, w / 2 + 0.35, 1.0), (0.6, 0.6, 2.0), "Palette:#e6e3dc")                 # fridge
    with frame(lt, a, r, z):
        lt.box((-0.25, 0, 1.6), (0.04, w, 0.04), "LightStrip")


def bath_pod(p, a0, a1, r0, r1, z, h=2.3):
    """a small bathroom box in the corner (walls, a door gap on the front side)"""
    D.radial_wall(p, a1, r0, r1, z, z + h, 0.1, "Palette:#e8e2d8")
    D.sector_prism(p, r0 - 0.05, r0 + 0.05, a0, a1 - 1.4, z, z + h, None, None, "Palette:#e8e2d8", "Palette:#e8e2d8", n=1)
    D.sector_prism(p, r0, r1, a0, a1, z + 0.01, z + 0.03, "Palette:#9fd4ea", None, None, None, n=1)


def screen(p, lt, a, r, z, w=1.2, h=0.7, seed=0):
    nrm = -pol(1.0, a)
    c = pol(r, a, z)
    with frame(p, a, r, 0.0):
        p.box((0.0, 0, z), (0.05, w + 0.06, h + 0.06), GRAPHITE)
    with frame(lt, a, r, 0.0):
        lt.box((0.03, 0, z), (0.01, w, h), "Screen")
    D.screen_content(lt, c + nrm * 0.035, Vector((0, 0, 1)).cross(nrm), nrm, w * 0.95, h * 0.95, seed=seed)


def hotel_room(p, lt, n, s, z0, z1):
    """a furnished hotel room in the sector frame of sector s (x radial 23..33.4, y along the ring)
    (critic round 28 fix 2): headboard bed with bedside lamps, rug, picture, TV, wardrobe, desk + chair, lounge chair
    and table by the window, curtains, bathroom with a door, luggage rack, floor lamp, plant"""
    ang = F.sec_angle(s)
    rot = RZ(ang).to_3x3()
    cover = ("#4a6fa5", "#7a2f3a", "#2f6b3a", "#6b4f8a")[s % 4]
    wood = ("#6b4f3a", "#8a6a4a", "#3a2f2a")[s % 3]
    out = []

    def w(x, y, z=0.0):
        return rot @ Vector((x, y, z0 + z))
    with p.at(RZ(ang)), lt.at(RZ(ang)):
        # bathroom pod (front left) with a door on its +Y face
        p.box((24.55, -2.95 + 0.05, z0 + 1.15), (2.5, 0.1, 2.3), "Palette:#e8e2d8")         # side wall
        p.box((25.8, -1.75, z0 + 1.15), (0.1, 2.5, 2.3), "Palette:#e8e2d8")                  # back wall
        p.box((24.05, -0.55, z0 + 1.15), (1.5, 0.1, 2.3), "Palette:#e8e2d8")                 # front wall left
        p.box((25.5, -0.55, z0 + 2.15), (0.6, 0.1, 0.3), "Palette:#e8e2d8")                  # over the door
        p.box((25.5, -0.57, z0 + 1.0), (0.6, 0.05, 2.0), "Palette:" + wood)                 # bathroom door
        p.box((25.25, -0.6, z0 + 1.0), (0.03, 0.03, 0.12), "Palette:#c3c9d1")               # handle
        p.box((24.5, -1.8, z0 + 0.015), (2.4, 2.3, 0.02), "Palette:#9fd4ea")                 # tiles
        p.box((24.0, -2.5, z0 + 0.4), (0.6, 0.5, 0.8), "Palette:#f2f0ea")                    # basin unit
        # wardrobe along the -Y wall behind the bathroom
        p.box((27.0, -3.05, z0 + 1.1), (1.8, 0.6, 2.2), "Palette:" + wood)
        p.box((27.0, -2.74, z0 + 1.1), (0.02, 0.01, 2.0), GRAPHITE)
        # desk + chair + desk lamp on the -Y wall
        p.box((28.9, -3.35, z0 + 0.74), (1.4, 0.55, 0.05), "Palette:" + wood)
        p.box((28.9, -3.35, z0 + 0.37), (1.3, 0.5, 0.02), "Palette:" + wood)
        p.box((28.9, -2.75, z0 + 0.45), (0.45, 0.45, 0.06), "Palette:#3c4a5e")
        p.box((28.9, -2.95, z0 + 0.75), (0.45, 0.06, 0.5), "Palette:#3c4a5e")
        lt.cyl((28.4, -3.45, z0 + 0.95), (28.4, -3.45, z0 + 1.1), 0.1, 0.08, seg=6, mat="WindowAmber")
        # the bed along Y, head on the +Y wall, with bedside tables and lamps, a rug and a picture
        bx, by = 30.4, 2.95
        p.box((bx, by - 1.02, z0 + 0.2), (1.6, 2.04, 0.4), GRAPHITE)
        p.box((bx, by - 1.02, z0 + 0.47), (1.56, 2.0, 0.16), "Palette:#f2f0ea", mats={"+z": "Palette:" + cover})
        p.box((bx, by - 1.62, z0 + 0.56), (1.58, 0.7, 0.02), "Palette:" + cover)             # folded throw
        for i in range(4):                                                                  # quilt pattern (stripes)
            p.box((bx, by - 1.95 + i * 0.3, z0 + 0.575), (1.6, 0.06, 0.01), "Palette:#f2f0ea" if i % 2 else "Palette:#e0b050")
        for i in range(3):                                                                  # quilted squares
            for j in range(2):
                p.box((bx - 0.45 + i * 0.45, by - 0.95 + j * 0.45, z0 + 0.556), (0.3, 0.3, 0.01),
                      "Palette:" + ("#f2f0ea", "#e0b050", "#d8cdb8")[(i + j) % 3])
        p.box((bx, by + 0.06, z0 + 0.75), (1.9, 0.1, 1.2), "Palette:" + wood)                 # headboard
        for sx in (-0.38, 0.38):                                                            # two pillows + cushions
            p.box((bx + sx, by - 0.2, z0 + 0.62), (0.62, 0.36, 0.14), "Palette:#f2f0ea", bevel=0.04)
            p.box((bx + sx * 0.8, by - 0.42, z0 + 0.66), (0.34, 0.12, 0.3), "Palette:" + cover, bevel=0.03)
        for sx in (-1, 1):
            p.box((bx + sx * 1.15, by - 0.25, z0 + 0.28), (0.5, 0.45, 0.56), "Palette:" + wood)
            lt.cyl((bx + sx * 1.15, by - 0.25, z0 + 0.56), (bx + sx * 1.15, by - 0.25, z0 + 0.85), 0.03, seg=4, mat=GRAPHITE)
            lt.cyl((bx + sx * 1.15, by - 0.25, z0 + 0.85), (bx + sx * 1.15, by - 0.25, z0 + 1.1), 0.16, 0.12, seg=8,
                   mat="WindowAmber")
        rugc = ("#b35a4a", "#3a4f6b", "#6b4f3a", "#2f6b3a")[(s + 1) % 4]
        p.box((bx, by - 1.3, z0 + 0.008), (2.8, 3.2, 0.01), "Palette:" + rugc)             # patterned rug: border,
        p.box((bx, by - 1.3, z0 + 0.012), (2.4, 2.8, 0.01), "Palette:#e8dcc4")              # field, medallion, stripes
        p.box((bx, by - 1.3, z0 + 0.016), (1.8, 2.2, 0.01), "Palette:" + rugc)
        with p.at(T(bx, by - 1.3, z0 + 0.02), RZ(45.0)):
            p.box((0, 0, 0), (0.9, 0.9, 0.01), "Palette:#e0b050")
        for i in range(2):
            p.box((bx, by - 2.55 + i * 2.5, z0 + 0.02), (2.2, 0.08, 0.01), "Palette:#e0b050")
        # a small lounge set in the middle of the room: two armchairs and a coffee table on a round rug
        p.cyl((27.8, 0.6, z0 + 0.004), (27.8, 0.6, z0 + 0.014), 1.3, seg=16, mat="Palette:#6b8aa5")
        p.cyl((27.8, 0.6, z0 + 0.015), (27.8, 0.6, z0 + 0.02), 0.9, seg=16, mat="Palette:#e8dcc4")
        p.cyl((27.8, 0.6, z0), (27.8, 0.6, z0 + 0.42), 0.35, seg=10, mat="Palette:" + wood)
        D.cups(p, Vector((27.8, 0.6, z0 + 0.42)), n=2, seed=s)
        for sy in (-1, 1):
            p.box((27.8, 0.6 + sy * 1.0, z0 + 0.22), (0.75, 0.7, 0.44), "Palette:#3a4f6b", bevel=0.04)
            p.box((27.8, 0.6 + sy * 1.3, z0 + 0.6), (0.75, 0.14, 0.5), "Palette:#3a4f6b", bevel=0.03)
        p.box((bx, by + 0.14, z0 + 1.75), (1.2, 0.03, 0.7), "Palette:#e6e3dc")                # picture frame
        p.box((bx, by + 0.12, z0 + 1.75), (1.05, 0.02, 0.55), "Palette:" + ("#e07a3a", "#4a90d9", "#6abf4b", "#e85d75")[s % 4])
        p.box((bx - 0.2, by + 0.11, z0 + 1.7), (0.4, 0.02, 0.3), "Palette:#f2c14e")
        # TV opposite the bed on the -Y wall, on a low cabinet
        p.box((bx, -3.55, z0 + 0.3), (1.6, 0.4, 0.6), "Palette:" + wood)
        p.box((bx, -3.7, z0 + 1.35), (1.3, 0.05, 0.75), GRAPHITE)
        lt.box((bx, -3.67, z0 + 1.35), (1.2, 0.01, 0.66), "Screen")
        # lounge chair + side table + floor lamp by the window
        p.box((32.6, -2.3, z0 + 0.22), (0.8, 0.8, 0.44), "Palette:#b35a4a")
        p.box((32.95, -2.3, z0 + 0.62), (0.15, 0.8, 0.5), "Palette:#b35a4a")
        p.cyl((32.4, -1.3, z0), (32.4, -1.3, z0 + 0.5), 0.25, seg=8, mat="Palette:" + wood)
        lt.cyl((32.9, -3.2, z0), (32.9, -3.2, z0 + 1.5), 0.02, seg=4, mat=GRAPHITE)
        lt.cyl((32.9, -3.2, z0 + 1.5), (32.9, -3.2, z0 + 1.8), 0.2, 0.15, seg=8, mat="WindowAmber")
        # curtains on the outer window
        for sy in (-1, 1):
            for j in range(3):
                p.box((33.35, sy * (3.1 + 0.2 * j), z0 + (z1 - z0) / 2), (0.08, 0.18, z1 - z0 - 0.1),
                      "Palette:" + ("#e8e2d8", "#d8cdb8")[j % 2])
        # luggage rack with a case, a plant by the door
        p.box((27.2, 2.6, z0 + 0.45), (0.9, 0.5, 0.05), "Palette:" + wood)
        p.box((27.2, 2.6, z0 + 0.66), (0.8, 0.42, 0.4), "Palette:" + ("#3a4f6b", "#b35a4a", "#2c3036")[s % 3])
    D.leaf_cluster(p, w(23.8, 2.5, 0.5), s=0.5, n=7, seed=n * 7 + s, tilt=0.6)
    with p.at(RZ(ang)):
        p.box((23.8, 2.5, z0 + 0.25), (0.4, 0.4, 0.5), "Palette:#e6e3dc")
    # anchors: bed stand points (outer side normal, inner side mirrored), desk, lounge chair
    out.append(("Bed", w(bx + 0.4 + 0.55, by - 1.02), rot @ Vector((1, 0, 0)), {"head": "+Y", "mattress_top": BED_TOP}))
    out.append(("Bed", w(bx - 0.4 - 0.55, by - 1.02), rot @ Vector((-1, 0, 0)), {"head": "-Y", "mirror": True,
                                                                                "mattress_top": BED_TOP}))
    out.append(("Desk", w(28.9, -2.45), rot @ Vector((0, -1, 0)), {"clip": "sit_type"}))
    out.append(("Seat", w(32.2, -2.3), rot @ Vector((-1, 0, 0)), {"clip": "sit_idle"}))
    for sy in (-1, 1):
        out.append(("Seat", w(27.8, 0.6 + sy * 0.75), rot @ Vector((0, -sy, 0)), {"clip": "sit_idle"}))
    # warm lamp light points for RENDER (role lamp): the two bedside lamps and the floor lamp
    for (x_, y_, z_) in ((bx - 1.15, by - 0.25, 1.0), (bx + 1.15, by - 0.25, 1.0), (32.9, -3.2, 1.65)):
        out.append(("Lamp", w(x_, y_, z_), Vector((0, 0, -1)), {"role": "lamp", "colour": "#ffb45e", "range_m": 3.0,
                                                               "optional": True}))
    return out


def front(p, lt, n, s0, ns, kind, z0, z1):
    """the gallery front of a unit: door, windows, plate, and a planter or bench (varies per unit)"""
    x, hw = F.chord(D.R_FRONT)
    for k in range(ns):
        s = s0 + k
        with p.at(RZ(F.sec_angle(s))), lt.at(RZ(F.sec_angle(s))):
            door = k == 0
            if door:
                p.box((x, -hw + 1.0, (z0 + z1) / 2), (0.25, 2.0, z1 - z0), WHITE)
                p.box((x, 0.25, z1 - 0.35), (0.25, 1.1, 0.7), WHITE)
                p.box((x - 0.02, 0.25, z0 + 1.07), (0.08, 1.0, 2.14),
                      "Palette:" + {"hotel": "#3a2f4f", "family": "#3a4f6b", "executive": "#1c2026"}[kind])
                lt.box((x - 0.14, 0.25, z1 - 0.62), (0.03, 0.3, 0.05), "Light")
                lt.box((x - 0.14, -0.55, z0 + 1.6), (0.02, 0.22, 0.14), "SignAmber" if kind == "hotel" else "WindowCream")
                wy0, wy1 = 0.95, hw - 0.05
            else:
                wy0, wy1 = -hw + 0.05, hw - 0.05
            p.box((x, (wy0 + wy1) / 2, z0 + 0.45), (0.25, wy1 - wy0, 0.9), WHITE)
            p.box((x, (wy0 + wy1) / 2, z1 - 0.3), (0.25, wy1 - wy0, 0.6), WHITE)
            tone = D.window_tone("uf", n, s, dark=0.22, colour=0.12)
            lt.poly([Vector((x - 0.14, wy0, z0 + 0.9)), Vector((x - 0.14, wy1, z0 + 0.9)), Vector((x - 0.14, wy1, z1 - 0.6)),
                     Vector((x - 0.14, wy0, z1 - 0.6))], tone)
            if kind == "executive" and not door:
                p.box((x - 0.12, (wy0 + wy1) / 2, (z0 + z1) / 2), (0.05, 0.06, z1 - z0 - 1.5), GRAPHITE)
            v = int(D.hsh("front", n, s) * 3)
            if v == 0:                                                      # planter
                p.box((x - 0.5, (wy0 + wy1) / 2, z0 + 0.25), (0.5, min(2.4, wy1 - wy0 - 0.4), 0.5), "Palette:#8a929c")
                D.leaf_cluster(p, Vector((x - 0.5, (wy0 + wy1) / 2, z0 + 0.5)), s=0.5, n=7, seed=n * 50 + s, tilt=0.55)
            elif v == 1:                                                    # a bench by the door
                D.colony_bench(p, Vector((x - 0.6, (wy0 + wy1) / 2, z0)), 180.0, L=1.4)


def interior(p, lt, n, s0, ns, kind, z0, z1):
    """furniture + anchors (dicts: kind, pos, fwd, extras)"""
    a0 = F.sec_angle(s0) - F.HALF
    a1 = F.sec_angle(s0 + ns - 1) + F.HALF
    span = a1 - a0
    mid = (a0 + a1) / 2
    A = []
    uid = "%d_%d" % (n, s0)

    def anchor(kind, a, r, fwd, **ex):
        A.append(dict(kind=kind, pos=pol(r, a, z0), fwd=Vector(fwd), extras=dict(unit=uid, unit_kind=ex.pop("uk", kind), **ex)))

    def at_pos(kind, pos, fwd, **ex):
        A.append(dict(kind=kind, pos=Vector((pos.x, pos.y, z0)), fwd=Vector(fwd).normalized(),
                      extras=dict(unit=uid, unit_kind=kind_, **ex)))

    def double_bed(ab, rb):
        """ART-NPC bed rule on a double bed lying radially, head outwards: one sleeper per half (lines at +-0.4 m);
        the left stand point has its head to local +Y; the right one is mirrored (extras head = -Y)"""
        c = pol(rb, ab, z0)
        t = pol(1.0, ab + 90.0)
        at_pos("Bed", c - t * 0.95, -t, mattress_top=BED_TOP, head="+Y")
        at_pos("Bed", c + t * 0.95, t, mattress_top=BED_TOP, head="-Y", mirror=True)

    def table_stands(ab, rb, d, chairs):
        c = pol(rb, ab, z0)
        inward = -pol(1.0, ab)
        t = pol(1.0, ab + 90.0)
        for k in range(chairs):
            sx = -1 if k % 2 else 1
            y = (k // 2 - (chairs / 2 - 1) / 2) * 0.7
            pos = c + inward * (sx * (d / 2 - 0.0)) - t * y
            at_pos("Seat", pos, -inward * sx, clip="sit_eat")
    kind_ = kind
    floor_col = {"hotel": "#b8a88a", "family": "#c8a27a", "executive": "#8a5a44"}[kind]
    D.sector_prism(p, D.R_FRONT, D.R_WALL, a0, a1, z0, z0 + 0.012, "Palette:" + floor_col, None, None, None, n=3 * ns)
    D.radial_wall(p, a0, D.R_FRONT, D.R_WALL, z0, z1, 0.18, WHITE)
    if kind == "hotel":
        for d in hotel_room(p, lt, n, s0, z0, z1):
            A.append(dict(kind=d[0], pos=d[1], fwd=d[2], extras=dict(unit=uid, unit_kind="hotel", **d[3])))
    elif kind == "family":
        bath_pod(p, a0, a0 + span * 0.4, 23.4, 25.8, z0)
        D.radial_wall(p, mid, 29.2, D.R_WALL, z0, z1, 0.12, "Palette:#e8e2d8")          # two bedrooms at the back
        D.sector_prism(p, 29.1, 29.3, a0, a1, z0, z1, None, None, "Palette:#e8e2d8", "Palette:#e8e2d8", n=2)
        bed(p, a0 + span * 0.28, 31.6, z0, double=True, cover="#4a6fa5", yaw=90.0)
        for k in range(2):                                                 # children's beds
            bed(p, a0 + span * (0.64 + 0.2 * k), 31.4, z0, double=False, cover=("#e85d75", "#f2c14e")[k], yaw=0.0)
        kitchenette(p, lt, a0 + span * 0.72, 24.2, z0, w=2.0)
        table(p, a0 + span * 0.6, 26.8, z0, w=1.4, d=0.9, chairs=4)
        sofa(p, a0 + span * 0.25, 27.8, z0, L=2.0, col=("#b35a4a", "#3a4f6b", "#6b4f3a")[s0 % 3], yaw=0.0)
        screen(p, lt, a0 + span * 0.25, 29.0, z0 + 1.4, w=1.1, h=0.65, seed=s0 + 7)
        double_bed(a0 + span * 0.28, 31.6)
        for k in range(2):                                               # single beds along the ring: stand on the outer side
            aa = a0 + span * (0.64 + 0.2 * k)
            at_pos("Bed", pol(31.95, aa), pol(1.0, aa), mattress_top=BED_TOP, head="+Y", child=True)
        table_stands(a0 + span * 0.6, 26.8, 0.9 + 0.0, 4)
        anchor("Seat", a0 + span * 0.25, 27.6, -pol(1.0, a0 + span * 0.25), uk="family")
    else:                                                                  # executive (2 sectors)
        bath_pod(p, a0, a0 + span * 0.2, 23.4, 26.4, z0)
        D.radial_wall(p, mid + span * 0.15, 28.0, D.R_WALL, z0, z1, 0.12, "Palette:#e8e2d8")
        bed(p, a0 + span * 0.8, 31.3, z0, double=True, cover="#1c2026", yaw=90.0)
        with frame(p, a0 + span * 0.3, 31.6, z0):                         # office: desk + two screens
            p.box((0, 0, 0.74), (0.8, 2.2, 0.05), "Palette:#1c2026")
        screen(p, lt, a0 + span * 0.3, D.R_WALL - 0.12, z0 + 1.6, w=1.8, h=0.8, seed=s0 + 11)
        sofa(p, a0 + span * 0.45, 26.4, z0, L=3.0, col="#e6e3dc", yaw=0.0)
        sofa(p, a0 + span * 0.62, 27.4, z0, L=1.4, col="#e6e3dc", yaw=90.0)
        with frame(p, a0 + span * 0.45, 25.4, z0):
            p.box((0, 0, 0.2), (0.8, 1.4, 0.4), D.WOOD)                      # coffee table
        table(p, a0 + span * 0.75, 24.6, z0, w=2.2, d=1.0, chairs=6, col="Palette:#f2f0ea")
        kitchenette(p, lt, a0 + span * 0.92, 25.6, z0, w=2.4)
        D.tree(p, pol(24.0, a0 + span * 0.3, z0), h=2.2, r=0.6, seed=s0)
        double_bed(a0 + span * 0.8, 31.3)
        table_stands(a0 + span * 0.75, 24.6, 1.0, 6)
        anchor("Desk", a0 + span * 0.3, 30.8, pol(1.0, a0 + span * 0.3), uk="executive")
        anchor("Seat", a0 + span * 0.45, 26.2, -pol(1.0, a0 + span * 0.45), uk="executive")
    return A


def build_units(n, fl, sh, lt, z0, z1):
    import vehicle_common as VC
    out = []
    for (kind, s0, ns) in plan(n):
        node = VC.Node("Unit_%d_%d" % (n, s0), None, fl, {"floor": n, "stage": "fitout", "unit_kind": kind, "sectors": [s0, ns]})
        front(sh, lt, n, s0, ns, kind, z0, z1)
        items = interior(node, lt, n, s0, ns, kind, z0, z1)
        mid = F.sec_angle(s0) + 0.8
        out.append(D.anchor("Anchor_Unit_%d_%d" % (n, s0), pol(D.R_FRONT - 1.0, mid, z0), forward=pol(1.0, mid), floor=n,
                            unit_kind=kind, sectors=[s0, ns]))
        counts = {}
        for d in items:
            k = counts.get(d["kind"], 0)
            counts[d["kind"]] = k + 1
            out.append(D.anchor("Anchor_%s_%d_%d_%d" % (d["kind"], n, s0, k), d["pos"], forward=d["fwd"], floor=n,
                                **d["extras"]))
        out.append(node)
    return out
