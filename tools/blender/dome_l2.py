"""
Frontier Habitat 5.0 - super dome level 2 venues (V5 section 8): the gaming lounge with the PRISM SHIFT cabinet
(V5 section 4.5), the Club (stage and light rig, podiums with poles, DJ booth, lounge booths, bar, LED dance floor,
bouncer spot), the gym, and the smaller shops. ART-B. Used by dome_floors.py (level 2); Blender --background only.

The PRISM SHIFT screen: node `ArcadeScreen_PrismShift` (child of Venue_arcade), one quad with material
`ArcadeScreen` and UV 0..1 (u to the right, v up, seen by the player) for RENDER's attract-loop shader.
"""
import math
from math import sin, cos, radians

import dome_common as D
import dome_floors as F
from dome_common import pol, T, RZ, RX, RY, GRAPHITE, WHITE
from vehicle_common import Node
from mathutils import Vector

# (id, sign, first sector, sectors, sign material, fascia colour, interior kind, floor colour)
L2_VENUES = [
    ("beauty", "BEAUTY", 0, 1, "SignMagenta", "#f0d8e0", "barber", "#e8e0e4"),
    ("arcade", "GAME ZONE", 1, 4, "SignCyan", "#1c1830", "arcade", "#2a2440"),
    ("shoes", "SHOES", 5, 1, "SignAmber", "#6b4a3a", "shoes", "#d8cdb8"),
    ("books", "BOOKS", 6, 1, "SignAmber", "#2f4f3a", "books", "#c8b89a"),
    ("gym", "GYM", 7, 3, "SignGreen", "#2c3036", "gym", "#4a5058"),
    ("toys", "TOYS", 10, 1, "SignMagenta", "#f2c14e", "toys", "#e8e2d8"),
    ("foodcourt", "FOOD COURT", 11, 2, "SignAmber", "#7a2f3a", "foodcourt", "#d8cdb8"),
    ("club", "CLUB", 13, 6, "SignMagenta", "#120e18", "club", "#15121c"),
    ("jewels", "JEWELS", 19, 1, "SignCyan", "#1f3552", "jewels", "#2c3036"),
    ("travel", "TRAVEL", 20, 1, "SignCyan", "#24405a", "office", "#c9d3e0"),
    ("flowers", "FLOWERS", 21, 1, "SignGreen", "#e6e3dc", "flowers", "#d8d2c6"),
    ("tailor", "TAILOR", 22, 1, "SignMagenta", "#3a2f4f", "clothing", "#e0d6c8"),
    ("vacant", "TO LET", 23, 1, "SignAmber", "#8a929c", "vacant", "#b9b3a8"),
]
SPECIAL = ("arcade", "club", "gym", "shoes", "books", "toys", "foodcourt", "jewels", "flowers", "vacant")
SIGN_SHIFT = {"arcade": -2.5, "flowers": 7.0}
CHROME = "Palette:#d8dde2"
NEONS = ("SignMagenta", "SignCyan", "SignAmber", "SignGreen")


def A(kind, pos, fwd, **ex):
    return dict(kind=kind, pos=Vector(pos), fwd=Vector(fwd), extras=ex)


def face_to(pos, target):
    d = Vector(target) - Vector(pos)
    d.z = 0
    return d.normalized() if d.length > 1e-6 else Vector((1, 0, 0))


# ======================================================================================
# gaming lounge
# ======================================================================================
def cabinet(p, lt, c, yaw, k, prism=False, scr=None):
    """an upright arcade cabinet at c facing yaw (the player stands 0.8 m in front, on +X local)"""
    body = "Palette:#1c1830" if prism else ("Palette:#2c3036", "Palette:#3a2f4f", "Palette:#24405a")[k % 3]
    mq = NEONS[k % 4] if not prism else "SignCyan"
    with p.at(T(*c), RZ(yaw)), lt.at(T(*c), RZ(yaw)):
        h = 2.05 if prism else 1.85
        p.box((-0.1, 0, 0.45), (0.65, 0.72, 0.9), body)                         # lower cabinet
        p.box((0.12, 0, 0.95), (0.42, 0.72, 0.12), "Palette:#4a5058")              # control panel
        for j in (-0.18, 0.06, 0.2):
            lt.cyl((0.2, j, 1.01), (0.2, j, 1.04), 0.025, seg=6, mat=NEONS[(k + int(j * 10)) % 4])  # buttons
        p.cyl((0.16, -0.12, 1.01), (0.16, -0.12, 1.12), 0.015, seg=4, mat=GRAPHITE)                 # joystick
        p.box((-0.18, 0, 1.45), (0.5, 0.72, 0.9), body)                         # screen housing
        p.box((-0.2, 0, h - 0.12), (0.62, 0.74, 0.24), body)                    # marquee box
        lt.box((0.11, 0, h - 0.12), (0.02, 0.66, 0.18), mq)                       # lit marquee
        for sy in (-1, 1):                                                        # side art stripes
            lt.box((-0.15, sy * 0.365, 1.2), (0.55, 0.01, 0.05), mq)
        if not prism:
            with lt.at(T(0.08, 0, 1.45), RY(-12.0)):
                lt.box((0, 0, 0), (0.02, 0.56, 0.46), scr or "Screen")
    return c + pol(0.85, yaw)


