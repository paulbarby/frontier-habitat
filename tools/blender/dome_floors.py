"""
Frontier Habitat 5.0 - super dome: the 5-storey ring building, one file per floor. ART-B. Blender --background only:
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/dome_floors.py [-- --floors 1,2,3,4,5]
Writes assets/models/dome_floor<n>.glb (contract: dome_common.py docstring).
Level plan (V5 section 8): L1 + L2 shops and businesses facing the atrium; L3-L5 accommodation.
PILOT (2026-09-29): L1 is complete (13 venues). L2-L5 are the generic fit-out (lit fronts, units); L2 venues
(gaming lounge, Club, gym ...) and the unit interiors come after the pilot.
"""
import os
import sys
import math
from math import sin, cos, radians

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import dome_common as D                                    # noqa: E402
from dome_common import Group, pol, T, RZ, RX, RY, S, GRAPHITE, WHITE, CONCRETE, TILE, SOFFIT, INK   # noqa: E402
from vehicle_common import Node                            # noqa: E402
from mathutils import Vector                               # noqa: E402

HALF = D.SEC / 2
MULLION = GRAPHITE
FASCIA_H = 1.0
FLOOR_LINE = {1: "SignMagenta", 2: "SignCyan", 3: "LightStrip", 4: "SignAmber", 5: "LightStrip"}
SIGN_SHIFT = {"restaurant": 11.0, "electronics": 4.5, "clinic": 1.0, "hotel": -3.0, "barber": -2.0}     # degrees, away from the lift in front

# ---- L1 venues: (id, sign text, first sector, sectors, sign material, fascia colour, interior kind, floor colour)
L1_VENUES = [
    ("grocery", "GROCERY", 1, 2, "SignAmber", "#2f6b3a", "grocery", "#d8d2c6"),
    ("clinic", "CLINIC", 3, 2, "SignGreen", "#e8eef0", "clinic", "#e4ecee"),
    ("barber", "BARBER", 5, 1, "SignMagenta", "#2c3036", "barber", "#b8a898"),
    ("cafe", "CAFE", 7, 2, "SignAmber", "#6b4a3a", "cafe", "#c8a27a"),
    ("restaurant", "RESTAURANT", 9, 2, "SignAmber", "#3a2a26", "restaurant", "#8a5a44"),
    ("credit", "CREDIT", 11, 1, "SignCyan", "#1f3552", "office", "#c9d3e0"),
    ("hotel", "HOTEL", 13, 2, "SignMagenta", "#3a2f4f", "hotel", "#b8a88a"),
    ("bar", "BAR", 15, 2, "SignMagenta", "#241c2c", "bar", "#4a3a40"),
    ("comms", "COMMS & POST", 17, 1, "SignCyan", "#24405a", "comms", "#c9d3e0"),
    ("clothing", "CLOTHING", 19, 2, "SignMagenta", "#e6e3dc", "clothing", "#e8e2d8"),
    ("electronics", "ELECTRONICS", 21, 2, "SignCyan", "#1c2430", "electronics", "#9aa3ad"),
    ("gifts", "GIFTS", 23, 1, "SignAmber", "#7a2f3a", "gifts", "#e0d6c8"),
]


def floor_z(n):
    return D.FLOOR_Z[n - 1]


def ceil_z(n):
    return (D.FLOOR_Z[n] if n < 5 else D.ROOF_Z) - D.SLAB


def sec_angle(s):
    return s * D.SEC


def chord(r):
    """(x of the chord plane, half width) of a sector chord at radius r, in the sector frame"""
    return r * cos(radians(HALF)), r * sin(radians(HALF))


# ======================================================================================
# structure: slab (ceiling of the level below), soffit downlights, columns, gallery edge fascia
# ======================================================================================
def slab(st, lt, n):
    """slab of level n (n >= 2): top at floor_z(n); the underside is the ceiling of level n-1"""
    z1 = floor_z(n)
    z0 = z1 - D.SLAB
    for s in range(D.N_SEC):
        a0, a1 = sec_angle(s) - HALF, sec_angle(s) + HALF
        D.sector_prism(st, D.R_IN, D.R_OUT, a0, a1, z0, z1, TILE, SOFFIT, WHITE, WHITE, n=3)
        D.sector_prism(st, D.R_IN - 0.02, D.R_IN, a0, a1, z0 + 0.08, z0 + 0.16, None, None, "Accent", None, n=3)
        # a light strip along the gallery edge: at night the galleries read as rings of light under the glass
        D.sector_prism(lt, D.R_IN - 0.03, D.R_IN, a0, a1, z1 - 0.07, z1 - 0.02, None, None, "LightStrip", None, n=3)
        for (r, da) in ((20.9, 0.0), (21.9, -4.0), (21.9, 4.0), (26.5, -4.5), (26.5, 4.5), (30.5, 0.0)):
            c = pol(r, sec_angle(s) + da, z0 - 0.01)
            lt.poly([c + Vector((0.22, 0.22, 0)), c + Vector((0.22, -0.22, 0)), c + Vector((-0.22, -0.22, 0)),
                     c + Vector((-0.22, 0.22, 0))], "Light")


def columns(st, n):
    z0, z1 = floor_z(n), ceil_z(n)
    for s in range(D.N_SEC):
        c = pol(20.7, sec_angle(s) - HALF)
        st.cyl((c.x, c.y, z0), (c.x, c.y, z1), 0.32, seg=8, mat=WHITE, cap0=False, cap1=False)
        st.cyl((c.x, c.y, z0), (c.x, c.y, z0 + 0.12), 0.40, seg=8, mat=GRAPHITE, cap0=False, cap1=True)