def racer_cabinet(p, lt, scr_node, c, yaw):
    """PRISM SHIFT as a sit-down racer (critic round 28 fix 4): a platform with neon underglow, a bucket seat,
    a steering wheel where ART-NPC's drive_sit hands are, pedals, a big screen (ArcadeScreen, UV 0..1) in a hood
    with prism side panels, and a wide marquee. Local +X points from the screen to the player."""
    with p.at(T(*c), RZ(yaw)), lt.at(T(*c), RZ(yaw)):
        p.box((0.0, 0, 0.06), (1.2, 1.3, 0.12), "Palette:#1c1830")                         # plinth under the hood
        for sy in (-1, 1):
            lt.box((0.6, sy * 0.66, 0.03), (2.4, 0.02, 0.04), "SignCyan")                  # floor underglow
        lt.box((1.8, 0, 0.03), (0.02, 1.3, 0.04), "SignMagenta")
        p.box((1.0, 0, 0.08), (0.46, 0.46, 0.16), GRAPHITE)                                # seat pedestal
        # bucket seat (top 0.46 m, centre 1.0 m from the screen side)
        p.box((1.0, 0, 0.3), (0.5, 0.52, 0.28), "Palette:#2c3036")
        p.box((1.0, 0, 0.45), (0.46, 0.48, 0.03), "Palette:#b0283a")
        p.box((1.27, 0, 0.8), (0.1, 0.5, 0.7), "Palette:#b0283a")
        for sy in (-1, 1):
            p.box((1.0, sy * 0.25, 0.55), (0.46, 0.05, 0.18), "Palette:#b0283a")
        # dash with the wheel (centre at the drive_sit grip height), pedals
        p.box((0.22, 0, 0.62), (0.35, 0.8, 0.9), "Palette:#1c1830")
        with p.at(T(0.4, 0, 0.925), RY(70.0)):
            p.torus(0.15, 0.022, GRAPHITE, seg=12, tseg=4)
        p.cyl((0.22, 0, 0.9), (0.4, 0, 0.925), 0.03, seg=5, mat=GRAPHITE)
        for sy in (-0.1, 0.1):
            p.box((0.5, sy, 0.22), (0.08, 0.08, 0.14), "Palette:#8a929c")
        # screen hood with prism side panels and the marquee
        p.box((-0.25, 0, 1.3), (0.4, 1.3, 1.0), "Palette:#1c1830")
        p.box((-0.1, 0, 1.87), (0.7, 1.4, 0.14), "Palette:#1c1830")                       # hood top
        for sy in (-1, 1):
            q = [Vector((0.25, sy * 0.66, 0.8)), Vector((-0.45, sy * 0.66, 0.8)), Vector((-0.1, sy * 0.66, 1.9))]
            p.poly(q if sy < 0 else list(reversed(q)), "Palette:#1c1830")
            q2 = [Vector((0.15, sy * 0.672, 0.9)), Vector((-0.35, sy * 0.672, 0.9)), Vector((-0.1, sy * 0.672, 1.7))]
            lt.poly(q2 if sy < 0 else list(reversed(q2)), "SignMagenta")
            q3 = [Vector((0.02, sy * 0.674, 1.0)), Vector((-0.22, sy * 0.674, 1.0)), Vector((-0.1, sy * 0.674, 1.4))]
            lt.poly(q3 if sy < 0 else list(reversed(q3)), "SignCyan")
        p.box((-0.3, 0, 2.15), (0.3, 1.6, 0.42), "Palette:#1c1830")                         # marquee box
        lt.box((-0.14, 0, 2.15), (0.02, 1.5, 0.34), "Palette:#120e18")
    fwd = pol(1.0, yaw)
    right = Vector((0, 0, 1)).cross(fwd).normalized()
    D.sign_text(lt, "PRISM SHIFT", Vector(c) + fwd * (-0.13) + Vector((0, 0, 2.15)), right, 0.16, "SignMagenta", fwd,
                depth=0.02)
    with scr_node.at(T(*c), RZ(yaw), T(-0.04, 0, 1.3), RY(-8.0)):
        scr_node.poly([Vector((0, -0.5, -0.3)), Vector((0, 0.5, -0.3)), Vector((0, 0.5, 0.3)), Vector((0, -0.5, 0.3))],
                      "ArcadeScreen")                                   # bottom-left, bottom-right, top-right, top-left
    return Vector(c) + fwd * 0.7                                          # the drive_sit stand point


def arcade(p, lt, v, a0, a1, z0, out_nodes):
    span = a1 - a0
    mid = (a0 + a1) / 2
    anchors = []
    scr = Node("ArcadeScreen_PrismShift", None, "Floor_2", {"floor": 2, "venue": "arcade", "material": "ArcadeScreen",
                                                            "uv": "0..1, u right, v up (seen by the player)"})
    out_nodes.append(scr)
    zc = F.ceil_z(2)
    D.sector_prism(p, D.R_WALL - 0.34, D.R_WALL - 0.3, a0, a1, z0, zc, None, None, "Palette:#1c1830", None, n=12)
    for ea, sgn in ((a0, 1), (a1, -1)):                          # dark lining (the white facade must not show inside)
        D.radial_wall(p, ea + sgn * 0.45, D.R_FRONT + 0.2, D.R_WALL - 0.06, z0, zc, 0.04, "Palette:#1c1830")
    # neon floor: dark carpet with neon arcs and chevrons
    for r in (25.2, 30.6):
        D.sector_prism(lt, r - 0.04, r + 0.04, a0 + 1.0, a1 - 1.0, z0 + 0.013, z0 + 0.018, "SignCyan" if r < 26 else "SignMagenta",
                       None, None, None, n=24)
    for k in range(10):
        a = a0 + span * (k + 0.5) / 10
        for j in range(3):
            c = pol(26.2 + j * 1.5, a, z0 + 0.016)
            t = pol(1.0, a + 90.0)
            rr = pol(1.0, a)
            D.quad(lt, [c - t * 0.35, c + rr * 0.3, c + t * 0.35, c + rr * 0.1], Vector((0, 0, 1)), NEONS[(k + j) % 4])
    # PRISM SHIFT: the sit-down racer in the middle of the room, its screen towards the entrance
    rc = pol(28.9, mid, z0)
    stand = racer_cabinet(p, lt, scr, rc, mid + 180.0)
    anchors.append(A("ArcadePrism", Vector((stand.x, stand.y, z0)), -pol(1.0, mid + 180.0), clip="drive_sit",
                     egg="prism_shift", seat="racer"))
    lt.box(tuple(pol(D.R_WALL - 0.4, mid, z0 + 2.6)), (0.03, 2.4, 0.5), "SignCyan")                 # halo on the wall
    # a row of 6 cabinets along the back wall (two each side of the racer)
    k = 0
    for f in (0.1, 0.22, 0.34, 0.66, 0.78, 0.9):
        a = a0 + span * f
        s_ = cabinet(p, lt, pol(D.R_WALL - 0.75, a, z0), a + 180.0, k)
        anchors.append(A("Arcade", Vector((s_.x, s_.y, z0)), -pol(1.0, a + 180.0), clip="play_arcade"))
        k += 1
    # two back-to-back blocks of 4 in the middle (8 cabinets)
    for fa in (0.2, 0.8):
        a = a0 + span * fa
        for j in (-1.2, 1.2):                                   # degrees along the ring
            aa = a + j
            for side, r in ((1, 27.4), (-1, 28.4)):
                yaw = aa + (180.0 if side > 0 else 0.0)
                s_ = cabinet(p, lt, pol(r, aa, z0), yaw, k)
                anchors.append(A("Arcade", Vector((s_.x, s_.y, z0)), -pol(1.0, yaw), clip="play_arcade"))
                k += 1
    # prize counter by the entrance: a lit glass counter and shelves of plush prizes
    pa = a0 + span * 0.62
    with F.at(p, pa, 24.6, z0), F.at(lt, pa, 24.6, z0):
        p.box((0, 0, 0.45), (0.7, 3.0, 0.9), "Palette:#1c1830")
        p.box((0, 0, 1.05), (0.66, 2.96, 0.3), "Glass")
        lt.box((0, 0, 0.91), (0.64, 2.9, 0.02), "WindowCream")
        for j in range(8):
            p.sphere((0.0, -1.3 + j * 0.37, 1.0), 0.08, "Palette:" + F.GOODS[j % 7], seg=6, rings=3)
        lt.box((0.36, 0, 0.55), (0.02, 2.9, 0.05), "SignAmber")
    for j in range(3):                                          # prize shelves on the side wall behind it
        with F.at(p, a1 - 1.2, 25.0 + j * 1.3, z0, yaw=90.0):
            p.box((0, 0, 1.2), (0.4, 1.2, 2.4), "Palette:#3a2f4f")
            for row in range(4):
                for col in range(4):
                    p.sphere((0.22, -0.45 + col * 0.3, 0.45 + row * 0.5), 0.1, "Palette:" + F.GOODS[(row + col + j) % 7],
                             seg=6, rings=3)
    D.sign_text(lt, "PRIZES", pol(24.2, pa, z0 + 1.9), Vector((0, 0, 1)).cross(-pol(1.0, pa)), 0.22, "SignAmber",
                -pol(1.0, pa), depth=0.02, plate="Palette:#1c2026", pad=0.08)
    anchors.append(A("Work", pol(25.2, pa, z0), -pol(1.0, pa)))
    # 4 VR pods at the front left
    for j in range(4):
        a = a0 + span * (0.08 + 0.1 * j)
        c = pol(24.9, a, z0)
        with p.at(T(*c)), lt.at(T(*c)):
            p.cyl((0, 0, 0), (0, 0, 0.1), 0.75, seg=12, mat="Palette:#2c3036")
            lt.lathe([(0.8, 0.1), (0.82, 0.12), (0.78, 0.12)], "SignCyan", seg=12, smooth=False)
            p.torus(0.7, 0.04, GRAPHITE, seg=12, tseg=4, z=1.1)
            for i in range(3):
                q = pol(0.7, 120.0 * i)
                p.cyl((q.x, q.y, 0.1), (q.x, q.y, 1.1), 0.03, seg=4, mat=GRAPHITE, cap0=False)
        anchors.append(A("VR", c, face_to(c, pol(20.0, mid, z0)), clip="play_arcade"))
    # pool table (right front) and seating: sofas, stools
    pc = pol(26.0, a0 + span * 0.86, z0)
    yaw = a0 + span * 0.86
    with p.at(T(*pc), RZ(yaw)):
        p.box((0, 0, 0.78), (1.3, 2.4, 0.12), "Palette:#6b4a3a")
        p.box((0, 0, 0.845), (1.12, 2.22, 0.02), "Palette:#2f7a4a")
        for sx in (-1, 1):
            for sy in (-1, 1):
                p.box((sx * 0.52, sy * 1.02, 0.36), (0.14, 0.14, 0.72), "Palette:#6b4a3a")
        for j, col in enumerate(("#f2c14e", "#e0503a", "#4a90d9", "#e6e3dc", "#2c3036", "#6abf4b", "#b58cff")):
            p.sphere((-0.2 + 0.12 * (j % 3), -0.4 + 0.1 * j, 0.89), 0.03, "Palette:" + col, seg=6, rings=3)
    lt.box(tuple(pc + Vector((0, 0, 2.2))), (0.5, 1.6, 0.06), "Light")
    for sy in (-1, 1):
        q = pc + pol(1.6, yaw + 90.0) * sy
        anchors.append(A("PoolTable", q, face_to(q, pc)))
    for fa in (0.35, 0.48):                                     # sofas facing the racer
        a = a0 + span * fa
        with F.at(p, a, 26.0, z0, yaw=0.0):
            p.box((0, 0, 0.22), (0.8, 1.8, 0.44), "Palette:#3a2f4f")
            p.box((0.35, 0, 0.6), (0.18, 1.8, 0.5), "Palette:#3a2f4f")
        anchors.append(A("Seat", pol(25.8, a, z0), pol(1.0, a), clip="sit_idle"))
    for j in range(4):                                          # stools at the middle blocks
        for fa in (0.2, 0.8):
            a = a0 + span * fa + (-1.8 + j * 1.2)
            q = pol(26.6, a, z0)
            with p.at(T(*q)):
                p.cyl((0, 0, 0), (0, 0, 0.6), 0.04, seg=4, mat=GRAPHITE, cap0=False)
                p.cyl((0, 0, 0.6), (0, 0, 0.65), 0.18, seg=8, mat="Palette:#b0283a")
    # neon ceiling strips
    for k in range(4):
        a = a0 + span * (k + 0.5) / 4
        with lt.at(RZ(a)):
            lt.box((28.0, 0, F.ceil_z(2) - 0.03), (8.0, 0.08, 0.03), NEONS[k % 4])
    return anchors