def facade(st, sh, n):
    """outer wall per sector: a chord panel at r 34 with two windows (lit panes: CabinWindow)"""
    z0, z1 = floor_z(n) - (D.SLAB if n > 1 else 0.0), (floor_z(n + 1) - D.SLAB) if n < 5 else D.ROOF_Z
    zw0 = floor_z(n) + (0.15 if n == 1 else 0.9)
    zw1 = ceil_z(n) - (0.5 if n == 1 else (1.3 if n == 2 else 0.35))
    for s in range(D.N_SEC):
        with st.at(RZ(sec_angle(s))), sh.at(RZ(sec_angle(s))):
            x, hw = chord(D.R_OUT)
            xi = chord(D.R_WALL)[0]
            if n == 1 and s in D.PASSAGES:
                st.box((x - 0.2, 0, (zw1 + z1) / 2), (0.4, 2 * hw, z1 - zw1), WHITE)          # lintel over the passage
                continue
            st.box((x - 0.2, 0, (z0 + zw0) / 2), (0.4, 2 * hw, zw0 - z0), WHITE)             # spandrel
            st.box((x - 0.2, 0, (zw1 + z1) / 2), (0.4, 2 * hw, z1 - zw1), WHITE)              # header
            st.box((x + 0.005, 0, z1 - 0.18), (0.01, 2 * hw, 0.10), "Accent" if n == 1 else GRAPHITE)
            sh.box((x + 0.012, 0, z0 + 0.09 if n > 1 else z1 - 0.08), (0.012, 2 * hw, 0.14), FLOOR_LINE[n])   # lit floor line
            if n == 2:                                                                       # upper neon band
                zb0, zb1 = zw1, ceil_z(n) - 0.35
                st.box((x - 0.15, 0, (zb0 + zb1) / 2), (0.3, 2 * hw, zb1 - zb0), "Palette:#1c2026")
                sh.box((x + 0.012, 0, zb1 - 0.05), (0.012, 2 * hw, 0.07), D.SIGNS4[s % 4])
                sh.box((x + 0.012, 0, zb0 + 0.05), (0.012, 2 * hw, 0.07), D.SIGNS4[(s + 2) % 4])
            pattern = 0 if n <= 2 else int(D.hsh("pat", n, s) * 3)                           # L3-L5: 3 window patterns
            piers = {0: (-hw + 0.3, 0.0, hw - 0.3), 1: (-hw + 0.3, hw - 0.3), 2: (-hw + 0.3, -hw / 3, hw / 3, hw - 0.3)}[pattern]
            for yy in piers:
                st.box((x - 0.2, yy, (zw0 + zw1) / 2), (0.4, 0.6 if abs(yy) < hw - 0.4 else 0.5, zw1 - zw0), WHITE)
            edges = sorted(piers)
            for w0, w1 in zip(edges[:-1], edges[1:]):
                y0, y1 = w0 + 0.3, w1 - 0.3
                blackout = n == 2 and 13 <= s <= 18                                        # the Club has no windows
                tone = D.DARK_GLASS if blackout else D.window_tone("f", n, s, round(w0, 2), dark=0.12 if n == 1 else 0.26,
                                                                  colour=0.1 if n >= 3 else 0.0)
                if n >= 3 and not blackout and D.hsh("bright", n, s, round(w0, 2)) < 0.07:
                    tone = "Light"                                                           # a few very bright rooms
                sh.poly([Vector((x - 0.25, y0, zw0)), Vector((x - 0.25, y1, zw0)), Vector((x - 0.25, y1, zw1)),
                         Vector((x - 0.25, y0, zw1))], tone)
                if pattern == 1:
                    sh.box((x - 0.2, (y0 + y1) / 2, (zw0 + zw1) / 2), (0.06, 0.06, zw1 - zw0), MULLION)
            if n >= 3 and (s + n) % 3 == 0:                                                # a balcony on every third unit
                zb = floor_z(n) - 0.05
                st.box((x + 0.85, 0, zb), (1.7, 2 * hw - 1.0, 0.2), WHITE, mats={"-z": "Palette:#e07a3a"})
                sh.poly([Vector((x + 1.68, -hw + 0.55, zb + 0.1)), Vector((x + 1.68, hw - 0.55, zb + 0.1)),
                         Vector((x + 1.68, hw - 0.55, zb + 1.05)), Vector((x + 1.68, -hw + 0.55, zb + 1.05))], "Glass")
                sh.box((x + 1.68, 0, zb + 1.08), (0.06, 2 * hw - 1.0, 0.06), GRAPHITE)
                for sy in (-1, 1):                                                         # planters both ends
                    sh.box((x + 1.2, sy * (hw - 1.1), zb + 0.35), (0.7, 0.9, 0.5), "Palette:#8a929c")
                    D.leaf_cluster(sh, Vector((x + 1.2, sy * (hw - 1.1), zb + 0.62)), s=0.65, n=8, seed=n * 31 + s + sy, tilt=0.6)
                sh.box((x + 1.0, 0.6, zb + 0.45), (0.5, 0.5, 0.05), D.WOOD)                    # table + chairs
                sh.box((x + 0.02, 0, zw1 - 0.1), (0.04, 0.3, 0.08), "WindowAmber")             # balcony lamp
                # round 32: the balcony must read at night from 250 m: a warm strip on the rail, lit planters
                sh.box((x + 1.72, 0, zb + 1.13), (0.03, 2 * hw - 1.0, 0.10), "WindowAmber")
                sh.box((x + 1.715, 0, zb), (0.03, 2 * hw - 1.1, 0.10), "WindowAmber")        # slab-edge strip
                for sy in (-1, 1):
                    sh.box((x + 1.56, sy * (hw - 1.1), zb + 0.35), (0.02, 0.9, 0.22), "SignAmber")
            if n == 1:                                                                        # canopy over the shop windows
                st.box((x + 0.9, 0, zw1 + 0.15), (1.8, 2 * hw, 0.12), WHITE, mats={"-z": "Palette:#c3c9d1"})


def gallery_rail(sh, n):
    """glass balustrade + handrail at the gallery edge (levels 2-5)"""
    z = floor_z(n)
    for s in range(D.N_SEC):
        a0, a1 = sec_angle(s) - HALF, sec_angle(s) + HALF
        pts0 = D.arc(D.R_IN + 0.12, a0, a1, 3, z + 0.05)
        pts1 = D.arc(D.R_IN + 0.12, a0, a1, 3, z + 1.05)
        for i in range(3):
            sh.poly([pts0[i], pts0[i + 1], pts1[i + 1], pts1[i]], "Glass")
        sh.beam_path(D.arc(D.R_IN + 0.12, a0, a1, 3, z + 1.08), 0.07, 0.06, GRAPHITE)
        c = pol(D.R_IN + 0.12, a0, z)
        sh.box((c.x, c.y, z + 0.55), (0.06, 0.06, 1.1), GRAPHITE)


# ======================================================================================
# L1: venues (front, sign, interior) and passages
# ======================================================================================
def shopfront(p, lt, s, z0, z1, first, last, door=True):
    """glass front on the chord at R_FRONT for sector s; the fascia (sign board) is added per venue"""
    x, hw = chord(D.R_FRONT)
    zg = z1 - FASCIA_H
    with p.at(RZ(sec_angle(s))):
        p.poly([Vector((x, -hw, z0)), Vector((x, hw, z0)), Vector((x, hw, zg)), Vector((x, -hw, zg))], "Glass")
        p.box((x, 0, z0 + 0.06), (0.14, 2 * hw, 0.12), MULLION)
        p.box((x, 0, zg), (0.16, 2 * hw, 0.10), MULLION)
        for yy in (-hw * 0.5, hw * 0.5):
            p.box((x, yy, (z0 + zg) / 2), (0.1, 0.07, zg - z0), MULLION)
        if first:
            p.box((x, -hw, (z0 + z1) / 2), (0.3, 0.3, z1 - z0), WHITE)
        if last:
            p.box((x, hw, (z0 + z1) / 2), (0.3, 0.3, z1 - z0), WHITE)
        if door:
            p.box((x - 0.05, 0, z0 + 1.2), (0.06, 1.8, 2.3), MULLION, mats={"-x": None})            # door frame
            p.box((x - 0.07, 0, z0 + 0.01), (0.9, 1.9, 0.02), "Palette:#6b7078")                   # mat