# ======================================================================================
# the Club (adults only; robot dancers are ART-NPC's, placed on Anchor_Dancer_<k>)
# ======================================================================================
def club_front(p, lt, v, z0, z1):
    """a closed dark front (no display glass) with neon trim, a double door with a canopy and rope posts"""
    vid, text, s0, ns, sign_mat, fascia, kind, floor_col = v
    for k in range(ns):
        s = s0 + k
        x, hw = F.chord(D.R_FRONT)
        with p.at(RZ(F.sec_angle(s))), lt.at(RZ(F.sec_angle(s))):
            door = k == ns // 2
            if door:
                p.box((x, -hw * 0.6 - 0.3, (z0 + z1) / 2), (0.25, hw * 0.8, z1 - z0), "Palette:#120e18")
                p.box((x, hw * 0.6 + 0.3, (z0 + z1) / 2), (0.25, hw * 0.8, z1 - z0), "Palette:#120e18")
                p.box((x, 0, z1 - 0.6), (0.25, 2.4, 1.2), "Palette:#120e18")
                p.box((x + 0.05, 0, z0 + 1.2), (0.08, 2.2, 2.4), "Palette:#2c1f3a")            # doors
                lt.box((x - 0.14, 0, z0 + 2.45), (0.02, 2.4, 0.06), "SignMagenta")
                for sy in (-1, 1):                                                          # lit door frame + handles
                    lt.box((x - 0.14, sy * 1.17, z0 + 1.22), (0.02, 0.05, 2.44), "SignMagenta")
                    p.box((x - 0.02, sy * 0.12, z0 + 1.1), (0.05, 0.04, 0.5), CHROME)
                p.box((x - 0.9, 0, z0 + 2.7), (1.6, 3.0, 0.1), "Palette:#120e18")              # canopy
                lt.box((x - 1.69, 0, z0 + 2.7), (0.02, 3.0, 0.1), "SignCyan")
                for sy in (-1, 1):                                                          # rope posts
                    for j in range(3):
                        q = Vector((x - 1.0 - j * 0.9, sy * 1.6, z0))
                        p.cyl(q, q + Vector((0, 0, 0.95)), 0.04, seg=6, mat=CHROME, cap0=False)
                        p.sphere(tuple(q + Vector((0, 0, 0.98))), 0.06, CHROME, seg=6, rings=3)
                    p.beam(Vector((x - 1.0, sy * 1.6, z0 + 0.85)), Vector((x - 2.8, sy * 1.6, z0 + 0.85)), 0.03, 0.03,
                           "Palette:#b0283a")
            else:
                p.box((x, 0, (z0 + z1) / 2), (0.25, 2 * hw, z1 - z0), "Palette:#120e18")
            lt.box((x - 0.14, 0, z1 - 0.12), (0.02, 2 * hw, 0.06), NEONS[k % 2])
            lt.box((x - 0.14, 0, z0 + 0.1), (0.02, 2 * hw, 0.05), NEONS[(k + 1) % 2])