def venue_shell(p, lt, v, z0, z1, shifts=None, front=True):
    vid, text, s0, ns, sign_mat, fascia, kind, floor_col = v
    a0, a1 = sec_angle(s0) - HALF, sec_angle(s0 + ns - 1) + HALF
    fz0 = z1 - FASCIA_H
    for k in (range(ns) if front else ()):
        s = s0 + k
        shopfront(p, lt, s, z0, z1, k == 0, k == ns - 1, door=(k == ns // 2 if ns > 1 else True))
        with p.at(RZ(sec_angle(s))):                                   # fascia board, venue colour
            x, hw = chord(D.R_FRONT)
            p.box((x - 0.05, 0, (fz0 + z1) / 2), (0.2, 2 * hw, z1 - fz0 - 0.02), "Palette:" + fascia)
    # sign (critic round 24 fix 4): a double-sided plate hung from the L2 slab edge at r 19.9, under the gallery
    # line, so the slab edge does not cut it from above; shifted where a lift stands in front of the venue
    mid = (a0 + a1) / 2 + (shifts if shifts is not None else SIGN_SHIFT).get(vid, 0.0)
    zc = z1 - 0.40
    c = pol(19.92, mid, zc)
    n_out = -pol(1.0, mid)
    right = Vector((0, 0, 1)).cross(n_out).normalized()          # reading left-to-right seen from the atrium
    hgt = 0.40 if len(text) <= 8 else 0.33
    ln = D.sign_text(lt, text, c, right, hgt, sign_mat, n_out, depth=0.04, plate="Palette:#1c2026", pad=0.13)
    D.sign_text(lt, text, c - n_out * 0.04, -right, hgt, sign_mat, -n_out, depth=0.04, plate="Palette:#1c2026", pad=0.13)
    for sx in (-1, 1):                                             # hangers to the slab
        h0 = c + right * sx * (ln / 2 - 0.1) - n_out * 0.02 + Vector((0, 0, hgt / 2 + 0.13))
        p.beam(h0, Vector((h0.x, h0.y, z1)), 0.03, 0.03, GRAPHITE)
    p.beam(c + right * (-ln / 2 - 0.13) - n_out * 0.02 + Vector((0, 0, hgt / 2 + 0.14)),
           c + right * (ln / 2 + 0.13) - n_out * 0.02 + Vector((0, 0, hgt / 2 + 0.14)), 0.05, 0.03, "Palette:" + fascia)
    # a blade sign at the door, perpendicular to the front: it reads along the colonnade / gallery
    ds = s0 + (ns // 2 if ns > 1 else 0)
    x, hw = chord(D.R_FRONT)
    ang = sec_angle(ds)
    tang = pol(1.0, ang + 90.0)
    bc = pol(x - 1.0, ang, 0.0) + tang * (-hw * 0.62) + Vector((0, 0, z1 - 0.62))
    btxt = text if len(text) <= 7 else text.split(" ")[0][:11]
    bh = 0.15
    D.sign_text(lt, btxt, bc, Vector((0, 0, 1)).cross(tang), bh, sign_mat, tang, depth=0.02, plate="Palette:#1c2026", pad=0.1)
    D.sign_text(lt, btxt, bc - tang * 0.03, Vector((0, 0, 1)).cross(-tang), bh, sign_mat, -tang, depth=0.02,
                plate="Palette:#1c2026", pad=0.1)
    p.beam(bc + Vector((0, 0, bh / 2 + 0.1)) - tang * 0.015, Vector((bc.x, bc.y, z1)) - tang * 0.015, 0.03, 0.03, GRAPHITE)
    # interior floor and back lightbox
    D.sector_prism(p, D.R_FRONT - 0.2, D.R_WALL, a0, a1, z0, z0 + 0.012, "Palette:" + floor_col, None, None, None, n=3 * ns)
    for k in (range(ns) if kind not in ("club", "arcade", "gym", "vacant") else ()):   # back lightbox (shops only)
        with lt.at(RZ(sec_angle(s0 + k))):
            xb, hb = chord(D.R_WALL - 0.12)
            lt.poly([Vector((xb, -hb + 0.3, z0 + 2.4)), Vector((xb, -hb + 0.3, z0 + 3.6)), Vector((xb, hb - 0.3, z0 + 3.6)),
                     Vector((xb, hb - 0.3, z0 + 2.4))], "CabinWindow")
    return a0, a1


def radial_walls(p, n, boundaries, z0, z1):
    for a in boundaries:
        D.radial_wall(p, a, D.R_FRONT, D.R_WALL, z0, z1, 0.2, WHITE)


# ---- interior props (polar placements inside a venue span) ----
def at(p, a, r, z, yaw=0.0):
    """transform context: a point at radius r, angle a, facing the atrium rotated by yaw"""
    c = pol(r, a, z)
    return p.at(T(*c), RZ(a + 180.0 + yaw))


def counter(p, a, r, z, w=3.0, col=D.WOOD, top="Palette:#e6e3dc"):
    with at(p, a, r, z):
        p.box((0, 0, 0.5), (0.7, w, 1.0), col, mats={"+z": top})


def table_set(p, a, r, z, seats=4, col=D.WOOD):
    with at(p, a, r, z):
        p.cyl((0, 0, 0), (0, 0, 0.72), 0.06, seg=5, mat=GRAPHITE, cap0=False)
        p.cyl((0, 0, 0.72), (0, 0, 0.76), 0.45, seg=8, mat=col)
        for k in range(seats):
            q = pol(0.75, 360.0 * k / seats + 45.0)
            p.box((q.x, q.y, 0.45), (0.42, 0.42, 0.06), "Palette:#3c4a5e")
            p.box((q.x, q.y, 0.22), (0.08, 0.08, 0.44), GRAPHITE)


def table_seats(a, r, z, seats):
    """stand points for the sit clips beside a table_set: 0.45 m from the table centre on the chair side, facing the
    table (critic round 26: bodies must stay clear of the table top)"""
    c = pol(r, a, z)
    out = []
    for k in range(seats):
        q = pol(0.75, 360.0 * k / seats + 45.0)
        w = Vector((q.x, q.y, 0))
        w.rotate(RZ(a + 180.0).to_3x3())
        pos = c + w * 0.6
        out.append(dict(kind="Seat", pos=pos, fwd=(c - pos).normalized(),
                        extras={"clip": "sit_eat"}))
    return out


def shelf(p, a, r, z, length=4.0, h=1.8, goods=("#e0503a", "#f2c14e", "#6abf4b")):
    """a gondola with separate product boxes and white price labels (critic round 26 fix 5)"""
    with at(p, a, r, z):
        p.box((0, 0, h / 2), (0.36, length, h), "Palette:#e6e3dc")
        for k, zz in enumerate((0.12, 0.62, 1.12)):
            if zz + 0.3 > h:
                continue
            p.box((0, 0, zz - 0.02), (0.62, length, 0.03), "Palette:#c3c9d1")                 # shelf board
            n = max(3, int(length / 0.3))
            for sx in (-1, 1):
                for j in range(n):
                    y = -length / 2 + length * (j + 0.5) / n
                    col = goods[(k + j // 3) % len(goods)] if D.hsh(a, r, k, j, sx) > 0.15 else "#e6e3dc"
                    hh = 0.18 + 0.12 * D.hsh(k, j, sx)
                    p.box((sx * 0.24, y, zz + hh / 2), (0.14, length / n * 0.86, hh), "Palette:" + col,
                          mats={"-z": None, ("-x" if sx > 0 else "+x"): None})
                    p.box((sx * 0.312, y, zz + 0.03), (0.004, length / n * 0.5, 0.035), "Palette:#f7f5f0",
                          mats={"-z": None, "+z": None, ("-x" if sx > 0 else "+x"): None})


GOODS = ("#e0503a", "#f2c14e", "#6abf4b", "#4a90d9", "#e85d75", "#b58cff", "#ff9f1c", "#e6e3dc")


def window_display(p, lt, kind, s, z0, k):
    """goods in the windows (critic round 24 fix 6): a plinth behind the glass of sector s with items by kind"""
    x, hw = chord(D.R_FRONT)
    with p.at(RZ(sec_angle(s))), lt.at(RZ(sec_angle(s))):
        for yy in ((-hw * 0.62,) if k % 2 else (-hw * 0.62, hw * 0.62)):
            if kind == "clothing":
                for j in (-0.5, 0.5):
                    D.mannequin(p, (x + 0.7, yy + j, z0), yaw=180.0, col=GOODS[(k * 3 + int(j * 2) + 5) % 7],
                                pants=("#2c3036", "#3a4f6b", "#6b4f3a")[k % 3])
                continue
            p.box((x + 0.65, yy, z0 + 0.2), (0.6, 1.6, 0.4), "Palette:#e6e3dc")
            if kind == "grocery":
                for j in range(3):
                    p.box((x + 0.65, yy - 0.5 + j * 0.5, z0 + 0.52), (0.45, 0.42, 0.24), "Palette:#b08560")
                    p.box((x + 0.65, yy - 0.5 + j * 0.5, z0 + 0.66), (0.4, 0.36, 0.06), "Palette:" + GOODS[j])
            elif kind in ("cafe", "restaurant"):
                for j, dy in enumerate((-0.45, 0.45)):                   # two cake stands with tiered cakes
                    cc = Vector((x + 0.65, yy + dy, z0 + 0.4))
                    p.cyl(cc, cc + Vector((0, 0, 0.25)), 0.03, seg=5, mat=GRAPHITE)
                    p.cyl(cc + Vector((0, 0, 0.25)), cc + Vector((0, 0, 0.27)), 0.3, seg=12, mat="Palette:#e6e3dc")
                    for t, (rr, hh, col) in enumerate(((0.22, 0.12, "#f2e6d0"), (0.15, 0.1, "#e85d75" if j else "#8a5a44"),
                                                       (0.08, 0.08, "#f2e6d0"))):
                        z_ = 0.27 + sum((0.12, 0.1, 0.08)[:t])
                        p.cyl(cc + Vector((0, 0, z_)), cc + Vector((0, 0, z_ + hh)), rr, seg=12,
                              mat="Palette:" + col)
                    p.sphere(tuple(cc + Vector((0, 0, 0.6))), 0.03, "Palette:#b0283a", seg=6, rings=3)
                for j in range(3):                                           # croissants and cups on the plinth
                    q = Vector((x + 0.55, yy - 0.6 + j * 0.6, z0 + 0.44))
                    with p.at(T(*q), RZ(30.0 * j)):
                        p.torus(0.07, 0.035, "Palette:#d9a054", seg=8, tseg=4, a0=0.0, a1=200.0)
                D.cups(p, Vector((x + 0.8, yy, z0 + 0.4)), n=3, seed=k)
                D.menu_board(p, lt, Vector((x + 0.95, yy, z0 + 2.6)), Vector((0, -1, 0)), Vector((-1, 0, 0)), w=1.2, h=0.8,
                             seed=k + 2)
            elif kind == "bar":
                for j in range(5):
                    lt.cyl((x + 0.65, yy - 0.6 + j * 0.3, z0 + 0.4), (x + 0.65, yy - 0.6 + j * 0.3, z0 + 0.75), 0.05,
                           seg=5, mat=("SignAmber", "SignMagenta", "SignGreen")[j % 3])
            elif kind in ("electronics", "credit", "comms"):
                for j in (-0.4, 0.4):
                    p.box((x + 0.65, yy + j, z0 + 0.5), (0.08, 0.06, 0.2), GRAPHITE)
                    lt.box((x + 0.65, yy + j, z0 + 0.82), (0.05, 0.6, 0.4), "Screen")
            elif kind == "clinic":
                for j in range(6):
                    p.box((x + 0.65, yy - 0.5 + (j % 3) * 0.5, z0 + 0.5 + (j // 3) * 0.22), (0.3, 0.35, 0.2),
                          "Palette:" + ("#e6e3dc", "#8fc9b8", "#e85d75")[j % 3])
                lt.box((x + 0.95, yy, z0 + 1.6), (0.03, 0.5, 0.5), "SignGreen")
            elif kind == "hotel":
                D.leaf_cluster(p, (x + 0.65, yy, z0 + 0.45), s=0.55, n=8, seed=k + int(yy * 10), tilt=0.7)
            elif kind == "barber":
                lt.box((x + 0.95, yy, z0 + 1.5), (0.03, 0.9, 1.1), "Screen")
            else:                                                  # gifts
                for j in range(3):
                    c = (x + 0.65, yy - 0.45 + j * 0.45, z0 + 0.52)
                    p.box(c, (0.34, 0.34, 0.24 + 0.08 * j), "Palette:" + GOODS[(j + 4) % 8])
                    p.box((c[0], c[1], c[2]), (0.36, 0.05, 0.25 + 0.08 * j), "Palette:#f2c14e")


def interior(p, lt, v, a0, a1, z0):
    vid, text, s0, ns, sign_mat, fascia, kind, floor_col = v
    mid = (a0 + a1) / 2
    span = a1 - a0
    rb = D.R_WALL - 0.6                                            # near the back wall
    anchors = []
    for k in range(ns):
        window_display(p, lt, kind, s0 + k, z0, k)
    if kind == "grocery":
        for k in range(5):
            shelf(p, a0 + span * (k + 1) / 6, 28.9, z0, length=5.4, h=1.7, goods=(GOODS[k % 7], GOODS[(k + 2) % 7], GOODS[(k + 4) % 7]))
        for k in range(ns * 2):                                    # lit fridge wall at the back
            aa = a0 + span * (k + 0.5) / (ns * 2)
            with at(p, aa, D.R_WALL - 0.45, z0):
                p.box((0, 0, 1.0), (0.8, 2.6, 2.0), "Palette:#e6e3dc")
            with at(lt, aa, D.R_WALL - 0.86, z0):
                lt.box((0, 0, 1.05), (0.02, 2.4, 1.6), "WindowCool")
        counter(p, a0 + span * 0.25, 24.6, z0, w=1.6)
        counter(p, a0 + span * 0.55, 24.6, z0, w=1.6)
        anchors += [("Work", a0 + span * 0.25, 25.2), ("Work", a0 + span * 0.55, 25.2)]
    elif kind == "clinic":
        for k in range(ns * 2):                                    # pharmacy shelves along the back
            shelf(p, a0 + span * (k + 0.5) / (ns * 2), D.R_WALL - 0.45, z0, length=2.4, h=2.0,
                  goods=("#e6e3dc", "#8fc9b8", "#e85d75"))
        counter(p, mid, 24.8, z0, w=2.4, col="Palette:#e8eef0")
        for k in range(3):
            aa = a0 + span * (k + 1) / 4
            with at(p, aa, 31.0, z0):
                p.box((0, 0, 0.35), (2.0, 0.9, 0.7), "Palette:#e6e3dc", mats={"+z": "Palette:#9fd4ea"})
                p.box((0.0, 0.55, 1.1), (2.2, 0.03, 2.0), "Palette:#8fc9b8")
        lt.box(tuple(pol(D.R_FRONT - 0.3, mid, z0 + 3.2)), (0.05, 0.25, 0.8), "SignGreen")
        anchors += [("Work", mid, 25.4)]
    elif kind == "barber":
        with at(p, mid, D.R_WALL - 0.4, z0):
            p.box((0, 0, 0.45), (0.5, 3.0, 0.9), "Palette:#e6e3dc")          # wash basins
            p.box((0.26, 0, 1.5), (0.02, 3.2, 1.0), "Palette:#dfe8ee")        # mirror wall
        with at(p, mid, 24.3, z0, yaw=90.0):
            p.box((0, 0, 0.45), (0.45, 2.0, 0.08), D.WOOD)                     # waiting bench
        for k in (-1, 1):
            aa = mid + k * span * 0.22
            with at(p, aa, 30.0, z0):
                p.box((0, 0, 0.45), (0.7, 0.6, 0.9), "Palette:#7a2f3a")
                p.box((0.45, 0, 1.4), (0.04, 0.9, 1.2), "Palette:#dfe8ee")
        counter(p, mid, 25.0, z0, w=1.4, col="Palette:#2c3036")
        anchors += [("Work", mid - span * 0.22, 29.3), ("Work", mid + span * 0.22, 29.3)]
    elif kind in ("cafe", "restaurant"):
        ca = a0 + span * 0.2
        counter(p, ca, rb - 1.0, z0, w=3.2)
        cc = pol(rb - 1.0, ca, z0 + 1.0)
        D.cups(p, cc + pol(0.6, ca + 90.0), n=5, seed=0)
        with at(p, ca, rb - 1.0, z0):                              # a lit cake case on the counter
            p.box((0, -0.8, 1.2), (0.5, 1.2, 0.36), "Glass")
            for j in range(4):
                p.cyl((0, -1.25 + j * 0.3, 1.02), (0, -1.25 + j * 0.3, 1.12), 0.1, seg=8,
                      mat="Palette:" + ("#f2c14e", "#8a5a44", "#e85d75", "#f2e6d0")[j])
        with at(lt, ca, rb - 1.0, z0):
            lt.box((0, -0.8, 1.02), (0.46, 1.16, 0.02), "WindowCream")
        mb = pol(D.R_WALL - 0.14, ca, z0 + 2.3)
        D.menu_board(p, lt, mb, Vector((0, 0, 1)).cross(-pol(1.0, ca)), -pol(1.0, ca), w=1.6, h=0.9, seed=len(vid))
        n_t = 3 if kind == "cafe" else 5
        for k in range(n_t):
            aa = a0 + span * (k + 1) / (n_t + 1)
            rr = 27.5 if k % 2 else 30.0
            table_set(p, aa, rr, z0, seats=2 if kind == "cafe" else 4,
                      col="Palette:#f2f0ea" if kind == "restaurant" else D.WOOD)
            D.cups(p, pol(rr, aa, z0 + 0.76), n=2, seed=k)
            anchors += table_seats(aa, rr, z0, 2 if kind == "cafe" else 4)
        for k in range(2):                                         # tables out in the colonnade
            aa = a0 + span * (k + 1) / 3
            table_set(p, aa, 21.6, z0, seats=2, col="Palette:#e6e3dc")
            anchors += table_seats(aa, 21.6, z0, 2)
        anchors.append(("Work", a0 + span * 0.2, rb - 1.8))
        ca = a0 + span * 0.5                                       # a chalkboard A-frame in the colonnade
        cb = pol(D.R_FRONT - 1.6, ca + 2.0, z0)
        nrm = -pol(1.0, ca + 2.0)
        with p.at(T(*cb), RZ(ca + 2.0)):
            for sx in (-1, 1):
                p.beam((sx * 0.22, -0.3, 0.0), (0.0, -0.3, 1.0), 0.04, 0.04, D.WOOD)
                p.beam((sx * 0.22, 0.3, 0.0), (0.0, 0.3, 1.0), 0.04, 0.04, D.WOOD)
        D.menu_board(p, lt, cb + Vector((0, 0, 0.55)) + nrm * 0.14, Vector((0, 0, 1)).cross(nrm), nrm, w=0.55, h=0.7, seed=3)
    elif kind == "bar":
        pts = D.arc(29.8, a0 + span * 0.12, a1 - span * 0.12, 6, z0)
        for i in range(6):
            aa = a0 + span * 0.12 + (span * 0.76) * (i + 0.5) / 6
            with at(p, aa, 29.8, z0):
                p.box((0, 0, 0.55), (0.8, (span * 0.76 / 6) * radians(1) * 29.8 + 0.02, 1.1), "Palette:#3a2a26",
                      mats={"+z": "Palette:#8a5a44"})
            with at(p, aa, 28.9, z0):
                p.cyl((0, 0, 0), (0, 0, 0.75), 0.04, seg=4, mat=GRAPHITE, cap0=False)
                p.cyl((0, 0, 0.75), (0, 0, 0.8), 0.2, seg=6, mat="Palette:#7a2f3a")
            anchors.append(("Seat", aa, 28.9))
        for k in range(ns * 2):                                    # back shelf with lit bottles
            aa = a0 + span * (k + 0.5) / (ns * 2)
            with at(p, aa, D.R_WALL - 0.3, z0):
                p.box((0, 0, 1.6), (0.4, 2.0, 1.6), "Palette:#241c2c")
            with at(lt, aa, D.R_WALL - 0.52, z0):
                lt.box((0, 0, 1.25), (0.02, 1.8, 0.05), "SignMagenta")
                lt.box((0, 0, 1.85), (0.02, 1.8, 0.05), "SignAmber")
        for k in range(2):
            table_set(p, a0 + span * (0.25 + 0.5 * k), 25.0, z0, seats=3, col="Palette:#3a2a26")
        anchors.append(("Work", mid, 30.6))
    elif kind == "hotel":
        counter(p, mid, 30.2, z0, w=4.0, col="Palette:#3a2f4f")
        D.sector_prism(p, 24.6, 28.4, mid - span * 0.3, mid + span * 0.3, z0 + 0.012, z0 + 0.03, "Palette:#7a2f3a", None,
                       None, None, n=4)                            # rug
        with at(p, mid + span * 0.36, 28.8, z0):
            for j in range(3):
                p.box((0, -0.3 + j * 0.3, 0.35), (0.35, 0.22, 0.6), "Palette:" + ("#3a4f6b", "#b35a4a", "#2c3036")[j])
        with at(lt, mid, D.R_WALL - 0.2, z0):
            lt.box((0, 0, 2.6), (0.03, 3.0, 0.5), "SignMagenta")
        for k in (-1, 1):
            aa = mid + k * span * 0.3
            with at(p, aa, 26.0, z0):
                p.box((0, 0, 0.25), (1.0, 2.2, 0.5), "Palette:#b35a4a")
                p.box((-0.4, 0, 0.6), (0.2, 2.2, 0.5), "Palette:#b35a4a")
            D.tree(p, pol(25.0, mid + k * span * 0.1, z0), h=2.2, r=0.7)
        anchors += [("Work", mid, 30.9)]
    elif kind == "clothing":
        for k in range(3):
            D.mannequin(p, pol(26.0, a0 + span * (k + 1) / 4, z0), yaw=a0 + span * (k + 1) / 4 + 180.0,
                        col=GOODS[(k + 3) % 7])
        for k in range(ns * 2):                                    # wall shelves with folded goods
            shelf(p, a0 + span * (k + 0.5) / (ns * 2), D.R_WALL - 0.45, z0, length=2.4, h=2.1,
                  goods=(GOODS[k % 7], GOODS[(k + 3) % 7], GOODS[(k + 5) % 7]))
        for k in range(4):
            aa = a0 + span * (k + 1) / 5
            with at(p, aa, 28.5, z0):
                p.box((0, 0, 1.45), (0.05, 2.4, 0.05), GRAPHITE)
                for j, col in enumerate(("#e85d75", "#4a90d9", "#f2c14e", "#2c3036", "#6abf4b")):
                    p.box((0, -1.0 + j * 0.5, 1.05), (0.35, 0.3, 0.8), "Palette:" + col)
        counter(p, a0 + span * 0.8, 25.0, z0, w=1.6, col="Palette:#e6e3dc")
        anchors += [("Work", a0 + span * 0.8, 25.6)]
    elif kind == "electronics":
        for k in range(3):
            aa = a0 + span * (k + 1) / 4
            with at(p, aa, 28.0, z0):
                p.box((0, 0, 0.45), (1.2, 2.0, 0.9), "Palette:#e6e3dc")
            with at(lt, aa, 28.0, z0):
                for j in (-0.5, 0.5):
                    lt.box((0, j, 1.05), (0.4, 0.5, 0.3), "Screen")
        for k in range(ns * 2):
            aa = a0 + span * (k + 0.5) / (ns * 2)
            with at(lt, aa, D.R_WALL - 0.2, z0):
                lt.box((0, 0, 1.9), (0.04, 2.4, 1.3), "Screen")
            nrm = -pol(1.0, aa)
            D.screen_content(lt, pol(D.R_WALL - 0.22, aa, z0 + 1.9), Vector((0, 0, 1)).cross(nrm), nrm, 2.3, 1.2, seed=k)
        counter(p, mid, 24.8, z0, w=1.8, col="Palette:#2c3036")
        anchors += [("Work", mid, 25.4)]
    else:                                                          # office, comms, gifts
        counter(p, mid, 26.5, z0, w=3.0, col="Palette:#e6e3dc")
        for k in range(ns * 2):
            shelf(p, a0 + span * (k + 0.5) / (ns * 2), D.R_WALL - 0.45, z0, length=2.4, h=2.0,
                  goods=(GOODS[(k + 1) % 7], GOODS[(k + 4) % 7], GOODS[(k + 6) % 7]))
        if kind == "comms":
            with at(p, mid, D.R_WALL - 0.4, z0):
                p.box((0, 0, 1.1), (0.6, 4.0, 2.2), "Palette:#4a90d9")
                for j in range(5):
                    p.box((0.31, -1.6 + j * 0.8, 1.1), (0.02, 0.02, 2.0), GRAPHITE)
        elif kind == "office":
            with at(lt, mid, 26.5, z0):
                for j in (-0.8, 0.8):
                    lt.box((0.1, j, 1.25), (0.04, 0.6, 0.4), "Screen")
            for k in (-1, 1):
                with at(p, mid + k * span * 0.3, 24.2, z0):
                    p.box((0, 0, 0.23), (0.5, 1.6, 0.46), "Palette:#3c4a5e")
        else:
            for k in range(2):
                with at(p, a0 + span * (k + 1) / 3, 30.0, z0):
                    p.box((0, 0, 0.45), (1.0, 1.0, 0.9), "Palette:#e6e3dc")
                    for j in range(3):
                        p.box((0, -0.3 + j * 0.3, 1.0), (0.2, 0.2, 0.2), "Palette:" + ("#e85d75", "#f2c14e", "#4a90d9")[j])
        anchors += [("Work", mid, 27.1)]
    return anchors


def passage(st, lt, s, z0, z1):
    """open passage through the ring: paving, side walls, lights, a directory sign"""
    a0, a1 = sec_angle(s) - HALF, sec_angle(s) + HALF
    D.sector_prism(st, D.R_IN, D.R_OUT, a0 + 0.8, a1 - 0.8, z0, z0 + 0.012, "Palette:#8e887d", None, None, None, n=3)
    for a in (a0, a1):
        D.radial_wall(st, a, D.R_FRONT, D.R_OUT, z0, z1, 0.3, WHITE)
    for r in (24.0, 27.0, 30.0, 33.0):
        c = pol(r, sec_angle(s), z1 - 0.01)
        lt.poly([c + Vector((0.3, 0.3, 0)), c + Vector((0.3, -0.3, 0)), c + Vector((-0.3, -0.3, 0)), c + Vector((-0.3, 0.3, 0))], "Light")
    with st.at(RZ(sec_angle(s))):
        st.box((D.R_FRONT - 0.5, 1.9, z0 + 1.1), (0.25, 0.8, 2.2), GRAPHITE)
    with lt.at(RZ(sec_angle(s))):
        lt.box((D.R_FRONT - 0.64, 1.9, z0 + 1.4), (0.02, 0.62, 1.2), "Screen")


# ======================================================================================
# L2-L5 generic fit-out (pilot)
# ======================================================================================
def generic_shops(sh, lt, n, sectors):
    z0, z1 = floor_z(n), ceil_z(n)
    for s in sectors:
        shopfront(sh, lt, s, z0, z1, True, True, door=True)
        with sh.at(RZ(sec_angle(s))):
            x, hw = chord(D.R_FRONT)
            sh.box((x - 0.05, 0, z1 - FASCIA_H / 2), (0.2, 2 * hw, FASCIA_H - 0.02), "Palette:#2c3036")
        with lt.at(RZ(sec_angle(s))):
            xb, hb = chord(D.R_WALL - 0.12)
            lt.poly([Vector((xb, -hb + 0.3, z0 + 1.8)), Vector((xb, -hb + 0.3, z0 + 3.0)), Vector((xb, hb - 0.3, z0 + 3.0)),
                     Vector((xb, hb - 0.3, z0 + 1.8))], "CabinWindow")
        D.sector_prism(sh, D.R_FRONT - 0.2, D.R_WALL, sec_angle(s) - HALF, sec_angle(s) + HALF, z0, z0 + 0.012,
                       "Palette:#c9d3e0", None, None, None, n=3)


def outer_signs(sh, lt):
    """critic round 24 fix 1: signs and neon on the outer face. The L1 venue names face the promenade on the L2
    spandrel (z 5.0-6.1); between them, neon billboards cover the L2 windows of some sectors."""
    zc = 5.62
    used = set()
    for v in L1_VENUES:
        vid, text, s0, ns, sign_mat, fascia, kind, floor_col = v
        mid = sec_angle(s0) + (ns - 1) * D.SEC / 2
        used.update(range(s0, s0 + ns))
        rr = D.R_OUT + (0.25 if ns % 2 else 0.85)
        c = pol(rr, mid, zc)
        n_out = pol(1.0, mid)
        right = Vector((0, 0, 1)).cross(n_out).normalized()
        hgt = 0.62 if len(text) <= 8 else 0.48
        ln = D.sign_text(lt, text, c, right, hgt, sign_mat, n_out, depth=0.05, plate="Palette:#1c2026", pad=0.16)
        for sx in (-1, 1):
            b0 = c + right * sx * (ln / 2) - n_out * 0.03
            sh.beam(b0, b0 - n_out * (rr - D.R_OUT + 0.1), 0.06, 0.06, GRAPHITE)
    import dome_l2
    zb = (ceil_z(2) - 1.3 + ceil_z(2) - 0.35) / 2
    for v in dome_l2.L2_VENUES:                                    # L2 names on the upper neon band
        vid, text, s0, ns, sign_mat, fascia, kind, floor_col = v
        mid = sec_angle(s0) + (ns - 1) * D.SEC / 2
        rr = (chord(D.R_OUT)[0] + 0.03) if ns % 2 else D.R_OUT + 0.62
        c = pol(rr, mid, zb)
        n_out = pol(1.0, mid)
        D.sign_text(lt, text, c, Vector((0, 0, 1)).cross(n_out), 0.46 if ns > 1 else 0.36, sign_mat, n_out, depth=0.04,
                    plate="Palette:#1c2026" if ns % 2 == 0 else None, pad=0.1)
    cols = ("SignMagenta", "SignCyan", "SignGreen", "SignAmber")
    for k, s in enumerate((2, 8, 14, 20)):                        # neon billboards over the L2 windows
        x, hw = chord(D.R_OUT)
        with sh.at(RZ(sec_angle(s))), lt.at(RZ(sec_angle(s))):
            sh.box((x + 0.1, 0, 7.4), (0.2, 4.6, 2.6), "Palette:#1c2026")
            lt.box((x + 0.21, 0, 7.4), (0.02, 4.2, 2.2), "Screen")
            D.screen_content(lt, Vector((x + 0.225, 0, 7.4)), Vector((0, 1, 0)), Vector((1, 0, 0)), 4.0, 2.0, seed=k + 3)
            for (dy, dz, w, h) in ((0, 1.25, 4.6, 0.1), (0, -1.25, 4.6, 0.1), (2.25, 0, 0.1, 2.6), (-2.25, 0, 0.1, 2.6)):
                lt.box((x + 0.22, dy, 7.4 + dz), (0.03, w, h), cols[k])
            lt.box((x + 0.23, -1.2, 7.4), (0.02, 1.2, 1.2), cols[(k + 1) % 4])
            lt.box((x + 0.23, 1.0, 7.9), (0.02, 1.6, 0.3), cols[(k + 2) % 4])
            lt.box((x + 0.23, 1.0, 7.2), (0.02, 1.6, 0.3), cols[(k + 3) % 4])


def unit_fronts(sh, lt, n):
    """accommodation: one unit per sector; front wall with a door, a lit window and a planter; simple furniture"""
    z0, z1 = floor_z(n), ceil_z(n)
    for s in range(D.N_SEC):
        with sh.at(RZ(sec_angle(s))), lt.at(RZ(sec_angle(s))):
            x, hw = chord(D.R_FRONT)
            sh.box((x, -hw + 1.0, (z0 + z1) / 2), (0.25, 2.0, z1 - z0), WHITE)               # wall left of the door
            sh.box((x, hw - 1.6, z0 + 0.45), (0.25, 3.2, 0.9), WHITE)                        # under the window
            sh.box((x, hw - 1.6, z1 - 0.3), (0.25, 3.2, 0.6), WHITE)                         # over the window
            sh.box((x, 0.25, z1 - 0.35), (0.25, 1.1, 0.7), WHITE)                            # over the door
            sh.box((x - 0.02, 0.25, z0 + 1.07), (0.08, 1.0, 2.14), "Palette:#3a4f6b")        # door
            lt.poly([Vector((x - 0.14, hw - 3.2, z0 + 0.9)), Vector((x - 0.14, hw - 0.01, z0 + 0.9)),
                     Vector((x - 0.14, hw - 0.01, z1 - 0.6)), Vector((x - 0.14, hw - 3.2, z1 - 0.6))],
                    D.window_tone("u", n, s, dark=0.25))
            lt.box((x - 0.14, 0.25, z1 - 0.62), (0.03, 0.3, 0.05), "Light")                  # door lamp
            sh.box((x - 0.5, hw - 1.6, z0 + 0.25), (0.5, 2.4, 0.5), "Palette:#8a929c", mats={"+z": D.PLANT})
            # furniture seen in the floor cutaway: bed, sofa, table
            sh.box((30.5, -1.2, z0 + 0.25), (2.1, 1.6, 0.5), "Palette:#e6e3dc", mats={"+z": "Palette:#4a6fa5"})
            sh.box((26.5, 1.5, z0 + 0.22), (0.9, 2.2, 0.44), "Palette:#b35a4a")
            sh.box((27.6, -1.4, z0 + 0.37), (0.9, 0.9, 0.74), D.WOOD)
        D.radial_wall(sh, sec_angle(s) - HALF, D.R_FRONT, D.R_WALL, z0, z1, 0.18, WHITE)
        D.radial_wall(sh, sec_angle(s), 28.8, D.R_WALL, z0, z1, 0.12, "Palette:#e8e2d8")     # bedroom wall
        D.sector_prism(sh, D.R_FRONT, D.R_WALL, sec_angle(s) - HALF, sec_angle(s) + HALF, z0, z0 + 0.012,
                       "Palette:#c8a27a", None, None, None, n=3)


def roof(st, sh, lt):
    """roof slab (the ceiling of L5), parapet, roof garden under the dome"""
    z1 = D.ROOF_Z
    z0 = z1 - D.SLAB
    for s in range(D.N_SEC):
        a0, a1 = sec_angle(s) - HALF, sec_angle(s) + HALF
        D.sector_prism(st, D.R_IN, D.R_OUT, a0, a1, z0, z1, "Palette:#8e887d", SOFFIT, WHITE, WHITE, n=3)
        D.sector_prism(st, D.R_OUT - 0.3, D.R_OUT, a0, a1, z1, z1 + 1.0, "Palette:#c3c9d1", None, WHITE, WHITE, n=3)
        D.sector_prism(st, D.R_IN, D.R_IN + 0.25, a0, a1, z1, z1 + 1.0, "Palette:#c3c9d1", None, WHITE, WHITE, n=3)
        D.sector_prism(st, D.R_IN - 0.02, D.R_IN, a0, a1, z1 + 0.7, z1 + 0.85, None, None, "Accent", None, n=3)
        for (r, da) in ((20.9, 0.0), (21.9, -4.0), (21.9, 4.0), (26.5, -4.5), (26.5, 4.5), (30.5, 0.0)):
            c = pol(r, sec_angle(s) + da, z0 - 0.01)
            lt.poly([c + Vector((0.22, 0.22, 0)), c + Vector((0.22, -0.22, 0)), c + Vector((-0.22, -0.22, 0)),
                     c + Vector((-0.22, 0.22, 0))], "Light")
        if s % 2 == 0:                                                 # roof garden beds
            with sh.at(RZ(sec_angle(s))):
                sh.box((27.0, 0, z1 + 0.3), (6.0, 3.0, 0.6), "Palette:#8a929c", mats={"+z": D.PLANT})
            D.tree(sh, pol(27.0, sec_angle(s), z1 + 0.6), h=2.6, r=0.9, seed=s)
        else:                                                          # plant-room units
            with sh.at(RZ(sec_angle(s))):
                sh.box((30.0, 0, z1 + 0.6), (2.4, 3.4, 1.2), "Palette:#c3c9d1", mats={"+z": GRAPHITE})


# ======================================================================================
def venues(n, fl, table, shifts, st, z0, z1):
    """venue nodes (front, sign, interior), radial walls between venues, and every venue anchor"""
    import dome_l2
    out, bounds, anchors = [], set(), []
    for v in table:
        vid = v[0]
        node = Node("Venue_%s" % vid, None, fl, {"floor": n, "stage": "fitout_%s" % vid, "venue": vid})
        vlt = Node("VenueLamps_%s" % vid, None, fl, {"floor": n, "stage": "fitout_%s" % vid, "venue": vid})
        club = v[6] == "club"
        a0, a1 = venue_shell(node, vlt, v, z0, z1, shifts, front=not club)
        if club:
            dome_l2.club_front(node, vlt, v, z0, z1)
        bounds.update((round(a0, 3), round(a1, 3)))
        if n == 2 and (v[6] in dome_l2.SPECIAL):
            extra = []
            for d in dome_l2.interior2(node, vlt, v, a0, a1, z0, extra):
                anchors.append((vid, d))
            for e in extra:
                e.parent = fl
                e.props["venue"] = vid
            out += extra
        else:
            for it in interior(node, vlt, v, a0, a1, z0):
                if isinstance(it, dict):
                    anchors.append((vid, it))
                else:
                    kind, a, r = it
                    anchors.append((vid, dict(kind=kind, pos=pol(r, a, z0), fwd=-pol(1.0, a), extras={})))
        mid = (a0 + a1) / 2
        out.append(D.anchor("Anchor_Venue_%s" % vid, pol(D.R_FRONT - 1.2, mid, z0), forward=pol(1.0, mid),
                            floor=n, venue=vid, sectors=[v[2], v[3]], label=v[1]))
        out += [node, vlt]
    radial_walls(st, n, sorted(bounds), z0, z1)
    counts = {}
    for (vid, d) in anchors:
        k = counts.get((vid, d["kind"]), 0)
        counts[(vid, d["kind"])] = k + 1
        out.append(D.anchor("Anchor_%s_%s_%d" % (d["kind"], vid, k), d["pos"], forward=d["fwd"], floor=n, venue=vid,
                            **d["extras"]))
    return out


def build_floor(n):
    def builder():
        z0, z1 = floor_z(n), ceil_z(n)
        fl = "Floor_%d" % n
        out = [Group(fl, None, {"floor": n, "height": z0, "stage": "level_%d" % n})]
        st = Node("Struct_%d" % n, None, fl, {"floor": n, "stage": "structure"})
        sh = Node("Shell_%d" % n, None, fl, {"floor": n, "stage": "fitout"})
        lt = Node("Lamps_%d" % n, None, fl, {"floor": n, "stage": "fitout"})
        if n > 1:
            slab(st, lt, n)
            gallery_rail(sh, n)
        columns(st, n)
        facade(st, sh, n)
        anchors = []
        if n == 1:
            for s_ in D.PASSAGES:
                passage(st, lt, s_, z0, z1)
            out += venues(n, fl, L1_VENUES, SIGN_SHIFT, st, z0, z1)
        elif n == 2:
            import dome_l2
            out += venues(n, fl, dome_l2.L2_VENUES, dome_l2.SIGN_SHIFT, st, z0, z1)
            outer_signs(sh, lt)
        else:
            import dome_units
            out += dome_units.build_units(n, fl, sh, lt, z0, z1)
        out += [st, sh, lt]
        if n == 5:
            rst = Node("Roof_Struct", None, "Floor_Roof", {"floor": 6, "stage": "structure"})
            rsh = Node("Roof_Garden", None, "Floor_Roof", {"floor": 6, "stage": "fitout"})
            rlt = Node("Roof_Lamps", None, "Floor_Roof", {"floor": 6, "stage": "fitout"})
            roof(rst, rsh, rlt)
            out = [Group("Floor_Roof", None, {"floor": 6, "height": D.ROOF_Z, "stage": "roof"})] + out + [rst, rsh, rlt]
        return out
    return builder


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    floors = [int(x) for x in argv[argv.index("--floors") + 1].split(",")] if "--floors" in argv else [1, 2, 3, 4, 5]
    import dome_l2
    for n in floors:
        lamps = ["Lamps_%d" % n] + ["VenueLamps_%s" % v[0] for v in L1_VENUES + dome_l2.L2_VENUES] + ["Roof_Lamps",
                                                                                                        "ArcadeScreen_PrismShift"]
        D.build_file("dome_floor%d.glb" % n, build_floor(n), ao={"dist": 1.2, "samples": 10, "skip": lamps})


if __name__ == "__main__":
    main()