def club(p, lt, v, a0, a1, z0):
    span = a1 - a0
    mid = (a0 + a1) / 2
    zc = F.ceil_z(2)
    anchors = []
    # dark lining on the outer wall and the two side walls (the white facade must not show inside the club)
    D.sector_prism(p, D.R_WALL - 0.34, D.R_WALL - 0.3, a0, a1, z0, zc, None, None, "Palette:#15121c", None, n=12)
    for ea, sgn in ((a0, 1), (a1, -1)):
        D.radial_wall(p, ea + sgn * 0.45, D.R_FRONT + 0.2, D.R_WALL - 0.06, z0, zc, 0.04, "Palette:#15121c")
    # LED dance floor: tiles in the middle, a third lit
    for i in range(6):
        for j in range(10):
            r0, r1 = 25.2 + i * 0.7, 25.2 + (i + 1) * 0.7
            aa0 = mid - 13.0 + j * 2.6
            mat = NEONS[(i + j) % 4] if D.hsh("tile", i, j) < 0.34 else "Palette:#1c1830"
            D.sector_prism(lt if mat in NEONS else p, r0 + 0.03, r1 - 0.03, aa0 + 0.08, aa0 + 2.52, z0 + 0.012,
                           z0 + 0.03, mat, None, None, None, n=1)
    for k in range(8):
        a = mid - 11.0 + k * 3.1
        r = 25.9 + (k % 3) * 1.3
        anchors.append(A("Dance", pol(r, a, z0 + 0.03), face_to(pol(r, a), pol(D.R_WALL, mid)), clip="dance_a"))
    # the stage at the back with an LED wall and a light rig
    D.sector_prism(p, 30.4, D.R_WALL - 0.1, mid - 12.0, mid + 12.0, z0, z0 + 0.8, "Palette:#2c3036", None,
                   "Palette:#1c1830", None, ends="Palette:#1c1830", n=6)
    D.sector_prism(lt, 30.37, 30.4, mid - 12.0, mid + 12.0, z0 + 0.7, z0 + 0.76, None, None, "SignMagenta", None, n=6)
    for k in range(6):                                                    # LED wall panels
        a = mid - 10.0 + k * 4.0
        with lt.at(RZ(a)):
            lt.box((D.R_WALL - 0.42, 0, z0 + 2.3), (0.03, 2.4, 2.6), "Screen")
            lt.box((D.R_WALL - 0.44, 0, z0 + 3.66), (0.03, 2.4, 0.08), NEONS[k % 4])
    # light rig: an arc truss over the stage front with coloured lamps
    truss = D.arc(30.0, mid - 13.0, mid + 13.0, 8, zc - 0.5)
    p.beam_path(truss, 0.3, 0.3, GRAPHITE)
    for k, q in enumerate(truss):
        lt.cyl(q - Vector((0, 0, 0.15)), q - Vector((0, 0, 0.4)), 0.12, 0.16, seg=8, mat=NEONS[k % 4])
    anchors.append(A("Stage", pol(31.9, mid, z0 + 0.8), -pol(1.0, mid)))
    # three podiums with poles in front of the stage (robot dancers)
    for k, da in enumerate((-9.0, 0.0, 9.0)):
        c = pol(29.2 if k != 1 else 29.6, mid + da, z0)
        with p.at(T(*c)), lt.at(T(*c)):
            p.cyl((0, 0, 0), (0, 0, 0.6), 0.85, 0.8, seg=14, mat="Palette:#1c1830")
            lt.lathe([(0.86, 0.02), (0.87, 0.1), (0.85, 0.1)], "SignMagenta", seg=14, smooth=False)
            p.cyl((0, 0, 0.6), (0, 0, 0.64), 0.8, seg=14, mat=CHROME)
            p.cyl((0, 0, 0.64), (0, 0, zc - z0), 0.045, seg=8, mat=CHROME, cap0=False)
        anchors.append(A("Dancer", c - pol(0.35, mid + da) + Vector((0, 0, 0.64)), -pol(1.0, mid + da), clip="robot_pole",
                         pole=[round(c.x, 3), round(c.y, 3)]))                  # 0.35 m in front of the pole
    # DJ booth on a raised stage right of the main stage (critic round 28 fix 3), with steps and a light strip
    dc = pol(30.6, mid + 17.0, z0)
    dyaw = mid + 17.0 + 180.0
    with p.at(T(*dc), RZ(dyaw)), lt.at(T(*dc), RZ(dyaw)):
        p.box((-0.2, 0, 0.3), (2.4, 3.4, 0.6), "Palette:#2c3036")                            # riser
        lt.box((1.01, 0, 0.55), (0.02, 3.4, 0.05), "SignMagenta")
        for j in range(3):
            p.box((1.15 + j * 0.3, 1.3, 0.1 + j * 0.1 - 0.05), (0.3, 0.8, 0.2 + j * 0.2 - 0.1), "Palette:#3a3f47")
    dc = dc + Vector((0, 0, 0.6))
    with p.at(T(*dc), RZ(dyaw)), lt.at(T(*dc), RZ(dyaw)):
        p.box((0, 0, 0.55), (0.9, 2.4, 1.1), "Palette:#1c1830")
        lt.box((0.46, 0, 0.55), (0.02, 2.3, 0.9), "Screen")
        lt.box((0.47, 0, 0.9), (0.02, 2.3, 0.05), "SignCyan")
        for sy in (-0.6, 0.6):
            p.cyl((0, sy, 1.1), (0, sy, 1.13), 0.18, seg=10, mat="Palette:#4a5058")
            lt.cyl((0, sy, 1.13), (0, sy, 1.14), 0.05, seg=6, mat="SignAmber")
        p.box((-0.1, 0, 1.12), (0.3, 0.5, 0.05), GRAPHITE)
    anchors.append(A("DJ", dc + pol(0.9, dyaw + 180.0), pol(1.0, dyaw)))
    # a light truss over the dance floor with spot cans (coloured lenses)
    zt = zc - 0.55
    corners = [pol(r, mid + da, zt) for (r, da) in ((25.0, -14.0), (29.8, -14.0), (29.8, 14.0), (25.0, 14.0))]
    for i in range(4):
        p.beam(corners[i], corners[(i + 1) % 4], 0.3, 0.3, GRAPHITE)
    for i in range(12):
        e0, e1 = corners[i // 3], corners[(i // 3 + 1) % 4]
        q = e0.lerp(e1, (i % 3 + 0.5) / 3) - Vector((0, 0, 0.18))
        tgt = pol(27.4, mid, z0)
        d = (tgt - q).normalized()
        p.cyl(q, q + d * 0.35, 0.12, 0.15, seg=8, mat=GRAPHITE)
        lt.cyl(q + d * 0.35, q + d * 0.36, 0.13, seg=8, mat=NEONS[i % 4])
    # textured back wall: raised acoustic panels with neon seams beside and above the LED wall
    for j in range(14):
        a = a0 + 1.5 + j * (span - 3.0) / 14
        for row in range(2):
            zz = z0 + 0.9 + row * 1.35
            if abs(a - mid) < 11.5 and row == 0:
                continue
            with F.at(p, a, D.R_WALL - 0.42, z0), F.at(lt, a, D.R_WALL - 0.42, z0):
                p.box((0, 0, zz - z0), (0.12, 1.1, 1.2), "Palette:#241c2c" if (j + row) % 2 else "Palette:#2c2236",
                      mats={"-x": None})
                if (j + row) % 3 == 0:
                    lt.box((0.07, 0, zz - z0 - 0.62), (0.02, 1.1, 0.03), NEONS[(j + row) % 4])
    # booths in view: two curved sofas facing the stage in front of the dance floor
    for da in (-17.0, 17.0):
        c = pol(24.6, mid + da, z0)
        with p.at(T(*c), RZ(mid + da)), lt.at(T(*c), RZ(mid + da)):
            p.box((0, 0, 0.22), (0.8, 2.4, 0.44), "Palette:#7a2f3a")
            p.box((-0.35, 0, 0.7), (0.15, 2.4, 0.6), "Palette:#7a2f3a")
            p.cyl((0.9, 0, 0), (0.9, 0, 0.72), 0.05, seg=5, mat=GRAPHITE, cap0=False)
            p.cyl((0.9, 0, 0.72), (0.9, 0, 0.75), 0.45, seg=10, mat="Palette:#2c3036")
            lt.box((-0.44, 0, 1.02), (0.02, 2.4, 0.04), "SignCyan")
        for j in (-0.6, 0.6):
            anchors.append(A("Booth", c + pol(j, mid + da + 90.0) + pol(0.3, mid + da), pol(1.0, mid + da), clip="sit_idle"))
    # cocktail tables round the dance floor
    for da in (-15.0, -5.0, 5.0, 15.0):
        c = pol(26.0 if abs(da) > 10 else 24.9, mid + da, z0)
        p.cyl(c, c + Vector((0, 0, 1.05)), 0.05, seg=5, mat=CHROME, cap0=False)
        p.cyl(c + Vector((0, 0, 1.05)), c + Vector((0, 0, 1.09)), 0.35, seg=10, mat="Palette:#1c1830")
        D.cups(p, c + Vector((0, 0, 1.09)), n=2, seed=int(da))
    # lounge booths along both side walls
    k = 0
    for side, ea in ((-1, a0), (1, a1)):
        for r in (25.0, 28.4):
            a = ea - side * 3.2
            c = pol(r, a, z0)
            yaw = a + 90.0 * side
            with p.at(T(*c), RZ(yaw)):
                p.box((0.0, 0, 0.22), (2.2, 0.8, 0.44), "Palette:#7a2f3a")                      # seat
                p.box((0.0, -0.35, 0.7), (2.2, 0.15, 0.6), "Palette:#7a2f3a")                   # back
                for sx in (-1, 1):
                    p.box((sx * 1.05, 0.35, 0.22), (0.8, 0.7, 0.44), "Palette:#7a2f3a")
                p.cyl((0, 0.8, 0), (0, 0.8, 0.72), 0.05, seg=5, mat=GRAPHITE, cap0=False)
                p.cyl((0, 0.8, 0.72), (0, 0.8, 0.75), 0.5, seg=10, mat="Palette:#2c3036")
            with lt.at(T(*c), RZ(yaw)):
                lt.box((0.0, -0.44, 1.05), (2.2, 0.02, 0.05), NEONS[k % 4])
            for j in (-0.6, 0.6):
                q = c + pol(j, yaw)
                anchors.append(A("Booth", q, pol(1.0, yaw + 90.0), clip="sit_idle"))
            k += 1
    # the bar along the front wall, on the left of the entrance
    for j in range(5):
        a = a0 + 6.0 + j * 2.2
        with F.at(p, a, 24.2, z0, yaw=180.0):
            p.box((0, 0, 0.55), (0.7, 1.0, 1.1), "Palette:#241c2c", mats={"+z": "Palette:#8a5a44"})
        with F.at(lt, a, 24.2, z0, yaw=180.0):
            lt.box((0.36, 0, 0.3), (0.02, 1.0, 0.05), "SignMagenta")
        q = pol(25.1, a, z0)
        with p.at(T(*q)):
            p.cyl((0, 0, 0), (0, 0, 0.75), 0.04, seg=4, mat=GRAPHITE, cap0=False)
            p.cyl((0, 0, 0.75), (0, 0, 0.8), 0.2, seg=6, mat="Palette:#7a2f3a")
        anchors.append(A("Seat", q, -pol(1.0, a), clip="sit_bar_stool"))
    anchors.append(A("Work", pol(23.5, a0 + 10.4, z0), pol(1.0, a0 + 10.4)))
    for j in range(5):                                          # back bar: shelves with lit bottles, pendants
        a = a0 + 6.0 + j * 2.2
        with F.at(p, a, 23.25, z0, yaw=180.0), F.at(lt, a, 23.25, z0, yaw=180.0):
            p.box((0, 0, 1.5), (0.3, 1.0, 1.2), "Palette:#241c2c")
            for row in range(2):
                for col in range(5):
                    lt.cyl((-0.12, -0.4 + col * 0.2, 1.05 + row * 0.5), (-0.12, -0.4 + col * 0.2, 1.3 + row * 0.5), 0.035, seg=5,
                           mat=("SignAmber", "SignMagenta", "SignGreen", "WindowAmber")[(row + col + j) % 4])
        q = pol(24.2, a, zc - 0.9)
        lt.cyl(q, q + Vector((0, 0, 0.9)), 0.01, seg=3, mat=GRAPHITE, cap0=False)
        lt.cyl(q - Vector((0, 0, 0.2)), q, 0.12, 0.05, seg=8, mat="WindowAmber")
    # disco ball and ceiling glitter
    bc = pol(27.2, mid, zc - 0.9)
    p.cyl(bc + Vector((0, 0, 0.3)), Vector((bc.x, bc.y, zc)), 0.01, seg=3, mat=GRAPHITE, cap0=False)
    p.sphere(tuple(bc), 0.35, CHROME, seg=10, rings=6, smooth=False)
    for k in range(10):
        q = bc + Vector((0.36 * cos(radians(36 * k)), 0.36 * sin(radians(36 * k)), 0.1 * ((k % 3) - 1)))
        lt.box(tuple(q), (0.06, 0.06, 0.06), NEONS[k % 4])
    # the bouncer post outside the door: a lectern, and the ADULTS ONLY sign on the front
    dm = F.sec_angle(v[2] + v[3] // 2)
    q = pol(D.R_FRONT - 1.6, dm + 4.2, z0)
    with p.at(T(*q), RZ(dm + 180.0)):
        p.box((0, 0, 0.55), (0.45, 0.55, 1.1), "Palette:#1c1830")
        p.box((0.05, 0, 1.12), (0.5, 0.6, 0.05), CHROME)
    lt.box(tuple(q + Vector((0, 0, 0.9))), (0.02, 0.02, 0.02), "SignMagenta")
    nrm = -pol(1.0, dm)
    right = Vector((0, 0, 1)).cross(nrm)
    xf = F.chord(D.R_FRONT)[0]
    sc_ = pol(xf - 0.15, dm) + pol(1.0, dm + 90.0) * 2.3 + Vector((0, 0, z0 + 1.75))
    D.sign_text(lt, "ADULTS ONLY", sc_, right, 0.18, "SignMagenta", nrm, depth=0.01, plate="Palette:#1c2026", pad=0.08)
    D.sign_text(lt, "21+", sc_ - Vector((0, 0, 0.42)), right, 0.24, "SignAmber", nrm, depth=0.01)
    anchors.append(A("Bouncer", q + pol(0.6, dm + 180.0), face_to(q, pol(D.R_FRONT - 1.6, dm, z0)), adults_only=True))
    return anchors


# ======================================================================================
# gym
# ======================================================================================
def gym(p, lt, v, a0, a1, z0):
    span = a1 - a0
    anchors = []
    for k in range(6):                                                 # treadmills facing the atrium
        a = a0 + span * (k + 0.5) / 6
        c = pol(25.2, a, z0)
        with p.at(T(*c), RZ(a + 180.0)), lt.at(T(*c), RZ(a + 180.0)):
            p.box((0, 0, 0.12), (1.8, 0.8, 0.24), GRAPHITE, mats={"+z": "Palette:#2c3036"})
            for sy in (-1, 1):
                p.beam((0.8, sy * 0.36, 0.24), (0.95, sy * 0.36, 1.25), 0.05, 0.05, "Palette:#8a929c")
            p.box((0.95, 0, 1.28), (0.2, 0.8, 0.1), "Palette:#4a5058")
            lt.box((0.95, 0, 1.36), (0.12, 0.4, 0.02), "Screen")
        anchors.append(A("Gym", c + Vector((0, 0, 0.24)), -pol(1.0, a), clip="jog", machine="treadmill"))
    for k in range(4):                                                 # exercise bikes
        a = a0 + span * (k + 0.5) / 4
        c = pol(27.9, a, z0)
        with p.at(T(*c), RZ(a + 180.0)):
            p.box((0, 0, 0.05), (1.1, 0.5, 0.1), GRAPHITE)
            p.beam((-0.3, 0, 0.1), (-0.2, 0, 0.85), 0.06, 0.06, "Palette:#8a929c")
            p.box((-0.2, 0, 0.88), (0.3, 0.22, 0.06), "Palette:#2c3036")
            p.beam((0.35, 0, 0.1), (0.45, 0, 1.05), 0.06, 0.06, "Palette:#8a929c")
            p.box((0.45, 0, 1.08), (0.08, 0.5, 0.05), GRAPHITE)
            p.cyl((0.15, -0.08, 0.35), (0.15, 0.08, 0.35), 0.28, seg=10, mat="Accent")
        anchors.append(A("Gym", c, -pol(1.0, a), clip="sit_idle", machine="bike"))
    for k in range(2):                                                 # weight benches and racks
        a = a0 + span * (0.3 + 0.4 * k)
        c = pol(30.6, a, z0)
        with p.at(T(*c), RZ(a)):
            p.box((0, 0, 0.42), (1.2, 0.35, 0.08), "Palette:#2c3036")
            p.box((0, 0, 0.2), (0.2, 0.3, 0.4), GRAPHITE)
            for sy in (-1, 1):
                p.beam((0.5, sy * 0.55, 0.0), (0.5, sy * 0.55, 1.4), 0.07, 0.07, "Palette:#8a929c")
            p.cyl((0.5, -0.9, 1.25), (0.5, 0.9, 1.25), 0.02, seg=4, mat=CHROME)
            for sy in (-1, 1):
                p.cyl((0.5, sy * 0.7, 1.25), (0.5, sy * 0.78, 1.25), 0.2, seg=10, mat=GRAPHITE)
        anchors.append(A("Gym", c + pol(0.9, a + 90.0), pol(1.0, a - 90.0), machine="weights"))
    for k in range(3):                                                 # mats + mirror wall
        a = a0 + span * (k + 0.5) / 3
        D.sector_prism(p, 31.8, 33.2, a - 5.0, a + 5.0, z0 + 0.012, z0 + 0.04, "Accent" if k % 2 else "Palette:#2f6fa0",
                       None, None, None, n=2)
        with F.at(p, a, D.R_WALL - 0.08, z0):
            p.box((0, 0, 1.6), (0.03, 6.0, 2.4), "Palette:#dfe8ee")
    F.counter(p, a0 + span * 0.5, 23.9, z0, w=1.6, col="Palette:#2c3036")
    anchors.append(A("Work", pol(24.5, a0 + span * 0.5, z0), -pol(1.0, a0 + span * 0.5)))
    return anchors


# ======================================================================================
# small shops
# ======================================================================================
def small_shop(p, lt, v, a0, a1, z0):
    vid, text, s0, ns, sign_mat, fascia, kind, floor_col = v
    span = a1 - a0
    mid = (a0 + a1) / 2
    anchors = []
    if kind == "vacant":
        for k in range(ns):
            x, hw = F.chord(D.R_FRONT)
            with p.at(RZ(F.sec_angle(s0 + k))):
                p.box((x + 0.05, 0, z0 + 1.8), (0.02, 2 * hw - 0.3, 3.0), "Palette:#e8e2d8")      # papered glass
                p.box((x + 0.03, 0, z0 + 1.8), (0.01, 2.4, 0.5), "Palette:#e07a3a")
        return anchors
    for k in range(ns):                                                # the window display
        x, hw = F.chord(D.R_FRONT)
        with p.at(RZ(F.sec_angle(s0 + k))), lt.at(RZ(F.sec_angle(s0 + k))):
            for yy in (-hw * 0.6, hw * 0.6):
                p.box((x + 0.65, yy, z0 + 0.2), (0.6, 1.6, 0.4), "Palette:#e6e3dc")
                if kind == "shoes":
                    for j in range(4):
                        p.box((x + 0.65, yy - 0.55 + j * 0.37, z0 + 0.47), (0.3, 0.12, 0.14), "Palette:" + F.GOODS[j + 2])
                elif kind == "books":
                    for j in range(5):
                        p.box((x + 0.65, yy - 0.6 + j * 0.3, z0 + 0.52), (0.22, 0.16, 0.24 + 0.04 * (j % 2)), "Palette:" + F.GOODS[j])
                elif kind == "jewels":
                    p.box((x + 0.65, yy, z0 + 0.62), (0.5, 1.4, 0.44), "Glass")
                    lt.box((x + 0.65, yy, z0 + 0.41), (0.46, 1.36, 0.02), "WindowCream")
                    for j in range(4):
                        p.sphere((x + 0.65, yy - 0.45 + j * 0.3, z0 + 0.47), 0.04, "Palette:#f2d27a", seg=6, rings=3)
                elif kind == "flowers":
                    for j in range(3):
                        c = Vector((x + 0.65, yy - 0.5 + j * 0.5, z0 + 0.4))
                        D.leaf_cluster(p, c, s=0.35, n=6, seed=j + k * 5, tilt=0.6)
                        p.box(tuple(c + Vector((0, 0, 0.22))), (0.12, 0.12, 0.1), "Palette:" + ("#e85d75", "#f2c14e", "#b58cff")[j])
                elif kind == "foodcourt":
                    lt.box((x + 0.95, yy, z0 + 1.5), (0.03, 1.2, 0.7), "Screen")
                else:                                                  # toys
                    for j in range(4):
                        p.box((x + 0.65, yy - 0.5 + j * 0.33, z0 + 0.5 + 0.05 * j), (0.26, 0.26, 0.2 + 0.1 * j), "Palette:" + F.GOODS[(j * 2) % 7])
    if kind == "foodcourt":                                            # three stalls along the back, tables in front
        for k in range(3):
            a = a0 + span * (k + 0.5) / 3
            with F.at(p, a, D.R_WALL - 0.9, z0):
                p.box((0, 0, 0.55), (0.8, 3.2, 1.1), "Palette:#e6e3dc", mats={"+z": "Palette:#8a929c"})
                p.box((-0.9, 0, 2.6), (0.1, 3.2, 1.0), "Palette:#2c3036")
            nrm = -pol(1.0, a)
            D.menu_board(p, lt, pol(D.R_WALL - 1.36, a, z0 + 2.6), Vector((0, 0, 1)).cross(nrm), nrm, w=2.8, h=0.8, seed=k)
            with F.at(lt, a, D.R_WALL - 0.9, z0):
                lt.box((0.43, 0, 3.08), (0.02, 3.0, 0.08), NEONS[k % 4])
            anchors.append(A("Work", pol(D.R_WALL - 0.4, a, z0), -pol(1.0, a)))
        for k in range(6):
            a = a0 + span * (k + 0.5) / 6
            r = 25.2 if k % 2 else 27.4
            F.table_set(p, a, r, z0, seats=4, col="Palette:#e6e3dc")
            D.cups(p, pol(r, a, z0 + 0.76), n=3, seed=k)
            anchors += [A(d["kind"], d["pos"], d["fwd"], **d["extras"]) for d in F.table_seats(a, r, z0, 4)]
        return anchors
    # wall shelves on both side walls and the back, a counter
    for k in range(ns * 2):
        F.shelf(p, a0 + span * (k + 0.5) / (ns * 2), D.R_WALL - 0.45, z0, length=2.4, h=2.1,
                goods=(F.GOODS[(k + 1) % 7], F.GOODS[(k + 3) % 7], F.GOODS[(k + 5) % 7]))
    if kind == "books":
        for k in range(2):
            F.shelf(p, a0 + span * (0.3 + 0.4 * k), 28.4, z0, length=4.0, h=1.9, goods=F.GOODS[:5])
        with F.at(p, mid, 25.5, z0):
            p.box((0, 0, 0.25), (0.8, 0.8, 0.5), "Palette:#7a2f3a")
    elif kind == "jewels":
        for k in range(3):
            a = a0 + span * (k + 0.5) / 3
            with F.at(p, a, 27.5, z0):
                p.box((0, 0, 0.45), (0.7, 1.4, 0.9), "Palette:#1f3552")
                p.box((0, 0, 1.05), (0.66, 1.36, 0.3), "Glass")
            with F.at(lt, a, 27.5, z0):
                lt.box((0, 0, 0.91), (0.64, 1.3, 0.02), "WindowCream")
    elif kind == "flowers":
        for k in range(4):
            a = a0 + span * (k + 0.5) / 4
            c = pol(27.0 + (k % 2) * 2.0, a, z0)
            with p.at(T(*c)):
                p.box((0, 0, 0.4), (1.2, 0.8, 0.8), D.WOOD)
            for j in range(3):
                D.leaf_cluster(p, c + pol(0.35 * (j - 1), a + 90.0, 0.8), s=0.45, n=7, seed=k * 3 + j, tilt=0.55)
    elif kind == "shoes":
        for k in range(2):
            with F.at(p, a0 + span * (0.3 + 0.4 * k), 27.0, z0, yaw=90.0):
                p.box((0, 0, 0.22), (0.45, 1.6, 0.44), "Palette:#3c4a5e")
    else:                                                              # toys
        for k in range(2):
            c = pol(27.0, a0 + span * (0.3 + 0.4 * k), z0)
            for j in range(5):
                p.box(tuple(c + Vector((0.3 * (j % 3), 0.3 * (j // 3), 0.15 + 0.1 * j))), (0.3, 0.3, 0.3), "Palette:" + F.GOODS[j])
    F.counter(p, mid, 24.8, z0, w=1.6, col="Palette:#e6e3dc")
    anchors.append(A("Work", pol(25.4, mid, z0), -pol(1.0, mid)))
    return anchors


def interior2(p, lt, v, a0, a1, z0, out_nodes):
    kind = v[6]
    if kind == "arcade":
        return arcade(p, lt, v, a0, a1, z0, out_nodes)
    if kind == "club":
        return club(p, lt, v, a0, a1, z0)
    if kind == "gym":
        return gym(p, lt, v, a0, a1, z0)
    return small_shop(p, lt, v, a0, a1, z0)
